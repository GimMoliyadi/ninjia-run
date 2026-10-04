# -*- coding: utf-8 -*-
# 精灵条切分拼版脚本：把桌面上四张横条（跑步/一段跳/翻滚/滑铲）
# 切成单帧 → 去掉切边碎片 → 裁到内容边界 → 统一缩放 → 对齐拼成 8×4 精灵表
from PIL import Image
import os

# ---------- 路径配置 ----------
DESKTOP = 'C:/Users/admin/Desktop'                       # 桌面：原始素材条所在目录
OUT_SHEET = 'C:/Users/admin/ninjia-run/public/ninja-sprites-padded.png'   # 输出：游戏使用的精灵表
OUT_PREVIEW = 'C:/Users/admin/AppData/Local/Temp/sprite_preview/packed_preview.jpg'  # 输出：拼版预览图（白底+红线网格）
OUT_CELLS = 'C:/Users/admin/ninjia-run/public/sprite-cells'  # 输出：单帧调试图目录

# ---------- 参数配置 ----------
MARGIN = 2          # 拼版时每帧四周留 2px 透明边距，防止绘制时采样到相邻帧（出血）
TARGET_H = 66       # 跑步帧缩放目标高度：对齐游戏角色碰撞盒 STAND_H=66
SCALE_MAX = 3.2     # 放大倍数上限：源图太小就不无限放大，避免糊成一团
CUT_WINDOW = 14     # 找切分线时在名义边界左右各搜索这么多像素
COMP_KEEP = 0.15    # 连通域保留阈值：面积达到最大连通域 15% 的都保留（防误删合法墨点）

# 四张条：文件名 → (动作名, 是否脚底对齐)
# 翻滚行是团身旋转，按身体中心对齐；其余按脚底对齐
STRIPS = [
    ('跑步.png',       'run',   True),
    ('一段跳.png',     'jump',  True),
    ('二段跳.png',     'flip',  False),
    ('滑铲.png',       'slide', True),
]
FRAMES_PER_STRIP = 8   # 每张条固定切 8 帧


def load_rgba(name):
    """加载图片并确保是 RGBA 四通道格式"""
    return Image.open(os.path.join(DESKTOP, name)).convert('RGBA')


def col_density(img):
    """统计每一列的不透明像素数量，用来找切分线"""
    w, h = img.size
    px = img.load()
    return [sum(1 for y in range(h) if px[x, y][3] > 5) for x in range(w)]


def find_gaps(img):
    """找所有竖向透明分隔带（不含条图两端），返回 (起点, 终点) 列表"""
    w, h = img.size
    px = img.load()
    gaps = []
    in_gap = False
    gs = 0
    for x in range(w):
        has = any(px[x, y][3] > 5 for y in range(h))   # 这一列是否有内容
        if not has:
            if not in_gap:
                in_gap = True
                gs = x
        else:
            if in_gap:                                  # 分隔带结束
                in_gap = False
                if gs > 0:                              # 不算条图左端
                    gaps.append((gs, x - 1))
    return gaps


