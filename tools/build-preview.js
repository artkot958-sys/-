/**
 * Генератор "статичной" копии мира для .rbxlx.
 *
 * Зачем: скрипты в Roblox Studio выполняются только при Play.
 * Если открыть файл и не нажать Play — видна пустая площадка.
 * Чтобы карта была видна СРАЗУ, дублируем геометрию мира прямо в файл:
 * части, базы, деревья, рынок — всё лежит в Workspace как обычные объекты.
 *
 * При нажатии Play скрипт EggGameMain удаляет эту копию (папка
 * "EggGamePreview") и строит живую арену с логикой.
 */

const PALETTE = {
  GrassDark: [64, 122, 62],
  GrassMid: [84, 146, 76],
  GrassLight: [104, 168, 88],
  Sand: [206, 184, 132],
  SandDark: [178, 154, 104],
  Stone: [126, 128, 134],
  StoneDark: [92, 94, 102],
  Rock: [108, 110, 118],
  Dirt: [128, 100, 72],
  DirtDark: [100, 78, 56],
  Wood: [124, 90, 58],
  WoodDark: [88, 62, 40],
  WoodLight: [158, 120, 78],
  RoofRed: [168, 64, 54],
  RoofOrange: [206, 112, 48],
  RoofBlue: [62, 104, 158],
  Canvas: [232, 218, 186],
  CanvasDark: [198, 178, 142],
  Gold: [255, 196, 64],
  LanternGlow: [255, 212, 132],
  Water: [78, 152, 196],
  LeafA: [58, 138, 78],
  LeafB: [96, 180, 108],
  LeafC: [44, 112, 66],
  MyBase: [70, 230, 140],
  White: [232, 238, 245],
};

// Материалы Roblox (числовые id)
const MATERIAL = {
  Plastic: 256,
  Grass: 1280,
  Sand: 1296,
  Rock: 896,
  Concrete: 816,
  WoodPlanks: 836,
  Wood: 512,
  Metal: 1088,
  Neon: 288,
  Marble: 784,
  Slate: 800,
  Fabric: 1312,
  Ground: 0,
  Snow: 1328,
  Glass: 1152,
  Cobblestone: 880,
};

// Детерминированный "рандом" — чтобы файл собирался одинаково
let seed = 20261109;
function rand() {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
}
function randRange(a, b) {
  return a + rand() * (b - a);
}
function randInt(a, b) {
  return Math.floor(randRange(a, b + 1));
}

function colorInt(rgb) {
  // Color3uint8: 0xFF000000 | (R<<16) | (G<<8) | B
  return (0xff000000 + (rgb[0] << 16) + (rgb[1] << 8) + rgb[2]) >>> 0;
}

function rgb(r, g, b) {
  return [r, g, b];
}

function mixColor(a, b, t) {
  return [
    Math.round(a[0] + (b[0] - a[0]) * t),
    Math.round(a[1] + (b[1] - a[1]) * t),
    Math.round(a[2] + (b[2] - a[2]) * t),
  ];
}

