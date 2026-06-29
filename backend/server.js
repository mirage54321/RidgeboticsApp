const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');

const app = express();
app.use(cors());
app.use(express.json({ limit: '100mb' }));

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const MONGODB_URI = process.env.MONGODB_URI;
const TEAM_PASSCODE = process.env.TEAM_PASSCODE;

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

if (!GEMINI_API_KEY) {
  console.error('Missing GEMINI_API_KEY');
  process.exit(1);
}

app.post('/analyzeImage', async (req, res) => {
  try {
    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(req.body),
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/', (req, res) => {
  res.send('Backend running');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});