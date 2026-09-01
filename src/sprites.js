// 精灵表加载与帧裁剪坐标
const HAS_IMAGE = typeof Image !== 'undefined';
const IMG = HAS_IMAGE ? new Image() : { complete: false, naturalWidth: 0 };
if (HAS_IMAGE) {
  // Vite maps public/ to the site root. The fallback also supports the
  // simple static server used for local previews, which exposes /public/.
  IMG.onerror = () => {
    if (!IMG.src.endsWith('/public/ninja-sprites.png')) IMG.src = 'public/ninja-sprites.png';
  };
  IMG.src = 'ninja-sprites.png';
}  // Vite public 目录
export const SPRITES_READY = HAS_IMAGE
  ? new Promise((r) => { IMG.onload = r; })
  : Promise.resolve();
export const FRAMES = {
  run: [0, 1, 2, 3, 4, 5].map(i => ({ x: i * 128, y: 0, w: 128, h: 128 })),
  jump1: [{ x: 0, y: 128, w: 128, h: 128 }],
  jump2: [{ x: 128, y: 128, w: 128, h: 128 }],
  slide: [
    { x: 0, y: 256, w: 128, h: 128 },
    { x: 128, y: 256, w: 128, h: 128 },
  ],
};
export function getImg() { return IMG; }
