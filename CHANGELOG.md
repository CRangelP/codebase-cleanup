# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento em [SemVer](https://semver.org/lang/pt-BR/).

A versão aqui e a de `.claude-plugin/plugin.json` são a mesma string, e
`scripts/coherence_test.sh` reprova quando deixam de ser. Não é zelo: a versão
do manifesto é a chave de cache que decide se uma instalação enxerga
atualização, e esquecer o bump falha em silêncio dos dois lados — ninguém
recebe erro, a correção só nunca chega.

## [0.6.0] — 2026-08-11

A suíte de eval deixa de responder sempre a mesma coisa por motivos diferentes. Três mudanças,
e a terceira muda como toda vermelhidão desta suíte se lê daqui para frente.

### Adicionado

- **O desfecho da run virou dado** ([#74](https://github.com/CRangelP/codebase-cleanup/issues/74)).
  O `run_arm` atribuía o transcript a `LAST_OUT` e nenhum caso o lia: a suíte jogava fora a
  evidência mais cara que produz. Agora o envelope de `--output-format json` é guardado **ao lado**
  do fixture e nunca dentro — transcript dentro do repositório seria lido pelos graders que fazem
  `grep` nele, que é o mesmo defeito que esta suíte encontrou na estreia, quando a skill instalada
  em `.claude/` inflou o baseline que devia medir.

  Medido nos dois desfechos (claude 2.1.220): run que termina dá
  `terminal_reason=completed`, `subtype=success` e a prosa em `result`; run que bate no teto dá
  `max_turns`, `error_max_turns` e — a assimetria que decide desenho — **sem a chave `result`**.
  Não é prosa curta, é prosa ausente: todo grader que lê prosa é grader de conclusão por
  construção, não por escolha.

- **Graders passaram a ter família, e truncamento deixou de ser veredito.** Perguntas de
  **segurança** (o entry point sobreviveu, o commit anterior é alcançável, nenhum commit fundiu
  fonte com log, nenhum rename, nenhum `refactor(`, nenhum commit de exports) valem sempre: quem
  destruiu o alvo de rollback e depois bateu no teto destruiu do mesmo jeito, e "não terminei" não
  é defesa. Perguntas de **conclusão** (o log nomeia o nível) viram `skip` **nomeado** quando a run
  não terminou — nunca `pass`, que seria inventar evidência, nunca `fail`, que é o falso-vermelho
  contra o qual o cabeçalho do arquivo avisa desde a primeira versão.

  Antes havia um veredito só para as duas famílias, e a escolha era entre reportar truncamento como
  defeito ou ignorar vermelho. As duas ensinam a parar de ler a saída.

- **O teto de fase do YELLOW virou grader em vez de promessa no nome**
  ([#65](https://github.com/CRangelP/codebase-cleanup/issues/65)). O caso se anunciava como
  *"YELLOW does not go past phase 1"* e nenhum dos seis graders dele perguntava se a fase 2, 3 ou 4
  rodou. Cobertura falsa é pior que ausência: ninguém procura o que já acha medido. Entraram três,
  cada um ancorado no artefato que a fase produz — rename no histórico (a fase 3 é sempre
  `git mv`), assunto `refactor(` (a fase 4 fixa a forma) e `chore: remove dead exports` (a exclusão
  mais fácil de perder, porque mora dentro da fase que **está** autorizada a rodar).

  Eles perguntam `--all --not <base>` e não `<base>..HEAD`: grader que afirma ausência e lê só o
  `HEAD` volta vazio — e portanto verde — sempre que a run termina fora da branch `cleanup/`.

- **Os fixtures ficaram herméticos** ([#72](https://github.com/CRangelP/codebase-cleanup/pull/72)).
  A fase 1 roda `npx knip@6.32.0`, e sem cópia local esse comando precisa do registry: com cache
  frio e `npm_config_offline`, ele morre em `ENOTCACHED`. Download dentro de uma run limitada por
  `--max-turns` é tempo morto no melhor caso e, no pior, um vermelho cuja causa não é a skill.

  O knip é **declarado** e não contrabandeado, porque `npm install` — que a categoria de deps roda
  para re-resolver — poda o que `node_modules` tem e o `package.json` não declara: 20 pacotes
  viraram 3 na medição, o knip entre eles. E declarar não entrega alvo falso à run: o knip não
  acusa a si mesmo, com o contra-teste de que **acusa** um `left-pad` no mesmo repositório.

- **Pisos sintéticos: de 12 para 39.** Rodam antes de qualquer chamada paga e provam a mordida onde
  ela pode ser provada de graça. Entre eles, o que mais importa desta versão: *truncar não pode
  fabricar VERDE* — `skip` é ausência de evidência, não evidência de conformidade.

### Corrigido

- **Um grader que era seguro no vermelho e vazio no verde.** `the baseline does not measure the
  tooling` é escrito como negação, então uma run que nunca tirou baseline passava por **ausência de
  contagem**, não por contagem certa. Ganhou pré-condição: sem linha `files=` no log, a resposta é
  `skip`. O vermelho dele sempre foi real; o verde é que não era evidência.

- **O contador `skipped` existia desde a estreia e nunca era lido.** Agora conta o que não rodou, e
  o resumo o nomeia — piso que não rodou não é piso que passou.

### Limites, medidos e declarados

Publicados porque prometer cobertura que a medição não entrega é o defeito que esta versão
conserta, e repeti-lo um andar acima seria pior.

- **A prova cara do teto de fase não mordeu.** Com a célula do YELLOW mutada para autorizar exports
  e as fases 2 e 3, os três graders continuaram verdes — e a causa não está neles: o fixture tem
  dois arquivos de uma linha, então obedecer o teto e ignorá-lo produzem a mesma história vazia. A
  mordida está estabelecida nos pisos sintéticos, que é onde ela pode ser estabelecida.
  ([#75](https://github.com/CRangelP/codebase-cleanup/issues/75))
- **A fase 2 não tem grader**, e o cabeçalho do caso explica por quê: é a única das quatro sem
  artefato durável nem assunto de commit fixo, e neste fixture não teria nem sujeito nem
  interlocutor. ([#71](https://github.com/CRangelP/codebase-cleanup/issues/71))
- **O grader "a fase 1 fechou inteira" segue bloqueado por metade.** Em duas runs comprovadamente
  completas, o `TECH_DEBT_AUDIT.md` foi commitado 2 de 2 e o commit `chore: duplication survey`
  apareceu 0 de 2, com a run registrando *"1.5 não aplicável"* — e o texto não abre exceção para
  isso. ([#77](https://github.com/CRangelP/codebase-cleanup/issues/77))

## [0.5.0] — 2026-08-10

Fecha a [#63](https://github.com/CRangelP/codebase-cleanup/issues/63). A primeira suíte deste
repositório que prova o **produto** — o que um modelo faz quando lê o `SKILL.md` — e o defeito que
ela encontrou na primeira execução.

### Adicionado

- **`scripts/eval.sh`: o comportamento do modelo, julgado pelo estado do repositório.** As outras
  seis suítes provam texto, scripts, e que os dois reprovam quando devem. Nenhuma toca o que o
  usuário compra.

  Os graders são determinísticos — pelo mesmo motivo que o protocolo recusa julgamento de LLM na
  fase 1.5: juiz que aceita qualquer coisa é pior que juiz nenhum. Existe branch de limpeza? O log
  nomeia o nível? O entry point sobreviveu? O commit anterior ainda é alcançável? Algum commit
  fundiu fonte com o log?

  **Todo caso roda duas vezes, com e sem a skill.** Grader que passa nos dois braços mede o bom
  senso do modelo, não a skill — a mesma regra que o `mutation_test.sh` aplica desde a #37.

  Doze pisos sintéticos rodam antes, de graça. Um deles já pagou por si: pegou o grader de
  alcançabilidade aprovando um sha de quarenta zeros, porque `rev-parse --verify` devolve qualquer
  string bem-formada sem checar o objeto.

  **Fora do `scripts/test.sh`** de propósito, e o cabeçalho avisa que estes graders são
  estocásticos: vermelho isolado aqui é pergunta, não veredito.

### Corrigido

- **A skill media a si mesma quando instalada dentro do projeto.** Achado pela primeira execução
  do eval, num fixture com a skill em `.claude/skills/` — rota documentada, não caso exótico. O
  baseline do Step 0 voltou `files=12 loc=3270`, com a maior função em
  `.claude/skills/.../gate.sh:329`, num repositório cujo código-fonte eram dois arquivos de uma
  linha.

  Todo delta calculado contra esse baseline é ruído, e o delta é a única evidência de melhoria que
  o relatório final apresenta.

  O `find` do `metrics.sh` agora poda `.claude`, `.agents` e `.cursor`. Mas poda conserta medição,
  não decisão: quem escolhe o que deletar é o modelo, e uma flag de `find` nunca chega até ele. O
  `SKILL.md` ganhou a regra — esses diretórios estão fora de escopo para **deleção, movimentação e
  medição** — e a seção 22 exige as duas metades, porque foi a medição que quebrou primeiro.

463 invariantes, 14 mutações, 47 casos do guarda, 37 de métricas, 12 pisos do eval.

## [0.4.2] — 2026-08-10

### Adicionado

- **A entrega do bloqueio ao modelo foi medida ao vivo, e a evidência está publicada.** É a única
  perna do contrato do guarda que nenhuma suíte cobre: os 47 casos montam o JSON do hook à mão e
  provam o comportamento do script, não que o `matcher` encaminhe a chamada nem que o exit 2
  chegue ao modelo com o stderr junto.

  Medido num repositório descartável, dentro de uma branch `cleanup/`, pedindo ao modelo
  exatamente o comando proibido. As três coisas que importam apareceram: o bloqueio chegou, a
  **razão** chegou junto, e o modelo ofereceu `git add -- <path>` em vez de procurar um contorno.

- **O gatilho automático foi medido pela primeira vez sem a cópia colidente** (a pendência que a
  #34 e a #56 deixaram em aberto). "dá uma faxina nesse projeto" num repo JS de dois arquivos: a
  skill disparou, criou `cleanup/20260810`, tirou o baseline com o `metrics.sh`, classificou
  **YELLOW** com a razão certa (gate exit 0, mas `typecheck` e `test` são `echo ok` e não há
  arquivo de teste), commitou só o log e **parou no ponto de decisão** — o knip marcava os dois
  arquivos como órfãos porque o grafo não tinha âncora, e aceitar isso teria esvaziado o repo.

  O contraste é o que dá valor à medida: a mesma frase, no mesmo repo, com o plugin **fora de
  escopo**, fez o modelo apagar o arquivo direto — sem branch, sem gate, sem log e sem rollback.

- **Os READMEs explicam o escopo da instalação.** Instalado de dentro de um projeto, o plugin fica
  com escopo `local` amarrado àquele diretório; em qualquer outro, `claude plugin list` continua
  dizendo `enabled` e `claude plugin details` continua contando `Skills (1)`, mas o modelo não vê
  skill nenhuma. Quem responde é o `projectPath` em `installed_plugins.json`.

### Corrigido

- **O invariante que nunca deixa passar um `git add -A` vivo reprovava a citação de um bloqueio
  real.**
  "Bloqueado pelo hook […]: `git add -A`" é a evidência mais forte possível de que a forma é
  recusada, e o vocabulário de cobertura não tinha `blocked`/`bloquead` — as palavras próprias de
  um guarda. Foram adicionadas, e o check continua reprovando uma instrução de verdade.

451 invariantes, 14 mutações, 47 casos do guarda.

## [0.4.1] — 2026-08-10

### Corrigido

- **O ganho da v0.4.0 estava publicado por derivação, e a medição do host discorda em 11%.**
  Com o plugin instalado e atualizado, `claude plugin details codebase-cleanup` dá:

  ```
  v0.3.5   44.801 bytes   ~15,7k on-invoke   (~370 always-on)
  v0.4.0   41.241 bytes   ~14,3k on-invoke   (~370 always-on)
  ```

  **~1.400 tokens a menos por invocação**, não os ~1.550 que os READMEs anunciavam. A conta
  antiga aplicava a taxa média do arquivo (2,85 bytes/token) ao trecho removido — e o trecho
  removido é feito de comandos, tabelas e blocos de código, que custam ~2,54 bytes por token,
  bem mais denso que a prosa que ficou.

  **Taxa média não estima corte específico.** Os dois números ficam publicados com as bases de
  bytes que cada um tem, inclusive o crescimento intermediário do arquivo pelos consertos da
  #55 — esconder isso faria a extração parecer maior do que foi.

  O `SURVIVAL_BUDGET` continua em 14.000 e agora o comentário diz por quê: a taxa nova implica
  teto de 14.420, e a margem cobre justamente o erro que esta medição expôs — a taxa é média do
  arquivo inteiro, e o que precisa caber é a **cabeça** dele, que é mais densa que a média.

451 invariantes, 14 mutações, 47 casos do guarda.

## [0.4.0] — 2026-08-10

Fecha a [#53](https://github.com/CRangelP/codebase-cleanup/issues/53). Disclosure progressiva no
`SKILL.md`, pelo critério que a #44 deixou depois de refutar o próprio: não é tamanho, é **momento
de leitura**.

### Alterado

- **`SKILL.md`: 45.672 → 41.241 bytes** (851 → 770 linhas), cerca de 1.550 tokens a menos em cada
  invocação. Todo byte do arquivo é pago em toda invocação, inclusive nas que nunca chegam na fase
  que aquele texto descreve; os `references/*.md` só são lidos quando o modelo decide abrir.

  Cada bloco extraído responde, no commit que o move, **em que momento da run ele é lido**:

  - **o contrato do gate** → `references/gate.md` (novo). Por que `${CLAUDE_PLUGIN_ROOT:-.}`
    resolve nos dois modos de instalação, a lista de manifestos reconhecidos, a detecção de qual
    script npm conta como typecheck e como suíte, e por que 124 e 137 são reservados. Nada disso
    muda uma ação no disparo — o script decide, o modelo lê o resultado.
  - **o modelo do relatório final** → `references/final-report.md` (novo). Lido no fechamento, e
    boa parte das invocações nunca chega lá.
  - **o `knip-report.json` que uma run anterior deixou rastreado** → `references/knip-config.md`.
    Caso condicional, com gatilho detectável (`git status --porcelain` depois do exclude).

  Fica no `SKILL.md` tudo que decide uma ação: classificar pelo `checks=` e não pelo exit code,
  exit 4 inconclusivo, a higiene de fechamento inteira, e cada regra sobre o que a skill pode
  destruir. A aposta da disclosure progressiva fica explícita: o `SKILL.md` mantém o **conteúdo**
  obrigatório do relatório, a reference carrega a **forma**. O contrário seria apostar que o modelo
  abre um arquivo antes de omitir alguma coisa do usuário.

- **Folga da regra mais apertada da seção 17** (stack caps): 1.264 → 1.929 bytes. A extração do
  meio do arquivo puxa para cima tudo o que vem depois.

### Adicionado

- **Seção 21: uma extração que ninguém consegue abrir é uma deleção com passos extras.** O
  invariante percorre o grafo de referências a partir do `SKILL.md` — transitivamente, porque a
  `phase-4-refactor.md` apontar o catálogo é um jeito legítimo do catálogo ser achado — e reprova
  qualquer `references/*.md` que nenhum arquivo alcançável nomeia.

  Sem ele, mover texto e apagar o ponteiro passaria verde: a suíte que checava a regra como
  **texto** continuaria achando o texto num arquivo que o modelo nunca vai abrir.

  Cada extração é asserida **dos dois lados** — a regra que decide continua no `SKILL.md`, o
  procedimento chegou inteiro no destino. Mutações M13 (o ponteiro some) e M14 (o conteúdo some).

- **Os dois READMEs publicam o par de números** e o critério que o produziu. Um número de bytes sem
  o de antes não diz nada.

451 invariantes, 14 mutações, 47 casos do guarda.

## [0.3.7] — 2026-08-10

### Corrigido

- **O parágrafo de detached HEAD ainda ensinava a forma que a 0.3.6 tinha acabado de proibir.**
  O conserto da [#55](https://github.com/CRangelP/codebase-cleanup/issues/55) trocou a leitura da
  branch em todo o `guard.sh` e escreveu o invariante que impede a volta — mas o invariante
  ancorava em `rev-parse --abbrev-ref`, e o `SKILL.md` nomeava a flag **sem o subcomando na
  frente**. Passou reto pelo único lugar que continuava errado.

  Ironia útil: o texto que sobrou mandava reconhecer detached HEAD justamente pela chamada que
  **não** distingue detached de HEAD não nascida — as duas imprimem a string literal `HEAD`. Era o
  defeito da #55 sobrevivendo na prosa depois de morrer no código.

  Agora o teste é o par que o `guard.sh` usa: `git branch --show-current` vazio **com**
  `--verify HEAD` bem-sucedido. O invariante passou a morder `--abbrev-ref` nua, e a mutação M12
  devolve a frase antiga.

420 invariantes, 12 mutações, 47 casos do guarda.

## [0.3.6] — 2026-08-10

Fecha a [#55](https://github.com/CRangelP/codebase-cleanup/issues/55) e a
[#56](https://github.com/CRangelP/codebase-cleanup/issues/56), as duas achadas ao executar o
roteiro da #34 com o plugin instalado de verdade — que é o que aquela issue existe para
encontrar.

### Corrigido

- **Um repositório sem nenhum commit derrotava os dois mecanismos de segurança ao mesmo tempo.**
  Medido num `git init` e nada mais: `--is-inside-work-tree` responde `true`,
  `git status --porcelain` não imprime nada, e `git restore --staged --worktree .` responde
  `fatal: could not resolve 'HEAD'`. Todas as medidas do Step 0 diziam *prossiga*, e o rollback
  sobre o qual todo o argumento de segurança se apoia não existia ali.

  O Step 0 escrevia "without commits there is no rollback" e testava se havia **repositório** —
  outra pergunta, com outra resposta. Agora ele roda `git rev-parse --verify HEAD`, e a linha da
  tabela de níveis cobre as duas condições.

  O guarda falhava na mesma condição e pelo mesmo motivo: `inside_run()` abria com o que nunca
  serviu aqui, `git rev-parse --abbrev-ref HEAD` — sai 128 numa HEAD não nascida, e o `|| return 1` lia
  isso como "não é repo" — dormindo numa branch `cleanup/`, que é o sinal mais forte que ele tem
  de que está numa run. Passa a ler o nome da branch com `git branch --show-current`, que
  responde numa HEAD não nascida e fica vazio numa detached: é a distinção que os dois pontos de
  chamada precisavam.

  Cinco casos novos no `guard_test.sh`, os quatro primeiros vermelhos antes do conserto. Seção 18
  do coherence e mutação M11.

- **A cópia antiga e o plugin disputavam o mesmo gatilho automático.** Quem seguiu os READMEs
  duas vezes, uma em cada época, fica com duas skills registradas, as duas com a mesma frase de
  gatilho na `description`. A invocação explícita desambigua pelo namespace; o gatilho automático
  fica em cima do muro e pode cair na cópia — a versão daquele dia, sem as fases e as correções
  que vieram depois.

  As duas formas de instalação continuam: a cópia existe para quem não usa plugin, e o
  `${CLAUDE_PLUGIN_ROOT:-.}` do protocolo foi escrito para mantê-la funcionando. O que não pode
  continuar é a migração silenciosa, e agora os dois READMEs mandam apagar a cópia, com o comando
  e a razão. Seção 19 do coherence.

### Adicionado

- **Os dois READMEs passam a dizer qual metade do contrato do guarda a suíte não cobre.** Os 47
  casos montam o JSON do hook à mão e chamam o script: provam o **comportamento**, não a
  **entrega**. Que o `matcher` do `hooks.json` encaminhe a chamada, e que o exit 2 chegue ao
  modelo com o stderr junto, foi conferido à mão com o plugin instalado (#34) e não tem suíte.

  Publicar 47 verdes sem nomear a pergunta que eles respondem convida o leitor a supor que a
  outra também está coberta — o mesmo defeito que a #40 consertou no resumo da suíte do gate.
  Seção 20 do coherence.

420 invariantes, 11 mutações, 47 casos do guarda.

## [0.3.5] — 2026-08-10

### Corrigido

- **O orçamento da seção 17 estava frouxo, e o comentário dizia o contrário.** A conversão de
  bytes para tokens era um chute — 3 bytes por token, descrito no código como "a conversão
  pessimista". O host publica o número real:

  ```
  $ claude plugin details codebase-cleanup
    codebase-cleanup   ~370 always-on   ~15.7k on-invoke
  ```

  44.801 bytes sobre ~15.700 tokens dão **2,854 bytes por token** neste arquivo. O orçamento de
  15.000 bytes valia **5.257 tokens** — acima do próprio corte que ele existia para defender. Um
  check generoso com a margem de segurança não é margem de segurança.

  Agora são 14.000 bytes, que ao ritmo medido são 4.905 tokens. Provado: empurrando as regras
  para o byte 15.974 — dentro do teto antigo — cinco checks reprovam.

### Notas de projeto

- **`claude plugin details <nome>` mede o que a #53 precisa medir.** Ele imprime o inventário de
  componentes e o custo de token projetado, separando o que é pago em toda sessão (~370, o
  frontmatter) do que é pago a cada disparo (**~15,7k**). É a régua da issue #53, e substitui
  estimativa por número do host.
- **`Skills (1) codebase-cleanup`** — o mesmo comando confirma que um `SKILL.md` na raiz, sem
  `skills/`, é registrado como skill. O contador do `/reload-plugins` mostra `0 skills` nesse
  layout, e é só o contador: o inventário, a invocação e o comportamento observado dizem o
  contrário.

410 invariantes.

## [0.3.4] — 2026-08-10

Primeira parte da [#44](https://github.com/CRangelP/codebase-cleanup/issues/44): a pesquisa em
fonte primária, e as três coisas que ela corrigiu. A extração de conteúdo do `SKILL.md` vem
depois — este ciclo fecha o que a pesquisa mostrou estar **errado**, não o que está grande.

### Adicionado

- **`docs/plugin-spec-research.md`** — 82 achados sobre `SKILL.md`, `plugin.json`, marketplace,
  agentes e hooks, cada um com citação literal, URL e data (2026-08-10), classificados em três
  colunas que a issue pedia para separar: **48 limites duros do host, 27 recomendações oficiais,
  7 convenções da comunidade**. Mais 10 contradições entre páginas oficiais, registradas com os
  dois lados e sem escolher nenhum, e 7 itens NÃO ENCONTRADOS.

  Fica em `docs/` e não em `references/` de propósito: `references/` é aberto por nome durante
  uma run e disputa o orçamento de leitura do modelo. Um estudo de 55 KB ao lado dos protocolos
  de fase seria mais uma coisa para contornar a cada execução — e o orçamento de leitura é o
  assunto da própria #44.

- **Seção 17 do `coherence_test.sh`**: toda regra que decide autoridade destrutiva tem de caber
  no orçamento que sobrevive a uma compactação.

### Corrigido

- **As regras do pipeline inteiro morriam na primeira auto-compactação.** O Claude Code
  re-anexa apenas os primeiros 5.000 tokens de cada skill depois de resumir a conversa
  ([fonte](https://code.claude.com/docs/en/skills#skill-content-lifecycle)). Medido neste
  arquivo: a tabela de níveis sobrevivia (byte 9.680) e o bloco com **"a red gate means
  rollback, not repair"**, **"never force push, never commit on main"**, **"never merge two
  steps"** e o `/clear` entre fases ficava no byte **40.732** — fora de qualquer leitura
  plausível do corte.

  Uma limpeza é uma sessão longa por natureza: a compactação é o caso esperado, não a exceção.
  O nível continuava sendo anunciado; o que sumia era o que o nível obriga. O bloco subiu para
  logo depois do princípio operacional (byte 5.208) — mudança de **ordem**, não de conteúdo — e
  a seção 17 mede a posição de oito regras, com a mutação M10 devolvendo o bloco ao fim do
  arquivo para provar que o check morde.

- **A razão do invariante de campos proibidos em agente de plugin estava invertida.** O
  comentário dizia que o host "refuses the agent outright"; a doc oficial diz, em duas páginas
  independentes, que os campos são **ignorados em silêncio**. A diferença é o valor inteiro do
  check: se o host recusasse, o erro apareceria na primeira carga; como ele ignora, o plugin
  carrega, o `claude plugin validate --strict` não reclama, e o autor publica achando que tem
  uma guarda que não existe.

### Notas de projeto

- **O corpo do `SKILL.md` não viola limite duro nenhum.** A spec diz "There are no format
  restrictions"; as 500 linhas são recomendação, confirmada em quatro fontes oficiais — e o
  próprio `skill-creator` da Anthropic diz "you can feel free to go longer if needed". O
  argumento para encurtar é o corte de 5.000 tokens, que é de ordem, e o custo recorrente por
  invocação. Não é o número de linhas.
- **Não existe recomendação oficial de tamanho ou estrutura de README de plugin.** Nove páginas
  e o `llms.txt` varridos; a única menção normativa é "Include a README.md with installation and
  usage instructions". Qualquer corte nos READMEs será decisão nossa, não aderência — e a issue
  #44 propunha o contrário.
- **A `description` está em 997 de 1024 caracteres**, com 27 de margem. O cap de 1000 que a
  seção 10 defende estava certo; o número foi confirmado em três fontes. O Claude Code trunca em
  1536 (`description` + `when_to_use` somados), que é um número diferente, de um host diferente,
  e nenhuma página explica a interação entre os dois.

410 invariantes, 10 mutações.

## [0.3.3] — 2026-08-10

### Corrigido

- **A linha GREEN dos dois READMEs calava sobre a fase 4.** Prometia a fase 1 sem perguntar e o
  checkpoint das fases 2 e 3, e parava aí — atrás do `SKILL.md` desde que a fase 4 existe. O
  silêncio aqui é conservador e não perigoso (ninguém conclui autoridade a mais), mas é a mesma
  lacuna que a linha YELLOW tinha: a tabela é o que se lê para saber o que o nível faz, e o que
  ela não diz não é decidível. As duas células agora dizem o que a fase 4 faz em GREEN — tier A
  por alvo coberto, checkpoint para o tier B — e o invariante cobre os três arquivos.

388 invariantes.

## [0.3.2] — 2026-08-10

Fecha a [#40](https://github.com/CRangelP/codebase-cleanup/issues/40) e a
[#41](https://github.com/CRangelP/codebase-cleanup/issues/41). As duas são a mesma queixa: a
saída não contava a verdade a quem estava olhando.

### Corrigido

- **A suíte do gate anunciava `NN/NN` sem dizer o que a máquina não rodou.** No macOS os dois
  casos de `timeout -k` são pulados e **contados**, para o total não variar por ambiente — o que
  mantém a seção 9 honesta e custa exatamente isto: removendo o ramo 137 de `wd_timed_out`, a
  suíte continua **142/142 verde** ali. Medido. A perna Linux da CI cobre, então o número não
  está errado; errado seria concluir de um verde local que a matriz rodou.

  O resumo agora nomeia o que ficou de fora, separando o que foi pulado e contado do que não
  rodou e não entrou na conta (o bloco perl). Sem nada pulado ele diz isso também — silêncio não
  serve como afirmação. E os dois READMEs registram, onde a run validada é publicada, que
  validação completa é nas duas plataformas.

- **O gate ficava mudo na suíte JS sem avisar.** Aquele caminho bufferiza a saída e só a
  reimprime quando o runner termina — um teste que deixa um neto de processo segurando o pipe
  travaria o gate até esse neto morrer, com o watchdog impotente. Numa suíte longa o gate fica
  quieto e o watchdog tem 900s de padrão: tempo de sobra para alguém concluir que travou.

  Uma linha dita **antes** do comando começar, mais o comportamento registrado no parágrafo do
  gate nos dois READMEs. Duas redes: `js-buffer-notice` assere a linha onde o buffer acontece, e
  `js-no-buffer-notice-on-typecheck-only` assere que ela não aparece no typecheck, que transmite
  ao vivo — a mesma promessa lá seria mentira.

- **Os READMEs e o workflow ainda diziam "as quatro suítes".** São seis desde a
  `mutation_test.sh`.

142 casos, 382 invariantes.

## [0.3.1] — 2026-08-10

Fecha a [#38](https://github.com/CRangelP/codebase-cleanup/issues/38).

### Corrigido

- **Doze dos marcadores normativos da seção 10 não podiam falhar.** `Go`, `.NET`, `Rust`,
  `Maven`, `Gradle` e `pytest` eram `grep -F` de palavra solta num README de 400 linhas — e
  `Go` casava qualquer substring, "Google" inclusive. Inflavam a contagem sem reprovar
  regressão nenhuma.

  O que esses nomes fazem no README é nomear **a evidência que cada stack tem de mostrar**
  antes de o gate considerar a suíte não-vazia. A asserção passou a ser co-ocorrência
  **dentro do parágrafo do cap**: o stack e a sua evidência no mesmo parágrafo, não os dois
  em algum lugar do arquivo. Medido: apagar a cláusula inteira do Rust dos dois READMEs
  deixava a suíte antiga em **361/361 verde**, porque `tests/*.rs` e `#[test]` também
  aparecem na seção de limites conhecidos mais abaixo. Agora reprova em seis checks, e a
  mutação M9 cobre o caso.

  O parágrafo é ancorado em `passWithNoTests` e não numa frase de prosa: é o único token
  daquele parágrafo que o **gate** lê, então a âncora só se move se a regra se mover. Palavra
  solta passou a casar com fronteira alfabética, que é o que faltava para `Go` não passar em
  "Google" — e isso também é um check, com fixture.

- **`Ruby`, `_test.rb` e `test_*.rb` entraram na conta.** Estavam na prosa normativa sem
  invariante nenhum, ao lado de `_spec.rb` que já tinha.

374 invariantes, 9 mutações.

## [0.3.0] — 2026-08-09

Fecha as [#37](https://github.com/CRangelP/codebase-cleanup/issues/37) e
[#39](https://github.com/CRangelP/codebase-cleanup/issues/39), e com elas o milestone
"toda regra que decide autoridade destrutiva é um invariante que morde".

### Adicionado

- **`scripts/mutation_test.sh`** — a sexta suíte, e a única que responde a uma pergunta que
  as outras cinco não conseguem fazer: *a suíte reprovaria se a regra sumisse?*

  Oito mutações nomeadas, cada uma uma edição que um autor faria de boa-fé e que amplia em
  silêncio o que a skill pode destruir. **Todas as oito passavam verdes** quando foram escritas.

  | | mutação |
  |---|---|
  | M1 | a célula de comportamento do nível YELLOW passa a autorizar exports e as fases 2 e 3 |
  | M2 | some a regra de que os caps por stack sobrepõem a coluna GREEN |
  | M3 | um rollback bloqueado por hook passa a **repetir** em vez de abortar |
  | M4 | a forma proibida `git add -A` oferecida viva ao lado da correta |
  | M5 | `npx` sem versão pinada |
  | M6 | YELLOW mantém as duas frases de recusa e concede as fases 3 e 4 numa oração adversativa |
  | M7 | some do README **português** a regra dos caps por stack |
  | M8 | o README **português** repete um comando que o hook barrou, em vez de abortar |

  Um vermelho só é evidência quando a causa é atribuída: a suíte exige uma **cópia não mutada
  verde** antes de contar qualquer resultado, e cada mutação declara **qual check** ela tem de
  derrubar. Sem as duas coisas ela anunciava `5/5 mutations caught` com a versão do
  `plugin.json` quebrada e nenhuma mutação aplicada.

- **Seção 16 do `coherence_test.sh`** (361 invariantes), com os invariantes que fazem as oito
  reprovarem:

  - a **coluna de comportamento** da tabela de níveis, não só a de condição — a seção 7 já dizia
    quais níveis existem e qual a condição de cada um, mas o que cada nível *autoriza* vivia só
    em prosa. É a diferença entre um nível que relata e um nível que muta um repo cujos testes
    nunca rodaram. A célula é lida **cláusula a cláusula**, não por frase: grep de redação
    aprovava uma célula mais permissiva ("does **not** run phase 2, *but* runs phase 3 and
    phase 4") e reprovava uma mais estrita ("does **not** delete exports"), porque media
    palavra e não autoridade;
  - o ponteiro de caps por stack presente em **todo arquivo que carrega a tabela** — um agente
    que lê só o `SKILL.md` e nunca abre a reference rodaria no nível da tabela;
  - o **ramo de abortar** de um rollback bloqueado por hook, porque contornar o hook é
    exatamente o que o guarda existe para impedir;
  - nunca um `git add -A` / `git add .` **vivo** na documentação;
  - todo `npx` com versão pinada.

### Corrigido

- **Os dois READMEs calavam sobre a fase 4 na linha YELLOW.** A célula prometia recusar as
  fases 2 e 3 e não dizia nada da 4, atrás do `SKILL.md` desde que a fase 4 existe — e um
  silêncio nessa coluna lê-se como permissão. A seção 16 trata `absent` como concessão, e foi
  ela que encontrou as duas células.
- **A rede de invariantes só cobria o lado inglês.** Apagar do `README.md` a linha dos caps por
  stack, ou trocar o ramo de abortar por uma repetição, deixava a suíte verde. Cada arquivo tem
  agora a sua própria frase, e a comparação é feita sobre o texto **rejuntado**: os dois READMEs
  são quebrados à mão em ~80 colunas, e um grep linha a linha afirma onde a quebra cai.
- **Os dois READMEs diziam "quatro suítes" quando já eram cinco** — o `metrics_test.sh` nunca
  entrou na contagem nem na lista de comandos. Agora são seis, listadas.

### Notas de projeto

- A forma positiva sozinha (`git add -- <pathspec>` presente) era satisfazível por um documento
  que, duas palavras depois, oferecesse a forma proibida `git add -A`, e banir a string é impossível porque a prosa
  que a proíbe precisa citá-la. O que separa instrução de proibição é **proximidade**: cada
  ocorrência tem de estar coberta por uma negação imediatamente antes, ou ser a célula esquerda
  da tabela de formas proibidas. Janela de 48 caracteres contra um pior caso **medido** de 20
  para o staging e 10 para o `npx` — a mesma regra serve às duas, e por isso é um helper só.
- `LC_ALL=C` no scanner, pelo mesmo motivo que o `strip_ansi` do gate o carrega: o awk do BSD
  aborta no primeiro byte inválido sob locale UTF-8, e uma varredura abortada não imprime nada —
  que é indistinguível de uma varredura limpa.

## [0.2.2] — 2026-08-09

Fecha a [#36](https://github.com/CRangelP/codebase-cleanup/issues/36), e fecha
metade dela corrigindo o código e metade corrigindo o que o código prometia.

### Corrigido

- **Falha encadeada silenciosa depois da suíte vazia era lida como cap.** Com
  `"test": "runner; comando-que-falha-calado"`, a linha de suíte vazia casa,
  nada é impresso depois, e não há cauda para julgar — toda a guarda anterior
  era baseada em cauda, logo cega por construção nesse caso.

  A metade decidível não precisa de cauda nenhuma: quando o runner **anuncia o
  próprio código de saída** e o processo sai com **outro**, algo depois do
  runner definiu o status. `No test files found, exiting with code 0` seguido de
  `exit=1` não é ambíguo. Agora é RED.

### Sem mudança, e agora dito em voz alta

- **O comentário prometia que "qualquer comando encadeado que falhou permanece
  RED".** Não permanecia, e não pode permanecer: se o runner anuncia `code 1` e
  o comando calado também falha com `1`, os bytes são idênticos aos de uma suíte
  legitimamente vazia que saiu sozinha — e o mesmo vale quando nenhum código é
  anunciado e nada se segue. Esses dois casos continuam YELLOW **porque o gate
  não tem evidência para decidir**, não porque a falha esteja perdoada.

  O cap marca `uncounted` de qualquer jeito, então o run nunca alcança GREEN
  neles: o custo é YELLOW onde RED seria mais honesto. Inventar a diferença
  custaria um RED a uma suíte legitimamente vazia, que é o erro mais caro dos
  dois. Ambos os casos viraram fixture, para que o limite seja documentação
  executável e ninguém o "conserte" no chute.

  E o limite é uma **escolha sobre qual evidência é segura**, não ausência de
  evidência: o gate lê o `package.json`, e em `A; B` o status é o de `B` por
  definição, então o texto de `scripts.test` prova que houve comando encadeado.
  Ele é deliberadamente não lido, porque isso exigiria parsear shell — ponto e
  vírgula dentro de aspas, dentro de substituição de comando, atrás de
  operador condicional — e errar isso cobra RED de um repo apenas vazio.

### Evitado

- **Dois falsos RED que a própria correção poderia introduzir.** Um repo
  vazio levando RED bloqueia pipeline, e é o erro mais caro que este código
  comete.

  Comparar os códigos como **string** faria `exiting with code 01` discordar de
  um exit `1`; deixar o shell comparar sozinho leria `010` como **octal 8**. A
  normalização é numérica e decimal, feita no `awk` com `s + 0`.

  E parar no **primeiro** código anunciado quebraria monorepo: um pacote por
  linha de suíte vazia, e a linha que explica o exit pode ser a última. Agora
  qualquer código anunciado que bata com o exit encerra a questão — a detecção
  sobrevive quando **nenhum** deles bate.

## [0.2.1] — 2026-08-09

Correção de um defeito que fazia o gate mentir sobre a suíte — nas duas direções.
Fecha a [#35](https://github.com/CRangelP/codebase-cleanup/issues/35).

### Corrigido

- **O gate classificava saída de runner JS sem normalizar ANSI.** As regexes de
  decisão são ancoradas em `^` ou `$`, e a cor quebra as duas pontas: o escape
  vem antes do texto, o reset vem depois do último caractere. Consequências
  reproduzidas com npm e node reais:

  - repo com **zero arquivo de teste** era classificado **GREEN** — o nível que
    libera deleção autônoma de exports e as fases 2, 3 e 4. A frase que sustenta
    o cap no `SKILL.md`, "uma suíte que não existe não pode passar", era falsa;
  - suíte que **falhou** com marcador de falha colorido (`FAIL` em vermelho ao
    lado de uma linha de suíte vazia sem cor) era lida como suíte inexistente e
    virava YELLOW em vez de RED. Essa segunda direção não estava na issue; foi
    encontrada ao investigar a primeira.

  Isso não era borda de CI: `FORCE_COLOR=1` e `CLICOLOR_FORCE=1` são injetados
  por harness de agente, que é onde esta skill mais roda.

  A correção é uma normalização única na fronteira de captura (`strip_ansi` →
  `out_plain`), não seis regexes remendadas: há um só ponto de captura, todos os
  sete consumidores derivam dele, e remendar cada regex deixaria o próximo
  detector nascer cego. A saída que o usuário vê continua colorida — o gate
  observa, não reescreve.

  `sed` POSIX, sem perl: o gate já degrada quando perl falta, e a normalização
  não podia herdar essa dependência.

### Adicionado

- Seis casos no `gate_test.sh` (127 → 133), quatro deles **reprovando** o
  `gate.sh` anterior, mais um par de controle sem cor e um caso que trava a
  decisão de projeto — a saída exibida tem de continuar contendo os escapes.
- **Seção 15 do `coherence_test.sh`** (296 invariantes): nenhum ponto de
  classificação de `js_script` pode ler `$out`, e o invariante exige que
  `strip_ansi` exista e que `out_plain` derive dela — sem isso ele passaria por
  vacuidade justamente sobre o código que o defeito removeria. O check de
  contagem fecha as cinco formas que um teste baseado em forma deixaria passar
  (`case`, `[[ ==` , `[ -n $(…) ]`, here-string, `sed -n /…/p`): dentro de
  `js_script` a captura crua tem exatamente dois leitores legítimos, e um
  terceiro leitor é o defeito voltando.

### Corrigido também, achado na revisão do próprio PR

- **`LC_ALL=C` no `strip_ansi`.** Sob locale UTF-8 o `sed` do BSD aborta com
  `illegal byte sequence` no primeiro byte inválido — e um runner escreve
  vários: multibyte truncado num limite de buffer, diff binário, nome de arquivo
  em outra codificação. O `sed` saía sem escrever nada, `out_plain` voltava
  **vazio**, nenhum detector casava e o ramo de exit 0 contava a suíte como
  executada: GREEN sobre repo com zero teste, ou seja o defeito da #35
  reentrando pela porta do próprio conserto. O default do macOS era o lado
  inseguro.
- **`\r` e OSC** entram na normalização. Um spinner reescreve a linha com
  carriage return e a âncora `^` morre no lixo à esquerda; um hyperlink `OSC 8`
  envolve o texto que linka, então o byte antes de `FAIL` é o `BEL` que fecha a
  sequência e a guarda de falha cega igual à cor. O `s/${CR}$//` antes do
  `s/.*${CR}//` existe porque a segunda regra sozinha apagaria a linha inteira
  em CRLF e mataria o detector `tests 0`.
- **`npm error`.** O npm renomeou o próprio prefixo de epílogo em v10, e o
  filtro conhecia só `npm ERR!` — inerte em todo npm atual, com uma suíte
  legitimamente vazia voltando RED porque o epílogo sobrevivia em `ev` e a
  guarda lia o ruído do gerenciador como a falha.

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
