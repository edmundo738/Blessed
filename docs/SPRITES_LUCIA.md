# Sprites da Lúcia — 8-Way / Multi-directional Billboarding (HD-2D)

**Personagem:** Lúcia Luckombo, 100% baseada nas imagens do dono — a
**menina afro normal** (tank top preto, cargo verde-azeitona, botas,
box braids longas, argolas douradas, colar de cruz), não a versão deusa.
Estilo: pixel art moderno (clusters limpos, silhueta legível) com
tempero PSX quente e identidade de Angola. Seres = sprites 2D em
billboarding direcional; o resto do mundo = 3D estilizado.

## Estado honesto

- `content/characters/lucia/sprites_v2/` — **biblioteca de poses nas 8
  direções** (S, SE, E, NE, N, NW, W, SW), separada por grupos:
  `01 idle/walk`, `02 run/jump`, `03 combate e reações (comb1/2/3,
  dano, medo, defesa)`, `04 swim/fast/deep`, `05 vida (sit, sleep,
  coleta, drag, drop, carry)`. Versões `_clean` já com fundo removido
  (chroma magenta → transparente).
- `sprites/` (v1) ficou **errada** (direções misturadas na mesma linha):
  arquivada como rascunho, não usar.
- **Falta o passo de Pixelorama** (`C:\Users\edmun\Downloads\Pixelorama`):
  recortar cada pose da v2 e montar a folha final uniforme —
  8 linhas (direções, ordem fixa S→SW) × frames do grupo, alinhada
  pelos pés. O gerador não cospe grelhas de motor perfeitas; a v2 dá
  as poses certas e consistentes para esse recorte.

## Organização (manifesto)

`content/characters/lucia/lucia_sprites.json` define grupos, frames,
fps, transições e a regra de direção. Resumo das transições:
idle↔walk por velocidade (com histerese), jump por `vy`, combo
1→2→3 por janela de 0,25 s, swim por profundidade, dano/medo como
overrides. Frames inteligentes: o frame de salto escolhe-se pela
velocidade vertical, o ciclo de walk acelera com a velocidade real
(pés não deslizam), coleta/drop são pares inversos.

## Direção (matemática)

Setor = ângulo entre o **vetor entidade→câmara** e o facing da
entidade, quantizado em 8 setores de 45°, com **histerese de 6°** na
fronteira para não piscar entre diagonais. Em 1ª pessoa o sprite é o
corpo (3ª pessoa/outros jogadores); as mãos e ferramentas vivem no
viewmodel próprio, sincronizado com a ação (bob/sway/impacto).

## Integração HD2D (decisão do dono, 2026-10-19)

A branch `agent/hd2d-art-pass` é a **base superior** do projeto. O seu
conteúdo entrou na branch de trabalho (player/corpo/mãos, animais,
mundo, sons com vozes limitadas, testes novos: selftest 250) e por
cima ficou o que ela não tinha: **construção inteligente do
laboratório** (snap/fundação/estabilidade/colapso + porta/janela/
escadas/telhado), briefing e pack. Do lab dela vieram ainda a malha
com pesos de material e `footstep_material_at` (passos por material).
