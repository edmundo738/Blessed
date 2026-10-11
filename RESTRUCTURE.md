# BLESSED — Reestruturação `.tscn`

Objetivo: mover o que faz sentido de **código** para **cenas editáveis no Godot**,
para poderes mexer no editor sem depender de GDScript (nem de mim).

Princípio: **sempre aditivo**. O código procedural continua como *fallback*; uma
cena `.tscn` só é usada quando existe. Nada parte.

## Estado

| Sistema | Estado | Onde |
|---|---|---|
| **Estruturas** (house, campfire, …) | ✅ prefab `.tscn` com fallback | `scenes/structures/<id>.tscn` → `structures.gd::_spawn` |
| Itens / receitas / props | ✅ data-driven (`.tres`/JSON) | `content/` → `Mods` (ver `MODDING.md`) |
| Ambiente / iluminação | ⏳ a mover para cena | (próximo) `scenes/environment.tscn` |
| Céu / água | ⏳ a mover para cena | (próximo) |
| Aldeia → **ruínas** | ⏳ prefabs + conteúdo | (próximo) |

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
