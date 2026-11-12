"""Render the small three-face tray mark; no black silhouette or external assets."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
scale = 8
image = Image.new('RGBA', (32 * scale, 32 * scale))
draw = ImageDraw.Draw(image)
def points(values): return [(round(x * scale), round(y * scale)) for x, y in values]
outline = [(16, 2), (29, 9.5), (29, 22.5), (16, 30), (3, 22.5), (3, 9.5), (16, 2)]
draw.line(points(outline), fill='#F4FCFF', width=4 * scale, joint='curve')
faces = [([(16, 2), (29, 9.5), (16, 17), (3, 9.5)], '#A7EDFF'),
         ([(3, 9.5), (16, 17), (16, 30), (3, 22.5)], '#448CF4'),
         ([(16, 17), (29, 9.5), (29, 22.5), (16, 30)], '#52CBDC')]
for polygon, color in faces: draw.polygon(points(polygon), fill=color)
for line in [outline, [(3, 9.5), (16, 17), (29, 9.5)], [(16, 17), (16, 30)]]:
    draw.line(points(line), fill='#285D8D', width=scale, joint='curve')
image.resize((128, 128), Image.Resampling.LANCZOS).save(root / 'assets/tray.png')
image.save(root / 'assets/tray.ico', sizes=[(16,16),(20,20),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
