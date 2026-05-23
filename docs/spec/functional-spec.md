# Mexican Train iOS — Functional Spec

A native iOS companion app for scoring Mexican Train, a domino game. The defining feature is photo-based pip counting: at the end of each round, the user photographs the tiles a player has left in hand and the app sums the pips and records the score.

This spec defines functional requirements only. Implementation details (frameworks, file layout, model choice, persistence library) live in the dev design doc.

## 1. Product summary

- One phone is the **scorebook** (host, operated by the person we call the **conductor**) and is the device of record. The host can pass the phone around the table, or one person can enter scores for everyone.
- Other phones in the room can **join** to see the live scoreboard — either as a **player** (claiming a slot in the game with their name and photo) or as a **spectator** (read-only). **Player joiners submit their own scores** from their own phones; the conductor can additionally submit on behalf of any player as an override (useful for players without a phone or who are temporarily away from the table). Spectators are read-only. See §7.
- No accounts, no server, no internet path. All gameplay data lives on the host device; broadcast to joiners is peer-to-peer on the local network only.
- The phone is the scorebook. The headline interaction is "tap Add Score → point camera at tiles → confirm number → done."
- Visual identity: **Caboose** theme — warm parchment background, oxblood brand color, brass borders, saloon-ledger typography. The app should feel like a hand-kept score ledger on a wood table.

## 2. Game model

### 2.1 Rounds (called "stops")
- A game is a sequence of **stops**. Each stop corresponds to a starting double tile (the engine).
- The user picks the game length at setup: **7, 10, or 13** stops. Default: 13.
- The starting engine for stop 1 is governed by a house rule (see §2.4). The engine for each subsequent stop is one lower (double-N, double-(N−1), …, double-0).
- At any point in a game there is a single "current stop" (1-indexed). The current stop advances when every player has a score recorded for it.

### 2.2 Players
- 1 to 8 players per game.
- Each player has a display name. Names within a game must be unique (case-insensitive).
- Exactly one player may be marked as **"you"** (the device owner). This is optional — a game can be set up with no "you" player.
- The "you" designation only affects display (highlight row, "your stats" strip). It has no effect on scoring.

### 2.3 Scores
- A score for a (player, stop) is a non-negative integer: the sum of pips left in that player's hand at the end of that stop.
- 0 is a valid score (player went out / had no tiles left).
- A score may be unset (the stop has not been entered for that player yet).
- Lower cumulative total wins. Final standings are ascending by total.

### 2.4 House rules
Mexican Train is famously played with local variations. The app exposes house-rule choices in new-game setup so a family can match how they actually play. Rules are per-game (selected at setup, immutable for the rest of that game).

v1 includes one house rule:

- **Starting engine** — selected at new-game setup with these options:
  - **Traditional (default)**: the starting double matches the game length. 7-stop starts at double-6, 10-stop at double-9, 13-stop at double-12. Each subsequent stop steps down by one.
  - **Always start at double-12**: every game begins at double-12, regardless of length. Shorter games end before reaching double-0 (a 7-stop game ends after double-6).

The new-game setup screen remembers the last-used choice as the default for the next game.

Additional house-rule toggles may be added in later versions (e.g. satisfying the double, train rules, penalty scoring) but are out of scope for v1.

## 3. Screens & flows

### 3.1 Home / game list
- On launch, the user lands on a home screen.
- The home screen shows:
  - A primary "New game" CTA.
  - A list of past games (most recent first), each with: date, player count, winner, final total spread. Tapping opens the game in read-only view. **Swiping a past-game row left reveals a destructive Delete handle**; tapping it presents a confirmation alert that, on accept, removes the game and its photos from the device.
  - An in-progress game pinned at the top (at most one in-progress game can exist; resuming it is the primary path back into play).

Deletion of finished games is reachable only from this list — the read-only detail view does not surface a destructive action.

### 3.2 New-game setup (lobby)
The new-game screen is a live lobby. As soon as the conductor (the person who taps "New game") enters this screen:

- The conductor is added as the first player automatically, with their name pre-populated from the device (see §7.3 for the iOS specifics). They are marked as "you."
- The app begins broadcasting on the local network with a fresh room code, so other phones at the table can scan the visible QR code (or type the room code) to join as additional players. Each joiner who confirms appears in the player list with their name and, when provided, photo.
- The conductor can also manually add players for anyone without a phone (typed-name only; no photo). Manually added players have no associated device.
- The conductor can edit: game length (7 / 10 / 13 stops, default 13), starting engine house rule (default "Traditional"), and can remove any non-conductor player from the list.
- "Start game" is enabled when there is at least 1 player and all names are non-empty and unique (case-insensitive). Tapping it locks the lobby — no further joiners are accepted as new players — and routes the conductor to the scoreboard (current stop = 1). Joiners already in the lobby remain connected and follow the host to live scoreboard view.
- Backing out of the lobby tears down the broadcast and discards the draft game.

### 3.3 Scoreboard (primary screen during a game)
The scoreboard is the home of the in-progress game. It must show, at a glance:
- A centered game-title strip with a back affordance and a menu affordance for game actions (rename, share with table, end early, delete). The current stop indicator (e.g. "STOP 4/13") is conveyed by the table itself and the primary CTA, not duplicated in the header.
- Engine indicator: a small domino glyph showing the double-tile for the current stop, plus "N aboard" (player count).
- **Your-stats strip** (only when a "you" player is set): the user's current place (1st, 2nd, …), their total, and either "leading the train" or "X pts behind {leader name}".
- **Golf-card table**: rows = players, columns = stops. Each cell shows that player's score for that stop, or a placeholder dot if unset. A total column on the right. The current stop column is visually highlighted. The "you" row is visually highlighted. The leader is marked with a crown.
- **Photo gallery** (when applicable): below the table, a row/grid of thumbnail captures from the previous stop, one per player. Each thumbnail shows the player's name and points. If no previous stop has photos, this area is hidden.
- **Primary CTA at the bottom**: "Add Score" — large, oxblood/ink button, labelled with the current stop.
- **Broadcast status strip**: a slim, tappable indicator beneath the primary CTA that surfaces the room code and joined-peer count (or "Share game" when nothing is connected yet). Tapping opens the share sheet (QR + room code). This replaces a header-side affordance so the title can stay centered.

Interactions (conductor on the host device):
- Tap "Add Score" → camera screen for the next player who has not yet been entered for the current stop. If all players are entered for the current stop, the CTA changes to "Advance to stop N+1" (or "Finish game" on the final stop).
- Tap any populated score cell → audit screen for that (player, stop).
- Tap any unset cell from a **past** stop → audit screen for that (player, stop) in **create mode** (manual entry, no camera). Saving creates the score as if originally submitted by the conductor.
- Unset **current**-stop cells display a small "+" affordance instead of the dot used for unset past-stop cells. Tapping "+" invokes the **conductor override** flow (see §3.6). The "+" is not shown for a slot once that player has submitted their own score.
- Tap the menu → sheet with: rename game, end game early, delete game.

Interactions (player joiner): see §7.4. The joiner's scoreboard view is read-only for everyone else's cells; their own current-stop cell, when unset, surfaces an "Add my score" CTA that opens the camera on their phone.

### 3.4 Camera screen (add score flow)
The camera is the default entry path. The top bar shows which player is being scored ("Aaron · Stop 4") with a back/cancel button.

Phases:
1. **Aim**: live viewfinder, framing brackets, hint text ("Point at your hand · hold still · good light"), large shutter button. Side button switches to manual entry.
2. **Scanning**: progress indicator runs while the on-device model analyses the photo. Cancel returns to aim.
3. **Confirm**: the detected pip count is shown large over the captured photo, with the count of tiles detected ("8 tiles · 47 pips"). Buttons: "Retake" (back to aim) and "All aboard ✓" (submit).

On submit:
- The score is saved for that (player, stop).
- A toast confirms ("Aaron's stop 4: 47 pips").
- The app returns to the scoreboard, ready for the next player.

