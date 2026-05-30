# Android splash screen — install

Uses the Android 12+ SplashScreen API (`androidx.core:core-splashscreen`).

```
app/src/main/res/
├── drawable/
│   └── splash_icon.png             ← rename splash-icon-1024.png to splash_icon.png
└── values/
    └── themes.xml                  ← merge entries from themes.xml in this folder
```

1. Add the dependency in `app/build.gradle.kts`:
   ```kotlin
   implementation("androidx.core:core-splashscreen:1.0.1")
   ```

2. Install the splash icon: copy `splash-icon-1024.png` to
   `app/src/main/res/drawable/splash_icon.png`.

3. Merge the theme entries from `themes.xml` into your project's `themes.xml`.

4. Set the activity theme in `AndroidManifest.xml`:
   ```xml
   <activity android:theme="@style/Theme.MexicanTrain.Splash" ...>
   ```

5. In your launcher activity's `onCreate`, install the splash:
   ```kotlin
   override fun onCreate(savedInstanceState: Bundle?) {
       installSplashScreen()           // dismisses cleanly when content loads
       super.onCreate(savedInstanceState)
       setContent { MexicanTrainApp() }
   }
   ```

## Notes
- The splash icon should be a centered, single-element drawable. The system
  applies a circular mask and sizes it to ~192dp (96dp inner safe zone).
- Our `splash-icon-1024.png` has the full train, which is wide. At launch it
  will be center-cropped to roughly the locomotive — that's fine and reads as
  the brand. For a tighter splash, swap in `../icon-layers/AppIcon-1024.png`
  instead, which keeps the iconic squircle form.
- `splash-mockup.png` shows the approximate look on a Pixel-class phone
  (1080×2400). Real splash duration is brief — the asset is mostly a brand cue,
  not a full-bleed screen.
