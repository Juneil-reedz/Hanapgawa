const crypto = require('crypto');
const express = require('express');
const jwt = require('jsonwebtoken');

const { asyncHandler } = require('../lib/async-handler');
const { HttpError } = require('../lib/http-error');
const { authenticate } = require('../middleware/authenticate');
const { env } = require('../config/env');

const router = express.Router();

let spotifyToken = null;
let spotifyTokenExpiresAt = 0;

const DEFAULT_LOCATIONS = [
  'Bongao, Tawi-Tawi, Philippines',
  'Panglima Sugala, Tawi-Tawi, Philippines',
  'Sapa-Sapa, Tawi-Tawi, Philippines',
  'Languyan, Tawi-Tawi, Philippines',
  'Tandubas, Tawi-Tawi, Philippines',
  'Simunul, Tawi-Tawi, Philippines',
  'Sitangkai, Tawi-Tawi, Philippines',
  'South Ubian, Tawi-Tawi, Philippines',
  'Turtle Islands, Tawi-Tawi, Philippines',
  'Mapun, Tawi-Tawi, Philippines',
  'Sibutu, Tawi-Tawi, Philippines',
].map((displayName, index) => ({
  id: `local-${index}`,
  name: displayName.split(',')[0],
  displayName,
  latitude: null,
  longitude: null,
}));

function localLocations(query) {
  const q = query.toLowerCase();
  return DEFAULT_LOCATIONS.filter((location) =>
    !q || location.displayName.toLowerCase().includes(q) || location.name.toLowerCase().includes(q),
  );
}

async function getSpotifyToken() {
  if (!env.spotifyClientId || !env.spotifyClientSecret) {
    throw new HttpError(503, 'Spotify search is not configured.');
  }
  if (spotifyToken && Date.now() < spotifyTokenExpiresAt - 60000) return spotifyToken;

  const credentials = Buffer.from(`${env.spotifyClientId}:${env.spotifyClientSecret}`).toString('base64');
  const response = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ grant_type: 'client_credentials' }),
  });
  if (!response.ok) {
    const error = await response.text();
    throw new HttpError(502, `Spotify auth failed (${response.status}): ${error.slice(0, 160)}`);
  }
  const json = await response.json();
  spotifyToken = json.access_token;
  spotifyTokenExpiresAt = Date.now() + (json.expires_in || 3600) * 1000;
  return spotifyToken;
}

router.get('/gifs/search', asyncHandler(async (req, res) => {
  if (!env.giphyApiKey) throw new HttpError(503, 'GIF search is not configured.');
  const q = (req.query.q || '').toString().trim();
  if (!q) return res.json({ gifs: [] });

  const url = new URL('https://api.giphy.com/v1/gifs/search');
  url.searchParams.set('api_key', env.giphyApiKey);
  url.searchParams.set('q', q);
  url.searchParams.set('limit', Math.min(parseInt(req.query.limit) || 12, 25).toString());
  url.searchParams.set('rating', 'pg');

  const response = await fetch(url);
  if (!response.ok) throw new HttpError(502, 'GIF provider is unavailable.');
  const data = await response.json();
  const gifs = (data.data || []).map((gif) => ({
    id: gif.id,
    title: gif.title || 'GIF',
    previewUrl: gif.images?.fixed_width_small?.url || gif.images?.preview_gif?.url,
    url: gif.images?.fixed_width?.url || gif.images?.original?.url,
  })).filter((gif) => gif.url);
  res.json({ gifs });
}));

router.get('/stickers/search', asyncHandler(async (req, res) => {
  if (!env.giphyApiKey) throw new HttpError(503, 'Sticker search is not configured.');
  const q = (req.query.q || '').toString().trim();
  const endpoint = q ? 'search' : 'trending';
  const url = new URL(`https://api.giphy.com/v1/stickers/${endpoint}`);
  url.searchParams.set('api_key', env.giphyApiKey);
  if (q) url.searchParams.set('q', q);
  url.searchParams.set('limit', Math.min(parseInt(req.query.limit) || 20, 50).toString());
  url.searchParams.set('rating', 'pg');

  const response = await fetch(url);
  if (!response.ok) throw new HttpError(502, 'Sticker provider is unavailable.');
  const data = await response.json();
  const stickers = (data.data || []).map((s) => ({
    id: s.id,
    title: s.title || 'Sticker',
    previewUrl: s.images?.fixed_width_small?.url || s.images?.preview_gif?.url,
    url: s.images?.fixed_width?.url || s.images?.original?.url,
  })).filter((s) => s.url);
  res.json({ stickers });
}));

