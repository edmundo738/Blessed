# BLESSED

Sandbox de sobrevivência em primeira pessoa, com mundo procedural, estilo anime cinemático.

> *Viveste muitas vidas. Um dia adormeceste. E acordaste abençoado — num mundo que não
> conheces. Podes fazer tudo. Mas tem cuidado com o escuro.*

---

## Jogar agora

```bash
./tools/setup_engine.sh        # uma vez: descarrega o template web do Godot 4.7.2
python3 tools/build_web.py     # empacota o jogo em export/web/
python3 tools/serve_web.py     # serve em http://0.0.0.0:8080
```

Abre `http://localhost:8080`, clica no ecrã e o rato é capturado.

| Tecla | Acção |
|---|---|
| `W A S D` | andar |
| `Shift` | correr · `Espaço` saltar · `Ctrl` agachar |
| rato | olhar · botão esquerdo **manter premido** para cortar / picar / colher |
| `F` | interagir (falar, acender, dormir) |
| `B` | modo construir · `R` rodar · roda do rato escolher peça |
| `Tab` | mochila · `J` diário · `M` mapa · `Esc` pausa |
| `1…9` | barra de atalhos · `G` largar item · `F5` guardar |
| `F1` | cena de diagnóstico (geometria conhecida, materiais básicos) |
| `F9` | materiais do jogo ↔ `StandardMaterial3D` — isola shaders vs. geometria |
| `F3`/`F6`/`F7`/`F8` | água · céu · sombras · meio-dia |

O prólogo abre o jogo: escolhes o **nome**, o **corpo** (Ela/Ele) e uma **alma** — o que te
ficou da vida anterior. Não é cosmético: cada alma muda números reais, medidos e testados
(tabela em [`docs/DESIGN.md`](docs/DESIGN.md) §6). Depois a câmara desce do céu sobre a
aldeia e entrega-te o controlo.

---

## Verificar

O projeto tem o seu próprio teste — é o que corre antes de se dizer que algo funciona:

```bash
cd /home/user/Blessed && ./tools/check.sh
```

Último resultado: **58 ok, 0 falhas** (`SELFTEST_PASS`).

Há duas sondas, ambas a correr o jogo a sério dentro do motor:

```bash
./tools/check.sh                                              # 53 verificações, PASS/FAIL
godot --headless --path . --quit-after 3000 -- diag           # números, não opiniões
```

O `tests/diag.gd` imprime o que o ecrã mostra sem olhar para o ecrã: a direção
que cada tecla produz comparada com a esperada, o winding e as normais de cada
malha, as cores de vértice por espécie, a posição do sol e o spawn. Foi assim
que se encontraram os quatro bugs de renderização — nenhum deles dava erro.

O que o `tests/selftest.gd` cobre:

- geração do mundo: altura do terreno, 49 chunks, 4 810 nós colhíveis, 10 379 instâncias de
  vegetação, 7 biomas
- inventário: soma, remoção, recusa sem stock, limite de 24 ranhuras
- crafting: tocha produzida, e **recusado** sem materiais (não devolve `ok` a fingir)
- construção: estrutura colocada, contagem antes/depois, e recusa quando não há material
- colheita: cortar uma árvore dá madeira e marca o nó como morto
- sobrevivência: comer, beber, dano, abrandamento por fome
- noite: fase detetada, luz a zero, criatura gerada; dia: luz a 0.89
- NPC: cadeia canónica completa, confiança sobe ao falar, ≥3 tópicos, resposta certa
- i18n: PT e EN diferentes, formatação com parâmetros
- os materiais opacos não escrevem `ALPHA` (escrever `ALPHA` num shader espacial
  põe o material no passe transparente — foi isso que fez as casas parecerem
  um raio X)
- a vista de depuração troca de materiais nos dois sentidos e constrói a cena
  de diagnóstico
- comandos: comando inexistente recusado
- save/load: round-trip de inventário e hora
- geometria do terreno: o chão com as faces para cima, a saia com as faces para
  fora e — regressão real que isto apanhou — a saia a usar os seus próprios
  vértices em vez dos do canto do chunk
- mapa de entrada: as 22 acções existem e têm teclas (o `[input]` é vazio de propósito —
  `Game._ready()` constrói-o em runtime, por isso isto tinha de ser verificado)
- os 4 traços do prólogo alteram mesmo números: alcance 4.20 → 5.67 m, trabalho ×1.45,
  medo 0.500 → 0.300, valência social 0.644 → 0.764

---

## Como está feito

Forward+ no desktop, `gl_compatibility` na web. **Zero assets importados** — cada malha,
material, textura e som é gerado em runtime, por isso o `.pck` tem 244 KB e o pipeline de
exportação não precisa do editor.

```
project.godot            autoloads + Forward+
scenes/main.tscn         um nó vazio: o mundo é todo construído em código
scripts/
  main.gd                bootstrap: liga tudo na ordem certa
  core/    946 linhas    Bus (sinais), Loc (PT/EN), Db (itens/receitas), Sfx (PCM), Game
                         (relógio, definições, memória, save, registo de comandos)
  world/  2024 linhas    Terrain (noise + biomas), MeshKit, SpeciesKit, Materials,
                         Chunk (LOD + colisão), World (streaming, sol, água, céu),
                         Structures, Village, Fx
  player/ 1247 linhas    Player (CharacterBody3D), Hands, Survival, Inventory, Interaction
  entities/ 639 linhas   Npc, Creature, NightDirector
  ui/     1046 linhas    Hud, Menus, Prologo
shaders/   297 linhas    céu anime, água estilizada, folhagem e terreno toon
locale/    358 linhas    pt.json / en.json
tests/     246 linhas    selftest.gd
tools/     443 linhas    build/verificação/empacotamento
```

### A regra que manda em tudo

Nenhuma acção acontece por magia. Cada comando passa pela mesma corrente:

```
PERCEPÇÃO → INTERPRETAÇÃO → INTENÇÃO → DECISÃO → MANIFESTAÇÃO → CONSEQUÊNCIA → MEMÓRIA
CONTRACT  →     OWNER     →  INPUT   → DECISION →    ACTION    →   RESULT    →  MEMORY
```

Tecnicamente: `Game.request(id, args)` é a **única** porta de entrada. Cada comando devolve
um resultado observado, e um comando que não fez nada **tem** de devolver `failed: true` —
`ok` nunca é assumido. É isto que o self-test verifica com "craft sem materiais é recusado".

### Prioridades

Quando duas coisas boas colidem, ganha a que está mais à esquerda:

**Compatibilidade > Estabilidade > Coerência > Imersão > Qualidade narrativa >
Integração > Profundidade > Variedade > Quantidade**

E o princípio LEGO: poucas peças boas + regras de combinação + contexto real + memória +
personalidade. Não é quantidade de conteúdo, é quantidade de coisas que se combinam.

Detalhe de desenho, decisões de âmbito e o que vem a seguir: **[`docs/DESIGN.md`](docs/DESIGN.md)**.

---

## O mundo

O terreno é uma soma de ruídos: continente, colinas, detalhe, vales de rio e um caminho
sinuoso que liga tudo. Sobre isso, 7 biomas por altitude, humidade e temperatura — areia,
prado, bosque, floresta, rocha, neve, pântano.

Cada chunk de 48 m tem 3 níveis de detalhe, só o mais próximo ganha colisão, e a vegetação
vai para `MultiMeshInstance3D`. Árvores, rochas e ervas são colhíveis: cada uma é um nó com
vida própria que desaparece quando o cortas.

Tudo determinístico a partir da semente (`20260109`): a mesma semente dá sempre o mesmo mundo.
