# Wayfarer — personagem da referência do Ramon

Nome de trabalho, sem alterar o personagem padrão. Atlas `assets/sprites/characters/WAYFARER.png` e fonte editável `WAYFARER.pxo`, criados com o MCP STDIO do Pixelorama/HermesBridge API 8, Pixelorama 1.1.10. Godot do projeto: 4.6; execução de revisão: 4.6.3.

## Abrir e testar

Também disponível no **Alabaster Bone Studio** (`scenes/labs/alabaster/AlabasterBoneStudio.tscn`): escolha **WAYFARER** em **Preview body** (Import/Retarget + Animator) ou em **Target figure** no **Live Tuning**. A seleção inicial permanece JUNO. O Wayfarer compartilha as 16 animações-base de JunoBase e possui namespace `wayfarer` para cópias CUSTOM salvas no Live Tuning, incluindo filtro WAYFARER. A troca pelo seletor de preview preserva a animação em edição conforme o fluxo existente. Não foi adicionada uma preferência de skin em disco: o Studio já inicia em JUNO para as demais opções.

Validador da integração: `godot --path . --script res://scripts/test/WayfarerBoneStudioValidator.gd`. Ele confere opções, troca pelos sinais dos controles, atlas por comparação dos pixels, animações, sincronização do Live Tuning e retorno a Juno/Default/JunoBase. O teste não grava cópias de animação no banco do usuário.

Abra `scenes/labs/alabaster/WayfarerReview.tscn` e pressione F6. A primeira linha é JUNOBASE; as seguintes mostram o novo personagem em oito direções, com idle, walk, run, atkSwordN1, guard e dead. O ataque mostra o corpo sem arma: a espada é equipamento externo aos recortes corporais.

Para integrar em outra cena isolada, instancie `scripts/labs/alabaster/WayfarerRig.gd`. A API de animação e direção é herdada de JunoBase. O atlas original, as cenas existentes e `project.godot` não foram editados nesta tarefa. A alteração preexistente em `project.godot` foi preservada.

## Estrutura verificada

- Canvas RGBA 144×284, 286 recortes, sem padding e sem redimensionar os pixels.
- `atlas-manifest.json` relaciona cada retângulo original 672×240 ao retângulo compactado, todos os proprietários, índice de gfx, direção, linha/pitch, frame keys, pivôs, posição do gfx, definição do nó e regras completas da textura. `atlas-regions.csv` é a versão tabular.
- O rig é `Node2D` com `Sprite2D`; calcula uma hierarquia de posições e rotações 3D e a projeta na tela. Não é um `Skeleton3D` com `BoneAttachment3D`.
- Cadeia efetiva: `WayfarerRig → AlabasterJunoBaseRig → BonesSystem → AlabasterRigRuntimeLayerGuard` e camadas herdadas de runtime. JunoBase filtra 16 animações, aplica a pose original e só depois remapeia os endereços da textura.
- O mapa JSON antigo ainda declara `data/labs/alabaster/juno_base_compact_atlas.png`; o caminho realmente carregado é a constante em `AlabasterJunoBaseRig.gd`, `assets/sprites/characters/JUNOBASE.png`. Wayfarer sobrescreve apenas o carregamento dessa textura.
- Os olhos desta seleção estão nos próprios recortes de cabeça. Não há células `eyes` entre os 286 recortes retidos. O guia antigo de quatro ciclos descreve um conjunto diferente; não use suas regiões diretamente no PNG compactado.

## Direções, pivôs e cortes

N=0°, E=90°, S=180°, W=270°. Para cada textura, `AlabasterRigRuntimeSource._select_facing_source` escolhe a coluna usando sua tabela, não a ordem visual de embalagem. No caso `FACE_16_MIRR`, as vistas N, NE, E, SE, S, SW, W, NW usam colunas 8,6,4,2,0,2,4,6; SW/W/NW usam flip horizontal. As peças FACE_8 e FACE_4 mantêm suas tabelas próprias. Limiares FACE_8 não são todos múltiplos de 22,5°: 25/70/115/160/200/245/290/335°.

