const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const { applyWorkerToAgency, listMyApplications, resolveApplication, listAgencyMemberships } = require('../services/agency-service');

const router = express.Router();

const createApplicationSchema = z.object({
  workerUserId: z.uuid(),
  message: z.string().max(1000).optional().default(''),
});

const updateApplicationSchema = z.object({
  status: z.enum(['approved', 'rejected', 'withdrawn']),
});

router.post(
  '/applications',
  authenticate,
  authorizeRoles('agency', 'admin'),
  asyncHandler(async (req, res) => {
    const payload = createApplicationSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid agency application payload.', payload.error.flatten());
    }

    const application = await applyWorkerToAgency({
      agencyUserId: req.auth.sub,
      workerUserId: payload.data.workerUserId,
      message: payload.data.message,
    });

    res.status(201).json({ application });
  }),
);

router.get(
  '/applications/mine',
  authenticate,
  authorizeRoles('agency', 'worker', 'admin'),
  asyncHandler(async (req, res) => {
    const applications = await listMyApplications({
      role: req.auth.role,
      userId: req.auth.sub,
      status: req.query.status ? String(req.query.status) : undefined,
    });

    res.json({ applications });
  }),
);

router.patch(
  '/applications/:applicationId',
  authenticate,
  authorizeRoles('worker', 'admin'),
  asyncHandler(async (req, res) => {
    const applicationId = z.uuid().safeParse(req.params.applicationId);

    if (!applicationId.success) {
      throw new HttpError(400, 'Invalid application id.');
    }

    const payload = updateApplicationSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid application update payload.', payload.error.flatten());
    }

    const application = await resolveApplication({
      applicationId: applicationId.data,
      status: payload.data.status,
      auth: req.auth,
    });

    res.json({ application });
  }),
);

router.get(
  '/memberships/:agencyUserId',
  asyncHandler(async (req, res) => {
    const agencyUserId = z.uuid().safeParse(req.params.agencyUserId);

    if (!agencyUserId.success) {
      throw new HttpError(400, 'Invalid agency user id.');
    }

    const memberships = await listAgencyMemberships(agencyUserId.data);
    res.json({ memberships });
  }),
);

module.exports = { agencyRoutes: router };
