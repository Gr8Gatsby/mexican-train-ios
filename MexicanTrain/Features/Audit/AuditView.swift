import SwiftUI
import SwiftData

struct AuditView: View {
    let game: Game
    let player: Player
    let stop: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var value: String
    @State private var excludedDraft: Bool
    /// Mutable working copy of the capture's per-half labels, edited via
    /// `EditableDetectionOverlay`. Seeded from `correctedTiles` if the
    /// conductor has labeled before, else the raw model output.
    @State private var labelDraft: [TileObservation] = []
    /// True when the user has touched at least one chip since arriving on
    /// this view; flips on `labelDraft` mutation. Drives whether `save()`
    /// writes corrected labels, and gates the "labels saved" toast.
    @State private var labelDraftDirty: Bool = false

    init(game: Game, player: Player, stop: Int) {
        self.game = game
        self.player = player
        self.stop = stop
        let existing = Scoring.score(for: player.id, stop: stop, in: game)
        _value = State(initialValue: existing.map { String($0.pips) } ?? "0")
        _excludedDraft = State(initialValue: existing?.excluded ?? false)
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: "Audit · \(player.name)",
                    subtitle: "STOP \(stop) / \(game.lengthStops)",
                    onLeading: { coordinator.openScoreboard(game) }
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        pipEditor
                        excludeToggle
                        infoBlock
                        referenceArea
                        if settings.trainingDataExportEnabled, matchingCapture != nil {
                            labelingEditorSection
                        }
                        auditHistorySection
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .onAppear { seedLabelDraft() }
    }

    private func seedLabelDraft() {
        guard let capture = matchingCapture else { return }
        labelDraft = capture.correctedTiles ?? capture.tiles
        labelDraftDirty = false
    }

