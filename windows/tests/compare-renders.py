from pathlib import Path
from PIL import Image, ImageCms
import io
import base64
import json

root = Path(__file__).resolve().parents[1] / 'artifacts'
names = ['usage-spark', 'usage-ring', 'usage-bar', 'usage-stepped', 'usage-numeric', 'cost-dollar', 'cost-multi', 'cost-tokens', 'cost-spark', 'overview', 'overview-detail']
names += [f'card-{form}-{metric}' for form in ('feed','square','story') for metric in ('apiValue','tokens')]
names += ['card-studio','settings-general','settings-providers','settings-display']
rows = []
for name in names:
    fixed_card = name.startswith('card-') and name != 'card-studio'
    actual_path = root / 'card-after' / f'win-{name}.png' if fixed_card and (root / 'card-after' / f'win-{name}.png').exists() else root / f'win-{name}.png'
    expected_path = root / 'mac-reference' / f'{name}.png'
    def pixels(path):
        bitmap = Image.open(path)
        if bitmap.info.get('icc_profile'):
            bitmap = ImageCms.profileToProfile(bitmap, ImageCms.ImageCmsProfile(io.BytesIO(bitmap.info['icc_profile'])), ImageCms.createProfile('sRGB'), outputMode='RGB')
        return bitmap.convert('RGB')
    actual, expected = pixels(actual_path), pixels(expected_path)
    assert actual.size == expected.size, (name, actual.size, expected.size)
    # Protect against the offscreen-glow regression that blanked unrelated text.
    visible = None
    panel = not name.startswith(('card-', 'settings-'))
    if panel:
        header = actual.crop((100, 15, 200, 60))
        visible = sum(max(pixel) > 100 for pixel in header.get_flattened_data())
        assert visible > 400, f'{name}: missing provider title'
    bounds = (24, 76, 1576, actual.height - 88) if panel else (0,0,actual.width,actual.height)
    samples = zip(actual.crop(bounds).get_flattened_data(), expected.crop(bounds).get_flattened_data())
    if fixed_card:
        background_actual, background_expected = actual.getpixel((0, 0)), expected.getpixel((0, 0))
        active = [(a, b) for a, b in samples if max(*(abs(x-y) for x,y in zip(a,background_actual)), *(abs(x-y) for x,y in zip(b,background_expected))) > 8]
    else:
        active = [(a, b) for a, b in samples if max(*a, *b) > 24]
    mismatch = sum(max(abs(x-y) for x,y in zip(a,b)) > 24 for a,b in active)
    def uri(path): return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()
    rows.append(dict(name=name, actual=uri(actual_path), expected=uri(expected_path), width=actual.width, height=actual.height,
                     visibleHeaderPixels=visible, changedActiveBodyPixels=mismatch, activeBodyPixels=len(active)))
metrics = [{k:v for k,v in row.items() if k not in ('actual','expected')} for row in rows]
(root / 'render-comparison.json').write_text(json.dumps(metrics, indent=2))
html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CodexIsland visual comparison</title><style>
*{box-sizing:border-box}body{margin:0;background:#101113;color:#ededee;font:14px system-ui,sans-serif;padding:32px}main{max-width:1600px;margin:auto}h1{font-size:25px;letter-spacing:-.6px;margin:0 0 12px}p{color:#a7aaaf;line-height:1.6;max-width:850px}nav{display:flex;gap:6px;flex-wrap:wrap;margin:24px 0}button{font:inherit;background:#202226;color:#ccc;border:1px solid #35383f;border-radius:6px;padding:8px 12px;cursor:pointer}button[aria-pressed=true]{border-color:#5aa8f0;color:#b7d9ff;background:#17212c}.canvas{position:relative;background:#30343b;width:100%;overflow:hidden}img{display:block;width:100%;height:auto}.over{position:absolute;inset:0;clip-path:inset(0 50% 0 0)}.line{position:absolute;left:50%;top:0;bottom:0;background:#f3f3f3;width:1px}.labels{display:flex;justify-content:space-between;font-size:12px;color:#b3b7bf;margin:14px 0 8px}.controls{display:flex;gap:12px;align-items:center;margin-top:18px}input{width:100%;accent-color:#5aa8f0}.note{font-size:12px}h2{font-size:15px;margin-top:28px}.status{color:#efb26f}kbd{background:#25282e;padding:2px 6px;border-radius:3px}</style><main>
<h1>Mac source ↔ Windows preview</h1><p>Actual captures at 2× scale, using the same demo data. Move the divider to compare. The Windows port has not passed the 100% visual-parity requirement.</p><p class="note">Mac: settled SwiftUI views rendered from this repository. Windows: ARM64 WPF renders and app captures in Parallels. Cards use the fixed demo fixture so dates remain comparable. Font rendering, icons, effects and some spacing still differ. This is a comparison tool, not a similarity score.</p><nav id="tabs" aria-label="View"></nav><div class="labels"><span>Windows</span><span id="size"></span><span>Mac</span></div><div class="canvas"><img id="mac" alt="Mac reference"><div class="over" id="over"><img id="win" alt="Windows capture"></div><div class="line" id="line"></div></div><div class="controls"><label for="slider">Divider</label><input id="slider" type="range" min="0" max="100" value="50" aria-label="Comparison divider"></div><p class="note" id="metric"></p><h2>Known gaps</h2><p>The main Windows interface uses Segoe UI and Cascadia Mono. Share cards use embedded Inter faces with rounded numeric outlines and measured Mac layout. The Mac uses SF Pro and SF Mono, so glyph identity still differs. Settings and the card studio are implemented, with some layout and symbol differences still visible. Alert decisions, pulse ownership, and ordinary borderless full-screen behavior pass fixture tests. Exact alert pixels and intermediate frames, real system power transitions, localization, and live provider services remain incomplete. VM screenshots do not establish frame pacing on a physical PC.</p><p class="note status">Interaction checks and rendering checks are tracked separately from visual approval.</p></main><script>
const views=DATA;const tabs=document.querySelector('#tabs');const slider=document.querySelector('#slider');let active=0;
function select(i){active=i;let v=views[i];document.querySelector('#mac').src=v.expected;document.querySelector('#win').src=v.actual;document.querySelector('#size').textContent=`${v.width} × ${v.height} pixels`;document.querySelector('#metric').textContent=`${v.changedActiveBodyPixels.toLocaleString()} of ${v.activeBodyPixels.toLocaleString()} active body pixels differ by more than 24/255 in at least one color channel. Blank background is excluded; this count is not a quality percentage.`;[...tabs.children].forEach((b,j)=>b.setAttribute('aria-pressed',j===i));}
views.forEach((v,i)=>{let b=document.createElement('button');b.textContent=v.name.replaceAll('-',' ');b.onclick=()=>select(i);tabs.appendChild(b)});slider.oninput=()=>{document.querySelector('#over').style.clipPath=`inset(0 ${100-slider.value}% 0 0)`;document.querySelector('#line').style.left=slider.value+'%'};select(0);
</script></html>'''.replace('DATA', json.dumps(rows))
(root / 'comparison.html').write_text(html)
print(f'Validated {len(rows)} capture sizes, with provider-header visibility guards on panels. Wrote comparison.html.')
