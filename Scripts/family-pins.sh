#!/bin/sh
# Lists every remote requirement in the manifests of the packages under a directory, and fails when one package is
# required in two different spellings and at least one of them names a revision or a branch: SwiftPM refuses that
# graph ("required using two different revision-based requirements") as soon as one package depends on both sides,
# even when the two spellings name the same commit (analyzerkit ADR-0025). Version ranges that differ are reconciled
# by SwiftPM and are not reported. Manifests are read as text; nothing is resolved or run.
#
# It reads each checkout's working-tree manifest: the requirements the next train would bring if every package took
# the others' heads, not the graph resolved today (a pinned revision of a dependency may predate a requirement its head
# adds). A requirement in the root does not override a conflict between two dependencies (ADR-0025, probe C6).
#
# Usage: Scripts/family-pins.sh <directory holding the checkouts> [package ...]
#   With package names, only those checkouts are read: a conflict matters only between packages that can meet in one
#   graph, and a directory may hold unrelated groups.
# Exit: 0 consistent, 1 a conflicting spelling, 64 usage.
set -eu
root=${1:-}
if [ -z "$root" ] || [ ! -d "$root" ]; then
    echo "usage: $0 <directory holding the package checkouts>" >&2
    exit 64
fi
shift
only=" $* "

table=$(
    for manifest in "$root"/*/Package.swift; do
        [ -f "$manifest" ] || continue
        package=$(basename "$(dirname "$manifest")")
        if [ "$only" != "  " ]; then
            case "$only" in (*" $package "*) ;; (*) continue ;; esac
        fi
        # One line per manifest, comments dropped (a // after a space or at a line's start, never a URL's), then
        # every url: "..." with the requirement that follows it up to the first closing parenthesis.
        sed -E 's#(^|[[:space:]])//.*$#\1#' "$manifest" | tr '\n\t' '  ' | awk -v package="$package" '{
            text = $0
            while (match(text, /url: *"[^"]+" *,[^)]*/)) {
                entry = substr(text, RSTART, RLENGTH)
                text = substr(text, RSTART + RLENGTH)
                url = entry; sub(/^url: *"/, "", url); sub(/".*$/, "", url)
                requirement = entry; sub(/^url: *"[^"]+" *, */, "", requirement)
                gsub(/  +/, " ", requirement); sub(/ +$/, "", requirement)
                identity = url; sub(/\/+$/, "", identity); sub(/\.git$/, "", identity); sub(/^.*\//, "", identity)
                print tolower(identity) "\t" requirement "\t" package
            }
        }'
    done | sort
)

if [ -z "$table" ]; then
    echo "no remote requirement found under $root"
    exit 0
fi

printf '%s\n' "$table" | awk -F '\t' '
    { requirements[$1] = requirements[$1] "\n" $2; packages[$1 "\t" $2] = packages[$1 "\t" $2] " " $3; rows[NR] = $0 }
    END {
        status = 0
        for (identity in requirements) {
            split(substr(requirements[identity], 2), list, "\n")
            distinct = 0; pinned = 0; delete seen
            for (i in list) {
                if (!(list[i] in seen)) { seen[list[i]] = 1; distinct++ }
                if (list[i] ~ /^(revision|branch):/) pinned = 1
            }
            if (distinct > 1 && pinned) {
                status = 1
                printf "conflict: %s is required in %d spellings\n", identity, distinct
                for (requirement in seen) printf "  %s:%s\n", requirement, packages[identity "\t" requirement]
            }
        }
        for (i = 1; i <= NR; i++) {
            split(rows[i], field, "\t")
            if (field[2] ~ /^(revision|branch):/) printf "%-28s %-60s %s\n", field[1], field[2], field[3]
        }
        exit status
    }'
