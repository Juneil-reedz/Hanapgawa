const dotenv = require('dotenv');

dotenv.config({ quiet: true });

const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 4000),
  apiPrefix: process.env.API_PREFIX || '/api/v1',
  clientOrigin: process.env.CLIENT_ORIGIN || 'http://localhost:8100',
  jwtSecret: process.env.JWT_SECRET || 'change-me',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  postgresUrl: process.env.POSTGRES_URL || '',
  postgresReadUrl: process.env.POSTGRES_READ_URL || '',
  postgresSsl: process.env.POSTGRES_SSL === 'true',
  mongodbUrl: process.env.MONGODB_URL || '',
  mongodbDbName: process.env.MONGODB_DB_NAME || 'hanapgawa',
  redisUrl: process.env.REDIS_URL || '',
  redisReadUrl: process.env.REDIS_READ_URL || '',
  brevoApiKey: process.env.BREVO_API_KEY || '',
  emailFrom: process.env.EMAIL_FROM || 'HanapGawa <noreply@hanapgawa.com>',
  emailLogoPath: process.env.EMAIL_LOGO_PATH || '',
  googleClientId: process.env.GOOGLE_CLIENT_ID || '',
  giphyApiKey: process.env.GIPHY_API_KEY || '',
  cloudinaryCloudName: process.env.CLOUDINARY_CLOUD_NAME || '',
  cloudinaryApiKey: process.env.CLOUDINARY_API_KEY || '',
  cloudinaryApiSecret: process.env.CLOUDINARY_API_SECRET || '',
  spotifyClientId: process.env.SPOTIFY_CLIENT_ID || '',
  spotifyClientSecret: process.env.SPOTIFY_CLIENT_SECRET || '',
  livekitUrl: process.env.LIVEKIT_URL || '',
  livekitApiKey: process.env.LIVEKIT_API_KEY || '',
  livekitApiSecret: process.env.LIVEKIT_API_SECRET || '',
  geminiApiKey: process.env.GEMINI_API_KEY || '',
  groqApiKey: process.env.GROQ_API_KEY || '',
  gatewayInternalSecret: process.env.GATEWAY_INTERNAL_SECRET || '',
  gatewayJwksUrl: process.env.GATEWAY_JWKS_URL || 'https://tawi-tawi-backend.onrender.com/.well-known/jwks.json',
};

module.exports = { env };
