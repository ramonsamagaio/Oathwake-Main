# Monstros humanoides no rig Alabaster — gabarito e pipeline

Este documento fecha o ciclo entre três coisas que já existem separadas no repo:

- o runtime Alabaster reconstruído (`AlabasterRigRuntimeSource.gd` e derivados);
- o Bone Studio / Bone Bridge, que importa `.fbx` de Mixamo/Cascadeur/Rokoko e retargeta para o rig;
- o atlas DEFAULT 672×120, que é o corpo Oathwake herdado do `Male-Dummy`.

O objetivo é: **criar inimigos humanoides novos com a mesma qualidade visual do player,
usando animações diferentes, sem redesenhar 16 direções de cada peça.**

---

## 1. Como a mecânica funciona de verdade

Não é `Skeleton2D`. Não é personagem 3D renderizado. É um **esqueleto 3D dirigindo billboards 2D**.

Por frame, para cada nó do rig:

1. O rig avalia a hierarquia de bones em 3D (`Transform3D`/quaternion, SLERP entre keys).
   `X/Y` é o plano do chão, `Z` é altura.
2. A pose 3D é projetada para a tela por uma câmera em perspectiva
   (`TILE_W=24`, `TILE_H=16`, snap de meio pixel em X/Y/Z independentes).
3. Para cada gráfico pendurado no nó, o runtime pergunta duas coisas ao atlas:
   - **qual coluna** — pelo yaw do root, através de uma tabela autorada de facing;
   - **qual linha** — pelo pitch do bone, através de faixas nomeadas (`ALL`, `UP1+`, `DOWN1+`, …).
4. O sprite escolhido ainda pode ser **rotacionado, esticado ou recortado** conforme o `texRotate`
   da linha (`ROTATE`, `PARENT_ROTATE_SCALE`, `ROTATE_CUT`, …), usando a projeção de dois pontos
   entre o bone e o pai.

O endereçamento do atlas é literalmente isto (`AlabasterRigRuntimeSource.gd`):

```gdscript
src_x = range.x + tile_w * tile_index     # tile_index vem da tabela de facing
src_y = range.y + tile_h * row_index      # row_index vem da faixa de pitch
```

**É por isso que uma única animação `walk` serve para as 16 direções.** A pose é 3D;
o atlas só fornece a arte correta para o ângulo em que ela está sendo vista.
Você nunca desenha "walk para o norte".

### A tabela de facing é o que decide quantos sprites você precisa desenhar

Cada peça declara seu próprio modo. O número de **células únicas por linha** é o que custa arte:

| facing | células únicas | ordem das colunas | oeste |
|---|---:|---|---|
| `FACE_4_MIRR` | 3 | S · E · N | espelho automático |
| `FACE_8_MIRR` | 5 | S · SE · E · NE · N | espelho automático |
| `FACE_16_MIRR` | 9 | S · SSE · SE · ESE · E · ENE · NE · NNE · N | espelho automático |
| `FACE_8` | 8 | S · SE · E · NE · N · NW · W · SW | desenhado à mão |
| `FACE_16` | 16 | todas | desenhado à mão |

Sufixo `_FLIP` = mesma tabela, arte espelhada — é assim que o lado direito do corpo
reaproveita as células do esquerdo.

Isso responde direto à pergunta "corpo em 4 direções, cabeça em 8": **é legítimo e é
exatamente o que a Juno original faz** — cabeça em `FACE_16`, pés em `FACE_4`, no mesmo
personagem. Peça a peça.

---

## 2. O que o gabarito entrega

Três arquivos, gerados por script e reprodutíveis:

| arquivo | onde | para quê |
|---|---|---|
| `monster_humanoid_01.png` | `assets/sprites/characters/alabaster/` | atlas placeholder 672×120, **já jogável** |
| `monster_template_overlay.png` | `docs/alabaster/` | camada transparente 672×120 com bordas de célula e pivôs — abra por cima no Aseprite |
| `monster_template_guide.png` | `docs/alabaster/` | pôster anotado: coordenadas, facing, pivô, texRotate, hierarquia, regras |
| `monster_humanoid_01.json` | `data/labs/alabaster/characters/` | figure derivado do `Male-Dummy` com facing reduzido |

Gerados por:

```bash
python tools/alabaster/make_alabaster_monster_template.py assets/sprites/characters/alabaster
python tools/alabaster/make_alabaster_monster_figure.py \
    data/labs/alabaster/characters/dummy.json \
    data/labs/alabaster/characters/monster_humanoid_01.json
python tools/alabaster/verify_alabaster_monster.py \
    data/labs/alabaster/characters/monster_humanoid_01.json \
    assets/sprites/characters/alabaster/monster_humanoid_01.png
```

### Layout do atlas

