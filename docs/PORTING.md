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

## iPad et iPhone

Deux questions différentes se cachent derrière « est-ce que ça tourne sur
iPad ? ». Elles n'ont pas la même réponse.

### 1. Piloter depuis un iPad — **fait, aujourd'hui**

L'application publie une page sur le réseau local (onglet *Périphériques* →
*Contrôle à distance*). La tablette ouvre cette page et retrouve les mêmes
écrans que le Mac : sons, égaliseur sept bandes avec analyseur de spectre,
accords, clavier, enregistrement, micro.

Posée sur l'écran d'accueil (**Partager → Sur l'écran d'accueil**), elle a son
icône et s'ouvre en plein écran, sans barre de Safari : à l'usage, c'est une
application. Rien à installer, rien à compiler, aucun compte.

Ce qu'il faut savoir :

- le son sort du Mac ; la tablette est une surface de commande ;
- l'icône emporte la clé d'accès, donc elle s'ouvre déjà connectée ;
- pas de fonctionnement hors ligne. Un *service worker* exige une connexion
  sécurisée, et on sert du HTTP en clair sur le réseau local. Sans le Mac, la
  page affiche qu'elle ne le trouve plus.

### 2. Faire tourner le moteur **sur** l'iPad — possible, mais

Côté code, presque tout existe sur iOS : Swift, SwiftUI, `AVAudioEngine`,
CoreMIDI. À remplacer :

| macOS | iOS |
|---|---|
| énumération CoreAudio HAL | `AVAudioSession.availableInputs`, la sortie est celle du système |
| `kAudioDevicePropertyBufferFrameSize` | `AVAudioSession.setPreferredIOBufferDuration` |
| `AudioDeviceIOProc` pour le micro | `AVAudioEngine.inputNode` — même session, même horloge : plus simple qu'ici |
| `NSEvent`, `NSWorkspace`, `NSApplication` | équivalents UIKit, ou rien |
| `NWListener` pour la page de commande | identique, `Network` existe sur iOS |

**Le vrai obstacle est l'installation, et il ne vient pas de ce code.** Sur
iPadOS, une application s'installe par l'App Store, par TestFlight, ou depuis
Xcode sur un Mac relié. Il n'existe aucun chemin « je clone le dépôt et
j'installe » — ni pour vous, ni pour un agent. Concrètement :

| Comment | Ce qu'il faut | Durée de vie |
|---|---|---|
| Xcode sur un Mac, par le câble | un Mac, un identifiant Apple gratuit | 7 jours, à resigner |
| TestFlight ou App Store | compte développeur Apple (99 $/an) + un Mac pour la soumission | permanent |
| Marché alternatif (UE seulement) | compte développeur, notarisation, **et un Mac pour construire** | selon le marché |

Donc : quelqu'un qui n'a **qu'un** iPad ne peut pas obtenir cette application
en application, quoi qu'on écrive dans le dépôt. Il peut en revanche utiliser
la page de commande tout de suite — c'est pour cela qu'elle existe.

### 3. Le seul chemin sans Mac du tout : Swift Playgrounds

Swift Playgrounds, gratuit sur l'App Store, construit et exécute une
application SwiftUI **sur** l'iPad, et sait la soumettre à l'App Store. Mais il
ne sait pas lier une bibliothèque C : **FluidSynth est hors jeu.**

Le remplaçant existe et est fourni par Apple : `AVAudioUnitSampler` charge
directement un SF2 et joue du MIDI. Une variante « tout Swift, tout Apple » est
donc faisable. Ce qu'elle coûte, honnêtement :

- `AVAudioUnitSampler` ne donne pas la main sur les réglages fins par banque
  (`fluid_synth_set_gen`, réverbération, chorus) ; l'équilibre des 31 sons
  serait à refaire à l'oreille ;
- un son par échantillonneur : les superpositions demandent plusieurs nœuds ;
- la chaîne de traitement (égaliseur, saturation, trémolo, limiteur) se place
  dans un `AVAudioSourceNode` ou un `AVAudioUnit` — le code DSP lui-même
  (`DSP.swift`) est déjà portable et se réutilise tel quel ;
- un clavier USB demande un adaptateur alimenté, et 1,5 Go d'échantillons ne
  passent pas : installation allégée obligatoire.

C'est un projet à part entière, pas une adaptation. Si vous le tentez,
commencez par l'étape 1 de la feuille de route ci-dessous : le cœur est déjà
prêt, c'est l'hôte qui change.

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
4. ~~**Une interface web** servie par cet exécutable.~~ **Faite** — voir
   `Sources/Core/RemoteServer.swift` et `Sources/Web/`. Un iPad ou un téléphone
   pilote le rig pendant que le Mac fait le son, ce qui est souvent ce qu'on veut
   vraiment sur scène. Elle est écrite sans rien de spécifique à macOS côté
   navigateur : un hôte Linux ou Windows qui publie les mêmes routes
   (`/api/stream`, `/api/state`, `/api/library`, `/api/cmd`) réutilise la page
   telle quelle.

Les étapes 1 à 3 restent à faire. Si vous les tentez, gardez l'application macOS
telle quelle : elle reste la référence qui sonne.

## Si vous vous lancez

Lisez [AGENTS.md](../AGENTS.md) d'abord, surtout la section sur les contraintes du
thread audio : elles valent sur tous les systèmes. Et gardez `make portable` au vert.
