const express = require('express');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');
const { env } = require('../config/env');

const router = express.Router();

function optionalAuth(req) {
  try {
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      return jwt.verify(header.slice(7), env.jwtSecret).sub;
    }
  } catch { /* invalid token - treat as unauthenticated */ }
  return null;
}

async function uploadToCloudinary(file, resourceType) {
  if (!file || file.startsWith('http://') || file.startsWith('https://')) return file;
  const { cloudinaryCloudName, cloudinaryApiKey, cloudinaryApiSecret } = env;
  if (!cloudinaryCloudName || !cloudinaryApiKey || !cloudinaryApiSecret) {
    throw new HttpError(503, 'Media upload is not configured.');
  }

  const timestamp = Math.floor(Date.now() / 1000).toString();
  const folder = 'hanapgawa/stories';
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

router.get('/', asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ stories: [] });
  const viewerId = optionalAuth(req);
  const result = await pool.query(
    `SELECT s.id, s.user_id AS "userId", s.full_name AS "fullName",
            COALESCE(up.profile_pic, s.profile_pic) AS "profilePic",
            s.body, s.image, s.video, s.metadata, s.privacy,
            s.expires_at AS "expiresAt", s.created_at AS "createdAt",
            CASE
              WHEN s.user_id = $1 THEN TRUE
              WHEN sv.user_id IS NOT NULL THEN TRUE
              ELSE FALSE
            END AS "viewedByMe"
     FROM stories s
     LEFT JOIN user_profiles up ON up.user_id = s.user_id
     LEFT JOIN story_views sv ON sv.story_id = s.id AND sv.user_id = $1
     WHERE s.expires_at > NOW() AND s.privacy = 'Public'
     ORDER BY s.created_at DESC
     LIMIT 50`,
    [viewerId],
  );
  res.json({ stories: result.rows });
}));

router.post('/', authenticate, asyncHandler(async (req, res) => {
  const body = (req.body.body || '').toString().trim();
  const image = req.body.image ? req.body.image.toString() : null;
  const video = req.body.video ? await uploadToCloudinary(req.body.video.toString(), 'video') : null;
  const metadata = req.body.metadata && typeof req.body.metadata === 'object' ? req.body.metadata : {};
  const privacy = req.body.privacy ? req.body.privacy.toString() : 'Public';
  if (!body && !image && !video && Object.keys(metadata).length === 0) {
    throw new HttpError(400, 'Story content is required.');
  }
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'Database unavailable.');
  const user = await pool.query(
    `SELECT u.full_name, up.profile_pic FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1`,
    [req.auth.sub],
  );
  const result = await pool.query(
    `INSERT INTO stories (user_id, full_name, profile_pic, body, image, video, metadata, privacy)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id, user_id AS "userId", full_name AS "fullName", profile_pic AS "profilePic",
       body, image, video, metadata, privacy, expires_at AS "expiresAt", created_at AS "createdAt"`,
    [req.auth.sub, user.rows[0]?.full_name || 'User', user.rows[0]?.profile_pic || null, body, image, video, JSON.stringify(metadata), privacy],
  );
  res.status(201).json({ story: result.rows[0] });
}));

router.post('/:storyId/view', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'Database unavailable.');
  await pool.query(
    `INSERT INTO story_views (story_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
    [req.params.storyId, req.auth.sub],
  );
  res.json({ viewed: true });
}));

router.delete('/:storyId', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'Database unavailable.');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const story = await client.query(
      `SELECT id FROM stories WHERE id = $1 AND user_id = $2`,
      [req.params.storyId, req.auth.sub],
    );
    if (!story.rows[0]) throw new HttpError(404, 'Story not found.');

    await client.query(`DELETE FROM story_reactions WHERE story_id = $1`, [req.params.storyId]);
    await client.query(`DELETE FROM story_views WHERE story_id = $1`, [req.params.storyId]);
    await client.query(`DELETE FROM stories WHERE id = $1`, [req.params.storyId]);
    await client.query('COMMIT');
    res.json({ deleted: true });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

router.get('/:storyId/viewers', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'Database unavailable.');
  const story = await pool.query(`SELECT user_id FROM stories WHERE id = $1`, [req.params.storyId]);
  if (!story.rows[0]) throw new HttpError(404, 'Story not found.');
  if (story.rows[0].user_id !== req.auth.sub) {
    throw new HttpError(403, 'Only the story owner can view story viewers.');
  }
  const result = await pool.query(
    `SELECT sv.user_id AS "userId", u.full_name AS "fullName", sv.created_at AS "viewedAt",
            sr.reaction
     FROM story_views sv
     JOIN users u ON u.id = sv.user_id
     LEFT JOIN story_reactions sr ON sr.story_id = sv.story_id AND sr.user_id = sv.user_id
     WHERE sv.story_id = $1 AND sv.user_id != $2
     ORDER BY sv.created_at DESC`,
    [req.params.storyId, req.auth.sub],
  );
  res.json({ viewers: result.rows });
}));

router.post('/:storyId/react', authenticate, asyncHandler(async (req, res) => {
  const reaction = (req.body.reaction || '').toString().trim();
  if (!reaction) throw new HttpError(400, 'Reaction is required.');
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'Database unavailable.');
  await pool.query(
    `INSERT INTO story_reactions (story_id, user_id, reaction)
     VALUES ($1, $2, $3)
     ON CONFLICT (story_id, user_id) DO UPDATE SET reaction = EXCLUDED.reaction, created_at = NOW()`,
    [req.params.storyId, req.auth.sub, reaction],
  );
  res.json({ reacted: true });
}));

module.exports = { storyRoutes: router };