/** XML для одной части */
function partXml(opts) {
  const {
    name,
    size,
    position,
    rotation = [0, 0, 0],
    color = PALETTE.Stone,
    material = MATERIAL.Plastic,
    transparency = 0,
    anchored = true,
    canCollide = false,
    shape = "Block",
    reflectance = 0,
  } = opts;

  // Для шара/цилиндра Roblox масштабирует по минимальной оси — приводим размер
  let finalSize = size;
  let shapeToken = "";
  if (shape === "Ball") {
    const d = Math.min(size[0], size[1], size[2]);
    finalSize = [d, d, d];
    shapeToken = `<token name="shape">2</token>`;
  } else if (shape === "Cylinder") {
    const d = Math.min(size[2], size[1]);
    finalSize = [size[0], d, d];
    shapeToken = `<token name="shape">3</token>`;
  }

  const [rx, ry, rz] = rotation;

  // Матрица поворота (простая, порядок XYZ)
  const cx = Math.cos(rx), sx = Math.sin(rx);
  const cy = Math.cos(ry), sy = Math.sin(ry);
  const cz = Math.cos(rz), sz = Math.sin(rz);

  const R00 = cy * cz;
  const R01 = sx * sy * cz - cx * sz;
  const R02 = cx * sy * cz + sx * sz;
  const R10 = cy * sz;
  const R11 = sx * sy * sz + cx * cz;
  const R12 = cx * sy * sz - sx * cz;
  const R20 = -sy;
  const R21 = sx * cy;
  const R22 = cx * cy;

  return `
		<Item class="Part" referent="RBXPART">
			<Properties>
				<string name="Name">${escapeXml(name)}</string>
				<bool name="Anchored">${anchored}</bool>
				<bool name="CanCollide">${canCollide}</bool>
				<bool name="CanQuery">${canCollide}</bool>
				<bool name="CanTouch">${canCollide}</bool>
				<token name="Material">${material}</token>
				<Color3uint8 name="Color3uint8">${colorInt(color)}</Color3uint8>
				<float name="Transparency">${transparency}</float>
				<float name="Reflectance">${reflectance}</float>
				${shapeToken}
				<Vector3 name="size">
					<X>${finalSize[0]}</X><Y>${finalSize[1]}</Y><Z>${finalSize[2]}</Z>
				</Vector3>
				<CoordinateFrame name="CFrame">
					<X>${position[0]}</X><Y>${position[1]}</Y><Z>${position[2]}</Z>
					<R00>${R00.toFixed(6)}</R00><R01>${R01.toFixed(6)}</R01><R02>${R02.toFixed(6)}</R02>
					<R10>${R10.toFixed(6)}</R10><R11>${R11.toFixed(6)}</R11><R12>${R12.toFixed(6)}</R12>
					<R20>${R20.toFixed(6)}</R20><R21>${R21.toFixed(6)}</R21><R22>${R22.toFixed(6)}</R22>
				</CoordinateFrame>
			</Properties>
		</Item>`;
}

function escapeXml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function folderXml(name, children) {
  return `
	<Item class="Folder">
		<Properties>
			<string name="Name">${escapeXml(name)}</string>
		</Properties>
${children.join("\n")}
	</Item>`;
}

function modelXml(name, children) {
  return `
	<Item class="Model">
		<Properties>
			<string name="Name">${escapeXml(name)}</string>
		</Properties>
${children.join("\n")}
	</Item>`;
}

// ============================================================
// ГЕНЕРАЦИЯ МИРА
// ============================================================

const ARENA = 400;
const MARKET_R = 36;
const BASES = 16;
const BASE_RING = 134;
const BASE_ZONE = 15;

