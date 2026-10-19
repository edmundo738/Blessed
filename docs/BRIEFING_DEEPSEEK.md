# BRIEFING COMPLETO — projeto BLESSED (para o agente DeepSeek Flash)

---

## ⚠️ LEITURA OBRIGATÓRIA ANTES DE TUDO — veredito e direção de arte do dono

**1. Nada neste jogo está bom só porque existe.** Veredito do dono, que já
jogou tudo: *"nada nesse jogo está bom, desde a gameplay até aos modelos.
Os modelos são figuras geométricas que não fazem sentido."* Portanto:
código que corre, teste que passa ou modelo que carrega **não** significa
"bom" — significa, no máximo, "provisório". Se vires uma árvore feita de
cilindro + esferas, um animal feito de caixas ou um personagem-cápsula,
isso é um **placeholder por substituir**, não um asset aprovado. Nunca
apresentes uma figura geométrica estranha como trabalho acabado.

**2. A direção de arte é HD-2D / 2.5D — duas técnicas combinadas:**

| O quê | Técnica |
|---|---|
| **Pessoas, animais, peixes, aves, monstros** | **Billboarding direcional** (sprites 2D em 8 direções que rodam para a câmara) |
| **Ferramentas e armas** (picareta, machado, pá, lâmina…), **mãos em 1ª pessoa**, **itens** (na mão e largados no mundo) | **Sprites** — nas mãos como *viewmodel* 2D animado; no mundo como billboards |
| **Todo o resto**: terreno, água, árvores, rochas, vegetação, paredes, tijolos, madeira, estruturas, aldeia | **3D estilizado** (toon low-poly, como os shaders atuais) |

Esta divisão **substitui** qualquer instrução anterior deste documento
sobre "criar modelos 3D para o jogador/animais". Personagens 3D com rig
**não** são o caminho. O projeto já tem uma semente disto:
`scripts/player/pixel_avatar.gd` e os frames em
`content/characters/camp_to_me/` (pastas por direção) — hoje pobres e
incompletos; a técnica está certa, a arte está má.

**Especificação dos sprites (o que tens de desenhar/gerar):**

- **Personagem desenhado a sério**: silhueta legível (cabeça, tronco,
  braços, pernas, roupa/cor própria), não um boneco de palitos nem uma
  cápsula com olhos. Cada ser com identidade por espécie (o carvalho
  anda igual? não — cada animal/NPC com as suas cores e proporções).
- **8 direções** por ser (frente, frente-direita, direita, trás-direita,
  trás, trás-esquerda, esquerda, frente-esquerda). A troca é matemática:
  `ângulo_relativo = wrapf(yaw_da_câmara − yaw_do_ser, 0, TAU)`,
  `linha = round(ângulo_relativo / (TAU/8)) % 8`. Billboard **cilíndrico**
  (roda só no eixo Y, sempre de pé — nunca esférico a tombar para trás).
  No Godot: `Sprite3D`/`AnimatedSprite3D` com billboard em Y, `shaded`
  ligado (para a luz do mundo o pintar), `alpha_cut` por corte, filtro
  **Nearest** (pixel art nítida), `pixel_size` consistente com a escala
  do `MODEL_SCALE_GUIDE.md` (personagem ≈ 1,7 m no mundo).
- **Animações por ação, em cada direção relevante**: parado (idle, 2–4
  frames com respiração), andar (6–8 frames), correr se existir, e as
  ações de gameplay do ser: para o jogador/NPC — cortar, escavar/minerar,
  colher/apanhar, atacar, magoar-se, dormir; para animais — pastar/
  espreitar, andar, fugir, atacar, dormir; peixes — nadar (com ondulação,
  e tinta azulada debaixo de água); aves — voar (asas em 2–3 posições) e
  pousar. Ação sem sprite = ação que não se lê = não está feita.
- **Mãos em 1ª pessoa**: sprite 2D sobreposto (estilo *viewmodel* de
  DOOM): mão vazia, e **cada ferramenta desenhada na mão** (picareta de
  pedra ≠ picareta trabalhada ≠ machado ≠ pá). Animações: idle com
  balanço de andar (bob), golpe (swing com arco e recuperação), escavar,
  bloquear/magoar. A ferramenta na mão tem de ser a mesma que o inventário
  diz — sprite por ferramenta e por tier.
- **Itens**: cada item do `Db.ITEMS` com sprite próprio (já existem
  ícones procedurais em `ui/item_icon.gd` — são a referência de forma/cor,
  não o produto final). No mundo, o item largado é um billboard que
  flutua/roda suavemente; na mão, o sprite da ferramenta.
- **Variações**: por espécie/cor (palette swaps contam como variação
  barata), por tier de ferramenta, e 2–3 variantes de postura/frame para
  não haver exércitos de clones.
- **Sombras e chão**: sprite com sombra projetada quando o motor aceitar
  (material com corte alfa) ou sombra-blob (decal escura elíptica) por
  baixo — um ser sem sombra parece flutuar e isso reprova o asset.
- **LOD de sprites**: de perto, animação completa; longe (>60 m), frame
  estático da direção certa (trocar de animação a essa distância é custo
  invisível); muito longe, pode cair para o LOD do mundo. Peixes/aves
  seguem a mesma regra dentro de água/ar.

