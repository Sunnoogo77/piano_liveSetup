# Mettre à jour

## En une commande

```bash
cd ~/Developer/piano_liveSetup   # là où vous avez cloné
./scripts/update.sh
```

Le script récupère la nouvelle version, reconstruit, lance les tests, et ne
remplace l'application dans `/Applications` que si tout passe. En cas d'échec,
l'application en place n'est pas touchée.

Pour seulement savoir s'il y a du nouveau, sans rien changer :

```bash
./scripts/update.sh --check
```

Il sort avec le code 1 s'il existe une version plus récente, 0 sinon — pratique
dans un script.

## Ce qui est conservé

Tout ce qui vous appartient vit **en dehors** du dépôt, dans
`~/Music/Piano Live Setup` :

| Dossier | Contenu |
|---|---|
| `Config/setup.json` | vos réglages, votre étalonnage, vos égaliseurs |
| `Sounds/` | les banques de sons (ne sont jamais retéléchargées sans raison) |
| `Enregistrements/` | vos prises |

La mise à jour n'y écrit pas. Et si une version ajoute un réglage, les anciens
fichiers de configuration restent lisibles : les champs absents prennent leur
valeur par défaut, le reste est conservé tel quel. C'est vérifié par un test
(`build/bin/rectest`, section « Configuration tolérante aux versions »).

## Demander à un agent de le faire

C'est le cas que ce dépôt prévoit : vous n'ouvrez pas de terminal, vous
demandez. Collez ceci dans Claude Code, Codex, Cursor ou équivalent :

> Mets à jour Piano Live Setup. Le dépôt est cloné sur cette machine ;
> trouve-le, puis lance `./scripts/update.sh` et montre-moi ce qui a changé.
> Ne touche pas à mes réglages et n'installe rien d'autre.

[AGENTS.md](../AGENTS.md) donne à l'agent la marche à suivre exacte, y compris
quoi faire si la construction échoue.

## Si vous avez téléchargé une archive ZIP

La mise à jour automatique a besoin de Git. Reprenez le projet une fois pour
toutes :

```bash
git clone https://github.com/Sunnoogo77/piano_liveSetup.git
cd piano_liveSetup && ./install.sh
```

Vos sons, réglages et enregistrements sont ailleurs : ils seront retrouvés
intacts, et rien n'est retéléchargé.

## Si vous avez modifié le code

Le script refuse d'écraser votre travail. Deux cas :

- **modifications non validées** : il s'arrête et vous laisse choisir
  (`git stash`, ou un commit) ;
- **historique divergé** (vous avez vos propres commits) : il s'arrête et vous
  propose `git rebase origin/main` ou `git merge origin/main`.

Dans les deux cas, rien n'a été modifié avant que vous ne décidiez.

## Revenir en arrière

Les versions sont étiquetées. Pour retrouver exactement une version publiée :

```bash
git fetch --tags
git checkout v1.0.0
./scripts/build.sh && cp -R "build/Piano Live Setup.app" /Applications/
```

Pour revenir au courant : `git checkout main && ./scripts/update.sh`.

## Numérotation

`MAJEUR.MINEUR.CORRECTIF` ([SemVer](https://semver.org/lang/fr/)) :

- **CORRECTIF** — des corrections, rien à refaire.
- **MINEUR** — des ajouts, vos réglages sont conservés.
- **MAJEUR** — quelque chose est à refaire à la main ; le
  [journal des changements](../CHANGELOG.md) dit quoi.

L'application affiche sa version dans l'onglet **Périphériques**, section
*Version et mises à jour*, et peut demander à GitHub s'il existe plus récent.
Elle ne télécharge ni n'installe jamais rien d'elle-même : elle donne la
commande, vous décidez. Cette vérification se coupe d'un interrupteur dans ce
même panneau.

## Publier une version (si vous maintenez un fork)

```bash
# 1. le numéro
echo "1.2.0" > VERSION

# 2. ce qui change, en haut du journal
$EDITOR CHANGELOG.md

# 3. vérifier avant de publier
./scripts/build.sh && ./scripts/test.sh

# 4. publier
git add -A && git commit -m "Version 1.2.0"
git tag -a v1.2.0 -m "1.2.0"
git push && git push --tags
```

L'étiquette est ce que lisent les copies installées : sans elle, personne ne
saura qu'il y a du nouveau. `AppInfo.slug` est déduit de votre `remote origin`
à la construction, donc **un fork vérifie ses propres étiquettes** — il n'y a
rien à changer dans le code.
