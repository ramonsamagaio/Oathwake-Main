# Paleta: números, não gosto

Este arquivo substitui o antigo. Tudo aqui é medido — pelas paletas de
referência do Lospec, pela concept art do projeto, ou por antropometria. As
fontes estão no fim.

Ferramenta: `tools/monsters/pal.py`

```
python pal.py audit <png...>     # cores por população, croma, área acima do teto
```

## 1. O teto de croma vem da referência, não da paleta famosa

Croma é medido em **OKLCh**, não em HSV. Duas réguas:

| paleta | Cmax | p90 | mediana (por área) |
|---|---|---|---|
| Apollo (AdamCYounis) — sensibilidade Octopath | 0.168 | 0.153 | — |
| Endesga-32 — arcade, vibrante de propósito | 0.254 | 0.181 | — |
| **Concept do Oathwake (o alvo real)** | **0.084** | **0.060** | **0.033** |

O concept deste projeto é **duas vezes menos saturado que a Apollo**. Usar a
Apollo como teto teria deixado tudo vibrante demais para a referência. **O teto
sai da imagem base do personagem, não de uma paleta famosa.**

Diagnóstico que isso pegou, com número:

```
golem jade   mediana 0.088  = 2.7x o concept   -> 51.5% da área acima do teto
golem pedra  Cmax 0.194     = 2.3x o concept   -> lima como acento, quente demais
kobold       mediana 0.034  = ok
herói        mediana 0.038  = ok (a arte sai do próprio concept)
```

Tetos adotados: **corpo 0.072 · acento 0.115 · desgaste 0.082**, mais 10% de
tinta global fria. Depois disso o jade caiu de 51.5% para 3.3% de área acima do
teto — dentro do orçamento de acento de 3-5%.

## 2. Dessature em OKLCh, nunca em HSV

Reduzir S no HSV **clareia** a cor. Medido, ΔL* para uma redução de 40%:

| cor | HSV S×0.6 | HSL S×0.6 | **OKLCh C×0.6** | mix 40% cinza de mesmo L* |
|---|---|---|---|---|
| vermelho `#e43b44` | **+12.5** | +0.2 | **+1.2** | −1.7 |
| azul `#0099db` | **+9.4** | −6.7 | **−0.1** | −1.8 |
| laranja/pele `#f77622` | **+11.9** | −3.6 | **+0.9** | −0.7 |

+12.5 de L* é **um degrau inteiro de rampa**. É por isso que "dessaturei e
ficou lavado": você dessaturou e apagou o contraste ao mesmo tempo. Em OKLCh o
valor não se move (|ΔL*| ≤ 1.2).

Pelo mesmo motivo: **nunca gire o matiz em HSV com V fixo.** Um hue shift de
20° custa até ±10.7 L*.

## 3. Curva de croma ao longo da rampa

Saturação constante ao longo da rampa é a assinatura de plástico. No mundo real
a sombra é iluminada por luz indireta (croma baixo) e a alta-luz caminha para a
cor do iluminante (croma cai de novo). Medido na Apollo:

| posição na rampa | 0.0 sombra | 0.2 | 0.4 | 0.6 | 0.8 | 1.0 luz |
|---|---|---|---|---|---|---|
| % do croma de pico | **36%** | 59% | 85% | **100%** | **100%** | **76%** |

Pico entre 0.4 e 0.8. Sombra a ~36%, luz a ~76%.

## 4. Hue shifting

- **12–16° por degrau, em OKLCH.** A mediana real da Apollo é 11.3°; o teto do
  Slynyrd é 20° ("20 is about as high as I go") e ele usa rampas de 9 degraus.
- Sombra gira −15° a −30° (azul/roxo), luz +15° a +25° (amarelo/laranja).
- Rotação total por rampa de 5-6 tons: 50–90°.

## 5. Quantos tons por peça

> **n_tons ≈ largura_da_peça_px ÷ 3**, saturando em 5.

Uma banda de sombreamento precisa de ≥2px para ler como banda e não como ruído.

| peça (sprite de 46px) | largura | tons |
|---|---|---|
| tronco / roupa | 14–18px | 4–5 |
| cabeça / cabelo | 10–14px | 3–4 |
| braço | 4–6px | **2** |
| perna | 5–7px | 2–3 |
| mão, cinto, fivela | 2–3px | 1 |

Orçamento total: **12–18 cores** por personagem de 46px.

## 6. Piso de contraste de valor

O que carrega a legibilidade num sprite pequeno é a **luminância**, não o
matiz. Teste: converta para cinza; se ainda lê, o contraste está certo.

- **ΔL\* ≥ 8** entre tons vizinhos do mesmo material
- **ΔL\* ≥ 12** onde duas peças se tocam (braço distante contra tronco)
- **ΔL\* ≥ 20–25** entre a silhueta e o fundo escuro
- Pares com **ΔE\*ab < 2.3** (JND) são redundantes: funda.

