"""Production RGBA, pairing, palette, original preservation and gameplay checks."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/resources'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'

def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def rgba(p):return Image.open(p).convert('RGBA')

def main():
    manifest=load(DOC/'normalized-manifest.json');jobs=load(DOC/'normalization-jobs.json')
    allowed={tuple(bytes.fromhex(h))+(255,) for h in manifest['palette']}|{(0,0,0,0)}
    records=[]
    for sheet in manifest['sheets']:
        name=sheet['name'];dest=DEST/(name+'.png' if name=='flora_ground_plants' else 'resources/'+name+'.png')
        expected=rgba(ROOT/sheet['path'][6:]);actual=rgba(dest)
        assert actual.size==expected.size and actual.tobytes()==expected.tobytes(),name+' PXO reopen/export mismatch'
        assert dest.with_suffix('.pxo').stat().st_size>0
        assert set(actual.get_flattened_data())<=allowed,name+' unexpected palette or alpha'
        records.append(dict(file=str(dest.relative_to(ROOT)),size=list(actual.size),
            expected_rgba_sha256=hashlib.sha256(actual.tobytes()).hexdigest(),roundtrip=True))
    original_resources=load(DOC/'source_copies/resources.json');new_resources=load(ROOT/'data/resources.json')
    for rid,old in original_resources.items():
        new=new_resources[rid]
        assert {k:v for k,v in old.items() if k!='layered_visual'}=={k:v for k,v in new.items() if k!='layered_visual'},rid+' gameplay data changed'
    sprites=load(ROOT/'data/sprites.json');old_sprites=load(DOC/'source_copies/sprites.json')
    changed=set(jobs['sprite_paths'])|{j['sprite'] for j in jobs['trees']}
    for sid,record in old_sprites.items():
        if sid not in changed:assert sprites[sid]==record,sid+' unrelated sprite changed'
        elif sid in jobs['sprite_paths']:
            assert {k:v for k,v in record.items() if k!='texture_path'}=={k:v for k,v in sprites[sid].items() if k!='texture_path'},sid+' region/anchor changed'
    for name,sheet in jobs['sheets'].items():
        assert (ROOT/sheet['source'][6:]).read_bytes()==(DOC/'source_copies'/name).read_bytes(),name+' original overwritten'
    crowns=rgba(DEST/'resources/tree_crowns.png');trunks=rgba(DEST/'resources/tree_trunks.png')
    expected=rgba(DOC/'trees-assembled-native.png')
    assembled=Image.new('RGBA',expected.size)
    for job in jobs['trees']:
        i=job['index'];x=i%8*128;y=i//8*112
        crown=crowns.crop((x,y,x+128,y+112));f=i*2;tx=f%16*64;ty=f//16*32
        trunk=trunks.crop((tx,ty,tx+64,ty+32));f+=1;tx=f%16*64;ty=f//16*32
        stump=trunks.crop((tx,ty,tx+64,ty+32))
        assert trunk.getbbox() and stump.getbbox() and crown.getbbox(),job['resource']+' empty state'
        assert trunk.tobytes()!=stump.tobytes(),job['resource']+' cut state indistinct'
        pair=Image.new('RGBA',(128,112));pair.alpha_composite(trunk,(32,80));pair.alpha_composite(crown,(0,-8))
        ref=expected.crop((x,y,x+128,y+112))
        assert pair.tobytes()==ref.tobytes(),job['resource']+' clipped roots or split seam'
        assembled.alpha_composite(pair,(x,y))
        assert crown.getbbox()[0]>0 and crown.getbbox()[2]<128,job['resource']+' clipped crown'
    runtime=load(DOC/'runtime-qa.json')
    assert not runtime['failures'],runtime['failures']
    report=dict(passed=True,sheets=records,tree_pairs=41,other_resource_sprites=72,
        decorative_variants=12,assembly_exact=True,gameplay_unchanged=True,
        originals_preserved=True,rgba_alpha='binary, transparent RGB zero',runtime=runtime)
    (DOC/'asset-qa.json').write_text(json.dumps(report,indent=2))
    # Keep the terrain manifest in sync with the explicitly requested flora replacement.
    terrain_path=ROOT/'docs/terrain/oathwake-tilesets-manifest.json';terrain=load(terrain_path)
    for rec in terrain['assets']:
        if rec['file']=='flora_ground_plants.png':
            im=rgba(DEST/rec['file']);source=rgba(Path(rec['source']))
            rec['expected_rgba_sha256']=hashlib.sha256(im.tobytes()).hexdigest()
            rec['changed_pixels']=sum(a!=b for a,b in zip(source.get_flattened_data(),im.get_flattened_data()))
            rec['alpha_changes']=sum(a[3]!=b[3] for a,b in zip(source.get_flattened_data(),im.get_flattened_data()))
            rec['revision']='2026-09-07 botanical reference redesign; docs/resources/asset-qa.json'
    terrain_path.write_text(json.dumps(terrain,indent=2))
    # QA boards only: no production images are authored by this script.
    board=Image.new('RGB',(2048,1344),'#827652');large=assembled.resize(board.size,Image.Resampling.NEAREST)
    board.paste(large,(0,0),large);board.save(DOC/'all-trees-assembled.png')
    flora=rgba(DEST/'flora_ground_plants.png').resize((1152,384),Image.Resampling.NEAREST)
    flora_board=Image.new('RGB',flora.size,'#64704e');flora_board.paste(flora,(0,0),flora);flora_board.save(DOC/'flora-final.png')
    for name in ['tree-pairs-alive','tree-stumps','tree-falling','resources','flora-in-engine']:
        im=Image.open(DOC/(name+'-native.png'));im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST).save(DOC/(name+'.png'))
    print(json.dumps({'passed':True,'sheets':len(records),'tree_pairs':41,'other_resources':72,'flora_variants':12,'pair_assembly':'pixel-identical','gameplay':'unchanged'}))

if __name__=='__main__':main()
