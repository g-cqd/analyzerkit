#!/bin/zsh
# top-of-stack (self) and the heaviest frames in the tool's own image
f=/tmp/perf/out/$1.sample; n=${2:-12}
echo "  [self]"; awk '/Sort by top of stack/{f=1;next} /Binary Images/{f=0} f&&NF' $f | head -$n | sed 's/^ */    /'
