# Mexican Train iOS — Dev Design

Companion to `docs/spec/functional-spec.md` (v0.2). The functional spec says **what** the app does; this doc says **how** we'll build it. Decisions here are reviewable and revisable.

## 1. Tech stack

| Concern | Choice | Reason |
| --- | --- | --- |
| Language | Swift 5.10+ | Native, modern, no FFI surprises. |
| UI | SwiftUI | The design is rich (custom typography, layered backgrounds, domino glyphs); SwiftUI's composability matches the per-component design in `screens.jsx`. We don't need UIKit-only APIs for v1. |
| Minimum iOS | iOS 17.0 | SwiftData and `@Observable` are both iOS-17-only and remove a lot of boilerplate. iPhones running iOS 17 cover 90%+ of the iPhone install base in 2026. |
| Devices | iPhone only, portrait only | Matches the design and the §8 spec constraint. |
| State | `@Observable` model objects, owned by a root coordinator | Lightweight MVVM. No third-party DI / state libraries. |
| Persistence | SwiftData | First-party, matches Codable, plays well with `@Observable`. The schema is small enough that we don't need a query language beyond what SwiftData gives us. |
| Photos | Files on disk under app sandbox + relative paths stored in SwiftData | Don't bloat the SQLite store with binary blobs. |
| Camera | `AVFoundation` with a `UIViewControllerRepresentable` wrapper | SwiftUI's `Camera` symbol is iOS-18-only; AVFoundation is the boring durable path. |
| Vision | Apple's Vision framework + a CoreML model | On-device requirement (spec §4.2). See §5 for the pipeline. |
| Custom fonts | Bundled .ttf/.otf in app target, registered via `UIAppFonts` plist key | Rye and Special Elite for Caboose. Free Google Fonts; license check needed at bundle time. |
| Networking | `MultipeerConnectivity` (Bonjour discovery + MCSession reliable channel) | Local-only broadcast (spec §7). Same model used in `~/code/farkle`. Zero remote infrastructure, works offline. |
| QR codes | `CoreImage` for generation, `AVCaptureMetadataOutput` for in-app scan, Universal Link for the iOS-Camera path | The QR encodes a join target (room code + service identifier); scanning from iOS Camera opens the app via Universal Link. |
| Device identity | `Contacts` framework, "Me" card lookup | Source of the user's name and photo for the player-join prefill (spec §7.3). Requires Contacts permission with a clear purpose string. |
| Build | Xcode project (no SPM split for v1) | One app target keeps things simple. We can carve out SPM packages later if vision becomes a separable library. |

### 1.1 What we explicitly skip
- **No backend, no internet networking.** Broadcast is strictly peer-to-peer on the local network via MultipeerConnectivity. No HTTP, no remote services.
- **No analytics / crash reporting** in v1. Add later if we ship to TestFlight.
- **No CocoaPods / Carthage.** SPM only if any dependency is needed; v1 plan adds none.
- **No reactive frameworks** (Combine, RxSwift). `@Observable` + plain Swift is enough.

## 2. Project structure

```
mexican-train-ios/
  MexicanTrain.xcodeproj/
  MexicanTrain/                       # app target
    App/
      MexicanTrainApp.swift           # @main, root container
      AppCoordinator.swift            # navigation state
    Models/
      Game.swift                      # @Model: Game, Player, Stop, Score, Capture
      HouseRules.swift                # enums for rule choices
      Scoring.swift                   # pure functions: totals, standings
    Persistence/
      DataStore.swift                 # SwiftData ModelContainer factory
      PhotoStore.swift                # disk read/write for captures
    Vision/
      PipCounter.swift                # protocol
      VisionPipCounter.swift          # production impl (CoreML + Vision)
      MockPipCounter.swift            # debug impl: returns plausible fake results
      DominoDetector.mlmodel          # bundled CoreML model (see §5)
    Networking/                       # broadcast (see §8)
      MexTrainNetSession.swift        # MCSession wrapper, host/joiner roles
      GameSnapshot.swift              # full-state wire model
      MultipeerMessage.swift          # envelope: .snapshot | .claim
      RoomCode.swift                  # 4-digit code generator + validator
      JoinURL.swift                   # encode/decode the Universal Link payload
    Identity/
      DeviceIdentity.swift            # Contacts "Me" card prefill, photo resize
    Theme/
      Theme.swift                     # struct + Caboose instance
      Fonts.swift                     # font registration helper
      Resources/Fonts/                # bundled .ttf files
    Features/
      Home/
      NewGame/
      Scoreboard/
      Camera/
      Audit/
      EndGame/
      Settings/
      Broadcast/                      # ShareGameSheet, JoinSheet, QRScannerView
    Components/                       # shared SwiftUI views
      DominoGlyph.swift
      ScoreCardTable.swift
      PhotoGalleryStrip.swift
      KeypadView.swift
    Assets.xcassets/
  MexicanTrainTests/                  # unit tests
    ScoringTests.swift
    HouseRulesTests.swift
    PhotoStoreTests.swift
  MexicanTrainUITests/                # one smoke test for the golden path
  docs/                               # already exists
```

