#!/bin/zsh
# inclusive sample counts per function of the given image (max count per symbol in the call tree)
f=/tmp/perf/out/$1.sample; img=$2; n=${3:-25}
awk -v img="(in $img)" '/Call graph:/{f=1} /Total number in stack/{f=0} f && index($0,img) {
  line=$0; sub(/^[ +!:|]*/,"",line); split(line,a," "); c=a[1]; sym=line; sub(/^[0-9]+ /,"",sym); sub(/  \(in .*$/,"",sym); sub(/ \+ [0-9]+.*$/,"",sym);
  if (c>m[sym]) m[sym]=c } END { for (s in m) printf "%7d  %s\n", m[s], s }' $f | sort -rn | head -$n
