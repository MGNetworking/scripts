# Cadrage — Docker/

Ce document **engage** : besoin du dossier et contrat de chacun de ses scripts
([décision 49](../orchestration/decisions.md)). Le [README](README.md) **explique**
(usage, exemples, risques). Tout ce qui figure au contrat est réputé utilisé : le
modifier est une rupture. Un changement incompatible ne touche jamais le script
existant : nouveau script, l'ancien déprécié avec une date.

État initial : chaque contrat décrit le comportement **actuel** du script, lu dans son
code le 2026-09-17, et non un comportement souhaité. Un écart entre le code et son aide
ou son README est consigné au registre, pas corrigé ici.

## Besoin

Poser, régler, tenir à jour, nettoyer et diagnostiquer le **moteur** Docker d'un serveur
Linux (Engine, client, `containerd`, Buildx, Compose) par des commandes rejouables, et
dire à tout moment ce que ce moteur porte et consomme.

Contexte visé : un VPS Debian 12 ou 13, ou Ubuntu 22.04 ou 24.04 (décision 14), préparé
par `Linux/`, où le moteur est administré en root et consulté par root ou un compte du
groupe `docker`.

**Hors besoin** : préparer le système (`Linux/`) ; K3s et les workloads gérés par
Kubernetes (`Linux/K3s/`, `Kubernetes/`) ; connaître, déployer ou redéployer une
application ; ajouter un compte au groupe `docker` ; Swarm et les réseaux `overlay` ;
modifier ou supprimer un réseau existant hors nettoyage ; lancer un conteneur de test.

**Conventions de tout le dossier** :

- codes de retour : `0` succès ou état déjà voulu, `1` échec nommé, `2` usage refusé ; les
  écarts de chaque script sont dans son contrat ; une commande externe en échec non
  interceptée sort par `set -e` avec son propre code, et non 1 (A138) ;
- chaque script écrit son journal sous `LOG_DIR` par le socle (`lib/common.sh`) : ce
  n'est pas répété dans les contrats ;
- le client `docker` honore l'environnement hérité, `DOCKER_HOST` compris : aucun script
  ne le neutralise ;
- **hors contrat** : le libellé exact des messages ; la mise en page des rubriques et
  tableaux, largeurs de colonnes comprises ; l'indentation de `daemon.json`, sauf sans
  `jq` (voir `configure-docker.sh`).

## Ensembles

### Moteur Docker

- **Fonction globale** : une fois ses scripts appliqués, la machine porte Docker Engine
  installé depuis `download.docker.com` (cinq paquets), son service activé et démarré,
  un `/etc/docker/daemon.json` qui borne les journaux des conteneurs créés ensuite
  (`json-file`, 10m, 3 fichiers par défaut), et le réseau partagé déclaré. À la demande,
  les composants installés sont mis à jour, les images d'un projet Compose nommé
  récupérées sans redéploiement, et les ressources inutilisées supprimées, volumes
  exclus par défaut. Les diagnostics relèvent l'état sans rien modifier.
- **Scripts membres et ordre** :
  1. à tout moment : `Diagnostics/check-docker.sh`, `Diagnostics/list-containers.sh`,
     `Diagnostics/docker-disk-usage.sh` ;
  2. `Installation/install-docker.sh`, puis `Configuration/configure-docker.sh`, puis
     `Configuration/create-network.sh` ;
  3. à la demande : `Maintenance/update-docker.sh`, `Maintenance/update-images.sh`,
     `Cleanup/docker-cleanup.sh`.
