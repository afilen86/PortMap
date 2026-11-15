"""The chosen Orbit pairing: Clay Studio in light, After Hours in dark.

Keeps the three-study gallery intact and produces a standalone selected preview.
"""
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('orbit_studies', HERE / 'build-orbit-variants.py')
studies = importlib.util.module_from_spec(spec)
spec.loader.exec_module(studies)
OUT = studies.library.ROOT / 'web/public/orbit/index.html'
page = studies.page


def replace(old, new):
    global page
    assert page.count(old) == 1, f'Template anchor changed: {old[:100]}'
    page = page.replace(old, new)


# Bundle just the selected two layouts; the original three studies stay intact.
payload = dict(studies.payload)
for key in ['layouts', 'sizes', 'routes']:
    payload[key] = {name: payload[key][name] for name in ['clay', 'afterhours']}
old_data = 'const DATA = ' + json.dumps(studies.payload, separators=(',', ':')) + ';'
replace(old_data, 'const DATA = ' + json.dumps(payload, separators=(',', ':')) + ';')
replace('<title>Workspace Orbit — three new iterations</title>', '<title>Port Map — Workspace Orbit</title>')
replace('Workspace Orbit / colour studies', 'Workspace Orbit')
replace('SAME SETUP / THREE EXPRESSIONS', 'YOUR CONNECTED WORKSPACE')
page, count = re.subn(r'<div class="lab-tabs".*?</div>', '''<div class="appearance-controls" role="group" aria-label="Appearance">
<button type="button" data-appearance="light" aria-pressed="false"><span aria-hidden="true">☀</span> Light</button>
<button type="button" data-appearance="dark" aria-pressed="false"><span aria-hidden="true">☾</span> Dark</button>
<button type="button" data-appearance="system" aria-pressed="true"><span aria-hidden="true">◐</span> System</button>
</div>''', page, count=1)
assert count == 1
replace('id="design-panel" role="tabpanel" aria-labelledby="tab-glacier"', 'id="design-panel" aria-label="Workspace connection map"')
start = page.index('const directions=')
end = page.index('\nlet design=', start)
page = page[:start] + '''const directions={
 clay:{kicker:'WORKSPACE ORBIT / LIGHT',title:'Your workspace, connected.',description:'Every device in view. Follow each connection back to your Mac.',name:'Clay Studio',spacing:'Light Mode',imagery:'Clay Studio'},
 afterhours:{kicker:'WORKSPACE ORBIT / DARK',title:'Your workspace, connected.',description:'Every device in view. Follow each connection back to your Mac.',name:'After Hours',spacing:'Dark Mode',imagery:'After Hours'}
};''' + page[end:]
replace("let design='glacier',selected='scarlett',playing=true,focused=false;", "let design='clay',selected='scarlett',playing=true,focused=false;")
replace("if(!directions[value])value='glacier';", "if(!directions[value])value='clay';")
replace("document.querySelector('#design-panel').setAttribute('aria-labelledby',`tab-${design}`);", '')
replace("document.querySelector('#map-name').textContent=`Workspace Orbit / ${info.name}`;", "document.querySelector('#map-name').textContent='Workspace Orbit';")
# The selected version has appearance buttons rather than mockup-navigation tabs.
page, count = re.subn(r"document.querySelectorAll\('\[role=tab\]'\).forEach\(tab=>\{.*?\nlocate.addEventListener", 'locate.addEventListener', page, count=1)
assert count == 1
replace("window.addEventListener('hashchange',()=>activate(location.hash.slice(1),false));", '')
replace("activate(location.hash.slice(1)||'glacier',false);motionPreference();document.fonts.ready.then(fit);", '''
const systemAppearance=matchMedia('(prefers-color-scheme: dark)');
const appearanceKey='portmap-orbit-appearance';
let appearance='system';
try{const saved=localStorage.getItem(appearanceKey);if(['light','dark','system'].includes(saved))appearance=saved;}catch{}
function applyAppearance(choice,persist=false){
 appearance=choice;
 const dark=choice==='dark'||(choice==='system'&&systemAppearance.matches);
 document.body.dataset.appearance=choice;
 document.documentElement.style.colorScheme=dark?'dark':'light';
 for(const button of document.querySelectorAll('[data-appearance]')){
  if(button.tagName==='BUTTON')button.setAttribute('aria-pressed',String(button.dataset.appearance===choice));
 }
 activate(dark?'afterhours':'clay',false);
 motionPreference();
 if(persist){try{localStorage.setItem(appearanceKey,choice);}catch{}}
}
for(const button of document.querySelectorAll('.appearance-controls button'))button.addEventListener('click',()=>applyAppearance(button.dataset.appearance,true));
systemAppearance.addEventListener('change',()=>{if(appearance==='system')applyAppearance('system');});
applyAppearance(appearance);document.fonts.ready.then(fit);
''')
replace('</style>', '''
/* Chosen appearance controls, shared by the two approved themes. */
.appearance-controls{display:flex;gap:4px;padding:4px;background:var(--bg);border:1px solid var(--line);border-radius:10px}
.appearance-controls button{display:flex;align-items:center;justify-content:center;gap:6px;padding:8px 14px;border-radius:6px;font-size:12px;color:var(--muted)}
.appearance-controls button span{font-size:14px;line-height:1}
.appearance-controls button[aria-pressed=true]{background:var(--panel);color:var(--accent);box-shadow:0 1px 4px #0001;font-weight:600}
body[data-variant=afterhours] .appearance-controls{background:#1c1723;border-color:#4b3a51}
body[data-variant=afterhours] .appearance-controls button[aria-pressed=true]{background:#51364a;color:#f2c4d2}
@media(max-width:760px){.appearance-controls{flex:1;justify-content:center}.appearance-controls button{padding:8px 10px;font-size:11px}}
</style>''')
# Keep the correct initial document theme for clients with JavaScript disabled.
replace('<body data-design="orbit" data-variant="glacier">', '<body data-design="orbit" data-variant="clay">')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page)
print(f'Built {OUT} ({OUT.stat().st_size:,} bytes); light=Clay Studio, dark=After Hours')
