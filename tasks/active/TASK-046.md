---
id: TASK-046
title: "Écrire Linux/Security/configure-ssh.sh"
status: in_progress
priority: high
depends_on:
  - TASK-025
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Durcir sshd par un fichier déposé dans /etc/ssh/sshd_config.d/ — PasswordAuthentication
  no, KbdInteractiveAuthentication no, PubkeyAuthentication yes, port inchangé
  (décision 19) — validé par « sshd -t » avant tout rechargement, et seulement si un
  compte non-root avec sudo et clé existe (décision 20).
scope:
  - Linux/Security/configure-ssh.sh
  - tests/integration/configure-ssh.test.sh
out_of_scope:
  - PermitRootLogin — c'est disable-root-login.sh
  - toute modification de sshd_config lui-même, du port ou des clés d'hôte
acceptance_criteria:
  - root requis (1) ; refus en 1 sans compte non-root membre de sudo ayant un authorized_keys non vide (SRV_ADMIN_UTILISATEUR ou --utilisateur), en le nommant
  - refus en 1 si sshd_config n'inclut pas sshd_config.d/*.conf
  - dépôt dans sshd_config.d/10-mgnetworking.conf par temporaire puis mv ; identique, rien n'est réécrit ni rechargé
  - « sshd -t » valide avant rechargement ; en échec, l'état antérieur est restauré et le script rend 1
  - rechargement par « systemctl reload ssh », jamais restart ; un avertissement demande de garder la session ouverte et de tester une connexion
  - --dry-run, confirmation et --yes comme configure-firewall.sh (ASSUME_YES remise à false, décision 45)
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/configure-ssh.sh --help"
implementation_notes:
  - faux sshd, systemctl et getent en tête de PATH ; les chemins sous /etc/ssh sont surchargeables par variables pour le test
---

# TASK-046 — Durcir SSH

**Peut couper l'accès à la machine** (plan §2). La garde de la décision 20 et
« sshd -t » avant rechargement sont les deux verrous.
