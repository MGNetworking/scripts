# Cadrage — Linux/

Ce document **engage** : besoin du dossier et contrat de chacun de ses scripts
([décision 49](../orchestration/decisions.md)). Le [README](README.md) et ceux des
sous-dossiers **expliquent** (usage, exemples, risques). Tout ce qui figure au contrat
est réputé utilisé : le modifier est une rupture. Un changement incompatible ne touche
jamais le script existant : nouveau script, l'ancien déprécié avec une date.

État initial : chaque contrat décrit le comportement **actuel** du script, lu dans son
code le 2026-09-17, et non un comportement souhaité. Un écart entre le code et son aide
ou son README est consigné au registre, pas corrigé ici.

## Besoin

Préparer, sécuriser et exploiter le système d'un serveur Linux par des commandes
rejouables, avant et indépendamment de Docker et de Kubernetes : nom d'hôte, fuseau,
swap, journaux, paquets, comptes, planification, diagnostics ; puis SSH, pare-feu et
fail2ban ; enfin la distribution K3s elle-même.

Contexte visé : un VPS Debian 12 ou 13, ou Ubuntu 22.04 ou 24.04 (décision 14), administré
en root par un compte non-root membre de `sudo` (décision 20), en K3s mono-nœud
(décision 23) quand il porte un cluster.

**Hors besoin** : administrer un cluster par `kubectl` ou `helm` (`Kubernetes/`) ; le
moteur Docker (`Docker/`) ; les partitions de swap ; les nœuds agents K3s et la haute
disponibilité ; supprimer ou verrouiller un compte, définir un mot de passe ; retirer une
règle de pare-feu ; sauvegarder les données d'un cluster.

**Conventions de tout le dossier** :

- codes de retour : `0` succès ou état déjà voulu, `1` échec nommé, `2` usage refusé ; les
  écarts de chaque script sont dans son contrat ; une commande externe en échec non
  interceptée sort par `set -e` avec son propre code, et non 1 (A132) ;
- chaque script écrit son journal sous `LOG_DIR` par le socle (`lib/common.sh`) : ce
  n'est pas répété dans les contrats ;
- **hors contrat** : `RACINE_TEST`, suivie seulement si `/.dockerenv` existe (tests en
  conteneur) ; le libellé exact des messages ; la mise en page des rubriques et
  tableaux ; les lignes de commentaire des fichiers déposés.

## Ensembles

### Socle du serveur

- **Fonction globale** : une fois ses scripts appliqués, la machine a son répertoire de
  journaux et leur rotation, son nom d'hôte cohérent avec `/etc/hosts`, son fuseau, son
  fichier d'échange inscrit dans `/etc/fstab`, ses paquets à jour, un compte
  d'administration à clé SSH, et la mise à jour hebdomadaire planifiée dans
  `/etc/cron.d/mgnetworking`. Les diagnostics la relèvent sans rien modifier.
