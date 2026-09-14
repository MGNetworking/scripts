# MGNetworking/script — Refactorisation complète

> **Ce document reste la référence de conception du chantier** : il décrit ce que
> doit faire chaque script et pourquoi. Ce qui est *à faire maintenant*, avec ses
> critères et ses preuves, vit désormais dans [tasks/backlog.md](../tasks/backlog.md).
>
> Les deux se complètent : le plan explique, le backlog engage.

## Objectif

Transformer le dépôt `MGNetworking/script` en bibliothèque personnelle de scripts d'administration, d'installation, de configuration et de maintenance d'infrastructure.

La refactorisation est complète : les anciens scripts peuvent être supprimés. La nouvelle organisation est la référence.

## Architecture cible

```text
MGNetworking/script
│
├── Linux
│   ├── System
│   ├── Security
│   ├── Docker
│   └── K3s
│
├── Kubernetes
│   ├── Installation
│   ├── Configuration
│   └── Maintenance
│
├── Docker
│   ├── Installation
│   ├── Maintenance
│   └── Cleanup
│
├── Synology
│   ├── Plex
│   └── Administration
│
├── lib          # fonctions communes (common.sh)
├── config       # un <contexte>.env par domaine ; seuls les .example sont versionnés
└── docs         # socle technique, ce plan, guides
```

## Conventions

Les conventions d'écriture — en-tête obligatoire, chargement de `lib/common.sh`,
nommage `verb-noun.sh`, idempotence, `--dry-run`, ordre préflight, interdiction
des secrets — sont définies une seule fois dans [CLAUDE.md](../CLAUDE.md), à la
racine du dépôt.

Elles n'y sont pas répétées ici : ce plan décrit un chantier et sera archivé une
fois celui-ci terminé, tandis que les conventions restent en vigueur ensuite.

Le fonctionnement du socle commun (résolution de la racine, configurations de
contexte, journalisation, rotation des logs) est décrit dans
[architecture-technique.md](architecture-technique.md).

---

# 0. Socle commun

Base partagée par tous les scripts, mise en place avant la phase 1.

## `lib/common.sh` — fait

Chargé au début de chaque script par trois lignes qui résolvent la racine du
dépôt, quelle que soit la profondeur du script et son emplacement de
déploiement :

```bash
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
```

Fournit :

| Fonctions | Rôle |
|---|---|
| `info` `warn` `error` `success` `die` | messages à l'écran et dans le fichier de log |
| `run_logged` | exécute une commande externe en capturant sa sortie |
| `enable_full_logging` | capture toute la sortie du script |
| `require_root` `require_cmd` `require_os` `detect_os` | vérifications de préflight |
| `confirm` | confirmation interactive, contournable par `ASSUME_YES` |
| `load_config` | charge `config/<contexte>.env` |

Ne connaît rien des configurations : c'est le script appelant qui décide d'en
charger une.

## `config/` — fait

Un fichier par contexte : `config/docker.env`, `config/k3s.env`…

- `<contexte>.env.example` versionné, sert de modèle ;
- `<contexte>.env` jamais versionné, propre à chaque serveur.

Tout script chargeant une configuration expose `--config <nom>`, ce qui permet de
nommer le fichier différemment selon la machine sans modifier le script.

## `.gitattributes` — fait

```text
* text=auto eol=lf
```

Fins de ligne `LF` garanties. Sans cela, un script enregistré sous Windows
échoue sous Linux avec `/usr/bin/env: bad interpreter`.

## Journalisation et rotation — `common.sh` fait, script de mise en place à faire

Chaque script écrit à l'écran **et** dans un fichier nommé d'après lui :
`/var/log/mgnetworking/<script>.log` en root, `<racine>/logs/<script>.log` sinon.

La rotation est assurée par `logrotate`, présent par défaut sur Debian, Ubuntu et
Synology DSM. Il s'exécute une fois par jour et lit `/etc/logrotate.d/`. Le
fichier à y déposer, `/etc/logrotate.d/mgnetworking` :

```text
/var/log/mgnetworking/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
```

