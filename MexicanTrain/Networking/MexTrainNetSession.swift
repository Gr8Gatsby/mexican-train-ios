import Foundation
import MultipeerConnectivity
import UIKit

/// Bonjour service type — ≤15 chars, lowercase + hyphens + digits.
private let kServiceType = "mextrain-game"

/// Multipeer wrapper modeled on `~/code/farkle/Farkle/Networking/FarkleNetSession.swift`.
/// Host advertises; joiners browse. The host pushes `GameSnapshot` envelopes on
/// every meaningful change; joiners send back `PlayerClaim` messages.
@MainActor
@Observable
final class MexTrainNetSession: NSObject {
    enum Role { case idle, host, joiner }
    enum JoinState { case browsing, connecting, connected, disconnected, hostEnded }

    struct DiscoveredHost: Identifiable, Equatable {
        let peerID: MCPeerID
        let roomCode: String
        let gameName: String
        let playerCount: Int
        let hostName: String
        var id: String { peerID.displayName + roomCode }
    }

    private(set) var role: Role = .idle
    private(set) var roomCode: String = ""
    private(set) var connectedPeerCount: Int = 0
    private(set) var availableHosts: [DiscoveredHost] = []
    private(set) var latestSnapshot: GameSnapshot?
    private(set) var joinState: JoinState = .disconnected

    /// Host-side accumulator of claims by player ID.
    private(set) var playerClaims: [UUID: PlayerClaim] = [:]

    /// Joiner-side: the `playerID` we sent in our claim. Lets the spectator
    /// view identify which row in the snapshot is "me" so it can decide
    /// whether to show the Add-my-score CTA. Nil for spectators and when no
    /// claim has been sent yet.
    private(set) var myPlayerID: UUID?

    /// Optional callback invoked on the main actor when the host receives a
    /// claim. NewGameView uses this to add the joiner as a new Player slot
    /// in the lobby.
    var onClaimReceived: ((PlayerClaim) -> Void)?

    /// Host-side callback for incoming `.scoreSubmission` messages. The
    /// scoreboard wires this on appear to dispatch to `GamePersistence`.
    var onScoreSubmissionReceived: ((ScoreSubmission) -> Void)?

    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var lastSentSeq: Int = 0

    override init() {
        let trimmed = String(UIDevice.current.name.prefix(63))
        self.myPeerID = MCPeerID(displayName: trimmed.isEmpty ? "Mex-Train player" : trimmed)
        super.init()
    }

    // MARK: - Host

    func startHosting(initialSnapshot: GameSnapshot) {
        role = .host
        roomCode = initialSnapshot.roomCode
        lastSentSeq = 0
        latestSnapshot = initialSnapshot

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let info: [String: String] = [
            "code": initialSnapshot.roomCode,
            "game": initialSnapshot.gameName,
            "players": String(initialSnapshot.players.count),
            "host": initialSnapshot.hostName
        ]
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: kServiceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        broadcast(snapshot: initialSnapshot)
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        role = .idle
        roomCode = ""
        playerClaims.removeAll()
        latestSnapshot = nil
        connectedPeerCount = 0
    }

    func broadcast(snapshot: GameSnapshot) {
        guard role == .host, let session else { return }
        lastSentSeq += 1
        var copy = snapshot
        copy.seq = lastSentSeq
        copy.claims = Array(playerClaims.values)
        latestSnapshot = copy
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(MultipeerMessage.snapshot(copy))
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // Log-only — broadcast errors aren't user-visible in v1.
        }
    }

    func revokeClaim(playerID: UUID) {
        playerClaims[playerID] = nil
        if let s = latestSnapshot { broadcast(snapshot: s) }
    }

    // MARK: - Joiner

    func startBrowsing() {
        role = .joiner
        joinState = .browsing
        availableHosts = []
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: kServiceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func connect(to host: DiscoveredHost, timeout: TimeInterval = 15) {
        guard role == .joiner, let session, let browser else { return }
        joinState = .connecting
        browser.invitePeer(host.peerID, to: session, withContext: nil, timeout: timeout)
    }

    func sendClaim(_ claim: PlayerClaim) {
        guard role == .joiner, let session else { return }
        myPlayerID = claim.playerID
        do {
            let data = try JSONEncoder().encode(MultipeerMessage.claim(claim))
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // Log only.
        }
    }

    /// Joiner → host. Send a pip count for the joiner's own slot. The host
    /// records the submission and rebroadcasts the resulting snapshot.
    func sendScoreSubmission(_ submission: ScoreSubmission) {
        guard role == .joiner, let session else { return }
        do {
            let data = try JSONEncoder().encode(MultipeerMessage.scoreSubmission(submission))
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // Log only.
        }
    }

    func leave() {
        session?.disconnect()
        stopBrowsing()
        role = .idle
        joinState = .disconnected
        latestSnapshot = nil
        connectedPeerCount = 0
        myPlayerID = nil
    }
}

extension MexTrainNetSession: @preconcurrency MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeerCount = session.connectedPeers.count
            switch state {
            case .connected:
                if role == .joiner { joinState = .connected }
            case .notConnected:
                if role == .joiner {
                    if joinState == .connected { joinState = .hostEnded }
                    else { joinState = .disconnected }
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(MultipeerMessage.self, from: data) else { return }
        Task { @MainActor in
            switch message {
            case .snapshot(let snap):
                if role == .joiner {
                    if let cur = latestSnapshot, snap.seq < cur.seq { return }
                    latestSnapshot = snap
                }
            case .claim(let claim):
                if role == .host {
                    playerClaims[claim.playerID] = claim
                    onClaimReceived?(claim)
                    if let s = latestSnapshot { broadcast(snapshot: s) }
                }
            case .scoreSubmission(let submission):
                if role == .host {
                    onScoreSubmissionReceived?(submission)
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MexTrainNetSession: @preconcurrency MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension MexTrainNetSession: @preconcurrency MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let host = DiscoveredHost(
            peerID: peerID,
            roomCode: info?["code"] ?? "",
            gameName: info?["game"] ?? "Mexican Train",
            playerCount: Int(info?["players"] ?? "0") ?? 0,
            hostName: info?["host"] ?? peerID.displayName
        )
        Task { @MainActor in
            if !availableHosts.contains(where: { $0.id == host.id }) {
                availableHosts.append(host)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            availableHosts.removeAll { $0.peerID == peerID }
        }
    }
}
