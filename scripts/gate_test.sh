#!/usr/bin/env bash
# Contract tests for gate.sh: exit codes 0/1/3, the checks= line and PARTIAL.
# Stacks whose toolchain is absent from the machine are covered by PATH stubs —
# the contract does not depend on the real toolchain, only on its exit code.
# Usage: gate_test.sh   (exit 0 = the whole matrix passed)
set -u

GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"
TMP=$(mktemp -d)
# The escapee case spawns a process outside the gate's process group on
# purpose; the suite kills it on the way out so a failure never leaks it.
# More than one case spawns one, so the sweep is a glob over every pid file.
ESCAPEE_PID_FILE=""
cleanup() {
  local f
  for f in "$TMP"/escapee*.pid; do
    [[ -s $f ]] || continue
    kill -KILL "$(cat "$f")" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
failures=0
total=0

BASE="/usr/bin:/bin"


# Extra environment for the next case_run only ("VAR=value VAR2=value2").
# A single string instead of an array: bash 3.2 has no associative arrays and
# word splitting is enough for the assignments used here.
GATE_ENV=""
LAST_ELAPSED=0

stub() { # stub <dir> <name> <exit>
  mkdir -p "$1"
  printf '#!/bin/sh\nexit %s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

stub_body() { # stub_body <dir> <name> <shell body>
  mkdir -p "$1"
  printf '#!/bin/sh\n%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

# link_bin <dir> <name...> — symlinks real binaries into a sandbox dir, so a
# case can build a minimal PATH (one without timeout/gtimeout, say) and still
# have what the gate needs to run. A name absent from the machine is skipped.
link_bin() {
  local dir=$1 name p
  shift
  mkdir -p "$dir"
  for name in "$@"; do
    p=$(command -v "$name") || continue
    ln -sf "$p" "$dir/$name"
  done
}

# stub_log <dir> <name> <log> <exit> — deterministic watchdog delegator: writes
# the arguments it received to <log> and exits with <exit>, never sleeping.
# It is how a case observes which backend gate.sh picked and with what timeout.
stub_log() {
  mkdir -p "$1"
  printf '#!/bin/sh\nprintf %%s "$*" > "%s"\nexit %s\n' "$3" "$4" > "$1/$2"
  chmod +x "$1/$2"
}

# stub_log_probe <dir> <name> <log> — same delegator, but it answers the -k
# capability probe the way GNU timeout does: 'timeout -k 2 1 true' exits 0 and
# leaves no trace, so the log only ever holds the real invocation that follows.
stub_log_probe() {
  mkdir -p "$1"
  {
    printf '#!/bin/sh\n'
    printf 'if [ "$1" = -k ] && [ "$3" = 1 ] && [ "$4" = true ]; then exit 0; fi\n'
    printf 'printf %%s "$*" > "%s"\nexit 124\n' "$3"
  } > "$1/$2"
  chmod +x "$1/$2"
}

assert_log() { # assert_log <name> <file> <expected content>
  local name=$1 file=$2 want=$3 got
  total=$((total+1))
  if [[ ! -f $file ]]; then
    failures=$((failures+1))
    echo "FAILED: $name (log not written: $file)"
    return 0
  fi
  got=$(cat "$file")
  if [[ $got == "$want" ]]; then echo "ok: $name"
  else
    failures=$((failures+1))
    echo "FAILED: $name (log='$got', want='$want')"
  fi
  return 0
}

assert_no_log() { # assert_no_log <name> <file>
  local name=$1 file=$2
  total=$((total+1))
  if [[ ! -e $file ]]; then echo "ok: $name"
  else
    failures=$((failures+1))
    echo "FAILED: $name (log should not exist, holds: $(cat "$file"))"
  fi
  return 0
}

assert_reaped() { # assert_reaped <name> <pidfile> — polls up to 10s for death
  local name=$1 file=$2 pid i=0
  total=$((total+1))
  if [[ ! -s $file ]]; then
    failures=$((failures+1))
    echo "FAILED: $name (the escapee never recorded its pid: $file)"
    return 0
  fi
  pid=$(cat "$file")
  while [[ $i -lt 20 ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      : > "$file"   # dead and accounted for: nothing left for the exit trap
      echo "ok: $name"
      return 0
    fi
    sleep 0.5
    i=$((i+1))
  done
  failures=$((failures+1))
  echo "FAILED: $name (pid $pid survived the watchdog)"
  return 0
}

case_run() { # case_run <name> <expected_exit> <dir> <PATH|-> <grep_pattern...>
  local name=$1 expected=$2 dir=$3 path=$4; shift 4
  local out rc p ok=1 start=$SECONDS
  # shellcheck disable=SC2086  # GATE_ENV is split on purpose
  # Prefer $BASH (the suite's own interpreter) over a bare 'bash' from PATH:
  # on the macOS CI job PATH can resolve to Homebrew bash, which defeats the
  # whole reason that job runs under /bin/bash 3.2.
  if [[ $path == - ]]; then out=$(env $GATE_ENV "${BASH:-bash}" "$GATE" "$dir" 2>&1); rc=$?
  else out=$(env PATH="$path" $GATE_ENV "${BASH:-bash}" "$GATE" "$dir" 2>&1); rc=$?; fi
  LAST_ELAPSED=$((SECONDS-start))
  GATE_ENV=""
  [[ $rc -eq $expected ]] || ok=0
  # a pattern starting with '!' asserts absence (a command that must NOT run)
  for p in "$@"; do
    case $p in
      '!'*) if grep -q "${p#!}" <<<"$out"; then ok=0; fi ;;
      *)    grep -q "$p" <<<"$out" || ok=0 ;;
    esac
  done
  total=$((total+1))
  if [[ $ok -eq 1 ]]; then echo "ok: $name"
  else
    failures=$((failures+1))
    echo "FAILED: $name (exit=$rc, expected=$expected)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# skipped <name> <reason> — a case the environment cannot run, counted anyway.
# The total is not cosmetic: coherence_test.sh section 9 checks it against the
# number the READMEs publish, so a case that silently vanishes on one runner
# turns the docs into a lie there. The macOS runner ships no GNU timeout, so
# the -k cases below only ever execute on Linux; counting the skip keeps one
# number true on both, and the reason is printed so nobody reads it as a pass.
skipped() {
  total=$((total+1))
  echo "ok: $1 (skipped: $2)"
}

elapsed_lt() { # elapsed_lt <name> <seconds> — asserts on the last case_run
  local name=$1 limit=$2
  total=$((total+1))
  if [[ $LAST_ELAPSED -lt $limit ]]; then echo "ok: $name (${LAST_ELAPSED}s)"
  else
    failures=$((failures+1))
    echo "FAILED: $name (elapsed=${LAST_ELAPSED}s, limit=${limit}s)"
  fi
}

# fixtures -------------------------------------------------------------
mkdir -p "$TMP/empty"

mkdir -p "$TMP/js-green"
cat > "$TMP/js-green/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 0"}}
EOF

mkdir -p "$TMP/js-test-only"
cat > "$TMP/js-test-only/package.json" <<'EOF'
{"name":"f","scripts":{"test":"node -e 0"}}
EOF

mkdir -p "$TMP/js-red"
cat > "$TMP/js-red/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 'process.exit(1)'"}}
EOF

mkdir -p "$TMP/js-bad-json"
printf '{"name":"f",\n' > "$TMP/js-bad-json/package.json"

# Alias fixtures: a project that names its scripts 'type-check'/'test:unit' has
# the same safety net as one that spells them canonically, and must reach the
# same verdict — with checks= still using the canonical words.
mkdir -p "$TMP/js-alias"
cat > "$TMP/js-alias/package.json" <<'EOF'
{"name":"f","scripts":{"type-check":"node -e 0","test:unit":"node -e 0"}}
EOF

mkdir -p "$TMP/js-alias-test-only"
cat > "$TMP/js-alias-test-only/package.json" <<'EOF'
{"name":"f","scripts":{"test:unit":"node -e 0"}}
EOF

# 'tsc' as a script name usually means an emitting compile, so it is not an
# alias: a project whose only typecheck-ish script is 'tsc' gets no typecheck.
mkdir -p "$TMP/js-alias-tsc"
cat > "$TMP/js-alias-tsc/package.json" <<'EOF'
{"name":"f","scripts":{"tsc":"node -e \"console.log('TSC_RAN')\"","test":"node -e 0"}}
EOF

# Exception: the value itself is a check with --noEmit as a real shell word.
# The script name is still 'tsc', but the body is safe to run and must count
# as typecheck. A real tsc binary is not required — node exits 0 and ignores
# the extra argv after `--`.
mkdir -p "$TMP/js-tsc-noemit"
cat > "$TMP/js-tsc-noemit/package.json" <<'EOF'
{"name":"f","scripts":{"tsc":"node -e 0 -- --noEmit","test":"node -e 0"}}
EOF

# Emitting form stays rejected even when the command looks like a real tsc.
mkdir -p "$TMP/js-tsc-emit"
cat > "$TMP/js-tsc-emit/package.json" <<'EOF'
{"name":"f","scripts":{"tsc":"tsc -p .","test":"node -e 0"}}
EOF

# A comment mentioning --noEmit must NOT promote an emitting compile.
mkdir -p "$TMP/js-tsc-comment-noemit"
cat > "$TMP/js-tsc-comment-noemit/package.json" <<'EOF'
{"name":"f","scripts":{"tsc":"tsc -p . # use --noEmit in CI","test":"node -e 0"}}
EOF

