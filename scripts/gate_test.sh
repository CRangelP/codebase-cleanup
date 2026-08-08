#!/usr/bin/env bash
# Contract tests for gate.sh: exit codes 0/1/3, the checks= line and PARTIAL.
# Stacks whose toolchain is absent from the machine are covered by PATH stubs —
# the contract does not depend on the real toolchain, only on its exit code.
# Usage: gate_test.sh   (exit 0 = the whole matrix passed)
set -u

GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
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
case_run go-with-tests    0 "$TMP/go-with-tests" "$GO:$BASE"  "checks=typecheck,test" "GREEN"
case_run go-no-tests      0 "$TMP/go-no-tests"  "$GO:$BASE"   "checks=typecheck" "not counted" '!go test'
case_run dotnet-no-tests  0 "$TMP/dotnet-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'
case_run dotnet-sub-no-t  0 "$TMP/dotnet-sub-no-tests" "$OK:$BASE" "checks=typecheck" "not counted" '!dotnet test'

GATE_ENV="GATE_TIMEOUT=2"
case_run hang             4 "$TMP/go-hang"      "$HANG:$BASE" "TIMEOUT after 2s"
elapsed_lt hang-is-bounded 10

echo "----"
echo "$((total-failures))/$total cases passed"
[[ $failures -eq 0 ]]