- **Scripts membres et ordre** (`Linux/System/`) :
  1. `configure-logging.sh`, `configure-hostname.sh`, `configure-timezone.sh` (avant
     `configure-cron.sh`, dont l'horaire suit le fuseau), `configure-swap.sh`,
     `update-system.sh`, `manage-users.sh` (avant `Linux/Security/`), puis
     `configure-cron.sh` ;
  2. à tout moment : `system-info.sh`, `check-disk.sh`, `check-memory.sh`,
     `check-services.sh` ;
  3. à la demande : `notify-failure.sh` (appelé par personne à ce jour),
     `reboot-system.sh`.
- **Conventions communes** :
  - les diagnostics (`system-info.sh`, `check-*.sh`) n'exigent aucun privilège et ne
    rendent jamais 1 sur un constat ; les autres exigent root, `--dry-run` compris, sauf
    `notify-failure.sh`, `configure-swap.sh` sans taille et `configure-timezone.sh --list` ;
  - une valeur fautive tapée sur la ligne de commande rend 2 ; venue de
    `config/server.env`, elle rend un `[WARN]` et un repli dans `check-disk.sh` et
    `check-memory.sh`, et 2 ailleurs ;
  - confirmation : `-y`/`--yes` confirme ; un `ASSUME_YES` hérité confirme aussi, sauf
    dans `reboot-system.sh` ; une confirmation refusée, ou lue sur une entrée sans
    terminal, abandonne en **0** sans rien modifier ; `manage-users.sh` et
    `notify-failure.sh` ne demandent aucune confirmation ;
  - fichiers système remplacés : `/etc/hosts` et `/etc/fstab` sauvegardés en
    `<fichier>.bak-AAAAMMJJ-HHMMSS` avant modification ;
  - réglages dans `config/server.env` : `SRV_HOSTNAME`, `SRV_TIMEZONE`, `SRV_SWAP_SIZE`,
    `SRV_CRON_UPDATE_SYSTEM`, `SRV_DISK_SEUIL`, `SRV_DISK_REPERTOIRE`, `SRV_MEM_SEUIL`,
    `SRV_MEM_TOP`, `SRV_ADMIN_UTILISATEUR`, `SRV_ADMIN_CLE_PUBLIQUE`, et `LOG_DIR`
    (défaut du socle : `/var/log/mgnetworking` en root) ; alertes dans
    `config/notify.env`.

### Sécurité du serveur

- **Fonction globale** : une fois ses scripts appliqués, ufw refuse l'entrant sauf SSH
  et les ports déclarés, sshd refuse le mot de passe, le clavier interactif et la
  connexion directe de root, et fail2ban surveille sshd. Les audits relèvent comptes,
  ports et bilan de sécurité sans rien modifier.
- **Scripts membres et ordre** (`Linux/Security/`) :
  1. à tout moment : `audit-users.sh`, `audit-ports.sh`, `security-check.sh` ;
  2. après `Linux/System/manage-users.sh` : `configure-firewall.sh`,
     `configure-ssh.sh`, `configure-fail2ban.sh`, puis `disable-root-login.sh`.
- **Conventions communes** :
  - audits : aucun privilège exigé ; sans root, ce qui ne se lit pas est annoncé, jamais
    compté comme défaut ;
  - scripts qui modifient : validation des options et des valeurs avant root ;
    `--dry-run` n'exige ni root ni distribution et n'écrit rien ; hors `--dry-run`, root
    et Debian ou Ubuntu ; `-y`/`--yes` seul confirme, obligatoire hors terminal (sinon
    1) ; `ASSUME_YES` hérité ignoré ; confirmation refusée : 1 ;
  - garde de la décision 20 : `configure-ssh.sh` et `disable-root-login.sh` refusent
    sans compte non-root, membre de `sudo`, à clé dans `authorized_keys` ;
    `configure-firewall.sh` pose et relit la règle SSH avant d'activer ufw ;
  - fichiers déposés dans des répertoires `.d` en 0644 par temporaire puis `mv`, jamais
    dans le fichier principal ; SSH rechargé (`reload`), jamais redémarré ; état
    antérieur restauré si la validation ou le rechargement échoue ;
  - réglages dans `config/server.env` : `SRV_SSH_PORT`, `SRV_FIREWALL_PORTS`,
    `SRV_ADMIN_UTILISATEUR`.

### Gestion de K3s

- **Fonction globale** : une fois ses scripts appliqués, la machine porte un K3s serveur
  mono-nœud installé par l'installateur officiel, son service activé, son
  `config.yaml` tenu par le dépôt, et un diagnostic qui dit si le cluster est sain.
- **Scripts membres et ordre** (`Linux/K3s/`) : `install-k3s.sh`, puis
  `configure-k3s.sh` ; `upgrade-k3s.sh` plus tard, une mineure à la fois ;
  `uninstall-k3s.sh` en dernier ; `verify-k3s.sh` à tout moment, et en fin
  d'installation, de configuration et de mise à niveau, qui lisent son code.
- **Conventions communes** :
  - root exigé, sauf `--dry-run` de `install-k3s.sh` et `configure-k3s.sh` ;
  - installateur `https://get.k3s.io` téléchargé en HTTPS seul dans un temporaire,
    exécuté par `sh` puis retiré, jamais `curl | sh` ; désinstallation par le seul
    `/usr/local/bin/k3s-uninstall.sh` (décision 47) ;
  - variables héritées neutralisées : `INSTALL_K3S_VERSION`, `INSTALL_K3S_CHANNEL`,
    `K3S_URL` et `K3S_TOKEN` par `install-k3s.sh` ; tout `INSTALL_K3S_*`, `K3S_URL`
    et `K3S_TOKEN` par `upgrade-k3s.sh` ; tout `INSTALL_K3S_*` et `K3S_*` par
    `uninstall-k3s.sh` ; aucune par `verify-k3s.sh` et `configure-k3s.sh` ;
  - `-y`/`--yes` seul confirme, obligatoire hors terminal (sinon 1) ; `ASSUME_YES`
    hérité ignoré (décision 45) ; confirmation refusée : 1 ;
  - aucun script n'affiche ni kubeconfig, ni jeton de nœud, ni Secret ; aucun ne touche
    au pare-feu ;
  - réglages dans `config/server.env` : `SRV_K3S_VERSION`, `SRV_K3S_TLS_SAN`.

## Scripts individuels

Aucun dans `Linux/`.

## Contrats

### system-info.sh — ensemble « Socle du serveur »

- Besoin : l'état du système en un coup d'œil.
- Fait : distribution, noyau, architecture, processeur et charge, mémoire (`free`, sinon
  `/proc/meminfo`), systèmes de fichiers hors tmpfs, devtmpfs, overlay, squashfs et
  `/snap/`, adresses IPv4 globales et passerelle, utilisateur, dépôt, uptime, date et
  fuseau ; une information absente s'affiche « non disponible ». Ne fait pas : juger.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 relevé affiché ; 1 `/etc/os-release` illisible ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `/etc/os-release`, `/proc/cpuinfo`, `/proc/loadavg`, `/proc/meminfo`, `df`,
  `ip`, `hostname`, `uptime`, `timedatectl` ou `/etc/timezone`.
- État : actif.

### update-system.sh — ensemble « Socle du serveur »

- Besoin : mettre à jour les paquets installés.
- Fait : `DEBIAN_FRONTEND=noninteractive` ; `apt-get update` (`--dry-run` compris) ;
  paquets listés par `apt-get -s upgrade` ; aucun : 0 ; sinon liste, confirmation,
  `apt-get upgrade -y` ; paquets retenus et `/var/run/reboot-required` signalés en
  `[WARN]`. Ne fait pas : `dist-upgrade`, supprimer un paquet, redémarrer.
- Options et défauts : `--dry-run` (index rafraîchi, liste seule) ; `-y`, `--yes` ;
  `-h`, `--help`.
- Codes de retour : 0 à jour, mis à jour, `--dry-run` ou confirmation refusée ; 1 root,
  distribution, `apt-get` absent ; échec d'`apt-get update` ou `upgrade` : code
  d'`apt-get` (A132) ; 2 option inconnue.
- Modifie sur la machine : paquets installés, index apt.
- Lit : index apt, `/var/run/reboot-required` et `.pkgs`.
- État : actif.

### configure-logging.sh — ensemble « Socle du serveur »

- Besoin : le répertoire des journaux du dépôt et leur rotation.
- Fait : crée `LOG_DIR` s'il manque et lui réapplique 0750 `root:adm` (`root:root` sans
  groupe `adm`) à chaque passage ; règle `/etc/logrotate.d/<nom de LOG_DIR>` :
  `<LOG_DIR>/*.log`, `weekly`, `rotate 8`, `compress`, `delaycompress`, `missingok`,
  `notifempty`, `create 0640 root <groupe>` ; identique : 0 ; différente : différence,
  confirmation ; écrite en 0644 puis contrôlée par `logrotate -d`. Ne fait pas : lancer
  une rotation, supprimer un journal.