**Critério de reprovação imediata**: cápsulas, caixas, esferas ou
"bonecos" geométricos apresentados como personagens/animais/ferramentas;
sprites de uma só direção; ferramenta genérica para todos os tiers;
animação de andar com 2 frames trocados sem peso. Se for provisório,
diz que é provisório — nunca vendas placeholder como acabado.

### O estilo dos sprites: pixel art MODERNO com tempero PSX — e África

A referência não é pixel art genérica de fantasia europeia. É isto:

- **Base moderna (a maior parte):** pixel clusters limpos e legíveis a
  qualquer distância, paletas ricas mas controladas (24–48 cores por
  personagem), sombreamento com 3–4 degraus por material, silhueta que
  se lê em 32 px de altura no ecrã. Animação fluida para pixel art:
  idle com vida, andar com peso (contacto → passagem → impulso).
- **Tempero PSX (só o tempero):** um toque de *dithering* nas transições
  de luz, paleta ligeiramente dessaturada/quente, e a aspereza charmosa
  dos sprites de 32 bits — **sem** o jitter de vértices nem texturas a
  nadar dos modelos 3D PSX (isso é do 3D, e o nosso 3D é estilizado
  moderno). Se tiveres de escolher entre "moderno limpo" e "PSX sujo",
  escolhe moderno.
- **África (a identidade, não um filtro):** o mundo do Blessed nasce de
  Angola/África Austral e os sprites têm de o dizer sem palavras:
  - **Pessoas:** tons de pele variados e reais, cabelo crespo/carapinha
    em cortes variados, roupa com **tecidos de padrões geométricos
    (tipo samakaka)** em cores terra/ocre/vermelho/índigo, sandálias,
    panos ao ombro. Nada de "aventureiro europeu de chapéu" como default.
  - **Fauna desenhada das espécies reais da savana/mata:** cabrito e
    galinha de aldeia, cão, porco, peixes de rio (tilápia/cacusso),
    aves (galinha-do-mato, corvos, garças), e vida selvagem (macaco,
    javali, antílopes — a **palanca** é candidata a animal-emblema).
    Monstros: inspira-te no folclore e no medo real (escuridão, rio,
    mata) antes de copiar bestiário europeu.
  - **Ferramentas/itens:** picareta e machado de pedra lascada com cabo
    de madeira e amarras de fibra, pá de madeira endurecida, lâmina de
    pedra — objetos que parecem feitos à mão **aqui**, evoluindo para
    ferro trabalhado nos tiers altos.
  - **Paleta do mundo 2D:** terra vermelha, ocre, verde de savana seca
    e de mata húmida, céu quente. A mesma família de cor dos biomas 3D
    para os sprites nunca parecerem "colados" de outro jogo.
  (Os IDs de espécies atuais em `data/species.json` — carvalho, bétula,
  sakura… — são conteúdo provisório do protótipo: **não mudes IDs sem o
  dono decidir**; a camada de arte nova pode começar pelo jogador,
  animais domésticos e ferramentas, que não têm esse bloqueio.)

**A matemática direcional certa** (a versão que circula em tutoriais
com `signed_angle_to` entre os *forwards* da câmara e da entidade
espelha os lados — não a uses): o que interessa é **para onde a entidade
está virada vs. onde a câmara está em relação a ela**:

```gdscript
# no ser (Sprite3D/AnimatedSprite3D filho, billboard cilindrico no Y)
var to_cam := (cam.global_position - global_position)
to_cam.y = 0.0
var rel := wrapf(atan2(to_cam.x, to_cam.z) - facing_yaw + PI, 0.0, TAU)
var dir8 := int(round(rel / (TAU / 8.0))) % 8  # 0=frente ... 4=tras
# toca a animacao "%s_%d" % [acao, dir8] so quando (acao, dir8) muda
```

- 8 setores de 45°; com espelho horizontal podes desenhar 5 direções e
  espelhar 3 — mas o **desenho** tem de existir para as 5 (frente,
  frente-lado, lado, trás-lado, trás). Ferramentas na mão e assimetrias
  (escudo, marca da bênção) podem proibir o espelho: decide por ser e
  documenta no asset.
- Troca de direção com **histerese** (só muda após cruzar o centro do
  setor vizinho) para não piscar nos limites.

**Mãos/ferramentas em 1ª pessoa (viewmodel):**

- Implementação: `CanvasLayer` + `AnimatedSprite2D` (simples, nunca
  atravessa paredes) — é o caminho atual a evoluir; uma segunda
  `Camera3D`/SubViewport só se um dia quisermos luz 3D real nas mãos.
- Cada ferramenta: sprite próprio por tier desenhado na mão (pele/luva
  com variantes), idle com respiração, bob de andar (seno em X/Y com
  atraso), sway ao rodar a câmara, **swing com squash & stretch** no
  impacto, micro-shake local ao bater em rocha e *hit-stop* de ~40 ms
  em golpes pesados. O peso sente-se antes de se ver o dano.
- O feedback é sincronizado com o mundo: frame de impacto do sprite =
  frame em que a poeira/som do material acontecem (a mesma
  `material_at` decide cor da poeira e som — ver §4.5).

**Cohesão 2D↔3D (o "game taste" híbrido):**

- Sprites `shaded` (a luz do mundo pinta-os: fogueira avermelha, noite
  escurece), `cast_shadow` ligado com corte alfa (ave 2D projeta sombra
  real no chão 3D); sem sombra, sombra-blob elíptica por baixo.
