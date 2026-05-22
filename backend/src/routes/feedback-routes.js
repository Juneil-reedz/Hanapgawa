const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { getPostgresPool } = require('../db/postgres');

const router = express.Router();

const submitSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).default(''),
  appVersion: z.string().max(20).default(''),
});

// POST /feedback — submit anonymous feedback (auth required to prevent spam)
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const parsed = submitSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Invalid feedback data' });
    }
    const { rating, comment, appVersion } = parsed.data;
    const pool = getPostgresPool();
    if (!pool) return res.json({ ok: true });

    await pool.query(
      `INSERT INTO app_feedback (rating, comment, app_version) VALUES ($1, $2, $3)`,
      [rating, comment.trim(), appVersion],
    );
    res.json({ ok: true });
  }),
);

// GET /feedback — admin view of all feedback
router.get(
  '/',
  authenticate,
  authorizeRoles('admin'),
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ feedback: [] });

    const result = await pool.query(
      `SELECT id, rating, comment, app_version AS "appVersion", created_at AS "createdAt"
       FROM app_feedback
       ORDER BY created_at DESC
       LIMIT 200`,
    );

    const rows = result.rows;
    const total = rows.length;
    const avg = total > 0
      ? (rows.reduce((s, r) => s + r.rating, 0) / total).toFixed(1)
      : '0.0';

    const distribution = [1, 2, 3, 4, 5].map((star) => ({
      star,
      count: rows.filter((r) => r.rating === star).length,
    }));

    res.json({ feedback: rows, total, average: parseFloat(avg), distribution });
  }),
);

module.exports = { feedbackRoutes: router };
