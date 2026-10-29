# Performance probes

- `timings.sh`: cold, write and warm runs of the five tools on the current directory (`/usr/bin/time -p`).
- `prof.sh <label> <command…>`: runs the command and samples it every millisecond (`sample`), writing
  `/tmp/perf/out/<label>.{stdout,stderr,sample}` (create `/tmp/perf/out` first).
- `top.sh <label> [n]`: top-of-stack symbols of a sample.
- `incl.sh <label> <image> [n]`: inclusive sample count per function of one image (the tool's binary name).

Sample counts are comparable inside one run only; absolute times move with machine load (research
`2026-10-29-performance-on-maintastic.md`).
