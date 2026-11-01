# Claude Code — dépôt Piano Live Setup

**Lisez [AGENTS.md](AGENTS.md) en premier.** Il contient la carte du code, les règles à
respecter et les pièges déjà rencontrés. Ce fichier n'ajoute que ce qui est propre à
Claude Code.

## Démarrage rapide

```bash
./install.sh --light      # pose tout ce qu'il faut, banques allégées
make test                 # vérifie sans avoir besoin d'un piano branché
make preview              # rend l'interface en PNG dans build/ui
make update               # passe à la dernière version publiée
```

## Conventions

- Interface, commentaires et messages de commit **en français**.
- Pas de dépendance de paquet. Si vous pensez en avoir besoin, c'est probablement non.
- Chaque modification du traitement du signal ou des presets se termine par
  `make calibrate && make test-audio`.

## Le design

**Avant de toucher à l'interface, lisez « Le langage visuel » dans [AGENTS.md](AGENTS.md)
(§4 bis).** Une seule couleur allumée, des étiquettes en casse normale, deux graisses, la
grille de 4. Ces règles viennent de deux dépôts indiqués par l'auteur du projet —
[unslop](https://github.com/heydamir/unslop) et
[stageshow](https://github.com/arm1383/stageshow-skills) — et elles s'appliquent des deux
côtés : l'application et la page de commande sont le même outil.

## Pour voir votre travail

La capture d'écran du système est souvent refusée à un agent. `make preview` rend les
vues SwiftUI hors écran en PNG depuis le processus lui-même : ouvrez les images, jugez,
corrigez. Les écrans sont rendus à 1020, 1440 et 1728 points de large.

**La page de commande, elle, se regarde dans un navigateur** : lancez l'application,
activez le contrôle à distance dans l'onglet Périphériques, et ouvrez l'adresse. Vérifiez
à deux tailles au moins — 1180×820 (iPad en paysage, barre latérale) et 375×812
(téléphone, onglets en bas). Les deux mises en page sont différentes, pas seulement
redimensionnées.

## Vérifier une installation en marche, sans interface graphique

Tout l'état de l'application est lisible et pilotable en HTTP une fois le contrôle à
distance actif. C'est le moyen honnête de tester sans prétendre avoir cliqué :

```bash
K=XXXXXX                                   # la clé affichée dans l'app
curl -s "http://127.0.0.1:8787/api/state?k=$K" | python3 -m json.tool
curl -sN --max-time 4 "http://127.0.0.1:8787/api/stream?k=$K"   # le flux temps réel
curl -s -X POST "http://127.0.0.1:8787/api/cmd?k=$K" \
     -H 'Content-Type: application/json' -d '{"action":"preset","index":7}'
```

Si vous changez quelque chose pendant un essai, remettez-le comme vous l'avez trouvé :
le piano peut être en train de servir.

## Ce qu'il ne faut pas faire

- Ne versionnez jamais le dossier `Sounds/` (1,5 Go, et les banques appartiennent à leurs
  auteurs).
- N'affirmez pas qu'une correction fonctionne sans avoir lancé les tests qui la couvrent.
- Ne codez en dur aucun nom de fabricant : le projet doit marcher avec n'importe quel
  clavier MIDI.
- Ne faites pas installer une mise à jour par l'application : elle la signale, l'utilisateur
  lance `./scripts/update.sh`.
- Ne versionnez rien de ce que `build/gen/` produit (`Version.swift`, `WebAssets.swift`).
