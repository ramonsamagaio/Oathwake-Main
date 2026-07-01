# Save/Load Stress Test - Alpha

Este roteiro valida que save/load da Alpha nao come item, nao duplica item e preserva metadata de durability.

## Ferramentas De Debug

- `F7`: roda `InventoryDebug.validate_full_item_state(self)`.
- `F8`: imprime estado detalhado com `InventoryDebug.print_all(self)`.
- `F9`: imprime `InventoryDebug.print_full_item_snapshot(self)`.

Fluxo recomendado:

1. Rodar `F9` antes de salvar.
2. Salvar.
3. Carregar.
4. Rodar `F9` depois de carregar.
5. Comparar snapshots.
6. Rodar `F7`.

## Teste 1 - Inventory Basico

1. Coletar wood.
2. Coletar stone.
3. Salvar.
4. Carregar.
5. Confirmar quantidades.

## Teste 2 - WorldItems

1. Quebrar tree.
2. Deixar wood no chao.
3. Salvar.
4. Carregar.
5. Confirmar wood no chao.
6. Pegar wood.
7. Confirmar que entrou no inventario.

## Teste 3 - Equipment

1. Equipar tool.
2. Equipar weapon.
3. Equipar armor.
4. Salvar.
5. Carregar.
6. Confirmar itens equipados.

## Teste 4 - Durability

1. Usar tool ate perder durability.
2. Salvar.
3. Carregar.
4. Confirmar durability preservada.

## Teste 5 - Chest

1. Colocar chest.
2. Guardar wood.
3. Guardar stone.
4. Salvar.
5. Carregar.
6. Confirmar chest, posicao e conteudo.

## Teste 6 - Dois Baus

1. Colocar dois chests.
2. Guardar itens diferentes.
3. Salvar.
4. Carregar.
5. Confirmar que os baus nao trocaram conteudo.

## Teste 7 - Repair

1. Danificar ferramenta.
2. Reparar.
3. Salvar.
4. Carregar.
5. Confirmar durability cheia.

## Teste 8 - Drop Manual

1. Dropar item do inventario no chao.
2. Salvar.
3. Carregar.
4. Confirmar item no chao.

## Teste 9 - Full Loop

1. Coletar.
2. Craftar.
3. Equipar.
4. Lutar.
5. Guardar em chest.
6. Dropar item.
7. Reparar.
8. Salvar.
9. Carregar.
10. Confirmar tudo.

## Snapshot De Itens

`InventoryDebug.get_full_item_snapshot(main)` conta:

- itens no player inventory
- itens equipados
- itens em chests
- itens no chao

Exemplo de retorno:

```json
{
	"wood": 30,
	"stone": 12,
	"wood_axe": 1
}
```

`InventoryDebug.print_full_item_snapshot(main)` imprime o snapshot ordenado por item_id.

## Validacao Completa

`InventoryDebug.validate_full_item_state(main)` valida:

1. Inventory slots.
2. Equipment slots.
3. Chest slots.
4. WorldItems.
5. Metadata de durability.
6. `storage_id` duplicado.
7. `item_id` invalido.
8. `amount` invalido.

Esta etapa e diagnostico. Nao apagar item invalido automaticamente. Nao corrigir save silenciosamente sem log. Apenas reportar.

## Como Testar

1. Rodar os 9 testes do documento.
2. Antes de salvar, printar snapshot com `F9`.
3. Depois de carregar, printar snapshot com `F9`.
4. Comparar.
5. Rodar `F7`.
6. Corrigir bugs pequenos se aparecerem.
7. Nao iniciar feature nova durante este roteiro.
