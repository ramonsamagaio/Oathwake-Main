# Alabaster — Bone Studio, importação e animação manual

## O que os bones são no Oathwake

O rig da Juno é um sistema híbrido:

- a hierarquia, as rotações e as animações dos bones são **3D**;
- os transforms usam quaternion / yaw-pitch-roll e posições `Vector3`;
- o gameplay continua em um `CharacterBody2D`;
- o runtime projeta os bones 3D para a tela 2D;
- sprites 2D pixel-art são escolhidos por direção da câmera e pela inclinação do bone.

Portanto não é um `Skeleton2D` convencional. Também não é um personagem 3D renderizado. É um esqueleto 3D dirigindo billboards/sprites 2D.

Esse detalhe é a razão pela qual uma única animação como `walk` normalmente pode funcionar olhando para norte, sul, leste e diagonais. A pose é 3D; o atlas fornece a arte correta para o ângulo observado.

## Cena de produção para importação / edição

Abra e execute isoladamente:

`res://scenes/labs/alabaster/AlabasterBoneStudio.tscn`

A ferramenta tem duas abas.

### Aba Import / Retarget

Fluxo recomendado:

1. Coloque o `.fbx`, `.glb` ou `.gltf` dentro do projeto para o Godot importá-lo como cena.
2. Abra `AlabasterBoneStudio.tscn`.
3. Clique em **Choose imported FBX / GLB / GLTF / TSCN**.
4. Escolha o clip no campo **Animation clip**.
5. Dê um nome Oathwake, por exemplo `OW_run_heavy`.
6. Mantenha **Remove source reference pose** ligado inicialmente.
7. Confira a tabela **source bone → Juno bone**.
8. Clique em **Preview Retarget**.
9. Use o preview N / NE / E / SE / S e diminua **Sprite opacity** para inspecionar os bones.
10. Se necessário, corrija manualmente os pares da tabela e os offsets globais de Yaw / Pitch / Roll.
11. Quando estiver correto, clique em **Save to Animation Bank**.

A animação entra em:

`res://data/labs/alabaster/custom_bone_animations.json`

Ela passa a ser carregada por `AlabasterRigRuntimeImportable` e aparece nos seletores do personagem Alabaster no Content Editor.

## Por que remover a reference pose

Mixamo, Blender, Unity Humanoid e rigs próprios raramente têm exatamente a mesma rest pose e os mesmos eixos da Juno.

Por padrão o importador calcula:

`delta = inverse(primeiro_frame) × pose_atual`

A Juno mantém a anatomia/rest pose dela, e recebe apenas o movimento relativo do clip importado. Isso reduz braços torcidos, tronco inclinado e pernas deslocadas causados por diferenças de T-pose/A-pose.

Se o primeiro frame do arquivo já for parte real do movimento e não uma boa referência, desligue a opção e faça a calibração manualmente.

## Retarget padrão Mixamo → Juno

O importador reconhece automaticamente os nomes mais comuns:

| Mixamo / humanoide | Juno |
| --- | --- |
| Root | `root` |
| Hips | `bottom` |
| Spine / Spine1 / Spine2 | `top` |
| Neck / Head | `head` |
| LeftShoulder / LeftArm | `shoulderL` |
| LeftForeArm | `armL` |
| LeftHand | `handL` |
| LeftHandIndex1 | `fingerL` |
| RightShoulder / RightArm | `shoulderR` |
| RightForeArm | `armR` |
| RightHand | `handR` |
| RightHandIndex1 | `fingerR` |
| LeftUpLeg | `hipL` |
| LeftLeg | `legL` |
| LeftFoot | `footL` |
| LeftToeBase | `toeL` |
| RightUpLeg | `hipR` |
| RightLeg | `legR` |
| RightFoot | `footR` |
| RightToeBase | `toeR` |

A tabela no Bone Studio é a autoridade final. Um bone pode ser ignorado ou redirecionado sem editar código.

## Ajuste para o top-down da Juno

Uma animação feita para uma câmera third-person pode parecer exagerada quando projetada para Oathwake. O importador mantém a rotação 3D, mas oferece correção de:

- **Yaw**: giro horizontal;
- **Pitch**: inclinação frente/trás;
- **Roll**: inclinação lateral;
- **Root translation scale**: desligado por padrão.

Comece com Yaw/Pitch/Roll = 0 e Root translation = 0. O movimento real do player deve continuar no `CharacterBody2D`.

Se um clip externo continuar ruim mesmo após retarget:

1. abra-o no Blender;
2. aplique/normalize transform do armature;
3. coloque o personagem fonte numa rest pose coerente;
4. remova root motion para locomotion in-place;
5. reduza exageros de quadril e deslocamento vertical que só fazem sentido em perspectiva 3D;
6. exporte GLB/FBX novamente;
7. retargete no Bone Studio.

Para uma biblioteca grande, o melhor fluxo é calibrar uma família de skeleton uma vez e reutilizar o mesmo mapeamento.

## FPS

O runtime original da Juno usa um relógio-base de 60 ticks por segundo.

O importador e o editor manual convertem automaticamente o FPS escolhido em `frameRepeat`:

`frameRepeat = 60 / FPS`

Assim um clip amostrado em 30 FPS continua durando o mesmo tempo quando entra no runtime Alabaster.

## Aba Manual Animator

A segunda aba permite criar animações sem Mixamo/Blender:

1. escolha um bone;
2. escolha o frame;
3. edite Yaw / Pitch / Roll;
4. opcionalmente edite X / Y / Z;
5. escolha o tween;
6. clique em **Add / Update Key**;
7. repita em outros frames/bones;
8. use **Preview Manual Animation**;
9. use **Save Manual Animation to Bank**.

Os sprites continuam por cima do esqueleto durante a edição. Use `Sprite opacity` entre 20% e 50% para enxergar melhor a relação entre bone, pivô e arte.

A interpolação usa o mesmo formato e caminho de quaternion do runtime Alabaster, portanto a prévia e o jogo compartilham o mesmo modelo de animação.

## Como usar a animação depois de salvar

No Content Editor:

1. abra **Characters**;
2. selecione `Juno - Alabaster Rig` ou outro personagem `visual_runtime = alabaster`;
3. em **Base Gameplay Actions**, escolha o clip para Idle / Walk / Run / Attack / Block / Hurt / Death / Dash;
4. normalmente deixe os overrides de direção como **Use Base Action**;
5. se um clip específico só funcionar bem em uma vista, use os overrides N / NE-NW / E-W / SE-SW / S.

Os overrides de direção são uma conveniência do Oathwake. A Juno original não precisa, em geral, de uma animação separada para cada direção: a animação esquelética é 3D e o renderer muda os sprites conforme o ângulo.

## Direções no renderer original

O source usa famílias de facing diferentes conforme a peça: `FACE_4`, `FACE_8`, `FACE_16`, variantes MIRR/FLIP etc. Assim, a cabeça pode ter resolução direcional mais fina que um pé ou uma mão.

A interface de 5 vistas do Bone Studio é uma interface de inspeção prática do Oathwake, não uma afirmação de que o atlas original possui somente cinco colunas.

## Regra de segurança

Importar mocap nunca deve alterar a anatomia gráfica da personagem. O clip dirige transforms; sprites, comprimentos e pivôs autorados continuam sendo a fonte da silhueta final.
