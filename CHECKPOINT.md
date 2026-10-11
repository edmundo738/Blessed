# CHECKPOINT — estado atual do projeto

> Este ficheiro é a memória do projeto. Qualquer IA (ou humano) que abra o
> repositório começa por lê-lo. Atualiza-se no fim de cada marco.
> Último update: commit `34d0480` + correções de API (ver KNOWN_ISSUES).

## O que é
Sandbox de sobrevivência first-person, estilizado "anime", em Godot 4.7.2.
Fatia vertical jogável: mundo procedural (chunks), dia/noite, NPCs, colheita,
crafting, construção, sobrevivência, prólogo com criação de personagem,
PT/EN, save/load. Tudo construído em GDScript (não há assets importados).

## Como corre
- **Preview web (Arena):** `tools/serve_web.py` + `export/web/blessed.pck`.
  Renderer web = `gl_compatibility` (definido em `project.godot`).
- **Local (máquina do dono):** abrir `project.godot` no Godot 4.7.2 e F5.
  O renderer local por omissão é Forward+; o web é Compatibility.
- **Testes do projeto:** `./tools/check.sh` (selftest headless, 60 checks).
- **Auditoria de erros:** correr o selftest e ler TODAS as linhas `ERROR:` —
  foi assim que se apanharam os bugs de API Godot-3 (ver KNOWN_ISSUES #1-#5).

## Estado por sistema (OBSERVED = medido, não opinado)
| Sistema            | Estado   | Prova |
|--------------------|----------|-------|
| Mundo/chunks       | OK       | selftest + rasterizador (`docs/shots/`) |
| Controlos          | OK       | selftest (tabela de teclas) |
| Água               | semi-transparente, sem depth-texture | selftest + shader |
| Céu/sombra/LOD     | OK       | rasterizador |
| Relva/árvores      | corrigido p/ Godot oficial (API `set_instance_*`) | NOT TESTED no sandbox (wasm não devolve readback de instâncias) |
| NPC                | tem material; `int(Vector3)` corrigido | selftest |
| Prólogo            | primeira frase agora escrita | selftest |

## Próximo marco (por ordem)
1. Perseguir os 101 avisos `!is_inside_tree()` (não fatais) até Output limpo.
2. Reestruturação editável: cenas `.tscn` reais + nós visíveis no editor
   (Camera3D, DirectionalLight3D, WorldEnvironment, Player, World) e dados em
   `.tres` com `@export` — ver DECISIONS.md.
3. Build Windows testada fora do editor (requer máquina com Godot; o sandbox
   não produz `.exe`).
