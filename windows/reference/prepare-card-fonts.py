"""Rebuild the portable card fonts from the verified Inter source (fontTools required)."""
from hashlib import sha256
from pathlib import Path
from urllib.request import urlopen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from io import BytesIO

root = Path(__file__).resolve().parents[1]
destination = root / 'IslandPrototype/Assets/Fonts'
source_url = 'https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf'
source_hash = '29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031'
source = urlopen(source_url).read()
if sha256(source).hexdigest() != source_hash:
    raise SystemExit('The upstream font changed. Review it before updating the pinned source hash.')
destination.mkdir(parents=True, exist_ok=True)
for family, optical_size, weight, style in [
    ('Card Text', 14, 600, 'SemiBold'),
    ('Card Display', 32, 400, 'Regular'),
    ('Card Display', 32, 500, 'Medium'),
    ('Card Display', 32, 600, 'SemiBold'),
]:
    font = instantiateVariableFont(TTFont(BytesIO(source)), {'opsz': optical_size, 'wght': weight}, inplace=True)
    names = {
        1: family + ' ' + style, 2: 'Regular',
        3: 'CodexIsland-' + family.replace(' ', '') + '-' + style,
        4: family + ' ' + style, 6: family.replace(' ', '') + '-' + style,
        16: family, 17: style,
    }
    for name_id, value in names.items():
        font['name'].setName(value, name_id, 3, 1, 0x409)
        font['name'].setName(value, name_id, 1, 0, 0)
    font.save(destination / (family.replace(' ', '') + '-' + style + '.ttf'))
license_data = urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/inter/OFL.txt').read()
(destination / 'Inter-OFL.txt').write_bytes(license_data)
print('Prepared four static card fonts. Original copyright and OFL metadata are retained.')
