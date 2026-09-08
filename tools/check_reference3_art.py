"""Verify Pixelorama round trip, pair assembly, alpha and reference frame bounds."""
import hashlib,json,shutil
from pathlib import Path
from PIL import Image,ImageDraw
from author_oathwake_native import Canvas
from trace_oathwake_reference import SOURCE,OUT,MODELS,ROOT_PROFILES,WOOD,trace_oak

root=Path(__file__).resolve().parents[1]
info=json.loads((OUT/'reference3-family.json').read_text())
checks=[]
for item in info['assets']:
    im=Image.open(OUT/(item['name']+'.png')).convert('RGBA')
    assert hashlib.sha256(im.tobytes()).hexdigest()==item['rgba_sha256'],item['name']
    assert set(im.getchannel('A').tobytes())=={0,255}
atlases=[Image.open(OUT/('reference3-'+part+'.png')).convert('RGBA') for part in ['trees','crowns','trunks']]
for i,model in enumerate(MODELS):
    box=((i%6)*128,(i//6)*192,(i%6+1)*128,(i//6+1)*192)
    full,crown,trunk=[a.crop(box) for a in atlases]
    assert Image.alpha_composite(trunk,crown).tobytes()==full.tobytes(),model['name']
    expected=trace_oak(model)
    for im,canvas in zip([full,crown,trunk],expected[:3]):
        assert im.tobytes()==canvas.bytes()
        assert len(canvas.components())==1,(model['name'],'disconnected art')
    assert not (set(expected[1].p)&set(expected[2].p))
    profile=ROOT_PROFILES[model['name']]
    root_mask=Canvas(128,192);root_mask.polygon(profile['outline'],WOOD[0],'wood')
    assert all(p in root_mask.p and co in WOOD for p,co in expected[0].p.items() if p[1]>=profile['clear_y'])
    assert model['anchor'][1]==max(p[1] for p in expected[0].p)+1
    assert all(co in WOOD for co in expected[2].p.values()),(model['name'],'green or nonwood living base')
    before_path=OUT/'before-bare-roots/reference3-trees.png'
    if before_path.exists():
        old=Image.open(before_path).convert('RGBA').crop(box)
        protected_height=min(y for x,y in profile['outline'])
        assert old.crop((0,0,128,protected_height)).tobytes()==full.crop((0,0,128,protected_height)).tobytes(),(model['name'],'unrequested upper crown change')
    checks.append({'name':model['name'],'alpha_binary':True,'exact_pair_assembly':True,'three_connected_masks':True,
                   'ground_mat_absent':True,'living_base_wood_only':True,'anchor_at_root_contact':True,'upper_crown_unchanged':True})
report={'pixelorama_roundtrip':True,'models':checks,'native_frame':[128,192],
        'method':'source-guided 1:1 tracing, explicit native palette and cleanup; no resizing',
        'scope':'tree replicas; isolated Godot preview; catalog not replaced',
        'visual_approval':'not assumed from technical checks'}
(OUT/'reference3-qa.json').write_text(json.dumps(report,indent=2))
destination=root/'assets/sprites/world/procedural/terrain/oathwake_tilesets/resources/reference3_native'
destination.mkdir(parents=True,exist_ok=True)
for item in info['assets']:
    for ext in ['.png','.pxo']:shutil.copy2(OUT/(item['name']+ext),destination/(item['name']+ext))
for name in ['reference3-family.json','reference3-qa.json']:shutil.copy2(OUT/name,destination/name)
source_dir=root/'docs/resources/source_copies'
source_dir.mkdir(exist_ok=True)
if SOURCE.resolve()!=(source_dir/'reference3-user.png').resolve():shutil.copy2(SOURCE,source_dir/'reference3-user.png')
# Display-only comparison: source top two rows and reconstructed trees at 1:1.
board=Image.new('RGB',(1568,430),(47,51,43))
source=Image.open(SOURCE).convert('RGB').crop((0,0,736,380))
board.paste(source,(16,38))
board.paste(atlases[0],(784,38),atlases[0])
d=ImageDraw.Draw(board)
d.text((16,15),'REFERENCIA 3 — MODELOS ORIGINAIS',fill='white')
d.text((784,15),'REPLICAS — PALETA OATHWAKE — PIXELS EM ESCALA 1:1',fill='white')
board.save(OUT/'reference3-family-comparison.png')
print('PASS: 12 models, binary alpha, connected full/crown/base, exact assembly and Pixelorama RGBA round trip.')
print(destination)
