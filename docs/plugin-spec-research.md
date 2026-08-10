# O que é limite, o que é conselho e o que é hábito

Pesquisa consolidada para a issue #44. As fontes foram consultadas em **2026-08-10** e o
conteúdo deste arquivo vem inteiro de duas pesquisas em fonte primária já concluídas
(`/tmp/research-44/skill-format.md`, `/tmp/research-44/plugin-manifest.md`) e de uma medição
feita sobre o `SKILL.md` deste repositório (`/tmp/research-44/compaction-cut.md`). Nada aqui
vem de memória de modelo: toda afirmação carrega a citação literal, a URL exata e a data.
Onde a doc oficial não diz, está escrito que não diz.

A issue #44 registra o problema desta forma: as três coisas "têm peso diferente e hoje estão
misturadas na nossa cabeça". Enquanto elas continuarem misturadas, uma decisão de corte não
tem como ser argumentada — "500 linhas" soa igual a "30 MB" e igual a "todo mundo faz assim",
e as três exigem respostas diferentes. Separá-las é o produto principal deste documento; a
lista de mudanças no fim é subproduto.

## O que conta como oficial aqui, e por que isso importa

Existem três hosts oficiais e eles não dizem a mesma coisa. Essa é a causa raiz da confusão,
não um detalhe de citação:

| Fonte | URL | Papel |
| :--- | :--- | :--- |
| Claude Code Docs | `https://code.claude.com/docs/en/*` | Doc oficial da Anthropic **do host que executa este projeto**. `docs.claude.com/en/docs/claude-code/...` redireciona para cá (verificado com `curl -sL -o /dev/null -w "%{http_code} %{url_effective}"`, devolveu `200 https://code.claude.com/docs/en/plugins-reference`, 2026-08-10). |
| Claude Platform Docs | `https://platform.claude.com/docs/en/agents-and-tools/agent-skills/*` | Doc oficial da Anthropic para API e claude.ai. `docs.claude.com` e `docs.anthropic.com` redirecionam para cá (verificado com `curl -I`, 2026-08-10). |
| Agent Skills spec | `https://agentskills.io/specification` | Spec formal, oficial **por referência**: `anthropics/skills/spec/agent-skills-spec.md` contém só `"The spec is now located at <https://agentskills.io/specification>"` e `code.claude.com/docs/en/skills` a linka como "the Agent Skills spec". |

Um repositório distribuído como plugin do Claude Code responde primeiro ao primeiro host. Mas
o mesmo `SKILL.md` que hoje roda sob o Claude Code pode amanhã ser empacotado ou subir para o
claude.ai, e aí o segundo host passa a valer — com regras mais estreitas e falha dura (F8).
Por isso as duas colunas de origem convivem na tabela: o limite não deixa de existir só porque
o caminho ainda não é usado.

## Como ler as três colunas

**LIMITE DURO DO HOST** — o host se comporta assim; não é opinião de estilo. Inclui o
comportamento silencioso: truncar, ignorar campo, descartar entrada. Um limite duro que age em
silêncio é pior que um erro, porque o autor acredita ter uma garantia que não tem (F29).

**RECOMENDAÇÃO OFICIAL** — a doc oficial recomenda e explica; nada quebra se você não seguir.
Descumprir uma recomendação é uma decisão defensável, desde que a razão dela seja endereçada.

**CONVENÇÃO DA COMUNIDADE** — padrão observado, inclusive nos repositórios da Anthropic, sem
regra escrita. Não obriga nada, e serve principalmente para mostrar quando a própria Anthropic
não segue o que documentou (F78, F80). Uma convenção nunca é argumento para cortar código ou
texto; é no máximo evidência de que a folga existe.

As três colunas são mutuamente exclusivas por construção: cada achado aparece uma vez, com uma
marca só. Quando uma mesma passagem da doc contém as duas naturezas — um comportamento e um
conselho sobre ele — o achado foi partido em dois (F18 e F62, F37 e F65, F48 e F74), porque
juntá-los é exatamente o erro que a issue #44 pede para desfazer. O que **não** cabe em coluna
nenhuma são as contradições e as ausências: elas têm seções próprias, porque classificar uma
contradição seria escolher um lado.

## Tabela-resumo: 82 achados

