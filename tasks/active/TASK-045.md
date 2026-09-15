---
id: TASK-045
title: "Écrire Linux/Security/configure-firewall.sh"
status: in_progress
priority: high
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Configurer ufw selon la décision 21 — deny en entrée, allow en sortie, SSH autorisé
  AVANT toute activation, ports supplémentaires par configuration — sans jamais
  pouvoir couper l'accès SSH.
scope:
  - Linux/Security/configure-firewall.sh
  - tests/integration/configure-firewall.test.sh
  - config/server.env.example — SRV_SSH_PORT et SRV_FIREWALL_PORTS
out_of_scope:
  - ufw reset, toute suppression de règle existante, nftables et iptables direct
  - toute ouverture non demandée par SRV_FIREWALL_PORTS ou --port
acceptance_criteria:
  - root requis (1) ; cibles de la décision 14 ; ufw installé par apt-get s'il manque
  - la règle du port SSH (SRV_SSH_PORT, défaut 22) est posée et vérifiée dans « ufw status » avant « ufw enable » ; absente, refus en 1 sans activer
  - politiques deny incoming et allow outgoing ; chaque port de SRV_FIREWALL_PORTS ou de --port (forme 443/tcp) est autorisé ; une valeur mal formée rend 2
  - une règle déjà présente n'est pas reposée ; une seconde exécution ne change rien et le dit
  - le résumé est confirmé ; --yes seul le confirme (ASSUME_YES remise à false avant les options, décision 45) ; sans terminal ni --yes, refus en 1
  - --dry-run affiche l'état et les commandes ufw prévues, sans rien modifier, et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/configure-firewall.sh --help"
implementation_notes:
  - faux ufw traceur en tête de PATH ; le fichier de cas vérifie l'ORDRE des appels, règle SSH avant enable, et ne lance jamais un vrai ufw
---

# TASK-045 — Firewall ufw

**Peut couper l'accès à la machine** (plan §2) : la règle SSH vérifiée avant
activation est le cœur de la tâche.
