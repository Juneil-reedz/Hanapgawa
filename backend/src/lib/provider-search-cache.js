const { getRedisClient } = require('../db/redis');

const CACHE_TTL_SECONDS = 300;
const CACHE_INDEX_KEY = 'providers:search:index';

function buildSearchCacheKey({ category = '', municipality = '', service = '' }) {
  return `providers:search:${JSON.stringify({
    category: category.trim().toLowerCase(),
    municipality: municipality.trim().toLowerCase(),
    service: service.trim().toLowerCase(),
  })}`;
}

async function getCachedProviderSearch(filters) {
  const redis = await getRedisClient();

  if (!redis) {
    return null;
  }

  const key = buildSearchCacheKey(filters);
  const cached = await redis.get(key);

  if (!cached) {
    return null;
  }

  return {
    key,
    data: JSON.parse(cached),
  };
}

async function setCachedProviderSearch(filters, payload) {
  const redis = await getRedisClient();

  if (!redis) {
    return null;
  }

  const key = buildSearchCacheKey(filters);
  await redis.set(key, JSON.stringify(payload), { EX: CACHE_TTL_SECONDS });
  await redis.sAdd(CACHE_INDEX_KEY, key);

  return key;
}

async function invalidateProviderSearchCache() {
  const redis = await getRedisClient();

  if (!redis) {
    return { invalidated: 0, configured: false };
  }

  const keys = await redis.sMembers(CACHE_INDEX_KEY);

  if (keys.length > 0) {
    await Promise.all(keys.map((key) => redis.del(key)));
  }

  await redis.del(CACHE_INDEX_KEY);

  return {
    invalidated: keys.length,
    configured: true,
  };
}

module.exports = {
  getCachedProviderSearch,
  invalidateProviderSearchCache,
  setCachedProviderSearch,
};
