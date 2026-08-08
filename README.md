[English](README.en.md) · **Português**

# codebase-cleanup

Skill de limpeza de codebase para Claude Code. Trabalha em três fases, nessa
ordem: remove código morto, consolida módulos rasos e reorganiza a estrutura
de pastas. A ordem importa — organizar pastas antes de apagar o que está morto
é arrumar lixo em gaveta bonita.

A skill executa sozinha o que dá para executar com segurança. O único ponto em
que ela para e pergunta é a escolha do candidato de consolidação na fase 2,
porque fronteira de módulo é decisão de domínio, não de código.

## Requisitos

- Claude Code com suporte a skills.
- `git` — todo o trabalho acontece numa branch `cleanup/YYYYMMDD`, nunca na main.
- Para projetos JS/TS: Node com `npx` (o knip roda via `npx knip`, sem
  instalação prévia).
- Outros stacks usam as ferramentas de cada ecossistema (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). O que faltar, a skill aponta em vez de
  instalar por conta.
- O gate (`scripts/gate.sh`) detecta o stack pelo manifesto e roda typecheck +
  testes em JS/TS, Go, Rust, Python, JVM, Ruby e .NET — basta o toolchain
  estar no PATH. É script bash (o 3.2 do macOS serve); no Windows, use WSL.

## Instalação

A skill é uma pasta. Instalar é copiá-la para o diretório de skills:

```bash
# global (vale para todos os projetos)
cp -R codebase-cleanup ~/.claude/skills/

# ou por projeto
cp -R codebase-cleanup .claude/skills/
```

Se você tem o pacote `codebase-cleanup.skill` (um zip), descompacte direto no
destino:

```bash
unzip codebase-cleanup.skill -d ~/.claude/skills/
```

A estrutura instalada:

```
codebase-cleanup/
├── SKILL.md                          instruções principais
├── README.md                         este arquivo
├── README.en.md                      versão em inglês
├── LICENSE                           MIT
├── references/
│   ├── audit.md                      protocolo de auditoria da fase 1.4
│   ├── knip-config.md                configuração do knip sem armadilhas
│   ├── duplication.md                funções duplicadas e a regra do churn
│   ├── phase-2-consolidation.md      protocolo de consolidação de módulos
│   ├── phase-3-structure.md          padrões de organização de pastas
│   └── other-stacks.md               Python, Go, Rust, JVM, Ruby, .NET
└── scripts/
    ├── gate.sh                       typecheck + testes multi-stack, exit 0/1/2/3
    └── gate_test.sh                  testes de contrato do gate (stubs de toolchain)
```

Para conferir a instalação, abra uma sessão nova (ou rode `/reload-skills`) e
veja se `codebase-cleanup` aparece na lista de skills disponíveis.

### Nenhuma outra skill é obrigatória

A codebase-cleanup é autossuficiente por design. O pipeline chama
ferramentas (knip, similarity-ts, jscpd, gate.sh), não outras skills — e o
conhecimento que veio de skills de terceiros foi absorvido nos arquivos
desta: o protocolo de auditoria da fase 1.4 vive em `references/audit.md`, e
o vocabulário de consolidação da fase 2 em
`references/phase-2-consolidation.md`. Instalar as skills citadas nos
créditos não muda o comportamento em runtime; elas são fonte, não
dependência.

## Uso

Não existe comando obrigatório. A skill dispara quando o pedido soa como
limpeza: "dá uma faxina nesse projeto", "dá uma limpada", "tem coisa aqui que
ninguém usa", "remove as dependências mortas", "reorganiza essas pastas".
Também dá para invocar direto com `/codebase-cleanup`.

Pedidos parciais funcionam — "remove só as dependências não usadas" executa a
categoria pedida e registra o resto como fora de escopo.

### O que acontece ao rodar

Antes de tocar em qualquer arquivo, a skill mede a rede de segurança do
projeto com `scripts/gate.sh` e se classifica em um de três níveis:

| Nível | Condição | O que ela faz |
|---|---|---|
| GREEN | typecheck e testes passam | executa as fases inteiras sem perguntar |
| YELLOW | rede parcial | só deps e arquivos órfãos, sem mexer em exports |
| RED | sem testes e sem typecheck | só diagnostica; nada é deletado |

