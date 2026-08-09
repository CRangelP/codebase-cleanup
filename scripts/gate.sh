#!/usr/bin/env bash
# Cleanup gate: typecheck + tests, stopping at the first red.
# Detects the stack from the root manifest (there may be more than one; runs all).
# Requires bash (macOS 3.2 is fine). Usage: gate.sh [dir]
# Output: "[gate] checks=..." lists what actually ran (compiling counts as typecheck).
#   The verdict line below it is GREEN only when checks=typecheck,test AND every
#   detected stack had a countable suite; otherwise it names the cap(s).
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
uncounted=0

# --- Watchdog ---------------------------------------------------------
# A hanging check (a test waiting on a port, a REPL, a prompt) would freeze the
# gate forever. Resolve one backend up front; all three exit 124 on timeout,
# copying GNU timeout so run() only has to know that number. Contract: 124 is
# reserved for the watchdog, exactly as in GNU timeout — a check that
# legitimately exits 124 under an active watchdog is read as TIMEOUT.
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
    uncounted_suite "$nt_label" "no tests collected (exit $rc)"
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

# no_tests <stack> <reason> [advice] — a green run with no test file is not a
# tested repo. Does not set incomplete: the verdict stays exit 0, which is the
# YELLOW cap, and the user can promote it by hand. Every stack whose suite could
# not be counted goes through here, because the literal "'test' not counted" is
# the marker SKILL.md tells the agent to classify by. A checks= list that is
# merely short (checks=test, no typecheck) is also a YELLOW cap and does not
# come through here — the missing word in checks= is its own marker.
# <advice> is how the user gets past the cap; it defaults to promotion, which
# is wrong for a suite that is present but sliced, so those callers pass their own.
no_tests() {
  local advice=${3:-"promote by hand if the suite lives elsewhere"}
  echo "[gate] $1: $2 — 'test' not counted (YELLOW cap; $advice)" >&2
}

