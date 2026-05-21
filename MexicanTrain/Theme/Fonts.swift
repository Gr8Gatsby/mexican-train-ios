import CoreText
import Foundation

enum Fonts {
    /// Registers any custom .ttf files we've bundled. If a file is missing
    /// (which is the case during early milestones), the app falls back to
    /// system fonts via Theme.displayFont / Theme.monoFont.
    static func registerBundledFonts() {
        let names = ["Rye-Regular", "SpecialElite-Regular"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
