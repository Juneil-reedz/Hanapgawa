const express = require('express');

const { asyncHandler } = require('../lib/async-handler');
const { authenticate } = require('../middleware/authenticate');
const { getPublicFeed, getUserTimeline } = require('../services/feed-service');

const router = express.Router();

// GET /feed — public newsfeed (recent listings + open jobs + reviews)
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 40, 80);
    const items = await getPublicFeed({ limit });
    res.json({ items });
  }),
);

// GET /feed/timeline — authenticated personal activity timeline
router.get(
  '/timeline',
  authenticate,
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const events = await getUserTimeline({ userId: req.auth.sub, role: req.auth.role, limit });
    res.json({ events });
  }),
);

module.exports = { feedRoutes: router };
