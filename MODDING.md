# BLESSED — Guia de Modding

O BLESSED tem uma camada **data-driven** (`Mods`) para o tornares modificável **sem
escrever código** e sem depender de ninguém. Tudo é **aditivo**: se não houver mods,
o jogo comporta-se exatamente como antes.

## Onde colocar conteúdo

| Pasta | Importada pelo editor? | Aceita `.glb` (Blender)? | Uso |
|---|---|---|---|
| `res://content/<nome_do_mod>/` | **Sim** | **Sim** | Conteúdo do projeto (o principal) |
| `user://mods/<nome_do_mod>/` | Não | Não (só JSON) | Tweaks rápidos em JSON |

Cada mod é uma **pasta** com um ficheiro **`mod.json`** dentro.

## Formato do `mod.json`

```json
{
  "name": "O Meu Mod",
  "items": {
    "meu_item": { "kind": "resource", "stack": 20, "icon": "stone", "name": "Meu Item" }
  },
  "recipes": [
    { "id": "minha_receita", "result": "meu_item", "qty": 1,
      "needs": { "wood": 2, "stone": 1 }, "station": "" }
  ],
  "props": {
    "meu_objeto": { "mesh": "modelo.glb", "scale": 1.0 }
  }
}
```

### `items`
Cada chave é o **id** do item. Campos:
- `kind`: `"resource"`, `"food"`, `"tool"`, etc.
- `stack`: quantidade máxima por slot.
- `icon`: nome do ícone existente (ou de um que adds).
- `name`: nome mostrado no jogo (tem prioridade sobre as traduções).

Podes **criar itens novos** ou **fazer override** de existentes (usa o mesmo id,
ex.: `"wood": { "stack": 99 }` muda a pilha da madeira).

### `recipes`
- `id`: identificador único.
- `result`: id do item produzido.
- `qty`: quantos produz.
- `needs`: `{ "id_item": quantidade }`.
- `station`: `""` (em qualquer lugar) ou o id de uma estação (ex.: `"campfire"`).

### `props` (objetos/cenários do Blender)
- `mesh`: caminho do `.glb`/`.gltf` **relativo à pasta do mod**.
- `scale`: escala.

## Editar o mundo sem código (100% data-driven)

Tudo o que afina o mundo está em **`data/*.json`** — edita estes ficheiros e o jogo
muda, **sem tocar em GDScript**. Se um ficheiro faltar ou for inválido, o jogo usa os
valores embutidos no código (não parte nada).

| Ficheiro | O que controla |
|---|---|
| `data/biomes.json` | Os 12 biomas: cor (RGB 0–1), nome, densidade de relva e de árvores. |
| `data/terrain.json` | O gerador: ruídos, spline continental, picos, rio, snowline. |
| `data/quality.json` | Os 3 perfis gráficos: toggles (ssao/nevoeiro/ssr/dof) e valores. |
| `data/species.json` | Árvores/rochas/plantas: biomas (por **id**), peso, colheita, escala, balanço. |

Exemplo — floresta mais verde e densa (edita a entrada `"forest"` em `data/biomes.json`):

```json
{ "id": "forest", "color": [0.10, 0.45, 0.30], "tree_density": 4.0 }
```

### Override via mod (sem alterar o jogo base)

Em vez de editares o `data/`, um **mod** pode fazer override. No `mod.json`:

```json
{
  "name": "O Meu Mundo",
  "biomes":  { "forest": { "color": [0.10, 0.45, 0.30], "tree_density": 4.0 } },
  "terrain": { "peak_height": 320.0 },
  "species": { "trees": { "oak": { "weight": 2.0, "biomes": ["meadow", "forest", "grove"] } } },
  "quality": { "values": { "fog_density": 0.03 } }
}
```

