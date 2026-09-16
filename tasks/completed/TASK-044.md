---
id: TASK-044
title: "Écrire Linux/Security/configure-fail2ban.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer fail2ban s'il est absent et activer la prison sshd avec les valeurs de la
  distribution (décision 22), par un fichier déposé et idempotent.
scope:
  - Linux/Security/configure-fail2ban.sh
  - tests/integration/configure-fail2ban.test.sh
out_of_scope:
  - toute modification de /etc/fail2ban/jail.conf ou jail.local
  - toute autre prison que sshd, et toute règle de firewall
acceptance_criteria:
  - root requis (1) ; cibles de la décision 14 seulement (1 sinon)
  - le paquet est installé par apt-get s'il manque ; déjà présent, rien n'est réinstallé
  - la prison est déposée dans /etc/fail2ban/jail.d/mgnetworking-sshd.conf ([sshd] enabled = true) ; identique, rien n'est réécrit
  - un changement est annoncé puis confirmé ; --yes le confirme sans question ; sans terminal ni --yes, refus en 1
  - le service est activé et redémarré seulement si quelque chose a changé ; « fail2ban-client status sshd » vérifie la prison, échec → 1
  - --dry-run affiche l'état et ce qui serait fait, sans rien modifier, et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/configure-fail2ban.sh --help"
implementation_notes:
  - faux apt-get, dpkg-query, systemctl et fail2ban-client en tête de PATH ; aucune installation réelle en test
  - écrire le fichier par un temporaire puis mv, jamais par ajout ; le répertoire jail.d est surchargeable par variable pour le test
---

# TASK-044 — fail2ban, prison sshd

Modifie le système, un effet borné (plan §2).
