const { env } = require('../config/env');

function parseEmailFrom(value) {
  const match = value.match(/^(.+?)\s*<(.+)>$/);

  if (match) {
    return { name: match[1].trim(), address: match[2].trim() };
  }

  return { name: 'HanapGawa', address: value.trim() };
}

async function sendEmailVerificationCode({ email, code }) {
  if (!env.zentroMailApiKey) {
    return { sent: false, reason: 'ZentroMail API key is not configured.' };
  }

  const from = parseEmailFrom(env.emailFrom);
  const response = await fetch(`${env.zentroMailApiUrl.replace(/\/$/, '')}/send-email-html`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': env.zentroMailApiKey,
    },
    body: JSON.stringify({
      from: from.address,
      to: email,
      subject: 'Verify your HanapGawa account',
      html: `
      <div style="font-family: Arial, sans-serif; line-height: 1.5; color: #222;">
        <h2>Verify your HanapGawa account</h2>
        <p>Enter this verification code to finish creating your account:</p>
        <p style="font-size: 28px; font-weight: 700; letter-spacing: 6px;">${code}</p>
        <p>This code expires in 15 minutes.</p>
      </div>
    `,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`ZentroMail failed with ${response.status}: ${body}`);
  }

  return { sent: true };
}

module.exports = { sendEmailVerificationCode };
