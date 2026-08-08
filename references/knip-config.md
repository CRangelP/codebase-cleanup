# Configuração do knip

Leia antes de escrever `knip.json`. Só se aplica a JS/TS.

Este guia foi escrito contra o knip v6. Confira a major instalada com
`npx knip --version`; se for outra, valide contra a doc oficial (knip.dev) o
que divergir — em especial o schema, a detecção de ciclos e nomes de opção.
Ajuste a versão do `$schema` abaixo para a major em uso.

## Índice
- [Ordem de trabalho](#ordem-de-trabalho)
- [Esqueleto](#esqueleto)
- [Aliases de import](#aliases-de-import)
- [Modo produção](#modo-produção)
- [Quando precisar suprimir algo](#quando-precisar-suprimir-algo)
- [Plugins](#plugins)
- [Monorepo](#monorepo)
- [Detecção de ciclos](#detecção-de-ciclos)
- [Armadilhas](#armadilhas)

## Ordem de trabalho

1. `npx knip` sem config nenhuma
2. Resolver **todos** os configuration hints
3. Só então escrever/ajustar `knip.json`
4. Repetir 2–3 até hints zerarem
5. `npx knip --production --reporter json > knip-report.json`

A mentalidade certa: quando o knip reporta algo inesperado, ele está dizendo a
verdade sobre o grafo de módulos — não conseguiu alcançar aquele código a partir
de um entry. Resultado surpreendente é achado real ou lacuna de configuração,
quase nunca falso positivo para silenciar.

## Esqueleto

```jsonc
{
  "$schema": "https://unpkg.com/knip@6/schema.json",
  "entry": ["src/main.ts", "scripts/*.ts", "!scripts/scratch.ts"],
  "project": ["src/**/*.{ts,tsx}", "scripts/**/*.ts"]
}
```

- `entry` — raízes do grafo, de onde a caminhada começa
- `project` — universo de arquivos considerados
- arquivo morto = está em `project` mas não é alcançável a partir de `entry`
- prefixo `!` nega o padrão
- sufixo `!` marca o padrão como exclusivo de production mode

Use `knip.jsonc` (schema `schema-jsonc.json`) se quiser comentários — vale a
pena para documentar por que cada entry exótico existe.

## Aliases de import

Maior fonte isolada de falso positivo em massa. O knip inclui
`compilerOptions.paths` do tsconfig automaticamente, mas **não** aliases de
webpack, Babel, vite ou jest moduleNameMapper. Declare na mão:

```jsonc
{
  "paths": {
    "@lib": ["./lib/index.ts"],
    "@lib/*": ["./lib/*"]
  }
}
```

Semântica igual à do TypeScript: valores são arrays de caminhos relativos, e
padrões sem `*` são match exato. Cada workspace pode ter seus próprios `paths`.

## Modo produção

```bash
npx knip --production
```

Exclui testes e devDependencies automaticamente. É o que separa "vivo" de "vivo
só para os testes" — código que só existe para satisfazer a suíte é dívida, não
funcionalidade.

**Nunca** tente obter o mesmo efeito com `ignore` em `**/*.test.ts`.

## Quando precisar suprimir algo

Evite `ignore`: ele não exclui da análise, só suprime o report, criando ponto
cego. Sempre existe opção mais cirúrgica:

| Situação | Opção |
|---|---|
| Código gerado, não deve contar como arquivo morto | `ignoreFiles` |
| Dep usada de forma invisível ao grafo | `ignoreDependencies` |
| Só certos tipos de issue em arquivos gerados | `ignoreIssues` |
| Export usado apenas dentro do próprio arquivo | `ignoreExportsUsedInFile` |
| Binário chamado em script, sem pacote correspondente | `ignoreBinaries` |
| Membro de enum/namespace | `ignoreMembers` |
| Especificador que não resolve | `ignoreUnresolved` |
| Testes atrapalhando | `--production` (nunca `ignore`) |

`ignoreFiles` difere de `ignore` por afetar só a seção de arquivos não usados —
o arquivo continua analisado para exports, deps e imports não resolvidos. É
quase sempre o que se queria ao pensar em `ignore`.

```jsonc
{
  "ignoreFiles": ["src/generated/**", "fixtures/**"],
  "ignoreDependencies": ["hidden-package", "@org/.+"],
  "ignoreIssues": {
    "src/generated/**": ["exports", "types"]
  },
  "ignoreExportsUsedInFile": { "interface": true, "type": true }
}
```

`ignoreDependencies`, `ignoreBinaries`, `ignoreUnresolved` e `ignoreMembers`
aceitam regex. Regex de verdade (não string) só em config dinâmica `.ts`.

Alternativa a suprimir por padrão: tags JSDoc.

```ts
/** @internal */
export const x = 1;
```

```jsonc
{ "tags": ["-internal"] }
```

## Plugins

```jsonc
{
  "playwright": true,                    // força habilitar
  "webpack": false,                      // desabilita
  "mocha": {
    "config": "config/mocha.config.js",
    "entry": ["**/*.spec.js"]
  }
}
```

Raramente é necessário sobrescrever `entry` de plugin — eles já leem os padrões
customizados da configuração da própria ferramenta. Configuração de plugin
funciona em raiz e por workspace, e um nível pode desabilitar o que o outro
habilitou.

## Monorepo

Pegadinha que quebra silenciosamente: **num projeto com workspaces, `entry` e
`project` no nível raiz são ignorados.** Use o workspace `"."`.

```jsonc
{
  "workspaces": {
    ".":            { "entry": ["scripts/*.ts"], "project": ["scripts/**/*.ts"] },
    "packages/*":   { "entry": ["src/index.ts"], "project": ["src/**/*.ts"] },
    "packages/cli": { "entry": ["bin/cli.js"] }
  }
}
```

- workspace = diretório com `package.json`
- workspaces declarados aqui e ausentes do `package.json`/`pnpm-workspace.yaml`
  são **adicionados** à análise
- opções só de raiz: `include`, `exclude`, `ignoreWorkspaces`, `workspaces`
- workspaces não aninham na config (mas podem aninhar no filesystem)
- projeto com um único `package.json` na raiz → ver "integrated monorepos" na
  doc, não workspaces

Em monorepo, considere `--isolate-workspaces` ao investigar um pacote só.

## Detecção de ciclos

Nativa no v6 — dispensa madge para a maioria dos casos.

```jsonc
{
  "cycles": {
    "dynamicImports": true,
    "allow": [["src/i18n/index.ts", "src/i18n/middleware.ts"]]
  }
}
```

Arestas de import dinâmico ficam **fora** por padrão: um import dinâmico adia a
avaliação, então não causa o hazard de inicialização que a detecção de ciclos
existe para pegar. Ligue `dynamicImports` só se quiser o grafo completo para a
fase 3.

Caminhos em `allow` são relativos à raiz e omitem a repetição final do primeiro
arquivo.

## Armadilhas

**`--fix` cedo demais.** Rodar antes da config assentar é destrutivo. Espere
duas ou três rodadas em que o output já não surpreende.

**Auto-imports e auto-mocking** (Nuxt, Jest) fazem código parecer órfão. Solução
é estender os padrões de `entry`, não ignorar.

**Rotas por convenção** (pages do Next, handlers registrados por glob) e imports
dinâmicos com string montada em runtime são invisíveis ao grafo. Declare como
entry explicitamente.

**Múltiplos `.eslintrc`/`jest.config.js`** num repo com um só `package.json`
aparecem como não usados. É caso de integrated monorepo, não de ignore.

**`treatConfigHintsAsErrors: true`** é bom para CI depois que a config
estabilizou — garante que ninguém mexe no build e deixa o grafo furado.
