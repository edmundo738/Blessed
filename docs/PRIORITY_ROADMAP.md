# Blessed — prioridades do próximo ciclo

## Feito nesta passagem

- 14 modelos de vegetação/rocha de origem gratuita entraram como espécies
  separadas, com variantes por bioma e LODs. O pinheiro escolhido não tem as
  estacas expostas que foram rejeitadas; a rocha não contém vegetação misturada.
- Céu com panoramas de dia, crepúsculo e noite, sol e lua ligados ao ciclo do
  jogo, fase lunar, brilho controlado e uma camada de nuvens com parallax.
- Poeira, pirilampos e impactos usam sprites Kenney CC0. O impacto mantém lascas
  3D e o sprite 2D; usa GPU em Forward+ e CPU no Compatibility.
- Godot 4.7.2: 125 verificações passaram, incluindo todos os meshes/LODs,
  distribuição por bioma, céu e os dois caminhos de partículas.

## Prioridades

### P0 — Ver o jogo nos renderizadores reais e medir

Headless confirma carregamento e lógica, mas não confirma a imagem final nem FPS.
Validar capturas a meio-dia, crepúsculo e noite em Forward+ e Compatibility/Web;
verificar o movimento do disco solar/lunar, a costura do panorama, as nuvens e a
leitura de cada árvore à escala do jogador. Guardar FPS/VRAM antes de mexer em
mais resolução, densidade ou LOD.

**Aceitação:** sem disco duplicado gravado no panorama, sem céu transparente fora
do passe das nuvens, sem novos erros no log e sem regressão observável nas cenas.

### P1 — Ferramentas e mãos em primeira pessoa

Substituir as silhuetas provisórias por meshes legíveis, acertar a escala e o
ponto de pega, e sincronizar o balanço com golpe, mineração e uso. Preservar o
espaço da câmara e garantir que cada item equipado mostra a ferramenta correta.

**Aceitação:** machado, picareta, tocha e comida distinguem-se à primeira vista;
animação e som correspondem ao contacto e não tapam o alvo.

### P2 — Recolha, queda e construção

Manter a regra de golpes, resistência, queda e pickups físicos já existente;
melhorar a queda em partes persistentes e o retorno visível de madeira/folhas.
Depois ligar receitas a bancada, cozinha, pesca e carpintaria e consolidar peças
de construção, portas e abrigo.

**Aceitação:** recurso aparece no local, pode ser recolhido, guardado e usado
numa receita coerente; nenhum recurso surge diretamente na mochila sem feedback.

### P3 — Água e vida selvagem

Resolver margens de rio e saídas de água profunda antes de aumentar vida marinha.
Introduzir animais por habitat e comportamento, mantendo animais e pessoas 2D e
o cenário em 3D estilizado.

**Aceitação:** o jogador consegue sair de cada margem jogável; cada espécie tem
habitat, animação, reação e recurso com propósito claro.

### P4 — Som e ritmo de sessão

Avaliar a mistura no jogo, reduzir o vento repetitivo, dar ao salto um som de
impulso curto e variar a música original por camadas sem copiar melodias de
referência.

**Aceitação:** nenhuma camada ambiente domina a sessão, efeitos não repetem a
curto intervalo, e mudanças de fase são graduais e audíveis.
