# 关卡编辑器开发交接文档

## 一、当前问题清单(优先级:高)

### 1.1 致命Bug - 对象无法移动
**现象**: 
- 从左侧拖动障碍物到画布后,对象无法再次被选中或移动
- Delete 键无反应
- 属性面板无法更新

**根因分析**:
`canvas-editor.js` 中 `getObjectAtPosition()` 方法可能存在问题:
- 碰撞检测逻辑错误
- 鼠标坐标转换问题(屏幕坐标 vs 世界坐标)
- 对象 x/y 存储与检测不一致

**修复方向**:
1. 在 `getObjectAtPosition()` 中添加 console.log 调试:
   ```javascript
   console.log('检测位置:', worldX, worldY);
   console.log('障碍物列表:', this.state.currentSegment.obstacles);
   ```
2. 检查障碍物的 `y` 坐标是否正确(可能是顶部坐标 vs 底部坐标混淆)
3. 确认 `mousedown` 事件是否正确触发

**优先级**: 🔥 **立即修复**

---

### 1.2 缺失功能 - 撤销/重做
**需求**:
- Ctrl+Z 撤销上一步操作
- Ctrl+Y 重做

**实现思路**:
```javascript
// 在 EditorState 中新增:
history: {
  past: [],      // 历史状态栈
  future: []     // 重做栈
}

// 每次修改前保存快照:
function saveSnapshot() {
  const snapshot = JSON.parse(JSON.stringify(state.currentSegment));
  state.history.past.push(snapshot);
  state.history.future = [];  // 新操作清空重做栈
  if (state.history.past.length > 50) {
    state.history.past.shift();  // 限制历史记录数量
  }
}

// 撤销:
function undo() {
  if (state.history.past.length === 0) return;
  const current = JSON.parse(JSON.stringify(state.currentSegment));
  state.history.future.push(current);
  state.currentSegment = state.history.past.pop();
  canvasEditor.render();
}
```

---

### 1.3 缺失功能 - 关卡命名与管理
**需求**:
- 编辑器顶部显示当前关卡名称(可点击编辑)
- 保存时自动使用关卡名作为文件名
- 新增"关卡属性"面板

**UI 位置**:
在顶部工具栏中间添加:
```html
<input id="segmentName" type="text" value="新建关卡段落" 
       style="padding: 6px; background: #2a2a2a; border: 1px solid #4a4a4a; 
              color: #d8a441; font-weight: bold; width: 200px;">
```

**保存逻辑修改**:
```javascript
// editor.js 中 saveSegment() 函数:
const name = document.getElementById('segmentName').value;
state.currentSegment.name = name;
const filename = `${name.replace(/\s+/g, '_')}_${state.currentSegment.id}.json`;
a.download = filename;
```

---

### 1.4 缺失功能 - 关卡截止线
**需求**:
- 在画布上放置一个可拖动的"截止线"(红色虚线)
- 保存到 JSON 时记录 `endX` 字段
- 游戏运行时,过了这条线就结束当前段落

**实现**:
```javascript
// 在 EditorState.currentSegment 中新增:
endX: 3600,  // 默认段落结束位置

// 画布上绘制截止线(canvas-editor.js):
drawEndLine() {
  const endX = this.state.currentSegment.endX - this.state.camera.x;
  if (endX < 0 || endX > this.canvas.width) return;
  
  this.ctx.strokeStyle = '#a53a2e';
  this.ctx.lineWidth = 3;
  this.ctx.setLineDash([15, 10]);
  this.ctx.beginPath();
  this.ctx.moveTo(endX, 0);
  this.ctx.lineTo(endX, this.canvas.height);
  this.ctx.stroke();
  this.ctx.setLineDash([]);
  
  // 绘制拖动手柄
  this.ctx.fillStyle = '#a53a2e';
  this.ctx.fillRect(endX - 5, this.canvas.height / 2 - 20, 10, 40);
}

// 鼠标事件支持拖动截止线(检测是否点击手柄):
const handleX = this.state.currentSegment.endX - this.state.camera.x;
if (Math.abs(this.mouseX - handleX) < 10 && 
    Math.abs(this.mouseY - this.canvas.height / 2) < 30) {
  this.draggingEndLine = true;
}
```

---

## 二、缺失核心功能 - AI 随机生成

### 2.1 生成逻辑概述
**需求**:
- 点击"生成"按钮 → AI 根据难度自动生成障碍物布局
- 生成后用户可手动微调

