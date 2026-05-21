const express = require('express');
const crypto = require('crypto');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');
const { env } = require('../config/env');
const { createNotification, notifyMentions } = require('../lib/notifications');
const { attachInteractionCounts } = require('../services/feed-service');

const router = express.Router();

async function uploadToCloudinary(file, resourceType) {
  if (!file || file.startsWith('http://') || file.startsWith('https://')) return file;
  const { cloudinaryCloudName, cloudinaryApiKey, cloudinaryApiSecret } = env;
  if (!cloudinaryCloudName || !cloudinaryApiKey || !cloudinaryApiSecret) return file;

  const timestamp = Math.floor(Date.now() / 1000).toString();
  const folder = 'hanapgawa/posts';
  const signature = crypto
    .createHash('sha1')
    .update(`folder=${folder}&timestamp=${timestamp}${cloudinaryApiSecret}`)
    .digest('hex');
  const mime = resourceType === 'video' ? 'video/mp4' : 'image/jpeg';
  const form = new FormData();
  form.append('file', file.startsWith('data:') ? file : `data:${mime};base64,${file}`);
  form.append('api_key', cloudinaryApiKey);
  form.append('timestamp', timestamp);
  form.append('folder', folder);
  form.append('signature', signature);

  const response = await fetch(`https://api.cloudinary.com/v1_1/${cloudinaryCloudName}/auto/upload`, {
    method: 'POST',
    body: form,
  });
  if (!response.ok) throw new HttpError(502, 'Media upload failed.');
  const json = await response.json();
  return json.secure_url;
}

// Used in INSERT...RETURNING (no JOIN alias needed)
const SELECT_COLS = `
  id, user_id AS "userId", full_name AS "fullName",
  profile_pic AS "profilePic", body, image, video, metadata, privacy,
  scheduled_at AS "scheduledAt",
  shared_from_type AS "sharedFromType",
  shared_from_id AS "sharedFromId",
  shared_snapshot AS "sharedSnapshot",
  created_at AS "createdAt"
`;

// Used in SELECT queries — JOINs current profile pic so old posts show updated avatars
const SELECT_JOINED = `
  sp.id, sp.user_id AS "userId", sp.full_name AS "fullName",
  COALESCE(up.profile_pic, sp.profile_pic) AS "profilePic",
  sp.body, sp.image, sp.video, sp.metadata, sp.privacy,
  sp.scheduled_at AS "scheduledAt",
  sp.shared_from_type AS "sharedFromType",
  sp.shared_from_id AS "sharedFromId",
  sp.shared_snapshot AS "sharedSnapshot",
  sp.created_at AS "createdAt"
`;
const FROM_JOINED = `FROM social_posts sp LEFT JOIN user_profiles up ON up.user_id = sp.user_id`;

// GET /posts
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 30, 80);
    const pool = getPostgresPool();
    if (!pool) return res.json({ posts: [] });

    const result = await pool.query(
      `SELECT ${SELECT_JOINED} ${FROM_JOINED}
       WHERE sp.privacy = 'Public' AND (sp.scheduled_at IS NULL OR sp.scheduled_at <= NOW())
       ORDER BY sp.created_at DESC LIMIT $1`,
      [limit],
    );
    res.json({ posts: result.rows });
  }),
);

// GET /posts/mine
router.get(
  '/mine',
  authenticate,
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 30, 80);
    const pool = getPostgresPool();
    if (!pool) return res.json({ posts: [] });

    const result = await pool.query(
      `SELECT ${SELECT_JOINED} ${FROM_JOINED} WHERE sp.user_id = $1 ORDER BY sp.created_at DESC LIMIT $2`,
      [req.auth.sub, limit],
    );
    const items = result.rows.map((post) => ({
      type: 'post',
      id: post.id,
      createdAt: post.createdAt,
      socialPost: post,
    }));
    await attachInteractionCounts(items, req.auth.sub);
    res.json({
      posts: items.map((item) => ({
        ...item.socialPost,
        likeCount: item.likeCount || 0,
        commentCount: item.commentCount || 0,
        isLiked: item.isLiked === true,
      })),
    });
  }),
);