| # | Achado | LIMITE DURO DO HOST | RECOMENDAÇÃO OFICIAL | CONVENÇÃO DA COMUNIDADE | Citação literal — fonte, consultada 2026-08-10 |
| :-- | :--- | :--: | :--: | :--: | :--- |
| F1 | `description` no máximo 1024 caracteres, não vazia | ✅ |  |  | "The [specification](/specification#description-field) enforces a hard limit of 1024 characters." — https://agentskills.io/skill-creation/optimizing-descriptions |
| F2 | No Claude Code, `description` + `when_to_use` são truncados em 1.536 caracteres na listagem | ✅ |  |  | "the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage" — https://code.claude.com/docs/en/skills |
| F3 | `name` de 1 a 64 caracteres, só `a-z0-9-`, sem `--`, sem hífen inicial ou final | ✅ |  |  | "Must be 1-64 characters", "Must not contain consecutive hyphens (`--`)" — https://agentskills.io/specification |
| F4 | `name` não pode conter as palavras reservadas "anthropic"/"claude" nem tags XML | ✅ |  |  | "Cannot contain reserved words: \"anthropic\", \"claude\"" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview |
| F5 | `name` tem de bater com o nome do diretório-pai | ✅ |  |  | "Must match the parent directory name" — https://agentskills.io/specification |
| F6 | `compatibility` no máximo 500 caracteres | ✅ |  |  | "Max 500 characters. Indicates environment requirements" — https://agentskills.io/specification |
| F7 | Upload de skill: 30 MB no total, no máximo 8 skills por request | ✅ |  |  | "Maximum Skill upload size: 30 MB (all files combined, uncompressed)" — https://platform.claude.com/docs/en/build-with-claude/skills-guide |
| F8 | Campo de frontmatter fora dos seis da spec quebra packaging/upload com erro duro | ✅ |  |  | "packaging or upload fails with a hard error instead of ignoring the field" — https://code.claude.com/docs/en/skills#using-skill-frontmatter-outside-claude-code |
| F9 | Depois da compactação sobrevivem os primeiros 5.000 tokens de cada skill, teto combinado de 25.000 | ✅ |  |  | "keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens" — https://code.claude.com/docs/en/skills#skill-content-lifecycle |
| F10 | Antes do disparo só `name` e `description` ocupam contexto | ✅ |  |  | "until a Skill is triggered, only its name and description occupy context" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview |
| F11 | No disparo entra o arquivo inteiro, não um trecho | ✅ |  |  | "the agent will load this entire file once it's decided to activate a skill" — https://agentskills.io/specification |
| F12 | No Claude Code o conteúdo renderizado fica na conversa até o fim da sessão e não é relido | ✅ |  |  | "stays there for the rest of the session" / "Claude Code does not re-read the skill file on later turns" — https://code.claude.com/docs/en/skills#skill-content-lifecycle |
| F13 | Metadata de cada skill instalada custa ~100 tokens permanentes | ✅ |  |  | "Metadata (~100 tokens): The `name` and `description` fields are loaded at startup for all skills" — https://agentskills.io/specification |
| F14 | Arquivo auxiliar não custa contexto até ser lido; script só devolve a saída | ✅ |  |  | "Files don't consume context until accessed" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview |
| F15 | `plugin.json` é opcional; havendo manifesto, só `name` é obrigatório | ✅ |  |  | "If you include a manifest, `name` is the only required field." — https://code.claude.com/docs/en/plugins-reference#required-fields |
| F16 | Campo de topo desconhecido é ignorado no runtime e vira warning, não erro | ✅ |  |  | "Claude Code ignores top-level fields it does not recognize." — https://code.claude.com/docs/en/plugins-reference#unrecognized-fields |
| F17 | Tipo errado em campo reconhecido derruba o carregamento do plugin | ✅ |  |  | "Most fields: the plugin fails to load." — https://code.claude.com/docs/en/plugins-reference#unrecognized-fields |
| F18 | `claude plugin validate --strict` converte warning em erro com exit 1 | ✅ |  |  | "Pass `--strict` to treat warnings as errors." — https://code.claude.com/docs/en/plugins-reference#unrecognized-fields |
| F19 | Apontado para a raiz do marketplace, o validador valida `marketplace.json`, e desde a v2.1.196 também as entradas cujo `source` é `.` | ✅ |  |  | "When pointed at a marketplace directory, the validator checks `marketplace.json` for schema errors... As of Claude Code v2.1.196, the per-entry pass also: includes plugins whose `source` is `.`" — https://code.claude.com/docs/en/plugin-marketplaces#marketplace-validation-errors |
| F20 | `marketplace.json` exige `name`, `owner` e `plugins` | ✅ |  |  | "required": ["name", "owner", "plugins"] — https://json.schemastore.org/claude-code-marketplace.json |
| F21 | Entrada de plugin exige `name` e `source` | ✅ |  |  | "Each plugin entry needs at minimum a `name` and a `source` that tells Claude Code where to fetch it from." — https://code.claude.com/docs/en/plugin-marketplaces#create-the-marketplace-file |
| F22 | `source` relativo começa com `./`, resolve contra a raiz do marketplace, e `../` é proibido | ✅ |  |  | "Resolved relative to the marketplace root, not the `.claude-plugin/` directory" / "Don't use `../`" — https://code.claude.com/docs/en/plugin-marketplaces#relative-paths |
| F23 | `source` relativo não resolve para quem adiciona o marketplace por URL direta ao JSON | ✅ |  |  | "If users add your marketplace via a direct URL to the `marketplace.json` file, relative paths won't resolve" — https://code.claude.com/docs/en/plugin-marketplaces#relative-paths |
| F24 | `metadata.description` e `metadata.version` continuam aceitos por compatibilidade | ✅ |  |  | "`description` and `version` are also accepted under `metadata` for backward compatibility." — https://code.claude.com/docs/en/plugin-marketplaces#optional-fields |
| F25 | `strict` default `true`: `plugin.json` é a autoridade e a entrada só suplementa | ✅ |  |  | "`true` (default) \| `plugin.json` is the authority." — https://code.claude.com/docs/en/plugin-marketplaces#strict-mode |
| F26 | Dezesseis nomes de marketplace são reservados para uso oficial da Anthropic | ✅ |  |  | "the following marketplace names are reserved for official Anthropic use" — https://code.claude.com/docs/en/plugin-marketplaces#required-fields |
| F27 | O Claude Desktop rejeita marketplace e descarta entrada em silêncio quando o nome foge de 128 caracteres alfanuméricos com `.`, `_` e `-` | ✅ |  |  | "Claude Desktop's managed marketplace sync rejects a marketplace whose name fails the check and silently drops a plugin entry whose name does." — https://code.claude.com/docs/en/plugin-marketplaces#marketplace-validation-errors |
| F28 | Agente de plugin não suporta `hooks`, `mcpServers` nem `permissionMode` | ✅ |  |  | "For security reasons, `hooks`, `mcpServers`, and `permissionMode` are not supported for plugin-shipped agents." — https://code.claude.com/docs/en/plugins-reference#agents |
| F29 | O mecanismo é ignorar em silêncio, não recusar o carregamento | ✅ |  |  | "These fields are ignored when loading agents from a plugin." — https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope |
| F30 | Nome de subagente com `:` não carrega e o erro só vai para o debug log | ✅ |  |  | "Claude Code doesn't load a file whose name contains one and logs an error to the debug log." — https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields |
| F31 | `agents/` de plugin é varrido recursivamente e a subpasta entra no identificador | ✅ |  |  | "a file at `agents/review/security.md` in plugin `my-plugin` registers as `my-plugin:review:security`" — https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope |
| F32 | `hooks/hooks.json` fica na raiz do plugin e os hooks se fundem com os de usuário e projeto | ✅ |  |  | "When a plugin is enabled, its hooks merge with your user and project hooks." — https://code.claude.com/docs/en/hooks#reference-scripts-by-path |
| F33 | Exit 2 bloqueia: stdout é ignorado e o stderr é entregue ao modelo como erro | ✅ |  |  | "Exit 2 means a blocking error... stderr text is fed back to Claude as an error message." — https://code.claude.com/docs/en/hooks#exit-code-output |
| F34 | Exit 1 não bloqueia nada, exceto em `WorktreeCreate` | ✅ |  |  | "Claude Code treats exit code 1 as a non-blocking error and proceeds with the action" — https://code.claude.com/docs/en/hooks#exit-code-output |
| F35 | `matcher` com qualquer caractere fora de letras, dígitos, `_`, `-`, espaço, vírgula e barra vertical vira regex JS não ancorada | ✅ |  |  | "A matcher on the regular-expression path is tested with JavaScript's `RegExp.prototype.test`, which succeeds on a match anywhere in the value." — https://code.claude.com/docs/en/hooks#matcher-patterns |
| F36 | O campo `if` só é avaliado em eventos de ferramenta; nos demais o hook nunca roda | ✅ |  |  | "On other events, a hook with `if` set never runs." — https://code.claude.com/docs/en/hooks#common-fields |
| F37 | Matcher só com `Bash` nunca dispara no Windows sem Git Bash | ✅ |  |  | "A hook that matches only `Bash` never fires there." — https://code.claude.com/docs/en/hooks#pretooluse |
| F38 | `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` e `${CLAUDE_PROJECT_DIR}` resolvem em qualquer ponto do comando do hook e são exportados como variáveis de ambiente | ✅ |  |  | "All three are exported as environment variables to hook processes" / "Hook and monitor commands \| Anywhere the placeholder appears" — https://code.claude.com/docs/en/plugins-reference#environment-variables |
| F39 | `${CLAUDE_PLUGIN_ROOT}` muda a cada atualização e o diretório antigo é efêmero | ✅ |  |  | "`${CLAUDE_PLUGIN_ROOT}` changes when the plugin updates... treat it as ephemeral and don't write state there." — https://code.claude.com/docs/en/plugins-reference#environment-variables |
| F40 | Todo componente que não seja `plugin.json` fica na raiz do plugin, nunca dentro de `.claude-plugin/` | ✅ |  |  | "All other directories (commands/, agents/, skills/, workflows/, output-styles/, themes/, monitors/, hooks/) must be at the plugin root, not inside `.claude-plugin/`." — https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout |
| F41 | `CLAUDE.md` na raiz do plugin não é carregado como contexto de projeto | ✅ |  |  | "A `CLAUDE.md` file at the plugin root is not loaded as project context." — https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout |
| F42 | `SKILL.md` na raiz, sem `skills/` e sem campo `skills`, carrega como skill único desde a v2.1.142 | ✅ |  |  | "is automatically loaded as a single-skill plugin in Claude Code v2.1.142 and later" — https://code.claude.com/docs/en/plugins-reference#path-behavior-rules |
| F43 | Sem `name` no frontmatter, o nome de invocação cai no diretório de instalação — uma string de versão que muda a cada atualização | ✅ |  |  | "Claude Code falls back to the install directory name, which for marketplace-installed plugins is a version string that changes on every update." — https://code.claude.com/docs/en/plugins-reference#skills |
| F44 | `version` é a chave de cache: sem bump, commit novo não chega a quem já instalou | ✅ |  |  | "Pushing new commits without bumping it has no effect, and `/plugin update` reports \"already at the latest version\"." — https://code.claude.com/docs/en/plugins-reference#version-management |
| F45 | A versão resolve em cascata: `plugin.json`, entrada do marketplace, commit SHA, digest SHA-256, `unknown` | ✅ |  |  | "The version is resolved from the first of these that is set" — https://code.claude.com/docs/en/plugins-reference#version-management |
| F46 | Plugins de marketplace são copiados para `~/.claude/plugins/cache`, uma pasta por versão, órfãs removidas em 14 dias | ✅ |  |  | "copies marketplace plugins to the user's local plugin cache (`~/.claude/plugins/cache`) rather than using them in-place" — https://code.claude.com/docs/en/plugins-reference#plugin-caching-and-file-resolution |
| F47 | Auto-update vem ligado só em marketplace oficial da Anthropic; terceiro e local vêm desligados | ✅ |  |  | "Third-party and local development marketplaces have auto-update disabled by default." — https://code.claude.com/docs/en/discover-plugins#configure-auto-updates |
| F48 | Plugin carregado com `--plugin-dir` tem precedência sobre o instalado de mesmo nome | ✅ |  |  | "the local copy takes precedence for that session" — https://code.claude.com/docs/en/plugins#test-your-plugins-locally |
| F49 | Manter o corpo do `SKILL.md` abaixo de 500 linhas e mover referência detalhada para arquivos separados |  | ✅ |  | "Keep SKILL.md body under 500 lines for optimal performance" / "Split content into separate files when approaching this limit" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| F50 | Manter o corpo abaixo de 5.000 tokens |  | ✅ |  | "Instructions (< 5000 tokens recommended): The full `SKILL.md` body is loaded when the skill is activated" — https://agentskills.io/specification |
| F51 | Manter o corpo conciso porque cada linha vira custo recorrente de token |  | ✅ |  | "Once a skill loads, its content stays in context across turns, so every line is a recurring token cost. State what to do rather than narrating how or why" — https://code.claude.com/docs/en/skills#types-of-skill-content |
| F52 | Escrever como instrução permanente, não como passo único, já que não há releitura |  | ✅ |  | "write guidance that should apply throughout a task as standing instructions rather than one-time steps" — https://code.claude.com/docs/en/skills#skill-content-lifecycle |
| F53 | Referências a um único nível de profundidade a partir do `SKILL.md` |  | ✅ |  | "Keep references one level deep from SKILL.md... Claude may partially read files when they're referenced from other referenced files... resulting in incomplete information" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| F54 | Sumário no topo de arquivo de referência longo, para o caso de leitura parcial |  | ✅ |  | "For reference files longer than 100 lines, include a table of contents at the top." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| F55 | Apontar cada arquivo auxiliar a partir do `SKILL.md` dizendo **quando** abri-lo |  | ✅ |  | "Read `references/api-errors.md` if the API returns a non-200 status code" is more useful than a generic "see references/ for details." — https://agentskills.io/skill-creation/best-practices |
| F56 | Manter cada arquivo de referência focado, porque menor significa menos contexto na hora da leitura |  | ✅ |  | "Keep individual reference files focused. Agents load these on demand, so smaller files mean less use of context." — https://agentskills.io/specification |
| F57 | A `description` diz o que a skill faz e quando usá-la, com termos-gatilho específicos |  | ✅ |  | "The `description` field enables Skill discovery and should include both what the Skill does and when to use it." — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| F58 | Ser explícito no gatilho, inclusive quando o usuário não nomeia o domínio |  | ✅ |  | "Err on the side of being pushy. Explicitly list contexts where the skill applies, including cases where the user doesn't name the domain directly" — https://agentskills.io/skill-creation/optimizing-descriptions |
| F59 | Avaliar o disparo com ~20 consultas, 8 a 10 que devem disparar e 8 a 10 que não devem |  | ✅ |  | "Aim for about 20 queries: 8-10 that should trigger and 8-10 that shouldn't." — https://agentskills.io/skill-creation/optimizing-descriptions |
| F60 | Criar ao menos três avaliações e testar com Haiku, Sonnet e Opus |  | ✅ |  | "[ ] At least three evaluations created / [ ] Tested with Haiku, Sonnet, and Opus" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| F61 | Diretórios `scripts/`, `references/` e `assets/` como partição do conteúdo auxiliar |  | ✅ |  | "scripts/ # Optional: executable code / references/ # Optional: documentation / assets/ # Optional: templates, resources" — https://agentskills.io/specification |
| F62 | Usar `--strict` em CI para pegar campo mal escrito antes de publicar |  | ✅ |  | "Use it in CI to catch a misspelled field name or a field left over from another tool's manifest before publishing" — https://code.claude.com/docs/en/plugins-reference#unrecognized-fields |
| F63 | Validar o diretório do plugin, e não só a raiz do marketplace, para cobrir `plugin.json` e os arquivos de skill, agente, comando e hook |  | ✅ |  | "To validate an individual plugin's `plugin.json` and its skill, agent, command, and hook files, run the command against the plugin directory itself" — https://code.claude.com/docs/en/plugin-marketplaces#marketplace-validation-errors |
| F64 | Rodar `claude plugin validate ./your-plugin` antes de submeter ao marketplace da comunidade |  | ✅ |  | "Run `claude plugin validate ./your-plugin` locally before you submit" — https://code.claude.com/docs/en/plugins#submit-your-plugin-to-the-community-marketplace |
| F65 | Casar `Bash\|PowerShell` em hook que inspeciona comando de shell |  | ✅ |  | "Match `Bash\|PowerShell` in hooks that inspect shell commands, so they cover both tools" — https://code.claude.com/docs/en/hooks#pretooluse |
| F66 | Usar exec form com `args` quando o hook referencia placeholder de caminho; em shell form, envolver em aspas duplas |  | ✅ |  | "Set `args` whenever the hook references a path placeholder, since each element is passed as one argument with no quoting." — https://code.claude.com/docs/en/hooks#exec-form-and-shell-form |
| F67 | Quem precisa de `hooks`/`mcpServers`/`permissionMode` copia o agente para `.claude/agents/` ou usa `permissions.allow`, que vale para a sessão inteira |  | ✅ |  | "If you need them, copy the agent file into `.claude/agents/` or `~/.claude/agents/`." — https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope |
| F68 | Plugin entrega contexto por skill, agente e hook — instrução que precisa entrar em contexto vira skill |  | ✅ |  | "Plugins contribute context through skills, agents, and hooks rather than CLAUDE.md. To ship instructions that load into Claude's context, put them in a skill." — https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout |
| F69 | Usar `skills/` em vez de `commands/` em plugin novo |  | ✅ |  | "Commands \| `commands/` \| Skills as flat Markdown files. Use `skills/` for new plugins" — https://code.claude.com/docs/en/plugins-reference#file-locations-reference |
| F70 | Fixar o `name` no frontmatter para controlar o nome de invocação da skill |  | ✅ |  | "Set the frontmatter `name` field to control the skill's invocation name." — https://code.claude.com/docs/en/plugins-reference#skills |
| F71 | Publicar com `README.md` contendo instruções de instalação e uso |  | ✅ |  | "Add documentation: Include a `README.md` with installation and usage instructions" — https://code.claude.com/docs/en/plugins#share-your-plugins |
| F72 | `LICENSE` e `CHANGELOG.md` na raiz do plugin |  | ✅ |  | "├── LICENSE  # License file" e "└── CHANGELOG.md  # Version history", no bloco "Standard plugin layout" — https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout |
| F73 | Versão explícita segue semver e a mudança é documentada em `CHANGELOG.md` |  | ✅ |  | "follow semantic versioning (`MAJOR.MINOR.PATCH`)... Document changes in a `CHANGELOG.md`." — https://code.claude.com/docs/en/plugins-reference#version-management |
| F74 | Testar localmente com `--plugin-dir`, sem instalar |  | ✅ |  | "Use the `--plugin-dir` flag to test plugins during development. This loads your plugin directly without requiring installation." — https://code.claude.com/docs/en/plugins#test-your-plugins-locally |
| F75 | Pedir que outras pessoas testem o plugin antes de distribuir |  | ✅ |  | "Test with others: Have team members test the plugin before wider distribution" — https://code.claude.com/docs/en/plugins#share-your-plugins |
| F76 | Todo plugin oficial da Anthropic tem `README.md` na raiz do plugin — sem regra escrita sobre forma ou tamanho |  |  | ✅ | `plugin-dev` → "README.md, agents, commands, skills"; `hookify` → ".claude-plugin, .gitignore, README.md, agents, commands, core, examples, hooks, matchers, skills, utils"; `pr-review-toolkit` → ".claude-plugin, README.md, agents, commands" — https://api.github.com/repos/anthropics/claude-code/contents/plugins |
| F77 | Nenhum plugin oficial usa `references/`; os diretórios auxiliares recebem nomes livres |  |  | ✅ | `core/`, `utils/`, `matchers/`, `examples/` no `hookify` — https://api.github.com/repos/anthropics/claude-code/contents/plugins |
| F78 | A Anthropic publica SKILL.md acima da própria recomendação: `claude-api` com 548 linhas e 72.716 bytes |  |  | ✅ | medido em `anthropics/skills` @ `main`: "skills/claude-api/SKILL.md \| 548 \| 72.716" — https://api.github.com/repos/anthropics/skills (árvore @ `main`) |
| F79 | Plugin oficial pode não ter manifesto: `plugin-dev` não tem `.claude-plugin/` |  |  | ✅ | "`https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/plugin-dev/.claude-plugin/plugin.json` → `404: Not Found`" — https://api.github.com/repos/anthropics/claude-code/contents/plugins |
| F80 | O `hookify` oficial usa shell form sem aspas no placeholder, contra a recomendação de exec form |  |  | ✅ | "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.py" — https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/hooks/hooks.json |
| F81 | Agente de plugin oficial usa frontmatter mínimo: `name`, `description`, `model`, `color` |  |  | ✅ | `plugins/pr-review-toolkit/agents/code-reviewer.md`: apenas `name`, `description`, `model: opus`, `color: green` — https://api.github.com/repos/anthropics/claude-code/contents/plugins/pr-review-toolkit/agents |
| F82 | O marketplace oficial da Anthropic declara `$schema` apontando para o schemastore |  |  | ✅ | primeira linha: "$schema": "https://json.schemastore.org/claude-code-marketplace.json" — https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json |

