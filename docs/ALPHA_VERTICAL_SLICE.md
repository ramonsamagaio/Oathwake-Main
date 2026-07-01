# AGNUS DEI - Alpha Vertical Slice

## Objetivo da Alpha

Definir que a Alpha precisa entregar uma experiencia jogavel de 30 a 60 minutos, focada em:

- Gathering.
- Inventory.
- Equipment.
- Crafting.
- Storage.
- Combat basico.
- Repair.
- Save/load.
- Primeiro bioma jogavel.
- Apresentacao visual suficiente para Steam.

A Alpha deve parecer uma fatia vertical vendavel, nao uma expansao infinita de sistemas.

## O Que Entra Na Alpha

### Player

- Movimento top-down.
- Vida.
- Ataque basico.
- Interacao.
- Inventario.
- Equipment.
- Tool slot.
- Weapon slot.
- Armor slot simples.
- Accessory slot simples.
- Save/load.

### Inventory

- Slots reais.
- Stack.
- Drag/drop.
- Botao direito.
- Drop manual.
- WorldItems.
- Magnet pickup.
- Baus independentes.
- Save/load de baus.
- Save/load de itens no chao.
- Itens quebrados identificados visualmente sem aumentar texto do slot.

### Gathering

- Tree.
- Oak Tree.
- Rock.
- Coal Node.
- Basic Herb/Fiber source.
- Regra de tool type.
- Regra de tier.
- Dano em resource.
- Drops fisicos no chao.

### Crafting

- Workbench.
- Chest.
- Wood Axe.
- Wood Pickaxe.
- Stone Axe.
- Stone Pickaxe.
- Repair basico.

### Equipment

- Weapon.
- Tool.
- Armor.
- Accessory.
- Stats de equipamento.
- Durability.
- Broken state.
- Repair.

### Combat

- 1 inimigo obrigatorio: Slime.
- 1 inimigo opcional: Goblin ou Corrupted Rat.
- Nameplate.
- HP bar.
- Floating damage.
- Crit/miss, se ja existir.
- Loot fisico no chao.

### Building

- Workbench colocavel.
- Chest colocavel.
- Opcionais: Campfire, Floor, Wall simples.

### Bioma

- Initial Forest.
- Visual dark fantasy/pixel.
- Recursos distribuidos.
- Pelo menos uma area clara de inicio.
- Pelo menos uma area com recurso T2.
- Pequeno obstaculo de progressao: recurso T2 precisa de ferramenta melhor.

### Save/load

Deve salvar:

- Player position.
- Inventory.
- Equipment.
- Durability.
- Chests.
- Itens dentro dos chests.
- WorldItems no chao.
- Resources destruidos/respawn, se ja existe.
- Buildings colocados.

## O Que NAO Entra Na Alpha

- Skills completas.
- Skills UI.
- Skill XP completo.
- Stamina.
- Farming completo.
- Settlement.
- Happiness.
- NPCs.
- Defesa de NPC.
- Boss grande.
- 7 tiers completos.
- Paper doll.
- Multiplayer.
- Quests complexas.
- Dificuldade por dia.

## Criterio De Pronto

A Alpha esta pronta quando:

1. O jogador consegue jogar 30 minutos sem erro critico.
2. Nenhum item some ou duplica em fluxo normal.
3. Save/load funciona apos coleta, craft, equipamento, bau e repair.
4. O primeiro bioma tem visual vendavel.
5. Existe uma build exportada.
6. Existem screenshots reais.
7. Existe trailer curto ou captura de gameplay.
8. A pagina Steam pode ser montada com material real.

## Checklist Final

- [ ] Inventory estavel.
- [ ] Equipment estavel.
- [ ] Gathering estavel.
- [ ] Crafting estavel.
- [ ] Chest/storage estavel.
- [ ] Durability/repair estavel.
- [ ] Combat basico estavel.
- [ ] Save/load estavel.
- [ ] First biome apresentavel.
- [ ] Build Windows exportada.
- [ ] Screenshots reais capturadas.
- [ ] Trailer curto capturado.
- [ ] Bugs criticos corrigidos.

## Nota De Escopo

- Nao implementar Skills.
- Nao criar sistemas novos nesta etapa.
- Nao alterar gameplay sem necessidade.
- Apenas documentar e, se util, criar pequenos TODOs no projeto.
