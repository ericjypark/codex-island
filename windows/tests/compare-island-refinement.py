"""Build a local comparison of current Mac, previous Windows, and refined Windows captures."""
import base64
import io
import json
import sys
from pathlib import Path
from PIL import Image, ImageCms

root = Path(__file__).resolve().parents[1] / 'artifacts'
alignment = '--alignment' in sys.argv
views = []
names = ['cost-dollar', 'usage-numeric', 'usage-ring', 'usage-bar', 'usage-stepped', 'usage-spark',
         'cost-multi', 'cost-tokens', 'cost-spark', 'overview', 'overview-detail']
for name in names:
    item = {'name': name}
    for label, folder, prefix in [('before', 'visual-confirmed' if alignment else 'visual-before', 'win-'), ('after', 'alignment-confirmed' if alignment else 'visual-confirmed', 'win-'), ('mac', 'mac-reference', '')]:
        source = root / folder / (prefix + name + '.png')
        bitmap = Image.open(source)
        if bitmap.info.get('icc_profile'):
            bitmap = ImageCms.profileToProfile(bitmap, ImageCms.ImageCmsProfile(io.BytesIO(bitmap.info['icc_profile'])), ImageCms.createProfile('sRGB'), outputMode='RGB')
        bitmap = bitmap.convert('RGB')
        if 'size' in item:
            assert item['size'] == bitmap.size, (name, label, item['size'], bitmap.size)
        item['size'] = bitmap.size
        buffer = io.BytesIO()
        bitmap.save(buffer, format='PNG')
        item[label] = 'data:image/png;base64,' + base64.b64encode(buffer.getvalue()).decode()
    views.append(item)
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Windows island refinement</title><style>
*{box-sizing:border-box}body{margin:0;padding:32px;background:#111214;color:#eceef1;font:14px system-ui,sans-serif}main{max-width:1500px;margin:auto}h1{font-size:25px;letter-spacing:-.5px;margin:0 0 12px}p{max-width:860px;color:#a9adb5;line-height:1.6}nav,.modes{display:flex;flex-wrap:wrap;gap:6px;margin:20px 0}button{font:inherit;background:#202226;color:#c3c6cd;border:1px solid #35383e;border-radius:6px;padding:8px 12px;cursor:pointer}button[aria-pressed=true]{color:#cae4ff;border-color:#639fda;background:#1b2b3b}button:focus-visible,input:focus-visible{outline:2px solid #b0d6ff;outline-offset:3px}.labels{display:flex;justify-content:space-between;color:#bbc0c8;margin:18px 0 8px}.canvas{position:relative;background:#000;overflow:hidden}.canvas img{display:block;width:100%;height:auto}.overlay{position:absolute;inset:0;clip-path:inset(0 50% 0 0)}.divider{position:absolute;top:0;bottom:0;left:50%;width:1px;background:#fff}.slider{display:flex;align-items:center;gap:16px;margin:18px 0}input{flex:1;accent-color:#5aa8f0}.note{font-size:12px;color:#8f959e}a{color:#9bcbff}h2{font-size:16px;margin-top:32px}table{border-collapse:collapse;width:100%;max-width:760px;font-variant-numeric:tabular-nums}th,td{text-align:left;padding:10px;border-bottom:1px solid #30333a}th{color:#aeb4bd;font-weight:500}@media(max-width:700px){body{padding:16px}button{padding:7px 9px}.labels{font-size:12px}}
</style><main><h1>Windows island refinement</h1>
<p>Updated typography, chart glows, and transition behavior. These are actual Mac and Windows renders using the same demo fixture. Use the divider to compare alignment, or switch to the previous Windows version.</p>
<nav id="views" aria-label="Island view"></nav><div class="modes" id="modes" aria-label="Comparison"><button data-mode="mac" aria-pressed="true">Refined Windows / Mac</button><button data-mode="before" aria-pressed="false">Refined Windows / Previous Windows</button></div>
<div class="labels"><span>Refined Windows</span><span id="rightLabel">Mac reference</span></div><div class="canvas"><img id="reference" alt="Mac reference"><div class="overlay" id="overlay"><img id="updated" alt="Refined Windows"></div><div class="divider" id="divider"></div></div>
<div class="slider"><label for="position">Divider</label><input type="range" id="position" min="0" max="100" value="50"></div>
<p class="note">Source renders are at 2x scale. The interface scales them to fit this window. Image color profiles are converted to sRGB for comparison. Different footer status text comes from the reference harness.</p>
<h2>Measured digit widths</h2><table><thead><tr><th>Cost value</th><th>Previous</th><th>Refined</th><th>Mac</th></tr></thead><tbody><tr><td>136</td><td>124 px</td><td>130 px</td><td>130 px</td></tr><tr><td>1,343</td><td>211 px</td><td>223 px</td><td>224 px</td></tr><tr><td>32.8</td><td>170 px</td><td>179 px</td><td>180 px</td></tr><tr><td>322</td><td>125 px</td><td>132 px</td><td>131 px</td></tr></tbody></table>
<p>Typography retains the Mac scale with portable Inter text faces and calibrated monospaced numbers. Numeric meters and Cost bars have their source glows. Detail reversal preserves its displayed position, and Reduce Motion settles transitions already running.</p>
<p class="note">This is not an identical-rendering claim. Glyph shapes, some cap heights, native backdrop material, blur kernels, and intermediate frames still differ. The Windows captures come from Parallels; they do not establish physical display frame pacing.</p></main><script>
const views=DATA;let active=0,mode='mac';const nav=document.getElementById('views');function show(){const view=views[active];document.getElementById('updated').src=view.after;const reference=document.getElementById('reference');reference.src=view[mode];reference.alt=mode==='mac'?'Mac reference':'Previous Windows';document.getElementById('rightLabel').textContent=reference.alt;[...nav.children].forEach((b,i)=>b.setAttribute('aria-pressed',i===active));document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===mode));}views.forEach((view,i)=>{const b=document.createElement('button');b.textContent=view.name.replaceAll('-',' ');b.onclick=()=>{active=i;show()};nav.appendChild(b)});document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;show()});document.getElementById('position').oninput=e=>{document.getElementById('overlay').style.clipPath=`inset(0 ${100-e.target.value}% 0 0)`;document.getElementById('divider').style.left=e.target.value+'%'};show();
</script></html>'''.replace('DATA', json.dumps(views))
if alignment:
    page = page.replace('Windows island refinement', 'Windows vertical alignment')
    page = page.replace('Updated typography, chart glows, and transition behavior.', 'Corrected text baselines, mixed-size numbers and units, chip centering, footer controls, and detail rows.')
    start = page.index('<h2>Measured digit widths</h2>')
    end = page.index('<p class="note">This is not an identical-rendering claim.', start)
    page = page[:start] + '''<h2>What changed</h2><p>Chart values, labels, and percent signs now use a shared baseline measured from the Mac layout. Header chips and reset counts use their row center. Cost units, overview totals, detail labels, and footer text use explicit alignment anchors. The reset popover also follows the Mac row height and spacing.</p>
<p class="note">The previous Windows version is the typography and motion refinement installed before this alignment pass. Compare all 11 panels. Different letterforms and antialiasing can still produce small differences at glyph edges even when baselines match.</p>''' + page[end:]
    page = page.replace("let active=0,mode='mac'", "let active=3,mode='before'")
name = 'vertical-alignment.html' if alignment else 'visual-refinement.html'
(root / name).write_text(page)
print(f'Built {name} with 11 verified before/after/Mac capture sizes.')
