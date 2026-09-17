---
id: TASK-083
title: "Essai DeepSeek sur une tâche documentaire : lignes « Prouvé par : » des scripts qui restent en Bash"
status: ready
priority: medium
depends_on: []
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Les contrats des scripts que la décision 50 garde en Bash portent une ligne
  « Prouvé par : » nommant leur fichier de cas et leur niveau de preuve. L'écriture est
  confiée à un agent DeepSeek pour mesurer ce que ce profil vaut sur de la documentation,
  face aux conducteurs Opus des cadrages (TASK-074 à 077).
scope:
  - Docker/CADRAGE.md — contrats des 3 scripts de Diagnostics/
  - Kubernetes/CADRAGE.md — contrats des 7 scripts de Maintenance/
out_of_scope:
  - les contrats des scripts voués à un rôle Ansible (installation, configuration)
  - Linux/CADRAGE.md et Synology/CADRAGE.md
  - modifier un script, un fichier de cas ou un README
acceptance_criteria:
  - chaque contrat visé porte une ligne « Prouvé par : <fichier de cas> — niveau <simulé|conteneur|machine> », le niveau étant celui que la décision 50 définit
  - chaque fichier de cas cité existe et contient au moins une assertion sur le script du contrat ; un contrat sans preuve porte « Prouvé par : rien — à combler » et une ligne au registre
  - aucune autre ligne des deux cadrages n'est modifiée (git diff limité aux ajouts)
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - décision 50 pour les trois niveaux de preuve ; décision 49 pour le rôle d'un cadrage
  - mesure attendue dans le rapport - jetons et durée de l'agent, défauts relevés par la relecture, comparés aux conducteurs Opus des cadrages
---

# TASK-083 — Essai DeepSeek sur de la documentation

Validé par user le 2026-09-17 : essayer DeepSeek sur une tâche documentaire avant d'y
basculer les suivantes. Le verdict se prend sur les chiffres du rapport.
