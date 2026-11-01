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

### Le micro ne passe pas

Trois causes, dans cet ordre :

1. **L'autorisation.** macOS demande l'accès au micro la première fois. Si vous avez
   refusé, l'entrée s'ouvre sans erreur et n'envoie que du silence. L'onglet
   *Périphériques* affiche l'état (« autorisé », « refusé… ») et propose d'ouvrir le bon
   volet des réglages.
2. **L'écoute est coupée.** C'est volontaire : un micro ouvert près des haut-parleurs
   siffle. Rien ne sort tant que *Envoyer dans la sortie* n'est pas coché.
3. **L'entrée n'envoie rien.** Au bout de deux secondes et demie de silence absolu,
   l'application le dit. Pour un iPhone utilisé comme micro : il doit être déverrouillé,
   à proximité, et ne pas déjà servir ailleurs.

### Après une mise à jour, macOS redemande l'autorisation du micro

C'est normal. L'application est compilée sur votre Mac et signée « à la volée », sans
identifiant de développeur Apple : chaque reconstruction produit une signature
différente, et macOS la considère comme une nouvelle application. Acceptez une fois de
plus.

### L'application reste bloquée sur son écran de chargement

Au bout de neuf secondes, elle affiche de quelle sortie il s'agit. CoreAudio n'a pas de
délai d'attente : un périphérique USB à moitié éteint, ou dont le câble a bougé, peut ne
jamais répondre. Éteignez puis rallumez l'instrument, ou débranchez et rebranchez son
câble — le démarrage reprend tout seul.

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

### La page de commande ne s'ouvre pas sur la tablette

1. La tablette et le Mac sont-ils sur le **même réseau Wi-Fi** ? Un réseau « invité »
   isole souvent les appareils les uns des autres.
2. Le pare-feu de macOS a-t-il demandé l'autorisation ? Réglages Système ▸ Réseau ▸
   Pare-feu ▸ Options : autorisez *Piano Live Setup* à recevoir des connexions entrantes.
3. Essayez l'autre adresse proposée : celle en chiffres marche quand le nom en `.local`
   échoue.
4. La clé est sensible à la casse ? Non, mais elle ne contient ni I, ni L, ni O, ni 0,
   ni 1 — justement pour éviter les confusions.

### La page affiche « Le Mac ne répond plus »

L'application a été quittée, le Mac s'est endormi, ou le Wi-Fi a changé. La page se
reconnecte toute seule dès que le Mac répond à nouveau.

### Je veux repartir de zéro

```bash
./scripts/uninstall.sh          # retire l'application
rm -rf "$HOME/Music/Piano Live Setup"   # efface sons, réglages ET enregistrements
./install.sh
```
