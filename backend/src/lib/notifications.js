const { sendPushNotification } = require('./firebase');

async function _getDeviceTokens(pool, userId) {
  try {
    const r = await pool.query(
      `SELECT token FROM user_device_tokens WHERE user_id = $1`,
      [userId],
    );
    return r.rows.map((row) => row.token);
  } catch {
    return [];
  }
}

async function createNotification(pool, { userId, actorId, actorName, type, title, body = '', linkType, linkId }) {
  if (!pool || !userId) return;
  try {
    await pool.query(
      `INSERT INTO notifications (user_id, actor_id, actor_name, type, title, body, link_type, link_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [userId, actorId || null, actorName || '', type, title, body.slice(0, 200), linkType || null, linkId || null],
    );
    // Send FCM push notification (fire-and-forget)
    _getDeviceTokens(pool, userId).then((tokens) => {
      for (const token of tokens) {
        sendPushNotification({
          token,
          title,
          body: body.slice(0, 120) || title,
          data: {
            type,
            ...(linkType ? { linkType } : {}),
            ...(linkId ? { linkId } : {}),
          },
        });
      }
    });
  } catch (e) {
    console.warn('Failed to create notification:', e.message);
  }
}

function extractMentions(text) {
  const results = [];
  const regex = /@([\w][\w ]{1,60}?)(?=[\s,;.!?@]|$)/g;
  let match;
  while ((match = regex.exec(text)) !== null) {
    const name = match[1].trim();
    if (name.length >= 2) results.push(name);
  }
  return results;
}

async function notifyMentions(pool, text, actorId, actorName, linkType, linkId) {
  const mentions = extractMentions(text);
  for (const name of mentions) {
    try {
      const r = await pool.query(
        `SELECT id FROM users WHERE full_name ILIKE $1 AND id != $2 LIMIT 1`,
        [name, actorId],
      );
      if (r.rows.length) {
        await createNotification(pool, {
          userId: r.rows[0].id, actorId, actorName,
          type: 'mention',
          title: `${actorName} mentioned you`,
          body: text.slice(0, 120),
          linkType, linkId,
        });
      }
    } catch { /* ignore */ }
  }
}

module.exports = { createNotification, notifyMentions };
