# BLESSED — desenho

Este documento existe para que a próxima decisão não contradiga a anterior.

---

## 1. A premissa

Viveste muitas vidas. Um dia adormeceste. E acordaste **abençoado** — num mundo que não
conheces, com um corpo novo e uma marca da vida anterior.

Três tensões sustentam o jogo:

1. **Dias serenos.** Explorar, construir, cozinhar, falar com gente. O mundo é bonito e
   generoso durante o dia.
2. **Noites que se lembram de ti.** O escuro não é só dano: é medo, e o medo é um estado que
   se acumula e que os outros notam.
3. **A bênção.** Um recurso que regenera devagar e que explica por que razão o mundo te
   aceita. É o gancho narrativo e, mais tarde, a chave para encontrares outros como tu.

Não há "game over". Há consequências: fome, frio, medo, e gente que deixa de confiar.

---

## 2. O princípio LEGO

> Poucas peças boas + regras de combinação + contexto real + memória + personalidade.

O inimigo é a quantidade. 40 árvores que se cortam todas da mesma maneira valem menos do que
5 espécies com madeira diferente, cada uma útil numa receita diferente, crescendo onde o
bioma as permite.

Teste prático para qualquer conteúdo novo: **se não mudar uma decisão do jogador, não entra.**

---

## 3. A cadeia canónica

Tudo o que age no mundo — jogador, NPC, criatura — passa pelos mesmos sete passos:

```
PERCEPÇÃO → INTERPRETAÇÃO → INTENÇÃO → DECISÃO → MANIFESTAÇÃO → CONSEQUÊNCIA → MEMÓRIA
```

Em código (`scripts/entities/npc.gd` é a implementação de referência):

| Passo | Função | O que faz |
|---|---|---|
| Percepção | `_perceive()` | o que os sentidos dão: distância, hora, fogo, estado do jogador |
| Interpretação | `_interpret(p)` | contexto + personalidade + confiança → situação e valência |
| Intenção | `_intend(s)` | situação → intenção (`GREET`, `CHAT`, `WARN`, `FLEE`, `SLEEP`, `IDLE`) |
| Decisão | `_decide()` | intenção + capacidades + cooldowns → acção concreta |
| Manifestação | `_manifest()` | a acção acontece no mundo: movimento, fala, som |
| Consequência | `_consequence()` | o mundo reage: confiança sobe ou desce, objetivos avançam |
| Memória | `_remember()` | fica guardado, e altera a próxima interpretação |

A memória é real: `Npc.memory` guarda eventos com timestamp e entra na interpretação
seguinte. Um NPC de quem te afastaste a correr à noite lembra-se.

---

## 4. Comando ≠ resultado

```
CONTRACT → OWNER → INPUT → DECISION → ACTION → OBSERVABLE RESULT
```

`Game.request(id, args)` é a **única** porta de entrada para qualquer acção do jogador.
Devolve sempre um dicionário com o que foi observado:

```gdscript
var r := Game.request("craft", {"recipe": "pickaxe"})
# {"ok": false, "failed": true, "reason": "no_materials"}
# ou
# {"ok": true, "made": "pickaxe"}
```

A regra que não se quebra: **um comando que não fez nada devolve `failed: true`.**
`ok` é `not failed` — nunca é assumido. Isto existe porque "não deu erro" não é o mesmo que
"fez", e é exatamente essa a diferença que o self-test procura.

Cada `request` emite `Bus.intent_requested` antes e `Bus.command_resolved` depois, por isso
a UI nunca tem de adivinhar o que aconteceu: ouve o resultado.

---

## 5. Prioridades

Quando duas coisas boas colidem, ganha a que está mais à esquerda:

**Compatibilidade > Estabilidade > Coerência > Imersão > Qualidade narrativa >
Integração > Profundidade > Variedade > Quantidade**

Consequências práticas já aplicadas:

- **Compatibilidade** → Forward+ no desktop e `gl_compatibility` na web. Assets externos
  só entram quando têm função clara e formato suportado nos dois renderizadores; as
  panorâmicas CC0 do céu e os GLBs de vegetação são recursos normais do projeto, não
  dependências de runtime ou plugins.
- **Estabilidade** → self-test antes de se dizer que funciona; nenhum `:=` em expressões
  dinâmicas (é erro de parse em Godot 4.7, não um aviso).
- **Coerência** → uma só porta de entrada para acções, uma só fonte de verdade para o
  relógio, uma só tabela de itens (`Db`).

