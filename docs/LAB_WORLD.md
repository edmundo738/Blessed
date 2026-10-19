# LAB_WORLD — laboratório de mecânicas (Etapa 1)

## Porquê um laboratório, e não remendar o mundo grande

O mundo atual mistura tudo em `Terrain` (ver `docs/CURRENT_ARCHITECTURE.md`).
Reconstruir por cima dele repetia o erro: cada correção nova nascia já
acoplada a 17 ruídos e a um rio-seno. Em vez disso, o Blessed ganha um
**mundo finito de teste, 400×400 m rodeado de oceano**, onde cada mecânica
se prova isolada, por estações, antes de entrar no mundo grande. Nada foi
apagado: o laboratório vive ao lado (`scripts/world/lab_world.gd`,
`data/lab.json`).

## O modelo (uma autoridade, vários leitores)

Grelha de 81×81 células de 5 m com campos causais:

```text
relevo (ilha + montanha NW + bacia SE)
  → temperatura (altitude arrefece) + chuva (barlavento W + altitude)
  → D8 sobre relevo com depressões preenchidas → acumulação de fluxo
  → rios escavam o próprio leito; depressões sem saída viram lagos; h<0 é oceano
  → distância à água (BFS) + chuva → humidade do solo
  → bioma (costa/areia/rocha/pântano na margem húmida/bosque/seco/floresta)
  → espécies por habitat × mancha: carvalho, bétula, sakura, pinheiro, salgueiro
```

`sample(x,z)` é a consulta única: altura, declive, temperatura, chuva,
humidade, fluxo, tipo/nível/profundidade de água, distância à água, bioma.
Render, gameplay e save leem daqui; nenhum leitor inventa mundo.

**Escavação é parte do modelo, não um truque visual:** `dig(x,z,raio,prof.)`
grava deltas na grelha, recompõe fluxo/água e devolve o solo removido.
Cavar abaixo do nível da água enche; aterrar um curso pode desviá-lo —
o jogador descobre pelo efeito, nunca por texto de solução.

## Estações de teste (em `data/lab.json`)

Nascer/prado · bosque de 3 espécies (cortar→tronco da mesma espécie→craft) ·
pedreira · zona de escavação · clareira de construção (fundação/estacas) ·
margem do rio · lago · praia/oceano. Cada estação declara o loop que prova:
recolha, escavação, craft, construção, geração — pequenos, finitos, jogáveis.

## Verificação

- `tests/labtest.gd` (`-- labtest`): testes de **causalidade**, não de
  sintaxe — determinismo, ilha rodeada de oceano, rede de rios, lago na
  bacia, escavar faz buraco e remove solo, carvalho agrupa na floresta e
  rareia no seco, salgueiro cola-se à margem, sakura ao bosque, clareira
  de construção avaliável.
- `tools/lab_preview.py`: mapa de campos (altura/água/bioma/espécies) em
  PNG a partir do mesmo modelo — o "debug obrigatório" da Etapa 0.

## O que falta (por etapa, sem saltos)

1. Render 3D do laboratório (mesh a partir de `sample`) + nascer nele por flag.
2. Colher/cortar com herança de espécie no tronco caído (H3) provado no bosque.
3. Escavação jogável (pá, solo como item, aterro) provada na estação de escavação.
4. Construção com fundação adaptativa/snap/suporte provada na clareira.
5. Só depois: migrar cada sistema provado para o mundo grande, um de cada vez.


## Etapa 2 — visualização, spawn e modo deus (2026-10-18)

- `scripts/world/lab_mesh.gd`: mesh suave por pedaços de 50 m (normais por
  gradiente, cor por bioma/humidade/declive) + faces côncavas de colisão;
  `rebuild_area()` reconstrói só os pedaços tocados ao cavar.
- `scripts/lab/lab_scene.gd` (`scenes/lab.tscn`): ilha em 3D, água por
  células, árvores/pedras reais por afinidade, 8 estações como plataformas
  coloridas (nomes só em modo dev), Player real a nascer em terra firme.