function buildTerrain() {
  const parts = [];
  const half = ARENA / 2;

  // основание
  parts.push(partXml({
    name: "WorldBase", size: [ARENA + 60, 24, ARENA + 60],
    position: [0, -13, 0], color: PALETTE.StoneDark,
    material: MATERIAL.Rock, canCollide: true,
  }));

  // трава
  parts.push(partXml({
    name: "Ground", size: [ARENA, 4, ARENA],
    position: [0, -2, 0], color: PALETTE.GrassMid,
    material: MATERIAL.Grass, canCollide: true,
  }));

  // пятна травы
  for (let i = 0; i < 40; i++) {
    const a = rand() * Math.PI * 2;
    const d = Math.sqrt(rand()) * (half - 12);
    const sz = randRange(18, 58);
    const col = i % 3 === 0 ? PALETTE.GrassLight : i % 3 === 1 ? PALETTE.GrassDark : PALETTE.GrassMid;
    parts.push(partXml({
      name: "GrassPatch", size: [sz, 0.3, sz],
      position: [Math.cos(a) * d, 0.12, Math.sin(a) * d],
      color: col, material: MATERIAL.Grass, shape: "Cylinder",
      rotation: [0, 0, Math.PI / 2],
    }));
  }

  // кольцевая дорога
  parts.push(partXml({
    name: "RingRoad", size: [0.6, (BASE_RING + 26) * 2, (BASE_RING + 26) * 2],
    position: [0, 0.2, 0], color: PALETTE.SandDark,
    material: MATERIAL.Sand, shape: "Cylinder",
    rotation: [0, 0, Math.PI / 2],
  }));

  // площадь рынка
  parts.push(partXml({
    name: "MarketPlaza", size: [0.9, (MARKET_R + 10) * 2, (MARKET_R + 10) * 2],
    position: [0, 0.3, 0], color: PALETTE.Stone,
    material: MATERIAL.Cobblestone, shape: "Cylinder", canCollide: true,
    rotation: [0, 0, Math.PI / 2],
  }));

  // дорожки к базам
  for (let i = 1; i <= BASES; i++) {
    const angle = ((i - 1) / BASES) * Math.PI * 2;
    const from = MARKET_R + 8;
    const to = BASE_RING - BASE_ZONE - 2;
    const length = to - from;
    const middle = (from + to) / 2;
    parts.push(partXml({
      name: "Path", size: [9, 0.35, length],
      position: [Math.cos(angle) * middle, 0.28, Math.sin(angle) * middle],
      rotation: [0, -angle + Math.PI / 2, 0],
      color: PALETTE.Dirt, material: MATERIAL.Ground,
    }));
  }

  // горы
  for (let i = 0; i < 26; i++) {
    const angle = (i / 26) * Math.PI * 2 + rand() * 0.15;
    const distance = half - rand() * 26 - 8;
    const h = randRange(34, 90);
    const w = randRange(26, 52);
    parts.push(partXml({
      name: "Mountain", size: [h, w, w],
      position: [Math.cos(angle) * distance, h / 2 - 3, Math.sin(angle) * distance],
      rotation: [0, rand() * Math.PI, Math.PI / 2],
      color: mixColor(PALETTE.Rock, PALETTE.StoneDark, rand()),
      material: MATERIAL.Rock, shape: "Cylinder", canCollide: true,
    }));
    parts.push(partXml({
      name: "Peak", size: [w * 0.55, w * 0.55, w * 0.55],
      position: [Math.cos(angle) * distance, h - 6, Math.sin(angle) * distance],
      color: PALETTE.White, material: MATERIAL.Snow, shape: "Ball",
    }));
  }

  // стены
  const wh = 26, wt = 8;
  parts.push(partXml({
    name: "WallN", size: [ARENA + wt * 2, wh, wt],
    position: [0, wh / 2 - 1, -half - wt / 2],
    color: PALETTE.StoneDark, material: MATERIAL.Rock, canCollide: true,
  }));
  parts.push(partXml({
    name: "WallS", size: [ARENA + wt * 2, wh, wt],
    position: [0, wh / 2 - 1, half + wt / 2],
    color: PALETTE.StoneDark, material: MATERIAL.Rock, canCollide: true,
  }));
  parts.push(partXml({
    name: "WallW", size: [wt, wh, ARENA],
    position: [-half - wt / 2, wh / 2 - 1, 0],
    color: PALETTE.StoneDark, material: MATERIAL.Rock, canCollide: true,
  }));
  parts.push(partXml({
    name: "WallE", size: [wt, wh, ARENA],
    position: [half + wt / 2, wh / 2 - 1, 0],
    color: PALETTE.StoneDark, material: MATERIAL.Rock, canCollide: true,
  }));

  return folderXml("Terrain", parts);
}

