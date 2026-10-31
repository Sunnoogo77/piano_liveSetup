# Claude Code — dépôt Piano Live Setup

**Lisez [AGENTS.md](AGENTS.md) en premier.** Il contient la carte du code, les règles à
respecter et les pièges déjà rencontrés. Ce fichier n'ajoute que ce qui est propre à
Claude Code.

## Démarrage rapide

```bash
./install.sh --light      # pose tout ce qu'il faut, banques allégées
make test                 # vérifie sans avoir besoin d'un piano branché
make preview              # rend l'interface en PNG dans build/ui
```

## Conventions

- Interface, commentaires et messages de commit **en français**.
- Pas de dépendance de paquet. Si vous pensez en avoir besoin, c'est probablement non.
- Chaque modification du traitement du signal ou des presets se termine par
  `make calibrate && make test-audio`.

## Pour voir votre travail

La capture d'écran du système est souvent refusée à un agent. `make preview` rend les
vues SwiftUI hors écran en PNG depuis le processus lui-même : ouvrez les images, jugez,
corrigez. Les écrans sont rendus à 1020, 1440 et 1728 points de large.

## Ce qu'il ne faut pas faire

- Ne versionnez jamais le dossier `Sounds/` (1,5 Go, et les banques appartiennent à leurs
  auteurs).
- N'affirmez pas qu'une correction fonctionne sans avoir lancé les tests qui la couvrent.
- Ne codez en dur aucun nom de fabricant : le projet doit marcher avec n'importe quel
  clavier MIDI.