- O 3D responde na mesma paleta: texturas/shaders toon com grão pixel
  subtil (ver §4.4) para os dois mundos casarem; contorno escuro fino
  nos sprites (outline de 1 px, cor da sombra mais escura do próprio
  sprite — nunca preto puro).
- Profundidade honesta: sprites ordenam-se pelo pé (pivot na base),
  peixes ganham tinta azul e desfoque de cor com a profundidade, aves
  encolhem/ganham névoa com a altura — tudo pela mesma atmosfera do 3D.

---

> **E o resto deste documento continua válido**: lê-o até ao fim antes de
> tocar em código. Ele diz-te
> o que estamos a construir, porquê, onde queremos chegar, **o que está
> mal e porquê**, e as tecnologias que tens de implementar/melhorar.
> O dono do projeto considera o estado atual **fraco em quase tudo** —
> a tua missão principal é **criar modelos 3D novos e melhores, e lapidar
> gameplay, física da água, física da terra/escavação, texturas, sons e LOD**.
> Motor: **Godot 4.7** (Forward+ local, Compatibility no export web),
> tudo em **GDScript**, mundo procedural determinístico por seed.

---

## 0. Como trabalhamos (regras que NÃO se quebram)

1. **Não presumas que o código atual está certo.** O protótipo é um
   laboratório/fonte de conhecimento. Para cada sistema pergunta:
   porque existe? O que afeta na gameplay? Que loops dependem disto?
2. **Não apagues sistemas por parecerem intermédios.** Melhorar, lapidar,
   sincronizar e dar uso é preferível a remover. Substituições fazem-se
   por fatias, mantendo o que já joga.
3. **Descoberta pelo efeito, nunca por texto.** Nenhum texto de gameplay
   pode revelar a solução. O jogador aprende vendo/ouindo/sentindo
   (poeira muda de cor, som muda, objeto cai). ~70% da comunicação é
   sensorial. Exceção deliberada: o HUD de desenvolvedor do laboratório
   (`LabDev`) é ferramenta do testador, não gameplay.
4. **Tudo se prova a jogar, numa estação do laboratório, antes de entrar
   no mundo grande.** Testes automáticos têm de provar gameplay e
   causalidade, não só sintaxe. Bug visual só se declara corrigido com
   imagem ou medição — nunca "passou nos testes, logo está bem".
5. **Determinismo:** mesmo seed + mesma versão de regras = mesmo mundo.
   Nada de sorteio independente por chunk que discorde nas bordas.
   Conteúdo e números vivem em `data/*.json`, não espalhados no código.
6. **Sem Node por cada lâmina de relva/planta.** Vegetação é MultiMesh
   por chunk. Sem conversão do mundo inteiro a voxels (voxel é só
   interno/local: cavernas e escavação profunda). WFC (Wave Function
   Collapse) só como composição local filtrada por campos contínuos —
   **WFC nunca controla a hidrologia**.
7. **Texturas/padrões nunca esticados numa direção fixa do mundo**
   (a "regra de ouro" do `shaders/toon_terrain.gdshader`): padrões
   isotrópicos ou projetados no plano da superfície (triplanar onde
   fizer sentido), sempre em espaço de mundo para não haver costuras.
8. Entrega de trabalho: código + testes a passar + **1 PNG por etapa**
   com o resultado + atualizar `CHECKPOINT.md`. O dono testa em Godot
   real; recebe sempre **link direto do GitHub** (nunca anexos).

---

## 1. O jogo — o que é e onde queremos chegar

**BLESSED** é um survival/exploração procedural em primeira pessoa:

- **Premissa** (`docs/DESIGN.md`): viveste muitas vidas; acordaste
  "abençoado" num mundo que não conheces, com uma marca da vida anterior.
- **Três tensões:** (1) dias serenos — explorar, construir, cozinhar,
  falar com gente; (2) noites que se lembram de ti — o medo é um estado
  que se acumula e que os NPCs notam; (3) a bênção — recurso que regenera
  devagar e explica porque o mundo te aceita. **Não há "game over"**:
  há consequências (fome, frio, medo, confiança perdida).
- **Princípio LEGO:** poucas peças boas + regras de combinação + contexto
  real + memória + personalidade. 5 espécies de árvore com madeira
  diferente e uso diferente valem mais que 40 iguais. Teste de entrada de
  qualquer conteúdo: *se não mudar uma decisão do jogador, não entra.*
- **O mundo é um sistema causal, não uma lista de objetos sorteados:**

```text
geografia → clima → hidrologia → solo → biomas → ecologia → recursos → gameplay
```

  A mesma coordenada tem de responder de forma coerente a: altura,
  declive, clima, água (nível/profundidade/corrente), bioma, espécies,
  recursos. Implementação: `Terrain.environment_at(x, z)` no mundo
  grande e `LabWorld.sample()` no laboratório — **uma só autoridade de
  dados, vários leitores**. Nunca inventes uma segunda fonte de verdade
  (ex.: um sistema de água que não lê a mesma hidrologia).

- **Cadeia canónica de agentes** (jogador/NPC/criatura):
  PERCEPÇÃO → INTERPRETAÇÃO → INTENÇÃO → DECISÃO → MANIFESTAÇÃO →
  CONSEQUÊNCIA → MEMÓRIA (`scripts/entities/npc.gd` é a referência; a
  memória dos NPCs é real e altera interpretações futuras).
