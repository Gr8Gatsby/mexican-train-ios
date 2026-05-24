import Foundation
import MultipeerConnectivity
import Network
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
        let peerID: MCPeerID?
        let roomCode: String
        let gameName: String
        let playerCount: Int
        let hostName: String
        let nsdEndpoint: NWEndpoint?
        var isTCP: Bool { nsdEndpoint != nil }
        var id: String { (peerID?.displayName ?? "tcp") + roomCode }

        static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
            lhs.id == rhs.id
        }
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
    private let tcpBridge = TCPBridge()
    private var hostPeerID: MCPeerID?

    // NSD/TCP joiner support
    private var nsdBrowserDelegate: NSDServiceBrowserDelegate?
    private var tcpJoinerConnection: NWConnection?
    private var tcpJoinerInputStream: InputStream?
    private var tcpJoinerOutputStream: OutputStream?
    private var tcpJoinerBuffer = Data()

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

        // Start TCP bridge for Android clients.
        _ = try? tcpBridge.start(roomCode: initialSnapshot.roomCode)
        tcpBridge.onClaimReceived = { [weak self] claim in
            Task { @MainActor in
                guard let self, self.role == .host else { return }
                self.playerClaims[claim.playerID] = claim
                self.onClaimReceived?(claim)
                if let s = self.latestSnapshot { self.broadcast(snapshot: s) }
            }
        }
        tcpBridge.onScoreSubmissionReceived = { [weak self] submission in
            Task { @MainActor in
                guard let self, self.role == .host else { return }
                self.onScoreSubmissionReceived?(submission)
            }
        }

        broadcast(snapshot: initialSnapshot)
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        tcpBridge.stop()
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

        // Send to MPC peers.
        if !session.connectedPeers.isEmpty {
            do {
                let data = try JSONEncoder().encode(MultipeerMessage.snapshot(copy))
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                // Log-only — broadcast errors aren't user-visible in v1.
            }
        }

        // Send to TCP (Android) clients.
        tcpBridge.broadcast(copy)
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

        startNSDBrowsing()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        nsdBrowserDelegate?.stop()
        nsdBrowserDelegate = nil
    }

    func connect(to host: DiscoveredHost, timeout: TimeInterval = 15) {
        guard role == .joiner else { return }
        joinState = .connecting

        // Re-fetch in case NSD resolved a TCP endpoint after the UI rendered.
        let resolved = availableHosts.first(where: { $0.roomCode == host.roomCode }) ?? host

        if resolved.isTCP, let endpoint = resolved.nsdEndpoint {
            hostPeerID = nil
            connectViaTCP(endpoint: endpoint)
        } else if let peerID = resolved.peerID, let session, let browser {
            hostPeerID = peerID
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: timeout)
        } else {
            joinState = .disconnected
        }
    }

    func sendClaim(_ claim: PlayerClaim) {
        guard role == .joiner else { return }
        myPlayerID = claim.playerID

        if tcpJoinerOutputStream != nil {
            sendTCPMessage(MultipeerMessage.claim(claim))
        } else if let session {
            do {
                let data = try JSONEncoder().encode(MultipeerMessage.claim(claim))
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                // Log only.
            }
        }
    }

    /// Joiner → host. Send a pip count for the joiner's own slot. The host
    /// records the submission and rebroadcasts the resulting snapshot.
    func sendScoreSubmission(_ submission: ScoreSubmission) {
        guard role == .joiner else { return }

        if tcpJoinerOutputStream != nil {
            sendTCPMessage(MultipeerMessage.scoreSubmission(submission))
        } else if let session {
            do {
                let data = try JSONEncoder().encode(MultipeerMessage.scoreSubmission(submission))
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                // Log only.
            }
        }
    }

    /// Connect directly to a host via IP address and port (bypasses discovery).
    func connectDirect(host: String, port: UInt16) {
        guard role == .joiner else { return }
        joinState = .connecting
        hostPeerID = nil
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        connectViaTCP(endpoint: endpoint)
    }

    func leave() {
        session?.disconnect()
        stopBrowsing()
        closeTCPJoiner()
        role = .idle
        joinState = .disconnected
        latestSnapshot = nil
        connectedPeerCount = 0
        myPlayerID = nil
        hostPeerID = nil
    }

    private func closeTCPJoiner() {
        tcpJoinerConnection?.cancel()
        tcpJoinerConnection = nil
        tcpJoinerInputStream?.close()
        tcpJoinerInputStream = nil
        tcpJoinerOutputStream?.close()
        tcpJoinerOutputStream = nil
        tcpJoinerBuffer = Data()
    }

    // MARK: - NSD/TCP Joiner (Android host support)

    private func startNSDBrowsing() {
        let delegate = NSDServiceBrowserDelegate { [weak self] host in
            Task { @MainActor in
                guard let self, self.role == .joiner else { return }
                if let idx = self.availableHosts.firstIndex(where: { $0.roomCode == host.roomCode }) {
                    // MPC may have found this host first without TCP endpoint — upgrade it
                    self.availableHosts[idx] = host
                } else {
                    self.availableHosts.append(host)
                }
            }
        } onLost: { [weak self] roomCode in
            Task { @MainActor in
                self?.availableHosts.removeAll { $0.isTCP && $0.roomCode == roomCode }
            }
        }
        delegate.start()
        self.nsdBrowserDelegate = delegate
    }

    private func connectViaTCP(endpoint: NWEndpoint) {
        guard case .hostPort(let host, let port) = endpoint else {
            print("TCP joiner: endpoint is not hostPort: \(endpoint)")
            joinState = .disconnected
            return
        }

        let hostStr = "\(host)"
        let portInt = Int(port.rawValue)
        print("TCP joiner: connecting to \(hostStr):\(portInt)")

        closeTCPJoiner()
        tcpJoinerBuffer = Data()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocketToHost(nil, hostStr as CFString, UInt32(portInt), &readStream, &writeStream)

            guard let inputCF = readStream?.takeRetainedValue(),
                  let outputCF = writeStream?.takeRetainedValue() else {
                Task { @MainActor in self?.joinState = .disconnected }
                return
            }

            let input = inputCF as InputStream
            let output = outputCF as OutputStream

            input.open()
            output.open()

            // Wait for the connection to establish
            for _ in 0..<100 {
                let s = input.streamStatus
                if s == .open || s == .reading { break }
                if s == .error || s == .closed { break }
                Thread.sleep(forTimeInterval: 0.05)
            }

            guard input.streamStatus == .open || input.streamStatus == .reading else {
                print("TCP joiner: stream failed to open - status \(input.streamStatus.rawValue)")
                input.close()
                output.close()
                Task { @MainActor in self?.joinState = .disconnected }
                return
            }

            print("TCP joiner: connected!")
            Task { @MainActor in
                self?.tcpJoinerInputStream = input
                self?.tcpJoinerOutputStream = output
                self?.joinState = .connected
            }

            // Read loop on background thread
            let bufSize = 65536
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }

            while true {
                let status = input.streamStatus
                if status == .closed || status == .error || status == .atEnd {
                    print("TCP joiner: read loop exiting, stream status = \(status.rawValue), error = \(String(describing: input.streamError))")
                    break
                }

                if input.hasBytesAvailable {
                    let bytesRead = input.read(buf, maxLength: bufSize)
                    if bytesRead > 0 {
                        let chunk = Data(bytes: buf, count: bytesRead)
                        Task { @MainActor in
                            self?.handleTCPJoinerData(chunk)
                        }
                    } else if bytesRead < 0 {
                        print("TCP joiner: read returned \(bytesRead), error = \(String(describing: input.streamError))")
                        break
                    }
                } else {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }

            print("TCP joiner: read loop ended")
            Task { @MainActor in
                if self?.joinState == .connected {
                    self?.joinState = .hostEnded
                }
            }
        }
    }

    private func handleTCPJoinerData(_ data: Data) {
        tcpJoinerBuffer.append(data)

        while let newlineIndex = tcpJoinerBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = tcpJoinerBuffer[tcpJoinerBuffer.startIndex..<newlineIndex]
            tcpJoinerBuffer = Data(tcpJoinerBuffer[tcpJoinerBuffer.index(after: newlineIndex)...])
            guard !lineData.isEmpty else { continue }

            do {
                let message = try JSONDecoder().decode(MultipeerMessage.self, from: Data(lineData))
                if case .snapshot(let snap) = message {
                    if let cur = latestSnapshot, snap.seq < cur.seq { continue }
                    latestSnapshot = snap
                }
            } catch {
                print("TCP joiner: failed to decode: \(error)")
            }
        }
    }

    private func sendTCPMessage(_ message: MultipeerMessage) {
        guard let output = tcpJoinerOutputStream,
              let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let line = jsonString + "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        lineData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            output.write(base, maxLength: lineData.count)
        }
    }
}

extension MexTrainNetSession: @preconcurrency MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeerCount = session.connectedPeers.count + self.tcpBridge.connectedClientCount
            switch state {
            case .connected:
                if role == .joiner { joinState = .connected }
            case .notConnected:
                if role == .joiner, peerID == hostPeerID {
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
            hostName: info?["host"] ?? peerID.displayName,
            nsdEndpoint: nil
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
