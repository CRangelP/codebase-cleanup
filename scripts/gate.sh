#!/usr/bin/env bash
# Cleanup gate: typecheck + tests, stopping at the first red.
# Detects the stack from the root manifest (there may be more than one; runs all).
# Requires bash (macOS 3.2 is fine). Usage: gate.sh [dir]
# Output: "[gate] checks=..." lists what actually ran (compiling counts as typecheck).
# Exit 0 = everything that ran passed · 1 = some check failed ·
# 2 = bad path (the argument is not a reachable directory: nothing was checked) ·
# 3 = no runnable check OR a detected stack has no toolchain (PARTIAL) —
#     in both cases, run the gate manually: classify according to the stack ·
# 4 = a check hit the GATE_TIMEOUT watchdog (inconclusive gate, never GREEN).
# GATE_TIMEOUT: seconds per check, default 900; 0 disables the watchdog.
set -uo pipefail

target="${1:-.}"
if [[ ! -d $target ]]; then
  echo "[gate] bad path: '$target' is not a directory" >&2
  exit 2
fi
cd "$target" || {
  echo "[gate] bad path: '$target' is not a directory we can enter" >&2
  exit 2
}
ran_typecheck=0
ran_test=0
incomplete=0

# --- Watchdog ---------------------------------------------------------
# A hanging check (a test waiting on a port, a REPL, a prompt) would freeze the
# gate forever. Resolve one backend up front; all three exit 124 on timeout,
# copying GNU timeout so run() only has to know that number.
# Limit: what still escapes the kill is a double fork already reparented to
# init/launchd when the alarm fires, and anything created between the snapshot
# and the kill. The perl backend also sweeps descendants by parent pid (needs
# ps; without it the sweep silently degrades to the group kill), so under perl
# a plain setsid does not escape — it changes the group, not the parent. GNU
# timeout/gtimeout kill the group only, with no sweep: there a setsid child
# does escape. A pid recycled during the TERM→KILL grace is no longer signalled
# by mistake: the snapshot records each process start time and the sweep only
# touches a survivor whose start time still matches. Where ps has no lstart
# (BusyBox), the sweep falls back to matching by pid alone, as before.
GATE_TIMEOUT=${GATE_TIMEOUT:-900}
case $GATE_TIMEOUT in
  ''|*[!0-9]*)
    echo "[gate] GATE_TIMEOUT='$GATE_TIMEOUT' is not a number — using 900" >&2
    GATE_TIMEOUT=900 ;;
esac

# fork + setpgrp so the whole group dies, not just the direct child. The alarm
# handler first snapshots the descendants of the child (ps, walked transitively)
# and only then kills the group: after the kill the survivors are reparented and
# the link that identifies them is gone, so the order matters.
PERL_WATCHDOG='my $t = shift;
my $pid = fork();
if (!defined $pid) { exit 127; }
if (!$pid) { setpgrp(0,0); exec @ARGV; exit 127; }
$SIG{ALRM} = sub {
  my (%kids, %start, %now, @tree, @queue, %seen);
  my $have_start = 0;
  if (open(my $ps, "-|", "ps", "-eo", "pid=,ppid=,lstart=")) {
    while (<$ps>) {
      my ($c, $p, $st) = /^\s*(\d+)\s+(\d+)\s+(.*?)\s*$/ or next;
      push @{$kids{$p}}, $c;
      $start{$c} = $st;
      $have_start = 1;
    }
    close $ps;
  }
  if (!$have_start) {
    %kids = ();
    if (open(my $ps, "-|", "ps", "-eo", "pid=,ppid=")) {
      while (<$ps>) {
        my ($c, $p) = /^\s*(\d+)\s+(\d+)/ or next;
        push @{$kids{$p}}, $c;
      }
      close $ps;
    }
  }
  @queue = ($pid); $seen{$pid} = 1;
  while (@queue) {
    my $cur = shift @queue;
    for my $k (@{$kids{$cur} || []}) {
      next if $seen{$k}++;
      push @tree, $k; push @queue, $k;
    }
  }
  kill "TERM", -$pid; sleep 2; kill "KILL", -$pid;
  if ($have_start && @tree) {
    if (open(my $ps, "-|", "ps", "-eo", "pid=,ppid=,lstart=")) {
      while (<$ps>) {
        my ($c, $p, $st) = /^\s*(\d+)\s+(\d+)\s+(.*?)\s*$/ or next;
        $now{$c} = $st;
      }
      close $ps;
    }
  }
  @tree = grep { $_ > 1 && $_ != $$ && kill(0, $_) &&
                 (!$have_start || !exists $start{$_} || $now{$_} eq $start{$_}) } @tree;
  if (@tree) { kill "TERM", @tree; sleep 1; kill "KILL", grep { kill(0, $_) } @tree; }
  exit 124;
};
alarm $t;
waitpid($pid, 0);
alarm 0;
my $rc = $?;
exit(($rc & 127) ? 128 + ($rc & 127) : ($rc >> 8));'