Each `Features/<Screen>/` folder owns a `…View.swift` and a `…ViewModel.swift` (when needed). Models and persistence are shared.

## 3. Data model

SwiftData `@Model` classes. Identifiers are `UUID` so we can move records around or export later without remapping.

```swift
@Model final class Game {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String?              // optional user-set; otherwise derived from date
    var lengthStops: Int           // 7, 10, or 13
    var rules: HouseRules          // see below
    var currentStopIndex: Int      // 1-indexed; equals lengthStops + 1 when finished
    var finishedAt: Date?          // nil until the last stop is closed
    @Relationship(deleteRule: .cascade) var players: [Player]
    @Relationship(deleteRule: .cascade) var scores: [Score]
    @Relationship(deleteRule: .cascade) var captures: [Capture]
}

@Model final class Player {
    @Attribute(.unique) var id: UUID
    var game: Game?                // back-ref
    var name: String               // canonical display name; overridden when a joiner claims this slot
    var seat: Int                  // order at the table; stable
    var isYou: Bool                // exactly 0 or 1 per game
    var avatarFilename: String?    // optional avatar JPEG (host-set or claimed by joiner)
}

@Model final class Score {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var playerID: UUID
    var stopIndex: Int             // 1-indexed
    var pips: Int                  // ≥ 0
    var source: ScoreSource        // .scanned or .manual
    var captureID: UUID?           // optional pointer into Capture
    var updatedAt: Date
}

enum ScoreSource: String, Codable { case scanned, manual }

@Model final class Capture {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var playerID: UUID
    var stopIndex: Int
    var createdAt: Date
    var filename: String           // relative path under photo store
    var pipsDetected: Int?
    var confidence: Confidence
    var tiles: [TileObservation]   // codable struct; see below
}

enum Confidence: String, Codable { case high, medium, low }

struct TileObservation: Codable {
    var a: Int
    var b: Int
    var bbox: CGRect?              // normalized [0,1]² coordinates if available
}

struct HouseRules: Codable {
    var startingEngine: StartingEngine
}

enum StartingEngine: String, Codable {
    case traditional               // double-N where N = lengthStops - 1 in 7/10, double-12 in 13
    case alwaysTwelve
}
```

Notes:

- **Scores are sparse.** A `(playerID, stopIndex)` row exists only when entered; "unset" is the absence of a row, not a sentinel value. Cleaner than null-padding arrays and lets us audit "is the current stop complete?" with a count query.
- **`Capture.tiles`** is stored as a codable JSON blob inside the SwiftData record. We don't need to query it relationally.
- **Photo bytes live on disk**, not in SwiftData. The `filename` is relative to `PhotoStore`'s root (`Application Support/photos/<gameID>/<captureID>.jpg`).
- **Deletion**: `.cascade` on the Game's relationships handles the metadata. `PhotoStore` listens for game deletion (via the coordinator, not SwiftData hooks — keep that boundary clean) and deletes the on-disk directory for that game. Idempotent: missing files are not an error.

### 3.1 Scoring (`Scoring.swift`)

Pure functions over arrays of scores, no SwiftData dependency. Trivially unit-testable.

```swift
enum Scoring {
    static func total(for playerID: UUID, in game: Game) -> Int
    static func standings(for game: Game) -> [Standing]   // sorted ascending
    static func isStopComplete(_ stop: Int, in game: Game) -> Bool
    static func nextUnenteredPlayer(stop: Int, in game: Game) -> Player?
    static func engineTile(stop: Int, rules: HouseRules, length: Int) -> Int
}

struct Standing {
    let player: Player
    let total: Int
    let place: Int                 // 1-indexed; ties share a place
}
```

