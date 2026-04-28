# Ball Connect

A ball-connect puzzle game. No ads, no IAP, no analytics, no tracking.

Drag a line from a colored ball to its same-color partner. Lines cannot cross
each other, cannot cross themselves, and cannot pass through other balls.
Connect every pair to win the level.

## Difficulty

Starts hard. Level 1 has 6 colour pairs on a non-grid 1080×1920 board.
Level 5 has 8 pairs in a tighter layout. Add more by dropping
`data/levels/level_NN.json` files.

## Run it

1. Install **Godot 4.4** (Standard, not Mono unless you want C#).
   - Linux: download from https://godotengine.org/, extract `Godot_v4.x_linux.x86_64`, run it.
2. Open the editor → **Import** → pick `project.godot` in this folder.
3. Press **F5** (or hit ▶). Mouse acts as touch on desktop.

## Level format

Each level is a JSON file in `data/levels/`. Coordinates are absolute pixels
referenced to a 1080×1920 viewport (the project stretch mode handles
scaling on other resolutions).

```json
{
  "level": 1,
  "ball_radius": 70,
  "balls": [
    {"color": "red",  "x": 180, "y": 350},
    {"color": "red",  "x": 900, "y": 1550},
    {"color": "blue", "x": 900, "y": 350},
    {"color": "blue", "x": 180, "y": 1550}
  ]
}
```

Each color must appear exactly twice. Supported colors are defined in
`scripts/GameManager.gd` (`COLOR_MAP`): `red`, `blue`, `green`, `yellow`,
`orange`, `pink`, `cyan`, `purple`. Add more by extending the dict.

Bump `max_level` in the Game scene's `GameManager` script export when you
add levels past 5.

## Build to APK (Phase 2 — not needed for first run)

You only need this when you want to install on your phone.

1. Install Android tooling:
   - **Android Studio** (https://developer.android.com/studio) — easiest path
     to get the SDK + JDK in one go. Open it once, let it install the default
     SDK, then close it.
   - **Android platform-tools** for `adb`:
     `sudo apt install android-tools-adb` (or use the standalone bundle from
     https://developer.android.com/tools/releases/platform-tools).
2. In Godot: **Editor → Editor Settings → Export → Android**. Set:
   - Java SDK Path → e.g. `/usr/lib/jvm/java-17-openjdk-amd64`
   - Android SDK Path → e.g. `~/Android/Sdk`
3. **Project → Export → Add… → Android**. Use the "Use Gradle Build" option
   (one-time install of build templates from the editor). Configure:
   - Package → Unique Name: `com.matswm.ballconnect`
   - Permissions: leave **all unchecked** (no internet, no nothing).
4. Click **Export Project** → produces `ball-connect.apk`.
5. Sideload: enable Developer Options on the phone, enable USB debugging,
   plug in, then `adb install ball-connect.apk`.

## File map

```
project.godot           Engine settings (1080×1920 portrait, GL Compat renderer)
icon.svg                App icon
scenes/
  Game.tscn             Root scene
  Ball.tscn             Ball template (instanced per ball)
scripts/
  GameManager.gd        Level loader, win detection, scene transitions
  LineDrawer.gd         Touch handling, polyline + segment-intersection rules
  Ball.gd               Ball draw + hit-test
data/levels/
  level_01.json         …through level_05.json
```

## Design rules (locked-in defaults)

- Free-form polyline path; sampled every 10px of finger movement.
- A new segment is rejected if it crosses any other path, crosses the
  current path's earlier segments, or passes within 85% of any
  non-endpoint ball's radius.
- Tap-and-drag from a ball that already has a path replaces that path.
- Release on the matching-color other ball completes the pair; release
  anywhere else cancels the in-progress drag.
- Win condition: all colors completed. Tap once to advance to the next level.

Tweak in `scripts/LineDrawer.gd`:
- `SAMPLE_DIST` — finer = smoother curves, more CPU
- `LINE_WIDTH` — visual thickness
- `BALL_BLOCK_FACTOR` — lower = easier to squeeze between balls