- `scripts/lab/lab_dev.gd`: modo deus — F voar, LMB cavar, RMB
  aterrar/reconstruir, E partir árvore/pedra (drops reais via Db.HARVEST),
  F1 painel com dar/spawnar TODOS os itens, repor mundo, renascer.
  Partículas de poeira no ponto da escavação (feedback do material).
- `Player.dev_fly`: voo sem gravidade (ferramenta dev, fora do gameplay).
- Item novo `soil`: cavar largar solo; aterrar é o seu par.
- Prova: `tests/labscene.gd` — LABSCENE_PASS 14/14 (mesh 7744 vértices,
  colisão por raycast, spawn assenta, cavar baixa, aterrar reconstrói,
  voo ativo, **winding do terreno e da água coerente com as normais —
  0 triângulos virados**, regressão do bug em que a face de cima era
  cullada e só se via por baixo) + LABTEST_PASS 14/14 + selftest
  245 ok/0 falhas.
- Como testar local: extrair o pack da etapa por cima da pasta Blessed,
  abrir `scenes/lab.tscn`, F5. Primeiro teste sugerido: cavar.

## Escavação por camadas + ferramentas (2026-10-18)

**O problema que o dono viu:** raio de escavação enorme, objetos a flutuar,
água serrilhada com triângulos órfãos na costa, e cavar "à mão" dava o
mesmo em areia, terra ou rocha. A matemática agora é uma só:

- **Material = lookup partilhada** (`LabWorld.material_at`): margem/leito →
  AREIA; afloramento (declive > 0,55 ou bioma rocha) → ROCHA; profundidade
  escavada face à superfície ORIGINAL (`depth_dug = original − atual`):
  ≤ 0,7 m solo solto, ≤ 2,3 m subsolo, > 2,3 m ROCHA. Dureza 1/1/2/3.
  É o mesmo desenho de dureza por profundidade do Astroneer e dos níveis
  1–3 do Deep Rock Galactic: a ferramenta certa lê-se do chão.
- **Ferramentas** (`LabScene.TOOLS` + `tool_dig`): mão r=1,5 m superficial
  (só areia/topsoil), pá r=2,3 m rápida (terra/areia, inútil na rocha),
  picareta r=1,3 m lenta (única que parte rocha). Rendimento por material:
  areia→`sand`, terra→`soil`, rocha→`stone`. Negação é EFEITO (poeira
  cinzenta, slot a piscar), não texto — o texto vive só na etiqueta dev.
- **Perfil do buraco:** queda co-seno `0,5+0,5·cos(π·d/r)` — tangente
  horizontal no centro e na orla; sem degrau, sem serrilhado na costa.
- **Água:** malha sobre os MESMOS pontos de grelha do terreno, triângulos
  recortados pelo campo assinado `nível − altura` (como `chunk.gd` faz no
  mundo principal). A costa nasce onde `nível == altura` na aresta;
  acabaram-se os quadrados planos por célula e os triângulos órfãos.
- **Nada flutua** (`reseat_props`): após deformar, cada prop na área
  compara o chão de nascimento com o novo — desceu pouco, assenta;
  árvore perdeu ≥ 1 m de chão, CAI (rotação ease-in à volta da base) e
  vira drops da espécie. Estações incluídas. Custo ∝ área tocada.
- **Camadas visíveis:** onde `depth_dug > 0,12`, a cor do vértice mistura
  para o estrato (topsoil → ocre → rocha): o buraco lê-se por camadas.
- **HUD dev:** barra compacta ao fundo (3 slots, roda/1-3 troca) +
  material/dureza sob a mira; painel F1 como antes.
- Prova: LABSCENE_PASS 20/20 (mão não parte rocha, picareta rende stone,
  árvore cai ao escavar por baixo), LABTEST_PASS 18/18, selftest 245 ok.

### A relva (implementada, 2026-10-18)