Região fonte usual = origem + (coluna × largura, linha × altura). `extendX` troca os eixos de avanço. O índice da linha vem de pitch/frame keys; não representa necessariamente um frame temporal.

Pivô inicial em meios-pixels: `round(tamanho × 2 × pivot)`, ajustado por `halfX`, `flipShift` e `halfPixelShift`. Depois divide por dois. ROTATE/CUT/SCALE/PARENT podem alterar região, pivô, rotação e escala segundo a articulação. Com flip, o pivô X efetivo é `largura_região − pivot_px.x`. O offset do Sprite2D centrado é `(largura/2 − pivôX_efetivo, altura/2 − pivotY)`.

O remapeamento compacto preserva tamanho e delta interno: se o runtime recorta uma sub-região, localiza a célula fonte que a contém e translada o recorte dentro do destino. A arte deve permanecer na mesma célula; não preencher intervalos transparentes entre peças.

A escala de pixels do atlas é 1:1. A projeção usa TILE_W=24, TILE_H=16, FOV=25°, câmera X=−45° e CAMERA_SKEW=0,45 no runtime fonte. As escalas finais das peças são dinâmicas. `rig-validation.json` registra 352 amostras idle com os offsets, regiões, escala, posição, rotação, flip e Z efetivamente produzidos.

## Decisões de arte e limites

Cabelo castanho curto com mechas e novo contorno/franja; roupa azul-escura, gola e punhos claros, tirante diagonal de couro, detalhes dourados, cintura/bolsa, luvas sem dedos e botas marrons. Foram redesenhados detalhes e clusters, além da paleta. A trança e o adorno da Juno ficaram transparentes nos 12 recortes correspondentes, sem remover seus endereços ou nós.

A referência é um personagem frontal de proporção diferente. Esta adaptação mantém a anatomia esguia e os pivôs de JUNOBASE; não reproduz literalmente o volume chibi da ilustração. A bolsa e a fivela são detalhes de poucos pixels dentro das células existentes; partes MIRR conservam o espelhamento do rig. A fonte editável tem uma camada e um frame contendo o atlas inteiro, não uma sequência de animações. Isso corresponde à função do PNG.

A revisão visual inclui escala nativa e ampliação nearest-neighbor e as poses capturadas pelo próprio Godot. A validação geométrica não equivale a aprovação artística pelo usuário nem cobre as 419 animações do catálogo completo: cobre as 16 do perfil JunoBase.

## Reprodução e evidências

`tools/author_wayfarer.py` lê o original e escreve lotes de pixels em JSON. Não gera o PNG da arte. `tools/character_pixelorama.py` envia os lotes por `mcp.ClientSession` ao servidor STDIO existente do Hermes. A arte nasce numa cel vazia do Pixelorama, é salva em PXO, reaberta e exportada pela ponte. Os caminhos da instalação local estão no cliente e podem ser ajustados para outra máquina; nenhuma credencial foi copiada.

`asset-qa.json` verifica o hash RGBA após reabrir o PXO, as dimensões, alfa e preservação do PNG original. `rig-validation.json`: 6.144 poses (16 animações × 16 direções × 24 amostras), 134.784 regiões visíveis, zero divergências geométricas e zero recortes sem mapeamento. A comparação cobre visibilidade, região, offset, transform, flip e Z entre o rig original e o novo.

Comandos: `godot --headless --path . --script scripts/test/WayfarerValidator.gd`; `godot --path . res://scenes/labs/alabaster/WayfarerReview.tscn -- --motion`. As imagens de revisão são capturas do engine; o GIF é composto dessas capturas.

Procedência: referência local fornecida pelo Ramon (`Downloads/ChatGPT Image 30 de ago. de 2026, 21_11_29.png`); base e convenções do atlas JUNOBASE existente. Esta tarefa não verifica direitos de distribuição da arte original: a derivação deve continuar registrada, sem atribuir licença nova ao material-base.
