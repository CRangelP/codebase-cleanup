#!/usr/bin/env bash
# Testes de contrato do gate.sh: exit codes 0/1/3, linha checks= e PARCIAL.
# Stacks sem toolchain na máquina são cobertos por stubs no PATH — o contrato
# não depende do toolchain real, só do exit code dele.
# Uso: gate_test.sh   (exit 0 = matriz inteira passou)
set -u

GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
falhas=0
total=0

BASE="/usr/bin:/bin"

stub() { # stub <dir> <nome> <exit>
  mkdir -p "$1"
  printf '#!/bin/sh\nexit %s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

caso() { # caso <nome> <exit_esperado> <dir> <PATH|-> <padrao_grep...>
  local nome=$1 esperado=$2 dir=$3 caminho=$4; shift 4
  local out rc p ok=1
  if [[ $caminho == - ]]; then out=$(bash "$GATE" "$dir" 2>&1); rc=$?
  else out=$(PATH="$caminho" bash "$GATE" "$dir" 2>&1); rc=$?; fi
  [[ $rc -eq $esperado ]] || ok=0
  for p in "$@"; do grep -q "$p" <<<"$out" || ok=0; done
  total=$((total+1))
  if [[ $ok -eq 1 ]]; then echo "ok: $nome"
  else
    falhas=$((falhas+1))
    echo "FALHOU: $nome (exit=$rc, esperado=$esperado)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# fixtures -------------------------------------------------------------
mkdir -p "$TMP/vazio"

mkdir -p "$TMP/js-verde"
cat > "$TMP/js-verde/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 0"}}
EOF

mkdir -p "$TMP/js-so-test"
cat > "$TMP/js-so-test/package.json" <<'EOF'
{"name":"f","scripts":{"test":"node -e 0"}}
EOF

mkdir -p "$TMP/js-vermelho"
cat > "$TMP/js-vermelho/package.json" <<'EOF'
{"name":"f","scripts":{"typecheck":"node -e 0","test":"node -e 'process.exit(1)'"}}
EOF

mkdir -p "$TMP/poliglota/tests"
touch "$TMP/poliglota/pyproject.toml" "$TMP/poliglota/tests/test_x.py"
printf 'module f\n\ngo 1.21\n' > "$TMP/poliglota/go.mod"

mkdir -p "$TMP/dotnet-raiz" "$TMP/dotnet-sub/src/App"
touch "$TMP/dotnet-raiz/App.csproj" "$TMP/dotnet-sub/src/App/App.fsproj"

mkdir -p "$TMP/jvm-hibrido"
touch "$TMP/jvm-hibrido/pom.xml" "$TMP/jvm-hibrido/build.gradle"

mkdir -p "$TMP/py-setupcfg/test"
printf '[mypy]\n' > "$TMP/py-setupcfg/setup.cfg"
touch "$TMP/py-setupcfg/test/test_x.py"

# stubs ----------------------------------------------------------------
OK="$TMP/stubs-ok"; FAIL="$TMP/stubs-fail"
for t in pytest mypy dotnet mvn gradle; do stub "$OK" "$t" 0; done
stub "$FAIL" dotnet 1

# matriz ---------------------------------------------------------------
caso vazio            3 "$TMP/vazio"       -                    "nenhum check"
caso js-verde         0 "$TMP/js-verde"    -                    "checks=typecheck,test" "VERDE"
caso js-so-test       0 "$TMP/js-so-test"  -                    "checks=test" "AMARELO"
caso js-vermelho      1 "$TMP/js-vermelho" -                    "VERMELHO"
caso js-sem-node      3 "$TMP/js-verde"    "$BASE"              "ausente"
caso poliglota-parcial 3 "$TMP/poliglota"  "$OK:$BASE"          "checks=test" "PARCIAL"
caso dotnet-verde     0 "$TMP/dotnet-raiz" "$OK:$BASE"          "checks=typecheck,test" "VERDE"
caso dotnet-vermelho  1 "$TMP/dotnet-raiz" "$FAIL:$BASE"        "VERMELHO"
caso dotnet-subdir    0 "$TMP/dotnet-sub"  "$OK:$BASE"          "src/App/App.fsproj" "VERDE"
caso jvm-hibrido      0 "$TMP/jvm-hibrido" "$OK:$BASE"          "mvn -q test" "gradle test" "VERDE"
caso py-setupcfg      0 "$TMP/py-setupcfg" "$OK:$BASE"          "checks=typecheck,test" "VERDE"

echo "----"
echo "$((total-falhas))/$total casos passaram"
[[ $falhas -eq 0 ]]
