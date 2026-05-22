const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');
const { findUserById } = require('../repositories/user-repository');
const { attachInteractionCounts } = require('../services/feed-service');

const router = express.Router();

// GET /users/search?q=  — search users by name (must come before /:userId)
router.get(
  '/search',
  asyncHandler(async (req, res) => {
    const q = (req.query.q || '').toString().trim();
    if (!q || q.length < 2) return res.json({ users: [] });

    const pool = getPostgresPool();
    if (!pool) return res.json({ users: [] });

    const result = await pool.query(
      `SELECT id, full_name AS "fullName", role, status
       FROM users
       WHERE (full_name ILIKE $1 OR email ILIKE $1) AND email_verified_at IS NOT NULL
       ORDER BY full_name
       LIMIT 20`,
      [`%${q}%`],
    );

    res.json({ users: result.rows });
  }),
);

// GET /users/me/photos — get current user's photo library
router.get(
  '/me/photos',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ photos: [] });

    const result = await pool.query(
      `SELECT id, image, caption, created_at AS "createdAt"
       FROM user_photos WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.auth.sub],
    );
    res.json({ photos: result.rows });
  }),
);

// POST /users/me/photos — upload a photo to library
router.post(
  '/me/photos',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const image = (req.body.image || '').toString().trim();
    if (!image) throw new HttpError(400, 'Image is required.');

    const caption = (req.body.caption || '').toString().trim().slice(0, 200);

    const result = await pool.query(
      `INSERT INTO user_photos (user_id, image, caption)
       VALUES ($1, $2, $3)
       RETURNING id, image, caption, created_at AS "createdAt"`,
      [req.auth.sub, image, caption],
    );
    res.status(201).json({ photo: result.rows[0] });
  }),
);

// DELETE /users/me/photos/:id — delete own photo
router.delete(
  '/me/photos/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const result = await pool.query(
      `DELETE FROM user_photos WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.auth.sub],
    );
    if (!result.rows.length) throw new HttpError(404, 'Photo not found.');
    res.json({ deleted: true });
  }),
);

// GET /users/me/profile-data — get own profile data
router.get(
  '/me/profile-data',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ profileData: null });

    const result = await pool.query(
      `SELECT bio, address, school, birthday, work,
              current_city AS "currentCity", hometown,
              relationship_status AS "relationshipStatus", featured,
              profile_pic AS "profilePic", cover_pic AS "coverPic"
       FROM user_profiles WHERE user_id = $1`,
      [req.auth.sub],
    );

    res.json({ profileData: result.rows[0] || null });
  }),
);

// PUT /users/me/profile-data — save own profile data
router.put(
  '/me/profile-data',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const {
      bio = '',
      address = '',
      school = '',
      birthday = '',
      work = '',
      currentCity = '',
      hometown = '',
      relationshipStatus = '',
      featured = [],
      profilePic,
      coverPic,
    } = req.body;

    await pool.query(
      `INSERT INTO user_profiles (user_id, bio, address, school, birthday, work, current_city, hometown, relationship_status, featured, profile_pic, cover_pic, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         bio = EXCLUDED.bio,
         address = EXCLUDED.address,
         school = EXCLUDED.school,
         birthday = EXCLUDED.birthday,
         work = EXCLUDED.work,
         current_city = EXCLUDED.current_city,
         hometown = EXCLUDED.hometown,
         relationship_status = EXCLUDED.relationship_status,
         featured = EXCLUDED.featured,
         profile_pic = COALESCE(EXCLUDED.profile_pic, user_profiles.profile_pic),
         cover_pic = COALESCE(EXCLUDED.cover_pic, user_profiles.cover_pic),
         updated_at = NOW()`,
      [
        req.auth.sub,
        bio,
        address,
        school,
        birthday,
        work,
        currentCity,
        hometown,
        relationshipStatus,
        JSON.stringify(Array.isArray(featured) ? featured : []),
        profilePic ?? null,
        coverPic ?? null,
      ],
    );

    const result = await pool.query(
      `SELECT bio, address, school, birthday, work,
              current_city AS "currentCity", hometown,
              relationship_status AS "relationshipStatus", featured,
              profile_pic AS "profilePic", cover_pic AS "coverPic"
       FROM user_profiles WHERE user_id = $1`,
      [req.auth.sub],
    );

    res.json({ profileData: result.rows[0] });
  }),
);

// PUT /users/me/profile-pic — update only profile pic (separate to keep payload small)
router.put(
  '/me/profile-pic',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const hasProfilePic = Object.prototype.hasOwnProperty.call(req.body, 'profilePic');
    const hasCoverPic = Object.prototype.hasOwnProperty.call(req.body, 'coverPic');
    const { profilePic, coverPic } = req.body;

    await pool.query(
      `INSERT INTO user_profiles (user_id, profile_pic, cover_pic, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         profile_pic = CASE WHEN $4 THEN EXCLUDED.profile_pic ELSE user_profiles.profile_pic END,
         cover_pic = CASE WHEN $5 THEN EXCLUDED.cover_pic ELSE user_profiles.cover_pic END,
         updated_at = NOW()`,
      [req.auth.sub, profilePic ?? null, coverPic ?? null, hasProfilePic, hasCoverPic],
    );

    res.json({ ok: true });
  }),
);

