const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');
const { MongoClient } = require('mongodb');
const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';
const MONGODB_URI = process.env.MONGODB_URI;
const TEAM_PASSCODE = process.env.TEAM_PASSCODE;
if (!GEMINI_API_KEY) {
  console.error('Missing GEMINI_API_KEY');
  process.exit(1);
}
if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI');
  process.exit(1);
}
if (!TEAM_PASSCODE) {
  console.error('Missing TEAM_PASSCODE');
  process.exit(1);
}

const mongoClient = new MongoClient(MONGODB_URI);
let batteriesCollection;

async function connectToMongo() {
  await mongoClient.connect();
  const db = mongoClient.db('ridgebotics');
  batteriesCollection = db.collection('batteries');
  console.log('Connected to MongoDB');
}

const reports = [];
const MAX_REPORTS = 50;

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

app.post('/reportFinding', (req, res) => {
  const { title, description, severity } = req.body;
  if (!title) {
    return res.status(400).json({ error: 'title is required' });
  }
  reports.unshift({
    title,
    description: description || '',
    severity: severity || 'unknown',
    reportedAt: new Date().toISOString(),
  });
  if (reports.length > MAX_REPORTS) {
    reports.length = MAX_REPORTS;
  }
  res.json({ ok: true });
});

app.get('/reports', (req, res) => {
  res.json({ reports });
});

function checkPasscode(req, res, next) {
  const passcode = req.body.passcode || req.query.passcode;
  if (passcode !== TEAM_PASSCODE) {
    return res.status(401).json({ error: 'Invalid passcode' });
  }
  next();
}

app.post('/battery/login', (req, res) => {
  const { teamNumber, passcode } = req.body;
  if (teamNumber !== '4388' || passcode !== TEAM_PASSCODE) {
    return res.status(401).json({ error: 'Invalid team number or passcode' });
  }
  res.json({ ok: true });
});

app.get('/battery/list', checkPasscode, async (req, res) => {
  try {
    const batteries = await batteriesCollection
      .find({})
      .sort({ lastUsedAt: 1 })
      .toArray();
    res.json({ batteries });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/add', checkPasscode, async (req, res) => {
  try {
    const count = await batteriesCollection.countDocuments();
    const label = `B${count + 1}`;
    const battery = {
      label,
      lastUsedAt: new Date(0).toISOString(),
      flags: [],
    };
    await batteriesCollection.insertOne(battery);
    res.json({ battery });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/use', checkPasscode, async (req, res) => {
  try {
    const { label } = req.body;
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }
    await batteriesCollection.updateOne(
      { label },
      { $set: { lastUsedAt: new Date().toISOString() } },
    );
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/flag', checkPasscode, async (req, res) => {
  try {
    const { label, note } = req.body;
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }
    await batteriesCollection.updateOne(
      { label },
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
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.delete('/battery/:label', checkPasscode, async (req, res) => {
  try {
    await batteriesCollection.deleteOne({ label: req.params.label });
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/', (req, res) => {
  res.send('Backend running');
});
const PORT = process.env.PORT || 3000;
connectToMongo()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB', err);
    process.exit(1);
  });