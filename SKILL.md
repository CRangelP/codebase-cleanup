---
name: codebase-cleanup
description: Faxina completa de codebase em três fases — remove código morto (knip/vulture/cargo-udeps), consolida módulos rasos e reorganiza a estrutura de pastas, executando tudo de forma autônoma com commits atômicos e rollback automático. Use SEMPRE que o usuário mencionar limpar, organizar, arrumar, refatorar ou "dar uma faxina" no projeto; falar em código morto, arquivos órfãos, dependências não usadas, dívida técnica, pastas bagunçadas, estrutura confusa ou codebase pesado; pedir auditoria ou health check do projeto; ou disser que o repo "cresceu demais", "está difícil de navegar" ou "tem coisa que ninguém usa". Use também quando o usuário só quiser uma das três fases isoladamente. Não use para formatação ou lint, atualização de dependências vulneráveis, otimização de tamanho de bundle, limpeza de banco de dados ou reescrita de histórico do git.
---

# Codebase Cleanup

Faxina de codebase em três fases sequenciais. A ordem não é negociável:

**Limpar o morto → decidir as fronteiras → mover os arquivos.**

Na ordem inversa você reorganiza lixo em pastas bonitas e depois descobre que
metade não deveria existir. Cada fase remove o ruído que atrapalharia a próxima:
o grafo de módulos só é confiável depois que o código morto sai, e as pastas só
fazem sentido depois que as fronteiras dos módulos estabilizaram.

## Princípio operacional

Execute o máximo possível sem perguntar. O usuário instalou esta skill para não
ter que digitar quinze comandos — cada confirmação desnecessária é uma falha de
design, não uma cortesia.

O que torna isso seguro não é perguntar, é a estrutura do trabalho: branch
dedicada, commits atômicos por categoria, e um gate verde (typecheck + testes)
antes de cada commit. Se algo quebra, o rollback é descartar o que ainda não
foi commitado com `git restore --staged --worktree .` — sem consultar ninguém,
porque o commit anterior já estava certo. Como todo commit só acontece com gate
verde, o HEAD é sempre um estado bom, e restaurar os arquivos rastreados para o
HEAD equivale ao rollback completo (nunca use `git reset --hard` nem
`git clean`: o restore cobre o caso e sobrevive a ambientes com hooks que
bloqueiam comandos destrutivos).

**Se um hook de segurança bloquear um comando do protocolo** (rollback, criação
de branch, deleção de arquivo), não contorne: registre a pendência em
`CLEANUP_PROGRESS.md`, entregue o comando pronto ao usuário e siga para o
próximo passo que não depende dele. Guard é política do ambiente, não obstáculo.

Só existe **um checkpoint obrigatório** no pipeline inteiro (fase 2, escolha do
candidato de consolidação). Todo o resto roda sozinho.

---

## Passo 0 — Calibrar autonomia

Antes de qualquer coisa, meça a rede de segurança. O nível de autonomia é uma
função dela, não uma preferência.

```bash
git status --porcelain                    # working tree limpa?
git rev-parse --abbrev-ref HEAD           # branch atual
[ -f package.json ] && grep -E '"(test|typecheck|lint|build)"' package.json
```

Rode o gate de baseline com `scripts/gate.sh` (caminho relativo ao diretório
desta skill; aceita o diretório do projeto como argumento) e classifique. O
script detecta o stack pelo manifesto na raiz — `package.json`, `go.mod`,
`Cargo.toml`, `pyproject.toml`/`setup.cfg`, `pom.xml`/`build.gradle`,
`Gemfile`, `sln`/`csproj`/`fsproj` — e roda typecheck e testes de cada um que
encontrar (compilar conta como typecheck).

Classifique pela linha `[gate] checks=...`, que lista o que de fato rodou, e
não só pelo exit code: VERDE exige `typecheck` e `test` na lista; lista
parcial limita a AMARELO, e o próprio script avisa. Exit 0 = tudo que rodou
passou; 1 = algo falhou; 3 = nenhum check executável **ou** algum stack
detectado ficou sem toolchain (`PARCIAL` — inclusive em repo poliglota onde
outro stack passou). Nos casos de exit 3, complete o gate à mão antes de
classificar.

