# App assets — Mexican Train

All brand and platform assets for the iOS app + optional Android port,
built around the Caboose theme (oxblood field, brass borders, cream tiles).

Source of truth: `icon-layers/composite-preview.svg`. Everything else is
derived from it.

## iOS

| Folder | What's in it |
|---|---|
| `icon-layers/` | 5 SVG layers (background, rays, train, smoke, highlight) for Icon Composer + flat `AppIcon-1024.png` |
| `ios-marketing/` | `AppIcon-1024-light.png`, `-dark.png`, `-tinted.png` — variants for iOS 18 home-screen modes |
| `ios-launch/` | `launch-icon@1x/@2x/@3x.png` + `Info.plist` snippet + SwiftUI preview view (`LaunchScreenPreview.swift`) + design mockup |
| `ios-promo/` | `feature-graphic-1920x1080.png` — horizontal hero for marketing / press / OG image |
| `ios-screenshots/` | `screenshot-frame-6.7.png`, `-6.5.png`, `-5.5.png` — branded templates for App Store Connect screenshots |

## Android

| Folder | What's in it |
|---|---|
| `android-icon/` | Adaptive icon: `ic_launcher_foreground.png` (432×432) + `ic_launcher_background.png` + `ic_launcher.xml` + `colors.xml` + circle/squircle previews + install README |
| `android-play-store/` | `play-store-512.png` (Play Store listing icon) + `feature-graphic-1024x500.png` (Play Store hero) |
| `android-splash/` | `splash-icon-1024.png` + `themes.xml` (SplashScreen API) + `splash-mockup.png` design preview + install README |

## Caboose theme tokens (for reference)

| Token | Hex |
|---|---|
| `bg` (oxblood field) | `#8C2A1A` |
| `bg-deep` (vignette corners) | `#5E1A0F` |
| `bg-light` (highlight peak) | `#A8341F` |
| `ink` (deep brown) | `#2A1D10` |
| `cream` (tile face) | `#FBF4E2` |
| `brass` (borders) | `#C2A778` |
| `brass-light` (highlights) | `#D9C294` |
| `accent` (rust orange) | `#C8541D` |
| `lantern-red` (caboose lantern) | `#E24B4A` |

## To regenerate

The build script that produces every PNG from the master SVG lives at
`outputs/_build_assets.py` (one level up from this folder). Run with
`python3 _build_assets.py` after `pip install cairosvg pillow`.

## Folder-specific READMEs

- `ios-launch/README.md` — Info.plist vs. SwiftUI launch installation
- `android-icon/README.md` — adaptive icon density buckets
- `android-splash/README.md` — SplashScreen API setup
