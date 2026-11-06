# Playtest kit: the relay slice (M13)

M13 is done when five people have played the slice cold and their sessions have been reviewed. This page holds the script for running a session, the observer's notes form and the questions to ask afterwards. The game records each session by itself (see "What the game records").

## Before each session

1. Use a build from the latest **Smoke test** run on `main` (see the README).
2. Note the tester's name and how much they play third-person shooters (none, some, a lot).
3. Start a **New game** on **Normal** difficulty with the **Medium** graphics preset. Leave every other setting at its default.
4. Tell the tester:
   - "Play as you would at home. Talk out loud about what you're thinking, what you're trying to do and anything that surprises you."
   - "If something confuses you, annoys you, breaks or feels great, press **F8**. It marks the moment so we can find it later."
   - "I can't help while you play. That's how we find out what the game fails to explain."
5. Stop when auxiliary power is restored on Kestrel, or after 30 minutes, whichever comes first.

## While they play

Don't help, and don't point at the screen. If the tester is stuck for 3 minutes, ask "What are you trying to do?" and note the answer. Give a hint only if they are stuck for 5 minutes, and note that you did.

Note the clock time for anything below. The game's timeline is in play time, so write the clock time when the session starts.

| Watch for | Notes |
| --- | --- |
| The crash intro: do they know who they are and what happened? | |
| First 60 seconds: do they find the red beacon and head for it? | |
| The walk to the relay: lost, bored, distracted by something? | |
| First fight: do they aim, dodge, reload and use stims without being told? | |
| Breakers and the generator: do they read the objective and prompts? | |
| The return trip: do they know to go back to Kestrel and where the aux bay is? | |
| The power-up: reaction when the lights come on (say it in their words) | |
| Anything they said out loud that stood out | |
| Bugs: what happened, and what they did just before | |

## Afterwards (5 minutes)

Ask these in order, before the tester sees anything else. Write their exact words where you can.

Score each 1 (poor) to 5 (great):

| Question | Score |
| --- | --- |
| How clear was it what to do next? | |
| How good did shooting and moving feel? | |
| How easy was the screen to read (objective, health, ammo, prompts)? | |
| How satisfying was getting the power back on? | |
| How much do you want to keep playing? | |

Open questions:

1. What was the best moment?
2. What was the most frustrating moment?
3. Was there a point where you didn't know what to do? Where?
4. What do you think the game is about, in one sentence?
5. Anything that looked or sounded wrong?

## What the game records

Each session writes a file to the `playtests` folder in the game's user folder:

- **Windows:** `%APPDATA%\Godot\app_userdata\Hard Landing\playtests`
- **Linux:** `~/.local/share/godot/app_userdata/Hard Landing/playtests`

It writes `session_<date>_<time>.json` and a `.txt` timeline next to it, updated every 30 seconds and at the end. Each session records:

- each objective and how long it took;
- the area the tester is in (Kestrel, a site, or the wilds) and how long they spent there;
- damage taken and deaths in each area, with the damage in the 10 seconds before each death;
- components picked up, repairs installed and logs found;
- every F8 flag;
- "STUCK?" when one objective runs past 5 minutes;
- frame rate (average and 5% low).

Nothing is sent anywhere.

## Reviewing the five sessions

1. Copy each tester's newest `session_*.json` into one folder, renamed after the tester (`ana.json`, `ben.json` and so on).
2. Run `python3 tools/playtest/summarise.py <folder> > summary.md`.
3. The summary lists every session, the median and slowest time for each objective, deaths and damage by area, and every flag, death and stuck point with the objective at the time.
4. Put the summary next to the notes forms. A problem that shows up for two or more testers goes on the fix list. A problem seen by one tester is worth a look if it's a bug or they quit over it.