`engineTile` resolves the house rule:
- `.traditional`: `start = length - 1` (so 13 → 12, 10 → 9, 7 → 6). Engine for stop `s` is `start - (s - 1)`.
- `.alwaysTwelve`: engine for stop `s` is `12 - (s - 1)`, clamped at 0 (and games end after `lengthStops` regardless of where that lands).

## 4. Photo storage

`PhotoStore` is a small struct that knows the on-disk layout. It does not touch SwiftData.

```
<Application Support>/MexicanTrain/photos/
  <gameID>/
    <captureID>.jpg        # full-res original (JPEG, 0.85 quality)
    <captureID>_thumb.jpg  # ~512px longest edge, lazily generated
```

Public API:

```swift
struct PhotoStore {
    func save(image: UIImage, gameID: UUID, captureID: UUID) throws -> String  // returns filename
    func load(filename: String, gameID: UUID) -> UIImage?
    func thumbnail(filename: String, gameID: UUID) -> UIImage?
    func deleteAll(gameID: UUID)
}
```

Thumbnail generation is lazy and cached in memory via a small `NSCache`. We do not store thumbnails in SwiftData — they're derivable.

Photo orientation: we strip EXIF orientation at save time by drawing into a fresh `CGContext`, so downstream viewers don't have to think about it.

## 5. Vision pipeline

This is the trickiest piece. The functional spec says on-device, with a per-capture result of `tiles[]`, `total`, and `confidence`. The reality is we need a CoreML model that can detect dominoes and read their pip counts. The web app's `ml/` folder is training a YOLOv11 — that's the eventual source, converted to CoreML via `coremltools`.

### 5.1 Protocol and impls

```swift
protocol PipCounter {
    func count(in image: UIImage) async throws -> PipCountResult
}

struct PipCountResult {
    let tiles: [TileObservation]   // empty if model returned nothing usable
    let total: Int                 // sum of a+b across tiles
    let confidence: Confidence
}

enum PipCounterError: Error { case noTilesDetected, modelUnavailable, badImage }
```

Two implementations:

- **`VisionPipCounter`** — production. Loads a CoreML model bundled in the app, runs detection via `Vision.VNCoreMLRequest`, post-processes to merge tile halves and compute a total.
- **`MockPipCounter`** — debug only, gated behind `#if DEBUG`. Returns 4–8 plausible tiles with random pip values after a 700ms delay so we can build and test the camera/audit flow before the real model is ready.

The app uses `MockPipCounter` when the bundled model file is absent (build flag), and `VisionPipCounter` otherwise. This lets UI work proceed in parallel with model training.

### 5.2 Model interface (target shape)

The CoreML model takes an image (probably 640×640 RGB, model-specific) and returns:
- A list of bounding boxes, each tagged with a class.
- Classes are either `tile-(a,b)` (one of 91 possibilities for double-12: 0-0, 0-1, … 12-12) **or** a two-stage `(domino, pip-count-half)` pipeline.

We'll commit to the **single-stage classification** shape because the web app's vision plan points that way; the CoreML model file will land in `Vision/DominoDetector.mlmodel`. If experiments find two-stage is better, we swap implementations behind the `PipCounter` protocol — no other code changes.

### 5.3 Confidence heuristic

`VisionPipCounter` derives a confidence bucket from model output:
- `high`: every detection above 0.8 score, at least 1 tile, all tiles' two halves resolved.
- `medium`: detections in 0.5–0.8, or 1+ tiles with unresolved halves we had to infer.
- `low`: anything else, or fewer than 1 tile.

The UI uses this to decide whether to surface manual entry as the recommended path (low confidence → "Couldn't read tiles cleanly — confirm or enter manually").

### 5.4 What gets shipped before the model exists

For pre-model milestones, the app uses `MockPipCounter` and **does not bundle the .mlmodel file**. The camera and audit screens work end-to-end against mock data. Reviewers can test the full flow without ML infra. Once the .mlmodel lands, we flip a build setting and ship.

## 6. Theme

`Theme` is a simple struct of colors, fonts, and metrics, mirroring `THEME_CABOOSE` from the design canvas.

