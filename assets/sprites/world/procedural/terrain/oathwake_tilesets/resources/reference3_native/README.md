# Árvores da referência 3

Doze modelos reproduzidos a partir da imagem fornecida por Ramon, mantendo as posições dos pixels da fonte (1:1, sem redimensionamento). Paleta adaptada ao Oathwake, remoção do fundo/sombra cinza, limpeza de contornos e pequenos resíduos. Autoria/exportação no Pixelorama por coordenadas; PNG e projeto PXO reaberto e conferido.

- `reference3-trees`: árvores completas.
- `reference3-crowns`: copas e galhos superiores.
- `reference3-trunks`: somente troncos vivos e raízes de madeira, sem vegetação nem chão anexado.
- Cada atlas mede 768×384, seis colunas e duas linhas de quadros 128×192.
- Ordem: carvalho, faia, outono, pinheiro torto, abeto, salgueiro; palmeira, pinheiro ramificado, árvore rosa, frutífera, árvore florida, árvore azulada.
- `reference3-family.json`: origem, quadros, âncoras e cortes individuais. Copa+tronco reconstituem exatamente a árvore completa.
- `reference3-qa.json`: conferência técnica. Ela não representa aprovação artística pelo usuário.

Correção de 8 setembro: o usuário considerou grande parte das árvores aceitável, mas rejeitou os losangos de grama e os troncos verdes. Todas as doze bases foram corrigidas com contornos individuais de raiz, usando `flora_stump.png` original de Romestead como referência de terminação. Partes sombreadas de madeira agora usam exclusivamente a paleta de madeira. As âncoras acompanham a nova linha de contato das raízes, e as copas acima da região corrigida permanecem idênticas. Não adicionar um piso, ilha de grama ou musgo às bases sem um novo pedido.

Refinamento seguinte: bases mais troncudas, com madeira contínua, raízes curtas e recortes rasos. Removida a silhueta de três raízes longas e abertas. Âncoras e cortes preservados. Comparação ampliada: `docs/resources/native/stout-roots-comparison.png`.

## Integração ativa — 8 setembro

`tree2` até `tree42` agora usam `integrated-tree-crowns`, `integrated-tree-trunks` e `integrated-tree-stumps` em PNG/PXO. Cada atlas tem 41 quadros 128×192, oito colunas. `integrated-tree-manifest.json` registra modelos, variantes de paleta, espelhamento, região, âncora e pivô. São 11 desenhos-base reutilizados nas 41 variantes, com cores sazonais e espelhamento; a palmeira permanece no conjunto de referência, sem ser introduzida em um grupo de geração que antes não tinha palmeiras. Não há redução de resolução. As antigas colunas de tamanhos diferentes agora usam os modelos no tamanho nativo aprovado.

`data/resources.json` e `data/sprites.json` apontam para estes atlas. `scripts/ResourceNode.gd` aceita `canopy_pivot_offset`, compensa a posição da copa e restaura o pivô após queda/reaparecimento. O comportamento antigo permanece como padrão quando esse campo está ausente. Três linhas de madeira idênticas se sobrepõem na junção para cobrir o movimento do vento; isso não altera a aparência montada. O atlas `integrated-tree-stumps` contém os tocos cortados, com face de madeira exposta. Os atlas `reference3-*` continuam sendo os desenhos-base para edição.

Validação: `docs/resources/native/integration/static-qa.json` e `runtime-qa.json`. As 41 variantes passaram pela queda real, toco, remanescente persistente e reaparecimento; a renderização depois de reaparecer coincide pixel a pixel com a árvore intacta. Colisões, saúde, coleta, chances, tempos e demais resources permaneceram iguais ao snapshot anterior à integração. Capturas da distribuição procedural real: `docs/resources/native/integration/world-0.png` e `world-1.png`, seed74291. Para testar no Godot, executar `scripts/test/OathwakeIntegratedTreeReview.gd`; ele usa uma cena isolada sem abrir um save do jogador.
