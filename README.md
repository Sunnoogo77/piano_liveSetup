<div align="center">

# Piano Live Setup

**Votre Mac devient l'expandeur de n'importe quel piano numérique branché en USB.**

31 sons de scène · égaliseur 7 bandes sur analyseur de spectre · détection d'accords
enregistrement audio, MIDI et partition · entrée micro · **2,9 ms de latence**

*A macOS live rig for any USB MIDI piano.* **[Read this in English →](README.en.md)**

![L'écran de jeu](docs/images/tab-play.png)

</div>

---

## Installation

```bash
git clone https://github.com/Sunnoogo77/piano_liveSetup.git
cd piano_liveSetup
./install.sh
```

C'est tout. Le script vérifie le Mac, installe ce qui manque, télécharge les banques de
sons depuis leurs sources officielles, compile, étalonne les 31 sons et pose
l'application dans `/Applications`.

Peu de place sur le disque ? `./install.sh --light` saute les deux grands pianos
échantillonnés (250 Mo au lieu de 1,5 Go). Les presets concernés basculent
automatiquement sur une équivalence : rien ne devient muet.

| | |
|---|---|
| **Il vous faut** | un Mac sous macOS 14 ou plus récent, un piano ou clavier MIDI avec une prise USB, et un câble USB |
| **L'installateur pose** | les outils Xcode en ligne de commande (si absents), Homebrew (si absent, après accord), FluidSynth, et les banques de sons |
| **Ça prend** | 5 à 10 minutes, selon la connexion |

---

## Ce que ça fait

### Un seul câble, et rien à configurer

Branchez le piano en USB. Il est reconnu **quelle que soit la marque** — Yamaha, Korg,
Roland, Casio, Nord…

Vous pouvez ouvrir l'application piano éteint : elle affiche clairement qu'elle attend
un clavier, et tout le reste reste utilisable. **Dès que vous allumez l'instrument, elle
le prend en main toute seule** : connexion MIDI, son interne coupé, et la sortie audio
bascule sur le piano s'il sait recevoir le son. Rien à cliquer.

Beaucoup de pianos numériques se présentent au Mac à la fois comme port MIDI **et** comme
carte son, sous le même nom. Quand l'application voit ce cas, elle y envoie le son :
vous jouez sur le clavier, vous entendez le Mac **dans les haut-parleurs du piano**, avec
le même câble. Sinon elle prend la sortie par défaut, et vous pouvez en changer à tout
moment.

Elle coupe aussi le son interne du clavier (CC 122, un message MIDI standard) pour que
vous n'entendiez pas deux hauteurs quand vous transposez — et le rétablit en se fermant.
Aucun réglage n'est modifié sur l'instrument.

### 31 sons, étalonnés

Six pianos acoustiques, six électriques, cinq orgues, six nappes et cordes, six
superpositions, deux partages clavier. Le piano principal est un **Yamaha C5 à 16 couches
de vélocité**.

Les variantes ne sont pas des doublons : chacune a son égaliseur, sa saturation, son
trémolo, sa compression et sa courbe de vélocité — c'est comme ça qu'un Nord fabrique ses
sons. Tous sont alignés à la même sonie, mesurée par rendu hors ligne, avec 6 dB de marge
avant saturation.

### Six écrans

| | |
|---|---|
| **Jeu** | l'écran de scène : accord joué, hauteur, clavier, niveaux |
| **Égaliseur** | analyseur de spectre temps réel, EQ 7 bandes à points déplaçables, effets |
| **Accords** | l'accord en grand, sa fiabilité, les notes et leurs degrés, l'historique |
| **Clavier** | les 88 touches, colorées par main |
| **Enregistrer** | la prise en cours et toutes les prises passées |
| **Périphériques** | clavier MIDI, sortie audio, entrée micro et son égaliseur |

<div align="center">

![En attente d'un clavier](docs/images/tab-play-waiting.png)
*Piano éteint : l'application le dit clairement et reste utilisable. Allumez-le, elle le prend en main toute seule.*

![Égaliseur](docs/images/tab-eq.png)
*L'égaliseur : la courbe se pose sur le spectre, les sept points se tirent à la souris.*

</div>

### Les accords, nommés correctement

Triades, septièmes, sixtes, neuvièmes, onzièmes, treizièmes, altérés, suspendus,
renversements en slash — et les voicings de pianiste avec quinte omise.

Les notes sont nommées **selon leur fonction dans l'accord**, pas selon leur classe de
hauteur : un C9 affiche *Do Mi Sol Si♭ Ré*, un E7 affiche *Mi Sol♯ Si Ré*.
43 accords de référence sont vérifiés automatiquement.

### Enregistrer en quatre formats

Un bouton, et chaque prise écrit :

| Fichier | Ce que c'est |
|---|---|
| `audio.wav` | le son exact qui sort, 24 bits stéréo, effets compris |
| `performance.mid` | MIDI standard, timing exact, **rejouable sur le piano** |
| `partition.musicxml` | la partition, deux portées, pour MuseScore, Dorico, Finale… |
| `accords.txt` | la grille d'accords horodatée |

### Un micro, à l'occasion

Entrée micro avec gain, compresseur et un **égaliseur 7 bandes indépendant** de celui du
piano. Le renvoi dans la sortie est coupé par défaut : un micro ouvert près des
haut-parleurs siffle.

---

## Les commandes

| | |
|---|---|
| `./install.sh` | installation complète |
| `./install.sh --light` | sans les grands pianos |
| `make build` | compiler seulement |
| `make test` | tests sans matériel (accords, formats d'export) |
| `make test-audio` | tous les tests, y compris ceux qui jouent du son |
| `make calibrate` | recalculer l'équilibre des sons après modification |
| `make preview` | rendre l'interface en PNG, sans ouvrir l'app |
| `make portable` | vérifier que le cœur compile sans framework Apple |
| `./scripts/uninstall.sh` | retirer l'application |

Raccourcis dans l'app : `←` `→` transposer · `0` remise à zéro · `[` `]` octave ·
`↑` `↓` son précédent/suivant · `P` arrêt des notes · `R` enregistrer ·
`L` son interne du clavier · `⌘1`…`⌘6` changer d'écran.

---

## Comment c'est fait

- **Swift + SwiftUI**, sans dépendance de paquet. Un seul binaire.
- **FluidSynth** (LGPL) rend les banques SF2/SF3, appelé depuis le bloc de rendu de
  `AVAudioEngine` ciblé sur le périphérique choisi, à 128 échantillons.
- Le traitement — saturation, EQ 7 bandes en biquads, trémolo, compresseur, limiteur —
  est écrit à la main, sans allocation ni verrou dans le thread audio.
- L'analyseur fait une FFT de 2048 points avec `vDSP`, répartie sur 128 bandes
  logarithmiques.

`Sources/Core/` — modèle, traitement du signal, accords, enregistrement — **compile sans
aucun framework Apple**, vérifié à chaque passage de la CI. L'analyseur a deux
implémentations, celle d'Accelerate et une FFT en Swift pur, qui donnent les mêmes
mesures.

Les détails sont dans [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Ce que j'ai appris en
le construisant — les pièges — est dans [AGENTS.md](AGENTS.md).

### Et sur iPad, Windows, Linux ?

Rien n'est porté à ce jour, et je ne vais pas prétendre le contraire. Mais le cœur est
déjà portable, et [docs/PORTING.md](docs/PORTING.md) détaille ce que chaque système
demanderait — avec le chemin qui me semble le plus rentable : un moteur sans interface
piloté par une page web, ce qui donnerait d'un coup Linux, Windows, **et le contrôle
depuis un iPad pendant que le Mac fait le son**.

---

## Vous travaillez avec un agent IA ?

Le dépôt est écrit pour ça. [AGENTS.md](AGENTS.md) contient la carte du code, les
commandes, les règles à ne pas enfreindre et les pièges déjà rencontrés.

Pour étendre le projet — un son, un effet, un écran, une banque —
[docs/EXTENDING.md](docs/EXTENDING.md) donne la recette de chaque cas.

Donnez simplement ceci à votre agent :

> Clone https://github.com/Sunnoogo77/piano_liveSetup, lis AGENTS.md, installe-le sur ce
> Mac en suivant le README, puis vérifie que tout fonctionne avec `make test`.

---

## Licences

Le code est sous **MIT** — faites-en ce que vous voulez.

Les banques de sons ne sont **pas** dans ce dépôt : elles sont téléchargées chez leurs
auteurs à l'installation, chacune avec sa licence. Deux d'entre elles demandent une
attribution si vous publiez un enregistrement. Tout est détaillé dans
[CREDITS.md](CREDITS.md) — merci de le lire avant de diffuser votre musique.

FluidSynth est sous LGPL et reste un paquet Homebrew séparé.
