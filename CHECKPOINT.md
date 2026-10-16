# CHECKPOINT — estado atual do projeto

> Este ficheiro é a memória do projeto. Qualquer IA (ou humano) que abra o
> repositório começa por lê-lo. Atualiza-se no fim de cada marco.
> Última passagem de auditoria: 2026-10-14 (Godot 4.7.2 headless: 125 verificações, 0 falhas).
> O histórico de auditoria abaixo preserva resultados antigos; quando diferirem, prevalecem
> este marco mais recente e `docs/AUDIT_2026-10-14.md`.

## Marco mais recente — GAMEPLAY: colheita, ferramentas, bancada, água e loot (2026-10-16)

Foco desta passagem: **a interação do jogador**. Nada aqui é ambiente — é o que a
pessoa faz e o que ela vê acontecer.

- **A mira acerta no que se está a olhar.** `interaction.gd` deixou de escolher o
  alvo por um ponto médio inventado (`pos + altura*0.45`) com um cone de 35°: agora
  faz raio contra a FORMA (cilindro do tronco + copa, elipsoide da rocha, esfera da
  planta, caixa da estrutura, segmento do tronco caído). Apontar ao tronco corta a
  árvore; apontar para o lado não apanha nada; o alcance é respeitado.
- **Três verbos distintos**, como o Minecraft: rato esquerdo = trabalhar (segurar),
  F = pegar/interagir (toro, encher, acender, dormir, falar), rato direito (ou X) =
  usar o que está na mão (comer, beber, colocar, pescar). Antes F e o rato faziam
  o mesmo.
- **Diferença real entre mãos, madeira e pedra.** Machado dá `power.chop` (1,1
  madeira / 2,2 pedra) e as mãos só 0,30-0,38 por golpe (árvore de 6 hp: 18 golpes
  à mão contra 6 com machado de madeira). A **pedra exige picareta** (`needs`): sem
  ela o nó não perde vida e o HUD diz o que falta. Trabalhar consome energia.
- **Ciclo de progressão fechado e sem dependência circular:** mãos → madeira, ramo,
  folha, fibra e **pedra solta** (`flint_node` dá pedra) → bancada (4 madeira + 2
  ramos) → machado/picareta de madeira → pedra a sério → ferramentas de pedra.
  `stations_near` passou a reconhecer a bancada colocada (antes só a fogueira
  contava e as receitas novas eram impossíveis).
- **Água que não prende ninguém:** rio raso atravessa-se a pé (vadear, mais lento);
  só acima de 1,35 m de profundidade é que se nada; quem está submerso sobe sozinho
  até à tona e fica neutro lá em cima. A criatura deixou de seguir o leito do rio
  (afundava-se e ficava presa) e passa a nadar à superfície.
- **Loot que não é feio:** cada família de item tem malha própria (ferramenta com
  cabo e cabeça, peixe com barbatana, sopa em tigela, mesa), o item assenta e gira
  devagar depois do arremesso, é atraído por um íman a 2,1 m e **flutua** se cair
  na água em vez de se perder no fundo.
- **Verificado:** `selftest` headless (wasm 4.7.2) — **141 ok, 0 falhas, 31
  saltadas**. As verificações novas medem resultado observável: o raio apanha o
  tronco e não o resto, a pedra sem picareta não perde vida, com picareta perde, o
  machado reduz o número de golpes, a bancada é exigida e reconhecida, comer com o
  rato direito tira o item da mão, a pesca dá peixe, o item é atraído, o item na
  água sobe. As 31 saltadas são de ambiente (sem cache de importação `.godot/` os
  modelos Blender não existem e usam-se as malhas geradas por código; em
  `gl_compatibility` não há passes de partícula) — falham por motivo declarado, não
  por bug.

- **Há caça no mundo (o ciclo da comida fecha):** `meat_raw`, `meat_cooked` e o
  guisado não tinham NENHUMA fonte — não existia um único animal. Agora o
  `Wildlife` mantém até 5 animais de dia (nascem longe e à vista, desaparecem a
  62 m), eles pastam em bando, fogem do jogador, nadam se caírem à água e largam
  carne quando são abatidos (rato esquerdo; o machado poupa golpes). Carne crua →
  assada na fogueira → guisado.
