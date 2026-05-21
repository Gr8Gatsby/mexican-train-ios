import Foundation

struct Standing: Equatable {
    let playerID: UUID
    let name: String
    let total: Int
    let place: Int          // 1-indexed; ties share a place
    let isYou: Bool
}

enum Scoring {

    /// Sum of pips for a single player across every recorded stop.
    static func total(for playerID: UUID, in game: Game) -> Int {
        game.scores
            .filter { $0.playerID == playerID }
            .reduce(0) { $0 + $1.pips }
    }

    /// Sorted ascending by total. Ties share a place (1, 1, 3, …).
    static func standings(for game: Game) -> [Standing] {
        let players = game.sortedPlayers
        let totals = players.map { ($0, total(for: $0.id, in: game)) }
            .sorted { $0.1 < $1.1 }

        var result: [Standing] = []
        var lastTotal: Int? = nil
        var lastPlace = 0
        for (index, pair) in totals.enumerated() {
            let (player, total) = pair
            let place: Int
            if let lt = lastTotal, lt == total {
                place = lastPlace
            } else {
                place = index + 1
                lastPlace = place
                lastTotal = total
            }
            result.append(Standing(
                playerID: player.id,
                name: player.name,
                total: total,
                place: place,
                isYou: player.isYou
            ))
        }
        return result
    }

    /// Whether every player has a score recorded for the given stop.
    static func isStopComplete(_ stop: Int, in game: Game) -> Bool {
        guard !game.players.isEmpty else { return false }
        return game.players.allSatisfy { p in
            game.scores.contains { $0.playerID == p.id && $0.stopIndex == stop }
        }
    }

    /// First player (in seat order) who has not yet entered the current stop.
    static func nextUnenteredPlayer(stop: Int, in game: Game) -> Player? {
        for p in game.sortedPlayers {
            if !game.scores.contains(where: { $0.playerID == p.id && $0.stopIndex == stop }) {
                return p
            }
        }
        return nil
    }

    /// The engine double for a given stop number, given the game's house rule.
    /// Returns 0 when the stop is past the end of the engine sequence.
    static func engineTile(stop: Int, rules: StartingEngine, length: Int) -> Int {
        let start: Int
        switch rules {
        case .traditional:
            start = length - 1          // 13→12, 10→9, 7→6
        case .alwaysTwelve:
            start = 12
        }
        let candidate = start - (stop - 1)
        return max(0, candidate)
    }

    /// Find a player's score (if any) for a given stop.
    static func score(for playerID: UUID, stop: Int, in game: Game) -> Score? {
        game.scores.first { $0.playerID == playerID && $0.stopIndex == stop }
    }

    /// Per-player score grid: `[playerID: [stop1, stop2, …]]`, with nil for unset.
    static func grid(for game: Game) -> [UUID: [Int?]] {
        var result: [UUID: [Int?]] = [:]
        for p in game.sortedPlayers {
            var row: [Int?] = Array(repeating: nil, count: game.lengthStops)
            for s in game.scores where s.playerID == p.id {
                let idx = s.stopIndex - 1
                if (0..<row.count).contains(idx) {
                    row[idx] = s.pips
                }
            }
            result[p.id] = row
        }
        return result
    }
}
