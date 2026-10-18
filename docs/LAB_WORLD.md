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
