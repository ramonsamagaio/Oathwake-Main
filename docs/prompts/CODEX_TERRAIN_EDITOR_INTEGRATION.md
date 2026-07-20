# Prompt para o Codex · validar e finalizar o Terrain Authoring do Oathwake

Você está trabalhando no repositório `ramonsamagaio/Oathwake-REPO-Main`, no branch atual. O novo pipeline de terreno **grama sobre terra** já foi adicionado. Sua tarefa é abrir o projeto no Godot 4.6.x, validar os recursos de verdade e deixar uma prova clara de que um level designer consegue criar mapas pelo editor usando Terrain Connect.

## Objetivo final

Um level designer deve conseguir:

1. abrir ou criar uma cena de mapa;
2. instanciar `res://scenes/world/terrain/OathwakeGrassDirtTerrainLayer.tscn`;
3. selecionar `Terrains` no painel do TileMap;
4. escolher o Terrain Set 0 e `Grass over Dirt`;
5. usar `Connect` para pintar transições automáticas entre grama e terra;
6. salvar o mapa com o `tile_map_data` autoral, sem geração procedural em runtime e sem alterar arquivos centrais do jogo.

## Decisão técnica já tomada

O recurso canônico de produção é **Godot nativo**, sem dependência obrigatória de plugin:

- `TileMapLayer` com tiles de **64×64**;
- Terrain Set em modo **Match Corners**;
- atlas reduzido **4×4**, contendo as 16 combinações dos quatro corners;
- shader que aplica as superfícies de grama e terra em coordenadas do mundo;
- atlas transparente separado para tufos, pedras e graminhas que avançam sobre a terra;
- grid de construções permanece **32×32**, separado deste sistema.

Os PNGs 12×4/47 tiles gerados no formato Webtyler existem somente como export de compatibilidade e pesquisa futura. **Não os transforme no fluxo principal e não crie um segundo TileSet concorrente sem necessidade comprovada.**

## Restrições arquiteturais obrigatórias

1. **Não modificar `Main`, `Player`, `Game`, `project.godot`, autoloads, boot ou `main_scene`.**
2. Não inserir lógica de terreno em scripts-base existentes.
3. Não instalar TileMapDual nem qualquer plugin como dependência obrigatória.
4. Usar `TileMapLayer`, nunca o nó legado `TileMap`.
5. Manter terreno visual 64×64 e construção/ocupação 32×32 em camadas e domínios separados.
6. Não usar escala fracionária nos tiles nem compensar erros alterando escala do node.
7. Qualquer código novo deve ficar em `scripts/world/terrain/`, `scripts/labs/` ou `scripts/test/`, conforme sua responsabilidade.
8. A cena de laboratório não pode ser carregada pelo runtime normal do jogo.
9. Não substituir nem converter automaticamente os mapas atuais. Primeiro prove o pipeline em uma cena isolada.
10. Corrija problemas dentro do novo domínio de terreno. Não espalhe remendos por sistemas não relacionados.

## Recursos canônicos já adicionados

### Componente reutilizável de produção

- `res://scripts/world/terrain/OathwakeTerrainLayer.gd`
- `res://scenes/world/terrain/OathwakeGrassDirtTerrainLayer.tscn`

### TileSet, material e shader

- `res://tilesets/terrain/terrain_grass_dirt_tileset.tres`
- `res://materials/terrain/terrain_grass_dirt_material.tres`
- `res://shaders/terrain/terrain_grass_dirt_world_space.gdshader`

### Assets funcionais

- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_mask_64.png`
- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_edge_overlay_64.png`
- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_texture_256.png`
- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_dirt_texture_256.png`

### Export opcional de compatibilidade

- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_native_47_mask.png`
- `res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_native_47_edge_overlay.png`

### Laboratório técnico já existente

- `res://scripts/labs/TerrainTechniqueLab.gd`
- `res://scenes/labs/TerrainTechniqueLab.tscn`
- `res://docs/terrain/OATHWAKE_TERRAIN_PIPELINE.md`
- `res://docs/terrain/STATIC_VALIDATION_REPORT.json`

## Trabalho solicitado

### 1. Fazer validação real no Godot 4.6.x

Importe o projeto e confirme, sem presumir:

- todos os novos `.tres`, `.tscn`, `.gd` e `.gdshader` carregam sem parse error;
- todas as referências `res://` estão resolvidas;
- `OathwakeTerrainLayer.gd` compila como `@tool` e não gera warnings repetitivos indevidos;
- o shader compila no renderer utilizado pelo projeto;
- `terrain_grass_dirt_tileset.tres` possui tile size 64×64;
- o Terrain Set 0 aparece em modo Match Corners;
- o terrain `Grass over Dirt` aparece no painel de Terrains;
- a folha 4×4 possui as 16 combinações necessárias e o Terrain Connect escolhe tiles válidos;
- o material da camada usa o atlas 4×4 de bordas correspondente ao atlas 4×4 de máscara;
- as texturas entram com nearest, sem blur e sem resize destrutivo.

