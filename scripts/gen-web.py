#!/usr/bin/env python3
"""Assemble la surface de commande en un seul fichier Swift.

    gen-web.py <dossier Sources/Web> <dossier des icônes> <sortie .swift>

La page est servie en un seul morceau : la feuille de style et le script sont
injectés dans le HTML à la place des marqueurs « @css » et « @js ». Les icônes
(écran d'accueil de l'iPad, favicon) sont embarquées en base64, ce qui évite
un dossier de ressources à côté du binaire.
"""
import base64
import pathlib
import sys

web, icons, dst = (pathlib.Path(p) for p in sys.argv[1:4])

html = (web / "remote.html").read_text(encoding="utf-8")
css = (web / "remote.css").read_text(encoding="utf-8")
js = (web / "remote.js").read_text(encoding="utf-8")

for marker, content, what in (("/* @css */", css, "feuille de style"),
                              ("/* @js */", js, "script")):
    if marker not in html:
        sys.exit(f"marqueur {marker} absent de remote.html ({what} non injecté)")
    html = html.replace(marker, content)


def swift_literal(text):
    """Protège ce qui termine une chaîne multiligne Swift."""
    return text.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')


def wrap(b64, width=120):
    return "\n".join(b64[i:i + width] for i in range(0, len(b64), width))


found = []
for name in ("icon-180.png", "icon-192.png", "icon-512.png"):
    path = icons / name
    if not path.exists():
        sys.exit(f"icône manquante : {path} (lancez makeicon --web)")
    found.append((name, wrap(base64.b64encode(path.read_bytes()).decode("ascii"))))

out = ['// Généré par scripts/gen-web.py — ne pas modifier à la main.',
       'import Foundation', '', 'enum WebAssets {',
       '    static let remotePage = """', swift_literal(html), '"""', '']
for name, b64 in found:
    key = name.replace("-", "").replace(".png", "").replace("icon", "icon")
    out += [f'    private static let {key} = """', b64, '"""', '']
out += ['    /// Les icônes sont décodées à la demande ; « ignoreUnknownCharacters »',
        '    /// permet de les garder découpées en lignes dans le source.',
        '    static func icon(_ path: String) -> Data? {',
        '        let b64: String',
        '        switch path {']
for name, _ in found:
    key = name.replace("-", "").replace(".png", "")
    out.append(f'        case "/{name}": b64 = {key}')
out += ['        default: return nil',
        '        }',
        '        return Data(base64Encoded: b64, options: [.ignoreUnknownCharacters])',
        '    }', '}', '']

dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text("\n".join(out), encoding="utf-8")
total = len(html) + sum(len(b) for _, b in found)
print(f"  page {len(html) // 1024} Ko + {len(found)} icônes → {total // 1024} Ko embarqués")
