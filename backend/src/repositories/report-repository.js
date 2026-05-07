const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createReport({ reporterUserId, providerUserId, bookingId, reason, details }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO reports (reporter_user_id, provider_user_id, booking_id, reason, details)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING
        id,
        reporter_user_id AS "reporterUserId",
        provider_user_id AS "providerUserId",
        booking_id AS "bookingId",
        reason,
        details,
        status,
        created_at AS "createdAt"
    `,
    [reporterUserId, providerUserId || null, bookingId || null, reason, details],
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
        id,
        reporter_user_id AS "reporterUserId",
        provider_user_id AS "providerUserId",
        booking_id AS "bookingId",
        reason,
        details,
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM reports
      ${where}
      ORDER BY created_at DESC
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
