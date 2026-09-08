# Pedras procedurais — 8 setembro 2026

Aplicados vinte sprites: `rock1..10`, `stone1..8`, `copper_ore_node` e `mossy_rock1`. Quatro atlas PNG/PXO ficam em `assets/sprites/world/procedural/terrain/oathwake_tilesets/resources/stones_native/`. Somente os vinte `texture_path` correspondentes em `data/sprites.json` foram trocados nesta fatia. Dimensões dos frames, regiões, âncoras, todos os dados de resources, colisões, drops e pools foram preservados.

## Direção e autoria

Referências: `docs/resources/source_copies/harmony-arid-user.png`, `harmony-meadow-user.png` e a prancha `reference3-user.png`. Pedras em cinza quente, planos superiores iluminados à esquerda, faces fraturadas e sombra nas junções. Cobre em pequenos veios ocres; musgo oliva nas superfícies da rocha, sem anexar um losango de chão. A primeira passagem ficou plana e foi revista com planos secundários, lascas e sombra basal antes da publicação. Esta é uma interpretação desenhada na escala original do jogo; não declarar réplica literal da referência.

`tools/author_oathwake_stones.py` descreve contornos, planos e fraturas em coordenadas inteiras. Nenhuma imagem de referência é lida para a autoria, redimensionada ou quantizada. Os 13.638 pixels opacos foram escritos pelo bridge no Pixelorama; cada PXO foi salvo, reaberto e exportado. Pillow somente verifica as imagens exportadas e cria folhas de comparação. `review.png` mostra antes/novo ampliados 2×, com a versão nativa abaixo; não usar essa folha como textura.

## Evidência

- `qa.json`: vinte sprites, quatro atlas, alpha binário, um componente conectado por sprite, RGBA exportado exatamente igual à autoria. Catálogo e resources comparados com snapshots feitos imediatamente antes desta fatia.
- `runtime-qa.json`: sessenta ResourceNodes reais, vinte modelos em areia/oliva/terra; atlas ativos idênticos, região/âncora/escala e raios de colisão mantidos. Impacto, estado coletado com colisão desativada e reaparecimento com vida/arte/colisão restaurados, sem falhas. O teste aciona o estado de coleta diretamente; não é teste de balanceamento ou sorteio de drops.
- `on-terrain-native.png`: comparação **organizada** no renderer do Godot; não representa distribuição aleatória.
- `world-0-after.png` e `world-1-after.png`: geração real de produção, seed74291, duas câmeras, 275 resources materializados. Os `before` preservam as mesmas regiões após a revisão das bordas e antes desta troca de pedras. Nenhuma sessão/save foi iniciada.

O importador adicionava RGB a pixels totalmente transparentes: 10.262 pixels afetados, nenhum pixel visível/alpha alterado. `process/fix_alpha_border=false` foi aplicado apenas nos quatro `.png.import` novos. Depois da reimportação, a comparação estrita de RGBA importado passou, inclusive na transparência. Compressão sem perda, mipmaps desligados e escala nativa mantidos.

## Reproduzir e testar

Usar o Python do bridge conforme `tools/character_pixelorama.py` e a skill oathwake:

1. `python tools/author_oathwake_stones.py`
2. `python tools/character_pixelorama.py docs/resources/native/stones/requests.json`
3. `python tools/author_oathwake_stones.py --verify`; inspecionar os exports.
4. `python tools/author_oathwake_stones.py --publish`; importar os quatro PNGs no Godot. O script também mantém as configurações dos `.import` já existentes.
5. `C:/Godot/godot.exe --path C:/Oathwake/Oathwake-Main --script res://scripts/test/OathwakeStoneReview.gd -- --require-active`
6. Captura real: mesmo comando com `res://scripts/test/OathwakeReferenceEdgeWorldCapture.gd -- --stones`.

O import geral do editor revelou um erro de resolução de classe em `tools/content_editor/ContentEditorPlayerCharacterExactSuite.gd`, dependente de `ContentEditorAlabasterPlayerSuite.gd`; esses arquivos não foram alterados nesta fatia. As cenas de revisão e o mundo procedural executaram. O aviso conhecido de BuildSystem ausente ocorre apenas no fixture isolado. Não apresentar a importação do projeto inteiro como livre de erros.

## Continuação

Esta fatia cobre os vinte resources minerais procedurais. O antigo resource genérico `rock` (`node_stonr`) e nós sem sprite próprio não foram trocados. Restam arbustos, flores/coletáveis, cogumelos, cereais, os novos elementos propostos e a revisão visual geral. As bordas foram melhoradas, mas ainda diferem da referência nos agrupamentos e na largura dos acentos; água/beira-mar e barreiras de floresta também continuam na revisão geral.
