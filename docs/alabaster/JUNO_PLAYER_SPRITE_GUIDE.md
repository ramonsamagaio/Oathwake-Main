# Juno — guia mínimo de sprites para gameplay

Este guia cobre **somente** o que é necessário para redesenhar a Juno mantendo os ciclos `idle`, `walk`, `run` e `atkSwordN1` (ataque de espada).

## A regra nova: endereço, não caixa colorida

Não marque cada sprite individual da sheet. Cada conjunto recebe um endereço estável:

`PEÇA · origem X,Y · célula WxH · direção · linhas de articulação`

Exemplo: `H-CABEÇA · (0,0) · 20×20 · FACE_16_MIRR · 11 linhas`.

As **colunas** normalmente representam direção. As **linhas** normalmente são variações de pitch/articulação que o bone escolhe conforme gira. Portanto uma linha extra quase nunca significa uma animação nova.

Para o redesenho Oathwake, pense em cinco vistas-mestre: `N`, `NE`, `E`, `SE`, `S`; o lado oposto é derivado por espelho quando o perfil daquela peça permitir. O atlas original da Juno, porém, mistura `FACE_16`, `FACE_8` e `FACE_4`. Não apague as vistas extras do atlas original até existir um perfil Oathwake 8-dir dedicado.

## Corpo base — usado nos quatro ciclos

| Endereço | Peça | Origem | Célula | Regra fonte | Linhas | Uso |
|---|---|---:|---:|---|---:|---|
| `H-CABEÇA` | cabeça + cabelo principal | 0,0 | 20×20 | FACE_16_MIRR | 11 | idle / walk / run / ataque |
| `HG-ADORNO` | adorno do cabelo | 528,108 | 16×16 | FACE_16_MIRR | 1 | idle / walk / run / ataque |
| `T-FRENTE` | torso principal | 288,0 | 12×12 | FACE_16 | 4 | idle / walk / run / ataque |
| `T-COSTAS` | camada traseira do torso/cintura | 288,84 | 12×8 | FACE_8_MIRR | 2 | idle / walk / run / ataque |
| `C-FRENTE` | cintura/quadril principal | 480,48 | 12×12 | FACE_16_MIRR | 5 | idle / walk / run / ataque |
| `C-TRÁS` | cintura traseira | 480,36 | 12×12 | FACE_16_MIRR | 1 | idle / walk / run / ataque |
| `PR` | perna direita | 480,0 | 8×12 | FACE_8 | 2 | idle / walk / run / ataque |
| `PL` | perna esquerda | 544,0 | 8×12 | FACE_8 | 2 | idle / walk / run / ataque |
| `PÉ-R/L` | pés, arte compartilhada | 608,0 | 8×12 | FACE_4_MIRR + flip | 3 | idle / walk / run / ataque |
| `DEDO-PÉ-R/L` | ponta dos pés | 348,84 | 8×8 | FACE_16_MIRR + flip | 2 | idle / walk / run / ataque |

### Olhos necessários

Não redesenhe os blocos `hyper` agora.

| Endereço | Estado | Origem | Célula | Uso |
|---|---|---:|---:|---|
| `OLHO-NORMAL` | normal | 180,0 | 12×8 | direção neutra/normal |
| `OLHO-BAIXO` | olhar para baixo | 180,32 | 12×8 | bone/pose seleciona quando necessário |
| `OLHO-CIMA` | olhar para cima | 180,64 | 12×8 | bone/pose seleciona quando necessário |
| `OLHO-DIR/ESQ` | perfil lateral | 180,96 | 12×8 | direita usa frente; esquerda usa flip |

Os três primeiros blocos possuem três linhas úteis ligadas aos frame keys 1, 4 e 5. O bloco lateral possui duas linhas. Eles não são quatro animações diferentes.

## Braços e mãos — usados nos quatro ciclos

| Endereço | Peça | Origem | Célula | Regra fonte | Linhas |
|---|---|---:|---:|---|---:|
| `BR-R-A` | braço direito, segmento superior | 608,36 | 8×8 | FACE_4_MIRR_FLIP | 3 |
| `BR-R-B` | braço direito, segmento inferior/corte | 608,60 | 8×8 | FACE_4_MIRR_FLIP | 2 |
| `BR-L-A` | braço esquerdo, segmento superior | 632,64 | 8×8 | FACE_8_MIRR | 4 |
| `BR-L-B` | braço esquerdo, segmento inferior/corte | 608,76 | 8×8 | FACE_4_MIRR | 3 |
| `MÃO-R/L` | mãos, arte compartilhada | 632,0 | 8×8 | FACE_8_MIRR + flip | 5 |
| `DEDOS-R/L` | dedos normais, arte compartilhada | 632,40 | 8×8 | FACE_8_MIRR + flip | 3 |

O bloco de dedos esticados em `(632,96)` não é necessário para `idle`, `walk`, `run` ou `atkSwordN1`.

## Trança / cauda de cabelo — aqui os ciclos realmente mudam de arte

A trança é a principal exceção. Ela possui artes próprias escolhidas pela animação:

| Endereço | Arte | Origem | Célula | Linhas/frame keys | Ciclo |
|---|---|---:|---:|---|---|
| `TR-IDLE` | repouso | 360,100 | 8×28 | 1 linha | idle |
| `TR-WALK` | movimento sutil | 308,100 | 16×28 | 4 linhas, keys 5–8 | walk |
| `TR-RUN` | onda/corrida | 324,100 | 12×28 | 4 linhas, keys 1–4 | run |
| `TR-ATK` | swing de espada | 384,100 | 16×28 | 5 poses por lado, keys 9–18 | atkSwordN1 |

O bone `tailEnd` move e gira essas artes. Não desenhe uma trança diferente para cada frame da animação corporal: só os estados acima são necessários.

## A espada não está nesta sprite sheet corporal

`weaponR` e `weaponL` são **sockets/bones sem pixels próprios**. O ataque `atkSwordN1` movimenta braço, mão e socket da arma. A espada deve ser anexada ao socket correspondente como equipamento.

Portanto, para redesenhar a Juno para Oathwake, não procure uma “linha da espada” escondida neste atlas.

## Camada de visibilidade da Juno

A ordem não pode ser global e fixa para cabelo/cabeça:

- **Sul/frente exato:** o adorno do cabelo fica **sobre a cabeça**, mas abaixo dos olhos.
- **Demais direções:** o adorno conserva a ordem autorada original.
- **Trança olhando para sul:** permanece atrás da cabeça/corpo.
- **Perfil:** passa entre corpo e cabeça.
- **Hemisfério norte/costas:** pode passar sobre a cabeça conforme a silhueta exige.

O runtime Alabaster aplica essa regra por setor de direção, sem alterar as prioridades-base dos sprites.

## O que você NÃO precisa redesenhar agora

Sleep head, hyper eyes, flashback, dedos stretched, alternate arms, estados especiais/cutscene e qualquer arte não alcançada por `idle`, `walk`, `run` e `atkSwordN1` ficam fora deste passe.
