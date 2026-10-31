#!/usr/bin/env bash
# Recalcule les gains de chaque preset pour une sonie égale.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x build/bin/calibrate ] || ./scripts/build.sh
exec build/bin/calibrate
