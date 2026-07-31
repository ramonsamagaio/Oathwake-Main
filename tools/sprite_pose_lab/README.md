# SpritePoseLab

Ferramenta interna do Oathwake para montar poses e ciclos 2D com peças rígidas, preservando a anatomia entre frames antes do pixel cleanup no Pixelorama.

## Abrir

Abra `res://tools/sprite_pose_lab/scenes/SpritePoseLab.tscn` no Godot e use **Run Current Scene** (`F6`). A cena é independente e não altera a cena principal, autoloads ou sistemas de gameplay.

## Fluxo básico

1. Escolha sul, norte, leste ou oeste.
2. Selecione cabeça, tronco, braço esquerdo, braço direito, perna esquerda ou perna direita.
3. Use **Carregar PNG** para atribuir a textura daquele membro naquela direção.
4. Ajuste posição, rotação, pivô, visibilidade e ordem Z.
5. Adicione ou duplique frames para montar poses-chave.
6. Reproduza em FPS global ou ative duração individual por frame.
7. Salve uma pose ou o ciclo completo em JSON.
8. Exporte o frame atual, todos os PNGs ou uma sprite sheet horizontal.
9. Faça o pixel cleanup no Pixelorama.

Enquanto nenhum PNG é carregado, blocos coloridos permitem testar o rig imediatamente.

## Convenções

- `left_arm` e `left_leg` representam sempre o lado esquerdo anatômico.
- A direção visual não altera os nomes anatômicos.
- A ordem de desenho é controlada por `z_index` em cada pose.
- `position` é medida em pixels em relação ao centro do canvas.
- `pivot` é medido em pixels em relação ao centro da textura.
- O snap inteiro arredonda posição e pivô.
- A pré-visualização usa filtro Nearest e zoom inteiro.
- A exportação oculta quadriculado, grade, eixos, linha dos pés e onion skin.
- Todos os frames usam o mesmo canvas, evitando tremor por recorte automático.

## Arquitetura

- `SpritePoseLab.gd`: arquivos, JSON e exportação.
- `SpritePoseLabInteraction.gd`: timeline, controles e reprodução.
- `SpritePoseLabBase.gd`: construção da interface e do viewport.
- `SpritePoseModel.gd`: formato estruturado, normalização e nomes de arquivo.
- `SpritePoseCanvas.gd`: composição dos `Sprite2D`, guias, placeholders e onion skin.
- `SpritePoseLab.tscn`: cena independente mínima.
- `example_cycle.json`: documento de exemplo sem sprites atribuídos.

As seis peças são `Sprite2D` rígidos. Não existe deformação de malha, stretch, interpolação automática ou alteração de paleta. Novos segmentos podem ser adicionados ampliando as listas de partes, os valores padrão e os controles correspondentes.

## Estrutura de um membro

```json
{
  "position": [-11.0, 1.0],
  "rotation_degrees": -8.0,
  "pivot": [0.0, 0.0],
  "z_index": 4,
  "visible": true
}
```

O formato permite que uma pessoa ou agente altere apenas valores numéricos, sem redesenhar o personagem completo.

## Limitações do MVP

- O pivô é editado numericamente, sem alça visual arrastável.
- Não há espelhamento automático, para evitar troca anatômica ou iluminação incorreta.
- Não há interpolação entre poses.
- Rotações podem criar pixels irregulares e continuam exigindo cleanup.
- Caminhos absolutos de PNG funcionam localmente. Para ciclos portáveis, coloque as peças no projeto e use caminhos `res://` no JSON.
- A ferramenta é um laboratório isolado e não cadastra os PNGs no Content Editor do jogo.
