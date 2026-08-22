// https://frc-events.firstinspires.org/2026/allteams
const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');
const webpush = require('web-push');
const { MongoClient } = require('mongodb');
const FIRST_USERNAME = process.env.FIRST_USERNAME;
const FIRST_TOKEN = process.env.FIRST_TOKEN;
const app = express();

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const DB_NAME = process.env.DB_NAME || 'ridgebotics';
const FRONTEND_ORIGIN = process.env.FRONTEND_ORIGIN || '*';

const GEMINI_SCAN_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
const GEMINI_TEXT_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

// --- Gemini request queue + retry-with-backoff -----------------------------
// The free Gemini tier's quota is shared across everyone using the same
// model/key, not just your own users. Two things happen in production that
// don't show up when testing alone:
//   1. Several users scanning at once can all fire requests in the same
//      instant, which is exactly the kind of burst that trips a 429.
//   2. A single 429 from Gemini doesn't mean "give up" — it usually means
//      "wait a moment," and retrying after a short delay often succeeds.
// GEMINI_MAX_CONCURRENT caps how many Gemini requests this server has in
// flight at once (extra requests wait in line instead of piling on top of
// each other). GEMINI_MAX_RETRIES adds automatic backoff retries on top of
// that, so a transient 429/503 resolves itself instead of failing the
// user's scan outright.
const GEMINI_MAX_CONCURRENT = Number(process.env.GEMINI_MAX_CONCURRENT || 2);
const GEMINI_MAX_RETRIES = Number(process.env.GEMINI_MAX_RETRIES || 3);
const GEMINI_BASE_DELAY_MS = Number(process.env.GEMINI_BASE_DELAY_MS || 2000);

let geminiActiveCount = 0;
const geminiWaitQueue = [];

function acquireGeminiSlot() {
  if (geminiActiveCount < GEMINI_MAX_CONCURRENT) {
    geminiActiveCount++;
    return Promise.resolve();
  }
  return new Promise((resolve) => geminiWaitQueue.push(resolve));
}

function releaseGeminiSlot() {
  const next = geminiWaitQueue.shift();
  if (next) {
    next(); // hand the slot straight to the next queued request
  } else {
    geminiActiveCount--;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableGeminiStatus(status) {
  // 429 = rate limited / quota exceeded, 503 = model temporarily overloaded.
  return status === 429 || status === 503;
}

function retryDelayMsFromResponse(response, attempt) {
  const retryAfter = response.headers.get('retry-after');
  const parsed = Number(retryAfter);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed * 1000;
  }
  return GEMINI_BASE_DELAY_MS * Math.pow(2, attempt); // 2s, 4s, 8s...
}

/**
 * Calls a Gemini generateContent endpoint, queueing behind
 * GEMINI_MAX_CONCURRENT other in-flight Gemini calls, and automatically
 * retrying with backoff (up to GEMINI_MAX_RETRIES total attempts) when
 * Gemini responds with a rate-limit/overload status. Returns the same
 * shape node-fetch's response.json() would, plus the final http status.
 */
async function callGeminiWithRetry(url, body) {
  await acquireGeminiSlot();
  try {
    let lastResponse;
    let lastData;
    for (let attempt = 0; attempt < GEMINI_MAX_RETRIES; attempt++) {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await response.json();

      if (response.ok || !isRetryableGeminiStatus(response.status)) {
        return { status: response.status, data };
      }

      lastResponse = response;
      lastData = data;

      const isLastAttempt = attempt === GEMINI_MAX_RETRIES - 1;
      if (isLastAttempt) break;

      const delay = retryDelayMsFromResponse(response, attempt);
      console.warn(
        `Gemini ${response.status}, retrying in ${delay}ms (attempt ${attempt + 1}/${GEMINI_MAX_RETRIES})`,
      );
      await sleep(delay);
    }
    return { status: lastResponse.status, data: lastData };
  } finally {
    releaseGeminiSlot();
  }
}

const TBA_AUTH_KEY = process.env.TBA_AUTH_KEY;
const TBA_BASE = 'https://www.thebluealliance.com/api/v3';
const NOTIFY_WINDOW_MIN = 12; // how late past start time we'll still fire the "starting" alert
const FINAL_SCORE_WINDOW_MIN = 20; // how late after the match we'll still fire the final-score alert

// Five separate alerts per match, keyed off minutes-until-predicted-start:
//   queue:   fires once the match is <=15 min out (but still >10 min out) — "you're on queue"
//   matchup: fires once the match is <=10 min out (but still >5 min out) — win prob + who to defend
//   field:   fires once the match is <=5 min out (but hasn't started yet) — "be on the field"
//   start:   fires once the match's predicted time has arrived (up to
//            NOTIFY_WINDOW_MIN minutes late, in case a check gets missed) — "game starting"
//   final:   fires once scores are posted (handled separately below, not
//            part of this minutes-away table, since it's keyed off the
//            match being played rather than off a countdown window)
// Each stage is dedup'd independently (see notifiedMatchesCollection below),
// so a single match can send up to five notifications as it approaches and
// resolves.
const NOTIFY_STAGES = [
  { stage: 'queue', minMinutesAway: 10, maxMinutesAway: 15 },
  { stage: 'matchup', minMinutesAway: 5, maxMinutesAway: 10 },
  { stage: 'field', minMinutesAway: 0, maxMinutesAway: 5 },
  { stage: 'start', minMinutesAway: -NOTIFY_WINDOW_MIN, maxMinutesAway: 0 },
];

function stageForMinutesAway(minsAway) {
  for (const { stage, minMinutesAway, maxMinutesAway } of NOTIFY_STAGES) {
    if (minsAway > minMinutesAway && minsAway <= maxMinutesAway) return stage;
  }
  return null;
}

/// Predicted margin -> win probability via a logistic curve. SCALE is the
/// point spread (in OPR points) at which the favored alliance is projected
/// to win about 88% of the time — tuned loosely for typical FRC OPR spreads,
/// not derived from real match data.
const WIN_PROB_SCALE = 12;

function allianceOpr(oprMap, teamKeys) {
  return teamKeys.reduce((sum, key) => sum + (oprMap[key] || 0), 0);
}

/// Builds the "who's favored, who to defend" context for the matchup-stage
/// alert. Returns null if we don't have OPR data for this match's teams.
function buildMatchupContext(match, teamKey, oprMap) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const myAlliance = onRed ? match.alliances.red.team_keys : match.alliances.blue.team_keys;
  const oppAlliance = onRed ? match.alliances.blue.team_keys : match.alliances.red.team_keys;
  if (!myAlliance || !oppAlliance) return null;

  const myOpr = allianceOpr(oprMap, myAlliance);
  const oppOpr = allianceOpr(oprMap, oppAlliance);
  const winProbPct = Math.round(
    (1 / (1 + Math.exp(-(myOpr - oppOpr) / WIN_PROB_SCALE))) * 100,
  );

  let topOpponentKey = null;
  for (const key of oppAlliance) {
    if (key === teamKey) continue;
    if (topOpponentKey === null || (oprMap[key] || 0) > (oprMap[topOpponentKey] || 0)) {
      topOpponentKey = key;
    }
  }

  return {
    winProbPct,
    topOpponentNumber: topOpponentKey ? topOpponentKey.replace(/^frc/, '') : null,
  };
}

