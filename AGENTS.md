# Notes pour un agent qui travaille sur ce dépôt

Ce fichier existe pour qu'un agent reprenne le projet sans refaire les erreurs déjà
faites. Lisez-le en entier avant de toucher au code.

---

## 1. Ce qu'est ce projet

Une application macOS native, en Swift + SwiftUI, qui transforme un Mac en expandeur de
scène pour un piano numérique branché en USB. Pas de dépendance de paquet : un seul
binaire, lié à **FluidSynth** installé par Homebrew.

**L'interface est en français.** Tout le texte visible, tous les commentaires de code et
tous les messages de commit sont en français. Gardez-le ainsi.

## 2. Mise en route

```bash
./install.sh --light      # installation rapide pour développer (250 Mo de banques)
make build                # compiler
make test                 # accords + formats d'export, sans matériel audio
make test-audio           # tout, y compris ce qui joue du son (demande un périphérique)
make preview              # rend l'interface en PNG dans build/ui — regardez-les
```

`PIANO_LIVE_HOME=/tmp/essai ./install.sh --light --no-app` installe dans un dossier
jetable sans toucher à l'installation de scène de l'utilisateur. **Faites toujours ça**
pour tester une installation propre.

## 3. Carte du code

```
Sources/Core/
  Model.swift       emplacements, banques et leurs équivalences, EQ, presets, bibliothèque
  RemoteServer.swift serveur HTTP local pour la page de commande (tablette, téléphone)
  DSP.swift         biquads RBJ, chaîne de traitement, analyseur FFT
  Chords.swift      reconnaissance d'accords et écriture des notes par degré
  Recording.swift   prise, WAV 24 bits, fichier MIDI standard, MusicXML, grille d'accords
  Mic.swift         entrée micro via AudioDeviceIOProc, rééchantillonnage asservi
  Engine.swift      FluidSynth + AVAudioEngine + CoreMIDI, le cœur
Sources/UI/
  Design.swift      palette, composants (Panel, Key, Fader, LevelMeter, Scroll)
  Controls.swift    NumberDrag, tranche d'EQ, ligne de preset
  Analyzer.swift    spectre + courbe d'EQ + points déplaçables
  App.swift         RigModel (ObservableObject) et écran de chargement
  Stage.swift       coque : bandeau, onglets, écran Égaliseur, barre d'état
  Screens.swift     clavier 88 touches, affichage d'accord, écrans Jeu / Accords / Clavier
  Screens2.swift    écrans Enregistrer et Périphériques
  Main.swift        point d'entrée @main et raccourcis clavier
Sources/Web/
  remote.html       la page de commande, transformée en chaîne Swift à la construction
                    par scripts/gen-web.py — modifiez le HTML, pas le fichier généré
Sources/Tools/      outils en ligne de commande, un dossier = une cible
                    MakeIcon fabrique l'icône de l'application à chaque construction
```

Un fichier compte : **`Sources/Tools/Preview/main.swift`** rend l'interface hors écran en
PNG. C'est le seul moyen de *voir* ce qu'on a dessiné sans capture d'écran. Utilisez-le.

## 4. Règles à ne pas enfreindre

1. **Rien de bloquant ni d'allouant dans le thread audio.** Pas de `NSLock`, pas de
   tableau Swift réaffecté, pas de `print`, pas de capture de `self` fort ou faible dans
   le bloc de rendu. Les coefficients d'EQ passent par un double tampon sans verrou
   (`ProcessorChain.liveSet`), la télémétrie par des `UnsafeMutablePointer`.
2. **Ne jamais versionner une banque de sons.** `.gitignore` les exclut. Elles font 1,5 Go
   et appartiennent à leurs auteurs.
3. **Les licences CC BY exigent une attribution.** Si vous ajoutez une banque, mettez
   `CREDITS.md` à jour et vérifiez la licence.
4. **Après toute modification des presets ou de la chaîne de traitement, relancez
   `make calibrate`.** Sinon les sons ne sont plus au même niveau.
5. **Ne touchez pas aux réglages de l'instrument de l'utilisateur.** Le seul message
   envoyé au clavier est CC 122 (Local Control), rétabli à la fermeture.
