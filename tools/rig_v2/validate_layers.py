import argparse
import io
import json
import zipfile
from pathlib import Path
from xml.etree import ElementTree

import numpy as np
from PIL import Image

from rig_definition import BONE_BY_NAME

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = PROJECT_ROOT / "assets/player/cultivator/rig_v2"
MOUNT_NAMES = {"ScabbardAnchor", "SheathedSwordSocket"}
EXPECTED_LAYER_COUNT = 19
EXPECTED_VISIBLE_COUNT = 18


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_textures(manifest):
    regions = manifest["regions"]
    require(len(regions) == EXPECTED_LAYER_COUNT, "分层数量不正确")
    require(len({part["name"] for part in regions}) == len(regions), "图层名称重复")
    require(len({part["texture"] for part in regions}) == len(regions), "部件共享了相同的整图贴图")
    require(sum(part["visible"] for part in regions) == EXPECTED_VISIBLE_COUNT, "可见图层数量不正确")
    width, height = manifest["source_size"]
    for part in regions:
        image = Image.open(PROJECT_ROOT / part["texture"])
        x, y, part_width, part_height = part["bounds"]
        require(image.mode == "RGBA", f"{part['name']}不是透明RGBA素材")
        require(image.size == (part_width, part_height), f"{part['name']}裁切尺寸与坐标记录不一致")
        require(0 <= x < x + part_width <= width and 0 <= y < y + part_height <= height, f"{part['name']}坐标越界")
        require(image.size != (width, height), f"{part['name']}仍在使用整幅人物图")
        require(set(part["influences"]) <= set(BONE_BY_NAME), f"{part['name']}存在无效骨链名称")
        if part["rigid_bone"]:
            require(part["rigid_bone"] in set(BONE_BY_NAME) | MOUNT_NAMES, f"{part['name']}挂点不正确")
        alpha = np.asarray(image)[:, :, 3]
        if part["unavailable"]:
            require(part["name"] == "Sword" and image.size == (1, 1) and not alpha.any(), "不可见剑体占位不透明")
        else:
            require(alpha.any(), f"{part['name']}实际为空")
            require(int((alpha == 255).sum()) >= part["reconstructed_pixels"], f"{part['name']}补足记录没有真实不透明像素")


def validate_openraster(manifest, expected):
    by_name = {part["name"]: part for part in manifest["regions"]}
    with zipfile.ZipFile(ASSET_DIR / "layered-character.ora") as archive:
        require(archive.testzip() is None, "ORA压缩包校验失败")
        first = archive.infolist()[0]
        require(first.filename == "mimetype" and first.compress_type == zipfile.ZIP_STORED, "ORA mimetype必须首项且不压缩")
        require(archive.read("mimetype") == b"image/openraster", "ORA类型不正确")
        document = ElementTree.fromstring(archive.read("stack.xml"))
        layers = document.findall("./stack/layer")
        require(len(layers) == EXPECTED_LAYER_COUNT, "ORA图层缺失")
        require([layer.attrib["name"] for layer in layers] == [part["name"] for part in sorted(by_name.values(), key=lambda part: part["z_index"], reverse=True)], "ORA前后层级不正确")
        canvas = Image.new("RGBA", tuple(manifest["source_size"]))
        for layer in reversed(layers):
            attributes = layer.attrib
            part = by_name[attributes["name"]]
            offset = (int(attributes["x"]), int(attributes["y"]))
            require(offset == tuple(part["bounds"][:2]), f"ORA {part['name']}位置不正确")
            require((attributes["visibility"] == "visible") == part["visible"], f"ORA {part['name']}显示状态不正确")
            image = Image.open(io.BytesIO(archive.read(attributes["src"]))).convert("RGBA")
            png = Image.open(PROJECT_ROOT / part["texture"]).convert("RGBA")
            require(np.array_equal(np.asarray(image), np.asarray(png)), f"ORA {part['name']}与独立PNG不同")
            if part["visible"]:
                canvas.alpha_composite(image, offset)
        merged = Image.open(io.BytesIO(archive.read("mergedimage.png"))).convert("RGBA")
        require(np.array_equal(np.asarray(canvas), expected), "从ORA真实图层复合后与中性基准不同")
        require(np.array_equal(np.asarray(merged), expected), "ORA合成预览与真实图层不同")


def main():
    parser = argparse.ArgumentParser(description="只检查分层素材完整性，不运行Gameplay或骨骼动画")
    parser.add_argument("source", type=Path)
    arguments = parser.parse_args()
    manifest = json.loads((ASSET_DIR / "regions.json").read_text(encoding="utf-8"))
    validate_textures(manifest)
    source = np.asarray(Image.open(arguments.source).convert("RGBA"))
    reference = np.asarray(Image.open(ASSET_DIR / "neutral-reference.png").convert("RGBA"))
    require(np.array_equal(source, reference), "原图存档像素被修改")
    expected = np.asarray(Image.open(ASSET_DIR / "neutral-base.png").convert("RGBA"))
    composite = np.asarray(Image.open(ASSET_DIR / "neutral-composite.png").convert("RGBA"))
    require(np.array_equal(composite, expected), "独立PNG中性复合与基准不一致")
    validate_openraster(manifest, expected)
    print("素材检查通过：18个可见透明PNG、1个透明剑体占位、19层ORA；尺寸、偏移、层级与独立复合一致，原图存档未改。")
    print("只验证素材结构和中性复合，不代表隐藏部位补绘或动画变形已验收。")


if __name__ == "__main__":
    main()
