"""Pixelorama-native tree states and narrow ContentDB integration, no resizing."""
import copy,hashlib,json,math,sys
from pathlib import Path
from author_oathwake_native import Canvas,color,requests_for,OUT
from trace_oathwake_reference import MODELS,LEAF,WOOD,trace_oak

ROOT=Path(__file__).resolve().parents[1]
DOC=OUT/'integration'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets/resources/reference3_native'
BASE='res://assets/sprites/world/procedural/terrain/oathwake_tilesets/resources/reference3_native/'
CUT=list(map(color,['5b503d','8a7853','a39065','c0a77c','d0ba8f']))
SEASONS=[
 ['293730','344638','42543f','536548','667850','7a895b','8e9a65','a2a976','b6b888','c8c799'],
 ['273730','304337','3c5040','4b6048','5b704f','6d805b','839069','99a07a','adb28c','bfc59d'],
 ['32392f','424a36','535b3f','666c47','7c7e51','93915f','a4a16e','b4af7f','c3bd93','d0cba6'],
 ['34352b','4d4530','5f5338','706041','84714c','99825a','aa926b','b7a07c','c2ae8a','cdba9a'],
 ['36312b','4b3e30','615039','785e40','8c704c','9e825b','ad926c','bda27c','cbb28e','d3c19f'],
 ['382e2a','4d3930','644738','7b5742','90694f','a17e60','b18e71','c0a080','cdb491','d9c4a3'],
 ['372d2b','4b3733','60453d','78534a','8b6557','a07968','b28c78','c29e88','cdb29a','d8c3ac'],
]

def clone(c,mirror=False,season=None):
    out=Canvas(c.w,c.h)
    mapping={a:color(b) for a,b in zip(LEAF,SEASONS[season])} if season is not None else {}
    for (x,y),co in c.p.items():out.dot(c.w-1-x if mirror else x,y,mapping.get(co,co),c.kind[x,y])
    return out

def stump_for(base,cut):
    stump=Canvas(base.w,base.h)
    for (x,y),co in base.p.items():
        if y>=cut:stump.dot(x,y,co,'wood')
    neck=[x for x,y in stump.p if y==cut+1]
    assert neck,'No wood at the cut'
    cx=(min(neck)+max(neck))/2;rx=max(3,(max(neck)-min(neck))/2+1);ry=max(2,min(4,int(rx/3)))
    for y in range(cut-ry,cut+ry+1):
        for x in range(math.floor(cx-rx),math.ceil(cx+rx)+1):
            radial=((x-cx)/rx)**2+((y-cut)/ry)**2
            if radial>1:continue
            shade=0 if radial>.79 else 1 if radial>.55 else 3
            if .17<radial<.28:shade=1
            if y<cut and .3<radial<.58:shade=4
            stump.dot(x,y,CUT[shade],'wood')
    assert len(stump.components())==1
    return stump,cx

def variant(n):
    # Preserve catalogue families and the seven seasonal rows. Native-size
    # models replace the former differently scaled columns; no texture shrink.
    if n<10:return [0,1,0,11,5,8,10,2][n-2],n==4,None
    if n<12:return 3,n==11,None
    if n==12:return 4,False,None
    if n<41:
        row,col=divmod(n-13,4)
        return [1,4,1,4][col],col>=2,row
    return (9,False,None) if n==41 else (7,False,None)