function buildMarket() {
  const parts = [];

  // пьедестал
  parts.push(partXml({
    name: "PedestalBase", size: [3.2, 14, 14], position: [0, 2, 0],
    color: PALETTE.Stone, material: MATERIAL.Marble, canCollide: true,
    shape: "Cylinder", rotation: [0, 0, Math.PI / 2],
  }));
  parts.push(partXml({
    name: "PedestalTop", size: [1.2, 10.4, 10.4], position: [0, 4, 0],
    color: PALETTE.StoneDark, material: MATERIAL.Marble, canCollide: true,
    shape: "Cylinder", rotation: [0, 0, Math.PI / 2],
  }));

  // статуя яйца
  parts.push(partXml({
    name: "MarketStatue", size: [4.4, 5.9, 4.4], position: [0, 7.4, 0],
    color: PALETTE.Gold, material: MATERIAL.Neon, shape: "Ball",
  }));

  // шатры
  const tentColors = [PALETTE.RoofRed, PALETTE.RoofOrange, PALETTE.RoofBlue];
  for (let i = 1; i <= 8; i++) {
    const angle = ((i - 1) / 8) * Math.PI * 2 + Math.PI / 8;
    const px = Math.cos(angle) * (MARKET_R - 4);
    const pz = Math.sin(angle) * (MARKET_R - 4);
    const rotY = -angle;

    parts.push(partXml({
      name: "TentFloor", size: [15, 0.7, 15], position: [px, 0.7, pz],
      rotation: [0, rotY, 0], color: PALETTE.WoodLight,
      material: MATERIAL.WoodPlanks, canCollide: true,
    }));

    // 4 столба
    for (let p = 1; p <= 4; p++) {
      const ox = p <= 2 ? -6.2 : 6.2;
      const oz = p % 2 === 1 ? -6.2 : 6.2;
      const cos = Math.cos(rotY), sin = Math.sin(rotY);
      parts.push(partXml({
        name: "Pillar", size: [0.9, 12, 0.9],
        position: [px + ox * cos + oz * sin, 6.4, pz - ox * sin + oz * cos],
        color: PALETTE.Wood, material: MATERIAL.Wood, canCollide: true,
      }));
    }

    parts.push(partXml({
      name: "Canopy", size: [16, 1.1, 16], position: [px, 12.6, pz],
      rotation: [0, rotY, 0], color: tentColors[(i - 1) % 3],
      material: MATERIAL.Fabric, canCollide: true,
    }));
    parts.push(partXml({
      name: "CanopyTop", size: [9, 2.4, 9], position: [px, 14, pz],
      rotation: [0, rotY, 0], color: PALETTE.CanvasDark, material: MATERIAL.Fabric,
    }));
    parts.push(partXml({
      name: "Counter", size: [7, 3, 2.2], position: [px, 3.4, pz + 3.4],
      rotation: [0, rotY, 0], color: PALETTE.WoodDark,
      material: MATERIAL.WoodPlanks, canCollide: true,
    }));
    parts.push(partXml({
      name: "Flag", size: [3.4, 2, 0.3], position: [px, 16.4, pz],
      rotation: [0, rotY, 0], color: PALETTE.Gold, material: MATERIAL.Fabric,
    }));
  }

  // фонари
  for (let i = 0; i < 12; i++) {
    const angle = (i / 12) * Math.PI * 2;
    const px = Math.cos(angle) * (MARKET_R + 6);
    const pz = Math.sin(angle) * (MARKET_R + 6);

    parts.push(partXml({
      name: "LanternPost", size: [0.8, 13, 0.8], position: [px, 6.5, pz],
      color: PALETTE.StoneDark, material: MATERIAL.Metal, canCollide: true,
    }));
    parts.push(partXml({
      name: "Lantern", size: [2.2, 2.2, 2.2], position: [px, 13.6, pz],
      color: PALETTE.LanternGlow, material: MATERIAL.Neon, shape: "Ball",
    }));
  }

  // спавн
  parts.push(partXml({
    name: "PreviewSpawn", size: [18, 1.2, 18], position: [0, 1.4, 18],
    color: PALETTE.Gold, material: MATERIAL.Neon, transparency: 0.55,
  }));

  return folderXml("Market", parts);
}

