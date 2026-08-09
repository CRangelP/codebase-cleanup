#!/usr/bin/env bash
# Runs the four suites in order and stops at the first red — a broken gate
# contract makes the rest of the run noise. Each one still works on its own.
# Usage: test.sh   (exit 0 = all four passed)
set -u

cd "$(dirname "$0")" || exit 2
# Capture gate_test.sh's NN/NN so coherence_test.sh can reuse it (avoids a
# second full matrix under scripts/test.sh). Standalone coherence still runs
# the suite itself.
GATE_TEST_CASE_COUNT=""
for suite in gate_test.sh guard_test.sh rollback_test.sh coherence_test.sh; do
  echo "=== $suite"
  if [[ $suite == gate_test.sh ]]; then
    gate_log=$(mktemp)
    "${BASH:-bash}" "$suite" | tee "$gate_log"
    rc=${PIPESTATUS[0]}
    GATE_TEST_CASE_COUNT=$(sed -n 's|^[0-9][0-9]*/\([0-9][0-9]*\) cases passed$|\1|p' "$gate_log" | tail -1)
    export GATE_TEST_CASE_COUNT
    rm -f "$gate_log"
    [[ $rc -eq 0 ]] || { echo "=== $suite FAILED — stopping here"; exit 1; }
  else
    "${BASH:-bash}" "$suite" || { echo "=== $suite FAILED — stopping here"; exit 1; }
  fi
done
echo "=== gate_test.sh, guard_test.sh, rollback_test.sh and coherence_test.sh: all green"
