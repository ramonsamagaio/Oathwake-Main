# Laboratório de mundo procedural, iluminação e clima

Cena: `res://scenes/labs/RomesteadWorldSystemsLab.tscn`

Este laboratório permanece isolado do jogo principal. Ele reúne:

- mundo determinístico por seed com campina dourada, ilhas verdes e manchas alaranjadas;
- autotile nativo do Romestead: classificação dos oito vizinhos, tabela original de 52 quadros e composição de até três recortes por célula;
- detalhes nativos de piso (folhas e pequenos tufos), mantendo os pixels em 1:1;
- árvores compostas por tronco e copa independentes, incluindo as oliveiras claras com frutos amarelos e os ciprestes da referência;
- somente as variações cinzas das pedras arredondadas grandes e pequenas;
- arbustos, plantas e trigo presentes na referência, com rotação rígida em pivô de chão, usando a mesma soma de ondas e velocidades do Romestead;
- ausência de tapete de grama procedural sobre o piso;
- copas das árvores movidas separadamente pelo vento, mantendo troncos e pixels da base imóveis;
- iluminação temporal com `CanvasModulate`, sol, lua, sombras de silhueta projetadas a partir do pé de cada objeto e braseiros oscilantes;
- clima baseado no sistema estudado do Alabaster, com transições de sete segundos, vento, nuvens, chuva, tempestade, neve, cinzas, umidade e relâmpagos.
- transição de floresta e floresta profunda usando os campos nativos `GroundValues2` e `StructureValues2` em escala 1/64;
- mata intransponível no limite nativo `abs(StructureValues2 * GroundValues2) > 0.20`, com base, copa e colisão em camadas próprias;
- caminhos finos, flores, folhas miúdas, cogumelos e pequenas plantas de chão em TileMap, sem processo individual;
- árvores coletáveis cuja copa cai em 1,2 segundo, entrega o drop no fim e preserva o tronco cortado;
- Squirrel, Rabbit, Deer Female e Bird com animações nativas e comportamento de passeio, pausa, alerta e fuga.

Nenhum arquivo de `assets/reference_imports` é carregado diretamente. A cena usa os PNGs editáveis em `assets/world_lab/romestead_native_png/sources`; assim, alterações feitas no Photoshop aparecem depois da reimportação do Godot.

## Controles

- WASD ou setas: mover
- Shift: correr
- 1 a 6: selecionar clima
- Q/E: recuar/avançar uma hora
- T: pausar o relógio
- B: ativar/desativar a troca automática de clima
- R: gerar outro mundo

## Como testar

Abra `RomesteadWorldSystemsLab.tscn` no Godot e use **Executar cena atual** (F6). A cena não altera o mapa nem os sistemas do jogo principal.
