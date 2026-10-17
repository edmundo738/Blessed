# GAMEPLAY_ARCHITECTURE — o que cada coisa existe para fazer

> Este ficheiro é escrito **antes** de mexer no código. Serve para responder a
> uma pergunta que já se falhou uma vez: *"se eu tirar esta peça, o que é que o
> jogador deixa de conseguir fazer?"*
>
> Regra: **Preservar → Corrigir → Ligar → Lapidar → Só depois Expandir.**

---

## 1. As Eras (e a ferramenta que faz a travessia)

Cada era existe porque **destranca uma extração que antes era impossível ou
desperdiçada**. Uma ferramenta intermédia não é "+10% de dano": é a chave de
uma porta.

| Era | Onde se faz | Ferramentas | O que destranca |
|----|----|----|----|
| **0 — Mãos** | — | nenhuma | gravetos, folhas, fibra, **pedra solta** (`flint_node` → pedra + sílex), cogumelos, fruta, água; madeira a 18 golpes por árvore |
| **1 — Improviso** | **Criação** (na mão) | lasca de pedra, isqueiro primitivo, tocha, **recipiente improvisado** | luz e fogo; transporte de água; cortar sem gastar os punhos |
| **2 — Primitivas** | **Criação** (na mão) | **machado primitivo**, **picareta primitiva** | abater árvores a sério; **picar rocha** (a primeira ferramenta com `mine`); a bancada passa a valer |
| **3 — Pedra trabalhada** | **Bancada** | machado de pedra, picareta de pedra | mais material por nó (menos desperdício); **rocha dura** (só tier ≥ 2); mobiliário; peças de construção |
| **4 — Metal** | Fornalha (futuro) | — | minérios duros, ferramentas melhores — **ainda não implementado** |

**A travessia crítica:** `mãos → pedra solta → picareta PRIMITIVA → rocha →
pedra → bancada → ferramentas de pedra`.

Sem a picareta primitiva esta cadeia parte-se num ponto invisível: há pedra
solta suficiente para uma lasca, mas nunca se chega à rocha, e a bancada fica a
pedir pedra que ninguém consegue tirar. Foi exactamente o que se quebrou ao
apagar a família de madeira. A família de madeira **era** a travessia; o nome
estava errado, a função não.

## 2. Diferença entre MÃO e FERRAMENTA (o que o jogador sente)

> **Decisão (2026-10-17):** as mãos só perdem material quando **arrancam**
> (`chop`, `mine`) — 0,7×. **Apanhar** (bagas, fibra, pedra solta) é o que as
> mãos fazem bem: 1,0×. Sem esta distinção o primeiro minuto era colher
> arbustos até secar o vale para juntar fibra, e o jogador desistia antes da
> primeira ferramenta.

| | Mãos | Ferramenta tier 1 | Ferramenta tier 2 |
|---|---|---|---|
| Golpes para abater uma árvore | 18 | 6 (machado primitivo) | 3 (machado de pedra) |
| Golpes para partir uma rocha | **impossível** | 5 | 3 |
| Material por nó | **-35%** (desperdício) | 100% | **+35%** (aproveitamento) |
| Rocha dura | impossível | impossível | **possível** |

Ou seja: a mão não é "ferramenta lenta". A mão **não chega** a certos materiais
e **estraga** parte do que apanha. É isto que dá valor ao primeiro machado.

## 3. Função de cada recurso (não há item decorativo)

| Recurso | Onde nasce | Que problema resolve | Que item posterior depende dele |
|---|---|---|---|
| `stick` (graveto) | arbustos, árvores, tronco abatido | cabo, atiçar fogo, construção | tocha, isqueiro, lasca, ferramentas, cama |
| `wood` (madeira) | **tronco abatido** (toro a toro, com F) | estrutura, fogo, mobiliário | bancada, fogueira, garrafa, cofre, parede |
| `fiber` (fibra) | arbustos, tufos, folhas | atar tudo | isqueiro, lasca, ferramentas, cama, garrafa |
| `stone` (pedra) | pedra solta e **rocha** | corte e peso | lasca, ferramentas, fogueira, forno |
| `flint` (sílex) | pedra solta | acender fogo | isqueiro primitivo |
| `leaf` (folha) | arbustos, árvores | fibra, cama, telhado | cama, fibra |
| `mushroom` | sombra/húmido | comida de risco | guisado |
| `meat_raw` / `fish_raw` | caça / pesca | comida | assado, guisado |
| `water` (crua) | rio, mar | sede | água fervida |
| `water_clean` | **fogueira** | sede sem risco | — |

Regra: se um recurso não tem **fonte no mundo**, **estações que o usam** e
**item posterior que dele depende**, não entra.

## 4. Função de cada estação

| Estação | Onde | Resolve | Não resolve |
|---|---|---|---|
| **Criação** | no inventário, em qualquer sítio | o improviso: o que se faz **agora**, com o que está no chão | nada que precise de bancada |
| **Bancada** | objeto no mundo; F abre a bancada | ferramentas que duram, mobiliário, peças de construção | cozinhar |
| **Fogueira** | objeto no mundo; F acende, F abre | luz, calor, cozinhar, **ferver água**, afastar criaturas | trabalhar pedra |
| **Cama / Cadeira** | objeto no mundo | descanso — a passagem do tempo (cama) e a energia (cadeira) | — |
| **Cofre** | objeto no mundo | guardar (a mochila tem 24 slots) | — |

