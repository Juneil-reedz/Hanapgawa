const bcrypt = require('bcrypt');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const { env } = require('../config/env');
const { HttpError } = require('../lib/http-error');
const {
  createEmailVerificationCode,
  createUser,
  findActiveEmailVerificationCode,
  findUserByEmail,
  markEmailVerified,
} = require('../repositories/user-repository');
const { sendEmailVerificationCode } = require('./email-service');

const VERIFICATION_CODE_TTL_MINUTES = 15;

function buildTokenPayload(user) {
  return {
    sub: user.id,
    email: user.email,
    role: user.role,
  };
}

function signAccessToken(user) {
  return jwt.sign(buildTokenPayload(user), env.jwtSecret, {
    expiresIn: env.jwtExpiresIn,
  });
}

function buildPublicUser(user) {
  return {
    id: user.id,
    email: user.email,
    role: user.role,
    fullName: user.fullName,
    status: user.status,
    emailVerified: Boolean(user.emailVerifiedAt),
  };
}

function hashVerificationCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

async function createVerificationCode(user) {
  const code = String(crypto.randomInt(100000, 1000000));
  const expiresAt = new Date(Date.now() + VERIFICATION_CODE_TTL_MINUTES * 60 * 1000);

  await createEmailVerificationCode({
    userId: user.id,
    codeHash: hashVerificationCode(code),
    expiresAt,
  });

  let emailResult;

  try {
    emailResult = await sendEmailVerificationCode({ email: user.email, code });
  } catch (error) {
    emailResult = { sent: false, reason: error.message };
    console.warn(`Email verification send failed for ${user.email}: ${error.message}`);
  }

  if (!emailResult.sent) {
    console.log(`HanapGawa email verification code for ${user.email}: ${code}`);
  }

  return { code, expiresAt, emailSent: emailResult.sent };
}

async function registerUser({ email, password, role, fullName }) {
  const existingUser = await findUserByEmail(email);

  if (existingUser) {
    throw new HttpError(409, 'Email is already registered.');
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const user = await createUser({ email, passwordHash, role, fullName });
  const verification = await createVerificationCode(user);

  return {
    user: buildPublicUser(user),
    emailVerificationRequired: true,
    emailSent: verification.emailSent,
    ...(!verification.emailSent && env.nodeEnv !== 'production' ? { devVerificationCode: verification.code } : {}),
  };
}

async function loginUser({ email, password }) {
  const user = await findUserByEmail(email);

  if (!user) {
    throw new HttpError(401, 'Invalid email or password.');
  }

  const passwordMatches = await bcrypt.compare(password, user.passwordHash);

  if (!passwordMatches) {
    throw new HttpError(401, 'Invalid email or password.');
  }

  if (!user.emailVerifiedAt) {
    throw new HttpError(403, 'Please verify your email before logging in.');
  }

  return {
    user: buildPublicUser(user),
    token: signAccessToken(user),
  };
}

async function resendVerificationCode({ email }) {
  const user = await findUserByEmail(email);

  if (!user) {
    throw new HttpError(404, 'No account exists for that email.');
  }

  if (user.emailVerifiedAt) {
    return { emailVerified: true };
  }

  const verification = await createVerificationCode(user);

  return {
    emailVerificationRequired: true,
    emailSent: verification.emailSent,
    ...(!verification.emailSent && env.nodeEnv !== 'production' ? { devVerificationCode: verification.code } : {}),
  };
}

async function verifyEmail({ email, code }) {
  const user = await findUserByEmail(email);

  if (!user) {
    throw new HttpError(404, 'No account exists for that email.');
  }

  if (user.emailVerifiedAt) {
    return {
      user: buildPublicUser(user),
      token: signAccessToken(user),
    };
  }

  const verification = await findActiveEmailVerificationCode(user.id);

  if (!verification || new Date(verification.expiresAt).getTime() < Date.now()) {
    throw new HttpError(400, 'Verification code is expired. Request a new code.');
  }

  if (verification.codeHash !== hashVerificationCode(code)) {
    throw new HttpError(400, 'Invalid verification code.');
  }

  const verifiedUser = await markEmailVerified(user.id, verification.id);

  return {
    user: buildPublicUser(verifiedUser),
    token: signAccessToken(verifiedUser),
  };
}

function verifyExternalToken(token) {
  return jwt.verify(token, env.jwtSecret);
}

module.exports = {
  loginUser,
  registerUser,
  resendVerificationCode,
  verifyEmail,
  verifyExternalToken,
};
