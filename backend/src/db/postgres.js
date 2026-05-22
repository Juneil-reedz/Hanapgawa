const { Pool } = require('pg');

const { env } = require('../config/env');

let pool;
let readPool;

function _sslConfig() {
  return env.postgresSsl || env.nodeEnv === 'production' ? { rejectUnauthorized: false } : false;
}

function getPostgresPool() {
  if (!env.postgresUrl) {
    return null;
  }

  if (!pool) {
    pool = new Pool({
      connectionString: env.postgresUrl,
      ssl: _sslConfig(),
      max: 3,
      idleTimeoutMillis: 10000,
      connectionTimeoutMillis: 5000,
      keepAlive: true,
      allowExitOnIdle: true,
    });
    pool.on('error', (err) => {
      console.warn('Postgres write pool error (non-fatal):', err.message);
    });
  }

  return pool;
}

// Returns a read-replica pool when POSTGRES_READ_URL is configured,
// otherwise falls back to the write pool so the app works on single-node setups.
function getPostgresReadPool() {
  if (!env.postgresUrl) {
    return null;
  }

  if (!env.postgresReadUrl) {
    return getPostgresPool();
  }

  if (!readPool) {
    readPool = new Pool({
      connectionString: env.postgresReadUrl,
      ssl: _sslConfig(),
      max: 3,
      idleTimeoutMillis: 10000,
      connectionTimeoutMillis: 5000,
      keepAlive: true,
      allowExitOnIdle: true,
    });
    readPool.on('error', (err) => {
      console.warn('Postgres read pool error (non-fatal):', err.message);
    });
  }

  return readPool;
}

// Creates yearly range partitions for tables that support them.
// Silently skips tables that exist but are not partitioned (i.e. existing deployments).
async function _ensurePartitions(client) {
  const partitionedTables = ['social_posts', 'notifications', 'conversation_messages'];

  for (const table of partitionedTables) {
    const check = await client.query(
      `SELECT relkind FROM pg_class WHERE relname = $1 AND relkind = 'p'`,
      [table],
    );

    if (!check.rows.length) continue; // regular table — skip

    for (const year of [2024, 2025, 2026, 2027]) {
      await client.query(`
        CREATE TABLE IF NOT EXISTS ${table}_${year}
          PARTITION OF ${table}
          FOR VALUES FROM ('${year}-01-01') TO ('${year + 1}-01-01')
      `);
    }

    await client.query(`
      CREATE TABLE IF NOT EXISTS ${table}_default
        PARTITION OF ${table} DEFAULT
    `);
  }
}

