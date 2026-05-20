const jwt = require('jsonwebtoken');
const express = require('express');
const { createNotification, notifyMentions } = require('../lib/notifications');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');
const { env } = require('../config/env');
const { getPublicFeed, getUserTimeline } = require('../services/feed-service');

const router = express.Router();

const VALID_TYPES = new Set(['listing', 'job', 'review', 'post']);

function optionalAuth(req) {
  try {
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      const decoded = jwt.verify(header.slice(7), env.jwtSecret);
      return decoded.sub;
    }
  } catch { /* invalid token — treat as unauthenticated */ }
  return null;
}

// GET /feed/post/:id — single social post for notification deep-link
router.get('/post/:id', asyncHandler(async (req, res) => {
  const pool = getPostgresPool();
  if (!pool) return res.status(404).json({ error: 'Not found' });

  const r = await pool.query(
    `SELECT id, user_id AS "userId", full_name AS "fullName",
            profile_pic AS "profilePic", body, image, video, metadata, privacy,
            created_at AS "createdAt",
            (SELECT COUNT(*)::int FROM post_reactions WHERE item_type = 'post' AND item_id = sp.id::text) AS "likeCount",
            (SELECT COUNT(*)::int FROM post_comments WHERE item_type = 'post' AND item_id = sp.id::text) AS "commentCount"
     FROM social_posts sp WHERE id = $1::uuid`,
    [req.params.id],
  );

  if (!r.rows.length) return res.status(404).json({ error: 'Post not found' });

  const p = r.rows[0];
  res.json({
    item: {
      id: p.id, type: 'post', createdAt: p.createdAt,
      likeCount: p.likeCount, commentCount: p.commentCount, isLiked: false,
      socialPost: {
        id: p.id, userId: p.userId, fullName: p.fullName,
        profilePic: p.profilePic, body: p.body, image: p.image,
        video: p.video, metadata: p.metadata || {}, privacy: p.privacy,
        createdAt: p.createdAt,
      },
    },
  });
}));

// GET /feed
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 40, 80);
    const userId = optionalAuth(req);
    const items = await getPublicFeed({ limit, userId });
    res.json({ items });
  }),
);

// GET /feed/timeline
router.get(
  '/timeline',
  authenticate,
  asyncHandler(async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const events = await getUserTimeline({ userId: req.auth.sub, role: req.auth.role, limit });
    res.json({ events });
  }),
);