WATCHDOG=""
WD_KILL_AFTER=""
if [[ $GATE_TIMEOUT -gt 0 ]]; then
  if command -v timeout >/dev/null; then WATCHDOG=timeout
  elif command -v gtimeout >/dev/null; then WATCHDOG=gtimeout
  elif command -v perl >/dev/null; then WATCHDOG=perl
  else echo "[gate] no watchdog available — checks run unbounded" >&2
  fi
fi

# GNU timeout only sends TERM: a check that ignores it stays alive and the gate
# waits for it forever. -k asks for a KILL 2s later, the same escalation the perl
# backend already does by hand. Not every timeout has the flag (BusyBox does
# not), so probe it once, here, with a command that cannot hang. Failing the
# probe — including a PATH without 'true' — means running without -k, which is
# exactly today's behaviour.
case $WATCHDOG in
  timeout|gtimeout)
    if "$WATCHDOG" -k 2 1 true >/dev/null 2>&1; then WD_KILL_AFTER="-k 2"; fi ;;
esac

# guard <cmd...> — runs the command under the resolved watchdog, if any
guard() {
  case $WATCHDOG in
    timeout|gtimeout)
      # shellcheck disable=SC2086  # WD_KILL_AFTER is a flag pair or empty, by design
      "$WATCHDOG" $WD_KILL_AFTER "$GATE_TIMEOUT" "$@" ;;
    perl) perl -e "$PERL_WATCHDOG" "$GATE_TIMEOUT" "$@" ;;
    *) "$@" ;;
  esac
}

# run <kind> <cmd...>
# <kind> is typecheck|test|both, optionally extended as <kind>:<rc>:<stack>:
# that <rc> is the runner's "I collected nothing" code, and it is a YELLOW cap
# (the check did not run) instead of RED. pytest is the case: exit 5 means zero
# tests collected, which would otherwise sink a repo whose suite lives elsewhere.
run() {
  local kind=$1; shift
  local rc
  local no_tests_rc="" nt_label=""
  case $kind in
    *:*) nt_label=${kind#*:}; no_tests_rc=${nt_label%%:*}; nt_label=${nt_label#*:}
         kind=${kind%%:*} ;;
  esac
  echo "[gate] $*"
  guard "$@"
  rc=$?
  # The watchdog keeps absolute priority: a check killed at the timeout is
  # inconclusive, never "no tests collected", whatever code it happens to share.
  if [[ -n $WATCHDOG && $rc -eq 124 ]]; then
    echo "[gate] TIMEOUT after ${GATE_TIMEOUT}s at '$*'" >&2
    exit 4
  fi
  if [[ -n $no_tests_rc && $rc -eq $no_tests_rc ]]; then
    no_tests "$nt_label" "no tests collected (exit $rc)"
    return 0
  fi
  if [[ $rc -ne 0 ]]; then
    echo "[gate] RED at '$*'" >&2
    exit 1
  fi
  case $kind in
    typecheck) ran_typecheck=1 ;;
    test) ran_test=1 ;;
    both) ran_typecheck=1; ran_test=1 ;;
  esac
}

missing() {
  echo "[gate] $1 present but toolchain '$2' missing — manual gate" >&2
  incomplete=1
}

# no_tests <stack> <reason> — a green run with no test file is not a tested
# repo. Does not set incomplete: the verdict stays exit 0 with checks=typecheck,
# which is the YELLOW cap, and the user can promote it by hand.
no_tests() {
  echo "[gate] $1: $2 — 'test' not counted (YELLOW cap; promote by hand if the" \
       "suite lives elsewhere)" >&2
}

py_missing() {
  echo "[gate] $1 present but toolchain '$2' missing — looked in \$VIRTUAL_ENV/bin," \
       ".venv/bin, venv/bin, uv/poetry and PATH — manual gate" >&2
  incomplete=1
}

# py_run <kind> <label> <tool> [args...] — resolves <tool> via py_cmd and runs
# it, or records the miss.
py_run() {
  local kind=$1 label=$2 tool=$3 prefix
  shift 3
  prefix=$(py_cmd "$tool")
  # shellcheck disable=SC2086  # the prefix is split on purpose
  if [[ -n $prefix ]]; then run "$kind" $prefix "$@"
  else py_missing "$label" "$tool"; fi
}