Rotation hebdomadaire, huit semaines conservées, anciens fichiers compressés.
Le motif `*.log` couvre automatiquement tout script ajouté par la suite : cette
configuration n'aura jamais à être modifiée.

Ce dépôt est effectué par `Linux/System/configure-logging.sh` (section 1),
à lancer une fois par serveur. **Ce script reste à écrire.**

Détail technique du socle :
[architecture-technique.md](architecture-technique.md).

---

# 1. Linux / System

Responsabilité : administration du système Linux lui-même, indépendamment de Docker et Kubernetes.

```text
Linux/System/
├── system-info.sh
├── update-system.sh
├── configure-logging.sh
├── configure-hostname.sh
├── configure-timezone.sh
├── configure-swap.sh
├── manage-users.sh
├── check-disk.sh
├── check-memory.sh
├── check-services.sh
└── reboot-system.sh
```

### `system-info.sh`

Script en lecture seule. Afficher :

- distribution et version ;
- kernel ;
- architecture ;
- CPU ;
- RAM ;
- stockage ;
- hostname ;
- uptime ;
- IP ;
- utilisateur courant ;
- date/heure.

### `update-system.sh`

Mettre à jour les paquets. Première cible : Debian/Ubuntu.

Prévoir `--dry-run` et `--yes`. Ne jamais redémarrer automatiquement.

### `configure-logging.sh`

À lancer une fois par serveur, à la mise en route. Deux actions :

1. créer `/var/log/mgnetworking` avec les permissions adéquates ;
2. déposer `/etc/logrotate.d/mgnetworking` — contenu en section 0.

Vérifier la présence de `logrotate` avant d'écrire, et ne pas écraser une
configuration existante sans confirmation. Idempotent : relançable sans effet de
bord.

### `configure-hostname.sh`

Configurer le hostname et assurer la cohérence de `/etc/hosts` lorsque nécessaire.

Usage :

```bash
./configure-hostname.sh my-server
```

### `configure-timezone.sh`

Configurer le fuseau horaire en validant qu'il existe.

Usage :

```bash
./configure-timezone.sh Europe/Paris
```

### `configure-swap.sh`

Afficher le swap actuel et permettre de créer/configurer un swapfile. Ne jamais écraser un swap existant sans confirmation.

### `manage-users.sh`

Créer des utilisateurs, gérer les groupes et sudo. Ne jamais stocker de mots de passe dans le script.

### `check-disk.sh`

Diagnostic de `df`, partitions, inodes et répertoires consommateurs.

### `check-memory.sh`

Diagnostic RAM, swap et processus consommateurs.

### `check-services.sh`

Afficher les services systemd actifs/en échec et permettre de vérifier un service précis.

### `reboot-system.sh`

Redémarrage explicite et confirmé du serveur. `--yes` possible pour l'automatisation.

---

# 2. Linux / Security

Responsabilité : sécurisation du serveur Linux.

```text
Linux/Security/
├── configure-ssh.sh
├── disable-root-login.sh
├── configure-firewall.sh
├── configure-fail2ban.sh
├── audit-users.sh
├── audit-ports.sh
└── security-check.sh
```

### `configure-ssh.sh`

Configurer SSH de manière sécurisée. Valider la configuration avant tout redémarrage. Ne jamais risquer de couper l'accès administrateur sans avertissement.

### `disable-root-login.sh`

Désactiver la connexion SSH directe de root uniquement après avoir vérifié qu'un compte administrateur fonctionnel existe.

### `configure-firewall.sh`

Configurer le firewall, initialement avec une cible Debian/Ubuntu clairement définie. Préserver obligatoirement SSH avant activation.

### `configure-fail2ban.sh`

Installer/configurer Fail2ban, initialement pour SSH.

### `audit-users.sh`

Auditer utilisateurs, shells, groupes privilégiés et membres de sudo.

### `audit-ports.sh`

Afficher les ports en écoute et les processus associés avec `ss`/`lsof`.

### `security-check.sh`

Lancer les contrôles non destructifs et produire des statuts :

```text
PASS
WARNING
FAIL
INFO
```

Contrôler notamment SSH, firewall, utilisateurs privilégiés, ports, services et mises à jour.

