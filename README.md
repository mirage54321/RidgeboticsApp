# RoboLens

An AI-powered inspection assistant and battery tracker for FRC robotics teams. Just snap a photo to get instant feedback on wiring, hardware, and rule compliance.

**[Try it live!](https://mirage54321.github.io/RoboLens/)**

This is just the README, **[view full documentation here!](https://github.com/mirage54321/RoboLens/blob/main/DOCUMENTATION.md)**

**[Look at Stardance project!](https://stardance.hackclub.com/projects/16179)**


---

## What it does

Built for a robotics team with limited hands on deck, RoboLens uses AI vision to scan a photo of your robot and flag problems a human might miss during a rushed pit-stop check. It's meant to cut down the time it takes to find an issue so your team has more time to actually fix it.

Three tools, one app:

- **Scan for issues** -> checks for loose or frayed wiring, loose screws, cracked/bent frames, corrosion, and other visible mechanical or electrical problems.
- **Check FRC rules** -> checks your robot photo against the official FRC game manual (2024-2026 supported) for things like bumper compliance, frame perimeter, and wiring rule violations.
- **Battery tracker** -> a shared, team-wide log for tracking which batteries are charged, in use, or flagged as weak, so nobody grabs a dead battery mid-match.

How to use it: go to https://mirage54321.github.io/RoboLens/, pick one of the three tools, either upload a photo or sign up as a team, tap scan or log batteries, and wait a few seconds for the AI to return its findings. Each one boxed directly on your photo so you can see exactly what it's talking about.

## How the AI works

The scanning pipeline runs in two passes instead of one, which is what makes the bounding boxes actually line up with the real issue:

1. **Detection pass** - > the full image is sent to Gemini, which returns a list of findings (title, description, severity) without worrying about exact pixel coordinates yet.
2. **Localization pass** - > for each finding, the AI first picks a rough region of the image (e.g. "bottom-left"), that region gets cropped out and zoomed in, and *then* the AI is asked to find the exact bounding box within that crop. The crop coordinates get mapped back onto the full image.

This two-step approach is more accurate than asking for one big list of exact coordinates in a single pass, especially on a full-size robot photo where a single component is a small fraction of the frame.

The Rules tool works the same way, but also feeds the actual FRC game manual PDF for the selected year into the model alongside the photo, so its answers are grounded in the real rulebook instead of general knowledge.

Both tools also pull from a small database of findings users have flagged as wrong, and pass that context back into the prompt so the AI is less likely to repeat the same mistake twice.

## How the battery tracking works

Unlike the two scanning tools, the battery tracker is a persistent, shared log rather than a one-off AI call. Each team's data lives in the cloud so the whole team sees the same up-to-date list.

1. **Team accounts** - > a team registers with a team number and a passcode, which get stored server-side. Anyone on the team can log in with those same credentials to see and update the shared battery list.
2. **Guest mode** - > anyone can view a team's batteries read-only by just entering the team number, no passcode needed. Handy for scouts or other teams checking status without needing real access.
3. **Battery state** - > each battery tracks whether it's currently charging, in use, or available, plus a timestamp for when it was last charged. Charging batteries show a live countdown based on a fixed charge time, so you can tell at a glance which one will be ready soonest.
4. **Flagging** - > any battery can be flagged as weak or unreliable with an optional note (e.g. "died after auto"), and flagged batteries stay visible with their flag history so the team knows to watch out for them.
5. **AI recommendation** - > on request, the app can ask the AI which battery to grab next based on current charge/use state, in addition to the app's own built-in "pick the most-charged available battery" logic.

Team settings also let you view or change your passcode, or wipe all battery data to start fresh for a new competition. As a small bonus, when a team registers, the backend automatically looks up their real team name via Gemini based on the team number, so the team doesn't have to type it in manually.

## Tech stack

| Layer | Tech |
|---|---|
| App | Flutter (Dart), deployed to web via GitHub Pages |
| AI | Google Gemini (vision + PDF input) |
| Backend | Node.js (Express) server on Render |
| Database | MongoDB |

## AI usage disclosure

I used Gemini as the AI model that actually scans the images and checks the rules. That's the core feature of the app. I used Claude to help debug issues and learn how to write parts of the Flutter/Dart code I wasn't familiar with yet, especially UI work, since Flutter had a steep learning curve for me.

## Progress


**Ship 1** - > Finished a foundation for the project with a simple UI and one AI tool that takes in a photo and tells you problems found in the photo whether it's with frayed wiring, loose screws, cracked/bent frames, or corrosion. 


## Why I built this

I'm on a robotics team with a small number of people, and I wanted something that could help catch physical problems on the robot faster. Plus I wanted a real excuse to work with an AI model end-to-end before starting college.