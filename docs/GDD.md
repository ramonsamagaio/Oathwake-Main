# Aquila - Game Design Document

## Visão geral
Aquila é um jogo 2D top-down de sobrevivência, coleta, construção e crafting, no estilo de Core Keeper e Zelda clássico.

## Referências
- Core Keeper (gameplay loop survival-crafting)
- Zelda clássico (visão top-down, itens/ferramentas)
- Romestead (estilo minimalista)
- Terraria (progressão e crafting)

## Sistemas implementados (MVP)

### Player
- Movimentação top-down com 8 direções
- Ação de ataque (espaço): dano a inimigos (usando arma equipada) e a recursos (usando ferramenta equipada)
- Floating text para dano e mensagens de item quebrado
- Fallback "hands" quando nenhuma ferramenta/arma está equipada
- Integração com EquipmentSystem: weapon slot p/ monstros, tool slot p/ recursos, armor/accessory p/ stats

### Câmera
- Segue o player com suavização (smoothing)
- Restrita aos limites do mundo

### Mapa
- TileMap com camadas de chão, decoração e colisão
- Limites de mundo definidos por TileMap

### Recursos (ResourceNode)
- Árvores (madeira) e pedras (pedra) quebradas com ferramenta adequada
- Suporta qualquer tipo configurável via ContentEditor
- Drops configuráveis (drop_item_id, drop_amount)
- Respawn automático com timer configurável

### Inventário (Inventory.gd)
- Slots com item_id, amount, metadata (durability para tools/weapons/armor)
- Suporta stack, split, move, sort
- `add_item` com suporte a metadata (preserva durability)
- `set_slot` com suporte a metadata
- `remove_from_slot` retorna metadata no dicionário
- `add_item_with_metadata` delegado a `add_item`

### Hotbar
- 5 slots visuais com atalhos 1-5
- Integrada ao sistema de ataque (usa slot selecionado)

### UI de Inventário
- Grid de slots com drag-and-drop
- Drop de itens (shift+click ou botão Drop)
- Split de stacks
- Tooltip com detalhes do item

### UI de Storage (StorageUI)
- Interface de transferência entre inventário do player e baús/containers
- Drag entre grids (preserva metadata durability)
- Right-click (move 1), shift+right-click (move stack)
- Quick stack e sort
- **Metadata preservada em todas as transferências** (corrigido)

### Crafting (WorkbenchUI)
- Sistema de receitas via RecipeBook
- Aba Craft: lista receitas que o jogador tem materiais, executa crafting
- Aba Repair: lista itens danificados no inventário e equipment slots
- **RepairCalculator**: calcula custo baseado na recipe original ou fallback por tier
- Reparo sempre 100%, custo = ceil(custo_original × repair_ratio × 0.5), mínimo 1
- Custa o mesmo tipo de material da recipe original

### Equipment System
- Slots: weapon, tool, armor, accessory
- Equipamento automático ao clicar em item equipável no inventário (quando sozinho no slot)
- Equip/unequip preserva metadata (durability)
- Suporta swap: equipar item ocupado troca os dois

### Durability
- Tools, weapons, armor, accessories têm `durability` configurável no item data
- Metadata `current_durability` é rastreada por instância
- Ao atingir 0, item fica BROKEN (não pode ser usado)
- Floating text "Tool is broken!" ou "Weapon is broken!" ao tentar usar quebrado
- Status de broken exibido no UI (label vermelha)

### Player Stats
- Base stats: HP, stamina, attack, defense, magic_defense, hit, flee, crit_chance
- Equipment bonus stats (stats_bonus) somados aos base via PlayerStatsResolver
- Exibidos na CharacterStatusUI

### WorldItem
- Itens dropados no mundo com física de magnet (atrai para o player)
- Spawn jump com animação de tween
- **Metadata preservada**: durability é mantida ao dropar e pegar de volta (corrigido)
- Save/load inclui metadata

### Save/Load
- Estado completo do jogo salvo em arquivo JSON
- Inclui inventário do player, equipment slots, baús, mundo (resources + world items + buildings)
- Equipment slots e world items preservam metadata

### Content Editor (ferramenta de desenvolvimento)
- Editor visual para adicionar/editar itens, recursos, receitas
- Suporta campos de repair_cost_multiplier, can_repair, stats_bonus, equipment slot

## Ferramentas de Debug
- `InventoryDebug.gd`: validates equipment slots, durability metadata, item state
- `validate_full_item_state()`: checa consistência de todos os slots, metadata e referências
- `validate_game_state()`: validação leve de inventário + mundo + baús

## Fora do escopo agora
- multiplayer
- mundo procedural
- sistema complexo de NPCs
- combate avançado (sistema de skills, combos)
- crafting gigante (centenas de receitas)
- arte final
- audio
