const express = require('express');

const { checkMongoHealth } = require('../db/mongo');
const { checkPostgresHealth } = require('../db/postgres');
const { checkRedisHealth } = require('../db/redis');
const { asyncHandler } = require('../lib/async-handler');

const router = express.Router();

router.get(
  '/',
  asyncHandler(async (_req, res) => {
    const [postgres, mongo, redis] = await Promise.allSettled([
      checkPostgresHealth(),
      checkMongoHealth(),
      checkRedisHealth(),
    ]);

    res.json({
      service: 'hanapgawa-backend',
      status: 'ok',
      databases: {
        postgres: postgres.status === 'fulfilled' ? postgres.value : { configured: true, healthy: false },
        mongo: mongo.status === 'fulfilled' ? mongo.value : { configured: true, healthy: false },
        redis: redis.status === 'fulfilled' ? redis.value : { configured: true, healthy: false },
      },
    });
  }),
);

module.exports = { healthRoutes: router };
