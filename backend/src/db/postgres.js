const { Pool } = require('pg');

const { env } = require('../config/env');

let pool;

function getPostgresPool() {
  if (!env.postgresUrl) {
    return null;
  }

  if (!pool) {
    pool = new Pool({
      connectionString: env.postgresUrl,
      ssl: env.postgresSsl || env.nodeEnv === 'production' ? { rejectUnauthorized: false } : false,
    });
  }

  return pool;
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
      role TEXT NOT NULL CHECK (role IN ('client', 'worker', 'agency', 'admin')),
      full_name TEXT NOT NULL,
      email_verified_at TIMESTAMPTZ,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ`);

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
      booking_id UUID UNIQUE NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
      reviewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      comment TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
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
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS conversation_messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      message TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
      post_type TEXT NOT NULL DEFAULT 'seeking_worker' CHECK (post_type IN ('seeking_worker', 'seeking_client')),
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

  await client.query(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS post_type TEXT NOT NULL DEFAULT 'seeking_worker'`);
  await client.query('ALTER TABLE job_posts DROP CONSTRAINT IF EXISTS job_posts_post_type_check');
  await client.query(`
    ALTER TABLE job_posts
    ADD CONSTRAINT job_posts_post_type_check CHECK (post_type IN ('seeking_worker', 'seeking_client'))
  `);

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

module.exports = {
  ensurePostgresSchema,
  checkPostgresHealth,
  getPostgresPool,
};