def split_frames(img, n):
    """把横条切成 n 帧：优先按检测到的透明分隔带下刀（绝不切到角色）；
    分隔带数量不够时，退回"名义边界附近找最薄列"的方式"""
    w, h = img.size
    gaps = find_gaps(img)
    cuts = [0]
    if len(gaps) == n - 1:
        # 恰好 n-1 条分隔带 = n 帧：每条带的中心就是最安全的下刀位置
        cuts += [(a + b) // 2 for (a, b) in gaps]
    else:
        # 分隔带不够（帧间有粘连）：在名义边界附近找内容最薄的列
        dens = col_density(img)
        step = w / n
        for i in range(1, n):
            c = int(i * step)                        # 名义边界位置
            lo, hi = max(0, c - CUT_WINDOW), min(w, c + CUT_WINDOW + 1)
            cuts.append(min(range(lo, hi), key=lambda x: dens[x]))  # 窗口内最薄列
    cuts.append(w)                                   # 最后一刀在右端
    return [img.crop((cuts[i], 0, cuts[i + 1], h)) for i in range(n)]


def remove_fragments(frame):
    """连通域清理：只保留最大的连通域，以及面积 ≥ 最大域 15% 的域（去掉切边带进的小碎片）"""
    w, h = frame.size
    px = frame.load()
    seen = [[False] * w for _ in range(h)]       # 访问标记矩阵
    comps = []                                   # 所有连通域：每个是 (面积, [(x,y)...])
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy][3] <= 5:
                continue
            stack = [(sx, sy)]                   # 泛洪填充的工作栈
            seen[sy][sx] = True
            pts = []
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for dx in (-1, 0, 1):            # 8 邻接扩散
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny][3] > 5:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
            comps.append(pts)
    if not comps:
        return frame                             # 整帧空白，原样返回
    comps.sort(key=len, reverse=True)            # 按面积从大到小排序
    # 主角色包围盒：用来识别"悬浮在角色上方的残线"（源图裁剪带进的上一行地线）
    mx0, my0, mx1, my1 = _bbox(comps[0], w, h)
    content_bottom = max(_bbox(p, w, h)[3] for p in comps)   # 全帧内容最低点（贴地影子的位置）
    keep = set()
    for pts in comps:
        if len(pts) < max(12, len(comps[0]) * COMP_KEEP):
            continue                             # 太小的碎片：丢弃
        x0, y0, x1, y1 = _bbox(pts, w, h)
        if y1 < my0:                             # 整体位于角色头顶之上：残线，丢弃
            continue
        thin_line = (x1 - x0) >= 3 * (y1 - y0) and (y1 - y0) <= 6   # 又细又长的横条
        if thin_line and y1 < content_bottom - 3:  # 悬空（不在贴地位置）：残线，丢弃
            continue
        keep.update(pts)
    out = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    opx = out.load()
    for (x, y) in keep:
        opx[x, y] = px[x, y]                     # 只回写保留的像素
    return out


def _bbox(pts, w, h):
    """求一组像素点的包围盒 (x0, y0, x1, y1)"""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def trim(frame):
    """裁掉四周透明边，只留内容紧贴的包围盒"""
    bbox = frame.getbbox()                       # PIL 自带：按 alpha 通道算内容包围盒
    return frame.crop(bbox) if bbox else frame


def pack_preview(sheet, cols, rows, cell_w, cell_h):
    """生成白底 + 红色网格线的预览图，方便肉眼验收切分质量"""
    big = Image.new('RGB', (sheet.size[0] * 2, sheet.size[1] * 2), (255, 255, 255))
    rgba = sheet.resize((sheet.size[0] * 2, sheet.size[1] * 2), Image.NEAREST)
    big.paste(rgba, mask=rgba.split()[3])
    from PIL import ImageDraw
    d = ImageDraw.Draw(big)
    for c in range(cols + 1):                    # 竖线
        d.line([(c * cell_w * 2, 0), (c * cell_w * 2, big.size[1])], fill=(255, 0, 0), width=1)
    for r in range(rows + 1):                    # 横线
        d.line([(0, r * cell_h * 2), (big.size[0], r * cell_h * 2)], fill=(255, 0, 0), width=1)
    big.save(OUT_PREVIEW, quality=92)


def strip_top_residual(img):
    """抹掉条图顶部被连带裁进来的横线残渣（生成图上一行的底边）。

    判定：某行不透明像素超过整宽 50% 视为"横线"，连续抹除这些行；
    一旦某行内容骤降（<20% 宽），说明下面是真正的角色头部，立即停止。
    """
    w, h = img.size
    px = img.load()
    out = img.copy()
    opx = out.load()
    erased = 0                                  # 记录抹掉了几行，方便调试
    for y in range(min(8, h)):                  # 只看顶部 8 行，防止误伤整图
        cnt = sum(1 for x in range(w) if px[x, y][3] > 5)
        if cnt > w * 0.5:                       # 这一行是贯穿整宽的横线
            for x in range(w):
                opx[x, y] = (0, 0, 0, 0)        # 抹成完全透明
            erased += 1
        elif cnt < w * 0.2:                     # 内容骤降：到角色头部了，停
            break
    if erased:
        print(f"  顶部抹除 {erased} 行残线")
    return out


