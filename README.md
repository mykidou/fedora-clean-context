# Contexte Technique : Conteneur `fedora-clean` sur GLF-OS (NixOS)

Ce dépôt contient l'état exact, fonctionnel et vérifié du conteneur système `fedora-clean` (Fedora 44 + KDE Plasma 6 Wayland imbriqué avec accélération NVIDIA RTX 4080 et pont audio PipeWire) afin que **Gemini Flash Lite** (ou tout autre modèle IA) puisse reprendre le projet sans aucune perte de contexte.

## Règles impératives pour l'IA (Gemini Flash Lite)
1. **Format des scripts Bash :** Toujours commencer par `clear`, journaliser dans `/var/log/<nom>.log` via `2>&1 | sudo tee /var/log/<nom>.log`, indiquer l'emplacement du log après l'exécution et expliquer comment vérifier le succès de l'étape.
2. **Protocole de modification de code :**
   - **Identifier et demander avant de supprimer :** Ne jamais supprimer une section sans demander : *"La section XYZ me semble obsolète car [raison]. Souhaitez-vous que je la retire en même temps que j'applique les modifications demandées ?"*
   - **Modifier avec contexte :** Toujours indiquer **AJOUTER**, **REMPLACER** ou **SUPPRIMER**, fournir le bloc complet, et inclure les lignes existantes juste avant et juste après comme point d'ancrage.
   - Toujours utiliser l'espace standard (` `) et jamais d'espace insécable.
3. **Architecture et garde-fous techniques :**
   - **Hôte NixOS :** `/etc/nixos/customConfig/fedora-clean.nix` monte `/mnt/ssd1to_linux/containers/fedora-clean/rootfs.img` (Btrfs, sous-volume `@root`, snapshot `@root-clean`) sur `/var/lib/machines/fedora-clean`.
   - **Session graphique invitée :** `/usr/local/libexec/fedora-clean-plasma-session` est lancé automatiquement au boot du conteneur par `/etc/systemd/user/fedora-clean-plasma.service` (via `linger` sur `myke`, UID 1000).
   - **INTERDICTION 1 :** Ne jamais appeler `/usr/bin/startplasma-wayland` dans `INNER_SESSION` (provoque un double `kwin_wayland` et fait clignoter l'écran).
   - **INTERDICTION 2 :** Ne jamais activer `xdg-desktop-portal.service` ni lancer `xdg-desktop-portal-kde` (bloque D-Bus après l'ouverture de la première application). Garder `GTK_USE_PORTAL=0`.
   - **INTERDICTION 3 :** Ne pas exécuter `systemctl --user restart fedora-clean-plasma.service` juste après `sudo fedora-clean-control start` ou `restart`, car le service démarre déjà automatiquement avec le conteneur.

## Fichiers du dépôt
- `host-nixos/fedora-clean.nix` : Module NixOS hôte.
- `guest-fedora/fedora-clean-plasma-session` : Script de lancement Wayland/KDE dans le conteneur.
- `guest-fedora/fedora-clean-plasma.service` : Service systemd user du conteneur.