| Sinal | Nível | Comportamento |
|---|---|---|
| Typecheck **e** testes passam | **VERDE** | Executa fases 1 e 3 inteiras sem perguntar. Fase 2 para no checkpoint. |
| Testes existem mas falham, ou só typecheck | **AMARELO** | Executa fase 1 (só deps e arquivos órfãos, **não** exports). Para antes da fase 2 e reporta. |
| Sem testes e sem typecheck | **VERMELHO** | Só diagnostica. Não deleta, não move, não commita. Entrega relatório. |

Se o baseline já está quebrado, **conserte ou avise antes de tocar em qualquer
coisa**. Você precisa de um verde inicial para distinguir o que você quebrou do
que já estava quebrado.

Anuncie o nível detectado em uma linha e siga. Não peça permissão para o nível.

```bash
git checkout -b faxina/$(date +%Y%m%d)
```

## Passo 0.1 — Estado persistente

Crie `CLEANUP_PROGRESS.md` na raiz e mantenha atualizado ao fim de cada passo.
As fases são separadas por `/clear` (contexto sujo de uma fase degrada a
seguinte), então este arquivo é o que permite retomar sem o usuário reexplicar
nada.

```markdown
# Cleanup Progress
Branch: faxina/20260808 · Nível: VERDE · Iniciado: 2026-08-08

- [x] Fase 1.1 — hints do knip zerados (3 rodadas)
- [x] Fase 1.2 — deps removidas (7) · commit a3f9c21
- [ ] Fase 1.3 — arquivos órfãos
...
## Decisões
- `lodash.merge` mantida: usada em script de build fora do grafo
## Pendências para o humano
- (nenhuma)
```

Ao ser invocada, **sempre leia este arquivo primeiro**. Se existir, retome de
onde parou em vez de recomeçar.

## Passo 0.2 — Sessão única ou subagentes

Pipeline completo em repo real: se o ambiente tiver subagentes, rode como
orquestrador — cada fase vai para um subagente de implementação com contexto
descartável, que é o mesmo efeito do `/clear` sem depender do usuário lembrar.
Pedido de fase única ou repo pequeno: sessão única, sem orquestração.

O contrato de cada delegação:

- o caminho desta skill (o subagente lê a SKILL.md e segue, com references/ e
  scripts/ ao lado) e o caminho do repo;
- a ordem de ler `CLEANUP_PROGRESS.md` antes de qualquer coisa;
- escopo de **uma** fase — e a fase 2 vira duas delegações: o levantamento
  devolve os candidatos, a implementação só parte depois da escolha do usuário;
- devolver um resumo do que fez, com `CLEANUP_PROGRESS.md` atualizado como
  estado canônico.

O Passo 0 (calibrar nível, criar a branch) e o checkpoint da fase 2 ficam com
o orquestrador — subagente não fala com o usuário. Nível e branch chegam aos
subagentes prontos, via `CLEANUP_PROGRESS.md`.

---

# FASE 1 — Morto ou vivo

Objetivo: separar o que é código de verdade do que pode sumir.

Aqui não use julgamento de LLM como juiz. Use ferramenta, e interprete o
resultado. "Esse arquivo parece não usado" é palpite; "nenhum entry point
alcança este arquivo no grafo de módulos" é fato.

Para stacks não-JS/TS, leia `references/outras-stacks.md`. O resto desta fase
assume JS/TS.

## 1.1 Configurar o knip até os hints zerarem

Rode `npx knip` sem config nenhuma primeiro. O knip tem plugins para a grande
maioria das ferramentas do ecossistema (Next, Vitest, ESLint, Playwright, e
dezenas de outras) que leem a configuração delas e deduzem entry points
sozinhos — escrever config antes de ver o que ele já sabe é trabalho jogado
fora.

**Trate os configuration hints antes de olhar qualquer finding.** Hints indicam
que o knip não conseguiu resolver uma dependência, plugin ou entry file — ou
seja, o grafo está incompleto e todo finding derivado dele é suspeito. Boa parte
da lista de "arquivos não usados" evapora sozinha quando os hints somem.