Quando houver erro, corrija apenas o novo pipeline de terreno e explique a causa. Não declare sucesso baseado somente em leitura estática.

### 2. Criar uma prova autoral no editor

Crie:

- `res://scenes/labs/TerrainAuthoringLab.tscn`

Essa cena deve provar **authoring real**, não geração automática. Estrutura recomendada:

- root `Node2D`;
- uma instância de `OathwakeGrassDirtTerrainLayer.tscn` ou um `OathwakeTerrainLayer` configurado com os mesmos recursos;
- câmera própria somente para executar a cena isoladamente;
- label discreto opcional;
- nenhum vínculo com o bootstrap do jogo.

Pinte manualmente pelo Terrain Connect e salve o `tile_map_data` na própria cena. Inclua:

- uma área grande de grama;
- terra ao redor;
- pelo menos dois cantos internos;
- pelo menos dois cantos externos;
- um corredor com largura de um tile;
- uma ilha pequena de grama;
- um buraco de terra dentro da grama;
- diagonais e mudanças de direção;
- situações suficientes para exercitar as 16 combinações de corners.

**Não gere o mapa em `_ready()` e não copie a estratégia procedural de `TerrainTechniqueLab.gd` para esta cena.** O laboratório procedural serve apenas para inspeção técnica do atlas. A nova cena deve provar que o fluxo de trabalho do editor funciona.

### 3. Conferir a aparência final

Inspecione no editor e ao executar apenas a cena de laboratório:

- grama e terra permanecem contínuas em coordenadas do mundo;
- a repetição espelhada do shader não cria costura ao completar os 256 pixels;
- o padrão não reinicia visivelmente a cada tile de 64 pixels;
- a grama contém pequenas graminhas e variação compatível com a direção visual do Oathwake;
- o edge overlay desenha graminhas avançando sobre a terra;
- os detalhes da borda acompanham exatamente a máscara correspondente;
- não existem linhas pretas, bleeding entre regiões do atlas, blur ou antialias;
- a borda mantém leitura de pixel art handmade;
- mover a camada pelo mundo não faz a textura “grudar na tela”;
- zoom e iluminação atuais do projeto não exigem alterar a escala `(1, 1)` da camada.

Se houver bleeding entre células do atlas, resolva no recurso/import/shader de forma robusta. Não esconda o problema com escala, blur ou margens arbitrárias no mapa.

### 4. Confirmar o isolamento arquitetural

Verifique que:

- qualquer cena de mapa pode adicionar a cena de terreno sem tocar em arquivos-base;
- `OathwakeTerrainLayer` contém somente configuração e validação do domínio de terreno;
- não há lógica de player, save, combate, construção ou inventário nessa classe;
- props, colisão, navegação, buildings e decals permanecem em layers/nós próprios;
- a camada 64×64 não tenta administrar o grid construtivo 32×32;
- `TerrainTechniqueLab.tscn` e `TerrainAuthoringLab.tscn` não entram no jogo normal.

### 5. Validador isolado, somente se combinar com a arquitetura existente

Avalie o padrão já existente em `scripts/test/`. Se for coerente, crie:

- `res://scripts/test/TerrainPipelineValidator.gd`

Ele pode validar invariantes estáveis:

- arquivos canônicos existem;
- TileSet carrega;
- tile size é 64×64;
- material é `ShaderMaterial`;
- cena de produção instancia;
- atlas funcional e overlay têm 256×256;
- texturas de superfície têm 256×256.

Não acople esse validador a `Main`, `Player`, `Game` ou ao runtime. Só altere CI se já houver um mecanismo claramente equivalente e a mudança permanecer isolada.

## Critérios de aceite

A tarefa só está concluída quando:

1. o Godot importa e compila todos os novos recursos;
2. `TerrainAuthoringLab.tscn` foi pintada via Terrain Connect e salva com dados autorais;
3. o terrain é editável pelo painel nativo do Godot;
4. as 16 combinações não produzem buracos ou escolhas inválidas;
5. máscara, surface textures e edge overlay funcionam juntos;
6. não houve modificação em arquivos centrais ou bootstrap;
7. a documentação continua descrevendo exatamente a implementação real.

## Entrega obrigatória

Ao terminar:

- liste todos os arquivos criados e alterados;
- descreva cada correção técnica e por que ela foi necessária;
- informe o comando exato de validação utilizado;
- registre o resultado de import/parse/shader/Terrain Connect separadamente;
- inclua screenshots da cena `TerrainAuthoringLab.tscn` no editor e em execução, quando o ambiente permitir;
- declare explicitamente qualquer ponto que permaneceu sem validação;
- não diga que está pronto se o projeto não foi realmente aberto no Godot.
