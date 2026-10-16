# BLESSED — Reestruturação `.tscn`

Objetivo: mover o que faz sentido de **código** para **cenas editáveis no Godot**,
para poderes mexer no editor sem depender de GDScript (nem de mim).

Princípio: **sempre aditivo**. O código procedural continua como *fallback*; uma
cena `.tscn` só é usada quando existe. Nada parte.

## Estado

| Sistema | Estado | Onde |
|---|---|---|
| **Sistemas do jogo** (World, Player, Structures, Village, Fx, Hud) | ✅ cada um é uma **cena `.tscn`** instanciada com fallback | `scenes/*.tscn` → `main.gd::_sys` |
| **Estruturas** (house, campfire, …) | ✅ prefab `.tscn` com fallback | `scenes/structures/<id>.tscn` → `structures.gd::_spawn` |
| Itens / receitas / props | ✅ data-driven (`.tres`/JSON) | `content/` → `Mods` (ver `MODDING.md`) |
| Ambiente / iluminação | ⏳ a mover para cena | (próximo) `scenes/environment.tscn` |
| Céu / água | ⏳ a mover para cena | (próximo) |
| Aldeia → **ruínas** | ⏳ prefabs + conteúdo | (próximo) |

## Progresso: nodes já movidos para cenas
- **`world.tscn`** tem agora os nós **`Sun`** (DirectionalLight3D) e **`WorldEnvironment`**.
  O `world.gd` usa-os da cena se existirem (senão cria-os — igual a antes). Podes
  selecioná-los e afinar sombras/ambiente no Inspector.
  >Nota: a COR/ENERGIA do sol e o nevoeiro/cor do ambiente são animados pelo código
  > (ciclo dia/noite + perfil de qualidade), por isso esses valores específicos são
  >  controlados em runtime; o que editas na cena é a configuração estática (sombras, etc.).

## Já funciona: o jogo é scene-based (com fallback)
O `main.gd` agora instancia **cenas** em vez de só `.new()`:
`scenes/world.tscn`, `player.tscn`, `structures.tscn`, `village.tscn`, `fx.tscn`,
`hud.tscn`. Cada uma tem o nó raiz + o script. O helper `_sys(cena, fallback)`
usa a cena se ela existir/carregar; senão, cai no código (não parte nada).

**O que isto te dá:** podes abrir cada `.tscn` no editor e **acrescentar/editar
nós** (luzes, meshes, partículas, a tua geometria). O próximo nível é ir movendo
para dentro das cenas o que o código ainda constrói em `_ready()` (ambiente, sol,
água, câmara, etc.), sistema a sistema — é isso que torna "tudo em nodes".

>Nota: por enquanto as cenas têm só o nó raiz; o resto ainda é construído em
> código no `_ready()`. Abre a cena, arrasta os nós que quiseres controlar — e
> diz-me quais para eu remover a construção procedural correspondente.

## Já funciona: estruturas editáveis
1. Vê o **id** da estrutura em `scripts/world/species.gd`.
2. Cria `scenes/structures/<id>.tscn` no editor (raiz = `Node3D`).
3. Edita visualmente (meshes, materiais, `.glb` do Blender, colisões, luzes).
4. O jogo usa a tua cena; sem ela, usa o procedural.
- Template: `scenes/structures/_exemplo_ruin_column.tscn`.

## Próximos passos (ordem sugerida)
1. **`scenes/environment.tscn`** — `WorldEnvironment` + `DirectionalLight3D` (sol)
   com os valores atuais, para ajustares luz/exposição/nevoeiro/DoF no Inspector.
   O `world.gd` passa a `load()`-a se existir (senão, constrói como agora).
2. **`scenes/sky.tscn` / `scenes/water.tscn`** — domo de céu e plano de água como
   cenas, com os shaders atribuídos e parâmetros expostos.
3. **Aldeia → ruínas**: definir as ruínas como prefabs (`.tscn` + `.glb`) e
   dados (`Props`/estruturas), substituindo as casas procedurais.
4. **Prefabs de vegetação/rochas** editáveis, se quiseres controlar o aspeto.

## Regras
- O nó raiz de um prefab de estrutura deve ser `Node3D` (o jogo posiciona/roda).
- Mantém o procedural como fallback até cada cena estar validada no teu Godot.
- `.glb` do Blender vão em `content/` ou dentro de `scenes/` (o editor importa).
- Nada disto é testável no sandbox (sem motor) — valida sempre no teu Godot.
