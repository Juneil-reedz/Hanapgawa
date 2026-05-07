const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createOrRefreshApplication({ agencyUserId, workerUserId, message }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO agency_worker_applications (
        agency_user_id,
        worker_user_id,
        status,
        message
      )
      VALUES ($1, $2, 'pending', $3)
      ON CONFLICT (agency_user_id, worker_user_id)
      DO UPDATE SET
        status = 'pending',
        message = EXCLUDED.message,
        updated_at = NOW()
      RETURNING
        id,
        agency_user_id AS "agencyUserId",
        worker_user_id AS "workerUserId",
        status,
        message,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [agencyUserId, workerUserId, message],
  );

  return result.rows[0];
}

async function findApplicationById(id) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        id,
        agency_user_id AS "agencyUserId",
        worker_user_id AS "workerUserId",
        status,
        message,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM agency_worker_applications
      WHERE id = $1
    `,
    [id],
  );

  return result.rows[0] || null;
}

async function updateApplicationStatus({ id, status }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      UPDATE agency_worker_applications
      SET status = $2, updated_at = NOW()
      WHERE id = $1
      RETURNING
        id,
        agency_user_id AS "agencyUserId",
        worker_user_id AS "workerUserId",
        status,
        message,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [id, status],
  );

  return result.rows[0] || null;
}

async function listAgencyApplicationsForUser({ agencyUserId, workerUserId, status }) {
  const pool = requirePostgres();
  const conditions = [];
  const values = [];

  if (agencyUserId) {
    values.push(agencyUserId);
    conditions.push(`agency_user_id = $${values.length}`);
  }

  if (workerUserId) {
    values.push(workerUserId);
    conditions.push(`worker_user_id = $${values.length}`);
  }

  if (status) {
    values.push(status);
    conditions.push(`status = $${values.length}`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const result = await pool.query(
    `
      SELECT
        id,
        agency_user_id AS "agencyUserId",
        worker_user_id AS "workerUserId",
        status,
        message,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM agency_worker_applications
      ${whereClause}
      ORDER BY created_at DESC
    `,
    values,
  );

  return result.rows;
}

module.exports = {
  createOrRefreshApplication,
  findApplicationById,
  listAgencyApplicationsForUser,
  updateApplicationStatus,
};
