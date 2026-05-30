import Foundation
import Network

/// Standalone TCP server that runs alongside MultipeerConnectivity,
/// enabling Android devices to connect to an iOS host over the local network.
///
/// Messages use newline-delimited JSON — the same `MultipeerMessage` envelope
/// that MPC uses. The host broadcasts `GameSnapshot` envelopes to all TCP
/// clients; clients send back `PlayerClaim` or `ScoreSubmission` messages.
@MainActor
final class TCPBridge: @unchecked Sendable {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var lastBroadcastData: Data?

    var onClaimReceived: ((PlayerClaim) -> Void)?
    var onScoreSubmissionReceived: ((ScoreSubmission) -> Void)?
    /// Called when a new TCP client connects and is ready. The host uses this
    /// to push all existing photos to the new joiner.
    var onNewClientConnected: ((NWConnection) -> Void)?

    var connectedClientCount: Int { connections.count }

    /// Start listening for TCP connections and advertise via Bonjour.
    /// Returns the port number the listener bound to (0 if not yet ready).
    @discardableResult
    func start(roomCode: String, hostName: String = "", playerCount: Int = 0) throws -> UInt16 {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let listener = try NWListener(using: params)

        let txtDict = ["host": hostName, "players": String(playerCount)]
        let txtData = NetService.data(fromTXTRecord: txtDict.mapValues { Data($0.utf8) })

        listener.service = NWListener.Service(
            name: "MexTrain-\(roomCode)",
            type: "_mextrain-game._tcp",
            txtRecord: txtData
        )

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                print("TCPBridge listener failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .main)
        self.listener = listener

        return listener.port?.rawValue ?? 0
    }

    /// Send a snapshot to every connected TCP client.
    func broadcast(_ snapshot: GameSnapshot) {
        let message = MultipeerMessage.snapshot(snapshot)
        guard let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let line = jsonString + "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        lastBroadcastData = lineData

        var dead: [Int] = []
        for (index, conn) in connections.enumerated() {
            if conn.state == .ready {
                conn.send(content: lineData, completion: .contentProcessed { error in
                    if let error {
                        print("TCPBridge send error: \(error)")
                    }
                })
            } else {
                dead.append(index)
            }
        }

        // Remove dead connections (iterate in reverse to keep indices valid).
        for index in dead.reversed() {
            removeConnection(at: index)
        }
    }

    /// Send raw data to all connected TCP clients (used for heartbeats).
    func sendRawToAll(_ data: Data) {
        for conn in connections where conn.state == .ready {
            conn.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    /// Send an encoded `MultipeerMessage` to every connected TCP client.
    func sendMessageToAll(_ message: MultipeerMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let line = jsonString + "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        sendRawToAll(lineData)
    }

    /// Send an encoded `MultipeerMessage` to a specific TCP client.
    func sendMessage(_ message: MultipeerMessage, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let line = jsonString + "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        guard connection.state == .ready else { return }
        connection.send(content: lineData, completion: .contentProcessed { error in
            if let error { print("TCPBridge send error: \(error)") }
        })
    }

    /// Tear down the listener and all connections.
    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        buffers.removeAll()
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    // Send the latest snapshot to the new client.
                    if let data = self?.lastBroadcastData {
                        connection.send(content: data, completion: .contentProcessed { _ in })
                    }
                    // Notify the host to push all existing photos.
                    self?.onNewClientConnected?(connection)
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receiveLoop(connection)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    self?.handleData(data, from: connection)
                }
                if isComplete || error != nil {
                    self?.removeConnection(connection)
                    connection.cancel()
                    return
                }
                // Continue receiving.
                self?.receiveLoop(connection)
            }
        }
    }

    private func handleData(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        var buffer = buffers[id] ?? Data()
        buffer.append(data)

        // Process complete lines (newline-delimited JSON).
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            do {
                let message = try JSONDecoder().decode(MultipeerMessage.self, from: Data(lineData))
                switch message {
                case .claim(let claim):
                    onClaimReceived?(claim)
                case .scoreSubmission(let submission):
                    onScoreSubmissionReceived?(submission)
                case .snapshot:
                    break // Host doesn't process inbound snapshots.
                case .heartbeat:
                    break // Host doesn't process inbound heartbeats.
                case .photoPush:
                    break // Host doesn't process inbound photo pushes.
                case .avatarPush:
                    break // Host doesn't process inbound avatar pushes.
                }
            } catch {
                print("TCPBridge: Failed to decode message: \(error)")
            }
        }

        buffers[id] = buffer
    }

    private func removeConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        buffers.removeValue(forKey: id)
        connections.removeAll { $0 === connection }
    }

    private func removeConnection(at index: Int) {
        let conn = connections[index]
        buffers.removeValue(forKey: ObjectIdentifier(conn))
        connections.remove(at: index)
    }
}
