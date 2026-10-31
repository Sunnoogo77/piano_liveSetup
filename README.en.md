<div align="center">

# Piano Live Setup

**Turn a Mac into the sound engine for any USB MIDI piano.**

31 stage sounds · 7-band EQ over a real-time spectrum analyser · live chord detection
recording to audio, MIDI and sheet music · microphone input · **2.9 ms latency**

[Version française](README.md) · [Architecture](docs/ARCHITECTURE.md) · [Porting](docs/PORTING.md)

![Play screen](docs/images/tab-play.png)

</div>

> **The app's interface is in French.** This file is here so the project can be
> understood from anywhere; translating the UI is a welcome contribution —
> see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Install

```bash
git clone https://github.com/Sunnoogo77/piano_liveSetup.git
cd piano_liveSetup
./install.sh
```

The script checks your Mac, installs what's missing, downloads the sound banks from
their official sources, builds, calibrates all 31 sounds and puts the app in
`/Applications`.

Short on disk? `./install.sh --light` skips the two large sampled pianos (250 MB
instead of 1.5 GB). The affected presets fall back to equivalent sounds — nothing
goes silent.

**Requirements:** macOS 14 or newer, a MIDI piano or keyboard with a USB port, a USB
cable. The installer handles Xcode Command Line Tools, Homebrew, FluidSynth and the
sound banks.

---

## What it does

**One cable.** Plug the piano in over USB. It is recognised whatever the brand —
Yamaha, Korg, Roland, Casio, Nord — and whether you plug it in before or after
launching. Many digital pianos present themselves to the Mac both as a MIDI port and
as a sound card under the same name; when the app sees that, it sends the sound back
into the instrument's own speakers through the same cable. It also silences the
keyboard's internal engine (CC 122, a standard MIDI message) so you don't hear two
pitches when you transpose — and restores it on quit. No setting on the instrument is
ever changed.

**31 calibrated sounds.** Six acoustic pianos, six electric, five organs, six pads and
strings, six layered patches, two keyboard splits. The main piano is a **Yamaha C5
with 16 velocity layers**. Each variant has its own EQ, drive, tremolo, compression and
velocity curve. All are matched to the same loudness, measured by offline rendering,
with 6 dB of headroom.

**Six screens:** Play, Equaliser, Chords, Keyboard, Record, Devices.

**Chords, spelled properly.** Triads through thirteenths, altered and suspended chords,
slash inversions, and pianists' voicings with the fifth omitted. Notes are named by
their **function in the chord**, not by pitch class: a C9 reads *C E G B♭ D*, an E7
reads *E G♯ B D*. 43 reference chords are checked automatically.

**Recording in four formats:** `audio.wav` (24-bit stereo, effects included),
`performance.mid` (exact timing, replayable on the piano), `partition.musicxml` (two
staves, for MuseScore, Dorico, Finale), `accords.txt` (time-stamped chord chart).

**Remote control from a tablet.** In the Devices tab, turn on remote control: the app
publishes a page on your local network. Scan the QR code shown, or type the address into
the tablet's browser, and you get the sounds, transposition, levels, EQ, panic and
recording. **Nothing to install on the tablet** — any browser will do. The Mac keeps
making the sound, so you keep the 2.9 ms latency and the 16-velocity-layer piano. An
access key keeps other people on the network out, and it is remembered.

**Microphone input** with its own gain, compressor and independent 7-band EQ. Monitoring
is off by default — an open mic next to the piano's speakers will howl.

---

## Commands

| | |
|---|---|
| `./install.sh` | full install |
| `./install.sh --light` | without the large pianos |
| `make build` | build only |
| `make test` | hardware-free tests (chords, export formats, portable core) |
| `make test-audio` | everything, including tests that play sound |
| `make calibrate` | re-balance the sounds after editing presets |
| `make preview` | render the interface to PNG without opening the app |
| `make portable` | check the core still builds without Apple frameworks |

---

## How it's built

Swift and SwiftUI, no package dependencies, one binary. **FluidSynth** (LGPL) renders
the SF2/SF3 banks, driven from an `AVAudioEngine` render block targeting the chosen
device at 128 frames. Drive, a 7-band biquad EQ, tremolo, compressor and limiter are
written by hand, with no allocation and no locks on the audio thread. The analyser runs
a 2048-point FFT across 128 logarithmic bands.

`Sources/Core/` — the model, DSP, chord detection and recording — **builds without any
Apple framework**, verified on every CI run. See [docs/PORTING.md](docs/PORTING.md) for
what a Linux, Windows, iPad or web port would take.

---

## Working with an AI agent

The repository is written for that. [AGENTS.md](AGENTS.md) holds the code map, the
commands, the rules that must not be broken and the traps already hit.

> Clone https://github.com/Sunnoogo77/piano_liveSetup, read AGENTS.md, install it on
> this Mac following the README, then verify everything with `make test`.

---

## Licences

The code is **MIT**. The sound banks are **not** in this repository: they are downloaded
from their authors at install time, each under its own licence. Two of them require
attribution if you publish a recording. See [CREDITS.md](CREDITS.md) before you release
your music.
