const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');
const { MongoClient } = require('mongodb');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const MONGODB_URI = process.env.MONGODB_URI;
const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

if (!GEMINI_API_KEY) {
  console.error('Missing GEMINI_API_KEY');
  process.exit(1);
}
if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI');
  process.exit(1);
}

const mongoClient = new MongoClient(MONGODB_URI);
let teamsCollection;
let batteriesCollection;

async function connectToMongo() {
  await mongoClient.connect();
  const db = mongoClient.db('ridgebotics');
  teamsCollection = db.collection('teams');
  batteriesCollection = db.collection('batteries');
  await teamsCollection.createIndex({ teamNumber: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1 });
  console.log('Connected to MongoDB');
}

const reports = [];
const MAX_REPORTS = 50;

async function getTeam(teamNumber) {
  if (!teamNumber) return null;
  return teamsCollection.findOne({ teamNumber: String(teamNumber) });
}

async function checkTeamAuth(req, res) {
  const teamNumber = req.body.teamNumber || req.query.teamNumber;
  const passcode = req.body.passcode || req.query.passcode;
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

app.post('/analyzeImage', async (req, res) => {
  try {
    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.status(response.status).json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/reportFinding', (req, res) => {
  const { title, description, severity } = req.body;
  if (!title) return res.status(400).json({ error: 'title is required' });
  reports.unshift({
    title,
    description: description || '',
    severity: severity || 'unknown',
    reportedAt: new Date().toISOString(),
  });
  if (reports.length > MAX_REPORTS) reports.length = MAX_REPORTS;
  res.json({ ok: true });
});

app.get('/reports', (req, res) => {
  res.json({ reports });
});

async function lookupTeamName(teamNumber) {
  try {
    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: `What is the team name of FIRST Robotics Competition (FRC) team number ${teamNumber}? Respond with ONLY the team name, nothing else, no punctuation, no explanation. If you do not know or are not confident, respond with exactly: UNKNOWN`,
              },
            ],
          },
        ],
        generationConfig: { temperature: 0, maxOutputTokens: 30 },
      }),
    });
    const data = await response.json();
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!text || text.toUpperCase().includes('UNKNOWN')) return null;
    return text;
  } catch (err) {
    console.error('Team name lookup failed', err);
    return null;
  }
}

app.post('/battery/register', async (req, res) => {
  try {
    const teamNumber = req.body.teamNumber ? String(req.body.teamNumber).trim() : null;
    const passcode = req.body.passcode ? String(req.body.passcode).trim() : null;

    if (!teamNumber || !passcode) {
      return res.status(400).json({ error: 'teamNumber and passcode required' });
    }
    if (passcode.length < 4) {
      return res.status(400).json({ error: 'Passcode must be at least 4 characters' });
    }

    const existing = await getTeam(teamNumber);
    if (existing) {
      return res.status(409).json({ error: 'Team already registered' });
    }

    const teamName = await lookupTeamName(teamNumber);

    await teamsCollection.insertOne({
      teamNumber,
      passcode,
      teamName: teamName || null,
      createdAt: new Date().toISOString(),
    });

    res.json({ ok: true, teamName: teamName || null });
  } catch (err) {
    console.error('Register error:', err);
    if (err.code === 11000) {
      return res.status(409).json({ error: 'Team already registered' });
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

app.post('/battery/changePasscode', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;
    const newPasscode = req.body.newPasscode ? String(req.body.newPasscode).trim() : null;
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
    const teamNumber = req.query.teamNumber ? String(req.query.teamNumber).trim() : null;
    const passcode = req.query.passcode ? String(req.query.passcode).trim() : null;
    const guest = req.query.guest === 'true';

    if (!teamNumber) {
      return res.status(400).json({ error: 'teamNumber required' });
    }

    const team = await getTeam(teamNumber);
    if (!team) {
      return res.status(404).json({ error: 'Team not found' });
    }

    if (!guest) {
      if (team.passcode !== passcode) {
        return res.status(401).json({ error: 'Invalid team number or passcode' });
      }
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
    const count = await batteriesCollection.countDocuments({
      teamNumber: team.teamNumber,
    });
    const label = `B${count + 1}`;
    const battery = {
      teamNumber: team.teamNumber,
      label,
      lastUsedAt: new Date(0).toISOString(),
      flags: [],
    };
    await batteriesCollection.insertOne(battery);
    res.json({ battery });
  } catch (err) {
    console.error('Add battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/use', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;
    const { label } = req.body;
    if (!label) return res.status(400).json({ error: 'label is required' });
    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      { $set: { lastUsedAt: new Date().toISOString() } },
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('Use battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/flag', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;
    const { label, note } = req.body;
    if (!label) return res.status(400).json({ error: 'label is required' });
    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $push: {
          flags: {
            note: note || '',
            flaggedAt: new Date().toISOString(),
          },
        },
      },
    );
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
    await batteriesCollection.deleteOne({
      teamNumber: team.teamNumber,
      label: req.params.label,
    });
    res.json({ ok: true });
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

    const summary = batteries.map((b) => {
      const restMinutes = Math.round((Date.now() - new Date(b.lastUsedAt).getTime()) / 60000);
      return `${b.label}: rested ${restMinutes} minutes, flagged ${b.flags.length} times`;
    }).join('\n');

    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: `Here is battery rest and flag data for an FRC robotics team:\n\n${summary}\n\nBased on this, which single battery should they grab next? Prefer batteries that have rested longer and have fewer flags. Respond ONLY with valid JSON, no markdown:\n\n{"recommendedLabel": "B1", "reason": "short reason in under 15 words"}`,
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

    if (!rawText) {
      return res.json({ recommendedLabel: batteries[0].label, reason: 'Most rested battery' });
    }

    const parsed = JSON.parse(rawText);
    res.json(parsed);
  } catch (err) {
    console.error('Recommend error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/', (req, res) => res.send('Backend running'));

const PORT = process.env.PORT || 3000;
connectToMongo()
  .then(() => {
    app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB', err);
    process.exit(1);
  });