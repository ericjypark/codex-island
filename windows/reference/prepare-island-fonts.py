"""Build the island's portable text faces from the same pinned Inter source as cards."""
from hashlib import sha256
from pathlib import Path
from io import BytesIO
from urllib.request import urlopen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
cached = root / 'artifacts/card-font-sources/Inter.ttf'
source = cached.read_bytes() if cached.exists() else urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf').read()
if sha256(source).hexdigest() != '29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031':
    raise SystemExit('The source changed. Review it before changing the pinned hash.')
for weight, style in [(500, 'Medium'), (600, 'SemiBold'), (650, 'Status')]:
    font = instantiateVariableFont(TTFont(BytesIO(source)), {'opsz': 14, 'wght': weight}, inplace=True)
    names = {1: 'Island Text ' + style, 2: 'Regular', 3: 'CodexIsland-IslandText-' + style,
             4: 'Island Text ' + style, 6: 'IslandText-' + style, 16: 'Island Text', 17: style}
    if style == 'Status':
        names.update({1: 'Island Status', 4: 'Island Status', 16: 'Island Status', 17: 'Regular'})
    for name_id, value in names.items():
        font['name'].setName(value, name_id, 3, 1, 0x409)
        font['name'].setName(value, name_id, 1, 0, 0)
    font.save(root / ('IslandPrototype/Assets/Fonts/IslandText-' + style + '.ttf'))
print('Prepared three static island text faces; original OFL metadata is retained.')
