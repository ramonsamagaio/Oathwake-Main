# Wyrdframe Studio: pesquisa aplicada do Pixelorama

Este documento registra o que foi estudado no repositório original do Pixelorama e quais padrões foram adotados no Wyrdframe Studio. A intenção não é copiar o Pixelorama, e sim reaproveitar decisões maduras de UX e arquitetura em um editor especializado em rig e animação por partes.

## Fontes estudadas

- `Orama-Interactive/Pixelorama/src/UI/Timeline/AnimationTimeline.gd`
- `Orama-Interactive/Pixelorama/src/Classes/Project.gd`
- `Orama-Interactive/Pixelorama/src/UI/UI.gd`
- `Orama-Interactive/Pixelorama/src/Autoload/OpenSave.gd`
- README e estrutura do repositório oficial.

## Padrões úteis encontrados

### 1. Documento central, interface reativa

O Pixelorama mantém frames, layers, seleção, FPS, caminhos e histórico no objeto `Project`, separado dos controles da interface. Alterações devem passar por métodos próprios, em vez de modificar arrays livremente.

Aplicação no Wyrdframe:

- `WyrdframeProject.gd` é a fonte de verdade;
- o canvas, a timeline e os painéis apenas editam ou exibem o documento;
- o formato `.wyrd` não depende da árvore visual da cena;
- o documento pode ser reutilizado numa futura aplicação standalone.

### 2. Timeline com dimensões ajustáveis e scroll sincronizado

O Pixelorama trata tamanho de célula, scroll horizontal/vertical, headers e divisão entre layers e frames como estado configurável. Também permite zoom das células da timeline.

Aplicação no Wyrdframe:

- timeline em matriz `bones × frames`;
- scroll horizontal e vertical;
- `Ctrl + roda` altera a largura das células;
- painéis usam splitters arrastáveis;
- offsets dos splitters e tamanho das células são persistidos em `user://wyrdframe/layout.cfg`.

### 3. Onion skin como configuração de edição

O Pixelorama separa passado e futuro, quantidade, posicionamento e opacidade. Essas configurações pertencem ao editor, não ao frame exportado.

Aplicação no Wyrdframe:

- anterior vermelho e posterior verde;
- opacidade independente;
- onion nunca aparece na exportação;
- estrutura preparada para múltiplos frames anteriores e posteriores.

### 4. Loop e playback como estados explícitos

A timeline do Pixelorama diferencia ciclo, ping-pong e reprodução sem loop, usando timer e frame canônico.

Aplicação no Wyrdframe:

- Loop, Ping-pong e Uma vez;
- FPS global ou duração individual por quadro;
- reprodução usa o mesmo estado que será rasterizado e exportado.

### 5. Arquivo de projeto com extensão própria

O Pixelorama reconhece `.pxo` como documento de projeto e diferencia abrir projeto de importar imagem.

Aplicação no Wyrdframe:

- extensão própria `.wyrd`;
- conteúdo JSON versionado e legível;
- migração do formato legado `oathwake_sprite_pose_project`;
- arquivos PNG continuam sendo referências não destrutivas.

### 6. Layout customizável

O Pixelorama usa um sistema de docks para esconder, mover e reorganizar painéis.

Aplicação nesta etapa:

- `HSplitContainer` e `VSplitContainer` nativos do Godot;
- todas as áreas principais podem ser redimensionadas por arraste;
- painéis internos têm `ScrollContainer`;
- layout é salvo e restaurado;
- a arquitetura não impede um dock system completo no futuro.

Não foi incorporado o plugin externo de docks nesta etapa. Isso evita adicionar uma dependência grande antes de estabilizar o fluxo do produto.

## Diferenças deliberadas

O Wyrdframe não é um editor de pintura genérico. Ele prioriza:

- personagem, monstro, boss ou estrutura custom;
- ações renomeáveis;
- quatro direções disponíveis em cada ação;
- bones, pivôs, constraints e hierarquia;
- rasterização pixel-perfect não destrutiva;
- presets sempre opcionais;
- customização livre em todos os níveis.

## Hierarquia de projeto adotada

```text
Projeto .wyrd
├── Rig
├── Ação: Idle
│   ├── Sul
│   ├── Norte
│   ├── Leste
│   └── Oeste
├── Ação: Walk
│   ├── Sul
│   ├── Norte
│   ├── Leste
│   └── Oeste
└── Ação: Custom
    ├── Sul
    ├── Norte
    ├── Leste
    └── Oeste
```

Cada combinação ação/direção possui seus próprios frames e sua própria biblioteca de sprites. Isso permite usar braços diferentes em ataque de arco e em ataque de espada sem duplicar o projeto inteiro.

## Próximas lições a absorver

- seleção múltipla de células;
- mover e copiar frames por drag and drop;
- tags e intervalos de animação;
- painéis destacáveis;
- sessões de backup recuperáveis;
- importadores extensíveis;
- atalhos remapeáveis;
- tabs para múltiplos projetos abertos.
