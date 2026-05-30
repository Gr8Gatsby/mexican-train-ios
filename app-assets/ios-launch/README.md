# iOS launch screen — install

Two paths to install, both supported on iOS 14+:

## Option A — Info.plist launch screen (recommended, simplest)

Apple's modern approach. No storyboard file needed.

1. Drop the three launch icons into `Assets.xcassets` as an Image Set
   named **LaunchIcon**:
   - `launch-icon@1x.png` → 1x slot (240 × 240)
   - `launch-icon@2x.png` → 2x slot (480 × 480)
   - `launch-icon@3x.png` → 3x slot (720 × 720)

2. Add a Color Set named **LaunchBackground**:
   - Any Appearance: `#8C2A1A` (oxblood)
   - Dark Appearance (optional): `#5E1A0F`

3. Merge `LaunchScreen-Info.plist.snippet.xml` into your `Info.plist` (or
   set the same keys in Xcode target ▸ Info).

That's it — iOS will render the centered icon on the oxblood field.

## Option B — Full-bleed SwiftUI "first screen"

Apple's launch screen can only display a centered image on a color, no text.
If you want the headline / tagline visible (like in `launch-screen-mockup.png`),
do Option A for the system launch *and* show `LaunchScreenPreview.swift`
(included in this folder) as your first SwiftUI view after launch — dismiss
it once your initial data load completes.

```swift
@main
struct MexicanTrainApp: App {
    @State private var loaded = false
    var body: some Scene {
        WindowGroup {
            if loaded {
                ContentView()
            } else {
                LaunchScreenPreview()
                    .task {
                        try? await Task.sleep(for: .seconds(0.6))
                        loaded = true
                    }
            }
        }
    }
}
```

## Files in this folder

- `launch-screen-mockup.png` — 1179 × 2556 design preview (full-bleed look)
- `launch-icon@1x/@2x/@3x.png` — the centered icon, for Option A
- `LaunchScreen-Info.plist.snippet.xml` — the Info.plist keys
- `LaunchScreenPreview.swift` — SwiftUI version for Option B
