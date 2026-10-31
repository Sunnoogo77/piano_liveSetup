#!/usr/bin/env python3
"""Transforme la page de commande HTML en chaîne Swift.

Le binaire embarque ainsi la page sans avoir besoin d'un dossier de ressources.
Seuls les antislashs et les triples guillemets doivent être protégés dans une
chaîne multiligne Swift.
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
html = open(src, encoding="utf-8").read()
html = html.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
with open(dst, "w", encoding="utf-8") as f:
    f.write("// Généré depuis Sources/Web/remote.html — ne pas modifier à la main.\n")
    f.write("enum WebAssets {\n    static let remotePage = \"\"\"\n")
    f.write(html)
    f.write("\n\"\"\"\n}\n")
print(f"  page embarquée : {len(html)} octets")