---

# 3. Linux / Docker — abandonnée

Cette couche prévoyait `prepare-docker-host.sh`, `configure-docker-host.sh` et
`verify-docker-host.sh` : architecture, kernel, disque et mémoire, puis groupe
`docker`, répertoires de données et permissions.

**Abandonnée le 2026-09-13.** Le préflight d'`install-docker.sh` couvre le même
besoin — l'ordre d'installation imposé par [CLAUDE.md](../CLAUDE.md) le lui
demande déjà : OS, architecture, ressources, dépendances, conflits. Une couche
Linux distincte aurait fait vérifier deux fois les mêmes conditions, par deux
scripts qu'il aurait fallu tenir d'accord.

La frontière `Linux/` ↔ `Docker/` reste valable pour tout le reste : elle cesse
seulement de justifier trois scripts dont le contenu tient dans un préflight. Le
numéro de section est conservé pour ne pas rompre les renvois.

---

# 4. Linux / K3s

Responsabilité : installation et administration de K3s sur Linux.

```text
Linux/K3s/
├── install-k3s.sh
├── configure-k3s.sh
├── verify-k3s.sh
├── upgrade-k3s.sh
└── uninstall-k3s.sh
```

### `install-k3s.sh`

Préflight :

1. arguments ;
2. privilèges ;
3. OS ;
4. architecture ;
5. ressources ;
6. réseau ;
7. conflits éventuels.

Puis installation via le mécanisme officiel K3s, activation du service et vérification du cluster.

Ne pas copier l'installateur K3s dans le dépôt et ne pas stocker de secrets.

### `configure-k3s.sh`

Gérer la configuration persistante, notamment :

```text
/etc/rancher/k3s/config.yaml
```

Séparer cette configuration de l'installation.

### `verify-k3s.sh`

Vérifier :

```text
service k3s
nodes
pods -A
namespaces
events
version
```

### `upgrade-k3s.sh`

Afficher version actuelle/cible, vérifier la santé du cluster, demander confirmation, effectuer la mise à niveau puis vérifier nodes et pods.

### `uninstall-k3s.sh`

Désinstallation explicitement confirmée. Documenter les données susceptibles d'être supprimées. Utiliser la procédure officielle.

---

# 5. Kubernetes / Installation

Responsabilité : outils et composants de l'écosystème Kubernetes, indépendamment de la distribution Kubernetes.

> **Frontière avec `Linux/K3s/`** — critère de rangement :
> *si K3s était remplacé par un cluster managé dans le cloud, ce script
> survivrait-il ?*
>
> - **Oui** → `Kubernetes/` : `kubectl`, Helm, ingress, cert-manager, namespaces,
>   TLS, diagnostics. Ces scripts s'adressent à un cluster, quelle que soit son
>   origine.
> - **Non** → `Linux/K3s/` : installer, mettre à niveau, désinstaller K3s,
>   configurer son service systemd. Spécifique à K3s sur Linux.
>
> `Linux/K3s/` reste plat : cinq scripts ne justifient pas un découpage
> Installation / Configuration / Maintenance.

```text
Kubernetes/Installation/
├── install-kubectl.sh
├── install-helm.sh
├── install-ingress.sh
├── install-cert-manager.sh
└── install-metrics.sh
```

### `install-kubectl.sh`

Installer/vérifier `kubectl`, son architecture, sa version et son accès au cluster.

### `install-helm.sh`

Installer/vérifier Helm.

### `install-ingress.sh`

Installer l'Ingress Controller retenu par le projet. Une seule solution doit être définie et documentée.

### `install-cert-manager.sh`

Installer cert-manager, attendre les pods et vérifier les ressources.

### `install-metrics.sh`

Installer la solution de métriques retenue lorsque nécessaire.

---

# 6. Kubernetes / Configuration

Responsabilité : configuration des ressources communes du cluster.

```text
Kubernetes/Configuration/
├── configure-namespaces.sh
├── configure-storage.sh
├── configure-ingress.sh
├── configure-tls.sh
└── configure-registry.sh
```

### `configure-namespaces.sh`

Créer les namespaces nécessaires au cluster.

