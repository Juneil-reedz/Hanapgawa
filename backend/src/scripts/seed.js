const bcrypt = require('bcrypt');

const { ensureMongoCollections, getMongoDb } = require('../db/mongo');
const { ensurePostgresSchema, getPostgresPool } = require('../db/postgres');
const { invalidateProviderSearchCache } = require('../lib/provider-search-cache');

const DEMO_USERS = [
  {
    email: 'admin@hanapgawa.demo',
    password: 'Password123!',
    role: 'admin',
    fullName: 'HanapGawa Admin',
    status: 'approved',
  },
];

async function resetDemoUsers(pool, mongoDb) {
  const existingUsers = await pool.query('SELECT id, email FROM users WHERE email = ANY($1)', [
    DEMO_USERS.map((user) => user.email),
  ]);

  const existingIds = existingUsers.rows.map((user) => user.id);

  if (existingIds.length > 0) {
    await mongoDb.collection('provider_profiles').deleteMany({ userId: { $in: existingIds } });
    await mongoDb.collection('service_listings').deleteMany({ providerUserId: { $in: existingIds } });
    await pool.query('DELETE FROM users WHERE id = ANY($1)', [existingIds]);
  }
}

async function seedUsers(pool) {
  const usersByEmail = {};

  for (const user of DEMO_USERS) {
    const passwordHash = await bcrypt.hash(user.password, 10);
    const result = await pool.query(
      `
        INSERT INTO users (email, password_hash, role, full_name, status, email_verified_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        RETURNING id, email, role, full_name AS "fullName", status, email_verified_at AS "emailVerifiedAt"
      `,
      [user.email, passwordHash, user.role, user.fullName, user.status],
    );

    usersByEmail[user.email] = result.rows[0];
  }

  return usersByEmail;
}


async function main() {
  const pool = getPostgresPool();
  const mongoDb = await getMongoDb();

  if (!pool) {
    throw new Error('POSTGRES_URL is required to run the seed script.');
  }

  if (!mongoDb) {
    throw new Error('MONGODB_URL is required to run the seed script.');
  }

  await ensurePostgresSchema();
  await ensureMongoCollections();
  await resetDemoUsers(pool, mongoDb);

  const usersByEmail = await seedUsers(pool);

  await invalidateProviderSearchCache();

  console.log('Seed complete. Demo accounts:');

  for (const user of DEMO_USERS) {
    console.log(`- ${user.role}: ${user.email} / ${user.password}`);
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('Seed failed:', error.message);
      process.exit(1);
    });
}

module.exports = { main };
