# Oathwake Figure System — expansão a partir do laboratório Alabaster

## Decisão arquitetural

O runtime Alabaster não deve ficar acoplado ao player. O mesmo formato de figure descreve personagens, equipamento, projéteis, pickups e elementos de cenário animados.

A camada comum do Oathwake passa a ser tratada conceitualmente como **Figure System**.

Famílias:

1. `Character Figure`
   - player skins
   - NPCs humanoides
   - monstros compatíveis com rig articulado
   - sockets de equipamento

2. `Equipment Figure`
   - armas
   - ferramentas
   - cosméticos
   - itens de mão direita/esquerda
   - figures auxiliares de repouso/ataque

3. `Projectile Figure`
   - alta resolução direcional
   - estados de voo / stuck / spin / catch / pull / phase
   - figures reutilizáveis por armas e inimigos

4. `Environment Figure`
   - barriers
   - traps
   - crescimento de gelo/raízes/cristais
   - árvores/folhagem quando o source JSON correspondente estiver disponível

## Playable profiles nesta branch

- `juno_alabaster` → profile `juno`
- `male_dummy_alabaster` → profile `male_dummy`
- `male_temp_alabaster` → profile `male_temp`

`male_temp` reutiliza o figure/rig do `Male-Dummy` com o atlas alternativo enviado. Isso é propositalmente uma skin do mesmo topology profile; se futuramente aparecer um JSON próprio do Male, ele pode ganhar um profile independente sem alterar Character gameplay.

## Equipment

O player weapon source possui figures independentes com seus próprios pivôs, z-order, facing, frame keys e graphics.

Inventory-facing figures nesta branch:

- Sword
- Broadsword
- Hammer
- Spear
- Tonfa
- Crossbow
- Chakram
- Kama
- Bomb
- Gauntlet

Source-internal figures como `hammerBack`, `hammerStand`, `spearBack`, `gauntletPre` e `gauntletPre2` devem ser tratados como states/variants da arma e não como loot duplicado.

`tonfa` confirma dual wield real via `weaponL` + `weaponR`.

## NPC equipment

O source de NPC weapons confirma o mesmo socket model:

- fisher spears → `weaponR`
- hub halberd → `weaponR`
- Eshrin cane → `weaponL`

Logo NPC equipment deve compartilhar o mesmo attachment renderer, não ganhar um sistema paralelo.

## Projectiles

O source usa `FACE_72` para vários projéteis. Isso permite uma direção visual muito mais fina do que a necessária para a maioria dos membros do personagem.

Behaviors extraídos para o catálogo:

- `stuck`
- `catch`
- `phase`
- `spin`
- `pull`
- `rotate`
- angle presets
- floating orb

Oathwake deve separar `Projectile Motion` de `Projectile Figure State`: trajetória pertence ao gameplay; aparência/estado pertence ao Figure System.

## Held tools and cosmetics

Ferramentas comprovam que `weaponR`/`weaponL` são sockets genéricos de mão, não exclusivamente slots de arma.

Hats comprovam overlay cosmético independente, com facing próprio e z-order próprio.

## Environment figures

### Root barriers / root spike

Possuem:

- collision metadata
- states `off`, `on`, `turnOff`, `turnOn`
- animação por transform de root

Isso deve ser generalizado como `Environment Figure Actor`, permitindo collider/state machine ligados à animação da figure.

### Icicles

`icicleBig` e `icicleHuge` usam um node `top` com dezenas de graphics e uma animação `grow` que altera scale + translation.

Esse padrão é adequado para:

- cristais
- raízes
- árvores
- galhos
- flora animada
- estruturas orgânicas
- boss props

## Tree support

A sprite sheet de árvore/partes separadas observada no lote sugere fortemente o mesmo pipeline, mas **não foi fornecido neste lote um figure JSON que relacione aqueles sprites a nodes/bones/transforms**.

Portanto tree runtime não deve ser inventado a partir da imagem. O catálogo marca essa integração como `awaiting_source_figure_json`.

## Regra de implementação

Dados de source devem ser preservados em uma biblioteca separada da lógica de gameplay. O Oathwake pode reinterpretar gameplay, mas deve manter como metadata de figure:

- nodes / parent hierarchy
- gfx pieces
- sprite sheet + source range
- pivot
- z-order
- facing mode
- pitch rows
- frame keys
- animation transforms
- collision metadata quando existir

Assim a mesma ferramenta de Bone Studio pode futuramente editar Character Figures e Environment Figures sem duplicar o editor.
