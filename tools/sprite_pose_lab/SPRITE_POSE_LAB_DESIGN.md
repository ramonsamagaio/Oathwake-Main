# SpritePoseLab: visão técnica e plano de produto

Este documento registra as decisões de produto, arte e engenharia discutidas para o laboratório interno de animação do Oathwake. Ele é a referência persistente para que o projeto não dependa da memória de uma conversa.

## Missão

O SpritePoseLab deve permitir montar animações 2D top-down por partes rígidas, preservando anatomia, identidade visual e continuidade temporal. O laboratório resolve pose, rig, timing, camadas e exportação. O Pixelorama continua disponível para cleanup artístico fino.

A ferramenta deve rodar como uma cena independente dentro do projeto Godot, de maneira semelhante ao Content Editor, mas sem depender dele:

`res://tools/sprite_pose_lab/scenes/SpritePoseLab.tscn`

## Princípios não negociáveis

1. Os PNGs de origem nunca são alterados destrutivamente.
2. A composição é renderizada na resolução nativa do canvas.
3. Filtro Nearest, MSAA 2D desligado, sem blur ou antialiasing deliberado.
4. Todos os frames usam o mesmo canvas, origem e linha dos pés.
5. Esquerda e direita são anatômicas, não “frente” e “trás”.
6. Ordem visual, visibilidade, pivô e troca de sprite podem variar por frame.
7. O documento de animação é separado da interface.
8. IDs estáveis são usados no lugar de caminhos de nós da cena.
9. O formato é aberto, versionado e preparado para futura aplicação standalone.
10. Preview e exportação devem usar o mesmo renderizador.

## Modelo conceitual

### Bone

Controla transformação, parent, constraints e pontos semânticos.

### Part

É uma imagem ou região de imagem associada a um bone em uma direção.

### Layer

Define desenho, ordem, visibilidade e composição. Um bone pode futuramente controlar várias layers, por exemplo cabeça, cabelo, capacete e olhos.

### Frame

Armazena keyframes por bone. Uma célula vazia herda o último keyframe anterior.

### Clip

Sequência de frames com FPS global ou duração individual por quadro.

### Rig preset

Define hierarquia e semântica, como Humanoid Basic, quadrúpede ou boss modular.

### Animation preset

Define movimento reutilizável, como idle, walk e run. Presets avançados devem usar anchors e proporções, não somente coordenadas absolutas.

## Rig Humanoid Basic

- Root
- Tronco
- Cabeça
- Braço esquerdo
- Braço direito
- Perna esquerda
- Perna direita

O Root não precisa de sprite. Os outros bones aceitam PNG por direção.

## Modo custom

O usuário pode:

- adicionar bone;
- remover bone;
- renomear;
- escolher parent;
- associar PNG;
- alterar pivô;
- bloquear bone;
- definir limites de rotação;
- marcar contato com o chão;
- animar ordem Z e visibilidade.

A ferramenta deve impedir parent circular, auto-parent e remoção do Root.

## Timeline

A timeline segue a lógica do Pixelorama:

- linhas verticais representam bones/layers;
- colunas horizontais representam frames;
- círculo azul representa keyframe;
- ponto discreto representa pose herdada;
- clique seleciona bone e frame;
- clique direito remove keyframe;
- adicionar, duplicar e remover quadros;
- primeiro, anterior, play, próximo e último;
- loop, ping-pong e reprodução única;
- FPS global ou duração individual por quadro.

Evoluções previstas:

- drag para reorganizar frames;
- seleção múltipla;
- copiar e colar células;
- exposição de sprite swap tracks;
- marcadores e intervalos de playback;
- solo, mute e lock diretamente na linha.

## Onion skin

- frame anterior em vermelho;
- frame posterior em verde;
- opacidade independente;
- sem aparecer na exportação;
- estrutura preparada para múltiplos frames anteriores e posteriores com queda progressiva.

Evoluções previstas:

- quantidade configurável;
- cores customizáveis;
- somente bone selecionado;
- somente silhueta;
- modo acessível para daltonismo.

## Gizmo

- arrastar o sprite ou alça verde move o bone;
- alça vermelha rotaciona;
- alça amarela move o pivô sem deslocar visualmente a peça;
- Alt força edição de pivô quando alças se sobrepõem;
- Shift aplica snap angular de 15 graus;
- Inspector numérico acompanha o gizmo em tempo real.

## Pipeline pixel-perfect

### Modo atual: raster nativo

1. PNGs permanecem intactos.
2. Bones movimentam partes rígidas.
3. A composição é renderizada por SubViewport no tamanho real do canvas.
4. Posição e pivô podem ser quantizados para pixels inteiros.
5. O zoom da interface é uma ampliação inteira.
6. Snapshot e exportação capturam a mesma rasterização vista no preview.

