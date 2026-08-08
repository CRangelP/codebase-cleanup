# Fase 1 em stacks não-JS/TS

O knip é só JS/TS. A lógica da fase 1 é idêntica em qualquer stack — o que muda
é o ferramental e, importante, a **confiabilidade** dele.

Detecte o stack pelo manifesto: `package.json`, `pyproject.toml`/`requirements.txt`,
`go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Gemfile`, `*.csproj`.

## Python

```bash
pip install vulture pip-audit ruff --quiet
vulture src/ --min-confidence 80     # código morto
pip-audit                            # CVEs
ruff check --select F401,F841 src/   # imports e variáveis não usados
deptry .                             # deps não usadas / não declaradas
```

**Calibre o `--min-confidence`.** Abaixo de 80 o vulture vira ruído. Mesmo em
100 ele erra com: Django/Flask (views, signals, management commands), pytest
(fixtures, conftest), Celery tasks, Pydantic validators, `__all__`, e qualquer
coisa acessada por `getattr`.

Vulture é análise sintática, não grafo de módulos. É **substancialmente menos
confiável que o knip** — trate a saída como lista de candidatos a investigar,
nunca como lista de deleção. Em nível VERDE, ainda assim confirme antes de
deletar em Python.

Whitelist para o que ele erra consistentemente:

```bash
vulture src/ whitelist.py
```

## Go

```bash
govulncheck ./...            # CVEs, com análise de alcançabilidade
staticcheck ./...            # U1000 = não usado
golangci-lint run            # agregador
go mod tidy                  # deps
deadcode ./...               # oficial, x/tools
```

`deadcode` do x/tools é o mais próximo do knip conceitualmente — parte dos
entry points e caminha o grafo de chamadas. Prefira ele a `staticcheck U1000`
para arquivos órfãos.

Cuidado com identificadores exportados: em pacote de biblioteca, exportado sem
uso interno é a interface pública, não código morto.

## Rust

```bash
cargo audit                  # CVEs
cargo udeps --all-targets    # deps não usadas (precisa nightly)
cargo machete                # deps não usadas, mais rápido, menos preciso
cargo +nightly udeps
```

O compilador já reporta `dead_code` — `#![warn(dead_code)]` e ler os warnings
cobre a maior parte. Cuidado com `#[cfg(feature = "...")]`: código atrás de
feature desligada aparece como morto.

## Java / Kotlin

```bash
mvn dependency:analyze              # deps declaradas e não usadas
./gradlew dependencies
```

Reflexão, DI (Spring), anotações e SPI tornam análise estática pouco confiável.
Em stack JVM, mantenha-se em nível AMARELO por padrão: remova só dependências
declaradas e não usadas, e trate código como diagnóstico.

## Ruby

```bash
bundle exec debride app/     # código possivelmente morto
bundle-audit check           # CVEs
```

Metaprogramação torna qualquer resultado suspeito. Diagnóstico apenas.

---

## Regra geral

A confiança na deleção automática segue a qualidade do grafo:

| Stack | Ferramenta principal | Deleção autônoma |
|---|---|---|
| JS/TS | knip (grafo de módulos) | sim, em VERDE |
| Go | deadcode (grafo de chamadas) | sim, em VERDE |
| Rust | compilador + udeps | sim para deps, confirmar código |
| Python | vulture (sintático) | confirmar sempre |
| JVM / Ruby | — | diagnóstico apenas |

Quando a ferramenta não constrói grafo de alcançabilidade, ela não sabe o que
está morto — ela sabe o que *parece* morto. A diferença importa quando o
comando é deletar sem perguntar.

As fases 2 e 3 são independentes de stack e valem para qualquer linguagem.