router.get('/locations/search', asyncHandler(async (req, res) => {
  const q = (req.query.q || '').toString().trim();
  if (!q) return res.json({ locations: localLocations('') });

  const url = new URL('https://nominatim.openstreetmap.org/search');
  url.searchParams.set('q', `${q}, Philippines`);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('limit', Math.min(parseInt(req.query.limit) || 8, 10).toString());
  url.searchParams.set('addressdetails', '1');

  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'HanapGawa/1.0 (support@hanapgawa.app)',
        'Accept-Language': 'en',
      },
    });
    if (!response.ok) throw new Error('Location provider unavailable');
    const data = await response.json();
    const locations = data.map((place) => ({
      id: place.place_id?.toString() || place.osm_id?.toString() || place.display_name,
      name: place.name || place.display_name,
      displayName: place.display_name,
      latitude: place.lat,
      longitude: place.lon,
    }));
    res.json({ locations: locations.length ? locations : localLocations(q) });
  } catch {
    res.json({ locations: localLocations(q) });
  }
}));

// Returns a signed Cloudinary upload params so Flutter can upload directly
router.get('/cloudinary-signature', authenticate, asyncHandler(async (req, res) => {
  const { cloudinaryCloudName, cloudinaryApiKey, cloudinaryApiSecret } = env;
  if (!cloudinaryCloudName || !cloudinaryApiKey || !cloudinaryApiSecret) {
    throw new HttpError(503, 'Media upload is not configured.');
  }
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const folder = 'hanapgawa/posts';
  const signature = crypto
    .createHash('sha1')
    .update(`folder=${folder}&timestamp=${timestamp}${cloudinaryApiSecret}`)
    .digest('hex');
  res.json({ cloudName: cloudinaryCloudName, apiKey: cloudinaryApiKey, timestamp, folder, signature });
}));

router.get('/music/search', asyncHandler(async (req, res) => {
  const q = (req.query.q || '').toString().trim();
  if (!q) return res.json({ tracks: [] });

  const url = new URL('https://api.deezer.com/search');
  url.searchParams.set('q', q);
  url.searchParams.set('limit', Math.min(parseInt(req.query.limit) || 10, 20).toString());
  const response = await fetch(url);
  if (!response.ok) throw new HttpError(502, 'Deezer music search is unavailable.');
  const data = await response.json();
  const tracks = (data.data || []).map((track) => ({
    id: track.id?.toString(),
    title: track.title || 'Track',
    artist: track.artist?.name || '',
    album: track.album?.title || '',
    imageUrl: track.album?.cover_medium || track.album?.cover || '',
    previewUrl: track.preview || '',
    musicUrl: track.link || '',
    source: 'deezer',
  }));
  res.json({ tracks });
}));

router.post('/livekit/token', authenticate, asyncHandler(async (req, res) => {
  if (!env.livekitUrl || !env.livekitApiKey || !env.livekitApiSecret) {
    throw new HttpError(503, 'Live video is not configured.');
  }

  const room = (req.body.room || '').toString().trim();
  if (!room) throw new HttpError(400, 'Room is required.');
  const name = req.auth.fullName || req.auth.email || req.auth.sub;
  const identity = req.auth.sub;
  const now = Math.floor(Date.now() / 1000);
  const token = jwt.sign(
    {
      iss: env.livekitApiKey,
      sub: identity,
      name,
      nbf: now,
      exp: now + 60 * 60,
      video: {
        room,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
      },
    },
    env.livekitApiSecret,
    { algorithm: 'HS256' },
  );

  res.json({ url: env.livekitUrl, room, token });
}));

module.exports = { mediaRoutes: router };
