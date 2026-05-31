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

// PUT /users/me/device-token — register/update FCM device token for push notifications
router.put(
  '/me/device-token',
  authenticate,
  asyncHandler(async (req, res) => {
    const { token, platform = 'android' } = req.body;
    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'token is required' });
    }
    const pool = getPostgresPool();
    if (!pool) return res.json({ ok: true });
    await pool.query(
      `INSERT INTO user_device_tokens (user_id, token, platform, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, token) DO UPDATE SET platform = $3, updated_at = NOW()`,
      [req.auth.sub, token, platform],
    );
    res.json({ ok: true });
  }),
);

// DELETE /users/me/device-token — unregister FCM token on logout
router.delete(
  '/me/device-token',
  authenticate,
  asyncHandler(async (req, res) => {
    const { token } = req.body;
    const pool = getPostgresPool();
    if (!pool) return res.json({ ok: true });
    if (token) {
      await pool.query(
        `DELETE FROM user_device_tokens WHERE user_id = $1 AND token = $2`,
        [req.auth.sub, token],
      );
    } else {
      await pool.query(`DELETE FROM user_device_tokens WHERE user_id = $1`, [req.auth.sub]);
    }
    res.json({ ok: true });
  }),
);

// GET /users/me/photos — get current user's photo library (own uploads + post media + profile/cover)
router.get(
  '/me/photos',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ photos: [] });

    const result = await pool.query(
      `SELECT id::text, image, NULL AS video, caption, created_at AS "createdAt", 'photo' AS source
       FROM user_photos WHERE user_id = $1 AND image IS NOT NULL
       UNION ALL
       SELECT id::text, image, NULL AS video, SUBSTRING(body, 1, 120) AS caption, created_at AS "createdAt", 'post' AS source
       FROM social_posts WHERE user_id = $1 AND image IS NOT NULL AND privacy = 'Public' AND (scheduled_at IS NULL OR scheduled_at <= NOW())
       UNION ALL
       SELECT id::text, NULL AS image, video, SUBSTRING(body, 1, 120) AS caption, created_at AS "createdAt", 'post_video' AS source
       FROM social_posts WHERE user_id = $1 AND video IS NOT NULL AND privacy = 'Public' AND (scheduled_at IS NULL OR scheduled_at <= NOW())
       UNION ALL
       SELECT 'profile_pic'::text AS id, profile_pic AS image, NULL AS video, 'Profile Photo' AS caption, updated_at AS "createdAt", 'profile_pic' AS source
       FROM user_profiles WHERE user_id = $1 AND profile_pic IS NOT NULL
       UNION ALL
       SELECT 'cover_pic'::text AS id, cover_pic AS image, NULL AS video, 'Cover Photo' AS caption, updated_at AS "createdAt", 'cover_pic' AS source
       FROM user_profiles WHERE user_id = $1 AND cover_pic IS NOT NULL
       ORDER BY "createdAt" DESC`,
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

// GET /users/me/followers — users who follow me
router.get(
  '/me/followers',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ users: [] });

    const result = await pool.query(
      `SELECT u.id, u.full_name AS "fullName", u.role, u.status,
              up.profile_pic AS "profilePic", up.bio,
              COALESCE(fc.followers, 0)::int AS followers,
              COALESCE(pc.posts, 0)::int AS posts
       FROM follows f
       JOIN users u ON u.id = f.follower_user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       LEFT JOIN (
         SELECT following_user_id, COUNT(*)::int AS followers
         FROM follows GROUP BY following_user_id
       ) fc ON fc.following_user_id = u.id
       LEFT JOIN (
         SELECT user_id, COUNT(*)::int AS posts
         FROM social_posts GROUP BY user_id
       ) pc ON pc.user_id = u.id
       WHERE f.following_user_id = $1
       ORDER BY u.full_name`,
      [req.auth.sub],
    );

    res.json({ users: result.rows });
  }),
);

// GET /users/me/following — users I follow
router.get(
  '/me/following',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ users: [] });

    const result = await pool.query(
      `SELECT u.id, u.full_name AS "fullName", u.role, u.status,
              up.profile_pic AS "profilePic", up.bio,
              COALESCE(fc.followers, 0)::int AS followers,
              COALESCE(pc.posts, 0)::int AS posts
       FROM follows f
       JOIN users u ON u.id = f.following_user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       LEFT JOIN (
         SELECT following_user_id, COUNT(*)::int AS followers
         FROM follows GROUP BY following_user_id
       ) fc ON fc.following_user_id = u.id
       LEFT JOIN (
         SELECT user_id, COUNT(*)::int AS posts
         FROM social_posts GROUP BY user_id
       ) pc ON pc.user_id = u.id
       WHERE f.follower_user_id = $1
       ORDER BY u.full_name`,
      [req.auth.sub],
    );

    res.json({ users: result.rows });
  }),
);