- Options et défauts : `--dry-run` ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 règle en place, écrite, `--dry-run` ou remplacement refusé ; 1 root,
  `logrotate` ou `/etc/logrotate.d` absent, `basename` en échec, règle rejetée par
  `logrotate -d` ; 2 option inconnue.
- Modifie sur la machine : répertoire `LOG_DIR` (droits), règle logrotate.
- Lit : `LOG_DIR`, groupe `adm`, règle en place.
- État : actif.

### configure-hostname.sh — ensemble « Socle du serveur »

- Besoin : un nom d'hôte cohérent avec `/etc/hosts`.
- Fait : nom validé (253 caractères, segments de 1 à 63 en lettres, chiffres et tirets,
  sans tiret en bord) avant root ; conforme si `hostname` rend le nom et qu'une ligne
  `127.0.1.1` le contient : 0 ; sinon résumé, confirmation ; nom posé par `hostnamectl
  set-hostname`, sinon `hostname` et `/etc/hostname` ; `/etc/hosts` sauvegardé, la
  première ligne `127.0.1.1` remplacée par `127.0.1.1 <nom> [<nom court>]` et les autres
  retirées, ou la ligne insérée après `127.0.0.1` (en fin à défaut) ; nom relu, écart en
  `[WARN]`. Ne fait pas : redémarrer, toucher K3s.
- Options et défauts : `[nom]` positionnel (défaut `SRV_HOSTNAME`) ; `--dry-run` ; `-y`,
  `--yes` ; `-h`, `--help`.
- Codes de retour : 0 appliqué, conforme, `--dry-run` ou confirmation refusée ; 1 root,
  `hostname` absent, `date` ou `mktemp` en échec ; 2 option inconnue, deux noms, nom
  absent ou invalide.
- Modifie sur la machine : nom d'hôte, `/etc/hostname`, `/etc/hosts`,
  `/etc/hosts.bak-AAAAMMJJ-HHMMSS[-n]`.
- Lit : `SRV_HOSTNAME`, `hostname`, `/etc/hosts`.
- État : actif.

### configure-timezone.sh — ensemble « Socle du serveur »

- Besoin : le fuseau horaire du serveur.
- Fait : fuseau refusé s'il commence par `posix/`, `right/` ou `/`, finit en `.tab` ou
  `.list`, contient `..`, ou n'existe pas sous `/usr/share/zoneinfo` ; fuseau courant lu
  par `timedatectl`, `/etc/timezone` puis le lien `/etc/localtime` ; identique : 0 ;
  sinon confirmation, `timedatectl set-timezone`, sinon `ln -sf` vers `/etc/localtime` ;
  `/etc/timezone`, s'il existe, réécrit ; fuseau, `/etc/localtime` et `/etc/timezone`
  relus. Ne fait pas : décaler les horaires de cron.
- Options et défauts : `[fuseau]` positionnel (défaut `SRV_TIMEZONE`) ; `--list` (liste
  les fuseaux et sort en 0, sans root, dès sa lecture) ; `--dry-run` ; `-y`, `--yes` ;
  `-h`, `--help`.
- Codes de retour : 0 appliqué, déjà en place, `--dry-run`, `--list` ou confirmation
  refusée ; 1 root, `/etc/timezone` illisible, relecture en écart ; 2 option inconnue,
  deux fuseaux, fuseau absent, invalide ou inconnu.
- Modifie sur la machine : fuseau système, `/etc/localtime`, `/etc/timezone`.
- Lit : `SRV_TIMEZONE`, `/usr/share/zoneinfo`, `timedatectl`, `/etc/timezone`,
  `/etc/localtime`.
- État : actif.

### configure-swap.sh — ensemble « Socle du serveur »

- Besoin : un fichier d'échange de la taille voulue, actif et persistant.
- Fait : sans taille, affiche swap actif, mémoire et entrées `swap` de `/etc/fstab`, puis
  0 sans root ; avec une taille : refus sur btrfs ou zfs et si l'espace libre manque ;
  fichier actif à la taille voulue et inscrit dans `/etc/fstab` : 0 ; sinon plan,
  confirmation ; `swapoff` refusé si le swap occupé dépasse `MemAvailable` ; fichier
  supprimé puis recréé (`fallocate`, sinon `dd`), 0600 `root:root`, `mkswap`, `swapon`
  (échec : fichier supprimé, fstab intact) ; ligne `<fichier> none swap sw 0 0` ajoutée à
  `/etc/fstab` si absente, après sauvegarde ; présence dans `/proc/swaps` relue. Un
  fichier actif à la bonne taille mais absent de fstab est recréé (A133). Ne fait pas :
  gérer une partition de swap, créer un répertoire.
- Options et défauts : `[taille]` positionnel, `2G`, `512M` ou mégaoctets seuls, unités
  G, GB, GO, M, MB, MO sans casse, 64 Mo au moins (défaut `SRV_SWAP_SIZE` ; absente :
  état seul) ; `--file <chemin>` (défaut `/swapfile`, absolu, ni lien symbolique, ni
  objet autre qu'un fichier, ni fichier existant qui ne soit pas un swap, parent
  existant) ; `--dry-run` ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 état affiché, déjà conforme, configuré, `--dry-run` ou confirmation
  refusée ; 1 root, `mkswap`, `swapon` ou `swapoff` absent, btrfs ou zfs, espace
  insuffisant, swap trop occupé pour `swapoff`, `swapon` en échec, `date`, `df`, `stat`
  en échec, swap absent après activation ; échec de `swapoff`, `dd` ou `mkswap` : code de
  la commande (A132) ; 2 option inconnue, deux tailles, taille ou unité invalide, sous
  64 Mo, `--file` sans valeur ou refusé.
- Modifie sur la machine : le fichier d'échange, l'état du swap, `/etc/fstab`,
  `/etc/fstab.bak-AAAAMMJJ-HHMMSS[-n]`.
