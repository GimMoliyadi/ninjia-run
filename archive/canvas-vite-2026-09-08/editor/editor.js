// 关卡编辑器主逻辑
import { CanvasEditor } from './canvas-editor.js';
import { ObstaclePanel } from './obstacle-panel.js';
import { LevelGenerator } from './generator.js';

// 编辑器状态
const EditorState = {
  mode: 'select',  // select | place | dart_edit
  selectedObjects: [],
  currentSegment: {
    id: 'segment_001',
    name: '新建关卡段落',
    length: 3600,  // 默认段落长度(像素)
    endX: 3600,
    obstacles: [],
    collectibles: []
  },
  camera: {
    x: 0,           // 画布滚动偏移
    scrollSpeed: 20
  },
  gridEnabled: true,
  gridSize: 50,
  playerTool: {
    enabled: false,
    x: 270,
    y: 462,
    pose: 'stand'  // stand | jump | slide
  },
  placingObject: null,  // 正在放置的对象类型
  history: {
    past: [],
    future: []
  }
};

// 保存当前关卡快照，供撤销和重做使用
EditorState.saveHistory = () => {
  EditorState.history.past.push(structuredClone(EditorState.currentSegment));
  EditorState.history.future = [];
  if (EditorState.history.past.length > 50) {
    EditorState.history.past.shift();
  }
};

// 初始化编辑器
window.addEventListener('DOMContentLoaded', () => {
  console.log('关卡编辑器启动...');

  // 初始化画布编辑器
  const canvas = document.getElementById('editorCanvas');
  const canvasEditor = new CanvasEditor(canvas, EditorState);
  const generator = new LevelGenerator(EditorState);

  // 初始化障碍物面板
  const obstaclePanel = new ObstaclePanel(EditorState, canvasEditor);

  // 顶部工具栏按钮事件
  setupToolbar(canvasEditor, generator);

  window.EditorActions = {
    setSelectedPosition(axis, value) {
      const coordinate = Number.parseFloat(value);
      const selected = EditorState.selectedObjects[0];
      if (!Number.isFinite(coordinate) || !selected) return;
      EditorState.saveHistory();
      selected[axis] = coordinate;
      canvasEditor.render();
    }
  };

  // 更新信息显示
  setInterval(() => updateInfoDisplay(), 100);
});

// 设置工具栏按钮事件
function setupToolbar(canvasEditor, generator) {
  const segmentName = document.getElementById('segmentName');
  segmentName.addEventListener('change', () => {
    if (segmentName.value === EditorState.currentSegment.name) return;
    EditorState.saveHistory();
    EditorState.currentSegment.name = segmentName.value.trim() || '新建关卡段落';
    segmentName.value = EditorState.currentSegment.name;
  });

  document.getElementById('btnUndo').addEventListener('click', () => EditorState.undo());
  document.getElementById('btnRedo').addEventListener('click', () => EditorState.redo());

  document.getElementById('btnGenerate').addEventListener('click', () => {
    const segment = EditorState.currentSegment;
    if ((segment.obstacles.length || segment.collectibles.length) &&
        !confirm('当前关卡有内容，生成会覆盖，确定继续？')) return;
    EditorState.saveHistory();
    generator.generate(segment.difficulty || 'medium', segment.endX ?? segment.length);
    EditorState.selectedObjects = [];
    canvasEditor.updatePropertiesPanel();
    canvasEditor.render();
  });

  // 保存按钮
  document.getElementById('btnSave').addEventListener('click', () => {
    saveSegment();
  });

  // 加载按钮
  document.getElementById('btnLoad').addEventListener('click', () => {
    loadSegment();
  });

  // 测试按钮
  document.getElementById('btnTest').addEventListener('click', () => {
    testSegment();
  });

  // 清空按钮
  document.getElementById('btnClear').addEventListener('click', () => {
    if (confirm('确定清空当前关卡?')) {
      EditorState.saveHistory();
      EditorState.currentSegment.obstacles = [];
      EditorState.currentSegment.collectibles = [];
      EditorState.selectedObjects = [];
      canvasEditor.render();
    }
  });

  // 网格开关
  document.getElementById('btnGrid').addEventListener('click', () => {
    EditorState.gridEnabled = !EditorState.gridEnabled;
    const btn = document.getElementById('btnGrid');
    btn.style.background = EditorState.gridEnabled ? '#4a8b9e' : '#3a3a3a';
    canvasEditor.render();
  });

  // 人物工具开关
  document.getElementById('btnPlayerTool').addEventListener('click', () => {
    EditorState.playerTool.enabled = !EditorState.playerTool.enabled;
    const btn = document.getElementById('btnPlayerTool');
    btn.style.background = EditorState.playerTool.enabled ? '#4a8b9e' : '#3a3a3a';
    canvasEditor.render();
  });
}

// 保存关卡段落为 JSON
function saveSegment() {
  const segmentName = document.getElementById('segmentName');
  EditorState.currentSegment.name = segmentName.value.trim() || '新建关卡段落';
  const json = JSON.stringify(EditorState.currentSegment, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  const safeName = EditorState.currentSegment.name.replace(/[\\/:*?"<>|]+/g, '_');
  a.download = `${safeName}_${EditorState.currentSegment.id}.json`;
  a.click();
  URL.revokeObjectURL(url);
  console.log('关卡已保存:', EditorState.currentSegment.id);
}

// 加载关卡段落 JSON
function loadSegment() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json';
  input.onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const data = JSON.parse(event.target.result);
        // 校验必需字段
        if (!data.id || !data.obstacles || !data.collectibles) {
          throw new Error('JSON 格式错误:缺少必需字段');
        }
        EditorState.currentSegment = data;
        EditorState.currentSegment.endX ??= data.length;
        EditorState.selectedObjects = [];
        EditorState.history.past = [];
        EditorState.history.future = [];
        document.getElementById('segmentName').value = data.name || data.id;
        console.log('关卡已加载:', data.id);
        // 触发重新渲染(需要 canvasEditor 实例,暂时通过全局事件)
        window.dispatchEvent(new Event('editorReload'));
      } catch (err) {
        alert('加载失败:' + err.message);
      }
    };
    reader.readAsText(file);
  };
  input.click();
}

// 测试当前关卡段落
function testSegment() {
  alert('测试功能开发中...\n将切换到游戏模式运行当前关卡段落');
  // TODO: 集成到游戏主循环
}

// 更新信息显示
function updateInfoDisplay() {
  document.getElementById('infoScroll').textContent = Math.round(EditorState.camera.x);
  document.getElementById('infoSelected').textContent = EditorState.selectedObjects.length;
}

// 撤销上一步编辑
EditorState.undo = () => {
  const previous = EditorState.history.past.pop();
  if (!previous) return;
  EditorState.history.future.push(structuredClone(EditorState.currentSegment));
  EditorState.currentSegment = previous;
  EditorState.selectedObjects = [];
  document.getElementById('segmentName').value = previous.name || previous.id;
  window.dispatchEvent(new Event('editorReload'));
};

// 重做被撤销的编辑
EditorState.redo = () => {
  const next = EditorState.history.future.pop();
  if (!next) return;
  EditorState.history.past.push(structuredClone(EditorState.currentSegment));
  EditorState.currentSegment = next;
  EditorState.selectedObjects = [];
  document.getElementById('segmentName').value = next.name || next.id;
  window.dispatchEvent(new Event('editorReload'));
};

// 导出全局访问(用于其他模块)
window.EditorState = EditorState;
