const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { getAllBookings } = require('../services/booking-service');
const { addCategory, editCategory, getCategories } = require('../services/category-service');
const { getReports, resolveReport } = require('../services/report-service');
const { getPostgresPool } = require('../db/postgres');
const { getMongoDb } = require('../db/mongo');
const { findUserById, listAllUsersForAdmin, listUsersByRoles, updateUserStatus } = require('../repositories/user-repository');

const router = express.Router();

const approvalSchema = z.object({
  status: z.enum(['approved', 'rejected', 'pending']),
});

const userStatusSchema = z.object({
  status: z.enum(['approved', 'rejected', 'pending', 'suspended', 'banned']),
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

const deletePostSchema = z.object({
  reason: z.string().max(240).optional().default('Removed by admin for violating HanapGawa community guidelines.'),
});

router.use(authenticate, authorizeRoles('admin'));

router.get(
  '/summary',
  asyncHandler(async (_req, res) => {
    const pool = getPostgresPool();
    if (!pool) {
      return res.json({
        summary: {
          totalUsers: 0,
          verifiedUsers: 0,
          pendingVerifications: 0,
          activePosts: 0,
          completedJobs: 0,
          pendingReports: 0,
          suspendedUsers: 0,
        },
      });
    }

    const result = await pool.query(`
      SELECT
        (SELECT COUNT(*)::INT FROM users) AS "totalUsers",
        (SELECT COUNT(*)::INT FROM users WHERE status = 'approved') AS "verifiedUsers",
        (SELECT COUNT(*)::INT FROM users WHERE status = 'pending') AS "pendingVerifications",
        (SELECT COUNT(*)::INT FROM job_posts WHERE status IN ('open', 'assigned'))
          + (SELECT COUNT(*)::INT FROM social_posts WHERE privacy = 'Public') AS "activePosts",
        (SELECT COUNT(*)::INT FROM bookings WHERE status = 'completed') AS "completedJobs",
        (SELECT COUNT(*)::INT FROM reports WHERE status = 'pending') AS "pendingReports",
        (SELECT COUNT(*)::INT FROM users WHERE status IN ('suspended', 'banned')) AS "suspendedUsers"
    `);

    res.json({ summary: result.rows[0] });
  }),
);

router.get(
  '/users',
  asyncHandler(async (req, res) => {
    const users = await listAllUsersForAdmin(req.query.search ? String(req.query.search) : '');
    res.json({ users });
  }),
);

router.patch(
  '/users/:userId/status',
  asyncHandler(async (req, res) => {
    const userId = z.uuid().safeParse(req.params.userId);

    if (!userId.success) {
      throw new HttpError(400, 'Invalid user id.');
    }

    const payload = userStatusSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid user status payload.', payload.error.flatten());
    }

    const user = await findUserById(userId.data);

    if (!user) {
      throw new HttpError(404, 'User not found.');
    }

    if (user.role === 'admin') {
      throw new HttpError(409, 'Admin accounts cannot be changed here.');
    }

    const updatedUser = await updateUserStatus(user.id, payload.data.status);
    res.json({ user: updatedUser });
  }),
);

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
  '/posts',
  asyncHandler(async (_req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ posts: [] });

    const result = await pool.query(`
      SELECT
        id,
        user_id AS "userId",
        full_name AS "fullName",
        body,
        image,
        privacy,
        created_at AS "createdAt"
      FROM social_posts
      ORDER BY created_at DESC
      LIMIT 100
    `);

    res.json({ posts: result.rows });
  }),
);

router.delete(
  '/posts/:postId',
  asyncHandler(async (req, res) => {
    const postId = z.uuid().safeParse(req.params.postId);

    if (!postId.success) {
      throw new HttpError(400, 'Invalid post id.');
    }

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const payload = deletePostSchema.safeParse(req.body || {});
    if (!payload.success) throw new HttpError(400, 'Invalid delete post payload.', payload.error.flatten());
    const result = await pool.query(
      `WITH deleted AS (
         DELETE FROM social_posts
         WHERE id = $1
         RETURNING id, user_id, body
       ), inserted AS (
         INSERT INTO notifications (
           user_id,
           actor_id,
           actor_name,
           type,
           title,
           body,
           link_type,
           link_id
         )
         SELECT
           user_id,
           $2,
           'HanapGawa Admin',
           'content_removed',
           'Your post was removed',
           $3,
           NULL,
           NULL
         FROM deleted
         RETURNING id
       )
       SELECT deleted.id, deleted.user_id AS "userId", inserted.id AS "notificationId"
       FROM deleted
       LEFT JOIN inserted ON true`,
      [postId.data, req.auth.sub, payload.data.reason],
    );
    if (!result.rows.length) throw new HttpError(404, 'Post not found.');
    res.json({ deleted: true, notified: !!result.rows[0].notificationId });
  }),
);

