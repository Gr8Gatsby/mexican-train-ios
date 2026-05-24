import Foundation
import Network

/// Browses for `_mextrain-game._tcp` services via Bonjour, resolves each to a
/// host:port using the actual IP address (not `.local.` hostname), and reports
/// them as `DiscoveredHost` instances with a ready-to-use `NWEndpoint.hostPort`.
final class NSDServiceBrowserDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onFound: (MexTrainNetSession.DiscoveredHost) -> Void
    private let onLost: (String) -> Void
    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []

    init(onFound: @escaping (MexTrainNetSession.DiscoveredHost) -> Void,
         onLost: @escaping (_ roomCode: String) -> Void) {
        self.onFound = onFound
        self.onLost = onLost
        super.init()
    }

    func start() {
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_mextrain-game._tcp.", inDomain: "local.")
        browser = b
    }

    func stop() {
        browser?.stop()
        browser = nil
        resolving.removeAll()
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name.hasPrefix("MexTrain-") else { return }
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 10)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolving.removeAll { $0 == service }
        if service.name.hasPrefix("MexTrain-") {
            let code = String(service.name.dropFirst("MexTrain-".count))
            onLost(code)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {}

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.name.hasPrefix("MexTrain-"),
              sender.port > 0 else { return }

        let code = String(sender.name.dropFirst("MexTrain-".count))

        // Prefer the explicit "ip" TXT record from the Android host (its WiFi address),
        // which avoids emulator-internal or loopback addresses that aren't routable.
        var resolvedHost: String
        if let txtIP = extractTXTAttribute("ip", from: sender),
           !txtIP.isEmpty, txtIP != "0.0.0.0", txtIP != "127.0.0.1",
           !txtIP.hasPrefix("10.0.2.") {
            resolvedHost = txtIP
        } else if let ip = extractIPv4Address(from: sender) {
            resolvedHost = ip
        } else if let hn = sender.hostName {
            resolvedHost = hn.hasSuffix(".") ? String(hn.dropLast()) : hn
        } else {
            print("NSD: no address for \(sender.name)")
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(resolvedHost),
            port: NWEndpoint.Port(rawValue: UInt16(sender.port))!
        )

        print("NSD resolved \(sender.name) → \(resolvedHost):\(sender.port)")

        let host = MexTrainNetSession.DiscoveredHost(
            peerID: nil,
            roomCode: code,
            gameName: "\(resolvedHost):\(sender.port)",
            playerCount: 0,
            hostName: sender.name,
            nsdEndpoint: endpoint
        )
        onFound(host)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("NSD resolve failed for \(sender.name): \(errorDict)")
        resolving.removeAll { $0 == sender }
    }

    // MARK: - TXT record

    private func extractTXTAttribute(_ key: String, from service: NetService) -> String? {
        guard let data = service.txtRecordData() else { return nil }
        let dict = NetService.dictionary(fromTXTRecord: data)
        guard let value = dict[key] else { return nil }
        return String(data: value, encoding: .utf8)
    }

    // MARK: - IP extraction

    private func extractIPv4Address(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        var fallback: String?
        for addrData in addresses {
            if addrData.count >= MemoryLayout<sockaddr_in>.size {
                let family = addrData.withUnsafeBytes { $0.load(fromByteOffset: 1, as: UInt8.self) }
                if family == UInt8(AF_INET) {
                    let addr = addrData.withUnsafeBytes { ptr -> String? in
                        let sockAddr = ptr.bindMemory(to: sockaddr_in.self).baseAddress!.pointee
                        var ip = sockAddr.sin_addr
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        guard let result = inet_ntop(AF_INET, &ip, &buf, socklen_t(INET_ADDRSTRLEN)) else {
                            return nil
                        }
                        return String(cString: result)
                    }
                    guard let addr, addr != "0.0.0.0" else { continue }
                    // Prefer routable addresses over loopback/link-local
                    if addr == "127.0.0.1" || addr.hasPrefix("169.254.") {
                        if fallback == nil { fallback = addr }
                        continue
                    }
                    return addr
                }
            }
        }
        return fallback
    }
}