/// "Team 4388 won 34-28." style summary for the post-match alert. Returns
/// null if scores aren't actually present (shouldn't happen given the
/// caller already checked `played`, but keeps this defensive).
function finalScoreSummary(match, teamKey) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const myScore = onRed ? match.alliances?.red?.score : match.alliances?.blue?.score;
  const oppScore = onRed ? match.alliances?.blue?.score : match.alliances?.red?.score;
  if (myScore == null || oppScore == null) return null;
  const teamNumber = teamKey.replace(/^frc/, '');
  const result = myScore > oppScore ? 'won' : myScore < oppScore ? 'lost' : 'tied';
  return `Team ${teamNumber} ${result} ${myScore}-${oppScore}.`;
}

function notificationForStage(teamNumber, label, stage, extra = {}) {
  switch (stage) {
    case 'queue':
      return {
        title: `Team ${teamNumber}: ${label} in 15 min`,
        body: "You're on queue — head to the queuing line.",
      };
    case 'matchup': {
      const { winProbPct, topOpponentNumber } = extra;
      const parts = [];
      if (winProbPct != null) parts.push(`You're favored to win about ${winProbPct}% of the time.`);
      if (topOpponentNumber) parts.push(`Watch Team ${topOpponentNumber} on the other alliance — they're projected to contribute the most, so they're the one to defend.`);
      return {
        title: `Team ${teamNumber}: ${label} in 10 min`,
        body: parts.length ? parts.join(' ') : 'Your match is coming up in 10 minutes.',
      };
    }
    case 'field':
      return {
        title: `Team ${teamNumber}: ${label} in 5 min`,
        body: 'Be on the field — your match starts in 5 minutes.',
      };
    case 'start':
      return {
        title: `Team ${teamNumber}: ${label} is starting`,
        body: 'Game starting now!',
      };
    case 'final':
      return {
        title: `Team ${teamNumber}: ${label} final score`,
        body: extra.summary || 'Your match has finished.',
      };
    default:
      return {
        title: `Team ${teamNumber}: ${label}`,
        body: 'Match update.',
      };
  }
}

// ---- Fake test competition (dev/testing aid) ------------------------------
// Setting your team number to "-4388" in the app opts into a synthetic
// "event" that never touches TBA. It exists purely so push notifications
// can be verified end-to-end without waiting for a real match.
//
// Everything (past matches, the one upcoming match, OPRs, team list) is
// driven off ONE clock-aligned bucket: FAKE_MATCH_INTERVAL_MS. A match
// lands on every interval boundary — with a 10-minute interval that's
// :00, :10, :20, :30, :40, :50 — and the "upcoming" match is always the
// next boundary ahead, counting down from 10 minutes to 0 in real time.
// Because match_number is just the bucket index, refreshing mid-countdown
// always shows the same match with a smaller number-of-minutes-away, never
// a different match — there used to be a second, independent 15-minute
// cycle just for the upcoming match, which is what caused it to look like
// a different match each time you reopened the screen.
//
// Everything below is generated on the fly; the only things actually
// written to Mongo are the normal push subscription row and the usual
// notifiedMatches dedup rows.
const FAKE_TEAM_NUMBER = '-4388';
const FAKE_TEAM_KEY = `frc${FAKE_TEAM_NUMBER}`;
const FAKE_EVENT_KEY = 'faketest2026';
const FAKE_MATCH_INTERVAL_MS = 10 * 60 * 1000; // one match every 10 minutes, aligned to the clock

function isFakeTeamNumber(teamNumber) {
  return cleanString(teamNumber) === FAKE_TEAM_NUMBER;
}

