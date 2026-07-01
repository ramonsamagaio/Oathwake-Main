# DEV Notes - Aquila

## Test Checklist (pós-correção de metadata)

### 1. Durability inicial
- [ ] Adquirir uma ferramenta/arma nova → verificar durability no tooltip
- [ ] Adquirir um item sem durability → verificar que não tem metadata

### 2. Desgaste de durability
- [ ] Usar ferramenta em árvore/pedra → durability diminui
- [ ] Usar arma em monstro → durability diminui
- [ ] Tomar dano com armadura → durability da armadura diminui
- [ ] Item chegar a 0 durability → mostrar [BROKEN] no UI
- [ ] Tentar usar item quebrado → floating text "is broken!"

### 3. Reparo (Workbench)
- [ ] Abrir Workbench → aba Repair mostra itens danificados (inventário + equipment)
- [ ] Selecionar item danificado → mostra custo e durability atual
- [ ] Sem materiais → botão Repair desabilitado
- [ ] Com materiais → reparar restaura durability para 100%
- [ ] Reparo consome materiais do inventário corretamente

### 4. Equip/Unequip
- [ ] Clicar em arma/ferramenta no inventário (sozinha) → equipa no slot correto
- [ ] Clicar em armadura → equipa no slot armor
- [ ] Equipar em slot ocupado → swap preserva durability de ambos
- [ ] Unequip → item volta para o inventário com durability preservada

### 5. Transferência entre inventários (StorageUI)
- [ ] Arrastar item com durability do player para o baú → durability preservada
- [ ] Arrastar item com durability do baú para o player → durability preservada
- [ ] Right-click para mover 1 → durability preservada
- [ ] Shift+right-click para mover stack → durability preservada
- [ ] Swap drag entre slots ocupados → ambos preservam durability
- [ ] Item sem durability → funciona normalmente

### 6. Drop e pickup
- [ ] Dropar item com durability do inventário → WorldItem aparece com durability correta
- [ ] Pegar WorldItem de volta → item volta ao inventário com durability preservada
- [ ] Dropar item sem durability → funciona normalmente
- [ ] Drop via hotbar → funciona
- [ ] Drop via botão Drop no UI → funciona

### 7. Save/Load
- [ ] Salvar jogo → arquivo contém metadata nos slots
- [ ] Carregar jogo → durability dos itens preservada
- [ ] World items com durability no chão → preservados no save/load

### 8. Debug/Validação
- [ ] Chamar `InventoryDebug.print_all(get_node("/root/Main"))` no console → mostra estado completo
- [ ] Chamar `InventoryDebug.print_durability_snapshot(get_node("/root/Main"))` → mostra durability de todos os itens
- [ ] Chamar `InventoryDebug.validate_full_item_state(get_node("/root/Main"))` → sem erros
- [ ] Chamar `InventoryDebug.validate_game_state(get_node("/root/Main"))` → true

## Como chamar funções de debug no console Godot
```
var main = get_node("/root/Main")
InventoryDebug.print_all(main)
InventoryDebug.print_durability_snapshot(main)
InventoryDebug.validate_full_item_state(main)
InventoryDebug.validate_game_state(main)
```

## Arquivos modificados (última rodada)
- `scripts/systems/InventoryDebug.gd`: validadores completos
- `scripts/Inventory.gd`: `set_slot` aceita metadata, `add_item` aceita metadata, `remove_from_slot` retorna metadata
- `scripts/items/WorldItem.gd`: campo `metadata`, `setup()` aceita metadata, save/load inclui metadata
- `scripts/systems/WorldItemSpawner.gd`: spawn functions aceitam metadata
- `scripts/Main.gd`: `add_item_to_inventory` e `drop_item_near_player` aceitam metadata, load de world items inclui metadata
- `scripts/ui/StorageUI.gd`: `_move_between_inventories` preserva metadata, `_move_amount_between_inventories` preserva metadata
- `scripts/ui/InventoryUI.gd`: drop paths extraem e passam metadata
- `docs/GDD.md`: atualizado
- `docs/DEV_NOTES.md`: criado

## Padrões e convenções
- Todas as funções de spawn/drop/transfer devem aceitar `metadata: Dictionary = {}` como parâmetro opcional
- Sempre usar `set_slot` + `set_slot_metadata` para preservar metadata (nunca `set_slot` sozinho quando o item tem metadata)
- `remove_from_slot` sempre retorna metadata (mesmo que vazio)
- `add_item` com metadata só aplica a novos slots (slots existentes mantêm metadata própria)
- Items com stack_size > 1 nunca devem ter durability (tools/weapons/armor sempre stack_size = 1)
