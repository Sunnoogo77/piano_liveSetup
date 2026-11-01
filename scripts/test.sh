#!/usr/bin/env bash
# Lance les tests. Par défaut seulement ceux qui ne demandent pas de matériel.
#   ./scripts/test.sh          accords + formats d'export (sans audio)
#   ./scripts/test.sh --audio  ajoute l'auto-test complet (joue du son, ~2 min)
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x build/bin/chordtest ] || ./scripts/build.sh
echo "── Reconnaissance d'accords ──────────────────────────"
build/bin/chordtest | tail -3
echo
echo "── Formats d'enregistrement ──────────────────────────"
build/bin/rectest | tail -4
echo
echo "── Numéros de version ────────────────────────────────"
build/bin/versiontest | tail -3
echo
echo "── Contrôle à distance ───────────────────────────────"
build/bin/remotetest | tail -4
echo
echo "── Le cœur compile sans framework Apple ──────────────"
if swiftc -swift-version 5 -typecheck -DPLS_PORTABLE \
     Sources/Core/Model.swift Sources/Core/DSP.swift \
     Sources/Core/Chords.swift Sources/Core/Recording.swift 2>/dev/null; then
  echo "  OK    Model, DSP, Chords et Recording sont du Swift portable"
else
  echo "  ÉCHEC un framework Apple s'est glissé dans le cœur"; exit 1
fi
if [ "${1:-}" = "--audio" ]; then
  echo
  echo "── Auto-test complet (du son va sortir) ──────────────"
  build/bin/selftest
fi
