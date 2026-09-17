#!/usr/bin/env bash
set -Eeuo pipefail

# Vérifie, en lecture seule, l'Ingress Controller Traefik fourni par K3s : IngressClass,
# déploiement de kube-system, occupants des ports 80 et 443. Rien n'est installé ni arrêté :
# le reconfigurer relève de Kubernetes/Configuration/.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5                  # --request-timeout de chaque appel kubectl, en secondes
MARGE=2                  # « timeout » qui l'entoure : le laisser écrire son message
NS_TRAEFIK="kube-system" # namespace où K3s pose Traefik
PORTS="80 443"           # les deux ports que l'Ingress Controller publie

usage() {
    cat <<'EOF'
install-ingress.sh — vérifie l'Ingress Controller Traefik de K3s, en lecture seule.

Usage : install-ingress.sh [--help]

Rien n'est installé : K3s fournit Traefik. Sont constatés l'IngressClass
« traefik » et la classe par défaut, le déploiement traefik de kube-system et
son image, puis les occupants possibles des ports 80 et 443 : Services
LoadBalancer étrangers à Traefik, et écoutes de la machine lues par « ss ».
Une autre IngressClass, comme un port déjà pris, sont signalés sans changer le
code : une seule solution est retenue, et arrêter l'occupant n'est pas du ressort
de ce script.

kubectl résout seul son kubeconfig — KUBECONFIG, sinon ~/.kube/config ; root
n'est pas requis, et chaque appel est borné par --request-timeout (5 s).

Codes de retour :
  0  Traefik est prêt — avertissements compris
  1  kubectl ou ss absent, cluster injoignable, IngressClass traefik absente,
     déploiement traefik absent ou non disponible, droits insuffisants,
     kubeconfig invalide, délai dépassé
  2  option inconnue — seul cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Même motif que install-kubectl.sh : un kubectl absent apprend où K3s le pose.
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl est introuvable dans le PATH."
    error "K3s le pose lui-même : voir Kubernetes/Installation/install-kubectl.sh."
    exit 1
fi
require_cmd timeout
command -v ss >/dev/null 2>&1 || die "ss est introuvable dans le PATH (paquet iproute2) : l'écoute des ports 80 et 443 ne peut pas être vérifiée."

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à un tableau serait lu comme une ligne de données.
REP=""; ERREUR=""; CODE=0
lire() {
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec du dernier appel : le 124 vient de « timeout », pas du cluster.
echec() {
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $1 a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh." ;;
    esac
}
# Deux champs nommés, jamais une position : le nom, puis la marque de classe par
# défaut — vide quand l'annotation est absente. Cette rubrique sert aussi de sonde.
printf '\nIngressClass\n'
lire get ingressclasses -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
[ "$CODE" = 0 ] || echec "« kubectl get ingressclasses »"
TRAEFIK=""; DEFAUT=""; AUTRES=""
while read -r nom marque; do
    [ -n "$nom" ] || continue
    if [ "$nom" = "traefik" ]; then TRAEFIK="oui"; fi
    [ "$marque" != "true" ] || DEFAUT="$nom"
    [ "$nom" = "traefik" ] || AUTRES="$AUTRES $nom"
done <<<"$REP"
printf '  IngressClass traefik : %s\n  IngressClass par défaut : %s\n' "${TRAEFIK:+présente}${TRAEFIK:-ABSENTE}" "${DEFAUT:-aucune}"
[ -n "$TRAEFIK" ] || die "IngressClass traefik absente du cluster : K3s la pose avec son Ingress Controller. Rien n'a été installé ; un second contrôleur ferait deux solutions."
[ -z "$AUTRES" ] || warn "Autre(s) IngressClass présente(s) :$AUTRES — une seule solution est retenue (Traefik), la coexistence est signalée sans plus."
printf '\nDéploiement traefik (%s)\n' "$NS_TRAEFIK"
lire get deployment traefik -n "$NS_TRAEFIK" --no-headers \
    -o 'custom-columns=IMAGE:.spec.template.spec.containers[0].image,PRETES:.status.readyReplicas,DESIREES:.spec.replicas'
case "$ERREUR" in *NotFound*) die "Déploiement traefik absent du namespace $NS_TRAEFIK : l'Ingress Controller n'est pas posé. Rien n'a été installé." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get deployment traefik -n $NS_TRAEFIK »"
[ -n "$REP" ] || die "Le déploiement traefik de $NS_TRAEFIK n'a rendu aucune ligne."
read -r IMAGE PRETES DESIREES <<<"$REP"
# Un champ absent s'affiche « <none> » et vaut zéro : sans réplique prête, le déploiement n'est pas disponible.
case "$PRETES" in ""|*[!0-9]*) PRETES=0 ;; esac
case "$DESIREES" in ""|*[!0-9]*) DESIREES=0 ;; esac
printf '  Image     %s\n  Répliques %s/%s prêtes\n' "$IMAGE" "$PRETES" "$DESIREES"
if [ "$PRETES" -lt "$DESIREES" ] || [ "$PRETES" -lt 1 ]; then die "Déploiement traefik non disponible dans $NS_TRAEFIK : $PRETES/$DESIREES répliques prêtes. Rien n'a été modifié."; fi
printf '\nServices LoadBalancer\n'
lire get services -A -o 'jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.type}{" "}{.spec.ports[*].port}{"\n"}{end}'
[ "$CODE" = 0 ] || echec "« kubectl get services -A »"
CONFLITS=0
while read -r ns nom type ports; do
    [ "$type" = "LoadBalancer" ] || continue
    pris=""
    for p in $ports; do
        case " $PORTS " in *" $p "*) pris="$pris $p" ;; esac
    done
    [ -n "$pris" ] || continue
    # Le Service de Traefik est l'occupant attendu de 80 et 443, pas un conflit.
    if [ "$ns" = "$NS_TRAEFIK" ] && [ "$nom" = "traefik" ]; then
        info "Service $ns/$nom sur les ports$pris : c'est Traefik lui-même."
        continue
    fi
    CONFLITS=$((CONFLITS + 1))
    warn "Service LoadBalancer $ns/$nom : port(s)$pris, déjà publiés par Traefik."
