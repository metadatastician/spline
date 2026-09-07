#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Spline owns the contract; Groove owns its executable checker and fixtures.
set -euo pipefail
if [[ $# != 1 || ! -d $1 ]]; then
  printf 'Usage: bash tests/check_alignment.sh /path/to/groove-checkout\n' >&2
  exit 2
fi
groove_root="$(cd "$1" && pwd)"
for path in scripts/check-bebop-alignment.mjs scripts/check-bebop-alignment.test.mjs registry/bebop-voice-signal-alignment.json spec/conformance/bebop/voice_signal_frames.hex; do
  if [[ ! -f "$groove_root/$path" ]]; then
    printf 'Missing authoritative Groove input: %s\n' "$path" >&2
    exit 2
  fi
done
printf 'Alignment verification scope: %s\n' "$groove_root"
git -C "$groove_root" rev-parse HEAD
bun "$groove_root/scripts/check-bebop-alignment.mjs"
bun "$groove_root/scripts/check-bebop-alignment.test.mjs"
printf 'Recorded-frame alignment passed: criterion (c), not live pairing criterion (d).\n'