function fakeCurrentBucket() {
  return Math.floor(Date.now() / FAKE_MATCH_INTERVAL_MS);
}

function fakeOpponentNumber(bucket, slot) {
  return String(1000 + (((bucket * 7) + (slot * 13)) % 8000));
}

function fakeEvent() {
  const now = Date.now();
  const iso = (ms) => new Date(ms).toISOString().slice(0, 10);
  return {
    key: FAKE_EVENT_KEY,
    name: 'RoboLens Test Event (fake \u2014 team -4388 only)',
    start_date: iso(now - 24 * 60 * 60 * 1000),
    end_date: iso(now + 24 * 60 * 60 * 1000),
    city: 'Testville',
    state_prov: 'CO',
    country: 'USA',
  };
}

function fakeMatchAllianceKeys(bucket) {
  const onRed = bucket % 2 === 0;
  const partner = `frc${fakeOpponentNumber(bucket, 1)}`;
  const opp1 = `frc${fakeOpponentNumber(bucket, 2)}`;
  const opp2 = `frc${fakeOpponentNumber(bucket, 3)}`;
  return {
    red: onRed ? [FAKE_TEAM_KEY, partner] : [opp1, opp2],
    blue: onRed ? [opp1, opp2] : [FAKE_TEAM_KEY, partner],
  };
}

// The next match: predicted_time is pinned to the next FAKE_MATCH_INTERVAL_MS
// clock boundary, so it counts down from 10 minutes away to 0 in real time,
// then the bucket rolls over and a fresh match (new key) begins.
function fakeUpcomingMatch(bucket) {
  const teams = fakeMatchAllianceKeys(bucket);
  const predictedTimeSec = Math.floor(((bucket + 1) * FAKE_MATCH_INTERVAL_MS) / 1000);
  return {
    key: `${FAKE_EVENT_KEY}_qm${bucket}`,
    comp_level: 'qm',
    match_number: bucket,
    set_number: 1,
    predicted_time: predictedTimeSec,
    actual_time: null,
    alliances: {
      red: { team_keys: teams.red, score: -1 },
      blue: { team_keys: teams.blue, score: -1 },
    },
  };
}

function fakePlayedMatch(bucket, matchesAgo) {
  const teams = fakeMatchAllianceKeys(bucket);
  const playedAt = Math.floor(Date.now() / 1000) - matchesAgo * (FAKE_MATCH_INTERVAL_MS / 1000);
  const redScore = 20 + (bucket % 30);
  const blueScore = 18 + ((bucket * 3) % 30);
  return {
    key: `${FAKE_EVENT_KEY}_qm${bucket}`,
    comp_level: 'qm',
    match_number: bucket,
    set_number: 1,
    predicted_time: playedAt,
    actual_time: playedAt,
    alliances: {
      red: { team_keys: teams.red, score: redScore },
      blue: { team_keys: teams.blue, score: blueScore },
    },
  };
}

// A short fake history plus the one always-upcoming match, so the schedule
// screen looks like a real quals list instead of a single lonely match.
function fakeMatches() {
  const current = fakeCurrentBucket();
  const matches = [];
  for (let i = 4; i >= 1; i--) {
    matches.push(fakePlayedMatch(current - i, i));
  }
  matches.push(fakeUpcomingMatch(current));
  return matches;
}

function fakeOprs() {
  const bucket = fakeCurrentBucket();
  const oprs = { [FAKE_TEAM_KEY]: 32.5 };
  for (let slot = 1; slot <= 3; slot++) {
    oprs[`frc${fakeOpponentNumber(bucket, slot)}`] = 20 + slot * 4;
  }
  return oprs;
}

function fakeStatus() {
  return {
    qual: {
      ranking: { rank: 3, record: { wins: 4, losses: 1, ties: 0 } },
      num_teams: 9,
    },
  };
}

function fakeEventTeamsList() {
  const bucket = fakeCurrentBucket();
  const numbers = [FAKE_TEAM_NUMBER];
  for (let i = 0; i <= 4; i++) {
    for (let slot = 1; slot <= 3; slot++) numbers.push(fakeOpponentNumber(bucket - i, slot));
  }
  return [...new Set(numbers)].map((n) => ({
    team_number: n,
    name: n === FAKE_TEAM_NUMBER ? 'Ridgebotics (test)' : `Team ${n}`,
  }));
}

function fakeEventStats() {
  return fakeEventTeamsList().map((t, index) => ({
    team_number: t.team_number,
    name: t.name,
    opr: t.team_number === FAKE_TEAM_NUMBER ? 32.5 : 18 + (index % 5) * 3,
    rank: index + 1,
    wins: 4,
    losses: 1,
    ties: 0,
  }));
}

const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.VAPID_SUBJECT;
const PUSH_CHECK_SECRET = process.env.PUSH_CHECK_SECRET;
const REPORTS_ADMIN_SECRET = process.env.REPORTS_ADMIN_SECRET;

const webpushConfigured = Boolean(VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY && VAPID_SUBJECT);
if (webpushConfigured) {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
} else {
  console.warn('VAPID keys not fully configured — /push/* routes will be disabled');
}

if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI');
  process.exit(1);
}

const corsOptions = {
  origin: FRONTEND_ORIGIN,
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'X-Reports-Admin-Secret'],
};

app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '50mb' }));