### Evolução: pixel remap assistido

Um rasterizador próprio poderá mapear cada pixel opaco da origem para o destino transformado. Estratégias planejadas:

- Crisp: prioriza contorno fino;
- Preserve Mass: reduz desaparecimento de pixels;
- Balanced: compromisso geral;
- Outline Priority: preserva bordas antes do preenchimento.

O problema matemático permanece: rotações arbitrárias fazem múltiplos pixels caírem no mesmo destino ou entre pixels. O sistema deve expor a escolha entre preservar massa, contorno e espessura, nunca prometer uma rotação perfeita.

## Importação e separação

### PNGs já separados

Fluxo preferencial e mais confiável.

### Imagem achatada

Planejado como editor não destrutivo de regiões e máscaras:

- seleção retangular;
- seleção poligonal;
- máscara pintável;
- criação de part sem modificar a fonte;
- definição imediata de pivô.

Limitação: pixels ocultos atrás de outras partes não existem na imagem achatada e precisam ser desenhados ou fornecidos separadamente.

## Presets de animação

Implementação inicial:

- Idle 4;
- Walk 4;
- Run 6.

Esses presets são bases editáveis, não animações finais AAA.

Evolução necessária para retarget de qualidade:

- anchors semânticos: pescoço, ombros, quadris e pés;
- rest pose;
- dimensões das partes;
- perfis por direção;
- transformações relativas;
- intenção como foot contact;
- variantes de sprite por ângulo.

## Recursos de qualidade previstos

### Foot lock

Mantém o pé plantado e detecta patinação.

### Motion arcs

Trajetória de mãos, pés, cabeça, arma, asa ou cauda.

### Jitter detector

Aponta deslocamentos abruptos da cabeça, root, pés e largura da silhueta.

### Silhouette compare

Compara área adicionada e removida entre frames.

### Rotation sets

Restringe ângulos a valores aprovados pelo estilo.

### Sprite variants

Permite escolher desenhos próprios para 0, 15, 30 ou 45 graus em vez de girar uma única imagem.

### Pixel correction layer

Camada raster não destrutiva por frame aplicada sobre o resultado do rig.

### Sprite swap track

Troca boca, mão, olho, asa ou qualquer part por frame.

## Undo, redo e autosave

A arquitetura usa snapshots versionados do documento para Undo/Redo e salva automaticamente em:

`user://sprite_pose_lab/autosave.json`

Evolução futura: sistema de comandos explícitos como MoveBoneCommand, AddFrameCommand e DeleteLayerCommand. Isso melhora histórico, macros, testes e controle por IA.

## Formato de documento

Formato atual:

`oathwake_sprite_pose_project`, versão 2.

Seções:

- project;
- canvas;
- rig;
- parts;
- animations;
- metadata.

O arquivo não deve salvar caminhos internos da árvore da cena como identidade. Bones usam IDs estáveis.

## Preparação para standalone

Não implementar a aplicação standalone agora. Porém, o desenvolvimento deve preservar:

- modelo de dados independente da UI;
- documento versionado;
- renderizador substituível;
- importadores e exportadores isolados;
- ausência de dependência no Content Editor;
- IDs estáveis;
- scene path independente;
- possibilidade de empacotar a cena como aplicação Godot própria.

## Roadmap sugerido

### Fase 1: editor funcional

- cena independente;
- rig Humanoid Basic;
- modo custom;
- timeline layers × frames;
- playback;
- onion anterior/posterior;
- gizmo;
- JSON;
- exportação PNG e sheet;
- autosave e Undo/Redo.

### Fase 2: produção eficiente

- copiar/colar células;
- múltiplos onion frames;
- presets com anchors;
- sprite swaps;
- motion arcs;
- foot lock;
- importação de sprite sheet;
- reordenação visual de layers.

### Fase 3: acabamento AAA

- jitter detector;
- silhouette compare;
- pixel remap assistido;
- correction layers;
- angle variants;
- validação automática de contato, volume e tremor;
- integração opcional com Pixelorama.

### Fase 4: produto independente

- empacotamento standalone;
- formatos de projeto portáveis;
- plugins/importadores;
- atalhos configuráveis;
- workspace persistente;
- documentação e distribuição.

## Definição de qualidade

O SpritePoseLab não deve substituir desenho artístico. Ele deve reduzir o espaço de erro, preservar anatomia, organizar decisões e entregar frames reproduzíveis. O resultado AAA virá da combinação de rig coerente, timing, silhueta, arcos, variantes desenhadas e cleanup consciente.
