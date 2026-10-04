import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from layer_export import export_layers
from region_layout import REGIONS

PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = PROJECT_ROOT / "assets/player/cultivator/rig_v2"
SOURCE_SIZE = (1086, 1448)
OPAQUE_THRESHOLD = 250
NOISE_ALPHA_MAXIMUM = 1
OUTLINE_BLEND_PIXELS = 3
RECONSTRUCTION_OVERLAP_PIXELS = 12
MAXIMUM_UNCLASSIFIED_DISTANCE = 80.0
MAXIMUM_MATERIAL_ROUTE_DISTANCE = 40.0
HAIR_BOTTOM_Y = 600
HAIR_SHADOW_RED_MAXIMUM = 120
HAIR_DONOR_RED_MAXIMUM = 160
WHITE_DONOR_WARMTH_MAXIMUM = 12
HIDDEN_TEXTURE_SMOOTHING_PIXELS = 4.0
HAND_TOP_Y = 650
REGION_BY_NAME = {region.name: region for region in REGIONS}
PANTS_BOTTOM_Y = 1035
PANTS_DONOR_BOTTOM_Y = 1000
COLLAR_TOP_Y = 218
SHOULDER_CAP = ((449,287),(465,289),(482,301),(493,321),(493,336),(473,351),(422,374),(433,342),(438,309))


def polygon_mask(points):
    canvas = Image.new("L", SOURCE_SIZE)
    ImageDraw.Draw(canvas).polygon(points, fill=255)
    return np.asarray(canvas) != 0


def preprocess_source(source):
    base = source.copy()
    alpha = base[:, :, 3]
    labels, count = ndimage.label(alpha > 0)
    maxima = ndimage.maximum(alpha, labels, range(1, count + 1))
    noise_ids = np.flatnonzero(maxima <= NOISE_ALPHA_MAXIMUM) + 1
    noise = np.isin(labels, noise_ids) & (alpha > 0)
    base[noise] = 0
    normalized = (alpha >= OPAQUE_THRESHOLD) & (alpha < 255)
    alpha[normalized] = 255
    base[alpha == 0, :3] = 0
    return base, {
        "opaque_threshold": OPAQUE_THRESHOLD,
        "alpha_normalized_pixels": int(normalized.sum()),
        "removed_isolated_alpha_one_pixels": int(noise.sum()),
        "maximum_alpha_change": int(np.abs(base[:, :, 3].astype(int) - source[:, :, 3]).max()),
        "notes": "原图另存不改。仅规范化主体近不透明像素；剔除独立且alpha不超过1的连通杂点，保留轮廓边缘。",
    }


def color_masks(base):
    red, green, blue = base[:, :, :3].astype(np.int16).transpose(2, 0, 1)
    skin = (red > 70) & (red - green > 2) & (green - blue > 2)
    skin = ndimage.binary_dilation(ndimage.binary_fill_holes(skin), iterations=OUTLINE_BLEND_PIXELS)
    return {
        "red": red,
        "skin": skin,
        "hair": (red < 190) & (red - green > 3) & (red - blue > 4),
        "blue": (green - red > 6) & (blue - red > 8),
        "weapon": (green - red < 12) & (blue - red < 14),
        "pants": (red > 95) & (green - red < 25) & (blue - red < 45) & (green - blue < 20),
        "pants_donor": (red > 100) & (red - blue <= WHITE_DONOR_WARMTH_MAXIMUM) & (np.abs(red - green) < 18) & (blue - red < 45),
    }


