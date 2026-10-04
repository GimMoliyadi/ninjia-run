// 精灵表加载与帧裁剪坐标
// 图片由 split_and_pack.py 生成：8列×4行、每格 81×81、四周留 2px 透明边距，
// 角色像素不贴格线，绘制时平滑采样不会把相邻帧带进来（"头上顶脚"问题已根治）。

// 帧网格尺寸：每格 81×81
export const FRAME_W = 81;
export const FRAME_H = 81;
// 贴图锚点：把整格左上角定位到 (屏幕x - 半格宽, 屏幕脚底y - 格高 + 底部留白)，
// 使角色脚底（内容底边 = 格内第 79 行）落在传入的 y 上
export const ANCHOR_X = FRAME_W / 2;   // 水平居中锚点（半格宽）
export const ANCHOR_Y = FRAME_H - 2;   // 垂直锚点：格高去掉 2px 底部留白

const HAS_IMAGE = typeof Image !== 'undefined';
const IMG = HAS_IMAGE ? new Image() : { complete: false, naturalWidth: 0 };
if (HAS_IMAGE) {
  // 优先加载重排后的新图；失败则回退旧图（兼容开发预览的 /public 路径）
  IMG.onerror = () => {
    if (!IMG.src.endsWith('ninja-sprites.png')) IMG.src = 'ninja-sprites.png';
    else if (!IMG.src.endsWith('/public/ninja-sprites.png')) IMG.src = 'public/ninja-sprites.png';
  };
  IMG.src = 'ninja-sprites-padded.png';
}
export const SPRITES_READY = HAS_IMAGE
  ? new Promise((r) => { IMG.onload = r; })   // 图片加载完成时置为已就绪
  : Promise.resolve();                         // 测试环境（无 Image）直接视为就绪

// 帧裁剪表：每行 8 帧——行0 跑 / 行1 一段跳弧线 / 行2 二段跳翻滚 / 行3 滑铲
const row = (r) => [0, 1, 2, 3, 4, 5, 6, 7].map((i) => ({ x: i * FRAME_W, y: r * FRAME_H, w: FRAME_W, h: FRAME_H }));
export const FRAMES = {
  run: row(0),      // 跑步循环 8 帧（首尾相接可循环）
  jump: row(1),     // 一段跳 8 帧：0蹲起 1蹬地 2上升 3近顶点 4顶点 5下坠 6下落 7触地前
  flip: row(2),     // 二段跳翻滚 8 帧：0-6 团身转体，7 展开落地
  slide: row(3),    // 滑铲循环 8 帧（首尾相接可循环）
};
export function getImg() { return IMG; }
