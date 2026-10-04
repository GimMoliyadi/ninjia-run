import { G } from './state.js';
import { ZONE_VILLAGE_AT, ZONE_MOUNTAIN_AT, ZONE_TRANSITION_T } from './constants.js';

export const ZONE = { BAMBOO: 'bamboo', VILLAGE: 'village', MOUNTAIN: 'mountain' };

// 各区域配置：天空渐变、地面填充、远山透明度、天空天体，供 background 按区绘制
export const ZONE_CFG = {
  [ZONE.BAMBOO]: {
    name: '翠竹林',
    sky: ['#f7f2e3', '#f2e8d0', '#ece4cf'],
    ground: 'rgba(58,54,48,0.52)',
    mountainA: [0.045, 0.115],
    accent: '#3a6b4a',   // 竹叶/墨绿点缀
    // 晨雾霞光：淡金色太阳低悬林间
    heaven: { type: 'sun', x: 0.78, y: 0.22, r: 32, color: 'rgba(232,162,75,0.7)', glow: 'rgba(232,162,75,0.3)' },
  },
  [ZONE.VILLAGE]: {
    name: '黄昏村',
    sky: ['#f6dbb0', '#e7c49a', '#c89a6a'],
    ground: 'rgba(74,56,42,0.55)',
    mountainA: [0.08, 0.16],
    accent: '#a85c32',   // 灯笼/赭石点缀
    // 夕阳：橘红落日贴近地平线，余晖浸染天际
    heaven: { type: 'sun', x: 0.62, y: 0.35, r: 44, color: 'rgba(200,90,40,0.8)', glow: 'rgba(200,90,40,0.35)' },
  },
  [ZONE.MOUNTAIN]: {
    name: '夜冥山',
    sky: ['#2b3442', '#405064', '#5a6d80'],
    ground: 'rgba(44,54,66,0.6)',
    mountainA: [0.12, 0.2],
    accent: '#4f7f8c',   // 鬼火/青蓝点缀
    // 夜月：冷白残月悬于夜空，清辉铺洒
    heaven: { type: 'moon', x: 0.25, y: 0.15, r: 30, color: 'rgba(200,210,220,0.6)', glow: 'rgba(180,200,220,0.2)' },
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
