# Si quelque chose ne va pas

### Je n'entends rien

1. Onglet **Périphériques** : la sortie choisie est-elle la bonne ? Essayez-en une autre,
   le changement est immédiat.
2. Si la sortie est le piano, montez son bouton **MASTER VOLUME**, et vérifiez qu'aucun
   casque n'est branché dessus.
3. Le curseur **Volume général** de l'onglet Jeu n'est pas à zéro ?

### J'entends deux sons différents quand je transpose

C'est le son interne du clavier qui joue en plus du Mac. La pastille en bas à droite doit
afficher « Son du piano coupé » — sinon cliquez dessus, ou appuyez sur `L`.

Si votre clavier ne répond pas au CC 122, cherchez « Local Control » ou « Local Off » dans
ses menus. Sur un Yamaha YDP-145 : maintenir **[DEMO/SONG] + [PIANO/VOICE]**, puis appuyer
sur la touche **Si3**.

### Mon piano n'est pas détecté

Onglet **Périphériques**, bouton **Rechercher les appareils**. Le branchement à chaud est
géré, mais ce bouton force une nouvelle détection.

Vérifiez que le câble est un vrai câble de données (certains câbles USB ne font que
charger) et que le piano est allumé. Utilisez le port **USB TO HOST** de l'instrument, pas
le port « USB TO DEVICE » prévu pour une clé.

### Le son craque

Augmentez la taille de tampon dans `Config/setup.json` (`bufferFrames` : 128 → 256), puis
relancez l'application. Fermez aussi les applications gourmandes : un rendu vidéo en
arrière-plan suffit à faire craquer une sortie à 2,9 ms.

### Je viens de quitter l'app, je la relance et il n'y a plus de son

L'application gère ce cas : elle vérifie que la sortie tourne vraiment et réessaie
jusqu'à quatre fois. Si malgré tout elle affiche « la sortie ne démarre pas », c'est
qu'une autre application tient le périphérique — fermez-la, ou choisissez une autre
sortie dans l'onglet Périphériques.

### L'application met longtemps à s'ouvrir

C'est normal : 1,5 Go d'échantillons passent en mémoire au lancement, dont un piano à
16 couches de vélocité. Comptez une dizaine de secondes, une seule fois par session. Pour
démarrer plus vite, réinstallez avec `./install.sh --light`.

### Le micro siffle

C'est un larsen : le micro réentend les haut-parleurs. Coupez **Envoyer dans la sortie**,
baissez le gain, éloignez le micro des enceintes, et creusez la bande qui siffle avec
l'égaliseur de la voix.

### « FluidSynth introuvable » à la compilation

```bash
brew install fluid-synth
```

### L'application refuse de s'ouvrir (développeur non identifié)

Elle est signée localement, pas notariée par Apple. Clic droit sur l'application ▸
**Ouvrir**, puis confirmez. Une seule fois.

### Je veux repartir de zéro

```bash
./scripts/uninstall.sh          # retire l'application
rm -rf "$HOME/Music/Piano Live Setup"   # efface sons, réglages ET enregistrements
./install.sh
```
