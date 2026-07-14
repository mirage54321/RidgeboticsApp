// https://frc-events.firstinspires.org/2026/allteams
const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');
const { MongoClient } = require('mongodb');
const FIRST_USERNAME = process.env.FIRST_USERNAME;
const FIRST_TOKEN = process.env.FIRST_TOKEN;
const app = express();

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const DB_NAME = process.env.DB_NAME || 'ridgebotics';
const FRONTEND_ORIGIN = process.env.FRONTEND_ORIGIN || '*';
const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI');
  process.exit(1);
}

const corsOptions = {
  origin: FRONTEND_ORIGIN,
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type'],
};

app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '50mb' }));

const mongoClient = new MongoClient(MONGODB_URI);
let teamsCollection;
let batteriesCollection;

const reports = [];
const MAX_REPORTS = 50;

async function connectToMongo() {
  await mongoClient.connect();

  const db = mongoClient.db(DB_NAME);
  teamsCollection = db.collection('teams');
  batteriesCollection = db.collection('batteries');

  await teamsCollection.createIndex({ teamNumber: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, label: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, lastUsedAt: 1 });

  console.log(`Connected to MongoDB database: ${DB_NAME}`);
}

async function getFIRSTTeamName(teamNumber) {
  try {
    const response = await fetch(
      `https://frc-api.firstinspires.org/v3.0/2026/teams?teamNumber=${teamNumber}`,
      {
        headers: {
          Authorization:
            'Basic ' +
            Buffer.from(
              `${FIRST_USERNAME}:${FIRST_TOKEN}`
            ).toString('base64'),
        },
      }
    );

    const data = await response.json();

    if (data.teams && data.teams.length > 0) {
      return data.teams[0].nameShort;
    }

    return null;

  } catch (err) {
    console.error("FIRST lookup failed:", err);
    return null;
  }
}


function cleanString(value) {
  if (value === undefined || value === null) return null;
  const cleaned = String(value).trim();
  return cleaned || null;
}

async function getTeam(teamNumber) {
  const cleanedTeamNumber = cleanString(teamNumber);
  if (!cleanedTeamNumber) return null;
  return teamsCollection.findOne({ teamNumber: cleanedTeamNumber });
}

async function checkTeamAuth(req, res) {
  const teamNumber = cleanString(req.body.teamNumber || req.query.teamNumber);
  const passcode = cleanString(req.body.passcode || req.query.passcode);

  if (!teamNumber || !passcode) {
    res.status(400).json({ error: 'teamNumber and passcode required' });
    return null;
  }

  const team = await getTeam(teamNumber);
  if (!team || team.passcode !== passcode) {
    res.status(401).json({ error: 'Invalid team number or passcode' });
    return null;
  }

  return team;
}

function fallbackRecommendation(batteries, reason = 'Most rested available battery') {
  const available = batteries.find((battery) => !battery.isInUse && !battery.isCharging);
  const picked = available || batteries[0];

  return {
    recommendedLabel: picked ? picked.label : null,
    reason: picked ? reason : 'No batteries logged yet',
  };
}

app.get('/', (req, res) => {
  res.send('Backend running');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    mongo: Boolean(teamsCollection && batteriesCollection),
    geminiConfigured: Boolean(GEMINI_API_KEY),
  });
});

