const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const {
  createServiceListing,
  getServiceListingById,
  searchServiceListings,
} = require('../services/service-listing-service');

const router = express.Router();

const serviceListingSchema = z.object({
  title: z.string().min(3).max(120),
  category: z.string().min(2).max(80),
  municipality: z.string().min(2).max(80),
  description: z.string().min(10).max(1500),
  priceMin: z.number().nonnegative().optional(),
  priceMax: z.number().nonnegative().optional(),
  estimatedDuration: z.string().max(80).optional().default(''),
  requirements: z.array(z.string().min(1).max(160)).max(20).default([]),
  media: z
    .array(
      z.object({
        title: z.string().min(1).max(120),
        url: z.string().min(1).max(500),
        type: z.enum(['image', 'video', 'document']).default('image'),
      }),
    )
    .max(20)
    .default([]),
});

router.post(
  '/',
  authenticate,
  authorizeRoles('worker', 'agency'),
  asyncHandler(async (req, res) => {
    const payload = serviceListingSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid service listing payload.', payload.error.flatten());
    }

    const listing = await createServiceListing({
      providerUserId: req.auth.sub,
      providerRole: req.auth.role,
      ...payload.data,
    });

    res.status(201).json({ listing });
  }),
);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const listings = await searchServiceListings({
      category: req.query.category,
      municipality: req.query.municipality,
      keyword: req.query.keyword,
    });

    res.json({ listings });
  }),
);

router.get(
  '/:listingId',
  asyncHandler(async (req, res) => {
    const listing = await getServiceListingById(req.params.listingId);
    res.json({ listing });
  }),
);

module.exports = { serviceListingRoutes: router };