router.get(
  '/reviews',
  asyncHandler(async (_req, res) => {
    const pool = getPostgresPool();
    if (!pool) return res.json({ reviews: [] });

    const result = await pool.query(`
      SELECT
        r.id,
        r.booking_id AS "bookingId",
        r.reviewer_user_id AS "reviewerUserId",
        reviewer.full_name AS "reviewerName",
        r.provider_user_id AS "reviewedUserId",
        reviewed.full_name AS "reviewedName",
        r.rating,
        r.comment,
        r.created_at AS "createdAt"
      FROM reviews r
      LEFT JOIN users reviewer ON reviewer.id = r.reviewer_user_id
      LEFT JOIN users reviewed ON reviewed.id = r.provider_user_id
      ORDER BY r.created_at DESC
      LIMIT 100
    `);

    res.json({ reviews: result.rows });
  }),
);

router.delete(
  '/reviews/:reviewId',
  asyncHandler(async (req, res) => {
    const reviewId = z.uuid().safeParse(req.params.reviewId);

    if (!reviewId.success) {
      throw new HttpError(400, 'Invalid review id.');
    }

    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const result = await pool.query('DELETE FROM reviews WHERE id = $1 RETURNING id', [reviewId.data]);
    if (!result.rows.length) throw new HttpError(404, 'Review not found.');
    res.json({ deleted: true });
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
  '/service-listings',
  asyncHandler(async (_req, res) => {
    const mongoDb = await getMongoDb();
    if (!mongoDb) return res.json({ listings: [] });
    const raw = await mongoDb.collection('service_listings')
      .find({})
      .sort({ createdAt: -1 })
      .limit(200)
      .toArray();
    const listings = raw.map((l) => ({
      id: l._id.toString(),
      providerUserId: l.providerUserId,
      providerDisplayName: l.providerDisplayName ?? null,
      title: l.title,
      category: l.category,
      municipality: l.municipality,
      status: l.status ?? 'active',
      priceMin: l.priceMin ?? null,
      priceMax: l.priceMax ?? null,
      createdAt: l.createdAt,
    }));
    res.json({ listings });
  }),
);

router.delete(
  '/service-listings/:listingId',
  asyncHandler(async (req, res) => {
    const mongoDb = await getMongoDb();
    if (!mongoDb) throw new HttpError(503, 'Database unavailable.');
    const { ObjectId } = require('mongodb');
    let oid;
    try { oid = new ObjectId(req.params.listingId); } catch {
      throw new HttpError(400, 'Invalid listing id.');
    }
    const result = await mongoDb.collection('service_listings')
      .deleteOne({ _id: oid });
    if (!result.deletedCount) throw new HttpError(404, 'Listing not found.');
    res.json({ deleted: true });
  }),
);

router.delete(
  '/jobs/:jobId',
  asyncHandler(async (req, res) => {
    const jobId = z.uuid().safeParse(req.params.jobId);
    if (!jobId.success) throw new HttpError(400, 'Invalid job id.');
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const result = await pool.query('DELETE FROM job_posts WHERE id = $1 RETURNING id', [jobId.data]);
    if (!result.rows.length) throw new HttpError(404, 'Job post not found.');
    res.json({ deleted: true });
  }),
);

router.delete(
  '/users/:userId',
  asyncHandler(async (req, res) => {
    const userId = z.uuid().safeParse(req.params.userId);
    if (!userId.success) throw new HttpError(400, 'Invalid user id.');
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const user = await findUserById(userId.data);
    if (!user) throw new HttpError(404, 'User not found.');
    if (user.role === 'admin') throw new HttpError(403, 'Admin accounts cannot be deleted here.');
    await pool.query('DELETE FROM users WHERE id = $1', [userId.data]);
    res.json({ deleted: true, user });
  }),
);

router.delete(
  '/users/by-email',
  asyncHandler(async (req, res) => {
    const email = z.string().email().safeParse(req.body?.email);
    if (!email.success) throw new HttpError(400, 'Valid email is required.');
    const pool = getPostgresPool();
    if (!pool) throw new HttpError(503, 'Database unavailable.');
    const result = await pool.query(
      'DELETE FROM users WHERE email = $1 RETURNING id, email, full_name AS "fullName"',
      [email.data],
    );
    if (!result.rows.length) throw new HttpError(404, 'No user found with that email.');
    res.json({ deleted: true, user: result.rows[0] });
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
