# Fase 2 — Consolidação de módulos

## O que procurar

Não procure arquivos ruins isolados. Procure **agrupamentos** de módulos
pequenos e fortemente acoplados, onde cada um tem interface quase tão complexa
quanto sua implementação, e onde se sente atrito ao navegar entre eles.

O sinal mais forte é o que se lê como "para entender o fluxo X eu preciso abrir
cinco arquivos e nenhum deles me diz o suficiente sozinho".

## Vocabulário

Use estes termos com precisão. Deriva para "componente", "serviço", "camada" ou
"boundary" e a análise vira genérica.

- **módulo** — unidade com interface e implementação separáveis
- **interface** — o que os chamadores precisam saber; o custo
- **implementação** — o que o módulo entrega; o benefício
- **profundidade** — quanta alavancagem a interface dá; propriedade da
  interface, não da implementação
- **seam** — ponto de corte onde chamadores e testes cruzam a mesma fronteira
- **adapter** — tradução entre dois formatos; um adapter é seam hipotético,
  dois adapters é seam real
- **locality** — quão perto do uso a informação mora

Profundidade **não** é razão linhas-de-implementação / linhas-de-interface. Essa
métrica premia inflar a implementação. Um módulo profundo pode ser construído
internamente de peças pequenas e trocáveis — elas só não aparecem para quem
chama.

## Teste da deleção

Imagine apagar o módulo.

- Complexidade **some** → era pass-through, consolide
- Complexidade **reaparece espalhada por N chamadores** → estava se pagando,
  mantenha

## Levantamento

1. **Mapear.** Grafo de imports (o `cycles` do knip já dá boa parte), tamanho
   dos módulos, quem chama quem.
2. **Cruzar com churn.** `git log --format=%H --name-only | sort | uniq -c |
   sort -rn` — a interseção entre "muito modificado" e "muito acoplado" é onde
   a consolidação paga mais.
3. **Ler os agrupamentos candidatos de verdade.** Não julgue por nome de
   arquivo.
4. **Ranquear por confiança**, não por tamanho.

## Formato de apresentação

Máximo 5 candidatos. Para cada um:

```markdown
### C1 — `src/payments/{validator,formatter,normalizer}.ts` → `src/payments/`
**Confiança:** alta
**Por que estão rasos:** os três exportam uma função cada, sempre chamadas em
sequência pelos mesmos dois call sites. Nenhum tem teste próprio.
**Vira:** um módulo `payments` com uma função pública `preparePayment()`.
**Risco:** baixo — nenhum chamador externo ao diretório.
**Teste da deleção:** apagar `formatter.ts` move 4 linhas para cada um dos 2
chamadores. Pass-through.
```

Termine com **uma** recomendação explícita e **uma** pergunta. Nada de
entrevista de múltiplas rodadas — se o usuário responder "vai", siga com a
recomendação.

## Implementação

Um candidato por sessão. Por consolidação:

1. Criar a interface nova
2. Migrar chamadores
3. Remover os módulos antigos
4. Typecheck + testes
5. Commit `refactor: consolidate X into Y`

Falhou o gate → `git restore --staged --worktree .`, registra, não tenta
consertar.

## O que esta fase NÃO faz

Não reorganiza pastas. Profundidade de módulo é sobre o desenho da interface e
o acesso através dela, independente de como o filesystem se pareça. As duas
coisas são ortogonais — estrutura de diretórios é fase 3.

Não é resgate. Num codebase genuinamente velho ela acha candidatos reais, mas
não desatola a lama sozinha. Se o levantamento retornar 40 candidatos, o
problema é anterior e o caminho é escopar por módulo.