**生成规则**(参考 `src/spawn-config.js`):
1. **难度分级**: 根据 `state.currentSegment.difficulty` (easy/medium/hard)
2. **安全间距**: 障碍物之间保持最小距离(单跳距离 ~300px)
3. **节奏变化**: rest 休息段 → danger 危险段 → challenge 挑战段
4. **金币引导**: 在需要跳跃的地方放置金币弧线

### 2.2 实现步骤

#### Step 1: 新增"生成"按钮
```html
<!-- editor.html 工具栏中添加 -->
<button id="btnGenerate">🎲 随机生成</button>
```

#### Step 2: 生成器函数
```javascript
// 新建 editor/generator.js
export class LevelGenerator {
  constructor(state) {
    this.state = state;
  }

  // 生成关卡
  generate(difficulty = 'medium', length = 3600) {
    const obstacles = [];
    const collectibles = [];
    
    // 按区段生成
    let currentX = 500;  // 起始位置留空
    const groundY = 462;
    
    while (currentX < length - 500) {
      const segment = this.generateSegment(currentX, difficulty);
      obstacles.push(...segment.obstacles);
      collectibles.push(...segment.collectibles);
      currentX = segment.nextX;
    }
    
    this.state.currentSegment.obstacles = obstacles;
    this.state.currentSegment.collectibles = collectibles;
  }

  // 生成一个小段落
  generateSegment(startX, difficulty) {
    const type = this.randomChoice(['rest', 'jump', 'slide', 'mixed']);
    
    switch (type) {
      case 'rest':
        return this.generateRest(startX);
      case 'jump':
        return this.generateJump(startX, difficulty);
      case 'slide':
        return this.generateSlide(startX, difficulty);
      case 'mixed':
        return this.generateMixed(startX, difficulty);
    }
  }

  // 生成休息段(只有金币)
  generateRest(startX) {
    const coins = [];
    const spacing = 150;
    for (let i = 0; i < 3; i++) {
      coins.push({
        type: 'coin',
        x: startX + i * spacing,
        y: 400,
        r: 14
      });
    }
    return {
      obstacles: [],
      collectibles: coins,
      nextX: startX + 500
    };
  }

  // 生成跳跃段(地面尖刺 + 金币弧线)
  generateJump(startX, difficulty) {
    const obstacles = [];
    const collectibles = [];
    
    // 地面尖刺
    obstacles.push({
      kind: 'spike',
      x: startX + 200,
      y: 446,  // 地面 462 - 高度 16
      w: 32,
      h: 16,
      dmg: 12
    });
    
    // 金币弧线引导(抛物线)
    const coinCount = 5;
    for (let i = 0; i < coinCount; i++) {
      const t = i / (coinCount - 1);  // 0~1
      const x = startX + 100 + t * 300;
      const y = 380 - Math.sin(t * Math.PI) * 80;  // 抛物线
      collectibles.push({ type: 'coin', x, y, r: 14 });
    }
    
    return {
      obstacles,
      collectibles,
      nextX: startX + 600
    };
  }

  // 生成滑铲段(高处障碍 + 低矮金币)
  generateSlide(startX, difficulty) {
    const obstacles = [];
    const collectibles = [];
    
    // 垂板(从天花板垂下,只能滑过)
    obstacles.push({
      kind: 'beam',
      x: startX + 200,
      y: 0,
      w: 20,
      h: 150,
      dmg: 0
    });
    
    // 低矮金币(提示滑铲)
    for (let i = 0; i < 3; i++) {
      collectibles.push({
        type: 'coin',
        x: startX + 150 + i * 50,
        y: 440,  // 接近地面
        r: 14
      });
    }
    
    return {
      obstacles,
      collectibles,
      nextX: startX + 500
    };
  }

  // 生成混合段
  generateMixed(startX, difficulty) {
    // TODO: 复杂组合(跳 + 滑 + 飞镖)
    return this.generateJump(startX, difficulty);
  }

  // 随机选择
  randomChoice(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }
}
```

