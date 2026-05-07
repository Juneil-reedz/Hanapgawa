const cors = require('cors');
const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');

const { env } = require('./config/env');
const { errorHandler } = require('./middleware/error-handler');
const { apiRoutes } = require('./routes');

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: env.clientOrigin,
    credentials: true,
  }),
);
app.use(express.json({ limit: '6mb' }));
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
