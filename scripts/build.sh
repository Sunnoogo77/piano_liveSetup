#!/usr/bin/env bash
# Compile l'application et tous les outils dans build/.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build"
BIN="$OUT/bin"
APP="$OUT/Piano Live Setup.app"

PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
if [ ! -f "$PREFIX/include/fluidsynth.h" ]; then
  echo "FluidSynth introuvable dans $PREFIX. Lancez : brew install fluid-synth" >&2
  exit 1
fi

ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos14.0"
FLAGS=(-O -swift-version 5 -import-objc-header Sources/fluid-bridge.h
       -I "$PREFIX/include" -L "$PREFIX/lib" -lfluidsynth
       -Xlinker -rpath -Xlinker "$PREFIX/lib"
       -target "$TARGET")

CORE=(Sources/Core/Model.swift Sources/Core/DSP.swift Sources/Core/Chords.swift
      Sources/Core/Recording.swift Sources/Core/Mic.swift Sources/Core/Engine.swift)
UI=(Sources/UI/Design.swift Sources/UI/Controls.swift Sources/UI/Analyzer.swift
    Sources/UI/App.swift Sources/UI/Stage.swift Sources/UI/Screens.swift Sources/UI/Screens2.swift)

mkdir -p "$BIN"
echo "→ application"
swiftc "${FLAGS[@]}" "${CORE[@]}" "${UI[@]}" Sources/UI/Main.swift -o "$BIN/PianoLiveSetup"
echo "→ outils"
swiftc "${FLAGS[@]}" "${CORE[@]}" "${UI[@]}" Sources/Tools/Preview/main.swift   -o "$BIN/preview"
swiftc "${FLAGS[@]}" Sources/Core/Model.swift Sources/Core/DSP.swift Sources/Tools/Calibrate/main.swift -o "$BIN/calibrate"
swiftc "${FLAGS[@]}" "${CORE[@]}" Sources/Tools/SelfTest/main.swift             -o "$BIN/selftest"
swiftc "${FLAGS[@]}" Sources/Core/Model.swift Sources/Core/DSP.swift Sources/Tools/Banks/main.swift -o "$BIN/banks"
swiftc -O -swift-version 5 Sources/Core/Chords.swift Sources/Tools/ChordTest/main.swift -o "$BIN/chordtest"
swiftc "${FLAGS[@]}" Sources/Core/Model.swift Sources/Core/DSP.swift Sources/Core/Chords.swift \
       Sources/Core/Recording.swift Sources/Tools/RecTest/main.swift            -o "$BIN/rectest"

echo "→ bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/PianoLiveSetup" "$APP/Contents/MacOS/PianoLiveSetup"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Construit : $APP"
