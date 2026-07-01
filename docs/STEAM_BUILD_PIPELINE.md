# AGNUS DEI - Steam Build Pipeline

## Objetivo

Gerar builds Windows testaveis para Alpha.

## Build Alvo Inicial

- Platform: Windows Desktop
- Architecture: x86_64
- Mode: Release
- Export path sugerido: `builds/windows_alpha/AgnusDei.exe`

## Antes De Exportar

- [ ] Jogo abre sem erro.
- [ ] Main scene correta.
- [ ] Save/load funcionando.
- [ ] Inventory funcionando.
- [ ] Equipment funcionando.
- [ ] Gathering funcionando.
- [ ] Crafting funcionando.
- [ ] Chest funcionando.
- [ ] Repair funcionando.
- [ ] Slime/combat funcionando.
- [ ] Primeiro bioma carregando.
- [ ] Sem caminhos absolutos locais.
- [ ] Sem assets faltando.
- [ ] Sem erros vermelhos no output.

## Configuracoes Importantes

- main_scene atual: `res://scenes/Main.tscn`.
- project name atual: `AgnusDei OPENCODE GPT`.
- resolucao/window size atual: nao configurado explicitamente em `project.godot`; usar default do Godot ate decidir alvo de Alpha.
- stretch mode atual: nao configurado explicitamente em `project.godot`.
- pixel art filtering atual: nao configurado explicitamente em `project.godot`.
- renderer atual: `gl_compatibility`.
- Windows rendering driver: `d3d12`.
- autoload atual: `ContentDB`.
- input map importante: movimento por `WASD`, ataque por `Space`/mouse esquerdo, interacao por `E`, troca de ferramenta por `Q`/`E`, build/debug conforme scripts atuais.
- save path usado: `user://savegame.json`.
- branch/build version: `res://data/build_info.json`.

## Export Preset

`export_presets.cfg` ainda nao existe.

Para evitar criar um preset invalido por texto, criar manualmente no Godot Editor:

1. Abrir Project > Export.
2. Clicar em Add.
3. Escolher Windows Desktop.
4. Definir modo Release.
5. Definir architecture x86_64.
6. Definir export path como `builds/windows_alpha/AgnusDei.exe`.
7. Conferir se os export templates do Godot estao instalados.
8. Exportar.

Quando o preset for criado pelo editor e testado, commitar `export_presets.cfg`.

## Versionamento Da Alpha

O arquivo `res://data/build_info.json` guarda a versao atual:

```json
{
	"version": "0.1.0-alpha",
	"build_name": "Alpha Vertical Slice",
	"steam_ready": false
}
```

Se uma tela de menu/debug for criada depois, mostrar essa versao discretamente. Sem menu ainda, manter apenas o JSON.

## Pasta De Builds

Builds locais/exportadas devem ficar fora do git:

- `builds/`
- `*.exe`
- `*.pck`

Esses ignores estao em `.gitignore`.

## Teste Pos-Export

1. Exportar build.
2. Rodar `.exe` fora do editor.
3. Criar novo save.
4. Coletar resource.
5. Craftar item.
6. Colocar chest.
7. Salvar.
8. Fechar jogo.
9. Abrir build de novo.
10. Carregar save.
11. Confirmar persistencia.

## Steam Future

Futuro, fora desta etapa:

- Steam app id.
- Steamworks SDK, se necessario depois.
- Achievements depois.
- Cloud save depois.
- Controller support depois.

Nao implementar agora:

- Steamworks SDK.
- Achievements.
- Cloud save.
- Mudanca de save path.
- Launcher.
- Menu complexo.
- Refactor de project settings sem teste.

## Como Testar

1. Abrir este documento.
2. Confirmar checklist.
3. Confirmar `res://data/build_info.json`.
4. Abrir Godot.
5. Criar preset Windows pelo editor, se ainda nao existir.
6. Exportar build manualmente, se possivel.
7. Rodar `.exe` fora do editor.
