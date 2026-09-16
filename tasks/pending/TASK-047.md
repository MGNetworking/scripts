---
id: TASK-047
title: "Écrire Linux/Security/disable-root-login.sh"
status: ready
priority: high
depends_on:
  - TASK-046
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Désactiver la connexion SSH directe de root (PermitRootLogin no, décision 19) par un
  fichier déposé, seulement après avoir vérifié qu'un compte administrateur
  fonctionnel existe (décision 20), avec validation « sshd -t » et retour arrière.
scope:
  - Linux/Security/disable-root-login.sh
  - tests/integration/disable-root-login.test.sh
out_of_scope:
  - les réglages de configure-ssh.sh, le port et les clés d'hôte
  - le verrouillage du mot de passe de root
acceptance_criteria:
  - mêmes gardes que configure-ssh.sh — root, compte non-root sudo avec clé, inclusion de sshd_config.d — refus en 1 en nommant la cause
  - dépôt dans sshd_config.d/05-mgnetworking-root.conf, lu avant les autres, idempotent
  - après « sshd -t », « sshd -T » confirme permitrootlogin no ; sinon restauration et 1
  - rechargement « systemctl reload ssh » et avertissement de garder la session ouverte
  - --dry-run, confirmation, --yes et ASSUME_YES remise à false (décision 45)
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/disable-root-login.sh --help"
implementation_notes:
  - même montage de faux binaires que TASK-046 ; s'inspirer de Linux/Security/configure-ssh.sh une fois écrit
---

# TASK-047 — Interdire la connexion de root

Dernier du domaine : il suppose le durcissement de TASK-046 en place.