# uncounted_suite <stack> <reason> [advice] — no_tests for a whole stack, plus
# the flag the verdict reads. Without it a polyglot repo hides the cap: another
# stack supplies 'test', checks= reads typecheck,test and the run is announced
# GREEN while this stack's suite never ran — which is exactly what GREEN is not
# allowed to mean, since it unlocks dead-export deletion. Per-project caps
# inside one stack (a .NET project with no test project next to one that has
# them) are not this: there the stack's suite did run, so they call no_tests.
uncounted_suite() {
  uncounted=1
  no_tests "$@"
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
    # js_script <kind> <script> — invokes one package.json script under the
    # canonical <kind>. What reaches run() is the *kind*, never the alias,
    # because run() classifies by kind and an unknown word there would run the
    # check and count nothing. The alias stays visible in the human
    # '[gate] <cmd>' line; checks= keeps its canonical vocabulary.
    # The test path captures the runner's output: vitest/jest exit 1 with
    # "No test files found" on an empty suite, which must be a YELLOW cap
    # (uncounted), not RED. Typecheck still goes through run() unchanged.
    js_script() {
      local kind=$1 name=$2 out rc
      if [[ $kind != test ]]; then
        if [[ $PM == yarn ]]; then run "$kind" yarn "$name"
        else run "$kind" "$PM" run "$name"; fi
        return
      fi
      if [[ $PM == yarn ]]; then set -- yarn "$name"
      else set -- "$PM" run "$name"; fi
      echo "[gate] $*"
      out=$(guard "$@" 2>&1)
      rc=$?
      printf '%s\n' "$out"
      if [[ -n $WATCHDOG && $rc -eq 124 ]]; then
        echo "[gate] TIMEOUT after ${GATE_TIMEOUT}s at '$*'" >&2
        exit 4
      fi
      if [[ $rc -ne 0 ]]; then
        # Empty-suite cap: only a runner empty-message *line* (vitest/jest
        # shape), never a mid-line substring in a real failure. A failing suite
        # whose log happens to contain "No tests found" in fixture names or
        # assertion text must stay RED.
        if printf '%s\n' "$out" | grep -qiE \
            '^[[:space:]]*(No test files found|No tests found|did not find any tests)\b' \
          && ! printf '%s\n' "$out" | grep -qiE \
            '(^|[[:space:]])(FAIL|Failed|AssertionError|Expected )|(^|[[:space:]])(●|✕|×)[[:space:]]|[1-9][0-9]* (failed|failing)\b'; then
          uncounted_suite js "no test files found (exit $rc)"
          return 0
        fi
        echo "[gate] RED at '$*'" >&2
        exit 1
      fi
      ran_test=1
    }

    # js_typecheck_script — the first of the accepted spellings the project
    # actually defines, in a single node pass. Projects name this script freely
    # ('type-check', 'check-types'), and refusing anything but the canonical
    # spelling made a fully covered repo look uncheckable. Exactly one script
    # runs: the first name the project defines wins, the rest are ignored, so
    # nothing runs or counts twice.
    # 'tsc' as a bare name usually means an emitting compile ("tsc": "tsc -p ."),
    # which would drop .js/.d.ts/.tsbuildinfo beside the sources of the tree
    # being judged, right before phase 1.3 stages pathspecs of that step
    # — and the documented rollback ('git restore --staged --worktree .') cannot
    # remove untracked files. It is therefore NOT an alias by name alone. The
    # one exception is when the script value itself carries --noEmit as a real
    # shell word (after stripping # / // comments): that is a check, not a
    # build, and counts. A trailing comment like `# use --noEmit in CI` must
    # NOT promote an emitting compile.
    # Echoes the script name, or nothing when the manifest declares none.
    js_typecheck_script() {
      node -e 'var s = require("./package.json").scripts || {};
var names = ["typecheck", "type-check", "check-types"];
var found = "";
for (var i = 0; i < names.length; i++) {
  if (s[names[i]]) { found = names[i]; break; }
}
if (!found && s.tsc) {
  var body = String(s.tsc).replace(/#.*/g, "").replace(/\/\/.*/g, "");
  if (/(?:^|[\s"'"'"'=])--noEmit(?:[\s"'"'"']|$)/.test(body)) found = "tsc";
}
if (found) console.log(found);' 2>/dev/null
    }

    # js_test_script — decides which script stands for the *whole* suite.
    # A plain 'test' always wins. Failing that, a 'test:*' script counts as the
    # canonical test only when it is the sole candidate in the manifest: a repo
    # with 'test:unit' and 'test:e2e' would otherwise report checks=typecheck,test
    # — GREEN, which unlocks dead-export deletion and phases 2 and 3 — on a net
    # where half the suite never ran. A slice declared with an empty command
    # still counts towards that cardinality: dropping it would turn the same two
    # halves into a lone slice and hand back the GREEN this rule exists to deny.
    # A watch/interactive slice is not a candidate at all: it never exits, so
    # running it as the gate's test can only ever end at the watchdog — 900s of
    # stall for an exit 4 that reads as "the safety net could not be measured".
    # 'watch', 'ui' and 'debug' are matched as whole segments of the name, so
    # 'test:watch:all' and 'test:ui:headed' are caught too and 'test:watchdog'
    # is not. Not running one and not counting one are two different questions,
    # though: 'watch' and 'debug' name a *mode* of the suite — the same tests,
    # started so they never exit — so they do not split it. 'ui' is not a mode
    # word: 'vitest --ui' never exits either, but 'test:ui' is just as often a
    # scope of its own that runs once, and the gate cannot tell. So it neither
    # runs it nor lets it vanish from the count: a lone 'test:unit' beside a
    # 'test:ui' is half a net, and half a net announced GREEN is the one thing
    # this rule exists to deny. Slices are still listed in the report, so the
    # cap is explained instead of silent. Same reasoning as the 'tsc' exclusion
    # above: a name that means "not a check" is not promoted to one.
    # The exact npm-init placeholder ('echo "Error: no test specified" && exit 1')
    # is recognised by value and reported as 'placeholder:test': running it would
    # only ever produce RED for a project that has never defined a suite.
    # Echoes 'run:<name>'; 'placeholder:test'; 'partial:<names>' when two or
    # more slices split the suite; 'watch:<names>' when no slice can be run at
    # all; nothing at all when the manifest declares no test script.
    js_test_script() {
      node -e 'var s = require("./package.json").scripts || {};
var npmPlaceholder = "echo \u0022Error: no test specified\u0022 && exit 1";
if (s.test === npmPlaceholder) { console.log("placeholder:test"); }
else if (s.test) { console.log("run:test"); }
else {
  var p = Object.keys(s).filter(function (k) { return k.indexOf("test:") === 0; });
  var slices = p.filter(function (k) { return !/(^|:)(watch|debug)(:|$)/.test(k); });
  var runnable = slices.filter(function (k) { return !/(^|:)ui(:|$)/.test(k); });
  if (slices.length === 1 && runnable.length === 1) console.log("run:" + runnable[0]);
  else if (slices.length > 1) console.log("partial:" + slices.join(" "));
  else if (p.length > 0) console.log("watch:" + p.join(" "));
}' 2>/dev/null
    }

    # A node failure on either lookup used to be a fully silent path: the empty
    # answer is indistinguishable from "this manifest declares no such script",
    # and the run would cap at YELLOW without a word about why. Both lookups
    # report it the same way now.
    if ! js_tc=$(js_typecheck_script); then
      echo "[gate] package.json scripts unreadable — JS/TS typecheck skipped" >&2
      incomplete=1
    elif [[ -n $js_tc ]]; then
      js_script typecheck "$js_tc"
    fi

    if ! js_test=$(js_test_script); then
      echo "[gate] package.json scripts unreadable — JS/TS test check skipped" >&2
      incomplete=1
    else
      case $js_test in
        run:*)
          js_script test "${js_test#run:}" ;;
        placeholder:*)
          uncounted_suite js "npm init placeholder test script" \
                   "replace scripts.test with a real suite" ;;
        partial:*)
          uncounted_suite js "no 'test' script; test:* slices found (${js_test#partial:})" \
                   "none of them stands for the whole suite; run them by hand" ;;
        watch:*)
          # Not "only watch mode": a lone 'test:ui' lands here too, and it may
          # well be a suite that runs once — the gate declines it because it
          # cannot tell, not because it knows the script hangs.
          uncounted_suite js "no 'test' script; no slice the gate will run (${js_test#watch:})" \
                   "watch mode never exits and a 'ui' slice may not either; add a script that runs the suite once" ;;
        *)
          uncounted_suite js "no 'test' script in package.json" ;;
      esac
    fi
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
      uncounted_suite go "no *_test.go found"
    fi
  else missing go.mod go; fi
