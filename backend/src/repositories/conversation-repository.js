const { getPostgresPool, getPostgresReadPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  return pool;
}

function requirePostgresRead() {
  const pool = getPostgresReadPool();
  if (!pool) throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  return pool;
}

async function createConversation({ clientUserId, providerUserId, serviceListingId, bookingId, initialMessage }) {
  const pool = requirePostgres();
  const conversation = await pool.query(
    `INSERT INTO conversations (client_user_id, provider_user_id, service_listing_id, booking_id, last_message_preview)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, client_user_id AS "clientUserId", provider_user_id AS "providerUserId",
       service_listing_id AS "serviceListingId", booking_id AS "bookingId",
       last_message_preview AS "lastMessagePreview", created_at AS "createdAt", updated_at AS "updatedAt"`,
    [clientUserId, providerUserId, serviceListingId || null, bookingId || null, initialMessage.slice(0, 140)],
  );
  const message = await pool.query(
    `INSERT INTO conversation_messages (conversation_id, sender_user_id, message)
     VALUES ($1, $2, $3)
     RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, image,
       voice_message AS "voiceMessage", voice_duration AS "voiceDuration", created_at AS "createdAt"`,
    [conversation.rows[0].id, clientUserId, initialMessage],
  );
  return { conversation: conversation.rows[0], message: message.rows[0] };
}

async function listConversationsForUser(userId, search = '') {
  const pool = requirePostgresRead();
  const q = search.trim();
  const result = await pool.query(
    `SELECT c.id,
       c.client_user_id AS "clientUserId", client_u.full_name AS "clientName",
       c.provider_user_id AS "providerUserId", provider_u.full_name AS "providerName",
       c.service_listing_id AS "serviceListingId", c.booking_id AS "bookingId",
       c.last_message_preview AS "lastMessagePreview",
       c.last_sender_id AS "lastSenderId",
       c.created_at AS "createdAt", c.updated_at AS "updatedAt",
       cn_other.nickname AS "otherNickname"
     FROM conversations c
     LEFT JOIN users client_u ON client_u.id = c.client_user_id
     LEFT JOIN users provider_u ON provider_u.id = c.provider_user_id
     LEFT JOIN conversation_nicknames cn_other ON
       cn_other.conversation_id = c.id AND
       cn_other.target_user_id = CASE WHEN c.client_user_id = $1 THEN c.provider_user_id ELSE c.client_user_id END
     WHERE (c.client_user_id = $1 OR c.provider_user_id = $1)
       AND ($2 = '' OR client_u.full_name ILIKE $3 OR provider_u.full_name ILIKE $3 OR c.last_message_preview ILIKE $3)
     ORDER BY c.updated_at DESC`,
    [userId, q, `%${q}%`],
  );
  return result.rows;
}

async function getConversationNicknames(conversationId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `SELECT cn.id, cn.conversation_id AS "conversationId", cn.target_user_id AS "targetUserId",
       cn.nickname, cn.set_by_user_id AS "setByUserId", u.full_name AS "targetName",
       cn.created_at AS "createdAt", cn.updated_at AS "updatedAt"
     FROM conversation_nicknames cn
     LEFT JOIN users u ON u.id = cn.target_user_id
     WHERE cn.conversation_id = $1`,
    [conversationId],
  );
  return result.rows;
}

async function upsertConversationNickname(conversationId, targetUserId, nickname, setByUserId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `INSERT INTO conversation_nicknames (conversation_id, target_user_id, nickname, set_by_user_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (conversation_id, target_user_id)
     DO UPDATE SET nickname = $3, set_by_user_id = $4, updated_at = NOW()
     RETURNING id, conversation_id AS "conversationId", target_user_id AS "targetUserId",
       nickname, set_by_user_id AS "setByUserId", created_at AS "createdAt", updated_at AS "updatedAt"`,
    [conversationId, targetUserId, nickname.trim(), setByUserId],
  );
  return result.rows[0];
}

async function deleteConversationNickname(conversationId, targetUserId) {
  const pool = requirePostgres();
  await pool.query(
    `DELETE FROM conversation_nicknames WHERE conversation_id = $1 AND target_user_id = $2`,
    [conversationId, targetUserId],
  );
}

