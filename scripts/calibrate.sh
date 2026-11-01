#!/usr/bin/env bash
# Recalcule les gains de chaque preset pour une sonie égale.
set -euo pipefail
cd "$(dirname "$0")/.."
# Reconstruire si l'outil manque ou si une source est plus récente que lui :
# un étalonnage de cinq minutes lancé sur un binaire périmé ne se voit pas,
# il écrit simplement les mauvais gains.
if [ ! -x build/bin/calibrate ] \
   || [ -n "$(find Sources -name '*.swift' -newer build/bin/calibrate -print -quit)" ]; then
  ./scripts/build.sh
fi
exec build/bin/calibrate