def region_masks(region, colors):
    if region.name == "Sword":
        empty = np.zeros((SOURCE_SIZE[1], SOURCE_SIZE[0]), dtype=bool)
        return empty, empty
    outlines = region.polygons
    footprint = np.zeros((SOURCE_SIZE[1], SOURCE_SIZE[0]), dtype=bool)
    for index, points in enumerate(outlines):
        part = polygon_mask(points)
        if region.name == "CoatBack_R" and index == 1:
            part &= colors["blue"]
        footprint |= part
    known = footprint.copy()
    if region.color_filter:
        known &= colors[region.color_filter]
    if region.name == "HairBack":
        known &= ndimage.binary_dilation(colors["hair"], iterations=1)
    if region.name.startswith("Leg_"):
        known[:PANTS_BOTTOM_Y] &= colors["pants"][:PANTS_BOTTOM_Y]
    elif region.name.startswith("Arm_"):
        known[HAND_TOP_Y:] &= ~colors["skin"][HAND_TOP_Y:]
        hair_footprint = polygon_mask(REGION_BY_NAME["HairBack"].polygons[0])
        dark_hair = colors["hair"] & (colors["red"] < HAIR_SHADOW_RED_MAXIMUM) & hair_footprint
        known &= ~dark_hair
        if region.name == "Arm_L":
            cap = polygon_mask(SHOULDER_CAP)
            known |= cap
            footprint |= cap
    elif region.name == "HeadFace":
        known[COLLAR_TOP_Y:] &= colors["skin"][COLLAR_TOP_Y:]
    elif region.name == "Torso":
        known &= ~polygon_mask(SHOULDER_CAP)
    return known, footprint


def route_material_boundaries(owners, unknown, colors):
    excluded_blue = {"HairBack", "Leg_L", "Leg_R", "Hand_L", "Hand_R", "Sword", "Scabbard"}
    excluded_white = {"HairBack", "Ribbon_L", "Ribbon_R", "Hand_L", "Hand_R", "HeadFace", "Sword", "Scabbard"}
    misplaced = {"blue": {"HairBack", "Leg_L", "Leg_R"}, "pants": {"HairBack"}}
    for material, excluded in (("blue", excluded_blue), ("pants", excluded_white)):
        seeds = colors[material] & np.isin(owners, [index for index, part in enumerate(REGIONS, 1) if part.name not in excluded])
        wrong_ids = [index for index, part in enumerate(REGIONS, 1) if part.name in misplaced[material]]
        target = unknown & colors[material] & np.isin(owners, wrong_ids)
        if material == "blue":
            allowed_area = np.zeros(owners.shape, dtype=bool)
            hair_id = next(index for index, part in enumerate(REGIONS, 1) if part.name == "HairBack")
            allowed_area[:HAIR_BOTTOM_Y] |= owners[:HAIR_BOTTOM_Y] == hair_id
            leg_ids = [index for index, part in enumerate(REGIONS, 1) if part.name.startswith("Leg_")]
            allowed_area[:PANTS_BOTTOM_Y] |= np.isin(owners[:PANTS_BOTTOM_Y], leg_ids)
            target &= allowed_area
        if target.any():
            distance, nearest = ndimage.distance_transform_edt(~seeds, return_indices=True)
            target &= distance <= MAXIMUM_MATERIAL_ROUTE_DISTANCE
            owners[target] = owners[tuple(nearest[:, target])]
    skin_names = {"HeadFace", "Hand_L", "Hand_R"}
    skin_area = np.zeros(owners.shape, dtype=bool)
    for part in REGIONS:
        if part.name in skin_names:
            skin_area |= polygon_mask(part.polygons[0])
    skin_area = ndimage.binary_dilation(skin_area, iterations=RECONSTRUCTION_OVERLAP_PIXELS)
    target = unknown & colors["skin"] & skin_area
    if target.any():
        skin_ids = [index for index, part in enumerate(REGIONS, 1) if part.name in skin_names]
        seeds = colors["skin"] & np.isin(owners, skin_ids)
        _, nearest = ndimage.distance_transform_edt(~seeds, return_indices=True)
        owners[target] = owners[tuple(nearest[:, target])]


def assign_visible_pixels(base, masks, colors):
    owners = np.zeros(base.shape[:2], dtype=np.int16)
    active = base[:, :, 3] > 0
    indices = sorted(range(len(REGIONS)), key=lambda index: REGIONS[index].z_index)
    for index in indices:
        owners[masks[index] & active] = index + 1
    unknown = active & (owners == 0)
    distance, nearest = ndimage.distance_transform_edt(owners == 0, return_indices=True)
    maximum = float(distance[unknown].max()) if unknown.any() else 0.0
    if maximum > MAXIMUM_UNCLASSIFIED_DISTANCE:
        raise ValueError(f"未归属像素距离已有分区最远{maximum:.1f}px，必须修正布局，不能静默分配")
    owners[unknown] = owners[tuple(nearest[:, unknown])]
    route_material_boundaries(owners, unknown, colors)
    if np.any(active & (owners == 0)):
        raise ValueError("仍存在没有分层归属的可见像素")
    return owners, {"nearest_boundary_pixels": int(unknown.sum()), "maximum_boundary_distance": maximum}