# npm init's placeholder test script exits 1 on purpose — that is YELLOW with a
# named cap, not RED (a broken suite). The value is the literal npm writes.
mkdir -p "$TMP/js-npm-placeholder"
cat > "$TMP/js-npm-placeholder/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"echo \"Error: no test specified\" && exit 1"}}
EOF

# Runner reports an empty suite (vitest/jest shape) and exits 1: YELLOW cap,
# not RED. Covers plain 'test' and a lone 'test:*' alias.
mkdir -p "$TMP/js-empty-suite"
cat > "$TMP/js-empty-suite/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.error('No test files found'); process.exit(1)\""}}
EOF

mkdir -p "$TMP/js-empty-suite-slice"
cat > "$TMP/js-empty-suite-slice/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:unit":"node -e \"console.error('No test files found'); process.exit(1)\""}}
EOF

# Failing suite whose log only mentions the empty-suite phrase mid-line must
# stay RED — never flip to YELLOW/uncounted.
mkdir -p "$TMP/js-empty-suite-incidental"
cat > "$TMP/js-empty-suite-incidental/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.error('FAIL tests/foo.spec.js'); console.error('AssertionError: expected true'); console.error('hint: No tests found was unexpected'); process.exit(1)\""}}
EOF

# Chained script: empty-suite line first, then a later failure without the
# assertion blacklist tokens. Must stay RED (exit 2 ≠ runner empty-suite).
mkdir -p "$TMP/js-empty-suite-chained"
cat > "$TMP/js-empty-suite-chained/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.error('No test files found'); console.error('configuration crashed'); process.exit(2)\""}}
EOF

# Same shape with exit 1: the post-empty line still proves a chained failure.
mkdir -p "$TMP/js-empty-suite-chained-exit1"
cat > "$TMP/js-empty-suite-chained-exit1/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.error('No test files found'); console.error('configuration crashed'); process.exit(1)\""}}
EOF

# The two runners the docs name, byte for byte. Both print the exit code inside
# the empty-suite line and then keep explaining themselves — vitest lists its
# include/exclude globs, jest prints how many files it checked and every
# pattern it tried. Read as a chained failure, that tail sent every real vitest
# and jest repo without a test file to RED while the docs promised YELLOW. The
# older fixtures above all emit a single line, which is why the guard could be
# wrong here and green there.
mkdir -p "$TMP/js-empty-vitest-real"
cat > "$TMP/js-empty-vitest-real/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log(' RUN  v3.2.7 ' + process.cwd()); console.log('No test files found, exiting with code 1'); console.log(''); console.log('include: **/*.{test,spec}.?(c|m)[jt]s?(x)'); console.log('exclude:  **/node_modules/**, **/dist/**'); process.exit(1)\""}}
EOF

mkdir -p "$TMP/js-empty-jest-real"
cat > "$TMP/js-empty-jest-real/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('No tests found, exiting with code 1'); console.log('Run with --passWithNoTests to exit with code 0'); console.log('In ' + process.cwd()); console.log('  2 files checked.'); console.log('  testMatch: **/__tests__/**/*.[jt]s?(x) - 0 matches'); console.log('  testPathIgnorePatterns: /node_modules/ - 2 matches'); process.exit(1)\""}}
EOF

# The inline code accounts for the process's exit, not for whatever else ran.
# A build that failed after the empty suite prints an error and still has to
# sink the run to RED — otherwise the tail-is-diagnosis rule would be a way of
# laundering any chained failure that exits 1.
mkdir -p "$TMP/js-empty-inline-then-error"
cat > "$TMP/js-empty-inline-then-error/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('No test files found, exiting with code 1'); console.log('error TS2304: Cannot find name foo.'); process.exit(1)\""}}
EOF

# --passWithNoTests: the runner is told to make an empty suite a success, so it
# exits 0 having run nothing. The empty-suite detection used to sit inside the
# non-zero branch only, so this reached GREEN — the level that unlocks
# dead-export deletion — over a repo where no test ever ran.
mkdir -p "$TMP/js-pwnt"
cat > "$TMP/js-pwnt/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('No tests found, exiting with code 0')\""}}
EOF

# node:test on an empty run: exit 0 and a count, none of the phrases the other
# runners print. Both reporters are covered — the default one's marker is
# multibyte, which a greedy negated class skips under a UTF-8 locale.
mkdir -p "$TMP/js-node-test-empty"
cat > "$TMP/js-node-test-empty/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('\\u2139 tests 0'); console.log('\\u2139 pass 0')\""}}
EOF

mkdir -p "$TMP/js-node-test-tap"
cat > "$TMP/js-node-test-tap/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('TAP version 13'); console.log('1..0'); console.log('# tests 0')\""}}
EOF

# Counts that must NOT cap: a real node:test run, and a two-digit total.
mkdir -p "$TMP/js-node-test-real"
cat > "$TMP/js-node-test-real/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('\\u2139 tests 10'); console.log('\\u2139 pass 10')\""}}
EOF

# The counterpart that must stay GREEN: a real suite reporting real passes.
# Without this, capping on exit 0 could silently swallow every healthy repo.
mkdir -p "$TMP/js-real-pass"
cat > "$TMP/js-real-pass/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('Test Files 3 passed (3)'); console.log('Tests 12 passed (12)')\""}}
EOF

# ANSI. Every runner above colours its output the moment it believes it is
# talking to a terminal, and a repo can force that from package.json
# ('vitest --color', FORCE_COLOR in a .npmrc/CI shim) with no tty in sight.
# The classification regexes are anchored — '^' on the empty-suite phrases,
# '$' on the node:test count — so a leading '\033[33m' or a trailing reset
# pushes the text out from under the anchor and the detector goes silent. The
# failure is one-sided and unsafe: an uncounted suite is read as a counted one,
# i.e. a repo where zero tests ran reports GREEN, the level that unlocks
# autonomous dead-export deletion. The stubs emit the escape bytes themselves
# rather than trusting a runner to decide to colour, so the case holds whatever
# the machine's tty and locale do.
mkdir -p "$TMP/js-pwnt-color"
cat > "$TMP/js-pwnt-color/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('\\u001b[33mNo test files found, exiting with code 0\\u001b[39m')\""}}
EOF

# node:test's default reporter, coloured: the reset lands after the count, so
# the '$' anchor on 'tests 0' never matches. Marker still multibyte on purpose
# — colour and the UTF-8 marker are the shape the built-in runner really emits.
mkdir -p "$TMP/js-node-test-empty-color"
cat > "$TMP/js-node-test-empty-color/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('\\u001b[34m\\u2139 tests 0\\u001b[39m'); console.log('\\u001b[34m\\u2139 pass 0\\u001b[39m')\""}}
EOF

# Mixed colouring is the dangerous half, and it is not hypothetical: vitest
# prints its empty-suite notice through a plain logger and its failure banner
# through a coloured one. The empty-suite phrase still matches, so the cap
# fires, while the chained-failure guard — anchored at '^' or a space before
# FAIL — is blind to '\033[31mFAIL\033[39m' because the character before FAIL
# is 'm'. A suite that actually failed is then laundered into YELLOW/uncounted
# instead of RED. Exit 1 with a real failing file must stay RED.
mkdir -p "$TMP/js-empty-mixed-color"
cat > "$TMP/js-empty-mixed-color/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('No test files found, exiting with code 1'); console.log('\\u001b[31mFAIL\\u001b[39m src/a.test.ts'); process.exit(1)\""}}
EOF

# The same laundering under a different escape, and the one that proves the
# normalisation had to cover more than colour. A runner that makes a failing
# path clickable wraps it in an OSC 8 hyperlink, so the byte before FAIL is the
# BEL that closes `ESC]8;;file://…` — the failure guard is anchored on
# `(^|[[:space:]])` and goes blind exactly as it did under SGR. Unlike a
# terminal-title OSC this one does not need a TTY, only the env that turns
# hyperlinks on, which is the same class of env that turned colour on here.
mkdir -p "$TMP/js-empty-osc-hyperlink"
cat > "$TMP/js-empty-osc-hyperlink/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.log('No test files found, exiting with code 1'); console.log('\\u001b]8;;file:///a.test.ts\\u0007\\u001b[31mFAIL\\u001b[39m\\u001b]8;;\\u0007 src/a.test.ts'); process.exit(1)\""}}
EOF

# The gate observes, it does not repaint: normalisation exists to classify, so
# the bytes the user sees must still carry their colour. This case asserts the
# raw escape survives into the gate's own output — a fix that stripped colour
# on the way through would pass every classification case above and quietly
# degrade every coloured run.
mkdir -p "$TMP/js-color-passthrough"
cp "$TMP/js-pwnt-color/package.json" "$TMP/js-color-passthrough/package.json"

# Same chained failure, lowercase runner line. The guard used to lean on awk's
# IGNORECASE — a gawk extension that BSD awk and mawk ignore, i.e. both CI legs
# — so only the exact casing of the fixtures above was ever caught and this
# shape slipped through as YELLOW.
mkdir -p "$TMP/js-empty-suite-chained-lower"
cat > "$TMP/js-empty-suite-chained-lower/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e \"console.error('no test files found'); console.error('configuration crashed'); process.exit(1)\""}}
EOF