Idêntico ao DEFAULT / `dummy.png`. **Nenhuma coordenada `range` mudou** — só o `facing`.
Isso é de propósito: o par pivô/geometria já está provado, e um monstro pode ser promovido
para 8 ou 16 direções depois sem tocar em uma linha de JSON de posição.

| # | peça | bone(s) | gfx | origem | célula | linhas de pitch | pivô | texRotate |
|---:|---|---|---|---|---|---|---|---|
| 1 | cabeça | `head` | gfx0 | (0,0) | 16×16 | `UP1+` / `ALL` / `DOWN1+` | 0.50 / 0.13 | NONE |
| 2 | torso | `top` | gfx0 | (0,48) | 16×16 | `ALL` / `DOWN1+` | 0.50 / 0.25 | NONE |
| 3 | abdômen | `root` | gfx0 | (0,80) | 16×12 | `ALL` / `DOWN1+` | 0.50 / 0.50 | NONE |
| 4 | pélvis | `bottom` | gfx0 (+gfx1 atrás) | (0,104) | 16×12 | `ALL` | 0.50 / 0.50 | NONE |
| 5 | coxa | `legL` / `legR` | gfx0 | (144,0) | 8×16 | `ALL` | 0.63 / 1.06 | `PARENT_ROTATE_SCALE` |
| 6 | canela | `footL` / `footR` | gfx0 | (144,16) | 8×12 | `ALL` | 0.50 / 0.75 | `PARENT_ROTATE_CUT` |
| 7 | pé | `toeL` / `toeR` | gfx0 | (144,28) | 12×12 | `ALL` | 0.50 / 0.25 | `ROTATE` |
| 8 | ombro | `armL` / `armR` | gfx0 | (208,0) | 8×8 | `ALL` | 0.38 / 0.38 | `ROTATE` |
| 9 | braço | `armL` / `armR` | gfx1 | (208,8) | 8×12 | `ALL` | 0.50 / 0.17 | `ROTATE_CUT` |
| 10 | antebraço | `handL` / `handR` | gfx0 | (208,20) | 8×8 | `ALL` | 0.38 / 0.75 | `PARENT_ROTATE_SCALE` |
| 11 | mão | `fingerL` / `fingerR` | gfx0 | (208,28) | 8×8 | `ALL` | 0.38 / 0.38 | `PARENT_ROTATE` |

Repare na armadilha de nomenclatura herdada do source: **`hand*` desenha o antebraço e
`finger*` desenha a mão; `foot*` desenha a canela e `toe*` desenha o pé.** O nome do bone
não é o nome da peça.

`weaponL` / `weaponR` são sockets sem pixels. Arma e ferramenta são figures separados.

### Custo de arte

Com `FACE_8_MIRR` em tudo e o corpo em 4 direções (colunas 1 e 3 são cópias de 0 e 4):

| bloco | células no atlas | células realmente desenhadas |
|---|---:|---:|
| cabeça (5 col × 3 linhas) | 15 | 15 |
| torso (5 × 2) | 10 | 6 |
| abdômen (5 × 2) | 10 | 6 |
| pélvis (5 × 1) | 5 | 3 |
| 7 blocos de membros (5 × 1) | 35 | 35 |
| **total** | **75** | **65** |

Comparando: o DEFAULT em `FACE_16_MIRR` no corpo e `FACE_8` nos membros pede 133 células.

---

## 3. Regras de desenho que não podem ser quebradas

1. **672×120 exato.** `AlabasterExternalSkinSource` e `AlabasterDefaultPlayableSkinRig`
   rejeitam qualquer outro tamanho e caem no atlas de fallback, sem erro visível no jogo.
2. **Fundo em `RGB(255, 0, 195)` exato.** O loader troca esse RGB por alpha 0.
   Anti-alias contra o magenta gera borda rosa. Desenhe hard-edge.
3. **O pivô é onde o bone encosta na arte**, medido em fração da célula a partir do canto
   superior esquerdo. `sprite.offset = (w/2 − pivotX·w, h/2 − pivotY·h)`.
   A peça é desenhada **em volta do pivô**, não centralizada na célula.
   Pivô de coxa em `1.06` fica fora da célula de propósito — é isso que faz o membro esticar certo.
4. **Colunas 0..4 = S, SE, E, NE, N.** Oeste é espelho automático. Nunca desenhe o lado esquerdo.
5. **Corpo em 4 direções:** desenhe S, E e N; copie S→SE e N→NE. Para virar 8 direções de
   verdade depois, repinte as duas cópias. Nada muda no JSON.
6. **Linhas são pitch, não animação.** A cabeça tem 3: linha 0 = `UP1+` (olhando para cima),
   linha 1 = `ALL` (neutro), linha 2 = `DOWN1+` (para baixo). Uma linha a mais quase nunca
   significa animação nova.
