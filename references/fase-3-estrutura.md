# Fase 3 — Estrutura de pastas

## Diagnóstico

Antes de mover qualquer arquivo, produza:

1. **Mapa da estrutura atual** — profundidade, o que mora onde, o que não tem
   dono claro
2. **Dependências circulares** — do `cycles` do knip ou de `madge --circular`
3. **Módulos-deus** — diretórios que todo mundo importa
4. **Abstrações vazando** — detalhe interno de um módulo referenciado de fora
5. **Estrutura alvo** com justificativa por movimento
6. **Plano faseado** — ordem das movimentações, começando pelas de menor risco

## Escolher o padrão

Não existe estrutura universalmente certa. Existe estrutura consistente com o
que o projeto já é.

**Por feature (colocation)** — utils, estilos, testes e tipos moram no mesmo
diretório da lógica que servem. Escolha quando o projeto tem features com
fronteiras claras e o `utils/` global virou depósito.

O ganho real não é estético: `utils/` global é onde código morto se esconde por
anos, porque ninguém sabe quem chama o quê. Colocation transforma "isso está
morto?" numa pergunta local, respondível olhando um diretório.

**Por camada** (`controllers/`, `services/`, `repositories/`) — escolha quando
o projeto já é assim e é consistente. Migrar camada→feature num codebase grande
é um projeto próprio, não uma faxina; se o diagnóstico apontar isso, entregue
como recomendação e não execute sem sinal explícito.

**Convenção da linguagem** — Go, Rust, Python e Node têm layouts esperados
(`cmd/`, `internal/`, `src/`, `tests/`). Se o projeto não segue a convenção da
própria linguagem, esse é o primeiro alvo e o de melhor retorno: qualquer pessoa
nova entende sem explicação.

## Heurísticas

- Diretório com um arquivo só quase sempre não deveria ser diretório
- Profundidade acima de 4 níveis costuma indicar categoria inventada
- Nome genérico (`helpers`, `common`, `shared`, `misc`) é sinal de que ninguém
  soube onde pôr — investigue o conteúdo, ele raramente é coeso
- Arquivo cujo nome repete o diretório (`user/userService.ts`) indica
  redundância de nomenclatura, não de estrutura
- Se dois diretórios sempre mudam juntos no `git log`, provavelmente são um

## Execução

Uma pasta por commit. Sempre:

```bash
git mv src/utils/format.ts src/features/billing/format.ts
```

`git mv` preserva histórico. `rm` + `create` destrói o `git blame` daquele
arquivo — justamente a informação que alguém vai querer daqui a seis meses ao
perguntar "por que isso está assim".

**Prefira atualizar path aliases a reescrever imports.** Se o projeto usa
`@/features/*`, mover uma pasta pode ser uma linha no `tsconfig.json` em vez de
um diff de 3.000 linhas que ninguém consegue revisar.

Se reescrever imports for inevitável, faça em commit separado do movimento:

```
1. refactor: move billing to features/    (git mv puro)
2. refactor: update imports for billing   (só os imports)
```

Typecheck ao final de cada pasta. Falhou → `git restore --staged --worktree .`,
registra, próxima pasta.

## Não esquecer

Coisas que apontam para caminhos e quebram em silêncio quando pastas mudam:

- `tsconfig.json` (`paths`, `include`), `jsconfig.json`
- config de bundler (vite, webpack, rollup), `jest.config`, `vitest.config`
- `knip.json` — se você mudou a estrutura, os `entry`/`project` mudaram
- `.eslintrc` com `overrides` por diretório
- CI: caminhos em workflows, `Dockerfile`, `.dockerignore`
- `CODEOWNERS`
- imports dinâmicos com string montada em runtime — typecheck **não** pega
- `CLAUDE.md` e docs que descrevem a estrutura antiga

O último item é o mais esquecido e o mais caro: um `CLAUDE.md` descrevendo uma
estrutura que não existe mais faz todo agente futuro trabalhar com mapa errado.
Atualize no mesmo commit da movimentação.