MultiMesh por pedaço de 50 m (6 lâminas-cruz candidatas por célula,
~3 500 instâncias na ilha) — nunca um Node por lâmina. A densidade lê a
superfície ATUAL (`LabScene.grass_density`): zero em água, areia, rocha,
declive > 0,38 ou onde `depth_dug > 0,1` (camada exposta não tem relva);
nos prados cresce com a humidade e o bioma. Interação com a escavação,
pela mesma regra dos props: ao cavar/aterrar só o pedaço tocado se
reconstrói, por isso a relva some do buraco e da terra revirada; o pedaço
fica "perturbado" (`_grass_growth = 0,15`) e recresce 0→1 em ~24 s, em
degraus de ¼ para reconstruir no máximo 4× durante o crescimento.
Prova (labscene 21–24): a ilha tem relva, escavar faz o pedaço perder
lâminas, aterrar + tempo faz-las voltar. Custo por frame: zero fora dos
pedaços a recrescer.

## Estação de escavação jogável (2026-10-19)

A estação `dig_pit` (30, 30) deixou de ser só "cava aqui": tem um objetivo
descoberto **pelo efeito, nunca por texto**:

- Enterrada a **3,2 m** (sob a camada de rocha dos 2,3 m) está uma
  **relíquia** (`LabScene.RELIC_DEPTH`). A matemática das camadas ensina a
  lição sem palavras: a pá escava o solo, **bate na rocha e é negada**
  (poeira cinzenta); a mão nem ao subsolo chega; só a picareta atravessa.
- **Glint:** ao escavar perto do sítio e já fundo, a poeira começa a
  brilhar dourada, com intensidade = proximidade × profundidade
  (`glint` 0..1 no resultado de `tool_dig`). Nenhum HUD diz "está aqui".
- **Desenterrar:** a relíquia emerge luminosa no buraco, com explosão de
  partículas douradas e flash dourado de 200 ms no `LabDev`
  (`_flash_gold`) — dopamina visual, zero texto. Item novo: `relic`.
- Prova (labscene 25–29): estação localizada; pá negada na rocha com a
  relíquia ainda enterrada; glint observado durante a descida; picareta
  desenterra; relíquia visível no mundo.

Game taste aplicado nesta passagem: feedback por material (poeira areia/
terra/rocha com cores próprias, cinzenta na negação), ritmo por ferramenta
(intervalos 0,22/0,14/0,28 s), negação por efeito (slot a piscar, poeira
seca), pista por intensificação sensorial (glint) e recompensa com
espetáculo curto (burst + flash + objeto emissivo). O ecrã continua
limpo: a barra dev mostra só ferramenta e material sob a mira.

## Construção inteligente (2026-10-19)

A estação `build_pad` prova o sistema novo (o do mundo grande será
migrado depois de aprovado aqui):

- **Snap de 2 m**: a peça salta para a célula — sem meio-pixel nem
  rotações tortas (R roda a parede em 90°).
- **Fundação adaptativa**: o topo nivela pelo canto mais alto; 4 estacas
  descem até ao chão real em cada canto. Declive até 2,6 m de estaca;
  além disso recusa (`too_steep`). Água recusa (`in_water`).
- **Estabilidade (tipo Valheim)**: fundação 1,0 → parede 0,92/0,74 →
  chão 0,70 (0,85 com pilar) → telhado 0,58 (0,75 com pilar). O preview
  fantasma pinta **verde ≥0,8 · amarelo ≥0,62 · laranja <0,62 ·
  vermelho = não entra** — a cor ensina, sem texto de tutorial.
- **Nada flutua**: `evaluate_place()` é a única porta (preview e
  colocação leem a mesma resposta). Parede sem fundação, chão sem
  parede e telhado sem apoio são recusados.
- **Colapso em cascata**: remover a fundação derruba a célula toda;
  remover a parede de baixo derruba a de cima, o chão e o telhado.
  Remover devolve metade dos materiais; colocar consome do inventário.
- Prova (labscene 30–37): recusas certas, empilhamento com suporte,
  contagem de peças, colapso ao tirar a fundação, custo debitado.

### Mais peças e telhados (2026-10-19)

- **Porta e janela ocupam o lugar da parede** (mesmo nível e suporte):
  porta = caixilho com vão real sem colisão (atravessa-se o buraco);
  janela = peitoril + lintel. Ambas sustentam chão/telhado como parede
  cheia, com estabilidade um pouco menor (0,88/0,84) — a abertura paga-se.
