# Porter le projet ailleurs

## Où en est-on vraiment

| Partie | État |
|---|---|
| `Sources/Core/Model.swift`, `DSP.swift`, `Chords.swift`, `Recording.swift` | **Portable, vérifié.** Compile avec `-DPLS_PORTABLE` sans aucun framework Apple. `make portable` le contrôle, et la CI aussi. |
| `Sources/Core/Engine.swift` | macOS. CoreMIDI, CoreAudio HAL, `AVAudioEngine`. |
| `Sources/Core/Mic.swift` | macOS. `AudioDeviceIOProc`. |
| `Sources/UI/` | macOS. SwiftUI + AppKit. |

L'analyseur a deux implémentations : la FFT d'Accelerate chez Apple, une FFT radix-2
en Swift pur ailleurs. Les deux donnent les mêmes mesures — c'est vérifié par
`make test`, qui compile et compare les deux chemins.

**Aucun portage n'est fait à ce jour.** Ce qui suit est un plan, pas une promesse.

## iPad et iPhone — le plus proche

Presque tout existe déjà sur iOS : Swift, SwiftUI, `AVAudioEngine`, CoreMIDI, et
FluidSynth se compile pour iOS.

À remplacer :

| macOS | iOS |
|---|---|
| énumération CoreAudio HAL | `AVAudioSession.availableInputs`, la sortie est celle du système |
| `kAudioDevicePropertyBufferFrameSize` | `AVAudioSession.setPreferredIOBufferDuration` |
| `AudioDeviceIOProc` pour le micro | `AVAudioEngine.inputNode`, même session donc même horloge — plus simple qu'ici |
| `NSEvent`, `NSWorkspace`, `NSApplication` | équivalents UIKit, ou rien |

Points durs : un iPad a besoin d'un adaptateur USB alimenté pour un clavier, et
1,5 Go d'échantillons passent mal — utilisez l'installation allégée. L'iPhone est
trop étroit pour l'égaliseur et l'analyseur côte à côte : il faudrait une mise en
page réduite, et l'écran Jeu seul a du sens.

Le vrai obstacle n'est pas technique : une app iOS s'installe par l'App Store ou
Xcode, pas par un script. Il faut un projet Xcode et un compte développeur.

## Linux

Swift tourne sur Linux, FluidSynth y est natif. Le cœur compile déjà.

À écrire : une implémentation de l'hôte audio utilisant les pilotes de FluidSynth
(`alsa`, `pulseaudio` ou `jack`) et son pilote MIDI (`alsa_seq`), à la place de
`AVAudioEngine` et CoreMIDI. C'est moins de travail qu'il n'y paraît : FluidSynth
sait ouvrir lui-même l'audio et le MIDI, et l'application reprend la main sur le
rendu seulement pour sa propre chaîne de traitement.

L'interface est le vrai sujet : SwiftUI n'existe pas sur Linux.

## Windows

Swift a un portage Windows, FluidSynth aussi. Mêmes remarques que Linux : les
pilotes `wasapi` et `winmm` de FluidSynth font le travail, l'interface est à
reprendre.

## Le chemin que je recommanderais

Plutôt qu'un portage complet de l'interface sur trois systèmes, l'approche qui
rapporte le plus vite :

1. **Extraire un paquet `PianoLiveCore`** (SwiftPM) avec les quatre fichiers déjà
   portables, et un protocole `AudioHost` / `MIDIHost`.
2. **Deux implémentations de l'hôte** : celle de macOS (déjà écrite, à déplacer) et
   une basée sur les pilotes FluidSynth pour Linux et Windows.
3. **Un exécutable sans interface** qui expose l'état et les commandes en HTTP et
   WebSocket sur le réseau local.
4. **Une interface web** servie par cet exécutable. Elle résout trois problèmes d'un
   coup : Linux et Windows ont enfin une interface, **et un iPad ou un téléphone
   peut piloter le rig à distance pendant que le Mac fait le son** — ce qui est
   souvent ce qu'on veut vraiment sur scène, plutôt que de faire tourner le moteur
   sur la tablette.

L'étape 4 est probablement la plus utile pour le moins d'effort. Si vous la tentez,
gardez l'application macOS telle quelle : elle reste la référence qui sonne.

## Si vous vous lancez

Lisez [AGENTS.md](../AGENTS.md) d'abord, surtout la section sur les contraintes du
thread audio : elles valent sur tous les systèmes. Et gardez `make portable` au vert.
