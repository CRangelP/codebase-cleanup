#!/usr/bin/env bash
# Runs the three suites in order and stops at the first red — a broken gate
# contract makes the rest of the run noise. Each one still works on its own.
# Usage: test.sh   (exit 0 = all three passed)
set -u

cd "$(dirname "$0")" || exit 2
for suite in gate_test.sh rollback_test.sh coherence_test.sh; do
  echo "=== $suite"
  "${BASH:-bash}" "$suite" || { echo "=== $suite FAILED — stopping here"; exit 1; }
done
echo "=== gate_test.sh, rollback_test.sh and coherence_test.sh: all green"