mkdir -p "$TMP/js-alias-check-types"
cat > "$TMP/js-alias-check-types/package.json" <<'EOF'
{"name":"f","scripts":{"check-types":"node -e 0","test":"node -e 0"}}
EOF

# Plain 'test' next to a slice: 'test' wins and the slice stays silent.
mkdir -p "$TMP/js-test-and-unit"
cat > "$TMP/js-test-and-unit/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 0","test:unit":"node -e \"console.log('ALIAS_TEST_RAN')\""}}
EOF

# Two slices and no whole: neither stands for the suite, so 'test' is not
# counted and the verdict falls back to the YELLOW cap.
mkdir -p "$TMP/js-test-slices"
cat > "$TMP/js-test-slices/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:unit":"node -e \"console.log('UNIT_RAN')\"","test:e2e":"node -e \"console.log('E2E_RAN')\""}}
EOF

# ...and with the slices as the only scripts at all, nothing countable ran.
mkdir -p "$TMP/js-test-slices-only"
cat > "$TMP/js-test-slices-only/package.json" <<'EOF'
{"name":"f","scripts":{"test:unit":"node -e 0","test:e2e":"node -e 0"}}
EOF

# A single slice that is not 'test:unit': the rule is about test:*, not about
# one blessed name.
mkdir -p "$TMP/js-test-integration"
cat > "$TMP/js-test-integration/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:integration":"node -e 0"}}
EOF

# A lone watch slice is not a suite: it never exits, so promoting it would end
# at the watchdog — GATE_TIMEOUT seconds of stall for an inconclusive exit 4 on
# a repo that has a perfectly good gate otherwise. The script here really does
# hang, so the case proves the gate never starts it: it has to come back fast,
# exit 0, and explain the cap.
mkdir -p "$TMP/js-test-watch"
cat > "$TMP/js-test-watch/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:watch":"node -e \"setInterval(function(){},1000)\""}}
EOF

# ...and the mode word is a segment of the name, not a suffix of it: 'test:watch:all'
# hangs exactly as hard as 'test:watch'. Anchoring the exclusion at the end of the
# name let this one through and cost a full GATE_TIMEOUT before exit 4.
mkdir -p "$TMP/js-test-watch-nested"
cat > "$TMP/js-test-watch-nested/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:watch:all":"node -e \"setInterval(function(){},1000)\""}}
EOF

# A slice declared with an empty command still splits the suite. Counting only
# the non-empty ones turned two halves into a lone slice — and a lone slice is
# promoted to the whole suite, which is the GREEN this rule exists to deny.
mkdir -p "$TMP/js-slice-empty"
cat > "$TMP/js-slice-empty/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:unit":"node -e \"console.log('UNIT_RAN')\"","test:e2e":""}}
EOF

# A manifest with a typecheck script and no test script of any spelling: the
# plainest YELLOW cap there is, and the one that used to produce no explanation
# at all — the run ended at 'checks=typecheck' with nothing on stderr saying why
# the suite was missing, while every other stack said so.
mkdir -p "$TMP/js-typecheck-only"
cat > "$TMP/js-typecheck-only/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","build":"node -e 0"}}
EOF

# Polyglot: the JS suite is sliced and never runs, Go's does. checks= then reads
# typecheck,test from Go alone, and announcing GREEN off that would unlock
# dead-export deletion over the JS half that nothing tested.
mkdir -p "$TMP/js-poly-uncounted"
cat > "$TMP/js-poly-uncounted/package.json" <<'EOF'
{"name":"f","scripts":{"test:unit":"node -e 0","test:e2e":"node -e 0"}}
EOF
printf 'module f\n\ngo 1.21\n' > "$TMP/js-poly-uncounted/go.mod"
printf 'package f\n' > "$TMP/js-poly-uncounted/x_test.go"

# 'ui' is excluded from *running* like 'watch' and 'debug', but not from the
# count: 'vitest --ui' never exits, yet 'test:ui' is just as often a scope of
# its own. Counting it as a mode turned this manifest into a lone slice and
# announced GREEN with the UI half never run.
mkdir -p "$TMP/js-test-ui"
cat > "$TMP/js-test-ui/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:unit":"node -e \"console.log('UNIT_RAN')\"","test:ui":"node -e \"console.log('UI_RAN')\""}}
EOF

# ...and a lone 'test:ui' is neither run nor called watch mode: the gate declines
# it because it cannot tell whether it exits, and says so.
mkdir -p "$TMP/js-test-ui-only"
cat > "$TMP/js-test-ui-only/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:ui":"node -e \"console.log('UI_RAN')\""}}
EOF

# ...while a watch slice beside a lone real one is still just a mode of it, so
# the real slice is promoted and the watch one is neither run nor counted.
mkdir -p "$TMP/js-test-unit-watch"
cat > "$TMP/js-test-unit-watch/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test:unit":"node -e 0","test:watch":"node -e \"setInterval(function(){},1000)\""}}
EOF

# Canonical and alias side by side: precedence says 'typecheck' wins and
# 'type-check' never runs. The alias prints a marker so its silence is provable.
mkdir -p "$TMP/js-alias-both"
cat > "$TMP/js-alias-both/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","type-check":"node -e \"console.log('ALIAS_TYPECHECK_RAN')\"","test":"node -e 0"}}
EOF

mkdir -p "$TMP/js-alias-red"
cat > "$TMP/js-alias-red/package.json" <<'EOF'
{"name":"f","scripts":{"type-check":"node -e 0","test:unit":"node -e 'process.exit(1)'"}}
EOF

# yarn.lock picks the 'yarn <script>' invocation instead of '<pm> run <script>';
# no fixture exercised that branch before, alias or not. The manifest is copied
# from js-alias on purpose: the lockfile is the only difference the case is
# about, and a second hand-written copy would let the two drift apart.
mkdir -p "$TMP/js-yarn-alias"
cp "$TMP/js-alias/package.json" "$TMP/js-yarn-alias/package.json"
touch "$TMP/js-yarn-alias/yarn.lock"

# Lockfile picks pnpm / bun the same way yarn.lock picks yarn.
mkdir -p "$TMP/js-pnpm"
cp "$TMP/js-green/package.json" "$TMP/js-pnpm/package.json"
touch "$TMP/js-pnpm/pnpm-lock.yaml"

mkdir -p "$TMP/js-bun"
cp "$TMP/js-green/package.json" "$TMP/js-bun/package.json"
touch "$TMP/js-bun/bun.lock"

# The empty-suite cap has to survive the package manager's own epilogue. Every
# manager but npm prints a line after the runner's message — pnpm 'ELIFECYCLE
# Command failed', yarn 'error Command failed with exit code 1.', bun 'error:
# script "test" exited with code 1' — all of them non-empty and carrying
# "failed", which read as a real failure and sank an empty suite to RED. One
# fixture per manager, distinguished only by the lockfile.
for pm in pnpm yarn bun; do
  mkdir -p "$TMP/js-empty-$pm"
  cp "$TMP/js-empty-suite/package.json" "$TMP/js-empty-$pm/package.json"
done
touch "$TMP/js-empty-pnpm/pnpm-lock.yaml" "$TMP/js-empty-yarn/yarn.lock" \
      "$TMP/js-empty-bun/bun.lock"

mkdir -p "$TMP/polyglot/tests"
touch "$TMP/polyglot/pyproject.toml" "$TMP/polyglot/tests/test_x.py"
printf 'module f\n\ngo 1.21\n' > "$TMP/polyglot/go.mod"

mkdir -p "$TMP/dotnet-root" "$TMP/dotnet-sub/src/App"
TESTPROJ='<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>'
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-root/App.csproj"
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-sub/src/App/App.fsproj"

# One solution next to a project of a different base name: the gate has to name
# the solution, or the real 'dotnet build' fails with MSB1011.
mkdir -p "$TMP/dotnet-sln"
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-sln/App.csproj"
printf 'Microsoft Visual Studio Solution File\n' > "$TMP/dotnet-sln/MyApp.sln"

# Two solutions is a choice the gate does not get to make: it abstains and
# calls dotnet with no argument, exactly as before.
mkdir -p "$TMP/dotnet-two-slns"
printf 'Microsoft Visual Studio Solution File\n' > "$TMP/dotnet-two-slns/A.sln"
printf 'Microsoft Visual Studio Solution File\n' > "$TMP/dotnet-two-slns/B.sln"

# The test project is nested deeper than the old three fixed globs reached.
mkdir -p "$TMP/dotnet-deep/src/App/Tests"
printf '<Project></Project>\n' > "$TMP/dotnet-deep/App.csproj"
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-deep/src/App/Tests/Tests.csproj"

# A marker under bin/ is build output, not the repo's suite.
mkdir -p "$TMP/dotnet-prune-bin/bin/Debug"
printf '<Project></Project>\n' > "$TMP/dotnet-prune-bin/App.csproj"
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-prune-bin/bin/Debug/Leftover.csproj"

mkdir -p "$TMP/dotnet-no-tests" "$TMP/dotnet-sub-no-tests/src/App"
printf '<Project></Project>\n' > "$TMP/dotnet-no-tests/App.csproj"
printf '<Project></Project>\n' > "$TMP/dotnet-sub-no-tests/src/App/App.fsproj"

# The standard layout is the JVM's evidence of a suite: 'mvn test' and 'gradle
# test' exit 0 on a project with no test source, and 'run both' has counted
# 'test' by then. The hybrid fixture carries src/test so it is a real green.
mkdir -p "$TMP/jvm-hybrid/src/test/java"
touch "$TMP/jvm-hybrid/pom.xml" "$TMP/jvm-hybrid/build.gradle"

