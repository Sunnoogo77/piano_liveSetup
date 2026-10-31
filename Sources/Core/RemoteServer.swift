import Foundation
import Network

// Petit serveur HTTP local : publie une page de commande que l'on ouvre depuis
// une tablette ou un téléphone sur le même réseau. Le Mac continue de faire le
// son ; l'appareil distant ne fait qu'afficher et commander.
//
// Volontairement simple : pas de WebSocket, la page interroge l'état plusieurs
// fois par seconde. Sur un réseau local c'est largement suffisant pour une
// surface de commande, et il n'y a presque rien qui puisse casser.

final class RemoteServer: @unchecked Sendable {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "piano.remote", qos: .utility)

    private(set) var isRunning = false
    private(set) var port: UInt16 = 8787
    private(set) var token = ""
    private(set) var lastError: String?
    private(set) var clientCount = 0
    private var lastSeen: [String: Date] = [:]

    /// Dernier instantané publié par l'application, servi tel quel.
    private var stateJSON = Data("{}".utf8)
    private var libraryJSON = Data("[]".utf8)
    private let lock = NSLock()

    /// Appelé sur la file principale quand la page envoie une commande.
    var onCommand: ((String, [String: Any]) -> Void)?

    // MARK: Publication de l'état

    func publish(state: Data) { lock.lock(); stateJSON = state; lock.unlock() }
    func publish(library: Data) { lock.lock(); libraryJSON = library; lock.unlock() }

    // MARK: Marche / arrêt

    /// `key` permet de réutiliser la clé précédente : l'appareil déjà appairé
    /// reste connecté d'un lancement à l'autre.
    func start(port requested: UInt16 = 8787, key: String = "") -> Bool {
        stop()
        token = key.count >= 4 ? key.uppercased() : Self.makeToken()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: requested),
              let l = try? NWListener(using: params, on: nwPort) else {
            lastError = "le port \(requested) est déjà pris"
            return false
        }
        port = requested
        // Bonjour : permet d'atteindre le Mac par son nom plutôt que par son adresse.
        l.service = NWListener.Service(name: "Piano Live Setup", type: "_http._tcp")
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let e):
                self?.lastError = "\(e)"
                self?.isRunning = false
            case .ready:
                self?.lastError = nil
            default: break
            }
        }
        listener = l
        l.start(queue: queue)
        isRunning = true
        return true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        clientCount = 0
        lastSeen.removeAll()
    }

    private static func makeToken() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")   // sans I, L, O, 0, 1
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    // MARK: Adresses à ouvrir

    /// Adresse IPv4 de la machine sur le réseau local.
    static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var best: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let name = String(cString: cur.pointee.ifa_name)
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    // en0 est le Wi-Fi sur la plupart des Mac : on le préfère.
                    if name == "en0" { best = ip } else if best == nil { best = ip }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return best
    }

    var addresses: [String] {
        guard isRunning else { return [] }
        var out: [String] = []
        if let ip = Self.localIPv4() { out.append("http://\(ip):\(port)/?k=\(token)") }
        let host = ProcessInfo.processInfo.hostName
        if !host.isEmpty, host != "localhost" {
            out.append("http://\(host):\(port)/?k=\(token)")
        }
        return out
    }

    // MARK: Service HTTP

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let sep = buf.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buf[..<sep.lowerBound], as: UTF8.self)
                let needed = Self.contentLength(header)
                let body = buf[sep.upperBound...]
                if body.count >= needed {
                    self.respond(conn, header: header, body: Data(body.prefix(needed)))
                    return
                }
            }
            if error != nil || complete { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private static func contentLength(_ header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func respond(_ conn: NWConnection, header: String, body: Data) {
        guard let requestLine = header.split(separator: "\r\n").first else { conn.cancel(); return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = String(parts[0])
        let target = String(parts[1])
        let path = target.split(separator: "?").first.map(String.init) ?? "/"
        let query = target.contains("?") ? String(target.split(separator: "?", maxSplits: 1)[1]) : ""

        func queryValue(_ key: String) -> String? {
            for pair in query.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == key { return String(kv[1]) }
            }
            return nil
        }

        // La page elle-même est servie sans clé : c'est la page qui la réclame
        // ensuite pour tout le reste. Un curieux sur le réseau voit un écran
        // de saisie, pas votre installation.
        if path == "/" || path == "/index.html" {
            send(conn, status: "200 OK", type: "text/html; charset=utf-8",
                 body: Data(WebAssets.remotePage.utf8))
            return
        }

        let provided = queryValue("k") ?? Self.headerValue(header, "x-piano-key")
        guard provided == token else {
            send(conn, status: "403 Forbidden", type: "application/json",
                 body: Data(#"{"error":"clé invalide"}"#.utf8))
            return
        }

        if let ip = conn.currentPath?.remoteEndpoint.map({ "\($0)" }) {
            lock.lock(); lastSeen[ip] = Date()
            clientCount = lastSeen.values.filter { Date().timeIntervalSince($0) < 10 }.count
            lock.unlock()
        }

        switch (method, path) {
        case ("GET", "/api/state"):
            lock.lock(); let d = stateJSON; lock.unlock()
            send(conn, status: "200 OK", type: "application/json", body: d)
        case ("GET", "/api/library"):
            lock.lock(); let d = libraryJSON; lock.unlock()
            send(conn, status: "200 OK", type: "application/json", body: d)
        case ("POST", "/api/cmd"):
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let action = obj["action"] as? String {
                DispatchQueue.main.async { [weak self] in self?.onCommand?(action, obj) }
                send(conn, status: "200 OK", type: "application/json", body: Data(#"{"ok":true}"#.utf8))
            } else {
                send(conn, status: "400 Bad Request", type: "application/json",
                     body: Data(#"{"error":"commande illisible"}"#.utf8))
            }
        default:
            send(conn, status: "404 Not Found", type: "text/plain", body: Data("introuvable".utf8))
        }
    }

    private static func headerValue(_ header: String, _ key: String) -> String? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func send(_ conn: NWConnection, status: String, type: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
