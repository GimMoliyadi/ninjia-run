// ============ 墨渍素材加载 ============
// Kenney Splat Pack（CC0 免费）共 36 张墨渍 PNG，本模块负责：
//   1) 从 public/splat/ 预加载全部图片（游戏启动时并行拉取，避免播放中途卡顿）
//   2) 把白色墨渍染色成游戏墨色（INK），返回可绘制的离屏画布数组
//   3) 供 particles.splatBurst() 随机抽取叠绘，形成水墨四溅效果
import { INK } from './constants.js';

const SPLAT_COUNT = 36;              // 素材包内墨渍张数（splat00 ~ splat35）
const SPLAT_SIZE = 256;              // 素材原始尺寸（256×256）

// 测试环境（Node 无全局 Image）不加载图片：splats 保持空数组、splatsReady() 恒为 false，
// 绘制层据此退化为程序化墨点，避免 ReferenceError 中断测试。
const HAS_IMAGE = typeof Image !== 'undefined';

// 染好色的墨渍画布数组：splats[i] 是一张可直接 drawImage 的 canvas
export const splats = [];

// 素材是否全部就绪：绘制前检查，未就绪时退化为程序化墨点，避免白屏
let ready = false;
export function splatsReady() { return ready; }

// 并行加载全部墨渍，加载完成染成墨色（白色墨渍 × source-in 染色 = 保留形状、替换为墨色）
const loaders = [];
if (HAS_IMAGE) {
  for (let i = 0; i < SPLAT_COUNT; i++) {
    loaders.push(new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement('canvas');
        c.width = SPLAT_SIZE; c.height = SPLAT_SIZE;
        const g = c.getContext('2d');
        // 先画原图（白色墨渍在透明底上），再用墨色填满其不透明部分（source-in）
        g.drawImage(img, 0, 0, SPLAT_SIZE, SPLAT_SIZE);
        g.globalCompositeOperation = 'source-in';
        g.fillStyle = INK;
        g.fillRect(0, 0, SPLAT_SIZE, SPLAT_SIZE);
        splats[i] = c;
        resolve();
      };
      img.onerror = () => resolve();   // 单张失败不阻塞整体，缺的图绘制时会被跳过
      img.src = `splat/splat${String(i).padStart(2, '0')}.png`;
    }));
  }
}

// 全部就绪后置 ready，游戏循环每帧读此标志
Promise.all(loaders).then(() => { ready = true; });
