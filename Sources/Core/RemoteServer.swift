import Foundation
import Network

// Petit serveur HTTP local : publie une page de commande que l'on ouvre depuis
// une tablette ou un téléphone sur le même réseau. Le Mac continue de faire le
// son ; l'appareil distant affiche et commande.
//
// Deux chemins de données, volontairement séparés :
//
//   • /api/stream — un flux Server-Sent Events ouvert en permanence. Tout ce
//     qui bouge vite (niveaux, spectre, notes tenues, accord) y passe à la
//     cadence de l'application, sans que la tablette ait à redemander. Une
//     seule connexion TCP pour toute la séance.
//
//   • /api/state et /api/library — ce qui change rarement (la liste des sons,
//     l'égaliseur, les prises enregistrées). La page les relit quand le flux
//     annonce un nouveau numéro de révision.
//
// La page se rabat sur l'interrogation périodique de /api/state si le flux ne
// s'établit pas : rien n'est perdu, c'est seulement moins fluide.

final class RemoteServer: @unchecked Sendable {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "piano.remote", qos: .utility)

    private(set) var isRunning = false
    private(set) var port: UInt16 = 8787
    private(set) var token = ""
    private(set) var lastError: String?
    private(set) var clientCount = 0
    private var lastSeen: [String: Date] = [:]

    /// Derniers instantanés publiés par l'application, servis tels quels.
    private var stateJSON = Data("{}".utf8)
    private var libraryJSON = Data("[]".utf8)
    private var liveJSON = Data("{}".utf8)
    private let lock = NSLock()

    /// Une connexion SSE ouverte. `busy` évite d'empiler les trames si
    /// l'appareil distant n'arrive pas à suivre : on en saute une plutôt que
    /// de gonfler la file d'envoi.
    private final class Stream {
        let conn: NWConnection
        var busy = false
        init(_ conn: NWConnection) { self.conn = conn }
    }
    private var streams: [UUID: Stream] = [:]

    /// Appelé sur la file principale quand la page envoie une commande.
    var onCommand: ((String, [String: Any]) -> Void)?

    // MARK: Publication de l'état

    func publish(state: Data) { lock.lock(); stateJSON = state; lock.unlock() }
    func publish(library: Data) { lock.lock(); libraryJSON = library; lock.unlock() }

    /// Publie l'instantané rapide et le pousse tout de suite aux flux ouverts.
    func publish(live: Data) {
        lock.lock()
        liveJSON = live
        let targets = streams
        lock.unlock()
        guard !targets.isEmpty else { return }
        var frame = Data("data: ".utf8)
        frame.append(live)
        frame.append(Data("\n\n".utf8))
        for (id, s) in targets {
            if s.busy { continue }
            s.busy = true
            s.conn.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil { self.drop(id) } else {
                    self.lock.lock(); self.streams[id]?.busy = false; self.lock.unlock()
                }
            })
        }
    }

    var streamCount: Int { lock.lock(); defer { lock.unlock() }; return streams.count }

    private func drop(_ id: UUID) {
        lock.lock()
        let s = streams.removeValue(forKey: id)
        lock.unlock()
        s?.conn.cancel()
    }

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
        lock.lock()
        let open = streams.values.map { $0.conn }
        streams.removeAll()
        lastSeen.removeAll()
        lock.unlock()
        open.forEach { $0.cancel() }
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

        let provided = queryValue("k") ?? Self.headerValue(header, "x-piano-key")

        // Ce qui est servi sans clé : la page, son manifeste et ses icônes.
        // La page réclame ensuite la clé pour tout le reste. Un curieux sur le
        // réseau voit un écran de saisie, pas votre installation.
        switch path {
        case "/", "/index.html":
            send(conn, status: "200 OK", type: "text/html; charset=utf-8",
                 body: Data(WebAssets.remotePage.utf8))
            return
        case "/manifest.webmanifest":
            // start_url emporte la clé si la page nous l'a passée : l'icône
            // posée sur l'écran d'accueil s'ouvre alors déjà connectée.
            let start = (provided == token && !token.isEmpty) ? "/?k=\(token)" : "/"
            send(conn, status: "200 OK", type: "application/manifest+json",
                 body: Data(Self.manifest(startURL: start).utf8))
            return
        case "/icon-180.png", "/icon-192.png", "/icon-512.png", "/favicon.png":
            let name = path == "/favicon.png" ? "/icon-192.png" : path
            if let png = WebAssets.icon(name) {
                send(conn, status: "200 OK", type: "image/png", body: png,
                     extra: ["Cache-Control": "public, max-age=86400"])
            } else {
                send(conn, status: "404 Not Found", type: "text/plain", body: Data())
            }
            return
        default: break
        }

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
        case ("GET", "/api/stream"):
            openStream(conn)
        case ("GET", "/api/state"):
            lock.lock(); let d = stateJSON; lock.unlock()
            send(conn, status: "200 OK", type: "application/json", body: d)
        case ("GET", "/api/live"):
            lock.lock(); let d = liveJSON; lock.unlock()
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

    // MARK: Flux temps réel

    private func openStream(_ conn: NWConnection) {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: text/event-stream; charset=utf-8\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: keep-alive\r\n"
        head += "X-Accel-Buffering: no\r\n\r\n"
        // « retry » : si le Wi-Fi hoquette, le navigateur se reconnecte seul.
        head += "retry: 1200\n\n"

        let id = UUID()
        lock.lock(); let snapshot = liveJSON; lock.unlock()
        var first = Data(head.utf8)
        first.append(Data("data: ".utf8))
        first.append(snapshot)
        first.append(Data("\n\n".utf8))

        let stream = Stream(conn)
        lock.lock(); streams[id] = stream; lock.unlock()

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(id)
            default: break
            }
        }
        conn.send(content: first, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil { self.drop(id) }
        })
        // Une tablette qui ferme l'onglet ne nous prévient pas : rien ne
        // revient sur la connexion, et un envoi n'échouera qu'à la trame
        // suivante. On garde donc une lecture ouverte, uniquement pour voir
        // arriver la fin de flux, et on libère tout de suite.
        drain(conn, id)
    }

    private func drain(_ conn: NWConnection, _ id: UUID) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, complete, error in
            guard let self else { conn.cancel(); return }
            if complete || error != nil { self.drop(id); return }
            self.drain(conn, id)
        }
    }

    // MARK: Manifeste d'application web

    /// Ce qui permet à l'iPad de poser une véritable icône sur l'écran
    /// d'accueil et d'ouvrir la page en plein écran, sans barre de navigateur.
    static func manifest(startURL: String) -> String {
        """
        {
          "name": "Piano Live Setup",
          "short_name": "Piano",
          "description": "Surface de commande du Mac qui fait le son.",
          "start_url": "\(startURL)",
          "scope": "/",
          "display": "standalone",
          "orientation": "any",
          "background_color": "#0A0C10",
          "theme_color": "#0A0C10",
          "icons": [
            { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
            { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" },
            { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png",
              "purpose": "maskable" }
          ]
        }
        """
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

    private func send(_ conn: NWConnection, status: String, type: String, body: Data,
                      extra: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        if extra["Cache-Control"] == nil { head += "Cache-Control: no-store\r\n" }
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
