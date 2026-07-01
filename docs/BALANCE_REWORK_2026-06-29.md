# Balance Rework - 2026-06-29

Este arquivo registra o primeiro rework de balanceamento do Agnus Dei feito em cima da tabela de tiers existente. A ideia foi preservar a identidade dos materiais ja criados no projeto e organizar os numeros em uma curva clara para early access.

## Objetivos

- Manter os 7 tiers existentes.
- Transformar `data/tiers.json` em fonte de verdade para metas de progressao.
- Reduzir o caos de valores soltos entre tools, recursos, monstros, repair e storage.
- Evitar que ferramenta muito fraca quebre recurso avancado.
- Fazer repair escalar com durabilidade perdida e tier do item.
- Trocar defesa flat demais por mitigacao com retorno decrescente.

## Tabela de power budget

Cada tier agora possui `power_budget` com alvos de:

- `tool_damage`
- `tool_durability`
- `resource_hp_tree`
- `resource_hp_ore_or_rock`
- `xp_reward`
- `crit_chance`
- `crit_power`
- `attack_cooldown`
- `repair_cost_multiplier`
- `storage_slots`
- `monster_hp_target`
- `monster_damage_target`
- `resource_respawn_seconds`

Esses campos tambem aparecem na aba **Tiers** do Content Editor.

## Curva de tiers atual

| Tier | Tool Damage | Tool Durability | Tree HP | Rock/Ore HP | Monster HP | Monster Damage | Storage |
| ---: | ----------: | --------------: | ------: | ----------: | ---------: | -------------: | ------: |
| 1 | 8 | 90 | 22 | 28 | 40 | 4 | 20 |
| 2 | 12 | 135 | 38 | 44 | 68 | 6 | 24 |
| 3 | 17 | 190 | 58 | 64 | 102 | 9 | 28 |
| 4 | 24 | 265 | 82 | 92 | 150 | 13 | 32 |
| 5 | 34 | 370 | 114 | 126 | 220 | 18 | 36 |
| 6 | 48 | 510 | 158 | 174 | 320 | 25 | 42 |
| 7 | 68 | 700 | 216 | 236 | 460 | 35 | 48 |

## Gathering

Regra aplicada em `scripts/systems/GatheringCalculator.gd`:

- Ferramenta 2+ tiers acima do recurso: 1.35x
- Ferramenta 1 tier acima: 1.15x
- Mesmo tier: 1.0x
- Ferramenta 1 tier abaixo: 0.45x
- Ferramenta 2 tiers abaixo: 0.15x
- Ferramenta 3+ tiers abaixo: 0.0x

Isso impede casos absurdos como ferramenta de madeira progredindo em recurso muito avancado, mas ainda deixa uma pequena zona de esforco quando a diferenca e de 1 ou 2 tiers.

## Combat

`CombatCalculator.gd` agora calcula hit antes de critico. Antes, critico podia funcionar como acerto automatico em algumas situacoes, o que tornava sorte forte demais.

A defesa deixou de ser uma subtracao flat pura e virou mitigacao por retorno decrescente:

```gdscript
defense_ratio = effective_defense / (effective_defense + max(raw_attack * 2.0, 8.0))
base_damage = raw_attack * (1.0 - defense_ratio)
```

Critico ainda aumenta dano, mas ignora parcialmente a defesa (`effective_defense * 0.45`) em vez de simplesmente furar tudo.

## Repair

`RepairCalculator.gd` agora respeita `can_repair` e `repair_cost_multiplier` por item. O custo escala com a durabilidade perdida e com o tier.

Regra importante: itens como `hands` nao sao reparaveis.

## Player stats

`PlayerStatsResolver.gd` agora soma bonus top-level de acessorios, como:

- `crit_chance_bonus`
- `crit_damage_bonus`

Isso faz itens como `lucky_charm` funcionarem sem depender de estarem dentro de `combat`.

## Content Editor

- Aba **Sprites** ganhou botao **Batch Static Sprites**.
- O botao seleciona multiplos arquivos de imagem.
- Depois da selecao, abre uma janela de revisao com preview, nome de arquivo, display name, ID e categoria.
- Ao clicar **Create All**, os arquivos externos sao copiados para `res://assets/sprites/static/` e registrados em `data/sprites.json` como `single_sprite`.

## Proximo passo recomendado

1. Abrir o projeto no Godot.
2. Rodar `res://tools/content_editor/ContentEditor.tscn` com F6.
3. Testar Batch Static Sprites com 2 ou 3 PNGs pequenos.
4. Testar quebrar recursos por tier:
   - wood tool em tier 1 deve funcionar normal;
   - wood tool em tier 3 deve quase nao funcionar;
   - wood tool em tier 4+ nao deve causar progresso real.
5. Testar reparar ferramenta danificada.
6. Testar combate contra slime e skeleton.

## Direcao de UI futura

Separar claramente:

- **UI de editor interno:** densa, com tabela, filtros, validacao e preview.
- **UI de jogador:** limpa, fisica e legivel, com hotbar, inventario, equipment, repair, chest/storage e crafting.

O visual do jogador deve priorizar leitura rapida, icones grandes, tooltip forte e feedback de pickup. A estetica pode puxar para madeira, metal, tecido, velas e manuscritos, mas sem sacrificar clareza.
