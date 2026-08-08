# codebase-cleanup

Skill de faxina de codebase para Claude Code. Trabalha em três fases, nessa
ordem: remove código morto, consolida módulos rasos e reorganiza a estrutura
de pastas. A ordem importa — organizar pastas antes de apagar o que está morto
é arrumar lixo em gaveta bonita.

A skill executa sozinha o que dá para executar com segurança. O único ponto em
que ela para e pergunta é a escolha do candidato de consolidação na fase 2,
porque fronteira de módulo é decisão de domínio, não de código.

## Requisitos

- Claude Code com suporte a skills.
- `git` — todo o trabalho acontece numa branch `faxina/AAAAMMDD`, nunca na main.
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
├── references/
│   ├── knip-config.md                configuração do knip sem armadilhas
│   ├── fase-2-consolidacao.md        protocolo de consolidação de módulos
│   ├── fase-3-estrutura.md           padrões de organização de pastas
│   └── outras-stacks.md              Python, Go, Rust, JVM, Ruby, .NET
└── scripts/
    ├── gate.sh                       typecheck + testes multi-stack, exit 0/1/3
    └── gate_test.sh                  testes de contrato do gate (stubs de toolchain)
```

Para conferir a instalação, abra uma sessão nova (ou rode `/reload-skills`) e
veja se `codebase-cleanup` aparece na lista de skills disponíveis.

### Skill complementar (opcional, mas vale instalar antes)

Ao fim da fase 1, a skill produz uma auditoria do que sobrou depois da
limpeza. Se a [tech-debt-audit](https://github.com/ksimback/tech-debt-skill)
estiver instalada, a codebase-cleanup segue o protocolo dela nessa etapa em
vez de improvisar o relatório — o resultado sai num formato estável, com
severidade e estimativa de esforço por achado.

O comando abaixo está pinado num commit específico, porque o arquivo baixado
não é dado: é instrução que o Claude executa com as permissões da sua sessão.
Leia o arquivo antes de usar, e revise de novo se um dia atualizar para uma
versão mais nova do repositório:

```bash
mkdir -p ~/.claude/skills/tech-debt-audit
curl -fSL -o ~/.claude/skills/tech-debt-audit/SKILL.md \
  https://raw.githubusercontent.com/ksimback/tech-debt-skill/5a15c1ca4a929b2759461c218478de391a8bda0f/SKILL.md
shasum -a 256 ~/.claude/skills/tech-debt-audit/SKILL.md
# esperado: 60bb907377d11cd71e3b0aa6bb67a3128de8ad6230352ff61c621a9d8bea441f
```

Sem ela nada quebra: a auditoria é gerada inline, só com formato menos
previsível. É a única dependência entre skills — nenhuma outra precisa existir
para a codebase-cleanup rodar.

## Uso

Não existe comando obrigatório. A skill dispara quando o pedido soa como
faxina: "dá uma limpada nesse projeto", "tem coisa aqui que ninguém usa",
"remove as dependências mortas", "reorganiza essas pastas". Também dá para
invocar direto com `/codebase-cleanup`.

Pedidos parciais funcionam — "remove só as dependências não usadas" executa a
categoria pedida e registra o resto como fora de escopo.

### O que acontece ao rodar

Antes de tocar em qualquer arquivo, a skill mede a rede de segurança do
projeto com `scripts/gate.sh` e se classifica em um de três níveis:

| Nível | Condição | O que ela faz |
|---|---|---|
| VERDE | typecheck e testes passam | executa as fases inteiras sem perguntar |
| AMARELO | rede parcial | só deps e arquivos órfãos, sem mexer em exports |
| VERMELHO | sem testes e sem typecheck | só diagnostica; nada é deletado |

Com o nível anunciado, ela cria a branch de faxina e segue:

1. **Fase 1 — código morto.** Configura o knip até os hints zerarem, roda em
   modo produção e deleta em commits atômicos, um por categoria: deps não
   usadas, arquivos órfãos, exports mortos. Cada commit só entra com gate
   verde. No fim, produz uma auditoria do que sobrou.
2. **Fase 2 — consolidação.** Levanta até 5 candidatos de módulos rasos,
   recomenda um e faz uma única pergunta. Respondeu "vai", ela implementa.
3. **Fase 3 — estrutura.** Diagnóstico da árvore de pastas, plano, e movimentos
   com `git mv`, uma pasta por commit.

Entre as fases a skill pede `/clear` — contexto acumulado de uma fase piora o
julgamento da seguinte. O progresso fica em `CLEANUP_PROGRESS.md` na raiz do
repo, então a sessão seguinte retoma de onde parou sem você reexplicar nada.
Em ambientes com subagentes, a skill pode rodar como orquestrador e despachar
cada fase para um contexto descartável; o protocolo está no Passo 0.2 da
SKILL.md.

### Como reverter

Cada categoria vive num commit próprio. Se algo quebrar depois:

```bash
git log --oneline          # na branch faxina/AAAAMMDD
git revert <sha>           # desfaz só aquela categoria
```

O merge da branch é decisão sua, no seu tempo. A skill nunca faz push, nunca
commita na main e nunca usa `git reset --hard` — o rollback dela é
`git restore --staged --worktree .`, que descarta apenas o que ainda não foi
commitado e convive com hooks que bloqueiam comandos destrutivos.

## Limites conhecidos

- O knip só cobre JS/TS. Nos outros stacks a confiança da deleção automática
  cai junto com a qualidade do grafo da ferramenta — a tabela em
  `references/outras-stacks.md` diz quando deletar e quando só diagnosticar.
- Import dinâmico com string montada em runtime é invisível ao grafo. A skill
  trata isso ensinando o knip (entry explícito) em vez de deletar, mas vale
  revisar o `knip.json` gerado.
- Nível VERMELHO devolve relatório, não faxina. Se o projeto não tem teste nem
  typecheck, o primeiro passo é criar uma verificação mínima; a skill aponta o
  caminho no próprio relatório.

## Créditos

Skills e materiais usados na construção desta:

- [tech-debt-audit](https://github.com/ksimback/tech-debt-skill), de ksimback —
  a fase 1.4 segue o protocolo dessa skill quando ela está instalada
  (instalação na seção acima).
- [skill-creator](https://github.com/anthropics/claude-plugins-official),
  plugin oficial da Anthropic — conduziu a revisão de boas práticas, os evals
  comparativos e a otimização da description desta skill.
- [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
  do WikiProject AI Cleanup da Wikipedia — base da adaptação local
  `humanizer-pt-br`, usada na escrita deste README.

As duas últimas foram ferramentas de desenvolvimento: não precisam estar
instaladas para usar a codebase-cleanup.
