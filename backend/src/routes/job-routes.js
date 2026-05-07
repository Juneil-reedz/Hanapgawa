const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { chooseOffer, getJobDetail, getJobs, getMyOffers, postJob, sendOffer } = require('../services/job-service');

const router = express.Router();

const jobPostSchema = z.object({
  postType: z.enum(['seeking_worker', 'seeking_client']).default('seeking_worker'),
  title: z.string().min(3).max(120),
  category: z.string().min(2).max(80),
  municipality: z.string().min(2).max(80),
  locationDetails: z.string().max(240).optional().default(''),
  description: z.string().min(10).max(1500),
  budgetMin: z.number().nonnegative().optional(),
  budgetMax: z.number().nonnegative().optional(),
  scheduledAt: z.iso.datetime().optional(),
});

const offerSchema = z.object({
  message: z.string().min(3).max(1000),
  proposedPrice: z.number().nonnegative().optional(),
  media: z
    .array(
      z.object({
        imageUrl: z.string().min(1).max(2000000),
        caption: z.string().max(160).optional().default(''),
      }),
    )
    .max(3)
    .default([]),
});

router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const payload = jobPostSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid job post payload.', payload.error.flatten());
    }

    const jobPost = await postJob({ auth: req.auth, ...payload.data });
    res.status(201).json({ jobPost });
  }),
);

router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const jobs = await getJobs({ auth: req.auth, status: req.query.status ? String(req.query.status) : undefined });
    res.json({ jobs });
  }),
);

router.get(
  '/offers/mine',
  authenticate,
  asyncHandler(async (req, res) => {
    const offers = await getMyOffers(req.auth);
    res.json({ offers });
  }),
);

router.get(
  '/:jobPostId',
  authenticate,
  asyncHandler(async (req, res) => {
    const jobPostId = z.uuid().safeParse(req.params.jobPostId);

    if (!jobPostId.success) {
      throw new HttpError(400, 'Invalid job post id.');
    }

    const data = await getJobDetail({ jobPostId: jobPostId.data, auth: req.auth });
    res.json(data);
  }),
);

router.post(
  '/:jobPostId/offers',
  authenticate,
  asyncHandler(async (req, res) => {
    const jobPostId = z.uuid().safeParse(req.params.jobPostId);

    if (!jobPostId.success) {
      throw new HttpError(400, 'Invalid job post id.');
    }

    const payload = offerSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid offer payload.', payload.error.flatten());
    }

    const offer = await sendOffer({ jobPostId: jobPostId.data, auth: req.auth, ...payload.data });
    res.status(201).json({ offer });
  }),
);

router.patch(
  '/:jobPostId/offers/:offerId/accept',
  authenticate,
  asyncHandler(async (req, res) => {
    const jobPostId = z.uuid().safeParse(req.params.jobPostId);
    const offerId = z.uuid().safeParse(req.params.offerId);

    if (!jobPostId.success || !offerId.success) {
      throw new HttpError(400, 'Invalid job or offer id.');
    }

    const result = await chooseOffer({ jobPostId: jobPostId.data, offerId: offerId.data, auth: req.auth });
    res.json(result);
  }),
);

module.exports = { jobRoutes: router };
