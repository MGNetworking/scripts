# lien-ecrit.awk — faux binaire écrit à travers un lien symbolique (A122, tests/README.md).
#
# Signale, dans un fichier de cas, une écriture « > » ou « >> » vers un chemin où une
# ligne précédente a créé un lien symbolique (« ln -s »), sans « rm » de ce chemin
# entre les deux : l'écriture suit le lien et remplace le vrai binaire du conteneur.
# Comparaison textuelle des chemins, ligne à ligne. Seuls sont développés :
#   - la variable d'une boucle « for v in a b; » (dernière liste vue pour v) ;
#   - « $1 » d'une fonction d'une ligne qui écrit « …/$1 », à chaque appel « fonction mot ».
#     C'est la forme du faux timeout de TASK-071 (6ad93f8) : « faux timeout <<EOF ».
# Limites : registre A123.
#
# Usage : awk -f lien-ecrit.awk <fichier de cas> — une ligne « FAIL » par écriture fautive.

function sans_guillemets(texte) { gsub(/["{}]/, "", texte); return texte }

# Chemins possibles d'une expression, séparés par des espaces : chaque variable de
# boucle remplacée par chacune de ses valeurs. Profondeur bornée à 4, pour qu'une
# liste qui contiendrait sa propre variable ne boucle pas sans fin.
function developper(chemin, profondeur,   var, n, i, valeurs, avant, apres, res) {
    if (profondeur < 4) for (var in boucle) if (match(chemin, "[$]" var "([^A-Za-z0-9_]|$)")) {
        # Gardés avant la récursion, qui réécrit RSTART.
        avant = substr(chemin, 1, RSTART - 1); apres = substr(chemin, RSTART + 1 + length(var))
        n = split(boucle[var], valeurs, " "); res = ""
        for (i = 1; i <= n; i++) res = res " " developper(avant valeurs[i] apres, profondeur + 1)
        return res
    }
    return chemin
}

function chemins(expression, liste) { return split(developper(sans_guillemets(expression), 0), liste, " ") }

function ecriture(expression,   n, i, cible) {
    n = chemins(expression, cible)
    for (i = 1; i <= n; i++) if (cible[i] in lien)
        printf "FAIL  faux binaire écrit à travers un lien : %s:%d, %s (lien ligne %d) — tests/README.md\n",
            FILENAME, FNR, cible[i], lien[cible[i]]
}

# Dernier argument d'une commande, redirections (« 2>/dev/null », « > f ») écartées.
function dernier_argument(commande,   n, i, mots) {
    n = split(commande, mots, " ")
    for (i = n; i > 1; i--) if (mots[i] !~ /^[0-9&]*>/ && mots[i - 1] !~ /^[0-9&]*>+$/) return mots[i]
    return ""
}

{
    ligne = $0
    sub(/(^|[ \t])#.*/, "", ligne)
    if (match(ligne, /for [A-Za-z_][A-Za-z0-9_]* in [^;]*/)) {
        split(substr(ligne, RSTART, RLENGTH), mots, " ")
        debut = 8 + length(mots[2])
        boucle[mots[2]] = sans_guillemets(substr(ligne, RSTART + debut, RLENGTH - debut))
    }
    if (match(ligne, /(^|[;&|{( \t])rm +[^;&|]*/)) {
        n = split(substr(ligne, RSTART, RLENGTH), mots, " ")
        for (i = 2; i <= n; i++) if (mots[i] !~ /^-/) {
            m = chemins(mots[i], cible); for (j = 1; j <= m; j++) delete lien[cible[j]]
        }
    }
    if (match(ligne, /(^|[;&|{( \t])ln +(-[A-Za-z]+ +)*-[A-Za-z]*s[A-Za-z]*( [^;&|]*)?/)) {
        commande = substr(ligne, RSTART, RLENGTH)
        if (commande !~ / -[A-Za-z]*t/) {
            n = chemins(dernier_argument(commande), cible)
            for (i = 1; i <= n; i++) lien[cible[i]] = FNR
        }
    }
    if (match(ligne, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
        nom = substr(ligne, RSTART, RLENGTH - 2); sub(/^[ \t]*/, "", nom)
        if (match(ligne, /[^0-9&>]>>? *"?[^" ;|&)]*\$1/)) {
            cible_fonction = sans_guillemets(substr(ligne, RSTART, RLENGTH)); sub(/^[^>]*>+ */, "", cible_fonction)
            fonction[nom] = cible_fonction
            next
        }
    }
    for (nom in fonction) if (match(ligne, "(^|[;&|{( \t])" nom " +[A-Za-z0-9_.-]+")) {
        argument = substr(ligne, RSTART, RLENGTH); sub(/^.*[ \t]/, "", argument)
        chemin = fonction[nom]; sub(/\$1/, argument, chemin); ecriture(chemin)
    }
    while (match(ligne, /(^|[^0-9&>])>>? *"?[^" ;|&)<>]+/)) {
        redirection = substr(ligne, RSTART, RLENGTH); ligne = substr(ligne, RSTART + RLENGTH)
        sub(/^[^>]*>+ */, "", redirection); ecriture(redirection)
    }
}
