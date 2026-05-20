const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createReport({ reporterUserId, providerUserId, bookingId, contentType, contentId, reason, details }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO reports (reporter_user_id, provider_user_id, booking_id, content_type, content_id, reason, details)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING
        id,
        reporter_user_id AS "reporterUserId",
        provider_user_id AS "providerUserId",
        booking_id AS "bookingId",
        content_type AS "contentType",
        content_id AS "contentId",
        reason,
        details,
        status,
        created_at AS "createdAt"
    `,
    [reporterUserId, providerUserId || null, bookingId || null, contentType || null, contentId || null, reason, details],
  );

  return result.rows[0];
}

async function listReports(status) {
  const pool = requirePostgres();
  const values = [];
  const where = status ? 'WHERE status = $1' : '';
  if (status) values.push(status);

  const result = await pool.query(
    `
      SELECT
        r.id,
        r.reporter_user_id AS "reporterUserId",
        u.full_name AS "reporterName",
        r.provider_user_id AS "providerUserId",
        r.booking_id AS "bookingId",
        r.content_type AS "contentType",
        r.content_id AS "contentId",
        CASE WHEN r.content_type = 'social_post' THEN (
          SELECT json_build_object(
            'id', sp.id,
            'userId', sp.user_id,
            'fullName', sp.full_name,
            'body', sp.body,
            'image', sp.image,
            'privacy', sp.privacy,
            'createdAt', sp.created_at
          )
          FROM social_posts sp
          WHERE sp.id::text = r.content_id
        ) ELSE NULL END AS "reportedContent",
        r.reason,
        r.details,
        r.status,
        r.created_at AS "createdAt",
        r.updated_at AS "updatedAt"
      FROM reports r
      LEFT JOIN users u ON u.id = r.reporter_user_id
      ${where}
      ORDER BY r.created_at DESC
    `,
    values,
  );

  return result.rows;
}

async function updateReportStatus(id, status) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      UPDATE reports
      SET status = $2, updated_at = NOW()
      WHERE id = $1
      RETURNING
        id,
        reporter_user_id AS "reporterUserId",
        provider_user_id AS "providerUserId",
        booking_id AS "bookingId",
        content_type AS "contentType",
        content_id AS "contentId",
        reason,
        details,
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [id, status],
  );

  return result.rows[0] || null;
}

module.exports = {
  createReport,
  listReports,
  updateReportStatus,
};
