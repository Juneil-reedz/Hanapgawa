const express = require('express');
const { asyncHandler } = require('../lib/async-handler');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');

const router = express.Router();

// GET /notifications/unread-count  (must be before /:id)
router.get('/unread-count', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ count: 0 });
  const r = await pool.query(
    `SELECT COUNT(*)::int AS count FROM notifications WHERE user_id = $1 AND read_at IS NULL`,
    [req.auth.sub],
  );
  res.json({ count: r.rows[0].count });
}));

// GET /notifications
router.get('/', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ notifications: [] });
  const limit = Math.min(parseInt(req.query.limit) || 40, 100);
  const r = await pool.query(
    `SELECT id, actor_id AS "actorId", actor_name AS "actorName", type, title, body,
            link_type AS "linkType", link_id AS "linkId",
            read_at AS "readAt", created_at AS "createdAt"
     FROM notifications WHERE user_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [req.auth.sub, limit],
  );
  res.json({ notifications: r.rows });
}));

// POST /notifications/read-all  (must be before /:id)
router.post('/read-all', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ ok: true });
  await pool.query(
    `UPDATE notifications SET read_at = NOW() WHERE user_id = $1 AND read_at IS NULL`,
    [req.auth.sub],
  );
  res.json({ ok: true });
}));

// POST /notifications/:id/read
router.post('/:id/read', authenticate, asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.json({ ok: true });
  await pool.query(
    `UPDATE notifications SET read_at = NOW() WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.auth.sub],
  );
  res.json({ ok: true });
}));

module.exports = { notificationRoutes: router };
