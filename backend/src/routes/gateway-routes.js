const express = require('express');
const crypto = require('crypto');
const bcrypt = require('bcrypt');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { env } = require('../config/env');
const { findUserByEmail, createUser } = require('../repositories/user-repository');

const router = express.Router();

// Middleware to verify the Gateway Signature
function requireGatewayAuth(req, res, next) {
  const secret = req.headers['x-internal-gateway-secret'];
  
  if (!secret || secret !== env.gatewayInternalSecret) {
    throw new HttpError(401, 'Unauthorized Gateway Request');
  }
  
  next();
}

// Apply the security check to all routes in this file
router.use(requireGatewayAuth);

// Handshake: Verification
router.post('/verify-user', asyncHandler(async (req, res) => {
  const { email } = req.body;
  
  // Search the PostgreSQL database for the user
  const user = await findUserByEmail(email);
  
  if (user) {
    res.json({ 
      isLinked: true, 
      requiresRegistration: false, 
      externalUserId: user.id 
    });
  } else {
    res.json({ 
      isLinked: false, 
      requiresRegistration: true, 
      externalUserId: null 
    });
  }
}));

// Handshake: Registration
router.post('/register-user', asyncHandler(async (req, res) => {
  const { email, fullName, role = 'client' } = req.body;
  
  let user = await findUserByEmail(email);
  
  if (!user) {
    // Generate a secure random password since the Gateway handles actual authentication
    const randomPass = crypto.randomBytes(32).toString('hex');
    const passwordHash = await bcrypt.hash(randomPass, 10);
    
    // Insert into PostgreSQL and mark as verified
    user = await createUser({
      email,
      passwordHash,
      role,
      fullName,
      emailVerifiedAt: new Date()
    });
  }
  
  res.json({ isLinked: true, externalUserId: user.id });
}));

module.exports = { gatewayRoutes: router };