- **Conventions communes** :
  - `Diagnostics/` est en **lecture seule**, sans exception (`CLAUDE.md`) : aucun
    privilège exigé, aucune écriture, aucun conteneur lancé, aucune image tirée, pas de
    `--dry-run` ; 1 si `docker` manque ou si le démon ne répond pas, 2 pour une option
    inconnue seulement ;
  - scripts qui modifient : tous ont `--dry-run`, qui n'exige pas root ; root exigé hors
    `--dry-run` par `install-docker.sh`, `configure-docker.sh` et `update-docker.sh` ;
    `create-network.sh`, `update-images.sh` et `docker-cleanup.sh` n'exigent aucun
    privilège, l'accès au démon suffit ;
  - les diagnostics, `update-images.sh` et la sonde de `docker-cleanup.sh` bornent leurs
    interrogations du démon par `timeout` (délais au contrat) ; les autres
    interrogations ne sont pas bornées (A141) ;
  - confirmation, réponse `o`, `oui`, `y` ou `yes` : trois régimes (A139) :
    - `install-docker.sh`, `configure-docker.sh`, `update-docker.sh` : hors terminal,
      `-y`/`--yes` obligatoire (sinon 1) ; en terminal, `--yes` ou un `ASSUME_YES` hérité
      confirme ; refus : 1, sauf `update-docker.sh` (0) ;
    - `update-images.sh` : `--yes` ou un `ASSUME_YES` hérité confirme ; sinon la réponse
      est lue sur l'entrée standard, terminal ou non ; refus ou entrée vide : 0 sans rien
      faire ;
    - `docker-cleanup.sh` : `--yes` seul confirme, `ASSUME_YES` hérité neutralisé
      (décision 45) ; réponse lue sur l'entrée standard, terminal ou non ; refus ou
      entrée vide : 0 sans rien supprimer ;
    - `create-network.sh` ne demande aucune confirmation ;
  - une valeur fautive rend 2, qu'elle vienne de la ligne de commande ou de
    `config/server.env` ;
  - `install-docker.sh` et `update-docker.sh` portent la même liste de paquets :
    `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
    `docker-compose-plugin` ;
  - aucun script n'ajoute un compte au groupe `docker`, n'emploie `docker network prune`
    ni `docker system prune` ; seul `configure-docker.sh` écrit `daemon.json` ;
  - réglages dans `config/server.env` : `SRV_DOCKER_LOG_DRIVER`,
    `SRV_DOCKER_LOG_MAX_SIZE`, `SRV_DOCKER_LOG_MAX_FILE`, `SRV_DOCKER_NETWORK`,
    `SRV_DOCKER_RESEAUX_PROTEGES`.

## Scripts individuels

Aucun dans `Docker/`.

## Contrats

### check-docker.sh — ensemble « Moteur Docker »

- Besoin : savoir ce que porte une machine qu'on découvre, et si Docker y est exploitable.
- Fait : client (`docker --version`), plugin Compose (`docker compose version --short`),
  Buildx (second champ de `docker buildx version`) ; socket : présent et accessible en
  écriture, présent mais interdit, autre chose qu'un socket, ou absent ; `DOCKER_HOST`
  affiché s'il est défini ; service (`systemctl is-active docker`, `is-enabled`) ; démon
  (`docker info` : version, pilote de stockage, répertoire de données). Chaque appel sauf
  `systemctl` en `LC_ALL=C`, borné à 5 s par `timeout`, appelé sans contrôle de présence
  (A141) ;
  information absente : « non disponible ». Démon qui répond, service non actif :
  `[WARN]` et 0. Ne fait pas : lancer un conteneur, tirer une image, installer.
- Options et défauts : `-h`, `--help`.
- Codes de retour : 0 client présent et démon qui répond ; 1 client absent, démon sans
  réponse (arrêté, socket interdit, délai dépassé, `timeout` absent) ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `DOCKER_SOCKET` (défaut `/var/run/docker.sock`), `DOCKER_HOST`, `docker
  --version`, `docker compose version`, `docker buildx version`, `systemctl is-active
  docker`, `systemctl is-enabled docker`, `docker info`.
- État : actif.

### list-containers.sh — ensemble « Moteur Docker »

- Besoin : l'inventaire des conteneurs.
- Fait : un seul `docker ps` (avec `--all` si l'option est donnée), en `LC_ALL=C`, borné à
  5 s si `timeout` existe ; section « en cours d'exécution » (état commençant par `Up`
  ou `Restarting`) et,
  avec `--all`, section « arrêtés » (tous les autres) ; colonnes nom, image, état,
  identifiant sur 12 caractères, ports, réseaux, sans troncature ; aucun conteneur : une
  phrase et 0. Échec : délai dépassé, accès refusé à la socket et démon injoignable
  nommés, autre cause en message générique. Ne fait pas : `start`, `stop`, `restart`,
  `rm`, `prune`.
- Options et défauts : `--all` ; `-h`, `--help`.
- Codes de retour : 0 inventaire produit, vide compris ; 1 `docker` absent, `docker ps` en
  échec ou au-delà de 5 s ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `docker ps`.
- État : actif.

### docker-disk-usage.sh — ensemble « Moteur Docker »

- Besoin : le stockage consommé par Docker.
- Fait : sonde `docker version` bornée à 5 s et `docker system df` à 120 s si `timeout`
  existe : pour
  images, conteneurs, volumes locaux et cache de build, objets, actifs, taille et
  récupérable (« non fourni » quand le démon ne le donne pas, jamais 0) ; répertoire de
  données (`docker info`) et occupation de son système de fichiers (`df -P -h`), « non
  disponible » s'il n'est pas visible ; rappel que journaux et résidus de couches ne sont
  pas comptés ; avec `--detail`, sortie de `docker system df -v` en plus. Commandes en
  `LC_ALL=C`. Ne fait pas : `prune`, supprimer, simuler une suppression.
- Options et défauts : `--detail` ; `-h`, `--help`.
- Codes de retour : 0 relevé produit, vide compris ; 1 `docker` absent, sonde en échec ou
  au-delà de 5 s (accès refusé et démon injoignable nommés), mesure en échec ou au-delà
  de 120 s ; 2 option inconnue.
- Modifie sur la machine : rien.
- Lit : `docker version`, `docker system df`, `docker info`, `df`, `docker system df -v`.
- État : actif.

### install-docker.sh — ensemble « Moteur Docker »

- Besoin : installer Docker Engine depuis le dépôt officiel.
- Fait : refus hors Debian 12/13 et Ubuntu 22.04/24.04, hors `x86_64` (amd64) et
  `aarch64` (arm64), sous un noyau 3.10, sans `VERSION_CODENAME` ; `docker` présent et
  paquet `docker-ce` installé (`dpkg-query`) : version, 0, rien réinstallé (`--dry-run`
  compris) ; refus sous 2 048 Mo libres sur `/var` (sortie de `df` vide : `[WARN]` ; `df`
  en échec : sortie par `set -e`, A138), mémoire sous
  512 Mo : `[WARN]` ; paquets en conflit relevés : `docker.io`, `docker-doc`,
  `docker-compose`, `docker-compose-v2`, `podman-docker`, `containerd`, `runc` ; résumé ;
  `--dry-run` s'arrête là. Sinon : conflits présents, confirmation propre puis `apt-get
  remove -y` ; confirmation de l'installation ; `apt-get update`, `apt-get install -y
  ca-certificates curl` ; `/etc/apt/keyrings` (0755) ; clé
  `https://download.docker.com/linux/<distribution>/gpg` téléchargée dans un temporaire,
  vide ou en échec : refus, sinon lisible par tous et mise en place ; `docker.list` :
  `deb [arch=<arch> signed-by=/etc/apt/keyrings/docker.asc] <dépôt> <nom de code>
  stable` ; `apt-get update` en échec : liste retirée, clé retirée si elle était
  nouvelle, refus ; `apt-get install -y` des cinq paquets ; `systemctl enable docker`,
  `systemctl start docker` ; versions affichées, `docker version` doit répondre. Journal
  complet du script hors `--dry-run`. Ne fait pas : configurer le démon, créer un réseau,
  ajouter un compte au groupe `docker`, réinstaller une installation présente.
