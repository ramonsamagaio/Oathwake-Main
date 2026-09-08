# Detalhes de chão — 8 setembro 2026

Publicados `flora_tiny_flowers.png/.pxo` (32×32) e `flora_tiny_ground_leaves.png/.pxo` (144×32) em `assets/sprites/world/procedural/terrain/oathwake_tilesets/`. Quatro flores, dezesseis folhagens usadas no mundo, duas folhagens na coluna9 de reserva. Células16×16, autoria por mapas explícitos de pixels no Pixelorama, sem resize das referências.

`tools/author_oathwake_ground_details.py` gera `requests.json`; `tools/character_pixelorama.py` aplica as coordenadas, salva/reabre PXO e exporta PNG. `--verify` compara RGBA exato, alpha0/255, margens transparentes e conectividade por célula; `--publish` copia PNG/PXO e atualiza apenas as duas entradas do manifesto de terreno. `before-*` preserva o passe anterior.

Organização preservada: linha0 para campo, linha1 para floresta. Nas folhas, colunas0..3 densas e4..7 esparsas; coluna8 de índice zero não é sorteada pela geração. `_draw_native_detail` mantém os ruídos, gate0.66, seeds141/141199 e frequências; `_spawn_prop(FLOOR_DETAIL)` mantém a escolha de flores versus folhas. Sem alterações no código de jogo, colisão, terreno, árvores ou resources.

QA: `qa.json` confirma os dois exports Pixelorama. `runtime-qa.json` registra atlas ativos idênticos aos revisados, 66 células comparadas sobre3terrenos e117 posições geradas pelo ruído original, inalteradas na troca antes/depois; zero falhas. O aviso conhecido de BuildSystem ausente vem da cena isolada.

Repetir: `C:/Godot/godot.exe --path C:/Oathwake/Oathwake-Main --script res://scripts/test/OathwakeGroundDetailsReview.gd -- --require-active`. O teste não usa saves de jogador. `on-terrain-native.png` é uma comparação organizada. `cluster-before-native.png` e `cluster-after-native.png` mostram o gerador de detalhes real sobre terreno de teste, com campos e floresta dispostos em duas metades; não são capturas de um mundo completo. As versões sem `-native` são somente ampliações3× do renderer.

Próxima fatia: bordas/paleta e harmonia com as duas novas referências do usuário. Plano completo em `docs/resources/ART_SLICES.md`. Essas referências tornam a revisão global ainda pendente, mesmo para famílias já aplicadas.
