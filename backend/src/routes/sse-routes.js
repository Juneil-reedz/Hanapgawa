const express = require('express');
const { authenticate } = require('../middleware/authenticate');
const { getPostgresPool } = require('../db/postgres');
const { addClient, removeClient } = require('../lib/sse-broadcaster');

const router = express.Router();

// GET /events — persistent SSE connection per authenticated user.
// Sends initial badge/notification state then pushes updates as they happen.
// Heartbeat every 25s keeps the connection alive through Render's proxy timeout.
router.get('/', authenticate, async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // disable nginx buffering on Render
  res.flushHeaders();

  const userId = req.auth.sub;
  addClient(userId, res);

  // Send current state immediately so client doesn't wait for first event
  try {
    const pool = getPostgresPool();
    if (pool) {
      const [notifResult, bookingResult, convResult] = await Promise.allSettled([
        pool.query(
          `SELECT COUNT(*)::int AS count FROM notifications WHERE user_id = $1 AND read_at IS NULL`,
          [userId],
        ),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM bookings
           WHERE (client_id = $1 OR provider_id = $1) AND status = 'pending'`,
          [userId],
        ),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM conversation_participants cp
           JOIN conversations c ON c.id = cp.conversation_id
           WHERE cp.user_id = $1 AND cp.unread_count > 0`,
          [userId],
        ),
      ]);

      const badges = {
        notifications: notifResult.status === 'fulfilled' ? notifResult.value.rows[0].count : 0,
        bookings: bookingResult.status === 'fulfilled' ? bookingResult.value.rows[0].count : 0,
        messages: convResult.status === 'fulfilled' ? convResult.value.rows[0].count : 0,
      };

      res.write(`event: badges\ndata: ${JSON.stringify(badges)}\n\n`);
    }
  } catch (_) {
    // Non-fatal — client will still receive future pushed events
  }

  // Heartbeat to keep connection alive through proxy/nginx timeouts
  const heartbeat = setInterval(() => {
    try {
      res.write(':heartbeat\n\n');
    } catch (_) {
      clearInterval(heartbeat);
    }
  }, 25000);

  req.on('close', () => {
    clearInterval(heartbeat);
    removeClient(userId, res);
  });
});

module.exports = { sseRoutes: router };
