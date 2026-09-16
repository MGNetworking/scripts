---
id: TASK-054
title: "Écrire Linux/K3s/uninstall-k3s.sh"
status: in_progress
priority: medium
depends_on:
  - TASK-051
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Désinstaller K3s par la procédure officielle /usr/local/bin/k3s-uninstall.sh (plan §4),
  après avoir listé les données qui seront détruites et obtenu une confirmation explicite.
scope:
  - Linux/K3s/uninstall-k3s.sh
  - tests/integration/uninstall-k3s.test.sh
out_of_scope:
  - toute suppression écrite à la main (rm -rf) en complément ou à la place du désinstallateur officiel
  - sauvegarde des ressources Kubernetes — Kubernetes/Maintenance/backup-resources.sh
  - suppression de Docker, des images Docker, des règles ufw ou de config/
  - archive ou copie des données avant suppression (décision 47 : aucune archive)
acceptance_criteria:
  - root requis (1) ; K3s absent (ni k3s ni k3s-uninstall.sh) → rend 0 en le disant, rien exécuté
  - binaire k3s présent sans k3s-uninstall.sh → refus en 1, rien supprimé
  - le résumé liste les chemins détruits et leur taille (du), dont les volumes local-path sous /var/lib/rancher/k3s/storage
  - ASSUME_YES remise à false avant les options (décision 45) ; seul --yes confirme ; sans terminal ni --yes, 1
  - --dry-run affiche le résumé et rend 0 sans appeler le désinstallateur
  - après exécution, binaire, unité k3s et répertoires listés ont disparu, sinon 1 en nommant ce qui reste
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/K3s/uninstall-k3s.sh --help"
implementation_notes:
  - faux k3s, k3s-uninstall.sh et systemctl en tête de PATH ; chemins surchargeables par variable ; aucun rm réel hors répertoire temporaire du test
  - décision 47 : /usr/local/bin/k3s-uninstall.sh seul, appelé après affichage du résumé de ce qui sera détruit
  - test : garde conteneur (/.dockerenv absent → sortie) avant tout trap, écriture ou suppression ; il ne peut jamais lancer un vrai désinstallateur
  - faux systemctl fidèle (is-active inactif → 3, is-enabled unité absente → 1) ; INSTALL_K3S_* et K3S_* héritées neutralisées (unset) dans le test
  - ASSUME_YES=true exportée sans --yes : refus prouvé sous pseudo-terminal (script -qec), pas seulement sans terminal
  - require_cmd sur les commandes utilisées ; aucun jeton (K3S_TOKEN, node-token) affiché ni journalisé
  - état final relu (binaire, unité, répertoires) : un reste → 1 en le nommant ; message d'échec exact, sans consigne de retour arrière inopérante (A74)
---

# TASK-054 — Désinstaller K3s

**Destructif** : toutes les données persistantes des pods (local-path) disparaissent.
La liste des chemins supprimés par k3s-uninstall.sh (/etc/rancher/k3s,
/var/lib/rancher/k3s, /var/lib/kubelet…) est à relever dans le désinstallateur
réel, pas supposée.


**Décidé par `user` le 2026-09-16** : voir `orchestration/decisions.md`, décision 47.
