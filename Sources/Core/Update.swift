import Foundation

// Vérification de version. On interroge les étiquettes Git du dépôt d'où vient
// cette copie — un fork vérifie donc le sien. Rien n'est téléchargé ni
// installé automatiquement : l'application dit ce qu'il y a de neuf et donne
// la commande exacte. La mise à jour reste une décision de celui qui joue.

/// Numéro de version comparable, tolérant : « v1.2 », « 1.2.3 », « 1.2.3-essai ».
struct SemVer: Comparable, CustomStringConvertible {
    var parts: [Int]
    var raw: String

    init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        raw = s
        let head = s.split(separator: "-").first.map(String.init) ?? s
        let nums = head.split(separator: ".").compactMap { Int($0) }
        guard !nums.isEmpty else { return nil }
        parts = nums
    }

    var description: String { raw }

    static func < (a: SemVer, b: SemVer) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: SemVer, b: SemVer) -> Bool { !(a < b) && !(b < a) }
}

enum UpdateCheck {

    struct Outcome: Sendable {
        var latest: String
        var isNewer: Bool
        var pageURL: String
    }

    enum Failure: Error, CustomStringConvertible {
        case offline(String)
        case rateLimited
        case noTags

        var description: String {
            switch self {
            case .offline(let why): return "vérification impossible : \(why)"
            case .rateLimited:      return "GitHub limite les requêtes — réessayez dans une heure"
            case .noTags:           return "aucune version publiée pour l'instant"
            }
        }
    }

    /// La commande à lancer dans un terminal, affichée telle quelle.
    /// Le dossier est celui d'où cette copie a été construite.
    static var command: String { "cd \"\(AppInfo.sourceDir)\" && ./scripts/update.sh" }

    static func run(current: String = AppInfo.version,
                    slug: String = AppInfo.slug,
                    session: URLSession = .shared,
                    completion: @escaping @Sendable (Result<Outcome, Failure>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(slug)/tags?per_page=50") else {
            completion(.failure(.offline("adresse du dépôt illisible"))); return
        }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PianoLiveSetup/\(current)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure(.offline(error.localizedDescription))); return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 403 || code == 429 { completion(.failure(.rateLimited)); return }
            guard code == 200, let data else {
                completion(.failure(.offline("réponse \(code) de GitHub"))); return
            }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(.failure(.offline("réponse illisible"))); return
            }
            let versions = rows.compactMap { $0["name"] as? String }.compactMap(SemVer.init)
            guard let best = versions.max(), let mine = SemVer(current) else {
                completion(.failure(.noTags)); return
            }
            completion(.success(Outcome(
                latest: best.raw,
                isNewer: mine < best,
                pageURL: "https://github.com/\(slug)/releases/tag/v\(best.raw)")))
        }.resume()
    }
}
