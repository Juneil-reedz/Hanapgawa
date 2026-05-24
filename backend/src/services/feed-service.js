const { getMongoDb } = require('../db/mongo');
const { getPostgresPool } = require('../db/postgres');

function getPool() {
  return getPostgresPool();
}

async function getMongo() {
  try { return await getMongoDb(); } catch { return null; }
}

async function getFollowedUserIds(userId) {
  if (!userId) return [];
  const pool = getPool();
  if (!pool) return [];
  try {
    const result = await pool.query(
      `SELECT following_user_id FROM follows WHERE follower_user_id = $1`,
      [userId],
    );
    return result.rows.map((r) => r.following_user_id);
  } catch { return []; }
}

async function attachInteractionCounts(items, userId = null) {
  if (!items.length) return;
  const pool = getPool();
  if (!pool) return;
  try {
    const ids = items.map((i) => i.id.toString());

    const likeResult = await pool.query(
      `SELECT item_type, item_id, COUNT(*)::int AS count
       FROM post_reactions WHERE item_id = ANY($1)
       GROUP BY item_type, item_id`,
      [ids],
    );
    const likeMap = new Map(likeResult.rows.map((r) => [`${r.item_type}:${r.item_id}`, r.count]));

    const commentResult = await pool.query(
      `SELECT item_type, item_id, COUNT(*)::int AS count
       FROM post_comments WHERE item_id = ANY($1)
       GROUP BY item_type, item_id`,
      [ids],
    );
    const commentMap = new Map(commentResult.rows.map((r) => [`${r.item_type}:${r.item_id}`, r.count]));

    let likedSet = new Set();
    if (userId) {
      const likedResult = await pool.query(
        `SELECT item_type, item_id FROM post_reactions WHERE user_id = $1 AND item_id = ANY($2)`,
        [userId, ids],
      );
      likedSet = new Set(likedResult.rows.map((r) => `${r.item_type}:${r.item_id}`));
    }

    for (const item of items) {
      const key = `${item.type}:${item.id}`;
      item.likeCount = likeMap.get(key) || 0;
      item.commentCount = commentMap.get(key) || 0;
      item.isLiked = likedSet.has(key);
    }
  } catch { /* counts default to 0 */ }
}

