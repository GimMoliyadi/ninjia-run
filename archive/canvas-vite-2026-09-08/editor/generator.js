// 关卡随机生成器 - 生成可继续手动调整的基础布局
export class LevelGenerator {
  constructor(state) {
    this.state = state;
  }

  // 根据难度生成完整段落
  generate(difficulty = 'medium', length = 3600) {
    const obstacles = [];
    const collectibles = [];
    let currentX = 500;

    while (currentX < length - 450) {
      const segment = this.generateSegment(currentX, difficulty);
      obstacles.push(...segment.obstacles);
      collectibles.push(...segment.collectibles);
      currentX = segment.nextX;
    }

    this.state.currentSegment.obstacles = obstacles;
    this.state.currentSegment.collectibles = collectibles;
  }

  // 生成一个有明确节奏的小段
  generateSegment(startX, difficulty) {
    const types = difficulty === 'easy'
      ? ['rest', 'rest', 'jump', 'slide']
      : difficulty === 'hard'
        ? ['jump', 'slide', 'mixed', 'mixed']
        : ['rest', 'jump', 'slide', 'mixed'];
    const type = this.randomChoice(types);

    if (type === 'rest') return this.generateRest(startX);
    if (type === 'slide') return this.generateSlide(startX);
    if (type === 'mixed') return this.generateMixed(startX, difficulty);
    return this.generateJump(startX, difficulty);
  }

  // 生成休息段
  generateRest(startX) {
    return {
      obstacles: [],
      collectibles: [0, 1, 2].map(index => ({
        type: 'coin', x: startX + index * 150, y: 400, r: 14
      })),
      nextX: startX + 500
    };
  }

  // 生成跳跃段和金币弧线
  generateJump(startX, difficulty) {
    const spikeCount = difficulty === 'hard' ? 2 : 1;
    const obstacles = Array.from({ length: spikeCount }, (_, index) => ({
      kind: 'spike', x: startX + 200 + index * 70, y: 446, w: 32, h: 16, dmg: 12
    }));
    const collectibles = Array.from({ length: 5 }, (_, index) => {
      const progress = index / 4;
      return {
        type: 'coin',
        x: startX + 100 + progress * 300,
        y: 380 - Math.sin(progress * Math.PI) * 80,
        r: 14
      };
    });
    return { obstacles, collectibles, nextX: startX + 600 };
  }

  // 生成滑铲段和低空金币
  generateSlide(startX) {
    return {
      obstacles: [{ kind: 'beam', x: startX + 200, y: 312, w: 20, h: 150, dmg: 0 }],
      collectibles: [0, 1, 2].map(index => ({
        type: 'coin', x: startX + 150 + index * 50, y: 440, r: 14
      })),
      nextX: startX + 500
    };
  }

  // 生成连续跳跃组合
  generateMixed(startX, difficulty) {
    const segment = this.generateJump(startX, difficulty);
    segment.obstacles.push({
      kind: 'pillar', x: startX + 440, y: 372, w: 36, h: 90, dmg: 20
    });
    segment.nextX = startX + 700;
    return segment;
  }

  // 从候选项中随机选取一个
  randomChoice(items) {
    return items[Math.floor(Math.random() * items.length)];
  }
}