# ---------- 主流程 ----------
os.makedirs(OUT_CELLS, exist_ok=True)
all_frames = {}                                  # {动作名: [帧列表]}
for fname, action, feet_align in STRIPS:
    img = load_rgba(fname)
    img = strip_top_residual(img)                    # 先抹顶部残线，再切分
    frames = split_frames(img, FRAMES_PER_STRIP)
    frames = [remove_fragments(f) for f in frames]   # 去掉切边碎片
    frames = [trim(f) for f in frames]               # 裁到内容边界
    all_frames[action] = frames
    bh = [f.size[1] for f in frames]
    print(f"{action}({fname}): 8帧内容高度 = {bh}")

# 统一缩放比例：以跑步条里最高的帧为基准，缩放到 TARGET_H
run_max_h = max(f.size[1] for f in all_frames['run'])

# 翻滚条（二段跳）来自另一批高分辨率生成图，先归一化体型：
# 把它的最高帧缩放到与跑步条最高帧一致，保证四个动作里角色一样大
flip_max_h = max(f.size[1] for f in all_frames['flip'])
pre = run_max_h / flip_max_h
if abs(pre - 1) > 0.01:                          # 比例明显偏离 1 才需要归一化
    all_frames['flip'] = [
        f.resize((max(1, round(f.size[0] * pre)), max(1, round(f.size[1] * pre))), Image.LANCZOS)
        for f in all_frames['flip']
    ]
    print(f"翻滚条归一化: 最高帧 {flip_max_h}px × {pre:.4f} → {run_max_h}px（与跑步体型对齐）")

scale = min(TARGET_H / run_max_h, SCALE_MAX)
print(f"跑步最高帧 {run_max_h}px → 缩放比例 {scale:.3f}（全动作统一，保证体型一致）")

for action in all_frames:
    all_frames[action] = [
        f.resize((max(1, round(f.size[0] * scale)), max(1, round(f.size[1] * scale))), Image.LANCZOS)
        for f in all_frames[action]
    ]

# 计算统一格子的宽高：所有 32 帧（缩放后）的最大宽高 + 左右边距
cell_w = max(f.size[0] for fs in all_frames.values() for f in fs) + MARGIN * 2
cell_h = max(f.size[1] for fs in all_frames.values() for f in fs) + MARGIN * 2
print(f"格子尺寸: {cell_w}x{cell_h} → 精灵表 {cell_w * 8}x{cell_h * 4}")

# 拼版：8列×4行，行顺序 = 跑 / 跳 / 翻 / 滑（和游戏 FRAMES 顺序一致）
order = ['run', 'jump', 'flip', 'slide']
sheet = Image.new('RGBA', (cell_w * 8, cell_h * 4), (0, 0, 0, 0))
for ri, action in enumerate(order):
    feet_align = dict((a, fa) for _, a, fa in STRIPS)[action]   # 该行是否脚底对齐
    for ci, f in enumerate(all_frames[action]):
        fw, fh = f.size
        px_x = ci * cell_w + (cell_w - fw) // 2                  # 水平居中
        px_y = (ri * cell_h + cell_h - MARGIN - fh) if feet_align else (ri * cell_h + (cell_h - fh) // 2)
        sheet.paste(f, (px_x, px_y))
        f.save(f'{OUT_CELLS}/{action}{ci}.png')                  # 存单帧调试图

sheet.save(OUT_SHEET)
print(f"已输出精灵表: {OUT_SHEET}")
pack_preview(sheet, 8, 4, cell_w, cell_h)
print(f"预览图: {OUT_PREVIEW}")
print(f"FRAMES 坐标系: 格子 {cell_w}x{cell_h}, 边距 {MARGIN}, 脚底锚点 y = cell_h - {MARGIN}")
