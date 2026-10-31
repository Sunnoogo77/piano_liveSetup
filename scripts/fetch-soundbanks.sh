#!/usr/bin/env bash
# Télécharge les banques de sons depuis leurs sources officielles.
# Rien n'est redistribué par ce dépôt : chaque banque vient de chez son auteur.
#
#   ./scripts/fetch-soundbanks.sh            installation complète (~1,5 Go)
#   ./scripts/fetch-soundbanks.sh --light    sans les gros pianos (~250 Mo)
#   PIANO_LIVE_HOME=/tmp/essai ./scripts/fetch-soundbanks.sh
set -uo pipefail

HOME_DIR="${PIANO_LIVE_HOME:-$HOME/Music/Piano Live Setup}"
SOUNDS="$HOME_DIR/Sounds"
WORK="$(mktemp -d)"
LIGHT=0
FORCE=0
for a in "$@"; do
  case "$a" in
    --light) LIGHT=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
  esac
done
trap 'rm -rf "$WORK"' EXIT

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
err()  { printf "  \033[31m✗\033[0m %s\n" "$*"; }

mkdir -p "$SOUNDS"

# nom|taille Mo|archive|chemin dans l'archive|url|sha256|lourd
BANKS=(
"GeneralUser-GS.sf2|31|raw|.|https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2|9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe|0"
"MuseScore_General.sf3|38|raw|.|https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3|5b85b6c2c61d10b2b91cddd41efcce7b25cd31c8271d511c73afafbef20b6fa3|0"
"SalamanderGrandPiano.sf2|1208|tar.xz|SalamanderGrandPiano-SF2-V3+20200602/SalamanderGrandPiano-V3+20200602.sf2|https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPiano-SF2-V3+20200602.tar.xz|712d0e681efbe5203a8014e9b3e84168f1908c82f2f6fb13bd2c77d6d72c70b7|1"
"YDP-GrandPiano.sf2|113|tar.bz2|YDP-GrandPiano-SF2-20160804/YDP-GrandPiano-20160804.sf2|https://freepats.zenvoid.org/Piano/YDP-GrandPiano/YDP-GrandPiano-SF2-20160804.tar.bz2|8757076aecf80abdad1e8f8f6168370399b06f94481796986e6e75ceca09ad21|1"
"Organ-Drawbar.sf2|6|tar.xz|DrawbarOrganEmulation-SF2-20190712/DrawbarOrganEmulation-20190712.sf2|https://freepats.zenvoid.org/Organ/DrawbarOrganEmulation/DrawbarOrganEmulation-SF2-20190712.tar.xz|200b7d762fb1d4d7dbee34760a768319c7548e94b1a6ba76108f0702888b33ce|0"
"Organ-Percussive.sf2|14|tar.xz|PercussiveOrganEmulation-SF2-20190715/PercussiveOrganEmulation-20190715.sf2|https://freepats.zenvoid.org/Organ/PercussiveOrganEmulation/PercussiveOrganEmulation-SF2-20190715.tar.xz|468bd7a250849002afc28e28d11579e62b26a291e64724047d7880d3b149e9ab|0"
"Organ-Rock.sf2|13|tar.xz|RockOrganEmulation-SF2-20190715/RockOrganEmulation-20190715.sf2|https://freepats.zenvoid.org/Organ/RockOrganEmulation/RockOrganEmulation-SF2-20190715.tar.xz|994f79822699ca17174641864583ec8d32042c188ec85dcc90c28d29830eddf9|0"
"Organ-Church.sf2|14|tar.xz|ChurchOrganEmulation-SF2-20190924/ChurchOrganEmulation-20190924.sf2|https://freepats.zenvoid.org/Organ/ChurchOrganEmulation/ChurchOrganEmulation-SF2-20190924.tar.xz|15b8d2baf6cd996c602040553e1aa30fe3143199c5c91aa5f8a00b51670ed85a|0"
"Pad-Choir.sf2|14|7z|SynthPadChoir SF2-20200516/SynthPadChoir 20200516.sf2|https://github.com/freepats/synth-pad-choir/releases/download/2020-05-16/SynthPadChoir-SF2-20200516.7z|8688e074a15a40f2d9a251f9a642f67f91b1667ba6f4a1e765b9ee7347260c2d|0"
"Pad-Sweep.sf2|8|7z|SweepPad SF2-20190813/SweepPad 20190813.sf2|https://github.com/freepats/sweep-pad/releases/download/2019-08-13/SweepPad-SF2-20190813.7z|5a09a1d8ab60d236907572a46af8b4211881e2f8c7325e75f782ad5d7acce433|0"
"Pad-NewAge.sf2|9|7z|NewAge SF2-20190730/NewAge 20190730.sf2|https://github.com/freepats/new-age/releases/download/2019-07-30/NewAge-SF2-20190730.7z|39a85b39e85a4115bcb8ab99ac2bde3070ab802ba60ca45e15ba34a6bde990f6|0"
"Pad-Bowed.sf2|25|7z|SynthPadBowed SF2-20190719/SynthPadBowed 20190719.sf2|https://github.com/freepats/synth-pad-bowed/releases/download/2019-07-19/SynthPadBowed-SF2-20190719.7z|d20b2c26757c58665f83850515d68a7ecee11a87103f849be2406f026f9cf52a|0"
"Strings-1.sf2|6|7z|SynthStrings1 SF2-20200528/SynthStrings1 20200528.sf2|https://github.com/freepats/synth-strings-1/releases/download/2020-05-28/SynthStrings1-SF2-20200528.7z|7df5074a9ca497adfc3b63a3501a9244495dbb3334b05bba00789bf83cfe6cd4|0"
"Strings-2.sf2|9|7z|SynthStrings2 SF2-20200528/SynthStrings2 20200528.sf2|https://github.com/freepats/synth-strings-2/releases/download/2020-05-28/SynthStrings2-SF2-20200528.7z|31dcd7a7eedf07088f091bc3722ab9fb40d7954d2f9476493195d9990792469e|0"
"FM-Piano1.sf2|42|7z|FM-Piano1 SF2-20190916/FM-Piano1 20190916.sf2|https://github.com/freepats/fm-piano1/releases/download/2019-09-16/FM-Piano1-SF2-20190916.7z|5bbf457fa4ec98b1007fcae75f8e2f7ab39dbddea7a5f49c974059a5efdf7af4|0"
"FM-Piano2.sf2|15|7z|FM-Piano2 SF2-20161112/FM-Piano2 20161112.sf2|https://github.com/freepats/fm-piano2/releases/download/2016-11-12/FM-Piano2-SF2-20161112.7z|ef07538bb367694a0f0c52f829d342a58106f391446c374b9eb5f782b90ee83c|0"
)

