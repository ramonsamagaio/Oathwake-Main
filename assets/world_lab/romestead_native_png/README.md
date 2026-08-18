# Romestead — PNGs nativos para edição

Este pacote contém extrações lossless dos `Texture2D` XNB disponibilizados em `reference_imports/romestead_raw`.

- `sources/floors`: folhas originais de piso e autotile, sem recorte ou escala.
- `sources/props`: folhas originais de árvores, pedras, arbustos, trigo e luzes, sem recorte ou escala.
- `romestead_floors_native_atlas.png`: todas as folhas de piso reunidas sem redimensionamento.
- `romestead_props_native_atlas.png`: todos os objetos reunidos sem redimensionamento.
- `runtime/`: atlas compactos auxiliares, mantidos por compatibilidade com as primeiras versões do laboratório.
- `romestead_native_atlas_manifest.json`: dimensões, origem e retângulos exatos de cada imagem.

O tile lógico nativo é **16×16 px**. A câmera amplia a cena com filtro nearest, mas os arquivos PNG e sprites permanecem em resolução nativa.

## Arquivos usados diretamente pela cena

- Piso-base: `sources/floors/plainsgrass2.png`
- Borda verde: `sources/floors/short_grass.png`
- Borda alaranjada: `sources/floors/plainsgrass3.png`
- Tronco: `sources/props/flora_stump.png`
- Copas: `sources/props/flora_tree1.png` e `flora_tree2.png`
- Pedras: `sources/props/terrain_round_rocks_big.png` e `terrain_round_rocks_small.png`
- Vegetação ao vento: `flora_big_bushes1.png`, `flora_ground_plants.png` e `flora_wheat_animated.png`
- Mata fechada: `forest_unbreakable_bushes_bottom_.png`, `forest_unbreakable_bushes_top_.png` e `tree_wall.png`
- Fauna: `sources/wildlife` e `romestead_wildlife_native_atlas.png`, sem redimensionamento
- Novos resources: macieira, stone pine, flores, cogumelos, copper ore e mossy boulder

Edite esses PNGs diretamente no Photoshop, preservando o tamanho da folha e as posições dos sprites. Ao salvar, o Godot reimporta o arquivo e a cena passa a usar a arte personalizada sem remontar atlas manualmente.

Para reconstruir o pacote a partir das referências brutas, execute `tools/build_romestead_native_atlases.py`.
