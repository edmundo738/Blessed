# CURRENT_ARCHITECTURE — o que existe hoje (medido, 2026-10-18)

> Etapa 0 da reconstrução. Isto é um mapa do protótipo atual, não uma defesa dele.
> Regra da casa: código existir não prova que a arquitetura esteja certa.

## Inventário

- 41 ficheiros GDScript, ~11 700 linhas. Maiores: `chunk.gd` 769, `hud.gd` 717,
  `interaction.gd` 589, `world.gd` 518, `terrain.gd` 508, `player.gd` 499.
- Autoloads: `Bus`, `Loc`, `Mods`, `Db`, `Sfx`, `Game` (ver `project.godot`).
- Dados editáveis: `data/terrain.json`, `data/biomes.json`, `data/species.json`,
  `data/quality.json`; itens/receitas em `scripts/core/db.gd` + `content/`.

## Quem é dono de quê (hoje)

| Área | Dono atual | Problema estrutural |
|---|---|---|
| Altura, clima, biomas, rio, costa, aldeia, caminho | `Terrain` (uma só classe, 17 ruídos) | Autoridade única para tudo: qualquer mudança mexe em tudo. Não há modelo de dados do mundo — só funções de ruído. |
| Água | `Terrain.water_info()` + `chunk._build_water()` + shader | A água é **derivada da altura por um rio-seno e uma costa-seno** (`_river_center`, `_coastline`). Não há bacia, fluxo nem nascente: o rio não nasce em lado nenhum, logo não pode descer, alagar ou secar. |
| Oceano/ilhas | `height()` mistura leito do mar por cima do relevo | O mar é um `lerp` tardio sobre o terreno. A ilha não "está no oceano": o oceano é pintado onde a função manda. Daí cones e elevações sólidas sem causa. |
| Biomas | `biome_weights_s()` classifica a partir de altura/declive/clima | Biome = cor + densidade. Não tem morfologia própria (floresta não muda a forma do chão), nem comportamento. |
| Vegetação | `chunk._scatter()` sorteia por célula com `rng` | Scatter puro: sem manchas de floresta, sem idades, sem afinidades. "Árvore chama árvore" não existe — cada célula decide sozinha. Daí repetição e variação sem lógica. |
| Árvore abatida | `world.fell_tree()` / `felled_tree.gd` | Regrediu: o tronco caído não herda a mesh/espécie da árvore original. |
| Construção | `structures.gd::place()` coloca prefabs | Sem sockets, sem preview com snap a sério, sem suporte/fundação. Colocar é "instanciar na posição", não construir. |
| Escavação | **não existe** | Há `pickaxe` para nós de pedra, mas o chão não se escava. Com voxel isto tem de ser testável. |
| Save | `Game` + `save_data()` por sistema | Guarda deltas de colheita/estruturas; não há versão de ruleset do mundo. |

## O que se aproveita (não apagar)

- Loop de sobrevivência/crafting/NPC/save e a tabela de itens/receitas (`Db`).
- `Bus` (eventos), `Mods` (conteúdo data-driven), localização PT/EN.
- Pipeline de chunks/LOD/MultiMesh e o rasterizador de diagnóstico (`tests/shot.gd`).
- A regra de descoberta por efeito (nunca por texto) — é de design, não de código.

## Veredito

O protótipo prova que o loop joga; não prova que o mundo exista. Terreno, água,
bioma e vegetação são quatro leituras independentes dos mesmos ruídos, por isso
nada se explica mutuamente: montanha não explica rio, rio não explica floresta.
A reconstrução troca "funções que desenham" por um **modelo de dados causal**
ver `docs/LAB_WORLD.md` — primeiro num laboratório finito de 400×400 m.
