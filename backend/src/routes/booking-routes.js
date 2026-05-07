const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { requestBooking, getBookingsForUser, getBookingForUser, changeBookingStatus } = require('../services/booking-service');

const router = express.Router();

const bookingSchema = z.object({
  providerUserId: z.uuid(),
  serviceListingId: z.string().optional(),
  serviceCategory: z.string().min(2).max(80),
  municipality: z.string().min(2).max(80),
  locationDetails: z.string().max(240).optional().default(''),
  notes: z.string().max(1000).optional().default(''),
  scheduledAt: z.iso.datetime().optional(),
});

const bookingStatusSchema = z.object({
  status: z.enum(['accepted', 'rejected', 'in_progress', 'completion_requested', 'completed', 'cancellation_requested', 'cancelled']),
});

router.post(
  '/',
  authenticate,
  authorizeRoles('client', 'admin'),
  asyncHandler(async (req, res) => {
    const payload = bookingSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid booking payload.', payload.error.flatten());
    }

    const booking = await requestBooking({
      clientUserId: req.auth.sub,
      isAdmin: req.auth.role === 'admin',
      ...payload.data,
    });

    res.status(201).json({ booking });
  }),
);

router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const bookings = await getBookingsForUser(req.auth.sub, req.query.status ? String(req.query.status) : undefined);
    res.json({ bookings });
  }),
);

router.get(
  '/:bookingId',
  authenticate,
  asyncHandler(async (req, res) => {
    const bookingId = z.uuid().safeParse(req.params.bookingId);

    if (!bookingId.success) {
      throw new HttpError(400, 'Invalid booking id.');
    }

    const booking = await getBookingForUser({ bookingId: bookingId.data, auth: req.auth });
    res.json({ booking });
  }),
);

router.patch(
  '/:bookingId/status',
  authenticate,
  asyncHandler(async (req, res) => {
    const bookingId = z.uuid().safeParse(req.params.bookingId);

    if (!bookingId.success) {
      throw new HttpError(400, 'Invalid booking id.');
    }

    const payload = bookingStatusSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid booking status payload.', payload.error.flatten());
    }

    const booking = await changeBookingStatus({
      bookingId: bookingId.data,
      status: payload.data.status,
      auth: req.auth,
    });

    res.json({ booking });
  }),
);

module.exports = { bookingRoutes: router };
