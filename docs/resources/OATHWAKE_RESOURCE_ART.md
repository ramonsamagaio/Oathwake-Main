# Oathwake — flora e resources, 2026-09-07

> REJEITADO PELO USUÁRIO. Este documento registra a tentativa antiga por redimensionamento, não uma entrega aprovada. Suas referências de resources no catálogo foram revertidas. A correção atual está em `native/CONTINUATION.md` e `native/reference3-family.json`; não republicar estes atlas antigos.

Repaginação autorizada por Ramon com as quatro referências em `REFS/GRAMAS`, principalmente a prancha de árvores, arbustos, pedras e ervas. Esta autorização substitui a exclusão de resources da primeira etapa de terreno.

## Entrega

- `flora_ground_plants.png`: 192×64, doze plantas diferentes em células de 32×32. Rosetas, samambaias, capins curvos, folhas largas e flores pequenas. Continua usando o renderer decorativo, sem colisão nem interação.
- `resources/tree_crowns.png`: 1024×672, 41 copas/partes superiores, oito colunas de quadros 128×112. A margem transparente maior acomoda troncos inclinados sem cortar os galhos.
- `resources/tree_trunks.png`: 1024×192, 82 bases, dezesseis colunas de quadros 64×32. Para cada árvore, quadro vivo seguido pelo quadro cortado.
- Onze outros atlas: pedras grandes/pequenas, arbustos, trigo, cogumelos, flores, arbusto roxo, arbusto pequeno, cobre e rocha musgosa. Cobrem os 72 sprites consumidos pelos resources da geração.
- Quatorze pares PNG/PXO ao todo, contando flora, copas e troncos. Caminho: `assets/sprites/world/procedural/terrain/oathwake_tilesets`, com os resources na subpasta `resources/`.

O catálogo conserva todas as 41 variantes de árvore e os 72 outros resources, usando doze desenhos-base de árvores e vinte e quatro desenhos-base de resources adaptados às dimensões existentes. Nem cada variante de catálogo é um desenho-base independente. A produção mantém a diferença entre as plantas decorativas e os resources coletáveis.

## Contrato das árvores

O consumidor de produção é `scripts/ResourceNode.gd`, não o construtor decorativo de árvores da cena de laboratório. `ResourceSceneFactory` instancia a cena indicada por `data/resources.json`; `ContentDB` resolve seus registros em `data/sprites.json`.

O motor separa a **base enraizada** da **parte superior que cai**, que inclui a copa e o trecho de tronco acima do corte. A arte acompanha essa separação já existente: não se deve colocar o tronco inteiro na base estática, pois ele deixaria de participar da queda.

Cada árvore tem seus próprios `trunk_sprite_id`, `alive_trunk_sprite_id` e `stump_sprite_id`. Isso evita unir copas novas a uma única raiz genérica. `canopy_sprite_id` mantém seu identificador anterior. Anchor da parte superior `(64,112)`, anchor da base `(32,32)`, `canopy_ground_lift=-8`, offsets zerados. O topo da base viva está em y=-10 e a parte superior termina em y=-9: duas linhas idênticas se sobrepõem. A composição foi comparada pixel a pixel à árvore inteira nas 41 variantes.

`CanopyWindPivot` preserva vento/reação e queda; `TrunkSprite` mantém a base no ponto de colisão. `_apply_destroyed_stump_sprite` mostra a seção cortada; `_respawn` e `_restore_living_tree_visual` restauram a árvore e preservam o toco remanescente. Raios, drops, HP, ferramentas, respawn, chance, biomas, profundidade e regras de geração não foram alterados.

## Direção e produção

Silhuetas assimétricas, folhas em grupos, galhos expostos, raízes angulares, pedras fraturadas e flores discretas. A paleta usa os mesmos oliva/terra/pedra dos tiles, com poucos acentos de palha, cobre, vinho e violeta. A lista de cores está em `normalized-manifest.json`.

As três pranchas foram criadas com o imagegen integrado; prompts completos em `floraPrompt.txt`, `treesPrompt.txt`, `resourcePrompt.txt`, originais em `generated/`. As referências foram usadas como inspiração, sem recortar seus sprites para o jogo. O gerador entregou RGB, inclusive um fundo quadriculado nas duas primeiras pranchas: não era transparência verdadeira. O preparador Godot removeu o fundo, reduziu em nearest-neighbor para o tamanho nativo, limitou a paleta, zerou RGB transparente e dividiu os atlas. Pixelorama recebeu cada PNG normalizado, salvou PXO, reabriu esse PXO e exportou o PNG final. Os quatorze exports são idênticos ao RGBA preparado.

Scripts: `tools/prepare_oathwake_resources.py` mede e prepara os contratos; `tools/normalize_oathwake_resources.gd` faz a normalização e o recorte; `tools/character_pixelorama.py` executa as chamadas persistidas em `pixelorama-author.json`. Não reexecutar a geração/normalização por cima de futuras edições manuais. Os arquivos originais do jogo permanecem intactos; `source_copies/` guarda o catálogo anterior e a flora rejeitada.

## Validação e visualização

`tools/verify_oathwake_resources.py`: quatorze round trips RGBA, paleta e alpha binário, 41 montagens inteiras sem perda/folga, estados vivos/cortados distintos, preservação dos originais, metadados de sprites não relacionados e todos os dados de gameplay. `scripts/test/OathwakeResourceArtReview.gd`: instâncias reais dos 113 resources, queda por tween, base imóvel, troca de toco e restauração; decoração sem collider. Evidências em `asset-qa.json` e `runtime-qa.json`.

`scripts/test/OathwakeResourceWorldCapture.gd` captura a geração real, seed 74291, três regiões e 251 resources carregados. `world-0.png`, `world-1.png`, `world-2.png` são ampliações 2× nearest-neighbor de renders 800×450. Não são mockups do imagegen. A captura não abre uma sessão de jogador nem escreve saves. Render observado: Godot 4.6.3 / Vulkan Forward+.

No editor Godot, reabra a execução do jogo para o ContentDB carregar os atlas novos. Para reproduzir a revisão isolada: execute Godot com `--path C:/Oathwake/Oathwake-Main --script res://scripts/test/OathwakeResourceArtReview.gd`. Para os prints do mundo, use `OathwakeResourceWorldCapture.gd`. Não usar `--headless` para essas capturas, pois dependem de desenho real. A configuração de recursos é global no ContentDB; a chave `use_oathwake_tilesets` continua governando apenas o terreno/decoração. Exportação empacotada não foi testada nesta etapa.
