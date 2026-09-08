"""Read exported art, verify MCP round-trip and assemble engine-capture reviews."""
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/characters/wayfarer'
ASSET = ROOT / 'assets/sprites/characters'

def main():
    manifest = json.loads((OUT/'atlas-manifest.json').read_text())
    im = Image.open(ASSET/'WAYFARER.png').convert('RGBA')
    assert list(im.size) == manifest['size']
    assert hashlib.sha256(im.tobytes()).hexdigest() == manifest['expected_rgba_sha256']
    assert hashlib.sha256((ASSET/'JUNOBASE.png').read_bytes()).hexdigest() == manifest['original_sha256']
    nonempty, empty = 0, []
    with (OUT/'atlas-regions.csv').open('w',newline='',encoding='utf-8') as file:
        writer = csv.writer(file)
        writer.writerow(['node','gfx','entry','facing','pitch','row','frame_keys','source_x','source_y','packed_x','packed_y','w','h','pivot_x','pivot_y','art_policy'])
        for entry in manifest['entries']:
            p,s=entry['packed'],entry['source']
            if im.crop((p['x'],p['y'],p['x']+p['w'],p['y']+p['h'])).getbbox(): nonempty+=1
            else:
                empty.append(entry['key'])
                assert all(o['node'] in ('tailEnd','headGear') for o in entry['owners'])
            for owner in entry['owners']:
                pivot = owner['billboard']
                writer.writerow([owner['node'],owner['gfx_index'],owner['entry'],owner['facing'],owner['pitch_range'],owner['row'],owner['frame_keys'],s['x'],s['y'],p['x'],p['y'],p['w'],p['h'],pivot.get('pivotX',0.5),pivot.get('pivotY',0.5),entry['art_policy']])
    report = {'size':list(im.size),'roundtrip_rgba_matches':True,'original_unchanged':True,'nonempty_cells':nonempty,'intentional_empty_cells':empty,'alpha_values':sorted(set(im.getchannel('A').get_flattened_data())),'color_count_including_transparent':len(set(im.get_flattened_data())),'png_sha256':hashlib.sha256((ASSET/'WAYFARER.png').read_bytes()).hexdigest(),'pxo_sha256':hashlib.sha256((ASSET/'WAYFARER.pxo').read_bytes()).hexdigest()}
    (OUT/'asset-qa.json').write_text(json.dumps(report,indent=2))
    im.resize((720,1420),Image.Resampling.NEAREST).save(OUT/'wayfarer-zoom.png')
    native = Image.open(OUT/'godot-native.png')
    native.resize((1280,960),Image.Resampling.NEAREST).save(OUT/'godot-preview.png')
    paths = sorted(OUT.glob('motion-*.png'))
    if len(paths) != 16: raise RuntimeError(f'Expected 16 engine captures, found {len(paths)}')
    frames = [Image.open(p).crop((0,64,640,256)).resize((1280,384),Image.Resampling.NEAREST) for p in paths]
    frames[0].save(OUT/'godot-motion.gif',save_all=True,append_images=frames[1:],duration=62,loop=0,disposal=2)
    print(json.dumps(report))

if __name__ == '__main__': main()
