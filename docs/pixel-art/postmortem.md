# Bugs já pagos

Lista de defeitos reais deste projeto, com sintoma, causa e correção. Antes de
investigar um sintoma novo, procure aqui.

| sintoma que o cliente descreve | causa | correção |
|---|---|---|
| "o pé tá muito longe da canela, não tem contato nenhum" | arte do pé com pivô 0.70 + `ROTATE` (gira 180°) → caía 8px abaixo do dedo; e o dedo tinha componente Z para baixo | pivô 0.25, dedo só-pra-frente (`toe: (0, 1.05, 0)`), arte gravada girada 180° no atlas |
| membro fininho, some em alguns quadros | `PARENT_ROTATE_SCALE` esmagando (canela a `scale.y = 0.33`) | `PARENT_ROTATE_CUT` + célula do tamanho da distância **máxima** medida |
| ombreira torta, "braços estranhos" | ombreira com `ROTATE`, cujo pai é a clavícula → girava ~110° | `texRotate: NONE` |
| punho girado em vista de perfil | punho com `PARENT_ROTATE` → girava 270° | `NONE` |
| "coxa parece colada por cima da pelve, paper doll" | coxa com `zOrder 11` (acima da pelve 0) e contorno preto fechado no topo | coxa em z **atrás** da pelve, topo sem contorno, pelve virou cintura com abas |
| vão vazado entre as coxas | nada atrás do quadril | chapa de fundo: pelve desenhada de novo em `z=-40` |
| braço de trás na frente do da frente | `FACE_8_MIRR` → leste e oeste no mesmo tile, z estático | `FACE_8`/`FACE_8_FLIP` + `zFrames` derivado da profundidade medida |
| personagem sem perna acima do joelho | pelve ocupando as 12 linhas da célula (de -30 a -17), engolindo a coxa | pelve reduzida a 9 linhas, pivô 0.17 |
| punho maior que a cabeça | punho inchado de 10 para 12 só para fechar 1.4px de vão | massa devolvida ao antebraço (transbordo 2→5), punho de volta a 10 |
| detalhe de 3px virou caixa preta | contorno preto em peça de ≤4px | helper `nub()`, sem contorno |
| "espantalho": joelho acima do quadril | pré-rotação duplicada do assimp | detectar e zerar `_$AssimpFbx$_PreRotation` |
| ossos com o dobro do comprimento | translação duplicada do assimp | detectar e ignorar `_$AssimpFbx$_Translation` |
| até 26° de erro no retarget | rotação resolvida fora do espaço achatado em Z | swing+twist no espaço achatado (erro → 0.000°) |
| monstro abre com sprite do dummy e tem animação `idle` que ninguém criou | classe herdando de `AlabasterPlayableSkinRig` → `install_juno_gameplay()` | herdar de `AlabasterRigRuntimeSource` e **não** chamar `super._ready()` |
| a arte parecia certa e no jogo estava errada | renderizador offline aproximava `PARENT_ROTATE` recentrando a peça | porte fiel (`rt.py`), validado renderizando o dummy |

| ponto magenta na arte no jogo | pixels com alpha 253 colados sobre o fundo chroma: o Pillow mistura 1% de magenta e o keying exato não reconhece | binarizar o alpha (0 ou 255) antes de colar no atlas |
| membro virado errado só nas vistas de perfil | ângulo da coluna calculado como `v/(n-1)*180` num bloco de 8 colunas; as colunas 5-7 são o OESTE, não o norte | `deg = v*45; if deg > 180: deg = 360 - deg`, e espelhar |
| cabeça vira capacete ao girar | modelo procedural de elipse + espinhos | girar por CAMADAS recortadas do concept (cabelo / rosto / franja) |
| cabeça vira borrão ao girar | projeção cilíndrica pixel a pixel sem dado de nuca | idem |
| nuca vira dreadlock | preenchida esticando cada coluna pra baixo | preencher como massa de base arredondada, depois carimbar a textura do topo espelhada |
| rosto engole a cabeça inteira | camadas separadas por COR (mecha clara passa em teste de pele) | separar por coordenada, medida na grade |
| ombreira vira bolsa pendurada | célula de 12x12 num ombro de 10px | 10x10 com pivô baixo; acima de ~5px de altura deixa de ler como ombro |