# ...and the same repo without it is the cap: the build still runs, the verdict
# refuses GREEN. Two modules deep, because a multi-module repo has no src/test
# at the root and the scan has to reach the ones that do.
mkdir -p "$TMP/jvm-no-tests"
touch "$TMP/jvm-no-tests/pom.xml"

mkdir -p "$TMP/jvm-module-tests/mod-a/src/test/java" "$TMP/jvm-module-tests/mod-b/src/main/java"
touch "$TMP/jvm-module-tests/pom.xml"

# Wrapper scripts win over a missing system mvn/gradle.
mkdir -p "$TMP/jvm-mvnw/src/test/java"
touch "$TMP/jvm-mvnw/pom.xml"
stub "$TMP/jvm-mvnw" mvnw 0

mkdir -p "$TMP/jvm-gradlew/src/test/java"
touch "$TMP/jvm-gradlew/build.gradle"
stub "$TMP/jvm-gradlew" gradlew 0

# Polyglot: JS supplies typecheck+test, the .NET half has no test project in any
# of its projects. Announcing GREEN off the JS suite would unlock dead-export
# deletion over C# that nothing tested — the same hole js-poly-uncounted covers
# for the JS side, on the per-project .NET path that used to skip the flag.
mkdir -p "$TMP/dotnet-poly-uncounted/src/App"
cat > "$TMP/dotnet-poly-uncounted/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 0"}}
EOF
printf '<Project></Project>\n' > "$TMP/dotnet-poly-uncounted/src/App/App.csproj"

# A bare requirements.txt (docs build, a pre-commit pin) is the loosest stack
# marker gate.sh has. Capping on it alone pinned an otherwise green repo below
# GREEN forever, for a Python "stack" that is one pip file and no Python.
mkdir -p "$TMP/py-reqs-no-source"
cat > "$TMP/py-reqs-no-source/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 0"}}
EOF
printf 'mkdocs\n' > "$TMP/py-reqs-no-source/requirements.txt"

# ...and with actual Python next to it the cap is right and still fires.
mkdir -p "$TMP/py-reqs-with-source"
cp "$TMP/py-reqs-no-source/package.json" "$TMP/py-reqs-with-source/package.json"
printf 'mkdocs\n' > "$TMP/py-reqs-with-source/requirements.txt"
printf 'def f():\n    pass\n' > "$TMP/py-reqs-with-source/tool.py"

# Same rule for Ruby: a Gemfile carrying only fastlane/Jekyll is not a Ruby
# stack without a suite, it is not a Ruby stack.
mkdir -p "$TMP/rb-gemfile-only"
cp "$TMP/py-reqs-no-source/package.json" "$TMP/rb-gemfile-only/package.json"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-gemfile-only/Gemfile"

mkdir -p "$TMP/rb-source-no-spec"
cp "$TMP/py-reqs-no-source/package.json" "$TMP/rb-source-no-spec/package.json"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-source-no-spec/Gemfile"
printf 'def f; end\n' > "$TMP/rb-source-no-spec/tool.rb"

# Ruby with sorbet + rspec: both typecheck and test must run (the GREEN path
# that used to have zero coverage).
mkdir -p "$TMP/rb-sorbet-rspec/spec" "$TMP/rb-sorbet-rspec/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-sorbet-rspec/Gemfile"
touch "$TMP/rb-sorbet-rspec/sorbet/config"
printf 'RSpec.describe "x" do; end\n' > "$TMP/rb-sorbet-rspec/spec/x_spec.rb"

# Ruby with rake test only (no spec/).
mkdir -p "$TMP/rb-rake/test"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-rake/Gemfile"
touch "$TMP/rb-rake/Rakefile"
printf 'class XTest; end\n' > "$TMP/rb-rake/test/x_test.rb"

# Both runners present: neither alone is the whole suite → YELLOW, run neither.
# sorbet is present so typecheck still runs and the cap is visible as YELLOW
# (without it the gate would exit 3 with nothing runnable).
mkdir -p "$TMP/rb-both-runners/spec" "$TMP/rb-both-runners/test" "$TMP/rb-both-runners/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-both-runners/Gemfile"
touch "$TMP/rb-both-runners/Rakefile" "$TMP/rb-both-runners/sorbet/config"
printf 'RSpec.describe "x" do; end\n' > "$TMP/rb-both-runners/spec/x_spec.rb"
printf 'class XTest; end\n' > "$TMP/rb-both-runners/test/x_test.rb"

# A spec/ holding no *_spec.rb is not a suite: rspec exits 0 on "0 examples",
# so judging by the directory alone announced GREEN for a repo with zero tests
# — the same trap go/cargo already guard against. Same for a rake test/ with
# no *_test.rb. sorbet is present so typecheck still runs and the cap shows as
# YELLOW instead of exit 3 with nothing runnable.
mkdir -p "$TMP/rb-spec-empty/spec" "$TMP/rb-spec-empty/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-spec-empty/Gemfile"
touch "$TMP/rb-spec-empty/sorbet/config"
printf '# support file, not a spec\n' > "$TMP/rb-spec-empty/spec/spec_helper.rb"

mkdir -p "$TMP/rb-test-empty/test" "$TMP/rb-test-empty/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-test-empty/Gemfile"
touch "$TMP/rb-test-empty/Rakefile" "$TMP/rb-test-empty/sorbet/config"
printf '# support file, not a test\n' > "$TMP/rb-test-empty/test/helper.rb"

# `test/test*.rb` is the DEFAULT pattern of Rake::TestTask, so this naming is
# the common one, not the exotic one. Recognising only the `*_test.rb` suffix
# dropped the both-runners cap here and announced GREEN with the rake half
# never measured.
mkdir -p "$TMP/rb-both-prefix/spec" "$TMP/rb-both-prefix/test" "$TMP/rb-both-prefix/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-both-prefix/Gemfile"
touch "$TMP/rb-both-prefix/Rakefile" "$TMP/rb-both-prefix/sorbet/config"
printf 'RSpec.describe "x" do; end\n' > "$TMP/rb-both-prefix/spec/x_spec.rb"
printf 'class TestX; end\n' > "$TMP/rb-both-prefix/test/test_x.rb"

# Rake-only repo using the same default naming: a real suite, so it runs.
mkdir -p "$TMP/rb-rake-prefix/test"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-rake-prefix/Gemfile"
touch "$TMP/rb-rake-prefix/Rakefile"
printf 'class TestX; end\n' > "$TMP/rb-rake-prefix/test/test_x.rb"

# test_helper.rb matches the prefix pattern but is support code, not a suite.
mkdir -p "$TMP/rb-helper-only/test" "$TMP/rb-helper-only/sorbet"
printf "source 'https://rubygems.org'\n" > "$TMP/rb-helper-only/Gemfile"
touch "$TMP/rb-helper-only/Rakefile" "$TMP/rb-helper-only/sorbet/config"
printf 'require "minitest"\n' > "$TMP/rb-helper-only/test/test_helper.rb"

mkdir -p "$TMP/py-setupcfg/test"
printf '[mypy]\n' > "$TMP/py-setupcfg/setup.cfg"
touch "$TMP/py-setupcfg/test/test_x.py"

mkdir -p "$TMP/py-venv/tests" "$TMP/py-venv/.venv/bin"
printf '[tool.mypy]\n' > "$TMP/py-venv/pyproject.toml"
touch "$TMP/py-venv/tests/test_x.py"
stub "$TMP/py-venv/.venv/bin" mypy 0
stub "$TMP/py-venv/.venv/bin" pytest 0

# Plain venv/bin (not .venv) and an active VIRTUAL_ENV are the other two
# resolution prefixes py_cmd promises.
mkdir -p "$TMP/py-venv-plain/tests" "$TMP/py-venv-plain/venv/bin"
printf '[tool.mypy]\n' > "$TMP/py-venv-plain/pyproject.toml"
touch "$TMP/py-venv-plain/tests/test_x.py"
stub "$TMP/py-venv-plain/venv/bin" mypy 0
stub "$TMP/py-venv-plain/venv/bin" pytest 0

mkdir -p "$TMP/py-virtualenv/tests" "$TMP/py-virtualenv-prefix/bin"
printf '[tool.mypy]\n' > "$TMP/py-virtualenv/pyproject.toml"
touch "$TMP/py-virtualenv/tests/test_x.py"
stub "$TMP/py-virtualenv-prefix/bin" mypy 0
stub "$TMP/py-virtualenv-prefix/bin" pytest 0

mkdir -p "$TMP/py-poetry/tests"
printf '[tool.mypy]\n' > "$TMP/py-poetry/pyproject.toml"
touch "$TMP/py-poetry/poetry.lock" "$TMP/py-poetry/tests/test_x.py"

mkdir -p "$TMP/py-no-tools/tests"
printf '[tool.mypy]\n' > "$TMP/py-no-tools/pyproject.toml"
touch "$TMP/py-no-tools/tests/test_x.py"

mkdir -p "$TMP/py-uv/tests"
printf '[project]\nname = "f"\n' > "$TMP/py-uv/pyproject.toml"
touch "$TMP/py-uv/uv.lock" "$TMP/py-uv/tests/test_x.py"