fi

# --- Rust (Cargo.toml) ---
if [[ -f Cargo.toml ]]; then
  if command -v cargo >/dev/null; then
    run typecheck cargo check --all-targets --quiet
    # 'cargo test' on a crate with no test exits 0 reporting "0 passed" — the
    # same trap as 'go test'. A Rust test is either an integration file under
    # tests/ or a #[test]/#[cfg(test)] item in the sources; target/ and vendor/ are
    # output and never evidence. /dev/null keeps grep off stdin when the scan
    # comes up empty, and head -1 is what makes the result the whole scan's,
    # not the last xargs batch's.
    rust_tests=$(find . -name '*.rs' -path '*/tests/*' -not -path './target/*' \
        -not -path './vendor/*' \
                   -print -quit 2>/dev/null)
    if [[ -z $rust_tests ]]; then
      rust_tests=$(find . -name '*.rs' -not -path './target/*' \
        -not -path './vendor/*' -print0 2>/dev/null \
        | xargs -0 grep -lE '#\[test\]|#\[cfg\(test\)\]' /dev/null 2>/dev/null | head -1)
    fi
    if [[ -n $rust_tests ]]; then
      run test cargo test --quiet
    else
      uncounted_suite rust "no #[test] or tests/*.rs found"
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
  # A cap only means something where there is Python to clean. requirements.txt
  # is the loosest stack marker in this script — a docs build, a pre-commit pin,
  # a deploy helper — and capping on it alone drags an otherwise green JS or Go
  # repo down to YELLOW forever, for a "stack" that is one pip file. Same
  # evidence rule as Go and Rust: a source file, not a manifest.
  # Pruned, not filtered: a virtualenv holds thousands of .py files that are
  # someone else's, and descending into it to reject them costs the walk anyway.
  elif [[ -n $(find . \( -name .venv -o -name venv -o -name node_modules \
        -o -name .git \) -prune -o -name '*.py' -print -quit 2>/dev/null) ]]; then
    uncounted_suite python "no pytest config and no tests/ directory"
  fi