```swift
struct Theme {
    let bg, headerBg, subBg, cardBg: Color
    let ink, muted: Color
    let border, borderLight: Color
    let brand, accent: Color
    let youBg, currentColumn: Color
    let cta, ctaText: Color
    let displayFont: String          // "Rye"
    let monoFont: String             // "Special Elite"
    // Spec §6: tweaks panel values are baked, not user-facing
    let buttonCornerRadius: CGFloat = 16
    let tilesOrientation: TilesOrientation = .horizontal
}

extension Theme {
    static let caboose = Theme(
        bg: Color(hex: 0xF4EAD5),
        // … remaining values lifted verbatim from screens.jsx THEME_CABOOSE
    )
}
```

Injected via SwiftUI `Environment` so every component reads `@Environment(\.theme)` and stays styleable. Even though v1 only ships Caboose, going through the environment costs nothing and leaves the door open for Pacific later.

Custom fonts (`Rye-Regular.ttf`, `SpecialElite-Regular.ttf`) are bundled in the target and listed under the `UIAppFonts` Info.plist key. We register them on app launch and fall back to system fonts if loading fails (so the app never renders blank text on a font glitch).

## 7. Navigation and state

A root `AppCoordinator` (`@Observable`) owns the navigation enum and current game reference:

```swift
@Observable final class AppCoordinator {
    enum Route {
        case home, newGame
        case scoreboard(Game), camera(Game, Player, stop: Int), audit(Score), endGame(Game)
        case joinSheet(JoinTarget)           // joiner: after QR scan or code entry
        case spectator(GameSnapshot)         // joiner: live broadcast view
    }
    var route: Route = .home
    var modalRoute: Route?           // for sheets (settings, share game)
    let container: ModelContainer
    let photoStore: PhotoStore
    let pipCounter: PipCounter
    let netSession: MexTrainNetSession   // owns Multipeer state (see §8)
}
```

The app's root `View` switches on `coordinator.route`. Sheets and navigation pushes are driven from the coordinator. This is light enough to grasp at a glance and avoids the boilerplate of a router framework.

Per-screen ViewModels are created on demand by the coordinator and own the screen's mutable state. They depend on `ModelContainer`, `PhotoStore`, `PipCounter` — injected via initializer, never via singleton, so tests can stub them.

## 8. Broadcast (multi-device)

Implements functional spec §7. Closely modeled on `~/code/farkle/Farkle/Networking/`. The host phone is the source of truth; joiners receive snapshots and (as players) send back a single identity claim. There is no client-to-host scoring path — that's a spec-level invariant we preserve here by simply not implementing the messages.

### 8.1 Transport
`MultipeerConnectivity` with Bonjour service type `mextrain-game` (≤15 chars, lowercase+hyphens). One `MCSession` per host, reliable channel only. We do not use the unreliable channel — snapshots are small and idempotent, "missed" intermediate states are fine.

```swift
@MainActor
@Observable
final class MexTrainNetSession: NSObject {
    enum Role { case idle, host, joiner }
    enum JoinState { case browsing, connecting, connected, disconnected, hostEnded }

    private(set) var role: Role = .idle
    private(set) var roomCode: String = ""
    private(set) var connectedPeerCount: Int = 0
    private(set) var availableHosts: [DiscoveredHost] = []
    private(set) var latestSnapshot: GameSnapshot?
    private(set) var joinState: JoinState = .browsing
    private(set) var playerClaims: [UUID: PlayerClaim] = [:]   // host-side accumulator

    func startHosting(initialSnapshot: GameSnapshot)
    func stopHosting()
    func broadcast(snapshot: GameSnapshot)
    func startBrowsing()
    func connect(to host: DiscoveredHost)
    func sendClaim(_ claim: PlayerClaim)
    func leave()
}
```

This is the same shape as `FarkleNetSession`. Re-reading that file before implementing — it's a working blueprint.

### 8.2 Wire models

```swift
enum MultipeerMessage: Codable {
    case snapshot(GameSnapshot)        // host → joiners
    case claim(PlayerClaim)            // joiner → host
}

struct GameSnapshot: Codable, Equatable {
    var seq: Int                        // monotonic per host session
    var roomCode: String
    var hostName: String
    var gameID: UUID
    var length: Int
    var rules: HouseRules
    var currentStop: Int
    var players: [PlayerSnapshot]
    var scores: [ScoreSnapshot]
    var recentCaptures: [CaptureSnapshot]   // last N for the previous stop's gallery
    var endedAt: Date?
    var winnerPlayerID: UUID?
    var claims: [PlayerClaim]           // identity overrides; host merges into broadcast
}

struct PlayerSnapshot:  Codable, Equatable { var id: UUID; var name: String; var seat: Int }
struct ScoreSnapshot:   Codable, Equatable { var playerID: UUID; var stop: Int; var pips: Int }
struct CaptureSnapshot: Codable, Equatable { var id: UUID; var playerID: UUID; var stop: Int; var thumbJPEG: Data }
struct PlayerClaim:     Codable, Equatable { var playerID: UUID; var displayName: String; var photoJPEG: Data? }
```

