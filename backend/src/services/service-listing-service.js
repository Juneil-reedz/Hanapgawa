const { ObjectId } = require('mongodb');

const { getMongoDb } = require('../db/mongo');
const { HttpError } = require('../lib/http-error');
const { assertApprovedProvider, isApprovedProvider } = require('../lib/provider-approval');
const { listReviewSummariesForProviders } = require('../repositories/review-repository');
const { findUserById, listUsersByIds } = require('../repositories/user-repository');

function requireMongo() {
  return getMongoDb().then((mongoDb) => {
    if (!mongoDb) {
      throw new HttpError(503, 'MongoDB is not configured. Set MONGODB_URL first.');
    }

    return mongoDb;
  });
}

async function createServiceListing({
  providerUserId,
  providerRole,
  title,
  category,
  municipality,
  description,
  priceMin,
  priceMax,
  estimatedDuration,
  requirements,
  availability,
  media,
}) {
  const provider = await findUserById(providerUserId);
  assertApprovedProvider(provider, 'Only approved workers and agencies can publish service listings.');

  const mongoDb = await requireMongo();
  const listing = {
    providerUserId,
    providerRole,
    title,
    category,
    municipality,
    description,
    priceMin,
    priceMax,
    estimatedDuration,
    requirements,
    availability,
    media,
    status: 'active',
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const result = await mongoDb.collection('service_listings').insertOne(listing);

  return { id: result.insertedId.toString(), ...listing };
}

async function searchServiceListings({ category, municipality, keyword }) {
  const mongoDb = await requireMongo();
  const filters = { status: 'active' };

  if (category) filters.category = String(category);
  if (municipality) filters.municipality = String(municipality);
  if (keyword) {
    filters.$or = [
      { title: { $regex: String(keyword), $options: 'i' } },
      { description: { $regex: String(keyword), $options: 'i' } },
      { requirements: { $elemMatch: { $regex: String(keyword), $options: 'i' } } },
    ];
  }

  const listings = await mongoDb.collection('service_listings').find(filters).limit(30).toArray();
  const users = await listUsersByIds(listings.map((listing) => listing.providerUserId));
  const approvedUserIds = new Set(users.filter(isApprovedProvider).map((user) => user.id));
  const providerProfiles = await mongoDb.collection('provider_profiles').find({ userId: { $in: listings.map((listing) => listing.providerUserId) } }).toArray();
  const profileByUserId = new Map(providerProfiles.map((profile) => [profile.userId, profile]));
  const reviewSummaries = await listReviewSummariesForProviders(listings.map((listing) => listing.providerUserId));
  const reviewSummaryByUserId = new Map(reviewSummaries.map((summary) => [summary.providerUserId, summary]));

  return listings
    .filter((listing) => approvedUserIds.has(listing.providerUserId))
    .map((listing) => ({
      ...listing,
      providerDisplayName: profileByUserId.get(listing.providerUserId)?.displayName || 'Local provider',
      reviewSummary: reviewSummaryByUserId.get(listing.providerUserId) || { providerUserId: listing.providerUserId, count: 0, average: 0 },
      id: listing._id.toString(),
      _id: undefined,
    }));
}

async function listServiceListingsForProvider(providerUserId) {
  const mongoDb = await requireMongo();
  const listings = await mongoDb.collection('service_listings').find({ providerUserId, status: 'active' }).sort({ createdAt: -1 }).toArray();

  return listings.map((listing) => ({
    ...listing,
    id: listing._id.toString(),
    _id: undefined,
  }));
}

async function getServiceListingById(listingId) {
  const mongoDb = await requireMongo();

  if (!ObjectId.isValid(listingId)) {
    throw new HttpError(400, 'Invalid service listing id.');
  }

  const listing = await mongoDb.collection('service_listings').findOne({
    _id: new ObjectId(listingId),
    status: 'active',
  });

  if (!listing) {
    throw new HttpError(404, 'Service listing not found.');
  }

  const provider = await findUserById(listing.providerUserId);
  assertApprovedProvider(provider, 'This provider is not currently approved.');

  return {
    ...listing,
    id: listing._id.toString(),
    _id: undefined,
  };
}

module.exports = {
  createServiceListing,
  getServiceListingById,
  listServiceListingsForProvider,
  searchServiceListings,
};
