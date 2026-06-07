# CLAUDE.md — Balade en chariot 🚂 (jeu Roblox)

> Contexte du projet pour **Claude Code**. À lire en entier avant de coder. Écrit en français (équipe FR).

## 🎮 Le projet
Jeu Roblox : un **chariot sur rails** à traverser, multi-mondes, multijoueur.
Mondes (ascension) : **Enfer → Ville → Montagne → Paradis**.
**Règle d'or du projet : TOUT est généré par CODE (procédural).** Pas de Toolbox, pas d'assets importés — la voie, le terrain, le décor, le hub, les chariots sont créés par script.

## 📂 Structure (Rojo)
- `src/BaladeEnChariot.server.lua` → **LE gros script serveur (~3000 lignes)**. Il génère TOUT le monde + gère TOUTE la logique. ~95% du jeu est ici.
- `client/CartCamera.client.lua` → caméra libre qui suit le siège du chariot.
- `client/UpgradeButton.client.lua` → menu d'achat des chariots (côté client).
- `default.project.json` → config Rojo (`src`→ServerScriptService, `client`→StarterPlayerScripts).
- `rojo.exe` + `LANCER-ROJO.bat` → pour synchroniser fichiers ↔ Studio.

## ▶️ Lancer / tester
1. Lancer `LANCER-ROJO.bat` (démarre `rojo serve`).
2. Studio : plugin **Rojo → Connect** (les scripts se synchronisent en direct).
3. **Play ▶**. Multijoueur : onglet **Test → « Serveur et clients » → 2 joueurs**.
- Logs Studio : `%LOCALAPPDATA%\Roblox\logs\*Studio*.log` (chercher `[DBG]`, `attempt to`, `Stack Begin`).

## ✅ VÉRIFIER LA SYNTAXE avant de faire tester (IMPORTANT)
Le fichier est énorme → une faute de syntaxe casse tout le jeu. **Avant de dire « teste ça »**, valide avec **luau-compile** :
- Télécharger une fois : `https://github.com/luau-lang/luau/releases/latest/download/luau-windows.zip` (contient `luau-compile.exe`).
- Lancer : `luau-compile.exe --binary src/BaladeEnChariot.server.lua` → **exit 0 = syntaxe OK**.
- ⚠️ luau-compile ne voit QUE la syntaxe, **pas** les bugs runtime (ex : `local function` appelée avant sa définition).

## 🏗️ Architecture (points clés)
### Génération de la voie
- `genLayout(world)` enchaîne des « runs » (`straight`, `sweep`, `hardTurn`, `hill`, `bigHill`, `loopRun`, `phantomRun`…) → remplit `nodes`.
- `genTrack(world)` → remplit `nodes`, `renderNodes` (avec inclinaison/bank), `cumDist`, `TOTAL_DIST`, `NSEG`, `segMeta` (champ `kind` : straight/turn/hill/loop/phantom).
- **`renderAtDistance(d)`** → renvoie un CFrame sur la voie à la distance `d` (courbe Catmull-Rom). C'est LA fonction centrale pour positionner quoi que ce soit sur la voie.
- `buildTrack()` construit ballast/traverses/rails/tunnel/checkpoints/obstacles + `buildStartLanes()` (voies de départ latérales qui fusionnent vers la voie centrale).

