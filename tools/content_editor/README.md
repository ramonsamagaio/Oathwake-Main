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
- `res://data/terrain_types.json`
- `res://data/sprites.json`

Atualmente Items, Resources, Monsters, Recipes, Terrain Types, NPCs e Sprites aparecem na navegacao. Sprites tem cadastro visual com preview simples, segmentacao por categoria, suporte inicial a `single_sprite` e `sprite_sheet`, e Items/Resources/Monsters/Recipes/Terrain Types/NPCs podem apontar para `sprite_id`.

O painel direito mostra o arquivo atual e tem botoes para salvar, recarregar a secao atual e atualizar o ContentDB. Ao salvar, o editor cria backup em `user://content_backups`.

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

### Terrain Type

1. Clique em **Terrain Types**.
2. Selecione `grass`.
3. Altere `Display Name`.
4. Clique em **Save**.
5. Crie `dark_forest` com **New** e salve.
6. Reabra o editor e confirme que `dark_forest` continua na lista.

### Sprite

1. Clique em **Sprites**.
2. Crie `wood_icon` com **New**.
3. Use **Browse...** para escolher um PNG ou outra textura dentro de `res://`.
4. Clique em **Save**.
5. Reabra o editor e confirme que o sprite continua na lista.
6. Use o filtro de categoria para separar `item`, `monster`, `tileset` e outras categorias.

### Sprite Sheet

1. Clique em **Sprites**.
2. Crie ou selecione um sprite e mude **Type** para `sprite_sheet`.
3. Use **Browse...** para escolher a textura.
4. Configure **Frame Width** e **Frame Height**.
5. Clique em **Detect Grid**.
6. Confirme que **Columns**, **Rows** e **Total Frames** foram preenchidos e que o preview mostra o grid numerado.
7. Clique em **Save**.

## Export futuro

Enquanto o editor roda dentro do Godot, ele salva em `res://data/...`.

Em um executavel exportado separado, escrita em `res://` pode nao ser adequada. Nesse caso, o plano mais seguro e migrar os dados editaveis para `user://data` ou para uma pasta externa escolhida pelo usuario.
