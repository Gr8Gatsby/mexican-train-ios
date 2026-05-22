import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var exportError: String?
    @State private var exportZipURL: URL?
    @State private var exporting: Bool = false

    var body: some View {
        @Bindable var bind = settings
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("DEFAULT GAME LENGTH") {
                            HStack(spacing: 8) {
                                ForEach([7, 10, 13], id: \.self) { n in
                                    Button { bind.defaultLengthStops = n } label: {
                                        Text("\(n)")
                                            .font(theme.displayFont(size: 22))
                                            .frame(maxWidth: .infinity, minHeight: 52)
                                            .foregroundStyle(settings.defaultLengthStops == n ? theme.ctaText : theme.ink)
                                            .background(settings.defaultLengthStops == n ? theme.cta : theme.cardBg,
                                                        in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                                    .stroke(theme.border, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        section("DEFAULT \"YOU\" NAME") {
                            TextField("Your name", text: $bind.defaultYouName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(theme.borderLight, lineWidth: 1)
                                )
                        }
                        trainingExportSection(bind: bind)
                        about
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("← BACK") { coordinator.goHome() }
                .font(theme.monoFont(size: 10))
                .tracking(1.2)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.subBg, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
            Text("SETTINGS")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            content()
        }
    }

    @ViewBuilder
    private func trainingExportSection(bind: AppSettings) -> some View {
        let labeledCount = TrainingDataExporter.labeledCaptureCount(in: modelContext)
        section("HELP IMPROVE THE MODEL") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { settings.trainingDataExportEnabled },
                    set: { bind.trainingDataExportEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save corrections as training data")
                            .font(theme.monoFont(size: 12))
                            .foregroundStyle(theme.ink)
                        Text("When on, the audit screen lets you tap individual tiles in the photo to correct the model's count. Saved labels stay on this device until you export them.")
                            .font(theme.monoFont(size: 10))
                            .foregroundStyle(theme.muted)
                    }
                }
                .tint(theme.brand)
                .padding(12)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.borderLight, lineWidth: 1)
                )

                if settings.trainingDataExportEnabled {
                    HStack {
                        Text("\(labeledCount) photo\(labeledCount == 1 ? "" : "s") labeled")
                            .font(theme.monoFont(size: 11))
                            .foregroundStyle(theme.muted)
                        Spacer()
                        Button {
                            runExport()
                        } label: {
                            HStack(spacing: 6) {
                                if exporting {
                                    ProgressView().tint(theme.ink)
                                }
                                Text(exporting ? "PREPARING…" : "EXPORT LABELED PHOTOS")
                                    .font(theme.monoFont(size: 11))
                                    .tracking(1.4)
                            }
                            .foregroundStyle(labeledCount > 0 ? theme.ink : theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .disabled(labeledCount == 0 || exporting)
                    }
                    if let url = exportZipURL {
                        ShareLink(item: url) {
                            Text("SHARE EXPORT.ZIP")
                                .font(theme.monoFont(size: 11))
                                .tracking(1.4)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(theme.ctaText)
                                .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                        }
                    }
                    if let exportError {
                        Text(exportError)
                            .font(theme.monoFont(size: 10))
                            .foregroundStyle(theme.brand)
                    }
                }
            }
        }
    }

    private func runExport() {
        exporting = true
        exportError = nil
        exportZipURL = nil
        Task {
            do {
                let summary = try TrainingDataExporter.export(
                    context: modelContext, photoStore: coordinator.photoStore
                )
                await MainActor.run {
                    exportZipURL = summary.zipURL
                    exporting = false
                }
            } catch TrainingDataExporter.ExportError.noLabeledCaptures {
                await MainActor.run {
                    exportError = "No labeled photos yet. Open the audit screen with a photo and tap a tile to correct it."
                    exporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = "Export failed: \(error.localizedDescription)"
                    exporting = false
                }
            }
        }
    }

    private var about: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text("ABOUT")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text("Mexican Train v\(version)")
                .font(theme.displayFont(size: 16))
                .foregroundStyle(theme.ink)
            Text("A toy companion app. Single device, no accounts, no cloud.")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
        }
    }
}
