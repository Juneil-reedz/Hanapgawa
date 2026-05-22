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

async function createReview({ bookingId, reviewerUserId, reviewedUserId, rating, comment }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `INSERT INTO reviews (
       booking_id, reviewer_user_id, provider_user_id, rating, comment
     )
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (booking_id, reviewer_user_id)
     DO UPDATE SET
       provider_user_id = EXCLUDED.provider_user_id,
       rating = EXCLUDED.rating,
       comment = EXCLUDED.comment,
       updated_at = NOW()
      RETURNING
        id,
       booking_id       AS "bookingId",
       reviewer_user_id AS "reviewerUserId",
       provider_user_id AS "reviewedUserId",
       rating,
       comment,
       created_at       AS "createdAt"`,
    [bookingId, reviewerUserId, reviewedUserId, rating, comment],
  );
  return result.rows[0];
}

async function listReviewsForUser(userId) {
  const pool = requirePostgresRead();

  const result = await pool.query(
    `SELECT
       r.id,
       r.booking_id       AS "bookingId",
       r.reviewer_user_id AS "reviewerUserId",
       r.provider_user_id AS "reviewedUserId",
       r.rating,
       r.comment,
       r.created_at       AS "createdAt",
       ru.full_name       AS "reviewerName",
       pu.full_name       AS "reviewedName"
     FROM reviews r
     LEFT JOIN users ru ON ru.id = r.reviewer_user_id::uuid
     LEFT JOIN users pu ON pu.id = r.provider_user_id::uuid
     WHERE r.provider_user_id = $1
     ORDER BY r.created_at DESC`,
    [userId],
  );

  const summary = await pool.query(
    `SELECT
       COUNT(*)::INT                             AS count,
       COALESCE(ROUND(AVG(rating)::numeric, 2), 0) AS average
     FROM reviews
     WHERE provider_user_id = $1`,
    [userId],
  );

  return {
    reviews: result.rows,
    summary: summary.rows[0],
  };
}

// Legacy alias used by feed-service / listing queries
async function listReviewSummariesForProviders(providerUserIds) {
  if (!providerUserIds.length) return [];
  const pool = requirePostgresRead();
  const result = await pool.query(
    `SELECT
       provider_user_id AS "providerUserId",
       COUNT(*)::INT                             AS count,
       COALESCE(ROUND(AVG(rating)::numeric, 2), 0) AS average
     FROM reviews
     WHERE provider_user_id = ANY($1)
     GROUP BY provider_user_id`,
    [providerUserIds],
  );
  return result.rows;
}

module.exports = {
  createReview,
  listReviewsForUser,
  listReviewsForProvider: listReviewsForUser, // backward-compat alias
  listReviewSummariesForProviders,
};