const mongoClient = new MongoClient(MONGODB_URI);
let teamsCollection;
let batteriesCollection;
let pushSubscriptionsCollection;
let notifiedMatchesCollection;
let eventRostersCollection;
let reportsCollection;
let worldRatingsCollection;
let eventTeamsCollection;
let countersCollection;
let worldRatingRefresh;

async function connectToMongo() {
  await mongoClient.connect();

  const db = mongoClient.db(DB_NAME);
  teamsCollection = db.collection('teams');
  batteriesCollection = db.collection('batteries');
  pushSubscriptionsCollection = db.collection('pushSubscriptions');
  notifiedMatchesCollection = db.collection('notifiedMatches');
  eventRostersCollection = db.collection('eventRosters');
  reportsCollection = db.collection('reports');
  worldRatingsCollection = db.collection('worldRatings');
  eventTeamsCollection = db.collection('eventTeams');
  countersCollection = db.collection('counters');

  await teamsCollection.createIndex({ teamNumber: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, label: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, lastUsedAt: 1 });
  await pushSubscriptionsCollection.createIndex({ endpoint: 1 }, { unique: true });
  await pushSubscriptionsCollection.createIndex({ teamNumber: 1, eventKey: 1 });
  await notifiedMatchesCollection.createIndex(
    { teamNumber: 1, eventKey: 1, matchKey: 1 },
    { unique: true },
  );
  await eventRostersCollection.createIndex({ teamNumber: 1, eventKey: 1 }, { unique: true });
  await reportsCollection.createIndex({ createdAt: -1 });
  await reportsCollection.createIndex({ findingType: 1, errorType: 1, createdAt: -1 });
  await reportsCollection.createIndex({ scanId: 1, findingId: 1 });
  await worldRatingsCollection.createIndex({ refreshedAt: -1 });
  await eventTeamsCollection.createIndex({ refreshedAt: -1 });

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

async function tbaGet(path) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  let res;
  try {
    res = await fetch(`${TBA_BASE}${path}`, {
      headers: { 'X-TBA-Auth-Key': TBA_AUTH_KEY }, signal: controller.signal,
    });
  } catch (err) {
    if (err.name === 'AbortError') {
      const timeoutError = new Error(`TBA ${path} timed out`);
      timeoutError.status = 504;
      throw timeoutError;
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }
  if (!res.ok) {
    const err = new Error(`TBA ${path} failed: ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}


async function tbaGetOprs(eventKey) {
  try {
    const data = await tbaGet(`/event/${eventKey}/oprs`);
    return data && typeof data === 'object' ? data : { oprs: {} };
  } catch (err) {
    return { oprs: {} };
  }
}

function cleanString(value) {
  if (value === undefined || value === null) return null;
  const cleaned = String(value).trim();
  return cleaned || null;
}

function checkReportsAdmin(req, res) {
  if (!REPORTS_ADMIN_SECRET) {
    res.status(503).json({ error: 'Report dashboard is not configured' });
    return false;
  }
  if (req.get('X-Reports-Admin-Secret') !== REPORTS_ADMIN_SECRET) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
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

// --- All-time scan counter --------------------------------------------
// One document (_id: 'scans') in the "counters" collection, incremented
// atomically with $inc every time a scan actually completes successfully
// (physical scan and rules scan both hit /analyzeImage, so counting there
// covers both without needing to know which mode the request was). This is
// a simple lifetime total — not broken down by day/week/year.
async function incrementScanCount() {
  if (!countersCollection) return;
  try {
    await countersCollection.updateOne(
      { _id: 'scans' },
      { $inc: { count: 1 } },
      { upsert: true },
    );
  } catch (err) {
    // Never let counter bookkeeping fail a real scan request.
    console.error('Scan counter increment failed:', err);
  }
}

app.get('/', (req, res) => {
  res.send('Backend running');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    mongo: Boolean(teamsCollection && batteriesCollection),
    reportsMongo: Boolean(reportsCollection),
    geminiConfigured: Boolean(GEMINI_API_KEY),
    tbaConfigured: Boolean(TBA_AUTH_KEY),
    webpushConfigured,
  });
});

app.get('/scans/count', async (req, res) => {
  if (!countersCollection) {
    return res.status(503).json({ error: 'Scan counter is not configured' });
  }
  try {
    const doc = await countersCollection.findOne({ _id: 'scans' });
    res.json({ totalScans: doc?.count || 0 });
  } catch (err) {
    console.error('Scan count fetch error:', err);
    res.status(500).json({ error: 'Could not load scan count' });
  }
});

app.post('/analyzeImage', async (req, res) => {
  try {
    if (!GEMINI_API_KEY) {
      return res.status(503).json({ error: 'GEMINI_API_KEY is not configured on the server' });
    }

    const { status, data } = await callGeminiWithRetry(
      `${GEMINI_SCAN_URL}?key=${GEMINI_API_KEY}`,
      req.body,
    );
    if (status >= 200 && status < 300) {
      // Fire-and-forget: don't make the user wait on counter bookkeeping.
      incrementScanCount();
    }
    res.status(status).json(data);
  } catch (err) {
    console.error('Analyze image error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/reportFinding', async (req, res) => {
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }

  const title = cleanString(req.body.title);
  const scanId = cleanString(req.body.scanId);
  const findingId = cleanString(req.body.findingId);
  const errorType = cleanString(req.body.errorType) || 'other';
  const allowedErrorTypes = new Set([
    'false_positive',
    'wrong_location',
    'wrong_description',
    'missed_problem',
    'other',
  ]);

  if (!title || !scanId || !findingId) {
    return res.status(400).json({ error: 'scanId, findingId, and title are required' });
  }
  if (!allowedErrorTypes.has(errorType)) {
    return res.status(400).json({ error: 'Invalid errorType' });
  }

  const report = {
    scanId,
    findingId,
    scanMode: cleanString(req.body.scanMode) || 'physical',
    errorType,
    findingType: title.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, ''),
    title,
    description: cleanString(req.body.description) || '',
    userComment: cleanString(req.body.userComment) || '',
    severity: cleanString(req.body.severity) || 'unknown',
    status: 'pending',
    createdAt: new Date(),
  };

  try {
    const result = await reportsCollection.insertOne(report);
    res.status(201).json({ ok: true, reportId: result.insertedId.toString() });
  } catch (err) {
    console.error('Report finding error:', err);
    res.status(500).json({ error: 'Could not save report' });
  }
});

app.get('/reports', async (req, res) => {
  if (!checkReportsAdmin(req, res)) return;
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }
  try {
    const reports = await reportsCollection.find({}).sort({ createdAt: -1 }).limit(50).toArray();
    res.json({ reports });
  } catch (err) {
    console.error('List reports error:', err);
    res.status(500).json({ error: 'Could not load reports' });
  }
});

app.get('/reports/summary', async (req, res) => {
  if (!checkReportsAdmin(req, res)) return;
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }
  try {
    const summary = await reportsCollection.aggregate([
      { $group: { _id: { findingType: '$findingType', errorType: '$errorType' }, count: { $sum: 1 } } },
      { $sort: { count: -1 } },
    ]).toArray();
    res.json({ summary });
  } catch (err) {
    console.error('Report summary error:', err);
    res.status(500).json({ error: 'Could not load report summary' });
  }
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

    const { status, data } = await callGeminiWithRetry(
      `${GEMINI_TEXT_URL}?key=${GEMINI_API_KEY}`,
      {
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
      },
    );
    const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text
      ?.replace(/```json/g, '')
      ?.replace(/```/g, '')
      ?.trim();

    if (status < 200 || status >= 300 || !rawText) {
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

app.get('/match/events', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const year = cleanString(req.query.year);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json([fakeEvent()]);
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber || !year) {
    return res.status(400).json({ error: 'teamNumber and year are required' });
  }

  try {
    const events = await tbaGet(`/team/frc${teamNumber}/events/${year}/simple`);
    res.json(events);
  } catch (err) {
    console.error('Match events error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load events' });
  }
});


app.get('/events', async (req, res) => {
  const year = cleanString(req.query.year) || String(new Date().getFullYear());

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }

  try {
    const events = await tbaGet(`/events/${year}/simple`);
    res.json(events);
  } catch (err) {
    console.error('Events list error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load events' });
  }
});

app.get('/match/data', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const eventKey = cleanString(req.query.eventKey);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json({ matches: fakeMatches(), oprs: fakeOprs(), status: fakeStatus() });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber || !eventKey) {
    return res.status(400).json({ error: 'teamNumber and eventKey are required' });
  }

  const teamKey = `frc${teamNumber}`;
  try {
    const [matches, oprs, status] = await Promise.all([
      tbaGet(`/team/${teamKey}/event/${eventKey}/matches/simple`),
      tbaGetOprs(eventKey),
      tbaGet(`/team/${teamKey}/event/${eventKey}/status`).catch(() => null),
    ]);
    res.json({
      matches,
      oprs: oprs.oprs || {},
      status,
    });
  } catch (err) {
    console.error('Match data error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load match data' });
  }
});


app.get('/event/matches', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json({ matches: fakeMatches() });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const matches = await tbaGet(`/event/${eventKey}/matches/simple`);
    res.json({ matches });
  } catch (err) {
    console.error('Event matches error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event matches' });
  }
});

app.get('/event/alliances', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json({ alliances: [] });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const alliances = await tbaGet(`/event/${eventKey}/alliances`);
    res.json({ alliances: alliances || [] });
  } catch (err) {
    console.error('Event alliances error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event alliances' });
  }
});

app.get('/event/roster', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const eventKey = cleanString(req.query.eventKey);

  if (!teamNumber || !eventKey) {
    return res.status(400).json({ error: 'teamNumber and eventKey are required' });
  }

  try {
    const doc = await eventRostersCollection.findOne({ teamNumber, eventKey });
    res.json({ people: doc?.people || [] });
  } catch (err) {
    console.error('Roster fetch error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/event/roster/add', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const eventKey = cleanString(req.body.eventKey);
    const name = cleanString(req.body.name);
    if (!eventKey || !name) {
      return res.status(400).json({ error: 'eventKey and name are required' });
    }

    await eventRostersCollection.updateOne(
      { teamNumber: team.teamNumber, eventKey },
      { $addToSet: { people: name }, $set: { updatedAt: new Date().toISOString() } },
      { upsert: true },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Roster add error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/event/roster/remove', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const eventKey = cleanString(req.body.eventKey);
    const name = cleanString(req.body.name);
    if (!eventKey || !name) {
      return res.status(400).json({ error: 'eventKey and name are required' });
    }

    await eventRostersCollection.updateOne(
      { teamNumber: team.teamNumber, eventKey },
      { $pull: { people: name }, $set: { updatedAt: new Date().toISOString() } },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Roster remove error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/push/config', (req, res) => {
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not configured on the server' });
  }
  res.json({ vapidPublicKey: VAPID_PUBLIC_KEY });
});

app.post('/push/subscribe', async (req, res) => {
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not configured on the server' });
  }

  const teamNumber = cleanString(req.body.teamNumber);
  const eventKey = cleanString(req.body.eventKey);
  const subscription = req.body.subscription;

  if (!teamNumber || !eventKey || !subscription?.endpoint) {
    return res.status(400).json({ error: 'Missing fields' });
  }

  try {
    await pushSubscriptionsCollection.updateOne(
      { endpoint: subscription.endpoint },
      { $set: { teamNumber, eventKey, subscription, updatedAt: new Date().toISOString() } },
      { upsert: true },
    );
    let testSent = false;
    try {
      await webpush.sendNotification(subscription, JSON.stringify({
        title: 'RoboLens alerts are on',
        body: `You will get a reminder before Team ${teamNumber}'s matches.`,
        url: '/',
      }));
      testSent = true;
    } catch (err) {
      console.warn('Push test notification failed:', err.message);
    }
    res.json({ ok: true, testSent });
  } catch (err) {
    console.error('Push subscribe error:', err);
    res.status(500).json({ error: 'Could not save subscription' });
  }
});