fi

# --- JVM (pom.xml and/or build.gradle — hybrid repos run both) ---
# 'mvn test' and 'gradle test' on a project with no test source exit 0 having
# run nothing — the same trap as 'go test' on a repo with no _test.go, except
# that 'run both' has already counted 'test' by the time it shows. Both runners
# take the standard layout, so a src/test directory is the evidence; without one
# the run is capped and can no longer be announced GREEN. target/, build/ and a
# vendored node_modules are output or someone else's code, never evidence, and
# they are pruned rather than filtered so the walk does not enter them at all.
jvm_ran=0
if [[ -f pom.xml ]]; then
  if [[ -x ./mvnw ]]; then run both ./mvnw -q test; jvm_ran=1
  elif command -v mvn >/dev/null; then run both mvn -q test; jvm_ran=1
  else missing pom.xml mvn; fi
fi
if [[ -f build.gradle || -f build.gradle.kts ]]; then
  if [[ -x ./gradlew ]]; then run both ./gradlew test; jvm_ran=1
  elif command -v gradle >/dev/null; then run both gradle test; jvm_ran=1
  else missing build.gradle gradle; fi
fi
if [[ $jvm_ran -eq 1 ]] && [[ -z $(find . \( -name target -o -name build \
      -o -name node_modules -o -name .git \) -prune -o -type d -path '*/src/test' \
      -print -quit 2>/dev/null) ]]; then
  uncounted_suite jvm "no src/test directory found"
fi