# pytest exits 5 when it collects no test: green-but-empty, not a pass.
mkdir -p "$TMP/py-pytest-no-tests/tests"
printf '[tool.mypy]\n[tool.pytest.ini_options]\n' > "$TMP/py-pytest-no-tests/pyproject.toml"

# ...and with pytest as the only configured check, nothing at all ran.
mkdir -p "$TMP/py-pytest-only-no-tests"
printf '[tool.pytest.ini_options]\n' > "$TMP/py-pytest-only-no-tests/pyproject.toml"

mkdir -p "$TMP/py-pyright"
printf '[tool.pyright]\n' > "$TMP/py-pyright/pyproject.toml"

mkdir -p "$TMP/go-only"
printf 'module f\n\ngo 1.21\n' > "$TMP/go-only/go.mod"

mkdir -p "$TMP/go-with-tests"
printf 'module f\n\ngo 1.21\n' > "$TMP/go-with-tests/go.mod"
printf 'package f\n' > "$TMP/go-with-tests/x_test.go"

mkdir -p "$TMP/go-no-tests/vendor/dep"
printf 'module f\n\ngo 1.21\n' > "$TMP/go-no-tests/go.mod"
printf 'package dep\n' > "$TMP/go-no-tests/vendor/dep/vendored_test.go"

# Rust: evidence is a #[test] in the sources or a file under tests/.
mkdir -p "$TMP/rust-with-tests/src"
printf '[package]\nname = "f"\n' > "$TMP/rust-with-tests/Cargo.toml"
printf 'pub fn f() {}\n\n#[test]\nfn t() {}\n' > "$TMP/rust-with-tests/src/lib.rs"

mkdir -p "$TMP/rust-tests-dir/src" "$TMP/rust-tests-dir/tests"
printf '[package]\nname = "f"\n' > "$TMP/rust-tests-dir/Cargo.toml"
printf 'pub fn f() {}\n' > "$TMP/rust-tests-dir/src/lib.rs"
printf 'fn it() {}\n' > "$TMP/rust-tests-dir/tests/it.rs"

# target/ is build output: a test attribute in there is not the crate's suite.
mkdir -p "$TMP/rust-no-tests/src" "$TMP/rust-no-tests/target/debug/tests"
printf '[package]\nname = "f"\n' > "$TMP/rust-no-tests/Cargo.toml"
printf 'fn main() {}\n' > "$TMP/rust-no-tests/src/main.rs"
printf '#[test]\nfn t() {}\n' > "$TMP/rust-no-tests/target/debug/tests/dep.rs"

# Vendored dependencies carry their own tests; they are not this crate's suite.
mkdir -p "$TMP/rust-vendor/src" "$TMP/rust-vendor/vendor/dep/tests"
printf '[package]\nname = "f"\n' > "$TMP/rust-vendor/Cargo.toml"
printf 'fn main() {}\n' > "$TMP/rust-vendor/src/main.rs"
printf '#[test]\nfn t() {}\n' > "$TMP/rust-vendor/vendor/dep/tests/it.rs"

mkdir -p "$TMP/go-hang"
printf 'module f\n\ngo 1.21\n' > "$TMP/go-hang/go.mod"
printf 'package f\n' > "$TMP/go-hang/x_test.go"

# stubs ----------------------------------------------------------------
OK="$TMP/stubs-ok"; FAIL="$TMP/stubs-fail"; HANG="$TMP/stubs-hang"; UV="$TMP/stubs-uv"
for t in pytest mypy pyright dotnet mvn gradle bundle; do stub "$OK" "$t" 0; done
stub "$FAIL" dotnet 1
stub_body "$HANG" go 'sleep 30'
# Ignores TERM, so the watchdog's -k escalation has to finish it with KILL and
# the shell reports 137, not 124. Used against the *real* timeout, not a
# logging stub: the passthrough case below only proves the flag is forwarded,
# never that the resulting exit code is read as a timeout.
IGNTERM="$TMP/stubs-ignterm"
stub_body "$IGNTERM" go 'trap "" TERM
sleep 30'
# The real timeout has to be reachable from the case's PATH, or the gate falls
# back to the perl backend, which raises 124 by hand and never exercises the
# -k/137 path this fixture exists to cover. On macOS GNU timeout lives outside
# /usr/bin, so $BASE alone is not enough.
link_bin "$IGNTERM" timeout sleep
stub "$UV" uv 0
GO="$TMP/stubs-go"; stub "$GO" go 0
# yarn is not on every machine, and the branch under test is only *how* the
# gate invokes it: a stub that always succeeds is enough, since the invocation
# itself is echoed by run(). The dir is prepended to the real PATH rather than
# replacing it, so the case runs node and the same watchdog backend as every
# other JS case — a hand-built minimal PATH would silently drop timeout and
# make this the one JS case gated by perl.
YARN="$TMP/stubs-yarn"
stub "$YARN" yarn 0
PNPM="$TMP/stubs-pnpm"
stub "$PNPM" pnpm 0
BUN="$TMP/stubs-bun"
stub "$BUN" bun 0
# Empty-suite stubs: typecheck succeeds, the test script prints the runner's
# empty-suite line and then the manager's own epilogue, exiting 1 — the exact
# shape each manager produces on a repo with no test files.
# pnpm v10/v11 — the shape a current pnpm actually prints, verified against
# pnpm 11.18.0. Writing only the v9 line here would have let the filter look
# covered while being inert on every supported pnpm.
EMPTY_PNPM="$TMP/stubs-empty-pnpm"
stub_body "$EMPTY_PNPM" pnpm 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
echo "[ELIFECYCLE] Test failed. See above for more details."
exit 1'
# pnpm v9 and older, still in the wild on pinned CI images.
EMPTY_PNPM9="$TMP/stubs-empty-pnpm9"
stub_body "$EMPTY_PNPM9" pnpm 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
echo " ELIFECYCLE  Command failed with exit code 1."
exit 1'
EMPTY_YARN="$TMP/stubs-empty-yarn"
stub_body "$EMPTY_YARN" yarn 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
echo "error Command failed with exit code 1."
echo "info Visit https://yarnpkg.com/en/docs/cli/run for documentation."
exit 1'
EMPTY_BUN="$TMP/stubs-empty-bun"
stub_body "$EMPTY_BUN" bun 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
echo "error: script \"test\" exited with code 1"
exit 1'
# npm's epilogue, coloured. The epilogue filter is anchored at '^[[:space:]]*'
# and the 'npm ERR!' alternative has no wildcard prefix, so '\033[31mnpm ERR!'
# is not stripped; it survives into $ev, and the chained-failure guard then
# reads its own ERR! as proof a second command failed. An empty suite sinks to
# RED — the mirror image of the exit-0 leaks, and the reason the filter has to
# judge normalised text too.
EMPTY_NPM_COLOR="$TMP/stubs-empty-npm-color"
stub_body "$EMPTY_NPM_COLOR" npm 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
printf "\033[31mnpm ERR! Test failed.  See above for more details.\033[39m\n"
exit 1'
# The control: byte-for-byte the same run without the escapes. It passes today
# and has to keep passing — without it a "fix" that broke the epilogue filter
# outright would be indistinguishable from one that repaired it.
EMPTY_NPM_PLAIN="$TMP/stubs-empty-npm-plain"
stub_body "$EMPTY_NPM_PLAIN" npm 'for a in "$@"; do [ "$a" = typecheck ] && exit 0; done
echo "No test files found, exiting with code 1"
echo "npm ERR! Test failed.  See above for more details."
exit 1'
POETRY="$TMP/stubs-poetry"
stub "$POETRY" poetry 0
CARGO="$TMP/stubs-cargo"; stub "$CARGO" cargo 0
# pytest's "no tests collected" code, with a passing mypy next to it.
PY5="$TMP/stubs-py5"; stub "$PY5" pytest 5; stub "$PY5" mypy 0

# watchdog sandbox: delegators that record how gate.sh called them, plus a
# minimal PATH with no timeout/gtimeout so the perl backend can be forced.
WD_T="$TMP/wd-timeout"; WD_LOG_T="$TMP/wd-timeout.log"
WD_G="$TMP/wd-gtimeout"; WD_LOG_G="$TMP/wd-gtimeout.log"
stub_log "$WD_T" timeout "$WD_LOG_T" 124
stub_log "$WD_G" gtimeout "$WD_LOG_G" 124
WD_K="$TMP/wd-kill-after"; WD_LOG_K="$TMP/wd-kill-after.log"
stub_log_probe "$WD_K" timeout "$WD_LOG_K"
GO124="$TMP/stubs-go-124"; stub "$GO124" go 124
MINI="$TMP/mini-path"
link_bin "$MINI" bash sh perl ps find grep sleep

# Sandbox with the gate's own needs and ZERO stack toolchains. The PARTIAL
# and missing-toolchain cases must not depend on what the host happens to
# have in /usr/bin — a GitHub ubuntu runner ships go there, a laptop does not.
NOTOOL="$TMP/notool-path"
link_bin "$NOTOOL" bash sh env grep find xargs head perl ps sleep true

# The same sandbox without ps: the perl watchdog cannot map the process tree,
# so the sweep degrades to killing the group. The timeout itself must not.
NOPS="$TMP/nops-path"
link_bin "$NOPS" bash sh perl find grep sleep

reset_logs() { rm -f "$WD_LOG_T" "$WD_LOG_G" "$WD_LOG_K"; }

