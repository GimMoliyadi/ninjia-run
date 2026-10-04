// 画布编辑器 - 负责渲染和交互
export class CanvasEditor {
  constructor(canvas, state) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.state = state;

    // 画布尺寸
    this.canvasHeight = 540;  // 游戏画面高度
    this.visibleWidth = 0;    // 可见宽度(由容器决定)

    // 地面线
    this.groundY = 462;

    // 拖动状态
    this.isDragging = false;
    this.dragStartX = 0;
    this.dragStartY = 0;
    this.dragObject = null;
    this.dragStartPositions = [];
    this.draggingEndLine = false;

    // 鼠标状态
    this.mouseX = 0;
    this.mouseY = 0;
    this.worldMouseX = 0;  // 鼠标在世界坐标系中的位置

    this.setupCanvas();
    this.setupEventListeners();
    this.render();

    // 监听窗口大小变化
    window.addEventListener('resize', () => {
      this.setupCanvas();
      this.render();
    });

    // 监听重新加载事件
    window.addEventListener('editorReload', () => {
      this.updatePropertiesPanel();
      this.render();
    });
  }

  // 设置画布尺寸
  setupCanvas() {
    const container = this.canvas.parentElement;
    this.visibleWidth = container.clientWidth;
    this.canvas.width = this.visibleWidth;
    this.canvas.height = this.canvasHeight;
  }

  // 设置事件监听
  setupEventListeners() {
    // 鼠标移动
    this.canvas.addEventListener('mousemove', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      this.mouseX = e.clientX - rect.left;
      this.mouseY = e.clientY - rect.top;
      this.worldMouseX = this.mouseX + this.state.camera.x;

      // 更新信息显示
      document.getElementById('infoMouse').textContent =
        `${Math.round(this.worldMouseX)}, ${Math.round(this.mouseY)}`;

      // 拖动截止线
      if (this.draggingEndLine) {
        let endX = this.worldMouseX;
        if (this.state.gridEnabled) {
          endX = Math.round(endX / this.state.gridSize) * this.state.gridSize;
        }
        this.state.currentSegment.endX = Math.max(0, endX);
        this.render();
      }

      // 拖动画布
      if (this.isDragging && !this.dragObject) {
        const deltaX = e.clientX - this.dragStartX;
        this.state.camera.x = Math.max(0, this.dragStartCameraX - deltaX);
        this.render();
      }

      // 拖动对象
      if (this.isDragging && this.dragObject) {
        const deltaX = this.worldMouseX - this.dragStartWorldX;
        const deltaY = this.mouseY - this.dragStartWorldY;
        for (const { obj, x, y } of this.dragStartPositions) {
          obj.x = x + deltaX;
          obj.y = y + deltaY;
          if (this.state.gridEnabled) {
            obj.x = Math.round(obj.x / this.state.gridSize) * this.state.gridSize;
            obj.y = Math.round(obj.y / this.state.gridSize) * this.state.gridSize;
          }
        }
        this.updatePropertiesPanel();
        this.render();
      }
    });

    // 鼠标按下
    this.canvas.addEventListener('mousedown', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      this.mouseX = e.clientX - rect.left;
      this.mouseY = e.clientY - rect.top;
      this.worldMouseX = this.mouseX + this.state.camera.x;

      const endX = (this.state.currentSegment.endX ?? this.state.currentSegment.length) - this.state.camera.x;
      if (this.isEndLineHandleHit(this.mouseX, this.mouseY, endX)) {
        this.state.saveHistory();
        this.draggingEndLine = true;
        this.canvas.style.cursor = 'ew-resize';
        return;
      }

      // 检查是否点击了对象
      const clickedObject = this.getObjectAtPosition(this.worldMouseX, this.mouseY);

      if (clickedObject) {
        // 选中对象
        if (e.shiftKey) {
          // Shift 多选
          const index = this.state.selectedObjects.indexOf(clickedObject);
          if (index === -1) {
            this.state.selectedObjects.push(clickedObject);
          } else {
            this.state.selectedObjects.splice(index, 1);
          }
        } else if (!this.state.selectedObjects.includes(clickedObject)) {
          this.state.selectedObjects = [clickedObject];
        }
        if (!e.shiftKey) {
          this.state.saveHistory();
          this.isDragging = true;
          this.dragObject = clickedObject;
          this.dragStartX = e.clientX;
          this.dragStartY = e.clientY;
          this.dragStartWorldX = this.worldMouseX;
          this.dragStartWorldY = this.mouseY;
          this.dragStartPositions = this.state.selectedObjects.map(obj => ({
            obj,
            x: obj.x,
            y: obj.y
          }));
        }
        this.updatePropertiesPanel();
      } else {
        // 开始拖动画布
        this.isDragging = true;
        this.dragStartX = e.clientX;
        this.dragStartY = e.clientY;
        this.dragStartCameraX = this.state.camera.x;
        this.canvas.style.cursor = 'grabbing';
      }

      this.render();
    });

    // 鼠标松开
    this.canvas.addEventListener('mouseup', () => {
      if (this.isDragging && this.dragObject) {
        this.updatePropertiesPanel();
      }
      this.isDragging = false;
      this.dragObject = null;
      this.dragStartPositions = [];
      this.draggingEndLine = false;
      this.canvas.style.cursor = 'move';
    });

    // 鼠标滚轮 - 横向滚动
    this.canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.state.camera.x = Math.max(0, this.state.camera.x + e.deltaY);
      this.render();
    });

    // 键盘事件
    window.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) {
          this.state.redo();
        } else {
          this.state.undo();
        }
        return;
      }

      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') {
        e.preventDefault();
        this.state.redo();
        return;
      }

      // Delete 键删除选中对象
      if (e.key === 'Delete' && this.state.selectedObjects.length > 0) {
        e.preventDefault();
        this.deleteSelectedObjects();
      }

      // Shift+H 水平对齐
      if (e.shiftKey && e.key === 'H') {
        this.alignHorizontal();
      }

      // Shift+V 竖直对齐
      if (e.shiftKey && e.key === 'V') {
        this.alignVertical();
      }

      // Shift+G 贴地对齐
      if (e.shiftKey && e.key === 'G') {
        this.alignGround();
      }
    });
  }

  // 渲染画布
  render() {
    const ctx = this.ctx;
    const camera = this.state.camera;

    // 清空画布
    ctx.fillStyle = '#f2ecd9';  // 宣纸底色
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // 绘制网格
    if (this.state.gridEnabled) {
      this.drawGrid();
    }

    // 绘制地面线
    ctx.strokeStyle = '#2b2b31';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, this.groundY);
    ctx.lineTo(this.canvas.width, this.groundY);
    ctx.stroke();

    // 绘制段落边界提示
    this.drawSegmentBoundary();

    // 绘制障碍物
    this.drawObstacles();

    // 绘制收集物
    this.drawCollectibles();

    // 绘制人物工具
    if (this.state.playerTool.enabled) {
      this.drawPlayerTool();
    }

    // 绘制选中框
    this.drawSelection();
  }

  // 绘制网格
  drawGrid() {
    const ctx = this.ctx;
    const camera = this.state.camera;
    const gridSize = this.state.gridSize;

    ctx.strokeStyle = 'rgba(43, 43, 49, 0.1)';
    ctx.lineWidth = 1;

    // 竖线
    const startX = Math.floor(camera.x / gridSize) * gridSize;
    for (let x = startX; x < camera.x + this.canvas.width; x += gridSize) {
      const screenX = x - camera.x;
      ctx.beginPath();
      ctx.moveTo(screenX, 0);
      ctx.lineTo(screenX, this.canvas.height);
      ctx.stroke();
    }

    // 横线
    for (let y = 0; y < this.canvas.height; y += gridSize) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(this.canvas.width, y);
      ctx.stroke();
    }
  }

  // 绘制段落边界提示
  drawSegmentBoundary() {
    const ctx = this.ctx;
    const camera = this.state.camera;
    const endWorldX = this.state.currentSegment.endX ?? this.state.currentSegment.length;

    // 起点线
    if (camera.x < 100) {
      ctx.strokeStyle = '#4a8b9e';
      ctx.lineWidth = 3;
      ctx.setLineDash([10, 5]);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, this.canvas.height);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = '#4a8b9e';
      ctx.font = '12px Arial';
      ctx.fillText('起点', 5, 20);
    }

    // 终点线
    const endX = endWorldX - camera.x;
    if (endX > 0 && endX < this.canvas.width) {
      ctx.strokeStyle = '#a53a2e';
      ctx.lineWidth = 3;
      ctx.setLineDash([10, 5]);
      ctx.beginPath();
      ctx.moveTo(endX, 0);
      ctx.lineTo(endX, this.canvas.height);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = '#a53a2e';
      ctx.font = '12px Arial';
      ctx.fillText('截止线', endX + 5, 20);
      ctx.fillRect(endX - 5, this.canvas.height / 2 - 20, 10, 40);
    }
  }

  // 绘制障碍物
  drawObstacles() {
    const ctx = this.ctx;
    const camera = this.state.camera;

    for (const ob of this.state.currentSegment.obstacles) {
      const screenX = ob.x - camera.x;

      // 只绘制可见范围内的对象
      if (screenX + ob.w < 0 || screenX > this.canvas.width) continue;

      // 判断是否选中
      const isSelected = this.state.selectedObjects.includes(ob);

      // 绘制碰撞盒
      ctx.fillStyle = isSelected ? 'rgba(165, 58, 46, 0.3)' : 'rgba(43, 43, 49, 0.2)';
      ctx.fillRect(screenX, ob.y, ob.w, ob.h);

      ctx.strokeStyle = isSelected ? '#a53a2e' : '#2b2b31';
      ctx.lineWidth = isSelected ? 2 : 1;
      ctx.strokeRect(screenX, ob.y, ob.w, ob.h);

      // 绘制类型标签
      ctx.fillStyle = '#2b2b31';
      ctx.font = '10px Arial';
      ctx.fillText(ob.kind, screenX + 2, ob.y + 12);
    }
  }

  // 绘制收集物
  drawCollectibles() {
    const ctx = this.ctx;
    const camera = this.state.camera;

    for (const c of this.state.currentSegment.collectibles) {
      const screenX = c.x - camera.x;

      if (screenX + c.r < 0 || screenX - c.r > this.canvas.width) continue;

      const isSelected = this.state.selectedObjects.includes(c);

      // 绘制圆形
      ctx.beginPath();
      ctx.arc(screenX, c.y, c.r, 0, Math.PI * 2);
      ctx.fillStyle = isSelected ? 'rgba(216, 164, 65, 0.5)' : 'rgba(216, 164, 65, 0.3)';
      ctx.fill();
      ctx.strokeStyle = isSelected ? '#d8a441' : '#d8a441';
      ctx.lineWidth = isSelected ? 2 : 1;
      ctx.stroke();

      // 类型标签
      ctx.fillStyle = '#2b2b31';
      ctx.font = '10px Arial';
      ctx.fillText(c.type, screenX - 10, c.y + 4);
    }
  }

  // 绘制人物工具
  drawPlayerTool() {
    const ctx = this.ctx;
    const camera = this.state.camera;
    const player = this.state.playerTool;

    const screenX = player.x - camera.x;

    // 碰撞盒
    const h = player.pose === 'slide' ? 32 : 66;
    const w = 46;
    const y = player.y - h;

    ctx.strokeStyle = 'rgba(165, 58, 46, 0.6)';
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 3]);
    ctx.strokeRect(screenX - w / 2, y, w, h);
    ctx.setLineDash([]);

    // 中心点
    ctx.fillStyle = '#a53a2e';
    ctx.beginPath();
    ctx.arc(screenX, player.y, 3, 0, Math.PI * 2);
    ctx.fill();

    // 标签
    ctx.fillStyle = '#a53a2e';
    ctx.font = 'bold 12px Arial';
    ctx.fillText('🥷', screenX - 8, y - 5);
  }

  // 绘制选中框
  drawSelection() {
    // 已在 drawObstacles/drawCollectibles 中处理
  }

  // 获取指定位置的对象
  getObjectAtPosition(worldX, worldY) {
    // 先检查障碍物
    for (let i = this.state.currentSegment.obstacles.length - 1; i >= 0; i--) {
      const ob = this.state.currentSegment.obstacles[i];
      if (worldX >= ob.x && worldX <= ob.x + ob.w &&
          worldY >= ob.y && worldY <= ob.y + ob.h) {
        return ob;
      }
    }

    // 再检查收集物
    for (let i = this.state.currentSegment.collectibles.length - 1; i >= 0; i--) {
      const c = this.state.currentSegment.collectibles[i];
      const dx = worldX - c.x;
      const dy = worldY - c.y;
      if (dx * dx + dy * dy <= c.r * c.r) {
        return c;
      }
    }

    return null;
  }

  // 检查是否命中截止线中央拖动手柄
  isEndLineHandleHit(mouseX, mouseY, endX) {
    return Math.abs(mouseX - endX) <= 10 &&
      Math.abs(mouseY - this.canvas.height / 2) <= 30;
  }

  // 删除选中对象
  deleteSelectedObjects() {
    this.state.saveHistory();
    for (const obj of this.state.selectedObjects) {
      const obsIndex = this.state.currentSegment.obstacles.indexOf(obj);
      if (obsIndex !== -1) {
        this.state.currentSegment.obstacles.splice(obsIndex, 1);
      }
      const colIndex = this.state.currentSegment.collectibles.indexOf(obj);
      if (colIndex !== -1) {
        this.state.currentSegment.collectibles.splice(colIndex, 1);
      }
    }
    this.state.selectedObjects = [];
    this.updatePropertiesPanel();
    this.render();
  }

  // 水平对齐
  alignHorizontal() {
    if (this.state.selectedObjects.length < 2) return;
    this.state.saveHistory();
    const refY = this.state.selectedObjects[0].y;
    for (const obj of this.state.selectedObjects) {
      obj.y = refY;
    }
    this.render();
  }

  // 竖直对齐
  alignVertical() {
    if (this.state.selectedObjects.length < 2) return;
    this.state.saveHistory();
    const refX = this.state.selectedObjects[0].x;
    for (const obj of this.state.selectedObjects) {
      obj.x = refX;
    }
    this.render();
  }

  // 贴地对齐
  alignGround() {
    if (this.state.selectedObjects.length === 0) return;
    this.state.saveHistory();
    for (const obj of this.state.selectedObjects) {
      if (obj.h !== undefined) {
        // 障碍物:底部贴地
        obj.y = this.groundY - obj.h;
      } else {
        // 收集物:中心贴地
        obj.y = this.groundY;
      }
    }
    this.render();
  }

  // 更新属性面板
  updatePropertiesPanel() {
    const panel = document.getElementById('propertiesContent');

    if (this.state.selectedObjects.length === 0) {
      panel.innerHTML = '<p style="color: #666; font-size: 12px;">未选中任何对象</p>';
      return;
    }

    if (this.state.selectedObjects.length === 1) {
      const obj = this.state.selectedObjects[0];
      panel.innerHTML = `
        <div class="property-row">
          <span class="property-label">类型:</span>
          <span style="color: #d8a441;">${obj.kind || obj.type}</span>
        </div>
        <div class="property-row">
          <span class="property-label">X 坐标:</span>
          <input class="property-input" type="number" value="${Math.round(obj.x)}"
                 onchange="window.EditorActions.setSelectedPosition('x', this.value);">
        </div>
        <div class="property-row">
          <span class="property-label">Y 坐标:</span>
          <input class="property-input" type="number" value="${Math.round(obj.y)}"
                 onchange="window.EditorActions.setSelectedPosition('y', this.value);">
        </div>
      `;
    } else {
      panel.innerHTML = `<p style="color: #d8a441;">已选中 ${this.state.selectedObjects.length} 个对象</p>`;
    }
  }
}