## 7. Tinta global: o que amarra um elenco

Misturar **15–25%** de uma cor comum em todas as rampas (gamut masking, Gurney).
A 20% o croma cai 19% e o contraste de valor entre degraus só comprime de 13.5
para 11.5 L*. Abaixo de 10% não se percebe; acima de 30% come a rampa.

E a coesão mora **nas pontas**: na Apollo, todas as rampas convergem para croma
4.5 ± 0.6 no degrau mais escuro, e divergem no meio. Um elenco combina porque
compartilha as sombras, não os meios-tons.

## 8. Orçamento de acento

60-30-10 (dominante / apoio / acento). Num sprite de 46px, com 500–900px
opacos:

| faixa | % da área | px |
|---|---|---|
| dominante | 60% | 300–540 |
| apoio | 30% | 150–270 |
| acento | 10% | 50–90 |
| **acento realmente saturado** | **3–5%** | **20–45** |

Acento no terço superior (cabeça, gola, ombro): é onde o olho pousa numa câmera
top-down e o que sobra visível atrás de props. Nunca nos pés.

## 9. Extrair paleta de uma referência

Anti-aliasing é o inimigo: um sprite indexado de **6 cores**, reamostrado 4×,
vira **596 cores** (bicubic) ou **1034** (Lanczos).

Pipeline:

1. Descartar alpha < 255 e uma borda de 1–2px.
2. **Histograma por população, corte em 0.5–1.0%** dos pixels. Cor de AA nunca
   passa desse limiar porque só vive na borda. Num teste, o corte em 1.0%
   recuperou exatamente as 6 cores originais.
3. Fundir pares com ΔE*ab < 2.3.
4. Só então clusterizar, em **CIELAB com distância HyAB** (`|ΔL| + √(Δa²+Δb²)`),
   nunca em RGB. k-means puro inventou 2 fantasmas de borda em 6 cores.
5. Ordenar por L* e forçar a curva de croma da seção 3.

`pal.py colours()` implementa os passos 1-2.

## 10. Perfil: antropometria, e a cabeça vai ao contrário

Esta seção existe porque "de lado eles parecem personagens de papel".

| dimensão | frente | perfil | razão |
|---|---|---|---|
| ombros / tronco | 100% | 50% | **0.50** |
| quadril | 100% | 62% | **0.62** |
| braço / perna (seção circular) | 100% | 100% | **1.00** |
| **cabeça** | 100% | **130%** | **1.30** |

O tronco encolhe pela metade. **A cabeça CRESCE 30%** — o crânio é mais
comprido do que largo. Braço e perna não mudam.

O erro clássico num rig articulado por peças é aplicar o mesmo aperto
horizontal em tudo, como se toda peça fosse uma caixa vista de frente. Nesse
projeto isso produziu exatamente dois defeitos:

- membros virando tiras de 3px de lado (deviam ficar iguais);
- rosto comprimido numa faixa vertical no meio de um borrão de cabelo (a
  cabeça devia ficar mais LONGA, e o rosto devia DESLIZAR para a borda próxima
  e ser ocluído pelo crânio, não encolher para o centro).

Num sprite de 46px:

| peça | frente | perfil |
|---|---|---|
| ombros | 16px | **8px** |
| quadril | 12px | **7–8px** |
| cabeça | 10px de largura | **13px** de comprimento |
| braço | 4px | 4px |

E de perfil um braço de 4px ocupa **50%** da largura do tronco de 8px, contra
25% na frente — a receita de sombreamento da vista frontal não transporta.

### As causas do "de papel", e a correção de cada uma

| causa | correção |
|---|---|
| tronco mantido na largura frontal | reduzir para 50%. Sozinha resolve a maior parte |
| cabeça mantida na mesma largura | alongar 30% no eixo de visão, volume atrás do crânio |
| braço distante com as mesmas cores do próximo | 1–2 degraus abaixo na rampa, ΔL* 10–20. Separação por VALOR, nunca por contorno |
| peças no mesmo plano | deslocar a distante 1–2px e deixar o tronco ocluir a raiz dela |
| contorno preto uniforme de 1px | selout: cor clara do corpo do lado da luz, tom de sombra (não preto) na segmentação interna |
| pillow shading | num tronco de 8px de perfil: 2 tons, divisa vertical em 1/3 da largura |

## 11. A escada de valor é o que separa membro de corpo

Diagnóstico que custou três rodadas de "os membros se confundem com o corpo".
Medido no herói:

```
tronco (TUNIC)    L* 32
braço  (LEATHER)  L* 32   -> dL* = 0
manga  (TUNIC)    L* 32   -> dL* = 0   (era literalmente a mesma cor)
calça  (PANTS)    L* 35
bota   (BOOT)     L* 29   -> dL* = 5
```

