const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { authorizeRoles } = require('../middleware/authorize-roles');
const {
  getConversationMessages,
  getMyConversations,
  sendConversationMessage,
  startConversation,
} = require('../services/conversation-service');

const router = express.Router();

const createConversationSchema = z.object({
  providerUserId: z.uuid(),
  serviceListingId: z.string().optional(),
  bookingId: z.uuid().optional(),
  initialMessage: z.string().min(2).max(1000),
});

const messageSchema = z.object({
  message: z.string().min(1).max(1000),
});

router.use(authenticate);

router.post(
  '/',
  authorizeRoles('client', 'admin'),
  asyncHandler(async (req, res) => {
    const payload = createConversationSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid inquiry payload.', payload.error.flatten());
    }

    const result = await startConversation({
      clientUserId: req.auth.sub,
      ...payload.data,
    });

    res.status(201).json(result);
  }),
);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const conversations = await getMyConversations(req.auth.sub);
    res.json({ conversations });
  }),
);

router.get(
  '/:conversationId/messages',
  asyncHandler(async (req, res) => {
    const conversationId = z.uuid().safeParse(req.params.conversationId);

    if (!conversationId.success) {
      throw new HttpError(400, 'Invalid conversation id.');
    }

    const result = await getConversationMessages({ conversationId: conversationId.data, auth: req.auth });
    res.json(result);
  }),
);

router.post(
  '/:conversationId/messages',
  asyncHandler(async (req, res) => {
    const conversationId = z.uuid().safeParse(req.params.conversationId);

    if (!conversationId.success) {
      throw new HttpError(400, 'Invalid conversation id.');
    }

    const payload = messageSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid message payload.', payload.error.flatten());
    }

    const message = await sendConversationMessage({
      conversationId: conversationId.data,
      auth: req.auth,
      message: payload.data.message,
    });

    res.status(201).json({ message });
  }),
);

module.exports = { inquiryRoutes: router };
