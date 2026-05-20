const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const {
  deleteConversationMessage, editConversationMessage, getConversationMessages,
  getMyConversations, listNicknames, removeConversation, removeNickname,
  sendConversationMessage, setNickname, startConversation,
} = require('../services/conversation-service');

const router = express.Router();
router.use(authenticate);

const createConversationSchema = z.object({
  providerUserId: z.string().uuid(),
  serviceListingId: z.string().optional(),
  bookingId: z.string().uuid().optional(),
  initialMessage: z.string().min(1).max(1000),
});

const messageSchema = z.object({
  message: z.string().max(2000).default(''),
  image: z.string().optional(),
  voiceMessage: z.string().optional(),
  voiceDuration: z.coerce.number().int().nonnegative().optional().default(0),
  replyToMessageId: z.string().uuid().optional(),
  forwardedFromMessageId: z.string().uuid().optional(),
}).refine(d => d.message.trim().length > 0 || d.image || d.voiceMessage, { message: 'Message, image, or voice message required.' });

// POST /inquiries — start conversation (any authenticated user)
router.post('/', asyncHandler(async (req, res) => {
  const payload = createConversationSchema.safeParse(req.body);
  if (!payload.success) throw new HttpError(400, 'Invalid inquiry payload.', payload.error.flatten());
  const result = await startConversation({
    initiatorUserId: req.auth.sub,
    targetUserId: payload.data.providerUserId,
    serviceListingId: payload.data.serviceListingId,
    bookingId: payload.data.bookingId,
    initialMessage: payload.data.initialMessage,
  });
  res.status(201).json(result);
}));

// GET /inquiries — list conversations with optional search
router.get('/', asyncHandler(async (req, res) => {
  const search = (req.query.q || '').toString().trim();
  const conversations = await getMyConversations(req.auth.sub, search);
  res.json({ conversations });
}));

// GET /inquiries/:conversationId/messages
router.get('/:conversationId/messages', asyncHandler(async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.conversationId);
  if (!parsed.success) throw new HttpError(400, 'Invalid conversation id.');
  const result = await getConversationMessages({ conversationId: parsed.data, auth: req.auth });
  res.json(result);
}));

// POST /inquiries/:conversationId/messages
router.post('/:conversationId/messages', asyncHandler(async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.conversationId);
  if (!parsed.success) throw new HttpError(400, 'Invalid conversation id.');
  const payload = messageSchema.safeParse(req.body);
  if (!payload.success) throw new HttpError(400, payload.error.errors[0]?.message || 'Invalid message.');
  const message = await sendConversationMessage({
    conversationId: parsed.data,
    auth: req.auth,
    message: payload.data.message || '',
    image: payload.data.image || null,
    voiceMessage: payload.data.voiceMessage || null,
    voiceDuration: payload.data.voiceDuration || 0,
    replyToMessageId: payload.data.replyToMessageId || null,
    forwardedFromMessageId: payload.data.forwardedFromMessageId || null,
  });
  res.status(201).json({ message });
}));

// PATCH /inquiries/:conversationId/messages/:messageId — edit message
router.patch('/:conversationId/messages/:messageId', asyncHandler(async (req, res) => {
  const msgId = z.string().uuid().safeParse(req.params.messageId);
  if (!msgId.success) throw new HttpError(400, 'Invalid message id.');
  const body = (req.body.message || '').toString().trim();
  if (!body) throw new HttpError(400, 'Message cannot be empty.');
  const message = await editConversationMessage({ messageId: msgId.data, auth: req.auth, message: body });
  res.json({ message });
}));

// DELETE /inquiries/:conversationId/messages/:messageId — delete a message
router.delete('/:conversationId/messages/:messageId', asyncHandler(async (req, res) => {
  const msgId = z.string().uuid().safeParse(req.params.messageId);
  if (!msgId.success) throw new HttpError(400, 'Invalid message id.');
  await deleteConversationMessage({ messageId: msgId.data, auth: req.auth });
  res.json({ deleted: true });
}));

// DELETE /inquiries/:conversationId — delete entire conversation
router.delete('/:conversationId', asyncHandler(async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.conversationId);
  if (!parsed.success) throw new HttpError(400, 'Invalid conversation id.');
  await removeConversation({ conversationId: parsed.data, auth: req.auth });
  res.json({ deleted: true });
}));

// GET /inquiries/:conversationId/nicknames
router.get('/:conversationId/nicknames', asyncHandler(async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.conversationId);
  if (!parsed.success) throw new HttpError(400, 'Invalid conversation id.');
  const nicknames = await listNicknames({ conversationId: parsed.data, auth: req.auth });
  res.json({ nicknames });
}));

// PUT /inquiries/:conversationId/nicknames — set/update/clear a nickname
router.put('/:conversationId/nicknames', asyncHandler(async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.conversationId);
  if (!parsed.success) throw new HttpError(400, 'Invalid conversation id.');
  const body = z.object({
    targetUserId: z.string().uuid(),
    nickname: z.string().max(60).default(''),
  }).safeParse(req.body);
  if (!body.success) throw new HttpError(400, 'Invalid nickname payload.');
  const result = await setNickname({
    conversationId: parsed.data,
    targetUserId: body.data.targetUserId,
    nickname: body.data.nickname,
    auth: req.auth,
  });
  res.json({ nickname: result });
}));

// DELETE /inquiries/:conversationId/nicknames/:targetUserId
router.delete('/:conversationId/nicknames/:targetUserId', asyncHandler(async (req, res) => {
  const convId = z.string().uuid().safeParse(req.params.conversationId);
  const userId = z.string().uuid().safeParse(req.params.targetUserId);
  if (!convId.success || !userId.success) throw new HttpError(400, 'Invalid id.');
  await removeNickname({ conversationId: convId.data, targetUserId: userId.data, auth: req.auth });
  res.json({ deleted: true });
}));

module.exports = { inquiryRoutes: router };