- Lit : `SRV_SWAP_SIZE`, `/proc/swaps`, `/proc/meminfo`, `free`, `/etc/fstab`, `df`,
  `systemd-detect-virt` (conteneur : `[WARN]`).
- État : actif.

### manage-users.sh — ensemble « Socle du serveur »

- Besoin : un compte d'administration non-root, à clé SSH, prérequis de la sécurisation.
- Fait : compte créé par `useradd --create-home --shell` s'il manque (shell d'un compte
  existant inchangé) ; ajouté à chaque groupe demandé qui lui manque (`usermod --append
  --groups`) ; avec `--sudo-sans-mot-de-passe`, `/etc/sudoers.d/mgnetworking-<nom>`
  (`<nom> ALL=(ALL) NOPASSWD:ALL`, 0440, `root:root`, contrôlé par `visudo -c` s'il est
  présent) ; clé ajoutée à `~/.ssh/authorized_keys` si la ligne manque, `~/.ssh` en 0700
  et `authorized_keys` en 0600, au compte, réappliqués à chaque passage ; sans
  confirmation. Ne fait pas : définir, lire ou demander un mot de passe, générer une clé,
  supprimer ou verrouiller un compte, créer un groupe, installer sudo, écrire à travers
  un lien symbolique.
- Options et défauts : `--utilisateur <nom>` (défaut `SRV_ADMIN_UTILISATEUR`) ;
  `--cle-fichier <chemin>` (défaut `SRV_ADMIN_CLE_PUBLIQUE`, une seule ligne utile, type
  `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-*` ou `sk-*`) ; `--groupe <nom>` (répétable) ;
  `--sudo` ; `--sudo-sans-mot-de-passe` (implique `--sudo`) ; `--shell <chemin>` (défaut
  `/bin/bash`, absolu) ; `--dry-run` ; `-h`, `--help`.
- Codes de retour : 0 compte conforme ou `--dry-run` ; 1 root, distribution, `useradd`,
  `usermod`, `getent`, `id`, `stat`, `cut` ou `mktemp` absent, groupe `sudo` ou groupe
  demandé inconnu, `/etc/sudoers.d` absent, règle refusée par `visudo`, `~/.ssh` ou
  `authorized_keys` lien symbolique ; échec de `useradd` ou `usermod` : code de la
  commande (A132) ; 2 option inconnue ou sans valeur, compte absent, `root`, nom invalide
  ou de plus de 32 caractères, shell non absolu, clé introuvable ou invalide.
- Modifie sur la machine : compte et home, appartenance aux groupes, règle sudoers,
  `~/.ssh/authorized_keys`.
- Lit : `SRV_ADMIN_UTILISATEUR`, `SRV_ADMIN_CLE_PUBLIQUE`, le fichier de clé, `getent`.
- État : actif.

### configure-cron.sh — ensemble « Socle du serveur »

- Besoin : planifier sans humain la mise à jour des paquets.
- Fait : horaire validé avant root (cinq champs, caractères `0-9A-Za-z*,/-`, raccourcis
  `@` refusés), quelle qu'en soit l'origine ; refus si `update-system.sh` manque, si son
  chemin contient une espace ou un `%`, sans démon `cron` ou `crond` (`[WARN]` sous
  `--dry-run`) ou sans `/etc/cron.d` ; planification de `update-system.sh` trouvée
  ailleurs dans `/etc/cron.d` ou `/etc/crontab` : `[WARN]` ; dépose
  `/etc/cron.d/mgnetworking` : `SHELL=/bin/bash`, `PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin`,
  `<horaire> root /bin/bash <dépôt>/Linux/System/update-system.sh --yes >/dev/null` ;
  identique : propriétaire `root:root` et mode 0644 rétablis, relus, 0 ; différent :
  différence, confirmation ; écrit par temporaire puis `mv`, contenu, propriétaire et mode
  relus. Ne fait pas : installer cron, recharger cron, planifier un autre script.
- Options et défauts : `--horaire "<cinq champs>"` (défaut `SRV_CRON_UPDATE_SYSTEM`,
  sinon `0 4 * * 1`) ; `--dry-run` ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 fichier en place et conforme, `--dry-run` ou remplacement refusé ;
  1 root, distribution, script à planifier absent, chemin du dépôt avec espace ou `%`,
  démon cron ou `/etc/cron.d` absent, `stat` en échec, relecture en écart ; 2 option
  inconnue, `--horaire` sans valeur, horaire invalide.
- Modifie sur la machine : `/etc/cron.d/mgnetworking`.
- Lit : `SRV_CRON_UPDATE_SYSTEM`, `LOG_DIR` (commentaire du fichier), `/etc/cron.d`,
  `/etc/crontab`.
- État : actif.

### check-disk.sh — ensemble « Socle du serveur »

- Besoin : l'occupation du stockage.
- Fait : occupation des systèmes de fichiers et des inodes (`df`, borné à 15 s si
  `timeout` existe), pseudo-systèmes écartés sauf `overlay` ; `[WARN]` pour tout
  système dont blocs ou inodes atteignent le seuil ; périphériques par `lsblk`, sinon
  `/proc/partitions` ; sous-répertoires les plus lourds par `du -x --max-depth=1` ; commande
  absente ou en échec : `[WARN]` et « non disponible ». Ne fait pas : juger, nettoyer.
- Options et défauts : `--seuil <1-100>` (défaut `SRV_DISK_SEUIL`, sinon 85) ;
  `--repertoire <chemin>` (défaut `SRV_DISK_REPERTOIRE`, sinon `/`) ; `--top <1-100>`
  (défaut 10) ; `--sans-repertoires` ; `--tous` (aucun système écarté) ; `-h`, `--help`.
  Entiers sans zéro initial. `SRV_DISK_SEUIL` refusé : `[WARN]`, 85 ;
  `SRV_DISK_REPERTOIRE` inaccessible : `[WARN]`, section sautée.
