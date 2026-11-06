# Journal des changements

Les versions suivent [SemVer](https://semver.org/lang/fr/) : `MAJEUR.MINEUR.CORRECTIF`.

- **MAJEUR** — il faut refaire quelque chose à la main (réglages, banques, matériel).
- **MINEUR** — nouvelles fonctions, vos réglages sont conservés.
- **CORRECTIF** — corrections seulement.

Pour passer à la dernière version : `./scripts/update.sh`
(détails dans [docs/UPDATING.md](docs/UPDATING.md)).

---

## 1.4.2 — 2026-11-06

Préparer une sortie qu'on ne connaît pas encore : une chapelle, un piano d'une
autre marque, une interface USB vers une table de mixage.

### Corrigé
- **Une interface qui refuse 128 échantillons ne reste plus muette.**
  Beaucoup d'appareils — interfaces USB, sorties HDMI — acceptent sans broncher
  une taille de tampon qu'ils ne savent pas tenir, puis ne font jamais tourner
  le rendu : aucune erreur, aucun son. L'application demande maintenant à
  l'appareil la plage qu'il accepte (`kAudioDevicePropertyBufferFrameSizeRange`)
  et s'y cale ; au deuxième essai, elle lui rend la taille qu'il avait. Quand
  elle a dû changer la valeur, elle l'écrit dans l'onglet Périphériques.
- **Une sortie qui ne démarre pas ne coupe plus le son.** L'application revient
  à celle qui marchait et dit pourquoi, au lieu de laisser le rig muet avec le
  nom du périphérique fautif enregistré pour le prochain lancement.

### Modifié
- Le README ne dit plus que l'application « coupe » le son interne du clavier,
  mais qu'elle le **demande** — et renvoie au réglage *Local Control* de
  l'instrument pour ceux qui ne reçoivent pas le message.
- Le guide de dépannage gagne une entrée : « Je choisis une interface USB et il
  n'y a pas de son ».

### Vérifié
- `make test-audio` passe en entier pour la première fois **avec un clavier
  branché** : le test 9, « Pilotage du son interne du piano », ne saute plus.

---

## 1.4.1 — 2026-11-06

Trois corrections trouvées en branchant un clavier d'une autre marque qu'au
premier jour : une sortie audio qui n'en était pas une, une destination MIDI
choisie au hasard, et une pastille qui promettait plus qu'elle ne savait.

### Corrigé
- **Une sortie audio fantôme disparaît de la liste.** macOS fabrique pour son
  propre compte un agrégat privé — « CADefaultDeviceAggregate-… » — dès qu'une
  application ouvre la sortie par défaut. Il n'est visible que dans le processus
  qui l'a provoqué et ne mène qu'à un appareil déjà présent dans la liste : le
  choisir coupait le son. Il est écarté, à sa marque officielle (la clé
  « private » de sa composition), pas à son nom. Un agrégat créé par
  l'utilisateur dans Configuration audio et MIDI reste proposé.
- **La destination MIDI est celle du même appareil que le clavier, pas celle du
  même nom.** Beaucoup d'instruments nomment leurs deux ports différemment — par
  exemple « … KEYBOARD » pour ce que les touches envoient et « … SOUND » pour
  leur générateur interne. L'ancienne recherche par nom ne trouvait rien et se
  rabattait sur la première destination venue : avec deux instruments branchés,
  elle coupait le son du mauvais.
- **La pastille dit « Coupure demandée » et non « Son du piano coupé ».** Le
  CC 122 part, mais l'instrument n'accuse pas réception et tous ne le reçoivent
  pas — le tableau d'implémentation MIDI du Korg EK-50, par exemple, marque
  « Local On/Off » comme non reçu. Le panneau Clavier le dit maintenant et
  renvoie au réglage *Local Control* de l'instrument.

### Modifié
- Le guide de dépannage explique comment lire la ligne « Local On/Off » d'un
  tableau d'implémentation MIDI, et donne le chemin exact sur trois instruments.

---

## 1.4.0 — 2026-11-01

La page de commande suit maintenant la **forme** de l'écran, et pas seulement sa
largeur. Un téléphone posé en paysage sur le pupitre devient utilisable :
l'égaliseur et les quatre-vingt-huit touches y tiennent sans rien faire défiler.

### Ajouté
- **Une troisième mise en page : l'écran couché et bas.** Sur un téléphone en
  paysage, la barre d'onglets du bas devient une colonne d'icônes à gauche et la
  barre du haut tient sur une ligne — quatre-vingt-dix points de hauteur rendus à
  la courbe et au clavier. Les 88 touches et leurs trois panneaux tiennent
  ensemble dans 390 points.
- **L'égaliseur en deux colonnes.** Dès qu'il y a la place, la courbe et la rampe
  des sept bandes occupent la gauche, les faders de la bande choisie se posent
  juste dessous, et le micro prend toute la hauteur à droite — son analyseur
  s'agrandit au lieu de laisser un vide. Sur une tablette debout, la courbe passe
  sur toute la largeur : une courbe large se lit mieux qu'une courbe haute.
- **La bibliothèque défile dans son panneau.** Sur un écran large, la liste des
  51 sons défile pour elle-même ; la transposition, les niveaux et les effets ne
  partent plus vers le haut avec elle.
- **Les curseurs se remplissent.** La piste se teinte jusqu'à la valeur, comme
  sur le Mac : un réglage se lit d'un coup d'œil, sans chercher la poignée.

### Corrigé
- **Le vumètre du micro portait l'accent sarcelle** au lieu des couleurs d'une
  mesure. Il passe au vert, puis à l'ambre, puis au rouge, aux mêmes seuils que
  les deux vumètres du bandeau et que ceux du Mac.
- **« Coupe-haut » se coupait en deux** dans la rampe des bandes dès que celle-ci
  passait en colonne. La rampe compte maintenant sa propre largeur, et montre les
  numéros des bandes quand les noms ne tiennent plus — comme le fait
  l'application quand sa fenêtre se resserre.
- **L'accord et le nombre de notes tenues** étaient écrits deux fois sur les
  écrans Accords et Clavier : le bandeau les tait quand l'écran les montre en
  grand.
- **Le sous-titre du bouton d'enregistrement** s'affichait sur la même ligne que
  le titre.
- Trois tailles de caractères hors de la rampe (14, 12,5 et 19 points) et quatre
  hauteurs hors de la grille de 4.

### Modifié
- Les écrans de réglages (Prise, Infos) ne s'étirent plus au-delà d'une largeur
  de lecture.
- Le mode d'emploi des poignées rejoint le panneau de la bande, au lieu
  d'occuper un panneau à lui seul.

---

## 1.3.0 — 2026-11-01

Vingt sons qui ne sont pas des pianos, une bibliothèque qui se replie famille par
famille, et un analyseur de spectre sur l'entrée micro. La passe de design
continue là où elle s'était arrêtée : les écrans de réglages.

### Ajouté
- **Vingt sons, quatre familles nouvelles.** *Cordes* (violon, violoncelle,
  ensemble, pizzicato, harpe), *Guitares* (nylon, folk, demi-caisse jazz,
  électrique claire), *Accordéon & anches* (accordéon, bandonéon, harmonica,
  harmonium) et *Mailloches* (vibraphone, marimba, célesta, kalimba, cloches
  tubulaires). Plus deux combinaisons : *Grand + Quatuor* et un partage
  *Accordéon / Piano*. La bibliothèque passe de 31 à 51 sons.
  Aucun téléchargement de plus : ces sons sortent des deux banques générales
  déjà installées, y compris en installation allégée.
- **La bibliothèque se replie.** Chaque famille a un en-tête avec son compte et
  un chevron ; « Tout replier » donne un sommaire de dix lignes. La famille du
  son en cours porte un point, pour qu'une famille fermée ne le cache pas. Les
  pastilles de filtre disparaissent : elles faisaient le même travail, moins
  bien. Même chose sur la page de commande.
- **Un analyseur de spectre sur l'entrée micro**, le même composant que pour le
  piano : le spectre de ce que le micro entend, avec par-dessus la courbe des
  sept bandes, et les poignées qu'on déplace. Sur le Mac et sur la tablette.
- **Les sons ajoutés par une mise à jour apparaissent vraiment.** La liste des
  sons est enregistrée dans `setup.json` : jusqu'ici, c'est l'ancienne qui était
  relue, et une nouvelle version n'apportait aucun son. La bibliothèque vient
  maintenant du code, vos réglages (égaliseur, effets, niveaux, étalonnage)
  viennent du disque.

### Corrigé
- **Le voile sombre de la main gauche s'affichait sur tous les sons**, pas
  seulement sur les partages clavier — la moitié gauche du clavier paraissait
  éteinte sans raison. Il n'apparaît plus que là où il y a un point de partage,
  sur le Mac comme sur la page.
- **Le spectre de la page de commande était resté bleu** alors que l'application
  l'avait passé en gris en 1.2.0, et ses graduations utilisaient encore l'ancien
  gris trop sombre. La page et l'application se ressemblent de nouveau au pixel.
- **L'étalonnage se laissait entraîner par un seul son.** La sonie commune était
  celle du son le plus contraignant ; une kalimba — attaque sèche, crête haute,
  sonie très basse — tirait toute la bibliothèque douze décibels plus bas. La
  cible est maintenant prise parmi les plus basses sans être la plus basse, et
  un son qui ne peut pas l'atteindre sans écrêter reste en dessous : l'outil le
  dit, nommément.
- **`make calibrate` et `make test` pouvaient tourner sur un binaire périmé** :
  ils ne reconstruisaient que si l'outil manquait. Cinq minutes d'étalonnage qui
  écrivent les mauvais gains, ça ne se voit pas.
- **La courbe de l'égaliseur micro était plate au lancement** : la chaîne du
  micro ne recevait ses réglages qu'à l'ouverture de l'entrée.

### Modifié
- **L'onglet Périphériques tient en colonnes.** Trois panneaux côte à côte sur
  un grand écran, deux en dessous, un sur une fenêtre étroite — et la colonne
  s'arrête à 1240 points au lieu de s'étirer. Les explications longues passent
  en infobulle sur la commande qu'elles expliquent ; la version et les mises à
  jour tiennent sur une ligne.
- **L'onglet Enregistrer aussi** : les quatre fichiers produits passent en liste
  au lieu de quatre cases étirées, et la liste des prises occupe la hauteur.
- **L'écran de jeu donne la hauteur au clavier** plutôt qu'au cadre de l'accord,
  et les deux faders de niveau se mettent côte à côte : un fader d'un mètre de
  long se règle moins bien qu'un fader de trois cent cinquante points.

### Pour les porteurs de fork
- `AnalyzerView` prend désormais un `SpectrumTap` et une `ProcessorChain` au lieu
  du moteur entier : c'est ce qui permet de le poser deux fois.
- `MicInput` porte son propre `SpectrumTap`, alimenté par le bloc d'entrée, donc
  actif même quand l'écoute est coupée.
- `Category` décode tolérant et a quatre cas de plus ; `RigConfig.merge` fusionne
  bibliothèque et réglages au chargement. `KeyboardView.splitAt` est un `Int?`.
- Le flux temps réel porte `micSpectrum` quand l'entrée est ouverte.

## 1.2.0 — 2026-11-01

Une passe de design sur toute l'interface, l'application et la page de commande.
Rien ne change dans ce que fait l'outil : ce qui change, c'est que chaque taille,
chaque couleur et chaque mot est maintenant choisi.

### Modifié
- **Plus de capitales espacées.** Toutes les étiquettes — `VOLUME GÉNÉRAL`,
  `ACCORD DÉTECTÉ`, `HPF`, `AUCUN CLAVIER` — passent en casse normale. C'est le
  changement qui se voit le plus, et celui qui se lit le plus vite.
- **Une seule couleur allumée.** Les six teintes par famille de sons disparaissent
  de la bibliothèque : le son choisi porte un trait sarcelle, les autres n'ont pas
  de couleur. Les quatre faders d'effets, qui avaient chacun la leur, prennent
  l'accent. Le vert, l'ambre et le rouge ne servent plus qu'à porter une mesure :
  un niveau, un enregistrement en cours, une alerte.
- **Un seul accent par graphique.** Dans l'analyseur, la courbe d'égalisation garde
  le sarcelle parce que c'est elle qu'on règle ; le spectre derrière devient un gris.
- **Deux graisses au lieu de cinq**, et la hiérarchie vient de la taille et de la
  couleur. Les valeurs mesurées passent en chasse fixe et s'alignent en colonne ;
  les grands nombres gardent la famille de l'interface, avec des chiffres de largeur
  fixe.
- **Tout tombe sur une grille de 4 points.** Les valeurs bricolées — 3, 7, 9, 13 —
  ont disparu.
- **Le gris du texte estompé passe de 3,2:1 à 4,9:1** sur un panneau. Sur scène, la
  lumière est mauvaise et l'œil est ailleurs.
- **La page de commande suit exactement la même rampe de couleurs et la même échelle
  de tailles que l'application**, au point près.

### Corrigé
- **La zone de la main gauche d'un partage clavier ne s'affichait pas** — ni sur le
  Mac, ni sur la tablette. L'ombre était dessinée sous les touches, qui sont opaques,
  et la légende décrivait donc quelque chose d'invisible. Elle passe par-dessus, avec
  un filet au point de partage, et se voit maintenant même quand aucune note n'est
  tenue.
- **En fenêtre étroite, « Enregistrer » se coupait en « Enregistre / r ».** Les deux
  commandes de scène passent l'une sous l'autre quand la place manque, et aucun
  bouton ne coupe plus son mot.
- **En fenêtre étroite, la transposition disparaissait des deux endroits à la fois.**
  Le bandeau ne la cache que lorsque l'écran de jeu l'affiche vraiment.
- **En fenêtre basse, les niveaux sortaient de l'écran.** L'accord passe en petit et
  le clavier se tasse, plutôt que de pousser un réglage hors de vue.
- **Sur téléphone, les sept tranches de l'égaliseur se chevauchaient** (`Présenc`,
  `Coupe-bas` sur deux lignes). Elles passent aux numéros, et le nom complet s'affiche
  sous la bande choisie. Les poignées de la courbe portent le numéro de leur bande au
  lieu d'un nom coupé au troisième caractère.
