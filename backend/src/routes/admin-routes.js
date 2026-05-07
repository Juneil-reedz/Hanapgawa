const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { getAllBookings } = require('../services/booking-service');
const { addCategory, editCategory, getCategories } = require('../services/category-service');
const { getReports, resolveReport } = require('../services/report-service');
const { findUserById, listUsersByRoles, updateUserStatus } = require('../repositories/user-repository');

const router = express.Router();

const approvalSchema = z.object({
  status: z.enum(['approved', 'rejected', 'pending']),
});

const categorySchema = z.object({
  name: z.string().min(2).max(80),
  description: z.string().max(240).optional().default(''),
  icon: z.string().max(80).optional().default('briefcase-outline'),
});

const categoryUpdateSchema = categorySchema.extend({
  active: z.boolean(),
});

const reportStatusSchema = z.object({
  status: z.enum(['resolved', 'dismissed', 'pending']),
});

router.use(authenticate, authorizeRoles('admin'));

router.get(
  '/providers',
  asyncHandler(async (req, res) => {
    const status = req.query.status ? String(req.query.status) : undefined;
    const providers = await listUsersByRoles(['worker', 'agency'], status);
    res.json({ providers });
  }),
);

router.patch(
  '/providers/:userId/status',
  asyncHandler(async (req, res) => {
    const userId = z.uuid().safeParse(req.params.userId);

    if (!userId.success) {
      throw new HttpError(400, 'Invalid user id.');
    }

    const payload = approvalSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid approval payload.', payload.error.flatten());
    }

    const user = await findUserById(userId.data);

    if (!user) {
      throw new HttpError(404, 'User not found.');
    }

    if (!['worker', 'agency'].includes(user.role)) {
      throw new HttpError(409, 'Only worker and agency accounts can be approved here.');
    }

    const updatedUser = await updateUserStatus(user.id, payload.data.status);
    res.json({ user: updatedUser });
  }),
);

router.get(
  '/bookings',
  asyncHandler(async (req, res) => {
    const bookings = await getAllBookings(req.query.status ? String(req.query.status) : undefined);
    res.json({ bookings });
  }),
);

router.get(
  '/categories',
  asyncHandler(async (_req, res) => {
    const categories = await getCategories(false);
    res.json({ categories });
  }),
);

router.post(
  '/categories',
  asyncHandler(async (req, res) => {
    const payload = categorySchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid category payload.', payload.error.flatten());
    }

    const category = await addCategory(payload.data);
    res.status(201).json({ category });
  }),
);

router.patch(
  '/categories/:categoryId',
  asyncHandler(async (req, res) => {
    const categoryId = z.uuid().safeParse(req.params.categoryId);

    if (!categoryId.success) {
      throw new HttpError(400, 'Invalid category id.');
    }

    const payload = categoryUpdateSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid category update payload.', payload.error.flatten());
    }

    const category = await editCategory({ id: categoryId.data, ...payload.data });
    res.json({ category });
  }),
);

router.get(
  '/reports',
  asyncHandler(async (req, res) => {
    const reports = await getReports(req.query.status ? String(req.query.status) : undefined);
    res.json({ reports });
  }),
);

router.patch(
  '/reports/:reportId',
  asyncHandler(async (req, res) => {
    const reportId = z.uuid().safeParse(req.params.reportId);

    if (!reportId.success) {
      throw new HttpError(400, 'Invalid report id.');
    }

    const payload = reportStatusSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid report status payload.', payload.error.flatten());
    }

    const report = await resolveReport({ id: reportId.data, status: payload.data.status });
    res.json({ report });
  }),
);

module.exports = { adminRoutes: router };
