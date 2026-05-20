const express = require('express');
const { z } = require('zod');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const {
  loginUser,
  registerUser,
  resendVerificationCode,
  signInWithGoogle,
  verifyEmail,
  verifyExternalToken,
} = require('../services/auth-service');

const router = express.Router();

const registerSchema = z.object({
  email: z.email(),
  password: z.string().min(8),
  role: z.enum(['user', 'client', 'worker', 'agency', 'admin']).optional().default('user'),
  fullName: z.string().min(2).max(120),
});

const loginSchema = z.object({
  email: z.email(),
  password: z.string().min(8),
});

const verifyEmailSchema = z.object({
  email: z.email(),
  code: z.string().regex(/^\d{6}$/),
});

const resendVerificationSchema = z.object({
  email: z.email(),
});

const googleSignInSchema = z.object({
  idToken: z.string().min(1),
});

router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const payload = registerSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid registration payload.', payload.error.flatten());
    }

    const result = await registerUser(payload.data);
    res.status(201).json(result);
  }),
);

router.post(
  '/email/verify',
  asyncHandler(async (req, res) => {
    const payload = verifyEmailSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid email verification payload.', payload.error.flatten());
    }

    const result = await verifyEmail(payload.data);
    res.json(result);
  }),
);

router.post(
  '/email/resend-code',
  asyncHandler(async (req, res) => {
    const payload = resendVerificationSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid resend verification payload.', payload.error.flatten());
    }

    const result = await resendVerificationCode(payload.data);
    res.json(result);
  }),
);

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const payload = loginSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid login payload.', payload.error.flatten());
    }

    const result = await loginUser(payload.data);
    res.json(result);
  }),
);

router.post(
  '/google',
  asyncHandler(async (req, res) => {
    const payload = googleSignInSchema.safeParse(req.body);

    if (!payload.success) {
      throw new HttpError(400, 'Invalid Google sign-in payload.', payload.error.flatten());
    }

    const result = await signInWithGoogle(payload.data);
    res.json(result);
  }),
);

router.get(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    res.json({ user: req.auth });
  }),
);

router.post(
  '/external/verify',
  asyncHandler(async (req, res) => {
    const token = req.body?.token;

    if (!token) {
      throw new HttpError(400, 'Token is required.');
    }

    const payload = verifyExternalToken(token);
    res.json({ valid: true, payload });
  }),
);

module.exports = { authRoutes: router };
