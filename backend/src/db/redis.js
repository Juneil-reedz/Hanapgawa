const { createClient } = require('redis');

const { env } = require('../config/env');

let client;

async function getRedisClient() {
  if (!env.redisUrl) {
    return null;
  }

  if (!client) {
    client = createClient({ url: env.redisUrl });
    client.on('error', () => {});
  }

  if (!client.isOpen) {
    await client.connect();
  }

  return client;
}

async function checkRedisHealth() {
  const redis = await getRedisClient();

  if (!redis) {
    return { configured: false, healthy: false };
  }

  await redis.ping();
  return { configured: true, healthy: true };
}

module.exports = {
  checkRedisHealth,
  getRedisClient,
};