done <<<"$REP"
# ss -p n'énumère les processus que pour root : sans root, le port est nommé seul.
printf '\nÉcoute des ports 80 et 443 sur la machine\n'
if [ "$(id -u)" -eq 0 ]; then OPTS=(-ltnp); else OPTS=(-ltn); fi
ECOUTES=0
if REP="$(timeout "$((DELAI + MARGE))" ss "${OPTS[@]}" 2>"$TEMPORAIRE/erreur")"; then
    while read -r etat _ _ adresse _ reste; do
        [ "$etat" = "LISTEN" ] || continue
        port="${adresse##*:}"
        case " $PORTS " in *" $port "*) ;; *) continue ;; esac
        OCCUPANT="$(printf '%s' "$reste" | sed -n 's/.*users:((\"\([^"]*\)\".*/\1/p')"
        NOM="$OCCUPANT"
        [ -n "$NOM" ] || NOM="processus non nommé — ss ne le donne qu'à root"
        warn "Port $port déjà en écoute sur la machine : $NOM."
        ECOUTES=$((ECOUTES + 1))
    done <<<"$REP"
else
    CODE=$?
    [ "$CODE" != 124 ] || die "« ss ${OPTS[*]} » a été interrompu : délai dépassé (${DELAI} s)."
    sed 's/^/  /' "$TEMPORAIRE/erreur" >&2
    die "« ss ${OPTS[*]} » a échoué (code $CODE) : l'écoute des ports 80 et 443 n'a pas pu être vérifiée."
fi
# Ce que le relevé ne voit pas se dit ici, plutôt que de se conclure d'un silence.
[ "$ECOUTES" -ne 0 ] || info "Aucune écoute visible par ss sur 80 ou 443 — sur K3s, servicelb (klipper-lb) les publie par des pods svclb-traefik-*, dont le hostPort n'ouvre aucune socket."
printf '\n'
[ "$CONFLITS" -eq 0 ] || warn "$CONFLITS occupant(s) étranger(s) des ports 80 et 443 — aucun n'est arrêté par ce script."
success "Traefik est prêt : IngressClass traefik (défaut : ${DEFAUT:-aucune}), déploiement $NS_TRAEFIK disponible ($IMAGE). Rien n'a été installé ni modifié."
