---
id: TASK-070
title: "Écrire Kubernetes/Configuration/configure-tls.sh"
status: in_progress
priority: medium
depends_on:
  - TASK-062
  - TASK-065
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Créer les ClusterIssuers letsencrypt-staging et letsencrypt-production (plan §6,
  décision 23), HTTP-01, e-mail SRV_K8S_ACME_EMAIL, par kubectl apply, sans demander de certificat.
scope:
  - Kubernetes/Configuration/configure-tls.sh
  - tests/integration/configure-tls.test.sh
  - config/server.env.example — SRV_K8S_ACME_EMAIL
out_of_scope:
  - créer un Certificate, pour quelque domaine que ce soit ; variable de domaine
  - installer cert-manager (TASK-065) ; Middlewares Traefik (TASK-069)
  - solveur DNS-01 et certificats wildcard ; lire, exporter ou afficher les Secrets de clé ACME ; supprimer un issuer
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent, API injoignable, CRD ClusterIssuer absente ou webhook cert-manager non prêt → 1 en nommant la cause
  - SRV_K8S_ACME_EMAIL absente ou vide → 2 la nommant ; e-mail mal formé → 2 ; dans les deux cas aucun appel kubectl
  - letsencrypt-staging et letsencrypt-production existent après exécution, solveur HTTP-01 ingressClassName traefik, et atteignent Ready dans le délai borné, sinon 1
  - aucun objet Certificate ni CertificateRequest créé par le script ; aucun appel réseau du script vers Let's Encrypt
  - seconde exécution → aucun changement (kubectl diff rend 0, apply non appelé)
  - --dry-run affiche la différence et rend 0 sans appeler apply ; sans terminal ni --yes, 1 si un changement est à faire
  - aucune clé privée ni contenu de Secret n'apparaît dans la sortie ni dans le journal ; aucune suppression (ni delete ni --prune)
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-tls.sh --help"
implementation_notes:
  - "faits VÉRIFIÉS par la session sur la documentation officielle (cert-manager.io/docs/configuration/acme/) : apiVersion cert-manager.io/v1, kind ClusterIssuer (ressource de cluster, sans namespace) ; champs spec.acme.email, spec.acme.server, spec.acme.privateKeySecretRef.name, spec.acme.solvers[].http01.ingress.ingressClassName ; pas de champ « class » ni d'autre groupe"
  - "serveurs : letsencrypt-staging → https://acme-staging-v02.api.letsencrypt.org/directory ; letsencrypt-production → https://acme-v02.api.letsencrypt.org/directory ; solveur ingressClassName: traefik (IngressClass de K3s, vérifiée par install-ingress.sh)"
  - "privateKeySecretRef.name : letsencrypt-staging-account-key et letsencrypt-production-account-key ; ce Secret est créé par cert-manager dans son namespace de ressources de cluster (par défaut cert-manager), jamais par le script, qui ne le lit ni ne l'affiche jamais"
  - "e-mail : SRV_K8S_ACME_EMAIL lue depuis config/server.env (chargé par common.sh) ; forme stricte local@domaine.tld (^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$), sans espace, retour ligne, guillemet ni caractère YAML ; jugée après le parsing et avant tout appel kubectl → 2 ; jamais injectée dans le YAML sans cette validation (injection YAML), et posée entre guillemets"
  - "config/server.env.example : bloc commenté SRV_K8S_ACME_EMAIL sous le bloc cert-manager, au style des blocs voisins (rôle, effet, valeur absente → 2)"
  - "manifeste des deux ClusterIssuers en heredoc, label app.kubernetes.io/managed-by=mgnetworking, écrit une fois et passé sur stdin (kubectl diff -f - puis apply -f -) ; relecture par get clusterissuers -l <label> -o name : exactement les deux noms"
  - "préflight : kubectl get crd clusterissuers.cert-manager.io → NotFound nommé (cert-manager non installé, TASK-065), 1 ; webhook non prêt : diff/apply échouent avec « failed calling webhook » (webhook.cert-manager.io, connection refused ou no endpoints available) → message qui nomme le webhook cert-manager, 1, testé avant la règle « injoignable », réservée à l'apiserver"
  - "echec() au modèle de Kubernetes/Configuration/configure-ingress.sh : 124 délai, Forbidden, Unauthorized/x509, ressource inconnue, CRD absente (« no matches for kind », « ensure CRDs are installed », « unable to recognize »), injoignable réservé au réseau, message neutre sinon"
  - "Ready : kubectl wait --for=condition=Ready clusterissuer/<nom> --timeout=<ATTENTE>s ; expiré, le vrai rend 1 avec « error: timed out waiting for the condition on clusterissuers/<nom> » → 1 nommant l'issuer ; timeout externe = ATTENTE + 2 pour cet appel, délai + 2 pour les autres ; 124 nommé"
  - "idempotence : kubectl diff rend 0 identique (rien appliqué, apply jamais appelé), 1 différences, 2 ou plus erreur ; --dry-run affiche le diff et n'appelle jamais apply ni wait"
  - "garde /.dockerenv avant tout trap ou écriture (surcharges DELAI_TEST/ATTENTE_TEST) ; require_cmd timeout ; --request-timeout sur chaque appel kubectl, prouvé par le journal du faux ; stderr tenu à part"
  - "confirmation par confirm, export ASSUME_YES=false avant le parsing (décision 45), testée sous pseudo-terminal (script -qec) ; sans terminal ni --yes et changement à faire → 1"
  - "faux kubectl en tête de PATH : contrôle le manifeste reçu sur stdin document par document et par clé parente (acme.email, acme.server, privateKeySecretRef.name, http01.ingress.ingressClassName sous chaque issuer), honore -l, rend les vrais codes de kubectl diff (0, 1, 2) et de wait, et les vrais messages ; journalise chaque appel ; échoue si un verbe create/delete ou un kind Certificate/CertificateRequest/Secret apparaît"
  - "mutations volontaires du manifeste (serveur interverti, ingressClassName changée, e-mail absent d'un document) dans une copie jetable du script → la suite doit échouer ; aucun cluster réel ; des tests qui ne prouveraient que le faux sont refusés"
---

# TASK-070 — Configurer TLS

Un ClusterIssuer HTTP-01 n'a pas besoin du domaine ; le staging évite les limites de
débit de production. Chaque site demande son certificat dans son propre Ingress.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
