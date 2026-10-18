# CURRENT_DEPENDENCIES — quem chama quem (Etapa 0)

## Fluxo principal

```text
main.gd
 ├─ World (world.gd)
 │   ├─ Terrain (altura/bioma/água — autoridade de facto de tudo)
 │   ├─ SpeciesKit (meshes/densidades por bioma)
 │   ├─ Materials (shaders)
 │   └─ Chunk (mesh do chão + água + scatter + colhíveis)
 ├─ Structures (place/remove de prefabs, sem sockets/suporte)
 ├─ Village (usa Terrain.village_* e Structures)
 ├─ Player / Survival / Inventory / Interaction
 └─ Hud / Menus / Prologo
```

## Dependências problemáticas

1. **Chunk depende de Terrain para tudo** (altura, bioma, água, relva) e de
   SpeciesKit para scatter. Chunk é renderização + população + gameplay
   (colhíveis) ao mesmo tempo.
2. **Terrain não conhece nenhum sistema, mas todos o consultam** — é um deus
   de funções puras: não guarda bacia, rio, solo nem histórico. Perguntas como
   "a que rio pertence este ponto?" ou "o que acontece se eu cavar aqui?" não
   têm resposta possível nesta API.
3. **Água não tem autoridade própria**: `water_info()` recalcula rio/costa a
   partir de senos a cada vértice. Mudar o terreno não muda a água por sistema,
   só por coincidência aritmética.
4. **Bioma→vegetação é uma tabela de densidades** (`biomes.json`): não há
   campos ambientais (humidade do solo, distância à água, sombra) a filtrar
   espécies — há sorteio por célula.
5. **Estruturas não consultam terreno** (fundação/declive/água): colocam-se
   onde o raycast acerta.

## Ciclos e fugas

- Sem ciclos duros de classes, mas com um ciclo lógico:
  `height()` mistura rio/costa/caminho/aldeia → `water_info()` chama
  `height()` → `chunk` chama ambos por vértice (custo e costuras).
- `Db` e `Mods` sobrepõem-se: receitas/itens vivem em código e em `content/`.

## Direção (reconstrução)

```text
LabWorld (dados: grelha de campos causais)  ← autoridade do mundo de teste
   ▲ consulta          ▲ consulta           ▲ consulta
Render (mesh)      Gameplay (colher/     Save (seed + deltas
                   cavar/construir)      de escavação/construção)
```

Uma autoridade de dados, vários leitores. Nenhum leitor inventa mundo.
