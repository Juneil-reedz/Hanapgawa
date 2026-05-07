const { getMongoDb } = require('../db/mongo');
const { getPostgresPool } = require('../db/postgres');

// ── Helpers ────────────────────────────────────────────────────────────

function getPool() {
  return getPostgresPool(); // may be null — callers handle gracefully
}

async function getMongo() {
  try { return await getMongoDb(); } catch { return null; }
}

// ── Public newsfeed ────────────────────────────────────────────────────

async function getPublicFeed({ limit = 40 } = {}) {
  const items = [];
  const perSource = Math.ceil(limit / 3);

  // 1. Recent approved service listings (MongoDB)
  try {
    const mongo = await getMongo();
    if (mongo) {
      const listings = await mongo
        .collection('service_listings')
        .find({ status: 'active' })
        .sort({ createdAt: -1 })
        .limit(perSource)
        .toArray();

      const profileDocs = await mongo
        .collection('provider_profiles')
        .find({ userId: { $in: listings.map((l) => l.providerUserId) } })
        .toArray();
      const profileMap = new Map(profileDocs.map((p) => [p.userId, p]));

      for (const l of listings) {
        const profile = profileMap.get(l.providerUserId);
        items.push({
          type: 'listing',
          id: l._id.toString(),
          createdAt: l.createdAt,
          listing: {
            id: l._id.toString(),
            providerUserId: l.providerUserId,
            providerRole: l.providerRole,
            providerDisplayName: profile?.displayName || 'Local Provider',
            title: l.title,
            category: l.category,
            municipality: l.municipality,
            description: l.description,
            priceMin: l.priceMin,
            priceMax: l.priceMax,
            estimatedDuration: l.estimatedDuration,
            requirements: l.requirements || [],
            availability: l.availability || [],
            media: l.media || [],
          },
        });
      }
    }
  } catch {
    // MongoDB unavailable — skip listings
  }

  // 2. Recent open job posts (PostgreSQL)
  try {
    const pool = getPool();
    if (pool) {
      const result = await pool.query(
        `
          SELECT
            jp.id,
            jp.client_user_id AS "clientUserId",
            u.full_name AS "clientFullName",
            jp.title,
            jp.category,
            jp.municipality,
            jp.description,
            jp.budget_min AS "budgetMin",
            jp.budget_max AS "budgetMax",
            jp.status,
            (SELECT COUNT(*)::int FROM job_offers jo WHERE jo.job_post_id = jp.id) AS "offerCount",
            jp.created_at AS "createdAt"
          FROM job_posts jp
          LEFT JOIN users u ON u.id = jp.client_user_id
          WHERE jp.status = 'open'
          ORDER BY jp.created_at DESC
          LIMIT $1
        `,
        [perSource],
      );

      for (const job of result.rows) {
        items.push({
          type: 'job',
          id: job.id,
          createdAt: job.createdAt,
          job,
        });
      }
    }
  } catch {
    // PostgreSQL unavailable — skip jobs
  }

  // 3. Recent reviews (PostgreSQL)
  try {
    const pool = getPool();
    if (pool) {
      const result = await pool.query(
        `
          SELECT
            r.id,
            r.provider_user_id AS "providerUserId",
            prov.full_name AS "providerName",
            r.rating,
            r.comment,
            r.created_at AS "createdAt"
          FROM reviews r
          LEFT JOIN users prov ON prov.id = r.provider_user_id
          ORDER BY r.created_at DESC
          LIMIT $1
        `,
        [perSource],
      );

      for (const review of result.rows) {
        items.push({
          type: 'review',
          id: review.id,
          createdAt: review.createdAt,
          review,
        });
      }
    }
  } catch {
    // PostgreSQL unavailable — skip reviews
  }

  // Merge and sort by createdAt desc
  items.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  return items.slice(0, limit);
}

// ── Personal timeline ──────────────────────────────────────────────────