| "está disforme, muito longe do concept" | personagem 3-6px gordo demais em TODA faixa; braço com metade da largura do torso (regra: 1/3) e zero vazio entre braço e tronco | medir largura por marco anatômico contra a referência; afinar até o braço caber em torso/3 |
| peça lê listrada, sem volume | tom claro no pixel mais à esquerda e médio no mais à direita, em toda linha — pillow shading + banding de uma vez | rampa diagonal `k = 0.62*t + 0.38*v`, com t medido dentro da LINHA |
| sprite parece adesivo com borda preta | contorno `#000` nos dois lados | selective outline: escuro só onde encontra o fundo, cor clara do corpo do lado da luz; e contorno = versão escurecida do tom mais escuro da peça |
| ombreira abre 2px de vão nos quadros de corrida | ancorada em `armL`, viajava com o balanço do braço | ancorar na CLAVÍCULA (`shoulderL`), que quase não se move |
| peça acessória aparece no lugar errado só no jogo | o renderizador offline ignorava o `pos` do gfx | implementar `gfx.pos` no porte: soma ao pos do NÓ, gira pela rotação acumulada, e só então globaliza |
| duas ombreiras de couro simétricas que o concept não tem | `armL` e `armR` apontando para o mesmo bloco | blocos diferentes por lado — é assim que o rig faz assimetria |

## Sessão do herói (escala da Juno)

| sintoma | causa | correção |
|---|---|---|
| "não parece do tamanho da Juno" | `root.pos[2]` = 1.6875 contra 1.3125 dela; a projeção é perspectiva, então o root mais alto amplia tudo em 27% | igualar o `root z` da referência ANTES de mexer em qualquer célula |
| braço na altura da orelha, mão no joelho | calibrei COMPRIMENTO de osso (batia com 1.4px de erro) em vez de POSIÇÃO projetada (errava 16px) | `layout2.py`: comparar a posição de tela média de cada nó ao longo do ciclo |
| corpo lê como adulto magro com cabeça de chibi | rig do Mixamo é anatômico — clavícula sobe, ombro no pescoço | o soquete do ombro da Juno fica 0.125 ABAIXO do peito; cravar a posição do soquete, preservando as direções dos outros ossos |
| balanço da animação vai pro lugar errado depois do retarget | troquei as DIREÇÕES de repouso, e as quaternions do Mixamo assumem a pose de repouso do Mixamo | trocar só as MAGNITUDES; direção só se crava em soquete (ombro, quadril), que não gira nada |
| cabeça enterrada no tronco, sobram 4px de peito | pivô Y da cabeça copiado da doadora (0.5) sem checar onde o NÓ cai dentro do recorte — o recorte ia do topo do cabelo até o pescoço, então o nó estava no fim, não no meio | o pivô é `linha_do_nó / altura_da_célula`; medido, 0.67 |
| membro pisca de perfil estando parado de frente | o runtime escolhe a coluna pelo YAW DO OSSO, não do personagem; num braço pendurado esse yaw é ruído (medido: face S sorteando as colunas SE e E) | membro é cilindro de 6px — as 5 colunas passam a ser iguais, mudando só o valor; o sorteio deixa de aparecer |
| braço com o dobro do comprimento | célula de 10 linhas preenchida inteira para um osso de 5.4px; com pivô Y 1.0 o `PARENT_ROTATE_CUT` não corta nada (o que está abaixo do pivô nunca é recortado) | com pivô na ponta, o comprimento do DESENHO é o comprimento do membro; desenhar só as linhas que o osso tem |
| barra marrom debaixo do queixo, peito some | cinto desenhado no torso, no abdômen E na pelve; medido, o nó do abdômen cai 3.4px abaixo do queixo | um cinto por corpo |
| sprite vira malha de linhas pretas | contorno = tom mais escuro −16; num membro de 6px isso são 2 de 6 colunas quase pretas, vezes 20 peças | −5, e só onde a peça encontra o fundo |
| reduzir a pixel art já quantizada come mecha e apaga o rosto | reduzir 30x70 para 22px de cabeça | voltar ao original em alta, refazer a média de área no tamanho alvo e só então travar na paleta (`hero/requant.py`) |
| recorte do concept vira chiado no corpo | numa peça de 8px sobram ~6 pixels úteis e o ruído do requant (pele aparecendo na braçadeira) domina | recorte ganha só onde a célula é grande (cabeça, 22px); no corpo a grade escrita à mão lê melhor |
| emenda abre de LADO, não em cima | tratei todo vão como falta de comprimento e fui alongando a arte | vão longitudinal = encurtar o osso ou transbordar na ponta; vão lateral = alargar a arte 1px de cada lado |

