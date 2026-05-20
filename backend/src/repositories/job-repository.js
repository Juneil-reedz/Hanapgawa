const { getPostgresPool, getPostgresReadPool } = require('../db/postgres');
const { HttpError } = require('../lib/http-error');

function requirePostgres() {
  const pool = getPostgresPool();
  if (!pool) throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  return pool;
}

function requirePostgresRead() {
  const pool = getPostgresReadPool();
  if (!pool) throw new HttpError(503, 'PostgreSQL is not configured. Set POSTGRES_URL first.');
  return pool;
}

const jobSelect = `
  jp.id,
  jp.client_user_id AS "clientUserId",
  client.full_name AS "clientFullName",
  jp.post_type AS "postType",
  jp.title,
  jp.category,
  jp.municipality,
  jp.location_details AS "locationDetails",
  jp.description,
  jp.budget_min AS "budgetMin",
  jp.budget_max AS "budgetMax",
  jp.allow_direct_booking AS "allowDirectBooking",
  jp.status,
  (SELECT COUNT(*)::int FROM job_offers offers WHERE offers.job_post_id = jp.id) AS "offerCount",
  (SELECT COUNT(*)::int FROM job_offers offers WHERE offers.job_post_id = jp.id AND offers.status = 'pending') AS "pendingOfferCount",
  jp.assigned_provider_user_id AS "assignedProviderUserId",
  provider.full_name AS "assignedProviderFullName",
  jp.scheduled_at AS "scheduledAt",
  jp.created_at AS "createdAt",
  jp.updated_at AS "updatedAt"
`;

const offerSelect = `
  jo.id,
  jo.job_post_id AS "jobPostId",
  jo.provider_user_id AS "providerUserId",
  provider.full_name AS "providerName",
  jo.message,
  jo.proposed_price AS "proposedPrice",
  jo.media,
  jo.status,
  jo.created_at AS "createdAt",
  jo.updated_at AS "updatedAt"
`;

async function createJobPost({ clientUserId, postType, title, category, municipality, locationDetails, description, budgetMin, budgetMax, scheduledAt, allowDirectBooking }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO job_posts (
        client_user_id,
        post_type,
        title,
        category,
        municipality,
        location_details,
        description,
        budget_min,
        budget_max,
        scheduled_at,
        allow_direct_booking
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING
        id,
        client_user_id AS "clientUserId",
        post_type AS "postType",
        title,
        category,
        municipality,
        location_details AS "locationDetails",
        description,
        budget_min AS "budgetMin",
        budget_max AS "budgetMax",
        allow_direct_booking AS "allowDirectBooking",
        status,
        0 AS "offerCount",
        assigned_provider_user_id AS "assignedProviderUserId",
        scheduled_at AS "scheduledAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [clientUserId, postType, title, category, municipality, locationDetails || '', description, budgetMin ?? null, budgetMax ?? null, scheduledAt || null, allowDirectBooking ?? false],
  );

  return result.rows[0];
}

async function updateJobPost(jobPostId, { postType, title, category, municipality, locationDetails, description, budgetMin, budgetMax, scheduledAt, allowDirectBooking }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      UPDATE job_posts
      SET
        post_type = $2,
        title = $3,
        category = $4,
        municipality = $5,
        location_details = $6,
        description = $7,
        budget_min = $8,
        budget_max = $9,
        scheduled_at = $10,
        allow_direct_booking = $11,
        updated_at = NOW()
      WHERE id = $1
      RETURNING
        id,
        client_user_id AS "clientUserId",
        post_type AS "postType",
        title,
        category,
        municipality,
        location_details AS "locationDetails",
        description,
        budget_min AS "budgetMin",
        budget_max AS "budgetMax",
        allow_direct_booking AS "allowDirectBooking",
        status,
        (SELECT COUNT(*)::int FROM job_offers offers WHERE offers.job_post_id = job_posts.id) AS "offerCount",
        assigned_provider_user_id AS "assignedProviderUserId",
        scheduled_at AS "scheduledAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [jobPostId, postType, title, category, municipality, locationDetails || '', description, budgetMin ?? null, budgetMax ?? null, scheduledAt || null, allowDirectBooking ?? false],
  );

  return result.rows[0] || null;
}

async function deleteJobPost(jobPostId) {
  const pool = requirePostgres();
  const result = await pool.query('DELETE FROM job_posts WHERE id = $1 RETURNING id', [jobPostId]);
  return result.rowCount > 0;
}