async function ensurePostgresSchema() {
  const client = getPostgresPool();

  if (!client) {
    return { configured: false, initialized: false };
  }

  await client.query(`
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('user', 'client', 'worker', 'agency', 'admin')),
      full_name TEXT NOT NULL,
      email_verified_at TIMESTAMPTZ,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check`);
  await client.query(`ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('user', 'client', 'worker', 'agency', 'admin'))`).catch(() => {});
  await client.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check`);
  await client.query(`ALTER TABLE users ADD CONSTRAINT users_status_check CHECK (status IN ('pending', 'approved', 'rejected', 'suspended', 'banned'))`).catch(() => {});

  await client.query(`
    CREATE TABLE IF NOT EXISTS email_verification_codes (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code_hash TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      used_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS bookings (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      client_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      service_listing_id TEXT,
      service_category TEXT NOT NULL,
      municipality TEXT NOT NULL,
      location_details TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      previous_status TEXT,
      scheduled_at TIMESTAMPTZ,
      provider_completed_at TIMESTAMPTZ,
      client_confirmed_at TIMESTAMPTZ,
      cancellation_requested_at TIMESTAMPTZ,
      cancellation_requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS service_listing_id TEXT`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS location_details TEXT NOT NULL DEFAULT ''`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS previous_status TEXT`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS provider_completed_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_confirmed_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_requested_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_requested_by UUID REFERENCES users(id) ON DELETE SET NULL`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reschedule_note TEXT`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS rescheduled_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_reason TEXT`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS from_offer BOOLEAN NOT NULL DEFAULT FALSE`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'direct_booking'`);
  await client.query(`UPDATE bookings SET from_offer = TRUE WHERE service_listing_id IS NULL AND from_offer = FALSE`);
  await client.query(`UPDATE bookings SET source = 'job_application' WHERE from_offer = TRUE AND source = 'direct_booking'`);
  await client.query(`ALTER TABLE bookings DROP COLUMN IF EXISTS from_offer`);
  // Rename provider_user_id to worker_user_id if not already done
  await client.query(`
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bookings' AND column_name = 'provider_user_id'
      ) THEN
        ALTER TABLE bookings RENAME COLUMN provider_user_id TO worker_user_id;
      END IF;
    END $$
  `);
  await client.query('ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_source_check');
  await client.query(`
    ALTER TABLE bookings
    ADD CONSTRAINT bookings_source_check CHECK (source IN ('direct_booking', 'job_application', 'service_booking'))
  `);

  await client.query('ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_status_check');
  await client.query(`
    ALTER TABLE bookings
    ADD CONSTRAINT bookings_status_check CHECK (
      status IN (
        'pending',
        'accepted',
        'in_progress',
        'completion_requested',
        'completed',
        'rejected',
        'cancellation_requested',
        'cancelled'
      )
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS reviews (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
      reviewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      comment TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(`ALTER TABLE reviews DROP CONSTRAINT IF EXISTS reviews_booking_id_key`);
  await client.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS reviews_booking_reviewer_unique
    ON reviews (booking_id, reviewer_user_id)
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS agency_worker_applications (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      agency_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      worker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
      message TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (agency_user_id, worker_user_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS service_categories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name TEXT UNIQUE NOT NULL,
      slug TEXT UNIQUE NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      icon TEXT NOT NULL DEFAULT 'briefcase-outline',
      active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      client_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      service_listing_id TEXT,
      booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
      last_message_preview TEXT NOT NULL DEFAULT '',
      last_sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(`ALTER TABLE conversations ADD COLUMN IF NOT EXISTS last_sender_id UUID REFERENCES users(id) ON DELETE SET NULL`);

  // Partitioned by created_at so old messages can be archived to cheaper storage.
  // New deployments get the partitioned structure; existing deployments keep
  // their regular table — _ensurePartitions() silently skips non-partitioned tables.
  await client.query(`
    CREATE TABLE IF NOT EXISTS conversation_messages (
      id UUID NOT NULL DEFAULT gen_random_uuid(),
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      message TEXT NOT NULL,
      image TEXT,
      reply_to_message_id UUID,
      forwarded_from_message_id UUID,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (id, created_at)
    ) PARTITION BY RANGE (created_at)
  `);

  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS image TEXT`);
  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS voice_message TEXT`);
  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS voice_duration INTEGER NOT NULL DEFAULT 0`);
  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS reply_to_message_id UUID`);
  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS forwarded_from_message_id UUID`);
  await client.query(`ALTER TABLE conversation_messages ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT FALSE`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS conversation_nicknames (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      nickname TEXT NOT NULL,
      set_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (conversation_id, target_user_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS reports (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
      booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
      reason TEXT NOT NULL,
      details TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    INSERT INTO service_categories (name, slug, description, icon)
    VALUES
      ('Carpentry', 'carpentry', 'Woodwork, repairs, and custom furniture.', 'hammer-outline'),
      ('Home Services', 'home-services', 'General household maintenance and repair.', 'home-outline'),
      ('Electrical', 'electrical', 'Wiring, outlet, and appliance support.', 'flash-outline'),
      ('Plumbing', 'plumbing', 'Water system repair and maintenance.', 'water-outline'),
      ('Tutoring', 'tutoring', 'Academic and skills-based tutoring.', 'school-outline'),
      ('Beauty', 'beauty', 'Beauty and personal care services.', 'sparkles-outline')
    ON CONFLICT (slug) DO NOTHING
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS job_posts (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      client_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      post_type TEXT NOT NULL DEFAULT 'looking_for_worker' CHECK (post_type IN ('looking_for_worker', 'offering_service')),
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      municipality TEXT NOT NULL,
      location_details TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL,
      budget_min NUMERIC(12, 2),
      budget_max NUMERIC(12, 2),
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'assigned', 'completed', 'cancelled')),
      assigned_provider_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
      scheduled_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS allow_direct_booking BOOLEAN NOT NULL DEFAULT FALSE`);
  await client.query(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS workers_needed INTEGER NOT NULL DEFAULT 1`);
  await client.query(`UPDATE job_posts SET workers_needed = 1 WHERE workers_needed IS NULL OR workers_needed < 1`);
  await client.query(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS post_type TEXT NOT NULL DEFAULT 'looking_for_worker'`);
  await client.query('ALTER TABLE job_posts DROP CONSTRAINT IF EXISTS job_posts_post_type_check');
  await client.query(`UPDATE job_posts SET post_type = 'looking_for_worker' WHERE post_type = 'seeking_worker'`);
  await client.query(`UPDATE job_posts SET post_type = 'offering_service' WHERE post_type = 'seeking_client'`);
  await client.query(`
    ALTER TABLE job_posts
    ADD CONSTRAINT job_posts_post_type_check CHECK (post_type IN ('looking_for_worker', 'offering_service'))
  `);

  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS job_post_id UUID REFERENCES job_posts(id) ON DELETE SET NULL`);
  await client.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reposted_job_id UUID REFERENCES job_posts(id) ON DELETE SET NULL`);

  await client.query(`ALTER TABLE reports ADD COLUMN IF NOT EXISTS content_type TEXT`);
  await client.query(`ALTER TABLE reports ADD COLUMN IF NOT EXISTS content_id TEXT`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS job_offers (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      job_post_id UUID NOT NULL REFERENCES job_posts(id) ON DELETE CASCADE,
      provider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      message TEXT NOT NULL DEFAULT '',
      proposed_price NUMERIC(12, 2),
      media JSONB NOT NULL DEFAULT '[]'::jsonb,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (job_post_id, provider_user_id)
    )
  `);

  await client.query(`ALTER TABLE job_offers ADD COLUMN IF NOT EXISTS media JSONB NOT NULL DEFAULT '[]'::jsonb`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS follows (
      follower_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (follower_user_id, following_user_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS post_reactions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_type TEXT NOT NULL,
      item_id TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (user_id, item_type, item_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS post_comments (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL DEFAULT '',
      item_type TEXT NOT NULL,
      item_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(`ALTER TABLE post_comments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE post_comments ADD COLUMN IF NOT EXISTS parent_comment_id UUID`);
  await client.query(`ALTER TABLE post_comments ADD COLUMN IF NOT EXISTS gif_url TEXT`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS post_comment_reactions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      comment_id UUID NOT NULL REFERENCES post_comments(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (user_id, comment_id)
    )
  `);

  // Partitioned by created_at for efficient time-range queries and archiving.
  // Reactions and comments reference social_posts via item_id TEXT (no FK),
  // so the compound PK (id, created_at) does not break any existing constraints.
  await client.query(`
    CREATE TABLE IF NOT EXISTS social_posts (
      id UUID NOT NULL DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL DEFAULT '',
      profile_pic TEXT,
      body TEXT NOT NULL,
      image TEXT,
      video TEXT,
      metadata JSONB,
      privacy TEXT NOT NULL DEFAULT 'Public',
      scheduled_at TIMESTAMPTZ,
      shared_from_type TEXT,
      shared_from_id TEXT,
      shared_snapshot JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (id, created_at)
    ) PARTITION BY RANGE (created_at)
  `);

  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS image TEXT`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS video TEXT`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS metadata JSONB`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS privacy TEXT NOT NULL DEFAULT 'Public'`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS shared_from_type TEXT`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS shared_from_id TEXT`);
  await client.query(`ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS shared_snapshot JSONB`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS user_photos (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      image TEXT NOT NULL,
      caption TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS stories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL DEFAULT '',
      profile_pic TEXT,
      body TEXT NOT NULL DEFAULT '',
      image TEXT,
      video TEXT,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      privacy TEXT NOT NULL DEFAULT 'Public',
      expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS story_reactions (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reaction TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id, user_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS story_views (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id, user_id)
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS user_profiles (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      bio TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      school TEXT NOT NULL DEFAULT '',
      birthday TEXT NOT NULL DEFAULT '',
      work TEXT NOT NULL DEFAULT '',
      current_city TEXT NOT NULL DEFAULT '',
      hometown TEXT NOT NULL DEFAULT '',
      relationship_status TEXT NOT NULL DEFAULT '',
      featured JSONB NOT NULL DEFAULT '[]'::jsonb,
      profile_pic TEXT,
      cover_pic TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS current_city TEXT NOT NULL DEFAULT ''`);
  await client.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS hometown TEXT NOT NULL DEFAULT ''`);
  await client.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS relationship_status TEXT NOT NULL DEFAULT ''`);
  await client.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS featured JSONB NOT NULL DEFAULT '[]'::jsonb`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS featured_stories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      story_id UUID,
      body TEXT NOT NULL DEFAULT '',
      image TEXT,
      video TEXT,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      full_name TEXT NOT NULL DEFAULT '',
      profile_pic TEXT,
      original_created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      featured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(user_id, story_id)
    )
  `);

  // Partitioned by created_at — nothing references notifications.id as a foreign key.
  await client.query(`
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID NOT NULL DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
      actor_name TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      link_type TEXT,
      link_id TEXT,
      read_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (id, created_at)
    ) PARTITION BY RANGE (created_at)
  `);

  await client.query(`CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON notifications (user_id, created_at DESC)`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS app_feedback (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      comment TEXT NOT NULL DEFAULT '',
      app_version TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS user_device_tokens (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token TEXT NOT NULL,
      platform TEXT NOT NULL DEFAULT 'android',
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, token)
    )
  `);

  await _ensurePartitions(client);

  return { configured: true, initialized: true };
}

async function checkPostgresHealth() {
  const client = getPostgresPool();

  if (!client) {
    return { configured: false, healthy: false };
  }

  await client.query('SELECT 1');
  return { configured: true, healthy: true };
}

async function closePostgresPool() {
  const tasks = [];

  if (pool) {
    tasks.push(pool.end().then(() => { pool = null; }));
  }

  if (readPool && readPool !== pool) {
    tasks.push(readPool.end().then(() => { readPool = null; }));
  }

  await Promise.all(tasks);
}

module.exports = {
  ensurePostgresSchema,
  checkPostgresHealth,
  getPostgresPool,
  getPostgresReadPool,
  closePostgresPool,
};
