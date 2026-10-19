# BRIEFING COMPLETO — projeto BLESSED (para o agente DeepSeek Flash)

> **Lê isto até ao fim antes de tocar em código.** Este documento diz-te
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

### 4.1 Modelos 3D novos (prioridade máxima)

Criar/substituir, por esta ordem de impacto:

1. **Jogador:** corpo 3D simples mas com presença + mãos em primeira
   pessoa que comuniquem a ação (mão vazia, ferramenta, golpe, nadar).
   Manter a cápsula de colisão (1,78 m, raio 0,34, olhos a 1,62 m) como
   referência de escala. Animações podem ser procedurais (ossos por
   código/tweens) — o estilo é toon/low-poly, não realista.
2. **Árvores por espécie com silhueta própria** (carvalho largo, bétula
   esguia e clara, pinheiro cónico alto, sakura torta e rosada, salgueiro
   pendente): tronco com afunilamento e ramos, copa em 2–3 massas com
   leitura de luz. Cada espécie liga ao seu `id` em `data/species.json`
   e aos seus materiais/colheitas em `Db.HARVEST` — **mudar a geometria
   nunca muda os ids**.
3. **Rochas por geologia:** formas que leiam o estrato (arenito em
   camadas, granito maciço, basalto colunar…) ligadas a
   `geology.gd`/`flint_node`, em vez de um cluster genérico.
4. **Animais/NPCs:** corpos low-poly com locomoção básica credível
   (pernas que mexem, cabeça que orienta), dentro da cadeia de 7 passos.
5. **Estruturas e props:** kit modular (fogueira, mesa, cama, cofre,
   fundações/paredes/telhado) com silhuetas distintas e encaixe legível.

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
...[truncated 8184 chars]