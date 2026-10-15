# Blessed — prioridades de gameplay e mundo

O critério de entrada continua a ser: cada objeto precisa de uma função clara,
uma ação do jogador e um resultado que se possa ver ou sentir.

## P0 — Cortar, remover e recolher sem contradições

**Implementado nesta passagem:** a árvore abatida conserva os materiais do modelo,
fica no mundo com colisor próprio e oferece toros com `F`. O colisor da árvore em pé
é removido no mesmo corte; a rocha colhida também deixa de bloquear o jogador.
Recursos largados usam `RigidBody3D`, assentam no terreno e recolhem por proximidade,
sem uma notificação grande por cada item. Árvores e rochas aceitam `F` mantido ou o
botão esquerdo. O HUD mostra o comando contextual e o arranque deixa de impor missões.

**Verificado em headless:** 128 verificações aprovadas. **Ainda precisa de validação
gráfica:** assentamento dos troncos em declives, contacto do jogador com o tronco,
leitura do pickup à escala normal e queda sem atravessar o terreno.

## P1 — Movimento e leitura do jogador

Testar subidas, descidas, ravinas e saltos em terrenos reais. Afinar assistência de
borda e colisão para que o jogador não fique preso nem deslize por encostas que parecem
transitáveis. Depois substituir a silhueta atual do jogador e as mãos provisórias por
um corpo e animações direcionais que comuniquem aceleração, salto, golpe, natação e
estado de mãos vazias.

**Aceitação:** atravessa as rotas comuns sem ficar preso; o jogador pode subir saliências
razoáveis; a pose e os efeitos confirmam a ação sem tapar o alvo.

## P2 — Ciclo inicial de sobrevivência e construção

Começar sem recursos mágicos: gravetos e pedras pequenos no chão, apanhar, combinar
pedra e fibra para afiar uma ferramenta, cortar madeira, fazer corda e construir uma
primeira estrutura. Cada receita deve consumir os ingredientes certos e produzir um
objeto visível. Colocar paredes, piso e telhado em encaixe simples, com pré-visualização
válida e remoção legível. Plantas diferentes passam a ter folhas, flores, tintas e frutos
quando a espécie justificar esses usos.

**Aceitação:** uma sessão nova permite recolher, fabricar e construir sem texto de missão;
cada falha de craft explica apenas o recurso em falta.

## P3 — Rios, mar e travessia

Dar ao mar uma superfície contínua no nível de água e modelar rios com margens graduais,
profundidade transitável e saídas acessíveis. O canal deve acompanhar a altura do terreno;
cachoeiras vêm depois, em quedas finitas entre cotas e reservatórios, sem água infinita.
Separar natação, corrente, som submerso e recolha aquática para cada uma ter resposta clara.

**Aceitação:** o mar não desaparece entre chunks; margens não viram crateras; o jogador
consegue sair da água em pontos jogáveis.

## P4 — Formas do terreno e biomas que se encontram

Reduzir costuras e faces sobrepostas do terreno atual; testar a migração a voxels numa
área limitada antes de substituir o gerador inteiro. Fazer transições de humidade, cor e
vegetação entre floresta, pradaria, savana, areia e rocha. Variar grupos de espécies e
espaços vazios; colocar ruínas com silhuetas e histórias distintas, não cópias repetidas.

**Aceitação:** não há paredes de chunk visíveis nem relva verde sobre areia seca; cada
bioma é identificável sem cortar o mundo numa borda abrupta.

## P5 — Desempenho e sombras medidos

Medir tempo de geração, FPS e uso de memória em pontos fixos, depois de o mundo aquecer.
Priorizar chunks visíveis, afastar detalhes e colisões sem apagar o horizonte, e verificar
sombras na malha do terreno com a luz real. Só então escolher limites de LOD e distância
de visão por renderer.

**Aceitação:** números antes/depois na mesma máquina e cena; sem pop de árvores visível,
buracos no mar, nem sombra que desaparece ao tocar a terra.

## P6 — Atmosfera e identidade visual

Depois do ciclo jogável e do perfil de desempenho: trabalhar sol, lua, nuvens em camadas,
reflexo do céu na água, névoa por clima e hora, vento visível na vegetação e paletas
noturnas. Usar as imagens de referência como direção de composição e cor, não como texturas
esticadas pelo cenário.

**Aceitação:** cada hora e bioma tem uma paleta reconhecível; o sol e a lua iluminam de
forma diferente; vento e névoa acrescentam atmosfera sem esconder o caminho.