- `biomes`: por **id**; cada campo substitui apenas esse campo.
- `terrain`: chaves de topo (ex.: `peak_height`, `sea_level`, `snowline_base`).
- `species`: `trees`/`rocks`/`plants` → id → campos (`weight`, `harvest`, `scale`,
  `height`, `wind`, `biomes` por **id**).
- `quality`: `values` (números) e `presets` (toggles ssao/nevoeiro/ssr/dof).

Os biomas são referidos **pelo id** (`"forest"`, `"snow"`…) em `species.json` e nos
mods — nunca por número. A ordem/índice dos biomas é estrutural (o shader usa-a) e
mantém-se fixa; o que é editável são as cores, densidades e afinações.

## Usar modelos do Blender

1. No Blender, exporta como **glTF 2.0 (`.glb`)**.
2. Coloca o `.glb` dentro da pasta do mod: `content/<mod>/modelo.glb`.
3. O Godot **importa automaticamente** tudo o que está em `res://content/`.
4. Referencia-o no `mod.json` (em `props`, ou como mesh de uma estrutura).

## Verificar se carregou

Na consola de saída do Godot aparece:
```
[Mods] 1 mod(s): O Meu Mod | items=2 recipes=1 props=0
```

## Para modding mais fundo (código)

Os sistemas que podes estender estão em:
- `scripts/core/db.gd` — itens, receitas, colheitas, objetivos.
- `scripts/world/species.gd` — espécies de árvores/rochas/plantas/estruturas.
- `scripts/world/structures.gd` — colocação e comportamento de estruturas.
- `scripts/world/village.gd` — geração da aldeia (a substituir por ruínas).
- `scripts/core/mods.gd` — o carregador de mods (podes acrescentar novos tipos aqui).

O `Mods` já faz override de **itens** e **receitas**. Para ligar **props/estruturas
data-driven** ao mundo, o ponto de entrada é `structures.gd`/`village.gd` — diz o que
queres e eu ligo, ou segue o padrão: ler de `Mods.prop(id)` e instanciar o `.glb`.

## Regras

- O sistema é **aditivo**: um mod partido não deve impedir o jogo de arrancar
  (o `Mods` ignora `mod.json` inválidos e avisa).
- Mantém os ids únicos para não colidir com o conteúdo base.
- `.glb` só funcionam em `res://content/` (importados pelo editor).

---

## Editar no Godot (Inspector) — sem GDScript e sem JSON

Para quem prefere o editor, há **Recursos (`.tres`)** com campos `@export` que se
criam e editam visualmente no **Inspector**. É o caminho mais fácil.

### Criar um item/receita/objeto no editor
1. No painel **FileSystem**, entra em `content/` (ou cria `content/o_meu_mod/`).
2. Botão direito → **New Resource…**.
3. Escolhe **ItemDef**, **RecipeDef** ou **PropDef**.
4. Preenche os campos no **Inspector** e guarda como `.tres` dentro de `content/`.

O `Mods` carrega automaticamente qualquer `.tres` destes tipos que esteja em
`res://content/` (raiz ou subpastas).

### Campos (visíveis no Inspector)
- **ItemDef**: `id`, `kind`, `stack`, `icon`, `display_name`.
- **RecipeDef**: `id`, `result`, `qty`, `needs` (dicionário id→quantidade), `station`.
- **PropDef**: `id`, `mesh` (**arrasta aqui o `.glb` do Blender**), `scale`.

### Objetos do Blender sem código
1. Exporta do Blender como `.glb` para `content/<mod>/`.
2. Cria um **PropDef** e **arrasta o `.glb` para o campo `mesh`** no Inspector.
3. Pronto — fica registado em `Mods.prop(id)` (a instanciação no mundo é o passo
   seguinte, em `structures.gd`).

### JSON vs `.tres`
- **`.tres` (Inspector)**: mais fácil, sem texto, ideal para quem usa o editor.
- **`mod.json`**: melhor para versionamento/edição em massa e para `user://mods/`.
- Podes usar os dois; o `Mods` carrega ambos.
