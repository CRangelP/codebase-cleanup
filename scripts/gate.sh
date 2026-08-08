#!/usr/bin/env bash
# Gate da faxina: typecheck + testes, parando no primeiro vermelho.
# Uso: gate.sh [dir]   (padrão: diretório atual)
# Exit 0 = VERDE · 1 = VERMELHO (algum script falhou) · 3 = sem package.json
# ou sem scripts typecheck/test (gate manual — classifique conforme o stack).
set -uo pipefail

cd "${1:-.}" || exit 3
if [[ ! -f package.json ]]; then
  echo "[gate] sem package.json — rode o gate do stack manualmente" >&2
  exit 3
fi

if [[ -f bun.lock || -f bun.lockb ]]; then RUN="bun run"
elif [[ -f pnpm-lock.yaml ]]; then RUN="pnpm run"
elif [[ -f yarn.lock ]]; then RUN="yarn"
else RUN="npm run"
fi

ran=0
for script in typecheck test; do
  if node -e "const s=require('./package.json').scripts||{};process.exit(s['$script']?0:1)" 2>/dev/null; then
    echo "[gate] $RUN $script"
    if ! $RUN "$script"; then
      echo "[gate] VERMELHO em '$script'" >&2
      exit 1
    fi
    ran=1
  fi
done

if [[ $ran -eq 0 ]]; then
  echo "[gate] package.json sem scripts 'typecheck' e 'test'" >&2
  exit 3
fi
echo "[gate] VERDE"
