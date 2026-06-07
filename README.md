# 🚂 Balade en chariot — projet Roblox (Rojo)

Jeu de chariot sur rails (multi-mondes), **100% généré par script** via Rojo.

## 🛠️ Installation (nouveau dev)
1. Installer **Roblox Studio**.
2. Dans Studio : onglet **Plugins** → installer le plugin **Rojo** (LPGhatguy).
3. Cloner ce dépôt : `git clone <url-du-depot>`
4. Ouvrir un **baseplate vide** dans Studio.
5. Lancer **`LANCER-ROJO.bat`** (Windows) → démarre le serveur Rojo (`rojo.exe` est inclus).
6. Dans Studio : plugin **Rojo → Connect** → les scripts se synchronisent dans le jeu.
7. **Play ▶** pour tester.

## 👥 Bosser à plusieurs (règles d'or)
- **`git pull`** AVANT de commencer à coder (récupérer les changements de l'autre).
- Coder (avec Claude ou à la main) dans `src/` et `client/`.
- Partager : `git add .` puis `git commit -m "ce que j'ai fait"` puis **`git push`**.
- ⚠️ Évitez de modifier **le même fichier en même temps** (sinon conflit). Répartissez-vous le boulot.

## 📂 Structure
- `src/` → **ServerScriptService** (le gros script serveur du jeu)
- `client/` → **StarterPlayerScripts** (caméra du chariot, menu chariots)
- `default.project.json` → config Rojo (quel dossier va où)
- `LANCER-ROJO.bat` + `rojo.exe` → pour lancer la synchro
