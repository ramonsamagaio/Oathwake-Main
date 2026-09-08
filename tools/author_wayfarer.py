"""Author exact pixel payloads for Pixelorama MCP; never writes artwork PNGs.
Pillow is used only to read the original and verify the bridge export.
The source rig's rectangles and anatomy are retained; costume clusters are redrawn.
"""
import base64
import gzip
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/characters/wayfarer'
ASSET = ROOT / 'assets/sprites/characters'
TRANSPARENT = (0, 0, 0, 0)
def color(h): return tuple(bytes.fromhex(h)) + (255,)
HAIR = list(map(color, ['241e24','35282b','493337','63463d','805949','a37457']))
NAVY = list(map(color, ['191c2a','282b40','393e58','505975','69728a']))
LEATHER = list(map(color, ['251e21','3b2929','563b31','78513b','a27550']))
LINEN = list(map(color, ['827c82','b5aaa0','e0d1b8']))
SKIN = list(map(color, ['684238','986047','c38a61','e2ae7d','f0c697']))
GOLD = list(map(color, ['88572b','c79242','f0c571']))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original = Image.open(ASSET / 'JUNOBASE.png').convert('RGBA')
    w, h = original.size
    data = list(original.get_flattened_data())
    mapping = json.loads((ROOT / 'data/labs/alabaster/juno_base_compact_map.json').read_text())
    audit = json.loads((ROOT / 'data/labs/alabaster/juno_base_sprite_audit.json').read_text())
    runtime = json.loads(gzip.decompress(base64.b64decode((ROOT / 'data/labs/alabaster/juno_runtime.json.gz.b64').read_text())))
    lookup = {tuple(c[k] for k in ('x','y','w','h')): c for c in audit['kept_cells']}
    manifest = []
    for entry in mapping['entries']:
        s, p = entry['source'], entry['packed']
        owners = lookup[tuple(s[k] for k in ('x','y','w','h'))]['owners']
        owner = owners[0]
        node = owner['node']
        cw, ch = p['w'], p['h']
        cell = [[original.getpixel((p['x']+x,p['y']+y)) for x in range(cw)] for y in range(ch)]
        before = [row[:] for row in cell]
        gfx = runtime['figure']['nodes'][node]['gfx'][owner['gfx_index']]
        tex = gfx['tex'].get('multi',{}).get('entries',{}).get(owner['entry'],{})
        rr = tex.get('range',[s['x'],s['y'],cw,ch])
        tile = (s['x']-rr[0])//cw
        def put(x,y,c,inside=False):
            if 0 <= x < cw and 0 <= y < ch and (not inside or before[y][x][3]): cell[y][x]=c
        for y in range(ch):
            for x in range(cw):
                r,g,b,a = before[y][x]
                if not a: continue
                lum = (r+g+b)/3
                if node in ('tailEnd','headGear'):
                    cell[y][x] = TRANSPARENT
                elif node == 'head':
                    # Warm source skin is separated from violet/silver hair.
                    skin = r > g*1.18 and g > b*1.10 and r > 70
                    eye = y > ch//2 and r > 235 and g > 220 and b > 215
                    if skin:
                        cell[y][x] = SKIN[min(4,max(0,int((lum-55)/32)))]
                    elif eye:
                        cell[y][x] = LINEN[2]
                    else:
                        level = min(5,max(0,int((lum-35)/40)))
                        # Broken diagonal locks replace the smooth silver helmet highlight.
                        lock_x = x - min(2,tile//3)
                        if (4 <= y <= 7 and 5 <= lock_x+y//2 <= 8) or (7 <= y <= 11 and 10 <= lock_x+y//3 <= 12):
                            level=max(1,level-2)
                        cell[y][x]=HAIR[level]
                elif node == 'top' or node.startswith('arm'):
                    if r > g*1.35 and r > b*1.12:
                        cell[y][x] = NAVY[min(4,max(0,int((r-50)/42)))]
                    elif r > 160 and g > 115 and b < 80:
                        cell[y][x] = LEATHER[2]
                    elif lum < 80:
                        cell[y][x] = NAVY[0 if lum < 35 else 1]
                elif node.startswith(('hand','finger')):
                    if r > g*1.2 and g > b*1.05:
                        cell[y][x]=SKIN[min(4,max(0,int((lum-50)/30)))]
                    else: cell[y][x]=LEATHER[min(4,int(lum/45))]
                    # Fingerless leather guards retain the exposed distal fingers.
                    if y < ch//2+1: cell[y][x]=LEATHER[min(3,max(0,int(lum/55)))]
                elif node.startswith(('foot','toe')):
                    cell[y][x]=LEATHER[min(4,max(0,int(lum/35)))]
                elif node.startswith('leg'):
                    cell[y][x]=color(['23222d','363440','4b4855','625c67'][min(3,int(lum/40))])
                elif node == 'bottom':
                    cell[y][x] = LEATHER[min(3,int(lum/45))] if y < ch//2 else NAVY[min(3,int(lum/45))]
        if node == 'head':
            # Short jagged nape, no Juno side strands; add crown cowlicks.
            for y in range(ch-4,ch):
                for x in range(cw):
                    if cell[y][x] in HAIR and (x < 6 or x > 14): put(x,y,TRANSPARENT)
            if owner['row'] in (0,1):
                shift = min(3,tile//2)
                for x,y,c in [(7+shift,1,HAIR[1]),(8+shift,1,HAIR[2]),(8+shift,2,HAIR[3]),(5+shift,3,HAIR[2]),(4+shift,4,HAIR[2]),(15,5,HAIR[1]),(16,4,HAIR[1])]: put(x,y,c)
            if tile <= 2 and owner['row'] == 0:
                # Uneven fringe, dark eyes and larger warm face clusters.
                for x,y,c in [(8,10,HAIR[2]),(8,11,HAIR[3]),(9,11,HAIR[2]),(9,12,HAIR[1]),(11,10,HAIR[3]),(11,11,HAIR[2]),(7,13,LINEN[2]),(8,13,HAIR[0]),(8,14,HAIR[0]),(12,13,HAIR[0]),(12,14,HAIR[0]),(13,13,LINEN[2])]:
                    put(x+min(tile,2),y,c,True)
        elif node == 'top' and cw == 12 and ch == 12:
            # Direction-aware linen collar and diagonal satchel harness.
            front = tile in (0,1,2,14,15)
            for y in range(3,10):
                x = (3+y//2) if tile < 8 else (8-y//2)
                put(x,y,LEATHER[1],True); put(x+1,y,LEATHER[3],True)
            if front:
                for x,y in [(4,2),(4,3),(5,4),(6,4),(7,3),(7,2)]: put(x,y,LINEN[2],True)
                put(5,3,SKIN[2],True); put(6,3,SKIN[3],True)
                put(4,6,GOLD[1],True); put(4,7,GOLD[2],True)
            elif tile in (7,8,9):
                for x in range(4,8): put(x,2,LINEN[1],True)
        elif node == 'bottom':
            for x in range(2,cw-2):
                put(x,ch//2,LEATHER[2],True)
            if tile <= 2:
                for x,y,c in [(5,ch//2,GOLD[1]),(6,ch//2,GOLD[2]),(5,ch//2+1,GOLD[1]),(6,ch//2+1,LEATHER[0])]: put(x,y,c,True)
            # Pouch follows the hips, within the existing cut rectangle.
            side = cw-3 if tile < 5 else 2
            for y in range(ch//2+1,ch-1):
                put(side,y,LEATHER[1],True); put(side-1,y,LEATHER[3],True)
            put(side-1,ch//2+2,GOLD[1],True)
        elif node.startswith('arm'):
            for x in range(cw): put(x,ch-3,LINEN[1],True); put(x,ch-4,LINEN[2],True)
        elif node.startswith('foot'):
            for x in range(cw): put(x,3,LEATHER[3],True)
            put(cw//2,4,GOLD[0],True)
        for y in range(ch):
            for x in range(cw): data[(p['y']+y)*w+p['x']+x]=cell[y][x]
        enriched_owners = []
        for item in owners:
            nd = runtime['figure']['nodes'][item['node']]
            gd = nd['gfx'][item['gfx_index']]
            enriched_owners.append({**item,'billboard':gd.get('shape',{}).get('billboard',{}),'gfx_position':gd.get('pos',[0,0,0]),'texture_definition':gd['tex'].get('multi',{}).get('entries',{}).get(item['entry'],{}),'node_definition':{k:v for k,v in nd.items() if k not in ('gfx','frameAnims','frameKeys')}})
        manifest.append({**entry,'owners':enriched_owners,'billboard':gfx.get('shape',{}).get('billboard',{}),'node_definition':{k:v for k,v in runtime['figure']['nodes'][node].items() if k not in ('gfx','frameAnims','frameKeys')},'texture_definition':tex,'tile_index':tile,'changed_pixels':sum(cell[y][x]!=before[y][x] for y in range(ch) for x in range(cw)),'art_policy':'intentionally transparent: short hair, no ornament' if node in ('tailEnd','headGear') else 'redesigned costume / hair clusters'})
    payload = [[i%w,i//w,*c] for i,c in enumerate(data) if c[3]]
    requests=[{'tool':'pixelorama_status'},{'tool':'pixelorama_create_project','args':{'name':'Oathwake Wayfarer - JUNO compatible','width':w,'height':h,'frame_count':1}}]
    requests += [{'tool':'pixelorama_set_pixels','args':{'frame':0,'pixels':payload[i:i+4000]}} for i in range(0,len(payload),4000)]
    requests += [{'tool':'pixelorama_save_project','args':{'path':str(ASSET/'WAYFARER.pxo')}},{'tool':'pixelorama_open_project','args':{'path':str(ASSET/'WAYFARER.pxo')}},{'tool':'pixelorama_export_spritesheet','args':{'path':str(ASSET/'WAYFARER.png'),'frame_count':1,'columns':1}},{'tool':'pixelorama_project_info'}]
    (OUT/'author-requests.json').write_text(json.dumps(requests))
    (OUT/'atlas-manifest.json').write_text(json.dumps({'size':[w,h],'original_sha256':hashlib.sha256((ASSET/'JUNOBASE.png').read_bytes()).hexdigest(),'expected_rgba_sha256':hashlib.sha256(bytes(v for c in data for v in c)).hexdigest(),'entries':manifest},indent=2))
    print(json.dumps({'size':[w,h],'cells':len(manifest),'authored_pixels':len(payload),'changed_cells':sum(e['changed_pixels']>0 for e in manifest)}))

if __name__ == '__main__': main()
