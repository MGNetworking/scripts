---
id: TASK-065
title: "Écrire Kubernetes/Installation/install-cert-manager.sh"
status: in_progress
priority: high
depends_on:
  - TASK-062
  - TASK-063
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer cert-manager (décision 23, plan §5) par le chart Helm officiel jetstack, à une
  version obligatoire, CRD comprises, puis attendre ses déploiements et relire ses CRD.
scope:
  - Kubernetes/Installation/install-cert-manager.sh
  - tests/integration/install-cert-manager.test.sh
  - config/server.env.example — SRV_CERT_MANAGER_VERSION
out_of_scope:
  - ClusterIssuer, Let's Encrypt, domaine, Certificate — c'est configure-tls.sh (Kubernetes/Configuration)
  - désinstallation ; suppression de CRD ; retour arrière de version ; CRD posées par kubectl apply
  - installer Helm ou kubectl ; installer cmctl ; lire /etc/rancher/k3s/k3s.yaml
acceptance_criteria:
  - aucun require_root ; helm et kubectl trouvent seuls KUBECONFIG ou ~/.kube/config ; aucune référence à k3s.yaml
  - helm ou kubectl absent, cluster injoignable — rend 1 en le nommant, renvoi vers TASK-063 / TASK-062
  - version cible obligatoire (--version prioritaire, sinon SRV_CERT_MANAGER_VERSION, forme vX.Y.Z) ; absente ou invalide — 1
  - release cert-manager présente à la version voulue — version affichée, rien refait, 0 ; CRD cert-manager.io sans release Helm — refus en 1, rien modifié
  - release à une version inférieure à la voulue — résumé « installée → voulue », rappel de lire les notes de version de cert-manager, confirmation (décision 45, --yes seul ; sans terminal ni --yes, 1), puis helm upgrade --install à la version voulue avec crds.enabled=true, attente des trois déploiements, version relue égale à la voulue, sinon 1
  - version voulue inférieure à l'installée — refus en 1, rien modifié (pas de retour arrière)
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche version et commande helm prévues, sans aucun helm install ni upgrade, rend 0
  - chart OCI officiel jetstack oci://quay.io/jetstack/charts/cert-manager, version épinglée, CRD installées par le chart (crds.enabled=true), namespace cert-manager créé
  - déploiements cert-manager, cert-manager-cainjector et cert-manager-webhook attendus avec délai borné ; dépassement — 1 en nommant les non prêts, rien désinstallé
  - CRD certificates, issuers et clusterissuers relues après installation ; manquante — 1 ; codes 0 / 1 / 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-cert-manager.sh --help"
implementation_notes:
  - vérifié par l'orchestrateur sur https://cert-manager.io/docs/installation/helm/ le 2026-09-17 (l'agent n'a pas d'accès web, ne rien inventer au-delà)
  - source de référence (« source of truth ») — chart OCI oci://quay.io/jetstack/charts/cert-manager, sans helm repo add ; le dépôt HTTP https://charts.jetstack.io est dit legacy et mis à jour plus tard — ne pas l'utiliser ; helm reçoit --timeout 5m (hook startupapicheck) sous un timeout externe plus long (330 s), 124 nommé
  - commande officielle — helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --version vX.Y.Z --namespace cert-manager --create-namespace --set crds.enabled=true ; le script emploie helm upgrade --install avec les mêmes options, pour la première installation comme pour la mise à jour confirmée ; comparaison de versions numérique champ par champ (X, Y, Z), jamais lexicale
  - CRD par crds.enabled=true (pas installCRDs) ; conservées à la désinstallation depuis v1.15.0 ; les supprimer efface tous Issuers, ClusterIssuers, Certificates — le script ne désinstalle rien et ne supprime aucune CRD
  - déploiements du namespace cert-manager — cert-manager, cert-manager-cainjector, cert-manager-webhook ; attente par kubectl rollout status --timeout=<délai>s sans --request-timeout, le tout sous timeout <délai + 2> ; code 124 nommé comme dépassement
  - version validée strictement ^v[0-9]+\.[0-9]+\.[0-9]+$ (ex. v1.21.2) ; release lue par helm list -n cert-manager -f '^cert-manager$' (colonne CHART cert-manager-vX.Y.Z)
  - require_cmd helm kubectl timeout ; tout appel kubectl porte --request-timeout, sauf kubectl rollout status (borné par --timeout et le timeout externe) ; stderr capturé à part de stdout ; distinguer NotFound, Forbidden, API injoignable et kubeconfig invalide (messages distincts)
  - "formats réels à imiter dans les faux — kubectl « Error from server (NotFound): … not found » et « Error from server (Forbidden): … » code 1 ; « The connection to the server … was refused - did you specify the right host or port? » ou « Unable to connect to the server: … » code 1 ; « error: error loading config file … » code 1 ; rollout status dépassé « error: timed out waiting for the condition » code 1 ; helm « Error: … » code 1"
  - neutraliser les variables héritées qui détournent la cible de helm — unset HELM_NAMESPACE HELM_KUBECONTEXT HELM_KUBETOKEN HELM_KUBEAPISERVER HELM_KUBEASUSER HELM_KUBEASGROUPS HELM_KUBECAFILE HELM_KUBEINSECURE_SKIP_TLS_VERIFY HELM_DRIVER ; KUBECONFIG hérité respecté tel quel, jamais fixé par le script
  - aucun [SUCCESS] après un échec partiel (A78) ; ASSUME_YES (décision 45) testée sous pseudo-terminal ; chaque exécution de test sous timeout
  - faux helm et kubectl en tête de PATH, aux vrais codes et messages, traçant leurs arguments ; aucun appel réseau, dépôt ni cluster réel ; le --dry-run prouvé par l'absence de toute trace install/upgrade ; aucun test qui ne prouve que le faux
  - garde /.dockerenv avant tout trap ou écriture ; modèles Kubernetes/Installation/install-helm.sh, install-kubectl.sh et Kubernetes/Maintenance/*.sh
---

# TASK-065 — Installer cert-manager

Doutes levés le 2026-09-17 sur la documentation officielle : `crds.enabled=true`, noms des
trois déploiements, chart OCI préféré au dépôt HTTP legacy (critère de source ajusté en
conséquence, toujours le chart officiel jetstack de la décision 48).

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
