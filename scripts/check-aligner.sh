#!/usr/bin/env bash
#
# Compiles the alignment algorithm on its own and runs it against a simulated transcript.
#
# The aligner is the product: if it drifts, the app is broken in a way no screenshot shows. It
# depends only on Foundation, so it can be checked in a second without a simulator, a microphone,
# or a test target.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/modules/sufler-core/ios"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

xcrun swiftc -O \
  "$src/Session/ScriptModel.swift" \
  "$src/Speech/TextNormalizer.swift" \
  "$src/Speech/Aligner.swift" \
  "$root/modules/sufler-core/tests/main.swift" \
  -o "$out/check-aligner"

"$out/check-aligner"
