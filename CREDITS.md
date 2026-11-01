# Crédits et licences des banques de sons

**Aucune banque de sons n'est contenue dans ce dépôt.** Elles sont téléchargées depuis
leurs sources officielles au moment de l'installation, par
`scripts/fetch-soundbanks.sh`, et restent la propriété de leurs auteurs.

## Attribution obligatoire

Deux banques sont sous **Creative Commons Attribution 3.0**. Si vous publiez ou diffusez
un enregistrement réalisé avec elles — en ligne, sur un disque, dans une vidéo — vous
devez créditer leur auteur.

| Banque | Auteur | Ce qu'il faut écrire |
|---|---|---|
| Salamander Grand Piano (Yamaha C5, 16 couches de vélocité) | Alexander Holm | « Piano : Salamander Grand Piano d'Alexander Holm, CC BY 3.0 » |
| YDP Grand Piano (Yamaha Disklavier Pro) | Zenph Studios, pour le projet FreePats | « Piano : YDP Grand Piano, Zenph Studios / FreePats, CC BY 3.0 » |

Les presets qui les utilisent : **Concert Grand, Soft Ballad, Stage Bright, Pop Piano,
Disklavier**, ainsi que toutes les **superpositions** et les **partages clavier**.

## Libres d'usage, sans attribution exigée

| Banque | Auteur | Licence |
|---|---|---|
| GeneralUser GS 2.0.3 | S. Christian Collins | Licence GeneralUser GS v2.0 — usage privé et commercial libre |
| MuseScore General | S. Christian Collins | MIT |
| Drawbar / Percussive / Rock / Church Organ Emulation | projet FreePats | CC0 (domaine public) |
| Synth Pad Choir, Sweep Pad, New Age, Synth Pad Bowed | projet FreePats | CC0 |
| Synth Strings 1 et 2 | projet FreePats | CC0 |
| FM Piano 1 et 2 | projet FreePats | CC0 |

Les textes de licence d'origine sont recopiés dans [docs/licences/](docs/licences/), et
chaque banque arrive avec le sien dans `Sounds/` après l'installation.

## Sources officielles

- **FreePats** — <https://freepats.zenvoid.org>
- **GeneralUser GS** — <https://schristiancollins.com/generaluser.php>
- **MuseScore General** — <https://musescore.org>

Merci de ne pas créer de lien direct vers les fichiers de S. Christian Collins depuis un
autre site : il le demande explicitement dans sa licence.

## Moteur de son

**FluidSynth**, sous LGPL 2.1, installé séparément par Homebrew (`brew install
fluid-synth`). Il n'est ni modifié ni redistribué ici. <https://www.fluidsynth.org>

## Documentation de l'instrument

Les PDF Yamaha du YDP-145 (mode d'emploi, référence MIDI) ne sont pas redistribués : ils
sont disponibles sur le site de Yamaha. Le projet ne dépend d'aucun document propriétaire.

## Le langage visuel de l'interface

Aucun code n'est repris, mais la méthode et les règles de l'interface viennent de deux
ensembles de notes de design publiés :

- **unslop**, de Damir Sokolovsky ([@heydamir](https://x.com/heydamir)), sous
  **CC BY 4.0** — <https://github.com/heydamir/unslop>. L'audit des signes, les passes
  dans l'ordre, et les valeurs de départ (rampe de gris, échelle de tailles, grille de 4).
- **stageshow**, de Benji Taylor — <https://github.com/arm1383/stageshow-skills> et
  <https://benji.org/stageshow>. Les règles de cadrage, de proportion et de retenue.

Ces règles sont écrites, telles qu'appliquées ici, dans [AGENTS.md](AGENTS.md) §4 bis.

## Ce que le projet ne prétend pas être

Les bibliothèques Nord sont dans un format propriétaire et ne fonctionnent que sur du
matériel Nord. Il n'existe pas de plug-in Nord pour Mac. Les presets de ce projet visent
une **palette de scène comparable**, jamais les sons Nord eux-mêmes.
