const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

let _initialized = false;

function initFirebase() {
  if (_initialized) return;
  const serviceAccountPath = path.join(__dirname, '../config/firebase-service-account.json');
  if (!fs.existsSync(serviceAccountPath)) {
    console.warn('Firebase service account not found — push notifications disabled.');
    return;
  }
  try {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    _initialized = true;
    console.log('Firebase Admin initialized.');
  } catch (e) {
    console.warn('Firebase Admin init failed:', e.message);
  }
}

async function sendPushNotification({ token, title, body, data = {} }) {
  if (!_initialized || !token) return;
  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)]),
      ),
      android: { priority: 'high', notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch (e) {
    // Invalid/expired tokens shouldn't crash the notification flow
    if (e.code === 'messaging/registration-token-not-registered') {
      // Token is stale — caller can clean it up if needed
      return 'stale';
    }
    console.warn('FCM send failed:', e.message);
  }
}

module.exports = { initFirebase, sendPushNotification };
