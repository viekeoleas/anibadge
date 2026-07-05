# SVG/параметрика -> полигоны для векторного движка знака (VS_POLY).
# Использование: правишь JOBS внизу -> python svg_to_vlogo.py ->
#   превью PNG (проверить глазами) + C-код контуров на stdout.
import math
import re
import sys
from xml.dom import minidom

from PIL import Image
from svg.path import parse_path

S = 480


def svg_contours(svg_file, samples_per_seg=14):
    """Все subpath'ы всех <path> как списки точек (в координатах SVG)."""
    doc = minidom.parse(svg_file)
    contours = []
    for p in doc.getElementsByTagName('path'):
        d = p.getAttribute('d')
        if not d:
            continue
        path = parse_path(d)
        cur = []
        for seg in path:
            name = type(seg).__name__
            if name == 'Move':
                if len(cur) >= 3:
                    contours.append(cur)
                cur = []
                continue
            n = 2 if name == 'Line' else samples_per_seg
            for i in range(n):
                z = seg.point((i + 1) / n)
                cur.append((z.real, z.imag))
        if len(cur) >= 3:
            contours.append(cur)
    doc.unlink()
    return contours


def normalize(contours, size=S, pad=0.78):
    xs = [x for c in contours for x, y in c]
    ys = [y for c in contours for x, y in c]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    k = min(size * pad / (x1 - x0), size * pad / (y1 - y0))
    ox, oy = (x0 + x1) / 2, (y0 + y1) / 2
    out = []
    for c in contours:
        out.append([((x - ox) * k + size / 2, (y - oy) * k + size / 2) for x, y in c])
    return out


def decimate(contours, tol=1.2):
    """Убрать почти-коллинеарные точки (меньше данных во флеш)."""
    out = []
    for c in contours:
        keep = [c[0]]
        for p in c[1:]:
            if math.dist(keep[-1], p) >= tol:
                keep.append(p)
        out.append(keep)
    return out


def mercedes_star(cx=240, cy=240, R=186, valley=48):
    """Трёхлучевая звезда MB: 3 острых луча = 6 вершин, прямые рёбра."""
    pts = []
    for k in range(3):
        tip = math.radians(-90 + k * 120)
        vall = tip + math.radians(60)
        pts.append((cx + math.cos(tip) * R, cy + math.sin(tip) * R))
        pts.append((cx + math.cos(vall) * valley, cy + math.sin(vall) * valley))
    return [pts]


def render_preview(contour_sets, path):
    """Скан-заливка even-odd — та же математика, что в прошивке."""
    img = Image.new('RGB', (S, S), (0, 0, 0))
    px = img.load()
    for contours, color in contour_sets:
        for y in range(S):
            fy = y + 0.5
            xs = []
            for c in contours:
                n = len(c)
                for i in range(n):
                    x1, y1 = c[i]
                    x2, y2 = c[(i + 1) % n]
                    if (y1 <= fy) == (y2 <= fy):
                        continue
                    t = (fy - y1) / (y2 - y1)
                    xs.append(x1 + (x2 - x1) * t)
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(max(0, int(xs[i])), min(S, int(xs[i + 1]) + 1)):
                    if (x - 240) ** 2 + (y - 240) ** 2 <= 239 ** 2:
                        px[x, y] = color
    img.save(path)


def emit_c(name, contours):
    pts, ends = [], []
    for c in contours:
        pts.extend(c)
        ends.append(len(pts))
    lines = [f'static const int16_t {name}_pts[] = {{']
    for i in range(0, len(pts), 8):
        chunk = ', '.join(f'{int(round(x))},{int(round(y))}' for x, y in pts[i:i + 8])
        lines.append('  ' + chunk + ',')
    lines.append('};')
    lines.append(f'static const uint16_t {name}_ends[] = {{ ' +
                 ', '.join(str(e) for e in ends) + ' };')
    lines.append(f'// VPoly: {{ {name}_pts, {name}_ends, {len(ends)}, {len(pts)} }}')
    return '\n'.join(lines)


def path_contours_of(el, samples_per_seg=14):
    path = parse_path(el.getAttribute('d'))
    contours, cur = [], []
    for seg in path:
        n = type(seg).__name__
        if n == 'Move':
            if len(cur) >= 3:
                contours.append(cur)
            cur = []
            continue
        k = 2 if n == 'Line' else samples_per_seg
        for i in range(k):
            z = seg.point((i + 1) / k)
            cur.append((z.real, z.imag))
    if len(cur) >= 3:
        contours.append(cur)
    return contours


