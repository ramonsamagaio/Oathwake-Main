# Bordas baseadas nas referências — 8 setembro 2026

Revisão aplicada em seis PNG/PXO de `assets/sprites/world/procedural/terrain/oathwake_tilesets`: `short_grass`, `plainsgrass1`, `plainsgrass2`, `plainsgrass3`, `tall_grass` e `oathwake_road`. Os originais desta revisão estão em `before/`, com os manifestos anteriores. As novas imagens do usuário são mantidas em `docs/resources/source_copies/harmony-meadow-user.png` e `harmony-arid-user.png`.

O usuário pediu máxima fidelidade às referências, tendo como meta bordas idênticas. A comparação foi feita com recortes visuais ampliados; não declarar equivalência literal ou aprovação do usuário a partir de testes técnicos. A distribuição procedural e o formato das ilhas continuam sendo os do jogo. O ambiente árido completo e a harmonia final de todos os resources ainda pertencem às etapas seguintes.

## O que mudou

- Transições entre materiais com grupos pequenos de folhas/lascas douradas, intervalos sem destaque, sombras locais e silhuetas redesenhadas dentro das conexões do atlas. O antigo cordão verde escuro não foi simplesmente recolorido: há suavização dos dentes antigos e novos grupos de pixels no contorno.
- Rampas de areia ocre apagada, terra marrom e verdes oliva aproximadas da referência de campo. A captura real revelou excesso de destaque nas fronteiras de floresta; as duas rampas de borda de floresta foram suavizadas. São rampas por material, não seleção dinâmica por terreno vizinho.
- Estrada com quatro contornos discretamente diferentes dentro das células, mantendo exatamente a mesma faixa de conexão de dois pixels. Substituído o halo translúcido por contorno com alpha binário. Os cantos continuam arredondados e as curvas se conectam ao mesmo caminho lógico.

## Autoria e verificação

`tools/author_oathwake_reference_edges.py` usa as máscaras verificadas para reconstruir contornos e pixels na grade nativa. A primeira tentativa de acentos de borda não alcançava as franjas estreitas de muitas células (por exemplo, a máscara3 ocupa apenas as colunas13..15). Os pontos de desenho foram corrigidos para alcançar essas franjas, preservando alpha nos dois pixels de conexão. Não usar a proximidade da transparência através de células vizinhas empacotadas: elas não representam vizinhos do mundo.

Os arquivos foram criados por coordenadas no Pixelorama, salvos em PXO, reabertos e exportados. PNGs foram comparados byte a byte com a autoria. Pillow foi usado para leitura e comparações visuais, sem resize na produção. `--ground-only` ou `--road-only` limita a geração de requests; `--verify` sempre verifica os seis resultados; `--publish` aplica e atualiza os manifestos.

QA: 42.560 pixels de conexão dos cinco terrenos preservados; base6 totalmente opaca. Grupos novos precisam estar conectados à máscara existente. Os 2.048 frames da estrada passam 20 montagens de curvasU/junçõesT, incluindo todas as variantes e combinações misturadas; sem ilhas desconectadas ou pinholes. Pixels isolados e um buraco detectados em tentativas intermediárias foram corrigidos antes da publicação.

O contrato da estrada mudou: `alpha_variant_policy=identical_two_pixel_join_guard`. O alpha completo das quatro variantes pode variar, mas os dois pixels de junção são idênticos. `verify_oathwake_terrain.py` reconhece os dois contratos: versões antigas com alpha integral idêntico, e esta com contornos variáveis e junções protegidas. Não enfraquecer o teste para apenas conferir dimensões.

`OathwakeReferenceEdgesReview.gd -- --require-active`: atlas ativos, 256 máscaras, 1.572 seleções de peças, centros da estrada, mapas lógicos e colisões. `runtime-qa.json` registra o resultado. Nenhum código de produção, save, resource, drop, árvore ou geometria lógica foi alterado nesta revisão; apenas arte, ferramentas, testes e registros.

`OathwakeReferenceEdgeWorldCapture.gd` usa o mundo de produção, seed74291, câmeras(-18,-4) e(-187,29), com275 resources materializados. `world-*-before.png` e `world-*-after.png` são capturas reais; não montagens de recursos. O aviso conhecido de BuildSystem ausente aparece nos testes isolados.

`tools/review_oathwake_reference_edges.py` monta comparações de capturas: referência ampliada2×, jogo3×, ampliações inteiras identificadas. `reference-comparison.png` permite comparar borda de grama sobre areia; `world-before-after.png` preserva as capturas completas. A água/beira-mar, as estruturas de floresta e diversos resources ainda destoam das referências e devem entrar na revisão global; não confundir esta fatia de solo/estrada com a conclusão do cenário inteiro.
