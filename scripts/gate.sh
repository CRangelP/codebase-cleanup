#!/usr/bin/env bash
# Gate da faxina: typecheck + testes, parando no primeiro vermelho.
# Detecta o stack pelo manifesto na raiz (pode haver mais de um; roda todos).
# Requer bash (o 3.2 do macOS serve). Uso: gate.sh [dir]
# Saída: "[gate] checks=..." lista o que rodou (compilar conta como typecheck).
# Exit 0 = tudo que rodou passou · 1 = algum check falhou ·
# 3 = nenhum check executável OU stack detectado sem toolchain (PARCIAL) —
#     nos dois casos, gate manual: classifique conforme o stack.
set -uo pipefail

cd "${1:-.}" || exit 3
ran_typecheck=0
ran_test=0
incompleto=0

# run <typecheck|test|both> <cmd...>
run() {
  local tipo=$1; shift
  echo "[gate] $*"
  if ! "$@"; then
    echo "[gate] VERMELHO em '$*'" >&2
    exit 1
  fi
  case $tipo in
    typecheck) ran_typecheck=1 ;;
    test) ran_test=1 ;;
    both) ran_typecheck=1; ran_test=1 ;;
  esac
}

falta() {
  echo "[gate] $1 presente mas toolchain '$2' ausente — gate manual" >&2
  incompleto=1
}

# --- JS/TS (package.json) ---
if [[ -f package.json ]]; then
  if [[ -f bun.lock || -f bun.lockb ]]; then PM=bun
  elif [[ -f pnpm-lock.yaml ]]; then PM=pnpm
  elif [[ -f yarn.lock ]]; then PM=yarn
  else PM=npm
  fi
  if ! command -v node >/dev/null; then falta package.json node
  elif ! command -v "$PM" >/dev/null; then falta package.json "$PM"
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
  else falta go.mod go; fi
fi

# --- Rust (Cargo.toml) ---
if [[ -f Cargo.toml ]]; then
  if command -v cargo >/dev/null; then
    run typecheck cargo check --all-targets --quiet
    run test cargo test --quiet
  else falta Cargo.toml cargo; fi
fi

# --- Python (pyproject.toml / setup.py / setup.cfg / requirements.txt) ---
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg || -f requirements.txt ]]; then
  if [[ -f mypy.ini || -f .mypy.ini ]] || grep -qs '^\[tool\.mypy\]' pyproject.toml \
      || grep -qs '^\[mypy\]' setup.cfg; then
    if command -v mypy >/dev/null; then run typecheck mypy .
    else falta config-mypy mypy; fi
  fi
  if [[ -f pyrightconfig.json ]]; then
    if command -v pyright >/dev/null; then run typecheck pyright
    else falta pyrightconfig.json pyright; fi
  fi
  if [[ -f pytest.ini || -d tests || -d test ]] || grep -qs '^\[tool\.pytest' pyproject.toml \
      || grep -qs '^\[tool:pytest\]' setup.cfg || grep -qs '^\[pytest\]' tox.ini; then
    if command -v pytest >/dev/null; then run test pytest -q
    else falta testes-python pytest; fi
  fi
fi

# --- JVM (pom.xml e/ou build.gradle — repos híbridos rodam os dois) ---
if [[ -f pom.xml ]]; then
  if [[ -x ./mvnw ]]; then run both ./mvnw -q test
  elif command -v mvn >/dev/null; then run both mvn -q test
  else falta pom.xml mvn; fi
fi
if [[ -f build.gradle || -f build.gradle.kts ]]; then
  if [[ -x ./gradlew ]]; then run both ./gradlew test
  elif command -v gradle >/dev/null; then run both gradle test
  else falta build.gradle gradle; fi
fi

# --- Ruby (Gemfile) ---
if [[ -f Gemfile ]]; then
  if command -v bundle >/dev/null; then
    [[ -f sorbet/config ]] && run typecheck bundle exec srb tc
    if [[ -d spec ]]; then run test bundle exec rspec
    elif [[ -f Rakefile && -d test ]]; then run test bundle exec rake test; fi
  else falta Gemfile bundler; fi
fi

# --- .NET (sln/slnx/csproj/fsproj/vbproj na raiz, ou projetos um nível abaixo) ---
dotnet_alvos=()
if compgen -G '*.sln' >/dev/null || compgen -G '*.slnx' >/dev/null \
    || compgen -G '*.??proj' >/dev/null; then
  dotnet_alvos=(.)
else
  for p in */*.??proj src/*/*.??proj; do
    [[ -e $p ]] && dotnet_alvos+=("$p")
  done
fi
if [[ ${#dotnet_alvos[@]} -gt 0 ]]; then
  if command -v dotnet >/dev/null; then
    for alvo in "${dotnet_alvos[@]}"; do
      if [[ $alvo == . ]]; then
        run typecheck dotnet build --nologo -v minimal
        run test dotnet test --nologo -v minimal
      else
        run typecheck dotnet build --nologo -v minimal "$alvo"
        run test dotnet test --nologo -v minimal "$alvo"
      fi
    done
  else falta 'sln/csproj' dotnet; fi
fi

# --- Veredito ---
checks=""
[[ $ran_typecheck -eq 1 ]] && checks="typecheck"
[[ $ran_test -eq 1 ]] && checks="${checks:+$checks,}test"

if [[ -z $checks ]]; then
  if [[ $incompleto -eq 1 ]]; then
    echo "[gate] PARCIAL — stack detectado sem toolchain; gate manual" >&2
  else
    echo "[gate] nenhum check detectado — rode o gate do stack manualmente" >&2
  fi
  exit 3
fi

echo "[gate] checks=$checks"
if [[ $incompleto -eq 1 ]]; then
  echo "[gate] PARCIAL — algum stack detectado ficou sem toolchain; complete o gate manualmente" >&2
  exit 3
fi
if [[ $checks == "typecheck,test" ]]; then
  echo "[gate] VERDE"
else
  echo "[gate] OK — rodou só: $checks (sem typecheck+test completos, nível máximo AMARELO)"
fi