function buildBases() {
  const bases = [];

  for (let i = 1; i <= BASES; i++) {
    const angle = ((i - 1) / BASES) * Math.PI * 2;
    const cx = Math.cos(angle) * BASE_RING;
    const cz = Math.sin(angle) * BASE_RING;
    const parts = [];

    // площадка
    parts.push(partXml({
      name: "Platform", size: [1.2, (BASE_ZONE + 2) * 2, (BASE_ZONE + 2) * 2],
      position: [cx, 0.6, cz], color: PALETTE.Sand,
      material: MATERIAL.Sand, shape: "Cylinder", canCollide: true,
      rotation: [0, 0, Math.PI / 2],
    }));

    // окантовка
    parts.push(partXml({
      name: "Glow", size: [0.25, (BASE_ZONE + 3.4) * 2, (BASE_ZONE + 3.4) * 2],
      position: [cx, 0.8, cz], color: [180, 190, 200],
      material: MATERIAL.Neon, shape: "Cylinder",
      rotation: [0, 0, Math.PI / 2],
    }));

    // склад
    parts.push(partXml({
      name: "VaultStand", size: [11, 3.6, 11], position: [cx, 2.6, cz],
      rotation: [0, -angle, 0], color: PALETTE.DirtDark,
      material: MATERIAL.WoodPlanks, canCollide: true,
    }));
    parts.push(partXml({
      name: "VaultTop", size: [10.4, 0.9, 10.4], position: [cx, 4.9, cz],
      rotation: [0, -angle, 0], color: PALETTE.WoodLight,
      material: MATERIAL.WoodPlanks, canCollide: true,
    }));
    parts.push(partXml({
      name: "VaultGlow", size: [11.4, 0.3, 11.4], position: [cx, 5.3, cz],
      rotation: [0, -angle, 0], color: PALETTE.Gold, material: MATERIAL.Neon,
    }));

    // вывеска
    const signX = cx - Math.cos(angle) * (BASE_ZONE - 1);
    const signZ = cz - Math.sin(angle) * (BASE_ZONE - 1);
    parts.push(partXml({
      name: "SignPost", size: [1.1, 15, 1.1], position: [signX, 8, signZ],
      color: PALETTE.WoodDark, material: MATERIAL.Wood, canCollide: true,
    }));
    parts.push(partXml({
      name: "SignBoard", size: [15, 6, 0.9], position: [signX, 16, signZ],
      color: PALETTE.WoodDark, material: MATERIAL.WoodPlanks,
    }));

    // ящики и бочка
    for (let c = 1; c <= 3; c++) {
      const side = c === 1 ? 1 : -1;
      const crateAngle = angle + side * (0.5 + c * 0.12);
      const px = Math.cos(crateAngle) * (BASE_RING + BASE_ZONE - 3);
      const pz = Math.sin(crateAngle) * (BASE_RING + BASE_ZONE - 3);

      if (c === 3) {
        parts.push(partXml({
          name: "Barrel", size: [4.2, 3.2, 3.2], position: [px, 3, pz],
          rotation: [0, 0, Math.PI / 2], color: PALETTE.Wood,
          material: MATERIAL.Wood, shape: "Cylinder", canCollide: true,
        }));
      } else {
        parts.push(partXml({
          name: "Crate", size: [3.4, 3.4, 3.4], position: [px, 2.5, pz],
          rotation: [0, (c * 24 + i * 13) * Math.PI / 180, 0],
          color: PALETTE.Wood, material: MATERIAL.WoodPlanks, canCollide: true,
        }));
      }
    }

    // костёр
    const fireAngle = angle + 0.7;
    const fx = cx + Math.cos(fireAngle) * (BASE_ZONE + 7) - Math.cos(angle) * 0;
    const fz = cz + Math.sin(fireAngle) * (BASE_ZONE + 7);
    const fpx = Math.cos(angle) * (BASE_RING + BASE_ZONE + 7);
    const fpz = Math.sin(angle) * (BASE_RING + BASE_ZONE + 7);

    parts.push(partXml({
      name: "CampfireBase", size: [0.9, 4.6, 4.6],
      position: [fpx, 0.7, fpz], rotation: [0, 0, Math.PI / 2],
      color: PALETTE.Stone, material: MATERIAL.Cobblestone, shape: "Cylinder",
    }));
    parts.push(partXml({
      name: "Flame", size: [1.9, 1.9, 1.9], position: [fpx, 2.2, fpz],
      color: [255, 146, 46], material: MATERIAL.Neon, shape: "Ball",
    }));

    bases.push(modelXml("Base_" + i, parts));
  }

  return folderXml("Bases", bases);
}