6. **Aucune marque en dur.** Les périphériques sont choisis par `DevicePicker`, jamais par
   un nom de fabricant.

## 5. Pièges déjà rencontrés — ne les redécouvrez pas

**La file d'événements de FluidSynth déborde.** `fluid_synth_*` appelé hors du thread
audio passe par un anneau d'événements vidé au rendu. Un arrêt d'urgence qui envoyait
5 messages sur 16 canaux, suivi d'un rechargement de preset, le saturait
(`Ringbuffer full, try increasing synth.polyphony`). N'écrivez que sur les canaux
réellement utilisés (`activeChannels`), et ne rechargez pas le preset dans `panic()`.

**La taille de tampon lue depuis un autre processus est fausse.**
`kAudioDevicePropertyBufferFrameSize` lu par un processus qui n'a pas ouvert le
périphérique renvoie la valeur par défaut (512), pas celle du client actif. La seule
vérité est le `frameCount` reçu par le bloc de rendu. Mesurez là.

**L'ordre compte pour fixer le tampon.** Ciblez le périphérique
(`auAudioUnit.setDeviceID`) *avant* d'écrire la taille de tampon : l'unité de sortie la
réinitialise quand on lui assigne un périphérique.

**`ImageRenderer` ne dessine pas le contenu d'un `ScrollView`**, ni les contrôles AppKit
(`Slider`, `TextField`, `Toggle` apparaissent en barres jaunes). D'où l'enveloppe
`Scroll` avec son drapeau `Flat.scrolls`, et les faders dessinés à la main. Ce n'est pas
un bug de l'app.

**CoreMIDI ne notifie que sur une run loop.** `MIDIClientCreateWithBlock` délivre les
changements de branchement sur la run loop du thread qui a créé le client. Créé depuis
une `Task.detached`, il n'en reçoit aucune : le piano allumé après le lancement n'est
jamais détecté, en silence. `startMIDI()` doit être appelé depuis le thread principal —
il y a une `assert` pour ça. Dans un outil en ligne de commande, `Thread.sleep` ne fait
pas tourner la run loop : utilisez `RunLoop.current.run(until:)` (voir le test 13).

**La carte son d'un piano n'apparaît qu'à son allumage.** Surveiller les ports MIDI ne
suffit pas : il faut aussi un écouteur sur `kAudioHardwarePropertyDevices`, sinon la
sortie reste sur les haut-parleurs du Mac alors que le piano est devenu disponible.

**Un périphérique audio qui vient d'être libéré accepte `engine.start()` sans erreur
mais ne fait jamais tourner le rendu.** Résultat : −180 dB partout, WAV vide, et ça ne
se répare jamais tout seul. Le MIDI et les accords continuent de fonctionner, ce qui
rend le diagnostic trompeur.

`startAudio()` compte désormais les appels du bloc de rendu après le démarrage, et
réessaie jusqu'à quatre fois si le compteur reste à zéro au bout de 600 ms. **Ne
supprimez pas cette boucle** : sans elle, quitter puis relancer l'application trop vite
donne une application muette. Si vous ajoutez un chemin qui démarre l'audio, faites-lui
passer la même vérification.

**L'étalonnage doit mesurer limiteur coupé.** Sinon toutes les crêtes butent au plafond
et le calcul est faux. `ProcessorChain.limiterEnabled = false` pendant la mesure.

**La sonie se juge sur l'attaque.** Mesurer le RMS sur toute la queue de réverbération
écrase un piano qui décroît face à un orgue tenu. La fenêtre est 0,05 s → 1,2 s.

**Nommez les notes par leur degré, pas par leur classe de hauteur.** La septième d'un C9
est un Si♭, pas un La♯. Voir `Spelling.noteName(rootPC:degree:actualPC:)`.