### CHARIOTS PAR JOUEUR (refactor récent — central)
- `playerCarts[player] = pc`, avec `pc = { player, cart, seat, base, rollSound, sparkEmitter, legendLight, legendFX, cartPitch, state, spawned, conns }`.
- `makeFreshState()` = un état NEUF par joueur (`distance`, `speed`, `score`=pièces, `xp`, `cartTier`, etc.).
- `makePlayerCart(player)` crée chariot+siège+effets (pas encore dans le monde). `spawnPlayerCart(player)` le fait APPARAÎTRE au départ (sur sa voie) + assoit le joueur. Déclenché par le pad/ProximityPrompt « Faire apparaître mon chariot ».
- **`stepCart(pc, dt)`** = corps de la boucle principale, appelé pour CHAQUE chariot par un seul `Heartbeat` qui itère `playerCarts` (saute si `not pc.spawned`, et si `rebuilding`).
- 💡 **Style de code à garder** : dans `stepCart` et les helpers, on met en tête `local state, cart, seat = pc.state, pc.cart, pc.seat` (alias) → le corps utilise `state`/`cart`/`seat` comme avant. Reprends ce style pour ajouter du code par-joueur.
- **PARTAGÉ** (pas par joueur) : le monde/voie, la boucle de rotation des obstacles (lames), la boucle des rails fantômes, `currentWorldIndex`/`CURRENT_ZONE`, et le flag `rebuilding` (vrai pendant la reconstruction d'un monde).
- `advanceWorld(player)` : quand un joueur atteint la fin, reconstruit le monde suivant **une seule fois** puis remet **TOUS** les chariots au départ (protégé par `rebuilding`).

### Économie / progression (par joueur)
- `pc.state.score` = pièces, `pc.state.xp`/`xpLevel`, `pc.state.cartTier` (chariot possédé), `reb`/`gainMul` (rebirth).
- `setWallet`, `addXp`, `award`, `completeStage`, `updateLeaderstats(player)` résolvent tous `pc = playerCarts[player]`.
- `DEBUG = true` → démarre riche (test) + prints `[DBG]`. À mettre `false` pour la prod.

## ⚠️ PIÈGES connus (appris à la dure — NE PAS refaire)
- **Ordre des fonctions** : une `local function` ne peut PAS être appelée avant sa ligne de définition (sinon `nil` au runtime). Bug vécu avec `setWallet`. luau-compile ne le détecte pas.
- **EditableMesh** : les meshes générés par code (`AssetService:CreateEditableMesh` + `CreateMeshPartAsync`) **se créent mais ne s'affichent pas de façon fiable** → abandonné. Utiliser **terrain** (volcan) ou **pièces** (hache).
- **Terrain `CrackedLava`** : rend **SOMBRE** même avec `SetMaterialColor`. Pour de la lave **brillante** → pièces **Neon** orange (pas le terrain CrackedLava). Le sol de lave de l'Enfer = des slabs Neon.
- **Volcan** : cône de **terrain** (`FillBall`, matière `Basalt` colorée **GRISE**) + coulées de lave en pièces **Neon jaune-orange**. Rocher gris + lave jaune = bon contraste (brun+orange se fondait → fade).
- Le cône-terrain (empilement de boules) est **plus large que le rayon nominal** (enveloppe des sphères) → placer les coulées avec assez de marge sinon elles **s'enterrent** sous la roche.
- Faire des **petits changements testables** : ce gros fichier est sensible.

## 📌 État au moment de l'écriture (snapshot — peut évoluer)
- ✅ Multijoueur : chariots par joueur (chacun ses pièces/XP/chariot).
- ✅ Enfer : sol de lave brillant, hub thème enfer, torches, obstacles (haches qui tournent), classement (leaderstats).
- 🔧 Volcan de l'Enfer : cône gris + coulées de lave jaune-orange (réglage visuel en cours).
- 🔧 Voies de départ (3 voies qui fusionnent) — réglage en cours.
- ⏳ À faire : téléport aux checkpoints depuis le hub ; embellir Ville / Montagne / Paradis comme l'Enfer.

## 🤝 Travailler à plusieurs (Git)
- **`git pull` AVANT de bosser.** Puis `git add . && git commit -m "..." && git push` pour partager.
- ⚠️ **Évitez d'éditer `src/BaladeEnChariot.server.lua` en même temps** (1 seul gros fichier = conflits faciles). Coordonnez-vous (ex : l'un le gameplay, l'autre le décor).
- Après un `git pull`, Rojo resynchronise les scripts tout seul dans Studio.

## 🗣️ Style attendu
- Équipe **francophone** → répondre en **français**.
- Le proprio teste en **jouant + captures d'écran** → privilégier des **petits changements**, et **valider la syntaxe (luau-compile)** avant de dire « teste ».
