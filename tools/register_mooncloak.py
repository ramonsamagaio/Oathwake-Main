"""Append a selectable Mooncloak character; preserve every existing record."""
import copy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
path=ROOT/'data/characters.json'
text=path.read_text();before=json.loads(text)
record=copy.deepcopy(before['wayfarer_alabaster'])
record['display_name']='Mooncloak';record['rig_profile_id']='mooncloak'
if 'mooncloak_alabaster' in before:
    assert before['mooncloak_alabaster']==record
else:
    (ROOT/'docs/characters/mooncloak/characters-before.json').write_text(text)
    addition=json.dumps({'mooncloak_alabaster':record},ensure_ascii=False,indent='\t')[1:-1]
    result=text.rstrip()[:-1].rstrip()+','+addition+'\n}\n'
    expected=copy.deepcopy(before);expected['mooncloak_alabaster']=record
    assert json.loads(result)==expected
    path.write_text(result)
print('Mooncloak registered; all previous characters and stats preserved.')
