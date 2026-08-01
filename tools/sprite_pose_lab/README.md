# SpritePoseLab

Editor interno de rig e animação 2D pixel-perfect do Oathwake.

## Abrir como programa independente dentro do projeto

Abra esta cena e pressione **F6 / Executar cena atual**:

`res://tools/sprite_pose_lab/scenes/SpritePoseLab.tscn`

Ela não depende do Content Editor e não altera a cena principal do jogo.

## Implementado nesta versão

- rig preset Humanoid Basic;
- modo custom com adição, remoção, parent e rename de bones;
- PNG separado por bone e direção;
- hierarquia real de transforms;
- gizmo de posição, rotação e pivô;
- constraints de rotação e lock;
- timeline estilo layers × frames;
- keyframes com herança da pose anterior;
- adicionar, duplicar e remover quadros;
- clips múltiplos;
- presets Idle 4, Walk 4 e Run 6;
- play, loop, ping-pong e reprodução única;
- FPS global ou duração por quadro;
- onion anterior vermelho e posterior verde, com opacidade independente;
- canvas configurável, linha dos pés, grade e eixo;
- raster nativo pixel-perfect com Nearest e MSAA desligado;
- Undo, Redo e autosave;
- salvar e abrir projeto JSON versionado;
- exportar frame, sequência PNG e sprite sheet horizontal.

## Timeline

- linhas são bones/layers;
- colunas são quadros;
- círculo azul é keyframe;
- ponto cinza é pose herdada;
- clique seleciona;
- clique direito remove a key daquela célula.

## Gizmo

- alça verde ou arrastar a peça: mover;
- alça vermelha: rotacionar;
- alça amarela: alterar pivô preservando a posição visual;
- Alt: priorizar pivô;
- Shift durante rotação: snap de 15 graus.

## Arquitetura V2

- `SpritePoseProject.gd`: documento, rig, clips, keys, presets e serialização;
- `SpritePoseCanvasV2.gd`: composição hierárquica, onion, guias e gizmo;
- `SpritePoseTimeline.gd`: matriz bones × frames;
- `SpritePoseStudioState.gd`: estado compartilhado e helpers;
- `SpritePoseStudioLayout.gd`: layout principal;
- `SpritePoseStudioPanels.gd`: inspector, viewport e timeline;
- `SpritePoseStudioInteraction.gd`: rig, playback, keys e gizmo;
- `SpritePoseStudio.gd`: arquivos, histórico, autosave e exportação;
- `SpritePoseLab.tscn`: cena independente executável.

O plano completo, as decisões técnicas e o caminho para uma futura versão standalone estão em `SPRITE_POSE_LAB_DESIGN.md`.
