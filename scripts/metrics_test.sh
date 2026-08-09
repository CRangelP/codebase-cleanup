#!/usr/bin/env bash
# Executable proof of metrics.sh. Each case builds its own throwaway tree inside a
# mktemp -d, so the suite never reads or writes anything outside of it -- in particular
# it never measures the real repository.
# Usage: metrics_test.sh   (exit 0 = every case passed)
set -u

METRICS="$(cd "$(dirname "$0")" && pwd)/metrics.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0
total=0

fixture() { # fixture <name> — empty dir inside TMP, echoes the path
  mkdir -p "$TMP/$1"
  echo "$TMP/$1"
}

fn_of() { # fn_of <lines> — a JS function exactly <lines> long, on stdout
  n=$1
  echo "function big() {"
  i=2
  while [[ $i -lt $n ]]; do
    echo "  const v$i = $i;"
    i=$((i + 1))
  done
  echo "}"
}

metric_is() { # metric_is <label> <dir> <key> <expected> — one "[metrics] key=" value
  total=$((total + 1))
  out=$(bash "$METRICS" "$2" 2>/dev/null)
  got=$(printf '%s\n' "$out" | sed -n "s/^\[metrics\] $3=\([^ ]*\).*/\1/p")
  if [[ "$got" == "$4" ]]; then
    echo "ok: $1"
  else
    failures=$((failures + 1))
    echo "FAILED: $1"
    echo "    $3 is '${got:-<missing>}' (wanted '$4')"
  fi
}

has_line() { # has_line <label> <dir> <exact "[metrics] ..." line> — whole line, spaces and all
  total=$((total + 1))
  out=$(bash "$METRICS" "$2" 2>/dev/null)
  if printf '%s\n' "$out" | grep -Fqx "$3"; then
    echo "ok: $1"
  else
    failures=$((failures + 1))
    echo "FAILED: $1"
    echo "    no line '$3' in: $(printf '%s' "$out" | tr '\n' '|')"
  fi
}

exits_with() { # exits_with <label> <dir> <code>
  total=$((total + 1))
  STDERR=$(bash "$METRICS" "$2" 2>&1 >/dev/null)
  rc=$?
  if [[ $rc -eq $3 ]]; then
    echo "ok: $1"
  else
    failures=$((failures + 1))
    echo "FAILED: $1"
    echo "    exit $rc (wanted $3), stderr: ${STDERR:-<empty>}"
  fi
}

# --- bad path and nothing to measure: the two non-zero exits, and nothing else ------

exits_with "missing directory exits 2" "$TMP/does-not-exist" 2

only_prose=$(fixture prose)
echo "# readme" > "$only_prose/README.md"
echo "notes" > "$only_prose/notes.txt"
exits_with "directory with no recognized source exits 3" "$only_prose" 3

js=$(fixture js)
cat > "$js/a.js" <<'EOF'
function alpha() {
  const a = 1;
  const b = 2;
  return a + b;
}
EOF
exits_with "a measurable directory exits 0" "$js" 0

# --- the measurements themselves ---------------------------------------------------

metric_is "known function measures maxfn" "$js" maxfn 5
has_line "known function reports file:line" "$js" "[metrics] maxfn=5 at=a.js:1 (approx)"
metric_is "blank and comment lines are not loc" "$js" loc 5

big=$(fixture big)
fn_of 60 > "$big/big.js"
metric_is "60-line function is over the limit" "$big" fn_over_50 1
metric_is "60-line function measures 60" "$big" maxfn 60

small=$(fixture small)
fn_of 50 > "$small/small.js"
metric_is "exactly 50 lines is not over the limit" "$small" fn_over_50 0

nest=$(fixture nest)
cat > "$nest/n.js" <<'EOF'
function deep() {
  if (a) {
    while (b) {
      x();
    }
  }
}
EOF
metric_is "known nesting measures maxnest" "$nest" maxnest 3

loose=$(fixture loose)
cat > "$loose/t.ts" <<'EOF'
// @ts-ignore
const a: any = 1;
const b = c as any;
let d: any[] = [];
function f(x: any) { return x; }
// @ts-expect-error
const e = 2;
EOF
metric_is "loose types are counted once each" "$loose" loose_types 6

marks=$(fixture marks)
cat > "$marks/m.js" <<'EOF'
// TODO: one
// FIXME: two
const x = 1; // HACK: three
// XXX: four
const y = 2;
EOF
metric_is "todo markers are counted" "$marks" todo 4

# --- non-JS stacks: Python (indentation) and Go (braces) ---------------------------

py=$(fixture py)
cat > "$py/p.py" <<'EOF'
def outer():
    for i in range(3):
        if i:
            print(i)


def small():
    return 1
