"""Native 16px ground botany, authored as explicit pixel maps in Pixelorama.

Pillow is only used after editor export for QA/review. No resampling in authoring.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import author_oathwake_native as native
from author_oathwake_native import Canvas, color

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/resources/native/ground-details'
DEST=ROOT/'assets/sprites/world/procedural/terrain/oathwake_tilesets'
PAL={str(i):color(h) for i,h in enumerate(['293730','344638','42543f','536548','7a895b','a2a976'])}
PAL.update({k:color(h) for k,h in {
    'a':'817959','b':'a69d76','c':'d0c6a0',
    'v':'625669','w':'8b7b92','x':'aa929a',
    'd':'686744','e':'8a8051','f':'a39065'}.items()})

# Rows are literal native pixels. Each cell is centered, never scaled.
# Columns0..3 dense,4..7 sparse; column8 is a prepared, unused reserve.
MEADOW=[
('broad_rosette',[
 '.....51....','....543....','....432.41.','..41.32.542',
 '.542.32.432','..43222132.','...432343..','.544334543.',
 '..43343221.','....2221...']),
('round_clover',[
 '....541....','...54431...','...43321...','....332....',
 '.541.32.541','54432325443','43332334332','.332343332.',
 '..233432...','....221....']),
('fern_spray',[
 '......41....','..41..54....','..543.32.41.','.1.43232.543',
 '.541.2324321','..432232321.','...232332...',
 '.541234.541.','..4334324321','...23333221.','.....221....']),
('low_fan',[
 '....41.....','...543.....','...432.541.','.41.3225432',
 '15432324321','..43232432.','...234332..','.544343541.',
 '..43333221.','....221....']),
('two_leaves',[
 '.541.....','54432....','.432.41..','..3225431','...234321','....221..']),
('sprout',[
 '..41....','..543...','..432...','...32.41','.4132543','15433321',
 '..23221.','...21...']),
('paired_round',[
 '.541...','54431..','43321..','.332...','..32541','..25443','...3321','....21.']),
('small_blades',[
 '...4....','...54...','.4.32..4','.5432.54','..432432','...2332.','....21..']),
('reserve_leaf_fall',[
 '...ef1....','..effd....','.efdd1.41.','..ddd.1543',
 '...dd.4321','....d332..','.....221..'])]

FOREST=[
('woodland_rosette',[
 '.....41....','.....54....','..41.43....','..54332.41.','..43232.543',
 '...32234321','.413223432.','154323343..','..433343541','...23333221','.....221...']),
('wood_sorrel',[
 '.....41.....','....543.....','....432.....','.41..32.41..','1543.325543.',
 '.4322324332.','..233233321.','....23432...', '.5412343541.',
 '..4334334321','....232221..','.....21.....']),
('shade_fern',[
 '......4.....','.....541....','..41.432....','..54332.41..','...43232543.',
 '.41.2324321.','1543232332..','..433233.41.','....23432543',
 '.54123434321','..433332221.','.....221....']),
('long_blades',[
 '.....4......','.....54.....','..4..43..4..','..54.32.54..','..43232.43..',
 '...3232432..','.4.323232.41','154323232543','..4332344321','...2333432..','.....221....']),
('woodland_pair',[
 '..41....','..543...','..432...','...32.41','...32543','.4134321','1543321.','..221...']),
('shade_sprout',[
 '...4...','...54..','...43..','.4132..','15432..','.433241','..23543','...3321','....21.']),
('folded_leaf',[
 '....41..','...543..','..5432..','...332..','.41.32..','15433241',
 '.4332543','..232321','...221..']),
('wood_grass',[
 '....4....','....54...','..4.43...','..5432..4','...432.54',
 '.4.232432','15432332.','..43321..','...221...']),
('reserve_dry_fern',[
 '.....e....','....ef1...','..e.edd...','..efdd..e.','.1.ddd.ef1',
 '.efd2ddfd1','..ddd2dd..','....232...','.4.233541.','154333321.','..22221...'])]

FLOWERS=[
('ivory_star',[
 '..b.....','..cb....','.ccac...','..bc....','...3.41.',
 '.4131543','15433321','..23321.','...221..']),
('ochre_buds',[
 '...b....','..bca...','...a....','.bc3..b.','.ba3.bca',
 '..323.a.','.432323.','..33341.','...25431','....221.']),
('woodland_ivory',[
 '....b....','...bca...','....a....','....3..b.',
 '..bc3.bca','..ba3..a.','...32323.','.4132432.','15433321.',
 '..23221..','...21....']),
('woodland_violet',[
 '....w....','...wxv...','....v....','..wx3....','..wv3.w..',
 '...32wxv.','...323v..','.413232..','15433341.','..2325431','...22221.'])]


def cell(rows):
    w=max(map(len,rows));h=len(rows)
    assert w<=12 and h<=12
    c=Canvas(16,16);ox=(16-w)//2;oy=(16-h)//2
    for y,row in enumerate(rows):
        for x,s in enumerate(row):
            if s!='.':c.dot(ox+x,oy+y,PAL[s],'petal' if s in 'abcvwx' else 'leaf')
    assert len(c.components())==1,('disconnected pixels',rows,[len(a) for a in c.components()])
    return c


def build():
    result=[]
    for name,cols,specs in [('flora_tiny_ground_leaves',9,MEADOW+FOREST),('flora_tiny_flowers',2,FLOWERS)]:
        atlas=Canvas(cols*16,32);records=[]
        for i,(kind,rows) in enumerate(specs):
            c=cell(rows);atlas.paste(c,i%cols*16,i//cols*16)
            records.append({'name':kind,'cell':[i%cols,i//cols],
                'active':name=='flora_tiny_flowers' or i%cols<8,
                'opaque_pixels':len(c.p),'components':1})
        result.append((name,atlas,records))
    return result


def verify(publish=False):
    from PIL import Image,ImageDraw
    reports=[]
    for name,atlas,records in build():
        im=Image.open(OUT/(name+'.png')).convert('RGBA')
        assert im.size==(atlas.w,atlas.h) and im.tobytes()==atlas.bytes(),name
        assert set(im.getchannel('A').tobytes())=={0,255}
        assert (OUT/(name+'.pxo')).stat().st_size>0
        for p,co in atlas.p.items():
            assert 2<=p[0]%16<=13 and 2<=p[1]%16<=13,('cell gutter',p)
        reports.append({'file':name+'.png','size':[atlas.w,atlas.h],
            'rgba_sha256':hashlib.sha256(im.tobytes()).hexdigest(),'colors':len(set(atlas.p.values())),
            'opaque_pixels':len(atlas.p),'frames':records,'pixelorama_roundtrip':True})
    (OUT/'qa.json').write_text(json.dumps({'assets':reports,'active_frames':20,'reserve_frames':2,
        'alpha':'binary','authorship':'Explicit 16x16 pixel maps via Pixelorama; no source resampling.'},indent=2))
    # Review-only enlargement of the actual editor export, plus native samples.
    board=Image.new('RGB',(960,440),(38,44,37));draw=ImageDraw.Draw(board)
    index=0
    for name,atlas,records in build():
        im=Image.open(OUT/(name+'.png')).convert('RGBA')
        for r in records:
            x=(index%8)*120;y=(index//8)*140
            cx,cy=r['cell'];crop=im.crop((cx*16,cy*16,cx*16+16,cy*16+16))
            enlarged=crop.resize((80,80),Image.Resampling.NEAREST)
            board.paste(enlarged,(x+20,y+5),enlarged)
            board.paste(crop,(x+8,y+104),crop)
            draw.text((x+30,y+103),r['name'].replace('_','\n'),fill=(183,191,168))
            index+=1
    board.save(OUT/'atlas-review.png')
    for name in ['on-terrain','cluster-after','cluster-before']:
        capture=OUT/(name+'-native.png')
        if capture.exists():
            im=Image.open(capture)
            im.resize((im.width*3,im.height*3),Image.Resampling.NEAREST).save(OUT/(name+'.png'))
    if publish:
        manifest_path=ROOT/'docs/terrain/oathwake-tilesets-manifest.json'
        manifest=json.loads(manifest_path.read_text())
        for report in reports:
            rec=next(r for r in manifest['assets'] if r['file']==report['file'])
            assert hashlib.sha256(Path(rec['source']).read_bytes()).hexdigest()==rec['source_sha256']
            original=Image.open(rec['source']).convert('RGBA')
            new=Image.open(OUT/rec['file']).convert('RGBA')
            a=list(original.get_flattened_data());b=list(new.get_flattened_data())
            rec.update(expected_rgba_sha256=report['rgba_sha256'],pixel_count=report['opaque_pixels'],
                changed_pixels=sum(x!=y for x,y in zip(a,b)),alpha_changes=sum(x[3]!=y[3] for x,y in zip(a,b)),
                revision='2026-09-08 native16 Pixelorama ground details; docs/resources/native/ground-details/qa.json')
        for report in reports:
            path=Path(report['file'])
            for ext in ['.png','.pxo']:shutil.copy2(OUT/path.with_suffix(ext),DEST/path.with_suffix(ext))
        manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'verified_assets':len(reports),'active_frames':20,'reserve_frames':2,'published':publish}))


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--verify' in sys.argv or '--publish' in sys.argv:verify('--publish' in sys.argv)
    else:
        calls=[{'tool':'pixelorama_status'},{'tool':'pixelorama_project_info'}];expected=[]
        native.OUT=OUT
        for name,atlas,records in build():
            for ext in ['.png','.pxo']:
                dest=OUT/('before-'+name+ext)
                if not dest.exists():shutil.copy2(DEST/(name+ext),dest)
            request,rec=native.requests_for(name,atlas);calls+=request;expected.append(rec)
        (OUT/'requests.json').write_text(json.dumps(calls))
        (OUT/'expected.json').write_text(json.dumps(expected,indent=2))
        print(json.dumps({'atlases':2,'requests':len(calls),'frames':22}))
