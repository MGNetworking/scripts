#!/usr/bin/env bash
# Grille neutre : comportements seulement, aucun libellé imposé.
# Usage (dans le conteneur, depuis /depot) : bash mesure-oracle.sh
set -u
C="Docker/Diagnostics/check-docker.sh"
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
ok=0; ko=0
v() { if [ "$1" = 0 ]; then ok=$((ok+1)); echo "PASS  $2"; else ko=$((ko+1)); echo "FAIL  $2"; fi; }
code() { "$@" >/dev/null 2>&1; echo $?; }
stub() { printf '#!/bin/sh\ncase "$*" in\n%s\nesac\n' "$1" > "$B/docker"; chmod +x "$B/docker"; }
a() { [ "$1" = "$2" ]; echo $?; }
has() { printf '%s' "$1" | grep -qF -- "$2"; echo $?; }
hasnt() { printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }

[ -f "$C" ] || { echo "FAIL  script absent"; exit 1; }
echo "INFO  $(wc -l < "$C") lignes"

v "$(code bash -n "$C")"                         "syntaxe bash -n"
v "$(code shellcheck -x "$C")"                   "shellcheck -x sans aucun avertissement"

o="$(bash "$C" 2>&1)"; c=$?
v "$(a "$c" 1)"                                  "docker absent : code 1"
v "$(hasnt "$o" 'command not found')"            "docker absent : aucun « command not found »"
v "$(hasnt "$o" 'No such file')"                 "docker absent : aucun « No such file »"
v "$(has "$o" 'docker.sock')"                    "l'état du socket figure dans la sortie"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  "info --format"*) echo "28.5.2|overlay2|/var/lib/docker" ;;
  "info"*) printf "Server Version: 28.5.2\nStorage Driver: overlay2\nDocker Root Dir: /var/lib/docker\n" ;;
  "version --format"*) echo "28.5.2" ;;
  "compose version --short") echo "2.39.1" ;;
  "compose version"*) echo "Docker Compose version v2.39.1" ;;
  "buildx version") echo "github.com/docker/buildx v0.17.1 abcdef0" ;;
  *) exit 1 ;;'
o="$(PATH="$B:$PATH" bash "$C" 2>&1)"; c=$?
v "$(a "$c" 0)"                                  "environnement sain : code 0"
v "$(has "$o" '28.5.2')"                         "sain : version du moteur affichée"
v "$(has "$o" 'overlay2')"                       "sain : pilote de stockage affiché"
v "$(has "$o" '/var/lib/docker')"                "sain : répertoire de données affiché"
v "$(has "$o" '2.39.1')"                         "sain : version de Compose affichée"
v "$(has "$o" '0.17.1')"                         "sain : VERSION de Buildx affichée (le défaut de la référence)"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  *) echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2; exit 1 ;;'
o="$(PATH="$B:$PATH" bash "$C" 2>&1)"; c=$?
v "$(a "$c" 1)"                                  "démon injoignable : code 1"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  *) sleep 60 ;;'
t=$SECONDS; PATH="$B:$PATH" bash "$C" >/dev/null 2>&1; c=$?; t=$((SECONDS-t))
v "$(a "$c" 1)"                                  "démon figé : code 1"
v "$([ "$t" -lt 30 ]; echo $?)"                  "démon figé : main rendue en ${t}s (< 30 s)"

v "$(a "$(code bash "$C" --help)" 0)"            "--help : code 0"
v "$(a "$(code bash "$C" --inconnue)" 2)"        "option inconnue : code 2"

echo "BILAN $ok réussies, $ko échouées"
[ "$ko" = 0 ]