- **Un pourcentage était tronqué sur le Mac et arrondi sur la page** : 82 % d'un côté,
  83 % de l'autre pour la même valeur. Les deux arrondissent.
- **Le nom d'un modèle de piano était écrit en dur dans l'écran de démarrage**, contre
  la règle du projet. L'outil marche avec le clavier qu'on lui branche, quel qu'il soit.
- **Le halo qui battait sans fin** sur le bandeau « en attente d'un clavier » s'arrête :
  rien ne s'y passe, et une animation en boucle use l'œil pendant un concert.
- Un panneau appelé « Effets » sur le Mac s'appelait « Couleur » sur la tablette.

### Pour les porteurs de fork
Le langage visuel est écrit dans [AGENTS.md](AGENTS.md), §4 bis : la direction en cinq
lignes, puis les règles qui en sortent. La méthode vient d'[unslop](https://github.com/heydamir/unslop)
(Damir Sokolovsky, CC BY 4.0) et de [stageshow](https://github.com/arm1383/stageshow-skills)
(Benji Taylor), indiqués par l'auteur du projet.

---

## 1.1.0 — 2026-11-01

### Ajouté
- **L'interface web reprend l'application entière.** La page ouverte sur une
  tablette ou un téléphone a maintenant les mêmes écrans que le Mac : Jeu,
  Égaliseur, Accords, Clavier, Enregistrement. L'égaliseur sept bandes y est
  complet, avec l'analyseur de spectre et les poignées que l'on déplace au
  doigt.
- **Mise en page adaptative.** Barre latérale sur iPad en paysage, onglets en
  bas sur téléphone, colonnes qui se réorganisent au lieu de s'étirer.
- **Flux temps réel** (`/api/stream`, *Server-Sent Events*) : spectre, niveaux
  et notes tenues arrivent sans interroger le Mac en boucle. La page se
  rabat sur l'interrogation périodique si le flux échoue.
- **Installable sur l'écran d'accueil** de l'iPad et de l'iPhone : icône,
  plein écran, sans la barre de Safari.
- **Mises à jour** : `./scripts/update.sh`, numéro de version visible dans
  l'application, et vérification de la dernière version publiée.
- **Le micro se pilote depuis la tablette** : entrée, gain, compresseur,
  écoute, et son égaliseur.
- **Journal des changements** (ce fichier) et étiquettes Git par version.

### Corrigé
- **L'entrée micro ne fonctionnait pas du tout.** Il manquait
  `NSMicrophoneUsageDescription` dans l'`Info.plist` : macOS ne demandait donc
  jamais l'autorisation, le périphérique s'ouvrait sans erreur et n'envoyait
  que du silence. L'application demande maintenant l'autorisation, affiche son
  état, propose d'ouvrir les réglages si elle a été refusée, et signale au bout
  de deux secondes et demie qu'une entrée ouverte n'envoie rien.
- **Un clavier allumé après le lancement n'était pas détecté** — le vrai
  correctif, cette fois. La livraison des changements CoreMIDI se fait par
  processus, sur la run loop du thread qui a créé le **premier** client ; un
  client créé avant le nôtre sur un thread endormi bloquait tout, y compris le
  rafraîchissement de la liste des appareils. L'application crée donc
  maintenant son client en tout premier, sur un thread dont elle fait tourner
  la run loop elle-même. L'onglet Périphériques affiche combien de changements
  ont été reçus — zéro après un branchement signale la panne.
- **Une sortie audio qui ne répond plus ne fige plus l'application.** Un piano
  USB à moitié éteint bloquait `setDeviceID` indéfiniment, sur le thread
  principal : écran de chargement figé, sans explication. Les bascules de
  sortie se font maintenant à part, et l'écran de démarrage dit au bout de
  neuf secondes quoi faire.
- Les réglages d'un ancien fichier de configuration ne sont plus perdus quand
  une nouvelle version ajoute un champ.
- La mesure de hauteur confondait la fondamentale avec la deuxième harmonique
  dans le grave, ce qui faisait échouer le test de transposition à l'octave.

### Pour les porteurs de fork
- `AppInfo` (version, commit, date de construction) est généré à la
  compilation dans `build/gen/Version.swift` ; ne le versionnez pas.
- Les fichiers web sont assemblés par `scripts/gen-web.py` : une page HTML,
  une feuille de style, un script, et les icônes — tout est embarqué dans le
  binaire.

## 1.0.0 — 2026-10-31

Première version complète.

### Ajouté
- 31 sons répartis en six familles, 16 banques, équilibrage mesuré.
- Égaliseur sept bandes avec analyseur de spectre temps réel.
- Détection d'accords et affichage du clavier.
- Enregistrement en quatre formes : audio, MIDI rejouable, partition
  MusicXML, suite d'accords.
- Entrée micro avec son propre égaliseur.
- Prise en main automatique de n'importe quel clavier MIDI, à chaud.
- Page de commande à distance pour tablette.
- Icône fabriquée à la compilation.
