# CHECKPOINT — estado atual do projeto

> Este ficheiro é a memória do projeto. Qualquer IA (ou humano) que abra o
> repositório começa por lê-lo. Atualiza-se no fim de cada marco.
> Última passagem de auditoria: 2026-10-14 (Godot 4.7.2 headless: 125 verificações, 0 falhas).
> O histórico de auditoria abaixo preserva resultados antigos; quando diferirem, prevalecem
> este marco mais recente e `docs/AUDIT_2026-10-14.md`.

## Etapa C (em curso) — a água nasce do mundo, e o mundo obedece-lhe

**Verificação: 242 ok, 0 falhas, 30 saltadas (SELFTEST_PASS). 75 s.**

Até aqui a água era uma **superfície derivada do chão**: um rio desenhado com
uma senóide, uma costa pintada, e o mar. A inversão desta etapa é a que faltava:

> o chão é que se adapta à água.

`Terrain.height()` deixou de ser o relevo e passou a ser `relevo − leito
escavado` (`relief()` é o relevo puro que a hidrologia consulta). Os rios
passam em vales verdadeiros, com margens, e a rede nasce da chuva que o relevo
manda para o mar.

- **`Water` (BHFS geográfico)** — bacia de 2,56 km a 20 m (129²) em volta da
  aldeia, calculada **uma vez por semente** e partilhada por todos os `Terrain`
  do mesmo mundo (cache estática). D8 com desempate diagonal → acumulação →
  nascentes → traços → lagos → leito. Números do mundo atual: **7 645
  segmentos, 738 células de rio, 49 lagos**; arranque ≈ **1,5 s no wasm** (só
  na primeira construção; nativo é uma fração).
- **Leito** — raster de 8 m, `depth·1,35·(1−d/reach)^1,7`, máximo dos
  segmentos (confluências não somam vales).
- **Nível da água = leito + 0,85·profundidade** (`_retune_levels`). Sem isto, o
  nível vinha do relevo ideal e 2/3 da rede ficava seca: o raster de 8 m não
  representa um rio de 3 m. Com a correção, **7 645/7 645 segmentos têm água**.
- **Mundo → água e água → mundo**: as margens ficam com areia/lama a partir do
  `carve`; o mangue entra no bioma; `is_ocean` deixa de chamar mar à foz
  (leito escavado = água doce); a garrafa enche água doce no rio e salgada no
  mar.
- **Corrente que se sente**: `Water.sample()` devolve `flow`+`speed`; o jogador
  nada/vadeia com um empurrão até 58 % da velocidade (nunca prende: 1,39 m/s
  contra 4 m/s a andar) e os itens largados descem o rio devagar.
- **Shader**: UV2 passa a `(profundidade, salinidade)` e COLOR leva
  `(velocidade, turvação, corrente 2D)`. Ondas grandes no mar, ondulação curta
  e riscos alinhados com a corrente no rio, espuma em corredeiras e margem,
  água barrenta no mangue. O mesmo material serve mar, rio e lago.
- **Custo**: um único raster de 400 KB e 4 leituras por vértice; a cache de
  segmentos por bucket passou a usar a margem real do leito (com margem fixa
  de 34 m, um chunk de rio custava **7 s**; agora fica abaixo de 400 ms).

PNG: `docs/shots/07_rio_do_relevo.png` — o rio no vale, com as margens que o
leito abriu.

**Ainda por fazer na Etapa C:** maré desenhada (subida/descida visível na
costa), espuma/ondulação do mar ao longe, juncos no mangue, peixes, filtro de
carvão (C5) e a chuva a alimentar a rede em tempo real.

## Etapa B concluída — fome e sede passam a governar o corpo

**Verificação: 229 ok, 0 falhas, 31 saltadas (SELFTEST_PASS).**

A fome era um contador de rodapé: descia sozinha e não mudava nada até chegar a
zero. Agora atravessa o corpo inteiro, e o jogador sente-a nas pernas:

- **Fôlego**: `player.stamina_reserve()` — com fome a 5 e sede a 5, a reserva
  cai de 100 para **40**, e a recuperação de **9/s para 2,2/s**. O sprint deixa
  de ser infinito quando o corpo está vazio.