def reconstruct_layer(base, owners, region, index, footprint, colors):
    visible = owners == index
    rgba = np.zeros_like(base)
    rgba[visible] = base[visible]
    if not region.reconstruct or not visible.any():
        return rgba, 0
    layer_z = np.array([0] + [part.z_index for part in REGIONS])
    expanded = ndimage.binary_dilation(footprint, iterations=RECONSTRUCTION_OVERLAP_PIXELS)
    covered = layer_z[owners] > region.z_index
    target = expanded & covered & (base[:, :, 3] == 255) & ~visible
    donor = visible & (base[:, :, 3] >= OPAQUE_THRESHOLD)
    if region.name.startswith("Leg_"):
        donor &= colors["pants_donor"] & ~colors["hair"]
        donor[PANTS_DONOR_BOTTOM_Y:] = False
    elif region.name == "HairBack":
        donor &= colors["hair"] & (colors["red"] < HAIR_DONOR_RED_MAXIMUM)
    if not donor.any():
        raise ValueError(f"{region.name}没有可用于补足遮挡区域的同区纹理")
    _, nearest = ndimage.distance_transform_edt(~donor, return_indices=True)
    fill_colors = base[nearest[0], nearest[1], :3].astype(np.float32)
    fill_colors = ndimage.gaussian_filter(fill_colors, sigma=(HIDDEN_TEXTURE_SMOOTHING_PIXELS, HIDDEN_TEXTURE_SMOOTHING_PIXELS, 0))
    rgba[target, :3] = np.rint(fill_colors[target]).astype(np.uint8)
    rgba[target, 3] = 255
    return rgba, int(target.sum())


def build_layers(base):
    colors = color_masks(base)
    masks_and_footprints = [region_masks(region, colors) for region in REGIONS]
    masks = [pair[0] for pair in masks_and_footprints]
    owners, statistics = assign_visible_pixels(base, masks, colors)
    layers = []
    for index, (region, (_, footprint)) in enumerate(zip(REGIONS, masks_and_footprints), 1):
        rgba, reconstructed = reconstruct_layer(base, owners, region, index, footprint, colors)
        if region.name != "Sword" and not np.any(rgba[:, :, 3]):
            raise ValueError(f"{region.name}分区为空")
        layers.append((region, rgba, reconstructed))
    statistics["visible_pixel_count"] = int((base[:, :, 3] > 0).sum())
    statistics["reconstructed_pixel_count"] = sum(layer[2] for layer in layers)
    return layers, statistics


def main():
    parser = argparse.ArgumentParser(description="从中性立绘生成透明分层素材，不运行Godot或制作动画")
    parser.add_argument("source", type=Path)
    arguments = parser.parse_args()
    original = Image.open(arguments.source).convert("RGBA")
    if original.size != SOURCE_SIZE:
        raise ValueError(f"需要{SOURCE_SIZE}立绘，实际为{original.size}")
    source = np.asarray(original)
    base, preprocessing = preprocess_source(source)
    layers, statistics = build_layers(base)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    export_layers(OUTPUT_DIR, original, base, layers, preprocessing, statistics)
    print(f"已输出18个可见部件+1个不可见剑体占位，真实纹理补足{statistics['reconstructed_pixel_count']}像素。")
    print(f"与预处理基准中性合成RGBA零误差；输入主体alpha规范化最大差{preprocessing['maximum_alpha_change']}。")
    print(f"边界归属补足{statistics['nearest_boundary_pixels']}像素，最远{statistics['maximum_boundary_distance']:.1f}px。")


if __name__ == "__main__":
    main()
