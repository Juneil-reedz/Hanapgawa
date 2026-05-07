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
  postgresSsl: process.env.POSTGRES_SSL === 'true',
  mongodbUrl: process.env.MONGODB_URL || '',
  mongodbDbName: process.env.MONGODB_DB_NAME || 'hanapgawa',
  redisUrl: process.env.REDIS_URL || '',
  zentroMailApiUrl: process.env.ZENTROMAIL_API_URL || 'https://email-service-app-0dpw.onrender.com',
  zentroMailApiKey: process.env.ZENTROMAIL_API_KEY || '',
  emailFrom: process.env.EMAIL_FROM || 'HanapGawa <verified-sender@example.com>',
};

module.exports = { env };