---

## 6. Personagem

Escolhida no prólogo, sem menu de criação:

- **Nome** — escrito à mão, usado pelos NPCs.
- **Corpo** — Ela / Ele. Afecta pronomes em todo o texto.
- **Alma** — o que ficou da vida anterior. Cada uma altera números reais, verificados no
  self-test:

| Alma | Promessa | Efeito medido |
|---|---|---|
| **Curiosidade** | "Encontras mais ao explorar" | alcance 4.20 → 5.67 m; bónus de colheita 35 % → 60 % |
| **Coragem** | "O medo cresce mais devagar" | medo base ×0.6 (0.500 → 0.300 na mesma noite) |
| **Mãos calejadas** | "Cortas, minas e constróis mais depressa" | `work_multiplier()` ×1.45 |
| **Silêncio** | "Os outros confiam mais cedo em ti" | valência social +0.12 (0.644 → 0.764) |

---

## 7. O mundo

Soma de ruídos, determinística a partir da semente:

```
continente (21 m) → colinas → detalhe → vales de rio → caminho sinuoso
```

Onze biomas decididos por altitude, declive, humidade e temperatura: areia, prado, bosque,
floresta, rocha, neve, pântano, deserto, badlands, savana e terra nua. A forma do terreno
(domain warping + erosion) é desacoplada do bioma (estilo Minecraft 1.18); a distribuição
exata depende da semente.

(A neve está calibrada para aparecer só muito longe; com a semente atual não aparece na
zona jogável.)

Chunks de 48 m com três níveis de detalhe; só o anel mais próximo tem `HeightMapShape3D`.
A vegetação vive em `MultiMeshInstance3D` com cor por instância. Números medidos no arranque:
49 chunks, 4 810 nós colhíveis, 10 379 instâncias de vegetação, ~34 amostras de terreno/ms.

**Nada é quadrado.** O terreno é uma malha irregular **sem saia** (a parede vertical à volta
de cada chunk foi removida — era visível de ângulos baixos e debaixo de água), as árvores são
construídas a partir de uma tabela de espécies (tronco + copas) e o caminho é uma curva senoidal
explícita, não uma textura.

---

## 8. O dia

`DAY_SECONDS = 600` — dez minutos por dia, quatro fases:

| Fase | Horas | O que muda |
|---|---|---|
| `dawn` | 5 → 8 | a luz sobe, o medo dissipa-se |
| `day` | 8 → 18 | exploração livre |
| `dusk` | 18 → 20.5 | aviso, os NPCs recolhem |
| `night` | 20.5 → 5 | medo acumula, criaturas aparecem |

---

## 9. Cadeia de objetivos

Não há lista de missões. Há uma sequência que se descobre a jogar:

```
wood (8) → campfire (1) → light (1) → survive (1) → talk (1)
```

Cada passo ensina uma mecânica e desbloqueia o seguinte. Contadores via `Game.bump(key)`.

---

## 10. Quatro bugs que só se viam a jogar

Todos medidos com `tests/diag.gd`, todos silenciosos (nenhum dava erro):

| Sintoma | Causa medida | Correcção |
|---|---|---|
| W/S/A/D todos ao contrário (dot = −1.00) | `Vector3(s, 0, f)` usava **+Z** como frente; em Godot a frente é **−Z**. E `get_axis` recebe (negativo, positivo) — trocar a ordem inverte o eixo | `_wish_direction()` reescrito, medido tecla a tecla |
| Chão às escuras, céu normal | `world.gd` punha o sol em `dir * 200` quando `dir` é a direção para onde a luz **viaja**: o nó ficava a **−67 m**, a iluminar o mundo por baixo | `-dir * 200` |
| Árvores pretas | `_offset()` lia as cores com `int(order[k])`; as malhas não são indexadas, `int(Vector3)` devolve 0 e **todas as copas ficavam pretas** | `SurfaceTool.append_from` |
| Não se viam casas | o spawn saía à volta da **origem**, a ~96 m da aldeia | `_pick_spawn()`: 20-32 m do centro, fora do anel das fogueiras |

E um quinto que estava lá desde o início: `st.get_vertex_count()` devolve 0, por
isso os **384 triângulos da saia do terreno apontavam todos para os vértices 0-3**
do canto do chunk. Lixo degenerado, mais 768 vértices órfãos por chunk.

Duas lições que ficam como regra:

