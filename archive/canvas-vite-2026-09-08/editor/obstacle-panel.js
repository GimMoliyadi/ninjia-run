// 障碍物面板 - 处理拖拽放置
export class ObstaclePanel {
  constructor(state, canvasEditor) {
    this.state = state;
    this.canvasEditor = canvasEditor;

    this.setupDragAndDrop();
  }

  // 设置拖放事件
  setupDragAndDrop() {
    const items = document.querySelectorAll('.obstacle-item');

    items.forEach(item => {
      // 开始拖动
      item.addEventListener('dragstart', (e) => {
        const kind = item.dataset.kind;
        e.dataTransfer.setData('obstacleKind', kind);
        item.style.opacity = '0.5';
      });

      // 拖动结束
      item.addEventListener('dragend', (e) => {
        item.style.opacity = '1';
      });

      // 使元素可拖动
      item.setAttribute('draggable', 'true');
    });

    // 画布接收拖放
    const canvas = this.canvasEditor.canvas;

    canvas.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });

    canvas.addEventListener('drop', (e) => {
      e.preventDefault();
      const kind = e.dataTransfer.getData('obstacleKind');
      if (!kind) return;

      // 计算放置位置
      const rect = canvas.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const mouseY = e.clientY - rect.top;
      const worldX = mouseX + this.state.camera.x;

      // 创建对象
      this.createObject(kind, worldX, mouseY);
    });
  }

  // 创建对象
  createObject(kind, worldX, worldY) {
    let obj = null;

    // 障碍物尺寸定义(从游戏常量复制)
    const obstacleSpecs = {
      spike: { w: 32, h: 16 },
      pillar: { w: 36, h: 90 },
      beam: { w: 20, h: 150 },
      rock: { w: 40, h: 40 },
      boulder: { w: 40, h: 40 },
      ninja: { w: 26, h: 58 },
      dart_wave: { w: 34, h: 36 }  // 单枚飞镖尺寸
    };

    // 收集物尺寸
    const collectibleSpecs = {
      coin: { r: 14 },
      scroll: { r: 15 },
      shield: { r: 16 }
    };

    // 网格吸附
    if (this.state.gridEnabled) {
      worldX = Math.round(worldX / this.state.gridSize) * this.state.gridSize;
      worldY = Math.round(worldY / this.state.gridSize) * this.state.gridSize;
    }

    // 判断是障碍物还是收集物
    if (obstacleSpecs[kind]) {
      // 障碍物
      const spec = obstacleSpecs[kind];

      if (kind === 'dart_wave') {
        // 飞镖组需要特殊处理
        this.createDartWave(worldX, worldY);
        return;
      }

      this.state.saveHistory();
      obj = {
        kind,
        x: worldX,
        y: worldY - spec.h,  // 从顶部计算
        w: spec.w,
        h: spec.h,
        dmg: this.getDefaultDamage(kind)
      };

      this.state.currentSegment.obstacles.push(obj);

    } else if (collectibleSpecs[kind]) {
      // 收集物
      const spec = collectibleSpecs[kind];

      this.state.saveHistory();
      obj = {
        type: kind,
        x: worldX,
        y: worldY,
        r: spec.r
      };

      this.state.currentSegment.collectibles.push(obj);
    }

    // 自动选中新创建的对象
    if (obj) {
      this.state.selectedObjects = [obj];
      this.canvasEditor.updatePropertiesPanel();
    }

    this.canvasEditor.render();
  }

  // 创建飞镖组(进入特殊编辑模式)
  createDartWave(worldX, worldY) {
    alert('飞镖组编辑模式:\n' +
          '1. 点击画布放置每枚飞镖\n' +
          '2. 完成后按 Enter 确认\n' +
          '3. 按 Escape 取消\n\n' +
          '此功能将在 Phase 4 实现');

    // TODO: 进入飞镖编辑模式(Phase 4)
  }

  // 获取默认伤害值
  getDefaultDamage(kind) {
    const damageMap = {
      spike: 12,
      pillar: 20,
      beam: 0,  // 垂板是推挤墙,不扣血
      rock: 12,
      boulder: 12,
      ninja: 30
    };
    return damageMap[kind] || 0;
  }
}
