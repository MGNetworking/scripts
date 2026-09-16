# Linux/K3s

Distribution K3s mono-nœud (décision 23) : ce qui dépend de K3s lui-même. Ce qui
survivrait à un cluster managé va dans `Kubernetes/`. Cibles : Debian 12 et 13,
Ubuntu 22.04 et 24.04 LTS (décision 14).

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `verify-k3s.sh` | diagnostic en lecture seule, rubriques dans l'ordre : service `k3s` (`systemctl is-active`), version, nœuds, pods de tous les namespaces, namespaces, événements Warning ; tout passe par `k3s kubectl`, chaque appel borné par `--request-timeout` ; un nœud non Ready, un pod ni Running ni Succeeded (« Completed ») ou un service inactif sont nommés en `[WARN]` ; les événements Warning s'affichent sans peser sur le verdict. Codes : 0 cluster sain, 1 K3s absent ou anomalie, 2 option inconnue | root (`/etc/rancher/k3s/k3s.yaml`) | non |
| `install-k3s.sh` | installe K3s serveur mono-nœud par l'installateur officiel `https://get.k3s.io`. Préflight : root, cible de la décision 14 en amd64 ou arm64, au moins 5 120 Mo libres sous `/var/lib` (bloquant), mémoire sous 512 Mo (`[WARN]` seul), ports 6443, 80 et 443 libres (`ss`, dont l'échec bloque), `get.k3s.io` joignable en HTTPS. K3s déjà présent : version affichée, rien réinstallé, 0. Version : canal `stable`, ou `SRV_K3S_VERSION` de `config/server.env` (décision 47) ; `INSTALL_K3S_*`, `K3S_URL` et `K3S_TOKEN` hérités sont ignorés. Installateur téléchargé en HTTPS seul (`--proto '=https'`) dans un temporaire, exécuté puis retiré, jamais `curl \| sh` ; `systemctl enable k3s`, service actif, puis `verify-k3s.sh`. `--dry-run` : préflight et commande, sans réseau. `--yes` obligatoire hors terminal ; `ASSUME_YES` hérité ignoré (décision 45). Codes : 0 installé et sain ou déjà présent, 1 refus ou échec nommé, 2 option inconnue | root | oui |
| `configure-k3s.sh` | écrit `/etc/rancher/k3s/config.yaml` entier (décision 47), jamais édité : `write-kubeconfig-mode: "0600"` et `tls-san` tiré de `SRV_K3S_TLS_SAN` (`config/server.env`, virgules ; clé omise si vide), rien d'autre. Chaque entrée doit être une IPv4, une IPv6 ou un nom d'hôte, sinon 2 sans rien écrire. Contenu et droits (0600) identiques : rien réécrit ni redémarré ; seuls les droits diffèrent : `chmod` seul. Sinon différence affichée, confirmation, original sauvegardé en `config.yaml.<horodatage>.bak`, écriture par temporaire puis `mv`, `systemctl restart k3s`, puis `verify-k3s.sh` ; échec de l'un ou l'autre : original restauré (ou fichier retiré s'il n'y en avait pas), K3s relancé, 1. `--dry-run` : différence seule, 0. `--yes` obligatoire hors terminal ; `ASSUME_YES` hérité ignoré (décision 45). Codes : 0 écrit, conforme ou `--dry-run`, 1 root, K3s absent, redémarrage ou diagnostic en échec, 2 option inconnue ou valeur mal formée | root | oui |
| `upgrade-k3s.sh` | met K3s à niveau par l'installateur officiel vers une version **explicite et obligatoire** (décision 47) : `--version vX.Y.Z+k3sN` ou `SRV_K3S_VERSION`, forme validée strictement, jamais « dernière stable ». Versions en place et cible affichées ; identiques : 0 sans rien télécharger. Refusés en 1 sans rien modifier : cible absente ou invalide, K3s absent (renvoi vers `install-k3s.sh`), changement de majeure, recul, saut de plus d'une mineure (comparaison champ à champ en base dix), `verify-k3s.sh` en échec avant. `INSTALL_K3S_*`, `K3S_URL` et `K3S_TOKEN` hérités neutralisés, seule `INSTALL_K3S_VERSION` transmise. Résumé, confirmation ; installateur en HTTPS seul (`--proto '=https' --tlsv1.2`) dans un temporaire, exécuté puis retiré ; version relue, qui doit égaler la cible ; puis `verify-k3s.sh`. Tout échec après le téléchargement rend 1 en affichant la version réellement en place ; aucun retour arrière automatique. `--dry-run` : versions, diagnostic et commande prévue, sans téléchargement ; root requis quand même. `--yes` obligatoire hors terminal ; `ASSUME_YES` hérité ignoré (décision 45). Codes : 0 à niveau, déjà à jour ou simulé, 1 refus ou échec nommé, 2 option inconnue | root | oui |
| `uninstall-k3s.sh` | désinstalle K3s serveur par le seul désinstallateur officiel `/usr/local/bin/k3s-uninstall.sh` (décision 47) ; aucune suppression écrite dans le script, aucune archive ni sauvegarde. K3s absent (ni binaire ni désinstallateur) : 0 sans rien exécuter ; binaire sans désinstallateur, ou nœud agent (`k3s-agent-uninstall.sh` seul) : refus en 1, rien supprimé. Résumé : chemins détruits selon `install.sh` officiel (`create_killall`, `create_uninstall`) avec leur taille `du` — `/etc/rancher/k3s`, `/var/lib/rancher/k3s` dont les volumes local-path de `storage`, `/var/lib/kubelet`, `/var/lib/cni`, `/run/k3s`, `/run/flannel`, `k3s-killall.sh`, `k3s.service` et `k3s.service.env` —, binaire, état du service. Confirmation, puis désinstallateur ; état relu : binaire, unité (fichier ou connue de systemd), chemins listés, service actif ; tout reste rend 1 en le nommant, et un désinstallateur sorti en 0 sans rien supprimer est signalé (autres unités `k3s*.service` ou `/etc/init.d/k3s*`). `INSTALL_K3S_*` et `K3S_*` hérités neutralisés. `--dry-run` : résumé seul, root requis. `--yes` obligatoire hors terminal ; `ASSUME_YES` hérité ignoré (décision 45). Codes : 0 désinstallé, absent ou simulé, 1 refus ou état final incomplet, 2 option inconnue | root | oui, destructif |

