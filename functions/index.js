/* eslint-disable */
const functions = require('firebase-functions');
const https = require('https');

// Helper: make outbound HTTPS request (server-side — no CORS restriction)
function robloxRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// CORS helper — allows hydra-bin.web.app and localhost
function setCors(req, res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
}

// POST /api/roblox-users  { usernames: ["name"], excludeBannedUsers: true }
exports.robloxUsers = functions.https.onRequest(async (req, res) => {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    const body = JSON.stringify(req.body);
    const result = await robloxRequest({
      hostname: 'users.roblox.com',
      path: '/v1/usernames/users',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, body);
    res.status(result.status).send(result.body);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /api/roblox-avatar?userIds=ID&size=150x150&format=Png&isCircular=true
exports.robloxAvatar = functions.https.onRequest(async (req, res) => {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    const params = new URLSearchParams(req.query).toString();
    const result = await robloxRequest({
      hostname: 'thumbnails.roblox.com',
      path: `/v1/users/avatar-headshot?${params}`,
      method: 'GET',
    });
    res.status(result.status).send(result.body);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});
