# Android adaptive icon — install

```
app/src/main/res/
├── mipmap-anydpi-v26/
│   ├── ic_launcher.xml          ← from ic_launcher.xml in this folder
│   └── ic_launcher_round.xml    ← duplicate of ic_launcher.xml
├── mipmap-mdpi/
│   └── ic_launcher_foreground.png   ← 108 px (resize from ic_launcher_foreground.png)
├── mipmap-hdpi/
│   └── ic_launcher_foreground.png   ← 162 px
├── mipmap-xhdpi/
│   └── ic_launcher_foreground.png   ← 216 px
├── mipmap-xxhdpi/
│   └── ic_launcher_foreground.png   ← 324 px
├── mipmap-xxxhdpi/
│   └── ic_launcher_foreground.png   ← 432 px (use the file in this folder as-is)
└── values/
    └── colors.xml               ← merge the ic_launcher_background entry
```

The 432×432 PNG in this folder is the xxxhdpi master. Android Studio's Image
Asset Studio (right-click `res/` → New → Image Asset) will generate the smaller
densities from that single master image — easier than hand-resizing.

## Notes
- `ic_launcher_background.png` is a flat oxblood square. You can swap to the
  `<color name="ic_launcher_background">` resource referenced in `ic_launcher.xml`
  and skip shipping the background PNG (smaller APK).
- The `<monochrome>` element enables Android 13+ themed icons; we point it at
  the same foreground for now. To get a true grayscale themed icon, supply a
  separate flat-silhouette PNG and reference it there.
- Previews of how the icon will look under the system launcher masks are in
  `preview-circle.png` and `preview-squircle.png`.
