const jwt = require('jsonwebtoken');

const { env } = require('../config/env');
const { HttpError } = require('../lib/http-error');

function authenticate(req, _res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return next(new HttpError(401, 'Missing bearer token.'));
  }

  const token = header.slice(7);

  try {
    req.auth = jwt.verify(token, env.jwtSecret);
    return next();
  } catch {
    return next(new HttpError(401, 'Invalid or expired token.'));
  }
}

module.exports = { authenticate };