- **Braços**: `survival.work_multiplier()` passou a contar sede (<20 → 0,88) e
  enjoo (>0,2 → 0,85), além da fome; bater num nó esfomeado gasta **1,45×** mais
  energia e **1,3×** mais com sede.
- **Esforço medido** (`player.exertion`): correr acumula cansaço a 0,11/s. O
  sono lê-o — `sleep_until_morning(..., exertion)` soma até **+0,18** de
  qualidade. Um dia duro rende uma noite melhor; um dia parado, pior. O esforço
  é gasto ao dormir (−80), por isso não se acumula entre dias.
- **Sem texto novo.** Nada disto diz ao jogador o que fazer: ele sente o sprint
  a acabar mais cedo e percebe que precisa de comer.

PNG: `docs/shots/06_fome_sede_folego.png` (o efeito no ecrã a acompanhar).

**Bug apanhado pelos testes:** o bloco novo foi inserido entre a ação da
cadeira e a sua verificação, e os testes de sono lá dentro avançavam o relógio
para as 6,8 — a cadeira "passava a noite". Reordenado; é a prova de que os
testes estão a ver o estado real e não só a correr.

## Etapa A concluída — o corpo sente-se em vez de se explicar (branch 49b92551)

**Verificação: 224 ok, 0 falhas, 31 saltadas (SELFTEST_PASS).**

O dono foi claro: *"as coisas podem ser descobertas pelo jogador, apenas vem o
efeito"*. Esta etapa não acrescenta sistemas — muda a **linguagem** com que o
jogo responde, e fá-lo em todo o lado de uma vez.

- **O véu da HUD passou a ser o corpo.** `hud.gd::_vignette` tem uniformes para
  fome, sede, cansaço, frio e enjoo. Todos **escurecem** as bordas (somar cor
  clara lia-se como neblina sobre a relva — a primeira versão foi rejeitada por
  isso e substituída). Cada um tem a sua cor escura: âmbar na fome, cinza na
  sede, azul-gelo no frio, verde no enjoo. O cansaço fecha as pálpebras, com um
  pulso duplo e lento.
- **O corpo treme.** `player.fatigue_level()` junta fome+sede+sono; abaixo de
  ~35 a câmara treme, o FOV aperta e a respiração entra no bob. Não há aviso
  escrito para isto — sente-se.
- **O corpo faz barulho.** `Sfx` ganhou `stomach` (gorgolejo a 45 de fome) e
  `breath` (respiração a 30 de energia). São avisos que não se leem.
- **Comer estragado passou a ser enjoo, não dano.** `survival.illness` sobe a
  0,75 e cai em ~20 s, com dano lento (`0,22/s × illness`) e a vista verde a
  respirar. O jogador vê a causa; ninguém lhe diz "cozinhar evitava isto".
