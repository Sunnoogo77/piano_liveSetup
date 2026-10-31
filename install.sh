#!/usr/bin/env bash
#
#  Piano Live Setup — installation complète
#
#    ./install.sh                 tout, y compris les deux grands pianos (~1,5 Go)
#    ./install.sh --light         sans les gros pianos (~250 Mo)
#    ./install.sh --yes           ne pose aucune question
#    ./install.sh --no-app        construit sans copier l'app dans /Applications
#    PIANO_LIVE_HOME=/tmp/essai ./install.sh    installe ailleurs
#
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
HOME_DIR="${PIANO_LIVE_HOME:-$HOME/Music/Piano Live Setup}"

LIGHT=""; YES=0; NOAPP=0
for a in "$@"; do
  case "$a" in
    --light) LIGHT="--light" ;;
    --yes|-y) YES=1 ;;
    --no-app) NOAPP=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $a"; exit 2 ;;
  esac
done

b()    { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗\033[0m %s\n" "$*"; exit 1; }
ask()  { [ "$YES" = 1 ] && return 0; printf "  %s [o/N] " "$1"; read -r r; [[ "$r" =~ ^[oOyY] ]]; }

cat <<'BANNER'

  ╭──────────────────────────────────────────────╮
  │   Piano Live Setup                           │
  │   Votre Mac devient l'expandeur de n'importe │
  │   quel piano numérique branché en USB.       │
  ╰──────────────────────────────────────────────╯
BANNER

# ── 1. Le Mac ────────────────────────────────────────────────────────
b "1/6  Vérification du Mac"
[ "$(uname -s)" = "Darwin" ] || die "Cet outil ne fonctionne que sur macOS."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "macOS 14 (Sonoma) ou plus récent est nécessaire — vous avez $(sw_vers -productVersion)."
ok "macOS $(sw_vers -productVersion) sur $(uname -m)"
FREE_GB=$(df -g / | awk 'NR==2{print $4}')
NEED=3; [ -n "$LIGHT" ] && NEED=1
[ "$FREE_GB" -ge "$NEED" ] || die "Il faut au moins $NEED Go libres (il en reste $FREE_GB)."
ok "$FREE_GB Go libres"

# ── 2. Outils de compilation ─────────────────────────────────────────
b "2/6  Outils de développement Apple"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
  warn "Les outils en ligne de commande de Xcode sont absents."
  if ask "Lancer leur installation maintenant ?"; then
    xcode-select --install 2>/dev/null || true
    echo
    echo "  Une fenêtre Apple s'est ouverte. Une fois l'installation terminée,"
    echo "  relancez :  ./install.sh"
    exit 0
  fi
  die "Installation impossible sans eux :  xcode-select --install"
fi
ok "swiftc $(swiftc --version 2>/dev/null | head -1 | sed 's/.*Swift version \([0-9.]*\).*/\1/')"

# ── 3. Homebrew ──────────────────────────────────────────────────────
b "3/6  Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$($p shellenv)" && break
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew n'est pas installé — il sert à poser le moteur de son."
  if ask "L'installer depuis brew.sh (script officiel d'Homebrew) ?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Installation d'Homebrew interrompue."
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$p" ] && eval "$($p shellenv)" && break
    done
  else
    die "Installez-le puis relancez :  https://brew.sh"
  fi
fi
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ── 4. Moteur de son ─────────────────────────────────────────────────
b "4/6  FluidSynth (le moteur de son, LGPL)"
if brew list fluid-synth >/dev/null 2>&1; then
  ok "déjà installé ($(fluidsynth --version 2>&1 | head -1 | awk '{print $3}'))"
else
  echo "  Installation…"
  brew install fluid-synth || die "brew install fluid-synth a échoué."
  ok "installé"
fi

# ── 5. Banques de sons ───────────────────────────────────────────────
b "5/6  Banques de sons"
echo "  Téléchargées depuis leurs sources officielles (FreePats, MuseScore, GitHub)."
echo "  Rien n'est redistribué par ce dépôt."
./scripts/fetch-soundbanks.sh $LIGHT || warn "Certaines banques manquent — l'app bascule sur des équivalences."

# ── 6. Construction ──────────────────────────────────────────────────
b "6/6  Construction et étalonnage"
./scripts/build.sh || die "La compilation a échoué."
ok "application construite"
echo "  Étalonnage des 31 sons (une minute environ)…"
if build/bin/calibrate >/tmp/pls-calib.log 2>&1; then
  ok "$(grep -c 'crête' /tmp/pls-calib.log) sons mesurés et équilibrés"
else
  warn "Étalonnage incomplet — voir /tmp/pls-calib.log"
fi

APP_SRC="$ROOT/build/Piano Live Setup.app"
if [ "$NOAPP" = 0 ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/Piano Live Setup.app"
  cp -R "$APP_SRC" "$DEST/" && ok "installée dans $DEST"
  APP_SRC="$DEST/Piano Live Setup.app"
fi

cat <<EOF

  ╭──────────────────────────────────────────────╮
  │   C'est prêt.                                │
  ╰──────────────────────────────────────────────╯

  Application :  $APP_SRC
  Vos données :  $HOME_DIR
                 (sons, réglages, enregistrements)

  Branchez votre piano en USB, puis ouvrez l'application.
  Elle reconnaît le clavier quelle qu'en soit la marque,
  même branché après le lancement.

  Essayer les tests :   ./scripts/test.sh
  Tout désinstaller :   ./scripts/uninstall.sh

EOF
if [ "$NOAPP" = 0 ] && ask "Ouvrir l'application maintenant ?"; then
  open "$APP_SRC"
fi