def prepare():
    DOC.mkdir(exist_ok=True,parents=True)
    models=[trace_oak(m)[:3] for m in MODELS]
    atlases={name:Canvas(1024,1152) for name in ['crowns','trunks','stumps']}
    records=[]
    for n in range(2,43):
        index,mirror,season=variant(n);model=MODELS[index]
        full,crown,trunk=[clone(part,mirror,season) for part in models[index]]
        cut=model['cut']-model['origin'][1];anchor=list(model['anchor'])
        if mirror:anchor[0]=127-anchor[0]
        for (x,y),co in trunk.p.items():
            if y<cut+3:crown.dot(x,y,co,'wood')
        # Three matching wood rows overlap only to cover the joint during wind.
        assert {**trunk.p,**crown.p}==full.p
        assert all(full.p[p] in WOOD for p in set(trunk.p)&set(crown.p))
        stump,cx=stump_for(trunk,cut)
        frame=n-2;x=(frame%8)*128;y=(frame//8)*192
        for name,part in [('crowns',crown),('trunks',trunk),('stumps',stump)]:
            assert len(part.components())==1,(n,name)
            atlases[name].paste(part,x,y)
        records.append({'resource':'tree'+str(n),'model':model['name'],'model_index':index,'mirror':mirror,'season':season,
                        'frame':frame,'region':[x,y,128,192],'anchor':anchor,'cut_y':cut,
                        'pivot':[cx-anchor[0],cut-anchor[1]],'full_rgba_sha256':hashlib.sha256(full.bytes()).hexdigest()})
    calls=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}];assets=[]
    for name,atlas in atlases.items():
        req,rec=requests_for('integrated-tree-'+name,atlas);calls+=req;assets.append(rec)
    (DOC/'requests.json').write_text(json.dumps(calls))
    (DOC/'manifest.json').write_text(json.dumps({'variants':records,'assets':assets,'overlap_wood_rows':3,'pixel_scale':1},indent=2))
    print('Prepared 41 native-size variants; three wood rows overlap at the moving joint; three Pixelorama atlases.')

def sprite_record(path,rec,label):
    x,y,w,h=rec['region']
    return {'category':'resource','columns':1,'rows':1,'total_frames':1,'display_name':label,
            'type':'single_sprite','frame_width':w,'frame_height':h,'frame_size':{'w':w,'h':h},
            'region_enabled':True,'region':{'x':x,'y':y,'w':w,'h':h},'texture_path':path,
            'anchor':{'x':rec['anchor'][0],'y':rec['anchor'][1]},'tags':['oathwake','editable_png'],
            'fade_when_player_behind':True,'shadow_profile_id':'auto'}

def publish():
    import shutil
    from PIL import Image
    manifest=json.loads((DOC/'manifest.json').read_text())
    for item in manifest['assets']:
        path=OUT/(item['name']+'.png');im=Image.open(path).convert('RGBA')
        assert hashlib.sha256(im.tobytes()).hexdigest()==item['rgba_sha256']
        for ext in ['.png','.pxo']:shutil.copy2(OUT/(item['name']+ext),DEST/(item['name']+ext))
    resources=json.loads((ROOT/'data/resources.json').read_text(encoding='utf-8-sig'))
    sprites=json.loads((ROOT/'data/sprites.json').read_text(encoding='utf-8-sig'))
    for rec in manifest['variants']:
        rid=rec['resource'];v=resources[rid]['layered_visual'];crown_id=v['canopy_sprite_id']
        alive=rid+'_oathwake_native_trunk';stump=rid+'_oathwake_native_stump'
        for sid,role in [(crown_id,'crowns'),(alive,'trunks'),(stump,'stumps')]:
            replacement=sprite_record(BASE+'integrated-tree-'+role+'.png',rec,'Oathwake '+rid+' '+role)
            sprites[sid]={**sprites.get(sid,{}),**replacement}
        v.update(trunk_sprite_id=alive,alive_trunk_sprite_id=alive,stump_sprite_id=stump,
                 canopy_ground_lift=0,canopy_offset={'x':0,'y':0},trunk_offset={'x':0,'y':0},
                 canopy_pivot_offset={'x':rec['pivot'][0],'y':rec['pivot'][1]})
    for name,data in [('resources',resources),('sprites',sprites)]:
        (ROOT/'data'/f'{name}.json').write_text(json.dumps(data,ensure_ascii=False,indent='\t')+'\n',encoding='utf-8')
    shutil.copy2(DOC/'manifest.json',DEST/'integrated-tree-manifest.json')
    print('Registered 41 tree variants; changed visual fields only. Other resources were not republished.')

if __name__=='__main__':publish() if '--publish' in sys.argv else prepare()