Contagem: **48 limites duros do host, 27 recomendações oficiais, 7 convenções da comunidade.**
A desproporção é informativa. Quase tudo que a doc diz sobre plugin é comportamento verificável
do host; quase tudo que ela diz sobre tamanho de arquivo é conselho. Um corte no `SKILL.md`
justificado por "a doc manda" está apoiado em 27 linhas desta tabela, não em 48.

## Onde estes limites encostam neste repositório

Medidas do repositório citadas abaixo vêm dos arquivos de pesquisa, medidas em 2026-08-10:
`SKILL.md` com 837 linhas e 44.801 bytes, frontmatter com `name` de 16 caracteres e
`description` de 997 caracteres, `README.md` com 411 linhas, `README.en.md` com 418,
`plugin.json` com `"version": "0.3.3"`, entrada de marketplace com `source: "."`,
`hooks/hooks.json` com `"matcher": "Bash"` em shell form, sete agentes usando apenas `name`,
`description` e `disallowedTools`, e os diretórios `references/` e `scripts/` já existentes.

### O corte de 5.000 tokens é o único limite duro que o corpo do `SKILL.md` viola

Não existe limite duro de tamanho para o corpo — a spec diz o contrário com todas as letras:

> "The Markdown body after the frontmatter contains the skill instructions. **There are no format restrictions.** Write whatever helps agents perform the task effectively."
> — https://agentskills.io/specification, consultado 2026-08-10

