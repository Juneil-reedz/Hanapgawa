const cors = require('cors');
const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');

const { env } = require('./config/env');
const { errorHandler } = require('./middleware/error-handler');
const { apiRoutes } = require('./routes');

const app = express();

function isAllowedOrigin(origin) {
  if (!origin) {
    return true;
  }

  if (origin === env.clientOrigin) {
    return true;
  }

  if (env.nodeEnv !== 'production') {
    return /^http:\/\/(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+):8100$/.test(origin);
  }

  return false;
}

app.use(helmet());
app.use(
  cors({
    origin(origin, callback) {
      callback(null, isAllowedOrigin(origin));
    },
    credentials: true,
  }),
);
app.use(express.json({ limit: '250mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

app.get('/', (_req, res) => {
  res.json({
    name: 'HanapGawa Backend API',
    version: '0.1.0',
    docsHint: `${env.apiPrefix}/health`,
  });
});

app.use(env.apiPrefix, apiRoutes);
app.use(errorHandler);

module.exports = { app };
