import SwiftUI
import SwiftData
import UIKit

/// Read-only detail screen for a game the user joined. Renders from the
/// cached `GameSnapshot` plus the accumulated `JoinedCapture` thumbnails.
/// Shareable via `GameReport.text(snapshot:)`; deletable from the
/// trash icon in the header.
struct JoinedGameView: View {
    let gameID: UUID

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query private var records: [JoinedGameRecord]
    @State private var confirmDelete = false

    init(gameID: UUID) {
        self.gameID = gameID
        let id = gameID
        _records = Query(filter: #Predicate<JoinedGameRecord> { $0.gameID == id })
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let record = records.first, let snap = record.snapshot {
                content(record: record, snap: snap)
            } else {
                ContentUnavailableView(
                    "Game not found", systemImage: "questionmark.folder",
                    description: Text("This joined-game record is missing or its data couldn't be decoded.")
                )
                .onAppear { coordinator.goHome() }
            }
        }
        .alert("Delete this joined game?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let record = records.first {
                    try? JoinedGamePersistence.delete(record, in: context)
                }
                coordinator.goHome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the cached snapshot and photos from this device. Won't affect anyone else.")
        }
    }

    @ViewBuilder
    private func content(record: JoinedGameRecord, snap: GameSnapshot) -> some View {
        VStack(spacing: 0) {
            AppHeaderBar(
                style: .push,
                title: record.gameName,
                subtitle: record.isFinished ? "FINAL · hosted by \(record.hostName)" : "JOINED · hosted by \(record.hostName)",
                onLeading: { coordinator.goHome() }
            ) {
                ShareLink(item: GameReport.text(snapshot: snap)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share game report")
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete joined game")
            }
            ScrollView {
                VStack(spacing: 12) {
                    summaryCard(snap: snap, record: record)
                    SnapshotTable(snap: snap, myPlayerID: record.myPlayerID)
                        .padding(.horizontal, 8)
                    if !record.captures.isEmpty {
                        capturesStrip(record.captures)
                    }
                }
                .padding(.vertical, 12)
            }
            footer
        }
    }

    private func summaryCard(snap: GameSnapshot, record: JoinedGameRecord) -> some View {
        VStack(spacing: 4) {
            Text(record.isFinished ? "FINAL" : "GAME IN PROGRESS WHEN YOU LEFT")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text("Hosted by \(record.hostName)")
                .font(theme.displayFont(size: 18))
                .foregroundStyle(theme.ink)
            Text("\(snap.players.count) players · \(snap.length)-stop game · stop \(min(snap.currentStop, snap.length))/\(snap.length)")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func capturesStrip(_ captures: [JoinedCapture]) -> some View {
        let sorted = captures.sorted { ($0.stopIndex, $0.receivedAt) < ($1.stopIndex, $1.receivedAt) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("PHOTOS")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sorted, id: \.captureID) { c in
                        if let img = UIImage(data: c.thumbJPEG) {
                            VStack(spacing: 2) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(theme.borderLight, lineWidth: 1)
                                    )
                                Text("STOP \(c.stopIndex)")
                                    .font(theme.monoFont(size: 9))
                                    .tracking(1.0)
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var footer: some View {
        Button { coordinator.goHome() } label: { Text("DONE") }
            .appPrimaryStyle()
            .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
            .background(theme.subBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }
}