- **O texto deixou de entregar a solução.** 24 chaves nos dois idiomas foram
  reescritas: a mensagem confirma o que aconteceu ("Bebeste do rio.", "As
  pálpebras pesam."), nunca a estratégia. Um teste **falha** se voltar a
  aparecer "cozinhar na fogueira", "Z no chão", "Junta-lhe madeira", etc.
- **O fogo vê-se a morrer** antes de apagar: a luz e a chama encolhem com o
  combustível e a chama fica mais nervosa. Deixa de ser binário.
- **`tools/render_feel.py`** porta o shader para Python, para o efeito ser
  provado com imagem em vez de afirmação. PNG: `docs/shots/04_corpo_a_falhar.png`.

## Etapa 2 — laboratório em 3D + modo deus (2026-10-18)

- LabWorld (vindo do main/PR #9) ganhou corpo: `LabMesh` (mesh suave +
  colisão por pedaços de 50 m), `LabScene` em `scenes/lab.tscn` com água,
  vegetação por afinidade, estações-plataforma e o Player real a nascer.
- Modo deus (`LabDev`): voar (F), cavar (LMB), aterrar/reconstruir (RMB),
  partir (E), painel F1 com TODOS os itens, repor mundo. O mundo
  destrói-se e reconstrói-se pelos deltas do `dig()`/`fill()`.
- **Verificação: LABSCENE_PASS 12/12, LABTEST_PASS 14/14, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.
- **Correção winding/normais (2026-10-18, pós-teste do dono):** os índices
  do terreno e da água em `LabMesh` estavam espelhados face à convenção do
  repo (`chunk.gd`; KNOWN_ISSUES #9 — frontal = horário no Godot), por isso
  a face de cima era descartada por backface culling e só se via por baixo.
  Ordem corrigida (terreno `[a,b,d / a,d,c]`, água `[0,1,3 / 0,3,2]`,
  colisão igual), auditoria nova `LabMesh.winding_mismatch()` e regressão
  no labscene: **LABSCENE_PASS 14/14 (0 triângulos maus no terreno e na
  água)**, LABTEST_PASS 14/14, selftest 245 ok / 0 falhas / 30 saltadas.
  `tools/render_lab3d.py` passou a recusar PNG se a winding voltar a virar.
- Pack de teste local: `Blessed_Lab_Etapa2_pack.zip` (só ficheiros da
  etapa; extrair por cima da pasta Blessed e abrir `scenes/lab.tscn`).

## Marco mais recente — o SONO e o FOGO passam a ser sistemas (2026-10-17, tarde)

**Verificação: 215 ok, 0 falhas, 31 saltadas (SELFTEST_PASS)**, incluindo o
teste do primeiro dia (25/25 no modo rápido).

- **Dormir deixou de ser um salto no relógio.** `data/sleep.json` guarda
  qualidades (chão 0,30 / cadeira 0,45 / cama 1,00), horas e custos. A sequência
  é: deitar → a câmara desce → o ecrã escurece → as horas passam → clareia →
  levantar. O jogador fica sem controlo durante ela e o teste espera por
  `interaction.sleeping == false`.
- **Dormir paga-se:** fome −3,4/h e sede −4,2/h. Sem isso era um botão grátis
  para saltar a noite. Fogueira acesa (+0,25) e abrigo (+0,20) melhoram a
  qualidade; uma criatura a rondar (`creature_threat ≥ 0,35`) **impede** de
  dormir.
- **A cadeira é um cochilo** (1,5 h, não passa a noite) — antes era +14 de
  energia instantâneos, exactamente o "Sleep -= X" que o projecto recusa.
- **O fogo gasta-se** (`data/fire.json`): 5 h por carga, +1,4 h por madeira (F),
  aviso a 1 h, e dormir queima combustível. Sem lenha, a noite acaba em cinzas
  e o `near_fire` desaparece.
- **Feedback corrigido:** comer carne crua e adoecer já não diz "Estás com
  fome"; diz que caiu mal e que cozinhar evitava. E o cansaço avisa aos 20 de
  energia com a tecla que resolve (Z), não só a zero.
- **Trabalhar exausto rende 30% menos** — a energia passou a pesar no loop.

## Marco anterior — o PRIMEIRO DIA joga-se de ponta a ponta (2026-10-17)

**Verificação: 197 ok, 0 falhas, 30 saltadas (SELFTEST_PASS)** — 167 verificações
anteriores + **25 do teste de GAMEPLAY do primeiro dia** + **5 da água do mar**.

- **Existe agora o teste que a constituição exige** (`tests/selftest.gd::_first_day()`):
  uma SESSÃO, não um teste de função. Mochila vazia, mãos nuas, e a cadeia
  inteira pelos sistemas reais:
  fibra/graveto → pedra solta → árvore abatida à mão → madeira →
  **lasca** → **picareta primitiva** → **rocha** → **bancada** (feita na
  Criação, pousada no mundo, F abre o painel DELA e não a apaga) →
  **picareta de pedra** → **rocha dura** (recusa tier 1, cede a tier 2) →
  **fogueira** (acender exige isqueiro) → **garrafa** → encher → **ferver** →
  beber → **carne assada** → **cama** → **noite passada**.
  Modo rápido: `-- selftest dia1`.
- **A travessia da pedra está fechada e é a certa:** mãos → pedra solta
  (`flint_node`) → **lasca** → **picareta primitiva** (Criação, na mão) →
  rocha → bancada → picareta de pedra. A lasca **não pica pedra** (é faca); é
  a picareta primitiva que faz a travessia — a função que a família de madeira
  fazia, agora com o nome certo.
- **`needs_tier` deixou de ser código morto:** o `_hold_work` já o lia, mas
  nenhum nó o declarava. `rock_hard` declara `"needs_tier": 2`, e é isso que
  faz a picareta de pedra valer a bancada.
- **Rendimento das mãos corrigido por *feel*:** as mãos só desperdiçam quando
  **arrancam** (`chop`/`mine`, 0,7×); **apanhar** é preciso (1,0×). E o arbusto
  passou a dar `fiber 2 + leaf 3 + stick 1`: o primeiro minuto tem fibra,
  folha e um graveto sem obrigar a abater uma árvore à mão só para um pau.
- **Harness headless recuperado e agora PERSISTENTE** em `tools/`:
  `tools/run.mjs` (motor web em Node; arranca com `Module.callMain`, **nunca**
  `emnapiInit`) e `tools/mkpack.py` (`.pck` com `tests/` dentro). O sandbox
  perdeu o `/tmp` duas vezes nesta sessão e o harness com ele.

- **O MAR TEM REGRA PRÓPRIA (constituição §5):** encher a garrafa no mar dá
  **água salgada** (`water_salt`, ícone e nome próprios); ferver **não** a
  transforma em potável; beber dá **Desidratação** — durante 45 s a sede
  escorre 2,6× mais depressa — e **nunca dano instantâneo**. Beber água doce
  cura. Provado: `0.455/s vs 0.175/s`, `hp 100 → 100`.

> Nota de método: as 4 causas que este teste apanhou e que os testes de função
> não apanhavam estão em `docs/GAMEPLAY_ARCHITECTURE.md` §6.2.

## Marco mais recente — ciclo do primeiro dia fechado (2026-10-16, continuação)

**Verificação: 161 ok, 0 falhas, 30 saltadas (SELFTEST_PASS)**, depois do merge
do `main` e com o `.pck` reconstruído. O que mudou, por ordem do que o jogador
sente:

- **A ÁRVORE CAI (bug encontrado e corrigido).** Dois erros somados: (1) o nó da
  árvore abatida tinha `sync_to_physics = true`, e o servidor de física reescrevia
  o transform — a rotação escrita pela queda era perdida a meio, e era isto o
  "só encosta um pouquinho e fica parada"; (2) o tronco levava o material das
  FOLHAS (translúcido, com vento, sem resposta à luz) e a copa inteira no LOD0 —
  era esta a "cor esquisita, mais plana, como se a luz já não a afetasse".
  Agora: queda em `_physics_process` (1,05 s, ~88°, com aceleração, o eixo
  assenta à altura do raio do tronco), material `structure`, tronco sem copa
  (`Species.trunk_lods`), impacto com som/partículas/dano a quem estiver no lado
  da queda, e o tronco deitado é o alvo da interação.
  _Prova:_ `docs/shots/2026-10-16-arvore-abatida.png` (medido: `settled=true`,
  `rot_z=1.53 rad`).
- **A FOGUEIRA deixou de ser um monte de calhaus brancos com dois pauzinhos.**
  Anel de 9 pedras de granito, leito de cinza, quatro achas radiais e três
  tições; **três camadas de chama** (exterior/média/núcleo, cada uma com a sua
  velocidade, eixo e energia — antes era um cone laranja igual a si mesmo);
  **luz que treme** (duas frequências + cor que respira), que era o que faltava
  para o fogo não parecer uma lâmpada laranja.
  _Prova:_ `docs/shots/2026-10-16-fogueira-jogador.png` (câmara do jogador).
- **O CRAFT passou a ter dois degraus, e são degraus de verdade.** Na mão
  (**"Criação"** no inventário) faz-se o improviso: ramos, fibra, tocha,
  **isqueiro primitivo** (sílex + pedra + fibra) e **lasca de pedra** — a lasca
  corta e pica devagar e é o que destranca a pedra. Na **bancada** fazem-se as
  ferramentas a sério (machado e picareta), o mobiliário e as peças de
  construção. A família de madeira a mais (machado/picareta de madeira) foi
  removida: era um passo intermédio que não mudava nada na mão do jogador.
- **Acender fogo exige isqueiro.** Sem ele, a fogueira não acende e o jogo diz
  porquê. Sem isto, "acender" era um botão mágico.
- **A água tem decisão.** Água do rio é **crua** (mata a sede toda, mas há
  risco); na fogueira ferve-se e sai **água fervida** (sem risco, mais sede por
  frasco). O ciclo mãos → fogueira → água segura fecha-se no primeiro dia.
- **As construções servem para algo.** **Cofre** guarda por tipo (F põe o que
  tens na mão, F com a mão vazia devolve o que lá está) — a mochila tem 24 slots
  e enchia-se sem sítio onde deixar coisas; **cadeira** descansa sem deitar
  (energia + cabeça). Nada de mobiliário decorativo.
- **As receitas saíram para `data/recipes.json`** (editável sem tocar em código,
  como os biomas): estação, ingredientes, resultado e o nome de cada degrau. A
  lista em código fica como reserva, para o jogo não morrer se o JSON falhar.
- **Ferramentas de diagnóstico**: `tools/render_shot.py` passou a desenhar a
  CHAMA (aditiva, com três camadas) e o `tests/shot.gd` ganhou `--fell` (abate e
  espera pela queda) e `--fire --player` (olha para a fogueira pela câmara do
  jogador). O `shot` marca `Game.started = true` — sem isso o prólogo agarrava o
  jogador e nenhuma fotografia era do sítio pedido.

## Marco anterior — relva reconstruída e instrumentos corrigidos (2026-10-16)

- **Relva: o "picotado em camadas" está resolvido e medido.** A causa não era o
  empilhamento de níveis: era ESCALA. `GRASS_MASK_SCALE` era 0,36 m, o que dava
  lâminas de ~5 mm — sub-pixel a partir de um metro de distância. Cada lâmina
  virava um ponto de alto contraste sobre um chão de outra cor. Agora o ladrilho
  da máscara tem 1,05 m (lâmina ~1 cm, 68% de cobertura, 11–27 cm de
  comprimento), a densidade nunca cai a meio do alcance e a relva por níveis
  desvanece aos ~50 m, onde continua nas cores do terreno.
- **A cor da relva vem do bioma** (`Terrain.grass_tint_of`): a lâmina leva a cor
  da relva daquele ponto (viçosa no húmido, seca na savana/deserto) em cor de
  vértice/instância; o shader só acrescenta a rampa base-escura → ponta-clara.
  Acabou o verde-atlas sobre chão amarelo.
- **Terra castanha debaixo da relva** (`toon_terrain`: `soil_near = 4`,
  `soil_far = 20`): de perto vê-se o solo onde a relva cresce; ao longe domina a
  cor da relva, para o campo não ler como poeira.
- **O rasterizador de diagnóstico passou a ver os shaders de relva.** O
  `tools/render_shot.py` avalia agora, pixel a pixel, a máscara (altura/tom/
  massa), os `discard` (nível, densidade, distância) e a cor por
  vértice/instância dos dois shaders de relva. Foi isso que permitiu medir em
  vez de adivinhar — e revelou dois erros graves nos próprios instrumentos:
  **culling invertido** (o Godot é horário; 178.469 de 235.000 triângulos iam
  para fora) e **MultiMesh sem transmissões em headless** (o dump não tinha
  cartas de relva nem árvores; resolvido com `scripts/core/shot_meta.gd`).
- **Bugs do mundo corrigidos:** ternário com array literal devolvia vazio
  (`species.gd`) → as três variedades de rocha desapareciam do mundo e a
  instância sem malha rebentava a build web; partículas de impacto sem malha no
  Compatibility; raio de 4,5 m limpo de vegetação à volta do nascimento.
- **Verificado:** `SELFTEST` 102 ok / 30 falhas, sendo todas as 30 dos modelos
  Blender que o template web NÃO consegue descodificar sem editor
  (`GLTFDocument` ausente — ver KNOWN_ISSUES #14); zero `Parse Error`, zero
  `SHADER ERROR`, zero "Cannot open file". Imagens do chão em `docs/shots/`.

## Marco anterior — água, luz local e relva (2026-10-15)

- Água usa shader opaco de dupla face, ondas/espuma estilizadas e paleta diferente
  debaixo da superfície; o tipo mar/rio agora é passado ao shader corretamente.
- Luzes locais usam decaimento contínuo nos materiais toon, sem bandas que
  facetavam o alcance da fogueira.
- Relva combina cartões MultiMesh com a textura Quaternius perto do jogador,
  shells com a mesma paleta até ao LOD distante e pintura do terreno no horizonte.
  A cobertura respeita pradaria/savana e transições, excluindo areia de praia,
  deserto e declives fortes; os níveis dos shells coincidem entre LODs.
- **Verificado:** arranque Godot 4.7.2 headless e compilação dos shaders sem
  erros. O renderizador de diagnóstico não reproduz o mascaramento do shader
  procedural de shells/cartões; a aparência e o FPS no renderer real ainda
  precisam de confirmação no jogo.

## Marco mais recente — vegetação e céu (2026-10-14)

- 14 famílias de modelos gratuitos Quaternius CC0 foram integradas como assets separados,
  com ficheiro-fonte Blender editável e LODs. O kit procedural anterior foi preservado.
- Kenney CC0 fornece três panoramas 2K e sprites de partículas. O céu liga sol e lua ao
  relógio do jogo, tem fase lunar, halo e nuvens estilizadas com deslocamento em duas escalas.
- A regra de chunks mantém detalhe e sombras perto do jogador; os anéis afastados usam LODs,
  sem colisão detalhada. Ver `docs/MODEL_SCALE_GUIDE.md`.
- **Verificado:** Godot 4.7.2 headless, 125 verificações aprovadas, 0 falhas; log final sem
  erros ou avisos. Os avisos ObjectDB da passagem antiga não reapareceram nesta execução.
- **Ainda por verificar visualmente:** renderização real, performance/FPS/VRAM em Forward+
  e Compatibility/Web. O teste headless comprova carregamento e lógica, não a qualidade da
  imagem no GPU. A prioridade seguinte está em `docs/PRIORITY_ROADMAP.md`.

## O que é
Sandbox de sobrevivência em 1.ª pessoa por omissão, estilizado "anime", em Godot 4.7.2.
Fatia vertical jogável: mundo procedural (chunks), dia/noite, NPCs, colheita,
crafting, construção, sobrevivência, prólogo com criação de personagem,
PT/EN, save/load. O cenário é híbrido: geração GDScript e um kit de modelos Blender.

## Como corre
- **Preview web (Arena):** `tools/serve_web.py` + `export/web/blessed.pck`.
  Renderer web = `gl_compatibility` (definido em `project.godot`).
- **Local (máquina do dono):** abrir `project.godot` no Godot 4.7.2 e F5.
  O renderer local por omissão é Forward+; o web é Compatibility.
- **Testes do projeto:** `./tools/check.sh` (selftest headless; última execução: 125 checks).
- **Auditoria de erros:** correr o selftest e ler TODAS as linhas `ERROR:` —
  foi assim que se apanharam os bugs de API Godot-3 (ver KNOWN_ISSUES #1-#5).

## Estado por sistema (OBSERVED = medido, não opinado)
| Sistema            | Estado   | Prova |
|--------------------|----------|-------|
| Mundo/chunks       | OK       | selftest + rasterizador (`docs/shots/`) |
| Controlos          | OK       | selftest (tabela de teclas) |
| Água               | hidrologia procedural (7 645 seg., 49 lagos), leito escavado, nível por leito, corrente no jogador/itens | selftest 242 ok; PNG `07_rio_do_relevo.png` no renderer real; maré e juncos pendentes |
| Céu/sombra/LOD     | céu Kenney CC0 2K, sol/lua e nuvens dinâmicos; LODs por anel | importação e contratos no selftest; imagem/FPS GPU ainda não medidos |
| Relva/árvores      | 14 famílias Quaternius CC0, espécies separadas e LODs | meshes, dimensões e instâncias validados no Godot headless; aparência no renderer por validar |
| NPC                | componente sprite 2D com variações; sem aldeões ativos na cena atual | script incluído no selftest; aldeões não aparecem na cena |
| Criatura noturna   | sprite 2D billboarding e fade de amanhecer | tipo de sprite confirmado no selftest; imagem não inspecionada |
| Música              | temas procedurais por fase e transição cruzada | seleção/funções confirmadas; mistura não ouvida |
| Câmara              | 1.ª pessoa por omissão; `V` alterna para câmara externa | selftest a validar nesta passagem |
| HUD                 | barra rápida com ícones e seleção, needs compacto, alvo contextual | menu mochila/bancada e slots conferidos no selftest; sem captura visual |
| Interação           | plantas com F; árvores/rochas com LMB mantido, dano por golpe e feedback | queda e respawn da árvore confirmados no selftest |
| Mãos 1.ª pessoa     | malha do item acompanha o espaço rápido; ferramentas desenhadas | nó/malha testados; imagem no renderer não inspecionada |
| Prólogo            | primeira frase agora escrita | selftest |

## Próximo marco (por ordem)
1. Capturar o jogo no renderer real em dia, crepúsculo e noite; medir FPS e VRAM em
   Forward+ e Compatibility/Web antes de mexer em qualidade ou densidade.
2. Melhorar ferramentas/mãos de primeira pessoa e feedback de colheita/construção.
3. Resolver margens e saídas de rios, depois expandir vida selvagem e som.
   Ver `docs/PRIORITY_ROADMAP.md` para critérios de aceitação.

## Auditoria local anterior (2026-10-14)

Os apontamentos abaixo são o registo da passagem anterior; os estados atuais de vegetação,
céu e testes estão no marco mais recente no topo e em `docs/AUDIT_2026-10-14.md`.

- **OBSERVADO:** o repositório não contém assets de áudio; `Sfx` já gerava efeitos em PCM.
  Não havia trilha musical, NPCs eram malhas 3D e a criatura noturna também era 3D. O avatar
  2D existia, mas ficava escondido porque a vista inicial era em 1.ª pessoa.
- **ALTERADO:** música procedural adaptada às fases do dia, protagonista 2D visível por
  omissão, sprites billboards para aldeões futuros e para a criatura noturna.
- **VERIFICADO:** Godot 4.7.2 headless executou o selftest: 86 verificações, 0 falhas.
  Foram corrigidos erros de inferência de tipos e atribuições de transformação no rig de
  diagnóstico que surgiram durante a execução.
- **ALTERADO:** HUD com ícones desenhados no jogo, seleção da barra rápida, mochila e bancada
  com ícones, receita com contagem de ingredientes, comandos de interação sem duplicação,
  dano por golpe, queda/respawn das árvores e recolha de excesso deixado no chão.
- **ALTERADO:** mãos/item em primeira pessoa inicializam corretamente; o salto ganhou um
  som próprio suave em vez de reutilizar um som de passo.
- **UNKNOWN / NOT VERIFIED:** o executável Blender 5.2 está assinado, mas o Windows terminou
  a tentativa de execução desta sessão com `-1073741790`; nenhum `.blend` ou `.glb` foi
  gerado. O machado e a picareta continuam a ser malhas geradas por GDScript nesta revisão.
- **LIMITAÇÃO OBSERVADA:** o processo termina com aviso de 8 instâncias ObjectDB ainda
  referenciadas.
- **UNKNOWN / NOT TESTED:** build web, execução interativa, aparência visual em Forward+ e
  Compatibility, desempenho e audição da mistura musical. O teste headless não comprova
  esses resultados.

## Escavação por camadas + ferramentas (2026-10-18, pós-teste do dono)

- Raio de escavação reduzido (4,5 m → mão 1,5 / pá 2,3 / picareta 1,3 m),
  perfil co-seno sem degrau na orla.
- Materiais geológicos (`LabWorld.material_at`): areia (margem/leito),
  terra, rocha (afloramento ou >2,3 m escavados); dureza 1–3; rendimento
  areia→sand, terra→soil, rocha→stone. Itens novos: `sand`, `shovel`
  (+ receita `stone_shovel` em Db e data/recipes.json, locales).
- Ferramentas com regras: mão não parte rocha nem terra compacta; pá
  inútil na rocha; picareta é a única na rocha. Negação por efeito.
- Água refeita: mesma grelha do terreno + recorte pelo campo assinado
  (nível−altura) — costa soldada, sem serrilhado/triângulos órfãos.
- Nada flutua: `reseat_props` assenta props/estações; árvore sem ≥1 m de
  chão cai com física e vira drops da espécie.
- HUD dev compacto: barra de ferramentas (roda/1-3), material sob a mira.
- **Verificação: LABSCENE_PASS 20/20, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.

## Relva que reage à escavação (2026-10-18)

- `LabScene.grass_density()` lê a superfície atual: zero em água/areia/
  rocha/declive>0,38/`depth_dug>0,1`; prados densos com humidade.
- MultiMesh por pedaço (6 candidatas/célula, ~3517 lâminas), AABB explícita
  por pedaço, sem Node por lâmina, custo zero por frame fora do rebuild.
- Escavar/aterrar reconstrói só o pedaço; pedaço perturbado recresce
  0,15→1 em ~24 s em degraus de ¼ (`advance_growth`).
- **Verificação: LABSCENE_PASS 24/24, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.

## Estação de escavação jogável (2026-10-19)

- Relíquia enterrada a 3,2 m na `dig_pit` (30,30): pá para na rocha
  (2,3 m), só a picareta desenterra. Glint dourado na poeira (proximidade
  × profundidade) como pista sensorial; burst + flash dourado ao emergir.
  Item novo `relic` (Db + locales). Descoberta pelo efeito, sem texto.
- **Verificação: LABSCENE_PASS 29/29, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.
- Entrega: UM pack cumulativo `Blessed_Lab_Tudo_pack.zip` (pedido do dono:
  nada de mini-zips por implementação).

## Construção inteligente no laboratório (2026-10-19)

- Snap 2 m, fundação adaptativa com estacas (até 2,6 m), estabilidade
  1,0→0,58 com preview verde/amarelo/laranja/vermelho, regras de suporte,
  colapso em cascata, custo em materiais e reembolso de 50% ao remover.
  Modo construir no LabDev: tecla B, roda/1-5 escolhe peça, R roda parede.
- **Verificação: LABSCENE_PASS 37/37, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.

## Construção expandida: porta/janela/escadas/telhado (2026-10-19)

- Porta (vão real) e janela (peitoril+lintel) como parede; escadas de 5
  degraus pisáveis; telhado de duas águas com cumeeira; rotação em 45°.
- **Verificação: LABSCENE_PASS 44/44, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.

## Polimento da construção (2026-10-19)

- Poeira por material + sons sintetizados ao colocar (madeira/pedra),
  poeira peça a peça e estrondo no colapso; casinha-exemplo de 15 peças
  nasce pronta junto à clareira de construção.
- **Verificação: LABSCENE_PASS 46/46, LABTEST_PASS 18/18, selftest
  245 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.

## Base HD2D + sprites da Lúcia v2 (2026-10-19)

- Decisão do dono: `agent/hd2d-art-pass` é a base superior. Integrada
  na branch de trabalho (af7a573): player/corpo/mãos, animais, mundo,
  sfx com vozes limitadas + os nossos sons de construção, testes
  novos, perf/gpushot/labshot, AUDIT. Preservado o que ela não tinha:
  construção inteligente do laboratório, briefing, pack.
- Do lab HD2D: malha com pesos de material (UV/UV2, contrato do shader
  do mundo) e `footstep_material_at` (passos por material no lab).
- Lúcia v2: poses nas 8 direções por grupos (idle/walk, run/jump,
  comb1-3/dano/medo/defesa, swim/fast/deep, sit/sleep/coleta/drag/
  drop/carry) + versões sem fundo. v1 arquivada como rascunho errado.
  Manifesto `content/characters/lucia/lucia_sprites.json`; guia
  `docs/SPRITES_LUCIA.md`. Falta: recorte Pixelorama p/ grelha final.
- **Verificação: selftest 250 ok, LABSCENE_PASS 46/46, LABTEST_PASS
  18/18.**

## Eficiência + construção ligada (2026-10-19)

- Base HD2D completa na branch: `.gitignore`, LEIA-ME, guia de escala
  com LOD medido (42/85/135 m), `tests/shot.gd`.
- Eficiência: materiais/BoxMesh partilhados por peça, material de
  água em cache, água só reconstruída perto de água (contador prova).
- Gameplay: fundação alinha nível com a vizinha; bónus de estabilidade
  por ligação (fundações/paredes vizinhas). Sprites: cancelados por
  agora a pedido do dono (ficam arquivados em content/characters/lucia).
- **Verificação: LABSCENE_PASS 50/50, LABTEST_PASS 18/18, selftest
  250 ok / 0 falhas / 30 saltadas.** PNG: `docs/shots/09_lab_3d.png`.
