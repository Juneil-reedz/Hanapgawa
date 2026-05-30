const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const { env } = require('../config/env');
const { HttpError } = require('../lib/http-error');

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

function authenticate(req, _res, next) {
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

  // ROUTE 1: Tawi-Tawi Gateway Token (Super App SSO)
  if (algorithm === 'RS256') {
    jwt.verify(token, getKey, { algorithms: ['RS256'] }, (err, decoded) => {
      if (err) {
        return next(new HttpError(401, 'Super App token expired or invalid.'));
      }
      // Debug: log token claims to identify Tawi-Tawi JWT structure
      console.log('[RS256 Token Claims]', JSON.stringify(decoded));
      // Normalize: Tawi-Tawi uses 'id' claim; HanapGawa routes expect 'sub'
      if (!decoded.sub && decoded.id) decoded.sub = decoded.id;
      if (!decoded.sub && decoded.userId) decoded.sub = decoded.userId;
      req.auth = decoded;
      return next();
    });
  } 
  // ROUTE 2: Native HanapGawa Token (Standalone App)
  else if (algorithm === 'HS256') {
    try {
      req.auth = jwt.verify(token, env.jwtSecret);
      return next();
    } catch {
      return next(new HttpError(401, 'Native token expired or invalid.'));
    }
  } 
  // ROUTE 3: Unknown Token Type
  else {
    return next(new HttpError(401, 'Unsupported authentication method.'));
  }
}

module.exports = { authenticate };