#### Step 3: 集成到编辑器
```javascript
// editor.js 中:
import { LevelGenerator } from './generator.js';

const generator = new LevelGenerator(EditorState);

document.getElementById('btnGenerate').addEventListener('click', () => {
  if (EditorState.currentSegment.obstacles.length > 0) {
    if (!confirm('当前关卡有内容,生成会覆盖,确定继续?')) return;
  }
  
  const difficulty = 'medium';  // 可以从 UI 选择
  const length = EditorState.currentSegment.endX || 3600;
  
  generator.generate(difficulty, length);
  canvasEditor.render();
  console.log('关卡生成完成');
});
```

---

## 三、关卡系统集成

### 3.1 关卡文件管理
**目标**: 将编辑器导出的 JSON 文件集成到游戏随机生成系统

**文件位置**:
```
ninja-run/
└── levels/           # 新建目录存放关卡 JSON
    ├── bamboo_01.json
    ├── bamboo_02.json
    ├── village_01.json
    └── ...
```

### 3.2 游戏集成步骤

#### Step 1: 关卡加载器
```javascript
// 新建 src/level-loader.js
export class LevelLoader {
  constructor() {
    this.segments = [];
    this.loaded = false;
  }

  // 加载所有关卡
  async loadAll() {
    const levelFiles = [
      '/levels/bamboo_01.json',
      '/levels/bamboo_02.json',
      // ... 更多关卡
    ];

    for (const file of levelFiles) {
      try {
        const response = await fetch(file);
        const data = await response.json();
        this.segments.push(data);
      } catch (err) {
        console.warn('加载关卡失败:', file, err);
      }
    }

    this.loaded = true;
    console.log(`已加载 ${this.segments.length} 个关卡段落`);
  }

  // 随机选择一个段落
  getRandomSegment() {
    if (this.segments.length === 0) return null;
    const index = Math.floor(Math.random() * this.segments.length);
    return this.segments[index];
  }
}
```

#### Step 2: 修改生成器逻辑
```javascript
// src/generator.js 中修改 spawnEvent():
import { levelLoader } from './level-loader.js';

function spawnEvent() {
  // 优先使用编辑器关卡
  if (levelLoader.loaded && Math.random() < 0.8) {
    const segment = levelLoader.getRandomSegment();
    if (segment) {
      spawnSegmentFromJSON(segment);
      return;
    }
  }
  
  // 否则使用程序生成(原逻辑)
  const t = pickEventTemplate();
  spawnFromTemplate(t);
}

// 从 JSON 段落生成障碍物
function spawnSegmentFromJSON(segment) {
  const baseX = G.scrollX + W + 200;
  
  // 生成障碍物
  for (const ob of segment.obstacles) {
    const worldX = baseX + ob.x;
    G.obstacles.push({
      kind: ob.kind,
      x: worldX,
      y: ob.y,
      w: ob.w,
      h: ob.h,
      dmg: ob.dmg,
      dodged: false
    });
  }
  
  // 生成收集物
  for (const c of segment.collectibles) {
    const worldX = baseX + c.x;
    G.collectibles.push({
      type: c.type,
      x: worldX,
      y: c.y,
      r: c.r,
      taken: false
    });
  }
  
  // 更新下次生成位置
  G.nextSpawnX = baseX + segment.endX;
}
```

#### Step 3: 初始化时加载
```javascript
// src/main.js 中:
import { LevelLoader } from './level-loader.js';

export const levelLoader = new LevelLoader();

// 游戏启动时加载关卡
levelLoader.loadAll().then(() => {
  console.log('关卡库加载完成');
  startGame();
});
```

---

## 四、关键修复优先级

### 🔥 立即修复(阻塞测试)
1. **对象无法移动** - `canvas-editor.js` 的 `getObjectAtPosition()` 调试
2. **Delete 键无反应** - 检查 `deleteSelectedObjects()` 是否被调用

### ⚠️ 高优先级(影响体验)
3. **撤销/重做** - 1小时内实现
4. **关卡命名** - 30分钟内实现
5. **截止线** - 1小时内实现

### 📋 中优先级(功能完整性)
6. **AI 随机生成** - 2-3小时(参考上方 Step 1-3)
7. **关卡加载器** - 1小时
8. **游戏集成** - 2小时测试

---

## 五、调试技巧

