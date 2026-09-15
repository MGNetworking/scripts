---
id: TASK-041
title: "Écrire Linux/Security/audit-users.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Auditer, en lecture seule, les comptes de la machine : comptes à UID 0, comptes
  dotés d'un shell de connexion, membres des groupes privilégiés (sudo, adm, docker)
  et, si /etc/shadow est lisible, comptes au mot de passe vide.
scope:
  - Linux/Security/audit-users.sh
  - tests/integration/audit-users.test.sh
out_of_scope:
  - toute modification de compte, de groupe ou de fichier
  - les clés SSH des utilisateurs et les sessions ouvertes
acceptance_criteria:
  - le script ne modifie rien et s'exécute sans root ; sans droit de lire /etc/shadow, il le dit et poursuit
  - chaque compte à UID 0 autre que root est signalé en [WARN]
  - les comptes à shell de connexion et les membres de sudo, adm et docker sont listés, un par ligne
  - un compte au mot de passe vide dans /etc/shadow est signalé en [WARN]
  - code 0 quand l'audit est produit, 1 si getent est absent, 2 sur option inconnue
  - --help documente les rubriques et les codes
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/Security/audit-users.sh --help"
  - "tests/env/run-in-container.sh -- bash Linux/Security/audit-users.sh"
implementation_notes:
  - lire les comptes par getent passwd et getent group, jamais en analysant /etc/passwd à la main
  - le fichier de cas remplace getent par un faux binaire en tête de PATH ; le chemin de shadow est surchargeable par variable
---

# TASK-041 — Auditer les comptes

Premier script du domaine `Linux/Security` (plan §2), en lecture seule : il prépare
ce que `security-check.sh` résume et ce qu'exige la garde de la décision 20.
