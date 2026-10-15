# Blessed — guia de escala e LOD

Usa este ficheiro antes de criar ou importar modelos novos. A unidade do Blender
e do Godot é **1 unidade = 1 metro**. O exportador converte o eixo vertical do
Blender para o eixo Y do Godot; não compenses essa conversão escalando o modelo
à mão no jogo.

## Referência do jogador

| Medida | Valor | Origem |
|---|---:|---|
| Cápsula de colisão, altura | 1,78 m | `scripts/player/player.gd` |
| Cápsula, raio | 0,34 m | `scripts/player/player.gd` |
| Altura dos olhos | 1,62 m | `scripts/player/player.gd` |
| Olhos agachado | 1,05 m | `scripts/player/player.gd` |

O jogador atual usa uma cápsula 3D e um avatar 2D opcional. Ainda não existe um
rig humano 3D aprovado para substituir essa escala; os assets abaixo usam a
cápsula como referência de leitura.

## Vegetação aprovada no Godot

Alturas abaixo são os AABBs dos meshes importados, medidos pelo self-test em
Godot 4.7.2. As variações de escala pequenas são controladas por `data/species.json`.

| ID no jogo | Espécie de origem | Altura | Vértices base | LOD1 / LOD2 |
|---|---|---:|---:|---:|
| `tree_oak` | CommonTree 1 | 6,80 m | 10 331 | 7 343 / 3 520 |
| `tree_birch` | CommonTree 2 | 7,10 m | 8 959 | 6 497 / 3 154 |
| `tree_pine` | Pine 5 | 8,40 m | 2 504 | 1 991 / 915 |
| `tree_sakura` | TwistedTree 1 | 5,80 m | 15 511 | 11 276 / 5 457 |
| `tree_willow` | CommonTree 3 | 7,40 m | 6 086 | 4 216 / 1 924 |
| `plant_bush` | Bush Common with Flowers | 0,95 m | 2 618 | 1 647 / 789 |
| `plant_mushroom` | Mushroom Common | 0,50 m | 555 | 351 / 192 |
| `rock_cluster` | Medium Rock 2 | 1,23 m | 249 | 164 / 86 |
| `grass_clump` | Common Grass Short | 0,68 m | 153 | — |
| `fern_clump` | Fern 1 | 0,40 m | 243 | — |
| `flower_clump` | Flower Group 3 | 0,72 m | 590 | — |
| `clover_clump` | Clover 1 | 0,40 m | 267 | — |
| `reed_clump` | Wispy Tall Grass | 1,12 m | 666 | — |

O modelo de arbusto com bagas permanece apenas como asset-fonte legado e já não é
instanciado no jogo. Cogumelos, fetos, rochas e cada árvore continuam em ficheiros
e grupos próprios.
O verdete pintado da rocha foi neutralizado; não há uma planta misturada dentro
da malha da pedra.

## Como os LODs entram no mundo

- Árvores, arbustos, cogumelos e rochas têm mesh base, LOD1 e LOD2.
- O gerador tenta os rácios de simplificação `0,58` e `0,25`; a tabela contém a
  contagem final real de vértices após exportação/importação.
- O mundo usa quatro faixas por distância: `lod 0` até 60 m, `lod 1` até 120 m,
  `lod 2` até 180 m e `lod 3` no horizonte. Uma histerese de 8 m evita alternância
  visível; o quarto nível só desenha terreno com uma grelha mais leve.
- Só `lod 0` recebe colisões e sombras detalhadas. A relva diminui com a distância;
  as algas ficam no anel mais próximo, debaixo de água rasa.
- Cada `MultiMeshInstance3D` pertence a um chunk, para o motor poder ocultar
  grupos inteiros. O self-test mediu 10 682 instâncias de vegetação no arranque.

## Qualidade e custo

As três panorâmicas do céu foram reduzidas de 4096×2048 para 2048×1024 com
Lanczos, com mipmaps ligados. A 1600×900, isto conserva mais de um texel por
pixel de ecrã. RGBA8 sem compressão ocuparia aproximadamente 24 MiB na base e
32 MiB com a cadeia de mipmaps; são estimativas, não uma leitura de memória da
GPU. O passe móvel de nuvens corre a um quarto da resolução do fundo.

Ainda falta medir FPS e uso real de VRAM em Forward+ e no Compatibility/Web. Não
reduzas os meshes próximos nem voltes as panorâmicas a 4K até haver uma captura
e uma medição que mostrem uma necessidade concreta.