Constraints (mirrors farkle):
- `PlayerClaim.photoJPEG` ≤ **32 KB**, resized to ~256×256 before send.
- `CaptureSnapshot.thumbJPEG` ≤ **32 KB**, only the most recent stop's gallery is sent.
- Worst-case snapshot stays well under 256 KB for 8 players × 8 captures × 32 KB photos.

Snapshots are recomputed and rebroadcast on every meaningful host-side mutation. We borrow farkle's pattern: a `hostBroadcaster(game:session:)` view modifier observes a composite fingerprint string and re-sends when it changes.

### 8.3 QR codes and Universal Links

Two paths into the join sheet for joiners:

1. **In-app scanner** (`AVCaptureMetadataOutput`, type `.qr`). The Share-Game sheet on the host displays a QR that encodes a `mextrain://join?code=NNNN&service=mextrain-game` URL. The in-app scanner decodes it directly.
2. **iOS Camera app** opens the URL via Universal Link. We register a Universal Link domain (e.g. `mextrain.app/join`) plus the apple-app-site-association file. If we'd rather not stand up a domain, we can ship with the custom URL scheme only and add Universal Link in a follow-up — both work; the custom scheme works without infrastructure.

`JoinURL` encapsulates encode/decode so the rest of the app speaks `JoinTarget` (just `code` + service ID), not URL parsing.

Room code policy is inherited from farkle's `RoomCode.swift`: 4 digits, no ambiguous patterns (1111, 1234, 4321, 2345, 5432).

### 8.4 Identity prefill (Contacts "Me" card)

`DeviceIdentity` reads the user's name and photo from the Contacts "Me" card:

```swift
struct DeviceIdentity {
    enum Access { case granted, denied, notDetermined }

    static func currentAccess() -> Access
    static func request() async -> Access                       // CNContactStore.requestAccess
    static func loadMeCard() async -> ContactPrefill?
}

struct ContactPrefill { let displayName: String?; let photo: UIImage? }
```

- We request only the keys we need: `givenName`, `familyName`, `imageData`.
- Purpose string in `Info.plist`'s `NSContactsUsageDescription`: "Use your name and photo so other players can see who joined."
- The join sheet's UI surfaces three states: permission not asked (button "Use my contact"), granted (prefilled, editable), denied (manual entry with a help link to Settings).
- Photos are resized to 256 × 256, encoded as JPEG at quality 0.7, and asserted ≤ 32 KB before being attached to a `PlayerClaim`.

### 8.5 Host-side claim handling

When a `claim` message arrives on the host:

1. Validate: `claim.playerID` matches a real player in the game; that slot is unclaimed by a different peer.
2. Persist: update `Player.name` to the claimed name; if a photo is included, save it via `PhotoStore` as `claims/<playerID>.jpg` and set `Player.avatarFilename`.
3. Re-broadcast: the next snapshot includes the merged identity.

The host's scoreboard menu has a "Revoke" action per slot that clears the claim, disconnects that peer, and rebroadcasts.

### 8.6 Joiner-side view

A joiner's app has no SwiftData game store; the view is a pure render of `MexTrainNetSession.latestSnapshot`. Components are the same ones the host uses for its own scoreboard (`ScoreCardTable`, `PhotoGalleryStrip`) — they take a snapshot-shaped input via a thin adapter, so we don't fork the rendering code.

If `joinState` flips to `.hostEnded`, the joiner sees a "host left" overlay with a "Back to home" button.

### 8.7 What doesn't ship
- No remote join (no internet relay).
- No host migration / failover.
- No spectator chat or reactions.
- No persistence on the joiner (snapshots are RAM-only). Joiners who reopen the app rejoin via room code; they don't see a history list of past hosts.

## 9. Testing

We test what matters and skip the rest.

