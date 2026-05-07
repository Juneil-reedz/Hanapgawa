const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createReview({ bookingId, reviewerUserId, providerUserId, rating, comment }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO reviews (
        booking_id,
        reviewer_user_id,
        provider_user_id,
        rating,
        comment
      )
      VALUES ($1, $2, $3, $4, $5)
      RETURNING
        id,
        booking_id AS "bookingId",
        reviewer_user_id AS "reviewerUserId",
        provider_user_id AS "providerUserId",
        rating,
        comment,
        created_at AS "createdAt"
    `,
    [bookingId, reviewerUserId, providerUserId, rating, comment],
  );

  return result.rows[0];
}

async function listReviewsForProvider(providerUserId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        id,
        booking_id AS "bookingId",
        reviewer_user_id AS "reviewerUserId",
        provider_user_id AS "providerUserId",
        rating,
        comment,
        created_at AS "createdAt"
      FROM reviews
      WHERE provider_user_id = $1
      ORDER BY created_at DESC
    `,
    [providerUserId],
  );

  const summary = await pool.query(
    `
      SELECT
        COUNT(*)::INT AS count,
        COALESCE(ROUND(AVG(rating)::numeric, 2), 0) AS average
      FROM reviews
      WHERE provider_user_id = $1
    `,
    [providerUserId],
  );

  return {
    reviews: result.rows,
    summary: summary.rows[0],
  };
}

async function listReviewSummariesForProviders(providerUserIds) {
  if (!providerUserIds.length) {
    return [];
  }

  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        provider_user_id AS "providerUserId",
        COUNT(*)::INT AS count,
        COALESCE(ROUND(AVG(rating)::numeric, 2), 0) AS average
      FROM reviews
      WHERE provider_user_id = ANY($1)
      GROUP BY provider_user_id
    `,
    [providerUserIds],
  );

  return result.rows;
}

module.exports = {
  createReview,
  listReviewsForProvider,
  listReviewSummariesForProviders,
};
