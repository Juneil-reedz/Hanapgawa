const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { submitReview, getProviderReviews, getReviewsForUser } = require('../services/review-service');

const router = express.Router();

const createReviewSchema = z.object({
  bookingId: z.uuid(),
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).optional().default(''),
});

router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const payload = createReviewSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid review payload.', payload.error.flatten());
    }

    const review = await submitReview({
      bookingId: payload.data.bookingId,
      reviewerUserId: req.auth.sub,
      rating: payload.data.rating,
      comment: payload.data.comment,
    });

    res.status(201).json({ review });
  }),
);

router.get(
  '/provider/:providerUserId',
  asyncHandler(async (req, res) => {
    const providerId = z.uuid().safeParse(req.params.providerUserId);

    if (!providerId.success) {
      throw new HttpError(400, 'Invalid provider user id.');
    }

    const data = await getProviderReviews(providerId.data);
    res.json(data);
  }),
);

// GET /reviews/user/:userId — reviews received by any user (provider or client)
router.get(
  '/user/:userId',
  asyncHandler(async (req, res) => {
    const userId = z.uuid().safeParse(req.params.userId);
    if (!userId.success) throw new HttpError(400, 'Invalid user id.');
    const data = await getReviewsForUser(userId.data);
    res.json(data);
  }),
);

module.exports = { reviewRoutes: router };