async function getPublicFeed({ limit = 40, userId = null } = {}) {
  const items = [];
  const perSource = Math.ceil(limit / 3);

  const followedIds = await getFollowedUserIds(userId);

  // 1. Recent approved service listings (MongoDB)
  try {
    const mongo = await getMongo();
    if (mongo) {
      const query = { status: 'active' };
      if (followedIds.length > 0) {
        // Include followed providers' listings even if not in the top N
        const followedListings = await mongo
          .collection('service_listings')
          .find({ providerUserId: { $in: followedIds } })
          .sort({ createdAt: -1 })
          .limit(10)
          .toArray();

        const generalListings = await mongo
          .collection('service_listings')
          .find(query)
          .sort({ createdAt: -1 })
          .limit(perSource)
          .toArray();

        const seen = new Set();
        const listings = [];
        for (const l of [...followedListings, ...generalListings]) {
          const key = l._id.toString();
          if (!seen.has(key)) { seen.add(key); listings.push(l); }
        }

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
            likeCount: 0,
            commentCount: 0,
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
      } else {
        const listings = await mongo
          .collection('service_listings')
          .find(query)
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
            likeCount: 0,
            commentCount: 0,
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
    }
  } catch {
    // MongoDB unavailable
  }

  // 2. Social posts (PostgreSQL)
  try {
    const pool = getPool();
    if (pool) {
      let socialQuery;
      let params;

      if (followedIds.length > 0) {
        socialQuery = `
          SELECT sp.id, sp.user_id AS "userId", sp.full_name AS "fullName",
                 COALESCE(up.profile_pic, sp.profile_pic) AS "profilePic",
                 sp.body, sp.image, sp.video, sp.metadata, sp.privacy,
                 sp.scheduled_at AS "scheduledAt",
                 sp.shared_from_type AS "sharedFromType",
                 sp.shared_from_id AS "sharedFromId",
                 sp.shared_snapshot AS "sharedSnapshot",
                 sp.created_at AS "createdAt"
          FROM social_posts sp
          LEFT JOIN user_profiles up ON up.user_id = sp.user_id
          WHERE (sp.user_id = ANY($2) OR sp.user_id = $3)
            AND (sp.scheduled_at IS NULL OR sp.scheduled_at <= NOW())
          ORDER BY sp.created_at DESC
          LIMIT $1
        `;
        params = [limit, followedIds, userId];
      } else {
        // No follows yet — show recent posts from all users so new users see content
        socialQuery = `
          SELECT sp.id, sp.user_id AS "userId", sp.full_name AS "fullName",
                 COALESCE(up.profile_pic, sp.profile_pic) AS "profilePic",
                 sp.body, sp.image, sp.video, sp.metadata, sp.privacy,
                 sp.scheduled_at AS "scheduledAt",
                 sp.shared_from_type AS "sharedFromType",
                 sp.shared_from_id AS "sharedFromId",
                 sp.shared_snapshot AS "sharedSnapshot",
                 sp.created_at AS "createdAt"
          FROM social_posts sp
          LEFT JOIN user_profiles up ON up.user_id = sp.user_id
          WHERE (sp.scheduled_at IS NULL OR sp.scheduled_at <= NOW())
          ORDER BY sp.created_at DESC
          LIMIT $1
        `;
        params = [limit];
      }

      const result = await pool.query(socialQuery, params);

      // Batch-check which authors the current user follows
      const authorIds = [...new Set(result.rows.map((p) => p.userId))];
      let followingAuthorIds = new Set();
      if (userId && authorIds.length > 0) {
        try {
          const fr = await pool.query(
            `SELECT following_user_id FROM follows
             WHERE follower_user_id = $1 AND following_user_id = ANY($2)`,
            [userId, authorIds],
          );
          followingAuthorIds = new Set(fr.rows.map((r) => r.following_user_id));
        } catch { /* ignore */ }
      }

      for (const post of result.rows) {
        items.push({
          type: 'post',
          id: post.id,
          createdAt: post.createdAt,
          likeCount: 0,
          commentCount: 0,
          isLiked: false,
          isFollowingAuthor: userId === post.userId || followingAuthorIds.has(post.userId),
          socialPost: post,
        });
      }
    }
  } catch {
    // PostgreSQL unavailable
  }

  // 3. Recent open job posts (PostgreSQL)
  try {
    const pool = getPool();
    if (pool) {
      const result = await pool.query(
        `SELECT jp.id,
                jp.client_user_id AS "clientUserId",
                u.full_name AS "clientFullName",
                jp.post_type AS "postType",
                jp.title, jp.category, jp.municipality, jp.description,
                jp.budget_min AS "budgetMin", jp.budget_max AS "budgetMax",
                jp.status,
                (SELECT COUNT(*)::int FROM job_offers jo WHERE jo.job_post_id = jp.id) AS "offerCount",
                jp.created_at AS "createdAt"
         FROM job_posts jp
         JOIN users u ON u.id = jp.client_user_id
         WHERE jp.status = 'open'
         ORDER BY jp.created_at DESC
         LIMIT $1`,
        [perSource],
      );
      for (const job of result.rows) {
        items.push({
          type: 'job',
          id: job.id,
          createdAt: job.createdAt,
          likeCount: 0,
          commentCount: 0,
          job,
        });
      }
    }
  } catch {
    // PostgreSQL unavailable
  }

  items.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  const sliced = items.slice(0, limit);

  await attachInteractionCounts(sliced, userId);

  return sliced;
}

async function getUserTimeline({ userId, role, limit = 50 }) {
  const events = [];
  const pool = getPool();

  if (!pool) return [];

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
        WHERE b.client_user_id = $1 OR b.worker_user_id = $1
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
  } catch { /* ignore */ }

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
  } catch { /* ignore */ }

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
    } catch { /* ignore */ }
  }

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
    } catch { /* ignore */ }
  }

  events.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  return events.slice(0, limit);
}

module.exports = { attachInteractionCounts, getPublicFeed, getUserTimeline };
