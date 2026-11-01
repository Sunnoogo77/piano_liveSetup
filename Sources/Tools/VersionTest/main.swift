import Foundation

// Vérifie la comparaison de versions. Une erreur ici ferait dire à
// l'application « vous êtes à jour » alors qu'une correction attend, ou
// l'inverse : ça mérite un test.
//
//   versiontest              hors ligne, instantané
//   versiontest --online     interroge aussi GitHub pour de vrai

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("  OK    \(name)\(detail.isEmpty ? "" : "  — \(detail)")") }
    else { print("  ÉCHEC \(name)\(detail.isEmpty ? "" : "  — \(detail)")"); failures += 1 }
}

print("--- Lecture des numéros ---")
check("« v1.2.3 » se lit", SemVer("v1.2.3")?.parts == [1, 2, 3])
check("« 1.2 » se lit", SemVer("1.2")?.parts == [1, 2])
check("« 2.0.0-essai » se lit", SemVer("2.0.0-essai")?.parts == [2, 0, 0])
check("espaces ignorés", SemVer("  1.4.0\n")?.parts == [1, 4, 0])
check("« bidon » est refusé", SemVer("bidon") == nil)
check("chaîne vide refusée", SemVer("") == nil)

print("--- Ordre ---")
let pairs: [(String, String)] = [
    ("1.0.0", "1.0.1"), ("1.0.9", "1.1.0"), ("1.9.0", "2.0.0"),
    ("1.2", "1.2.1"), ("v1.0.0", "v1.0.2"), ("1.0.0", "1.10.0"),
]
for (a, b) in pairs {
    guard let x = SemVer(a), let y = SemVer(b) else { check("\(a) < \(b)", false, "illisible"); continue }
    check("\(a) < \(b)", x < y)
    check("\(b) > \(a)", y > x)
}
check("1.2.0 == 1.2", SemVer("1.2.0")! == SemVer("1.2")!)
check("1.2.0 n'est pas < 1.2", !(SemVer("1.2.0")! < SemVer("1.2")!))

print("--- Choix de la plus récente ---")
let tags = ["v1.0.0", "v1.10.2", "v1.9.9", "v0.4", "pas-une-version", "v1.10.1"]
let best = tags.compactMap(SemVer.init).max()
check("la plus récente est 1.10.2", best?.raw == "1.10.2", best?.raw ?? "aucune")

print("--- Cette copie ---")
check("la version de cette copie se lit", SemVer(AppInfo.version) != nil, AppInfo.version)
check("le dépôt est renseigné", AppInfo.slug.contains("/"), AppInfo.slug)
check("la commande de mise à jour nomme le script",
      UpdateCheck.command.contains("update.sh"), UpdateCheck.command)

if CommandLine.arguments.contains("--online") {
    print("--- Interrogation réelle de GitHub ---")
    let done = DispatchSemaphore(value: 0)
    UpdateCheck.run { result in
        switch result {
        case .success(let o):
            check("GitHub répond", true, "dernière publiée : \(o.latest)")
            check("comparaison cohérente",
                  o.isNewer == (SemVer(AppInfo.version)! < SemVer(o.latest)!),
                  o.isNewer ? "plus récente disponible" : "à jour")
        case .failure(let e):
            // Pas de réseau : ce n'est pas un défaut du code.
            print("  (ignoré) \(e.description)")
        }
        done.signal()
    }
    _ = done.wait(timeout: .now() + 20)
}

print(failures == 0 ? "TOUS LES TESTS PASSENT" : "\(failures) TEST(S) EN ÉCHEC")
exit(failures == 0 ? 0 : 1)
