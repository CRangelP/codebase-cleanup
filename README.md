[English](README.en.md) · **Português** · [![ci](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml)

# codebase-cleanup

Skill de limpeza de codebase para Claude Code. Trabalha em quatro fases, nessa
ordem: remove código morto, consolida módulos rasos, reorganiza a estrutura de
pastas e remodela o interior das funções que sobraram. Entre a primeira e a
segunda entra a fase 1.5, que procura arquivos e funções duplicados — a mesma
ideia implementada duas vezes com nomes diferentes — e entrega os pares como
candidatos à consolidação. A ordem importa — organizar pastas antes de apagar o
que está morto é arrumar lixo em gaveta bonita, e remodelar função dentro de
módulo que a fase 2 vai consolidar é trabalho feito duas vezes.

A skill executa sozinha o que dá para executar com segurança. Ela para e
pergunta em quatro casos: na escolha do candidato de consolidação da fase 2,
porque fronteira de módulo é decisão de domínio, não de código; na confirmação
do plano de pastas da fase 3, antes de qualquer `git mv`; na fase 4, se a fila
tiver operação de tier B, que escolhe uma abstração ou um nome de domínio; e
logo no começo, se a árvore de trabalho estiver suja — aí você decide entre
`git stash`, commitar o que está pendente ou abortar, e nada acontece antes da
sua resposta.

## Requisitos

- Claude Code com suporte a skills.
- `git` — todo o trabalho acontece numa branch `cleanup/YYYYMMDD`, nunca na
  main. Sem repositório git — ou num repositório onde o primeiro commit ainda não
  foi feito — a skill só diagnostica: o rollback dela depende de ter um commit
  bom para onde voltar, e `git init` sozinho não dá nenhum.
- Para projetos JS/TS: Node com `npx` (o knip roda via `npx knip@6.32.0`,
  versão pinada — nunca `npx knip` sem versão).
- Outros stacks usam as ferramentas de cada ecossistema (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). O que faltar, a skill aponta em vez de
  instalar por conta; `pip install` só com confirmação.
- O gate (`scripts/gate.sh`) detecta o stack pelo manifesto e roda typecheck +
  testes em JS/TS, Go, Rust, Python, JVM, Ruby e .NET. O toolchain precisa
  estar alcançável: no PATH na maioria dos stacks e, em Python, também vale
  `$VIRTUAL_ENV/bin`, `.venv/bin`, `venv/bin` ou os runners `uv run` e
  `poetry run` (nessa ordem). Cada check roda sob um watchdog (`GATE_TIMEOUT`, 900s por
  padrão, `0` desliga): estourou o tempo, o gate sai 4 e vale como não
  conclusivo. Em JS/TS a saída da suíte é bufferizada e só aparece quando o
  comando termina — um teste que deixa um neto de processo segurando o pipe
  travaria o gate até esse neto morrer, e aí o watchdog não teria como agir. O
  gate avisa antes de começar; numa suíte longa ele fica mudo, e ficar mudo é o
  esperado, não sintoma de travamento. É script bash (o 3.2 do macOS serve); no
  Windows, use WSL.

## Instalação

Como plugin, que é o caminho recomendado — dá versão, atualização e os guardas
do `PreToolUse`:

```bash
/plugin marketplace add CRangelP/codebase-cleanup
/plugin install codebase-cleanup@codebase-cleanup
```

Atualizar depois é `/plugin update codebase-cleanup@codebase-cleanup`.

**O escopo da instalação decide onde a skill existe, e o `list` não deixa isso
óbvio.** Instalado de dentro de um projeto, o plugin fica com escopo `local` e
amarrado àquele diretório — em qualquer outro, `claude plugin list` continua
dizendo `enabled`, `claude plugin details` continua contando `Skills (1)`, e o
modelo não vê skill nenhuma. Para valer em todos os projetos, instale com
`--scope user`; para conferir onde ele está de fato ativo, o que responde é o
`projectPath` em `~/.claude/plugins/installed_plugins.json`.

Para um
time, declare no `.claude/settings.json` do repositório:

```json
{
  "extraKnownMarketplaces": {
    "codebase-cleanup": {
      "source": { "source": "github", "repo": "CRangelP/codebase-cleanup" }
    }
  },
  "enabledPlugins": { "codebase-cleanup@codebase-cleanup": true }
}
```

Isso não instala nada na máquina de ninguém: cada pessoa é perguntada uma vez
se confia e instala.

Copiar a pasta continua funcionando, e continua sendo uma skill:

```bash
# global (vale para todos os projetos)
cp -R codebase-cleanup ~/.claude/skills/

# ou por projeto
cp -R codebase-cleanup .claude/skills/
```

Copiada assim ela também carrega como plugin, porque `.claude-plugin/` viaja
junto — o que muda é só de onde vem a atualização. Se você tem o pacote
`codebase-cleanup.skill` (um zip), descompacte direto no destino:

```bash
unzip codebase-cleanup.skill -d ~/.claude/skills/
```

**Se você está migrando da cópia para o plugin, apague a cópia.** As duas formas
carregam ao mesmo tempo e as duas trazem "dá uma faxina" na `description`. A
invocação explícita desambigua pelo namespace
(`/codebase-cleanup:codebase-cleanup` é sempre o plugin), mas o gatilho
automático fica em cima do muro e pode cair na cópia — que é a versão que você
instalou naquele dia, sem as fases e as correções que vieram depois:

```bash
rm -rf ~/.claude/skills/codebase-cleanup
```

A estrutura instalada:

```
codebase-cleanup/
├── SKILL.md                          instruções principais
├── README.md                         este arquivo
├── README.en.md                      versão em inglês
├── LICENSE                           MIT
├── CHANGELOG.md                      o que mudou em cada versão
├── .claude-plugin/
│   ├── plugin.json                   manifesto do plugin (nome, versão, licença)
│   └── marketplace.json              catálogo, para instalar por /plugin install
├── agents/
│   ├── cleanup-phase-1.md            fases 1 e 1.5
│   ├── cleanup-phase-2-survey.md     candidatos de consolidação (só leitura)
│   ├── cleanup-phase-2-impl.md       implementa o candidato escolhido
│   ├── cleanup-phase-3-survey.md     plano de estrutura (só leitura)
│   ├── cleanup-phase-3-impl.md       executa os movimentos aprovados
│   ├── cleanup-phase-4-survey.md     fila de remodelagem (só leitura)
│   └── cleanup-phase-4-impl.md       aplica tier A e o tier B aprovado
├── docs/
│   └── plugin-spec-research.md       o que é limite do host, conselho e hábito
├── hooks/
│   └── hooks.json                    registra o guarda no evento PreToolUse
├── references/
│   ├── gate.md                       o contrato do gate: exit codes, watchdog, scripts
│   ├── audit.md                      protocolo de auditoria da fase 1.4
│   ├── final-report.md               o modelo do relatório e como preenchê-lo
│   ├── knip-config.md                configuração do knip sem armadilhas
│   ├── duplication.md                funções duplicadas e a regra do churn
│   ├── phase-2-consolidation.md      protocolo de consolidação de módulos
│   ├── phase-3-structure.md          padrões de organização de pastas
│   ├── phase-4-refactor.md           protocolo da fase 4 e a rede por alvo
│   ├── refactoring-catalog.md        as 11 operações, em dois tiers
│   └── other-stacks.md               Python, Go, Rust, JVM, Ruby, .NET
└── scripts/
    ├── gate.sh                       typecheck + testes multi-stack, exit 0/1/2/3/4
    ├── guard.sh                      bloqueia os cinco comandos que o protocolo proíbe
    ├── test.sh                       roda as seis suítes em sequência
    ├── metrics.sh                    métricas de qualidade, exit 0/2/3
    ├── gate_test.sh                  testes de contrato do gate (stubs de toolchain)
    ├── guard_test.sh                 o que o guarda bloqueia e o que ele deixa passar
    ├── rollback_test.sh              prova executável do protocolo de rollback
    ├── eval.sh                      o que o modelo faz lendo a skill (fora do test.sh)
    ├── metrics_test.sh               casos do medidor, em repos sintéticos
    ├── coherence_test.sh             invariantes de coerência entre doc e código
    ├── mutate.sh                     aplica uma mutação e prova que ela aplicou (STALE aborta)
    └── mutation_test.sh              muta regras de autoridade destrutiva; cada uma tem de reprovar
```

Para conferir a instalação, abra uma sessão nova (ou rode `/reload-skills`) e
veja se `codebase-cleanup` aparece na lista de skills disponíveis.

### Testes

Seis suítes, sem dependência além de `bash` e `git`:

```bash
bash scripts/test.sh            # roda as seis, para na primeira que falhar

bash scripts/gate_test.sh       # contrato do gate: exit codes, linha checks=, PARTIAL
bash scripts/guard_test.sh      # o que o guarda bloqueia, e o que ele deixa passar
bash scripts/rollback_test.sh   # o que `git restore` recupera e o que ele destrói
bash scripts/metrics_test.sh    # o medidor de qualidade, em repos sintéticos

# fora do test.sh: roda o modelo de verdade, custa minutos e dinheiro
bash scripts/eval.sh            # o que o modelo faz lendo a skill
bash scripts/coherence_test.sh  # doc e código dizendo a mesma coisa
bash scripts/mutation_test.sh   # a suíte acima reprovaria se a regra sumisse?
```

A primeira execução do `eval.sh` baixa o `knip@6.32.0` uma vez, para dentro de
`~/.cache/codebase-cleanup-eval/.vendor/`, e copia essa árvore para cada
fixture. É de propósito: a fase 1 roda `npx knip@6.32.0`, e sem cópia local
esse comando precisa do registry — um download dentro de uma run limitada por
`--max-turns` é tempo morto ou um vermelho que nada tem a ver com a skill. Sem
rede e sem a árvore, a suíte para antes de gastar o primeiro minuto de modelo,
em vez de descobrir isso no meio do caso.

Toda mutação feita à mão — para provar que um invariante morde, ou que um caso de
eval reprova quando a regra some — passa pelo `mutate.sh`, que aborta quando a
edição não mudou nada. A razão é assimétrica: a mutação cara é a que roda o
modelo contra a cópia mutada, e o modo de falha dela é silencioso na pior
direção — uma expressão que não casa faz a run acontecer contra o texto
**original**, o verde volta, e ele se lê como "o caso não morde" quando nada foi
mutado. O `mutation_test.sh` roda os pisos dessa guarda antes de tudo e para se
eles falharem.

Cada uma sai 0 quando tudo passou e imprime o caso que falhou quando não; o
`test.sh` só encadeia as seis e para na primeira vermelha.
Nenhuma das quatro toca o repositório em que você a rodou: o gate usa stubs de
toolchain, o guarda e o rollback criam repositórios descartáveis dentro de um
`mktemp -d`, com `HOME` redirecionado e identidade de commit passada por `-c`
— sua config do git não é lida nem escrita —, e a de coerência só lê arquivos.

A CI roda as seis suítes a cada push e PR: ubuntu (GNU `timeout` real,
procps) e macOS com o `/bin/bash` 3.2 de fábrica. As duas pernas são
necessárias, e não redundantes: no macOS os dois casos de `timeout -k` são
pulados e contados, então o total não se mexe e uma regressão no ramo 137 do
watchdog passa verde ali com o mesmo `NN/NN`. Por isso o resumo do
`gate_test.sh` nomeia o que a máquina não rodou — validação completa é nas duas
plataformas.

As suítes também rodam fora do macOS. Num container Linux, o caso de hang
exercita o GNU `timeout` real em vez do backend perl:

```bash
docker run --rm -v "$PWD":/repo:ro node:22-bookworm bash -c \
  'apt-get update -qq && apt-get install -y -qq procps && cd /repo && bash scripts/test.sh'
# validado em 08/2026: 143/143 casos, 47/47 casos do guarda, 5/5 propriedades,
# 37/37 casos de métrica, 463/463 invariantes, 14/14 mutações pegas
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

### O que o `SKILL.md` carrega, e o que ele adia

Todo byte do `SKILL.md` é pago em **toda** invocação: ele entra inteiro no
contexto quando a skill dispara, inclusive nas invocações que nunca chegam na
fase que aquele texto descreve. Os `references/*.md` só são lidos quando o
modelo decide abrir um. É a única alavanca que existe, e ela tem um preço: o
que desce para uma reference pode não ser lido.

Por isso o critério não é tamanho, é **momento de leitura**. Fica no `SKILL.md`
tudo que decide uma ação — os níveis, os checkpoints, o rollback, e cada regra
sobre o que a skill pode destruir. Desce o que só se consulta depois de um
resultado surpreender: a mecânica interna do gate, o modelo do relatório final,
o procedimento para um `knip-report.json` que uma run anterior deixou
rastreado.

A extração da v0.4.0 tirou 4.431 bytes: **45.672 → 41.241** (851 → 770 linhas).
Em tokens, que é a unidade que se paga, medido pelo host com
`claude plugin details codebase-cleanup`:

```
v0.3.5   44.801 bytes   ~15,7k on-invoke     (~370 always-on)
v0.4.0   41.241 bytes   ~14,3k on-invoke     (~370 always-on)
```

**~1.400 tokens a menos em cada invocação.** As duas medições têm bases de bytes
diferentes de propósito: entre uma e outra o arquivo *cresceu* com os consertos
da #55, e esconder isso deixaria a extração parecer maior do que foi.

Vale registrar o erro da conta que antecedeu a medição. Estimando pela taxa
média do arquivo (2,85 bytes/token) o ganho projetado era ~1.550 tokens, 11%
acima do real. O texto extraído — comandos, tabelas, blocos de código — custa
cerca de 2,54 bytes por token, bem mais denso que a prosa que ficou. **Taxa
média não estima corte específico**, e a régua que vale é a do host.

O número sozinho não diz nada — o par diz, e a redução é resultado, não meta.
Nada saiu "para ficar menor": bloco cuja pergunta de leitura não tinha resposta
clara ficou onde estava.

Duas coisas garantem que a conta não seja uma mentira. A seção 21 do
`coherence_test.sh` percorre o grafo de referências a partir do `SKILL.md` e
reprova qualquer arquivo que ninguém aponta — uma reference órfã não é conteúdo
adiado, é conteúdo apagado com passos extras. E cada extração é asserida **dos
dois lados**: a regra que decide continua no `SKILL.md`, o procedimento chegou
inteiro no destino. Afirmar só um dos lados é como uma extração vira deleção
silenciosa.

## Uso

Não existe comando obrigatório. A skill dispara quando o pedido soa como
limpeza: "dá uma faxina nesse projeto", "dá uma limpada", "tem coisa aqui que
ninguém usa", "remove as dependências mortas", "reorganiza essas pastas".
Também dá para invocar direto: `/codebase-cleanup:codebase-cleanup` instalada
como plugin (skills de plugin sempre levam o nome do plugin na frente), ou
`/codebase-cleanup` na instalação por cópia.

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
| GREEN | typecheck e testes passam | executa a fase 1 sem perguntar; fase 2 e fase 3 param no checkpoint humano; a fase 4 aplica o tier A por alvo coberto e para no checkpoint do tier B |
| YELLOW | rede parcial, ou nenhum arquivo de teste no stack | só deps e arquivos órfãos, sem mexer em exports; não roda fase 2, fase 3 nem fase 4 |
| RED | sem testes e sem typecheck, ou baseline já vermelho | só diagnostica; nada é deletado; não commit de `CLEANUP_PROGRESS` |

Os caps por stack em `references/other-stacks.md` sobrescrevem a coluna GREEN
(Python confirma antes de deletar; JVM/Ruby/.NET código ficam em YELLOW ou só
diagnóstico por padrão).

Projeto que já chega com a suíte vermelha cai em RED, não em YELLOW: com o
baseline quebrado não dá para separar o que a limpeza quebrou do que já estava
quebrado, e como todo commit exige gate verde, nenhum deles aconteceria. A
skill diz qual check falhou e para por aí.

Stack sem nenhum arquivo de teste não conta como testado: o gate não conta
suíte vazia, seja porque não a rodou, seja porque rodou e não voltou nada, e o
nível fica em YELLOW. Vale para JS/TS cujo runner sai com suíte vazia
("No test files found") — inclusive quando ele sai 0 porque mandaram, como em
`--passWithNoTests`, já que exit 0 não é prova de que uma suíte rodou —,
Go e .NET sem arquivo de teste, crate Rust sem
`tests/*.rs` nem `#[test]`, build Maven ou Gradle sem nenhum `src/test`, Ruby
cujo `spec/` ou `test/` não guarda nenhum `*_spec.rb`, `*_test.rb` nem
`test_*.rb` (o padrão do `Rake::TestTask`), e pytest
que sai 5 sem coletar nada. Manifesto que está ali só por ferramenta —
um `requirements.txt` do build da documentação, um `Gemfile` do fastlane —
não é stack sem suíte: sem código daquela linguagem no repositório, o gate
não fala dele. Se a sua suíte mora fora do lugar padrão, a promoção é sua —
o gate não se promove sozinho.

Em JS/TS o placeholder exato do `npm init` (`echo "Error: no test specified"
&& exit 1`) também cai em YELLOW com a linha `'test' not counted` e o marcador
`npm init placeholder` — não é RED de suíte quebrada. O mesmo cap pega a suíte
fatiada: sem script `test`, com `test:unit` e `test:e2e` no manifesto, nenhuma
fatia responde pela suíte inteira e o gate não conta nenhuma delas. Promover
à mão aqui é o caminho errado, porque a suíte não está fora do lugar, está
dividida; rode as fatias todas. Uma fatia
sozinha vale como a suíte, com uma exceção: modo watch nunca termina, então o
gate não o executa. `watch`, `ui` e `debug` são lidos como segmentos inteiros
do nome, o que pega `test:watch:all` e deixa `test:watchdog` em paz. Só que não
executar e não contar são coisas diferentes: `watch` e `debug` são um modo da
suíte, então `test:watch` ao lado de um `test:unit` sozinho deixa essa fatia
valendo como a suíte; `test:ui` pode muito bem ser uma suíte à parte, então ele
não roda e mesmo assim conta, e aí `test:unit` ao lado dele já é uma divisão.

Em repositório poliglota o cap sobrevive aos outros stacks. Go com testes ao
lado de uma metade JS que ninguém contou ainda imprime `checks=typecheck,test`,
porque cada palavra veio de um manifesto diferente — e aí o gate se recusa a
dizer GREEN, e nomeia o stack que ficou sem suíte.

Com o nível anunciado, ela cria a branch de limpeza e segue:

- **Fase 1 — código morto.** Configura o knip até os hints zerarem, roda em
  modo produção e deleta em commits atômicos, um por categoria: deps não
  usadas, arquivos órfãos, exports mortos. Cada passo faz stage só com
  pathspecs dos artefatos daquele passo (`git add -- …`, nunca `git add -A`),
  e só entra com gate verde. No fim, produz uma auditoria do que sobrou.
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
Em ambientes com subagentes, a skill roda como orquestrador e despacha cada
fase para um contexto descartável. Instalada como plugin, esses subagentes
vêm declarados em `agents/`: `cleanup-phase-1` (fases 1 e 1.5), e mais um par
de survey e implementação para cada uma das fases 2 e 3. Os dois de survey não
conseguem escrever — é assim que o checkpoint deixa de depender de boa
vontade: a pergunta chega até você antes de qualquer mudança, e a
implementação só começa depois da sua resposta. O protocolo está na seção
"Step 0.2" da SKILL.md.

### Como reverter

Cada categoria vive num commit próprio. Se algo quebrar depois:

```bash
git log --oneline          # na branch cleanup/YYYYMMDD
git revert <sha>           # desfaz só aquela categoria
```

O merge da branch é decisão sua, no seu tempo. A skill nunca faz push, nunca
commita na main e nunca usa `git reset --hard` — o rollback dela é
`git restore --staged --worktree .`, que joga fora tudo o que ainda não foi
commitado. Se um hook de segurança bloquear esse restore, a skill **aborta**
o pipeline (não contorna o hook): reporta a branch, a árvore suja e o comando
manual, e para.

Note o "tudo": alteração sua que estava no diretório antes de a skill começar
entraria nessa conta. É por isso que ela exige árvore limpa no início e
interrompe para perguntar quando não está — com a árvore limpa, o que o
rollback joga fora foi ela mesma que criou. O stage por pathspec (em vez de
`git add -A`) evita engolir rascunhos e `.env` locais no commit da categoria.

### Os guardas

Instalada como plugin, essas proibições deixam de ser texto que o modelo pode
esquecer. `hooks/hooks.json` registra `scripts/guard.sh` no evento
`PreToolUse`, e ele barra cinco comandos antes de rodarem:

| Comando | Por quê |
|---|---|
| `git reset --hard` | levaria junto trabalho que estava na árvore antes da limpeza |
| `git clean` | apagaria arquivos não rastreados que precisam sobreviver: saída de ferramenta, caches, `.env` locais |
| `git push` | a skill nunca publica; o merge é decisão sua |
| `git commit` na `main` | todo o trabalho vive na branch de limpeza |
| `git add -A` | staging de árvore inteira engole no commit o que não é da categoria |

O guarda só acorda dentro de uma run: HEAD numa branch `cleanup/`, ou um
`CLEANUP_PROGRESS.md` **não rastreado** — que é o que uma run RED deixa, e o
que existe antes do primeiro commit. Log rastreado numa branch normal é
limpeza já mergeada, não run em curso, e aí ele volta a dormir; sem isso ele
ficaria ativo na main para sempre depois do primeiro merge. Fora disso esses
comandos são trabalho normal, e ele não diz nada.

Na dúvida ele libera. Sem repo, sem JSON, sem comando: sai 0 e cala. Um guarda
que bloqueia por engano é pior que guarda nenhum, porque a skill **aborta** o
pipeline quando um comando do protocolo é barrado — um falso positivo derruba
uma run legítima. O que ele bloqueia e o que ele deixa passar está em
`scripts/guard_test.sh`, incluindo `git restore --staged --worktree .`,
`git revert`, `git mv`, `git stash push -u` e o `git add --` por pathspec.

Uma coisa esses 47 casos não alcançam, e vale saber qual: eles montam o JSON do
hook à mão e chamam o script, então provam o **comportamento do guarda** — não a
entrega. Que o `matcher` do `hooks.json` realmente encaminhe a chamada, e que o
exit 2 chegue ao modelo com o stderr junto, foi conferido à mão com o plugin
instalado, e não por suíte.

Como isso é a única perna do contrato que nenhuma suíte cobre, aqui está a
medição, feita num repositório descartável, dentro de uma branch `cleanup/`,
pedindo ao modelo exatamente o comando proibido:

> Bloqueado pelo hook […] do codebase-cleanup: `git add -A` (staging de
> árvore inteira) é proibido durante cleanup, para não engolir arquivo alheio no
> commit da categoria. Não vou contornar por outro caminho — bloqueio que
> disparou é decisão final. […] Para stage por pathspec: `git add -- novo.ts`

As três coisas que importam estão ali: o bloqueio chegou, a **razão** chegou
junto, e o modelo ofereceu a forma correta em vez de procurar um contorno. É o
que a distinção protege — um guarda que bloqueia sem entregar a razão vira um
erro opaco, e um modelo que não lê a razão reformula o comando até passar.

## Limites conhecidos

- O knip só cobre JS/TS. Nos outros stacks a confiança da deleção automática
  cai junto com a qualidade do grafo da ferramenta — a tabela em
  `references/other-stacks.md` diz quando deletar e quando só diagnosticar.
- Import dinâmico com string montada em runtime é invisível ao grafo. A skill
  trata isso ensinando o knip (entry explícito) em vez de deletar, mas vale
  revisar o `knip.json` gerado.
- Nível RED devolve relatório, não limpeza. Cai aí quem não tem teste nem
  typecheck, e também quem chega com a suíte vermelha. Sem teste, o primeiro
  passo é criar uma verificação mínima; com a suíte quebrada, é consertar o
  check que o relatório nomeia.
- Exit 124 é reservado ao watchdog, igual ao GNU `timeout`: um check que
  legitimamente sai 124 sob watchdog ativo é lido como TIMEOUT. Exit 137 vale
  o mesmo enquanto o watchdog roda com `-k`, porque é o código que a escalada
  kill-after produz contra um check que ignora TERM.
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
- A categoria de deps roda o install simples do gerenciador depois de podar o
  manifesto, então o lockfile é reescrito e o `node_modules` é resolvido de
  novo. Essa parte fica fora do rollback: o `git restore` traz de volta o
  `package.json` e o lockfile, nunca a árvore instalada. Se for essa categoria
  que falhar, rode o install outra vez; as outras duas não mexem no manifesto e
  não precisam.

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
