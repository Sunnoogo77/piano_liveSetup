# Architecture

## Le chemin du son

```
Clavier MIDI ──USB──▶ CoreMIDI ──▶ Engine.handleMIDI
                                      │  transposition, octave, courbe de vélocité,
                                      │  partage clavier, routage des couches
                                      ▼
                            FluidSynth (jusqu'à 3 canaux)
                                      │
                                      ▼
   bloc de rendu d'AVAudioSourceNode, 128 échantillons
      fluid_synth_write_float
      ProcessorChain : saturation ▸ EQ 7 bandes ▸ trémolo ▸ compresseur ▸ gain
      MicInput.mix   : entrée micro rééchantillonnée, son propre EQ
      limiteur général à −0,5 dB
      SpectrumTap    : copie pour l'analyseur
      AudioFileRecorder : copie pour l'enregistrement WAV
                                      │
                                      ▼
                  périphérique de sortie choisi (souvent le piano lui-même)
```

Trois threads se partagent le travail :

| Thread | Ce qu'il fait | Contraintes |
|---|---|---|
| **audio** | le bloc de rendu ci-dessus | aucune allocation, aucun verrou, aucun ARC |
| **MIDI** | `handleMIDI`, appelé par CoreMIDI | un `NSLock` court y est toléré |
| **principal** | interface, FFT d'affichage, écriture des fichiers | tout le reste |

Les données qui traversent ces frontières passent par :
- un **double tampon sans verrou** pour les coefficients d'EQ (`ProcessorChain.liveSet`) ;
- des **`UnsafeMutablePointer`** pour la télémétrie (crêtes, horodatage MIDI) ;
- des **tampons circulaires** à un écrivain et un lecteur pour l'analyseur,
  l'enregistrement audio et l'entrée micro.

## Pourquoi FluidSynth

Il lit SF2 et SF3, il est sous LGPL, il est disponible dans Homebrew, et surtout il est
l'un des rares moteurs à implémenter complètement la spécification SoundFont — ce
qu'exige GeneralUser GS 2.0. Les réglages de réverbération et de chorus sont ceux
recommandés par l'auteur de cette banque.

Il est utilisé en **rendu manuel** : aucun pilote audio de FluidSynth n'est ouvert. Son
flux est tiré par le bloc de rendu d'`AVAudioEngine`, ce qui laisse le contrôle du
périphérique et de la taille de tampon à l'application.

## Le démarrage de la sortie

Un périphérique que vient de relâcher une autre application accepte le démarrage sans
erreur mais ne lance pas son rendu. `startAudio()` compte donc les appels du bloc de
rendu : si le compteur reste à zéro au bout de 600 ms, il arrête, attend 300 ms et
recommence, jusqu'à quatre fois. C'est ce qui évite une application muette quand on
quitte et relance dans la foulée, ou quand on change de sortie en cours de jeu.

## Les presets

Un preset est une liste de **couches** (trois au maximum, une par canal FluidSynth), plus
une chaîne de traitement. Une couche porte sa banque, son programme, son volume, son
panoramique, son décalage en demi-tons, son étendue de clavier et son étendue de
vélocité. C'est ce qui donne les superpositions et les partages avec le même mécanisme.

Si une banque n'est pas installée, `Engine.resolve` suit les équivalences déclarées dans
`Bank.fallbacks` — soit un fichier équivalent gardant le même numéro de programme, soit
un programme précis d'une banque générale. Une installation allégée reste donc jouable.

## L'étalonnage

`Sources/Tools/Calibrate` rend chaque preset hors ligne avec sa chaîne complète, mesure la
crête réelle (limiteur coupé) et le niveau RMS **sur l'attaque** (0,05 à 1,2 s), puis
calcule pour chacun le gain qui aligne tous les sons sur la même sonie tout en gardant
6 dB de marge sous le plafond. Les gains sont écrits dans `Config/setup.json`.

## L'analyseur

FFT de 2048 points avec fenêtre de Hann, via `vDSP`, répartie sur 128 bandes
logarithmiques de 20 Hz à 20 kHz, avec montée immédiate et descente lissée plus maintien
de crête. Le même objet expose `dominantFrequency` et `energyDB`, qui servent aux tests
automatiques à vérifier la transposition et l'effet de l'égaliseur.
