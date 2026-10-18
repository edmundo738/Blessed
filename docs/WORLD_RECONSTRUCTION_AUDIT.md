# WORLD_RECONSTRUCTION_AUDIT — inventário de problemas (Etapa 0)

Severidade: CRITICAL = impede o mundo de ser mundo; HIGH = gameplay sente-se;
MEDIUM = dívida que cresce; LOW = cosmético.

## CRITICAL
- **C1 — Água sem hidrologia.** Rio = seno (`Terrain._river_center`), mar =
  `lerp` sobre o relevo. Sem bacia/fluxo/nascente: rios não descem de lado
  nenhum, ilhas não estão no oceano, cones e elevações sólidas aparecem sem
  causa. → LabWorld: D8 + acumulação de fluxo sobre grelha finita.
- **C2 — Terreno é ruído empilhado, não modelo de dados.** 17 FastNoiseLite
  somados com máscaras; não existe célula com solo/humidade/erosão/geologia
  que outros sistemas possam consultar ou alterar. → grelha de campos.
- **C3 — Vegetação é scatter.** Sorteio por célula, sem manchas, afinidades,
  idades ou sucessão. Repetitivo e ilógico ao mesmo tempo. → densidades por
  espécie derivadas de campos + manchas (patch noise) + afinidades.

## HIGH
- **H1 — Construção sem sistema.** Sem sockets, snap, suporte nem fundação;
  colocar prefab não é construir. → etapa própria com estações de teste.
- **H2 — Chão não se escava.** Sem deltas de terreno não há voxel/mineração/
  barragem possíveis. → `dig()` com deltas + recomputação local no LabWorld.
- **H3 — Árvore abatida regredida.** Tronco caído não herda mesh/espécie.
  → corrigir na etapa da árvore, com teste de identidade (espécie→tronco).
- **H4 — Bioma é cor.** Sem morfologia nem comportamento por bioma.
  → híbrido: macro classifica, meso/local o bioma molda (vale do rio, bacia
  do lago, duna seca) já no laboratório.

## MEDIUM
- **M1 — `Terrain` faz tudo** (508 linhas: continente, montanhas, clima,
  geologia implícita, rio, costa, aldeia, caminho). Separar dados/geração/
  simulação/renderização.
- **M2 — Sem testes de causalidade.** 141+ checks de código não provam
  gameplay. → `tests/labtest.gd`: remover chuva seca rios? cavar enche de
  água? mesma espécie agrupa?
- **M3 — WFC ausente e sem lugar marcado.** Quando entrar, é composição
  local filtrada por campos (margens, clareiras, ruínas), nunca hidrologia.

## LOW
- **L1 — Debug visual do mundo é só altura/cor.** Faltam mapas de campos
  (chuva, fluxo, humidade, bioma) — primeiro mapa sai já nesta etapa.

## O que NÃO é problema (não tocar sem motivo)
- Loop de crafting/sobrevivência/NPC/save joga e tem testes.
- Chunks/LOD/MultiMesh rendem; o problema é o que lhes é dado para renderizar.
