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

### E a relva, neste desenho?

A relva NÃO será um Node por lâmina: será MultiMesh por pedaço, gerada
dos mesmos campos (`species_density`-like: humidade/declive/bioma da
superfície ATUAL). Interação com a escavação, pela mesma regra dos props:
ao cavar/aterrar, só o pedaço tocado regenera as suas instâncias —
lâminas onde `depth_dug > 0,1` ou a nova superfície ficou molhada/íngreme
desaparecem (ficou terra exposta, lê-se a camada), e a relva volta a
crescer por humidade ao longo de dias de jogo nos pontos que voltaram a
ser prado. Custo: zero por frame, só rebuild local — idêntico ao terreno.
