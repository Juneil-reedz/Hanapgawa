const express = require('express');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');

const router = express.Router();

router.get('/', asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ stories: [] });
  const result = await pool.query(
    `SELECT s.id, s.user_id AS "userId", s.full_name AS "fullName",
            COALESCE(up.profile_pic, s.profile_pic) AS "profilePic",
            s.body, s.image, s.video, s.metadata, s.privacy,
            s.expires_at AS "expiresAt", s.created_at AS "createdAt"
     FROM stories s
     LEFT JOIN user_profiles up ON up.user_id = s.user_id
     WHERE s.expires_at > NOW() AND s.privacy = 'Public'
     ORDER BY s.created_at DESC
     LIMIT 50`,
  );
  res.json({ stories: result.rows });
}));

router.post('/', authenticate, asyncHandler(async (req, res) => {
  const body = (req.body.body || '').toString().trim();
  const image = req.body.image ? req.body.image.toString() : null;
  const video = req.body.video ? req.body.video.toString() : null;
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
