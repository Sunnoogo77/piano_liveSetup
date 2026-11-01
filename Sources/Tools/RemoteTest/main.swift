import Foundation

// Vérifie le serveur de contrôle à distance : la page est servie, la clé est
// exigée, l'état est lisible et une commande envoyée depuis la page arrive bien.

var fails = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  \(ok ? "OK   " : "ÉCHEC") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { fails += 1 }
}

struct Reply { var status: Int; var body: Data }

func request(_ url: String, method: String = "GET", json: [String: Any]? = nil) -> Reply? {
    guard let u = URL(string: url) else { return nil }
    var req = URLRequest(url: u)
    req.httpMethod = method
    req.timeoutInterval = 5
    if let json {
        req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    var out: Reply?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        if let http = resp as? HTTPURLResponse {
            out = Reply(status: http.statusCode, body: data ?? Data())
        }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 6)
    return out
}

let server = RemoteServer()
var received: [(String, [String: Any])] = []
server.onCommand = { action, args in received.append((action, args)) }

// Un port peu banal, pour ne pas tomber sur un service existant.
let port: UInt16 = 8921
check("le serveur démarre", server.start(port: port), server.lastError ?? "port \(port)")
guard server.isRunning else {
    print("\n\(fails) PROBLÈME(S) — serveur indisponible"); exit(1)
}
Thread.sleep(forTimeInterval: 0.4)

let key = server.token
let base = "http://127.0.0.1:\(port)"
print("  clé d'accès : \(key)")

// État et bibliothèque publiés par l'application
let state: [String: Any] = ["preset": "Concert Grand", "category": "Pianos acoustiques",
                            "presetIndex": 0, "transpose": -3, "octave": 0,
                            "master": 0.8, "chord": "Cmaj7", "hasKeyboard": true]
server.publish(state: try! JSONSerialization.data(withJSONObject: state))
server.publish(library: try! JSONSerialization.data(withJSONObject:
    [["name": "Concert Grand", "subtitle": "Yamaha C5", "category": "Pianos acoustiques"]]))

print("\n--- La page de commande ---")
if let r = request(base + "/") {
    let html = String(decoding: r.body, as: UTF8.self)
    check("servie sans clé", r.status == 200, "\(r.body.count) octets")
    check("c'est bien la page", html.contains("Piano Live Setup") && html.contains("Transposition"))
    check("prévue pour une tablette", html.contains("viewport") && html.contains("apple-mobile-web-app-capable"))
    check("la feuille de style est injectée", html.contains("--accent:#4FD1C5"))
    check("le script est injecté", html.contains("function paintEQ"))
    check("tous les écrans sont là",
          ["s-play", "s-eq", "s-chords", "s-keys", "s-rec", "s-info"].allSatisfy { html.contains($0) })
    check("l'analyseur est là", html.contains("eqcanvas"))
} else { check("la page répond", false) }

print("\n--- Installable sur l'écran d'accueil ---")
if let r = request(base + "/manifest.webmanifest"),
   let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] {
    check("le manifeste est servi sans clé", r.status == 200)
    check("plein écran", obj["display"] as? String == "standalone")
    check("sans clé, départ à la racine", obj["start_url"] as? String == "/")
    check("trois icônes déclarées", (obj["icons"] as? [[String: Any]])?.count == 3)
} else { check("manifeste lisible", false) }

if let r = request(base + "/manifest.webmanifest?k=" + key),
   let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] {
    check("avec la clé, le départ l'emporte", obj["start_url"] as? String == "/?k=" + key)
} else { check("manifeste avec clé", false) }

for name in ["/icon-180.png", "/icon-192.png", "/icon-512.png", "/favicon.png"] {
    if let r = request(base + name) {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        check("\(name) est une vraie image", r.status == 200
              && r.body.count > 400 && Array(r.body.prefix(4)) == png,
              "\(r.body.count) octets")
    } else { check("\(name) répond", false) }
}

print("\n--- La clé est exigée ---")
check("état refusé sans clé", request(base + "/api/state")?.status == 403)
check("état refusé avec une mauvaise clé", request(base + "/api/state?k=ZZZZZZ")?.status == 403)

print("\n--- L'état est lisible ---")
if let r = request(base + "/api/state?k=" + key),
   let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] {
    check("réponse acceptée", r.status == 200)
    check("le son actif est transmis", obj["preset"] as? String == "Concert Grand")
    check("la transposition est transmise", obj["transpose"] as? Int == -3)
    check("l'accord est transmis", obj["chord"] as? String == "Cmaj7")
} else { check("état lisible", false) }