Itere sozinho: escreva `knip.json`, rode de novo, ajuste, repita. Não mostre
cada rodada ao usuário — reporte no fim quantas rodadas foram necessárias e
quantos achados sumiram.

Detalhes de configuração (entry, project, paths, monorepo, quando usar cada
`ignore*`) em `references/knip-config.md`. Leia antes de escrever o arquivo.

A regra que mais economiza retrabalho: **não use a opção `ignore`.** Ela não
exclui da análise, só esconde o report — criando ponto cego. Se algo aparece
errado, o conserto é ensinar o grafo (entry, project, paths, plugin), não calar
o output.

## 1.2 Rodar em modo produção

```bash
npx knip --production --reporter json > knip-report.json
```

Production mode exclui testes e devDependencies automaticamente. Isso importa
porque uma função importada só por um teste está tecnicamente viva, mas está
morta para a aplicação — e é exatamente esse código que você quer encontrar.

Nunca exclua testes com `ignore` para conseguir o mesmo efeito.

## 1.3 Deletar em commits atômicos, um por categoria

Execute os três sem perguntar (nível VERDE) ou os dois primeiros (AMARELO).
Cada um é: deleta → gate → commit. Para o gate, use `scripts/gate.sh` (detecta
o stack e o package manager e roda typecheck + testes na ordem certa); se ele
sair com código 3, rode os comandos equivalentes do stack à mão.

```
1. deps não usadas    → "chore: remove unused deps"
2. arquivos órfãos    → "chore: remove orphan files"
3. exports mortos     → "chore: remove dead exports"
```

Separados porque se algo quebrar em produção daqui duas semanas, o usuário
precisa reverter *um* commit — não uma faxina de 400 arquivos.

**Em caso de falha no gate:** `git restore --staged --worktree .`, registre a
categoria como falha em `CLEANUP_PROGRESS.md` com o erro, e **siga para a
próxima categoria**.
Não pare o pipeline inteiro e não tente consertar — se o typecheck quebrou, o
knip errou sobre aquela categoria, e a informação útil é qual categoria, não um
remendo.

Não rode `knip --fix` até a config estar assentada por duas ou três rodadas sem
surpresas.

## 1.4 Auditoria completa

Com o lixo fora, o grafo está limpo e a auditoria fica precisa. Se a skill
`tech-debt-audit` estiver instalada, leia o SKILL.md dela e siga o protocolo —
ela é marcada como user-invoked (`disable-model-invocation`), então não
tente invocá-la como skill; o valor está no protocolo, que você executa
diretamente. Se não estiver instalada, produza o equivalente: varredura de
repo inteiro citando `arquivo:linha` em cada achado,
com severidade e esforço, cobrindo decadência arquitetural, inconsistência,
dívida de tipos, testes, deps e config, performance, tratamento de erro,
higiene de segurança e documentação desatualizada.

Inclua obrigatoriamente uma seção **"parece ruim mas está ok"** — chamadas que
você considerou fazer e decidiu não fazer, com o motivo. Se essa seção vier
vazia, a auditoria não olhou fundo o suficiente e você deve voltar.

Commit o relatório. Atualize `CLEANUP_PROGRESS.md`. **Diga ao usuário para rodar
`/clear` antes da fase 2.**

---

# FASE 2 — Consolidar módulos

Objetivo: descobrir onde "esses três módulos deveriam virar um".

Leia `references/fase-2-consolidacao.md` para o protocolo completo de
levantamento e o vocabulário de análise.

## O checkpoint irredutível

Este é o único ponto do pipeline que exige o humano, e vale explicar por quê:
consolidar módulos muda fronteiras de responsabilidade, e essa é uma decisão
sobre o *domínio*, não sobre o código. Testes verdes não provam que a fronteira
nova é a certa — provam que o comportamento não mudou, que é outra coisa.

Reduza o custo do checkpoint ao mínimo:

1. Apresente **no máximo 5 candidatos** ranqueados por confiança.
2. Para cada um: quais módulos, por que estão rasos, o que vira depois, e o
   risco de mexer.
3. **Recomende um** explicitamente, com o motivo em uma frase.
4. Faça **uma** pergunta: qual seguir. Não faça entrevista de múltiplas rodadas.

