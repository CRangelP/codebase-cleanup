# Research: Archify e reorganização de pastas

Pesquisa consolidada para responder: **como a skill Archify contribui para reorganizar a arquitetura das pastas do codebase, no contexto do workflow local de codebase-cleanup?**

Fontes consultadas em **2026-08-12**. Afirmações sobre Archify vêm do clone em `/tmp/archify-research` (`tt-a1i/archify@a3bf80c`, release **v2.14.0**, 2026-08-11). Afirmações sobre a faxina local vêm do snapshot pedido (`/Users/rangel/.claude/skills/codebase-cleanup-workspace/skill-snapshot/…`) e, onde útil para o produto atual do repo, de `/Users/rangel/GitHub/codebase-cleanup`. Onde a fonte não diz, está escrito que não diz.

## Pergunta

Como a skill Archify (https://github.com/tt-a1i/archify) contribui para reorganizar a arquitetura das pastas do codebase, no contexto do workflow local de codebase-cleanup?

## Fontes

| ID | Fonte | Papel |
|---|---|---|
| A1 | https://github.com/tt-a1i/archify — `README.md` (clone `@a3bf80c`) | Posicionamento do produto, tipos de diagrama, escopo explícito |
| A2 | `archify/SKILL.md` | Contrato da skill: o que o agente deve fazer |
| A3 | `PRODUCT.md` | Propósito de produto e anti-referências |
| A4 | `archify/references/authoring-contract.md` — seção Repository evidence | Como Archify usa evidência de repositório |
| A5 | `docs/research-architecture-delta-pr-proof-2026-07-23.md` | Significado de `moved` no Architecture Delta |
| A6 | Metadados GitHub (`gh api repos/tt-a1i/archify`) | Descrição oficial, tópicos, licença MIT |
| A7 | `archify/package.json` | Versão estável (`2.14.0`), runtime Node (`>=18`) |
| A8 | https://github.com/tt-a1i/archify/issues/24 · https://github.com/tt-a1i/archify/issues/59 | Limitações abertas de layout (architecture) e escopo de repo evidence |
| B1 | `/Users/rangel/.claude/skills/codebase-cleanup-workspace/skill-snapshot/SKILL.md` | Pipeline de faxina (3 fases no snapshot) |
| B2 | `…/skill-snapshot/references/fase-3-estrutura.md` | Protocolo da fase de pastas |
| C1 | `/Users/rangel/GitHub/codebase-cleanup/SKILL.md` + `references/phase-3-structure.md` + `agents/cleanup-phase-3-survey.md` | Evolução do produto no repo (4 fases; checkpoint na fase 3) |
| C2 | `/Users/rangel/GitHub/codebase-cleanup/docs/*-research.md` | Convenção de notas de pesquisa neste repo |

## Resumo executivo

**Archify não reorganiza pastas.** Ele transforma descrição de sistema ou evidência de repositório em **mapa técnico interativo** (HTML + JSON tipado), com validação determinística e artefatos compartilháveis ([A1], [A2], [A3], [A6]).

A **Fase 3** da skill local faz o oposto operacional: **diagnostica a árvore de diretórios, escolhe um padrão (feature / camada / convenção da linguagem) e executa `git mv` com gate** ([B1], [B2]).

A contribuição real do Archify, relativa à Fase 3, é **complementar e anterior à execução**: ajudar a *ver* e *comunicar* a arquitetura de runtime/sistema (e, opcionalmente, um delta Before/After de fatos autorados). **Não substitui** plano de pastas, `git mv`, aliases, CODEOWNERS nem rollback atômico. Usar Archify *no lugar* da Fase 3 seria confundir mapa visual com mutação da árvore.

## O que o Archify faz

### Produto

- Skill de agente que gera diagramas **architecture, workflow, sequence, dataflow e lifecycle** como HTML autocontido com SVG, temas, motion opcional e export ([A1], [A2], [A6]).
- Fluxo resumido: o agente escreve **JSON IR tipado** → `validate` → `deliver` → artefato verificado ([A1], [A2]).
- Propósito declarado: o leitor entende a história principal, inspeciona relações autoradas e leva o artefato (ou um Route/Reach Share Card) para review/docs/apresentação ([A3]).
- **Não é** editor WYSIWYG geral, tema Mermaid, nem auto-layout genérico; parsing automático de Mermaid, sharing hospedado e edição WYSIWYG estão **fora do escopo** ([A1], [A3]).

### Instalação e runtime

- Instalação global genérica (comando do Archify; pin de versão é da doc
  deles, não desta skill): `npx skills@latest add tt-a1i/archify -g` ([A1]).
- Cursor (explícito, não interativo): `npx -y skills@latest add tt-a1i/archify --skill archify --agent cursor --global --copy --yes` ([A1]).
- Runtime: **Node ≥ 18** (`engines.node` em `archify/package.json`) ([A7]).
- Versão estável citada nesta pesquisa: **v2.14.0** (2026-08-11) ([A1], [A7]).

### Caminho de autorar (CLI / skill)

O produto autoriza **diagramas**, não pastas. O caminho documentado em SKILL.md e README ([A1], [A2]):

1. Escolher o tipo (`architecture`, `workflow`, `sequence`, `dataflow`, `lifecycle`).
2. Ler o schema correspondente em `schemas/` e um exemplo JSON em `examples/`.
3. Escrever o candidato **JSON IR** (artefato primeiro; coordenadas exatas não são planejadas em prosa).
4. `node bin/archify.mjs validate <type> <candidate.json> --quality showcase --json`.
5. **Preview opcional** (`preview`) — loop desktop que só publica revisões verificadas; nunca é o default ([A2]).
6. `node bin/archify.mjs deliver <type> <candidate.json> <output.html> --quality showcase --json` — aceitação final; bytes congelados após passar.
7. **Compare opcional** (só `architecture`): `node bin/archify.mjs compare architecture base.json head.json architecture-delta.html --json` → Architecture Delta Before / Delta / After ([A1]).

### Relação com “arquitetura” e código

- Pode **inspecionar o repositório** quando o diagrama deve refletir código real: entrypoints, boundaries de runtime, storage, transports, config de deploy; registrar só evidência verificada; não inferir causalidade de runtime só por proximidade de arquivo ou nome ([A4]).
- **Limites da repo evidence (v2.14.0):** modo **Architecture only** — `meta.repository`, node `sources` e `--repo-root` não se aplicam a workflow/sequence/dataflow/lifecycle; exige URL **pública do GitHub** e **commit SHA completo** (40 caracteres); repositórios privados, revisões não pinadas e paths locais no artefato ficam fora do contrato ([A1], docs internos de repo evidence). Issue aberta para estender evidence aos outros tipos: https://github.com/tt-a1i/archify/issues/59 ([A8]).
- Architecture Delta compara dois JSON de architecture já validados (Before / Delta / After) com fatos added/removed/changed/**moved**/rerouted — **`moved` aqui é geometria/posição de componente no diagrama**, não `git mv` de arquivo ([A1], [A5]).
- O contrato de PR Proof deixa explícito que a primeira versão **não** analisa impacto de código nem afirma segurança de merge ([A5]).

### O que a fonte **não** afirma

Em README, SKILL, PRODUCT, authoring-contract e ROADMAP amostrado **não há** protocolo de reorganização de pastas, escolha feature-vs-camada, `git mv`, atualização de path aliases, CODEOWNERS ou commits atômicos por pasta. A descrição GitHub fala em diagramas de arquitetura/workflow/etc., não em cleanup estrutural da árvore ([A6]).

**Saídas explicitamente fora de escopo** (não aparecem como produto Archify): plano de pastas, patches de rename, árvore `src/` reorganizada, nem commits Git no repositório fonte — o `deliver` do CLI congela snapshot/HTML do diagrama, não muta o codebase inspecionado ([A1], [A2], [A3]).

**Lacuna de vocabulário:** nas fontes primárias Archify (README, SKILL, PRODUCT, authoring-contract) **não há** linguagem de “deep modules”, fronteiras de pacote no código, ou protocolo de colocation/feature-folder — o vocabulário é de componentes runtime, boundaries de diagrama, JSON IR e validação de layout ([A1]–[A4]).

## O que a skill codebase-cleanup já faz (fase pastas)

### No snapshot pedido (B1/B2) — três fases

Ordem fixa: **Limpar o morto → decidir fronteiras → mover arquivos** ([B1]).

**Fase 3 — Estrutura de pastas** ([B1], [B2]):

1. Diagnóstico antes de mover: mapa atual, ciclos, módulos-deus, abstrações vazando, estrutura alvo, plano faseado.
2. Escolha de padrão: por feature (colocation), por camada, ou convenção da linguagem.
3. Execução: uma pasta por commit com `git mv`; preferir path aliases a reescrever imports em massa; typecheck; rollback com `git reset --hard` se o gate falhar.
4. Atualizar configs que quebram em silêncio (tsconfig, bundler, knip, CI, CODEOWNERS, imports dinâmicos, `CLAUDE.md`).

No snapshot, o **único checkpoint humano obrigatório** do pipeline é a Fase 2 (consolidação); em nível VERDE, a Fase 3 **executa o plano sem perguntar** ([B1]).

### Nota sobre o repo de produto (C1)

O workspace `/Users/rangel/GitHub/codebase-cleanup` evoluiu para **quatro fases** e, na Fase 3 VERDE, exige **checkpoint humano antes de qualquer `git mv`**, com agente `cleanup-phase-3-survey` só-leitura para o plano ([C1]). A comparação abaixo usa o snapshot (B) como contrato pedido; C1 importa só para integração com o produto atual.

## Contribuição do Archify (mapa claro)

| Capacidade Archify | Ajuda a “reorganizar pastas”? | Como encaixa na faxina |
|---|---|---|
| Mapa runtime/sistema (8–12 componentes) | Indiretamente | Pode informar o *diagnóstico* da Fase 3 (quem depende de quem no runtime), sem mover arquivos ([A1], [A4]) |
| Evidence-backed nodes (`SRC n`, commit pinado) | Indiretamente | Ancora o mapa em arquivos reais; ainda não decide destino de pasta ([A1], [A4]) |
| Architecture Delta (Before/After) | Comunicação / review | Mostra mudança de *fatos autorados* do diagrama — útil pós-faxina ou para explicar fronteiras; **não** executa movimentos de árvore ([A1], [A5]) |
| Workflow / sequence / dataflow / lifecycle | Fora do job da Fase 3 | Útil para explicar fluxos; não é protocolo de pastas ([A2]) |
| `git mv`, aliases, gates, commits atômicos | **Não** | Ausente nas fontes Archify |

**Contribuição única relativa à Fase 3:** artefato de comunicação e exploração de topologia **autorada/verificada**, com validação e share cards — algo que a Fase 3 não produz. A Fase 3, por sua vez, **muta** a árvore com disciplina operacional que Archify não cobre.

## Comparativo

| Dimensão | Archify | Fase 3 (snapshot) |
|---|---|---|
| Job-to-be-done | Explicar/visualizar sistema | Tornar a árvore de pastas legível e coerente |
| Input | Descrição ou evidência de repo → JSON IR | Mapa de diretórios + ciclos + fronteiras pós-Fase 2 |
| Output | HTML + JSON + exports | Commits `git mv` + configs atualizadas |
| “Moved” | Geometria de nó no delta de diagrama ([A5]) | Arquivo/pasta no Git ([B1], [B2]) |
| Gate de verdade | Schema/layout/artifact checks do CLI ([A2]) | Typecheck + testes; rollback ao último commit verde ([B1]) |
| Decisão de domínio | Layout e ênfase do diagrama (agente) | Feature vs camada vs convenção ([B2]); no snapshot, consolidação (Fase 2) é o checkpoint humano ([B1]) |
| Overlap real | Ambos usam a palavra “arquitetura” e podem olhar o repo | Overlap operacional **baixo** |

## Recomendação de uso

**Não substituir a Fase 3.** Archify não implementa o job da Fase 3 ([A1]–[A3] vs [B1]–[B2]).

**Complementar, opcionalmente:**

1. **Antes do plano de pastas (diagnóstico):** mapa runtime de alto nível quando o time não enxerga fronteiras reais (serviços, stores, boundaries) e o grafo de pastas sozinho engana — com a restrição de não inferir causalidade por proximidade de arquivo ([A4]).
2. **No checkpoint humano (produto atual C1):** anexar o HTML Archify ao plano de `cleanup-phase-3-survey` para o humano validar a *história* do sistema, não como prova de que o `git mv` é seguro.
3. **Depois da faxina:** Architecture Delta Before/After como comunicação de PR/release da mudança de entendimento arquitetural — sem confundir com diff de pastas ([A5]).

**Só a skill local basta quando:** o padrão alvo já é claro (ex.: esvaziar `utils/` global para features), ciclos já vêm do knip/madge, e o trabalho é mover com gate — o caso nominal da Fase 3 ([B2]).

**Ignorar Archify na faxina quando:** o custo de autorar/validar um diagrama showcase atrasa um plano de pastas já óbvio, ou quando se esperaria que Archify “sugerisse a árvore nova” — a fonte não oferece esse produto.

## Limitações e questões abertas

1. **Risco de falsa equivalência:** “architecture map” ≠ “folder architecture”. Usar Archify como oráculo de destinos de pasta viola o próprio authoring contract (não inferir runtime por naming/proximidade) ([A4]).
2. **Escopo limitado do mapa:** recomendação de 8–12 componentes ([A1]) — útil para overview, insuficiente como inventário completo da árvore.
3. **Delta não prova segurança de merge** nem blast radius de código ([A5]).
4. **Divergência snapshot × repo:** o snapshot executa Fase 3 sem checkpoint em VERDE ([B1]); o produto em `codebase-cleanup` exige aprovação do plano ([C1]). Qualquer integração deve alinhar ao contrato vigente do plugin instalado.
5. **Layout em architecture mode:** conexões podem rotear *através* de componentes não relacionados sem erro de `validate`/`render`, distorcendo topologia visualmente (workflow já rejeita isso desde v2.8). Issue aberta: https://github.com/tt-a1i/archify/issues/24 ([A8]).
6. **Repo evidence só em architecture:** estender `--repo-root` / `meta.repository` a sequence, dataflow e lifecycle é pedido de feature, não bug — ver https://github.com/tt-a1i/archify/issues/59 ([A8]).
7. **Questão aberta:** vale um gancho formal (“opcional: gerar artefato Archify no survey da Fase 3”) no `SKILL.md` do produto, ou basta menção em docs? As fontes Archify não definem integração com skills de cleanup; isso seria decisão de produto local, não feature Archify.

## Referências

- https://github.com/tt-a1i/archify — README.md, PRODUCT.md, `archify/SKILL.md`, `archify/package.json`, `archify/references/authoring-contract.md`, `docs/research-architecture-delta-pr-proof-2026-07-23.md`, `docs/research-repo-evidence-passport-2026-07-23.md` (clone `@a3bf80c`, release v2.14.0, 2026-08-12)
- https://github.com/tt-a1i/archify/issues/24 — architecture: rotas atravessando componentes não relacionados
- https://github.com/tt-a1i/archify/issues/59 — repo evidence limitada a architecture
- https://tt-a1i.github.io/archify/ — página do projeto / Proof Lab (citada pelo README)
- `/Users/rangel/.claude/skills/codebase-cleanup-workspace/skill-snapshot/SKILL.md`
- `/Users/rangel/.claude/skills/codebase-cleanup-workspace/skill-snapshot/references/fase-3-estrutura.md`
- `/Users/rangel/GitHub/codebase-cleanup/SKILL.md`, `references/phase-3-structure.md`, `agents/cleanup-phase-3-survey.md`, `docs/`