- **`:=` sobre qualquer expressão dinâmica é erro de parse em Godot 4.7**, não um
  aviso. Inclui `for x in [1.0, 2.0]` (o `x` é Variant) e qualquer acesso a um
  `Node` não tipado.
- **Uma lambda GDScript captura variáveis por valor.** `contador += 1` dentro
  dela não avança nada lá fora — usar um Array de um elemento.

---

## 11. O que está por fazer

Por ordem de prioridade, com a razão:

1. **Cozinha, pesca e carpintaria como estações reais.** Já existem as bancadas
   (`structures.stations_near`); faltam as receitas ligadas a elas. É *Profundidade* a
   partir de peças que já existem — o caso mais barato de LEGO.
2. **Mais aldeões com agenda própria.** O ciclo de 7 passos já existe; falta rotina diária
   (trabalhar, comer, dormir) e memória de longo prazo persistida.
3. **Zonas urbanas no gerador.** O caminho já existe como curva; falta densidade à volta
   dele e um segundo pólo para dar destino à exploração.
4. **Água atravessável e margens de saída.** Já existe natação; faltam rios com margens
   navegáveis e uma saída consistente quando o jogador cai em zonas profundas.
5. **Segunda língua dos NPCs.** O texto PT/EN existe e alterna em jogo (`F2`); falta voz.

O que **não** entra por enquanto: mais biomas, mais espécies, mais mobs. Variedade e
Quantidade estão no fim da lista por decisão, não por esquecimento.

---

## 12. Direção audiovisual

O mundo e a arquitetura continuam em 3D estilizado, com materiais toon, cores pintadas e
formas legíveis. Pessoas, criaturas e animais ficam em sprites 2D integrados como billboards;
o terreno, a vegetação, os objetos e as construções continuam em 3D. A câmara começa em
A câmara começa em 1.ª pessoa, com mãos e ferramenta equipadas visíveis; `V` mantém a opção
de câmara externa. O avatar Blessed 2D continua disponível mas fica oculto por omissão. A
substituição experimental de *Come to Me* está desligada e não entra na apresentação atual.

A música é original e sintetizada no próprio jogo: camadas harmónicas suaves e um motivo
melódico curto acompanham quatro estados — alvorada, dia, crepúsculo e noite. Os temas
mudam com transições longas, deixando espaço para passos, ferramentas, água, fogo, vento e
criaturas. As referências servem como orientação de atmosfera e acabamento, não como fonte
de melodias, personagens ou assets copiados.

O céu usa três panorâmicas ilustradas CC0 para dia, alvorada/crepúsculo e noite, reduzidas a
2K com mipmaps. O shader substitui o disco solar/lunar gravado nas imagens por discos ligados
ao ciclo real de luz; uma fase lunar muda ao longo de 28 dias. As nuvens combinam essas
formas pintadas com uma camada discreta de duas escalas, deslocada a velocidades diferentes
num passe a quarto da resolução. A radiância atualiza incrementalmente e os parâmetros do
ciclo sincronizam até cinco vezes por segundo. Poeira e pirilampos usam sprites CC0 em
billboards leves; densidade continua ligada ao perfil de qualidade. Ver medidas e contagens
em [`MODEL_SCALE_GUIDE.md`](MODEL_SCALE_GUIDE.md).

---

## 13. Interface e ações do mundo

A interface de jogo deve priorizar sinais visuais estáveis: ícones desenhados pelo próprio
jogo, quantidades curtas, item selecionado e um único alvo contextual. O menu da mochila e o
menu da bancada são superfícies separadas; comida pode ser consumida na mochila e os outros
itens podem ser enviados para o espaço rápido selecionado.

Ações seguem o peso do objeto. `F` colhe plantas e frutos num gesto; árvores e rochas pedem
manter o botão esquerdo e recebem impactos repetidos. Ferramentas certas aceleram o trabalho,
o progresso fica visível, árvores tombam no golpe final e entram no ciclo de respawn do mundo.
Madeira, ramos, folhas e frutos nascem como pickups no local; só entram na mochila quando o
jogador se aproxima e os recolhe. Três folhas podem ser transformadas em fibra à mão.

Esta é uma passagem de gameplay. Os pickups ainda usam malhas provisórias do Blessed, não os
modelos Blender finais. A árvore abatida ainda não se parte num tronco persistente; ferramentas
não têm durabilidade; as margens dos rios precisam de uma rota de saída mais previsível. Estes
sistemas devem crescer a partir das mesmas regras de alvo, custo, feedback e consequência, em
vez de acrescentarem prompts duplicados.
