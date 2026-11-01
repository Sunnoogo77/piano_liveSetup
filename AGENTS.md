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
  Mic.swift         entrée micro via AudioDeviceIOProc, rééchantillonnage asservi,
                    et MicPermission (autorisation macOS)
  Update.swift      SemVer et interrogation des étiquettes du dépôt
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
  remote.html       structure de la page de commande (les écrans)
  remote.css        sa feuille de style
  remote.js         sa logique : flux SSE, rendu, analyseur en canvas
                    Les trois sont assemblés en un seul fichier par scripts/gen-web.py,
                    qui y ajoute les icônes en base64 et écrit build/gen/WebAssets.swift.
                    Modifiez ces trois fichiers, jamais le fichier généré.
Sources/Tools/      outils en ligne de commande, un dossier = une cible
                    MakeIcon fabrique l'icône de l'application et celles de la page web
build/gen/          engendré à chaque construction, jamais versionné
  Version.swift     AppInfo : version, commit, date, dépôt (déduit du remote Git)
  WebAssets.swift   la page de commande et ses icônes
```

### Comment l'état voyage jusqu'à la tablette

Deux chemins, à ne pas confondre :

| | Quoi | Quand |
|---|---|---|
| `/api/stream` (SSE) | niveaux, spectre, notes tenues, accord, chrono | 24 fois par seconde, poussé |
| `/api/state` | sons, égaliseur, prises, micro, version | seulement quand ça change |

`RigModel.publishRemote()` envoie le premier à chaque tic. `refreshRemoteSlow()`
reconstruit le second, le compare à l'envoi précédent et n'incrémente `rev` que s'il
diffère ; la page voit `rev` changer dans le flux et relit `/api/state` d'elle-même.
Si vous ajoutez un réglage visible à distance, mettez-le dans le **lent**, et ajoutez sa
commande dans `handleRemote`.

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
7. **Ne faites jamais installer une mise à jour par l'application elle-même.** Elle dit
   qu'une version existe et donne la commande ; c'est l'utilisateur qui lance
   `scripts/update.sh`. Un rig de scène ne se met pas à jour tout seul pendant un concert.
8. **Un réglage ajouté à `RigConfig` se décode avec `decodeIfPresent` et une valeur par
   défaut**, dans l'`init(from:)` écrit à la main. Swift n'applique pas les valeurs par
   défaut aux clés absentes : un oubli efface la configuration de tous ceux qui mettent
   à jour. `rectest` le vérifie.
9. **Le langage visuel est écrit plus bas et il n'est pas négociable au cas par cas.**
   Une seule couleur allumée, des étiquettes en casse normale, deux graisses, la grille
   de 4. Une exception ajoutée « juste pour cet écran » devient la règle le mois suivant.
10. **L'application et la page disent la même chose avec les mêmes mots.** Un panneau qui
   s'appelle « Effets » sur le Mac ne s'appelle pas « Couleur » sur la tablette, et un
   pourcentage s'arrondit des deux côtés. Les deux interfaces sont le même outil.

## 4 bis. Le langage visuel

La direction, en cinq lignes, dont tout le reste découle :

- **Produit** — un rig de piano de scène : un clavier MIDI branché à un Mac devient un
  instrument prêt à jouer, pour quelqu'un qui monte sur scène.
- **Caractère** — posé, exact, chaud sous la main.
- **Monde** — les consoles et les claviers : panneaux noirs mats, sérigraphie claire,
  une seule couleur allumée dans le noir.
- **Moments** — l'analyseur et sa courbe d'égalisation ; le clavier 88 touches avec les
  notes tenues. Ce sont les deux seuls endroits riches de l'outil.
- **Signature** — les degrés sous les notes de l'accord (`Do¹ Sol⁵ Mi³ Si♭⁷`). Aucun
  autre produit n'a ça. Gardez-le, et ne le mettez nulle part ailleurs.

Les règles qui en sortent :

- **Une rampe de gris froids, et rien d'autre.** Les quatre fonds (`Tone.bg0…bg3`,
  `--bg0…--bg4`) sont des marches : la profondeur vient d'une marche et d'un filet d'un
  pixel, jamais d'une ombre portée — sur fond sombre, une ombre ne se voit pas, elle
  salit.
- **Un seul accent, le sarcelle, et il veut dire « c'est ceci qui est actif ».** Les
  couleurs restantes (`ok`, `warn`, `hot`) portent une mesure : un niveau, un témoin
  d'enregistrement, une alerte. Jamais une famille de sons, jamais un fader, jamais une
  décoration. Un graphique n'a qu'un accent : la courbe qu'on règle le porte, le spectre
  derrière est un gris.
- **Trois rôles de texte seulement** (`txt0`, `txt1`, `txt2`). Le troisième reste
  au-dessus de 4,5:1 sur un panneau : sur scène la lumière est mauvaise.
- **Casse normale partout.** Pas de capitales espacées — `Caption` ne transforme plus
  rien. Une console est sérigraphiée en capitales parce que la peinture le permet ; un
  écran n'a pas cette excuse, et les capitales espacées se lisent moins vite.
- **Deux graisses, `.regular` et `.medium`.** La hiérarchie vient de la taille et de la
  couleur. Tailles : 10 (graduation d'axe), 11, 12, 13, 15, 18, 22, 28, puis l'affichage.
  Pas de taille fractionnaire.
- **Les chiffres.** `Font.value` (chasse fixe) pour une valeur mesurée — décibels,
  hertz, pourcentages : elles s'alignent en colonne. `Font.display` (famille de
  l'interface, chiffres à largeur fixe) pour un grand nombre : la chasse fixe y donne un
  zéro barré qui saute aux yeux.
- **La grille de 4.** Marges, espacements, hauteurs fixes. Un pas de 2 est toléré à
  l'intérieur d'une petite commande, nulle part ailleurs. Rayons : 6 pastille,
  10 commande, 14 panneau.
- **Rien ne tourne en boucle.** Une animation sans fin dans un coin de l'écran use l'œil
  pendant un concert. Les seules transitions sont un survol (120 ms) et un changement de
  valeur. Le point rouge d'un enregistrement en cours est l'exception : là, il se passe
  vraiment quelque chose.
- **Une information se dit une fois par écran.** Le bandeau cache la transposition quand
  l'écran de jeu l'affiche déjà en grand — et seulement dans ce cas, sinon elle
  disparaîtrait des deux endroits.
- **Un bouton ne coupe pas son mot en deux.** S'il ne tient pas, c'est la mise en page
  qu'il faut revoir : en fenêtre étroite, les commandes passent l'une sous l'autre, et
  l'égaliseur montre les numéros des bandes au lieu de leurs noms.

- **Trois formes d'écran, pas trois largeurs.** Un téléphone debout : onglets en bas,
  sous le pouce. Un écran large : barre latérale étiquetée. Un écran couché et bas — le
  téléphone posé sur le pupitre — où la hauteur est la ressource rare : la barre
  d'onglets devient une colonne d'icônes, la barre du haut tient sur une ligne, et les
  quatre-vingt-dix points récupérés vont à la courbe et au clavier. Dans les deux
  dernières, la page ne défile plus en entier : la barre du haut tient, et c'est la zone
  des écrans qui défile. C'est la forme d'une console.
- **Ce qui cède, c'est le grand élément, jamais la commande.** Dans une colonne de
  hauteur fixe, la courbe se resserre ; la rampe des bandes et les faders gardent leur
  taille — ce sont eux qu'on cherche du doigt. Et quand un panneau ne remplit pas sa
  colonne, l'espace reste **en bas**, sous le dernier panneau : deux panneaux écartés
  aux deux bords se lisent plus mal, pas mieux.

Ce langage vient des deux dépôts que l'utilisateur a indiqués :
[unslop](https://github.com/heydamir/unslop) de Damir Sokolovsky (CC BY 4.0) pour la
méthode — l'audit, puis les passes dans l'ordre : espacement, couleur, icônes, texte,
typographie, mise en page, détails, images, mouvement — et
[stageshow](https://github.com/arm1383/stageshow-skills) de Benji Taylor pour les règles
de cadrage et de proportion. Relisez-les avant une refonte, pas avant une retouche.

## 5. Pièges déjà rencontrés — ne les redécouvrez pas

**La bibliothèque de sons est enregistrée dans `setup.json`.** Ajouter un preset à
`Library.all()` ne suffit donc pas : une installation existante relirait l'ancienne liste
et ne verrait rien de neuf. `RigConfig.merge` règle ça au chargement — la définition
(couches, famille, textes, courbe de vélocité) vient du code, les réglages (égaliseur,
effets, niveaux, gain d'étalonnage) viennent du disque, et un son inconnu de la
bibliothèque est conservé à la fin. Un son qui vient d'arriver prend le gain médian des
autres jusqu'au prochain `make calibrate` : à 1, il sortirait beaucoup plus fort que le
reste, en plein concert.

**L'étalonnage ne doit pas se laisser entraîner par un seul son.** La sonie commune était
celle du son le plus contraignant ; une kalimba — attaque sèche, crête haute, sonie très
basse — a tiré toute la bibliothèque douze décibels plus bas le jour où elle est arrivée.
La cible se prend maintenant au huitième le plus bas, et chaque son est bridé par sa
propre crête s'il ne peut pas l'atteindre sans écrêter. Regardez toujours la ligne
« sonie cible » avant et après : c'est elle qui dit si la bibliothèque entière a bougé.

**`scripts/calibrate.sh` et `scripts/test.sh` ne reconstruisaient que si l'outil
manquait.** Cinq minutes d'étalonnage sur un binaire périmé n'échouent pas : elles
écrivent simplement les mauvais gains, sans rien dire. Les deux scripts comparent
désormais les dates des sources.

**Un voile dessiné par-dessus doit savoir quand ne pas l'être.** `KeyboardView.splitAt`
est un `Int?` : la zone de main gauche n'existe que pour un son partagé. Tant que le
voile était dessiné *sous* des touches opaques, un mauvais point de partage ne se voyait
pas ; le jour où il est passé au-dessus, la moitié gauche de tous les claviers s'est
assombrie. Le `0` envoyé à la page de commande veut dire la même chose : rien à
assombrir.

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

**Le premier client CoreMIDI du processus confisque la livraison des notifications.**
C'est le piège le plus coûteux de ce projet, et il ne ressemble à rien de ce qu'on
imagine en le lisant.

CoreMIDI accroche la livraison des changements de configuration à la run loop du thread
qui crée le client — et cette livraison est **par processus**, pas par client. Si un
autre morceau de code (FluidSynth, un framework audio) crée un client avant nous sur un
thread qui ne fait jamais tourner sa run loop, **plus aucun client du processus ne reçoit
quoi que ce soit**. Pire : `MIDIGetNumberOfSources()` est rafraîchi par ce même canal.
La liste des appareils reste donc figée sur ce qu'elle était au lancement, pour toute la
séance, sans la moindre erreur. Un clavier allumé après coup n'existe tout simplement
pas, et un balayage forcé n'y change rien.

Vérifié sur un cas minimal : un « squatteur » — un client créé en premier sur un thread
endormi — suffit à bloquer la détection d'un second client pourtant parfaitement posé sur
une run loop vivante. Sans lui, tout marche.

D'où la règle, et elle n'est pas négociable :

1. `RigModel.boot()` appelle `engine.startMIDI()` **en tout premier**, avant le
   chargement des banques et avant l'ouverture de l'audio.
2. `startMIDI()` ouvre un thread à nous (`piano.midi`), y crée le client, et fait
   tourner sa run loop indéfiniment (`RunLoop.current.add(NSMachPort(), …)` puis une
   boucle `run(mode:before:)`). On ne dépend plus de la run loop de personne.
3. Comme le client naît avant l'audio, `followKeyboardIfPossible()` est gardé par
   `audioReady` : sinon une notification précoce ferait basculer la sortie pendant que
   `startAudio()` tourne sur un autre thread.
4. CoreMIDI refuse parfois un client dans les toutes premières millisecondes :
   `startMIDI()` réessaie huit fois à 150 ms d'intervalle.

Pour vérifier sans débrancher le piano : un processus séparé crée une source MIDI
virtuelle (`MIDISourceCreate`), et l'application doit la faire apparaître dans
`keyboards` en une seconde ou deux. Le compteur `midiEvents` de `/api/state`, affiché
aussi dans l'onglet Périphériques, dit combien de changements ont été reçus : **s'il
reste à zéro quand on branche quelque chose, c'est que la livraison est confisquée.**

**Un périphérique audio USB peut ne jamais répondre, et `setDeviceID` n'a pas de délai
d'attente.** Un piano éteint à moitié, ou dont le câble a été retiré au mauvais moment,
reste listé par CoreAudio mais bloque `AUHALOutputUnit.setDeviceID` indéfiniment, dans
`mach_msg`. Appelé depuis le thread principal — c'était le cas de
`followKeyboardIfPossible()` — il gèle toute l'application, écran compris. D'où
`switchAudioDevice(named:completion:)`, qui fait la bascule sur une file à part, et le
chien de garde de `RigModel.armAudioWatchdog()` qui, au bout de neuf secondes, dit à
l'écran de chargement ce qui se passe au lieu de laisser tourner l'anneau indéfiniment.

**Le micro s'ouvre, démarre sans erreur, et n'envoie que des zéros.** Il manquait
`NSMicrophoneUsageDescription` dans `resources/Info.plist`. Sans cette clé macOS ne
demande jamais l'autorisation : `AudioDeviceStart` renvoie `noErr`, le bloc d'entrée est
appelé, et tous les échantillons valent 0. Aucune erreur nulle part. Il faut **la clé
dans le plist** *et* une demande explicite (`MicPermission.request`, qui passe par
`AVCaptureDevice`). `RigModel.watchMic()` surveille en plus le niveau d'entrée et le dit
au bout de 2,5 s de zéro absolu, plutôt que de laisser croire que tout va bien.

**L'analyseur n'est calculé que par celui qui le regarde.** `SpectrumTap.analyse()` est
appelé depuis `AnalyzerView.draw`. Si l'écran Égaliseur du Mac n'est pas affiché,
personne ne l'appelle et `bandsDB` reste plat — la tablette recevait un spectre à zéro.
`publishRemote()` le réveille quand un appareil distant est connecté et que l'écran
Égaliseur n'est pas au premier plan. Ne l'appelez pas deux fois par image : le lissage
et la retombée des crêtes en seraient doublés.

**Une tablette qui ferme l'onglet ne prévient pas.** Une connexion SSE abandonnée reste
`.ready` côté serveur : rien ne revient, et l'envoi suivant seulement échouera. D'où la
lecture ouverte en permanence sur chaque flux (`RemoteServer.drain`), uniquement pour
voir arriver la fin de flux TCP et libérer tout de suite.

**Une grille de hauteur fixe laisse quand même sa rangée grandir.** `height:100%` sur la
grille ne suffit pas : sans `grid-template-rows` explicite, la rangée implicite se
dimensionne sur son contenu et déborde. La bibliothèque de 51 sons sortait ainsi de son
cadre. Il faut `grid-template-rows:minmax(0,1fr)` — et `min-height:0` sur l'enfant, sinon
sa taille minimale automatique l'empêche de se resserrer.

**`align-items:start` empêche une colonne de prendre la hauteur de son cadre.** Posé pour
que deux colonnes inégales ne s'alignent pas sur la plus longue, il annule l'étirement :
la colonne se dimensionne sur son contenu et déborde au lieu de défiler. Si une colonne
doit remplir la hauteur, remettez `align-items:stretch` et ne calez que le panneau qui
doit rester en haut (`align-self:start`).

**La largeur de la fenêtre ne dit pas la largeur d'une colonne.** La rampe des sept bandes
tenait ses noms à 844 points de fenêtre, mais elle n'en avait que 462 : « Coupe-haut » se
coupait en deux, ce que le langage visuel interdit. C'est une requête de conteneur
(`@container`) qui décide, sur `.eqmain`, pas une `@media`.

**Deux `span` côte à côte restent sur la même ligne**, et leur `margin-top` ne fait rien.
Le sous-titre du bouton d'enregistrement s'affichait à la suite du titre depuis le début.

**`vh` n'est pas la hauteur visible sur un téléphone.** Les barres du navigateur sont
comptées dedans. Toutes les hauteurs d'écran sont écrites deux fois — `vh` puis `dvh` —
pour que le navigateur qui ignore `dvh` garde la première.

**`timeout` n'existe pas sur macOS.** Dans un script de test, `curl --max-time` fait le
travail ; `timeout 4 curl …` échoue avec « command not found » et laisse un fichier vide
qui ressemble à un serveur muet.

## 6. Tâches courantes

**Ajouter un son** → `Library.all()` dans `Model.swift`, puis `make calibrate`, puis
`make test-audio` pour vérifier qu'il n'est pas muet.

**Ajouter une banque** → constante dans `Bank`, entrée dans `Bank.fallbacks` (pour une
installation allégée), ligne dans `scripts/fetch-soundbanks.sh` avec son empreinte
SHA-256, et crédit dans `CREDITS.md`.

**Changer l'interface** → relisez « Le langage visuel » (§4 bis), modifiez, puis
`make build && make preview`, puis *regardez les PNG*. Les tailles rendues couvrent 1020,
1440 et 1728 points de large. Le rendu le plus étroit, `ui-min.png`, est celui qui casse :
c'est là qu'un bouton coupe son mot et qu'un panneau sort de l'écran.

**Toucher au traitement du signal** → `make test-audio` mesure réellement l'effet de l'EQ
sur le signal en sortie (+12 dB demandés doivent donner ~+12 dB mesurés).

**Changer la page de commande** → modifiez `Sources/Web/remote.{html,css,js}`, puis
`make build`. Pour la *voir* : lancez l'application, activez le contrôle à distance, et
ouvrez l'adresse dans un navigateur que vous redimensionnez (1180×820 pour un iPad en
paysage, 375×812 pour un téléphone). `build/bin/remotetest` vérifie que la page est
servie entière, que les icônes et le manifeste répondent, que le flux pousse des trames
distinctes et que chaque commande arrive.

**Ajouter une commande à distance** → un `case` dans `RigModel.handleRemote`, le réglage
correspondant dans `refreshRemoteSlow` (état lent) ou `publishRemote` (état rapide), le
contrôle dans `remote.html` / `remote.js`, et une ligne dans la liste du test.

**Publier une version** → voir [docs/UPDATING.md](docs/UPDATING.md), section « Publier une
version ». En résumé : `VERSION`, `CHANGELOG.md`, tests, commit, étiquette `vX.Y.Z`,
`git push --tags`. Sans étiquette, aucune copie installée ne saura qu'il y a du nouveau.

**Mettre à jour une installation** → `./scripts/update.sh`. S'il s'arrête parce que le
dépôt a des modifications locales ou un historique divergé, **ne forcez pas** : montrez
le message à l'utilisateur, il contient les deux commandes au choix. Si la construction
ou les tests échouent, l'application en place n'a pas été remplacée — dites-le, et ne
copiez pas le bundle à la main pour « finir le travail ».

## 7. Ce qui est vérifié automatiquement

`make test` : 43 accords de référence, puis la validité des quatre formats d'export
(en-tête MIDI, MusicXML bien formé avec mesures exactement remplies, en-tête WAV).

`make test-audio` demande un périphérique de sortie. Le contrôle du son interne du
clavier est ignoré proprement si aucun piano n'est branché. La batterie ajoute, sur la
vraie sortie audio : les 51 sons produisent du son, la
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
