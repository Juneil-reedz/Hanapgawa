const { HttpError } = require('../lib/http-error');
const { assertApprovedProvider } = require('../lib/provider-approval');
const { createBooking, findBookingById, listAllBookings, listBookingsForUser, updateBookingStatus } = require('../repositories/booking-repository');
const { findUserById } = require('../repositories/user-repository');

async function requestBooking({ clientUserId, providerUserId, serviceListingId, serviceCategory, municipality, locationDetails, notes, scheduledAt, isAdmin }) {
  if (!isAdmin) {
    const provider = await findUserById(providerUserId);

    if (!provider) {
      throw new HttpError(404, 'Provider account not found.');
    }

    assertApprovedProvider(provider, 'Bookings can only be created for approved providers.');
  }

  return createBooking({ clientUserId, providerUserId, serviceListingId, serviceCategory, municipality, locationDetails, notes, scheduledAt });
}

async function getBookingsForUser(userId, status) {
  const bookings = await listBookingsForUser(userId);
  return status ? bookings.filter((booking) => booking.status === status) : bookings;
}

async function getBookingForUser({ bookingId, auth }) {
  const booking = await findBookingById(bookingId);

  if (!booking) {
    throw new HttpError(404, 'Booking not found.');
  }

  const isParticipant = booking.clientUserId === auth.sub || booking.providerUserId === auth.sub;
  if (!isParticipant && auth.role !== 'admin') {
    throw new HttpError(403, 'You can only view bookings you are part of.');
  }

  return booking;
}

async function changeBookingStatus({ bookingId, status, auth }) {
  const booking = await findBookingById(bookingId);

  if (!booking) {
    throw new HttpError(404, 'Booking not found.');
  }

  const isAdmin = auth.role === 'admin';
  const isProviderOwner = booking.providerUserId === auth.sub;
  const isClientOwner = booking.clientUserId === auth.sub;

  const providerStatuses = ['accepted', 'rejected', 'in_progress', 'completion_requested'];
  const clientStatuses = ['completed', 'cancellation_requested'];

  if (!isAdmin && providerStatuses.includes(status)) {
    const provider = await findUserById(booking.providerUserId);
    assertApprovedProvider(provider, 'Only approved providers can manage booking status.');
  }

  if (providerStatuses.includes(status) && !isAdmin && !isProviderOwner) {
    throw new HttpError(403, 'Only the assigned provider or admin can update this booking stage.');
  }

  if (clientStatuses.includes(status) && !isAdmin && !isClientOwner) {
    throw new HttpError(403, 'Only the client or admin can confirm this booking stage.');
  }

  if (status === 'cancelled') {
    if (!isAdmin && !(isClientOwner || isProviderOwner)) {
      throw new HttpError(403, 'Only booking participants or admin can finalize cancellation.');
    }

    if (booking.status !== 'cancellation_requested' && !isAdmin) {
      throw new HttpError(409, 'Cancellation must be requested before it can be finalized.');
    }
  }

  if (status === 'completed' && booking.status !== 'completion_requested' && !isAdmin) {
    throw new HttpError(409, 'Provider must request completion before client confirmation.');
  }

  return updateBookingStatus({ bookingId: booking.id, status, actorUserId: auth.sub });
}

async function getAllBookings(status) {
  return listAllBookings(status);
}

module.exports = { requestBooking, getBookingsForUser, getBookingForUser, changeBookingStatus, getAllBookings };