# --- Ruby (Gemfile) ---
if [[ -f Gemfile ]]; then
  if command -v bundle >/dev/null; then
    [[ -f sorbet/config ]] && run typecheck bundle exec srb tc
    # rspec and rake are two halves of a suite when both layouts exist — running
    # only one would announce GREEN with the other half never measured. Cap and
    # name both, same shape as JS test:* slices.
    if [[ -d spec && -f Rakefile && -d test ]]; then
      uncounted_suite ruby "both rspec (spec/) and rake test (Rakefile+test/) present" \
               "neither stands for the whole suite alone; run them by hand"
    elif [[ -d spec ]]; then run test bundle exec rspec
    elif [[ -f Rakefile && -d test ]]; then run test bundle exec rake test
    # Same evidence rule as Python: a Gemfile alone (fastlane, Jekyll, danger)
    # in a repo of another stack is not a Ruby stack without a suite, it is not
    # a Ruby stack. Capping on it would pin that repo below GREEN forever.
    elif [[ -n $(find . \( -name vendor -o -name node_modules -o -name .git \) \
          -prune -o \( -name '*.rb' -o -name '*.gemspec' \) \
          -print -quit 2>/dev/null) ]]; then
      uncounted_suite ruby "no spec/ and no Rakefile with test/"
    fi
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
dotnet_root_arg=""
if compgen -G '*.sln' >/dev/null || compgen -G '*.slnx' >/dev/null \
    || compgen -G '*.??proj' >/dev/null; then
  dotnet_targets=(.)
  # A root holding a solution and a project whose base names differ makes
  # 'dotnet build' with no argument fail with MSB1011 (more than one target) on
  # a repo that compiles. With exactly one solution there is nothing to choose:
  # name it. Two or more is a real decision and the gate abstains — a lone
  # .csproj is already unambiguous, so only sln/slnx count here.
  slns=()
  for f in *.sln *.slnx; do [[ -e $f ]] && slns+=("$f"); done
  if [[ ${#slns[@]} -eq 1 ]]; then dotnet_root_arg=${slns[0]}; fi
else
  for p in */*.??proj src/*/*.??proj; do
    [[ -e $p ]] && dotnet_targets+=("$p")
  done
fi
if [[ ${#dotnet_targets[@]} -gt 0 ]]; then
  if command -v dotnet >/dev/null; then
    dotnet_counted=0
    for target in "${dotnet_targets[@]}"; do
      # 'dotnet test' on a solution with no test project is a no-op that exits
      # 0 — same trap as 'go test' on a repo with no _test.go file.
      if [[ $target == . ]]; then
        has_tests=0
        # Walks the tree down to five levels instead of three fixed globs, so a
        # test project under src/App/Tests/ still counts. bin/obj/node_modules
        # and .git are pruned: a marker in build output is leftover, not the
        # repo's suite. /dev/null keeps grep from reading stdin when the scan
        # comes back empty, and head -1 closes the pipe on the first hit.
        if [[ -n $(find . -maxdepth 5 \
              \( -name bin -o -name obj -o -name node_modules -o -name .git \) \
              -prune -o -name '*.??proj' -print0 \
              | xargs -0 grep -lE "$DOTNET_TEST_MARKERS" /dev/null 2>/dev/null \
              | head -1) ]]; then
          has_tests=1
        fi
        # shellcheck disable=SC2086  # the :+ expansion is one argument or none
        run typecheck dotnet build --nologo -v minimal ${dotnet_root_arg:+"$dotnet_root_arg"}
        if [[ $has_tests -eq 1 ]]; then
          # shellcheck disable=SC2086  # same expansion, same reason
          run test dotnet test --nologo -v minimal ${dotnet_root_arg:+"$dotnet_root_arg"}
          dotnet_counted=1
        else uncounted_suite dotnet "no test project found"; fi
      else
        run typecheck dotnet build --nologo -v minimal "$target"
        if grep -qsE "$DOTNET_TEST_MARKERS" "$target"; then
          run test dotnet test --nologo -v minimal "$target"
          dotnet_counted=1
        else no_tests dotnet "no test project found in '$target'"; fi
      fi
    done
    # The per-project caps above really are per project: one project without a
    # test project next to one that has them is a covered stack. No project with
    # tests at all is not — that is the stack having no countable suite, and the
    # verdict has to hear about it, or another stack's 'test' carries this one
    # to GREEN and phase 1.3 deletes dead exports here with nothing to catch it.
    [[ $dotnet_counted -eq 0 ]] && uncounted=1
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
if [[ $checks == "typecheck,test" && $uncounted -eq 0 ]]; then
  echo "[gate] GREEN"
else
  # Two independent caps, and one run can hit both, so they are reported
  # together: an if/elif dropped whichever came second. The first is a short
  # checks= list. The second is that checks= can read typecheck,test in a
  # polyglot repo where one stack supplied the suite and another has none —
  # not GREEN either, because the stack without a suite would have its dead
  # exports deleted with nothing to catch the mistake.
  caps=""
  if [[ $checks != "typecheck,test" ]]; then
    caps="only ran: $checks (missing full typecheck+test)"
  fi
  if [[ $uncounted -eq 1 ]]; then
    caps="${caps:+$caps; }a detected stack has no countable suite (see 'test' not counted above)"
  fi
  echo "[gate] OK — $caps — YELLOW cap"
fi