// POST /posts
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    if (req.auth.role === 'admin') {
      throw new HttpError(403, 'Admins cannot create user posts.');
    }

    const body = (req.body.body || '').toString().trim();
    if (!body && !req.body.image && !req.body.video && !req.body.sharedFromType) throw new HttpError(400, 'Post body is required.');
    if (body.length > 2000) throw new HttpError(400, 'Post is too long.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const image = req.body.image ? await uploadToCloudinary(req.body.image.toString(), 'image') : null;
    const video = req.body.video ? await uploadToCloudinary(req.body.video.toString(), 'video') : null;
    const metadata = req.body.metadata && typeof req.body.metadata === 'object' ? req.body.metadata : {};
    const privacy = req.body.privacy ? req.body.privacy.toString() : 'Public';
    const scheduledAt = req.body.scheduledAt ? new Date(req.body.scheduledAt) : null;
    const validPrivacy = new Set(['Public', 'Friends', 'Friends except...', 'Specific friends', 'Only me']);
    if (!validPrivacy.has(privacy)) throw new HttpError(400, 'Invalid privacy setting.');
    if (scheduledAt && Number.isNaN(scheduledAt.getTime())) throw new HttpError(400, 'Invalid schedule date.');
    const sharedFromType = req.body.sharedFromType ? req.body.sharedFromType.toString() : null;
    const sharedFromId = req.body.sharedFromId ? req.body.sharedFromId.toString() : null;
    const sharedSnapshot = req.body.sharedSnapshot || null;

    const userResult = await pool.query(
      `SELECT u.full_name, up.profile_pic
       FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1`,
      [req.auth.sub],
    );
    const fullName = userResult.rows[0]?.full_name || 'User';
    const profilePic = userResult.rows[0]?.profile_pic || null;

    const result = await pool.query(
      `INSERT INTO social_posts
         (user_id, full_name, profile_pic, body, image, video, metadata, privacy, scheduled_at, shared_from_type, shared_from_id, shared_snapshot)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING ${SELECT_COLS}`,
      [req.auth.sub, fullName, profilePic, body || '', image, video, JSON.stringify(metadata), privacy, scheduledAt, sharedFromType, sharedFromId,
       sharedSnapshot ? JSON.stringify(sharedSnapshot) : null],
    );

    (async () => {
      try {
        // Notify original post author when their post is shared
        if (sharedFromType === 'post' && sharedFromId) {
          const orig = await pool.query(
            `SELECT user_id FROM social_posts WHERE id = $1`, [sharedFromId],
          );
          if (orig.rows.length && orig.rows[0].user_id !== req.auth.sub) {
            await createNotification(pool, {
              userId: orig.rows[0].user_id,
              actorId: req.auth.sub,
              actorName: fullName,
              type: 'share',
              title: `${fullName} shared your post`,
              body: body.slice(0, 100),
              linkType: 'post',
              linkId: result.rows[0].id,
            });
          }
        }
        // Notify @mentions in the post body
        if (body) await notifyMentions(pool, body, req.auth.sub, fullName, 'post', result.rows[0].id);
      } catch { /* non-fatal */ }
    })();

    res.status(201).json({ post: result.rows[0] });
  }),
);

// PATCH /posts/:id
router.patch(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    if (req.auth.role === 'admin') {
      throw new HttpError(403, 'Admins cannot edit user posts.');
    }

    const body = (req.body.body || '').toString().trim();
    const privacy = req.body.privacy ? req.body.privacy.toString() : 'Public';
    const validPrivacy = new Set(['Public', 'Friends', 'Friends except...', 'Specific friends', 'Only me']);
    if (!validPrivacy.has(privacy)) throw new HttpError(400, 'Invalid privacy setting.');
    if (body.length > 2000) throw new HttpError(400, 'Post is too long.');
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const result = await pool.query(
      `UPDATE social_posts
       SET body = $1, privacy = $2
       WHERE id = $3 AND user_id = $4
       RETURNING ${SELECT_COLS}`,
      [body, privacy, req.params.id, req.auth.sub],
    );
    if (!result.rows.length) throw new HttpError(404, 'Post not found or not yours.');
    res.json({ post: result.rows[0] });
  }),
);

// DELETE /posts/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const result = await pool.query(
      `DELETE FROM social_posts WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.auth.sub],
    );
    if (!result.rows.length) throw new HttpError(404, 'Post not found or not yours.');
    res.json({ deleted: true });
  }),
);

module.exports = { socialPostRoutes: router };
