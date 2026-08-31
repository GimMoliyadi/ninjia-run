import { G } from './state.js';
import { ZONE_VILLAGE_AT, ZONE_MOUNTAIN_AT, ZONE_TRANSITION_T } from './constants.js';

export const ZONE = { BAMBOO: 'bamboo', VILLAGE: 'village', MOUNTAIN: 'mountain' };

// 各区域配置：天空渐变、地面填充、远山透明度，供 background 按区绘制
export const ZONE_CFG = {
  [ZONE.BAMBOO]: {
    name: '翠竹林',
    sky: ['#f7f2e3', '#ece4cf'],
    ground: 'rgba(58,54,48,0.52)',
    mountainA: [0.045, 0.115],
    accent: '#3a6b4a',   // 竹叶/墨绿点缀
  },
  [ZONE.VILLAGE]: {
    name: '黄昏村',
    sky: ['#f6e7cd', '#e7c49a'],
    ground: 'rgba(74,56,42,0.55)',
    mountainA: [0.08, 0.16],
    accent: '#a85c32',   // 灯笼/赭石点缀
  },
  [ZONE.MOUNTAIN]: {
    name: '夜冥山',
    sky: ['#cfd8e0', '#9fb0c2'],
    ground: 'rgba(44,54,66,0.6)',
    mountainA: [0.12, 0.2],
    accent: '#4f7f8c',   // 鬼火/青蓝点缀
  },
};

export function zoneAtM(m) {
  if (m < ZONE_VILLAGE_AT) return ZONE.BAMBOO;
  if (m < ZONE_MOUNTAIN_AT) return ZONE.VILLAGE;
  return ZONE.MOUNTAIN;
}

export function zoneName(zone) { return ZONE_CFG[zone].name; }

// 区域切换：进入新区时启动泼墨过渡（engine 每帧调用）
export function updateZone() {
  const next = zoneAtM(G.distM);
  if (next === G.zone) return;
  G.zone = next;
  G.zoneTransitionT = ZONE_TRANSITION_T;
}