- **Escadas**: 5 degraus com colisão própria, sobem os 2,4 m até ao chão;
  a rotação escolhe o sentido da subida.
- **Telhado de duas águas**: 2 painéis inclinados + cumeeira com beiral
  (adeus placa plana torta). A rotação escolhe a direção da cumeeira.
- **Rotação em 45°** (tecla R): parede/porta/janela/escadas/telhado
  também entram em diagonal. Teclas 1–8 escolhem as 8 peças.
- Colapso coerente: tirar uma janela/porta de baixo derruba chão e
  telhado; a fundação continua a arrastar a célula toda.
- Prova (labscene 38–44): porta no nível 0 com rotação de 45°, parede
  sobre porta só no nível 1, janela sustenta e ao sair derruba, telhado
  com ≥6 peças, escadas com ≥10 corpos (degraus + colisões).

### Polimento da construção (2026-10-19)

- **Feedback sensorial sem texto**: colocar uma peça = poeira da cor do
  material + batida sintetizada posicional (madeira aguda `build_wood`,
  pedra surda `build_stone`); remover = poeira peça a peça; colapso em
  cascata = estrondo `collapse`. A estabilidade também se OUVE.
- **Casinha-exemplo** nasce construída pelas regras normais junto à
  clareira: parede+pilar, porta com vão, janela, andares, telhados de
  duas águas e escadas para a porta (15 peças). É também o alvo ideal
  para ver o colapso: tira-lhe a fundação.
- Prova (labscene 45–46): casinha de pé com porta/telhado/escadas nos
  slots certos; streams de som sintetizados existem.

### Eficiência e construção ligada (2026-10-19, base HD2D)

- **Materiais/malhas partilhados**: 1 material por tipo de peça e 1
  BoxMesh por tamanho, em cache — acabou a criação de recursos gémeos
  por peça colocada. Material da água também é único e reutilizado.
- **Água preguiçosa**: escavar reconstruía a malha de água inteira
  (81×81) a cada golpe. Agora só reconstrói quando há água (ou terreno
  abaixo do nível dela) na área tocada — `_near_water` amostra 5
  pontos em vez de varrer a grelha. Prova com contador `_water_builds`.
- **Fundação que conversa com a vizinha**: fundação nova ao lado de
  outra adota o nível dela (se as estacas aguentarem) — casas ligadas
  partilham o piso em vez de nascerem com degraus entre divisões.
- **Construção ligada é mais forte**: +0,015 de estabilidade por
  fundação vizinha e +0,02 por parede vizinha na mesma linha (máx.
  +0,10). Isolar sai mais fraco; ligar a aldeia compensa.
- Provas (labscene 47–50): alinhamento de nível, bónus de ligação,
  material partilhado entre peças, água não reconstruída em terra seca.

### CavePatch: escavação volumétrica (2026-10-19)

Protótipo sobre o LabWorld, **sem tocar na hidrologia**: o terreno
continua heightfield (rios/lagos como estão) e ao lado nasce um bloco
de rocha volumétrico (24×12×24 m, células de 1 m) na zona alta do
bosque (44,-64).

- **SDF**: campo de distância assinada em grelha 3D (sólido < 0,
  ar > 0), caixa com ruído determinístico de rocha.
- **Escavar = CSG**: subtrair esfera ao campo (`max(sdf, r−d)`); só a
  picareta entra, a negação é por efeito como no resto do lab.
- **Surface Nets ingénua**: 1 vértice por célula cortada (média das
  interseções das arestas, `t=|a|/(|a|+|b|)`), quads nas arestas com
  mudança de sinal, normais pelo gradiente. Cada triângulo é virado
  até alinhar com o gradiente → faces para fora **por construção**
  (a lição do winding), com `last_outward_ratio` como prova.
- Colisão = as mesmas faces (ConcavePolygonShape), por isso o túnel
  anda-se por dentro a sério.
- Fronteira do protótipo: a água não entra nos túneis (inundação de
  minas é decisão futura do dono, não um acidente).
- Provas (labscene 51–56): bloco sólido → pá negada → picareta abre
  ar → escavações ligadas formam túnel contínuo → malha orientada →
  heightfield/hidrologia intocados.