# A check whose grandchild calls setsid: it leaves the gate's process group, so
# 'kill -PGID' alone would leave it running past the timeout. It records its own
# pid and sleeps for a bounded time, never longer than the suite. Its output goes
# to /dev/null on purpose: holding the case's pipe open would make case_run wait
# for it, which hides the very leak this case is about.
make_escapee() { # make_escapee <dir> <pidfile>
  mkdir -p "$1"
  cat > "$1/go" <<EOF
#!/bin/sh
perl -e 'use POSIX; POSIX::setsid(); open(F, ">", "$2") or exit 1;
         print F \$\$; close F; sleep 60' >/dev/null 2>&1 &
sleep 45
EOF
  chmod +x "$1/go"
}

# The JS test path captures the runner's output, and that capture is the one
# place where a leaked process can stall the gate without any signal reaching
# it: a detached grandchild that inherited stdout holds the pipe open, so a
# reader waits for the grandchild, not the runner, with GATE_TIMEOUT long
# elapsed and the watchdog powerless — it kills what it launched, not a reader
# blocked on a pipe. Note this is the inverse of make_escapee above, which
# sends its output to /dev/null precisely to avoid the stall; here the
# inherited stdout *is* the case. npm exits 0 immediately; only the grandchild
# lingers, so anything slower than a couple of seconds means the gate waited.
JS_HOLD="$TMP/stubs-js-hold"
mkdir -p "$JS_HOLD"
cat > "$JS_HOLD/npm" <<EOF
#!/bin/sh
[ "\$1" = run ] && [ "\$2" = typecheck ] && exit 0
perl -e 'use POSIX; POSIX::setsid(); open(F, ">", "$TMP/escapee-jshold.pid") or exit 1;
         print F \$\$; close F; sleep 30' &
exit 0
EOF
chmod +x "$JS_HOLD/npm"
mkdir -p "$TMP/js-hold"
printf '%s\n' '{"name":"f","scripts":{"typecheck":"node -e 0","test":"leaks"}}' \
  > "$TMP/js-hold/package.json"

ESCAPE="$TMP/stubs-escape"
ESCAPEE_PID_FILE="$TMP/escapee.pid"
make_escapee "$ESCAPE" "$ESCAPEE_PID_FILE"

# The same check, for the sandbox without ps: its own pid file so the two
# escapees never share one and the exit trap can reap both.
ESCAPE_NOPS="$TMP/stubs-escape-nops"
make_escapee "$ESCAPE_NOPS" "$TMP/escapee-nops.pid"

# A ps that rejects lstart (BusyBox shape): delegates the plain pid=,ppid= form
# to the real ps and fails on anything mentioning lstart.
NOLS="$TMP/nols-path"
mkdir -p "$NOLS"
REAL_PS=$(command -v ps)
cat > "$NOLS/ps" <<EOF
#!/bin/sh
case "\$*" in *lstart*) exit 1 ;; esac
exec "$REAL_PS" "\$@"
EOF
chmod +x "$NOLS/ps"
ESCAPE_NOLS="$TMP/stubs-escape-nols"
make_escapee "$ESCAPE_NOLS" "$TMP/escapee-nols.pid"

# matrix ---------------------------------------------------------------
case_run bad-path         2 "$TMP/nope"         -             "bad path"
case_run empty            3 "$TMP/empty"        -             "no runnable checks"
case_run js-green         0 "$TMP/js-green"     -             "checks=typecheck,test" "GREEN"
case_run js-test-only     0 "$TMP/js-test-only" -             "checks=test" "YELLOW"
case_run js-red           1 "$TMP/js-red"       -             "RED"
case_run js-no-node       3 "$TMP/js-green"     "$NOTOOL"     "toolchain 'node' missing"
case_run js-bad-json      3 "$TMP/js-bad-json"  -             "unparseable"
case_run js-alias         0 "$TMP/js-alias"     -             "run type-check" "run test:unit" \
         "checks=typecheck,test" "GREEN"
case_run js-alias-test-only 0 "$TMP/js-alias-test-only" -     "run test:unit" "checks=test" "YELLOW"
case_run js-alias-tsc     0 "$TMP/js-alias-tsc" -             "checks=test" "YELLOW" \
         '!run tsc' '!TSC_RAN'
case_run js-tsc-noemit    0 "$TMP/js-tsc-noemit" -            "run tsc" \
         "checks=typecheck,test" "GREEN"
case_run js-tsc-emit      0 "$TMP/js-tsc-emit" -              "checks=test" "YELLOW" \
         '!run tsc'
case_run js-tsc-comment-noemit 0 "$TMP/js-tsc-comment-noemit" - "checks=test" "YELLOW" \
         '!run tsc'
case_run js-npm-placeholder 0 "$TMP/js-npm-placeholder" -     "checks=typecheck$" "YELLOW" \
         "npm init placeholder" "'test' not counted" '!RED' '!GREEN'
case_run js-empty-suite   0 "$TMP/js-empty-suite" -           "checks=typecheck$" "YELLOW" \
         "no test files found" "'test' not counted" '!RED' '!GREEN'
case_run js-empty-suite-slice 0 "$TMP/js-empty-suite-slice" - "run test:unit" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run js-empty-suite-incidental 1 "$TMP/js-empty-suite-incidental" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-empty-suite-chained 1 "$TMP/js-empty-suite-chained" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-empty-suite-chained-exit1 1 "$TMP/js-empty-suite-chained-exit1" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-empty-suite-chained-lower 1 "$TMP/js-empty-suite-chained-lower" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-empty-vitest-real 0 "$TMP/js-empty-vitest-real" - "checks=typecheck$" \
         "YELLOW" "no test files found" "'test' not counted" '!GREEN' '!RED'
case_run js-empty-jest-real 0 "$TMP/js-empty-jest-real" - "checks=typecheck$" \
         "YELLOW" "no test files found" "'test' not counted" '!GREEN' '!RED'
case_run js-empty-inline-then-error 1 "$TMP/js-empty-inline-then-error" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-pwnt          0 "$TMP/js-pwnt" -                "checks=typecheck$" "YELLOW" \
         "runner reported no tests" "'test' not counted" '!GREEN' '!RED'
case_run js-real-pass     0 "$TMP/js-real-pass" -           "checks=typecheck,test" "GREEN" \
         "!'test' not counted"
case_run js-node-test-empty 0 "$TMP/js-node-test-empty" -   "checks=typecheck$" "YELLOW" \
         "0 tests" "'test' not counted" '!GREEN' '!RED'
case_run js-node-test-tap   0 "$TMP/js-node-test-tap" -     "checks=typecheck$" "YELLOW" \
         "0 tests" "'test' not counted" '!GREEN' '!RED'
case_run js-node-test-real  0 "$TMP/js-node-test-real" -    "checks=typecheck,test" "GREEN" \
         "!'test' not counted"
# ANSI cases. FORCE_COLOR/CLICOLOR_FORCE are set for honesty about the
# situation being reproduced, but the verdict does not depend on them: the
# stubs print the escapes unconditionally, so these cases cannot pass by
# accident on a machine where some runner declines to colour.
ESC=$(printf '\033')
GATE_ENV="FORCE_COLOR=1 CLICOLOR_FORCE=1"
case_run js-pwnt-color    0 "$TMP/js-pwnt-color" -          "checks=typecheck$" "YELLOW" \
         "runner reported no tests" "'test' not counted" '!GREEN' '!RED'
GATE_ENV="FORCE_COLOR=1 CLICOLOR_FORCE=1"
case_run js-node-test-empty-color 0 "$TMP/js-node-test-empty-color" - \
         "checks=typecheck$" "YELLOW" "0 tests" "'test' not counted" '!GREEN' '!RED'
# No FORCE_COLOR here: npm would colour its own ERR! epilogue and sink the run
# to RED for a reason that has nothing to do with the guard under test.
case_run js-empty-mixed-color 1 "$TMP/js-empty-mixed-color" - "RED" \
         '!YELLOW' "!'test' not counted"
case_run js-empty-osc-hyperlink 1 "$TMP/js-empty-osc-hyperlink" - "RED" \
         '!YELLOW' "!'test' not counted"
GATE_ENV="FORCE_COLOR=1 CLICOLOR_FORCE=1"
case_run js-empty-npm-color 0 "$TMP/js-empty-suite" "$EMPTY_NPM_COLOR:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run js-empty-npm-plain 0 "$TMP/js-empty-suite" "$EMPTY_NPM_PLAIN:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
GATE_ENV="FORCE_COLOR=1 CLICOLOR_FORCE=1"
case_run js-color-passthrough 0 "$TMP/js-color-passthrough" - \
         "$ESC\[33mNo test files found, exiting with code 0$ESC\[39m"
case_run js-alias-check-types 0 "$TMP/js-alias-check-types" - "run check-types" \
         "checks=typecheck,test" "GREEN"
case_run js-test-and-unit 0 "$TMP/js-test-and-unit" -         "run test$" \
         "checks=typecheck,test" "GREEN" '!run test:unit' '!ALIAS_TEST_RAN'
# Two caps at once — a short checks= list and an uncounted suite — and the
# verdict has to carry both on one line: an if/elif reported whichever came
# first and dropped the other, and every other assertion here passed anyway.
case_run js-test-slices   0 "$TMP/js-test-slices" -           "checks=typecheck$" "YELLOW" \
         "test:\* slices found (test:unit test:e2e)" "'test' not counted" \
         "only ran: typecheck (missing full typecheck+test); a detected stack has no countable suite" \
         '!UNIT_RAN' '!E2E_RAN'