- Codes de retour : 0 diagnostic produit, seuil dépassé et valeur de `config/` refusée
  compris ; 2 option inconnue ou sans valeur, `--seuil` ou `--top` invalide,
  `--repertoire` commençant par un tiret ou inaccessible.
- Modifie sur la machine : rien.
- Lit : `SRV_DISK_SEUIL`, `SRV_DISK_REPERTOIRE`, `df`, `lsblk`, `/proc/partitions`, `du`.
- État : actif.

### check-memory.sh — ensemble « Socle du serveur »

- Besoin : l'état de la mémoire et du swap.
- Fait : mémoire vive par `free -k`, sinon `/proc/meminfo` ; `[WARN]` si la mémoire non
  disponible (totale moins disponible) atteint le seuil ; swap et zones de `/proc/swaps`,
  `[WARN]` seulement si swap et mémoire atteignent tous deux le seuil ; processus
  classés par mémoire résidente (`ps`). Ne fait pas : juger, libérer de la mémoire.
- Options et défauts : `--seuil <1-100>` (défaut `SRV_MEM_SEUIL`, sinon 90) ; `--top
  <1-100>` (défaut `SRV_MEM_TOP`, sinon 10) ; `-h`, `--help`. Valeur de `config/`
  refusée : `[WARN]` et défaut.
- Codes de retour : 0 diagnostic produit, seuil dépassé et valeur de `config/` refusée
  compris ; 2 option inconnue ou sans valeur, `--seuil` ou `--top` invalide.
- Modifie sur la machine : rien.
- Lit : `SRV_MEM_SEUIL`, `SRV_MEM_TOP`, `free`, `/proc/meminfo`, `/proc/swaps`, `ps`.
- État : actif.

### check-services.sh — ensemble « Socle du serveur »

- Besoin : l'état des services systemd, en inventaire ou pour un service nommé.
- Fait : sans option, état global (`systemctl is-system-running`), services actifs et
  services en échec (`[WARN]` par service) ; avec `--service`, chargement, activation,
  exécution et dernier démarrage (`systemctl show`), code porté par l'état. Ne fait pas :
  `start`, `stop`, `restart`, `enable`, `disable`, diagnostiquer une unité autre qu'un
  service.
- Options et défauts : `--service <nom>` (suffixe `.service` ajouté s'il manque) ; `-h`,
  `--help`.
- Codes de retour : 0 inventaire produit (services en échec compris), ou service actif ;
  1 `systemctl` absent, service inconnu, masqué, non chargé, en échec ou inactif, état
  impossible à établir ; 2 option inconnue, `--service` sans valeur, nom commençant par
  un tiret, caractère hors `A-Za-z0-9@:._\-`, suffixe d'un autre type d'unité ou point
  sans type connu.
- Modifie sur la machine : rien.
- Lit : `systemctl is-system-running`, `list-units`, `show`.
- État : actif.

### notify-failure.sh — ensemble « Socle du serveur »

- Besoin : alerter l'échec d'un script planifié.
- Fait : message ntfy (texte : script, code, machine, date, journal
  `<LOG_DIR>/<script sans .sh>.log`) ou webhook (objet JSON `script`, `code`, `machine`,
  `date`, `journal`) ; `POST` par `curl --config -`, URL et en-têtes passés par l'entrée
  standard, `Authorization: Bearer` si un jeton est fourni ; réponse 2xx exigée. Ne fait
  pas : afficher l'URL ou le jeton (seul l'hôte est nommé), réessayer, être appelé par un
  autre script à ce jour.
- Options et défauts : `--script <nom>` (requis) ; `--code <entier>` (requis) ; `--config
  <nom>` (défaut `notify`, fichier absent toléré) ; `--dry-run` (méthode, format, hôte et
  message, sans configuration ni `curl` exigés) ; `-h`, `--help`.
