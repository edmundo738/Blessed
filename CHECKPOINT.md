# CHECKPOINT — estado atual do projeto

> Este ficheiro é a memória do projeto. Qualquer IA (ou humano) que abra o
> repositório começa por lê-lo. Atualiza-se no fim de cada marco.
> Última passagem de auditoria: 2026-10-14 (Godot 4.7.2 headless: 125 verificações, 0 falhas).
> O histórico de auditoria abaixo preserva resultados antigos; quando diferirem, prevalecem
> este marco mais recente e `docs/AUDIT_2026-10-14.md`.

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
| Água               | shader opaco dupla face, ondas/espuma; sem depth-texture | shader e arranque Godot headless; aparência no renderer real pendente |
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
