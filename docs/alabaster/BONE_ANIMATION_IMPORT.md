# Alabaster — importação de animações de bones

## Objetivo

Permitir que uma animação esquelética externa mova o rig 2D da Juno sem substituir sprites, equipamento, colisão ou lógica de gameplay.

A origem pode ser Mixamo, Blender, Unity ou qualquer ferramenta que consiga entregar uma cena esquelética importável pelo Godot.

## Pipeline

`FBX / GLB → Godot Skeleton3D + AnimationPlayer → AlabasterBoneAnimationImporter → retarget → animação do rig 2D`

O Godot funciona como formato intermediário. Não existe dependência de um arquivo proprietário da Unity ou do Mixamo.

### 1. Importar a animação externa

Importe normalmente um `.fbx` ou `.glb` contendo Skeleton3D + AnimationPlayer.

Para Unity, exporte a animação/skeleton para FBX ou GLB antes. O bridge não tenta interpretar `.anim` binário da Unity diretamente.

### 2. Converter um clip

```gdscript
var clip := AlabasterBoneAnimationImporter.import_scene_clip(
    "res://imports/mixamo/sword_attack.glb",
    "mixamo.com",
    60.0,
    false
)
```

O resultado usa exatamente o formato de `transforms` que o runtime Alabaster já consome.

### 3. Instalar no rig em runtime

```gdscript
var rig := player.get_alabaster_player_rig()
AlabasterBoneAnimationImporter.install_on_rig(rig, "external_sword_attack", clip)
rig.set_animation("external_sword_attack")
```

Depois a animação pode ser ligada a uma ação em `rig_animation_map` do Characters record.

## Retarget padrão Mixamo → Juno

O importador já conhece os pares principais:

- Hips → `bottom`
- Spine2 → `top`
- Head → `head`
- LeftArm / RightArm → `shoulderL/R`
- LeftForeArm / RightForeArm → `armL/R`
- LeftHand / RightHand → `handL/R`
- LeftUpLeg / RightUpLeg → `hipL/R`
- LeftLeg / RightLeg → `legL/R`
- LeftFoot / RightFoot → `footL/R`
- LeftToeBase / RightToeBase → `toeL/R`

Também há mapeamento de dedos principais e root.

Um skeleton diferente pode fornecer um dicionário de retarget customizado sem alterar o importador.

## O que é importado

Por padrão:

- rotação local dos bones: **sim**;
- escala: **sim**, quando o clip possuir;
- translação/root motion: **desligada** (`translation_scale = 0.0`).

A translação fica desligada porque o corpo pixel-art já tem comprimentos e encaixes autorados. Para o gameplay, movimento real do personagem continua sendo responsabilidade do `CharacterBody2D`, não do mocap.

## O que a animação externa NÃO faz

Ela não cria sprites e não inventa direções do atlas. O bone define a pose; o runtime continua escolhendo a arte direcional correta de cabeça, torso, braços, pernas, mãos, pés, cabelo e equipamento.

Ela também não substitui sockets de arma. `weaponR` / `weaponL` continuam sendo pontos de encaixe do equipamento do jogo.

## Calibração de rest pose

Mixamo, Unity humanoid e rigs customizados podem possuir eixos/rest poses diferentes. O bridge já resolve nomes e converte os eixos básicos para a convenção `[yaw, pitch, roll]` da Juno, mas uma animação de produção pode precisar de **offsets de rest pose por bone**.

O próximo nível dessa ferramenta é um `retarget_profile.json` por família de skeleton, contendo:

- nome fonte → bone Juno;
- offset de rotação de repouso;
- inversão de eixo quando necessária;
- escala opcional de translação;
- bones ignorados.

Isso permite calibrar Mixamo uma vez e reutilizar a calibração em centenas de clips.

## Regra de segurança

Importar mocap nunca deve alterar a anatomia gráfica da personagem. O clip só dirige transforms. Os sprites e os comprimentos autorados pelo rig continuam sendo a fonte da silhueta final.