| Area | Test |
| --- | --- |
| Scoring | Unit tests covering totals, standings, ties, sparse-score handling, engine-tile calculation across both house-rule modes. |
| House rules | Cover edge cases: 7-stop traditional ends at double-0, 7-stop alwaysTwelve ends at double-6. |
| Persistence round-trip | Save → reopen container → assert game/players/scores intact, including manual-vs-scanned source flags. |
| PhotoStore | Save/load/delete on a temp directory; assert cascade delete. |
| Vision | Test against `MockPipCounter` only; the production model is validated separately by the web app's vision harness. |
| UI | One UI smoke test: create game → enter a manual score → audit it → end game. |

No snapshot tests in v1; the components are simple enough that visual regressions are caught by eye during dev. Revisit if Pacific theme ships.

## 10. Build order

Each milestone is a feature branch + PR, targeting main. No pushing to main directly (per global CLAUDE.md).

1. **M0 — Skeleton**: Xcode project, app target, SwiftData container, Caboose theme + font registration, blank Home view. Goal: app launches with branded splash + Home shell.
2. **M1 — Game lifecycle (manual entry only)**: New-game setup, Scoreboard with golf-card table, manual keypad add-score flow, audit screen (manual), end-game screen, history list, settings. No camera, no vision. Goal: fully playable end-to-end with manual scores.
3. **M2 — Camera + MockPipCounter**: Camera capture, scanning/confirm UI, photo storage, photo gallery on scoreboard, reference photo on audit. `MockPipCounter` returns fake tiles. Goal: full UX flow works against fake vision.
4. **M3 — Real CoreML model**: Drop in `DominoDetector.mlmodel` (sourced from the web app's `ml/` training output), wire `VisionPipCounter`, tune the confidence heuristic against a small set of test photos in `MexicanTrainTests/Resources/`. Goal: shipping accuracy on real photos.
5. **M4 — Polish**: VoiceOver labels, Dynamic Type pass, empty-state copy, animations (tile pop, scan line, toast), small-screen layout checks (iPhone SE size class). Goal: TestFlight-ready build for the standalone scoring experience.
6. **M5 — Broadcast**: Implement §8 — `MexTrainNetSession`, `GameSnapshot`/`PlayerClaim` wire models, Share-Game sheet with QR + room code, in-app QR scanner, Universal Link / `mextrain://` URL handler, Join sheet with `DeviceIdentity` contacts prefill, joiner-side spectator/player view rendering snapshots, host claim handling + revoke. Goal: two phones in the same room can join one host and see live scores.

Each milestone is independently demoable. M1 alone is a useful manual scoreboard; M2 adds the camera flow with stub vision; M3 is the headline feature; M4 finishes the standalone product; M5 turns it into a table-wide experience.

## 11. Open dev questions

1. **CoreML model source**: do we wait for the YOLOv11 training in `platform/apps/mextrain/ml/` to finish, or do we train a smaller iOS-targeted model from the same `testdata/photos/` set? Affects M3 readiness. Recommend: use whatever the web app produces, since the training set and ground truth are already there.
2. **Font licensing**: Rye and Special Elite are SIL OFL — fine to bundle. Need to commit `LICENSE.fonts.txt` alongside the .ttf files. Mechanical; flagging so we don't forget.
3. **Photo capture orientation lock**: if a user holds the phone landscape to photograph tiles, do we accept the landscape photo or force portrait? Recommend: accept landscape captures (rotate at save time so the model gets upright input), but keep the UI portrait-locked.
4. **iCloud / device backup**: SwiftData and Application Support are both included in default iOS backups. That's fine for v1 — users get device-restore "for free." Note for the spec: this isn't iCloud sync, just standard backup behavior.
5. **Universal Link domain**: standing one up costs us an AASA file and a hostname. Acceptable answer for M5 is "custom URL scheme `mextrain://` only — Universal Link in a follow-up." Confirm before M5 begins so we don't half-implement.
6. **Joiner data model**: spectator/player joiners don't get a SwiftData store. If we later want join history ("recent games I watched"), that's a follow-on; flagging so the snapshot model stays self-contained and doesn't pull in SwiftData types.

## 12. Change log

- 2026-05-21 — v0.1 — Initial draft. Covers stack, project layout, data model, photo storage, vision pipeline, theme, navigation, testing, and a four-milestone build plan.
- 2026-05-21 — v0.2 — Added broadcast (§8 / M5): MultipeerConnectivity transport modeled on `~/code/farkle`, `GameSnapshot` / `PlayerClaim` wire models, QR + room code join, Contacts-Me-card identity prefill (`DeviceIdentity`), host claim handling, and joiner spectator/player rendering. Added `avatarFilename` to `Player`. Two new open questions (URL scheme vs Universal Link, joiner data model).
- 2026-05-21 — **M0 landed** on branch `m0-skeleton`. Xcode project generated via XcodeGen (`project.yml`), iOS 17 target, Caboose theme injected via SwiftUI Environment, `AppCoordinator` + `MexicanTrainApp` wired, SwiftData `ModelContainer` instantiates with a stub `Game` model, Home view renders a branded empty state with a disabled "NEW GAME" CTA. Two unit tests passing. Custom .ttf files deferred — `Theme.displayFont`/`monoFont` fall back to system serif/monospaced until Rye and Special Elite are dropped into `MexicanTrain/Resources/Fonts/`.
- 2026-05-21 — **M1 landed** on branch `m1-game-lifecycle`. Full SwiftData model (Game, Player, Score, Capture), pure-Swift `Scoring` (totals, standings with tied places, sparse grid, engine tile per house rule), `GamePersistence` helpers (create / record / advance / rename / delete / end early), `AppSettings` (UserDefaults). Screens: Home (in-progress card + history list + settings gear), NewGame (length picker, house-rule picker, dynamic player list, "you" toggle), Scoreboard (header + engine strip + you-stats strip + golf-card table + add-score / advance / finish CTA + game menu), ManualEntry (keypad), Audit (± / quick-chip pip editor), EndGame (winner card + standings), GameHistory (read-only), Settings. 10 unit tests passing (scoring totals, ties, sparse rows, stop advance, finish-on-final, engine traditional/alwaysTwelve, audit overwrite).
- 2026-05-21 — **M2 landed** on branch `m2-camera-mock-vision`. Adds `PipCounter` protocol with `MockPipCounter` (seeded randomness, 4–8 tiles, ~700ms simulated latency). `PhotoStore` writes JPEGs under `Application Support/MexicanTrain/photos/<gameID>/<captureID>.jpg` and produces on-demand thumbnails. `CapturePersistence.saveCapture` ties a SwiftData `Capture` to a saved photo + pip-count result. New `CameraView` uses AVFoundation (with a simulator fallback that synthesizes a wood-tone capture) and runs an aim → scanning → confirm flow; "123" button swaps to manual entry. Scoreboard "Add Score" now opens camera by default; new `PhotoGalleryStrip` renders the previous stop's captures below the table. Audit screen shows the reference photo and a "Re-scan" button. `NSCameraUsageDescription` added. 4 new unit tests (PhotoStore round-trip, thumbnail, delete cascade; MockPipCounter contract). 14 total tests passing.
- 2026-05-21 — **M3 landed** on branch `m3-coreml-wiring`. `VisionPipCounter` uses `VNCoreMLRequest` against a bundled `DominoDetector.mlmodel` and parses class strings of the form `tile-A-B` (with a forgiving regex that accepts `_` separators, no-separator concatenations, and either order). Confidence is bucketed via `avg ≥ 0.80 ∧ min ≥ 0.50 → high`, `avg ≥ 0.50 → medium`, else `low`. `PipCounterFactory.makeProductionCounter()` returns the Vision impl when the model file is bundled and falls back to `MockPipCounter` otherwise — the app shipping path. `Vision/MODEL_CONTRACT.md` documents input shape, class-string regex, confidence rules, and the `coremltools` export recipe to convert the YOLOv11 checkpoint from the web app's `ml/`. 4 new unit tests (class parser, confidence buckets, factory fallback). 18 total tests passing. The .mlmodel itself is **not yet bundled** — drop into `MexicanTrain/Vision/` and re-add to the target to activate without code changes.
- 2026-05-21 — **M4 landed** on branch `m4-polish`. Dynamic Type pass: `Theme.displayFont` / `monoFont` now anchor to `Font.TextStyle` via `relativeTo:` so custom-font text scales with the user's preferred size (system-font fallback already scaled). Camera confirm shows a row of detected tiles with a spring-animated pop entrance and uses `contentTransition(.numericText())` on the big total. Toast on stop-close slides up + fades. Accessibility labels on the scoreboard CTA, photo-tile buttons, individual detected tiles, and decorative SF Symbols marked `accessibilityHidden`. End-to-end persistence smoke tests cover the golden path (create → score every stop → finish, audit overwrite, delete cascade). 21 total tests passing.
