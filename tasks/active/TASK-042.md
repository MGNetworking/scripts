---
id: TASK-042
title: "Écrire Linux/Security/audit-ports.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher, en lecture seule, les ports TCP et UDP en écoute, l'adresse d'écoute et
  le processus associé, en distinguant ce qui écoute sur toutes les interfaces de ce
  qui n'écoute qu'en local.
scope:
  - Linux/Security/audit-ports.sh
  - tests/integration/audit-ports.test.sh
out_of_scope:
  - toute règle de firewall — c'est configure-firewall.sh
  - lsof, nmap et tout balayage réseau
acceptance_criteria:
  - un seul appel à « ss -H -tulpn », sans rien modifier
  - chaque ligne donne protocole, adresse, port et processus ; un processus illisible sans root est affiché « inconnu (root requis) »
  - les écoutes sur 0.0.0.0, [::] ou * sont marquées « exposé », celles sur 127.0.0.1 ou [::1] « local »
  - un résumé compte les ports exposés
  - code 0 quand le relevé est produit, même vide ; 1 si ss est absent ; 2 sur option inconnue
  - --help documente les colonnes et les codes
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/audit-ports.sh --help"
  - "tests/env/run-in-container.sh -- bash Linux/Security/audit-ports.sh"
implementation_notes:
  - ss vient d'iproute2, présent dans l'image de test ; le fichier de cas le remplace par un faux ss à sortie fixe
---

# TASK-042 — Auditer les ports en écoute

Lecture seule (plan §2). Sert à `security-check.sh` et aux ouvertures de
`configure-firewall.sh`.
