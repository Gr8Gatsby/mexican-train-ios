import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var exportError: String?
    @State private var exportZipURL: URL?
    @State private var exporting: Bool = false
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var bind = settings
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: "Settings",
                    onLeading: { coordinator.goHome() }
                )
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
                        section("YOUR IDENTITY") {
                            identityBlock(bind: bind)
                        }
                        trainingExportSection(bind: bind)
                        about
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func identityBlock(bind: AppSettings) -> some View {
        @Bindable var bind = bind
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatarView
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(
                        selection: $photoPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 13, weight: .semibold))
                            Text(settings.defaultYouPhotoJPEG == nil ? "PICK PHOTO" : "CHANGE PHOTO")
                        }
                        .font(theme.monoFont(size: 12))
                        .fontWeight(.semibold)
                        .tracking(1.4)
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }
                    .accessibilityLabel(settings.defaultYouPhotoJPEG == nil ? "Pick photo" : "Change photo")
                    if settings.defaultYouPhotoJPEG != nil {
                        Button {
                            bind.defaultYouPhotoJPEG = nil
                            photoPickerItem = nil
                        } label: { Text("REMOVE PHOTO") }
                            .appLinkStyle()
                    }
                }
                Spacer()
            }

            TextField("Your name", text: $bind.defaultYouName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.borderLight, lineWidth: 1)
                )

            Text("Used as the default for new games and when joining games from this device.")
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.muted)
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task { await loadPickedPhoto(newItem, into: bind) }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(theme.cardBg)
                .overlay(Circle().stroke(theme.border, lineWidth: 1))
            if let data = settings.defaultYouPhotoJPEG, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?, into bind: AppSettings) async {
        guard let item else { return }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        let compressed = DeviceIdentity.compressPhoto(raw)
        await MainActor.run {
            bind.defaultYouPhotoJPEG = compressed
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.monoFont(size: 11))
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
                    Text("\(labeledCount) photo\(labeledCount == 1 ? "" : "s") labeled")
                        .font(theme.monoFont(size: 12))
                        .foregroundStyle(theme.muted)
                    Button {
                        runExport()
                    } label: {
                        HStack(spacing: 8) {
                            if exporting {
                                ProgressView().tint(theme.ink)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(exporting ? "PREPARING…" : "EXPORT LABELED PHOTOS")
                        }
                    }
                    .appSecondaryStyle()
                    .disabled(labeledCount == 0 || exporting)
                    .opacity(labeledCount == 0 ? 0.55 : 1)
                    if let url = exportZipURL {
                        ShareLink(item: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.fill")
                                Text("SHARE EXPORT.ZIP")
                            }
                            .font(theme.displayFont(size: 14))
                            .tracking(2.5)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(theme.ctaText)
                            .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                        }
                    }
                    if let exportError {
                        Text(exportError)
                            .font(theme.monoFont(size: 11))
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
