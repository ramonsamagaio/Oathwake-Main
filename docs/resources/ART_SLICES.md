# Fatias de arte Oathwake — atualizado em 8 setembro 2026

O usuário pediu acrescentar bordas/paleta dos tiles, harmonia com props/resources, novos elementos e revisão visual geral. São trabalho autorizado, ainda pendente; os testes técnicos anteriores não significam que a direção de arte inteira foi aprovada.

## Referências de conjunto

- `docs/resources/source_copies/harmony-arid-user.png`: arquivo enviado `ChatGPT Image 7 de set. de 2026, 04_04_34.png`. Solo cinza amarronzado, caminhos em taupe, rochas quentes e frias de contraste moderado, capim seco palha, árvores mortas e arbustos retorcidos, formações minerais verticais e pedras estratificadas. Flores lilases são acentos mínimos. O chão e os objetos compartilham luz e temperatura de sombra.
- `docs/resources/source_copies/harmony-meadow-user.png`: arquivo enviado `ChatGPT Image 7 de set. de 2026, 04_04_30.png`. Areia ocre apagada, terra marrom e verdes oliva. Tons azulados nas folhagens aparecem em grupos pontuais. Caminhos e manchas têm bordas quebradas finas, reentrâncias orgânicas e textura que chega até a transição, sem um cordão uniforme contornando cada ilha.

As imagens orientam composição, proporção, cor e acabamento. Não extrair screenshots redimensionadas como tiles. Manter autoria na grade nativa pelo Pixelorama, transparência limpa e fontes PNG/PXO editáveis.

## Estado entregue

- Árvores: 41 registros integrados, copas/troncos/tocos, bases compactas de madeira sem grama anexada. Paleta e leitura conjunta ainda entram na revisão geral.
- Flora32: 12 plantas de chão sem interação, atlas nativo32×32 e teste no Godot.
- Detalhes16: PUBLICADOS, quatro flores + dezesseis folhas usadas na geração; duas folhas adicionais de reserva. `native/ground-details/runtime-qa.json`: atlas ativos conferidos, 66 células em comparação e117 posições de geração preservadas, zero falhas.
- Pedras procedurais: PUBLICADAS vinte versões (`rock1..10`, `stone1..8`, cobre e afloramento com musgo), quatro PNG/PXO nativos. `native/stones/README.md` registra autoria, comparação e sessenta instâncias testadas em três terrenos; capturas `world-0/1-after.png` mostram distribuição real. Catálogo alterado somente em vinte caminhos de textura; gameplay e escalas preservados.

## Terreno e bordas — revisão aplicada, fidelidade mantida como alvo

Aplicada a revisão de cinco atlas de solo e do atlas de estrada; fontes, comparações e testes em `docs/terrain/reference-edge-revision/README.md`. Capturas reais antes/depois usam a mesma seed e câmera. A meta expressa pelo usuário é borda idêntica à referência; a revisão aplicada não deve ser tratada como aprovação final do usuário. Água/beira-mar, barreiras de floresta e harmonia dos resources ainda exigem revisão do conjunto. Próximas fatias: resources existentes e novos elementos, preservando o alvo visual das bordas durante a revisão global.

Revisar o acabamento de areia/terra/grama e os caminhos, usando as duas imagens como alvo visual. O usuário disse explicitamente que as bordas atuais ainda não correspondem à referência: não reabrir somente uma tarefa de recoloração.

Desenhar transições irregulares finas, com pequenos recortes e continuidade de textura; eliminar cordões uniformes, escadinhas repetitivas e finais quadrados de estrada. Harmonizar as rampas de campo e ambiente árido, preservando suas diferenças. Conferir também água, detalhes e acabamentos gerados em código: não basta trocar a folha PNG quando o produtor desenha parte do resultado.

Verificar montagem de células vizinhas, centros opacos, cantos convexos/côncavos, ilhas, buracos, junções T e curvas. Manter máscaras e conectividade necessárias ao autotile. Fotografar os mesmos pontos do mundo, com a mesma seed/câmera/luz, antes e depois. Aprovação visual não pode ser substituída por hashes ou número de testes.

## Fatias seguintes — resources existentes e novos elementos

Pedras/minério da geração procedural estão aplicados; o resource genérico antigo `rock` e nós sem sprite próprio não fazem parte desses vinte registros. Próxima fatia: arbustos e coletáveis vegetais, depois flores, cogumelos, cereais e outros resources que ainda usam arte anterior. Comparar cada grupo no mesmo solo usado pelas árvores e detalhes16/32. Manter IDs funcionais, drops, vida, interação, regeneração e colisões existentes durante mudanças de arte.

Adicionar um primeiro conjunto pequeno baseado nas referências: duas árvores secas com arquiteturas diferentes, arbusto seco ramificado, tronco caído, afloramento de pedra estratificada e formação rochosa vertical. Estes seis itens são a proposta de execução da fatia, ainda não foram criados. Árvores/pedras que sejam resources devem reutilizar comportamento e balanceamento da família existente; props decorativos devem continuar sem interação. Integrar nos biomas apropriados com distribuição revisada, sem bloquear passagens ou lotar o mapa.

Nas árvores novas, projetar a separação entre base e parte superior visualmente, abaixo da massa de folhagem ou ramificação, com pivô e junção testados. Conservar base troncuda e raízes curtas, sem losango de chão. Na pedra, usar planos e fraturas legíveis, não ruído uniforme ou contraste preto exagerado.

## Última fatia — revisão visual de todo o conjunto

Reavaliar tiles, árvores, props e resources juntos em cenas reais de campo e ambiente árido. Corrigir diferenças de saturação, luminosidade, temperatura de sombra, direção da luz, densidade de textura, escala do pixel e peso dos contornos. Preservar contraste suficiente para leitura de objetos e personagem; harmonia não significa pintar todos os materiais com a mesma rampa.

Revisar nativo1×, ampliações inteiras e câmera normal do jogo; repetir células e observar densidade nos agrupamentos. Checar recortes, pixels soltos, base/chão, vento, queda, tocos, reaparecimento, profundidade e sombras quando aplicáveis. Entrega final exige captura da geração real com os novos elementos aplicados. Comparações organizadas em cenas de teste devem ser identificadas como tais.

## Execução e retomada

Checkpoint operacional: `docs/resources/native/CONTINUATION.md`; conhecimento estável: skill oathwake. O agendamento único de06:15 foi executado e excluído ao retomar em8/9/2026. Não recriar sem novo pedido. Registrar por fatia o que foi aplicado, evidência visual, limites e próxima parte; não declarar a revisão geral concluída enquanto houver assets destoando.
