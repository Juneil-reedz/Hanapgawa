const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { createServiceListing, getServiceListingById, searchServiceListings } = require('../services/service-listing-service');

const router = express.Router();

const serviceListingSchema = z.object({
  title: z.string().min(3).max(120),
  category: z.string().min(2).max(80),
  municipality: z.string().min(2).max(80),
  description: z.string().min(10).max(2000),
  priceMin: z.number().nonnegative(),
  priceMax: z.number().nonnegative(),
  estimatedDuration: z.string().min(2).max(120),
  requirements: z.array(z.string().min(1).max(160)).max(12).default([]),
  availability: z.array(z.string().min(1).max(120)).max(12).default([]),
  media: z.array(z.object({ imageUrl: z.string().max(500), caption: z.string().max(160).optional().default('') })).max(12).default([]),
});

router.get(
  '/search',
  asyncHandler(async (req, res) => {
    const listings = await searchServiceListings({
      category: req.query.category,
      municipality: req.query.municipality,
      keyword: req.query.keyword || req.query.service,
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

router.post(
  '/',
  authenticate,
  authorizeRoles('worker', 'agency', 'admin'),
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

module.exports = { serviceRoutes: router };
