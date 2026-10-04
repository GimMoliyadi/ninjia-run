# -*- coding: utf-8 -*-
"""
精灵图去出血重排脚本
- 读取 public/ninja-sprites.png（6列x3行，每格128x128）
- 逐帧检测真实内容边界（alpha>5 的像素）
- 把每帧内容平移到新格子的固定锚点：水平保留相对格心的偏移，垂直底边留 2px 透明边距
- 输出 public/ninja-sprites-padded.png（6列x3行，每格132x132），并打印新的 FRAMES 坐标
原理：只要角色像素不触碰 128px 格线，浏览器平滑采样就不会采到相邻行的像素（消除"头上顶脚"）。
"""
from PIL import Image

SRC = 'C:/Users/admin/ninjia-run/public/ninja-sprites.png'
DST = 'C:/Users/admin/ninjia-run/public/ninja-sprites-padded.png'

PAD = 2          # 四周透明边距 px
CELL = 128       # 原格子边长
NEW = CELL + PAD * 2   # 新格子边长 = 132
COLS, ROWS = 6, 3

img = Image.open(SRC).convert('RGBA')
out = Image.new('RGBA', (COLS * NEW, ROWS * NEW), (0, 0, 0, 0))

def content_bbox(cx, cy):
    """返回某格子里非透明像素的 (min_x, min_y, max_x, max_y)，全空则 None"""
    crop = img.crop((cx * CELL, cy * CELL, (cx + 1) * CELL, (cy + 1) * CELL))
    px = crop.load()
    min_x = min_y = CELL
    max_x = max_y = -1
    for y in range(CELL):
        for x in range(CELL):
            if px[x, y][3] > 5:
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    return None if max_x < 0 else (min_x, min_y, max_x, max_y)

frames = {}
for r in range(ROWS):
    for c in range(COLS):
        box = content_bbox(c, r)
        if box is None:
            frames[(r, c)] = None
            continue
        min_x, min_y, max_x, max_y = box
        w = max_x - min_x + 1
        h = max_y - min_y + 1
        # 取原格内容
        tile = img.crop((c * CELL + min_x, r * CELL + min_y, c * CELL + min_x + w, r * CELL + min_y + h))
        # 新格内坐标：水平保留相对格心的偏移（nx = min_x + PAD），垂直底边留 PAD 边距（ny = NEW - PAD - h）
        nx = min_x + PAD
        ny = NEW - PAD - h
        out.paste(tile, (c * NEW + nx, r * NEW + ny), tile)
        frames[(r, c)] = (min_x, min_y, w, h, nx, ny)

out.save(DST)
print(f'已生成: {DST} 尺寸={out.size[0]}x{out.size[1]}')

# 校验：新图上每帧内容四周是否都有 >= PAD 透明边距
print('\n=== 边距校验 ===')
ok = True
for r in range(ROWS):
    for c in range(COLS):
        if frames[(r, c)] is None:
            print(f'  行{r} 列{c}: 空白（跳过）')
            continue
        min_x, min_y, w, h, nx, ny = frames[(r, c)]
        left = nx; right = NEW - (nx + w)
        top = ny; bottom = NEW - (ny + h)
        status = 'OK' if (left >= PAD and right >= PAD and top >= PAD and bottom >= PAD) else 'FAIL'
        if status == 'FAIL': ok = False
        print(f'  行{r} 列{c}: 内容 {w}x{h} 边距 左{left} 右{right} 上{top} 下{bottom} -> {status}')

print('\n=== 新的 FRAMES 坐标（每格 132x132）===')
for r in range(ROWS):
    print(f'  行{r}: y={r * NEW}')
    for c in range(COLS):
        if frames[(r, c)] is None:
            print(f'    列{c}: 空白')
        else:
            print(f'    列{c}: x={c * NEW}')
print(f'\n校验{'通过' if ok else '未通过'}')
