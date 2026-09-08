"""Read original asset contracts and prepare Godot/Pixelorama normalization jobs.
Pillow is used only for measuring source sprites, never writing production images.
Run once to prepare; --publish registers the verified exported art in ContentDB.
"""
import copy
import hashlib
import json
import shutil
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/resources'
DEST = ROOT / 'assets/sprites/world/procedural/terrain/oathwake_tilesets'
BASE = 'res://assets/sprites/world/procedural/terrain/oathwake_tilesets/'
GEN = Path('C:/Users/ramon/.codex/generated_images/01a07976-6f12-7372-af78-4bde91066a07')
INPUTS = {'flora': 'exec-ea333424-0fb5-40d2-b7cc-f45e06a89ba9.png',
          'trees': 'exec-15b7e957-b847-428c-af46-06f5b6f2dce0.png',
          'resources': 'exec-9c72b02f-4b1c-48cd-bde8-c9d802c736c2.png'}

def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p, v): p.write_text(json.dumps(v, indent='\t', ensure_ascii=False)+'\n', encoding='utf-8')

def sprite_record(path, rect, anchor):
    x,y,w,h=rect
    return dict(category='resource', columns=1, rows=1, total_frames=1,
        display_name='Oathwake tree base', type='single_sprite', frame_width=w,
        frame_height=h, frame_size={'w':w,'h':h}, region_enabled=True,
        region={'x':x,'y':y,'w':w,'h':h}, texture_path=path,
        anchor={'x':anchor[0],'y':anchor[1]}, tags=['oathwake','editable_png'],
        fade_when_player_behind=True, shadow_profile_id='auto')

def prepare():
    DOC.mkdir(exist_ok=True)
    (DOC/'source_copies').mkdir(exist_ok=True)
    (DOC/'generated').mkdir(exist_ok=True)
    for file in ['sprites.json','resources.json']:
        target=DOC/'source_copies'/file
        if not target.exists(): shutil.copy2(ROOT/'data'/file,target)
    for role,file in INPUTS.items(): shutil.copy2(GEN/file,DOC/'generated'/f'{role}.png')
    old=DEST/'flora_ground_plants.png'
    if not (DOC/'source_copies'/'flora_ground_plants-rejected.png').exists():
        shutil.copy2(old,DOC/'source_copies'/'flora_ground_plants-rejected.png')
        shutil.copy2(old.with_suffix('.pxo'),DOC/'source_copies'/'flora_ground_plants-rejected.pxo')
    sprites=load(DOC/'source_copies/sprites.json'); resources=load(DOC/'source_copies/resources.json')
    jobs={'trees':[], 'sheets':{}, 'provenance':INPUTS}
    maps={}
    for n in range(2,43):
        rid=f'tree{n}'; v=resources[rid]['layered_visual']; sid=v['canopy_sprite_id'];s=sprites[sid]
        reg=s['region']; im=Image.open(ROOT/s['texture_path'][6:]).convert('RGBA')
        box=tuple(int(reg[k]) for k in ['x','y'])+(int(reg['x']+reg['w']),int(reg['y']+reg['h']))
        bbox=im.crop(box).getbbox(); bw=bbox[2]-bbox[0]; bh=bbox[3]-bbox[1]
        if n<10: seed=[0,1,2,10,11,2,0,1][n-2]
        elif n<12: seed=3
        elif n==12: seed=4
        elif n<41: seed=[4,6,5,7][(n-13)//7]
        else: seed=8 if n==41 else 9
        jobs['trees'].append(dict(resource=rid,sprite=sid,index=n-2,seed=seed,
            max_size=[max(18,min(72,bw)),max(30,min(104,bh+8))],mirror=n in [8,9,11,17,23,30,37],
            source=s['texture_path'],source_region=reg))
    for sid,s in sprites.items():
        path=s.get('texture_path','')
        if not path.startswith('res://assets/sprites/world/procedural/') or '/trees/' in path or '/terrain/' in path: continue
        if not sid.startswith('romestead_'): continue
        n=int(sid.rsplit('_',1)[-1]) if sid.rsplit('_',1)[-1].isdigit() else 0
        seed=None
        if sid.startswith('romestead_rock_'): seed=(n-1)%6
        elif sid.startswith('romestead_stone_'): seed=(n-1)%5
        elif sid.startswith('romestead_bush_'): seed=6+(n-1)%6
        elif sid.startswith('romestead_wheat_'): seed=12+(n-1)%4
        else: seed={'romestead_mossy_boulder':5,'romestead_bellflower':16,'romestead_lily':17,
          'romestead_mushroom_red':18,'romestead_mushroom_brown':19,'romestead_mushroom_yellow':20,
          'romestead_copper_ore':21,'romestead_purple_bush':22,'romestead_forest_bush':23}.get(sid)
        if seed is None: continue
        source=ROOT/path[6:];im=Image.open(source).convert('RGBA');reg=s['region'];r=[int(reg[k]) for k in ['x','y','w','h']]
        frame=im.crop((r[0],r[1],r[0]+r[2],r[1]+r[3]));box=frame.getbbox()
        if box is None: raise ValueError(sid)
        name=source.name
        if name not in jobs['sheets']:
            jobs['sheets'][name]={'source':path,'size':list(im.size),'cells':[]}
            backup=DOC/'source_copies'/name
            if not backup.exists():shutil.copy2(source,backup)
        jobs['sheets'][name]['cells'].append(dict(sprite=sid,rect=r,seed=seed,
            max_size=[box[2]-box[0],box[3]-box[1]], baseline=box[3],mirror=n%2==0))
        maps[sid]=BASE+'resources/'+name
    jobs['sprite_paths']=maps
    save(DOC/'normalization-jobs.json',jobs)
    print(json.dumps({'trees':len(jobs['trees']), 'other_sprites':len(maps), 'sheets':len(jobs['sheets'])}))

def publish():
    jobs=load(DOC/'normalization-jobs.json')
    sprites=load(ROOT/'data/sprites.json');resources=load(ROOT/'data/resources.json')
    for sid,path in jobs['sprite_paths'].items():
        assert (ROOT/path[6:]).exists(),path
        sprites[sid]['texture_path']=path
    for job in jobs['trees']:
        rid=job['resource'];i=job['index'];sid=job['sprite'];s=sprites[sid]
        s.update(sprite_record(BASE+'resources/tree_crowns.png',[(i%8)*128,(i//8)*112,128,112],[64,112]))
        s['display_name']=f'Oathwake {rid} crown'
        alive=f'oathwake_{rid}_trunk';stump=f'oathwake_{rid}_stump'
        for j,key in enumerate([alive,stump]):
            frame=i*2+j;sprites[key]=sprite_record(BASE+'resources/tree_trunks.png',[(frame%16)*64,(frame//16)*32,64,32],[32,32])
            sprites[key]['display_name']=f'Oathwake {rid} '+('living base' if j==0 else 'cut stump')
        v=resources[rid]['layered_visual']
        v.update(trunk_sprite_id=alive,alive_trunk_sprite_id=alive,stump_sprite_id=stump,
                 trunk_offset={'x':0,'y':0},canopy_offset={'x':0,'y':0},canopy_ground_lift=-8)
    save(ROOT/'data/sprites.json',sprites);save(ROOT/'data/resources.json',resources)
    print('Registered 41 crown/base pairs and',len(jobs['sprite_paths']),'other resource sprites.')

if __name__=='__main__':
    publish() if '--publish' in sys.argv else prepare()
