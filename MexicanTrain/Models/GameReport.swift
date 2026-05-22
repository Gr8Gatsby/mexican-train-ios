import Foundation

/// Plain-text game report formatted for the iOS share sheet (spec §3.8).
/// Faithful to what happened: includes original submissions, audits, and
/// exclusions so the report can be sent to players after the game without
/// anyone wondering how a score got from one value to another.
enum GameReport {
    static func text(for game: Game, now: Date = .now) -> String {
        var lines: [String] = []
        lines.append("MEXICAN TRAIN — \"\(game.displayName)\"")
        lines.append("\(dateLine(game: game, fallback: now))")
        let players = game.sortedPlayers
        let engine0 = Scoring.engineTile(stop: 1, rules: game.startingEngine, length: game.lengthStops)
        lines.append("\(players.count) players · \(game.lengthStops)-stop game · engine \(engine0) → 0")
        lines.append("")
        lines.append("FINAL STANDINGS")
        for s in Scoring.standings(for: game) {
            let dots = String(repeating: ".", count: max(1, 20 - s.name.count))
            lines.append("  \(s.place). \(s.name) \(dots) \(s.total)")
        }

        let lastEnteredStop = (1...game.lengthStops).reversed().first { stop in
            game.scores.contains(where: { $0.stopIndex == stop })
        } ?? 0
        if lastEnteredStop >= 1 {
            lines.append("")
            for stop in 1...lastEnteredStop {
                let engine = Scoring.engineTile(stop: stop, rules: game.startingEngine, length: game.lengthStops)
                lines.append("STOP \(stop) (engine \(engine))")
                let entered = players.contains { p in
                    game.scores.contains(where: { $0.playerID == p.id && $0.stopIndex == stop })
                }
                if !entered {
                    lines.append("  (no scores entered)")
                    continue
                }
                for p in players {
                    if let score = game.scores.first(where: { $0.playerID == p.id && $0.stopIndex == stop }) {
                        lines.append("  " + scoreLine(player: p, score: score))
                    } else {
                        lines.append("  \(pad(p.name)) — — — not entered")
                    }
                }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Joiner-side report, generated from a cached `GameSnapshot`.
    /// Snapshots don't carry the audit chain, so this version is
    /// summary-only — current pip value, original submitter — with a
    /// footer noting that the host has the full audit log.
    static func text(snapshot snap: GameSnapshot, now: Date = .now) -> String {
        var lines: [String] = []
        lines.append("MEXICAN TRAIN — \"\(snap.gameName)\" (joined)")
        lines.append(dateLine(snapshot: snap, fallback: now))
        let engine0 = Scoring.engineTile(stop: 1, rules: snap.startingEngine, length: snap.length)
        lines.append("\(snap.players.count) players · \(snap.length)-stop game · engine \(engine0) → 0")
        lines.append("Hosted by \(snap.hostName)")
        lines.append("")

        let players = snap.players.sorted(by: { $0.seat < $1.seat })
        let nameFor: (UUID) -> String = { pid in
            if let claim = snap.claims.first(where: { $0.playerID == pid }) {
                return claim.displayName
            }
            return players.first(where: { $0.id == pid })?.name ?? "Player"
        }

        let totals: [(UUID, String, Int)] = players.map { p in
            let total = snap.scores
                .filter { $0.playerID == p.id && !$0.excluded }
                .reduce(0) { $0 + $1.pips }
            return (p.id, nameFor(p.id), total)
        }
        let standings = totals.sorted { $0.2 < $1.2 }

        lines.append(snap.isFinished ? "FINAL STANDINGS" : "STANDINGS (game in progress)")
        var lastTotal: Int? = nil
        var lastPlace = 0
        for (i, (_, name, total)) in standings.enumerated() {
            let place: Int
            if let lt = lastTotal, lt == total {
                place = lastPlace
            } else {
                place = i + 1
                lastPlace = place
                lastTotal = total
            }
            let dots = String(repeating: ".", count: max(1, 20 - name.count))
            lines.append("  \(place). \(name) \(dots) \(total)")
        }

        let lastStop = (1...snap.length).reversed().first { stop in
            snap.scores.contains(where: { $0.stop == stop })
        }
        if let lastStop {
            lines.append("")
            for stop in 1...lastStop {
                let engine = Scoring.engineTile(stop: stop, rules: snap.startingEngine, length: snap.length)
                lines.append("STOP \(stop) (engine \(engine))")
                for p in players {
                    let name = nameFor(p.id)
                    if let s = snap.scores.first(where: { $0.playerID == p.id && $0.stop == stop }) {
                        let value = s.excluded ? 0 : s.pips
                        let submitter = s.submittedBy == .player ? name : "conductor"
                        var line = "  \(pad(name)) \(String(format: "%3d", value))  submitted by \(submitter)"
                        if s.excluded { line += " (excluded — counted as 0)" }
                        lines.append(line)
                    } else {
                        lines.append("  \(pad(name)) — — — not entered")
                    }
                }
            }
        }
        lines.append("")
        lines.append("— Joiner-side summary. The host has the full audit log.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting helpers

    private static func dateLine(game: Game, fallback: Date) -> String {
        let date = game.finishedAt ?? fallback
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func dateLine(snapshot: GameSnapshot, fallback: Date) -> String {
        let date = snapshot.endedAt ?? fallback
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func pad(_ name: String, width: Int = 12) -> String {
        if name.count >= width { return String(name.prefix(width)) }
        return name + String(repeating: " ", count: width - name.count)
    }

    private static func scoreLine(player: Player, score: Score) -> String {
        var parts: [String] = []
        let value = score.excluded ? 0 : score.pips
        parts.append("\(pad(player.name)) \(String(format: "%3d", value))")

        let edits = score.edits.sorted(by: { $0.editedAt < $1.editedAt })
        let submitter = score.originalSubmittedBy == .player ? player.name : "conductor"
        var trail = "submitted \(score.originalPips) by \(submitter)"

        for e in edits {
            let editor = e.editedBy == .player ? player.name : "conductor"
            if e.fromExcluded != e.toExcluded {
                trail += " → \(e.toExcluded ? "excluded" : "re-included") by \(editor)"
            } else {
                trail += " → audited to \(e.toPips) by \(editor)"
            }
        }
        if score.excluded {
            trail += " (excluded — counted as 0)"
        }
        parts.append(trail)
        return parts.joined(separator: "  ")
    }
}