### `configure-storage.sh`

Configurer StorageClass et éléments de stockage. Aucune suppression destructive automatique.

### `configure-ingress.sh`

Configurer les règles HTTP/HTTPS communes.

### `configure-tls.sh`

Configurer les ressources TLS après installation de cert-manager. Ne jamais versionner les clés privées.

### `configure-registry.sh`

Configurer l'accès à un registry privé. Les credentials doivent être injectés comme secrets.

---

# 7. Kubernetes / Maintenance

Responsabilité : exploitation et diagnostic du cluster.

```text
Kubernetes/Maintenance/
├── cluster-status.sh
├── diagnostics.sh
├── pods-status.sh
├── events.sh
├── resource-usage.sh
├── backup-resources.sh
└── cleanup-resources.sh
```

### `cluster-status.sh`

Afficher nodes, versions, namespaces, pods, deployments et services.

### `diagnostics.sh`

Rechercher notamment :

- `NotReady` ;
- `Pending` ;
- `CrashLoopBackOff` ;
- erreurs ;
- événements ;
- workloads indisponibles.

### `pods-status.sh`

Afficher les pods globalement ou pour un namespace.

### `events.sh`

Afficher les événements Kubernetes de manière exploitable.

### `resource-usage.sh`

Afficher CPU et mémoire disponibles lorsque les métriques le permettent.

### `backup-resources.sh`

Exporter les manifests importants. Ne jamais placer de secrets en clair dans un dépôt public.

### `cleanup-resources.sh`

Nettoyer uniquement les ressources explicitement identifiées. Prévoir confirmation et idéalement `--dry-run`.

---

# 8. Docker / Installation

Responsabilité : installation et validation de Docker Engine.

```text
Docker/Installation/
├── install-docker.sh
└── verify-docker.sh
```

### `install-docker.sh`

Première cible : Debian/Ubuntu.

Étapes :

```text
préflight
→ paquets conflictuels
→ dépôt officiel
→ installation
→ service
→ permissions
→ test
```

Installe le moteur, le CLI, `containerd`, Buildx et le plugin Compose par les
dépôts officiels. Le préflight porte aussi ce que la section 3 abandonnée
prévoyait : architecture, kernel, disque, mémoire.

Ne jamais supprimer une installation existante sans confirmation.

### `verify-docker.sh`

Vérifier daemon, version, permissions, stockage, réseau et exécution d'un
conteneur de test. Lecture seule.

---

# 8 bis. Docker / Configuration

Responsabilité : configuration du moteur et des ressources d'infrastructure
partagées entre projets.

```text
Docker/Configuration/
├── configure-docker.sh
└── create-network.sh
```

### `configure-docker.sh`

Écrire `/etc/docker/daemon.json` de manière idempotente : rotation des journaux
de conteneurs en premier lieu, afin qu'aucun conteneur ne fasse croître le disque
sans borne. Valider la configuration avant de l'appliquer, et ne redémarrer le
démon que si elle a réellement changé.

Les valeurs propres à la machine viennent de `config/server.env`.

### `create-network.sh`

Créer un réseau Docker nommé, indépendant de tout fichier Compose, afin que
plusieurs projets Compose distincts puissent se joindre sur un même réseau :

```text
Compose applicatif ───┐
                      ├── réseau externe partagé
Compose reverse proxy ┘
```

Le nom est un argument, jamais une valeur codée en dur pour une application
donnée. Idempotent : un réseau déjà présent et conforme n'est pas recréé.

---

# 9. Docker / Maintenance

Responsabilité : administration courante de Docker standalone.

```text
Docker/Maintenance/
├── update-docker.sh
├── update-images.sh
├── restart-container.sh
├── container-logs.sh
└── inspect-container.sh
```

### `update-docker.sh`

Mettre à jour le moteur et ses composants — Engine, CLI, `containerd`, Buildx,
Compose — selon ce que le socle a réellement installé. Vérifier l'état avant et
après. Ne touche pas aux images applicatives.

### `update-images.sh`

Mettre à jour les images d'un projet désigné explicitement, jamais de tous les
projets de la machine par défaut. Distinguer la récupération d'une image du
redéploiement d'un service, et préserver les données persistantes.