- Codes de retour : 0 alerte émise ou `--dry-run` ; 1 `NOTIFY_URL` absente ou ni `http`
  ni `https`, fichier de contexte illisible, `curl` absent ou en échec, réponse hors 2xx ;
  2 option inconnue ou sans valeur, `--script` absent ou contenant `/`, espace, `"` ou
  `\`, `--code` absent, non entier ou à zéro de tête, `NOTIFY_FORMAT` inconnu
  (`--dry-run` compris).
- Modifie sur la machine : rien ; émet une requête HTTP.
- Lit : `config/<nom>.env` : `NOTIFY_URL`, `NOTIFY_FORMAT` (`ntfy` défaut ou `webhook`),
  `NOTIFY_JETON`, `NOTIFY_DELAI` (défaut 10 s, invalide : `[WARN]` et 10) ; `LOG_DIR`.
- État : actif.

### reboot-system.sh — ensemble « Socle du serveur »

- Besoin : redémarrer la machine sans casser une opération en cours.
- Fait : refus si `dpkg`, `apt`, `apt-get`, `aptitude` ou `unattended-upgr` tourne ;
  résumé (machine, date, uptime, `/run/reboot-required` et paquets, sessions de `who` en
  `[WARN]`, sans effet sur la décision) ; avec `--si-necessaire` et sans
  `/run/reboot-required` : 0 ; confirmation, puis `systemctl reboot`. Ne fait pas :
  `shutdown`, `halt`, `telinit`, attendre la fin des sessions.
- Options et défauts : `--si-necessaire` ; `--dry-run` (contrôles et commande, sans
  redémarrer) ; `-y`, `--yes` (seuls à confirmer ; `ASSUME_YES` hérité ignoré) ; `-h`,
  `--help`.
- Codes de retour : 0 redémarrage demandé, rien à faire, `--dry-run` ou confirmation
  refusée ; 1 root, distribution, `systemctl` absent, opération de paquets en cours,
  `systemctl reboot` en échec ; 2 option inconnue.
- Modifie sur la machine : **redémarre** la machine.
- Lit : `/proc/*/comm`, `/proc/uptime`, `/run/reboot-required` et `.pkgs`, `who`.
- État : actif.

### audit-users.sh — ensemble « Sécurité du serveur »

- Besoin : relever les comptes à risque.
- Fait : quatre rubriques : comptes à UID 0 (autre que root : `[WARN]`), comptes à shell
  de connexion (présent dans `/etc/shells`, ni `nologin`, ni `false`, ni `true`), membres
  de `sudo`, `adm` et `docker` (groupe principal compris), comptes au mot de passe vide
  (`[WARN]` chacun) ; fichier illisible : `[WARN]` et « non vérifié », audit poursuivi.
  Ne fait pas : modifier un compte, un groupe, une clé ou une session.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 audit produit, comptes signalés compris ; 1 `getent` absent ou
  `getent passwd` en échec ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `getent passwd`, `getent group`, `FICHIER_SHELLS` (défaut `/etc/shells`),
  `FICHIER_SHADOW` (défaut `/etc/shadow`).
- État : actif.

### audit-ports.sh — ensemble « Sécurité du serveur »

- Besoin : relever les ports en écoute et leur exposition.
- Fait : un appel `ss -H -tulpn` ; une ligne par écoute : protocole, portée (« local » sur
  `127.*`, `[::1]`, `[::ffff:127.*]`, portée `%if` ignorée ; « exposé » sinon), adresse,
  port, processus (« inconnu (root requis) » sans root) ; résumé : écoutes, écoutes
  exposées, ports exposés distincts et leur liste. Ne fait pas : fermer un port, lire le
  pare-feu.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 relevé produit, vide compris ; 1 `ss` absent ou en échec ; 2 option
  inconnue.
- Modifie sur la machine : rien.
- Lit : `ss -H -tulpn`.
- État : actif.

### security-check.sh — ensemble « Sécurité du serveur »

- Besoin : un bilan de sécurité dont le code de retour sert à cron.
- Fait : une ligne par contrôle, statut `PASS`, `WARNING`, `FAIL` ou `INFO` : SSH
  (`sshd -T` : `PasswordAuthentication` et `PermitRootLogin` à `no`, sinon `FAIL`) ;
  pare-feu (`ufw status verbose` : inactif ou entrée ni `deny` ni `reject` : `FAIL`) ;
  fail2ban (`fail2ban-client status` : prison `sshd` absente : `WARNING`) ; comptes à UID
  0 autres que root : `FAIL` ; mises à jour en attente (`apt-get -s upgrade`) :
  `WARNING`. Commande absente ou en échec : `WARNING` pour ufw et fail2ban, `INFO` pour
  les autres ; ufw et fail2ban sans root : `INFO`. Chaque commande bornée par `timeout`
  s'il existe, en `LC_ALL=C`. Ne fait pas : corriger, installer.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 aucun `FAIL` ; 1 au moins un `FAIL` ; 2 option inconnue, `BORNE`
  non entière ou nulle (vérifiée avant les options, `--help` compris).
- Modifie sur la machine : rien.
- Lit : `BORNE` (défaut 10 s), `sshd -T`, `ufw status verbose`, `fail2ban-client status`,
  `getent passwd`, `apt-get -s upgrade`.
- État : actif.

### configure-firewall.sh — ensemble « Sécurité du serveur »

- Besoin : un pare-feu ufw qui refuse l'entrant sans couper SSH.
- Fait : ports validés avant root ; hors `--dry-run`, refus si le port de sshd (`sshd -T`,
  sinon `ss -tlnp`) diffère de `SRV_SSH_PORT` (invérifiable : `[WARN]`) ; ufw absent :
  installé par `apt-get update` et `apt-get install -y ufw` avant la confirmation ; plan
  des seules commandes manquantes d'après `ufw show added` et `ufw status verbose` :
  `allow <port SSH>/tcp`, `allow` des autres ports, `default deny incoming`, `default
  allow outgoing`, `--force enable` si inactif ; refus si une règle `deny` porte déjà sur
  le port SSH ; règle SSH relue avant l'activation, absente : refus. Ne fait pas :
  supprimer une règle, changer le port de sshd.
- Options et défauts : `--port <n/tcp|n/udp>` (répétable, 1 à 65535) ; `--dry-run` (sans
  root ni installation) ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 appliqué, conforme ou `--dry-run` ; 1 root, distribution, port de
  sshd différent, ufw introuvable après installation, règle `deny` sur SSH, hors terminal
  sans `--yes`, confirmation refusée, règle SSH absente après pose ; échec d'`apt-get` ou
  d'une commande `ufw` : code de la commande (A132) ; 2 option inconnue, `--port` sans
  valeur ou mal formé, `SRV_SSH_PORT` ou port de `SRV_FIREWALL_PORTS` mal formé.
- Modifie sur la machine : paquet ufw, règles `allow`, politiques par défaut, activation.
- Lit : `SRV_SSH_PORT` (défaut 22), `SRV_FIREWALL_PORTS` (séparés par des espaces),
  `sshd -T`, `ss -tlnp`, `ufw status verbose`, `ufw show added`.
- État : actif.

### configure-ssh.sh — ensemble « Sécurité du serveur »

- Besoin : refuser l'authentification SSH par mot de passe.
- Fait : garde de la décision 20 ; exige que `sshd_config` inclue `sshd_config.d/*.conf`
  et que ce répertoire existe ; dépose `10-mgnetworking.conf` : `PasswordAuthentication
  no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes` ; identique : rien
  réécrit ni rechargé ; sinon `sshd -t -f <sshd_config>`, puis `systemctl reload ssh` ;
  l'un en échec : fichier précédent restauré (ou retiré). Ne fait pas : changer le port,
  `restart`, créer `sshd_config.d`, toucher `sshd_config`.
- Options et défauts : `--utilisateur <nom>` (défaut `SRV_ADMIN_UTILISATEUR`) ;
  `--dry-run` ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 appliqué, conforme ou `--dry-run` ; 1 aucun compte nommé, `root`,
  root manquant, distribution, `sshd` ou `systemctl` absent, `sshd_config` illisible ou
  sans `Include`, répertoire absent, compte introuvable, à UID 0, hors `sudo` ou sans clé,
  hors terminal sans `--yes`, confirmation refusée, `sshd -t` ou rechargement en échec ;
  2 option inconnue, `--utilisateur` sans valeur, nom invalide ou de plus de 32
  caractères.
- Modifie sur la machine : `<SSHD_CONFIG_D>/10-mgnetworking.conf`, rechargement de ssh.
- Lit : `SRV_ADMIN_UTILISATEUR`, `SSHD_CONFIG` (défaut `/etc/ssh/sshd_config`),
  `SSHD_CONFIG_D` (défaut `/etc/ssh/sshd_config.d`), `getent`, `authorized_keys` du
  compte.
- État : actif.

### disable-root-login.sh — ensemble « Sécurité du serveur »

- Besoin : interdire la connexion SSH directe de root.
- Fait : mêmes gardes et mêmes exigences que `configure-ssh.sh` ; dépose
  `05-mgnetworking-root.conf` : `PermitRootLogin no` ; identique : rien réécrit ni
  rechargé ; sinon `sshd -t`, puis `sshd -T` doit annoncer `permitrootlogin no`, puis
  `systemctl reload ssh` ; l'un en échec : fichier précédent restauré (ou retiré). Ne
  fait pas : `restart`, modifier `sshd_config`.
- Options et défauts : `--utilisateur <nom>` (défaut `SRV_ADMIN_UTILISATEUR`) ;
  `--dry-run` ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 appliqué, conforme ou `--dry-run` ; 1 comme `configure-ssh.sh`, plus
  `sshd -T` en échec ou valeur effective autre que `no` ; 2 comme `configure-ssh.sh`.
- Modifie sur la machine : `<SSHD_CONFIG_D>/05-mgnetworking-root.conf`, rechargement de
  ssh.
- Lit : `SRV_ADMIN_UTILISATEUR`, `SSHD_CONFIG`, `SSHD_CONFIG_D` (mêmes défauts),
  `getent`, `authorized_keys` du compte, `sshd -T`.
- État : actif.

### configure-fail2ban.sh — ensemble « Sécurité du serveur »

- Besoin : fail2ban actif sur sshd, avec les valeurs de la distribution (décision 22).
- Fait : fail2ban installé par `apt-get update` et `apt-get install -y` s'il manque
  (`dpkg-query`) ; dépose `<jail.d>/mgnetworking-sshd.conf` : `[sshd]`, `enabled = true` ;
  `systemctl enable` s'il n'est pas activé ; `restart` seulement si installé, déposé,
  activé à l'instant ou arrêté ; rien à faire : vérification seule ; démon attendu par
  `fail2ban-client ping`, puis `fail2ban-client status sshd`. Ne fait pas : toucher
  `jail.conf` ou `jail.local`, fixer une valeur de prison.
- Options et défauts : `--dry-run` (sans root ni vérification) ; `-y`, `--yes` ; `-h`,
  `--help`.
- Codes de retour : 0 appliqué et vérifié, conforme et vérifié, ou `--dry-run` ; 1 root,
  distribution, `apt-get`, `dpkg-query`, `systemctl` ou `fail2ban-client` absent, hors
  terminal sans `--yes`, confirmation refusée, installation, `enable` ou `restart` en
  échec, démon muet après les essais, prison `sshd` non chargée ; 2 option inconnue.
- Modifie sur la machine : paquet fail2ban, `<jail.d>/mgnetworking-sshd.conf`, activation
  et redémarrage du service.
- Lit : `FAIL2BAN_JAIL_D` (défaut `/etc/fail2ban/jail.d`), `FAIL2BAN_ESSAIS` (défaut
  10), `FAIL2BAN_DELAI` (défaut 1 s entre essais), état du paquet et du service.
- État : actif.

### verify-k3s.sh — ensemble « Gestion de K3s »

- Besoin : dire si le K3s de la machine est installé et sain.
- Fait : service `k3s` (`systemctl is-active`), version, nœuds, pods de tous les
  namespaces, namespaces, événements Warning ; tout par `k3s kubectl`, chaque appel borné
  à 5 s ; nœud non `Ready`, pod ni `Running`, ni `Succeeded`, ni `Completed`, service non
  actif : anomalie nommée ; événements Warning affichés sans effet sur le code. Ne fait
  pas : corriger, appeler un `kubectl` du PATH.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 K3s installé, cluster sain ; 1 root, ni binaire `k3s` ni unité
  `k3s.service`, API muette, anomalie ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `systemctl is-active k3s`, `systemctl list-unit-files k3s.service`, `k3s
  --version`, nœuds, pods, namespaces, événements Warning.
- État : actif.

### install-k3s.sh — ensemble « Gestion de K3s »

- Besoin : installer K3s serveur mono-nœud.
- Fait : Debian 12/13 ou Ubuntu 22.04/24.04, amd64 ou arm64, sinon refus ; `k3s` présent :
  version, 0, rien réinstallé ; refus sous 5 120 Mo libres sur `/var/lib`, mémoire sous
  512 Mo : `[WARN]` ; refus si 6443, 80 ou 443 écoute (`ss -H -ltn` ; `ss` absent :
  `[WARN]`, `ss` en échec : refus) ; résumé ; `get.k3s.io` sondé en HTTPS (15 s), puis
  confirmation, téléchargement (120 s), installateur, `systemctl enable k3s`, service
  actif exigé, `verify-k3s.sh`. Ne fait pas : écrire `config.yaml`, ouvrir le pare-feu,
  réinstaller un K3s présent.
- Options et défauts : `--dry-run` (préflight local et commande, sans root ni réseau) ;
  `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 installé et sain, déjà présent, ou `--dry-run` ; 1 root, système ou
  architecture non supporté, `systemctl` ou `curl` absent, disque insuffisant, `ss` en
  échec, port occupé, `get.k3s.io` injoignable, hors terminal sans `--yes`, confirmation
  refusée, téléchargement, installateur ou activation en échec, service inactif,
  diagnostic en échec ; 2 option inconnue.
- Modifie sur la machine : par l'installateur, binaire `k3s`, unité `k3s.service`,
  `/etc/rancher/k3s`, `/var/lib/rancher/k3s` ; activation du service ; journal complet
  du script.
- Lit : `SRV_K3S_VERSION` (absente : canal `stable`), `/var/lib` (`df`),
  `/proc/meminfo`, `ss`.
- État : actif.

### configure-k3s.sh — ensemble « Gestion de K3s »

- Besoin : tenir `/etc/rancher/k3s/config.yaml` depuis le dépôt (décision 47).
- Fait : `SRV_K3S_TLS_SAN` validée avant root (entrées IPv4, IPv6 ou nom d'hôte, sans
  virgule finale) ; K3s absent : refus, `--dry-run` compris ; contenu : `write-kubeconfig-mode:
  "0600"` et, si la liste n'est pas vide, `tls-san` ; contenu et mode 600 identiques : 0 ;
  contenu identique, mode différent : `chmod` seul ; sinon différence, confirmation,
  original sauvegardé en `config.yaml.AAAAMMJJ-HHMMSS.bak`, écriture par temporaire puis
  `mv`, `systemctl restart k3s`, `verify-k3s.sh` ; l'un en échec : original restauré (ou
  fichier retiré), K3s relancé. Ne fait pas : fusionner une clé ajoutée à la main, purger
  les `.bak`.
- Options et défauts : `--dry-run` (différence seule, sans root) ; `-y`, `--yes` ; `-h`,
  `--help`.
- Codes de retour : 0 écrit, conforme, droits corrigés ou `--dry-run` ; 1 root,
  `systemctl`, `diff`, `install`, `mktemp` ou `stat` absent, K3s absent, `diff` en
  erreur, hors terminal sans `--yes`, confirmation refusée, redémarrage ou diagnostic en
  échec ; 2 option inconnue, `SRV_K3S_TLS_SAN` mal formée.
- Modifie sur la machine : `config.yaml` (0600), ses `.bak`, redémarrage de `k3s`.
- Lit : `SRV_K3S_TLS_SAN` (virgules), `K3S_CONFIG_DIR` (défaut `/etc/rancher/k3s`), le
  fichier en place.
- État : actif.

### upgrade-k3s.sh — ensemble « Gestion de K3s »

- Besoin : mettre K3s à niveau vers une version explicite.
- Fait : cible de forme `vX.Y.Z+k3sN` exigée ; version en place relue ; identique : 0
  sans téléchargement ; refus sans rien modifier : changement de majeure, recul, saut de
  plus d'une mineure, `verify-k3s.sh` en échec avant (`--dry-run` compris) ; résumé,
  confirmation, téléchargement (120 s), installateur avec `INSTALL_K3S_VERSION` seule ;
  version relue égale à la cible, puis `verify-k3s.sh`. Ne fait pas : viser la dernière
  stable, revenir en arrière.
- Options et défauts : `--version <vX.Y.Z+k3sN>` (défaut `SRV_K3S_VERSION`, aucune
  autre) ; `--dry-run` (versions, diagnostic et commande, root exigé) ; `-y`, `--yes` ;
  `-h`, `--help`.
- Codes de retour : 0 à niveau, déjà à la cible ou `--dry-run` ; 1 cible absente ou mal
  formée, root, `curl` absent, K3s absent, version en place illisible, majeure, recul,
  saut, cluster malsain, hors terminal sans `--yes`, confirmation refusée,
  téléchargement ou installateur en échec, version relue différente, diagnostic final en
  échec ; 2 option inconnue, `--version` sans valeur.
- Modifie sur la machine : binaire `k3s` et redémarrage du service, par l'installateur.
- Lit : `SRV_K3S_VERSION`, `k3s --version`.
- État : actif.

### uninstall-k3s.sh — ensemble « Gestion de K3s »

- Besoin : désinstaller K3s serveur.
- Fait : nœud agent (`k3s-agent-uninstall.sh` sans `k3s-uninstall.sh`) : refus ; ni
  binaire ni désinstallateur : 0 ; binaire sans désinstallateur : refus ; résumé :
  `/etc/rancher/k3s`, `/var/lib/rancher/k3s` dont `storage` (volumes local-path),
  `/var/lib/kubelet`, `/var/lib/cni`, `/run/k3s`, `/run/flannel`,
  `/usr/local/bin/k3s-killall.sh`, `k3s.service.env`, avec leur taille `du`, binaire,
  unité, état du service ; confirmation ; `/usr/local/bin/k3s-uninstall.sh` ; état relu :
  binaire, unité (fichier ou connue de systemd), chemins listés, service actif. Ne fait
  pas : supprimer quoi que ce soit lui-même, sauvegarder, toucher Docker, ufw ou
  `config/`.
- Options et défauts : `--dry-run` (résumé seul, root exigé) ; `-y`, `--yes` ; `-h`,
  `--help`.
- Codes de retour : 0 désinstallé, absent ou `--dry-run` ; 1 root, `du`, `cut` ou
  `systemctl` absent, nœud agent, désinstallateur absent, hors terminal sans `--yes`,
  confirmation refusée, désinstallateur en échec ou état final incomplet ; 2 option
  inconnue.
- Modifie sur la machine : **détruit** K3s, sa configuration et les données des pods.
- Lit : chemins listés, `systemctl is-active k3s`, `systemctl is-enabled k3s`.
- État : actif.

## Historique du cadrage

| Date | Changement | Nature (correction, ajout compatible, nouveau script, dépréciation) | Validé par user |
|---|---|---|---|
| 2026-09-17 | État initial : besoin, ensembles « Socle du serveur », « Sécurité du serveur » et « Gestion de K3s », contrats des 25 scripts tels qu'écrits (TASK-075) | état initial | |
