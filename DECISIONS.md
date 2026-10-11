# DECISIONS — o que escolhemos e porquê

- **Tudo em GDScript, sem assets importados.** Motivo original: o sandbox não
  tem Blender nem pipeline de import, e o preview web precisa de tudo em código.
  _Custo reconhecido:_ o editor mostra pouco; o dono quer editar nós reais.
  _Plano:_ migrar gradualmente para cenas `.tscn` + `.tres` + `@export` (marco 2
  do CHECKPOINT), mantendo o procedural como gerador, não como única verdade.
- **Renderer web = `gl_compatibility`; local = Forward+.** Motivo: o web export
  do Godot 4 só oferece Compatibility. _Consequência:_ shaders têm de ser
  compatíveis com os dois; nada de `hint_depth_texture`/reverse-z específico.
- **Água = única superfície transparente** (`blend_mix`, sem `hint_depth_texture`).
  Motivo: várias superfícies transparentes causavam o "raio X"; uma única, sobre
  um mundo opaco, ordena-se bem.
- **Sem saia nos chunks.** Motivo: a franja vertical desenhava os limites dos
  chunks (visto no rasterizador). As costuras de LOD ficam tapadas pelo overlap.
- **Diagnóstico por "olhos":** `tests/shot.gd` + `tools/render_shot.py` geram
  PNGs da geometria real. Regra: nunca declarar um bug visual fixado sem uma
  imagem ou uma medição que o prove.
- **Carimbo de build** (`build_info` no pck, no HUD e na consola) para saber
  sempre que código está a correr — acabou as rondas às cegas.