**As estações são objetos do mundo.** Interagir com elas abre a interface
**daquela** estação — não se volta ao inventário para "simular" a bancada.

## 5. Os loops (cada um com NECESSIDADE → DECISÃO → CONSEQUÊNCIA)

### 5.1 Água
`sede → (a) beber na fonte: rápido, água CRUA com risco | (b) encher o
recipiente → levar → ferver na fogueira → água segura e mais sede por frasco`.
O recipiente nasce **vazio** e é uma ferramenta de transporte, não uma garrafa
de água. Água do **mar** é salgada: hidrata de imediato e depois cobra.

### 5.2 Comida
`fome → colher/caçar/pescar → cru (risco, `risk`) ou cozinhar (na fogueira) →
assado sem risco → guisado (carne + cogumelo + água) que alimenta E hidrata`.
Cozinhar é uma **estação de transformação**, não um botão `raw → cooked`.

### 5.3 Sono
`cansaço → chão (mau) | cadeira (descansa a energia, não passa a noite) | cama
(boa: passa a noite e recupera a sério)`. Cada degrau exige mais trabalho.

### 5.4 Árvore (loop completo, ponta a ponta)
`árvore em pé → golpes (com feedback de lascas e som) → cai → tronco fica
DEITADO e sólido → F retira um toro → madeira → Criação/Bancada → fogueira,
bancada, cofre, parede, cama`.

### 5.5 Rocha
`rocha → golpes → fissuras → parte → pedra + sílex`.
A **pedra solta** (`flint_node`) é a porta de entrada sem ferramenta; a
**rocha** exige picareta; a **rocha dura** exige picareta de pedra.

### 5.6 Fogo
`isqueiro primitivo (sílex + pedra + fibra) → F na fogueira → acesa: luz que
treme, chama de três camadas, calor, cozinha, ferve água, afasta criaturas`.
Sem isqueiro, a fogueira não acende — e o jogo diz porquê.

### 5.7 Construção
`receita → colocar (com pré-visualização) → objeto útil no mundo: dormir,
guardar, sentar, trabalhar`. Cada peça tem uma função declarada.

## 6. Teste de aceitação (teste de GAMEPLAY, não de função)

O `tests/selftest.gd` corre a **primeira sessão completa**, passo a passo, e
falha no ponto exacto onde o loop se quebra:

```
pedra solta (mãos) → lasca → picareta primitiva → ROCHA → pedra
→ bancada (Criação) → colocada no mundo → picareta de pedra
→ rocha dura (só tier 2) → árvore (machado) → tronco → madeira
→ isqueiro → fogueira acesa → garrafa → encher → ferver → beber seguro
→ carne assada → cama → dormir → noite passada
```

Se qualquer passo falhar, **não se acrescenta conteúdo novo**: corrige-se o
passo.

### 6.1 Como está implementado

- `tests/selftest.gd::_first_day()` — a sessão. Corre no fim do self-test, com
  a mochila **esvaziada** e as estruturas dos testes anteriores removidas: a
  bancada e a fogueira deste dia são construídas pelo próprio teste.
- Cada passo é uma verificação `DIA 1 · …`. No fim há uma que só passa se
  **todos** os passos passarem ("o primeiro dia fecha-se ponta a ponta").
- Modo rápido (só o dia 1, sem o resto da suite):

  ```
  node tools/run.mjs --headless --quit-after 6000 -- selftest dia1
  ```

### 6.2 O que este teste já apanhou (e que os testes de função não apanhavam)

1. **O alvo da interação é recalculado a cada frame** (`interaction._process`
   lê o que o jogador está a olhar). Num teste headless sem mira, o alvo tem de
   ser reposto **antes de cada golpe**; sem isso cada nó levava um golpe só e
   uma árvore nunca caía (18 golpes de mão apareciam como "2 golpes, hp 5.0 →
   4.7").
2. **A madeira do toro cai ao longo do tronco deitado**, a ~2 m do jogador —
   fora do raio do íman (2,1 m). Apanhá-la exige **andar até lá**; o teste
   teleporta-se para cima do pickup, como faria um jogador a caminhar.
3. **`needs_tier` era lido mas nenhum nó o declarava**: a rocha dura aceitava a
   picareta primitiva. Agora `rock_hard` declara `"needs_tier": 2`.
4. **Objectos libertados**: varrer os filhos do mundo à procura de pickups
   toca em nós que já estão em `queue_free` e rebenta a build web
   (`null function or function signature mismatch`). Guardar sempre com
   `is_instance_valid`.
5. **A fogueira só é estação de cozinha quando está ACESA** — a verificação
   tem de ser feita depois de acender, não antes.

## 7. Perguntas obrigatórias antes de qualquer alteração

1. O que é que este sistema já fazia?
2. Que loop dependia dele?
3. Que recursos entram e saem?
4. Que sistemas dependem do resultado?
5. O que acontece se eu tirar esta peça?
6. O jogador perde alguma etapa de progressão?
7. A mudança **reduz ou aumenta** as decisões?
8. Estou a remover complexidade inútil ou **profundidade**?
9. Consigo **lapidar** o que existe em vez de apagar?
10. Que contradição isto cria com outro sistema?

Se a resposta não estiver clara: **não alterar ainda**. Medir primeiro
(`tests/shot.gd`, `tools/render_shot.py`, `tests/selftest.gd`).