def svg_per_path(svg_file):
    doc = minidom.parse(svg_file)
    out = [path_contours_of(p) for p in doc.getElementsByTagName('path')
           if p.getAttribute('d')]
    doc.unlink()
    return out


def normalize_grouped(per_path, size=S, pad=0.94):
    flat = [c for cs in per_path for c in cs]
    flat_n = normalize(flat, size, pad)
    out, k = [], 0
    for cs in per_path:
        out.append(flat_n[k:k + len(cs)])
        k += len(cs)
    return out


def bbox(c):
    xs = [x for x, y in c]
    ys = [y for x, y in c]
    return max(xs) - min(xs), max(ys) - min(ys)


if __name__ == '__main__':
    scratch = r'C:\Users\maybe\AppData\Local\Temp\claude\d--znachok-dima-bmw\a7d62528-64e2-460d-9939-cc9bfb3064ee\scratchpad'

    # Tesla: из настоящего SVG
    tesla = decimate(normalize(svg_contours(scratch + r'\src_teslasvg.svg')), tol=2.0)
    print(f'tesla: {len(tesla)} contour(s), {sum(len(c) for c in tesla)} pts')

    # Mercedes: параметрическая звезда (кольцо добавляется VS_RING в прошивке)
    star = mercedes_star()

    badges = r'C:\Users\maybe\Downloads\Нова папка (4)\значки для клода'

    # BMW из пользовательского SVG: 7 путей -> 7 элементов с even-odd парами
    per = [ [decimate([c], tol=1.4)[0] for c in cs]
            for cs in normalize_grouped(svg_per_path(badges + r'\bmw-logo-logo-svgrepo-com (1).svg'), pad=0.94) ]
    bmw_groups = [
        ('VP_BMW_RIMOUT', per[0] + per[1], (206, 210, 218)),   # внешний серебр. обод
        ('VP_BMW_BODY',   per[1] + per[2], (30, 33, 39)),      # тёмное тело
        ('VP_BMW_RIMIN',  per[2] + per[3], (30, 33, 39)),      # тёмная полоса с буквами
        ('VP_BMW_DISC',   list(per[3]),    (60, 140, 210)),    # диск = синяя основа
        ('VP_BMW_QUADS',  list(per[4]),    (245, 247, 250)),   # белые сектора
        ('VP_BMW_TEXT',   list(per[5]),    (222, 226, 233)),   # буквы BMW
        ('VP_BMW_HOLES',  list(per[6]),    (30, 33, 39)),      # дырки буквы B
    ]

    # Toyota из пользовательского SVG: 6 контуров -> 3 овала (пары по форме bbox)
    # Toyota_EU.svg — единый even-odd силуэт (контуры = внешний край + дырки),
    # на овалы не делится -> один цельный элемент
    tcs = decimate(normalize(svg_contours(badges + r'\Toyota_EU.svg'), pad=0.8), tol=1.4)
    TRED = (214, 30, 40)
    toyota_groups = [('VP_TOYOTA', tcs, TRED)]

    blocks = [
        '// АВТОГЕНЕРАЦИЯ: tools/svg_to_vlogo.py — руками не править.',
        '// Полигоны векторных логотипов (контуры, even-odd заливка).',
        '#pragma once',
        '#include <stdint.h>',
        '',
        emit_c('VP_TESLA', tesla),
        emit_c('VP_MB_STAR', star),
    ]
    for name, cs, _ in bmw_groups + toyota_groups:
        blocks.append(emit_c(name, cs))
    with open(r'd:\znachok_dima_bmw\src\vlogo_data.h', 'w', encoding='utf-8') as f:
        f.write('\n'.join(blocks) + '\n')
    print('written src/vlogo_data.h')
    for name, cs, _ in bmw_groups + toyota_groups:
        print(f'  {name}: {len(cs)} contours, {sum(len(c) for c in cs)} pts')

    render_preview([(tesla, (226, 26, 44))], scratch + r'\poly_tesla.png')
    render_preview([(star, (220, 224, 230))], scratch + r'\poly_mb.png')
    render_preview([(cs, col) for _, cs, col in bmw_groups], scratch + r'\poly_bmw.png')
    render_preview([(cs, col) for _, cs, col in toyota_groups], scratch + r'\poly_toyota.png')
    print('previews saved')