case_run js-test-slices-only 3 "$TMP/js-test-slices-only" -   "no runnable checks" \
         "test:\* slices found" "'test' not counted"
case_run js-test-integration 0 "$TMP/js-test-integration" -   "run test:integration" \
         "checks=typecheck,test" "GREEN"
# Both watch fixtures hang for real, so they run under a short watchdog: if the
# exclusion ever regresses the gate starts the script, and at the default 900s
# the regression costs a quarter of an hour before elapsed_lt can report it.
GATE_ENV="GATE_TIMEOUT=20"
case_run js-test-watch    0 "$TMP/js-test-watch" -            "checks=typecheck$" "YELLOW" \
         "no slice the gate will run (test:watch)" "'test' not counted" '!run test:watch'
elapsed_lt js-test-watch-never-started 15
GATE_ENV="GATE_TIMEOUT=20"
case_run js-test-watch-nested 0 "$TMP/js-test-watch-nested" - "checks=typecheck$" "YELLOW" \
         "no slice the gate will run (test:watch:all)" '!run test:watch:all'
elapsed_lt js-test-watch-nested-never-started 15
case_run js-slice-empty   0 "$TMP/js-slice-empty" -           "checks=typecheck$" "YELLOW" \
         "test:\* slices found (test:unit test:e2e)" '!UNIT_RAN'
case_run js-typecheck-only 0 "$TMP/js-typecheck-only" -       "checks=typecheck$" "YELLOW" \
         "no 'test' script in package.json" "'test' not counted"
case_run js-poly-uncounted 0 "$TMP/js-poly-uncounted" "$GO:$PATH" "checks=typecheck,test" \
         "'test' not counted" "no countable suite" '!GREEN'
case_run js-test-ui       0 "$TMP/js-test-ui" -              "checks=typecheck$" "YELLOW" \
         "test:\* slices found (test:unit test:ui)" '!UNIT_RAN' '!UI_RAN' '!GREEN'
case_run js-test-ui-only  0 "$TMP/js-test-ui-only" -          "checks=typecheck$" "YELLOW" \
         "no slice the gate will run (test:ui)" "'test' not counted" \
         '!UI_RAN' '!only watch-mode' '!GREEN'
# Bounded like the other fixtures that hang for real: the promotion rule here is
# about counting, but the slice it declines to run still never exits, so a
# regression must cost 20s and not the default quarter of an hour.
GATE_ENV="GATE_TIMEOUT=20"
case_run js-test-unit-watch 0 "$TMP/js-test-unit-watch" -     "run test:unit" \
         "checks=typecheck,test" "GREEN" '!run test:watch'
elapsed_lt js-test-unit-watch-bounded 15
case_run js-alias-both    0 "$TMP/js-alias-both" -            "run typecheck$" \
         "checks=typecheck,test" "GREEN" '!run type-check' '!ALIAS_TYPECHECK_RAN'
case_run js-alias-red     1 "$TMP/js-alias-red" -             "RED at 'npm run test:unit'"
case_run js-yarn-alias    0 "$TMP/js-yarn-alias" "$YARN:$PATH" "yarn type-check" "yarn test:unit" \
         "checks=typecheck,test" "GREEN" '!yarn run'
case_run js-pnpm          0 "$TMP/js-pnpm"       "$PNPM:$PATH" "pnpm run typecheck" "pnpm run test" \
         "checks=typecheck,test" "GREEN"
case_run js-bun           0 "$TMP/js-bun"        "$BUN:$PATH"  "bun run typecheck" "bun run test" \
         "checks=typecheck,test" "GREEN"
# The empty-suite cap must not depend on which manager ran the script: each of
# these prints its own epilogue after the runner's line, and every one of them
# used to be read as a chained failure and sink the run to RED.
case_run js-empty-pnpm    0 "$TMP/js-empty-pnpm" "$EMPTY_PNPM:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run js-empty-pnpm9   0 "$TMP/js-empty-pnpm" "$EMPTY_PNPM9:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run js-empty-yarn    0 "$TMP/js-empty-yarn" "$EMPTY_YARN:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run js-empty-bun     0 "$TMP/js-empty-bun"  "$EMPTY_BUN:$PATH" \
         "checks=typecheck$" "YELLOW" "no test files found" "'test' not counted" \
         '!RED' '!GREEN'
case_run polyglot-partial 3 "$TMP/polyglot"     "$OK:$NOTOOL" "checks=test" "some detected stack"
case_run partial-none-ran 3 "$TMP/go-only"      "$NOTOOL"     "nothing ran"
case_run dotnet-green     0 "$TMP/dotnet-root"  "$OK:$BASE"   "checks=typecheck,test" "GREEN"
case_run dotnet-red       1 "$TMP/dotnet-root"  "$FAIL:$BASE" "RED"
case_run dotnet-subdir    0 "$TMP/dotnet-sub"   "$OK:$BASE"   "src/App/App.fsproj" "GREEN"
case_run dotnet-sln       0 "$TMP/dotnet-sln"   "$OK:$BASE" \
         "dotnet build --nologo -v minimal MyApp.sln" \
         "dotnet test --nologo -v minimal MyApp.sln" "GREEN"
case_run dotnet-two-slns  0 "$TMP/dotnet-two-slns" "$OK:$BASE" \
         "dotnet build --nologo -v minimal$" "checks=typecheck"
case_run jvm-hybrid       0 "$TMP/jvm-hybrid"   "$OK:$BASE"   "mvn -q test" "gradle test" "GREEN"
case_run jvm-no-tests     0 "$TMP/jvm-no-tests" "$OK:$BASE"   "mvn -q test" \
         "no src/test directory found" "not counted" "no countable suite" '!GREEN'
case_run jvm-module-tests 0 "$TMP/jvm-module-tests" "$OK:$BASE" "mvn -q test" "GREEN" \
         '!not counted'
case_run jvm-mvnw         0 "$TMP/jvm-mvnw"     "$NOTOOL"     "./mvnw -q test" \
         "checks=typecheck,test" "GREEN"
case_run jvm-gradlew      0 "$TMP/jvm-gradlew"  "$NOTOOL"     "./gradlew test" \
         "checks=typecheck,test" "GREEN"
case_run dotnet-poly-uncounted 0 "$TMP/dotnet-poly-uncounted" "$OK:$PATH" \
         "checks=typecheck,test" "not counted" "no countable suite" '!GREEN'
case_run py-reqs-no-source 0 "$TMP/py-reqs-no-source" -       "checks=typecheck,test" "GREEN" \
         '!not counted'
case_run py-reqs-with-source 0 "$TMP/py-reqs-with-source" -   "checks=typecheck,test" \
         "no pytest config" "no countable suite" '!GREEN'
case_run rb-gemfile-only  0 "$TMP/rb-gemfile-only" "$OK:$PATH" "checks=typecheck,test" "GREEN" \
         '!not counted'
case_run rb-source-no-spec 0 "$TMP/rb-source-no-spec" "$OK:$PATH" "checks=typecheck,test" \
         "no spec/ and no Rakefile" "no countable suite" '!GREEN'
case_run rb-sorbet-rspec  0 "$TMP/rb-sorbet-rspec" "$OK:$BASE" \
         "bundle exec srb tc" "bundle exec rspec" "checks=typecheck,test" "GREEN"
case_run rb-rake          0 "$TMP/rb-rake"      "$OK:$BASE"   "bundle exec rake test" \
         "checks=test" "YELLOW"
case_run rb-both-runners  0 "$TMP/rb-both-runners" "$OK:$BASE" \
         "bundle exec srb tc" "checks=typecheck$" "YELLOW" \
         "both rspec" "rake test" "'test' not counted" "no countable suite" \
         '!bundle exec rspec' '!bundle exec rake' '!GREEN'
# A directory is not a suite: rspec on a spec/ with no *_spec.rb exits 0 on
# "0 examples" and used to reach GREEN, which unlocks dead-export deletion on a
# repo that has no tests at all. The runner must not even be invoked.
case_run rb-spec-empty    0 "$TMP/rb-spec-empty" "$OK:$BASE" \
         "bundle exec srb tc" "checks=typecheck$" "YELLOW" \
         "holds no" "'test' not counted" "no countable suite" \
         '!bundle exec rspec' '!GREEN'
case_run rb-test-empty    0 "$TMP/rb-test-empty" "$OK:$BASE" \
         "bundle exec srb tc" "checks=typecheck$" "YELLOW" \
         "holds no" "'test' not counted" "no countable suite" \
         '!bundle exec rake' '!GREEN'
# Rake::TestTask's default naming counts as a real suite on both sides.
case_run rb-both-prefix   0 "$TMP/rb-both-prefix" "$OK:$BASE" \
         "checks=typecheck$" "YELLOW" "both rspec" "'test' not counted" \
         '!bundle exec rspec' '!bundle exec rake' '!GREEN'
case_run rb-rake-prefix   0 "$TMP/rb-rake-prefix" "$OK:$BASE" \
         "bundle exec rake test" "checks=test" "YELLOW" "!'test' not counted"
case_run rb-helper-only   0 "$TMP/rb-helper-only" "$OK:$BASE" \
         "checks=typecheck$" "YELLOW" "holds no" "'test' not counted" \
         '!bundle exec rake' '!GREEN'
