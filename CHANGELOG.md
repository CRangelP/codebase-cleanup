# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento em [SemVer](https://semver.org/lang/pt-BR/).

A versão aqui e a de `.claude-plugin/plugin.json` são a mesma string, e
`scripts/coherence_test.sh` reprova quando deixam de ser. Não é zelo: a versão
do manifesto é a chave de cache que decide se uma instalação enxerga
atualização, e esquecer o bump falha em silêncio dos dois lados — ninguém
recebe erro, a correção só nunca chega.

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