async function findConversationBetweenUsers(userAId, userBId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `SELECT id, client_user_id AS "clientUserId", provider_user_id AS "providerUserId",
       service_listing_id AS "serviceListingId", booking_id AS "bookingId",
       last_message_preview AS "lastMessagePreview", created_at AS "createdAt", updated_at AS "updatedAt"
     FROM conversations
     WHERE (client_user_id = $1 AND provider_user_id = $2)
        OR (client_user_id = $2 AND provider_user_id = $1)
     ORDER BY updated_at DESC
     LIMIT 1`,
    [userAId, userBId],
  );
  return result.rows[0] || null;
}

async function findConversationById(id) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `SELECT id, client_user_id AS "clientUserId", provider_user_id AS "providerUserId",
       service_listing_id AS "serviceListingId", booking_id AS "bookingId",
       last_message_preview AS "lastMessagePreview", created_at AS "createdAt", updated_at AS "updatedAt"
     FROM conversations WHERE id = $1`,
    [id],
  );
  return result.rows[0] || null;
}

async function listMessages(conversationId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `SELECT id, conversation_id AS "conversationId", sender_user_id AS "senderUserId",
       message, image, voice_message AS "voiceMessage", voice_duration AS "voiceDuration",
       reply_to_message_id AS "replyToMessageId",
       forwarded_from_message_id AS "forwardedFromMessageId",
       is_system AS "isSystem", created_at AS "createdAt"
     FROM conversation_messages WHERE conversation_id = $1 ORDER BY created_at ASC`,
    [conversationId],
  );
  return result.rows;
}

async function addSystemMessage({ conversationId, message }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `INSERT INTO conversation_messages (conversation_id, sender_user_id, message, is_system)
     VALUES ($1, (SELECT client_user_id FROM conversations WHERE id = $1), $2, TRUE)
     RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId",
       message, image, voice_message AS "voiceMessage", voice_duration AS "voiceDuration",
       is_system AS "isSystem", created_at AS "createdAt"`,
    [conversationId, message],
  );
  return result.rows[0];
}

async function addMessage({ conversationId, senderUserId, message, image = null, voiceMessage = null, voiceDuration = 0, replyToMessageId = null, forwardedFromMessageId = null }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `INSERT INTO conversation_messages (conversation_id, sender_user_id, message, image, voice_message, voice_duration, reply_to_message_id, forwarded_from_message_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, image,
       voice_message AS "voiceMessage", voice_duration AS "voiceDuration",
       reply_to_message_id AS "replyToMessageId", forwarded_from_message_id AS "forwardedFromMessageId",
       is_system AS "isSystem", created_at AS "createdAt"`,
    [conversationId, senderUserId, message, image, voiceMessage, voiceDuration, replyToMessageId, forwardedFromMessageId],
  );
  const preview = voiceMessage ? 'Voice message' : image ? 'Photo' : message.slice(0, 140);
  await pool.query(
    `UPDATE conversations SET last_message_preview = $2, last_sender_id = $3, updated_at = NOW() WHERE id = $1`,
    [conversationId, preview, senderUserId]);
  return result.rows[0];
}

async function deleteMessage({ messageId, senderUserId }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `DELETE FROM conversation_messages WHERE id = $1 AND sender_user_id = $2 RETURNING id`,
    [messageId, senderUserId],
  );
  if (!result.rows.length) throw new HttpError(404, 'Message not found or not yours.');
}

async function editMessage({ messageId, senderUserId, message }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `UPDATE conversation_messages SET message = $1 WHERE id = $2 AND sender_user_id = $3
     RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, image,
       voice_message AS "voiceMessage", voice_duration AS "voiceDuration",
       reply_to_message_id AS "replyToMessageId", forwarded_from_message_id AS "forwardedFromMessageId", created_at AS "createdAt"`,
    [message, messageId, senderUserId],
  );
  if (!result.rows.length) throw new HttpError(404, 'Message not found or not yours.');
  return result.rows[0];
}

async function deleteConversation({ conversationId, userId }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `DELETE FROM conversations WHERE id = $1 AND (client_user_id = $2 OR provider_user_id = $2) RETURNING id`,
    [conversationId, userId],
  );
  if (!result.rows.length) throw new HttpError(404, 'Conversation not found or not yours.');
}

module.exports = {
  addMessage, addSystemMessage, createConversation, deleteConversation, deleteConversationNickname,
  deleteMessage, editMessage, findConversationBetweenUsers, findConversationById,
  getConversationNicknames, listConversationsForUser, listMessages, upsertConversationNickname,
};
