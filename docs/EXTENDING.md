# Bidouiller, forker, étendre

Le projet est fait pour être repris. Voici les recettes des modifications les plus
courantes.

## Ajouter un son

Tout se passe dans `Library.all()`, dans `Sources/Core/Model.swift`. Un preset,
c'est un nom, une famille, une à trois couches, un égaliseur et des effets.

```swift
p.append(Preset(name: "Mon Rhodes", subtitle: "Chaud, trémolo lent",
                category: .electric,
                layers: [L(Bank.ms, 0, 4, rev: 26)],
                eqBands: eq([(1, 150, 2.0), (4, 3200, 1.5)], hpf: 50),
                tremRate: 4.2, tremDepth: 0.35))
```

`L(banque, banqueInterne, programme, …)` construit une couche. Les paramètres
optionnels : `vol`, `pan`, `semi` (décalage en demi-tons), `lo` et `hi` (étendue de
clavier, pour un partage), `rev`, `cho`.

`eq(...)` part des sept bandes à plat ; chaque `(index, fréquence, gain)` en modifie
une. `hpf:` et `lpf:` placent les coupe-bas et coupe-haut.

Ensuite, obligatoirement :

```bash
make calibrate     # pour que votre son soit au même niveau que les autres
make test-audio    # pour vérifier qu'il n'est pas muet
```

## Superposer ou partager le clavier

Deux couches suffisent. Superposition :

```swift
layers: [L(Bank.salamander, rev: 26),
         L(Bank.ms, 0, 89, vol: 0.30, rev: 62)],
layerMix: 0.30
```

Partage à Mi2 :

```swift
layers: [L(Bank.gu, 0, 33, lo: 21, hi: 51),      // basse à gauche
         L(Bank.salamander, lo: 52, hi: 108)],   // piano à droite
category: .split
```

## Ajouter une banque de sons

1. Une constante dans `enum Bank`, et le nom de fichier dans `Bank.all`.
2. Une entrée dans `Bank.fallbacks` : ce qu'on joue si la banque n'est pas installée.
   Sans ça, une installation allégée rend vos presets muets.
3. Une ligne dans `scripts/fetch-soundbanks.sh`, avec l'URL officielle et l'empreinte
   SHA-256 (`shasum -a 256 fichier.sf2`).
4. Le crédit et la licence dans `CREDITS.md`. **Vérifiez la licence avant.**

`build/bin/banks MaBanque.sf2` liste ses presets avec leurs numéros.

## Ajouter un effet

`ProcessorChain.process` dans `Sources/Core/DSP.swift`. L'ordre actuel est
saturation → égaliseur → trémolo → compresseur → gain. Ajoutez votre étage au bon
endroit, exposez ses paramètres comme les autres (de simples `var` : une lecture
déchirée d'un scalaire n'a pas de conséquence audible), et branchez-le dans
`Preset` et `applyProcessing`.

**Rien qui alloue, rien qui verrouille.** Pas de tableau Swift réaffecté, pas de
`print`. Si votre effet a besoin d'une table, allouez-la à l'initialisation.

## Ajouter un écran

1. Un cas dans `enum Tab` (`Sources/UI/App.swift`) avec son symbole SF.
2. Une `View` dans `Screens.swift` ou `Screens2.swift`.
3. Un cas dans `StageView.content(width:)`.

Puis `make build && make preview` et **regardez les PNG** dans `build/ui`. C'est le
seul moyen fiable de juger sans lancer l'app.

## Ajouter un accord à la reconnaissance

`ChordBook.templates` dans `Sources/Core/Chords.swift` : les intervalles en
demi-tons depuis la fondamentale, le suffixe affiché, le nom français, et un poids
qui départage les ambiguïtés. Ajoutez vos cas à `Sources/Tools/ChordTest/main.swift`
et lancez `make test`.

Attention : vérifiez votre théorie avant de « corriger » le détecteur. Pendant
l'écriture, trois cas de test se sont révélés faux alors que le code avait raison.

## Changer la palette

`enum Tone` dans `Sources/UI/Design.swift`, et les variables `--bg0…--t2` en haut
de `Sources/Web/remote.css`. **Les deux doivent rester identiques** : l'application
et la page sont le même outil, et une page qui dérive d'un ton finit par ne plus
ressembler à rien.

Les règles qui tiennent la palette — une rampe de gris froids, un seul accent, trois
rôles de texte, les couleurs vives réservées à une mesure — sont écrites dans
[AGENTS.md](../AGENTS.md) §4 bis. Lisez-les avant de changer une valeur : elles
expliquent pourquoi le gris estompé est à 4,9:1 et pas plus bas.

Après modification : `make build && make preview`, puis *regardez les PNG* — surtout
`ui-min.png`, le rendu le plus étroit.

## Travailler sans casser votre installation de scène

```bash
PIANO_LIVE_HOME=/tmp/essai ./install.sh --light --no-app
PIANO_LIVE_HOME=/tmp/essai ./build/bin/selftest
```

## Avant d'ouvrir une pull request

Lisez [CONTRIBUTING.md](../CONTRIBUTING.md). En résumé : `make test` toujours,
`make calibrate && make test-audio` si vous avez touché au son, `make preview` si
vous avez touché à l'interface.