7. **Peças com `PARENT_ROTATE_SCALE` / `_CUT` são esticadas e recortadas pelo runtime** entre
   dois bones. Desenhe-as retas e cheias no comprimento total; o motor faz o encurtamento
   em perspectiva sozinho. Não tente "desenhar o braço dobrado".
8. **Vermelho = marcador de frente, azul = marcador de costas** no placeholder. Só servem
   para achar direção invertida no teste. Apague quando a arte final entrar.

---

## 4. Pipeline de animação: Mixamo / Cascadeur / Rokoko → monstro

As animações **não** vêm do atlas. Vêm do banco de bones, e é aí que dois monstros com o
mesmo corpo ficam diferentes.

Os `.fbx` em `assets/anims/` (`Walking.fbx`, `Fast Run.fbx`, `Punching.fbx`) já são exemplos
válidos desse caminho.

### Fluxo

1. Baixe o clip do Mixamo **sem skin** (`Without Skin`), FBX binário, in-place quando for locomoção.
2. Coloque o arquivo em `assets/anims/` e deixe o Godot importar como cena.
3. Abra `res://scenes/labs/alabaster/AlabasterBoneStudio.tscn`.
4. Aba **Import / Retarget** → *Choose imported FBX / GLB / GLTF / TSCN* → escolha o clip.
5. Nomeie no padrão do monstro, por exemplo `MON_ghoul_walk`.
6. Mantenha **Remove source reference pose** ligado. O importador calcula
   `delta = inverse(primeiro_frame) × pose_atual`, então o monstro mantém a própria anatomia
   e recebe só o movimento relativo.
7. Confira a tabela source bone → bone alvo. O mapa Mixamo padrão já está embutido
   (`Hips→bottom`, `Spine*→top`, `LeftArm→armL`, `LeftForeArm→…`, etc.).
   Lembre: `shoulderL/R` e `hipL/R` são **pivôs de fixação**, não os primeiros segmentos
   deformáveis — não case `LeftShoulder` com `armL`.
8. Preview N / NE / E / SE / S com **Sprite opacity** baixa para ver o esqueleto.
9. **Root translation scale = 0** para locomoção. O deslocamento real é do `CharacterBody2D`.
10. Salvar → entra em `data/labs/alabaster/custom_bone_animations.json`, por profile.

### Diferenciar monstros usando o mesmo corpo

Esta é a parte que realmente cria variedade barata:

| eixo | como |
|---|---|
| animação | banco de bones próprio por profile (`MON_ghoul_walk` vs `MON_brute_walk`) |
| proporção | edite `pos` dos nós no figure JSON — braço mais longo, tronco mais curto |
| velocidade | `frameRepeat` (`frameRepeat = 60 / FPS`) |
| silhueta | repinte só o atlas, mantendo pivôs |
| altura | `scale` do rig no controller |
| equipamento | figure de arma anexado a `weaponL` / `weaponR` |

Um ghoul e um bruto podem compartilhar `monster_humanoid_01.json` e ter só atlas + banco
de animação diferentes.

---

## 5. O que falta no repo para monstros usarem isso

Hoje o caminho Alabaster existe **só para o player**:

- `AlabasterPlayerVisualController.gd` decide `visual_runtime == "alabaster"` e instancia o rig;
- `data/characters.json` tem `juno_alabaster`, `default_alabaster`, `male_dummy_alabaster`, `male_temp_alabaster`;
- inimigos passam por `EnemyBase` → `MonsterAnimator` → `AnimatedSprite2D` + `SpriteFrames`.
  Não há nenhum ponto no caminho de monstro que instancie um rig Alabaster.

Então falta uma ponte. O menor caminho, em três mudanças:

**(a) Registrar o profile — JÁ FEITO.** `scripts/labs/alabaster/AlabasterExternalSkinSource.gd`
ganhou uma entrada em `PROFILE_JSON_PATHS`, `PROFILE_FIGURES` e `PROFILE_ATLAS_PATHS`:

```gdscript
"monster_humanoid_01": "res://data/labs/alabaster/characters/monster_humanoid_01.json",
"monster_humanoid_01": "Monster-Humanoid-01",
"monster_humanoid_01": "res://assets/sprites/characters/alabaster/monster_humanoid_01.png",
```

Nenhuma entrada foi adicionada em `REQUIRED_ANIMATIONS`: sem entrada, a lista obrigatória
fica vazia e o figure só precisa ter os nós humanoides completos.

**(a2) Botão no Mechanic Lab — JÁ FEITO.** `AlabasterMechanicLabProfiles.gd` ganhou
`PROFILE_MONSTER` e uma constante `PROFILE_ORDER`, que agora alimenta tanto a criação dos
botões quanto o guard de `_replace_rig`. O switcher passou a ter cinco botões:
`DEFAULT · DUMMY · MALE · MONSTER · JUNO`.

