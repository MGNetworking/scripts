# AGENTS.md — point d'entrée pour tout agent, quel que soit l'outil

Ce dépôt se conduit par des agents. Le fichier que lit votre outil peut différer
(`CLAUDE.md`, `AGENTS.md`, autre) ; le contenu, lui, est le même pour tous.

**À lire dans cet ordre, avant toute action :**

1. [CLAUDE.md](CLAUDE.md) — comment écrire un script, l'arborescence cible, les secrets.
2. [docs/reprise-2026-09-18.md](docs/reprise-2026-09-18.md) — l'état du projet, ce qui
   vient ensuite, et la procédure de portage vers un autre harnais.
3. [orchestration/regles.md](orchestration/regles.md) — périmètre de modification,
   commandes autorisées, Git, validation, arrêt.
4. [orchestration/decisions.md](orchestration/decisions.md) — les décisions en vigueur.
   Ce qui y est tranché ne se redemande pas.
5. [tasks/README.md](tasks/README.md) — le format d'une tâche et son cycle de vie.

**Les trois règles qui ne se négocient pas :**

- **Rien n'est prouvé tant qu'une commande de `tests/` n'a pas réussi.** Ni la lecture du
  code, ni la conviction d'un modèle.
- **Le dépôt est public** : aucun mot de passe, jeton, clé privée, adresse de serveur ni
  kubeconfig n'y entre, jamais.
- **Un contrat inscrit dans un `CADRAGE.md` est réputé utilisé** : le rompre impose un
  nouveau script ou un nouveau rôle, l'ancien déprécié avec une date (décision 49).

**Registre des anomalies** : [tasks/pending/TASK-039.md](tasks/pending/TASK-039.md). Tout
défaut constaté et non corrigé s'y consigne, nulle part ailleurs.
