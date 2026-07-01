# AGNUS DEI - Alpha Content Lock T1/T2

Este documento trava o conteudo minimo da Alpha para evitar expansao antes de existir uma versao jogavel, vendavel e testavel.

## Regras Do Lock

- Nao apagar conteudo maior ja existente.
- Nao renomear IDs funcionando sem migracao.
- Preservar JSONs existentes.
- Ajustar JSONs apenas quando for seguro.
- Criar conteudo simples quando algo obrigatorio estiver ausente.
- Documentar mapping quando um ID equivalente ja existir.
- Nao implementar Skills.
- Nao implementar Stamina.
- Nao implementar Farming.
- Nao implementar Settlement.
- Nao implementar Boss.
- Nao implementar 7 tiers completos.
- Nao implementar biomas extras.

## Parte 1: Verificacao De Dados Existentes

Arquivos inspecionados:

- `data/items.json`
- `data/resources.json`
- `data/recipes.json`
- `data/monsters.json`

Resultado:

- A base ja possui a maior parte dos materiais, ferramentas, storage, recursos e slime.
- Foram adicionados apenas IDs obrigatorios ausentes para fechar o lock T1/T2.
- `workbench` existe como receita/building basico.
- `chest` existe como item de building e receita de workbench.
- `slime` ja possui `display_name`, `max_health`, `damage`, `base_combat`, `move_speed` e `loot_table`.

## Materials

### T1

- [x] wood
- [x] stone
- [x] fiber
- [x] fiber_cloth
- [x] basic_herb
- [x] berry
- [x] gel

### T2

- [x] oak_wood
- [x] coal
- [x] clay opcional
- [x] linen
- [x] basic_gem opcional

## Tools

### T1

- [x] wood_axe
- [x] wood_pickaxe

### T2

- [x] stone_axe
- [x] stone_pickaxe

## Weapons

### T1

- [x] wooden_sword
- [ ] crude_bow opcional

### T2

- [x] stone_sword

Mapping:

- O ID escolhido para espada T1 e `wooden_sword`.
- Nenhum ID existente precisou ser renomeado.

## Armor

### T1

- [x] cloth_armor

### T2

- [x] linen_armor

Mapping:

- `leather_armor` ja existia como armadura T2.
- `linen_armor` foi adicionada para cumprir explicitamente o lock sem remover `leather_armor`.

## Buildings

### Obrigatorios

- [x] workbench
- [x] chest

### Opcionais

- [x] oak_chest
- [ ] campfire
- [x] wooden_floor
- [x] wooden_wall

Mapping:

- `workbench` esta em `recipes.json` como building basico.
- `chest` esta em `items.json` e `recipes.json`.

## Resources

### Obrigatorios

- [x] tree
- [x] oak_tree
- [x] rock
- [x] coal_node
- [x] fiber_bush
- [x] herb_bush

Cada resource obrigatorio deve ter:

- [x] display_name
- [x] resource_tier
- [x] resource_hp
- [x] required_tool_type
- [x] skill_type, mesmo que Skills nao estejam ativas
- [x] xp_reward, mesmo que Skills nao estejam ativas
- [x] base_drops
- [x] rare_drops

## Monsters

### Obrigatorio

- [x] slime

### Opcional

- [ ] goblin
- [ ] corrupted_rat

Cada monster da Alpha deve ter:

- [x] display_name
- [x] max_health
- [x] damage/base_combat
- [x] movement speed
- [x] loot_table
- [ ] nameplate funcionando em playtest
- [ ] HP bar funcionando em playtest

## Recipes Obrigatorias

### Workbench

- [x] chest
- [x] wood_axe
- [x] wood_pickaxe
- [x] stone_axe
- [x] stone_pickaxe
- [x] cloth_armor
- [x] stone_sword

Receitas extras adicionadas para manter o loop fabricavel:

- [x] fiber_cloth
- [x] linen
- [x] linen_armor
- [x] wooden_sword

### Repair

- [x] Reparo de wood_axe.
- [x] Reparo de wood_pickaxe.
- [x] Reparo de stone_axe.
- [x] Reparo de stone_pickaxe.
- [x] `can_repair` nos itens obrigatorios.
- [x] `RepairCalculator` existente.
- [x] WorkbenchUI com fluxo de repair existente.

## Progressao Minima Desejada

1. Player comeca com maos ou ferramenta fraca.
2. Coleta wood/fiber/stone.
3. Cria workbench.
4. Cria chest.
5. Cria wood_axe/wood_pickaxe.
6. Coleta melhor.
7. Cria stone_axe/stone_pickaxe.
8. Consegue cortar oak_tree ou minerar recurso T2.
9. Luta contra slime.
10. Repara ferramenta.

## Balance Inicial

### tree

- tier 1
- hp 20 aproximado
- required_tool_type axe
- drops wood 2-4

### oak_tree

- tier 2
- hp 35 aproximado
- required_tool_type axe
- drops oak_wood 2-4

### rock

- tier 1
- hp 25 aproximado
- required_tool_type pickaxe
- drops stone 2-4

### coal_node

- tier 2
- hp 35 aproximado
- required_tool_type pickaxe
- drops coal 1-3

### Ferramentas

- wood_axe: tier 1, tool_tier 1, tool_damage 8.
- wood_pickaxe: tier 1, tool_tier 1, tool_damage 8.
- stone_axe: tier 2, tool_tier 2, tool_damage 12.
- stone_pickaxe: tier 2, tool_tier 2, tool_damage 12.

### slime

- max_health 30-40.
- low damage.
- drops gel.

## Como Testar

1. Abrir ContentEditor.
2. Confirmar itens T1/T2.
3. Confirmar resources T1/T2.
4. Confirmar recipes obrigatorias.
5. Rodar jogo.
6. Coletar wood/stone.
7. Craftar workbench/chest/ferramenta.
8. Coletar oak_wood com ferramenta compativel.
9. Matar slime.
10. Confirmar loot fisico.

## Riscos E TODOs

- Posicionar `fiber_bush`, `herb_bush` e `coal_node` no primeiro bioma caso ainda nao existam instancias em cena.
- Confirmar nameplate e HP bar do slime em playtest real.
- Confirmar que `wooden_floor` e `wooden_wall` estao acessiveis pelo fluxo atual.
- Revisar balanceamento apos um playtest completo de 30 minutos.
