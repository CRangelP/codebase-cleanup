[English](README.en.md) · **Português** · [![ci](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml)

# codebase-cleanup

Skill de limpeza de codebase para Claude Code. Trabalha em três fases, nessa
ordem: remove código morto, consolida módulos rasos e reorganiza a estrutura
de pastas. Entre a primeira e a segunda entra a fase 1.5, que procura arquivos
e funções duplicados — a mesma ideia implementada duas vezes com nomes
diferentes — e entrega os pares como candidatos à consolidação. A ordem
importa — organizar pastas antes de apagar o que está morto é arrumar lixo em
gaveta bonita.

A skill executa sozinha o que dá para executar com segurança. Ela para e
pergunta em dois casos: na escolha do candidato de consolidação da fase 2,
porque fronteira de módulo é decisão de domínio, não de código; e logo no
começo, se a árvore de trabalho estiver suja — aí você decide entre `git stash`,
commitar o que está pendente ou abortar, e nada acontece antes da sua resposta.

## Requisitos

- Claude Code com suporte a skills.
- `git` — todo o trabalho acontece numa branch `cleanup/YYYYMMDD`, nunca na
  main. Sem repositório git a skill só diagnostica: o rollback dela depende de
  ter um commit bom para onde voltar.
- Para projetos JS/TS: Node com `npx` (o knip roda via `npx knip`, sem
  instalação prévia).
- Outros stacks usam as ferramentas de cada ecossistema (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). O que faltar, a skill aponta em vez de
  instalar por conta.
- O gate (`scripts/gate.sh`) detecta o stack pelo manifesto e roda typecheck +
  testes em JS/TS, Go, Rust, Python, JVM, Ruby e .NET. O toolchain precisa
  estar alcançável: no PATH na maioria dos stacks e, em Python, também vale
  `$VIRTUAL_ENV/bin`, `.venv/bin`, `venv/bin` ou os runners `uv run` e
  `poetry run` (nessa ordem). Cada check roda sob um watchdog (`GATE_TIMEOUT`, 900s por
  padrão, `0` desliga): estourou o tempo, o gate sai 4 e vale como não
  conclusivo. É script bash (o 3.2 do macOS serve); no Windows, use WSL.

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
    ├── gate.sh                       typecheck + testes multi-stack, exit 0/1/2/3/4
    ├── test.sh                       roda as três suítes em sequência
    ├── gate_test.sh                  testes de contrato do gate (stubs de toolchain)
    ├── rollback_test.sh              prova executável do protocolo de rollback
    └── coherence_test.sh             invariantes de coerência entre doc e código
```

Para conferir a instalação, abra uma sessão nova (ou rode `/reload-skills`) e
veja se `codebase-cleanup` aparece na lista de skills disponíveis.

### Testes

Três suítes, sem dependência além de `bash` e `git`:

```bash
bash scripts/test.sh            # roda as três, para na primeira que falhar

bash scripts/gate_test.sh       # contrato do gate: exit codes, linha checks=, PARTIAL
bash scripts/rollback_test.sh   # o que `git restore` recupera e o que ele destrói
bash scripts/coherence_test.sh  # doc e código dizendo a mesma coisa
```

Cada uma sai 0 quando tudo passou e imprime o caso que falhou quando não; o
`test.sh` só encadeia as três e para na primeira vermelha.
Nenhuma das três toca o repositório em que você a rodou: o gate usa stubs de
toolchain, o rollback cria repositórios descartáveis dentro de um `mktemp -d`,
com `HOME` redirecionado e identidade de commit passada por `-c` — sua config
do git não é lida nem escrita —, e a de coerência só lê arquivos.

A CI roda as três suítes a cada push e PR: ubuntu (GNU `timeout` real,
procps) e macOS com o `/bin/bash` 3.2 de fábrica.

As suítes também rodam fora do macOS. Num container Linux, o caso de hang
exercita o GNU `timeout` real em vez do backend perl:

```bash
docker run --rm -v "$PWD":/repo:ro node:22-bookworm bash -c \
  'apt-get update -qq && apt-get install -y -qq procps && cd /repo && bash scripts/test.sh'
# validado em 08/2026: 53/53 casos, 5/5 propriedades, 49/49 invariantes
```

A heurística .NET foi validada contra o SDK real (`mcr.microsoft.com/dotnet/sdk:8.0`
e `:10.0`, 08/2026): `dotnet test` sem projeto de teste é mesmo no-op com exit 0
nas duas versões, e os templates `xunit`, `nunit` e `mstest` casam com os
marcadores — no 10.0 o mstest casa só pelo token `MSTest`.

A terceira transforma em teste o que antes dependia de reler tudo: o comando de
rollback escrito igual em todo lugar, o contrato de exit codes do gate batendo
com os READMEs, instrução velha que ficou para trás e árvore de arquivos que
combina com o que existe no disco.

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

Antes de qualquer coisa ela confere o terreno: se a árvore de trabalho tem
alteração não commitada, ela para e pergunta o que fazer (stash, commitar ou
abortar) em vez de arriscar o seu trabalho em progresso no primeiro rollback.
Com a árvore limpa, mede a rede de segurança do projeto com `scripts/gate.sh`
e se classifica em um de três níveis:

| Nível | Condição | O que ela faz |
|---|---|---|
| GREEN | typecheck e testes passam | executa as fases inteiras sem perguntar |
| YELLOW | rede parcial, ou nenhum arquivo de teste no stack | só deps e arquivos órfãos, sem mexer em exports |
| RED | sem testes e sem typecheck | só diagnostica; nada é deletado |

Stack sem nenhum arquivo de teste não conta como testado: o gate não roda a
suíte vazia e o nível fica em YELLOW. Vale para Go e .NET sem arquivo de
teste, para crate Rust sem `tests/*.rs` nem `#[test]`, e para pytest que sai
5 sem coletar nada. Se a sua suíte mora fora do lugar padrão, a promoção é
sua — o gate não se promove sozinho.

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
`git restore --staged --worktree .`, que joga fora tudo o que ainda não foi
commitado e convive com hooks que bloqueiam comandos destrutivos.

Note o "tudo": alteração sua que estava no diretório antes de a skill começar
entraria nessa conta. É por isso que ela exige árvore limpa no início e
interrompe para perguntar quando não está — com a árvore limpa, o que o
rollback joga fora foi ela mesma que criou.

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
- Exit 124 é reservado ao watchdog, igual ao GNU `timeout`: um check que
  legitimamente sai 124 sob watchdog ativo é lido como TIMEOUT.
- Com uma única `.sln`/`.slnx` na raiz o gate a passa explícita ao `dotnet`;
  com duas ou mais ele se abstém e invoca sem argumento, e a ambiguidade
  volta a ser do MSBuild. Falha fechada: rode o gate manual apontando a
  solução.
- Crate Rust cujos testes existem só como doc-tests (ou gerados por macro)
  cai no cap YELLOW — a evidência procurada é `tests/*.rs` ou `#[test]` no
  fonte. Promova à mão se a suíte vive em outro lugar.
- Pasta sem git também cai em RED, mesmo com typecheck e testes passando. Sem
  commit não existe rollback, e é o rollback que sustenta a autonomia do resto
  do pipeline.

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
