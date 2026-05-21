const nodemailer = require('nodemailer');

const { env } = require('../config/env');

let transporter;

function getTransporter() {
  if (!env.gmailUser || !env.gmailAppPassword) return null;
  if (!transporter) {
    transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: env.gmailUser,
        pass: env.gmailAppPassword,
      },
    });
  }
  return transporter;
}

async function sendEmailVerificationCode({ email, code }) {
  const transport = getTransporter();

  if (!transport) {
    return { sent: false, reason: 'Gmail credentials are not configured.' };
  }

  await transport.sendMail({
    from: env.emailFrom || `HanapGawa <${env.gmailUser}>`,
    to: email,
    subject: 'Verify your HanapGawa account',
    html: `
      <div style="font-family: Arial, sans-serif; line-height: 1.5; color: #222; max-width: 520px; margin: 0 auto; padding: 28px;">
        <h2 style="margin: 0 0 12px; text-align: center; color: #2f203f;">Verify your HanapGawa account</h2>
        <p style="margin: 0 0 18px; text-align: center; color: #604f6f;">Enter this verification code to finish creating your account:</p>
        <p style="margin: 0 auto 18px; width: fit-content; font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #2f203f;">${code}</p>
        <p style="margin: 0; text-align: center; color: #604f6f;">This code expires in 15 minutes.</p>
      </div>
    `,
  });

  return { sent: true };
}

module.exports = { sendEmailVerificationCode };