Com o nível anunciado, ela cria a branch de limpeza e segue:

- **Fase 1 — código morto.** Configura o knip até os hints zerarem, roda em
  modo produção e deleta em commits atômicos, um por categoria: deps não
  usadas, arquivos órfãos, exports mortos. Cada commit só entra com gate
  verde. No fim, produz uma auditoria do que sobrou.
- **Fase 1.5 — funções duplicadas** (fecha a fase 1). Varre funções com nomes
  diferentes fazendo a mesma coisa (similarity-ts ou fallow em JS/TS, jscpd
  nos demais stacks) e aplica a regra do churn: par que muda junto no git é
  duplicação real e vira candidato da fase 2; par que evolui separado é
  coincidência estrutural e fica em paz. Só relatório — nada é deletado aqui.
- **Fase 2 — consolidação.** Levanta até 5 candidatos de módulos rasos
  (começando pelos pares da fase 1.5), recomenda um e faz uma única pergunta.
  Respondeu "vai", ela implementa.
- **Fase 3 — estrutura.** Diagnóstico da árvore de pastas, plano, e movimentos
  com `git mv`, uma pasta por commit.

Entre as fases a skill pede `/clear` — contexto acumulado de uma fase piora o
julgamento da seguinte. O progresso fica em `CLEANUP_PROGRESS.md` na raiz do
repo, então a sessão seguinte retoma de onde parou sem você reexplicar nada.
Em ambientes com subagentes, a skill pode rodar como orquestrador e despachar
cada fase para um contexto descartável; o protocolo está na seção "Step 0.2"
da SKILL.md.

### Como reverter

Cada categoria vive num commit próprio. Se algo quebrar depois:

```bash
git log --oneline          # na branch cleanup/YYYYMMDD
git revert <sha>           # desfaz só aquela categoria
```

O merge da branch é decisão sua, no seu tempo. A skill nunca faz push, nunca
commita na main e nunca usa `git reset --hard` — o rollback dela é
`git restore --staged --worktree .`, que descarta apenas o que ainda não foi
commitado e convive com hooks que bloqueiam comandos destrutivos.

## Limites conhecidos

- O knip só cobre JS/TS. Nos outros stacks a confiança da deleção automática
  cai junto com a qualidade do grafo da ferramenta — a tabela em
  `references/other-stacks.md` diz quando deletar e quando só diagnosticar.
- Import dinâmico com string montada em runtime é invisível ao grafo. A skill
  trata isso ensinando o knip (entry explícito) em vez de deletar, mas vale
  revisar o `knip.json` gerado.
- Nível RED devolve relatório, não limpeza. Se o projeto não tem teste nem
  typecheck, o primeiro passo é criar uma verificação mínima; a skill aponta o
  caminho no próprio relatório.

## Créditos

Skills e materiais usados na construção desta:

- [tech-debt-audit](https://github.com/ksimback/tech-debt-skill), de ksimback
  (MIT) — o protocolo de auditoria da fase 1.4 (`references/audit.md`) é
  destilado dela: as nove dimensões, o template do relatório e a seção
  obrigatória "parece ruim mas está ok".
- [codebase-design e improve-codebase-architecture](https://github.com/mattpocock/skills),
  de Matt Pocock — o vocabulário de análise da fase 2 (module, interface,
  implementation, depth, seam, adapter, locality), o teste da deleção e a
  definição de módulo raso vêm dessas skills. Os conceitos de seam e
  profundidade de módulo remontam a Michael Feathers e a John Ousterhout
  (*A Philosophy of Software Design*).
- [skill-creator](https://github.com/anthropics/claude-plugins-official),
  plugin oficial da Anthropic — conduziu a revisão de boas práticas, os evals
  comparativos e a otimização da description desta skill.
- [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
  do WikiProject AI Cleanup da Wikipedia — base da adaptação local
  `humanizer-pt-br`, usada na escrita deste README.

Nenhuma delas é dependência de runtime: são fontes e ferramentas de
desenvolvimento — nada além desta pasta precisa estar instalado para usar a
codebase-cleanup.

## Licença

MIT — use, copie, modifique e redistribua à vontade. Texto completo em
[LICENSE](LICENSE).
