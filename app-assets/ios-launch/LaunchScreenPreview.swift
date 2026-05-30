import SwiftUI

// LaunchScreenPreview.swift
//
// SwiftUI mockup of the launch screen for design preview ONLY. Apple's launch
// screens are static (UILaunchScreen plist or .storyboard); a SwiftUI view
// cannot be the actual launch screen. Use this in #Preview to iterate on the
// look, and ship the static asset described in LaunchScreen-Info.plist.snippet.xml.
//
// To make it your *first real screen* (so you can keep the SwiftUI design
// rendered briefly after the system splash dismisses), present this view
// in AppCoordinator and dismiss after a short delay or when initial data loads.

struct LaunchScreenPreview: View {
    var body: some View {
        ZStack {
            Color(red: 0x8C / 255.0, green: 0x2A / 255.0, blue: 0x1A / 255.0)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                Image("LaunchIcon")            // The 720pt centered train asset
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)

                VStack(spacing: 10) {
                    Text("MEXICAN TRAIN")
                        .font(.custom("Rye-Regular", size: 36, relativeTo: .largeTitle))
                        .foregroundStyle(Color(red: 0xFB / 255.0,
                                               green: 0xF4 / 255.0,
                                               blue: 0xE2 / 255.0))

                    Text("All aboard the scorebook")
                        .font(.custom("SpecialElite-Regular", size: 16, relativeTo: .body))
                        .foregroundStyle(Color(red: 0xD9 / 255.0,
                                               green: 0xC2 / 255.0,
                                               blue: 0x94 / 255.0))
                }

                Spacer()
                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    LaunchScreenPreview()
}