# py_cmd <tool> — echoes the command prefix that runs <tool> in this project.
# A Python project rarely puts its tools on the global PATH: the virtualenv
# comes first, then the lockfile runners, and only then the global install.
# Echoes a string (bash 3.2 has no arrays to return); call sites split it on
# whitespace, which is safe because none of these paths contain spaces.
py_cmd() {
  local tool=$1
  if [[ -n ${VIRTUAL_ENV:-} && -x ${VIRTUAL_ENV:-}/bin/$tool ]]; then
    echo "$VIRTUAL_ENV/bin/$tool"; return 0
  fi
  if [[ -x .venv/bin/$tool ]]; then echo ".venv/bin/$tool"; return 0; fi
  if [[ -x venv/bin/$tool ]]; then echo "venv/bin/$tool"; return 0; fi
  if [[ -f uv.lock ]] || grep -qs '^\[tool\.uv\]' pyproject.toml; then
    if command -v uv >/dev/null; then echo "uv run $tool"; return 0; fi
  fi
  if [[ -f poetry.lock ]]; then
    if command -v poetry >/dev/null; then echo "poetry run $tool"; return 0; fi
  fi
  if command -v "$tool" >/dev/null; then echo "$tool"; return 0; fi
  return 1
}

# --- JS/TS (package.json) ---
if [[ -f package.json ]]; then
  if [[ -f bun.lock || -f bun.lockb ]]; then PM=bun
  elif [[ -f pnpm-lock.yaml ]]; then PM=pnpm
  elif [[ -f yarn.lock ]]; then PM=yarn
  else PM=npm
  fi
  if ! command -v node >/dev/null; then missing package.json node
  elif ! command -v "$PM" >/dev/null; then missing package.json "$PM"
  elif ! node -e "require('./package.json')" 2>/dev/null; then
    # Without this probe the script lookup below fails silently and the whole
    # JS/TS stack disappears from the verdict as if it did not exist.
    echo "[gate] package.json unparseable — JS/TS checks skipped" >&2
    incomplete=1
  else
    for script in typecheck test; do
      if node -e "const s=require('./package.json').scripts||{};process.exit(s['$script']?0:1)" 2>/dev/null; then
        if [[ $PM == yarn ]]; then run "$script" yarn "$script"
        else run "$script" "$PM" run "$script"; fi
      fi
    done
  fi
fi

# --- Go (go.mod) ---
if [[ -f go.mod ]]; then
  if command -v go >/dev/null; then
    run typecheck go build ./...
    # 'go test ./...' passes on a repo with zero test files. Counting that as a
    # test is how a suiteless repo gets classified GREEN.
    if [[ -n $(find . -name '*_test.go' -not -path './vendor/*' -print -quit 2>/dev/null) ]]; then
      run test go test ./...
    else
      no_tests go "no *_test.go found"
    fi
  else missing go.mod go; fi
fi

# --- Rust (Cargo.toml) ---
if [[ -f Cargo.toml ]]; then
  if command -v cargo >/dev/null; then
    run typecheck cargo check --all-targets --quiet
    # 'cargo test' on a crate with no test exits 0 reporting "0 passed" — the
    # same trap as 'go test'. A Rust test is either an integration file under
    # tests/ or a #[test]/#[cfg(test)] item in the sources; target/ is build
    # output and never evidence. /dev/null keeps grep off stdin when the scan
    # comes up empty, and head -1 is what makes the result the whole scan's,
    # not the last xargs batch's.
    rust_tests=$(find . -name '*.rs' -path '*/tests/*' -not -path './target/*' \
                   -print -quit 2>/dev/null)
    if [[ -z $rust_tests ]]; then
      rust_tests=$(find . -name '*.rs' -not -path './target/*' -print0 2>/dev/null \
        | xargs -0 grep -lE '#\[test\]|#\[cfg\(test\)\]' /dev/null 2>/dev/null | head -1)
    fi
    if [[ -n $rust_tests ]]; then
      run test cargo test --quiet
    else
      no_tests rust "no #[test] or tests/*.rs found"
    fi
  else missing Cargo.toml cargo; fi
fi