case_run py-setupcfg      0 "$TMP/py-setupcfg"  "$OK:$BASE"   "checks=typecheck,test" "GREEN"
case_run py-venv          0 "$TMP/py-venv"      "$BASE"       ".venv/bin/mypy" ".venv/bin/pytest" "GREEN"
case_run py-venv-plain    0 "$TMP/py-venv-plain" "$BASE"      "venv/bin/mypy" "venv/bin/pytest" "GREEN"
GATE_ENV="VIRTUAL_ENV=$TMP/py-virtualenv-prefix"
case_run py-virtualenv    0 "$TMP/py-virtualenv" "$BASE" \
         "$TMP/py-virtualenv-prefix/bin/mypy" "$TMP/py-virtualenv-prefix/bin/pytest" "GREEN"
case_run py-poetry        0 "$TMP/py-poetry"    "$POETRY:$BASE" "poetry run mypy" "poetry run pytest" \
         "checks=typecheck,test" "GREEN"
case_run py-no-tools      3 "$TMP/py-no-tools"  "$BASE"       "toolchain 'mypy' missing" "looked in"
case_run py-uv            0 "$TMP/py-uv"        "$UV:$BASE"   "uv run pytest" "checks=test"
case_run py-pyright       0 "$TMP/py-pyright"   "$OK:$BASE"   "checks=typecheck"
case_run py-pytest-no-tests 0 "$TMP/py-pytest-no-tests" "$PY5:$BASE" \
         "checks=typecheck" "not counted" "no tests collected (exit 5)"
case_run py-pytest-only-no-tests 3 "$TMP/py-pytest-only-no-tests" "$PY5:$BASE" \
         "no runnable checks" "no tests collected (exit 5)"
case_run go-with-tests    0 "$TMP/go-with-tests" "$GO:$BASE"  "checks=typecheck,test" "GREEN"
case_run go-no-tests      0 "$TMP/go-no-tests"  "$GO:$BASE"   "checks=typecheck" "not counted" '!go test'
case_run rust-with-tests  0 "$TMP/rust-with-tests" "$CARGO:$BASE" "checks=typecheck,test" "GREEN"
case_run rust-tests-dir   0 "$TMP/rust-tests-dir" "$CARGO:$BASE" "checks=typecheck,test" "GREEN"
case_run rust-no-tests    0 "$TMP/rust-no-tests"  "$CARGO:$BASE" "checks=typecheck" "not counted" '!cargo test'
case_run rust-vendor      0 "$TMP/rust-vendor"    "$CARGO:$BASE" "checks=typecheck" "not counted" '!cargo test'
case_run dotnet-no-tests  0 "$TMP/dotnet-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'
case_run dotnet-sub-no-t  0 "$TMP/dotnet-sub-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'
case_run dotnet-deep      0 "$TMP/dotnet-deep"  "$OK:$BASE"   "checks=typecheck,test" "dotnet test" "GREEN"
case_run dotnet-prune-bin 0 "$TMP/dotnet-prune-bin" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'

GATE_ENV="GATE_TIMEOUT=2"
case_run hang             4 "$TMP/go-hang"      "$HANG:$BASE" "TIMEOUT after 2s"
elapsed_lt hang-is-bounded 10

# watchdog resolution ---------------------------------------------------
# Which backend the gate picks, and with which timeout, is contract: all three
# have to exit 124, and the order timeout > gtimeout > perl must hold on any
# machine. The delegators make that observable without waiting for a real hang.
# These first delegators fail the -k capability probe (they exit 124 for every
# argument list, the probe included), so they also pin the degraded shape: a
# backend without -k is called exactly as before, with no extra flag.
reset_logs
GATE_ENV="GATE_TIMEOUT=2"
case_run wd-timeout-dispatch 4 "$TMP/go-hang" "$WD_T:$GO:$BASE" "TIMEOUT after 2s"
assert_log wd-timeout-args "$WD_LOG_T" "2 go build ./..."

reset_logs
GATE_ENV="GATE_TIMEOUT=2"
case_run wd-order-timeout-wins 4 "$TMP/go-hang" "$WD_T:$WD_G:$GO:$BASE" "TIMEOUT after 2s"
assert_log wd-order-timeout-log "$WD_LOG_T" "2 go build ./..."
assert_no_log wd-order-gtimeout-idle "$WD_LOG_G"

reset_logs
GATE_ENV="GATE_TIMEOUT=2"
case_run wd-gtimeout-over-perl 4 "$TMP/go-hang" "$WD_G:$GO:$MINI" "TIMEOUT after 2s"
assert_log wd-gtimeout-args "$WD_LOG_G" "2 go build ./..."

# A backend that does answer the probe gets -k: TERM at the timeout, KILL 2s
# later, so a check that ignores TERM cannot hold the gate open.
reset_logs
GATE_ENV="GATE_TIMEOUT=2"
case_run wd-kill-after-passthrough 4 "$TMP/go-hang" "$WD_K:$GO:$BASE" "TIMEOUT after 2s"
assert_log wd-kill-after-args "$WD_LOG_K" "-k 2 2 go build ./..."

# And the code that escalation actually produces. Against the real timeout, a
# check that ignores TERM dies from the -k KILL and the shell reports 137 —
# which used to miss the `rc -eq 124` test and be announced as "RED at 'go
# build ./...'", turning "we could not tell, it hung" into "your code is
# broken". Skipped where the -k probe found no support, since then no
# escalation happens at all.
if command -v timeout >/dev/null 2>&1 && timeout -k 2 1 true >/dev/null 2>&1; then
  GATE_ENV="GATE_TIMEOUT=2"
  case_run wd-kill-after-137 4 "$TMP/go-hang" "$IGNTERM:$BASE" "TIMEOUT after 2s" '!RED'
  elapsed_lt wd-kill-after-137-is-bounded 15
else
  skipped wd-kill-after-137 "no timeout with -k support"
  skipped wd-kill-after-137-is-bounded "no timeout with -k support"
fi

# The perl backend is the one that only shows up on a machine without coreutils;
# a minimal PATH keeps it covered even when the suite runs on Linux.
if command -v perl >/dev/null; then
  reset_logs
  GATE_ENV="GATE_TIMEOUT=2"
  case_run wd-perl-forced 4 "$TMP/go-hang" "$HANG:$MINI" "TIMEOUT after 2s"
  elapsed_lt wd-perl-is-bounded 10

  # Regression: killing the process group is not enough — a descendant that
  # called setsid keeps running after the gate reports TIMEOUT unless the
  # watchdog snapshots the tree before the kill and sweeps the survivors.
  GATE_ENV="GATE_TIMEOUT=2"
  case_run wd-escapee 4 "$TMP/go-hang" "$ESCAPE:$MINI" "TIMEOUT after 2s"
  elapsed_lt wd-escapee-is-bounded 10
  assert_reaped wd-escapee-reaped "$ESCAPEE_PID_FILE"

  # Regression: the JS test path captures output, and a detached grandchild
  # holding the inherited stdout kept that capture blocked for the
  # grandchild's whole life — GATE_TIMEOUT=2 with a 30s leak returned in 30s,
  # verdict GREEN, exit 4 never raised. The runner itself exits 0 at once, so
  # the gate is only allowed the couple of seconds that costs.
  GATE_ENV="GATE_TIMEOUT=2"
  case_run js-hold-detached 0 "$TMP/js-hold" "$JS_HOLD:$PATH" \
           "checks=typecheck,test" "GREEN"
  elapsed_lt js-hold-detached-is-bounded 10

  # Without ps there is no tree to snapshot and no start time to confirm, so
  # the watchdog only kills the group: the escapee survives, and asserting
  # otherwise would be freezing a limitation as a promise. What is contract
  # here is that the degraded path still returns exit 4 on schedule instead of
  # dying on the missing ps or hanging on the ps that never answers.
  GATE_ENV="GATE_TIMEOUT=2"
  case_run wd-no-ps 4 "$TMP/go-hang" "$ESCAPE_NOPS:$NOPS" "TIMEOUT after 2s"
  elapsed_lt wd-no-ps-is-bounded 10

  # ps present but without lstart support (BusyBox shape): the watchdog must
  # fall back to pid-only matching and still reap the escapee.
  GATE_ENV="GATE_TIMEOUT=2"
  case_run wd-ps-no-lstart 4 "$TMP/go-hang" "$ESCAPE_NOLS:$NOLS:$MINI" "TIMEOUT after 2s"
  elapsed_lt wd-ps-no-lstart-is-bounded 10
  assert_reaped wd-ps-no-lstart-reaped "$TMP/escapee-nols.pid"
else
  echo "skip: wd-perl-forced (no perl on this machine)"
fi

# 0 disables the watchdog: a check that exits 124 on its own is RED, not
# TIMEOUT, and no backend is invoked at all.
reset_logs
GATE_ENV="GATE_TIMEOUT=0"
case_run wd-disabled 1 "$TMP/go-hang" "$WD_T:$GO124:$BASE" "RED at 'go build"
assert_no_log wd-disabled-no-dispatch "$WD_LOG_T"

reset_logs
GATE_ENV="GATE_TIMEOUT=abc"
case_run wd-bad-value 4 "$TMP/go-hang" "$WD_T:$GO:$BASE" "is not a number — using 900"
assert_log wd-bad-value-args "$WD_LOG_T" "900 go build ./..."

echo "----"
echo "$((total-failures))/$total cases passed"
[[ $failures -eq 0 ]]
