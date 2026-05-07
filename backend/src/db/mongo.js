const { MongoClient } = require('mongodb');

const { env } = require('../config/env');

let client;
let db;

async function getMongoDb() {
  if (!env.mongodbUrl) {
    return null;
  }

  if (!client) {
    client = new MongoClient(env.mongodbUrl);
    await client.connect();
    db = client.db(env.mongodbDbName);
  }

  return db;
}

async function ensureMongoCollections() {
  const mongoDb = await getMongoDb();

  if (!mongoDb) {
    return { configured: false, initialized: false };
  }

  await mongoDb.createCollection('provider_profiles').catch((error) => {
    if (error.codeName !== 'NamespaceExists') {
      throw error;
    }
  });

  await mongoDb.createCollection('service_listings').catch((error) => {
    if (error.codeName !== 'NamespaceExists') {
      throw error;
    }
  });

  return { configured: true, initialized: true };
}

async function checkMongoHealth() {
  const mongoDb = await getMongoDb();

  if (!mongoDb) {
    return { configured: false, healthy: false };
  }

  await mongoDb.command({ ping: 1 });
  return { configured: true, healthy: true };
}

module.exports = {
  ensureMongoCollections,
  checkMongoHealth,
  getMongoDb,
};