## Sessão do vídeo do lab (galeria em movimento)

Todos estes só apareceram vendo o lab **animado**, nunca numa pose parada.

| sintoma | causa | correção |
|---|---|---|
| "vibrante demais pra referência" | usei a Apollo como teto (Cmax 0.168). O concept do projeto tem Cmax 0.084 — **metade**. O golem jade estava com 51.5% da área acima do teto, contra orçamento de acento de 3-5% | o teto sai da IMAGEM BASE do personagem, não de uma paleta famosa. Tetos: corpo 0.072, acento 0.115 |
| dessaturar deixou tudo lavado | reduzir S em HSV **clareia** a cor em até +12.5 L*, um degrau inteiro de rampa | reduzir C em **OKLCh** (|ΔL*| ≤ 1.2), ou misturar com cinza do mesmo L* |
| "umas bolas que não parecem ser do body" | bolas de articulação: peças de 6px com contorno próprio, desenhadas no nó da junta. Em movimento, nas diagonais, a junta viaja mais que o membro e a bola se desprende | remover. Emenda se fecha com **transbordo distal da própria peça**, não com peça extra sobre a junta. Medido: sem as bolas sobrou 1px de vão no golem |
| "perna entrando na frente de braço" | `zFrames` escrito à mão. Erra o sinal em um par e só aparece numa direção específica | derivar da **profundidade de câmera medida** (`zfix.py`), limitada a ±8 |
| ...e ao derivar, o corpo inteiro embaralhou | a oscilação medida chega a ±38 e engole a diferença de zOrder entre braço (14) e perna (−4) | limitar zFrames a **metade da menor distância entre dois zOrder vizinhos**. `zFrames` resolve só esquerda/direita; hierarquia de corpo é do `zOrder` |
| "de lado parecem personagens de papel" | apertei toda peça horizontalmente no perfil, como se tudo fosse uma caixa | antropometria: tronco 50%, quadril 62%, **membro 100%**, **cabeça 130%**. Membro é cilindro: de lado tem a MESMA largura |
| cabeça de perfil "impraticável": rosto vira tira vertical | mesma causa — o rosto era comprimido em direção ao centro | o rosto **desliza** para a borda próxima e é **ocluído** pelo crânio; a cabeça **alonga** 18%; nariz e queixo de 1px na borda fecham a leitura |
| buraco retangular no meio da cabeça ao girar | a camada de cabelo tem um buraco com a forma do rosto (camadas separadas por coordenada); assim que o rosto desliza, o buraco aparece | desenhar a **massa do crânio** por baixo: silhueta cheia preenchida com a textura do cabelo, buscada em linhas de CIMA (não de baixo — abaixo não existe imagem, e o preenchimento cai num tom chapado) |
| "quadrados quando se movimentam, coisa fora do lugar" | a passada dos FBX do Mixamo é de câmera livre; nesta câmera de 45° projeta ~2x maior que a do dummy do Alabaster | **amortecer a amplitude** de rotação (Euler × k) nos nós de perna e braço: perna 0.58-0.62, braço 0.70-0.72. Mantém fase e número de quadros |
| membro pisca de perfil parado de frente | o runtime escolhe a coluna pelo yaw do OSSO; num braço pendurado esse yaw é ruído | as 5 colunas do membro passam a ser quase iguais (só valor muda) |
| silhueta do herói sem vazio entre braço e tronco | a régua estava faltando | pôr a **Juno** no teste de silhueta e na galeria do lab. A dela tem vazios visíveis; a minha não tinha |

## Sessão da comparação com a Juno

