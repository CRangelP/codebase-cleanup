#!/usr/bin/env bash
# Cleanup gate: typecheck + tests, stopping at the first red.
# Detects the stack from the root manifest (there may be more than one; runs all).
# Requires bash (macOS 3.2 is fine). Usage: gate.sh [dir]
# Output: "[gate] checks=..." lists what actually ran (compiling counts as typecheck).
# Exit 0 = everything that ran passed · 1 = some check failed ·
# 3 = no runnable check OR a detected stack has no toolchain (PARTIAL) —
#     in both cases, run the gate manually: classify according to the stack.
set -uo pipefail

cd "${1:-.}" || exit 3
ran_typecheck=0
ran_test=0
incomplete=0

# run <typecheck|test|both> <cmd...>
run() {
  local kind=$1; shift
  echo "[gate] $*"
  if ! "$@"; then
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

# --- JS/TS (package.json) ---
if [[ -f package.json ]]; then
  if [[ -f bun.lock || -f bun.lockb ]]; then PM=bun
  elif [[ -f pnpm-lock.yaml ]]; then PM=pnpm
  elif [[ -f yarn.lock ]]; then PM=yarn
  else PM=npm
  fi
  if ! command -v node >/dev/null; then missing package.json node
  elif ! command -v "$PM" >/dev/null; then missing package.json "$PM"
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
    run test go test ./...
  else missing go.mod go; fi
fi

# --- Rust (Cargo.toml) ---
if [[ -f Cargo.toml ]]; then
  if command -v cargo >/dev/null; then
    run typecheck cargo check --all-targets --quiet
    run test cargo test --quiet
  else missing Cargo.toml cargo; fi
fi

# --- Python (pyproject.toml / setup.py / setup.cfg / requirements.txt) ---
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg || -f requirements.txt ]]; then
  if [[ -f mypy.ini || -f .mypy.ini ]] || grep -qs '^\[tool\.mypy\]' pyproject.toml \
      || grep -qs '^\[mypy\]' setup.cfg; then
    if command -v mypy >/dev/null; then run typecheck mypy .
    else missing config-mypy mypy; fi
  fi
  if [[ -f pyrightconfig.json ]]; then
    if command -v pyright >/dev/null; then run typecheck pyright
    else missing pyrightconfig.json pyright; fi
  fi
  if [[ -f pytest.ini || -d tests || -d test ]] || grep -qs '^\[tool\.pytest' pyproject.toml \
      || grep -qs '^\[tool:pytest\]' setup.cfg || grep -qs '^\[pytest\]' tox.ini; then
    if command -v pytest >/dev/null; then run test pytest -q
    else missing python-tests pytest; fi
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
      if [[ $target == . ]]; then
        run typecheck dotnet build --nologo -v minimal
        run test dotnet test --nologo -v minimal
      else
        run typecheck dotnet build --nologo -v minimal "$target"
        run test dotnet test --nologo -v minimal "$target"
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