app.post('/push/unsubscribe', async (req, res) => {
  const endpoint = cleanString(req.body.endpoint);
  if (!endpoint) {
    return res.status(400).json({ error: 'endpoint required' });
  }

  try {
    await pushSubscriptionsCollection.deleteOne({ endpoint });
    res.json({ ok: true });
  } catch (err) {
    console.error('Push unsubscribe error:', err);
    res.status(500).json({ error: 'Could not remove subscription' });
  }
});

app.get('/push/check', async (req, res) => {
  // NOTE: this used to also require TBA_AUTH_KEY, which shut the whole
  // route down (503, nothing ever sent, for every team including the
  // fake -4388 tester) whenever TBA_AUTH_KEY wasn't set — even though the
  // fake-team path below never calls TBA at all. Real-team groups already
  // catch their own TBA failures per-group further down, so the route only
  // needs webpush configured to do anything.
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not fully configured' });
  }
  if (!PUSH_CHECK_SECRET || req.query.secret !== PUSH_CHECK_SECRET) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  try {
    const subs = await pushSubscriptionsCollection.find({}).toArray();
    if (subs.length === 0) {
      return res.json({ checked: 0, sent: 0 });
    }

    const groups = new Map();
    for (const sub of subs) {
      const key = `${sub.teamNumber}|${sub.eventKey}`;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(sub);
    }

    let sent = 0;
    for (const [key, groupSubs] of groups) {
      const [teamNumber, eventKey] = key.split('|');
      const teamKey = `frc${teamNumber}`;
      const isFake = isFakeTeamNumber(teamNumber) && eventKey === FAKE_EVENT_KEY;

      let matches;
      if (isFake) {
        matches = fakeMatches();
      } else {
        if (!TBA_AUTH_KEY) continue; // can't check real events without a TBA key
        try {
          matches = await tbaGet(`/team/${teamKey}/event/${eventKey}/matches/simple`);
        } catch (err) {
          continue;
        }
      }

      const now = Date.now();
      const label = (match) =>
        match.comp_level === 'qm'
          ? `Quals ${match.match_number}`
          : `${match.comp_level.toUpperCase()} ${match.match_number}`;

      // Lazily fetched (and cached per group) since only the 'matchup'
      // stage needs OPRs — no point calling TBA for a group whose next
      // check only lands on the queue/field/start/final stages.
      let oprMapPromise = null;
      const getOprMap = () => {
        if (!oprMapPromise) {
          oprMapPromise = isFake
            ? Promise.resolve(fakeOprs())
            : tbaGetOprs(eventKey).then((data) => data.oprs || {});
        }
        return oprMapPromise;
      };

      for (const match of matches) {
        const played =
          match.alliances?.red?.score >= 0 && match.alliances?.blue?.score >= 0;

        if (played) {
          // Post-match final-score alert. Keyed off the match actually
          // being played rather than the countdown table above, and
          // windowed so a backlog of long-past matches (e.g. the fake
          // team's synthetic match history) doesn't all fire the first
          // time this route runs.
          const matchTimeSec = match.actual_time || match.predicted_time;
          if (!matchTimeSec) continue;
          const minsSincePlayed = (now - matchTimeSec * 1000) / 60000;
          if (minsSincePlayed < 0 || minsSincePlayed > FINAL_SCORE_WINDOW_MIN) continue;

          try {
            await notifiedMatchesCollection.insertOne({
              teamNumber,
              eventKey,
              matchKey: `${match.key}::final`,
            });
          } catch (err) {
            continue; // already sent the final score for this match
          }

          const summary = finalScoreSummary(match, teamKey);
          const { title, body } = notificationForStage(teamNumber, label(match), 'final', { summary });
          const payload = JSON.stringify({ title, body, url: '/' });
          for (const sub of groupSubs) {
            try {
              await webpush.sendNotification(sub.subscription, payload);
              sent++;
            } catch (err) {
              if (err.statusCode === 404 || err.statusCode === 410) {
                await pushSubscriptionsCollection.deleteOne({ endpoint: sub.subscription.endpoint });
              }
            }
          }
          continue;
        }

        if (!match.predicted_time) continue;

        const minsAway = (match.predicted_time * 1000 - now) / 60000;
        const stage = stageForMinutesAway(minsAway);
        if (!stage) continue;

        // Each match can fire up to four pre-match times (queue, matchup,
        // field, start) plus one post-match (final) — dedup per stage, not
        // just per match, by folding the stage into the matchKey we
        // insert. The unique index is still just
        // {teamNumber, eventKey, matchKey}, so this needs no schema change.
        try {
          await notifiedMatchesCollection.insertOne({
            teamNumber,
            eventKey,
            matchKey: `${match.key}::${stage}`,
          });
        } catch (err) {
          continue; // already sent this match's alert for this stage
        }

        let extra = {};
        if (stage === 'matchup') {
          try {
            const oprMap = await getOprMap();
            extra = buildMatchupContext(match, teamKey, oprMap) || {};
          } catch (err) {
            extra = {};
          }
        }

        const { title, body } = notificationForStage(teamNumber, label(match), stage, extra);
        const payload = JSON.stringify({ title, body, url: '/' });

        for (const sub of groupSubs) {
          try {
            await webpush.sendNotification(sub.subscription, payload);
            sent++;
          } catch (err) {
            if (err.statusCode === 404 || err.statusCode === 410) {
              await pushSubscriptionsCollection.deleteOne({
                endpoint: sub.subscription.endpoint,
              });
            }
          }
        }
      }
    }

    res.json({ checked: groups.size, sent });
  } catch (err) {
    console.error('Push check error:', err);
    res.status(500).json({ error: 'Check failed' });
  }
});

