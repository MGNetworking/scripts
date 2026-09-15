---
id: TASK-043
title: "Écrire Linux/Security/security-check.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Produire, en lecture seule, un bilan de sécurité à statuts PASS, WARNING, FAIL,
  INFO — SSH, firewall, fail2ban, comptes privilégiés, mises à jour en attente —
  utilisable en tâche planifiée.
scope:
  - Linux/Security/security-check.sh
  - tests/integration/security-check.test.sh
out_of_scope:
  - toute correction : le script constate, il ne répare rien
  - le branchement sur notify-failure.sh et sur cron — tâche distincte
acceptance_criteria:
  - chaque contrôle rend une ligne « STATUT  contrôle — détail », statut parmi PASS, WARNING, FAIL, INFO
  - SSH (« sshd -T ») — passwordauthentication no et permitrootlogin no donnent PASS, sinon FAIL (décision 19)
  - ufw actif avec deny en entrée donne PASS ; inactif FAIL ; absent WARNING (décision 21)
  - fail2ban actif avec la prison sshd donne PASS, sinon WARNING (décision 22)
  - un compte à UID 0 autre que root donne FAIL ; des mises à jour en attente donnent WARNING avec leur nombre
  - un outil absent rend le contrôle INFO « non vérifiable », jamais PASS
  - code 0 sans FAIL, 1 dès un FAIL, 2 sur option inconnue ; le bilan final compte chaque statut
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/security-check.sh --help"
implementation_notes:
  - chaque commande interrogée (sshd, ufw, fail2ban-client, getent, apt-get -s) est bornée par timeout et remplacée par un faux binaire dans le fichier de cas
  - apt-get -s upgrade ne modifie rien ; ne jamais lancer apt-get update
---

# TASK-043 — Bilan de sécurité

Lecture seule, destiné à cron (plan §2). Son code 1 sur FAIL permettra de le
brancher sur `notify-failure.sh` (décision 15).
