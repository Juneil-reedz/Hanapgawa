const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { findUserById } = require('../repositories/user-repository');

const router = express.Router();

router.get(
  '/:userId/public',
  authenticate,
  asyncHandler(async (req, res) => {
    const userId = z.uuid().safeParse(req.params.userId);

    if (!userId.success) {
      throw new HttpError(400, 'Invalid user id.');
    }

    const user = await findUserById(userId.data);
    if (!user) {
      throw new HttpError(404, 'User not found.');
    }

    res.json({
      user: {
        id: user.id,
        fullName: user.fullName,
        role: user.role,
        status: user.status,
      },
    });
  }),
);

module.exports = { userRoutes: router };