O que existe é um corte de contexto, e ele é numérico:

> "When the conversation is summarized to free context, Claude Code re-attaches the most recent invocation of each skill after the summary, **keeping the first 5,000 tokens of each**. Re-attached skills share a **combined budget of 25,000 tokens**."
> — https://code.claude.com/docs/en/skills#skill-content-lifecycle, consultado 2026-08-10

A medição em `/tmp/research-44/compaction-cut.md` converteu esse corte em bytes do arquivo
atual. Na conversão mais generosa (4,0 bytes por token), 5.000 tokens são 20.000 bytes, o que
cai na linha 351; a 3,5 bytes por token o corte cai na linha 300, e a 3,0, na linha 241. O que
sobrevive e o que morre, por byte:

| Sobrevive ao corte | byte | Morre no corte | byte |
| :--- | ---: | :--- | ---: |
| rollback canônico `git restore --staged --worktree .` | 2.104 | checkpoint irredutível da fase 2 | 32.239 |
| staging por pathspec `git add -- <paths>` | 2.767 | fase 3 — checkpoint antes de mover | 35.161 |
| hook de segurança / abortar | 3.061 | fase 4 — tier B para no checkpoint | 37.537 |
| tabela de níveis GREEN/YELLOW/RED | 9.680 | "Rules that apply to the whole pipeline" | 40.732 |
| caps por stack sobrepõem a coluna GREEN | 10.808 | | |