// GET /users/me/profile-data — get own profile data
router.get(
  '/me/profile-data',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ profileData: null, followerCount: 0, followingCount: 0 });

    const [profileResult, countResult] = await Promise.all([
      pool.query(
        `SELECT bio, address, school, birthday, work,
                current_city AS "currentCity", hometown,
                relationship_status AS "relationshipStatus", featured,
                profile_pic AS "profilePic", cover_pic AS "coverPic"
         FROM user_profiles WHERE user_id = $1`,
        [req.auth.sub],
      ),
      pool.query(
        `SELECT
           (SELECT COUNT(*)::int FROM follows WHERE following_user_id = $1) AS "followerCount",
           (SELECT COUNT(*)::int FROM follows WHERE follower_user_id = $1) AS "followingCount"`,
        [req.auth.sub],
      ),
    ]);

    const counts = countResult.rows[0] || { followerCount: 0, followingCount: 0 };
    res.json({
      profileData: profileResult.rows[0] || null,
      followerCount: counts.followerCount,
      followingCount: counts.followingCount,
    });
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

// GET /users/:userId/photos — public photo library (uploads + post media + profile/cover)
router.get(
  '/:userId/photos',
  asyncHandler(async (req, res) => {
    const parsed = z.string().uuid().safeParse(req.params.userId);
    if (!parsed.success) throw new HttpError(400, 'Invalid user id.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ photos: [] });

    const result = await pool.query(
      `SELECT id::text, image, NULL AS video, caption, created_at AS "createdAt", 'photo' AS source
       FROM user_photos WHERE user_id = $1 AND image IS NOT NULL
       UNION ALL
       SELECT id::text, image, NULL AS video, SUBSTRING(body, 1, 120) AS caption, created_at AS "createdAt", 'post' AS source
       FROM social_posts WHERE user_id = $1 AND image IS NOT NULL AND privacy = 'Public' AND (scheduled_at IS NULL OR scheduled_at <= NOW())
       UNION ALL
       SELECT id::text, NULL AS image, video, SUBSTRING(body, 1, 120) AS caption, created_at AS "createdAt", 'post_video' AS source
       FROM social_posts WHERE user_id = $1 AND video IS NOT NULL AND privacy = 'Public' AND (scheduled_at IS NULL OR scheduled_at <= NOW())
       UNION ALL
       SELECT 'profile_pic'::text AS id, profile_pic AS image, NULL AS video, 'Profile Photo' AS caption, updated_at AS "createdAt", 'profile_pic' AS source
       FROM user_profiles WHERE user_id = $1 AND profile_pic IS NOT NULL
       UNION ALL
       SELECT 'cover_pic'::text AS id, cover_pic AS image, NULL AS video, 'Cover Photo' AS caption, updated_at AS "createdAt", 'cover_pic' AS source
       FROM user_profiles WHERE user_id = $1 AND cover_pic IS NOT NULL
       ORDER BY "createdAt" DESC`,
      [parsed.data],
    );
    res.json({ photos: result.rows });
  }),
);

// GET /users/suggested — suggested accounts to follow (must come before /:userId)
router.get(
  '/suggested',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ users: [] });

    const userId = req.auth.sub;
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);

    const result = await pool.query(
      `SELECT u.id, u.full_name AS "fullName", u.role,
              up.profile_pic AS "profilePic", up.bio,
              COALESCE(fc.followers, 0)::int AS followers,
              COALESCE(pc.posts, 0)::int AS posts
       FROM users u
       LEFT JOIN user_profiles up ON up.user_id = u.id
       LEFT JOIN (
         SELECT following_user_id, COUNT(*)::int AS followers
         FROM follows GROUP BY following_user_id
       ) fc ON fc.following_user_id = u.id
       LEFT JOIN (
         SELECT user_id, COUNT(*)::int AS posts
         FROM social_posts GROUP BY user_id
       ) pc ON pc.user_id = u.id
       WHERE u.email_verified_at IS NOT NULL
         AND u.id != $1
         AND u.role != 'admin'
         AND u.id NOT IN (
           SELECT following_user_id FROM follows WHERE follower_user_id = $1
         )
       ORDER BY (COALESCE(fc.followers, 0) + COALESCE(pc.posts, 0) * 2) DESC
       LIMIT $2`,
      [userId, limit],
    );

    res.json({ users: result.rows });
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

// GET /users/:userId/avatar — lightweight profile pic fetch (used by feed cards)
router.get(
  '/:userId/avatar',
  asyncHandler(async (req, res) => {
    const pool = require('../db/postgres').getPostgresReadPool();
    if (!pool) return res.json({ pic: null });
    const result = await pool.query(
      `SELECT profile_pic AS pic FROM user_profiles WHERE user_id = $1`,
      [req.params.userId],
    );
    res.json({ pic: result.rows[0]?.pic ?? null });
  }),
);

// POST /users/avatars — batch profile pic fetch for multiple user IDs
router.post(
  '/avatars',
  asyncHandler(async (req, res) => {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids.slice(0, 50) : [];
    if (!ids.length) return res.json({ pics: {} });
    const pool = require('../db/postgres').getPostgresReadPool();
    if (!pool) return res.json({ pics: {} });
    const result = await pool.query(
      `SELECT user_id AS "userId", profile_pic AS pic FROM user_profiles WHERE user_id = ANY($1)`,
      [ids],
    );
    const pics = {};
    for (const row of result.rows) pics[row.userId] = row.pic ?? null;
    res.json({ pics });
  }),
);

module.exports = { userRoutes: router };
