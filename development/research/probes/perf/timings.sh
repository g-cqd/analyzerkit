#!/bin/zsh
# Cold, cache-writing and warm wall/user/sys of the five tools on one corpus. Run from the corpus root.
# Usage: G=<dir holding the five checkouts, release-built> timings.sh
set -u; : ${G:?directory with arcleak, deadwood, dolly, fcheck, modeler checkouts built with -c release}
C=$(mktemp -d /private/tmp/analyzer-cache.XXXXXX); trap 'rm -rf "$C"' EXIT
t() { local label=$1; shift; /usr/bin/time -p "$@" >/dev/null 2>$C/err; awk -v l="$label" '/^real/{r=$2}/^user/{u=$2}/^sys/{s=$2}
  END{printf "%-16s wall %5.2fs  user %5.2fs  sys %5.2fs  cores %.1f\n", l, r, u, s, (u+s)/r}' $C/err; }
for tool in fcheck modeler dolly arcleak deadwood; do
  sub=analyze; extra=(); [ $tool = modeler ] && sub=check; [ -f .$tool.json ] && extra=(--config .$tool.json)
  t "$tool cold"  $G/$tool/.build/release/$tool $sub . $extra --no-cache
  t "$tool write" $G/$tool/.build/release/$tool $sub . $extra --cache-path $C/$tool
  t "$tool warm"  $G/$tool/.build/release/$tool $sub . $extra --cache-path $C/$tool
done