### 5.1 对象无法选中的调试
打开浏览器控制台(F12),在 `canvas-editor.js` 的 `getObjectAtPosition()` 开头添加:
```javascript
console.log('=== 检测点击 ===');
console.log('鼠标世界坐标:', worldX, worldY);
console.log('当前障碍物数量:', this.state.currentSegment.obstacles.length);

for (const ob of this.state.currentSegment.obstacles) {
  console.log('检查障碍物:', ob.kind, 
    `范围 x:[${ob.x}, ${ob.x + ob.w}] y:[${ob.y}, ${ob.y + ob.h}]`);
  
  const inX = worldX >= ob.x && worldX <= ob.x + ob.w;
  const inY = worldY >= ob.y && worldY <= ob.y + ob.h;
  console.log('  匹配结果: inX=' + inX + ', inY=' + inY);
}
```

点击画布后查看控制台输出,确认:
- 鼠标坐标是否正确
- 障碍物范围是否正确
- 匹配逻辑是否正确

### 5.2 常见问题排查

**问题**: 拖放后对象位置不对
- **检查**: `obstacle-panel.js` 中 `createObject()` 的 `y` 坐标计算
- **正确做法**: `y: worldY - spec.h` (从顶部开始)

**问题**: 网格吸附后对象偏移
- **检查**: 吸附逻辑是否在世界坐标系下进行
- **正确做法**: 先转世界坐标,吸附,再存储

---

## 六、文件清单

### 已完成文件
- ✅ `editor/editor.html` - 编辑器界面
- ✅ `editor/editor.js` - 主逻辑
- ✅ `editor/canvas-editor.js` - 画布渲染与交互
- ✅ `editor/obstacle-panel.js` - 障碍物拖放

### 待创建文件
- ❌ `editor/generator.js` - AI 关卡生成器
- ❌ `src/level-loader.js` - 关卡加载器
- ❌ `levels/*.json` - 关卡数据文件(从编辑器导出)

---

## 七、测试检查清单

### 基础功能测试
- [ ] 打开 http://localhost:5173/editor/editor.html
- [ ] 从左侧拖动尖刺到画布
- [ ] **点击尖刺,能否选中?(边框变红)**
- [ ] **拖动尖刺,能否移动?**
- [ ] **按 Delete,能否删除?**
- [ ] 底部属性面板能否显示坐标?
- [ ] 修改坐标输入框,对象是否移动?

### 高级功能测试
- [ ] 拖动多个对象,Shift+点击多选
- [ ] 多选后按 Shift+H,是否水平对齐?
- [ ] 多选后按 Shift+G,是否贴地?
- [ ] 点击"💾 保存",是否下载 JSON?
- [ ] 点击"📂 加载",导入 JSON 是否正确?
- [ ] 点击"⊞ 网格",网格是否显示/隐藏?

---

## 八、Codex 接手指南

### 立即行动步骤
1. **第一步**: 修复对象无法移动的 Bug(见第一章 1.1)
   - 打开 `editor/canvas-editor.js`
   - 在 `getObjectAtPosition()` 添加调试日志
   - 在浏览器测试,查看控制台输出
   - 修复坐标检测逻辑

2. **第二步**: 实现撤销/重做(见第一章 1.2)
   - 在 `EditorState` 添加 `history` 字段
   - 在 `editor.js` 添加 `saveSnapshot()` / `undo()` / `redo()`
   - 监听 Ctrl+Z / Ctrl+Y 键盘事件

3. **第三步**: 添加关卡命名(见第一章 1.3)
   - 在工具栏中间添加输入框
   - 保存时使用名称作为文件名

4. **第四步**: 实现截止线(见第一章 1.4)
   - 在 `canvas-editor.js` 添加 `drawEndLine()`
   - 支持拖动调整

5. **第五步**: 实现 AI 生成器(见第二章)
   - 创建 `editor/generator.js`
   - 实现 `generate()` 方法
   - 添加"生成"按钮

### 关键注意事项
⚠️ **不要删除游戏原有的螺旋丸和能量系统** - 这是误操作,已经恢复
⚠️ **坐标系**: 画布使用屏幕坐标,对象存储使用世界坐标(需转换)
⚠️ **障碍物 y**: 存储的是顶部坐标,不是底部

### 代码风格
- 所有注释用中文
- 函数命名用驼峰
- 常量用大写下划线
- 每个函数前写注释说明功能

---

## 九、联系与反馈

如遇到问题或需要更多细节,请检查:
1. `LEVEL_EDITOR_SPEC.md` - 完整规格文档
2. 浏览器控制台 - 查看报错和调试日志
3. `src/spawn-config.js` - 游戏原有的生成逻辑(可参考)

祝开发顺利! 🚀