- **Comando ≠ resultado:** `Game.request(id, args)` devolve sempre o que
  foi observado (`{"ok": false, "failed": true, "reason": ...}`). Um
  comando que não fez nada **tem** de devolver `failed: true`.

---

## 2. Estado real do projeto (mapa de ficheiros)

### 2.1 Mundo grande (o jogo)

| Área | Onde | Estado honesto |
|---|---|---|
| Terreno | `scripts/world/terrain.gd`, `chunk.gd` (chunks de 48 m, heightfield) | Funciona, com costuras/LOD por lapidar |
| Geologia | `scripts/world/geology.gd` | Províncias contínuas (aluvião/arenito/calcário/granito/basalto), dureza afeta erosão — base boa |
| Hidrologia/água | `scripts/world/water.gd` (`build/sample/carve`, D8, lagos por priority-flood, rios escavados) | **A ir na direção certa** — falta física/juice |
| Biomas/espécies | `scripts/world/species.gd`, `terrain.gd`, `data/biomes.json`, `data/species.json` | Densidades por habitat contínuo; modelos fracos (ver §3) |
| Ecossistema/animais | `ecosystem.gd`, `wildlife.gd`, `entities/animal.gd`, `creature.gd` | Esqueleto; comportamento pobre |
| NPCs/aldeia | `entities/npc.gd`, `world/village.gd`, `structures.gd` | Cadeia de 7 passos existe; conteúdo pobre |
| Jogador | `player/player.gd`, `hands.gd`, `pixel_avatar.gd`, `interaction.gd`, `inventory.gd`, `survival.gd` | Cápsula 1,78 m + avatar **2D por frames**; sem corpo 3D nem rig |
| Itens/craft | `core/db.gd` (ITEMS/HARVEST/RECIPES) + `data/*.json` | Funcional; ícones procedurais em `ui/item_icon.gd` |
| Sons | `core/sfx.gd` | **Tudo sintetizado por código** (ver §4.5) |
| Shaders | `shaders/` (toon_terrain, stylized_water, foliage, grass shells/cards, sky…) | Estilo toon; sem texturas importadas |
| Áudio/UI/menus | `ui/hud.gd`, `menus.gd`, `prologo.gd` | Funcionais, aspeto provisório |

### 2.2 Laboratório (onde se prova tudo primeiro)

Mundo finito **400×400 m** (81×81 células de 5 m) rodeado de oceano, com
**8 estações** em `data/lab.json` (spawn, bosque 3 espécies, pedreira,
zona de escavação, clareira de construção, margem de rio, lago, praia).
Cena direta: `scenes/lab.tscn` (F5 no Godot).

- `scripts/world/lab_world.gd` — núcleo causal em miniatura:
  relevo → clima → priority-flood → D8 → rios/lagos/oceano → humidade →
  biomas → `species_density`; `sample()` único; `dig()`/`fill()` gravam
  **deltas** sobre a grelha (clamp −4..40) e recompõem água/fluxo;
  `original_height()` e `depth_dug()` sabem quanto já foi escavado;
  `material_at()` identifica **AREIA/TERRA/ROCHA** por margem, declive e
  profundidade; dureza 1–3.
- `scripts/world/lab_mesh.gd` — mesh suave por pedaços de 50 m (normais
  por gradiente, cor por bioma + **estratos expostos ao escavar**) +
  colisão côncava; **água sobre a mesma grelha do terreno, recortada
  pelo campo assinado `nível − altura`** (costa soldada, sem serrilhado);
  auditoria `winding_mismatch()`.
- `scripts/lab/lab_scene.gd` — cena jogável: `tool_dig()` com ferramentas
  **mão (r=1,5 m) / pá (r=2,3 m) / picareta (r=1,3 m)** e regras de
  material (mão não parte rocha nem terra compacta; pá inútil na rocha;
  picareta é a única na rocha); perfil de buraco em co-seno
  `0,5+0,5·cos(π·d/r)`; `reseat_props()` — objetos assentam quando o chão
  desce e **árvores sem ≥1 m de chão caem com física e viram drops da
  espécie**; relva **MultiMesh reativa** (~3 500 lâminas: some ao escavar,
  recresce em ~24 s); estação de escavação com **relíquia enterrada a
  3,2 m** descoberta por *glint* dourado na poeira (sem texto).
- `scripts/lab/lab_dev.gd` — modo deus do testador: voar (F), escavar
  (LMB), aterrar (RMB), trocar ferramenta (roda/1-2-3), partir (E),
  painel F1 com todos os itens, HUD compacto com material sob a mira.
- Ficheiros novos do Db nesta linha: itens `soil`, `sand`, `shovel`,
  `relic` (+ receita `stone_shovel` em `db.gd` **e** `data/recipes.json`
  — têm de dizer o mesmo, há teste disso).

### 2.3 Experiências WIP nesta branch (não confundir com o jogo)

- `scripts/world/voxel_generator.gd`, `wfc2d.gd`,
  `shaders/voxel_toon_terrain.gdshader`, `addons/zylann.voxel`,
  `tools/_probe_*.gd`: experiências de refatoração voxel/WFC. **Destino
  por decidir pelo dono.** Não construas em cima disto sem confirmação,
  e nunca substituas a hidrologia por WFC.
