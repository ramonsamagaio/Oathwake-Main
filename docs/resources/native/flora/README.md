# Flora ground plants — 8 setembro 2026

Fatia: doze plantas decorativas sem interação, no atlas ativo `assets/sprites/world/procedural/terrain/oathwake_tilesets/flora_ground_plants.png`, com PXO editável ao lado. As árvores integradas anteriormente foram preservadas.

Desenho em coordenadas inteiras na grade nativa de 32×32, enviado ao Pixelorama por `pixelorama_set_pixels`, salvo em PXO, reaberto e exportado. Não há resize ou amostragem das referências na autoria. A referência `docs/resources/source_copies/reference3-user.png` orientou formas e variedade; estas plantas são interpretações na escala do atlas, não réplicas pixel a pixel daquela folha maior.

Ordem (seis colunas, duas linhas): roseta larga, samambaia, grama, urtiga, erva marfim, tufo seco; folhas longas, erva azul, trevo baixo, erva violeta, azedinha, grama curvada. Folhas oliva e flores discretas, sem placas de chão anexas. A primeira revisão de gramas e flores estava rala e recebeu mais folhas antes da publicação.

`tools/author_oathwake_flora.py` contém contornos, planos de luz e pixels das flores. A execução padrão gera `requests.json`; `tools/character_pixelorama.py` executa a autoria. `--verify` compara todos os bytes exportados com as coordenadas esperadas, alpha binário, conectividade por célula e margens. `--publish` copia os dois arquivos verificados e atualiza somente sua entrada no manifesto de terreno. `before.png/.pxo` preservam a versão substituída.

Contrato: `RomesteadBiomeWorld2D._spawn_prop` seleciona uma das doze regiões de 32×32 para `GROUND_PLANT`. `_build_wind_sprite` posiciona o sprite em (0,-16), pivô no centro inferior, sombra projetada e sway_scale0.42. Sem mudança nesse código, probabilidades, colisões ou catálogo de resources.

`qa.json`: 4.154 pixels opacos, 21 cores, uma componente conectada por planta, RGBA exato após reabrir o PXO. `OathwakeFloraReview.gd` instancia 36 plantas pelo método de produção, cobrindo doze regiões sobre areia, grama oliva e terra; confere escala, âncora, pivô e ausência de colisores. `runtime-qa.json`: zero falhas, atlas ativo confirmado. O aviso conhecido de BuildSystem ausente pertence à cena isolada de revisão.

Repetir no Godot: `C:/Godot/godot.exe --path C:/Oathwake/Oathwake-Main --script res://scripts/test/OathwakeFloraReview.gd -- --require-active`. A revisão não grava saves. `on-terrain-native.png` é captura real do renderer, com distribuição organizada para comparação, não posições sorteadas de um mundo procedural. `on-terrain.png` é ampliação exata 2×, apenas para revisão.

Próximas fatias: pequenas flores/folhas de chão, arbustos, rochas, cogumelos e demais resources ainda permanecem com artes anteriores. Esta entrega não conclui a repaginação inteira.
