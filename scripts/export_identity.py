"""Export the editable logo geometry to SVG and supersampled PNG using Pillow.
Run with Python + Pillow. No source concept bitmap is cropped or embedded.
"""
from pathlib import Path
import json, re
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PULSE = 'M 306 760 L 306 286 C 306 266 320 252 340 252 L 508 252 C 640 252 704 310 704 410 C 704 492 660 545 580 561 L 756 704 C 766 714 762 726 747 728 L 677 733 L 645 794 C 638 807 625 806 618 793 L 475 574 L 438 574 L 438 760 C 438 785 423 798 399 798 L 346 798 C 320 798 306 785 306 760 Z'

def polygon(path):
    tokens = re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', path)
    i, points, current = 0, [], (0, 0)
    while i < len(tokens):
        op = tokens[i]; i += 1
        if op in ('M', 'L'):
            current = tuple(map(float, tokens[i:i+2])); i += 2; points.append(current)
        elif op == 'C':
            values = list(map(float, tokens[i:i+6])); i += 6
            p0, p1, p2, p3 = current, values[:2], values[2:4], values[4:]
            for step in range(1, 65):
                t = step / 64; u = 1-t
                points.append(tuple(u**3*p0[j]+3*u*u*t*p1[j]+3*u*t*t*p2[j]+t**3*p3[j] for j in (0,1)))
            current = p3
    return points

def export(name, background, foreground):
    folder = ROOT / 'design/identity' / name
    folder.mkdir(parents=True, exist_ok=True)
    if name == 'pulse':
        mask_svg = f'<path d="{PULSE}" fill="white"/><circle cx="500" cy="410" r="70" fill="black"/>'
    else:
        mask_svg = '<rect x="326" y="154" width="372" height="716" rx="130" fill="none" stroke="white" stroke-width="28"/><circle cx="512" cy="354" r="77" fill="none" stroke="white" stroke-width="26"/><path d="M 438 481 Q 512 548 586 481" fill="none" stroke="white" stroke-width="27" stroke-linecap="round"/><circle cx="512" cy="686" r="27" fill="white"/>'
    header = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
    mark = f'<defs><mask id="mark">{mask_svg}</mask></defs><rect width="1024" height="1024" fill="{foreground}" mask="url(#mark)"/>'
    (folder / 'logo.svg').write_text(header + mark + '</svg>')
    (folder / 'app-icon.svg').write_text(header + f'<rect width="1024" height="1024" fill="{background}"/>' + mark + '</svg>')
    scale = 3
    mask = Image.new('L', (1024*scale, 1024*scale)); d = ImageDraw.Draw(mask)
    def box(values): return tuple(int(v*scale) for v in values)
    if name == 'pulse':
        d.polygon([(int(x*scale),int(y*scale)) for x,y in polygon(PULSE)], fill=255)
        d.ellipse(box((430,340,570,480)), fill=0)
    else:
        d.rounded_rectangle(box((312,140,712,884)), radius=144*scale, outline=255, width=28*scale)
        d.ellipse(box((422,264,602,444)), outline=255, width=26*scale)
        pts = []
        for n in range(65):
            t=n/64; u=1-t
            pts.append((int((u*u*438+2*u*t*512+t*t*586)*scale),int((u*u*481+2*u*t*548+t*t*481)*scale)))
        # Round overlapping discs avoid seams at the individual curve segments.
        for x,y in pts: d.ellipse((x-13.5*scale,y-13.5*scale,x+13.5*scale,y+13.5*scale),fill=255)
        d.ellipse(box((485,659,539,713)),fill=255)
    mask = mask.resize((1024,1024),Image.Resampling.LANCZOS)
    logo = Image.new('RGBA',(1024,1024),foreground); logo.putalpha(mask); logo.save(folder/'logo.png')
    icon = Image.new('RGB',(1024,1024),background); icon.paste(logo,(0,0),logo); icon.save(folder/'app-icon.png')
    assets = ROOT/'ios/Remio/Resources/Assets.xcassets'
    iconset = assets / ('AppIcon.appiconset' if name=='pulse' else 'AppIconSignal.appiconset')
    iconset.mkdir(parents=True,exist_ok=True); icon.save(iconset/'icon.png')
    (iconset/'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
    imageset=assets/f'{name.title()}Preview.imageset'; imageset.mkdir(exist_ok=True)
    icon.resize((180,180),Image.Resampling.LANCZOS).save(imageset/'preview.png')
    (imageset/'Contents.json').write_text(json.dumps({'images':[{'filename':'preview.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2))

export('pulse','#121212','#D4D4D4')
export('signal','#101114','#FFFFFF')