Manual entry mode (reachable from the camera's "123" button or from a fallback path if vision fails):
- Numeric keypad (0-9, backspace).
- Big readout of the entered value.
- "All aboard ✓" submit, disabled until a value is entered.
- Manual-entered scores are flagged as such in the data model so the audit screen can distinguish them.

If the vision model returns no detection or an obviously invalid result (e.g. zero tiles), the camera screen offers a "Couldn't read tiles — enter manually" path that takes the user to manual entry pre-populated with the photo for reference.

### 3.5 Audit screen
Opened by the conductor by tapping any score cell (populated → edit mode; unset past-stop → create mode). Shows:
- Header: "Audit · Stop N" with back button.
- Hero strip: player name (with "you" badge if applicable), engine glyph for that stop, and the player's new running total (with delta vs. recorded if changed).
- **Pip count editor**: big number readout, − and + step buttons, quick-adjust chips (−10, −5, +5, +10), and a tappable numeric input.
- **Exclude toggle**: when enabled, the score contributes 0 to that player's total but remains on the board for audit visibility. The cell still satisfies "every player has entered a score for this stop" so the stop can complete. Excluding does not remove the entry — the original and any edits remain in the audit history.
- **Scanned tiles section** (if the original entry was from a photo): the tiles the model identified, with a "Re-scan" button that returns to the camera screen for this (player, stop). For manual entries, this section shows "Entered manually" and a "Scan now" affordance.
- **Reference photo** (if any): the captured photo, with timestamp.
- **Audit history**: an ordered list of the original submission and every subsequent change, each line showing what changed (pip value or exclude state), who made the change (player or conductor), and when. The original submitted value is never overwritten and is always shown first.
- Footer: "Discard" (cancel changes, return) and a primary commit button. The commit button is labelled **"Save score"** when creating a previously-unset score, and **"Update"** when modifying an existing one.

The audit screen is the conductor's general-purpose adjustment tool. Audits change the score that counts toward the game total but never modify the originally submitted value; the audit history preserves the full chain. This rule is what makes the end-of-game report (§3.8) honest.

### 3.6 Conductor override (submitting on behalf of a player)
The conductor uses this when a player isn't present, doesn't have a phone, or simply can't submit themselves.

Flow:
1. On the scoreboard, every unset current-stop cell shows a "+" affordance (see §3.3).
2. Tapping "+" presents a **confirmation sheet** naming the player: "Submit on behalf of {Player}?" with **Cancel** and a primary action (e.g. "Open Camera as {Player}"). The confirmation is mandatory — there is no one-tap path from "+" directly to the camera, to prevent accidental override.
3. Confirming opens the camera screen (§3.4) configured for that player. The camera's top bar makes the override visible (e.g. "AS {Player} · Stop N") so the conductor cannot forget mid-scan that they are submitting for someone else.
4. Submission records the score as **originally submitted by the conductor**, distinguished from a player's own submission in the audit history. Manual entry is available from the same path.

**Race resolution: player submissions take priority.** If the conductor submits on behalf of a player and that player later submits their own score for the same stop, the player's value replaces the conductor's as the current value. The conductor's earlier value is preserved as the original entry in the audit history, with an automatic adjustment entry showing the player's correction. The reverse direction (conductor submitting after a player already has) does not happen by design: the "+" affordance disappears once a player has submitted. If the conductor wants to correct a player-submitted score, they use the audit screen (§3.5) instead.

### 3.7 End of game
- When the final stop's last score is entered, the app advances to an end-game screen.
- End-game screen shows: a celebratory **winner card** with a prominent trophy icon, the winner's name, and their final total; final standings (ascending by total); per-player totals; a "New game" CTA; and a button to view the completed game in the history list.
- A short **confetti animation** plays once on arrival to mark the moment. The animation is decorative only; it does not block interaction.
- The primary **Share action** shares a rendered image of the winner card (PNG) via the iOS share sheet — visual, suitable for text/chat. The plain-text game report (§3.8) remains reachable from the game's row in the home history list.

### 3.8 Game report
A report of a completed game can be shared as plain text via the iOS share sheet. The report must include:
- Game title and final date.
- Final standings with places and totals.
- A per-stop breakdown for every player showing the score that counted toward the total, with annotations for any score that was audited or excluded (showing the original value, the actor who changed it, and when).
- An indication of who submitted each score (player vs conductor override) where that distinction is meaningful.

The share action is reachable from:
- Any finished game's row in the home screen's history list (§3.1) and from the read-only game detail view as a "Share report" button.

The end-of-game screen's primary share is an **image** of the winner card rather than this text report; see §3.7.

The intent is that the report is faithful to what actually happened — including all corrections — so it can be sent to players after the game without anyone wondering how a score got from one value to another.

## 4. Photo / vision

### 4.1 Capture
- The app captures still photos using the rear camera.
- The first time the camera is used, the app requests camera permission with a purpose string that explains the use ("Photograph tiles to count pips automatically").
- Each capture is saved locally (full-resolution + thumbnail) and associated with the (game, player, stop) it was taken for.

### 4.2 On-device pip counting
- Pip counting runs entirely on-device. No network call is made for vision.
- For each capture, the model returns:
  - A list of detected tiles, each with two half-values (a, b ∈ 0…N where N matches the engine range — 6, 9, or 12).
  - A total pip count (sum of all halves).
  - A confidence indicator (high / medium / low) used to drive UI hints.
- If the model fails or returns low confidence, the user is routed to manual entry with the photo still saved.

### 4.3 Reference and history
- Captures are retained as part of the game's history indefinitely. They appear in:
  - The scoreboard's photo gallery (last stop) during play.
  - The audit screen (reference photo for the relevant entry) during play.
  - The completed-game read-only view from the home screen's history list.
- Photos are deleted only when the user deletes that game from the history list. Deleting a game removes the game record and all its photos together.
- There is no time-based auto-purge.

## 5. Persistence

- All game state — games, players, stops, scores, captures, manual/scanned flag — is persisted locally on the device.
- App restart, force-quit, or device reboot must not lose any in-progress game state.
- Photos are stored at full capture resolution; thumbnails are derived on demand or cached.

## 6. Settings / preferences

A minimal settings screen, reachable from the home screen menu:
- Default game length (7 / 10 / 13).
- **Your identity**: a default name and, optionally, a default profile photo picked from the user's photo library. Both persist across launches and serve as the canonical "this is me" identity for this device.
  - When starting a new game, the conductor's player slot is pre-populated with this name and photo.
  - When joining another phone's game, the join sheet pre-populates the joiner's name and photo from the same values (still editable before tapping Join).
  - Either field can be cleared independently. When no photo is set, slots fall back to initials (or the train avatar, see §7.3).
- About / version.

House-rule defaults (e.g. starting engine) are not duplicated in settings; new-game setup remembers the last-used choice instead.

Settings are intentionally small. The web app's "tweaks panel" (density, history visibility, button radius, tile orientation) is a design exploration tool and is not exposed to end users; the iOS app picks one set of defaults: cozy density, score history visible, photo gallery visible, manual fallback allowed, horizontal tiles.

## 7. Broadcast (multi-device viewing and scoring)

The host phone is the device of record for the game's data. Other phones in the room may join to see the live scoreboard, and **player joiners may submit their own scores** for their own slot. The host receives, records, and rebroadcasts; the conductor on the host can override or audit any score (§3.5, §3.6). Spectators never submit anything.

### 7.1 Roles
- **Host**: the scorebook, operated by the conductor. Owns the game's data of record; broadcasts state; receives and records score submissions from player joiners. There is exactly one host per game.
- **Player joiner**: a person at the table who claims one of the game's player slots. Their phone shows the same live scoreboard as the host, with their claimed slot highlighted as "you." They contribute a name and photo to that slot (see §7.3) and may submit their own scores for their own slot only (see §7.4).
- **Spectator**: a person watching. Their phone shows the live scoreboard read-only. They do not claim a slot and contribute no name, photo, or scores.

Multiple joiners can connect to a single host concurrently, in any combination of player and spectator roles. Each player slot may be claimed by at most one joiner at a time.

### 7.2 Discovery and join
- The scoreboard has a "Share game" affordance that opens a sheet on the host showing a **QR code** and a short **room code**. Both encode the same join target.
- A joiner reaches the host by:
  - Scanning the QR code with the in-app scanner or with the iOS Camera app (the QR opens the app directly to the join sheet for that host), **or**
  - Typing the room code into the join screen as a fallback.
- After connecting, the joiner picks a role on a join sheet pre-populated with the host's game name, the list of player slots, and which slots are already claimed.
  - Selecting an unclaimed slot → joining as that player.
  - Selecting "Spectate" → joining as a spectator.
- Discovery is local-only (same Wi-Fi network or short-range wireless). The app makes no internet calls for any part of join or broadcast.

### 7.3 Identity prefill for player joiners
When joining as a player, the join sheet pre-populates the slot's display name and photo from this device's saved identity:

1. **Settings-saved identity (§6)** wins when set: the user's chosen name and photo from settings.
2. **Device-derived fallback**: if no name is saved in settings, the prefill comes from `UIDevice.current.name` with the trailing "'s iPhone" / "'s iPad" suffix stripped. (iOS does not expose a macOS-style "Me card" API; the device name is the closest stable signal available without prompting.)

Both the name and the photo are always editable before tapping Join. The joiner is never forced to send what was prefilled.

For the photo, the joiner has three options:
- Use whatever photo is prefilled from settings.
- Pick a new photo from the iOS photo library via the standard Photos picker (no permission prompt; runs out of process).
- **Pick a colored train**: a 10-color palette of `tram.fill` glyphs presented as a grid on the join sheet. Picking one renders the colored train as the avatar JPEG and sends it through the same `photoJPEG` field used for real photos — no protocol change. This is the fallback for joiners who don't want to share a real photo but still want their slot to be visually distinct.

When the joiner taps "Join," the chosen name and photo (real or train) becomes the visible identity for that slot across the host and every other joiner. A joined player's name overrides any host-set name for that slot. If the joiner provides no photo and no train, the slot shows initials only. The photo wire format remains a single JPEG, resized to ~256² and ≤ 32 KB.

### 7.4 Live state sync between host and joiners

**Host → joiners (broadcast).** On every meaningful change, the host pushes the current game state to all connected joiners. "Meaningful change" includes (non-exhaustive): a score added, audited, or excluded; a stop advanced; a player added/renamed; the game ended; a new capture taken; a claim received from another joiner.

The broadcast carries enough state for joiners to render the full scoreboard, the photo gallery from the most recent stop, and identity claims for every player. Joiners do not hold their own copy of the game's history; their view is driven entirely by the most recent broadcast.

**Player joiner → host (score submission).** A player joiner may submit a score for their own slot only, for the current stop only, when that slot has no existing score for that stop. The submission carries the pip count and, optionally, the captured photo and the tile detections used to derive it (so the conductor can audit a submitted score against the same evidence the joiner saw).

Submission outcomes:
- If the slot has no score for the current stop: the host records the submission as a score originally submitted by that player and rebroadcasts. The joiner's "Add my score" CTA disappears.
- If the slot has a score that was previously entered by the conductor's override (§3.6): the host accepts the player's submission as the new current value and records the override-vs-correction transition in the audit history. The original conductor-submitted value is preserved; the score's submitter-of-record becomes the player.
- If the slot has a score the player themselves already submitted: the submission is rejected (idempotent re-submit becomes a no-op; an explicit change requires the conductor's audit screen).

Joiners do not submit on behalf of other players, do not audit, and do not exclude. All such adjustments are the conductor's, via §3.5.

### 7.5 Connection lifecycle
- A joiner who briefly loses Wi-Fi reconnects automatically when the network is back.
- If the host ends, deletes, or quits the game, joiners are shown a "host left the game" state and returned to their own home screen on dismissal.
- A joiner can leave at any time; the host's game continues unaffected. The slot retains the joiner's contributed name and photo unless the host clears it from the scoreboard menu.

### 7.6 Privacy
- All broadcast traffic stays on the local network between the host and joiners. Nothing is sent to a remote server.
- A joiner's name and photo are sent only after they tap "Join" on the prefilled sheet — never proactively during discovery.
- The host can revoke a joiner's claim from the scoreboard menu, which clears the contributed name and photo from the slot and disconnects that joiner.

## 8. Non-goals (v1)

- No accounts, no cloud backup, no iCloud sync, no internet-based multiplayer.
- No audit or exclude actions from joiners — only the conductor (on the host) may adjust scores after submission.
- No exporting a game as an image or PDF. Plain-text share is supported (§3.8).
- No undo of game-advance once a stop has been closed (a stop's scores can still be audited individually).
- No tile-tracking during play (the app counts pips at the end of a round, not which tiles are in which train).
- No statistics across games (head-to-head records, per-player averages) beyond the home-screen game list.

## 9. Accessibility & platform behavior

- The app supports portrait orientation only on iPhone.
- Dynamic Type: the scoreboard and large readouts must remain legible at the user's preferred text size, up to and including XXL accessibility sizes (rows reflow, columns scroll horizontally if needed).
- VoiceOver: every actionable element (cells, buttons, gallery thumbnails) must have a meaningful label. Score cells announce "{player}, stop {n}: {value} or blank, double-tap to edit."
- Dark mode: out of scope for v1; the Caboose theme is parchment-light by design.

## 10. Open questions

(None outstanding for v1 scope.)

## 11. Change log

- 2026-05-21 — v0.1 — Initial draft. Scope: standalone single-device, on-device vision, Caboose theme. Authored from the design canvas (`docs/design/Mexican Train/`) and the companion web-app README in the sibling `platform/apps/mextrain` repo.
- 2026-05-21 — v0.2 — Resolved open questions: default game length confirmed at 13; photos retained with game history and deleted only when the user deletes a game (no time-based purge); starting engine made a per-game house rule (§2.4) with "Traditional" as the default.
- 2026-05-21 — v0.3 — Added broadcast (§7): host advertises a game via QR code + room code; other phones join as player (with iOS-prefilled name and photo) or spectator. Scoring inputs remain host-only. Adjusted §1 product summary and §8 non-goals to match.
- 2026-05-21 — v0.4 — Tightened §7.3 to reflect the iOS reality: identity prefill comes from `UIDevice.current.name` (with the device-suffix stripped) rather than a Contacts "Me card," which iOS doesn't expose. The wire format still carries an optional photo for a future Photo Picker flow.
- 2026-05-21 — v0.5 — Reframed §3.2 New-game setup as a live lobby: the conductor is auto-added with their device-derived identity, broadcast (QR + room code) starts immediately so other phones can join as players from the new-game screen, and a "Add player manually" path remains for phone-less players. Replaces the previous "type every name" flow.
- 2026-05-22 — v0.6 — Shifted scoring authority: player joiners now submit their own scores from their own phones (§1, §7.1, §7.4); the conductor can submit on behalf of any player as a deliberate override (new §3.6) via a "+" affordance on unset current-stop cells (§3.3) plus a mandatory confirmation. Player submissions take priority over conductor overrides for the same slot/stop; conflicts are preserved in the audit history. Documented exclude semantics and the audit history list on the audit screen (§3.5). Audits never overwrite originally submitted values — they update the score that counts toward the total while preserving the original. Added a plain-text shareable end-of-game report (new §3.8), reachable from the end-of-game screen (§3.7) and from finished-game entries in the history list (§3.1). Updated §8 non-goals accordingly.
- 2026-05-23 — v0.7 — UX-review sweep across the v2 deck. §3.1: deletion of past games moves to swipe-to-delete on the home list (no longer offered from the read-only detail view). §3.3: scoreboard title is centered; the broadcast/share affordance moves out of the header into a tappable bottom strip beneath the primary CTA; the per-stop subtitle is removed (the table and CTA already convey it). §3.5: existing-score commit button is labelled "Update" (was "Save correction"). §3.7: end-of-game screen gains a larger trophy treatment, a one-shot confetti flourish, and an **image** share of the winner card; §3.8 plain-text report stays reachable from the history list. §6: settings now own a persistent "your identity" with name + optional library photo; both prefill new-game conductor and join-sheet joiner identity. §7.3: joiners get a 10-color `tram.fill` train-avatar fallback for when they'd rather not share a real photo; settings-saved name/photo wins over the device-derived prefill.
