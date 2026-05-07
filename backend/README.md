# HanapGawa Backend

Initial Node.js/Express backend for the HanapGawa distributed local service marketplace.

## Stack

- Express API
- PostgreSQL for transactional data such as users and bookings
- MongoDB for flexible provider profiles and portfolios
- Redis reserved for search/discovery caching
- JWT authentication for app login and future One Tawi-Tawi token sharing

## Implemented So Far

- API bootstrap with security middleware
- Health endpoint with PostgreSQL, MongoDB, and Redis checks
- JWT-based auth routes
- PostgreSQL-backed user registration and login groundwork
- Role-based authorization middleware for protected routes
- MongoDB-backed provider profile creation and search groundwork
- Redis-backed provider search caching with invalidation on profile updates
- PostgreSQL-backed bookings and reviews groundwork
- Admin provider approval workflow
- Agency-worker application and membership workflow
- External token verification endpoint for future One Tawi-Tawi integration

## Project Structure

```text
src/
  app.js
  server.js
  config/
  db/
  lib/
  middleware/
  repositories/
  routes/
  services/
```

## Environment Setup

Copy `.env.example` to `.env` and update the values.

## Run

```bash
npm install
npm run dev
```

Or start without auto-reload:

```bash
npm start
```

## Demo Seed

Use the standalone seed script when you want demo data:

```bash
npm run seed
```

What it creates:

- 1 admin account
- 1 client account
- 1 approved worker account with provider profile
- 1 approved agency account with provider profile
- 1 approved agency-worker relationship
- 2 sample bookings
- 1 sample review

Demo credentials:

- `admin@hanapgawa.demo` / `Password123!`
- `client@hanapgawa.demo` / `Password123!`
- `worker@hanapgawa.demo` / `Password123!`
- `agency@hanapgawa.demo` / `Password123!`

This script is isolated in `src/scripts/seed.js` and can be removed later without affecting runtime routes.

## API Endpoints

- `GET /`
- `GET /api/v1/health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/external/verify`
- `POST /api/v1/bookings`
- `GET /api/v1/bookings`
- `PATCH /api/v1/bookings/:bookingId/status`
- `GET /api/v1/admin/providers`
- `PATCH /api/v1/admin/providers/:userId/status`
- `POST /api/v1/agencies/applications`
- `GET /api/v1/agencies/applications/mine`
- `PATCH /api/v1/agencies/applications/:applicationId`
- `GET /api/v1/agencies/memberships/:agencyUserId`
- `POST /api/v1/providers`
- `GET /api/v1/providers/search`
- `POST /api/v1/reviews`
- `GET /api/v1/reviews/provider/:providerUserId`

## Sample Payloads

Register:

```json
{
  "email": "client@example.com",
  "password": "Password123!",
  "role": "client",
  "fullName": "Nur Client"
}
```

Login:

```json
{
  "email": "client@hanapgawa.demo",
  "password": "Password123!"
}
```

Create provider profile:

```json
{
  "displayName": "Jamal Carpenter Services",
  "category": "Carpentry",
  "municipality": "Bongao",
  "services": ["Custom shelves", "Door repair"],
  "portfolio": [
    {
      "title": "Kitchen shelf repair",
      "imageUrl": "https://example.com/photo.jpg",
      "description": "Repaired damaged wood shelving."
    }
  ]
}
```

Search providers:

```text
GET /api/v1/providers/search?category=Carpentry&municipality=Bongao&service=shelf
```

Create booking:

```json
{
  "providerUserId": "<approved-provider-uuid>",
  "serviceCategory": "Carpentry",
  "municipality": "Bongao",
  "notes": "Need help repairing a window frame.",
  "scheduledAt": "2026-05-02T10:00:00.000Z"
}
```

Update booking status:

```json
{
  "status": "accepted"
}
```

Create review:

```json
{
  "bookingId": "<completed-booking-uuid>",
  "rating": 5,
  "comment": "Very reliable and easy to work with."
}
```

## Notes

- The server can boot even if databases are not configured yet.
- Routes that depend on PostgreSQL or MongoDB return `503` until their connection variables are set.
- Only `worker`, `agency`, and `admin` users can create provider profiles.
- Only `client` and `admin` users can create bookings.
- Only completed bookings can receive a review.
- Admin users can approve or reject worker and agency accounts by updating `users.status`.
- Agency-worker memberships are derived from approved agency applications.
- Provider search caches category, municipality, and service queries in Redis for 5 minutes.
- Only approved worker and agency accounts are visible in provider search and allowed to act as service providers.
- For PostgreSQL, `gen_random_uuid()` requires the `pgcrypto` extension. Enable it with:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```
