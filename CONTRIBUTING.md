# Contribuer

Les contributions sont bienvenues. Quelques repères pour que ça se passe bien.

## Avant de commencer

Lisez [AGENTS.md](AGENTS.md). Il contient la carte du code, les règles du thread audio et
la liste des pièges déjà rencontrés — ça vous évitera de les retrouver.

## Mettre en route

```bash
./install.sh --light
make test
```

Pour travailler sans toucher à une installation qui sert sur scène :

```bash
PIANO_LIVE_HOME=/tmp/essai ./install.sh --light --no-app
```

## Avant d'envoyer une modification

| Vous avez touché à… | Lancez |
|---|---|
| n'importe quoi | `make test` |
| le traitement du signal, les presets | `make calibrate && make test-audio` |
| l'interface | `make preview`, et regardez les PNG |
| la reconnaissance d'accords | `make test`, et ajoutez vos cas à `ChordTest` |

N'annoncez pas qu'une modification fonctionne sans avoir lancé les tests qui la couvrent.

## Style

- Interface, commentaires et messages de commit **en français**.
- Pas de dépendance de paquet.
- Les commentaires expliquent *pourquoi*, pas *quoi*.

## Idées utiles

- D'autres sons, surtout des orgues et des nappes de meilleure qualité, sous licence
  libre vérifiée.
- Une vraie simulation de cabine Leslie.
- Un affichage de partition dans l'application (aujourd'hui c'est un export MusicXML).
- La traduction de l'interface, si quelqu'un la veut en anglais.