**(b) Um controller de monstro — FALTA.** `scripts/enemies/AlabasterMonsterVisualController.gd`,
espelhando `AlabasterPlayerVisualController`: recebe `monster_data`, instancia
`AlabasterPlayableSkinRig` com `configure_skin_profile(profile_id)`, chama `initialize_skin()`,
`set_embedded_world_mode(true)` e instala o banco custom do profile.

**(c) Um desvio em `MonsterAnimator.configure()` — FALTA.** Se
`monster_data.visual_runtime == "alabaster"`, delega para o controller e não constrói
`SpriteFrames`. `play_state(state, facing_direction)` vira `rig.set_facing_from_vector(vetor)`
+ `rig.set_animation(action)`.

Cuidado ao ligar: `MonsterAnimator.play_state` recebe `facing_direction` como **string**
(`"left"/"right"/"up"/"down"`). O rig precisa de um `Vector2`. Converta na ponte, ou melhor,
passe o vetor de movimento real de `MonsterLocomotion` — senão o monstro fica preso em
4 direções mesmo com o rig capaz de 16.

Regra do `AGENTS.md`: (a) e (a2) já são pequenos e testáveis isoladamente. Valide-os no
Mechanic Lab e no validador headless antes de escrever (b) e (c).

---

## 6. Validação

### Passo 1 — offline, sem Godot

```bash
python tools/alabaster/verify_alabaster_monster.py \
    data/labs/alabaster/characters/monster_humanoid_01.json \
    assets/sprites/characters/alabaster/monster_humanoid_01.png
```

O script reimplementa `_facing_table`, `_pitch_bounds` e o endereçamento do atlas do
`AlabasterRigRuntimeSource.gd`, e para cada peça × 16 direções × cada linha de pitch confere que:

- a célula escolhida cai dentro do atlas;
- a célula escolhida tem pixel desenhado (não é só chroma);
- `rootFacing`, `spriteSheets["Male-1"]` e o tamanho batem com o que o loader exige.

O mesmo script roda contra `dummy.json` + `default.png` e passa — ou seja, ele reproduz o
layout que já está no jogo, não uma teoria.

### Passo 2 — headless no Godot

```bash
godot --headless --path . --script res://scripts/test/AlabasterMonsterTemplateValidator.gd
```

Esse validador vai além do offline: ele carrega o profile pelo **loader canônico**
(`AlabasterExternalSkinSource`, que roda `_validate_humanoid_figure` e
`_validate_sprite_sheet_binding`), instancia o `AlabasterPlayableSkinRig` de verdade,
chama `initialize_skin()` / `is_skin_ready()`, e então varre `walk`, `run` e `punch`
× 16 direções conferindo que o corpo continua desenhando o número esperado de peças.
Também recusa qualquer peça que tenha escapado do contrato reduzido de facing.

Marcador de sucesso:

```
ALABASTER_MONSTER_TEMPLATE_VALIDATION_OK profile=monster_humanoid_01 directions=48 min_visible_pieces=…
```

Falhas saem como `ALABASTER_MONSTER_TEMPLATE_VALIDATION_FAILURE: …` com exit code 1.

### Passo 3 — visual

1. Abra `res://scenes/labs/alabaster/AlabasterMechanicLab.tscn` e clique em **MONSTER**
   no switcher TEST FIGURE (canto superior direito).
2. WASD para girar; `Sprite opacity` em ~40% e F1 para ver o esqueleto por baixo.
3. Marcador vermelho aparecendo de costas = coluna trocada. Marcador azul de frente = idem.
   Membro que "desliza" ou salta de posição normalmente é pivô errado, não animação errada.
4. Console: procure `ALABASTER_REPO_FIGURE_OK profile=monster_humanoid_01` e
   `ALABASTER_REPO_ATLAS_OK`. Se aparecer o atlas de fallback, o PNG foi rejeitado por tamanho.

O Bone Studio **não** serve para esse teste: ele é fixo no rig da Juno (`BonesSystem`),
sem seletor de profile. Ele continua sendo a ferramenta de importar/retargetar animação,
não de inspecionar skin de monstro.

---

## 7. Limites conhecidos

- Os modos `*_CUT` continuam sendo aproximação da CPU-fallback do source; o shader de
  billboard de dois pontos original não foi reproduzido. Isso afeta antebraço e canela em
  ângulos extremos.
- O placeholder deste gabarito valida geometria, direção e profundidade — não valida leitura
  artística. Silhueta boa em 16×16 continua sendo trabalho manual.
- `AlabasterMixamoRetargetV16` é a versão de produção do retarget; V6–V15 ficam no repo
  para diagnóstico A/B. Ao debugar um clip torto, compare contra V14 antes de mexer na tabela
  de bones.
