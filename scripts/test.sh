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
if [ "${1:-}" = "--audio" ]; then
  echo
  echo "── Auto-test complet (du son va sortir) ──────────────"
  build/bin/selftest
fi
