const { createClient } = require('redis');

const { env } = require('../config/env');

let client;
let readClient;

async function getRedisClient() {
  if (!env.redisUrl) {
    return null;
  }

  if (!client) {
    client = createClient({
      url: env.redisUrl,
      socket: { tls: env.redisUrl.startsWith('rediss://'), rejectUnauthorized: false },
    });
    client.on('error', (err) => console.warn('[Redis error]', err.message));
  }

  if (!client.isOpen) {
    await client.connect();
  }

  return client;
}

// Returns a separate read-replica client when REDIS_READ_URL is configured,
// otherwise falls back to the main client.
async function getRedisReadClient() {
  if (!env.redisUrl) {
    return null;
  }

  if (!env.redisReadUrl) {
    return getRedisClient();
  }

  if (!readClient) {
    readClient = createClient({ url: env.redisReadUrl });
    readClient.on('error', () => {});
  }

  if (!readClient.isOpen) {
    await readClient.connect();
  }

  return readClient;
}

async function checkRedisHealth() {
  const redis = await getRedisClient();

  if (!redis) {
    return { configured: false, healthy: false };
  }

  await redis.ping();
  return { configured: true, healthy: true };
}

async function closeRedisClient() {
  const tasks = [];

  if (client) {
    if (client.isOpen) tasks.push(client.quit());
    else tasks.push(Promise.resolve());
    client = null;
  }

  if (readClient) {
    if (readClient.isOpen) tasks.push(readClient.quit());
    else tasks.push(Promise.resolve());
    readClient = null;
  }

  await Promise.all(tasks);
}

module.exports = {
  checkRedisHealth,
  getRedisClient,
  getRedisReadClient,
  closeRedisClient,
};
