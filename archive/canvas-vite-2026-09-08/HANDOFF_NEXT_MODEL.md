# Ninja Run 创意工坊接力交接

## 用户最终需求

实现深坑控制与标准快捷键方案，并让创意工坊易于设置关卡：

- `Ctrl/Cmd+C` 复制选中对象，`Ctrl/Cmd+V` 在视口中心附近粘贴并错开，`Ctrl/Cmd+X` 剪切。
- `Ctrl/Cmd+Z` / `Ctrl/Cmd+Y` 撤销、重做；`Delete` / `Backspace` 删除。
- 剪贴板只保存在工坊内部，不使用系统剪贴板。
- 单选、多选、深坑、金币路径均可复制；深坑复制要保留宽度和固定宽度状态。
- 多选支持 Shift 点选、拖拽框选、批量移动/删除/复制/对齐。
- 删除左右键移动忍者和左右按钮。地图用鼠标拖拽浏览。
- 试玩时忍者自动前进，速度递增，仍可正常跳跃、下滑。
- 深坑独立设置：起点、宽度、终点、固定宽度、短坑/安全一段跳/标准一段跳/二段跳预设。
- 深坑宽度限制 80~600px；锁定后拖动只改变位置；输入宽度仍可主动修改。
- 深坑不能越界、重叠，地形始终排序连续。
- 深坑显示实际宽度、单跳/二段跳落点和可玩性提示（尚未完成）。

## 已完成改动

### `src/state.js`

`G.workshop` 已增加/保留：

```js
selection: [], clipboard: [], boxSelect: null, pan: null
```

旧字段 `moveLeft`、`moveRight`、`selected`、`dragging` 仍部分保留，需继续清理兼容。

### `index.html`

- 已嵌入创意工坊。
- 已删除左右移动按钮。
- 工坊工具已有金币直线、跳跃拱形、金币间距、网格、吸附、轨迹录制。
- 已加入 `#pit-settings`：
  - `#pit-start`
  - `#pit-width`
  - `#pit-end`
  - `#pit-lock-width`
  - `[data-pit-preset="short|safe|jump|double"]`

### `src/workshop.js`

已有：

- `checkpoint()` / undo、redo 栈。
- `allObjects()`、`setSelection()`、`selectedObjects()`、`removeObject()`。
- 深坑对象格式 `{ type:'pit', start, end, widthLocked:false }`。
- `rebuildTerrain()` 保证深坑排序、平地分段连续。
- `pitFits()` 防止深坑越界和重叠。
- `generateCoinLine()`、`generateCoinArc()`、轨迹录制金币。
- `updateWorkshop()` 中自动试玩使用 `updateSpeed(dt, !ws.testing)`：编辑模式不自动前进，试玩模式自动前进且速度递增。
- `handleWorkshopShortcut()` 已支持 C/X/V，并已补 Z/Y：
  - 内部结构化克隆对象。
  - 粘贴到视口中心附近并有 24px 偏移。
  - 深坑粘贴前调用 `pitFits()`。
- `moveWorkshopObject()` 已加入 `widthLocked` 逻辑：锁定深坑移动时保持原宽度。
- 选择命中后使用 `setSelection([ob])`；Shift 点选会追加/取消选择；多个选中对象批量拖动；空白区域仍用于鼠标拖拽地图平移。
- 选中对象 overlay 已改为绘制全部选中对象。
- 深坑面板已有 `updatePitFromPanel()` 和 `setPitPreset()`，并绑定起点、宽度、锁定、预设事件。
- 随机生成深坑已保留 `widthLocked` 字段。

### `src/input.js`

- 已导入 `handleWorkshopShortcut`。
- 工坊键盘处理最前面调用 `if (handleWorkshopShortcut(e)) return;`。
- 工坊内仍支持 Delete/Backspace、R、跳跃/下滑；左右键逻辑已移除。

### 验证

`rtk npm run build` 最近一次通过（Vite build 成功）。

## 需要下一个模型继续完成

1. **检查当前文件实际状态并修正残留**
   - 上一轮最后一次 apply_patch 可能被中断，确认 `src/workshop.js` 是否已删除所有 `moveLeft/moveRight` 控制逻辑。
   - `setupWorkshopControls()` 中不应再绑定 `[data-move]`，左右按钮已不存在。
   - `focusin` 不应再清理左右键字段。
   - `src/physics.js` 可能仍引用 `G.workshop.moveLeft/moveRight` 的 wallPush；编辑器中应保持 false 或移除工坊依赖，不能恢复左右控制。

2. **多选框选尚未真正实现**
   - 当前 Shift 点选和批量拖动已加入，但空白拖拽仍直接 pan。
   - 需要设计不冲突的交互：例如在选择工具下空白拖动框选，使用中键/空格拖拽地图；或 Alt/空格作为平移修饰键。
   - `ws.boxSelect` 需保存起点/当前点，pointermove 更新，pointerup 根据 `objectBounds()` 选中相交对象，并在 overlay 绘制选择框。

3. **深坑面板和移动边界复核**
   - `updatePitFromPanel()` 当前应限制宽度 80~600，并调用 `pitFits()`；确认修改起点时 clamp 后再检查。
   - `setPitPreset()` 当前建议值：`short=160`、`safe=200`、`jump=Math.round(C.JUMP_DIST_BASE*0.9)`、`double=Math.round(C.JUMP2_DIST_BASE*0.9)`。
   - 确认 `moveWorkshopObject()` 的锁定宽度逻辑不会因默认参数丢失宽度。
   - 深坑 overlay 尚未显示宽度、预计单跳落点、二段跳落点及颜色可玩性提示，需要补画布标注。
   - `src/workshop.css` 尚未专门美化 `#pit-settings`，需确保移动端不溢出。

4. **撤销/重做语义复核**
   - 批量拖动应只调用一次 `checkpoint()`（当前 pointermove 使用 `drag.saved`）。
   - 批量删除、复制粘贴、金币路径生成、深坑设置修改都应是一次撤销操作。
   - `restore()` 应清空 selection/dragging，并在必要时重建地形。

5. **测试更新**

旧测试中依赖左右键的用例需要改写，因为左右控制已按用户要求删除。应补充：

- 自动试玩 `scrollX` 增长、速度递增、跳跃和下滑。
- `generateCoinLine()` 等间距。
- `generateCoinArc()` 符合跳跃公式。
- 单对象/多对象/深坑/金币路径复制粘贴剪切。
- 深坑复制保留 `widthLocked`。
- 深坑宽度输入、四个预设、锁定后拖动宽度不变。
- 深坑越界/重叠拒绝。
- `handleWorkshopShortcut()` 的 C/V/X/Z/Y 行为。

建议命令：

```powershell
rtk npm run build
rtk proxy node --test tests/workshop.test.js
```

6. **浏览器验证**

启动：

```powershell
rtk npm run dev -- --host 127.0.0.1
```

检查首页、进入工坊、随机关卡可见、深坑设置显示、预设修改、锁定拖动、Ctrl+C/V、试玩自动前进、鼠标拖拽地图，以及移动端布局。

## 约束

- 所有 shell 命令以 `rtk` 开头。
- 文件编辑使用 `apply_patch`。
- 不创建 commit、不 push。
- 不修改系统剪贴板。
- 不删除旧 `editor/`。
- 最终用中文简洁汇报。