**O corpo inteiro estava dentro de 6 pontos de L\*.** Matiz diferente, valor
igual. Num sprite de 46px o matiz não separa nada — quem separa é o valor.

A Juno resolve com uma escada explícita, de cima para baixo: cabeça clara,
**braço claro**, jaqueta escura, calça média, bota escura. Copiar a estrutura
(não o desenho) dá:

| peça | L\* alvo | contra | dL\* |
|---|---|---|---|
| gola / pano | 80 | — | acento |
| rosto | 77 | — | acento |
| braço (couro) | 49 | tronco | **21** |
| manga | 40 | tronco | **12** |
| tronco | 28 | — | a massa escura |
| calça | 24 | tronco | 4 (o cinto separa) |
| bota | 14 | calça | 10 |
| cabelo | 25 | rosto | 52 |

Duas coisas fazem o valor funcionar de verdade:

1. **Retone em OKLCh.** Deslocar a rampa inteira até o tom do meio bater no L\*
   alvo, mexendo só a luminância. Em HSV você clareia e dessatura junto.
2. **1px de vazio.** Deixe as colunas de borda da peça de trás transparentes.
   Dois volumes encostados com dL\* 12 ainda leem como um bloco só; com 1px de
   fundo entre eles, leem como dois.

E o erro que eu cometi tentando consertar: dei ao painel do peito o **mesmo
tom da manga**. Braço e peito voltaram a fundir na hora. Cada peça vizinha
precisa do seu degrau — reaproveitar tom entre peças que se tocam é o mesmo
defeito com outro nome.

## 12. Cabeça mais larga que os ombros lê como pirulito

| | cabeça | ombros | razão |
|---|---|---|---|
| Juno | 19px | 18px | **0.95** |
| herói (antes) | 20px | 15px | 0.75 |
| herói (depois) | 17px | 20px | 1.18 |

Na Juno a linha do ombro tem praticamente a largura da cabeça. Com ombros a
75% da cabeça o busto some e o personagem lê como um pirulito — e isso é
percebido como "está bem maior", mesmo com a altura medida quase igual
(54.5 contra 52.5).

Duas alavancas: a posição X do **soquete do ombro** no figure, e a **compactação
do cabelo**. Cabelo do concept é uma massa esgarçada — mechas de 1px além da
silhueta. Em alta resolução é textura; em 20px é uma nuvem com buracos, e o
olho lê a extensão externa. Erodir os pixels com menos de 3 vizinhos opacos
devolve a forma compacta.

## 13. Orçamento de tom, medido peça a peça

A regra da seção 5 (`n_tons ≈ largura ÷ 3`) só vira ferramenta quando você
**mede**. `tools/monsters/px.py` imprime a célula do atlas como grade de
caracteres, um caractere por tom, e conta:

```
python px.py hero            # todas as peças, coluna a coluna
```

O que ele achou na versão que o autor chamou de "montagem confusa":

| peça | largura | tons usados | teto |
|---|---|---|---|
| upper_arm | 4px | **5** | 1–2 |
| thigh | 5px | **5** | 2 |
| torso | 10px | **11** | 3–4 |

Duas a três vezes o orçamento em toda peça. Num membro de 4px, 5 tons não são
sombreamento — são 5 colunas de 1px, que é a definição de ruído. E o relatório
mostra também os degraus: `dL* 7.6 8.4 7.6 2.3` — o último par estava a 2.3,
abaixo do JND, dois tons redundantes.

Depois de gerar as peças de um estêncil com orçamento explícito
(`tools/monsters/body.py`): limbo 5–6px → 3 tons, tronco 10px → 3 tons + 5
acentos (pescoço, gola, cinto, sombra do cinto, fivela).

## 14. Contraste contra o FUNDO, não só entre peças

Medido no lab (fundo L\* 10.3):

```
bota    L* 12.2   ->  dL* 1.9   o pé do personagem era invisível
tronco  L* 25.8   ->  dL* 15.6
```

O piso é ΔL\* 20 contra o fundo. E a correção não é "clarear tudo": o concept
tem a **bota mais clara que a calça** (couro médio, L\* 22–38, contra calça em
L\* 19–31). Eu tinha invertido a escada por hábito — bota escura "ancora a
base" é verdade em silhueta, não em valor absoluto.

Distribuição de valor, por área:

| | mediana | L\*<20 | L\* 30–60 | L\*>70 |
|---|---|---|---|---|
| Juno | 37.1 | 14.3% | 35.2% | **17.2%** |
| concept do herói | 24.1 | 42.8% | 24.7% | 2.8% |
| herói | 27.2 | 30.5% | 27.2% | 1.5% |

Útil para não corrigir na direção errada: o herói é escuro **porque o concept
é escuro**. O que a Juno tem e ele não é uma ÂNCORA CLARA — 17% da área acima
de L\* 70 (o capacete). Perseguir a mediana dela seria trair o concept;
perseguir a âncora clara, não.

