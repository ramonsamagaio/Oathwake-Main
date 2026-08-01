# Wyrdframe Studio

Editor interno de rig e animação 2D pixel-perfect do Oathwake.

## Nome e extensão

- Programa: **Wyrdframe Studio**
- Projeto: `*.wyrd`
- Formato interno: JSON versionado `wyrdframe_project`, versão 3.

“Wyrd” representa destino, trama e caminhos entrelaçados; “frame” é o quadro de animação. O nome combina a identidade dark fantasy do Oathwake com a função técnica do programa.

## Abrir

Abra e execute com **F6**:

`res://tools/sprite_pose_lab/scenes/WyrdframeStudio.tscn`

O caminho antigo também continua funcionando:

`res://tools/sprite_pose_lab/scenes/SpritePoseLab.tscn`

A cena funciona separadamente do Content Editor.

## Estrutura de projeto

Um `.wyrd` representa um personagem, monstro, boss ou entidade customizada.

```text
Projeto
├── Rig
└── Ações renomeáveis
    ├── Sul
    ├── Norte
    ├── Leste
    └── Oeste
```

Cada ação e direção possui frames e sprites próprios. Ações sugeridas podem ser adicionadas sem apagar ações existentes.

## Presets disponíveis

- Idle
- Walk
- Run
- Attack 1 Handed
- Attack 2 Handed
- Attack Bow
- Attack genérico
- Cast
- Hit
- Death
- Phase
- Custom

Presets são pontos de partida editáveis. **Custom permanece disponível em todos os fluxos.**

## Entidades sugeridas

- Personagem: idle, walk, run, ataques 1H, 2H, bow e custom.
- Monstro: idle, walk, attack, hit, death e custom.
- Boss: idle, walk, attack, cast, phase, hit, death e custom.
- Custom: estrutura livre.

Adicionar uma estrutura sugerida nunca precisa apagar o conteúdo já criado.

## Interface

- painel de Projeto/Ações;
- painel de Rig;
- canvas pixel-perfect;
- Inspector;
- timeline bones × frames;
- splitters horizontais e verticais arrastáveis;
- scrollbars nas áreas de conteúdo;
- janela redimensionável com tamanho mínimo;
- layout persistido entre sessões.

## Frames

- adicionar frame vazio;
- duplicar frame resolvido;
- remover frame;
- mover frame para esquerda ou direita;
- `Insert`: adicionar;
- `Delete`: remover;
- `Alt+D`: duplicar;
- setas: navegar;
- espaço: play/pause.

## Salvamento e segurança

- `Ctrl+S`: salvar `.wyrd`;
- autosave em `user://wyrdframe/autosave.wyrd`;
- Undo/Redo;
- migração de projetos JSON legados;
- PNGs de origem nunca são alterados.

## Pesquisa de referência

As decisões absorvidas do Pixelorama e as diferenças deliberadas estão em:

`PIXELORAMA_RESEARCH.md`

A visão de longo prazo do produto continua em:

`SPRITE_POSE_LAB_DESIGN.md`
