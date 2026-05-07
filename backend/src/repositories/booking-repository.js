const { getPostgresPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();

  if (!pool) {
    throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  }

  return pool;
}

async function createBooking({ clientUserId, providerUserId, serviceListingId, serviceCategory, municipality, locationDetails, notes, scheduledAt }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO bookings (
        client_user_id,
        provider_user_id,
        service_listing_id,
        service_category,
        municipality,
        location_details,
        notes,
        scheduled_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        service_category AS "serviceCategory",
        municipality,
        location_details AS "locationDetails",
        notes,
        status,
        previous_status AS "previousStatus",
        scheduled_at AS "scheduledAt",
        provider_completed_at AS "providerCompletedAt",
        client_confirmed_at AS "clientConfirmedAt",
        cancellation_requested_at AS "cancellationRequestedAt",
        cancellation_requested_by AS "cancellationRequestedBy",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [clientUserId, providerUserId, serviceListingId || null, serviceCategory, municipality, locationDetails || '', notes, scheduledAt],
  );

  return result.rows[0];
}

async function listBookingsForUser(userId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        service_category AS "serviceCategory",
        municipality,
        location_details AS "locationDetails",
        notes,
        status,
        previous_status AS "previousStatus",
        scheduled_at AS "scheduledAt",
        provider_completed_at AS "providerCompletedAt",
        client_confirmed_at AS "clientConfirmedAt",
        cancellation_requested_at AS "cancellationRequestedAt",
        cancellation_requested_by AS "cancellationRequestedBy",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM bookings
      WHERE client_user_id = $1 OR provider_user_id = $1
      ORDER BY created_at DESC
    `,
    [userId],
  );

  return result.rows;
}

async function findBookingById(bookingId) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      SELECT
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        service_category AS "serviceCategory",
        municipality,
        location_details AS "locationDetails",
        notes,
        status,
        previous_status AS "previousStatus",
        scheduled_at AS "scheduledAt",
        provider_completed_at AS "providerCompletedAt",
        client_confirmed_at AS "clientConfirmedAt",
        cancellation_requested_at AS "cancellationRequestedAt",
        cancellation_requested_by AS "cancellationRequestedBy",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM bookings
      WHERE id = $1
    `,
    [bookingId],
  );

  return result.rows[0] || null;
}

async function updateBookingStatus({ bookingId, status, actorUserId }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      UPDATE bookings
      SET
        previous_status = CASE WHEN $2 = 'cancellation_requested' THEN status ELSE previous_status END,
        status = $2,
        provider_completed_at = CASE WHEN $2 = 'completion_requested' THEN NOW() ELSE provider_completed_at END,
        client_confirmed_at = CASE WHEN $2 = 'completed' THEN NOW() ELSE client_confirmed_at END,
        cancellation_requested_at = CASE WHEN $2 = 'cancellation_requested' THEN NOW() ELSE cancellation_requested_at END,
        cancellation_requested_by = CASE WHEN $2 = 'cancellation_requested' THEN $3 ELSE cancellation_requested_by END,
        updated_at = NOW()
      WHERE id = $1
      RETURNING
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        service_category AS "serviceCategory",
        municipality,
        location_details AS "locationDetails",
        notes,
        status,
        previous_status AS "previousStatus",
        scheduled_at AS "scheduledAt",
        provider_completed_at AS "providerCompletedAt",
        client_confirmed_at AS "clientConfirmedAt",
        cancellation_requested_at AS "cancellationRequestedAt",
        cancellation_requested_by AS "cancellationRequestedBy",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [bookingId, status, actorUserId || null],
  );

  return result.rows[0] || null;
}

async function listAllBookings(status) {
  const pool = requirePostgres();
  const values = [];
  const where = status ? 'WHERE status = $1' : '';

  if (status) {
    values.push(status);
  }

  const result = await pool.query(
    `
      SELECT
        id,
        client_user_id AS "clientUserId",
        provider_user_id AS "providerUserId",
        service_listing_id AS "serviceListingId",
        service_category AS "serviceCategory",
        municipality,
        location_details AS "locationDetails",
        notes,
        status,
        previous_status AS "previousStatus",
        scheduled_at AS "scheduledAt",
        provider_completed_at AS "providerCompletedAt",
        client_confirmed_at AS "clientConfirmedAt",
        cancellation_requested_at AS "cancellationRequestedAt",
        cancellation_requested_by AS "cancellationRequestedBy",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM bookings
      ${where}
      ORDER BY created_at DESC
    `,
    values,
  );

  return result.rows;
}

module.exports = {
  createBooking,
  findBookingById,
  listAllBookings,
  listBookingsForUser,
  updateBookingStatus,
};
