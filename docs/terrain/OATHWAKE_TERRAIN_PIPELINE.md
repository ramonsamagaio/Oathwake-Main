# Oathwake Terrain Pipeline

## Decisão arquitetural

O recurso canônico para criação de mapas dentro do Godot é um **Terrain Set nativo em modo Match Corners**, usando a folha 4×4 com 16 combinações e tiles de 64×64.

Isso preserva a técnica reduzida dos vídeos e combina com o padrão que o próprio projeto já usa em `tileset_standard.tres`, sem adicionar dependência obrigatória de plugin.

- Fonte visual e funcional: atlas 4×4, 64×64 por tile.
- Terrain Set: Godot nativo, `terrain_set_0/mode = 1` (`MATCH_CORNERS`).
- Camada reutilizável: `OathwakeTerrainLayer`.
- Grid de construção: continua 32×32, em sistema e camada separados.
- Webtyler 12×4: export opcional de compatibilidade, não é o recurso principal de authoring.

## Pilha visual final

1. O atlas funcional armazena máscara de grama/terra e informação de sombra/highlight nas bordas.
2. O shader preenche grama e terra em coordenadas do mundo usando texturas 256×256.
3. A repetição das superfícies é espelhada em world-space, evitando costura sem reiniciar a textura a cada tile de 64 pixels.
4. Um atlas transparente pareado devolve graminhas, musgo e pequenas pedras desenhadas sobre a borda da terra.
5. O Terrain Connect do Godot escolhe automaticamente uma das 16 combinações de corners.
6. O shader não usa `unshaded`: CanvasModulate, ciclo dia/noite e PointLight2D continuam podendo afetar o terreno.

O atlas de detalhes não é uma imagem de apresentação. Ele é amostrado pelo shader e é necessário para o visual aprovado.

## Estrutura de camadas recomendada por mapa

- `GroundBase`: piso-base opcional do bioma.
- `GroundTerrain`: instância de `OathwakeGrassDirtTerrainLayer`, pintada com Terrain Connect.
- `GroundDecals`: caminhos, rachaduras, manchas e detalhes sem colisão.
- `WorldProps`: árvores, pedras, recursos e decoração.
- `Buildings`: conteúdo do sistema de construção.
- `Collision` e `Navigation`: camadas funcionais separadas quando necessárias.

Não misture construções destrutíveis nem ocupação 32×32 dentro deste TileSet de terreno 64×64.

## Criação de mapa no Godot

1. Abra ou crie uma cena de mapa.
2. Adicione uma instância de `res://scenes/world/terrain/OathwakeGrassDirtTerrainLayer.tscn`.
3. Selecione a camada.
4. No painel TileMap, abra `Terrains`.
5. Selecione o Terrain Set 0 e `Grass over Dirt`.
6. Use Terrain Connect para pintar as formas de grama. O terreno `<any>` representa a terra/fundo.
7. Mantenha escala `(1, 1)` e posição em pixels inteiros.

## Recursos principais

- `terrain_grass_dirt_dual_mask_64.png`: atlas funcional 4×4 usado pelo TileSet.
- `terrain_grass_dirt_dual_edge_overlay_64.png`: detalhes visuais pareados com o atlas 4×4.
- `terrain_grass_texture_256.png`: superfície de grama aprovada.
- `terrain_dirt_texture_256.png`: superfície de terra correspondente.
- `terrain_grass_dirt_tileset.tres`: Terrain Set nativo e canônico.
- `terrain_grass_dirt_material.tres`: material pareado com o atlas 4×4.
- `terrain_grass_dirt_native_47_mask.png` e `terrain_grass_dirt_native_47_edge_overlay.png`: saída opcional Webtyler 12×4 para compatibilidade ou pesquisa futura.

## Importação

- Filter: Nearest.
- Mipmaps: desligados.
- Compressão: lossless.
- Sem resize na importação.
- Sem escala fracionária no node.
- Não substitua a função de UV espelhado por `fract()` simples ou por UV local do tile, pois isso reintroduziria costura/repetição a cada quadrado.

## Isolamento

Este pipeline não exige mudanças em `Main`, `Player`, `Game`, `project.godot` ou autoloads. A integração correta acontece em cenas de mapa, adicionando a camada de domínio dedicada.