app.get('/event/stats', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json(fakeEventStats());
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const [teams, rankings, oprData] = await Promise.all([
      tbaGet(`/event/${eventKey}/teams/simple`),
      tbaGet(`/event/${eventKey}/rankings`).catch(() => ({ rankings: [] })),
      tbaGetOprs(eventKey),
    ]);
    const names = new Map(teams.map((team) => [team.key, team.nickname || `Team ${team.team_number}`]));
    const rankingByTeam = new Map((rankings.rankings || []).map((ranking) => [ranking.team_key, ranking]));
    const teamKeys = new Set([...names.keys(), ...Object.keys(oprData.oprs || {})]);

    const stats = [...teamKeys].map((teamKey) => {
      const ranking = rankingByTeam.get(teamKey);
      const record = ranking?.record || {};
      return {
        team_number: teamKey.replace(/^frc/, ''),
        name: names.get(teamKey) || `Team ${teamKey.replace(/^frc/, '')}`,
        opr: Number(oprData.oprs?.[teamKey] || 0),
        rank: ranking?.rank ?? 0,
        wins: record.wins || 0,
        losses: record.losses || 0,
        ties: record.ties || 0,
      };
    });
    stats.sort((a, b) => (a.rank || Number.MAX_SAFE_INTEGER) - (b.rank || Number.MAX_SAFE_INTEGER) || b.opr - a.opr);
    res.json(stats);
  } catch (err) {
    console.error('Event stats error:', err.message);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event stats' });
  }
});

