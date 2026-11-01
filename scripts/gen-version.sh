#!/usr/bin/env bash
# Écrit build/gen/Version.swift : la version, le commit, la date, le dépôt.
# Le dépôt est lu depuis le remote Git : un fork vérifie donc ses propres
# mises à jour, sans rien changer dans le code.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/gen/Version.swift}"
mkdir -p "$(dirname "$OUT")"

VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.0.0)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo inconnu)"
DIRTY=""
git diff --quiet 2>/dev/null || DIRTY="+"
BUILT="$(date +%Y-%m-%d)"
WHERE="$PWD"

SLUG="$(git config --get remote.origin.url 2>/dev/null || true)"
SLUG="${SLUG%.git}"
SLUG="${SLUG#*github.com/}"
SLUG="${SLUG#*github.com:}"
case "$SLUG" in */*) : ;; *) SLUG="Sunnoogo77/piano_liveSetup" ;; esac

cat > "$OUT" <<SWIFT
// Généré par scripts/gen-version.sh — ne pas modifier, ne pas versionner.
enum AppInfo {
    static let version = "$VERSION"
    static let commit = "$COMMIT$DIRTY"
    static let built = "$BUILT"
    static let slug = "$SLUG"
    /// Dossier du dépôt depuis lequel cette copie a été construite.
    static let sourceDir = "$WHERE"
    static var repoURL: String { "https://github.com/" + slug }
    static var long: String { "\(version) (\(commit), \(built))" }
}
SWIFT
echo "  version $VERSION ($COMMIT$DIRTY) — $SLUG"