async function getUserTimeline({ userId, role, limit = 50 }) {
  const events = [];
  const pool = getPool();

  if (!pool) return [];

  // 1. User's bookings (client or provider)
  try {
    const result = await pool.query(
      `
        SELECT
          b.id,
          b.service_category AS "serviceCategory",
          b.municipality,
          b.status,
          b.created_at AS "createdAt",
          b.updated_at AS "updatedAt",
          CASE WHEN b.client_user_id = $1 THEN 'client' ELSE 'provider' END AS perspective
        FROM bookings b
        WHERE b.client_user_id = $1 OR b.provider_user_id = $1
        ORDER BY b.updated_at DESC
        LIMIT $2
      `,
      [userId, Math.ceil(limit / 3)],
    );

    for (const b of result.rows) {
      events.push({
        type: 'booking',
        id: b.id,
        createdAt: b.updatedAt,
        title: b.serviceCategory,
        subtitle: `${b.municipality} · ${b.perspective === 'client' ? 'You hired' : 'You were hired'}`,
        status: b.status,
      });
    }
  } catch {
    // ignore
  }

  // 2. Reviews submitted or received
  try {
    const col = role === 'client' ? 'reviewer_user_id' : 'provider_user_id';
    const result = await pool.query(
      `
        SELECT
          r.id,
          r.rating,
          r.comment,
          r.provider_user_id AS "providerUserId",
          prov.full_name AS "providerName",
          r.created_at AS "createdAt"
        FROM reviews r
        LEFT JOIN users prov ON prov.id = r.provider_user_id
        WHERE r.${col} = $1
        ORDER BY r.created_at DESC
        LIMIT $2
      `,
      [userId, Math.ceil(limit / 4)],
    );

    for (const r of result.rows) {
      events.push({
        type: 'review',
        id: r.id,
        createdAt: r.createdAt,
        title: role === 'client' ? `You rated ${r.providerName || 'a provider'}` : `${r.providerName || 'Client'} reviewed you`,
        subtitle: `${'★'.repeat(r.rating)}${'☆'.repeat(5 - r.rating)} · ${r.comment ? r.comment.slice(0, 60) + (r.comment.length > 60 ? '…' : '') : 'No comment'}`,
        status: `${r.rating}/5`,
      });
    }
  } catch {
    // ignore
  }

  // 3a. Job posts (clients)
  if (role === 'client') {
    try {
      const result = await pool.query(
        `
          SELECT
            jp.id,
            jp.title,
            jp.category,
            jp.status,
            (SELECT COUNT(*)::int FROM job_offers jo WHERE jo.job_post_id = jp.id) AS "offerCount",
            jp.created_at AS "createdAt",
            jp.updated_at AS "updatedAt"
          FROM job_posts jp
          WHERE jp.client_user_id = $1
          ORDER BY jp.updated_at DESC
          LIMIT $2
        `,
        [userId, Math.ceil(limit / 4)],
      );

      for (const jp of result.rows) {
        events.push({
          type: 'job_post',
          id: jp.id,
          createdAt: jp.updatedAt,
          title: jp.title,
          subtitle: `${jp.category} · ${jp.offerCount} offer${jp.offerCount === 1 ? '' : 's'}`,
          status: jp.status,
        });
      }
    } catch {
      // ignore
    }
  }

  // 3b. Job offers (workers/agencies)
  if (role === 'worker' || role === 'agency') {
    try {
      const result = await pool.query(
        `
          SELECT
            jo.id,
            jp.title AS "jobTitle",
            jp.category AS "jobCategory",
            jo.proposed_price AS "proposedPrice",
            jo.status,
            jo.created_at AS "createdAt",
            jo.updated_at AS "updatedAt"
          FROM job_offers jo
          JOIN job_posts jp ON jp.id = jo.job_post_id
          WHERE jo.provider_user_id = $1
          ORDER BY jo.updated_at DESC
          LIMIT $2
        `,
        [userId, Math.ceil(limit / 4)],
      );

      for (const jo of result.rows) {
        events.push({
          type: 'job_offer',
          id: jo.id,
          createdAt: jo.updatedAt,
          title: `Offer on: ${jo.jobTitle}`,
          subtitle: `${jo.jobCategory}${jo.proposedPrice ? ` · P${jo.proposedPrice}` : ''}`,
          status: jo.status,
        });
      }
    } catch {
      // ignore
    }
  }

  events.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  return events.slice(0, limit);
}

module.exports = { getPublicFeed, getUserTimeline };
