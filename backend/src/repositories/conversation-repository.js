const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createConversation({ clientUserId, providerUserId, serviceListingId, bookingId, initialMessage }) {
  const pool = requirePostgres();
  const conversation = await pool.query(
    `
      INSERT INTO conversations (
        client_user_id,
        provider_user_id,
        service_listing_id,
        booking_id,
        last_message_preview
      )
      VALUES ($1, $2, $3, $4, $5)
      RETURNING
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        booking_id AS "bookingId",
        last_message_preview AS "lastMessagePreview",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [clientUserId, providerUserId, serviceListingId || null, bookingId || null, initialMessage.slice(0, 140)],
  );

  const message = await pool.query(
    `
      INSERT INTO conversation_messages (conversation_id, sender_user_id, message)
      VALUES ($1, $2, $3)
      RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, created_at AS "createdAt"
    `,
    [conversation.rows[0].id, clientUserId, initialMessage],
  );

  return {
    conversation: conversation.rows[0],
    message: message.rows[0],
  };
}

async function listConversationsForUser(userId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        c.id,
        c.client_user_id AS "clientUserId",
        client_u.full_name AS "clientName",
        c.provider_user_id AS "providerUserId",
        provider_u.full_name AS "providerName",
        c.service_listing_id AS "serviceListingId",
        c.booking_id AS "bookingId",
        c.last_message_preview AS "lastMessagePreview",
        c.created_at AS "createdAt",
        c.updated_at AS "updatedAt"
      FROM conversations c
      LEFT JOIN users client_u ON client_u.id = c.client_user_id
      LEFT JOIN users provider_u ON provider_u.id = c.provider_user_id
      WHERE c.client_user_id = $1 OR c.provider_user_id = $1
      ORDER BY c.updated_at DESC
    `,
    [userId],
  );

  return result.rows;
}

async function findConversationById(id) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        booking_id AS "bookingId",
        last_message_preview AS "lastMessagePreview",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM conversations
      WHERE id = $1
    `,
    [id],
  );

  return result.rows[0] || null;
}

async function listMessages(conversationId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, created_at AS "createdAt"
      FROM conversation_messages
      WHERE conversation_id = $1
      ORDER BY created_at ASC
    `,
    [conversationId],
  );

  return result.rows;
}

async function addMessage({ conversationId, senderUserId, message }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO conversation_messages (conversation_id, sender_user_id, message)
      VALUES ($1, $2, $3)
      RETURNING id, conversation_id AS "conversationId", sender_user_id AS "senderUserId", message, created_at AS "createdAt"
    `,
    [conversationId, senderUserId, message],
  );

  await pool.query(
    `
      UPDATE conversations
      SET last_message_preview = $2, updated_at = NOW()
      WHERE id = $1
    `,
    [conversationId, message.slice(0, 140)],
  );

  return result.rows[0];
}

module.exports = {
  addMessage,
  createConversation,
  findConversationById,
  listConversationsForUser,
  listMessages,
};