// POST /feed/:itemType/:itemId/like — toggle like
router.post(
  '/:itemType/:itemId/like',
  authenticate,
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const existing = await pool.query(
      `SELECT id FROM post_reactions WHERE user_id = $1 AND item_type = $2 AND item_id = $3`,
      [req.auth.sub, itemType, itemId],
    );

    if (existing.rows.length > 0) {
      await pool.query(
        `DELETE FROM post_reactions WHERE user_id = $1 AND item_type = $2 AND item_id = $3`,
        [req.auth.sub, itemType, itemId],
      );
    } else {
      await pool.query(
        `INSERT INTO post_reactions (user_id, item_type, item_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
        [req.auth.sub, itemType, itemId],
      );
    }

    const count = await pool.query(
      `SELECT COUNT(*)::int AS count FROM post_reactions WHERE item_type = $1 AND item_id = $2`,
      [itemType, itemId],
    );

    res.json({ liked: existing.rows.length === 0, likeCount: count.rows[0].count });
  }),
);

// GET /feed/:itemType/:itemId/like-status — check if current user liked this item
router.get(
  '/:itemType/:itemId/like-status',
  authenticate,
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');

    const pool = getPostgresPool();
    if (!pool) return res.json({ isLiked: false });

    const result = await pool.query(
      `SELECT 1 FROM post_reactions WHERE user_id = $1 AND item_type = $2 AND item_id = $3`,
      [req.auth.sub, itemType, itemId],
    );

    res.json({ isLiked: result.rows.length > 0 });
  }),
);

// GET /feed/:itemType/:itemId/likers — users who reacted to this item
router.get(
  '/:itemType/:itemId/likers',
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');
    const pool = getPostgresPool();
    if (!pool) return res.json({ likers: [] });
    const result = await pool.query(
      `SELECT u.id AS "userId", u.full_name AS "fullName", up.profile_pic AS "profilePic"
       FROM post_reactions pr
       JOIN users u ON u.id = pr.user_id
       LEFT JOIN user_profiles up ON up.user_id = pr.user_id
       WHERE pr.item_type = $1 AND pr.item_id = $2
       ORDER BY pr.created_at DESC
       LIMIT 50`,
      [itemType, itemId],
    );
    res.json({ likers: result.rows });
  }),
);

// GET /feed/:itemType/:itemId/sharers — users who shared this item
router.get(
  '/:itemType/:itemId/sharers',
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');
    const pool = getPostgresPool();
    if (!pool) return res.json({ sharers: [] });
    const result = await pool.query(
      `SELECT user_id AS "userId", full_name AS "fullName", profile_pic AS "profilePic"
       FROM social_posts
       WHERE shared_from_type = $1 AND shared_from_id = $2
       ORDER BY created_at DESC
       LIMIT 50`,
      [itemType, itemId],
    );
    res.json({ sharers: result.rows });
  }),
);

// GET /feed/:itemType/:itemId/comments
router.get(
  '/:itemType/:itemId/comments',
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');
    const userId = optionalAuth(req);

    const pool = getPostgresPool();
    if (!pool) return res.json({ comments: [] });

    const result = await pool.query(
      `SELECT c.id, c.user_id AS "userId", c.full_name AS "fullName",
              c.parent_comment_id AS "parentCommentId", c.body, c.gif_url AS "gifUrl",
              c.created_at AS "createdAt", c.updated_at AS "updatedAt",
              COUNT(cr.id)::int AS "reactionCount",
              EXISTS (
                SELECT 1 FROM post_comment_reactions mine
                WHERE mine.comment_id = c.id AND mine.user_id = $3
              ) AS "isReacted"
       FROM post_comments c
       LEFT JOIN post_comment_reactions cr ON cr.comment_id = c.id
       WHERE c.item_type = $1 AND c.item_id = $2
       GROUP BY c.id
       ORDER BY c.created_at ASC
       LIMIT 200`,
      [itemType, itemId, userId],
    );

    res.json({ comments: result.rows });
  }),
);

// POST /feed/:itemType/:itemId/comments
router.post(
  '/:itemType/:itemId/comments',
  authenticate,
  asyncHandler(async (req, res) => {
    const { itemType, itemId } = req.params;
    if (!VALID_TYPES.has(itemType)) throw new HttpError(400, 'Invalid item type.');

    const body = (req.body.body || '').toString().trim();
    const gifUrl = req.body.gifUrl ? req.body.gifUrl.toString() : null;
    if (!body && !gifUrl) throw new HttpError(400, 'Comment body is required.');
    if (body.length > 1000) throw new HttpError(400, 'Comment too long.');
    const parentCommentId = req.body.parentCommentId ? req.body.parentCommentId.toString() : null;

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    if (parentCommentId) {
      const parent = await pool.query(
        `SELECT id FROM post_comments WHERE id = $1 AND item_type = $2 AND item_id = $3`,
        [parentCommentId, itemType, itemId],
      );
      if (!parent.rows.length) throw new HttpError(404, 'Parent comment not found.');
    }

    const userResult = await pool.query(
      `SELECT full_name FROM users WHERE id = $1`,
      [req.auth.sub],
    );
    const fullName = userResult.rows[0]?.full_name || 'User';

    const result = await pool.query(
      `INSERT INTO post_comments (user_id, full_name, item_type, item_id, body, parent_comment_id, gif_url)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, user_id AS "userId", full_name AS "fullName",
                 parent_comment_id AS "parentCommentId", body, gif_url AS "gifUrl", created_at AS "createdAt"`,
      [req.auth.sub, fullName, itemType, itemId, body, parentCommentId, gifUrl],
    );

    // Notify the post author (async, don't await)
    (async () => {
      try {
        if (itemType === 'post') {
          const postAuthor = await pool.query(
            `SELECT user_id FROM social_posts WHERE id = $1`, [itemId],
          );
          if (postAuthor.rows.length && postAuthor.rows[0].user_id !== req.auth.sub) {
            await createNotification(pool, {
              userId: postAuthor.rows[0].user_id,
              actorId: req.auth.sub,
              actorName: fullName,
              type: 'comment',
              title: `${fullName} commented on your post`,
              body: body.slice(0, 100),
              linkType: 'post',
              linkId: itemId,
            });
          }
        }
        await notifyMentions(pool, body, req.auth.sub, fullName, itemType, itemId);
      } catch { /* non-fatal */ }
    })();

    res.json({ comment: result.rows[0] });
  }),
);

// PATCH /feed/comments/:commentId — edit own comment
router.patch(
  '/comments/:commentId',
  authenticate,
  asyncHandler(async (req, res) => {
    const body = (req.body.body || '').toString().trim();
    if (!body) throw new HttpError(400, 'Comment body is required.');
    if (body.length > 1000) throw new HttpError(400, 'Comment too long.');

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const result = await pool.query(
      `UPDATE post_comments
       SET body = $1, updated_at = NOW()
       WHERE id = $2 AND user_id = $3
       RETURNING id, user_id AS "userId", full_name AS "fullName",
                 parent_comment_id AS "parentCommentId", body, gif_url AS "gifUrl",
                 created_at AS "createdAt", updated_at AS "updatedAt"`,
      [body, req.params.commentId, req.auth.sub],
    );
    if (!result.rows.length) throw new HttpError(404, 'Comment not found or not yours.');
    res.json({ comment: { ...result.rows[0], reactionCount: 0, isReacted: false } });
  }),
);

// DELETE /feed/comments/:commentId — delete own comment
router.delete(
  '/comments/:commentId',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const result = await pool.query(
      `SELECT id FROM post_comments WHERE id = $1 AND user_id = $2`,
      [req.params.commentId, req.auth.sub],
    );
    if (!result.rows.length) throw new HttpError(404, 'Comment not found or not yours.');
    await pool.query(
      `WITH RECURSIVE thread AS (
         SELECT id FROM post_comments WHERE id = $1
         UNION ALL
         SELECT c.id FROM post_comments c INNER JOIN thread t ON c.parent_comment_id = t.id
       )
       DELETE FROM post_comments WHERE id IN (SELECT id FROM thread)`,
      [req.params.commentId],
    );
    res.json({ deleted: true });
  }),
);

// POST /feed/comments/:commentId/reaction — toggle comment reaction
router.post(
  '/comments/:commentId/reaction',
  authenticate,
  asyncHandler(async (req, res) => {
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');

    const existing = await pool.query(
      `SELECT id FROM post_comment_reactions WHERE user_id = $1 AND comment_id = $2`,
      [req.auth.sub, req.params.commentId],
    );

    if (existing.rows.length > 0) {
      await pool.query(
        `DELETE FROM post_comment_reactions WHERE user_id = $1 AND comment_id = $2`,
        [req.auth.sub, req.params.commentId],
      );
    } else {
      await pool.query(
        `INSERT INTO post_comment_reactions (user_id, comment_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [req.auth.sub, req.params.commentId],
      );
    }

    const count = await pool.query(
      `SELECT COUNT(*)::int AS count FROM post_comment_reactions WHERE comment_id = $1`,
      [req.params.commentId],
    );
    res.json({ reacted: existing.rows.length === 0, reactionCount: count.rows[0].count });
  }),
);

module.exports = { feedRoutes: router };
