const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const { env } = require('../config/env');
const { HttpError } = require('../lib/http-error');
const { findUserByTawiTawiId, findUserById } = require('../repositories/user-repository');

// Configure the JWKS client to fetch the public key from the Tawi-Tawi Gateway
const client = jwksClient({
  jwksUri: env.gatewayJwksUrl,
  cache: true,
  rateLimit: true,
  jwksRequestsPerMinute: 5
});

// Helper function to extract the correct public key based on the token's 'kid'
function getKey(header, callback) {
  client.getSigningKey(header.kid, function(err, key) {
    if (err) {
      console.error("[JWKS Error] Failed to fetch signing key:", err.message);
      return callback(err, null);
    }
    const signingKey = key.publicKey || key.rsaPublicKey;
    callback(null, signingKey);
  });
}

async function authenticate(req, _res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return next(new HttpError(401, 'Missing bearer token.'));
  }

  const token = header.slice(7);

  // Decode the token WITHOUT verifying it first to inspect the header algorithm
  const decodedUnverified = jwt.decode(token, { complete: true });
  
  if (!decodedUnverified || !decodedUnverified.header) {
    return next(new HttpError(401, 'Invalid token format.'));
  }

  const algorithm = decodedUnverified.header.alg;

  // Temporary debug log — remove after diagnosing the 401 issue
  console.log(`[AUTH DEBUG] alg=${algorithm} kid=${decodedUnverified.header.kid} path=${req.path} token_prefix=${token.slice(0, 30)}`);

  // ROUTE 1: Tawi-Tawi Gateway Token (Super App SSO)
  if (algorithm === 'RS256') {
    jwt.verify(token, getKey, { algorithms: ['RS256'] }, async (err, decoded) => {
      if (err) {
        return next(new HttpError(401, 'Super App token expired or invalid.'));
      }
      // Normalize: Tawi-Tawi uses 'userId' claim; HanapGawa routes expect 'sub'
      const tawiTawiId = decoded.sub || decoded.userId || decoded.id;
      if (!tawiTawiId) return next(new HttpError(401, 'Cannot resolve user identity from token.'));

      try {
        // Resolve the real HanapGawa user ID (handles existing accounts linked via tawi_tawi_id)
        const user = await findUserByTawiTawiId(tawiTawiId);
        decoded.sub = user ? user.id : tawiTawiId;
        if (user) decoded.role = user.role;
        req.auth = decoded;
        return next();
      } catch (dbErr) {
        return next(dbErr);
      }
    });
  } 
  // ROUTE 2: HS256 token — either native HanapGawa (standalone app) or gateway-translated
  // (Tawi-Tawi proxy mints HS256 tokens but carries the Kawman role, not the HanapGawa role).
  // Always look up the real role from DB so admin access works through the gateway.
  else if (algorithm === 'HS256') {
    let decoded;
    try {
      decoded = jwt.verify(token, env.jwtSecret);
    } catch {
      return next(new HttpError(401, 'Native token expired or invalid.'));
    }
    try {
      const user = await findUserById(decoded.sub);
      if (user) decoded.role = user.role;
    } catch { /* ignore — fall back to token's own role claim */ }
    req.auth = decoded;
    return next();
  }
  // ROUTE 3: Unknown Token Type
  else {
    return next(new HttpError(401, 'Unsupported authentication method.'));
  }
}

module.exports = { authenticate };