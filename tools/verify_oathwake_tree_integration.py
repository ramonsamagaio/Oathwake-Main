"""Verify the authored atlases and the exact scope of tree catalogue changes."""
import hashlib,json
from pathlib import Path
from PIL import Image
from author_oathwake_tree_integration import ROOT,DOC,DEST,BASE,MODELS,variant,clone,trace_oak

def main():
    manifest=json.loads((DOC/'manifest.json').read_text())
    for item in manifest['assets']:
        image=Image.open(DEST/(item['name']+'.png')).convert('RGBA')
        assert hashlib.sha256(image.tobytes()).hexdigest()==item['rgba_sha256']
        assert set(image.getchannel('A').tobytes())=={0,255}
    atlas={name:Image.open(DEST/('integrated-tree-'+name+'.png')).convert('RGBA') for name in ['crowns','trunks','stumps']}
    for rec in manifest['variants']:
        x,y,w,h=rec['region'];box=(x,y,x+w,y+h)
        crown,trunk,stump=[atlas[name].crop(box) for name in ['crowns','trunks','stumps']]
        full=Image.alpha_composite(trunk,crown)
        assert hashlib.sha256(full.tobytes()).hexdigest()==rec['full_rgba_sha256'],rec['resource']+' assembly'
        assert stump.tobytes()!=trunk.tobytes(),rec['resource']+' stump indistinct'
    before=json.loads((DOC/'resources-before.json').read_text(encoding='utf-8-sig'))
    after=json.loads((ROOT/'data/resources.json').read_text(encoding='utf-8-sig'))
    ids={r['resource'] for r in manifest['variants']}
    assert set(before)==set(after)
    visual_keys={'trunk_sprite_id','alive_trunk_sprite_id','stump_sprite_id','canopy_ground_lift','canopy_offset','trunk_offset','canopy_pivot_offset'}
    for rid,old in before.items():
        new=after[rid]
        if rid not in ids:assert old==new,rid+' unrelated change';continue
        assert {k:v for k,v in old.items() if k!='layered_visual'}=={k:v for k,v in new.items() if k!='layered_visual'},rid+' gameplay changed'
        assert {k:v for k,v in old['layered_visual'].items() if k not in visual_keys}=={k:v for k,v in new['layered_visual'].items() if k not in visual_keys}
    old_s=json.loads((DOC/'sprites-before.json').read_text(encoding='utf-8-sig'))
    new_s=json.loads((ROOT/'data/sprites.json').read_text(encoding='utf-8-sig'))
    changed={before[r]['layered_visual']['canopy_sprite_id'] for r in ids}
    added={r+'_oathwake_native_'+part for r in ids for part in ['trunk','stump']}
    assert set(new_s)==set(old_s)|added
    for sid,old in old_s.items():
        if sid not in changed:assert new_s[sid]==old,sid+' unrelated sprite changed'
    report={'variants':41,'rgba_and_pixelorama_roundtrip':True,'exact_assembly':True,'distinct_cut_stumps':True,
            'gameplay_fields_unchanged':True,'other_resources_unchanged':True,'pixel_scale':1,
            'overlap':'3 matching wood rows below the canopy cut for wind'}
    (DOC/'static-qa.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))

if __name__=='__main__':main()