- Futuro aceite no desenho: **CavePatch** — cavernas/minas/túneis como
  patches volumétricos locais (SDF + Surface Nets/Marching Cubes) só onde
  a geologia permite (carste/fratura), com entrada/saída navegável e
  junção explícita ao heightfield. Inspiração estudada: SDF de Inigo
  Quilez (booleanos suaves), Surface Nets com anel de borda (17³),
  CodeJar/GDVoxelTerrain (chunks, LOD por anéis, custo de colisão
  orçamentado). **Nunca** o mundo inteiro em voxels.

### 2.4 Testes e ferramentas (como provar o teu trabalho)

- `tests/selftest.gd` — o jogo grande (245 verificações ok à data).
  Corre com `-- selftest`; `tests/labtest.gd` — causalidade do
  laboratório (18); `tests/labscene.gd` — laboratório 3D jogável (29).
  Entrada dos argumentos em `scripts/main.gd`. Ao adicionares uma
  `class_name` nova corre `python3 tools/gen_class_cache.py .` ou o pck
  fica sem a classe e tudo rebenta com "type not found".
- Diagnóstico visual: `tests/shot.gd` + `tools/render_shot.py`
  (rasterizador por software da geometria real, com backface culling e
  auditoria de winding); no laboratório, `tools/lab_preview.py` e
  `tools/render_lab3d.py` (este último **recusa gerar PNG se a winding
  estiver virada**).
- Ler antes de mexer: `docs/DESIGN.md`, `docs/WORLD_SYSTEMS.md`,
  `docs/GAMEPLAY_ARCHITECTURE.md`, `DECISIONS.md`, `KNOWN_ISSUES.md`,
  `docs/PRIORITY_ROADMAP.md`, `docs/MODEL_SCALE_GUIDE.md`,
  `docs/LAB_WORLD.md`, `CHECKPOINT.md`.

---

## 3. O que está MAL e porquê (a tua lista de trabalho)

### 3.1 Modelos 3D — **maus, muito maus (prioridade nº 1 do dono)**

- As árvores do mundo vêm de GLBs genéricos (kit Quaternius) gerados por
  `tools/generate_quaternius_runtime.py` para `content/models/runtime/`,
  com *fallback* procedural em `species.gd` (troncos = cilindros, copas =
  esferas achatadas). Silhuetas repetidas, copas "algodão", troncos sem
  carácter por espécie. No laboratório é pior: cilindro + esfera crus.
- O **jogador não tem corpo 3D**: é uma cápsula invisível + avatar 2D por
  frames (`content/characters/camp_to_me/`, `pixel_avatar.gd`) e mãos
  provisórias. Sem rig, sem animações direcionais (andar/saltar/golpear/
  nadar), sem leitura de estado pelas mãos.
- NPCs/animais: geometria primitiva, sem animação digna desse nome.
- Rochas: clusters genéricos (249 vértices) e, no laboratório, **caixas**.
- Estruturas/aldeia: blocos funcionais sem silhueta nem identidade.
- Pickups: ícones/itens pequenos sem presença física convincente.

**Porquê assim:** o projeto nasceu "tudo em código, sem assets importados"
(ver `DECISIONS.md`) porque não havia pipeline de Blender no sandbox.
Esse custo foi reconhecido: o dono quer modelos a sério. **A direção é
criar modelos novos** (procedurais bem construídos por código e/ou GLB
gerados por scripts em `tools/generate_*`), respeitando o
`docs/MODEL_SCALE_GUIDE.md`.

### 3.2 Texturas e materiais — quase inexistentes

- Não há texturas de superfície pintadas: o terreno é um shader toon com
  pesos por vértice (UV = relva/terra, UV2 = areia/estratos, COLOR =
  tinta do bioma + neve) e a relva usa máscaras geradas
  (`tools/make_grass_masks.py`). Resultado: superfícies lisas, leitura
  pobre de material a curta distância (não se distingue areia de terra
  de rocha pelo grão, só pela cor).
- A água tem shader próprio (`stylized_water.gdshader`, toon, dupla face)
  mas sem espuma de costa por distância assinada, sem cauticas, sem
  variação por turbidez visível de perto.

### 3.3 Física e "feel"

- **Água:** a hidrologia (D8, lagos, carve de rios, `Water.sample()` com
  nível/profundidade/corrente/turbidez) está boa e **deve ser lapidada,
  não substituída**. Falta: o jogador/itens sentirem a água (flutuação
  de pickups, salpicos, som submerso, resistência suave sem arrastar nem
  prender o jogador), maré, espuma na costa, cachoeiras finitas entre
  cotas.
- **Terra/escavação:** no laboratório já é sistema (deltas, camadas,
  ferramentas, objetos que caem). No mundo grande, **não existe ainda**:
  migrar por fatias o que o laboratório provou. Falta também erosão/
  assentamento (terra escavada não desmorona), e sombras de contacto.
- **Objetos:** troncos caídos têm física (`felled_tree.gd`), mas o
  assentamento em declives e o contacto com o jogador estão por validar
  (ver `docs/PRIORITY_ROADMAP.md` P0).
