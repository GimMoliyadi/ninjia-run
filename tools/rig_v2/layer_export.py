import io
import json
import re
import zipfile
from xml.etree import ElementTree

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PREVIEW_COLUMNS = 4
PREVIEW_CELL_SIZE = (360, 330)
PREVIEW_IMAGE_MARGIN = 16
PREVIEW_LABEL_HEIGHT = 56
CHECKER_SIZE = 12
THUMBNAIL_SIZE = (256, 256)
ASSET_PREFIX = "assets/player/cultivator/rig_v2/"


def png_bytes(image):
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def texture_filename(name):
    separated = re.sub("([a-z0-9])([A-Z])", lambda match: match[1] + "_" + match[2], name)
    return separated.lower() + ".png"


def save_layer(output_dir, region, rgba, reconstructed):
    image = Image.fromarray(rgba)
    box = image.getbbox()
    unavailable = region.name == "Sword"
    if unavailable:
        box = (553, 563, 554, 564)
    cropped = image.crop(box)
    filename = texture_filename(region.name)
    cropped.save(output_dir / filename)
    notes = "图中可见区域由原画分离，独立透明贴图。"
    if reconstructed:
        notes += " 遮挡底层采用本区域相同材质的邻近可见纹理延展补足；不是隐藏结构的精确复原。"
    if unavailable:
        notes = "原图未露出可独立确认的剑体，只有剑鞘。保留1x1透明占位，不伪造剑柄或剑刃。"
    influences = list(region.influences)
    if region.name.startswith("Arm_"):
        influences.insert(0, "Chest")
    entry = {
        "name": region.name,
        "texture": ASSET_PREFIX + filename,
        "bounds": [box[0], box[1], box[2] - box[0], box[3] - box[1]],
        "outline": [] if unavailable else [list(point) for point in region.polygons[0]],
        "outlines": [] if unavailable else [[list(point) for point in polygon] for polygon in region.polygons],
        "rigid_bone": region.rigid_bone,
        "influences": influences,
        "z_index": region.z_index,
        "visible": not unavailable,
        "unavailable": unavailable,
        "reconstructed_pixels": reconstructed,
        "notes": notes,
    }
    return entry, cropped


def composite_layers(size, layers):
    canvas = Image.new("RGBA", size)
    for entry, image in sorted(layers, key=lambda layer: layer[0]["z_index"]):
        if entry["visible"]:
            canvas.alpha_composite(image, tuple(entry["bounds"][:2]))
    return canvas


def checkerboard(size):
    canvas = Image.new("RGBA", size, (240, 242, 245, 255))
    draw = ImageDraw.Draw(canvas)
    for y in range(0, size[1], CHECKER_SIZE):
        for x in range(0, size[0], CHECKER_SIZE):
            if (x // CHECKER_SIZE + y // CHECKER_SIZE) % 2:
                draw.rectangle((x, y, x + CHECKER_SIZE - 1, y + CHECKER_SIZE - 1), fill=(218, 223, 229, 255))
    return canvas


def save_preview(output_dir, layers):
    width, height = PREVIEW_CELL_SIZE
    rows = (len(layers) + PREVIEW_COLUMNS - 1) // PREVIEW_COLUMNS
    preview = Image.new("RGBA", (width * PREVIEW_COLUMNS, height * rows), (250, 250, 252, 255))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    for index, (entry, image) in enumerate(layers):
        x, y = (index % PREVIEW_COLUMNS) * width, (index // PREVIEW_COLUMNS) * height
        area_size = (width - 2 * PREVIEW_IMAGE_MARGIN, height - PREVIEW_LABEL_HEIGHT - PREVIEW_IMAGE_MARGIN)
        tile = checkerboard(area_size)
        display = image.copy()
        display.thumbnail((area_size[0] - 20, area_size[1] - 20), Image.Resampling.LANCZOS)
        tile.alpha_composite(display, ((area_size[0] - display.width) // 2, (area_size[1] - display.height) // 2))
        preview.alpha_composite(tile, (x + PREVIEW_IMAGE_MARGIN, y + PREVIEW_LABEL_HEIGHT))
        draw = ImageDraw.Draw(preview)
        draw.text((x + 16, y + 6), entry["name"], font=font, fill=(28, 37, 49, 255))
        detail = "原图不可见：透明占位" if entry["unavailable"] else f"底层推断补足 {entry['reconstructed_pixels']} 像素"
        draw.text((x + 16, y + 30), detail, font=font, fill=(75, 86, 101, 255))
    preview.convert("RGB").save(output_dir / "layer_preview.png")


def save_openraster(output_dir, size, layers, merged):
    document = ElementTree.Element("image", {"w": str(size[0]), "h": str(size[1]), "name": "青蓝劲装少年分层素材", "version": "0.0.3"})
    stack = ElementTree.SubElement(document, "stack", {"name": "角色素材"})
    thumbnail = merged.copy()
    thumbnail.thumbnail(THUMBNAIL_SIZE, Image.Resampling.LANCZOS)
    with zipfile.ZipFile(output_dir / "layered-character.ora", "w") as archive:
        archive.writestr("mimetype", "image/openraster", compress_type=zipfile.ZIP_STORED)
        for index, (entry, image) in enumerate(sorted(layers, key=lambda layer: layer[0]["z_index"], reverse=True)):
            path = f"data/layer_{index:02d}.png"
            ElementTree.SubElement(stack, "layer", {
                "name": entry["name"], "src": path,
                "x": str(entry["bounds"][0]), "y": str(entry["bounds"][1]),
                "opacity": "1.0", "visibility": "visible" if entry["visible"] else "hidden",
                "composite-op": "svg:src-over",
            })
            archive.writestr(path, png_bytes(image), compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("stack.xml", ElementTree.tostring(document, encoding="utf-8", xml_declaration=True), compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("mergedimage.png", png_bytes(merged), compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("Thumbnails/thumbnail.png", png_bytes(thumbnail), compress_type=zipfile.ZIP_DEFLATED)


def export_layers(output_dir, original, base, layers, preprocessing, statistics):
    exported = [save_layer(output_dir, region, rgba, reconstructed) for region, rgba, reconstructed in layers]
    composite = composite_layers(original.size, exported)
    difference = np.abs(np.asarray(composite).astype(np.int16) - base.astype(np.int16))
    if np.any(difference):
        raise ValueError(f"中性分层合成未保真：最大RGBA误差{difference.max()}，不能宣称素材通过")
    original.save(output_dir / "neutral-reference.png")
    Image.fromarray(base).save(output_dir / "neutral-base.png")
    composite.save(output_dir / "neutral-composite.png")
    save_preview(output_dir, exported)
    save_openraster(output_dir, original.size, exported, composite)
    manifest = {
        "source_size": list(original.size),
        "preprocessing": preprocessing,
        "statistics": {**statistics, "composite_maximum_rgba_error": int(difference.max())},
        "regions": [entry for entry, _ in exported],
    }
    (output_dir / "regions.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
