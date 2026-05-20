const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { getProviderDetail, upsertProviderProfile, searchProviders } = require('../services/provider-service');

const router = express.Router();

const providerProfileSchema = z.object({
  displayName: z.string().min(2).max(120),
  category: z.string().min(2).max(80),
  municipality: z.string().min(2).max(80),
  services: z.array(z.string().min(1).max(120)).max(30).default([]),
  portfolio: z
    .array(
      z.object({
        title: z.string().min(1).max(120),
        imageUrl: z.string().min(1).max(500).optional().default(''),
        description: z.string().max(500).optional().default(''),
      }),
    )
    .max(30)
    .default([]),
});

router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const payload = providerProfileSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid provider profile payload.', payload.error.flatten());
    }

    if (req.auth.role === 'admin') {
      throw new HttpError(403, 'Admins cannot create provider profiles.');
    }

    const profile = await upsertProviderProfile({
      userId: req.auth.sub,
      role: req.auth.role,
      isAdmin: false,
      ...payload.data,
    });

    res.status(201).json({ profile });
  }),
);

router.get(
  '/search',
  asyncHandler(async (req, res) => {
    const result = await searchProviders({
      category: req.query.category,
      municipality: req.query.municipality,
      service: req.query.service,
    });

    res.json(result);
  }),
);

router.get(
  '/:providerUserId',
  asyncHandler(async (req, res) => {
    const providerUserId = z.uuid().safeParse(req.params.providerUserId);

    if (!providerUserId.success) {
      throw new HttpError(400, 'Invalid provider user id.');
    }

    const data = await getProviderDetail(providerUserId.data);
    res.json(data);
  }),
);

module.exports = { providerRoutes: router };
