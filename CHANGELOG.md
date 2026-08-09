# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento em [SemVer](https://semver.org/lang/pt-BR/).

A versão aqui e a de `.claude-plugin/plugin.json` são a mesma string, e
`scripts/coherence_test.sh` reprova quando deixam de ser. Não é zelo: a versão
do manifesto é a chave de cache que decide se uma instalação enxerga
atualização, e esquecer o bump falha em silêncio dos dois lados — ninguém
recebe erro, a correção só nunca chega.

## [0.2.0] — 2026-08-09

A fase 4 — remodelagem local. As três fases anteriores apagam, consolidam e
movem; nenhuma delas nunca tocou o interior de uma função. A auditoria da 1.4
já apontava função-deus e dívida de tipo numa coluna `Recommendation` que nada
consumia. Agora consome.

### Adicionado

- **Fase 4, remodelagem local** (`references/phase-4-refactor.md`). Vem depois
  da 3 pelo mesmo argumento que ordena o resto: remodelar função dentro de
  módulo que a fase 2 consolida, ou de arquivo que a fase 3 move, é trabalho
  feito duas vezes. O princípio de ordem passa a ter quatro termos.
- **Rede de segurança por alvo.** GREEN mede o repositório: diz que a suíte que
  existe passa, não quais linhas ela executa. Para reescrever o interior de uma
  função só importa se *aquela* função é exercitada — um repo GREEN com 4% de
  cobertura não autoriza nada, porque o gate verde depois da mudança prova que
  ainda compila, que é o que um refactor quebrado também prova. Alvo sem
  cobertura tem duas saídas: pular e registrar, ou escrever teste de
  caracterização como commit próprio. Não existe terceira.
- **Catálogo de 11 operações** (`references/refactoring-catalog.md`), em dois
  tiers. Tier A é mecânico e o gate é evidência real; tier B escolhe uma
  abstração ou um nome de domínio, e teste verde não atesta escolha — mesmo
  argumento do checkpoint da fase 2, uma altitude abaixo. Cada operação traz o
  que o gate atesta **e o que não atesta**.
- **Dois subagentes** (`cleanup-phase-4-survey`, `cleanup-phase-4-impl`). O
  survey não escreve: ele lê cobertura por alvo, e um survey que escreve fica a
  um passo de "consertar" o alvo que estava medindo.
- **`scripts/metrics.sh` + `metrics_test.sh`** (35 casos). Delta de qualidade
  antes/depois no relatório final. O cabeçalho declara que tudo ali é
  heurística textual, não parser, e que são evidência e não meta — picar função
  para baixar média é o dano que esta skill existe para evitar.
- **Saída honesta do RED.** No relatório, a skill passa a *propor* o teste de
  caracterização mínimo do caminho crítico. Propor não é se promover: o nível
  continua sendo medido, nunca concedido.

### Mudado

- O `SKILL.md` passa a declarar **um checkpoint condicional** na fase 4, além
  dos dois agendados — ele só existe se a fila tiver operação tier B.
- A fase 3 passa a fechar com `/clear`, como a fase 1 já fazia. Deixou de ser
  a última.
- `scripts/test.sh` encadeia cinco suítes. `coherence_test.sh` cobre os dois
  agentes novos e exige o `disallowedTools` do survey da fase 4. E os onze ids
  de operação deixam de ser onze strings copiadas à mão em quatro lugares: a
  seção 14 compara a tabela do catálogo, as seções do catálogo e as duas listas
  do `SKILL.md`, porque um id que existe num e não nos outros é ou uma operação
  que ninguém consegue rodar ou uma mensagem de commit que ninguém rastreia, e
  as duas falham caladas. 291 invariantes.

## [0.1.0] — 2026-08-09

Primeira versão publicada como plugin. A skill continua sendo uma pasta que
você pode copiar; o que muda é que agora ela também é instalável, versionada e
capaz de trazer garantias que uma skill sozinha não tem.

### Adicionado

- **Manifesto de plugin** (`.claude-plugin/plugin.json`). Com `SKILL.md` na
  raiz, a pasta carrega como plugin de skill única; copiada para
  `~/.claude/skills/`, carrega como plugin de diretório de skills.
- **Marketplace no próprio repo** (`.claude-plugin/marketplace.json`), então
  `/plugin marketplace add CRangelP/codebase-cleanup` e `/plugin update`
  passam a existir. Instalação por cópia continua funcionando.
- **Guardas de protocolo** (`hooks/hooks.json` → `scripts/guard.sh`). Cinco
  comandos que a skill proibia em prosa passam a ser bloqueados no
  `PreToolUse`: `git reset --hard`, `git clean`, `git push`, `git commit` na
  `main` e staging de árvore inteira. O guarda só acorda dentro de uma run —
  branch `cleanup/`, ou `CLEANUP_PROGRESS.md` não rastreado — e falha aberta
  em qualquer ambiguidade.
- **Cinco subagentes declarados** (`agents/`), um por fase, com survey e
  implementação separados nas fases 2 e 3. Os dois de survey declaram
  `disallowedTools: Write, Edit`, o que torna o checkpoint mecânico: a
  pergunta chega ao usuário antes de qualquer mudança.
- **Quarta suíte** (`scripts/guard_test.sh`), 42 casos. A metade que mais
  importa é o que o guarda deixa passar: rollback canônico, staging por
  pathspec, `revert`, `mv`, `stash push -u`.

### Alterado

- O gate é invocado por `"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` em todo o
  protocolo. Instalado como plugin a pasta vive num diretório de cache, e um
  caminho relativo seria lido como relativo ao projeto sendo limpo — onde o
  script não existe. O `:-.` mantém a instalação por cópia intacta.
- Instalado como plugin, a skill é invocada como
  `/codebase-cleanup:codebase-cleanup`: skills de plugin levam sempre o nome
  do plugin na frente.
- Invariantes de coerência: 151 → 248.