need_7z=0
for row in "${BANKS[@]}"; do
  IFS='|' read -r name _ kind _ _ _ heavy <<<"$row"
  [ "$LIGHT" = 1 ] && [ "$heavy" = 1 ] && continue
  [ -f "$SOUNDS/$name" ] && [ "$FORCE" = 0 ] && continue
  [ "$kind" = "7z" ] && need_7z=1
done
if [ "$need_7z" = 1 ] && ! command -v 7z >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    bold "Installation de p7zip (nécessaire pour trois archives)…"
    brew install p7zip >/dev/null 2>&1 || warn "p7zip non installé : les banques .7z seront ignorées"
  else
    warn "p7zip absent et Homebrew introuvable : les banques .7z seront ignorées"
  fi
fi

bold "Banques de sons → $SOUNDS"
[ "$LIGHT" = 1 ] && warn "Mode allégé : les deux grands pianos échantillonnés sont ignorés."

got=0; skipped=0; failed=0
for row in "${BANKS[@]}"; do
  IFS='|' read -r name size kind inner url sha heavy <<<"$row"
  if [ "$LIGHT" = 1 ] && [ "$heavy" = 1 ]; then
    skipped=$((skipped+1)); continue
  fi
  target="$SOUNDS/$name"
  if [ -f "$target" ] && [ "$FORCE" = 0 ]; then
    have="$(shasum -a 256 "$target" | cut -d' ' -f1)"
    if [ "$have" = "$sha" ]; then ok "$name — déjà présente"; got=$((got+1)); continue
    else warn "$name — présente mais différente du manifeste, conservée telle quelle"; got=$((got+1)); continue; fi
  fi
  printf "  … %s (%s Mo)\n" "$name" "$size"
  arc="$WORK/$(basename "$url")"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$arc" "$url"; then
    err "$name — téléchargement impossible"; failed=$((failed+1)); continue
  fi
  case "$kind" in
    raw)    mv "$arc" "$target" ;;
    tar.xz) tar -xJf "$arc" -C "$WORK" && mv "$WORK/$inner" "$target" ;;
    tar.bz2)tar -xjf "$arc" -C "$WORK" && mv "$WORK/$inner" "$target" ;;
    7z)     if command -v 7z >/dev/null 2>&1; then
              7z x -y -o"$WORK" "$arc" >/dev/null && mv "$WORK/$inner" "$target"
            else err "$name — 7z absent"; failed=$((failed+1)); continue; fi ;;
  esac
  if [ ! -f "$target" ]; then err "$name — extraction impossible"; failed=$((failed+1)); continue; fi
  have="$(shasum -a 256 "$target" | cut -d' ' -f1)"
  if [ "$have" = "$sha" ]; then ok "$name"
  else warn "$name — empreinte différente du manifeste (l'auteur a peut-être publié une mise à jour)"; fi
  got=$((got+1))
done

echo
bold "$got banque(s) en place, $skipped ignorée(s), $failed en échec."
du -sh "$SOUNDS" 2>/dev/null | awk '{print "  Taille totale : " $1}'
[ "$failed" -gt 0 ] && exit 1
exit 0
