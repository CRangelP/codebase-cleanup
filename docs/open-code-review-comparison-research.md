# Research: Alibaba OpenCodeReview × codebase-cleanup

Pesquisa consolidada para responder: **o que o projeto local pode aproveitar do [alibaba/open-code-review](https://github.com/alibaba/open-code-review)?**

As fontes foram consultadas em **2026-08-12**. Afirmações factuais sobre o OCR vêm do repositório GitHub (README, docs em `pages/src/content/docs/en/`, skills, `action.yml`, `ROADMAP.md`, `LICENSE`) e da API do GitHub (`gh repo view` / `gh api`). Afirmações sobre o projeto local vêm dos arquivos deste repositório (`README.md`, `SKILL.md`, `.claude-plugin/plugin.json`, `docs/`). Onde a fonte não diz, está escrito que não diz.

Nada aqui recomenda commit ou merge automático de código Apache-2.0 neste repositório MIT — ver seção de licença.

---

## 1. Veredito em uma frase

São produtos **complementares**, não substitutos: o **codebase-cleanup** é uma skill Claude Code de faxina estrutural (código morto → consolidação → pastas → remodelagem local) com gate e commits atômicos; o **OpenCodeReview (OCR)** é um CLI Go de *code review* por diff, com pipeline determinístico + agente LLM, regras multi-linguagem e integrações CI/IDE. O que vale aproveitar são **padrões de engenharia e disciplina de cobertura**, não embutir o OCR como dependência de runtime da skill de limpeza.

---

## 2. Projeto local — codebase-cleanup

### Propósito

Skill (e plugin) de limpeza de codebase para Claude Code. Quatro fases, nessa ordem: (1) código morto, (1.5) funções duplicadas, (2) consolidação de módulos rasos, (3) reorganização de pastas, (4) remodelagem local do que sobrou. Ordem fixa porque organizar antes de apagar morto é “arrumar lixo em gaveta bonita”.

Fonte: [`README.md`](../README.md) (consultado 2026-08-12).

### Escopo e não-escopo

| Faz | Não faz (explícito na `description` do `SKILL.md`) |
| --- | --- |
| Remover deps/arquivos/exports mortos | Formatação / lint |
| Detectar duplicação com regra de churn | Atualização de deps vulneráveis |
| Consolidar módulos rasos | Otimização de bundle size |
| Reorganizar pastas com `git mv` | Limpeza de banco |
| Remodelar funções (tier A/B) | Reescrita de histórico git |
| Gate multi-stack + rollback | Code review de PR / comentários line-level |

Fonte: frontmatter de [`SKILL.md`](../SKILL.md).

### Stack e forma de distribuição

- Artefato: Markdown de skill + agents + `references/` + scripts bash (`gate.sh`, `guard.sh`, testes).
- Host: Claude Code (plugin marketplace / cópia em `~/.claude/skills/`).
- Versão do plugin: `0.9.0` ([`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json)).
- Licença: **MIT** ([`LICENSE`](../LICENSE), README).
- Ferramentas externas por stack: knip (JS/TS pinado), vulture/deadcode, cargo-udeps, jscpd/similarity-ts, etc. — a skill aponta o que falta; não instala toolchain à força.
- Autonomia calibrada: níveis GREEN / YELLOW / RED via `scripts/gate.sh`.
- Guardas PreToolUse: nunca `git add -A`; também bloqueiam `git reset --hard`, `git clean`, `git push` e commit na `main`.

### Arquitetura operacional

```
Step 0 (calibração) → branch cleanup/YYYYMMDD
  → Fase 1 (+1.5) → /clear → Fase 2 (checkpoint) → /clear
  → Fase 3 (checkpoint) → /clear → Fase 4 (tier B conditional)
  → relatório final + CLEANUP_PROGRESS.md
```

Subagentes em `agents/` (survey read-only vs impl) para não burlar checkpoints. Progresso durável em `CLEANUP_PROGRESS.md`.

### Maturidade (local)

Repositório próprio com CI multi-plataforma (ubuntu + macOS), suítes de contrato (`gate_test`, `guard_test`, `rollback_test`, `metrics_test`, `coherence_test`, `mutation_test`) e evals de modelo (`eval.sh`). Foco em **protocolo seguro de mutação do repo**, não em achar bugs de lógica em diffs de PR.

---

## 3. Alibaba OpenCodeReview — fatos da fonte primária

### Identidade e maturidade

| Campo | Valor (2026-08-12) | Fonte |
| --- | --- | --- |
| Repo | `alibaba/open-code-review` | GitHub |
| Site | https://open-codereview.ai | README |
| Descrição | Hybrid architecture code review: deterministic pipelines + LLM Agent; line-level comments; multi-language ruleset | `gh repo view` description |
| Criado | 2026-05-18 | API |
| Stars / forks | ~20 240 / ~1 420 | API |
| Issues abertas | ~112 | API |
| Release | **v1.9.2** (2026-08-12) | `gh release list` |
| Linguagem principal | Go (~2.1 MB de código Go; também TS/JS na extensão VS Code e pages) | API languages |
| Pacote npm | `@alibaba-group/open-code-review` (wrapper que baixa binário) | `package.json` |
| Licença | **Apache-2.0** | `LICENSE`, badge README |
| OpenSSF | Badge Gold (README) | README |
| Origem | Assistente interno da Alibaba Group; “tens of thousands of developers”, “millions of code defects” (claim do README — não auditado aqui) | README |

### Propósito

CLI `ocr` que lê diffs Git, envia arquivos alterados a um LLM com tool-use, e gera comentários estruturados com precisão de linha. Também `ocr scan` para auditar arquivos inteiros sem diff significativo.

Citação (README):

> “It reads Git diffs, sends changed files to a configurable LLM via an agent with tool-use capabilities, and generates structured review comments with line-level precision.”

### Problema que o OCR diz resolver (vs agents genéricos)

O README lista falhas de skills de review puramente em linguagem natural:

1. Cobertura incompleta em changesets grandes (“cut corners”).
2. Drift de posição (linha/arquivo errados).
3. Qualidade instável com pequenas variações de prompt.

Causa declarada: falta de **hard constraints** no processo.

### Arquitetura (docs oficiais no repo)

Pipeline documentado em `pages/src/content/docs/en/architecture.md`:

1. **Bootstrap** — resolve endpoint LLM, carrega template, tools, system rules.
2. **Diff provider** — modos Workspace / Commit / Range (`merge-base(a,b)..b`).
3. **Filter & rules** — filtro de 5 gates; regra por arquivo.
4. **Subtask dispatch** — um sub-agente por arquivo (concorrência default 8); plan opcional se >50 linhas alteradas; main loop com tools.
5. **Comment processing** — resolução de linha, re-location opcional, review-filter LLM, render text/JSON.
6. **Persistência** — sessões JSONL em `~/.opencodereview/sessions/…`; `ocr viewer`.

Filosofia: **engenharia determinística × agente híbrido**.

| Determinístico | Agente |
| --- | --- |
| Seleção precisa de arquivos | Prompts sintonizados para review |
| Bundling de arquivos relacionados | Toolset destilado de traços de produção |
| Matching de regras por path (template engine) | Decisões dinâmicas e busca de contexto |
| Módulos externos de posicionamento e “reflection” | Comentários via `code_comment` |

### Regras

Cadeia de 4 camadas (`pages/.../review-rules.md`):

1. `--rule` (CLI)
2. `<repo>/.opencodereview/rule.json`
3. `~/.opencodereview/rule.json`
4. `system_rules.json` embutido (sempre presente)

Regras built-in por extensão/caminho: Java, Go, TS/JS, Python, Rust, Kotlin, C/C++, PHP, Terraform, Prisma, GraphQL, workflows GitHub, `package.json`, MyBatis mappers, etc. Exemplo TS inclui dead code local, XSS, hooks React, `==` vs `===` — **review heurístico**, não deleção via grafo (diferente do knip).

### Integração

| Canal | O que oferece | Fonte |
| --- | --- | --- |
| CLI | `ocr review`, `scan`, `delegate`, `config`, `session`, `viewer`, `rules check` | README |
| Claude Code plugin | `/plugin marketplace add alibaba/open-code-review` → slash commands | `plugins/.../README.md` |
| Codex / Cursor plugins | Skills portáteis | mesmo |
| Delegation mode | OCR só filtra arquivos + resolve regras; host agent faz o review com a LLM da assinatura | `integrations/delegate.md` |
| GitHub Action | `action.yml` — comentários inline, sticky summary, incremental | `action.yml`, `examples/github_actions/` |
| Outros CI | GitLab, Gerrit, Bitbucket, GitFlic, Codeup (examples/) | tree do repo |
| VS Code extension | `extensions/vscode/` | tree |
| MCP | Documentado no README / ROADMAP | README |
| Telemetry | OpenTelemetry | README / architecture |

### O que o OCR declara fora de escopo

`ROADMAP.md` (“Not Planned”):

- Automated code fixing **without human review**
- General-purpose AI coding assistant (geração, **refactoring**, chat coding)
- Self-hosted LLM bundling

Isso reforça a complementaridade: refactoring/cleanup estrutural **não é roadmap do OCR**.

### Benchmark (claim do README)

Benchmark próprio: 50 repos, 200 PRs, 10 linguagens, 1 505 issues anotadas por 80+ engenheiros. Vs Claude Code genérico: maior Precision/F1, ~1/9 dos tokens, Recall menor (trade-off deliberado). **Não reproduzido nesta pesquisa** — tratado como claim do projeto.

---

## 4. Comparação lado a lado

| Dimensão | codebase-cleanup | OpenCodeReview |
| --- | --- | --- |
| **Job-to-be-done** | Reduzir dívida estrutural no repo (morto, raso, pastas, forma local) | Encontrar defeitos/riscos em mudanças (diff/PR) com comentários |
| **Unidade de trabalho** | Categorias e fases sobre a árvore inteira | Arquivo/diff no changeset |
| **Mutação do código** | Sim — deleções, moves, refactors com gate | Primário: só reporta; fix é opcional e o ROADMAP rejeita auto-fix sem humano |
| **Rede de segurança** | Gate typecheck+test; branch dedicada; commits atômicos; guardas PreToolUse | Filtro de arquivos, review-filter LLM, posicionamento de linha; CI posta comentários |
| **Host** | Claude Code skill/plugin | CLI + plugins multi-host + Action + VS Code |
| **Stack de implementação** | Markdown + bash | Go (binário) + npm installer + TS (extensão) |
| **LLM** | Usa o modelo do Claude Code (host) | Endpoint configurável **ou** delegation ao host |
| **Regras de domínio** | Protocolo de limpeza + catalogs em `references/` | `rule.json` + system rules por linguagem |
| **Cobertura de changeset** | N/A (não é review de PR) | Hard constraint: seleção determinística + checklist de coverage no delegate |
| **CI do produto** | Testa a skill (contratos) | Também oferece Action para review de PRs de terceiros |
| **Licença** | MIT | Apache-2.0 |
| **Sobreposição funcional** | Baixa | Baixa |

### Fluxo de “code review”

- **Local:** não há fluxo de code review. Há *revisão humana* só nos checkpoints de fronteira de módulo / plano de pastas / tier B, e caps de diff reviewável na fase 4 (“Cap per session: 5 tier A…”) — isso é orçamento de remodelagem, não review de defeitos.
- **OCR:** preview → (plan) → main loop com tools → code_comment → resolve linhas → filter → saída agent/human/CI.

### Extensibilidade

| | Local | OCR |
| --- | --- | --- |
| Adiar contexto | `references/*.md` lidos sob demanda | Prompts em `internal/config/template/prompts/` (rebuild) |
| Customizar política | Editar SKILL/agents; caps em `other-stacks.md` | `.opencodereview/rule.json`, `--rule`, tools JSON |
| Outros hosts | Claude Code (primário) | Claude, Codex, Cursor, OpenCode, QCA, MCP |

---

## 5. O que o local já cobre vs o que o OCR oferece de diferente

### Já coberto (não precisa do OCR)

- Deleção segura de código morto com grafo (knip etc.) e níveis GREEN/YELLOW/RED.
- Duplicação com churn git (fase 1.5).
- Consolidação e estrutura de pastas.
- Remodelagem local limitada e reviewável.
- Rollback e proibição de push/commit na main.
- Relatório final de limpeza (`references/final-report.md`).
- Distribuição como plugin Claude Code com hooks.

### OCR oferece e o local não tem (e em geral não deveria absorver como core)

- Review line-level de PR/diff com precisão de âncora.
- Ruleset multi-linguagem de defeitos (NPE, XSS, SQL injection, thread-safety…).
- GitHub Action / GitLab / Gerrit posting.
- Session viewer, SARIF, telemetry OTel.
- Benchmark de qualidade de review (Precision/Recall).
- Extensão VS Code.
- Bundling concorrente de arquivos relacionados para review estável em PRs enormes.
- Delegation mode: scaffolding determinístico + LLM do host.

### Zona cinzenta (parecem vizinhos, mas não são a mesma coisa)

| Aparência | Realidade |
| --- | --- |
| Regra TS do OCR menciona “Dead Code” | É heurística de review no diff; cleanup usa knip/vulture e **deleta** com gate |
| Ambos falam em “cobertura” | OCR: todo arquivo do changeset revisado; cleanup: categorias do knip + gate verde |
| Ambos têm plugin Claude Code | OCR invoca `ocr` CLI; cleanup *é* o protocolo |
| Ambos usam agents | OCR: sub-agentes por arquivo de review; cleanup: survey/impl por fase |

---

## 6. O que pode ser aproveitado

Ordenado do mais útil ao mais cosmético. “Aproveitar” aqui significa **padrão, receita ou uso complementar** — não fork do binário Go.

### Ideias e padrões (alto valor)

1. **Híbrido determinístico × agente**  
   Hard constraints no que não pode errar (seleção, filtro, ordem, checklist de coverage); LLM só onde há julgamento. O cleanup já faz isso no gate/guardas; o OCR reforça o mesmo princípio no domínio review — útil para endurecer fases grandes (1 e 1.5) contra “cortar caminho” do modelo.

2. **`ocr review --preview` / `ocr delegate preview`**  
   Dry-run que lista o que seria tocado **antes** de gastar tokens. Análogo desejável: preview da fase 1 (lista de deletes) já existe em espírito via knip report; formalizar “preview sem mutação” como passo nomeado ajuda UX.

3. **Mandato de coverage no delegate**  
   Skill `open-code-review-delegate`: todo arquivo previewed deve terminar `reviewed` ou `skipped` com razão + métricas `coverage_rate`. Padrão importável para varreduras da fase 1.5 / auditoria 1.4 quando o changeset/repo é grande.

4. **Camadas de regra por path (`.opencodereview/rule.json`)**  
   Não copiar o formato para “ser OCR”, mas o *modelo mental*: política de projeto versionada, override global, override CLI. Útil se no futuro a cleanup quiser checklists de domínio na fase 4 (ex.: “nunca fundir X com Y”) sem inflar o `SKILL.md`.

5. **Classificação severidade × categoria no relatório**  
   OCR usa `critical|high|medium|low` e categorias (`bug`, `security`, …). O relatório final de cleanup poderia adotar severidade para *riscos residuais* da auditoria 1.4 (já tem dimensões) — melhora priorização humana pós-faxina.

6. **Concorrência com isolamento de contexto**  
   Subtask por arquivo, concurrency=N, falha isolada. Para cleanup, o paralelo já existe via subagentes de fase; o insight é **não compartilhar contexto poluído entre unidades** (OCR: um arquivo; cleanup: já pede `/clear` entre fases).

7. **Uso complementar do produto**  
   Em times que já usam Claude Code: **OCR (delegate ou managed) no PR** + **cleanup na dívida estrutural**. ROADMAP do OCR exclui refactoring — encaixa com o produto local.

8. **Empacotamento multi-host**  
   OCR publica Claude + Cursor + Codex a partir do mesmo repo. Se o cleanup quiser Cursor no futuro, o layout `plugins/…` + skills portáteis é referência de packaging (não de domínio).

### Módulos / prompts / regras (aproveitamento seletivo)

| Artefato OCR | Aproveitar? | Como |
| --- | --- | --- |
| `rule_docs/*.md` (ex. dead code em TS) | Parcial | Como *checklist de auditoria humana*, não como motor de deleção |
| `main_task_system.md` (foco no diff novo, ignorar achados fora do arquivo) | Ideia | Analogia: fase N não “conserta” o que a fase N+1 vai mexer |
| `REVIEW_FILTER_TASK` (segunda passagem que remove falso positivo) | Ideia | Pós-processar candidatos knip/duplicação antes de deletar/consolidar |
| `RE_LOCATION_TASK` / line resolution | Não | Cleanup não ancora comentários em PR |
| Action.yml / CI examples | Não no core | Outro produto; usuário pode adotar no *seu* app, não neste repo de skill |
| Binário Go / agent loop | Não | Stack e job diferentes; viraria dependência pesada |

### Integrações

- **Recomendação de documentação:** “Para review de PR, use OCR; para faxina, use esta skill.”
- **Receita opcional (não runtime):** após merge da branch `cleanup/`, rodar `ocr review --from main --to cleanup/…` (ou delegate) como QA da própria limpeza — detecta regressões lógicas que o gate de testes não pegou.
- **Delegation mode:** se o usuário já está no Claude Code, `ocr delegate` evita segunda API key — alinhado ao modelo econômico do cleanup (usa o host).

---

## 7. O que NÃO faz sentido copiar

1. **Embutir `@alibaba-group/open-code-review` como dependência obrigatória da skill**  
   Viola o desenho “nenhuma outra skill/ferramenta de review é obrigatória”; o cleanup já é autossuficiente com knip/gate. OCR exige Git ≥ 2.41 e (no modo managed) LLM endpoint.

2. **Trocar knip/vulture por regras de “Dead Code” do OCR**  
   São problemas diferentes: grafo de alcance vs impressão do modelo no diff. False positives de review ≠ candidatos seguros a `rm`.

3. **Virar produto de code review**  
   Escopo do cleanup é faxina; o OCR já ocupa review com escala e CI. Duplicar fragmentaria o produto local.

4. **Auto-fix agressivo pós-review**  
   O próprio OCR coloca “automated fixing without human review” como Not Planned. O cleanup já tem política estrita de mutação; misturar “review and fix” diluiria os guardrails.

5. **Copiar prompts/código Go em volume para este repo MIT**  
   Licença Apache-2.0 exige preservação de notices/ATTRIBUTION ao redistribuir código coberto; ideias e APIs públicas são outra história. Preferir citar e linkar.

6. **System rules de segurança (XSS, SQLi) como fase da cleanup**  
   Fora do job-to-be-done; melhor apontar SAST/OCR.

7. **Session JSONL viewer / OTel / SARIF**  
   Infra de produto SaaS/CLI maduro; custo alto, benefício baixo para uma skill de protocolo.

8. **Benchmark de 200 PRs**  
   Bom *inspiração metodológica* para evals; o cleanup já tem `eval.sh` + mutation — não precisa importar o harness do OCR.

---

## 8. Oportunidades concretas de adaptação

Prioridade = impacto para o usuário do cleanup × esforço de implementação **neste** repositório.

| # | Oportunidade | Impacto | Esforço | Notas |
| --- | --- | --- | --- | --- |
| **A** | Doc “complementaridade”: quando usar cleanup vs OCR; receita pós-cleanup `ocr review` / `ocr delegate` na branch | Alto | Baixo | Só documentação + talvez seção no README; zero runtime |
| **B** | Formalizar **coverage mandate** nas varreduras grandes (fase 1.5 / audit): checklist de arquivos/pares, `reviewed|skipped+reason`, taxa de cobertura no `CLEANUP_PROGRESS` | Alto | Médio | Padrão da skill delegate; não precisa do binário OCR |
| **C** | Passo nomeado **Preview** antes de mutação na fase 1 (lista knip → confirmação só se YELLOW/cap já exige; em GREEN manter autonomia mas gravar preview no progress) | Médio | Baixo–médio | Espelha `ocr review --preview` |
| **D** | Segunda passagem tipo **review-filter** nos candidatos de deleção/duplicação (“provably incorrect → drop”) antes do commit | Médio | Médio | Prompt curto + invariante; cuidado para não virar review de bug |
| **E** | Severidade no relatório final / auditoria 1.4 para resíduos | Médio | Baixo | Cosmético mas útil na decisão humana |
| **F** | Regras de domínio versionadas (arquivo de projeto) para restrições da fase 2/4 (“não consolidar billing×auth”) | Médio | Médio | Inspirado em `rule.json`; formato próprio MIT |
| **G** | Packaging Cursor (espelhar layout OCR) | Baixo–médio | Médio | Só se houver demanda de host; domínio continua cleanup |
| **H** | Integrar CLI `ocr` no pipeline da skill | Baixo (produto) / Alto (risco) | Alto | **Não recomendado** como default; conflita autossuficiência e licença/ops |
| **I** | Adotar Action do OCR no CI **deste** repo de skill | Baixo | Baixo | CI da skill valida contratos bash, não PRs de app; pouco valor |

### Top 3 recomendadas

1. **A — Documentar complementaridade + receita opcional OCR na branch de cleanup** (alto/baixo).  
2. **B — Coverage mandate nas varreduras** (alto/médio) — ataca a mesma falha que o OCR aponta em agents genéricos.  
3. **C ou E — Preview explícito e/ou severidade no relatório** (médio/baixo) — ganho de previsibilidade sem mudar o core.

---

## 9. Licença e outros bloqueios

### Licença

| | cleanup | OCR |
| --- | --- | --- |
| SPDX | MIT | Apache-2.0 |

- **Usar o CLI/npm como ferramenta externa** (usuário instala `ocr` na máquina): geralmente ok; Apache-2.0 permite uso.
- **Copiar código/prompts substanciais para dentro deste repo MIT:** exige cumprimento Apache-2.0 (notices, NOTICE se aplicável, estado de mudanças). Risco de incompatibilidade de *relicensing* se o projeto quiser permanecer MIT puro sem dual-license.
- **Recomendação desta research:** aproveitar **ideias e APIs CLI** por referência; não vendorar `internal/` do OCR.

### Outros bloqueios / ressalvas

- Site `open-codereview.ai/docs` retornou 404 neste ambiente em 2026-08-12; a doc canônica usada foi a árvore `pages/src/content/docs/en/` no GitHub (mesma fonte do site).
- Claims de escala interna Alibaba e números do benchmark **não foram reproduzidos**.
- OCR default de idioma de comentário: docs da skill mencionam default Chinese na config — relevante se integrar em time PT-BR (configurável).
- Delegation e managed mode mudam o custo (assinatura host vs API key); qualquer receita deve deixar isso explícito.
- Git ≥ 2.41 no OCR pode ser mais novo que o Git de alguns ambientes; cleanup hoje é mais permissivo no Git.

### Lacunas de doc

- Não foi auditado o código Go linha a linha (só docs + samples de rules/prompts).
- Não foi medido token/latência do OCR vs skill cleanup (jobs diferentes — comparação numérica seria enganosa).

---

## 10. Fontes consultadas (2026-08-12)

### OpenCodeReview

- https://github.com/alibaba/open-code-review (README, LICENSE, ROADMAP, AGENTS.md, action.yml, package.json, go.mod)
- `pages/src/content/docs/en/architecture.md`
- `pages/src/content/docs/en/review-rules.md`
- `pages/src/content/docs/en/integrations/delegate.md`
- `skills/open-code-review/SKILL.md`
- `skills/open-code-review-delegate/SKILL.md`
- `plugins/open-code-review/README.md`
- `plugins/open-code-review/claude-code/commands/review.md`
- `internal/config/rules/rule_docs/default.md`, `ts_js_tsx_jsx.md`
- `internal/config/template/prompts/main_task_system.md`
- `examples/github_actions/ocr-review.yml`
- `gh repo view` / `gh api` / `gh release list` — metadados e tree

### codebase-cleanup

- [`README.md`](../README.md)
- [`SKILL.md`](../SKILL.md)
- [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json)
- [`docs/plugin-spec-research.md`](plugin-spec-research.md) (convenção de research no repo)
- [`references/final-report.md`](../references/final-report.md)

---

## 11. Conclusão operacional

Trate o OCR como **vizinho de ecossistema**, não como biblioteca a embutir. O maior retorno para este repositório é importar a **disciplina** (preview, coverage, filtro de falso positivo, regras de projeto em camadas) e, opcionalmente, **apontar** o OCR para review de PR / QA da branch `cleanup/`. O menor retorno — e o maior risco — é fundir os dois produtos ou vendorar o CLI Go sob a skill MIT de faxina.
