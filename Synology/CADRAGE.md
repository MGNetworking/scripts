# Cadrage — Synology/

Ce document **engage** : besoin du dossier et contrat de chacun de ses scripts
([décision 49](../orchestration/decisions.md)). Le [README](README.md) et ceux des
sous-dossiers **expliquent** (usage, exemples, risques). Tout ce qui figure au contrat
est réputé utilisé : le modifier est une rupture. Un changement incompatible ne touche
jamais le script existant : nouveau script, l'ancien déprécié avec une date.

État initial : chaque contrat décrit le comportement **actuel** du script, lu dans son
code le 2026-09-17, et non un comportement souhaité. Un écart entre le code et son aide
ou son README est consigné au registre, pas corrigé ici. Aucun de ces scripts ne peut
s'exécuter en conteneur : ces contrats sont lus dans le code, non observés.

## Besoin

Automatiser, sur un NAS Synology sous DSM qui porte Plex (décision 17), les gestes
répétés autour de la médiathèque : nommer les épisodes d'une saison comme Plex les
attend, et mettre à jour le conteneur Plex. Les scripts se lancent depuis une session
SSH sur le NAS ou depuis le planificateur de tâches de DSM, et restent indépendants de
l'infrastructure du VPS.

`Plex/` porte ces deux scripts. `Administration/`, **sans script**, répond au besoin
d'administrer le NAS lui-même : sauvegardes, stockage, réseau, services, utilisateurs,
maintenance ; aucun contrat tant qu'aucun script n'y est écrit.

**Hors besoin** : le système, le moteur Docker et le cluster d'un serveur Linux
(`Linux/`, `Docker/`, `Kubernetes/`) ; installer ou régler Container Manager ou DSM ;
écrire ou modifier le fichier Compose de Plex ; installer, sauvegarder ou restaurer
Plex ; organiser des films, ou des épisodes répartis sur plusieurs dossiers.

**Conventions de tout le dossier** :

- ni l'un ni l'autre ne charge `lib/common.sh` : ni `config/server.env`, ni option
  de configuration, ni journal sous le répertoire du socle, ni préfixes `[INFO]`… ;
  chaque contrat dit son propre journal, écrit en ajout et jamais tourné ;
- aucun privilège exigé ni contrôlé, aucune confirmation, aucune simulation ; codes
  de retour : `0` et `1` seulement, `2` jamais rendu ;
- les commandes externes honorent l'environnement hérité (locale de `sort`, variables
  du client `docker`) : aucun script ne le neutralise ;
- **hors contrat** : le libellé exact des messages et des lignes de journal, horodatage
  compris ; la mise en page des bannières, de l'aide et du récapitulatif.

## Ensembles

Aucun dans `Synology/`.

## Scripts individuels

### organize-series.sh

- Dossier : `Plex/`. Autonome : n'attend ni ne prépare aucun autre script.
- Lancement : à la main, ou tâche DSM lancée à la demande, une saison à la fois.

### update-plex.sh

- Dossier : `Plex/`. Autonome ; suppose Container Manager (client `docker` et
  `docker compose`) et la pile Plex déjà en place sur le NAS.
- Lancement : à la main, ou tâche DSM planifiée ; rien n'est affiché, tout va au journal.

## Contrats

### organize-series.sh — script individuel

- Besoin : renommer d'un coup les épisodes d'une saison au format que Plex reconnaît.
- Fait : sauf aide, crée `/volume1/development/scripts/logs` s'il manque, **avant** de
  valider les arguments ; contrôle d'abord le nombre d'arguments (autre que 3 : message
  et aide, arrêt), puis nom, saison et dossier, toutes leurs erreurs à la fois, puis
  l'aide ; crée le répertoire de `LOG_FILE` ; affiche les paramètres et le nombre de
  fichiers ordinaires du dossier ; liste ces fichiers (`find -maxdepth 1 -type f`,
  sous-dossiers exclus, fichiers cachés compris) dans un temporaire
  `/tmp/files_to_process_<pid>.txt`, triés par `sort` sur le chemin ; dans cet ordre,
  chaque fichier devient `<nom> <saison>E<numéro>.<extension>`, numéro sur deux
  chiffres au moins depuis 01, extension = texte après le dernier point du **chemin** ;
  nom visé existant (`-e`) et chemin visé différent, **comparé comme texte**, du chemin
  listé : fichier ignoré (`ATTENTION`), numéro non avancé ; sinon `mv`, en échec :
  fichier laissé (`ERREUR`), numéro non avancé ; un fichier déjà bien nommé est donc
  ignoré si le dossier est donné avec un `/` final, et passé à `mv` sur lui-même sinon
  (échec avec le `mv` de GNU, non vérifié sur DSM) ; numéro avancé à chaque renommage
  réussi ; temporaire supprimé ; chaque renommage journalisé (ancien et nouveau nom) ;
  récapitulatif : renommés (compte rendu modulo 256, code de retour de la fonction),
  erreurs = lignes du journal contenant `ERREUR` ou `ATTENTION` et la date du jour, où
  que ce soit dans la ligne (noms de fichiers compris), toutes exécutions confondues ;
  statut « succès complet » si ce nombre est nul. Ne fait pas : descendre dans les
  sous-dossiers, filtrer les fichiers par type, simuler, demander confirmation.