EOF
metric_is "python def measures maxfn by dedent" "$py" maxfn 4
metric_is "python nesting measures by indentation" "$py" maxnest 3
metric_is "python comment lines are not loc" "$py" loc 6

pyignore=$(fixture pyignore)
cat > "$pyignore/i.py" <<'EOF'
import os  # type: ignore
x = os.sep  # type: ignore
EOF
metric_is "python type: ignore is a loose type" "$pyignore" loose_types 2

go=$(fixture go)
printf 'package main\n\nfunc add(a int, b int) int {\n\treturn a + b\n}\n\ntype T interface{}\n\nfunc main() {\n\tvar x interface{} = 1\n\t_ = x\n\t// TODO: something\n}\n' > "$go/g.go"
metric_is "go func measures maxfn" "$go" maxfn 5
metric_is "go interface{} is a loose type" "$go" loose_types 2
metric_is "go todo is counted" "$go" todo 1

# --- the hostile inputs -------------------------------------------------------------

spaced=$(fixture spaced)
mkdir -p "$spaced/a dir"
fn_of 6 > "$spaced/a dir/weird name.js"
has_line "a file name with spaces is measured" "$spaced" "[metrics] maxfn=6 at=a dir/weird name.js:1 (approx)"
metric_is "a file name with spaces is counted once" "$spaced" files 1

ignored=$(fixture ignored)
mkdir -p "$ignored/src" "$ignored/node_modules/pkg" "$ignored/dist" "$ignored/.git"
cat > "$ignored/src/keep.js" <<'EOF'
function keep() {
  return 1;
}
EOF
fn_of 80 > "$ignored/node_modules/pkg/vendored.js"
fn_of 90 > "$ignored/dist/bundle.js"
fn_of 70 > "$ignored/.git/hook.js"
metric_is "node_modules and dist are not sources" "$ignored" files 1
metric_is "excluded trees do not move maxfn" "$ignored" maxfn 3
metric_is "excluded trees do not move fn_over_50" "$ignored" fn_over_50 0

# --- the property the whole script exists for: two runs must diff to nothing --------

total=$((total + 1))
mixed=$(fixture mixed)
mkdir -p "$mixed/deep/er"
cp "$js/a.js" "$mixed/a.js"
cp "$py/p.py" "$mixed/deep/p.py"
cp "$go/g.go" "$mixed/deep/er/g.go"
fn_of 12 > "$mixed/deep/er/twelve.js"
bash "$METRICS" "$mixed" > "$TMP/before" 2>/dev/null
bash "$METRICS" "$mixed" > "$TMP/after" 2>/dev/null
if cmp -s "$TMP/before" "$TMP/after"; then
  echo "ok: two runs on the same input are byte-for-byte equal"
else
  failures=$((failures + 1))
  echo "FAILED: two runs on the same input are byte-for-byte equal"
  echo "    diff: $(diff "$TMP/before" "$TMP/after" | tr '\n' ' ')"
fi

# A run from inside the tree and a run naming the tree must agree: the report is a
# delta between two runs, and the caller should not have to stand in the same place.
total=$((total + 1))
( cd "$mixed" && bash "$METRICS" ) > "$TMP/inside" 2>/dev/null
if cmp -s "$TMP/before" "$TMP/inside"; then
  echo "ok: default argument measures the current directory the same way"
else
  failures=$((failures + 1))
  echo "FAILED: default argument measures the current directory the same way"
  echo "    diff: $(diff "$TMP/before" "$TMP/inside" | tr '\n' ' ')"
fi

# Every metric named in the header must actually be printed, in one stable order:
# the report diffs these lines, so a silently missing line is a silently wrong delta.
total=$((total + 1))
got_keys=$(sed -n 's/^\[metrics\] \([a-z_0-9]*\)=.*/\1/p' "$TMP/before" | tr '\n' ' ')
want_keys="files loc maxfn fn_over_50 maxnest loose_types todo "
if [[ "$got_keys" == "$want_keys" ]]; then
  echo "ok: every metric is printed in a fixed order"
else
  failures=$((failures + 1))
  echo "FAILED: every metric is printed in a fixed order"
  echo "    got '$got_keys' (wanted '$want_keys')"
fi

# The approximations must stay labelled. If someone drops the marker, the number starts
# looking like a fact.
total=$((total + 1))
approx=$(grep -c '(approx)' "$TMP/before")
if [[ $approx -eq 3 ]]; then
  echo "ok: heuristic metrics stay marked as approximations"
else
  failures=$((failures + 1))
  echo "FAILED: heuristic metrics stay marked as approximations"
  echo "    $approx lines marked (approx), wanted 3"
fi

echo "$((total-failures))/$total cases passed"
[[ $failures -eq 0 ]] || exit 1