# --- Python (pyproject.toml / setup.py / setup.cfg / requirements.txt) ---
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg || -f requirements.txt ]]; then
  if [[ -f mypy.ini || -f .mypy.ini ]] || grep -qs '^\[tool\.mypy\]' pyproject.toml \
      || grep -qs '^\[mypy\]' setup.cfg; then
    py_run typecheck config-mypy mypy .
  fi
  if [[ -f pyrightconfig.json ]] || grep -qs '^\[tool\.pyright\]' pyproject.toml; then
    py_run typecheck config-pyright pyright
  fi
  if [[ -f pytest.ini || -d tests || -d test ]] || grep -qs '^\[tool\.pytest' pyproject.toml \
      || grep -qs '^\[tool:pytest\]' setup.cfg || grep -qs '^\[pytest\]' tox.ini; then
    py_run "test:5:python" python-tests pytest -q
  fi
fi

# --- JVM (pom.xml and/or build.gradle — hybrid repos run both) ---
if [[ -f pom.xml ]]; then
  if [[ -x ./mvnw ]]; then run both ./mvnw -q test
  elif command -v mvn >/dev/null; then run both mvn -q test
  else missing pom.xml mvn; fi
fi
if [[ -f build.gradle || -f build.gradle.kts ]]; then
  if [[ -x ./gradlew ]]; then run both ./gradlew test
  elif command -v gradle >/dev/null; then run both gradle test
  else missing build.gradle gradle; fi
fi

# --- Ruby (Gemfile) ---
if [[ -f Gemfile ]]; then
  if command -v bundle >/dev/null; then
    [[ -f sorbet/config ]] && run typecheck bundle exec srb tc
    if [[ -d spec ]]; then run test bundle exec rspec
    elif [[ -f Rakefile && -d test ]]; then run test bundle exec rake test; fi
  else missing Gemfile bundler; fi
fi

# --- .NET (sln/slnx/csproj/fsproj/vbproj at the root, or projects one level down) ---
# A test project is detected by content, not by name: the test SDK package, the
# explicit flag, or one of the three usual frameworks.
# Validated against mcr.microsoft.com/dotnet/sdk:8.0 (8.0.423) and :10.0
# (10.0.302) on 2026-08: 'dotnet test' without a test project really is a
# silent no-op exit 0 in both, and every dotnet-new test template matches the
# markers — on 10.0 the mstest template matches only through the MSTest token.
DOTNET_TEST_MARKERS='Microsoft\.NET\.Test\.Sdk|<IsTestProject>|xunit|NUnit|MSTest'
dotnet_targets=()
if compgen -G '*.sln' >/dev/null || compgen -G '*.slnx' >/dev/null \
    || compgen -G '*.??proj' >/dev/null; then
  dotnet_targets=(.)
else
  for p in */*.??proj src/*/*.??proj; do
    [[ -e $p ]] && dotnet_targets+=("$p")
  done
fi
if [[ ${#dotnet_targets[@]} -gt 0 ]]; then
  if command -v dotnet >/dev/null; then
    for target in "${dotnet_targets[@]}"; do
      # 'dotnet test' on a solution with no test project is a no-op that exits
      # 0 — same trap as 'go test' on a repo with no _test.go file.
      if [[ $target == . ]]; then
        has_tests=0
        # Three fixed depths only; a test project nested deeper is missed and
        # the verdict caps at YELLOW — fail-safe, promote by hand if so.
        grep -qsE "$DOTNET_TEST_MARKERS" ./*.??proj ./*/*.??proj ./src/*/*.??proj \
          && has_tests=1
        run typecheck dotnet build --nologo -v minimal
        if [[ $has_tests -eq 1 ]]; then run test dotnet test --nologo -v minimal
        else no_tests dotnet "no test project found"; fi
      else
        run typecheck dotnet build --nologo -v minimal "$target"
        if grep -qsE "$DOTNET_TEST_MARKERS" "$target"; then
          run test dotnet test --nologo -v minimal "$target"
        else no_tests dotnet "no test project found in '$target'"; fi
      fi
    done
  else missing 'sln/csproj' dotnet; fi
fi

# --- Verdict ---
checks=""
[[ $ran_typecheck -eq 1 ]] && checks="typecheck"
[[ $ran_test -eq 1 ]] && checks="${checks:+$checks,}test"

if [[ -z $checks ]]; then
  if [[ $incomplete -eq 1 ]]; then
    echo "[gate] PARTIAL — a detected stack has no toolchain and nothing ran; run the gate manually" >&2
  else
    echo "[gate] no runnable checks detected — run the stack's gate manually" >&2
  fi
  exit 3
fi

echo "[gate] checks=$checks"
if [[ $incomplete -eq 1 ]]; then
  echo "[gate] PARTIAL — some detected stack had no toolchain; finish the gate manually" >&2
  exit 3
fi
if [[ $checks == "typecheck,test" ]]; then
  echo "[gate] GREEN"
else
  echo "[gate] OK — only ran: $checks (missing full typecheck+test, YELLOW cap)"
fi
