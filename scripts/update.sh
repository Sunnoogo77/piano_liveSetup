#!/usr/bin/env bash
#
#  Piano Live Setup — mise à jour
#
#    ./scripts/update.sh              récupère, reconstruit, réinstalle
#    ./scripts/update.sh --check      dit seulement s'il y a du nouveau
#    ./scripts/update.sh --yes        ne pose aucune question
#    ./scripts/update.sh --no-app     ne recopie pas l'app dans /Applications
#    ./scripts/update.sh --no-test    saute les tests (déconseillé)
#
#  Ce script ne touche jamais à vos réglages ni à vos enregistrements :
#  ils vivent dans ~/Music/Piano Live Setup, en dehors du dépôt.
#
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

CHECK=0; YES=0; NOAPP=""; TEST=1
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --yes|-y) YES=1 ;;
    --no-app) NOAPP="--no-app" ;;
    --no-test) TEST=0 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $a"; exit 2 ;;
  esac
done

b()    { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗\033[0m %s\n" "$*"; exit 1; }
ask()  { [ "$YES" = 1 ] && return 0; printf "  %s [o/N] " "$1"; read -r r; [[ "$r" =~ ^[oOyY] ]]; }

HERE="$(cat VERSION 2>/dev/null || echo inconnue)"

# ── Est-on bien dans un clone Git ? ──────────────────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  cat <<AIDE

  Ce dossier n'est pas un clone Git : la mise à jour automatique ne peut
  pas fonctionner (vous avez probablement téléchargé une archive ZIP).

  Version ici : $HERE

  Reprenez le projet avec Git, une fois pour toutes :

      git clone https://github.com/Sunnoogo77/piano_liveSetup.git
      cd piano_liveSetup && ./install.sh

  Vos sons, réglages et enregistrements sont ailleurs
  (~/Music/Piano Live Setup) : ils seront retrouvés tels quels.

AIDE
  exit 1
fi

command -v git >/dev/null 2>&1 || die "git est absent."

# ── Ce qui est disponible en face ────────────────────────────────────
b "Recherche d'une version plus récente"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch --tags --quiet origin || die "impossible de joindre le dépôt (réseau ?)"

REMOTE_REF="origin/$BRANCH"
git rev-parse --verify --quiet "$REMOTE_REF" >/dev/null \
  || die "la branche « $BRANCH » n'existe pas sur origin."

LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "$REMOTE_REF")"
THERE="$(git show "$REMOTE_REF:VERSION" 2>/dev/null | tr -d '[:space:]' || echo inconnue)"

printf "  ici    : %s  (%s)\n" "$HERE" "$(git rev-parse --short HEAD)"
printf "  là-bas : %s  (%s)\n" "$THERE" "$(git rev-parse --short "$REMOTE_REF")"

if [ "$LOCAL" = "$REMOTE" ]; then
  ok "Vous êtes déjà à jour."
  exit 0
fi

if git merge-base --is-ancestor "$REMOTE" "$LOCAL" 2>/dev/null; then
  ok "Votre copie est en avance sur origin — rien à récupérer."
  exit 0
fi

COUNT="$(git rev-list --count "HEAD..$REMOTE_REF")"
echo
printf "  \033[1m%s nouveau(x) changement(s) :\033[0m\n" "$COUNT"
git --no-pager log --format='    • %s' "HEAD..$REMOTE_REF" | head -20
[ "$COUNT" -gt 20 ] && echo "    … et $((COUNT - 20)) autre(s)"

if [ "$CHECK" = 1 ]; then
  echo
  echo "  Pour l'appliquer :  ./scripts/update.sh"
  exit 1          # 1 = il y a du nouveau, pour les scripts qui appellent
fi

# ── Protéger le travail local ────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
  warn "Vous avez des modifications non validées :"
  git --no-pager diff --stat HEAD | sed 's/^/      /'
  echo
  echo "  La mise à jour n'y touchera pas. Mettez-les de côté d'abord :"
  echo "      git stash          # puis, après la mise à jour : git stash pop"
  echo "  ou validez-les :"
  echo "      git add -A && git commit -m \"mes retouches\""
  die "rien n'a été modifié."
fi

MANIFEST_BEFORE="$(git hash-object scripts/fetch-soundbanks.sh 2>/dev/null || echo -)"

# ── Récupérer ────────────────────────────────────────────────────────
b "Récupération"
if ! git merge --ff-only "$REMOTE_REF" >/dev/null 2>&1; then
  warn "Votre historique a divergé de celui d'origine (vous avez des commits à vous)."
  echo "  Deux chemins possibles, à vous de choisir :"
  echo "      git rebase $REMOTE_REF     # rejouer vos commits par-dessus"
  echo "      git merge  $REMOTE_REF     # fusionner les deux"
  die "rien n'a été modifié."
fi
NEW="$(cat VERSION 2>/dev/null || echo inconnue)"
ok "version $NEW récupérée"

# ── Nouvelles banques de sons ? ──────────────────────────────────────
MANIFEST_AFTER="$(git hash-object scripts/fetch-soundbanks.sh 2>/dev/null || echo -)"
if [ "$MANIFEST_BEFORE" != "$MANIFEST_AFTER" ]; then
  b "La liste des banques de sons a changé"
  if ask "Télécharger ce qui manque ? (les fichiers déjà présents sont gardés)"; then
    ./scripts/fetch-soundbanks.sh || warn "le téléchargement a échoué — l'app marchera avec les banques déjà là"
  else
    warn "ignoré : des sons peuvent rester muets jusqu'à ./scripts/fetch-soundbanks.sh"
  fi
fi

# ── Reconstruire ─────────────────────────────────────────────────────
b "Construction"
./scripts/build.sh || die "la construction a échoué. Votre ancienne application dans /Applications est intacte."
ok "construit"

if [ "$TEST" = 1 ]; then
  b "Tests"
  ./scripts/test.sh || die "les tests échouent. L'application n'a pas été remplacée."
fi

# ── Installer ────────────────────────────────────────────────────────
if [ -z "$NOAPP" ]; then
  b "Installation"
  RUNNING=0
  pgrep -f "/Applications/Piano Live Setup.app" >/dev/null 2>&1 && RUNNING=1
  if [ "$RUNNING" = 1 ]; then
    if ask "L'application est ouverte. La fermer pour la remplacer ?"; then
      osascript -e 'tell application "Piano Live Setup" to quit' 2>/dev/null || true
      for _ in $(seq 1 20); do
        pgrep -f "/Applications/Piano Live Setup.app" >/dev/null 2>&1 || break
        sleep 0.5
      done
    else
      warn "l'application en place n'a pas été remplacée — relancez ce script plus tard"
      exit 0
    fi
  fi
  rm -rf "/Applications/Piano Live Setup.app"
  cp -R "build/Piano Live Setup.app" "/Applications/" || die "copie impossible dans /Applications"
  touch "/Applications/Piano Live Setup.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "/Applications/Piano Live Setup.app" 2>/dev/null || true
  ok "/Applications/Piano Live Setup.app"
fi

b "Mise à jour terminée : $HERE → $NEW"
if [ -f CHANGELOG.md ]; then
  echo "  Ce qui change :"
  awk '/^## /{n++} n==1 && !/^## /' CHANGELOG.md | sed 's/^/  /' | head -30
fi
echo
echo "  Vos réglages, vos sons et vos enregistrements n'ont pas été touchés."