if let r = request(base + "/api/library?k=" + key),
   let arr = try? JSONSerialization.jsonObject(with: r.body) as? [[String: Any]] {
    check("la bibliothèque est transmise", arr.count == 1 && arr[0]["name"] as? String == "Concert Grand")
} else { check("bibliothèque lisible", false) }

print("\n--- Une commande venue de la page arrive ---")
let r = request(base + "/api/cmd?k=" + key, method: "POST",
                json: ["action": "preset", "index": 7])
check("commande acceptée", r?.status == 200)
Thread.sleep(forTimeInterval: 0.4)
RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la commande part sur la file principale
check("commande reçue par l'application", received.contains { $0.0 == "preset" },
      received.map { $0.0 }.joined(separator: ", "))
check("avec son argument", received.first { $0.0 == "preset" }?.1["index"] as? Int == 7)
check("commande illisible rejetée",
      request(base + "/api/cmd?k=" + key, method: "POST", json: ["rien": 1])?.status == 400)
check("chemin inconnu", request(base + "/api/inconnu?k=" + key)?.status == 404)

print("\n--- Le flux temps réel ---")
// On ouvre le flux, on publie pendant ce temps, et on compte les trames
// reçues : c'est ce qui fait bouger le spectre sur la tablette.
var frames: [[String: Any]] = []
var streamStatus = 0
var streamType = ""
let publisher = Thread {
    for i in 0..<60 {
        let live: [String: Any] = ["rev": 1, "peakL": -20.0 + Double(i), "spectrum": "AAAA"]
        server.publish(live: try! JSONSerialization.data(withJSONObject: live))
        Thread.sleep(forTimeInterval: 0.04)
    }
}
let streamed = DispatchSemaphore(value: 0)
Task {
    do {
        var req = URLRequest(url: URL(string: base + "/api/stream?k=" + key)!)
        req.timeoutInterval = 12
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse {
            streamStatus = http.statusCode
            streamType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        }
        publisher.start()
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] {
                frames.append(obj)
            }
            if frames.count >= 4 { break }
        }
    } catch { }
    streamed.signal()
}
_ = streamed.wait(timeout: .now() + 14)
check("le flux s'ouvre", streamStatus == 200, "réponse \(streamStatus)")
check("annoncé comme un flux d'événements", streamType.contains("text/event-stream"), streamType)
check("au moins quatre trames reçues", frames.count >= 4, "\(frames.count) trames")
check("les trames portent l'instantané rapide",
      frames.last?["spectrum"] as? String == "AAAA")
check("les trames se suivent (ce n'est pas la même répétée)",
      Set(frames.compactMap { $0["peakL"] as? Double }).count > 1,
      frames.compactMap { $0["peakL"] as? Double }.map { String(format: "%.0f", $0) }.joined(separator: " "))

if let r = request(base + "/api/live?k=" + key),
   let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] {
    check("l'instantané rapide est aussi lisible d'un coup", obj["spectrum"] as? String == "AAAA")
} else { check("/api/live lisible", false) }
// Le serveur apprend la fermeture par la fin de flux TCP : on lui laisse
// un instant pour en prendre acte.
for _ in 0..<30 where server.streamCount > 0 { Thread.sleep(forTimeInterval: 0.05) }
check("le flux est refermé quand la tablette s'en va",
      server.streamCount == 0, "\(server.streamCount) encore ouvert(s)")

print("\n--- Les nouvelles commandes ---")
received.removeAll()
for (action, args) in [("eqfreq", ["index": 3, "freq": 1200] as [String: Any]),
                       ("eqq", ["index": 3, "q": 1.4]),
                       ("eqenabled", ["index": 3, "on": false]),
                       ("recordAudio", ["on": true]),
                       ("tempo", ["value": 96]),
                       ("checkUpdate", [:])] {
    var body: [String: Any] = args
    body["action"] = action
    _ = request(base + "/api/cmd?k=" + key, method: "POST", json: body)
}
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
for action in ["eqfreq", "eqq", "eqenabled", "recordAudio", "tempo", "checkUpdate"] {
    check("« \(action) » arrive", received.contains { $0.0 == action })
}

print("\n--- Adresses proposées ---")
let addrs = server.addresses
check("au moins une adresse", !addrs.isEmpty, addrs.joined(separator: "  "))
check("la clé y figure", addrs.allSatisfy { $0.contains(key) })

server.stop()
Thread.sleep(forTimeInterval: 0.3)
check("arrêt effectif", request(base + "/api/state?k=" + key) == nil)

print("\n\(fails == 0 ? "LE CONTRÔLE À DISTANCE FONCTIONNE" : "\(fails) PROBLÈME(S)")")
exit(fails == 0 ? 0 : 1)
