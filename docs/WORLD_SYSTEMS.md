# Blessed — arquitetura viva do mundo

## Fonte de verdade

O mundo não deve ser uma lista de objetos colocados por sorteio. A mesma
coordenada precisa responder a perguntas de terreno, água, clima, bioma,
vegetação e recursos sem cada sistema inventar uma resposta diferente.

```text
seed + coordenada global
        ├── relevo-base + geologia
        │       └── drenagem → rios, lagos, margens e humidade
        ├── clima + altitude + água + declive → pesos contínuos de bioma
        ├── bioma + manchas ecológicas + geologia → espécies e recursos
        └── representação por chunk/LOD → malha, colisão e instâncias
```

`Terrain.environment_at(x, z)` é a consulta de gameplay/editor que reúne
altura, declive, clima, pesos de bioma, água e geologia. A malha continua a usar
funções escalares nos caminhos quentes para não alocar um dicionário por vértice.
Todos os campos usam coordenadas globais e a semente do mundo, portanto os
resultados coincidem nas bordas dos chunks.

## O que já está ligado

- **Geologia determinística:** províncias contínuas de aluvião, arenito, calcário,
  granito e basalto; dureza altera erosão e altura das cristas, estratos afetam
  badlands, permeabilidade ajusta o escoamento superficial e a exposição altera
  o peso do terreno rochoso. O calcário/fraturamento expõe potencial de carste,
  cavernas e minérios para a próxima camada.
- **Hidrologia causal:** a rede D8 recebe relevo, humidade e infiltração. A água
  escava o terreno e o terreno determina as margens e os biomas ribeirinhos. A
  costa inicial tem baías e promontórios determinísticos e mantém o mar fora da
  área de nascimento. A rede atual é regional (2,56 km de largura); ainda não é
  um mapa continental infinito com várias bacias.
- **Ecologia por habitat, não por bioma vencedor:** as espécies somam os pesos
  de todos os seus habitats, então prado/floresta/savana se encontram sem uma
  linha de troca. Campos globais de cobertura criam povoamentos e clareiras sem
  repetir o mesmo sorteio em cada chunk. Densidades de plantas e rochas são
  afináveis em `data/biomes.json`.
- **Conteúdo usado:** fetos, flores, trevos e caniços do kit Quaternius entram
  apenas nos habitats adequados. Continuam decorativos até haver uma regra de
  recolha própria; não aparecem como alvos falsos de interação.
- **Recursos ligados à rocha:** `flint_node` favorece formações sedimentares e
  calcárias, em vez de ter a mesma chance em qualquer terreno elegível.

## Representação e persistência

O exterior continua como heightfield procedural em chunks de 48 m. Não vamos
converter o mapa inteiro em voxels. Cavernas, minas e túneis devem ser patches
volumétricos locais, criados só onde a geologia os permite, com malha e colisão
próprias e uma junção explícita com o terreno exterior. O mundo gerado fica como
base imutável; mineração, construção, árvores cortadas e mudanças de água são
deltas persistentes por cima dela.

## Próximas etapas estruturais

1. **CavePatch jogável:** selecionar entradas por carste/fratura/declive,
   gerar uma câmara e túneis finitos, colisão e saída; persistir mineração local.
   Não gerar cavernas só como decoração nem abrir buracos sem caminho navegável.
2. **Bacias e costas:** substituir a costa de arranque e a bacia única por
   regiões determinísticas que partilham cotas, divisores, nascentes, afluentes,
   estuários e mar. Cachoeiras são quedas finitas entre cotas, com água a jusante.
3. **Geografia grande/média/pequena:** primeiro continentes e cordilheiras,
   depois vales e corredores ecológicos, por fim rochas, árvores, ruínas e
   detalhes. Marcos humanos são selecionados por regras de contexto e variedade.
4. **Travessia:** avaliar a malha de colisão e as rotas geradas para que ravinas,
   margens, grutas e encostas tenham subidas e saídas deliberadas para o jogador.
5. **Streaming e custo:** manter a consulta determinística; limitar colisões e
   detalhe por LOD e só depois medir e ajustar a quantidade de instâncias.

## Critério de aceitação do mundo

Uma coordenada deve ter uma explicação coerente: por que o terreno tem aquela
forma, por onde a água segue, por que o bioma muda ali, que espécies podem
crescer, que rocha aparece e que recursos podem existir. A transição deve ser
suave quando clima/elevação mudam e pode ser definida quando existe uma barreira
física, como costa, crista ou parede de caverna.
