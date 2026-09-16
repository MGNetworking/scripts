---
id: TASK-052
title: "Écrire Linux/K3s/configure-k3s.sh"
status: pending
priority: medium
depends_on:
  - TASK-051
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Tenir la configuration persistante de K3s dans /etc/rancher/k3s/config.yaml (plan §4),
  séparée de l'installation, à partir de config/, avec redémarrage seulement si le
  fichier a changé.
scope:
  - Linux/K3s/configure-k3s.sh
  - tests/integration/configure-k3s.test.sh
  - config/server.env.example — variables SRV_K3S_* retenues par la décision ci-dessous
out_of_scope:
  - installer, mettre à niveau ou désinstaller K3s
  - désactiver Traefik (décision 23), toute clé non listée par la décision attendue
  - les manifestes de /var/lib/rancher/k3s/server/manifests, ufw, cert-manager
acceptance_criteria:
  - root requis (1) ; K3s absent → refus en 1 en le nommant
  - le fichier est généré depuis config/, écrit par temporaire puis mv ; identique, rien n'est réécrit ni redémarré
  - une valeur mal formée dans config/ rend 2 sans rien écrire
  - un config.yaml existant qui diffère est affiché en différence avant confirmation, et sauvegardé avant remplacement
  - résumé confirmé ; --yes seul le confirme ; sans terminal ni --yes, 1 ; --dry-run affiche la différence et rend 0
  - après changement, « systemctl restart k3s » puis verify-k3s.sh ; échec → restauration de l'ancien fichier, redémarrage, 1
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/K3s/configure-k3s.sh --help"
implementation_notes:
  - faux k3s et systemctl en tête de PATH ; le répertoire /etc/rancher/k3s est surchargeable par variable pour le test
  - pas de parseur YAML : le script produit le fichier entier, il ne l'édite pas
---

# TASK-052 — Configurer K3s

K3s ne lit config.yaml qu'au démarrage, d'où le redémarrage. Redémarrer k3s
n'arrête pas les conteneurs des pods (à confirmer dans la documentation K3s).

Décision attendue de user : contenu géré — (a) `write-kubeconfig-mode: "0600"` et
`tls-san` depuis SRV_K3S_TLS_SAN, rien d'autre, ou (b) liste plus large ?
Recommandé : (a).

Décision attendue de user : cible — (a) config.yaml entier, possédé par le script,
ou (b) dépôt dans config.yaml.d/50-mgnetworking.yaml ? Recommandé : (a), nommé par
le plan ; (b) suppose le support config.yaml.d, à vérifier sur la version retenue.
