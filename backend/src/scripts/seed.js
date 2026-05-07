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
  {
    email: 'client@hanapgawa.demo',
    password: 'Password123!',
    role: 'client',
    fullName: 'Amina Client',
    status: 'approved',
  },
  {
    email: 'worker@hanapgawa.demo',
    password: 'Password123!',
    role: 'worker',
    fullName: 'Jamal Carpenter',
    status: 'approved',
  },
  {
    email: 'agency@hanapgawa.demo',
    password: 'Password123!',
    role: 'agency',
    fullName: 'Tawi Service Agency',
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

async function seedProviderProfiles(mongoDb, usersByEmail) {
  const worker = usersByEmail['worker@hanapgawa.demo'];
  const agency = usersByEmail['agency@hanapgawa.demo'];
  const now = new Date();

  await mongoDb.collection('provider_profiles').insertMany([
    {
      userId: worker.id,
      role: worker.role,
      displayName: 'Jamal Carpenter Services',
      category: 'Carpentry',
      municipality: 'Bongao',
      services: ['Custom shelves', 'Roof framing', 'Door repair'],
      portfolio: [
        {
          title: 'Market stall renovation',
          imageUrl: 'https://example.com/demo/jamal-market-stall.jpg',
          description: 'Wood framing and finish work for a small market stall.',
        },
      ],
      createdAt: now,
      updatedAt: now,
    },
    {
      userId: agency.id,
      role: agency.role,
      displayName: 'Tawi Service Agency',
      category: 'Home Services',
      municipality: 'Bongao',
      services: ['Electrical repair', 'Plumbing', 'General maintenance'],
      portfolio: [
        {
          title: 'Multi-service response team',
          imageUrl: 'https://example.com/demo/tawi-agency-team.jpg',
          description: 'Agency-managed field team for home repair and maintenance.',
        },
      ],
      createdAt: now,
      updatedAt: now,
    },
  ]);
}

async function seedServiceListings(mongoDb, usersByEmail) {
  const worker = usersByEmail['worker@hanapgawa.demo'];
  const agency = usersByEmail['agency@hanapgawa.demo'];
  const now = new Date();

  const result = await mongoDb.collection('service_listings').insertMany([
    {
      providerUserId: worker.id,
      providerRole: worker.role,
      title: 'Custom Shelf Repair and Installation',
      category: 'Carpentry',
      municipality: 'Bongao',
      description: 'Repair old wooden shelves or install custom-fit storage for kitchens, sari-sari stores, and study corners.',
      priceMin: 800,
      priceMax: 2500,
      estimatedDuration: '2 to 5 hours',
      requirements: ['Photos of the space', 'Preferred dimensions', 'Access to work area'],
      availability: ['Weekdays', 'Morning', 'Bongao proper'],
      media: [{ imageUrl: 'https://example.com/demo/shelf-repair.jpg', caption: 'Kitchen shelf upgrade' }],
      status: 'active',
      createdAt: now,
      updatedAt: now,
    },
    {
      providerUserId: agency.id,
      providerRole: agency.role,
      title: 'Home Electrical Safety Check',
      category: 'Electrical',
      municipality: 'Bongao',
      description: 'Agency-dispatched technician checks outlets, switches, and basic wiring concerns for homes and small shops.',
      priceMin: 1200,
      priceMax: 3200,
      estimatedDuration: '1 to 3 hours',
      requirements: ['List of faulty outlets', 'Site contact number', 'Preferred time window'],
      availability: ['Daily', 'Afternoon', 'Bongao and nearby barangays'],
      media: [{ imageUrl: 'https://example.com/demo/electrical-check.jpg', caption: 'Outlet inspection visit' }],
      status: 'active',
      createdAt: now,
      updatedAt: now,
    },
    {
      providerUserId: agency.id,
      providerRole: agency.role,
      title: 'Quick Plumbing Maintenance Visit',
      category: 'Plumbing',
      municipality: 'Bongao',
      description: 'Leak inspection, faucet replacement, and small pipe maintenance from an agency-managed repair team.',
      priceMin: 900,
      priceMax: 2800,
      estimatedDuration: '1 to 4 hours',
      requirements: ['Water issue summary', 'Accessible shutoff valve', 'Location pin or landmark'],
      availability: ['Daily', 'Morning', 'Emergency callout'],
      media: [{ imageUrl: 'https://example.com/demo/plumbing-service.jpg', caption: 'Pipe maintenance work' }],
      status: 'active',
      createdAt: now,
      updatedAt: now,
    },
  ]);

  const insertedIds = Object.values(result.insertedIds).map((id) => id.toString());

  return {
    shelfServiceId: insertedIds[0],
    electricalServiceId: insertedIds[1],
    plumbingServiceId: insertedIds[2],
  };
}

async function seedApplications(pool, usersByEmail) {
  const agency = usersByEmail['agency@hanapgawa.demo'];
  const worker = usersByEmail['worker@hanapgawa.demo'];

  await pool.query(
    `
      INSERT INTO agency_worker_applications (agency_user_id, worker_user_id, status, message)
      VALUES ($1, $2, 'approved', $3)
    `,
    [agency.id, worker.id, 'Join our approved home service team in Bongao.'],
  );
}

async function seedBookingsAndReviews(pool, usersByEmail, serviceIds) {
  const client = usersByEmail['client@hanapgawa.demo'];
  const worker = usersByEmail['worker@hanapgawa.demo'];
  const agency = usersByEmail['agency@hanapgawa.demo'];

  const completedBooking = await pool.query(
    `
      INSERT INTO bookings (
        client_user_id,
        provider_user_id,
        service_listing_id,
        service_category,
        municipality,
        location_details,
        notes,
        status,
        scheduled_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'completed', NOW() - INTERVAL '2 days')
      RETURNING id
    `,
    [client.id, worker.id, serviceIds.shelfServiceId, 'Carpentry', 'Bongao', 'Barangay Tubig Boh, near the market', 'Repair wooden kitchen shelves.'],
  );

  await pool.query(
    `
      INSERT INTO reviews (booking_id, reviewer_user_id, provider_user_id, rating, comment)
      VALUES ($1, $2, $3, $4, $5)
    `,
    [
      completedBooking.rows[0].id,
      client.id,
      worker.id,
      5,
      'Fast work, respectful service, and good craftsmanship.',
    ],
  );

  await pool.query(
    `
      INSERT INTO bookings (
        client_user_id,
        provider_user_id,
        service_listing_id,
        service_category,
        municipality,
        location_details,
        notes,
        status,
        scheduled_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'accepted', NOW() + INTERVAL '1 day')
    `,
    [client.id, agency.id, serviceIds.electricalServiceId, 'Home Services', 'Bongao', 'Near provincial capitol extension', 'Need a technician for electrical outlet inspection.'],
  );
}

async function seedConversationsAndReports(pool, usersByEmail, serviceIds) {
  const client = usersByEmail['client@hanapgawa.demo'];
  const agency = usersByEmail['agency@hanapgawa.demo'];

  const conversation = await pool.query(
    `
      INSERT INTO conversations (client_user_id, provider_user_id, service_listing_id, last_message_preview)
      VALUES ($1, $2, $3, $4)
      RETURNING id
    `,
    [client.id, agency.id, serviceIds.electricalServiceId, 'Is your team available this Friday afternoon?'],
  );

  await pool.query(
    `
      INSERT INTO conversation_messages (conversation_id, sender_user_id, message)
      VALUES
        ($1, $2, $3),
        ($1, $4, $5)
    `,
    [
      conversation.rows[0].id,
      client.id,
      'Is your team available this Friday afternoon?',
      agency.id,
      'Yes, we can reserve a technician if you confirm the exact address.',
    ],
  );

  await pool.query(
    `
      INSERT INTO reports (reporter_user_id, provider_user_id, reason, details, status)
      VALUES ($1, $2, $3, $4, 'pending')
    `,
    [client.id, agency.id, 'Late arrival', 'Demo dispute entry for admin review.'],
  );
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

  await seedProviderProfiles(mongoDb, usersByEmail);
  const serviceIds = await seedServiceListings(mongoDb, usersByEmail);
  await seedApplications(pool, usersByEmail);
  await seedBookingsAndReviews(pool, usersByEmail, serviceIds);
  await seedConversationsAndReports(pool, usersByEmail, serviceIds);
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