| sintoma | causa | correção |
|---|---|---|
| "os membros se confundem com o corpo" | o corpo inteiro dentro de 6 pontos de L*: tronco 32, braço 32, manga 32, calça 35, bota 29. Matiz diferente, valor igual | escada de valor explícita, retonada em OKLCh: braço 49, manga 40, tronco 28, calça 24, bota 14 |
| ...e a primeira tentativa de consertar falhou | dei ao painel do peito o mesmo tom da manga; braço e peito fundiram de novo | nenhum tom se repete entre peças que se tocam |
| "ele tá bem maior que a juno" (altura medida quase igual) | cabeça 20px sobre ombros de 15px. Na Juno a razão é 0.95; com 0.75 o busto some e o crânio domina | afastar o soquete do ombro (X 0.108 -> 0.150) e compactar o cabelo |
| cabelo lê como nuvem grande e com buracos | mechas de 1px do concept: textura em alta resolução, ruído em 20px | erodir pixels com menos de 3 vizinhos opacos, 2 passadas |
| "a bunda do golem na frente" | a pelve era desenhada como duas abas arredondadas com um vão no meio em TODAS as direções. Duas abas com vão são uma bunda, em qualquer direção | placa contínua com quilha central na frente; as duas nádegas só na coluna de costas |
| emendas reabriram depois de alargar o ombro | mexer no esqueleto move toda a cadeia distal; a arte continuou dimensionada para a cadeia antiga | rodar `seams.py` DEPOIS de toda mudança de figure, não só de arte |

## Sessão do "analise pixel por pixel"

| sintoma | causa medida | correção |
|---|---|---|
| "montagem confusa" | `px.py`: 5 tons num membro de 4px, 11 num tronco de 10px — 2 a 3× o orçamento em toda peça | gerar as peças de um estêncil com orçamento explícito (`body.py`): largura por direção da antropometria, tons de largura÷3 |
| perfil voltou a medir 10px depois de apertar o tronco | o cinto estava escrito como string fixa `".0LLLLLLLL0."` — 10px em TODAS as direções | acento tem de seguir a largura da própria linha, senão o aperto do perfil não existe |
| vão de 5.4px entre antebraço e braço, do nada | as linhas vazias de preenchimento (`tail`) iam no FIM da célula, e em peça com pivô Y 1.0 é o fim que encosta na junta — a arte ficava 4px acima do pivô | vazio vai em cima (`top`) para pivô 1.0; a arte tem de terminar na última linha |
| o pé do personagem sumia no lab | bota em L\* 12.2 contra fundo L\* 10.3 — ΔL\* 1.9 | ΔL\* ≥ 20 contra o fundo. E o concept tem a bota MAIS CLARA que a calça: eu tinha invertido a escada |
| bota clareada virou pé descalço | fui de 12 para 46, mais claro que a pele | 34, que é o valor do couro no próprio concept |
| antebraço lê como braço nu | `LEATH_HI (194,142,120) L*63.8 H44` e `SKIN_SH (196,140,108) L*63.3 H51` são a mesma cor. Qualquer valor que separava a braçadeira do tronco a jogava em cima da pele | trocar o MATERIAL: braçadeira virou azul da manga, e a mão se separa por 127° de matiz |
| toda escada de valor reprovava em algum par | tentei encaixar 6 materiais numa escada única dentro de 20 pontos de L\* | são duas cadeias independentes (braço e perna); o cinto separa. Dois problemas de 4 e 2 cabem folgados |
| mão virou bloco de pele maior que o rosto | enchi as 8 linhas da célula para fechar um vão que era LATERAL | vão lateral se fecha alargando (4→5px), não alongando |
| kobold reprovava na silhueta preta | ombro em 0.80 punha o braço encostado no tronco em toda a extensão: a mancha virava um trapézio maciço | ombro 1.45. Vão entre braço e tronco não é detalhe de sombreamento — é o que dá forma à mancha |

## A lição de método

Quase todo item acima foi **invisível no atlas** e óbvio na composição. Dois
hábitos evitam a lista inteira:

1. Compor antes de entregar, com um renderizador **validado contra o dummy**.
2. Medir antes de desenhar, e escrever o número medido no comentário.