- Options et défauts : trois arguments positionnels, tous requis — `nom` (non vide),
  `saison` (`^S[0-9]{2}$`), `dossier` (répertoire existant) ; `-h`, `--help` en premier
  argument, ou aucun argument : aide.
- Codes de retour : 0 aide, ou traitement mené à son terme, fichiers ignorés et
  renommages en échec compris ; 1 un, deux, ou quatre arguments et plus (hors aide), nom
  vide, saison vide ou mal formée, dossier vide ou qui n'est pas un répertoire.
- Modifie sur la machine : renomme les fichiers du dossier désigné ; crée
  `/volume1/development/scripts/logs` ; ajoute au journal `LOG_FILE`
  (`/volume1/development/scripts/logs/plex_series_organizer.log`) ; temporaire dans
  `/tmp`, supprimé en fin de traitement.
- Lit : les arguments, la liste des fichiers du dossier, `LOG_FILE` (décompte des
  erreurs du jour) ; aucune variable d'environnement propre, `LOG_FILE` étant fixé dans
  le code.
- État : actif.

### update-plex.sh — script individuel

- Besoin : mettre Plex à jour sans intervenir, depuis une tâche planifiée du NAS.
- Fait : `SCRIPT_DIR` = répertoire du script (`$0`) ; crée `SCRIPT_DIR/logs` ; ajoute
  au journal un en-tête (`SCRIPT_DIR`, `STACK_DIR`, `COMPOSE_FILE`, service, `IMAGE`) ;
  refus si `docker` est introuvable (le greffon `compose` n'est pas contrôlé), si
  `STACK_DIR` n'est pas un répertoire ou si `STACK_DIR/COMPOSE_FILE` n'est pas un
  fichier ; `docker pull` de `IMAGE`, en échec : arrêt avant tout redéploiement ; dans
  `STACK_DIR`, `docker compose -f <COMPOSE_FILE> up -d --pull always --no-deps
  <SERVICE_NAME>` : crée le conteneur du service s'il manque, le recrée si son image ou
  sa définition a changé, le démarre s'il est arrêté (même arrêté volontairement), et
  crée les réseaux et volumes nommés qu'il déclare ; puis `docker image prune -f`
  (images sans étiquette de tout le démon, échec ignoré). Sorties de `docker` et
  messages envoyés au seul journal : rien sur le terminal, sauf l'erreur d'une commande
  non interceptée. Aucun appel borné dans le temps. Ne fait pas : lire un argument (tout
  argument, demande d'aide comprise, est ignoré et la mise à jour a lieu), redémarrer
  les autres services de la pile, supprimer une image étiquetée, un volume, ou un
  conteneur autre que celui du service qu'il recrée.
- Options et défauts : aucune. Constantes du code, non réglables : `STACK_DIR`
  `/volume1/docker/docker-plex`, `COMPOSE_FILE` `docker-compose-nas.yml`,
  `SERVICE_NAME` `plex`, `IMAGE` `lscr.io/linuxserver/plex:latest`.
- Codes de retour : 0 dès que `docker compose up` réussit, qu'il ait changé quelque chose
  ou non (nettoyage en échec compris) ; 1 `docker` absent, `STACK_DIR` ou fichier
  Compose introuvable, `docker pull` ou `docker compose up` en échec (greffon absent
  compris) ; création de `SCRIPT_DIR/logs`, écriture du journal ou `cd` en échec :
  sortie par `set -e` avec le code de la commande.
- Modifie sur la machine : `SCRIPT_DIR/logs` et `LOG_FILE` (`update-plex.log`) ; image
  `IMAGE` ; conteneur du service `SERVICE_NAME`, créé, recréé (coupure de Plex) ou
  démarré, et ses réseaux et volumes nommés s'ils manquent ; images sans étiquette du
  démon, supprimées.
- Lit : `$0`, `STACK_DIR/COMPOSE_FILE` et ce que `docker compose` lit depuis
  `STACK_DIR` (fichier `.env` du dossier, fichiers `env_file` déclarés) ; aucune
  variable d'environnement propre, toutes les variables étant fixées dans le code.
- État : actif.

## Historique du cadrage

| Date | Changement | Nature (correction, ajout compatible, nouveau script, dépréciation) | Validé par user |
|---|---|---|---|
| 2026-09-17 | État initial : besoin, `Administration/` décrit par son seul besoin, contrats des 2 scripts individuels tels qu'écrits (TASK-077) | état initial | |