## 15. Duas cadeias, não uma escada

Espremer 6 materiais numa escada única dentro de 20 pontos de L\* faz algum par
sempre reprovar. Mas **só peças que se tocam precisam de degrau**, e num corpo
humano elas formam duas cadeias independentes:

```
braço:  tronco 24 -> manga 38 -> braçadeira 50 -> mão 77
perna:  calça 22 -> bota 34
```

O cinto separa as duas. Resolver como dois problemas de 4 e 2 elementos cabe
folgado; resolver como um problema de 6, não.

## 16. Quando o valor acaba, separe por MATIZ

Duas colisões que nenhum ajuste de L\* resolveu:

```
LEATH_HI  (194,142,120)  L* 63.8  H 44    <- realce da braçadeira
SKIN_SH   (196,140,108)  L* 63.3  H 51    <- sombra da pele
```

A mesma cor. O antebraço lia como braço nu. Com a braçadeira em couro, **todo**
valor que a separava do tronco a jogava em cima da pele.

Solução: trocar o material. A braçadeira virou o mesmo azul da manga, mais
clara — e a mão passou a se separar dela por **127° de matiz em OKLCh** (284
azul contra 51 pele quente), com apenas ΔL\* 10 de apoio. É o que a Juno faz:
antebraço de armadura cinza, mão de pele.

> Valor separa matizes parecidos. Matiz separa valores parecidos. Se você está
> brigando com o L\* há três rodadas, o problema é o material.

## Regras que cabem numa linha

1. Teto de croma sai da **imagem base**, não da paleta famosa. Aqui: 0.084.
2. Dessature **em OKLCh**. HSV S×0.6 clareia +12.5 L*.
3. Croma: sombra 36% do pico, meio 100%, luz 76%.
4. Hue shift 12–16°/degrau em OKLCH; sombra ao azul, luz ao amarelo.
5. Nunca gire matiz em HSV com V fixo (±10.7 L*).
6. Tons por peça = largura ÷ 3, máximo 5. Braço de 5px = 2 tons.
7. Orçamento: 12–18 cores no personagem de 46px.
8. ΔL* ≥ 8 vizinhos, ≥ 12 onde peças se tocam, ≥ 20 contra o fundo.
9. Tinta global 15–25% de uma cor comum amarra o elenco.
10. Unifique nas SOMBRAS; deixe os meios-tons divergirem.
11. Acento saturado: 3–5% da área, no terço superior.
12. Extração de paleta: corte por população em 0.5–1.0% ANTES de clusterizar.
13. Perfil: tronco 50%, quadril 62%, membro 100%, **cabeça 130%**.
14. Rosto de perfil DESLIZA e é ocluído; não encolhe para o centro.
15. Separe peça distante por VALOR (ΔL* 10–20), nunca por contorno.

## Fontes

- [Pixelblog 1 — Color Palettes, SLYNYRD](https://www.slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes)
- [Pixelblog 22 — Top Down Character Sprites, SLYNYRD](https://www.slynyrd.com/blog/2019/10/21/pixelblog-22-top-down-character-sprites)
- [Basic Color Theory, Pedro Medeiros (saint11)](https://saint11.art/pixel_art_articles/article6/)
- [The Pixel Art Tutorial, Pixel Joint](https://pixeljoint.com/forum/forum_posts.asp?TID=11299&PID=139318)
- [Pixel Art Tutorial, Arne / androidarts](https://androidarts.com/pixtut/pixelart.htm)
- [Apollo palette, Lospec](https://lospec.com/palette-list/apollo) · [Endesga-32](https://lospec.com/palette-list/endesga-32) · [Resurrect 64](https://lospec.com/palette-list/resurrect-64) · [AAP-64](https://lospec.com/palette-list/aap-64) · [Sweetie 16](https://lospec.com/palette-list/sweetie-16)
- [Gamut Masking Method, James Gurney](http://gurneyjourney.blogspot.com/2011/09/part-1-gamut-masking-method.html)
- [HyAB k-means for color quantization, 30fps.net](https://30fps.net/pages/hyab-kmeans/)
- [Extracting Color Palettes from Images, Atomic Object](https://spin.atomicobject.com/pixels-and-palettes-extracting-color-palettes-from-images/)
- [Delta E 101 (JND ≈ 2.3)](http://zschuessler.github.io/DeltaE/learn/)
- [Anthropometry Summary Table 2020 (ANSUR II), NC State](https://ergocenter.ncsu.edu/wp-content/uploads/sites/358/2025/11/Anthropometry-Summary-Table-2020.pdf)
- [Anthropometric Data Table, RoyMech](https://www.roymech.co.uk/Useful_Tables/Ergonomics/Human_sizes.html)
