# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento em [SemVer](https://semver.org/lang/pt-BR/).

A versão aqui e a de `.claude-plugin/plugin.json` são a mesma string, e
`scripts/coherence_test.sh` reprova quando deixam de ser. Não é zelo: a versão
do manifesto é a chave de cache que decide se uma instalação enxerga
atualização, e esquecer o bump falha em silêncio dos dois lados — ninguém
recebe erro, a correção só nunca chega.

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