async function listJobPosts({ userId, role, status }) {
  const pool = requirePostgresRead();
  const values = [];
  const conditions = [];

  if (status) {
    values.push(status);
    conditions.push(`jp.status = $${values.length}`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const result = await pool.query(
    `
      SELECT ${jobSelect}
      FROM job_posts jp
      JOIN users client ON client.id = jp.client_user_id
      LEFT JOIN users provider ON provider.id = jp.assigned_provider_user_id
      ${where}
      ORDER BY jp.created_at DESC
      LIMIT 50
    `,
    values,
  );

  return result.rows;
}

async function findJobPostById(jobPostId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `
      SELECT ${jobSelect}
      FROM job_posts jp
      JOIN users client ON client.id = jp.client_user_id
      LEFT JOIN users provider ON provider.id = jp.assigned_provider_user_id
      WHERE jp.id = $1
    `,
    [jobPostId],
  );

  return result.rows[0] || null;
}

async function createJobOffer({ jobPostId, providerUserId, message, proposedPrice, media }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `
      INSERT INTO job_offers (job_post_id, provider_user_id, message, proposed_price, media)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (job_post_id, provider_user_id)
      DO UPDATE SET message = EXCLUDED.message, proposed_price = EXCLUDED.proposed_price, media = EXCLUDED.media, status = 'pending', updated_at = NOW()
      RETURNING
        id,
        job_post_id AS "jobPostId",
        provider_user_id AS "providerUserId",
        message,
        proposed_price AS "proposedPrice",
        media,
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `,
    [jobPostId, providerUserId, message || '', proposedPrice ?? null, JSON.stringify(media || [])],
  );

  return result.rows[0];
}

async function listOffersForJob(jobPostId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `
      SELECT ${offerSelect}
      FROM job_offers jo
      JOIN users provider ON provider.id = jo.provider_user_id
      WHERE jo.job_post_id = $1
      ORDER BY jo.created_at DESC
    `,
    [jobPostId],
  );

  return result.rows;
}

async function listOffersForProvider(providerUserId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `
      SELECT
        ${offerSelect},
        jp.title AS "jobTitle",
        jp.category AS "jobCategory",
        jp.municipality AS "jobMunicipality"
      FROM job_offers jo
      JOIN users provider ON provider.id = jo.provider_user_id
      JOIN job_posts jp ON jp.id = jo.job_post_id
      WHERE jo.provider_user_id = $1
      ORDER BY jo.created_at DESC
    `,
    [providerUserId],
  );

  return result.rows;
}

async function findJobOfferById(offerId) {
  const pool = requirePostgresRead();
  const result = await pool.query(
    `
      SELECT ${offerSelect}
      FROM job_offers jo
      JOIN users provider ON provider.id = jo.provider_user_id
      WHERE jo.id = $1
    `,
    [offerId],
  );

  return result.rows[0] || null;
}

async function acceptJobOffer({ jobPostId, offerId }) {
  const pool = requirePostgres();
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const offerResult = await client.query(
      `
        UPDATE job_offers
        SET status = 'accepted', updated_at = NOW()
        WHERE id = $1 AND job_post_id = $2 AND status = 'pending'
        RETURNING
          id,
          job_post_id AS "jobPostId",
          provider_user_id AS "providerUserId",
          message,
          proposed_price AS "proposedPrice",
          media,
          status,
          created_at AS "createdAt",
          updated_at AS "updatedAt"
      `,
      [offerId, jobPostId],
    );

    const offer = offerResult.rows[0] || null;
    if (!offer) {
      await client.query('ROLLBACK');
      return null;
    }

    await client.query(
      `
        UPDATE job_offers
        SET status = 'rejected', updated_at = NOW()
        WHERE job_post_id = $1 AND id <> $2 AND status = 'pending'
      `,
      [jobPostId, offerId],
    );

    const jobResult = await client.query(
      `
        UPDATE job_posts
        SET status = 'assigned', assigned_provider_user_id = $2, updated_at = NOW()
        WHERE id = $1 AND status = 'open'
        RETURNING
          id,
          client_user_id AS "clientUserId",
          post_type AS "postType",
          title,
          category,
          municipality,
          location_details AS "locationDetails",
          description,
          budget_min AS "budgetMin",
          budget_max AS "budgetMax",
          status,
          (SELECT COUNT(*)::int FROM job_offers offers WHERE offers.job_post_id = job_posts.id) AS "offerCount",
          assigned_provider_user_id AS "assignedProviderUserId",
          scheduled_at AS "scheduledAt",
          created_at AS "createdAt",
          updated_at AS "updatedAt"
      `,
      [jobPostId, offer.providerUserId],
    );

    const jobPost = jobResult.rows[0] || null;
    if (!jobPost) {
      await client.query('ROLLBACK');
      return null;
    }

    await client.query('COMMIT');
    return { jobPost, offer };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function declineJobOffer({ jobPostId, offerId }) {
  const pool = requirePostgres();
  const result = await pool.query(
    `UPDATE job_offers SET status = 'declined', updated_at = NOW()
     WHERE id = $1 AND job_post_id = $2 AND status = 'pending'
     RETURNING id, job_post_id AS "jobPostId", provider_user_id AS "providerUserId",
               status, created_at AS "createdAt"`,
    [offerId, jobPostId],
  );
  return result.rows[0] || null;
}

module.exports = {
  acceptJobOffer,
  createJobOffer,
  createJobPost,
  declineJobOffer,
  deleteJobPost,
  findJobOfferById,
  findJobPostById,
  listJobPosts,
  listOffersForJob,
  listOffersForProvider,
  updateJobPost,
};
