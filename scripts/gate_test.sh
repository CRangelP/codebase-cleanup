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
ESCAPEE_PID_FILE=""
cleanup() {
  if [[ -n $ESCAPEE_PID_FILE && -s $ESCAPEE_PID_FILE ]]; then
    kill -KILL "$(cat "$ESCAPEE_PID_FILE")" 2>/dev/null
  fi
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
  if [[ $path == - ]]; then out=$(env $GATE_ENV bash "$GATE" "$dir" 2>&1); rc=$?
  else out=$(env PATH="$path" $GATE_ENV bash "$GATE" "$dir" 2>&1); rc=$?; fi
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

mkdir -p "$TMP/polyglot/tests"
touch "$TMP/polyglot/pyproject.toml" "$TMP/polyglot/tests/test_x.py"
printf 'module f\n\ngo 1.21\n' > "$TMP/polyglot/go.mod"

mkdir -p "$TMP/dotnet-root" "$TMP/dotnet-sub/src/App"
TESTPROJ='<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>'
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-root/App.csproj"
printf '%s\n' "$TESTPROJ" > "$TMP/dotnet-sub/src/App/App.fsproj"

mkdir -p "$TMP/dotnet-no-tests" "$TMP/dotnet-sub-no-tests/src/App"
printf '<Project></Project>\n' > "$TMP/dotnet-no-tests/App.csproj"
printf '<Project></Project>\n' > "$TMP/dotnet-sub-no-tests/src/App/App.fsproj"

mkdir -p "$TMP/jvm-hybrid"
touch "$TMP/jvm-hybrid/pom.xml" "$TMP/jvm-hybrid/build.gradle"

mkdir -p "$TMP/py-setupcfg/test"
printf '[mypy]\n' > "$TMP/py-setupcfg/setup.cfg"
touch "$TMP/py-setupcfg/test/test_x.py"

mkdir -p "$TMP/py-venv/tests" "$TMP/py-venv/.venv/bin"
printf '[tool.mypy]\n' > "$TMP/py-venv/pyproject.toml"
touch "$TMP/py-venv/tests/test_x.py"
stub "$TMP/py-venv/.venv/bin" mypy 0
stub "$TMP/py-venv/.venv/bin" pytest 0

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

mkdir -p "$TMP/go-hang"
printf 'module f\n\ngo 1.21\n' > "$TMP/go-hang/go.mod"
printf 'package f\n' > "$TMP/go-hang/x_test.go"

# stubs ----------------------------------------------------------------
OK="$TMP/stubs-ok"; FAIL="$TMP/stubs-fail"; HANG="$TMP/stubs-hang"; UV="$TMP/stubs-uv"
for t in pytest mypy pyright dotnet mvn gradle; do stub "$OK" "$t" 0; done
stub "$FAIL" dotnet 1
stub_body "$HANG" go 'sleep 30'
stub "$UV" uv 0
GO="$TMP/stubs-go"; stub "$GO" go 0
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

reset_logs() { rm -f "$WD_LOG_T" "$WD_LOG_G" "$WD_LOG_K"; }

# A check whose grandchild calls setsid: it leaves the gate's process group, so
# 'kill -PGID' alone would leave it running past the timeout. It records its own
# pid and sleeps for a bounded time, never longer than the suite. Its output goes
# to /dev/null on purpose: holding the case's pipe open would make case_run wait
# for it, which hides the very leak this case is about.
ESCAPE="$TMP/stubs-escape"
ESCAPEE_PID_FILE="$TMP/escapee.pid"
mkdir -p "$ESCAPE"
cat > "$ESCAPE/go" <<EOF
#!/bin/sh
perl -e 'use POSIX; POSIX::setsid(); open(F, ">", "$ESCAPEE_PID_FILE") or exit 1;
         print F \$\$; close F; sleep 60' >/dev/null 2>&1 &
sleep 45
EOF
chmod +x "$ESCAPE/go"

# matrix ---------------------------------------------------------------
case_run bad-path         2 "$TMP/nope"         -             "bad path"
case_run empty            3 "$TMP/empty"        -             "no runnable checks"
case_run js-green         0 "$TMP/js-green"     -             "checks=typecheck,test" "GREEN"
case_run js-test-only     0 "$TMP/js-test-only" -             "checks=test" "YELLOW"
case_run js-red           1 "$TMP/js-red"       -             "RED"
case_run js-no-node       3 "$TMP/js-green"     "$BASE"       "toolchain 'node' missing"
case_run js-bad-json      3 "$TMP/js-bad-json"  -             "unparseable"
case_run polyglot-partial 3 "$TMP/polyglot"     "$OK:$BASE"   "checks=test" "some detected stack"
case_run partial-none-ran 3 "$TMP/go-only"      "$BASE"       "nothing ran"
case_run dotnet-green     0 "$TMP/dotnet-root"  "$OK:$BASE"   "checks=typecheck,test" "GREEN"
case_run dotnet-red       1 "$TMP/dotnet-root"  "$FAIL:$BASE" "RED"
case_run dotnet-subdir    0 "$TMP/dotnet-sub"   "$OK:$BASE"   "src/App/App.fsproj" "GREEN"
case_run jvm-hybrid       0 "$TMP/jvm-hybrid"   "$OK:$BASE"   "mvn -q test" "gradle test" "GREEN"
case_run py-setupcfg      0 "$TMP/py-setupcfg"  "$OK:$BASE"   "checks=typecheck,test" "GREEN"
case_run py-venv          0 "$TMP/py-venv"      "$BASE"       ".venv/bin/mypy" ".venv/bin/pytest" "GREEN"
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
case_run dotnet-no-tests  0 "$TMP/dotnet-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'
case_run dotnet-sub-no-t  0 "$TMP/dotnet-sub-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'

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
