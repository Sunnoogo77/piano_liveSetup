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
} else { check("la page répond", false) }

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

print("\n--- Adresses proposées ---")
let addrs = server.addresses
check("au moins une adresse", !addrs.isEmpty, addrs.joined(separator: "  "))
check("la clé y figure", addrs.allSatisfy { $0.contains(key) })

server.stop()
Thread.sleep(forTimeInterval: 0.3)
check("arrêt effectif", request(base + "/api/state?k=" + key) == nil)

print("\n\(fails == 0 ? "LE CONTRÔLE À DISTANCE FONCTIONNE" : "\(fails) PROBLÈME(S)")")
exit(fails == 0 ? 0 : 1)
