#!/usr/bin/env bash
# Retire l'application. Les enregistrements ne sont jamais supprimés sans accord.
set -euo pipefail
HOME_DIR="${PIANO_LIVE_HOME:-$HOME/Music/Piano Live Setup}"
for d in "/Applications/Piano Live Setup.app" "$HOME/Applications/Piano Live Setup.app"; do
  [ -d "$d" ] && rm -rf "$d" && echo "Supprimé : $d"
done
echo
echo "Les banques de sons et vos enregistrements sont toujours dans :"
echo "  $HOME_DIR"
echo
echo "Pour tout effacer, y compris vos prises :"
echo "  rm -rf \"$HOME_DIR\""
echo "Pour retirer le moteur de son :  brew uninstall fluid-synth"