> Ne pas utiliser ces scripts pour modifier directement les workloads gérés par
> Kubernetes.

### `restart-container.sh`

Redémarrer un conteneur nommé.

### `container-logs.sh`

Simplifier l'accès aux logs.

### `inspect-container.sh`

Afficher image, ports, mounts, réseaux et état sans afficher automatiquement les
secrets.

---

# 9 bis. Docker / Diagnostics

Responsabilité : lecture seule. Aucun script de ce dossier ne modifie l'état de
la machine.

```text
Docker/Diagnostics/
├── check-docker.sh
├── list-containers.sh
├── list-images.sh
└── docker-disk-usage.sh
```

### `check-docker.sh`

Constater qu'un serveur possède un environnement Docker exploitable : présence et
version de Docker, état du service et du démon, versions de Compose et de Buildx,
répertoire et pilote de stockage.

`verify-docker.sh` valide une installation qu'on vient de faire ;
`check-docker.sh` diagnostique une machine qu'on découvre. Les deux restent
séparés.

### `list-containers.sh`

Nom, image, état, ports, réseaux et identifiant des conteneurs. Les conteneurs
actifs par défaut, les conteneurs arrêtés sur demande.

### `list-images.sh`

Dépôt, étiquette, identifiant, date de création, taille et statut d'utilisation
lorsque Docker le fournit.

### `docker-disk-usage.sh`

Consommation de stockage, distinguant images, conteneurs, volumes et cache de
build, et l'espace récupérable lorsque Docker le fournit.

---

# 10. Docker / Cleanup

Responsabilité : récupération des ressources Docker inutilisées.

```text
Docker/Cleanup/
├── docker-cleanup.sh
├── cleanup-images.sh
├── cleanup-containers.sh
├── cleanup-networks.sh
└── cleanup-volumes.sh
```

### `docker-cleanup.sh`

Orchestrer les nettoyages et afficher un résumé avant suppression :

```text
Images inutilisées : ...
Containers arrêtés : ...
Networks inutilisés : ...
Volumes inutilisés : ...
```

`--dry-run` obligatoire, confirmation avant toute suppression réelle, et aucune
suppression d'une ressource en cours d'utilisation.

**Les volumes sont exclus par défaut.** Ils portent les données ; un nettoyage
général ne les emporte jamais sans une intention explicitement exprimée.

Nommé ainsi par [décisions](../orchestration/decisions.md)
décision 15, qui en fait l'un des appelants de `notify-failure.sh`.

### `cleanup-images.sh`

Identifier et supprimer les images inutilisées, en distinguant les images
`dangling` des images simplement inutilisées — la seconde catégorie est bien plus
large, et les confondre détruit des images qu'on voulait garder.

### `cleanup-containers.sh`

Supprimer les conteneurs arrêtés.

### `cleanup-networks.sh`

Supprimer les réseaux inutilisés. Les réseaux d'infrastructure déclarés en
configuration ne sont jamais supprimés par défaut.

### `cleanup-volumes.sh`

Opération très sensible. Afficher les volumes inutilisés et demander confirmation
avant toute suppression.

---

# 11. Synology / Plex

Responsabilité : automatisations Plex sur Synology.

```text
Synology/Plex/
├── organize-series.sh      # existant, à mettre au standard
├── update-plex.sh          # existant, à mettre au standard
├── install-plex.sh
├── backup-plex.sh
├── restore-plex.sh
├── plex-status.sh
└── plex-diagnostics.sh
```

Ces scripts restent indépendants de l'infrastructure Linux/Kubernetes du VPS.

**État** : `organize-series.sh` (anciennement `plex_series_organizer.sh`) et
`update-plex.sh` ont été déplacés depuis la racine du dépôt, avec leur code
d'origine. Ils ne passent pas encore par `lib/common.sh` et ne respectent pas
encore les conventions — c'est le travail de la phase 4.

---

# 12. Synology / Administration

Responsabilité : administration générale du NAS.

```text
Synology/Administration/
├── backup/
├── storage/
├── network/
├── services/
├── users/
└── maintenance/
```

