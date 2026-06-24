# Content Editor

Ferramenta interna para editar dados de conteudo do projeto sem trocar a cena principal do jogo.

## Como abrir

1. Abra o projeto no Godot.
2. Abra `res://tools/content_editor/ContentEditor.tscn`.
3. Rode apenas essa cena com **F6**.

Tambem existe `res://tools/content_editor/ContentEditorMain.tscn`, uma cena bootstrap simples para facilitar um export separado do editor no futuro.

## Arquivos editados

- `res://data/items.json`
- `res://data/resources.json`
- `res://data/monsters.json`
- `res://data/recipes.json`

Atualmente Items e Resources tem formularios visuais completos. Monsters e Recipes ja aparecem na navegacao e podem ser expandidos com formularios especificos nas proximas etapas.

## Testes rapidos

### Item

1. Abra o Content Editor.
2. Clique em **Items**.
3. Busque `wood`.
4. Altere `Description`.
5. Clique em **Save**.
6. Rode o jogo e confirme que o conteudo ainda carrega.

### Resource

1. Clique em **Resources**.
2. Selecione `tree`.
3. Altere `Respawn Time Seconds`.
4. Clique em **Save**.
5. Rode o jogo, quebre uma arvore e confirme o tempo de respawn.

### Monster

1. Clique em **Monsters**.
2. Selecione `slime`.
3. Confirme que os dados aparecem no painel direito.

### Recipe

1. Clique em **Recipes**.
2. Selecione `workbench`, `axe`, `pickaxe` ou `bed`.
3. Confirme que os dados aparecem no painel direito.
4. Por enquanto, edicao visual detalhada de Recipes ainda deve ser adicionada em uma etapa propria.

## Export futuro

Enquanto o editor roda dentro do Godot, ele salva em `res://data/...`.

Em um executavel exportado separado, escrita em `res://` pode nao ser adequada. Nesse caso, o plano mais seguro e migrar os dados editaveis para `user://data` ou para uma pasta externa escolhida pelo usuario.
