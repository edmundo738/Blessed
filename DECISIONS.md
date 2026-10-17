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
- **Relva: um ladrilho de máscara = 1,05 m, não 0,36 m** (`Materials.GRASS_MASK_SCALE`).
  Motivo: com 0,36 m cada lâmina tinha ~5 mm — sub-pixel a partir de um metro —
  e o campo só podia ler-se como pontilhado. A 1,05 m a lâmina fica com ~1 cm e
  11–27 cm de comprimento, com 68% de cobertura. Densidade da máscara gerada por
  `tools/make_grass_masks.py` a ~420 fios por ladrilho.
- **A cor da relva vem do BIOMA, não de um atlas** (`Terrain.grass_tint_of`):
  a lâmina leva a cor da relva daquele ponto (viçosa num sítio húmido, seca no
  deserto/savana) em cor de vértice/instância, e o shader só acrescenta a rampa
  base-escura → ponta-clara. Antes as lâminas eram verde-atlas sobre chão
  amarelo de savana: cada lâmina sub-pixel virava um ponto de ruído de alto
  contraste (o "picotado" reportado pelo dono).
- **Terra castanha só junto ao jogador** (`soil_near = 4`, `soil_far = 20` no
  `toon_terrain`): de perto vê-se o solo onde a relva cresce; a partir de ~20 m
  domina a cor da relva, senão o campo lia-se como poeira com pontos verdes.
- **A relva por níveis desaparece aos ~50 m** (`size_far`): a partir daí cada
  lâmina é menor que um pixel e o campo continua nas cores do terreno (mesma
  família de cor). Densidade mínima 0,62 — nunca se corta o campo a meio.
- **Raio limpo à volta do nascimento** (`World.SPAWN_CLEAR_RADIUS = 4,5 m`):
  nascer dentro de um tronco é nascer preso. A vegetação é espalhada depois de
  `main.gd` dizer onde é o nascimento, e salta esse raio.
- **Servidor de preview sem cabeçalhos de isolamento** (`tools/serve_web.py`):
  COOP/COEP/CORP só são precisos em builds com threads; num build single-thread
  impediam a página de ser embutida (pré-visualização) e forçavam CORP em todos
  os recursos. `--isolate` liga-os quando forem necessários.

- **Sono é tempo e custa recursos, não um botão.** Decisão: `sleep_until_morning`
  cobra fome e sede; a cama resolve a noite, a cadeira só dá um cochilo, o chão
  é mau. _Alternativa rejeitada:_ `energy += X` instantâneo (o "Sleep -= X" que
  o dono recusou) e o ecrã a preto sem tempo a passar. _Custo:_ dormir é
  assíncrono, e os testes têm de esperar em vez de ler `Game.hour` a seguir.
- **O fogo tem combustível (5 h + 1,4 h/madeira).** Motivo: uma fogueira acesa
  para sempre é uma lâmpada, não um sistema; sem isto juntar lenha não tinha
  razão e o `near_fire` era dado, não conquistado. _Custo:_ fogueiras podem
  apagar-se a meio da noite — é intencional.
- **`data/*.json` para números de sobrevivência** (`sleep.json`, `fire.json`),
  com valores de reserva no código para o jogo nunca depender do ficheiro para
  arrancar.
- **Texto de consequência em vez de texto de estado:** quando algo corre mal, a
  mensagem diz o que aconteceu e o que o teria evitado ("caiu-te mal; cozinhar
  na fogueira evitava isto"), não apenas "estás doente".