const WORLD_RATING_CACHE_MS = 12 * 60 * 60 * 1000;

async function mapWithConcurrency(items, limit, work) {
  const results = [];
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const index = next++;
      try {
        results.push(await work(items[index]));
      } catch (err) {
        console.warn(`World rating skipped ${items[index].key}: ${err.message}`);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

async function rebuildWorldRatings(year) {
  const events = await tbaGet(`/events/${year}/simple`);
  const official = events.filter((event) =>
    [0, 1, 2, 3, 4].includes(event.event_type) && event.end_date &&
    new Date(`${event.end_date}T23:59:59Z`) <= new Date(),
  );
  const eventRows = await mapWithConcurrency(official, 6, async (event) => {
    const [teams, oprData, rankings] = await Promise.all([
      tbaGet(`/event/${event.key}/teams/simple`),
      tbaGetOprs(event.key),
      tbaGet(`/event/${event.key}/rankings`).catch(() => ({ rankings: [] })),
    ]);
    const names = new Map(teams.map((team) => [team.key, team.nickname || `Team ${team.team_number}`]));
    const records = new Map((rankings.rankings || []).map((r) => [r.team_key, r.record || {}]));
    return Object.entries(oprData.oprs || {}).map(([teamKey, rawOpr]) => {
      const record = records.get(teamKey) || {};
      const played = (record.wins || 0) + (record.losses || 0) + (record.ties || 0);
      return { teamKey, name: names.get(teamKey) || `Team ${teamKey.replace(/^frc/, '')}`,
        opr: Number(rawOpr || 0), weight: Math.max(1, played),
        wins: record.wins || 0, losses: record.losses || 0, ties: record.ties || 0 };
    });
  });
  const totals = new Map();
  for (const rows of eventRows) for (const row of rows) {
    const old = totals.get(row.teamKey) || { ...row, weightedOpr: 0, weightTotal: 0, wins: 0, losses: 0, ties: 0 };
    old.name = row.name;
    old.weightedOpr += row.opr * row.weight;
    old.weightTotal += row.weight;
    old.wins += row.wins; old.losses += row.losses; old.ties += row.ties;
    totals.set(row.teamKey, old);
  }
  const teams = [...totals.values()].map((row) => ({
    team_number: row.teamKey.replace(/^frc/, ''), name: row.name,
    opr: Number((row.weightedOpr / row.weightTotal).toFixed(2)),
    wins: row.wins, losses: row.losses, ties: row.ties,
  })).sort((a, b) => b.opr - a.opr);
  teams.forEach((team, index) => { team.rank = index + 1; });
  const doc = { _id: String(year), year, teams, refreshedAt: new Date(), eventCount: official.length };
  await worldRatingsCollection.replaceOne({ _id: doc._id }, doc, { upsert: true });
  return doc;
}

function startWorldRatingRefresh(year) {
  if (!worldRatingRefresh) {
    worldRatingRefresh = rebuildWorldRatings(year)
      .catch((err) => console.error('World rating refresh failed:', err.message))
      .finally(() => { worldRatingRefresh = null; });
  }
  return worldRatingRefresh;
}

app.get('/world/stats', async (req, res) => {
  if (!TBA_AUTH_KEY) return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  const year = Number(cleanString(req.query.year) || new Date().getFullYear());
  try {
    const cached = await worldRatingsCollection.findOne({ _id: String(year) });
    const stale = !cached || Date.now() - new Date(cached.refreshedAt).getTime() > WORLD_RATING_CACHE_MS;
    if (stale) startWorldRatingRefresh(year);
    if (cached) return res.json({ teams: cached.teams, year, eventCount: cached.eventCount, refreshedAt: cached.refreshedAt, refreshing: stale });
    res.status(202).json({ teams: [], year, refreshing: true, message: 'World rating is being calculated. Try again shortly.' });
  } catch (err) {
    console.error('World stats error:', err.message);
    res.status(500).json({ error: 'Could not load world stats' });
  }
});


app.get('/world/team/:teamNumber', async (req, res) => {
  const year = String(new Date().getFullYear());
  try {
    const cached = await worldRatingsCollection.findOne({ _id: year });
    if (!cached) return res.status(202).json({ error: 'World rating is being calculated' });
    const index = cached.teams.findIndex((team) => team.team_number === req.params.teamNumber);
    if (index < 0) return res.status(404).json({ error: 'Team is not in the current world rating' });
    res.json({ team: cached.teams[index], nearby: cached.teams.slice(Math.max(0, index - 2), index + 4) });
  } catch (err) {
    res.status(500).json({ error: 'Could not load team rating' });
  }
});

app.get('/event/teams', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json(fakeEventTeamsList());
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const cached = await eventTeamsCollection.findOne({ eventKey });
    if (cached && Date.now() - new Date(cached.refreshedAt).getTime() < 6 * 60 * 60 * 1000) {
      return res.json(cached.teams);
    }
    const teams = await tbaGet(`/event/${eventKey}/teams/simple`);
    const mapped = teams
      .map((t) => ({
        team_number: String(t.team_number),
        name: t.nickname || `Team ${t.team_number}`,
      }))
      .sort((a, b) => Number(a.team_number) - Number(b.team_number));
    await eventTeamsCollection.updateOne(
      { eventKey },
      { $set: { teams: mapped, refreshedAt: new Date() } },
      { upsert: true },
    );
    res.json(mapped);
  } catch (err) {
    console.error('Event teams error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event teams' });
  }
});

