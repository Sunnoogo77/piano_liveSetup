# Journal des changements

Les versions suivent [SemVer](https://semver.org/lang/fr/) : `MAJEUR.MINEUR.CORRECTIF`.

- **MAJEUR** — il faut refaire quelque chose à la main (réglages, banques, matériel).
- **MINEUR** — nouvelles fonctions, vos réglages sont conservés.
- **CORRECTIF** — corrections seulement.

Pour passer à la dernière version : `./scripts/update.sh`
(détails dans [docs/UPDATING.md](docs/UPDATING.md)).

---

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
