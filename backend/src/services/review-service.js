const { HttpError } = require('../lib/http-error');
const { findBookingById } = require('../repositories/booking-repository');
const { createReview, listReviewsForUser } = require('../repositories/review-repository');
const { findUserById } = require('../repositories/user-repository');

async function submitReview({ bookingId, reviewerUserId, rating, comment }) {
  const booking = await findBookingById(bookingId);

  if (!booking) {
    throw new HttpError(404, 'Booking not found.');
  }

  const isClient = booking.clientUserId === reviewerUserId;
  const isWorker = booking.workerUserId === reviewerUserId;

  if (!isClient && !isWorker) {
    throw new HttpError(403, 'You must be a participant in this booking to leave a review.');
  }

  if (booking.status !== 'completed') {
    throw new HttpError(409, 'Only completed bookings can be reviewed.');
  }

  // The reviewed person is the other party in the booking
  const reviewedUserId = isClient ? booking.workerUserId : booking.clientUserId;
  const [reviewer, reviewedUser] = await Promise.all([
    findUserById(reviewerUserId),
    findUserById(reviewedUserId),
  ]);

  if (reviewer?.role === 'admin') {
    throw new HttpError(403, 'Admins cannot leave marketplace reviews.');
  }

  if (reviewedUser?.role === 'admin') {
    throw new HttpError(403, 'Admin accounts cannot receive marketplace reviews.');
  }

  return createReview({
    bookingId: booking.id,
    reviewerUserId,
    reviewedUserId,
    rating,
    comment,
  });
}

async function getProviderReviews(providerUserId) {
  return listReviewsForUser(providerUserId);
}

async function getReviewsForUser(userId) {
  return listReviewsForUser(userId);
}

module.exports = { submitReview, getProviderReviews, getReviewsForUser };