app.get('/team/profile', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json({
      team_name: 'Ridgebotics (test)',
      rookie_year: new Date().getFullYear(),
      world_rank: null,
      events: [],
      awards: [],
    });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber) {
    return res.status(400).json({ error: 'teamNumber is required' });
  }

  const teamKey = `frc${teamNumber}`;
  try {
    // NOTE: the /simple variant of this endpoint does not include
    // rookie_year at all (that's why "Years" was always blank) — the full
    // team model is required to get it.
    const teamInfo = await tbaGet(`/team/${teamKey}`);
    const [yearsParticipated, awards] = await Promise.all([
      tbaGet(`/team/${teamKey}/years_participated`).catch(() => []),
      tbaGet(`/team/${teamKey}/awards`).catch(() => []),
    ]);


    const perYear = await Promise.all(
      yearsParticipated.map(async (year) => {
        try {
          const [events, statuses] = await Promise.all([
            tbaGet(`/team/${teamKey}/events/${year}/simple`),
            tbaGet(`/team/${teamKey}/events/${year}/statuses`).catch(() => ({})),
          ]);
          return events.map((event) => {
            const status = statuses[event.key];
            const ranking = status?.qual?.ranking;
            return {
              eventKey: event.key,
              eventName: event.name,
              year,
              rank: ranking?.rank ?? null,
              numTeams: status?.qual?.num_teams ?? null,
            };
          });
        } catch (err) {
          return [];
        }
      }),
    );

    const flatEvents = perYear.flat();
    const eventNameByKey = new Map(flatEvents.map((e) => [e.eventKey, e.eventName]));

    const rating = await worldRatingsCollection.findOne({ _id: String(new Date().getFullYear()) });
    const worldRank = rating?.teams?.find((team) => team.team_number === teamNumber)?.rank ?? null;

    res.json({
      team_name: teamInfo.nickname || teamInfo.name || `Team ${teamNumber}`,
      rookie_year: teamInfo.rookie_year || null,
      world_rank: worldRank,
      events: flatEvents.map((e) => ({
        event_key: e.eventKey,
        event_name: e.eventName,
        year: e.year,
        rank: e.rank,
        num_teams: e.numTeams,
        awards: awards.filter((a) => a.event_key === e.eventKey).map((a) => a.name),
      })),
      awards: awards.map((a) => ({
        name: a.name,
        event_name: eventNameByKey.get(a.event_key) || a.event_key,
        year: a.year,
      })).sort((a, b) => b.year - a.year),
    });
  } catch (err) {
    console.error('Team profile error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load team profile' });
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