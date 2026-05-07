const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { submitReport } = require('../services/report-service');

const router = express.Router();

const reportSchema = z.object({
  providerUserId: z.uuid().optional(),
  bookingId: z.uuid().optional(),
  reason: z.string().min(3).max(160),
  details: z.string().max(1500).optional().default(''),
});

router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const payload = reportSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid report payload.', payload.error.flatten());
    }

    const report = await submitReport({
      reporterUserId: req.auth.sub,
      ...payload.data,
    });

    res.status(201).json({ report });
  }),
);

module.exports = { reportRoutes: router };