O bloco do byte 40.732 contém `/clear` entre fases ("Not optional"), "Never merge two steps",
"A red gate means rollback, not repair" e "Never force push, never commit on main". Uma limpeza
de codebase é longa por natureza, então a auto-compactação é o caso esperado, não a exceção.
Depois dela a skill continua anunciando o nível de autonomia e perde as regras que dizem o que
o nível obriga a fazer. O problema não é o tamanho do arquivo: é a **ordem** dele.

O mesmo host explica por que a ordem importa tanto — o conteúdo não é relido:

> "When you or Claude invoke a skill, the **rendered** `SKILL.md` content enters the conversation **as a single message and stays there for the rest of the session**." / "**Claude Code does not re-read the skill file on later turns**, so write guidance that should apply throughout a task as standing instructions rather than one-time steps."
> — https://code.claude.com/docs/en/skills#skill-content-lifecycle, consultado 2026-08-10

### A `description` está a 27 caracteres do teto

> "`description`: Must be non-empty / Maximum 1024 characters / Cannot contain XML tags"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview, consultado 2026-08-10

Com 997 caracteres, o orçamento de 1.000 usado hoje é o teto prático correto: conservador o
suficiente para não estourar por acidente e alinhado ao limite real. A margem é de 27
caracteres, o que significa que qualquer termo-gatilho novo exige remover outro.

### `version` não é cosmético, é a chave de cache

> "Pushing new commits without bumping it has no effect, and `/plugin update` reports **"already at the latest version"**."
> — https://code.claude.com/docs/en/plugins-reference#version-management, consultado 2026-08-10

Como `plugin.json` fixa `"version": "0.3.3"` e a entrada do marketplace não traz `version`, a
versão resolvida é a do manifesto (F45). Qualquer commit publicado sem bump não chega a quem já
instalou. Isso põe o bump dentro do fluxo de release, não depois dele.

### O hook casa só `Bash`, e há uma plataforma onde isso nunca dispara

> "Match `Bash|PowerShell` in hooks that inspect shell commands, so they cover both tools: ... On Windows without Git Bash, the tool is enabled automatically and Claude Code doesn't register the Bash tool at all. **A hook that matches only `Bash` never fires there.**"
> — https://code.claude.com/docs/en/hooks#pretooluse, consultado 2026-08-10

A recomendação (F65) e a consequência (F37) são coisas diferentes e por isso estão em linhas
separadas: a segunda é comportamento do host, e é ela que transforma a primeira em algo mais
que estilo. Vale notar que as aspas duplas em torno de `${CLAUDE_PLUGIN_ROOT}` no hook atual já
seguem a regra de shell form (F66).

### A regra do repositório sobre agente de plugin está certa no efeito e frouxa no texto

> "**For security reasons, `hooks`, `mcpServers`, and `permissionMode` are not supported for plugin-shipped agents.**"
> — https://code.claude.com/docs/en/plugins-reference#agents, consultado 2026-08-10

> "**These fields are ignored when loading agents from a plugin.** If you need them, copy the agent file into `.claude/agents/` or `~/.claude/agents/`."
> — https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope, consultado 2026-08-10

"Ignorado" não é "rejeitado". Um agente de plugin que declare `hooks` carrega assim mesmo, com
o campo descartado em silêncio, e `claude plugin validate` não reclama — a guarda do repositório
é a única que existe. O texto da regra precisa dizer isso, porque quem lê "inválido" espera que
o validador pegue, e ele não pega.

### O layout atual está conforme, e o modo de carregamento é o documentado

> "A plugin that has a `SKILL.md` at its root, no `skills/` subdirectory, and no `skills` manifest field is automatically loaded as a single-skill plugin in Claude Code v2.1.142 and later."
> — https://code.claude.com/docs/en/plugins-reference#path-behavior-rules, consultado 2026-08-10