### Backup

Vérification et exécution des sauvegardes.

### Storage

Diagnostic des volumes, espace disponible et utilisation.

### Network

Diagnostic réseau du NAS.

### Services

Contrôle des services Synology.

### Users

Administration des utilisateurs lorsque nécessaire.

### Maintenance

Opérations courantes d'entretien.

---

# 13. README par domaine

Chaque domaine doit avoir son propre README :

```text
Linux/README.md
Docker/README.md
Kubernetes/README.md
Synology/README.md
```

**Au domaine, pas au sous-dossier.** Le dépôt porte aujourd'hui
`Linux/System/README.md` et `Synology/Plex/README.md` : le README y est descendu
d'un cran parce que `Linux/` réunit des sous-domaines sans rapport entre eux —
préparer l'OS, le sécuriser, poser K3s.

`Docker/` est l'inverse : ses cinq dossiers sont les facettes d'un même moteur, et
l'ordre d'utilisation traverse les dossiers — on installe, on configure, puis on
diagnostique. Un README par dossier découperait cet ordre en cinq morceaux dont
aucun ne se tient seul, et deux d'entre eux n'auraient qu'un script à décrire.

**Un seul `Docker/README.md`** donc, créé par la première tâche du domaine qui
s'exécute, complété d'une ligne de tableau par chacune des suivantes. Fixé le
2026-09-13 pour que la question ne se rouvre pas à chaque tâche.

Chaque README documente :

1. rôle ;
2. prérequis ;
3. scripts disponibles ;
4. ordre d'utilisation ;
5. risques ;
6. systèmes supportés ;
7. commandes d'exécution.

Le README racine présente :

```text
# MGNetworking Scripts

## Objectif
## Architecture
## Conventions
## Linux
## Docker
## K3s
## Kubernetes
## Synology
## Sécurité
```

---

# 14. Règles d'implémentation et secrets

Déplacé dans [CLAUDE.md](../CLAUDE.md) — sections « Ordre des scripts
d'installation » et « Secrets ».

Ces règles s'appliqueront encore après l'archivage de ce plan ; elles n'ont donc
qu'une seule source de vérité, chargée automatiquement à chaque session.

---

# 15. Configuration

Séparer les scripts de leur configuration.

Deux niveaux coexistent.

**Configuration de contexte**, un fichier par domaine, propre à chaque serveur :

```text
config/
├── docker.env.example    # versionné, modèle
├── docker.env            # non versionné, propre au serveur
├── k3s.env.example
└── k3s.env
```