function buildNature() {
  const parts = [];
  const half = ARENA / 2;
  const leafColors = [PALETTE.LeafA, PALETTE.LeafB, PALETTE.LeafC];

  // деревья
  for (let i = 0; i < 50; i++) {
    const angle = rand() * Math.PI * 2;
    let distance = BASE_RING + BASE_ZONE + 16 + rand() * (half - BASE_RING - BASE_ZONE - 40);
    distance = Math.min(distance, half - 22);
    const px = Math.cos(angle) * distance;
    const pz = Math.sin(angle) * distance;
    const scale = randRange(0.8, 1.5);
    const trunkH = randRange(9, 16) * scale;
    const trunkW = randRange(2.4, 3.6) * scale;

    parts.push(partXml({
      name: "Trunk", size: [trunkH, trunkW, trunkW],
      position: [px, trunkH / 2, pz], rotation: [0, 0, Math.PI / 2],
      color: mixColor(PALETTE.Wood, PALETTE.WoodDark, rand()),
      material: MATERIAL.Wood, shape: "Cylinder", canCollide: true,
    }));

    for (let layer = 1; layer <= 3; layer++) {
      const ls = (10 - layer * 2.2 + rand() * 1.6) * scale;
      parts.push(partXml({
        name: "Leaves", size: [ls, ls, ls],
        position: [
          px + (rand() - 0.5) * 2.6 * scale,
          trunkH + (layer - 1) * 2.8 * scale - 1.6 * scale,
          pz + (rand() - 0.5) * 2.6 * scale,
        ],
        color: leafColors[randInt(0, 2)],
        material: MATERIAL.Grass, shape: "Ball",
      }));
    }
  }

  // камни
  for (let i = 0; i < 55; i++) {
    const angle = rand() * Math.PI * 2;
    const distance = MARKET_R + 14 + rand() * (half - MARKET_R - 40);
    const rockSize = randRange(2, 7);
    parts.push(partXml({
      name: "Rock", size: [rockSize, rockSize, rockSize],
      position: [Math.cos(angle) * distance, rockSize / 3, Math.sin(angle) * distance],
      rotation: [rand() * 3, rand() * 3, rand() * 3],
      color: mixColor(PALETTE.Rock, PALETTE.Stone, rand()),
      material: MATERIAL.Rock, shape: "Ball",
    }));
  }

  // кусты
  for (let i = 0; i < 75; i++) {
    const angle = rand() * Math.PI * 2;
    const distance = MARKET_R + 10 + rand() * (half - MARKET_R - 30);
    const bushSize = randRange(1.8, 4);
    parts.push(partXml({
      name: "Bush", size: [bushSize, bushSize, bushSize],
      position: [Math.cos(angle) * distance, bushSize / 2.4, Math.sin(angle) * distance],
      color: mixColor(PALETTE.LeafC, PALETTE.LeafA, rand()),
      material: MATERIAL.Grass, shape: "Ball",
    }));
  }

  // цветы
  const flowerColors = [
    [255, 120, 140], [255, 216, 96], [196, 132, 255],
    [120, 200, 255], [255, 255, 255],
  ];
  for (let i = 0; i < 130; i++) {
    const angle = rand() * Math.PI * 2;
    const distance = MARKET_R + 8 + rand() * (half - MARKET_R - 30);
    parts.push(partXml({
      name: "Flower", size: [0.75, 0.75, 0.75],
      position: [Math.cos(angle) * distance, 1.1, Math.sin(angle) * distance],
      color: flowerColors[randInt(0, 4)],
      material: MATERIAL.Grass, shape: "Ball",
    }));
  }

  // пруд
  const pondX = -BASE_RING - 8;
  const pondZ = BASE_RING - 30;
  parts.push(partXml({
    name: "PondEdge", size: [0.8, 48, 48], position: [pondX, 0.4, pondZ],
    rotation: [0, 0, Math.PI / 2], color: PALETTE.SandDark,
    material: MATERIAL.Sand, shape: "Cylinder",
  }));
  parts.push(partXml({
    name: "PondWater", size: [0.5, 42, 42], position: [pondX, 0.55, pondZ],
    rotation: [0, 0, Math.PI / 2], color: PALETTE.Water,
    material: MATERIAL.Glass, transparency: 0.25, shape: "Cylinder",
    reflectance: 0.3,
  }));

  return folderXml("Nature", parts);
}

function buildPreview() {
  const terrain = buildTerrain();
  const market = buildMarket();
  const bases = buildBases();
  const nature = buildNature();

  return folderXml("EggGamePreview", [terrain, market, bases, nature]);
}

module.exports = { buildPreview, PALETTE, MATERIAL, partXml, folderXml, colorInt, escapeXml };