`references/` e `scripts/` são exatamente o que a spec chama de partição de conteúdo auxiliar
(F61), e `scripts/` aparece no layout oficial de plugin com o rótulo "Hook and utility scripts".
`LICENSE` e `CHANGELOG.md`, pedidos pelo layout padrão (F72) e pelo texto de versionamento
(F73), já existem na raiz.

## Contradições entre páginas oficiais

Cada item registra **as duas versões**, sem escolher lado, e diz o que este repositório fica
proibido de afirmar por causa da divergência. Escolher lado aqui seria inventar autoridade que
nenhuma das páginas dá.

### C1 — `name` e `description` são obrigatórios, ou tudo é opcional?

> "**Required fields:** `name` and `description`"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview, consultado 2026-08-10
> "| `name` | Yes | ... | `description` | Yes | ..."
> — https://agentskills.io/specification, consultado 2026-08-10

contra

> "All fields are optional. Only `description` is recommended so Claude knows when to use the skill."
> — https://code.claude.com/docs/en/skills, consultado 2026-08-10

A leitura conciliadora plausível — o Claude Code lê do filesystem e cai no nome do diretório,
enquanto a API valida um upload — **não está escrita em página nenhuma**. O repositório não pode
afirmar "o frontmatter mínimo obrigatório é X" como fato do host; pode dizer que declara os dois
campos porque isso satisfaz os três hosts de uma vez.

### C2 — 1.024 ou 1.536 caracteres de `description`?

> "The [specification] enforces a hard limit of 1024 characters."
> — https://agentskills.io/skill-creation/optimizing-descriptions, consultado 2026-08-10

contra

> "the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage"
> — https://code.claude.com/docs/en/skills, consultado 2026-08-10

Os dois números medem coisas diferentes: 1.024 é validação de upload e packaging sobre a
`description` sozinha, com falha; 1.536 é truncagem silenciosa do Claude Code sobre
`description` + `when_to_use` somados. **Nenhuma página diz como eles interagem.** O repositório
não pode afirmar "o limite é 1.024" sem dizer de qual host, nem afirmar que uma `description` de
1.024 caracteres passa intacta pela listagem do Claude Code — que 1.024 < 1.536 é aritmética
nossa, não citação.

### C3 — `references/`, `reference/` ou arquivos soltos na raiz?

> "```
> skill-name/
> ├── SKILL.md          # Required: metadata + instructions
> ├── scripts/          # Optional: executable code
> ├── references/       # Optional: documentation
> ├── assets/           # Optional: templates, resources
> ```"
> — https://agentskills.io/specification, consultado 2026-08-10

contra

> "```
> bigquery-skill/
> ├── SKILL.md (overview and navigation)
> └── reference/
>     ├── finance.md ...
> ```"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10

E um terceiro arranjo, com arquivos soltos, na doc do host que executa este projeto — onde a
string `references/` sequer aparece:

> "```
> my-skill/
> ├── SKILL.md (required - overview and navigation)
> ├── reference.md (detailed API docs - loaded when needed)
> ├── examples.md (usage examples - loaded when needed)
> └── scripts/
>     └── helper.py (utility script - executed, not loaded)
> ```"
> — https://code.claude.com/docs/en/skills#add-supporting-files, consultado 2026-08-10

Não há convenção única e nenhum host força qualquer uma delas. O repositório não pode afirmar
que `references/` é "o padrão oficial"; pode afirmar que é o nome usado pela spec e pelo
`skill-creator` da Anthropic, e que por isso não vale renomear.

### C4 — o corpo é lido com `cat` na hora, ou injetado e mantido?

> "3. **Claude invokes:** `bash: cat pdf-processing/SKILL.md` → Instructions loaded into context"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview, consultado 2026-08-10

contra

> "the **rendered** `SKILL.md` content enters the conversation **as a single message and stays there for the rest of the session**" / "**Claude Code does not re-read the skill file on later turns**"
> — https://code.claude.com/docs/en/skills#skill-content-lifecycle, consultado 2026-08-10

As duas descrevem hosts diferentes e o texto não as reconcilia. O repositório não pode afirmar
"o Claude relê a skill quando precisa" — sob o Claude Code, a doc diz o oposto. E não pode
generalizar o modelo do Claude Code para a API sem citar que a página da plataforma descreve
leitura sob demanda.

### C5 — `description` em terceira pessoa ou no imperativo?

> "**Always write in third person**. ... **Good:** "Processes Excel files and generates reports""
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10

contra

> "**Use imperative phrasing.** Frame the description as an instruction to the agent: "Use this skill when..." rather than "This skill does...""
> — https://agentskills.io/skill-creation/optimizing-descriptions, consultado 2026-08-10

Os exemplos oficiais fazem as duas coisas na mesma frase, mas **nenhuma página escreve essa
síntese**. O repositório não pode transformar nenhuma das duas em regra de revisão da própria
`description`.

### C6 — sumário em arquivo de referência: acima de 100 ou de 300 linhas?

> "For reference files longer than 100 lines, include a table of contents at the top."
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10

contra

> "For large reference files (>300 lines), include a table of contents"
> — https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md, consultado 2026-08-10

O repositório não pode usar nenhum dos dois números como critério de aceite; a razão por trás
dos dois é a mesma e é citável ("Claude can see the full scope of available information even
when previewing with partial reads"), e é ela que deve orientar, não o número.

### C7 — 500 linhas é regra ou é folga declarada?

> "Keep SKILL.md body under 500 lines for optimal performance" e, no checklist, "- [ ] SKILL.md body is under 500 lines"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10

contra, no material oficial da própria Anthropic:

> "**SKILL.md body** - In context whenever skill triggers (<500 lines ideal)" ... "These word counts are approximate and **you can feel free to go longer if needed**."
> — https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md, consultado 2026-08-10

E a prática publicada contradiz o checklist: `skills/claude-api/SKILL.md` tem 548 linhas e
72.716 bytes — mais que o `SKILL.md` deste repositório — medido em `anthropics/skills` @ `main`
via API do GitHub em 2026-08-10. O repositório não pode dizer que passar de 500 linhas
"viola a doc"; o que ele pode dizer é que passa de um número recomendado cujo próprio autor
declara folga.

### C8 — `color` e `initialPrompt` valem em agente de plugin?

> "Plugin agents support `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, and `isolation` frontmatter fields."
> — https://code.claude.com/docs/en/plugins-reference#agents, consultado 2026-08-10

contra a tabela geral, que lista `color` e `initialPrompt` e marca explicitamente como ignorados
em plugin apenas `permissionMode`, `mcpServers` e `hooks`:

> "`permissionMode` … Ignored for [plugin subagents](#choose-the-subagent-scope)"
> — https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields, consultado 2026-08-10

Leitura 1: a lista de plugins-reference é exaustiva e `color`/`initialPrompt` não valem.
Leitura 2: a tabela de sub-agents é a autoridade por campo e a lista é ilustrativa. Nenhuma
resolve a outra. O repositório **não pode** transformar essa lista de onze campos em asserção da
suíte de coerência sem medir o comportamento real do host.

### C9 — a página de Hooks não repete a exceção de plugin

> "| [Skill](/docs/en/skills) or [agent](/docs/en/sub-agents) frontmatter | While the component is active | Yes, defined in the component file |" e "Subagents use the same format in their YAML frontmatter."
> — https://code.claude.com/docs/en/hooks#hook-locations e #hooks-in-skills-and-agents, consultado 2026-08-10

contra a proibição explícita de F28. Formalmente não é contradição — a página de hooks nunca
afirma que agente *de plugin* pode — mas é silêncio no lugar exato onde o leitor procuraria a
regra, e quem só ler `hooks.md` conclui o contrário. Registrado como lacuna de cobertura entre
três páginas oficiais da mesma data. O repositório não pode citar `hooks.md` como fonte do que
vale para agente de plugin.

### C10 — o JSON Schema publicado está defasado em relação à doc

O schema referenciado pela própria doc traz `"$comment": "Generated on 2026-04-23T05:09:41.810Z"`
e `"required": ["name"]`, mas **não** contém `displayName`, `metadata`, `defaultEnabled`,
`workflows` nem o agrupador `experimental`, que a doc de 2026-08-10 documenta
(https://json.schemastore.org/claude-code-plugin-manifest.json contra
https://code.claude.com/docs/en/plugins-reference#metadata-fields, ambos consultados em
2026-08-10). Não é contradição de conteúdo, é defasagem de artefato — e ela é coerente com
"Claude Code ignores top-level fields it does not recognize", já que o schema também não declara
`additionalProperties: false`. O repositório não pode usar esse schema como definição do conjunto
de campos válidos.

## NÃO ENCONTRADO

O que se procurou em fonte oficial e não existe. A ausência é resultado, não lacuna de pesquisa:
enquanto ela não estiver escrita aqui, alguém vai voltar a supor que existe.

**Recomendação de tamanho ou estrutura de README de plugin.** Varridas em 2026-08-10, sem
nenhum resultado sobre tamanho, número de seções ou forma:
`https://code.claude.com/docs/en/plugins.md`, `.../plugins-reference.md`,
`.../plugin-marketplaces.md`, `.../discover-plugins.md`, `.../plugin-dependencies.md`,
`.../hooks.md`, `.../hooks-guide.md`, `.../sub-agents.md`, `.../skills.md`, e o índice
`https://code.claude.com/docs/llms.txt`. `grep -i README` nas nove páginas devolve duas
ocorrências, e a única normativa é sobre **existir**, não sobre extensão:

> "1. **Add documentation**: Include a `README.md` with installation and usage instructions"
> — https://code.claude.com/docs/en/plugins#share-your-plugins, consultado 2026-08-10

Isto importa diretamente para a #44. A issue propunha cortar os READMEs "seguindo boas
práticas", e **não há boa prática oficial a seguir**: qualquer corte no `README.md` (411 linhas)
ou no `README.en.md` (418) será decisão nossa, argumentada por nós, e não aderência a padrão
externo. O que existe e é frequentemente confundido com isso é a regra de tamanho do `SKILL.md`,
que é outro arquivo, com outro custo — o README não entra no contexto do modelo.

**Limite duro de tamanho para o corpo do `SKILL.md`.** Procurado em
`code.claude.com/docs/en/skills`, `platform.claude.com/.../agent-skills/overview`,
`.../agent-skills/best-practices`, `platform.claude.com/docs/en/build-with-claude/skills-guide` e
`agentskills.io/specification`. Nenhuma estabelece limite de bytes ou linhas, e a spec afirma
"There are no format restrictions" (URL em §"Onde estes limites encostam"). O único limite duro
de tamanho é do pacote inteiro, no caminho da API: 30 MB e 8 skills por request (F7).

**Como 1.024 e 1.536 interagem.** Nenhuma página diz se uma `description` no teto da spec é
truncada pelo Claude Code. Ver C2.

**Limite de tamanho de `name` na doc do Claude Code.** O host que executa este projeto só diz
que é display name com fallback para o nome do diretório; os 64 caracteres vêm da spec e da
plataforma (F3).

**Reconciliação entre "required" e "all fields are optional".** Ver C1: a explicação plausível
não está escrita em lugar nenhum.

**`references/` na doc de plugin.** O layout padrão de plugin lista `LICENSE` e `CHANGELOG.md` e
**não** lista `README.md` nem `references/`
(https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout, 2026-08-10). Nenhum
plugin oficial da Anthropic usa `references/` (F77). Isso não torna o diretório irregular — só
significa que ele é escolha nossa, amparada pela spec de skills, não pela doc de plugins.

**`color`/`initialPrompt` em agente de plugin.** Ver C8: as duas páginas oficiais não se
resolvem.

## Divergências entre os dois arquivos de pesquisa de entrada

Nenhuma divergência de número, campo ou URL. Onde os dois medem a mesma coisa, o valor é o
mesmo: `SKILL.md` com 837 linhas e 44.801 bytes, e a recomendação de 500 linhas atribuída às
mesmas páginas. Há uma diferença apenas de ancoragem: `skill-format.md` cita a regra das 500
linhas em `https://code.claude.com/docs/en/skills#add-supporting-files` e `plugin-manifest.md`
cita o mesmo conteúdo em `https://code.claude.com/docs/en/skills` — mesma página, âncora
diferente. Registrado para que ninguém leia isso como duas fontes independentes.

## O que este repositório precisa mudar

Em ordem de impacto. Cada item traz a citação que o justifica. **Nada aqui foi implementado** —
este documento é insumo para a decisão, não patch.

**1. Reordenar o `SKILL.md` para que toda regra que decide autoridade destrutiva caiba nos
primeiros 5.000 tokens.** É o único item da lista apoiado num limite duro do host que o arquivo
atual viola de fato:

> "keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens"
> — https://code.claude.com/docs/en/skills#skill-content-lifecycle, consultado 2026-08-10