Se o usuário responder "vai" ou equivalente, siga com sua recomendação.

## Critério de decisão: o teste da deleção

Imagine apagar o módulo. Se a complexidade some, ele era pass-through e deve ser
consolidado. Se a complexidade reaparece espalhada por N chamadores, ele estava
se pagando e deve ficar.

Um módulo raso é aquele cuja interface é quase tão complexa quanto o que ela
esconde — o custo de aprender a interface se aproxima do custo de simplesmente
ler a implementação. Consolide agrupamentos de módulos pequenos e fortemente
acoplados, não arquivos grandes isolados (arquivo grande é problema da fase 1,
e módulo grande com interface simples é exatamente o que você *quer*).

## Implementação

Depois da escolha, execute sozinho: um módulo por vez, typecheck e testes entre
cada passo, um commit por consolidação. Mesmo protocolo de rollback da fase 1.

**Um candidato por sessão.** Não empilhe dois — o segundo refactor herda o
contexto sujo do primeiro e a taxa de erro sobe.

Atualize `CLEANUP_PROGRESS.md`. Recomende `/clear` antes da fase 3.

---

# FASE 3 — Estrutura de pastas

Objetivo: organização legível de diretórios e arquivos.

Vem por último porque consolidar módulos muda o que as pastas deveriam ser.
Mover arquivo antes de decidir a fronteira é retrabalho garantido.

Leia `references/fase-3-estrutura.md` para os padrões de organização e como
escolher entre eles.

## Diagnóstico primeiro, movimento depois

Produza um plano faseado antes de mover qualquer coisa: mapa da estrutura
atual, dependências circulares, módulos-deus, abstrações vazando, e a estrutura
alvo com justificativa. Só então execute.

## Execução autônoma

Nível VERDE executa o plano inteiro sem perguntar. Uma pasta por commit:

```bash
git mv src/utils/format.ts src/features/billing/format.ts   # sempre git mv
```

`git mv` preserva histórico — `rm` + `create` destrói o `git blame` daquele
arquivo, que é justamente a informação que alguém vai querer daqui a seis meses.

Prefira atualizar **path aliases** a reescrever 200 imports. Se o projeto usa
`@/features/*`, mover uma pasta pode ser uma linha no tsconfig em vez de um diff
de 3.000 linhas.

Typecheck ao final de cada pasta. Falhou: `git restore --staged --worktree .`,
registra, próxima pasta.

---

## Regras que valem para o pipeline inteiro

**`/clear` entre fases.** Não é opcional. Contexto acumulado da fase anterior
degrada o julgamento da seguinte, e `CLEANUP_PROGRESS.md` existe para que isso
não custe nada.

**Nunca junte dois passos.** "Configure o knip e delete o que ele achar" é como
se deleta um handler de rota registrado por convenção que o knip não conhecia.
A separação entre configurar, verificar e deletar é o que impede isso.

**Gate vermelho é rollback, não conserto.** Se typecheck ou testes falham, o
commit anterior já estava certo. Reverta, registre, siga. Tentar consertar
transforma uma faxina em um debugging não solicitado.

**Nunca force push, nunca commite na main.** Todo o trabalho vive na branch de
faxina. O merge é decisão do usuário, no tempo dele.

## Relatório final

Ao encerrar (ou ao ser interrompido), entregue:

```markdown
## Faxina — resumo
Branch: `faxina/AAAAMMDD` · Nível: VERDE · N commits

| Fase | Resultado |
|---|---|
| 1 — código morto | 7 deps, 23 arquivos, 41 exports removidos |
| 2 — consolidação | 3 módulos → 1 (`src/billing/`) |
| 3 — estrutura | 4 pastas reorganizadas, 2 ciclos quebrados |

### Reverter qualquer coisa
`git revert <sha>` — commits são atômicos por categoria.

### Falhou / não foi feito
- exports mortos: typecheck quebrou em `src/api/routes.ts` (import dinâmico)

### Pendente de decisão sua
- (nada)
```

Se o nível era VERMELHO, o relatório é só diagnóstico: liste o que faria e o que
precisa existir (testes, typecheck) para poder fazer.