Chargée explicitement par le script : `load_config docker`. `lib/common.sh` ne
charge aucune configuration de lui-même. Voir
[architecture-technique.md](architecture-technique.md#3-configuration-de-contexte).

**Configuration d'un composant**, propre à un domaine :

```text
Linux/K3s/
├── install-k3s.sh
├── configure-k3s.sh
└── config.yaml.example
```

Dans les deux cas : les fichiers `.example` sont versionnés, les configurations
réelles ne le sont jamais.

---

# 16. Relation entre les couches

```text
                    Linux
                      │
          ┌───────────┼────────────┐
          │           │            │
       System      Security      Docker
          │
         K3s
          │
          ▼
     Kubernetes
          │
    ┌─────┼──────┐
    │     │      │
  Helm  Ingress  TLS
    │
    ▼
Applications
```

À retenir :

```text
Linux
→ système d'exploitation

Docker
→ moteur de conteneurs

K3s
→ distribution Kubernetes

Kubernetes
→ orchestration

Helm / Ingress / cert-manager
→ outils/composants Kubernetes
```

Les workloads gérés par Kubernetes ne doivent pas être administrés directement avec `docker restart`, `docker stop`, etc.

---

# 17. Ordre de développement

Ne pas développer toute la bibliothèque en une fois.

## Phase 0 — Socle commun — fait

`lib/common.sh`, `config/`, `.gitattributes`, documentation. Voir section 0.

## Phase 1 — VPS actuel

```text
Linux/System/
Linux/Security/
Linux/K3s/
```

Priorité :

```text
system-info.sh
update-system.sh
configure-logging.sh
configure-hostname.sh
configure-timezone.sh
configure-swap.sh

configure-ssh.sh
configure-firewall.sh
security-check.sh

install-k3s.sh
configure-k3s.sh
verify-k3s.sh
```

## Phase 2 — Kubernetes

```text
Kubernetes/Installation/
Kubernetes/Configuration/
Kubernetes/Maintenance/
```

Priorité :

```text
install-kubectl.sh
install-helm.sh
install-ingress.sh
install-cert-manager.sh

configure-namespaces.sh
configure-storage.sh
configure-ingress.sh
configure-tls.sh

cluster-status.sh
diagnostics.sh
backup-resources.sh
```

## Phase 3 — Docker — en cours

**Avancée devant la phase 2 le 2026-09-13**, à la demande de Maxime : le premier
serveur à servir doit héberger une application conteneurisée derrière un reverse
proxy, sans Kubernetes. L'ordre ci-dessus reste celui du plan ; cette phase le
devance sans le remplacer.

```text
Docker/Installation/
Docker/Configuration/
Docker/Maintenance/
Docker/Cleanup/
Docker/Diagnostics/
```

Neuf tâches prioritaires — sections 8 à 10 — dans l'ordre :

```text
install-docker.sh → configure-docker.sh → check-docker.sh → create-network.sh
       ├── list-containers.sh
       └── docker-disk-usage.sh
              → update-images.sh → update-docker.sh → docker-cleanup.sh
```

Le domaine ne connaît aucune application déployée : ni son nom, ni son fichier
Compose, ni sa configuration. Il fournit les primitives, les projets applicatifs
portent leur propre cycle de vie.

La phase est terminée lorsqu'un serveur Linux supporté peut, de bout en bout :
installer Docker, le configurer, le vérifier, créer un réseau partagé,
inventorier ses conteneurs, diagnostiquer son stockage, mettre à jour les images
d'un projet, mettre à jour le moteur, puis nettoyer ce qui ne sert plus.

## Phase 4 — Synology

Déplacement fait : `Synology/Plex/` contient `organize-series.sh` et
`update-plex.sh`, `Synology/Administration/` est créé et vide.

Reste à faire : mettre les deux scripts existants au standard du dépôt
(`lib/common.sh`, conventions, journalisation), puis développer les scripts
manquants des sections 11 et 12.

Les anciens `install.sh`, `Wake-on-LAN.sh` et `exemple_option.sh` ont été
supprimés — sans objet dans la nouvelle organisation, et récupérables dans
l'historique Git si nécessaire.

---

# 18. Consignes de mise en oeuvre

Reportées dans [CLAUDE.md](../CLAUDE.md), qui est chargé automatiquement à chaque
session — ces consignes doivent s'appliquer sans qu'il soit nécessaire d'ouvrir
ce plan.

Elles y sont réparties entre « Conventions de script » (structure, nommage,
idempotence, réutilisation de `lib/common.sh`), « Ordre des scripts
d'installation » (préflight, mécanismes officiels), « Secrets » et « Consignes de
mise en oeuvre » (périmètre, dépendances, tests, exécution répétée).

---

# 19. Première cible concrète

La première version utile du dépôt doit pouvoir couvrir :

```text
lib/common.sh
config/README.md

Linux/
├── System/
│   ├── system-info.sh
│   ├── update-system.sh
│   ├── configure-logging.sh
│   ├── configure-hostname.sh
│   ├── configure-timezone.sh
│   └── configure-swap.sh
│
├── Security/
│   ├── configure-ssh.sh
│   ├── configure-firewall.sh
│   └── security-check.sh
│
└── K3s/
    ├── install-k3s.sh
    ├── configure-k3s.sh
    └── verify-k3s.sh
```

Puis seulement après validation :

```text
Kubernetes/
Docker/
Synology/
```

L'objectif final est de disposer d'une bibliothèque personnelle permettant de reconstruire, sécuriser, déployer et maintenir progressivement une infrastructure Linux/K3s/Kubernetes, tout en conservant les automatisations Synology existantes dans un domaine séparé.
