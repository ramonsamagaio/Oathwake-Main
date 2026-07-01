\# AGENTS.md



Este projeto é um jogo 2D top-down survival/crafting em Godot 4, inspirado em Romestead, Core Keeper e Zelda clássico.



Regras obrigatórias:

\- Usar Godot 4.x.

\- Usar GDScript.

\- Não usar C#.

\- Fazer mudanças pequenas, testáveis e por etapas.

\- Não implementar multiplayer ainda.

\- Não criar sistemas gigantes de uma vez.

\- Priorizar código simples, modular e fácil de entender.

\- Sempre explicar quais arquivos foram alterados.

\- Sempre preservar cenas existentes, salvo quando eu pedir para recriar.

\- Evitar dependências externas desnecessárias.

\- Usar nomes claros: Player, World, Inventory, BuildSystem, ResourceNode, Enemy, DayNightCycle.

\- Depois de cada feature, indicar como testar dentro do Godot.



## Estado Atual

### ✅ Concluído
1. **Personagem top-down** com movimento, câmera segue, colisão
2. **Mapa** simples com tiles
3. **Interação** com árvore/pedra (ResourceNode), coleta de recurso
4. **Inventário** completo (Inventory.gd) com slots, stacking, sorting, split
5. **Sistema básico de construção** (BuildSystem)
6. **Equipamento/durabilidade**: EquipmentSystem (weapon/tool/armor/accessory/ring), durability check/reduce, BROKEN display, RepairCalculator, WorkbenchUI Craft/Repair
7. **Player combat/gathering** integrado com weapon/tool slots, Hands fallback, armor stats
8. **PlayerStatsResolver, CharacterStatusUI, ContentEditor** (armor/accessory/stats_bonus), ItemInstanceHelper
9. **InventoryDebug.gd** — validadores: `validate_equipment_slots()`, `validate_full_item_state()`, `print_durability_snapshot()`, `get_item_count_snapshot()`, `validate_game_state()`, validadores internos de metadata em slots, world items, chests
10. **Correção de metadata em transfers**:
    - `remove_from_slot()` retorna metadata, `set_slot()` e `add_item()` aceitam metadata opcional
    - WorldItem.gd: campo `metadata`, setup()/save/load/pickup com metadata
    - WorldItemSpawner.gd: spawn functions aceitam metadata
    - StorageUI.gd: `_move_between_inventories` e `_move_amount_between_inventories` preservam metadata
    - Main.gd: `add_item_to_inventory()` e `drop_item_near_player()` aceitam metadata
    - InventoryUI.gd: drop paths extraem e passam metadata
11. **Correções de tipo**: CombatCalculator.gd com tipos explícitos (`var x: float = ...`); InventoryUI.gd com `data_dict: Dictionary` para Variant casts
12. **WorldItem sprite scale = 0.5x**
13. **Drag outside inventory → drop no chão**: InventorySlot.gd sinal `drag_started`, InventoryUI.gd `NOTIFICATION_DRAG_END` + `_drop_from_slot()`
14. **Lixeira no inventário**: TrashSlot (ColorRect) com ConfirmationDialog; `mouse_filter = MOUSE_FILTER_PASS` corrigido; `_can_drop_data` checa Rect2 position corretamente
15. **Documentação**: GDD.md atualizado, DEV_NOTES.md com checklist de teste e resumo de patches

### 🔍 Aberto
- Bug: itens BROKEN ocupando 2 slots no grid (causa não identificada). Para debug: rodar `InventoryDebug.print_durability_snapshot(m)` e `InventoryDebug.print_all(m)` no console.

### Próximos passos sugeridos
- Diagnosticar bug dos 2 slots
- Expandir lixeira para equipment slots
- Testes manuais seguindo checklist em DEV_NOTES.md

