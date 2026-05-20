const fs = require('fs');

const { env } = require('../config/env');

function getLogoDataUrl() {
  if (!env.emailLogoPath || !fs.existsSync(env.emailLogoPath)) {
    return null;
  }

  return `data:image/png;base64,${fs.readFileSync(env.emailLogoPath).toString('base64')}`;
}

async function sendEmailVerificationCode({ email, code }) {
  if (!env.zentromailApiKey) {
    return { sent: false, reason: 'Zentromail API key is not configured.' };
  }

  const logoDataUrl = getLogoDataUrl();
  const html = `
    <div style="font-family: Arial, sans-serif; line-height: 1.5; color: #222; max-width: 520px; margin: 0 auto; padding: 28px;">
      ${logoDataUrl ? `<img src="${logoDataUrl}" alt="HanapGawa" width="72" height="72" style="display: block; margin: 0 auto 18px; border-radius: 18px;" />` : ''}
      <h2 style="margin: 0 0 12px; text-align: center; color: #2f203f;">Verify your HanapGawa account</h2>
      <p style="margin: 0 0 18px; text-align: center; color: #604f6f;">Enter this verification code to finish creating your account:</p>
      <p style="margin: 0 auto 18px; width: fit-content; font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #2f203f;">${code}</p>
      <p style="margin: 0; text-align: center; color: #604f6f;">This code expires in 15 minutes.</p>
    </div>
  `;

  const response = await fetch(env.zentromailApiUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': env.zentromailApiKey,
    },
    body: JSON.stringify({
      from: env.emailFrom,
      to: email,
      subject: 'Verify your HanapGawa account',
      html,
    }),
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(detail || `Zentromail email send failed with ${response.status}.`);
  }

  return { sent: true };
}

module.exports = { sendEmailVerificationCode };
