const express = require('express');
const https = require('https');

const { env } = require('../config/env');
const { authenticate } = require('../middleware/authenticate');

const router = express.Router();

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_MODEL = 'llama-3.3-70b-versatile';

const USER_SYSTEM_PROMPT = `You are HanapGawa AI, a friendly assistant for the HanapGawa app — a local service marketplace in Tawi-Tawi, Philippines that connects clients with skilled workers and agencies.

Help users with:
- Finding workers or services (plumbing, electrical, cleaning, tutoring, beauty, delivery, etc.)
- How to post a job or book a worker
- How bookings, reviews, and messages work
- Platform safety tips
- Pricing and payment info
- Anything related to using HanapGawa

Keep answers concise, friendly, and practical. Use simple English. When relevant, mention specific app features (Explore tab, Jobs tab, Bookings tab). The app serves municipalities in Tawi-Tawi like Bongao, Panglima Sugala, Sapa-Sapa, Languyan, Tandubas, etc.`;

const ADMIN_SYSTEM_PROMPT = `You are HanapGawa Admin AI, an intelligent assistant for platform administrators of HanapGawa — a service marketplace in Tawi-Tawi, Philippines.

You help admins with:
- Understanding platform data and metrics
- Identifying fraud, suspicious users, or abuse patterns
- Report management and prioritization
- User moderation decisions (suspend, ban, reactivate)
- Platform health and analytics insights
- Policy and moderation guidance

Be direct, analytical, and professional. When platform data is provided in the message, use it to give specific answers.`;

async function callGemini(systemPrompt, history, userMessage) {
  const contents = [
    ...history.map((m) => ({
      role: m.isUser ? 'user' : 'model',
      parts: [{ text: m.text }],
    })),
    { role: 'user', parts: [{ text: userMessage }] },
  ];

  const body = JSON.stringify({
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 512,
    },
  });

  return new Promise((resolve, reject) => {
    const url = new URL(`${GEMINI_URL}?key=${env.geminiApiKey}`);
    const req = https.request(
      {
        hostname: url.hostname,
        path: url.pathname + url.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            const json = JSON.parse(data);
            if (res.statusCode !== 200 || json.error) {
              return reject(new Error(json.error?.message || `Gemini error ${res.statusCode}`));
            }
            const text =
              json?.candidates?.[0]?.content?.parts?.[0]?.text ||
              'Sorry, I could not generate a response.';
            resolve(text);
          } catch {
            reject(new Error('Failed to parse Gemini response'));
          }
        });
      }
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function callGroq(systemPrompt, history, userMessage) {
  const messages = [
    { role: 'system', content: systemPrompt },
    ...history.map((m) => ({ role: m.isUser ? 'user' : 'assistant', content: m.text })),
    { role: 'user', content: userMessage },
  ];

  const body = JSON.stringify({
    model: GROQ_MODEL,
    messages,
    temperature: 0.7,
    max_tokens: 512,
  });

  return new Promise((resolve, reject) => {
    const url = new URL(GROQ_URL);
    const req = https.request(
      {
        hostname: url.hostname,
        path: url.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
          Authorization: `Bearer ${env.groqApiKey}`,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            const json = JSON.parse(data);
            if (res.statusCode !== 200 || json.error) {
              return reject(new Error(json.error?.message || `Groq error ${res.statusCode}`));
            }
            const text = json?.choices?.[0]?.message?.content || 'Sorry, I could not generate a response.';
            resolve(text);
          } catch {
            reject(new Error('Failed to parse Groq response'));
          }
        });
      }
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function callAI(systemPrompt, history, userMessage) {
  if (env.geminiApiKey) {
    try {
      return await callGemini(systemPrompt, history, userMessage);
    } catch (err) {
      console.warn('Gemini failed, falling back to Groq:', err.message);
    }
  }
  if (env.groqApiKey) {
    return callGroq(systemPrompt, history, userMessage);
  }
  throw new Error('No AI service configured');
}

function buildAdminFallback(message, context = '') {
  const text = `${message} ${context}`.toLowerCase();
  if (text.includes('high-risk') || text.includes('risk')) {
    return 'AI provider is not configured, so I can only use local dashboard signals. Review users with high report counts, repeated cancellations, and unresolved pending reports first.';
  }
  if (text.includes('report')) {
    return 'AI provider is not configured. Use the Reports tab to prioritize pending reports, open reported post details when available, then resolve, dismiss, suspend, ban, or delete content as appropriate.';
  }
  if (text.includes('summary') || text.includes('platform')) {
    return `AI provider is not configured. Current local context: ${context || 'No platform context was provided.'}`;
  }
  return 'AI provider is not configured, but the admin dashboard is available. Check Risk Board, Reports, Insights, and Analytics for local moderation signals.';
}

function buildUserFallback(message) {
  const text = message.toLowerCase();
  if (text.includes('book')) {
    return 'AI provider is not configured right now. To book a worker, open Explore, choose a service or worker, then tap Book or send a message.';
  }
  if (text.includes('job')) {
    return 'AI provider is not configured right now. To post a job, go to the Jobs tab, create a job post, and wait for workers to apply.';
  }
  if (text.includes('report') || text.includes('safe')) {
    return 'AI provider is not configured right now. For safety, use Report on posts, profiles, or messages. Admins can review reports and take action.';
  }
  return 'AI provider is not configured right now. You can still use Explore to find workers, Jobs to post work, Bookings to manage transactions, and Messages to chat.';
}

// POST /ai/chat — user-facing assistant
router.post('/chat', authenticate, async (req, res) => {
  try {
    const { message, history = [] } = req.body;
    if (!message || typeof message !== 'string') {
      return res.status(400).json({ error: 'message is required' });
    }
    if (!env.geminiApiKey && !env.groqApiKey) {
      return res.json({ reply: buildUserFallback(message), degraded: true });
    }
    const reply = await callAI(USER_SYSTEM_PROMPT, history, message);
    res.json({ reply });
  } catch (err) {
    console.error('Gemini user chat error:', err.message);
    res.status(500).json({ error: 'AI service unavailable' });
  }
});

// POST /ai/admin-chat — admin assistant (admin only)
router.post('/admin-chat', authenticate, async (req, res) => {
  try {
    if (req.auth.role !== 'admin') {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const { message, history = [], context = '' } = req.body;
    if (!message || typeof message !== 'string') {
      return res.status(400).json({ error: 'message is required' });
    }
    if (!env.geminiApiKey && !env.groqApiKey) {
      return res.json({
        reply: buildAdminFallback(message, context),
        degraded: true,
      });
    }
    const fullMessage = context
      ? `Platform context:\n${context}\n\nAdmin question: ${message}`
      : message;
    const reply = await callAI(ADMIN_SYSTEM_PROMPT, history, fullMessage);
    res.json({ reply });
  } catch (err) {
    console.error('Gemini admin chat error:', err.message);
    res.status(500).json({ error: 'AI service unavailable' });
  }
});

module.exports = { aiRoutes: router };