- **O menu de craft mostra os degraus que faltam** ("Ainda não tens a estação
  destas receitas: bancada — machado de pedra, picareta, cama…") em vez de as
  esconder, que era o que fazia parecer que o craft tinha acabado.

## Marco anterior — água, luz local e relva (2026-10-15)

- Água usa shader opaco de dupla face, ondas/espuma estilizadas e paleta diferente
  debaixo da superfície; o tipo mar/rio agora é passado ao shader corretamente.
- Luzes locais usam decaimento contínuo nos materiais toon, sem bandas que
  facetavam o alcance da fogueira.
- Relva combina cartões MultiMesh com a textura Quaternius perto do jogador,
  shells com a mesma paleta até ao LOD distante e pintura do terreno no horizonte.
  A cobertura respeita pradaria/savana e transições, excluindo areia de praia,
  deserto e declives fortes; os níveis dos shells coincidem entre LODs.
- **Verificado:** arranque Godot 4.7.2 headless e compilação dos shaders sem
  erros. O renderizador de diagnóstico não reproduz o mascaramento do shader
  procedural de shells/cartões; a aparência e o FPS no renderer real ainda
  precisam de confirmação no jogo.

## Marco anterior — vegetação e céu (2026-10-14)

- 14 famílias de modelos gratuitos Quaternius CC0 foram integradas como assets separados,
  com ficheiro-fonte Blender editável e LODs. O kit procedural anterior foi preservado.
- Kenney CC0 fornece três panoramas 2K e sprites de partículas. O céu liga sol e lua ao
  relógio do jogo, tem fase lunar, halo e nuvens estilizadas com deslocamento em duas escalas.
- A regra de chunks mantém detalhe e sombras perto do jogador; os anéis afastados usam LODs,
  sem colisão detalhada. Ver `docs/MODEL_SCALE_GUIDE.md`.
- **Verificado:** Godot 4.7.2 headless, 125 verificações aprovadas, 0 falhas; log final sem
  erros ou avisos. Os avisos ObjectDB da passagem antiga não reapareceram nesta execução.
- **Ainda por verificar visualmente:** renderização real, performance/FPS/VRAM em Forward+
  e Compatibility/Web. O teste headless comprova carregamento e lógica, não a qualidade da
  imagem no GPU. A prioridade seguinte está em `docs/PRIORITY_ROADMAP.md`.

## O que é
Sandbox de sobrevivência em 1.ª pessoa por omissão, estilizado "anime", em Godot 4.7.2.
Fatia vertical jogável: mundo procedural (chunks), dia/noite, NPCs, colheita,
crafting, construção, sobrevivência, prólogo com criação de personagem,
PT/EN, save/load. O cenário é híbrido: geração GDScript e um kit de modelos Blender.

## Como corre
- **Preview web (Arena):** `tools/serve_web.py` + `export/web/blessed.pck`.
  Renderer web = `gl_compatibility` (definido em `project.godot`).
- **Local (máquina do dono):** abrir `project.godot` no Godot 4.7.2 e F5.
  O renderer local por omissão é Forward+; o web é Compatibility.
- **Testes do projeto:** `./tools/check.sh` (selftest headless; última execução: 125 checks).
- **Auditoria de erros:** correr o selftest e ler TODAS as linhas `ERROR:` —
  foi assim que se apanharam os bugs de API Godot-3 (ver KNOWN_ISSUES #1-#5).

## Estado por sistema (OBSERVED = medido, não opinado)
| Sistema            | Estado   | Prova |
|--------------------|----------|-------|
| Mundo/chunks       | OK       | selftest + rasterizador (`docs/shots/`) |
| Controlos          | OK       | selftest (tabela de teclas) |
| Água               | shader opaco dupla face, ondas/espuma; sem depth-texture | shader e arranque Godot headless; aparência no renderer real pendente |
| Céu/sombra/LOD     | céu Kenney CC0 2K, sol/lua e nuvens dinâmicos; LODs por anel | importação e contratos no selftest; imagem/FPS GPU ainda não medidos |
| Relva/árvores      | 14 famílias Quaternius CC0, espécies separadas e LODs | meshes, dimensões e instâncias validados no Godot headless; aparência no renderer por validar |
| NPC                | componente sprite 2D com variações; sem aldeões ativos na cena atual | script incluído no selftest; aldeões não aparecem na cena |
| Criatura noturna   | sprite 2D billboarding e fade de amanhecer | tipo de sprite confirmado no selftest; imagem não inspecionada |
| Música              | temas procedurais por fase e transição cruzada | seleção/funções confirmadas; mistura não ouvida |
| Câmara              | 1.ª pessoa por omissão; `V` alterna para câmara externa | selftest a validar nesta passagem |
| HUD                 | barra rápida com ícones e seleção, needs compacto, alvo contextual | menu mochila/bancada e slots conferidos no selftest; sem captura visual |
| Interação           | plantas com F; árvores/rochas com LMB mantido, dano por golpe e feedback | queda e respawn da árvore confirmados no selftest |
| Mãos 1.ª pessoa     | malha do item acompanha o espaço rápido; ferramentas desenhadas | nó/malha testados; imagem no renderer não inspecionada |
| Prólogo            | primeira frase agora escrita | selftest |

## Próximo marco (por ordem)
1. Capturar o jogo no renderer real em dia, crepúsculo e noite; medir FPS e VRAM em
   Forward+ e Compatibility/Web antes de mexer em qualidade ou densidade.
2. Melhorar ferramentas/mãos de primeira pessoa e feedback de colheita/construção.
3. Resolver margens e saídas de rios, depois expandir vida selvagem e som.
   Ver `docs/PRIORITY_ROADMAP.md` para critérios de aceitação.

## Auditoria local anterior (2026-10-14)

Os apontamentos abaixo são o registo da passagem anterior; os estados atuais de vegetação,
céu e testes estão no marco mais recente no topo e em `docs/AUDIT_2026-10-14.md`.

- **OBSERVADO:** o repositório não contém assets de áudio; `Sfx` já gerava efeitos em PCM.
  Não havia trilha musical, NPCs eram malhas 3D e a criatura noturna também era 3D. O avatar
  2D existia, mas ficava escondido porque a vista inicial era em 1.ª pessoa.
- **ALTERADO:** música procedural adaptada às fases do dia, protagonista 2D visível por
  omissão, sprites billboards para aldeões futuros e para a criatura noturna.
- **VERIFICADO:** Godot 4.7.2 headless executou o selftest: 86 verificações, 0 falhas.
  Foram corrigidos erros de inferência de tipos e atribuições de transformação no rig de
  diagnóstico que surgiram durante a execução.
- **ALTERADO:** HUD com ícones desenhados no jogo, seleção da barra rápida, mochila e bancada
  com ícones, receita com contagem de ingredientes, comandos de interação sem duplicação,
  dano por golpe, queda/respawn das árvores e recolha de excesso deixado no chão.
- **ALTERADO:** mãos/item em primeira pessoa inicializam corretamente; o salto ganhou um
  som próprio suave em vez de reutilizar um som de passo.
- **UNKNOWN / NOT VERIFIED:** o executável Blender 5.2 está assinado, mas o Windows terminou
  a tentativa de execução desta sessão com `-1073741790`; nenhum `.blend` ou `.glb` foi
  gerado. O machado e a picareta continuam a ser malhas geradas por GDScript nesta revisão.
- **LIMITAÇÃO OBSERVADA:** o processo termina com aviso de 8 instâncias ObjectDB ainda
  referenciadas.
- **UNKNOWN / NOT TESTED:** build web, execução interativa, aparência visual em Forward+ e
  Compatibility, desempenho e audição da mistura musical. O teste headless não comprova
  esses resultados.
