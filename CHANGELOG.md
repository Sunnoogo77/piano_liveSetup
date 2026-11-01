# Journal des changements

Les versions suivent [SemVer](https://semver.org/lang/fr/) : `MAJEUR.MINEUR.CORRECTIF`.

- **MAJEUR** — il faut refaire quelque chose à la main (réglages, banques, matériel).
- **MINEUR** — nouvelles fonctions, vos réglages sont conservés.
- **CORRECTIF** — corrections seulement.

Pour passer à la dernière version : `./scripts/update.sh`
(détails dans [docs/UPDATING.md](docs/UPDATING.md)).

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
