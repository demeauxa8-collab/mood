"""Mood app icon: the two interlocked "o" of the wordmark (an infinity), big enough to read in the Dock.

Purple passes over at the top crossing, blue over at the bottom one (same weave as MoodInfinitySymbol),
with a thin dark gap where a ring passes over. Writes the iOS full-bleed icon and the macOS plate set.
"""
import json, pathlib, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 2048
OUT = pathlib.Path(sys.argv[1])
PURPLE_TOP, PURPLE_BOTTOM = (0x86, 0x6e, 0xe6), (0x5a, 0x43, 0xb8)
BLUE_TOP, BLUE_BOTTOM = (0x4d, 0xb0, 0xff), (0x1e, 0x83, 0xec)
BG_TOP, BG_BOTTOM = (0x2b, 0x2c, 0x33), (0x13, 0x14, 0x17)


def vgradient(size, top, bottom):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        col.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return col.resize((w, h))


def ring_mask(cx, cy, r, t):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    d.ellipse((cx - r + t, cy - r + t, cx + r - t, cy + r - t), fill=0)
    return m


def dilate(mask, radius):
    """Fast dilation: blur then threshold (MaxFilter with a large kernel is far too slow)."""
    return mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: 255 if v > 8 else 0)


def half_mask(top):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rectangle((0, 0, S, S // 2) if top else (0, S // 2, S, S), fill=255)
    return m


def artwork(scale=1.0):
    """The glyph on its background, full bleed, at S x S."""
    bg = vgradient((S, S), BG_TOP, BG_BOTTOM)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((S * 0.12, -S * 0.55, S * 0.88, S * 0.42), fill=58)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.09))
    bg = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), bg, glow)

    # d < inner radius: the rings cross at two separate points (top, bottom) like chain links.
    r, t, d = S * 0.21 * scale, S * 0.088 * scale, S * 0.106 * scale
    cy = S * 0.5
    purple_m = ring_mask(S * 0.5 - d, cy, r, t)
    blue_m = ring_mask(S * 0.5 + d, cy, r, t)

    shadow = ImageChops.lighter(purple_m, blue_m).filter(ImageFilter.GaussianBlur(S * 0.022))
    shadow = ImageChops.offset(shadow, 0, int(S * 0.018)).point(lambda v: int(v * 0.45))
    img = Image.composite(Image.new("RGB", (S, S), (0, 0, 0)), bg, shadow)

    purple = vgradient((S, S), PURPLE_TOP, PURPLE_BOTTOM)
    blue = vgradient((S, S), BLUE_TOP, BLUE_BOTTOM)
    both = ImageChops.multiply(purple_m, blue_m)
    gap_w = max(3, int(S * 0.014))

    def over(img, top_ring, top_mask, under_mask, region):
        # Dark gap around the ring that passes over, inside the crossing only, then the ring itself.
        grown = dilate(top_mask, gap_w)
        gap = ImageChops.multiply(ImageChops.multiply(ImageChops.subtract(grown, top_mask), region), under_mask)
        img = Image.composite(Image.new("RGB", (S, S), (0x15, 0x16, 0x19)), img, gap)
        return Image.composite(top_ring, img, ImageChops.multiply(top_mask, region))

    img = Image.composite(blue, img, blue_m)
    img = Image.composite(purple, img, purple_m)
    crossing = dilate(both, gap_w * 2)
    img = over(img, purple, purple_m, blue_m, ImageChops.multiply(crossing, half_mask(True)))
    img = over(img, blue, blue_m, purple_m, ImageChops.multiply(crossing, half_mask(False)))
    return img


def ios_icon():
    return artwork().resize((1024, 1024), Image.LANCZOS)


def mac_icon():
    """macOS grid: 824 pt plate centered on 1024, continuous-looking corners, soft drop shadow."""
    plate = int(S * 824 / 1024)
    inset = (S - plate) // 2
    radius = int(plate * 0.2237)
    art = artwork(scale=1.0).resize((plate, plate), Image.LANCZOS)
    mask = Image.new("L", (plate, plate), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, plate - 1, plate - 1), radius=radius, fill=255)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((inset, inset + int(S * 0.012), inset + plate, inset + plate + int(S * 0.012)),
                                             radius=radius, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.018))
    canvas.paste(Image.new("RGBA", (S, S), (0, 0, 0, 255)), (0, 0), shadow)
    canvas.paste(art.convert("RGBA"), (inset, inset), mask)
    return canvas.resize((1024, 1024), Image.LANCZOS)


OUT.mkdir(parents=True, exist_ok=True)
ios_icon().save(OUT / "icon_1024.png")
mac = mac_icon()
images = [{"filename": "icon_1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"mac_{pt}x{pt}@{scale}x.png"
        mac.resize((px, px), Image.LANCZOS).save(OUT / name)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
(OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print("icons written:", len(images))