app.post('/analyzeImage', async (req, res) => {
  try {
    if (!GEMINI_API_KEY) {
      return res.status(503).json({ error: 'GEMINI_API_KEY is not configured on the server' });
    }

    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (err) {
    console.error('Analyze image error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/reportFinding', (req, res) => {
  const title = cleanString(req.body.title);

  if (!title) {
    return res.status(400).json({ error: 'title is required' });
  }

  reports.unshift({
    title,
    description: cleanString(req.body.description) || '',
    severity: cleanString(req.body.severity) || 'unknown',
    reportedAt: new Date().toISOString(),
  });

  if (reports.length > MAX_REPORTS) reports.length = MAX_REPORTS;

  res.json({ ok: true });
});

app.get('/reports', (req, res) => {
  res.json({ reports });
});

app.post('/battery/register', async (req, res) => {
  try {
    const teamNumber = cleanString(req.body.teamNumber);
    const passcode = cleanString(req.body.passcode);

    if (!teamNumber || !passcode) {
      return res.status(400).json({ error: 'teamNumber and passcode required' });
    }

    if (passcode.length < 4) {
      return res.status(400).json({ error: 'Passcode must be at least 4 characters' });
    }

    const existing = await getTeam(teamNumber);
    if (existing) {
      return res.status(409).json({ error: 'Team already registered. \n\nContact mira.j.maroni@gmail.com if you don\'t have access to your team account.' });
    }

const teamName = await getFIRSTTeamName(teamNumber);

    await teamsCollection.insertOne({
      teamNumber,
      passcode,
      teamName,
      createdAt: new Date().toISOString(),
    });

    res.json({ ok: true, teamName });
  } catch (err) {
    console.error('Register error:', err);

    if (err.code === 11000) {
      return res.status(409).json({ error: 'Team already registered. \n\nContact mira.j.maroni@gmail.com if you don\'t have access to your team account.' });
    }

    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/login', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    res.json({ ok: true, teamName: team.teamName || null });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/changeTeamName', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const teamName = cleanString(req.body.teamName);

    await teamsCollection.updateOne(
      { teamNumber: team.teamNumber },
      { $set: { teamName } },
    );

    res.json({ ok: true, teamName });
  } catch (err) {
    console.error('Change team name error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/changePasscode', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const newPasscode = cleanString(req.body.newPasscode);
    if (!newPasscode || newPasscode.length < 4) {
      return res.status(400).json({ error: 'New passcode must be at least 4 characters' });
    }

    await teamsCollection.updateOne(
      { teamNumber: team.teamNumber },
      { $set: { passcode: newPasscode } },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Change passcode error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/reset', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const result = await batteriesCollection.deleteMany({ teamNumber: team.teamNumber });
    res.json({ ok: true, deletedCount: result.deletedCount });
  } catch (err) {
    console.error('Reset error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/battery/list', async (req, res) => {
  try {
    const teamNumber = cleanString(req.query.teamNumber);
    const passcode = cleanString(req.query.passcode);
    const guest = req.query.guest === 'true';

    if (!teamNumber) {
      return res.status(400).json({ error: 'teamNumber required' });
    }

    const team = await getTeam(teamNumber);
    if (!team) {
      return res.status(404).json({ error: 'Team not found' });
    }

    if (!guest && team.passcode !== passcode) {
      return res.status(401).json({ error: 'Invalid team number or passcode' });
    }

    const batteries = await batteriesCollection
      .find({ teamNumber })
      .sort({ lastUsedAt: 1 })
      .toArray();

    res.json({ batteries, teamName: team.teamName || null });
  } catch (err) {
    console.error('List error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/add', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const count = await batteriesCollection.countDocuments({ teamNumber: team.teamNumber });
    const label = `B${count + 1}`;
    const battery = {
      teamNumber: team.teamNumber,
      label,
      lastUsedAt: new Date(0).toISOString(),
      flags: [],
      isCharging: false,
      isInUse: false,
      createdAt: new Date().toISOString(),
    };

    await batteriesCollection.insertOne(battery);
    res.json({ battery });
  } catch (err) {
    console.error('Add battery error:', err);

    if (err.code === 11000) {
      return res.status(409).json({ error: 'Battery already exists' });
    }

    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/use', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const battery = await batteriesCollection.findOne({ teamNumber: team.teamNumber, label });
    if (!battery) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    const nextInUse = !battery.isInUse;

    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $set: {
          isInUse: nextInUse,
          isCharging: false,
          lastUsedAt: new Date().toISOString(),
        },
      },
    );

    res.json({ ok: true, isInUse: nextInUse });
  } catch (err) {
    console.error('Use battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/charging', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const battery = await batteriesCollection.findOne({ teamNumber: team.teamNumber, label });
    if (!battery) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    const nextCharging = !battery.isCharging;

    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $set: {
          isCharging: nextCharging,
          isInUse: false,
          chargedAt: nextCharging ? new Date().toISOString() : battery.chargedAt || null,
        },
      },
    );

    res.json({ ok: true, isCharging: nextCharging });
  } catch (err) {
    console.error('Charging battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/flag', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const result = await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $push: {
          flags: {
            note: cleanString(req.body.note) || '',
            flaggedAt: new Date().toISOString(),
          },
        },
      },
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('Flag error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.delete('/battery/:label', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const result = await batteriesCollection.deleteOne({
      teamNumber: team.teamNumber,
      label: req.params.label,
    });

    res.json({ ok: true, deletedCount: result.deletedCount });
  } catch (err) {
    console.error('Delete battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/recommend', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const batteries = await batteriesCollection
      .find({ teamNumber: team.teamNumber })
      .sort({ lastUsedAt: 1 })
      .toArray();

    if (batteries.length === 0) {
      return res.json({ recommendedLabel: null, reason: 'No batteries logged yet' });
    }

    if (!GEMINI_API_KEY) {
      return res.json(fallbackRecommendation(batteries));
    }

    const chargeMinutes = 45;
    const summary = batteries
      .map((battery) => {
        const restMinutes = Math.round(
          (Date.now() - new Date(battery.lastUsedAt).getTime()) / 60000,
        );

        const chargingStatus = battery.isInUse
          ? 'currently in use'
          : battery.isCharging
            ? (() => {
                const chargedAt = battery.chargedAt
                  ? new Date(battery.chargedAt).getTime()
                  : Date.now();
                const elapsedMin = Math.round((Date.now() - chargedAt) / 60000);
                const remaining = Math.max(0, chargeMinutes - elapsedMin);
                return remaining > 0 ? `charging (${remaining}min left)` : 'charging (ready)';
              })()
            : 'available';

        const flags = Array.isArray(battery.flags) ? battery.flags : [];
        const flagSummary =
          flags.length === 0
            ? 'no flags'
            : `flagged ${flags.length}x, reasons: ${flags
                .map((flag) => flag.note || 'no reason given')
                .join('; ')}`;

        return `${battery.label}: charged ${restMinutes} minutes ago, status: ${chargingStatus}, ${flagSummary}`;
      })
      .join('\n');

    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: `Here is battery data for an FRC robotics team preparing for a match:\n\n${summary}\n\nBased on this, which single battery should they grab next? Prefer available batteries that were charged longest ago (most rested). Avoid batteries currently in use or still charging. Heavily penalize batteries with flags mentioning serious issues like dying mid-match or brownouts. Respond ONLY with valid JSON, no markdown:\n\n{"recommendedLabel":"B1","reason":"one sentence reason under 15 words"}`,
              },
            ],
          },
        ],
        generationConfig: { temperature: 0, maxOutputTokens: 100 },
      }),
    });

    const data = await response.json();
    const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text
      ?.replace(/```json/g, '')
      ?.replace(/```/g, '')
      ?.trim();

    if (!response.ok || !rawText) {
      return res.json(fallbackRecommendation(batteries));
    }

    try {
      const parsed = JSON.parse(rawText);
      return res.json({
        recommendedLabel: parsed.recommendedLabel || null,
        reason: parsed.reason || 'Recommended by battery history',
      });
    } catch (parseErr) {
      console.error('Gemini JSON parse error:', parseErr);
      return res.json(fallbackRecommendation(batteries));
    }
  } catch (err) {
    console.error('Recommend error:', err);
    res.status(500).json({ error: err.message });
  }
});

connectToMongo()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB:', err);
    process.exit(1);
  });