## Ordre d'utilisation

Après `Linux/System` et `Linux/Security`. `install-k3s.sh`, puis
`configure-k3s.sh` pour `/etc/rancher/k3s/config.yaml`. `upgrade-k3s.sh` plus
tard, une version mineure à la fois. `uninstall-k3s.sh` en dernier, après une
sauvegarde faite à part (`Kubernetes/Maintenance/backup-resources.sh`).
`verify-k3s.sh` sert de vérification finale à l'installation et à la mise à
niveau, qui lisent son code de retour.

```bash
sudo ./Linux/K3s/install-k3s.sh --dry-run   # préflight et commande prévue, rien d'installé
sudo ./Linux/K3s/install-k3s.sh             # résumé, confirmation, installation, diagnostic
sudo ./Linux/K3s/configure-k3s.sh --dry-run # différence avec config.yaml, rien d'écrit
sudo ./Linux/K3s/configure-k3s.sh           # différence, confirmation, écriture, redémarrage, diagnostic
sudo ./Linux/K3s/upgrade-k3s.sh --version v1.31.1+k3s1 --dry-run # versions, diagnostic, commande prévue
sudo ./Linux/K3s/upgrade-k3s.sh --version v1.31.1+k3s1           # résumé, confirmation, mise à niveau, diagnostic
sudo ./Linux/K3s/uninstall-k3s.sh --dry-run # ce qui serait détruit, avec les tailles, rien supprimé
sudo ./Linux/K3s/uninstall-k3s.sh           # résumé, confirmation, désinstallateur officiel, état relu
sudo ./Linux/K3s/verify-k3s.sh              # diagnostic ; code 0 si le cluster est sain
./Linux/K3s/verify-k3s.sh --help            # rubriques et codes de retour
```

## Risques

`install-k3s.sh` télécharge et exécute l'installateur officiel en root : il pose
le binaire `k3s`, le service systemd et `/var/lib/rancher/k3s`. Traefik, conservé
(décision 23), prend 80 et 443 : un reverse proxy Docker déjà en écoute fait
refuser l'installation. Avec ufw en `deny` (décision 21), le trafic des pods et
services (10.42.0.0/16, 10.43.0.0/16) peut être bloqué : à autoriser à part, ce
script ne touche pas au pare-feu. Un installateur qui échoue en cours de route
laisse un état incertain : relancer le script, qui ne réinstalle pas un K3s
présent. Les seuils de disque et de mémoire viennent de la documentation K3s,
non mesurés ici.

`configure-k3s.sh` possède `config.yaml` entier : toute clé ajoutée à la main est
écrasée au prochain passage. Un changement redémarre `k3s`, ce qui coupe l'API le
temps du redémarrage. Les `.bak` s'accumulent dans `/etc/rancher/k3s`, sans purge.

`upgrade-k3s.sh` remplace le binaire et fait redémarrer `k3s` par l'installateur :
l'API est coupée le temps du redémarrage. Il ne revient jamais en arrière de
lui-même ; un échec à mi-chemin rend 1 en affichant la version réellement en
place, à diagnostiquer par `verify-k3s.sh`. Ses messages d'échec suggèrent un
retour par `install-k3s.sh`, qui ne réinstalle pas un K3s présent (A74).

`uninstall-k3s.sh` est **destructif et sans retour** : le cluster, sa
configuration et toutes les données persistantes des pods (volumes local-path)
disparaissent ; rien n'est archivé. Sauvegarder avant, à part. Docker, ufw et
`config/` ne sont pas touchés. Il contient une racine de test (`RACINE_TEST`),
suivie seulement dans un conteneur (`/.dockerenv`) et annoncée en `[WARN]` (A76).

Aucun de ces scripts n'affiche ni kubeconfig, ni jeton de nœud, ni Secret. Ils
n'ont été éprouvés qu'avec de faux `curl`, installateur, désinstallateur, `k3s`,
`systemctl` et `ss`, jamais contre un vrai cluster.
