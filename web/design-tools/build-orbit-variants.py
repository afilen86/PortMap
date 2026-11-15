"""Three Orbit studies, sharing the original design lab's imagery and behavior.

python3 web/design-tools/build-orbit-variants.py
The original three concepts are preserved. No source images are modified.
"""
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('mockup_library', HERE / 'build-mockups.py')
library = importlib.util.module_from_spec(spec)
spec.loader.exec_module(library)
OUT = library.ROOT / 'web/public/mockups/orbit/index.html'

# Three different silhouettes: a wide elliptical orbit, generous photo tiles,
# and compact outer constellations around a dominant central Mac.
layouts = {
    'glacier': {
        'mac': (670, 300), 'satechi': (230, 300), 'element': (1110, 300),
        'expansion': (20, 120), 'satechiSSD': (240, 60), 'usbStorage': (460, 30),
        'hdmi': (680, 10), 'display12': (900, 30), 'displayDP': (1120, 60), 'nvme': (1340, 120),
        'ether5': (20, 330), 'lacie': (1340, 330),
        'ether25': (20, 540), 'scarlett': (240, 600), 'maestro': (460, 630),
        'speakers': (680, 650), 'z1': (900, 630), 's4': (1120, 600), 'x1': (1340, 540),
    },
    'afterhours': {
        'mac': (660, 300), 'satechi': (230, 310), 'element': (1110, 310),
        'expansion': (10, 30), 'satechiSSD': (230, 30), 'usbStorage': (450, 30),
        'hdmi': (670, 30), 'display12': (890, 30), 'displayDP': (1110, 30), 'nvme': (1330, 30),
        'ether5': (10, 320), 'lacie': (1330, 320),
        'ether25': (10, 600), 'scarlett': (230, 600), 'maestro': (450, 600),
        'speakers': (670, 600), 'z1': (890, 600), 's4': (1110, 600), 'x1': (1330, 600),
    },
    'clay': {
        'mac': (650, 280), 'satechi': (250, 310), 'element': (1110, 310),
        'expansion': (40, 140), 'satechiSSD': (250, 110), 'usbStorage': (460, 80),
        'hdmi': (700, 40), 'display12': (940, 80), 'displayDP': (1150, 110), 'nvme': (1360, 140),
        'ether5': (40, 330), 'lacie': (1360, 330),
        'ether25': (40, 520), 'scarlett': (250, 550), 'maestro': (460, 580),
        'speakers': (700, 620), 'z1': (940, 580), 's4': (1150, 550), 'x1': (1360, 520),
    },
}


def dimensions(width, height, photo):
    return dict(width=width, height=height, photo=photo)


sizes = {}
for key, peripheral, host, hub in [
    ('glacier', (180, 140, 100), (220, 180, 136), (200, 160, 112)),
    ('afterhours', (200, 180, 132), (240, 220, 166), (220, 200, 148)),
    ('clay', (160, 120, 74), (260, 220, 164), (200, 160, 108)),
]:
    sizes[key] = {node['id']: dimensions(*(host if node['id'] == 'mac' else hub if node['kind'] == 'hub' else peripheral)) for node in library.nodes}

for variant, positions in layouts.items():
    # Fail during generation if any photograph cards would overlap or leave the canvas.
    rectangles = [(id, x, y, sizes[variant][id]['width'], sizes[variant][id]['height']) for id, (x, y) in positions.items()]
    for i, (id, x, y, w, h) in enumerate(rectangles):
        assert 0 <= x and x + w <= 1560 and 0 <= y and y + h <= 820, (variant, id)
        for other, ox, oy, ow, oh in rectangles[i+1:]:
            assert x+w <= ox or ox+ow <= x or y+h <= oy or oy+oh <= y, (variant, id, other)

payload = dict(nodes=library.nodes, assets=library.assets, atlas=library.atlas, layouts=layouts, sizes=sizes,
               routes={key: library.route_edges(pos, sizes[key], height=820) for key, pos in layouts.items()})
page = (HERE / 'mockups.template.html').read_text()


def replace(old, new):
    global page
    assert page.count(old) == 1, f'Template anchor changed: {old[:100]}'
    page = page.replace(old, new)