- Options et défauts : `--dry-run` (contrôles et résumé, sans root, sans écriture ni
  `apt-get`) ; `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 installé et démon qui répond, déjà installé, ou `--dry-run` ; 1
  root, distribution, version ou architecture non supportée, noyau trop ancien,
  `VERSION_CODENAME` absent, espace insuffisant, hors terminal sans `--yes`, retrait des
  conflits ou installation refusé, clé irrécupérable, `apt-get update` en échec avec le
  dépôt, démon muet après installation ; échec du premier `apt-get update`, d'`apt-get
  remove`, d'`apt-get install` ou de `systemctl` : code de la commande (A138) ; 2 option
  inconnue.
- Modifie sur la machine : paquets en conflit retirés, `ca-certificates` et `curl`,
  `/etc/apt/keyrings/docker.asc`, `/etc/apt/sources.list.d/docker.list`, index apt, les
  cinq paquets Docker, service `docker` activé et démarré.
- Lit : `/etc/os-release`, `uname`, `df -Pm /var`, `/proc/meminfo`, état des paquets
  (`dpkg-query`).
- État : actif.

### configure-docker.sh — ensemble « Moteur Docker »

- Besoin : borner les journaux des conteneurs par `/etc/docker/daemon.json`.
- Fait : valeurs validées avant root et avant `--dry-run` ; fichier absent, conforme ou
  divergent ; conforme : avec `jq`, `log-driver`, `log-opts.max-size` et
  `log-opts.max-file` égaux aux valeurs, en chaînes, autres clés ignorées ; sans `jq`,
  texte identique au contenu que le script construit ; `--dry-run` : état et contenu visé,
  0, sans root ni `docker` ; conforme : 0 sans écriture ni redémarrage ; divergent sans
  `jq` : refus, rien écrit ; divergent avec `jq` : fusion (ces trois clés posées, toutes
  les autres conservées), fichier en place invalide : refus ; résumé et nombre de
  conteneurs en cours (`docker ps -q`) ; confirmation ; `/etc/docker` créé s'il manque ;
  écriture par temporaire, validé par `jq` s'il est là, puis `mv`, mode 0644 ; original
  divergent sauvegardé en `daemon.json.AAAAMMJJ-HHMMSS.bak` ; `systemctl restart docker`,
  puis `docker version` en 3 essais à 1 s d'écart ; redémarrage en échec ou démon muet :
  original restauré (ou fichier retiré), démon relancé, refus. Ne fait pas : tronquer ou
  purger les journaux existants, appliquer la rotation aux conteneurs déjà créés, poser
  une autre clé, activer `live-restore`.
- Options et défauts : `--log-driver <json-file|local>` (défaut `SRV_DOCKER_LOG_DRIVER`,
  sinon `json-file`) ; `--log-max-size <entier suivi de k, m ou g, sans casse>` (défaut
  `SRV_DOCKER_LOG_MAX_SIZE`, sinon `10m`) ; `--log-max-file <entier ≥ 1>` (défaut
  `SRV_DOCKER_LOG_MAX_FILE`, sinon `3`) ; la ligne de commande prime ; `--dry-run` ; `-y`,
  `--yes` ; `-h`, `--help`.
- Codes de retour : 0 écrit et démon revenu, déjà conforme, ou `--dry-run` ; 1 root,
  `docker` absent, divergent sans `jq`, fichier en place ou produit invalide, hors
  terminal sans `--yes`, confirmation refusée, redémarrage en échec, démon muet après
  3 essais ; 2 option inconnue, valeur manquante, pilote, taille ou nombre mal formé.
- Modifie sur la machine : `/etc/docker`, `/etc/docker/daemon.json`, ses `.bak`,
  redémarrage du démon, qui interrompt les conteneurs en cours.
- Lit : `SRV_DOCKER_LOG_DRIVER`, `SRV_DOCKER_LOG_MAX_SIZE`, `SRV_DOCKER_LOG_MAX_FILE`,
  `daemon.json` en place, `jq` s'il est présent, `docker ps -q` (non borné, A141).
- État : actif.

### create-network.sh — ensemble « Moteur Docker »

- Besoin : un réseau Docker externe, partagé par plusieurs projets Compose.
- Fait : nom validé (`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`), pilote `overlay` refusé,
  sous-réseau CIDR IPv4 (préfixe jusqu'à 32) ou IPv6 (jusqu'à 128) validé ; état lu par
  `docker network inspect` ; absent (ou nom qui ne résout qu'un préfixe d'identifiant
  d'un autre réseau) : `docker network create --driver <pilote> [--subnet <cidr>] <nom>` ;
  présent : pilote comparé, et sous-réseau s'il est demandé (parmi ceux du réseau) ;
  conforme : 0 ; divergent : refus sans rien modifier, `--dry-run` compris ; lecture en
  échec pour une autre raison : démon injoignable. Aucune confirmation, aucun privilège
  exigé. Ne fait pas : supprimer, recréer ou modifier un réseau, comparer un autre
  attribut que le pilote et le sous-réseau, créer un réseau Swarm.
- Options et défauts : `[nom]` positionnel (défaut `SRV_DOCKER_NETWORK`) ; `--driver
  <pilote>` (défaut `bridge`, tout autre que `overlay` transmis à Docker) ; `--subnet
  <cidr>` (défaut : choisi par Docker) ; `--dry-run` (commande affichée ; démon
  injoignable : `[WARN]` et 0) ; `-h`, `--help`.
- Codes de retour : 0 créé, déjà conforme, ou `--dry-run` sur un réseau absent ou un
  démon injoignable ; 1 démon injoignable ou `docker` absent hors `--dry-run`, réseau
  divergent, création refusée par Docker ; 2 option inconnue, deux noms, nom absent ou
  invalide, `--driver` ou `--subnet` sans valeur ou commençant par un tiret, `overlay`,
  sous-réseau invalide.
- Modifie sur la machine : crée un réseau Docker.
- Lit : `SRV_DOCKER_NETWORK`, `docker network inspect`.
- État : actif.

### update-docker.sh — ensemble « Moteur Docker »

- Besoin : mettre à jour les composants Docker installés, et eux seuls.
- Fait : refus hors Debian 12/13 et Ubuntu 22.04/24.04 (`--dry-run` compris) ;
  `DEBIAN_FRONTEND=noninteractive` ; version de chacun des cinq paquets (`dpkg-query`)
  et état du service ; aucun installé : 0 sous `--dry-run`, refus sinon ; conteneurs en
  cours (`docker ps -q`) et `live-restore` (`docker info`) lus sans borne (A141), coupure
  annoncée avant toute question (`[WARN]` si des conteneurs tournent sans `live-restore`
  ou si le démon est muet) ; `--dry-run` : `apt-get update` (échec : `[WARN]`), paquets à
  mettre à niveau par `apt-get -s install --only-upgrade`, commandes affichées, 0 ; sinon
  tous les composants installés annoncés, confirmation, `apt-get update`, `apt-get
  install --only-upgrade -y` des composants installés ; versions avant et après ;
  service relu : actif, 0 ; illisible, `[WARN]` et 0 ; autre état, 1. Ne fait pas :
  installer un composant absent, `apt-get upgrade`, écrire `daemon.json`, activer
  `live-restore`, toucher une image, un conteneur ou un volume.
- Options et défauts : `--dry-run` (relevé, simulation et commandes, sans root) ; `-y`,
  `--yes` ; `-h`, `--help`.
- Codes de retour : 0 mis à jour avec service actif ou illisible, `--dry-run`, ou
  confirmation refusée ; 1 root, distribution ou version, `apt-get` ou `dpkg-query`
  absent, aucun composant installé, hors terminal sans `--yes`, service non actif après
  la mise à jour ; échec d'`apt-get update` ou d'`apt-get install` : code d'`apt-get`
  (A138) ; 2 option inconnue.
- Modifie sur la machine : index apt (`--dry-run` compris), composants Docker installés,
  et par leurs paquets le redémarrage du démon.
- Lit : état des paquets (`dpkg-query`), `systemctl is-active docker`, `docker ps -q`,
  `docker info`, `apt-get -s`.
- État : actif.

### update-images.sh — ensemble « Moteur Docker »

- Besoin : récupérer les images d'un projet Compose désigné, sans redéployer.
- Fait : `--project` : un fichier est pris tel quel ; dans un répertoire,
  `compose.yaml`, `compose.yml`, `docker-compose.yaml` puis `docker-compose.yml` ; chemin
  rendu absolu ; sondes, lecture des images et identifiants bornés à 5 s si `timeout`
  existe ; sondes : `docker`, greffon Compose v2 (`docker compose
  version`), démon (`docker version`) ; images par `docker compose -f <fichier> config
  --images`, sans doublon ; blocage (sonde, `config` en échec, aucune image) : `[WARN]`,
  puis 0 sous `--dry-run`, 1 sinon ; `--dry-run` : projet, fichier, images et commande,
  0 ; identifiant de chaque image relevé ; confirmation ; `docker compose -f <fichier>
  pull`, non borné ; état de chaque image avant et après ; commande `docker compose -f
  <fichier> up -d` affichée, jamais lancée. Ne fait pas : `up`, `down`, `stop`, `rm`,
  supprimer une image, toucher un volume, chercher un projet.
- Options et défauts : `--project <chemin>` (requis) ; `--dry-run` (lisible sans démon) ;
  `-y`, `--yes` ; `-h`, `--help`.
- Codes de retour : 0 récupération faite, `--dry-run` (blocage compris), ou confirmation
  refusée ; 1 hors `--dry-run` : `docker` ou greffon Compose v2 absent, démon muet,
  `config --images` en échec, aucune image, `pull` en échec ; 2 option inconnue,
  `--project` absent ou sans valeur, chemin introuvable, répertoire sans fichier Compose.
- Modifie sur la machine : images locales du démon.
- Lit : le fichier Compose désigné, `docker compose version`, `docker version`, `docker
  compose config --images`, `docker image inspect`.
- État : actif.

### docker-cleanup.sh — ensemble « Moteur Docker »

- Besoin : récupérer l'espace des ressources Docker inutilisées sans toucher ce qui sert.
- Fait : sonde `docker version` bornée à 5 s si `timeout` existe ; démon injoignable :
  sous `--dry-run`,
  opérations annoncées et 0, sinon 1 ; relevé, non borné (A141) : `docker system df`,
  conteneurs à l'état `exited` ou `created`, images sans étiquette qu'aucun conteneur ne
  référence, volumes `dangling`, réseaux sans conteneur attaché hors `bridge`, `host`,
  `none`, `SRV_DOCKER_RESEAUX_PROTEGES` et `SRV_DOCKER_NETWORK` ; une commande de relevé
  en échec arrête tout ; relevé par catégorie avec l'espace récupérable annoncé par le
  démon ; `--dry-run` s'arrête là ; rien à supprimer dans les catégories retenues : 0
  sans question ; confirmation des totaux ; avec `--supprimer-volumes` et des volumes
  relevés, seconde confirmation qui les nomme (refus : volumes conservés, le reste
  poursuivi) ; dans l'ordre, `docker container prune -f`, `docker network rm <nom>` un
  par un, `docker image prune -f`, `docker volume rm <nom>` un par un ; les deux `prune`
  suppriment ce que Docker juge inutilisé au moment de l'appel, qui peut dépasser le
  relevé (conteneurs dans un autre état arrêté, images libérées par la purge des
  conteneurs, A142) ; une suppression en échec arrête la suite ; relevé refait (en échec :
  1, suppressions faites), récapitulatif par catégorie. Ne fait pas :
  `docker network prune`, `docker system prune`, supprimer un volume sans
  `--supprimer-volumes`, une image étiquetée ou un conteneur en cours.
- Options et défauts : `--dry-run` ; `--supprimer-volumes` ; `-y`, `--yes` ; `-h`,
  `--help`.
- Codes de retour : 0 nettoyage fait, rien à nettoyer, `--dry-run` (démon injoignable
  compris), ou confirmation refusée ; 1 `docker` absent ou démon muet hors `--dry-run`,
  relevé en échec (`--dry-run` compris, et après les suppressions), suppression en
  échec ; 2 option inconnue.
- Modifie sur la machine : **supprime** conteneurs arrêtés, réseaux inutilisés, images
  sans étiquette et, avec `--supprimer-volumes`, les volumes inutilisés et leurs données.
- Lit : `SRV_DOCKER_RESEAUX_PROTEGES` (noms séparés par des espaces),
  `SRV_DOCKER_NETWORK`, `docker version`, `docker system df`, `docker ps -a`, `docker
  images`, `docker volume ls`, `docker network ls`.
- État : actif.

## Historique du cadrage

| Date | Changement | Nature (correction, ajout compatible, nouveau script, dépréciation) | Validé par user |
|---|---|---|---|
| 2026-09-17 | État initial : besoin, ensemble « Moteur Docker », contrats des 9 scripts tels qu'écrits (TASK-076) | état initial | |