**Swift n'applique pas les valeurs par défaut aux clés absentes.** Ajouter un champ à
`RigConfig` ou à `Preset` rendait illisible la configuration de tous ceux qui mettaient
à jour : le décodage échouait, l'application retombait silencieusement sur les réglages
d'usine, et **l'étalonnage de l'utilisateur était perdu**. Les deux types ont maintenant
un `init(from:)` écrit à la main, qui utilise `decodeIfPresent` avec une valeur de repli.
**Si vous ajoutez un champ, ajoutez-y sa ligne**, et gardez le test de compatibilité de
`RecTest` au vert.

**Le pic le plus fort n'est pas la fondamentale.** Sur une note grave de piano, la
deuxième harmonique dépasse souvent la fondamentale : un détecteur naïf se trompe d'une
octave, et le test de transposition échoue par intermittence. `fundamentalFrequency`
redescend tant qu'une sous-harmonique porte une énergie significative. Utilisez-la, pas
`dominantFrequency`, dès qu'il s'agit d'une hauteur.

**Mesurez la bonne grandeur.** Deux tests ont dû être réécrits parce qu'ils
mesuraient un seuil arbitraire au lieu de la propriété réelle :

- *« aucune note bloquée »* comparait le niveau à un plancher fixe. Une queue de
  réverbération le franchissait parfois. Ce qui distingue une note bloquée d'une
  réverbération, c'est qu'elle **ne décroît pas** : comparez deux relevés espacés.
- *« l'égaliseur agit »* mesurait sur un piano. Ses aigus s'éteignent en une
  fraction de seconde, donc le résultat dépendait de l'instant du relevé. Mesurez
  sur un son **tenu** (un orgue), après établissement, en moyennant plusieurs
  relevés.

Un test instable qu'on « corrige » en desserrant son seuil ne teste plus rien.

**Vos cas de test peuvent être faux.** Trois fois pendant l'écriture de
`ChordTest`, le détecteur avait raison et le test avait tort (La-Do-Mi-Sol est Am7, pas
Do/La). Vérifiez la théorie avant de « corriger » le code.

## 6. Tâches courantes

**Ajouter un son** → `Library.all()` dans `Model.swift`, puis `make calibrate`, puis
`make test-audio` pour vérifier qu'il n'est pas muet.

**Ajouter une banque** → constante dans `Bank`, entrée dans `Bank.fallbacks` (pour une
installation allégée), ligne dans `scripts/fetch-soundbanks.sh` avec son empreinte
SHA-256, et crédit dans `CREDITS.md`.

**Changer l'interface** → modifiez, puis `make build && make preview`, puis *regardez les
PNG*. Les tailles rendues couvrent 1020, 1440 et 1728 points de large.

**Toucher au traitement du signal** → `make test-audio` mesure réellement l'effet de l'EQ
sur le signal en sortie (+12 dB demandés doivent donner ~+12 dB mesurés).

## 7. Ce qui est vérifié automatiquement

`make test` : 43 accords de référence, puis la validité des quatre formats d'export
(en-tête MIDI, MusicXML bien formé avec mesures exactement remplies, en-tête WAV).

`make test-audio` demande un périphérique de sortie. Le contrôle du son interne du
clavier est ignoré proprement si aucun piano n'est branché. La batterie ajoute, sur la
vraie sortie audio : les 31 sons produisent du son, la
transposition décale la hauteur au cent près, aucune note ne reste bloquée, les partages
clavier routent les bonnes zones, l'EQ agit, l'arrêt d'urgence fonctionne, il reste de la
marge avant saturation, une prise complète écrit ses quatre fichiers.

**N'annoncez jamais qu'une modification fonctionne sans avoir lancé ces tests.**

## 8. Limites connues, à ne pas présenter autrement

- La partition est une transcription quantifiée à la double croche, mains séparées à Do4,
  sans voix multiples. Elle est structurellement correcte, ce n'est pas une gravure.
- L'entrée micro traverse un rééchantillonnage par interpolation linéaire quand l'horloge
  d'entrée diffère de celle de sortie. Bon pour du renfort de voix, pas pour une prise
  studio.
- Les orgues et les nappes sont des émulations CC0, pas des instruments échantillonnés
  haut de gamme. Le piano, lui, l'est.
- Pas de simulation de cabine Leslie : « Gospel Leslie » est un désaccord plus un trémolo.
