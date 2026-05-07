const { HttpError } = require('../lib/http-error');
const { findBookingById } = require('../repositories/booking-repository');
const { createReview, listReviewsForProvider } = require('../repositories/review-repository');
const { findUserById } = require('../repositories/user-repository');

async function submitReview({ bookingId, reviewerUserId, rating, comment, isAdmin }) {
  const booking = await findBookingById(bookingId);

  if (!booking) {
    throw new HttpError(404, 'Booking not found.');
  }

  if (!isAdmin && booking.clientUserId !== reviewerUserId) {
    throw new HttpError(403, 'You can only review your own bookings.');
  }

  if (booking.status !== 'completed') {
    throw new HttpError(409, 'Only completed bookings can be reviewed.');
  }

  const provider = await findUserById(booking.providerUserId);

  if (!provider || !['worker', 'agency'].includes(provider.role)) {
    throw new HttpError(409, 'The booking provider is not reviewable.');
  }

  return createReview({
    bookingId: booking.id,
    reviewerUserId,
    providerUserId: booking.providerUserId,
    rating,
    comment,
  });
}

async function getProviderReviews(providerUserId) {
  return listReviewsForProvider(providerUserId);
}

module.exports = { submitReview, getProviderReviews };
