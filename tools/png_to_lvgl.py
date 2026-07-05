#!/usr/bin/env python3
# Конвертер PNG -> LVGL C-array (RGB565, LV_IMG_CF_TRUE_COLOR), 480x480 круглый.
import sys
from PIL import Image, ImageDraw, ImageChops

SRC = sys.argv[1] if len(sys.argv) > 1 else r"d:\znachok_dima_bmw\bmw logo.png"
OUT = sys.argv[2] if len(sys.argv) > 2 else r"d:\znachok_dima_bmw\src\bmw_logo.c"
NAME = "bmw_logo"
SIZE = 480

im = Image.open(SRC).convert("RGBA")

# 1) плотный кроп по содержимому (по альфе, иначе по отличию от белого)
alpha = im.getchannel("A")
bbox = alpha.getbbox() if alpha.getextrema()[0] < 255 else None
if bbox is None:
    rgb = Image.alpha_composite(Image.new("RGBA", im.size, (255, 255, 255, 255)), im).convert("RGB")
    diff = ImageChops.difference(rgb, Image.new("RGB", im.size, (255, 255, 255)))
    bbox = diff.getbbox()
im = im.crop(bbox)

# 2) в квадрат (по большей стороне), центрируем
w, h = im.size
s = max(w, h)
sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
sq.paste(im, ((s - w) // 2, (s - h) // 2))
im = sq.resize((SIZE, SIZE), Image.LANCZOS)

# 3) на чёрный фон + круглая маска (углы в чёрный)
canvas = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
canvas.paste(im, (0, 0), im)
mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).ellipse((0, 0, SIZE - 1, SIZE - 1), fill=255)
black = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
img = Image.composite(canvas, black, mask)

# 4) RGB565 little-endian (LV_COLOR_DEPTH=16, LV_COLOR_16_SWAP=0)
px = img.load()
data = bytearray()
for y in range(SIZE):
    for x in range(SIZE):
        r, g, b = px[x, y]
        v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        data += bytes((v & 0xFF, (v >> 8) & 0xFF))

# 5) C-файл LVGL
with open(OUT, "w") as f:
    f.write('#include "lvgl.h"\n\n')
    f.write(f"static const uint8_t {NAME}_map[] = {{\n")
    for i in range(0, len(data), 16):
        f.write("  " + ",".join(f"0x{b:02x}" for b in data[i:i+16]) + ",\n")
    f.write("};\n\n")
    f.write(f"const lv_img_dsc_t {NAME} = {{\n")
    f.write("  .header.cf = LV_IMG_CF_TRUE_COLOR,\n")
    f.write("  .header.always_zero = 0,\n  .header.reserved = 0,\n")
    f.write(f"  .header.w = {SIZE},\n  .header.h = {SIZE},\n")
    f.write(f"  .data_size = {SIZE*SIZE*2},\n")
    f.write(f"  .data = {NAME}_map,\n}};\n")

print(f"wrote {OUT} ({len(data)} bytes image data)")