    private var originalPips: Int {
        Scoring.score(for: player.id, stop: stop, in: game)?.pips ?? 0
    }
    private var numeric: Int { Int(value) ?? 0 }
    private var delta: Int { numeric - originalPips }
    private var newTotal: Int {
        Scoring.total(for: player.id, in: game) - originalPips + numeric
    }
    private var existing: Score? {
        Scoring.score(for: player.id, stop: stop, in: game)
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYER")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.8)
                    .foregroundStyle(theme.muted)
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(theme.displayFont(size: 24))
                        .foregroundStyle(theme.ink)
                    if player.isYou {
                        Text("YOU")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                    }
                }
                HStack(spacing: 6) {
                    Text("ENGINE")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(theme.muted)
                    let n = Scoring.engineTile(stop: stop, rules: game.startingEngine, length: game.lengthStops)
                    DominoGlyph(value: n, width: 26, color: theme.ink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("TOTAL AFTER SAVE")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
                Text("\(newTotal)")
                    .font(theme.displayFont(size: 28))
                    .foregroundStyle(theme.brand)
                if existing != nil, delta != 0 {
                    Text("\(delta > 0 ? "+" : "")\(delta) vs recorded")
                        .font(theme.monoFont(size: 12))
                        .foregroundStyle(delta > 0 ? Color(hex: 0xB54B2C) : Color(hex: 0x3A7A3A))
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(theme.subBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var pipEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PIP COUNT")
                .font(theme.monoFont(size: 11))
                .tracking(1.8)
                .foregroundStyle(theme.muted)

            HStack(spacing: 10) {
                stepButton(label: "−") { adjust(-1) }
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(theme.displayFont(size: 64))
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity)
                stepButton(label: "+") { adjust(+1) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 1)
            )

            HStack(spacing: 6) {
                ForEach([-10, -5, 5, 10], id: \.self) { d in
                    Button {
                        adjust(d)
                    } label: {
                        Text(d > 0 ? "+\(d)" : "\(d)")
                            .font(theme.monoFont(size: 14))
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = existing {
                Text(s.source == .scanned ? "ENTERED VIA CAMERA" : "ENTERED MANUALLY")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.6)
                    .foregroundStyle(theme.muted)
            }
            Text("LAST UPDATED \(existing?.updatedAt.formatted(date: .omitted, time: .shortened) ?? "—")")
                .font(theme.monoFont(size: 11))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14)
    }

    private var matchingCapture: Capture? {
        if let cid = existing?.captureID {
            return game.captures.first(where: { $0.id == cid })
        }
        return game.captures.first(where: { $0.playerID == player.id && $0.stopIndex == stop })
    }

    @ViewBuilder
    private var referenceArea: some View {
        let capture = matchingCapture
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(capture == nil ? "NO CAPTURE" : "REFERENCE PHOTO")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.8)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button {
                    coordinator.openCamera(game: game, player: player, stop: stop)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 13, weight: .semibold))
                        Text(capture == nil ? "SCAN NOW" : "RE-SCAN")
                    }
                }
                .appPillStyle()
            }
            if let capture, let img = coordinator.photoStore.load(filename: capture.filename, gameID: game.id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.ink, lineWidth: 2)
                    )
                if !capture.tiles.isEmpty {
                    Text("DETECTED \(capture.tiles.count) TILES · \(capture.pipsDetected ?? 0) PIPS")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.2)
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder
    private var excludeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EXCLUDE FROM TOTAL")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.8)
                    .foregroundStyle(theme.muted)
                Spacer()
                Toggle("", isOn: $excludedDraft)
                    .labelsHidden()
                    .tint(theme.brand)
            }
            Text(excludedDraft
                 ? "Counts as 0 toward this player's total. Original value kept in audit history."
                 : "Counts toward the total normally.")
                .font(theme.monoFont(size: 12))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private var labelingEditorSection: some View {
        if let capture = matchingCapture,
           let img = coordinator.photoStore.load(filename: capture.filename, gameID: game.id) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LABEL TILES")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.8)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    if capture.isLabeled || labelDraftDirty {
                        Text("LABELED")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                    }
                }
                Text("Tap a chip to correct its pip value. Tap empty space on the photo to add a missed half. Saved labels are used by Export in Settings.")
                    .font(theme.monoFont(size: 12))
                    .foregroundStyle(theme.muted)
                EditableDetectionOverlay(
                    image: img,
                    tiles: Binding(
                        get: { labelDraft },
                        set: { new in
                            labelDraft = new
                            labelDraftDirty = true
                        }
                    ),
                    color: theme.accent
                )
                .frame(height: 220)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.border, lineWidth: 1)
                )
                if labelDraftDirty {
                    Text("Sum of corrected halves: \(labelDraft.reduce(0) { $0 + $1.pips })")
                        .font(theme.monoFont(size: 12))
                        .foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var auditHistorySection: some View {
        if let s = existing, !s.edits.isEmpty || s.originalPips != s.pips {
            VStack(alignment: .leading, spacing: 6) {
                Text("AUDIT HISTORY")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.8)
                    .foregroundStyle(theme.muted)
                VStack(spacing: 0) {
                    historyRow(label: "Submitted",
                               value: "\(s.originalPips) pips",
                               by: s.submittedBy,
                               at: s.edits.min(by: { $0.editedAt < $1.editedAt })?.editedAt ?? s.updatedAt)
                    ForEach(s.edits.sorted(by: { $0.editedAt < $1.editedAt })) { e in
                        Divider().overlay(theme.borderLight)
                        historyRow(label: editLabel(for: e),
                                   value: editValue(for: e),
                                   by: e.editedBy,
                                   at: e.editedAt)
                    }
                }
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.borderLight, lineWidth: 1)
                )
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func historyRow(label: String, value: String, by: ScoreActor, at: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.ink)
                Text("by \(by == .player ? "player" : "conductor") · \(at.formatted(date: .omitted, time: .shortened))")
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Text(value)
                .font(theme.monoFont(size: 11))
                .fontWeight(.semibold)
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func editLabel(for e: ScoreEdit) -> String {
        if e.fromExcluded != e.toExcluded {
            return e.toExcluded ? "Excluded" : "Re-included"
        }
        return "Adjusted"
    }

    private func editValue(for e: ScoreEdit) -> String {
        if e.fromExcluded != e.toExcluded {
            return e.toExcluded ? "→ 0 pips (was \(e.fromPips))" : "→ \(e.toPips) pips"
        }
        return "\(e.fromPips) → \(e.toPips) pips"
    }

    private func stepButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(theme.displayFont(size: 24))
                .foregroundStyle(theme.ink)
                .frame(width: 48, height: 48)
                .background(theme.subBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.openScoreboard(game)
            } label: { Text("DISCARD") }
                .appSecondaryStyle()
            Button(action: save) {
                Text(existing == nil ? "SAVE SCORE" : "SAVE CORRECTION")
            }
            .appPrimaryStyle()
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private func adjust(_ delta: Int) {
        let next = max(0, numeric + delta)
        value = String(next)
    }

    private func save() {
        let n = max(0, numeric)
        do {
            try GamePersistence.recordScore(in: context, game: game, player: player,
                                            stop: stop, pips: n,
                                            source: existing?.source ?? .manual,
                                            submittedBy: existing?.submittedBy ?? .conductor,
                                            editedBy: .conductor,
                                            captureID: existing?.captureID)
            if let s = Scoring.score(for: player.id, stop: stop, in: game),
               s.excluded != excludedDraft {
                try GamePersistence.setScoreExcluded(in: context, score: s,
                                                    excluded: excludedDraft,
                                                    editedBy: .conductor)
            }
            if labelDraftDirty, let capture = matchingCapture {
                try CapturePersistence.saveLabels(in: context, capture: capture, tiles: labelDraft)
            }
            coordinator.openScoreboard(game)
        } catch {
            coordinator.goHome()
        }
    }
}