replace('<title>Port Map — three design directions</title>', '<title>Workspace Orbit — three new iterations</title>')
replace('</style>', '\n' + (HERE / 'orbit-variants.css').read_text() + '\n</style>')
replace('/*__DATA__*/', 'const DATA = ' + json.dumps(payload, separators=(',', ':')) + ';')
replace('Design explorations', 'Workspace Orbit / colour studies')
replace('THREE DIRECTIONS / ONE SETUP', 'SAME SETUP / THREE EXPRESSIONS')
replace('01 · Connection Atlas', '01 · Glacier')
replace('02 · Signal Desk', '02 · After Hours')
replace('03 · Workspace Orbit', '03 · Clay Studio')
# Rename tab IDs and data keys; the Orbit visual structure remains shared.
for old, new in [('atlas', 'glacier'), ('signal', 'afterhours'), ('orbit', 'clay')]:
    page = page.replace(f'id="tab-{old}"', f'id="tab-{new}"').replace(f'data-design="{old}"', f'data-design="{new}"')
replace('aria-labelledby="tab-atlas"', 'aria-labelledby="tab-glacier"')
replace('<body data-design="glacier">', '<body data-design="orbit" data-variant="glacier">')
replace("let design='atlas',selected='scarlett',playing=true,focused=false;", "let design='glacier',selected='scarlett',playing=true,focused=false;")
# Names and descriptions also communicate the meaningful spacing/scale differences.
start = page.index('const directions=')
end = page.index('\nlet design=', start)
page = page[:start] + '''const directions={
 glacier:{kicker:'ORBIT / 01 — GLACIER',title:'A little room to think.',description:'Cool porcelain, glacial blue, and an open elliptical layout. Medium portraits give every device equal breathing room.',name:'Glacier',spacing:'Airy spacing',imagery:'Medium portraits'},
 afterhours:{kicker:'ORBIT / 02 — AFTER HOURS',title:'The studio, after dark.',description:'Deep aubergine, lilac light, and oversized device portraits. A closer, tactile orbit built around the hardware.',name:'After Hours',spacing:'Close spacing',imagery:'Large portraits'},
 clay:{kicker:'ORBIT / 03 — CLAY STUDIO',title:'Made for your corner of the world.',description:'Warm chalk, terracotta, and olive. Smaller peripherals form compact constellations around a larger, central Mac.',name:'Clay Studio',spacing:'Clustered spacing',imagery:'Small portraits · hero Mac'}
};''' + page[end:]
replace("card.style.top=`${y}px`;card.append(photo(n));", "card.style.top=`${y}px`;const metrics=DATA.sizes[design][n.id];card.style.width=`${metrics.width}px`;card.style.height=`${metrics.height}px`;card.style.setProperty('--portrait-size',`${metrics.photo}px`);card.style.setProperty('--well-size',`${metrics.height-40}px`);card.append(photo(n));")
# Per-iteration ring annotations, positioned outside every image card.
page, count = re.subn(r'function renderZones\(\).*?\nfunction select', '''function renderZones(){
 const layer=document.querySelector('#zones');layer.replaceChildren();
 const labels=design==='glacier'?[['Storage & network',240,245],['Display paths',1090,245],['Your Mac, at the centre',674,510],['Audio & performance',920,555]]:
 design==='afterhours'?[['STORAGE / INPUTS',250,245],['SCREENS / OUTPUTS',1090,245],['HOST COMPUTER',700,545],['AUDIO / CONTROL',1050,565]]:
 [['Storage & connections',230,245],['Screens & control',1120,245],['Your workspace starts here',665,525]];
 for(const [name,x,y] of labels){const label=el('div',{class:'zone-label'});label.textContent=name;label.style.left=`${x}px`;label.style.top=`${y}px`;layer.append(label);}
}
function select''', page, count=1)
assert count == 1
replace("if(!directions[value])value='atlas';design=value;document.body.dataset.design=design;", "if(!directions[value])value='glacier';design=value;document.body.dataset.design='orbit';document.body.dataset.variant=design;")
replace("document.querySelector('#map-name').textContent=info.name;", "document.querySelector('#map-name').textContent=`Workspace Orbit / ${info.name}`;document.querySelector('#spacing-badge').textContent=info.spacing;document.querySelector('#imagery-badge').textContent=info.imagery;")
replace('<span class="badge">Interactive mockup</span>', '<span class="badge" id="spacing-badge">Airy spacing</span><span class="badge" id="imagery-badge">Medium portraits</span>')
replace("activate(location.hash.slice(1)||'atlas',false)", "activate(location.hash.slice(1)||'glacier',false)")
replace('viewBox="0 0 1560 780"', 'viewBox="0 0 1560 820"')
page = page.replace('available/780', 'available/820').replace('Math.ceil(780*scale)', 'Math.ceil(820*scale)')
def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page)
    print(f'Built {OUT} ({OUT.stat().st_size:,} bytes); 3 Orbit variants, 19 persistent images each')


if __name__ == "__main__":
    main()