// GET /users/:userId/profile-data — public profile data (bio, pics, etc.)
router.get(
  '/:userId/profile-data',
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ profileData: null });

    const result = await pool.query(
      `SELECT bio, address, school, birthday, work,
              current_city AS "currentCity", hometown,
              relationship_status AS "relationshipStatus", featured,
              profile_pic AS "profilePic", cover_pic AS "coverPic"
       FROM user_profiles WHERE user_id = $1`,
      [parsed.data],
    );
    res.json({ profileData: result.rows[0] || null });
  }),
);

// GET /users/:userId/social-posts — public social posts
router.get(
  '/:userId/social-posts',
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ posts: [] });

    const limit = Math.min(parseInt(req.query.limit) || 30, 80);
    const result = await pool.query(
      `SELECT id, user_id AS "userId", full_name AS "fullName",
              profile_pic AS "profilePic", body, image, video, metadata, privacy,
              scheduled_at AS "scheduledAt",
              shared_from_type AS "sharedFromType",
              shared_from_id AS "sharedFromId",
              shared_snapshot AS "sharedSnapshot",
              created_at AS "createdAt"
       FROM social_posts
       WHERE user_id = $1 AND privacy = 'Public' AND (scheduled_at IS NULL OR scheduled_at <= NOW())
       ORDER BY created_at DESC LIMIT $2`,
      [parsed.data, limit],
    );
    const items = result.rows.map((post) => ({
      type: 'post',
      id: post.id,
      createdAt: post.createdAt,
      socialPost: post,
    }));
    await attachInteractionCounts(items);
    res.json({
      posts: items.map((item) => ({
        ...item.socialPost,
        likeCount: item.likeCount || 0,
        commentCount: item.commentCount || 0,
        isLiked: false,
      })),
    });
  }),
);

// GET /users/:userId/photos — public photo library
router.get(
  '/:userId/photos',
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ photos: [] });

    const result = await pool.query(
      `SELECT id, image, caption, created_at AS "createdAt"
       FROM user_photos WHERE user_id = $1 ORDER BY created_at DESC`,
      [parsed.data],
    );
    res.json({ photos: result.rows });
  }),
);

// GET /users/:userId/profile — public profile with posts and follow counts
router.get(
  '/:userId/profile',
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const userResult = await pool.query(
      `SELECT id, full_name AS "fullName", role, status, created_at AS "createdAt"
       FROM users WHERE id = $1`,
      [parsed.data],
    );
    if (!userResult.rows.length) throw new HttpError(404, 'User not found.');

    const postsResult = await pool.query(
      `SELECT jp.id, jp.title, jp.category, jp.municipality, jp.description,
              jp.budget_min AS "budgetMin", jp.budget_max AS "budgetMax",
              jp.post_type AS "postType", jp.status, jp.created_at AS "createdAt",
              (SELECT COUNT(*)::int FROM job_offers jo WHERE jo.job_post_id = jp.id) AS "offerCount"
       FROM job_posts jp
       WHERE jp.client_user_id = $1
       ORDER BY jp.created_at DESC LIMIT 15`,
      [parsed.data],
    );

    const countResult = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM follows WHERE following_user_id = $1) AS "followerCount",
         (SELECT COUNT(*)::int FROM follows WHERE follower_user_id = $1) AS "followingCount"`,
      [parsed.data],
    );

    const counts = countResult.rows[0] || { followerCount: 0, followingCount: 0 };

    res.json({
      user: userResult.rows[0],
      posts: postsResult.rows,
      followerCount: counts.followerCount,
      followingCount: counts.followingCount,
    });
  }),
);

// GET /users/:userId/follow-status — check if current user follows this user
router.get(
  '/:userId/follow-status',
  authenticate,
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ isFollowing: false });

    const result = await pool.query(
      `SELECT 1 FROM follows WHERE follower_user_id = $1 AND following_user_id = $2`,
      [req.auth.sub, parsed.data],
    );

    res.json({ isFollowing: result.rows.length > 0 });
  }),
);

// POST /users/:userId/follow
router.post(
  '/:userId/follow',
  authenticate,
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');
    if (parsed.data === req.auth.sub) throw new HttpError(400, 'Cannot follow yourself.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    await pool.query(
      `INSERT INTO follows (follower_user_id, following_user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [req.auth.sub, parsed.data],
    );

    const countResult = await pool.query(
      `SELECT COUNT(*)::int AS "followerCount" FROM follows WHERE following_user_id = $1`,
      [parsed.data],
    );

    res.json({ followed: true, followerCount: countResult.rows[0].followerCount });
  }),
);

// DELETE /users/:userId/follow
router.delete(
  '/:userId/follow',
  authenticate,
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    await pool.query(
      `DELETE FROM follows WHERE follower_user_id = $1 AND following_user_id = $2`,
      [req.auth.sub, parsed.data],
    );

    const countResult = await pool.query(
      `SELECT COUNT(*)::int AS "followerCount" FROM follows WHERE following_user_id = $1`,
      [parsed.data],
    );

    res.json({ unfollowed: true, followerCount: countResult.rows[0].followerCount });
  }),
);

// GET /users/:userId/public (existing route — keep)
router.get(
  '/:userId/public',
  authenticate,
  asyncHandler(async (req, res) => {
    const userId = z.string().uuid().safeParse(req.params.userId);

    if (!userId.success) {
      throw new HttpError(400, 'Invalid user id.');
    }

    const user = await findUserById(userId.data);
    if (!user) {
      throw new HttpError(404, 'User not found.');
    }

    res.json({
      user: {
        id: user.id,
        fullName: user.fullName,
        role: user.role,
        status: user.status,
      },
    });
  }),
);

module.exports = { userRoutes: router };
