#!/bin/bash
# Run the Z3 wrapper spike inside the nim-perf container with Z3 installed.
set -e

cd "$(dirname "$0")/../.."
podman run --rm \
  -v "$PWD/z3:/z3" \
  -v "$PWD/../softlink:/softlink" \
  -w /z3/spike \
  localhost/nim-perf:2.2.0 \
  sh -c "
    apt-get update >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y libz3-dev z3 >/dev/null 2>&1
    nim c -r --hints:off --path:/softlink/src spike.nim 2>&1
  "
