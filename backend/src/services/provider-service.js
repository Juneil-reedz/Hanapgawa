const { getMongoDb } = require('../db/mongo');
const { HttpError } = require('../lib/http-error');
const { assertApprovedProvider, isApprovedProvider } = require('../lib/provider-approval');
const {
  getCachedProviderSearch,
  invalidateProviderSearchCache,
  setCachedProviderSearch,
} = require('../lib/provider-search-cache');
const { listReviewsForProvider, listReviewSummariesForProviders } = require('../repositories/review-repository');
const { findUserById, listUsersByIds } = require('../repositories/user-repository');

async function upsertProviderProfile({ userId, role, isAdmin, displayName, category, municipality, services, portfolio }) {
  if (!isAdmin) {
    const user = await findUserById(userId);
    assertApprovedProvider(user, 'Only approved worker and agency accounts can publish provider profiles.');
  }

  const mongoDb = await getMongoDb();

  if (!mongoDb) {
    throw new HttpError(503, 'MongoDB is not configured. Set MONGODB_URL first.');
  }

  const existing = await mongoDb.collection('provider_profiles').findOne({ userId });
  const document = {
    userId,
    role,
    displayName,
    category,
    municipality,
    services,
    portfolio,
    createdAt: existing?.createdAt || new Date(),
    updatedAt: new Date(),
  };

  await mongoDb.collection('provider_profiles').updateOne(
    { userId },
    { $set: document },
    { upsert: true },
  );

  await invalidateProviderSearchCache();

  return document;
}

async function searchProviders({ category, municipality, service }) {
  const mongoDb = await getMongoDb();

  if (!mongoDb) {
    throw new HttpError(503, 'MongoDB is not configured. Set MONGODB_URL first.');
  }

  const normalizedFilters = {
    category: category ? String(category) : '',
    municipality: municipality ? String(municipality) : '',
    service: service ? String(service) : '',
  };

  const cached = await getCachedProviderSearch(normalizedFilters);

  if (cached) {
    return { ...cached.data, cache: { source: 'redis', hit: true } };
  }

  const filters = {};

  if (normalizedFilters.category) filters.category = normalizedFilters.category;
  if (normalizedFilters.municipality) filters.municipality = normalizedFilters.municipality;
  if (normalizedFilters.service) {
    filters.services = { $elemMatch: { $regex: normalizedFilters.service, $options: 'i' } };
  }

  const profiles = await mongoDb.collection('provider_profiles').find(filters).limit(20).toArray();
  const users = await listUsersByIds(profiles.map((p) => p.userId));
  const approvedUserIds = new Set(users.filter(isApprovedProvider).map((u) => u.id));
  const visibleProfiles = profiles.filter((p) => approvedUserIds.has(p.userId));

  const reviewSummaries = await listReviewSummariesForProviders(visibleProfiles.map((profile) => profile.userId));
  const summariesByProviderId = new Map(reviewSummaries.map((summary) => [summary.providerUserId, summary]));

  const enrichedProfiles = visibleProfiles.map((profile) => {
    const summary = summariesByProviderId.get(profile.userId);

    return {
      ...profile,
      reviewSummary: summary || { providerUserId: profile.userId, count: 0, average: 0 },
    };
  });

  const payload = { profiles: enrichedProfiles, filters: normalizedFilters };
  await setCachedProviderSearch(normalizedFilters, payload);

  return { ...payload, cache: { source: 'mongo', hit: false } };
}

async function getProviderDetail(providerUserId) {
  const provider = await findUserById(providerUserId);

  if (!provider) {
    throw new HttpError(404, 'Provider not found.');
  }

  assertApprovedProvider(provider, 'This provider is not currently approved.');

  const mongoDb = await getMongoDb();

  if (!mongoDb) {
    throw new HttpError(503, 'MongoDB is not configured. Set MONGODB_URL first.');
  }

  const [profile, serviceListings, reviews] = await Promise.all([
    mongoDb.collection('provider_profiles').findOne({ userId: providerUserId }),
    mongoDb.collection('service_listings').find({ providerUserId, status: 'active' }).sort({ createdAt: -1 }).toArray(),
    listReviewsForProvider(providerUserId),
  ]);

  return {
    provider,
    profile,
    serviceListings: serviceListings.map((listing) => ({
      ...listing,
      id: listing._id.toString(),
      _id: undefined,
    })),
    reviews: reviews.reviews,
    reviewSummary: reviews.summary,
  };
}

module.exports = { getProviderDetail, searchProviders, upsertProviderProfile };