Hoje, medido, o que morre na compactação é "Never force push, never commit on main", "A red gate
means rollback, not repair", "Never merge two steps" e o `/clear` obrigatório entre fases (byte
40.732), enquanto a tabela de níveis sobrevive (byte 9.680). O nível de autonomia continua sendo
anunciado depois que as regras que o limitam já sumiram. O critério de aceite proposto é de
ordem, não de tamanho, e é mensurável como invariante executável.

**2. Tratar o bump de `version` no `plugin.json` como parte obrigatória do release.**

> "Pushing new commits without bumping it has no effect, and `/plugin update` reports "already at the latest version"."
> — https://code.claude.com/docs/en/plugins-reference#version-management, consultado 2026-08-10

Com `"version": "0.3.3"` fixo no manifesto e sem `version` na entrada do marketplace, é o
manifesto que resolve a versão (F45). Sem bump, nenhuma das mudanças decididas nesta issue chega
a quem já instalou.

**3. Corrigir o texto da regra sobre `hooks`/`mcpServers`/`permissionMode` em agente para
"silenciosamente ignorado pelo host", não "inválido".**

> "These fields are ignored when loading agents from a plugin."
> — https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope, consultado 2026-08-10

O efeito que a suíte de coerência defende está correto e agora tem duas URLs oficiais. O que
está errado é a expectativa embutida na palavra: `claude plugin validate` não sinaliza isso, o
agente carrega assim mesmo, e a guarda do repositório é a única que existe.

**4. Trocar o matcher `"Bash"` do hook por `Bash|PowerShell`.**

> "A hook that matches only `Bash` never fires there."
> — https://code.claude.com/docs/en/hooks#pretooluse, consultado 2026-08-10

Um hook de segurança que não dispara numa plataforma inteira é pior que ausência de hook, porque
a proteção é anunciada. A mudança é de uma linha em `hooks/hooks.json`.

**5. Reescrever a justificativa de qualquer corte nos READMEs.** A #44 propôs cortar "seguindo
boas práticas". A única menção normativa a README na doc de plugins é sobre existir:

> "Add documentation: Include a `README.md` with installation and usage instructions"
> — https://code.claude.com/docs/en/plugins#share-your-plugins, consultado 2026-08-10

Não há recomendação oficial de tamanho ou estrutura (lista de URLs varridas na seção NÃO
ENCONTRADO). Cortar 411 e 418 linhas de README pode continuar sendo a decisão certa — mas o
argumento tem de ser nosso, sobre leitor humano e manutenção de duas traduções, e não "a doc
manda". Um corte justificado por padrão inexistente vira dívida de argumento na próxima revisão.

**6. Tratar as 500 linhas e os 5.000 tokens como meta subordinada ao item 1.**

> "Keep SKILL.md body under 500 lines for optimal performance"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10
> "Instructions (< 5000 tokens recommended)"
> — https://agentskills.io/specification, consultado 2026-08-10

São recomendações, com folga declarada pelo próprio `skill-creator` da Anthropic e contrariadas
pela prática publicada (C7). Encurtar continua valendo, porque cada linha é custo recorrente de
token por toda a sessão (F51), mas o número não é o critério de aceite: o critério é o item 1.

**7. Não transformar a lista de onze campos de agente de plugin em asserção de teste.**

> "Plugin agents support `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, and `isolation` frontmatter fields."
> — https://code.claude.com/docs/en/plugins-reference#agents, consultado 2026-08-10

A tabela de sub-agents lista `color` e `initialPrompt` sem marcá-los como ignorados em plugin
(C8). Um teste construído sobre essa lista afirmaria mais do que a doc sustenta. Os sete agentes
atuais usam só `name`, `description` e `disallowedTools`, todos suportados — a asserção não é
necessária hoje.

**8. Registrar o teto real da `description` e o que muda se `when_to_use` entrar.**

> "Maximum 1024 characters"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview, consultado 2026-08-10
> "the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing"
> — https://code.claude.com/docs/en/skills, consultado 2026-08-10

Com 997 caracteres, restam 27 de margem. O orçamento de 1.000 está correto e deve continuar. Se
algum dia `when_to_use` for adicionado, o limite que morde passa a ser outro, de outro host, e
com truncagem silenciosa em vez de erro.

**9. Manter o frontmatter dentro dos seis campos da spec enquanto packaging for uma
possibilidade.**

> "If you include any field the spec doesn't allow, packaging or upload fails with a hard error instead of ignoring the field"
> — https://code.claude.com/docs/en/skills#using-skill-frontmatter-outside-claude-code, consultado 2026-08-10

Hoje o arquivo declara só `name` e `description`, então está conforme. O item existe para que a
adição de um `argument-hint` ou `disable-model-invocation` — legais no Claude Code — seja uma
decisão consciente de abrir mão do caminho de upload, e não um acidente.

**10. Apontar `claude plugin validate` para o diretório do plugin, com `--strict`, em CI.**

> "To validate an individual plugin's `plugin.json` and its skill, agent, command, and hook files, run the command against the plugin directory itself"
> — https://code.claude.com/docs/en/plugin-marketplaces#marketplace-validation-errors, consultado 2026-08-10
> "Use it in CI to catch a misspelled field name or a field left over from another tool's manifest before publishing"
> — https://code.claude.com/docs/en/plugins-reference#unrecognized-fields, consultado 2026-08-10

Como `source` é `"."`, plugin e marketplace têm a mesma raiz e o validador escolhe o manifesto
de marketplace; a passagem por entrada (v2.1.196+) é quem cobre o `plugin.json` (F19). Vale
confirmar por medição, não por leitura, o que exatamente é validado nesse arranjo.

**11. Garantir que cada arquivo de `references/` seja apontado pelo `SKILL.md` com o gatilho de
quando abri-lo, a um nível de profundidade.**

> ""Read `references/api-errors.md` if the API returns a non-200 status code" is more useful than a generic "see references/ for details.""
> — https://agentskills.io/skill-creation/best-practices, consultado 2026-08-10
> "Keep references one level deep from SKILL.md... Claude may partially read files when they're referenced from other referenced files... resulting in incomplete information"
> — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, consultado 2026-08-10

Isso é o que torna o item 1 possível sem perder conteúdo: o que sai do corpo só continua
existindo de fato se o corpo disser quando ir buscá-lo. Um arquivo de referência que ninguém é
instruído a abrir foi deletado com passos extras.

---

Este documento é insumo. Ele não altera nenhum arquivo do repositório, não propõe patch e não
escolhe lado em nenhuma das dez contradições registradas — deliberadamente, porque cada uma
delas restringe o que o repositório pode afirmar, e afirmar menos com fonte é melhor que
afirmar mais sem.