- Movimento do jogador: subidas/ravinas/saltos por afinar (P1);
  ~101 avisos `!is_inside_tree()` no arranque por limpar
  (`KNOWN_ISSUES.md` #7).

### 3.4 Sons — sintetizados, pobres

- `core/sfx.gd` gera **todos** os sons por código (ruído filtrado, tons,
  sweeps → `AudioStreamWAV`). É engenhoso, mas o resultado é pobre e
  repetitivo: não há sons por material (cavar areia ≠ terra ≠ rocha),
  passos por superfície, água (salpico/nadar/submerso com lowpass),
  vento por bioma/hora, nem camadas de ambiente.
- **Regra de ouro do som neste jogo:** o som é *feedback* (diz o que
  aconteceu sem texto), não decoração. Dureza do material deve ouvir-se.

### 3.5 LOD e desempenho — por medir e lapidar

- Faixas atuais (`MODEL_SCALE_GUIDE.md`): LOD0 <60 m, LOD1 <120 m,
  LOD2 <180 m, LOD3 = só terreno no horizonte; histerese de 8 m; só LOD0
  tem colisão/sombras; água com resolução `[24,24,16,12]` por faixa;
  relva desvanece ~50 m. Árvores GLB têm LOD1/LOD2 (~0,58/0,25 dos
  vértices). MultiMesh por chunk (~10 682 instâncias de vegetação).
- **Nunca foi medido como deve ser:** não há números de FPS/VRAM em
  Forward+ vs Compatibility/Web (P5 do roadmap). Falta: impostores/
  billboards além dos 180 m? horizonte com grelha leve já existe;
  sombras que não desaparecem; zero pop visível como critério.

### 3.6 Estrutura e processo

- Protótipo misturado com jogo: muito nasce em `_ready` por código em
  vez de cenas `.tscn` editáveis (plano: migrar gradualmente, mantendo o
  procedural como gerador). Avisos de arranque por limpar. CI do GitHub
  historicamente falhado por motivos externos — **confia nos testes
  locais headless, não no CI**.

---

## 4. Tecnologias a implementar / melhorar / lapidar (o coração do pedido)

### 4.1 Arte nova (prioridade máxima) — sprites direcionais + 3D estilizado

⚠️ **Lê primeiro a "LEITURA OBRIGATÓRIA" no topo deste documento.** Em
resumo: seres e ferramentas são **sprites billboarding 8-direções**
(desenhados, animados por ação, com variações); mundo e construções são
**3D estilizado**. Por ordem de impacto:

1. **Jogador e seres em sprites**: personagem principal desenhado (8
   direções × idle/andar/cortar/escavar/colher/atacar/magoar/dormir),
   mãos em 1ª pessoa como viewmodel 2D com **cada ferramenta desenhada**,
   e cada espécie animal/NPC/monstro/peixe/ave com o seu conjunto.
   Evoluir `pixel_avatar.gd` e o formato de frames por direção em vez de
   inventar outro sistema. Manter a cápsula de colisão (1,78 m, raio
   0,34, olhos a 1,62 m) como referência física e de escala.
2. **Árvores por espécie com silhueta própria, em 3D estilizado**
   (carvalho largo, bétula esguia e clara, pinheiro cónico alto, sakura
   torta e rosada, salgueiro pendente): tronco com afunilamento e ramos,
   copa em 2–3 massas com leitura de luz. Cada espécie liga ao seu `id`
   em `data/species.json` e aos seus materiais/colheitas em `Db.HARVEST`
   — **mudar a geometria nunca muda os ids**.
3. **Rochas por geologia, em 3D:** formas que leiam o estrato (arenito em
   camadas, granito maciço, basalto colunar…) ligadas a
   `geology.gd`/`flint_node`, em vez de um cluster genérico.
4. **Estruturas e props em 3D estilizado:** kit modular (fogueira, mesa,
   cama, cofre, fundações/paredes/telhado) com silhuetas distintas e
   encaixe legível. Paredes/tijolos/madeira são sempre 3D — nunca sprites.

**Regras de produção (obrigatórias):**
- 1 unidade = 1 metro; **não** compensar eixos à mão (Blender→Godot já
  converte). Verificar AABB contra a tabela do `MODEL_SCALE_GUIDE.md`.
- Cada modelo com **LOD1/LOD2** (~0,58 / ~0,25 dos vértices) gerados no
  mesmo pipeline; só LOD0 com colisão. Orçamentos atuais de referência:
  árvores 2,5–15k vértices na base conforme a espécie; arbustos ~2,6k;
  rochas ~250; plantas 150–700. Se propuseres orçamentos novos, mede e
  justifica.
- Materiais: toon, cor por vértice/face quando baste (o pipeline atual
  não importa texturas de diffuse para vegetação); folhagem tem de
  responder ao **vento** dos shaders `toon_foliage*.gdshader` (não
  partas esse contrato: estuda como `species.gd`/assets atuais pintam
  os dados de vento antes de propor outro).
- Pipeline: fontes em `content/models/source/`, runtime em
  `content/models/runtime/`, geradores em `tools/generate_*.py`.
  **Atenção** (`KNOWN_ISSUES.md` #14): o template web sem editor **não
  descodifica glTF** — modelos têm de funcionar também pelo fallback de
  código (`Assets` faz essa deteção). Testa os dois caminhos.
- No laboratório, os props são primitiv
...[truncated 8184 chars]os crus de propósito — o laboratório prova mecânicas, não arte final;
  não "melhores" os props do laboratório como se fossem o produto.

### 4.2 Água — física e presença (lapidar, não substituir)

O sistema atual (`water.gd` + `shaders/stylized_water.gdshader` +
recorte por campo assinado nos chunks) **está a ir na forma certa**:
hidrologia causal real, lagos por priority-flood, rios escavados,
costa soldada sem serrilhado. O teu trabalho:

- **Espuma de costa** a partir do campo assinado (distância à linha
  onde nível == altura), animada e com quebra nas margens — nunca um
  anel duro colado.
- **Flutuação**: pickups e troncos flutuam com balanço suave e derivam
  com a corrente (`sample()` já devolve direção/velocidade de fluxo);
  nada de arrastar nem prender o jogador — a água acompanha, não agarra.
- **Jogador na água**: resistência suave, salpico ao entrar/sair,
  câmara submersa com tinta e som filtrado; natação legível pelas
  mãos em sprite (braçadas).
- **Maré e hora**: nível do mar com ciclo lento ligado à lua; rios com
  caudal que responde à chuva; cachoeiras como quedas finitas entre
  cotas (com reservatório a jusante), nunca água infinita.
- **Leitura de material**: profundidade/turbidez/salinidade já existem
  em `sample()` — torna-os visíveis (cor, transparência, espuma) sem
  superfícies transparentes extra (só UMA superfície transparente no
  projeto: ver `DECISIONS.md`).
- Sentinela de "seco": `-100000` (DRY). `water_info` devolve
  `Vector2(nível, profundidade)`. Não quebres estes contratos.

### 4.3 Terra e escavação — física das camadas

O laboratório já provou (e o mundo grande ainda não tem):

- **Deltas, não destruição da base**: escavar grava `_dig_delta` sobre
  a grelha e recompõe água/fluxo; a superfície original fica consultável
  (`original_height`/`depth_dug`). Migrar este desenho para o mundo
  grande por fatias (primeiro uma área de teste, não o mapa todo).
- **Camadas com significado**: areia (margem/leito) → solo → subsolo →
  rocha a >2,3 m ou em afloramento; dureza 1–3; ferramentas com papéis
  (mão superficial, pá larga e rápida no mole, picareta curta e lenta
  na rocha). Rendimento por material: `sand`/`soil`/`stone`.
- **Desmoronamento**: o que falta — terra escavada por baixo deve poder
  colapsar por ângulo de repouso (células acima do declive estável
  deslizam), com poeira e som; árvores/objetos sem chão caem (já provado
  no laboratório com `reseat_props`).
- **Cavernas (CavePatch)**: só locais e onde a geologia permite; SDF +
  Surface Nets com anel de borda, colisão orçamentada, entrada/saída
  navegável. Marching Cubes clássico (tabela de 256 casos) é alternativa
  válida para o patch — o que reprova é voxel no mundo inteiro.
- **Perfil do furo**: queda co-seno (tangente horizontal no centro e na
  orla) — sem degraus onde a água encosta.

### 4.4 Texturas e materiais — dar grão sem esticar

- Procedural primeiro (o projeto evita assets importados): voronoi/
  ruído isotrópico em espaço de mundo para rocha; estratos horizontais
  por altitude+ruído para arenito; grão fino de areia; terra com manchas
  de humidade ligadas aos campos (a mesma humidade que decide biomas).
- Se gerares PNGs (ferramentas em `tools/`), têm de ser pequenos,
  tileable, com mipmaps, e lidos em espaço de mundo/triplanar — **nunca**
  uma textura esticada por face nem UVs que mudam por chunk (costuras).
- O terreno já traz pesos por vértice (relva/terra/areia/estratos/neve):
  estende esse contrato em vez de o substituir; a cor da relva vem do
  bioma, a lâmina só acrescenta a rampa base→ponta (ver `DECISIONS.md`).

### 4.5 Sons — feedback por material (a tecnologia atual é síntese)

Tudo é sintetizado em `scripts/core/sfx.gd` (ruído + filtros one-pole +
tons → WAV). Melhora **dentro** deste desenho (ou propõe amostras
geradas por script, nunca ficheiros descarregados sem licença clara):

- **Por material, com a mesma fonte de verdade do gameplay**:
  cavar/minerar lê `material_at`/`material_hardness` — areia (fofo,
  grave filtrado), terra (baque surdo), rocha (clac metálico + faísca
  sonora), negação (tink seco e curto). Dureza ouve-se.
- **Passos por superfície** (areia/terra/rocha/relva/madeira/água) com
  variação de pitch/ritmo para não repetir.
- **Água**: salpico por velocidade de entrada, natação, submerso com
  lowpass + bolhas raras; ambiente por bioma/hora (vento, insetos de
  dia, silêncio tenso à noite) em camadas de baixo volume.
- Pools de `AudioStreamPlayer3D/2D` já existem — reutiliza; distância e
  oclusão simples antes de quantidade de sons.

### 4.6 LOD e desempenho — medir primeiro

- Faixas: LOD0 <60 m / LOD1 <120 m / LOD2 <180 m / LOD3 horizonte (só
  terreno), histerese de 8 m, colisão e sombras só no LOD0. Sprites:
  animação completa perto, frame estático longe (ver especificação no
  topo). Relva some ~50 m e continua na cor do terreno.
- **Antes de otimizar, mede**: FPS, tempo de geração de chunk e VRAM em
  pontos fixos, em Forward+ e em Compatibility/Web, e regista no PR.
  Sem números, qualquer "otimização" é chute.
- Alvos de lapidação: zero pop visível de árvores/sprites, sombras que
  não desaparecem ao tocar no chão, mar contínuo entre chunks, e custo
  de reconstrução proporcional à área tocada (nunca a ilha inteira).

### 4.7 Relva e vegetação — derivada dos campos

- MultiMesh por chunk, densidade de `moisture/biome/slope/material/
  depth_dug` da superfície **atual** (o laboratório já faz isto —
  porta o desenho). Cavar expõe camada e a relva some; aterrar +
  tempo = recresce. Vento nos shaders de folhagem/relva existentes.
- Nada de relva verde sobre areia seca nem dentro de água; transições
  por humidade contínua, não por fronteira de bioma.

---

## 5. Método de trabalho e armadilhas (não repetir os nossos erros)

**Método:** (1) lê os docs da §2.4; (2) implementa primeiro numa
estação do laboratório; (3) prova com os testes (`-- selftest`,
`-- labtest`, `-- labscene`; nova `class_name` ⇒ `gen_class_cache.py`);
(4) gera o PNG da etapa; (5) atualiza `CHECKPOINT.md`; (6) commit +
push + **link direto do GitHub**. Pergunta ao dono quando uma decisão
for de gosto/arte — não adivinhes o gosto dele.

**Armadilhas já pagas por nós (não repetir):**

1. **Winding**: no Godot a face frontal é a de winding **HORÁRIA**; a
   convenção que funciona está em `scripts/world/chunk.gd`
   (`a,b,c / a,c,d`). Winding espelhada = face de cima descartada por
   backface culling (só se vê por baixo) — já nos custou uma etapa.
   `cull_disabled` é diagnóstico, nunca solução.
2. **Normais ≠ winding**: declarar normais "para cima" com triângulos
   virados é contradição que a auditoria de winding apanha — usa-a.
3. **Altura analítica ≠ malha**: o jogador anda sobre triângulos; testes
   de spawn/colisão medem-se contra a malha (raycast), não contra
   `height()` com tolerância apertada.
4. **Receitas em dois sítios**: `Db` e `data/recipes.json` têm de dizer
   o mesmo (há teste). Itens novos entram nos dois + locales PT/EN.
5. **GDScript**: chave duplicada em Dictionary = Parse Error; índices de
   grelha derivados de iteração precisam de tipo explícito (`: int`);
   ternário com array literal pode devolver vazio ao converter tipos.
6. **Build web**: sem `GLTFDocument` no template — todo o modelo precisa
   de caminho de código alternativo; shaders compatíveis com
   Compatibility **e** Forward+.
7. **Não faças `git checkout --` sobre edições não commitadas** nem
   `json.dumps` sobre os locales (destrói a formatação).
8. **Priority-flood, não "levantar o mínimo"**, para bacias/lagos: lago
   é `filled − base > 0,5`. Distância a água doce (`_fresh_dist`) é
   separada da distância ao oceano — não as mistures.

---

## 6. Ordem de trabalho sugerida

```text
P0  Sprites direcionais: jogador + 3 animais completos (8 dir × ações),
    mãos/viewmodel com as ferramentas por tier — provados no laboratório
P0b Árvores/rochas 3D estilizadas por espécie/geologia (LOD1/2 incluídos)
P1  Sons por material (escavar, passos, negação) com material_at
P2  Água: espuma de costa, flutuação de pickups, salpico/submerso, maré
P3  Texturas procedurais do terreno (rocha/areia/terra por campos)
P4  Medição de desempenho (Forward+ vs Web) e lapidação de LOD com números
P5  Escavação do laboratório migrada para uma área do mundo grande
P6  CavePatch SDF/Surface Nets (carste) — só depois de P5 estar sólido
```

Em cada passo: laboratório primeiro, teste a provar gameplay, PNG,
checkpoint, link. Se algo desta lista contradisser o gosto do dono em
teste real, **o teste do dono ganha** — este documento é a nossa melhor
intenção, não uma lei acima dos olhos dele.

---

## 7. Glossário rápido de ficheiros

| Quero… | Vai a… |
|---|---|
| Regras de arte/sprites | Topo deste documento + `docs/MODEL_SCALE_GUIDE.md` |
| Visão e desenho do jogo | `docs/DESIGN.md`, `docs/GAMEPLAY_ARCHITECTURE.md` |
| Arquitetura do mundo | `docs/WORLD_SYSTEMS.md`, `scripts/world/terrain.gd` |
| Laboratório (provar mecânicas) | `docs/LAB_WORLD.md`, `scenes/lab.tscn`, `scripts/lab/` |
| Itens/receitas/harvest | `scripts/core/db.gd` + `data/*.json` |
| Sons | `scripts/core/sfx.gd` |
| Água/rios/lagos | `scripts/world/water.gd`, `shaders/stylized_water.gdshader` |
| Bugs que não podem voltar | `KNOWN_ISSUES.md` |
| Decisões e porquês | `DECISIONS.md` |
| Onde parámos | `CHECKPOINT.md` (fim do ficheiro = estado mais recente) |

**Última palavra:** o dono está a jogar e a reprovar coisas em tempo
real. O teu sucesso mede-se pelo que ele vê e sente no ecrã — silhuetas
que se leem, poeira que ensina, água que se sente, sons que explicam —
e não por testes verdes sobre figuras geométricas. Não o dececiones.
