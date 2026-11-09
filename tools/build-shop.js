/**
 * Магазин улучшений — отдельное здание на карте.
 *
 * Что строит:
 *   • Здание с фундаментом, стенами, витриной и двускатной крышей
 *   • Внутри: прилавок-касса, 6 полок с товаром (по улучшению на полку)
 *   • Вывеску "МАГАЗИН УЛУЧШЕНИЙ" с подсветкой
 *   • NPC-продавца
 *   • Стойку-терминал у входа (ProximityPrompt для открытия UI)
 *
 * Экспортирует два варианта:
 *   buildShopPreview() — статичный XML для .rbxlx
 *   (живая версия строится в EggGameMap.lua)
 */

const PALETTE = {
  Wood: [124, 90, 58],
  WoodDark: [88, 62, 40],
  WoodLight: [158, 120, 78],
  Stone: [126, 128, 134],
  StoneDark: [92, 94, 102],
  Wall: [236, 226, 208],
  WallTrim: [176, 140, 100],
  RoofTeal: [58, 140, 140],
  RoofDark: [42, 104, 112],
  Gold: [255, 196, 64],
  Glass: [186, 222, 236],
  Red: [196, 72, 64],
  Purple: [150, 96, 210],
  Blue: [78, 140, 210],
  Green: [86, 176, 110],
  Orange: [230, 138, 56],
  White: [246, 242, 234],
  SkinTone: [232, 190, 154],
  ShirtBlue: [66, 118, 176],
  Pants: [62, 68, 88],
  Hair: [68, 48, 36],
};

const MATERIAL = {
  Plastic: 256,
  SmoothPlastic: 272,
  Grass: 1280,
  Sand: 1296,
  Rock: 896,
  Concrete: 816,
  WoodPlanks: 836,
  Wood: 512,
  Metal: 1088,
  Neon: 288,
  Marble: 784,
  Fabric: 1312,
  Glass: 1152,
  Cobblestone: 880,
  Brick: 848,
};

const SHAPE = { Block: null, Ball: 0, Cylinder: 2 };

function colorInt(rgb) {
  return (0xff000000 + (rgb[0] << 16) + (rgb[1] << 8) + rgb[2]) >>> 0;
}

function escapeXml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Собирает XML одной части.
 * rotation в радианах: [X, Y, Z]
 */
function part(opts) {
  const {
    name = "Part",
    size,
    position,
    rotation = [0, 0, 0],
    color = PALETTE.Stone,
    material = MATERIAL.Plastic,
    transparency = 0,
    canCollide = false,
    shape = null,
    anchor = true,
  } = opts;

  let finalSize = size;
  let shapeTag = "";

  if (shape === "Ball") {
    const d = Math.min(size[0], size[1], size[2]);
    finalSize = [d, d, d];
    shapeTag = `<token name="Shape">0</token>`;
  } else if (shape === "Cylinder") {
    const d = Math.min(size[1], size[2]);
    finalSize = [size[0], d, d];
    shapeTag = `<token name="Shape">2</token>`;
  }

  const [rx, ry, rz] = rotation;
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
		<Item class="Part">
			<Properties>
				<string name="Name">${escapeXml(name)}</string>
				<bool name="Anchored">${anchor}</bool>
				<bool name="CanCollide">${canCollide}</bool>
				<token name="Material">${material}</token>
				<Color3uint8 name="Color3uint8">${colorInt(color)}</Color3uint8>
				<float name="Transparency">${transparency}</float>
				${shapeTag}
				<Vector3 name="size"><X>${finalSize[0]}</X><Y>${finalSize[1]}</Y><Z>${finalSize[2]}</Z></Vector3>
				<CoordinateFrame name="CFrame">
					<X>${position[0]}</X><Y>${position[1]}</Y><Z>${position[2]}</Z>
					<R00>${R00.toFixed(6)}</R00><R01>${R01.toFixed(6)}</R01><R02>${R02.toFixed(6)}</R02>
					<R10>${R10.toFixed(6)}</R10><R11>${R11.toFixed(6)}</R11><R12>${R12.toFixed(6)}</R12>
					<R20>${R20.toFixed(6)}</R20><R21>${R21.toFixed(6)}</R21><R22>${R22.toFixed(6)}</R22>
				</CoordinateFrame>
			</Properties>
		</Item>`;
}

function folder(name, children) {
  return `
	<Item class="Folder">
		<Properties><string name="Name">${escapeXml(name)}</string></Properties>
${children.join("\n")}
	</Item>`;
}

// ============================================================
// ПОСТРОЙКА МАГАЗИНА
// ============================================================

/**
 * @param {object} origin  {x, y, z} — точка центра магазина
 * @param {number} facing  угол поворота (радианы), 0 = вход смотрит на +Z
 */
function buildShop(origin = { x: 0, y: 0, z: -70 }, facing = Math.PI) {
  const ox = origin.x;
  const oy = origin.y;
  const oz = origin.z;
  const parts = [];

  const W = 34;   // ширина
  const D = 26;   // глубина
  const H = 16;   // высота стен

  // helper: точка в локальных координатах магазина -> мировые
  function local(lx, ly, lz) {
    const cos = Math.cos(facing);
    const sin = Math.sin(facing);
    return [ox + lx * cos + lz * sin, oy + ly, oz - lx * sin + lz * cos];
  }

  function add(opts) {
    parts.push(part(opts));
  }

  // ===================== ФУНДАМЕНТ =====================
  add({
    name: "ShopFloor",
    size: [W + 4, 1.6, D + 4],
    position: local(0, 0.8, 0),
    rotation: [0, facing, 0],
    color: PALETTE.Stone,
    material: MATERIAL.Concrete,
    canCollide: true,
  });

  // мощёный дворик перед входом
  add({
    name: "ShopYard",
    size: [46, 0.35, 30],
    position: local(0, 0.18, D / 2 + 12),
    rotation: [0, facing, 0],
    color: PALETTE.Stone,
    material: MATERIAL.Cobblestone,
  });

  // дорожка от дворика к рынку
  add({
    name: "ShopPath",
    size: [10, 0.4, 34],
    position: local(0, 0.2, D / 2 + 40),
    rotation: [0, facing, 0],
    color: PALETTE.SandDark,
    material: MATERIAL.Cobblestone,
  });

  // ===================== СТЕНЫ =====================
  const wallThickness = 1.2;

  // задняя стена
  add({
    name: "WallBack",
    size: [W, H, wallThickness],
    position: local(0, H / 2 + 1.6, -D / 2),
    rotation: [0, facing, 0],
    color: PALETTE.Wall,
    material: MATERIAL.Concrete,
    canCollide: true,
  });

  // боковые стены
  for (const side of [-1, 1]) {
    add({
      name: "WallSide",
      size: [wallThickness, H, D],
      position: local(side * W / 2, H / 2 + 1.6, 0),
      rotation: [0, facing, 0],
      color: PALETTE.Wall,
      material: MATERIAL.Concrete,
      canCollide: true,
    });
  }

  // фасад: две колонны + широкий проём (открытый вход)
  for (const side of [-1, 1]) {
    add({
      name: "FacadeColumn",
      size: [5, H, wallThickness],
      position: local(side * (W / 2 - 2.5), H / 2 + 1.6, D / 2),
      rotation: [0, facing, 0],
      color: PALETTE.Wall,
      material: MATERIAL.Concrete,
      canCollide: true,
    });
  }

  // верхняя перемычка фасада
  add({
    name: "FacadeLintel",
    size: [W, 4, wallThickness],
    position: local(0, H + 1.6 - 2, D / 2),
    rotation: [0, facing, 0],
    color: PALETTE.Wall,
    material: MATERIAL.Concrete,
    canCollide: true,
  });

  // декоративный деревянный пояс по стенам
  add({
    name: "WallTrim",
    size: [W + 0.6, 1.2, wallThickness + 0.5],
    position: local(0, 6, -D / 2),
    rotation: [0, facing, 0],
    color: PALETTE.WallTrim,
    material: MATERIAL.WoodPlanks,
  });
  for (const side of [-1, 1]) {
    add({
      name: "WallTrimSide",
      size: [wallThickness + 0.5, 1.2, D],
      position: local(side * W / 2, 6, 0),
      rotation: [0, facing, 0],
      color: PALETTE.WallTrim,
      material: MATERIAL.WoodPlanks,
    });
  }

  // ===================== КРЫША =====================
  // Двускатная: два наклонных ската
  const roofAngle = Math.atan2(7, D / 2);
  const roofLen = Math.sqrt((D / 2) ** 2 + 7 ** 2);

  for (const side of [-1, 1]) {
    add({
      name: "RoofSlope",
      size: [W + 5, 1.2, roofLen + 2],
      position: local(0, H + 5.5, side * D / 4),
      rotation: [side * roofAngle, facing, 0],
      color: PALETTE.RoofTeal,
      material: MATERIAL.Fabric,
      canCollide: true,
    });
  }

  // конёк крыши
  add({
    name: "RoofRidge",
    size: [W + 6, 1.6, 2.4],
    position: local(0, H + 9.2, 0),
    rotation: [0, facing, 0],
    color: PALETTE.RoofDark,
    material: MATERIAL.Wood,
  });

  // ===================== ВИТРИНА =====================
  // Стеклянные панели по бокам от входа
  for (const side of [-1, 1]) {
    add({
      name: "WindowGlass",
      size: [8, 8, 0.4],
      position: local(side * 10, 9, D / 2),
      rotation: [0, facing, 0],
      color: PALETTE.Glass,
      material: MATERIAL.Glass,
      transparency: 0.55,
    });

    // рама
    add({
      name: "WindowFrame",
      size: [8.6, 8.6, 0.3],
      position: local(side * 10, 9, D / 2 - 0.3),
      rotation: [0, facing, 0],
      color: PALETTE.WoodDark,
      material: MATERIAL.WoodPlanks,
    });
  }

  // ===================== ВЫВЕСКА =====================
  add({
    name: "ShopSignBack",
    size: [26, 6, 0.8],
    position: local(0, H + 2.5, D / 2 + 0.9),
    rotation: [0, facing, 0],
    color: PALETTE.WoodDark,
    material: MATERIAL.WoodPlanks,
  });

  // рама вывески (золотая окантовка)
  add({
    name: "ShopSignTrim",
    size: [27.4, 7.4, 0.4],
    position: local(0, H + 2.5, D / 2 + 0.6),
    rotation: [0, facing, 0],
    color: PALETTE.Gold,
    material: MATERIAL.Neon,
    transparency: 0.35,
  });

  // ===================== ВНУТРИ: ПРИЛАВОК-КАССА =====================
  add({
    name: "ShopCounter",
    size: [16, 4, 3.2],
    position: local(0, 3.6, -2),
    rotation: [0, facing, 0],
    color: PALETTE.Wood,
    material: MATERIAL.WoodPlanks,
    canCollide: true,
  });

  add({
    name: "CounterTop",
    size: [17, 0.7, 4],
    position: local(0, 5.9, -2),
    rotation: [0, facing, 0],
    color: PALETTE.WoodLight,
    material: MATERIAL.WoodPlanks,
    canCollide: true,
  });

  // кассовый аппарат
  add({
    name: "Register",
    size: [3, 2.4, 2.4],
    position: local(4.5, 7.5, -2),
    rotation: [0, facing, 0],
    color: PALETTE.Gold,
    material: MATERIAL.Neon,
  });

  add({
    name: "RegisterScreen",
    size: [2.2, 1.4, 0.2],
    position: local(4.5, 8.4, -0.9),
    rotation: [0, facing, 0],
    color: [30, 40, 50],
    material: MATERIAL.SmoothPlastic,
  });

  // ===================== ПОЛКИ С ТОВАРОМ =====================
  // 6 полок = 6 улучшений, каждая своего цвета
  const shelfColors = [
    PALETTE.Blue,    // Рюкзак
    PALETTE.Orange,  // Скорость
    PALETTE.Purple,  // Магнит
    PALETTE.Red,     // Ловкость
    PALETTE.Green,   // Склад
    PALETTE.Gold,    // Доход
  ];

  for (let i = 0; i < 6; i++) {
    const side = i < 3 ? -1 : 1;
    const index = i % 3;
    const lx = side * (10 + index * 0);
    const lz = -D / 2 + 4 + index * 7;
    const color = shelfColors[i];

    // стойка
    add({
      name: "Shelf",
      size: [6, 1.2, 5],
      position: local(side * 12.5, 4 + [], 0) && local(side * 12.5, 4.5, -D / 2 + 5 + index * 6),
      rotation: [0, facing, 0],
      color: PALETTE.WoodDark,
      material: MATERIAL.WoodPlanks,
      canCollide: true,
    });

    // товар на полке — цветной куб
    add({
      name: "ShelfItem",
      size: [2.4, 2.4, 2.4],
      position: local(side * 12.5, 6.4, -D / 2 + 5 + index * 6),
      rotation: [0.4, facing, 0.3],
      color: color,
      material: MATERIAL.SmoothPlastic,
    });

    // подсветка полки
    add({
      name: "ShelfGlow",
      size: [6.6, 0.3, 5.6],
      position: local(side * 12.5, 5.2, -D / 2 + 5 + index * 6),
      rotation: [0, facing, 0],
      color: color,
      material: MATERIAL.Neon,
      transparency: 0.2,
    });
  }

  // ===================== NPC-ПРОДАВЕЦ =====================
  // Простая фигурка за прилавком
  const npcX = -4;
  const npcZ = -4;

  // торс
  add({
    name: "NPC_Torso",
    size: [4, 5, 2.2],
    position: local(npcX, 6.5, npcZ),
    rotation: [0, facing, 0],
    color: PALETTE.ShirtBlue,
    material: MATERIAL.SmoothPlastic,
    canCollide: true,
  });

  // голова
  add({
    name: "NPC_Head",
    size: [2.6, 2.6, 2.6],
    position: local(npcX, 10.4, npcZ),
    rotation: [0, facing, 0],
    color: PALETTE.SkinTone,
    material: MATERIAL.SmoothPlastic,
  });

  // волосы
  add({
    name: "NPC_Hair",
    size: [2.9, 1.1, 2.9],
    position: local(npcX, 11.5, npcZ),
    rotation: [0, facing, 0],
    color: PALETTE.Hair,
    material: MATERIAL.SmoothPlastic,
  });

  // руки
  for (const side of [-1, 1]) {
    add({
      name: "NPC_Arm",
      size: [1.2, 4.4, 1.2],
      position: local(npcX + side * 2.7, 6.6, npcZ),
      rotation: [0, facing, 0],
      color: PALETTE.ShirtBlue,
      material: MATERIAL.SmoothPlastic,
    });
  }

  // ноги
  for (const side of [-1, 1]) {
    add({
      name: "NPC_Leg",
      size: [1.6, 4, 1.6],
      position: local(npcX + side * 1, 2.2, npcZ),
      rotation: [0, facing, 0],
      color: PALETTE.Pants,
      material: MATERIAL.SmoothPlastic,
    });
  }

  // ===================== ФОНАРИ У ВХОДА =====================
  for (const side of [-1, 1]) {
    add({
      name: "ShopLanternPost",
      size: [0.7, 11, 0.7],
      position: local(side * (W / 2 + 3), 7, D / 2 + 4),
      rotation: [0, facing, 0],
      color: PALETTE.WoodDark,
      material: MATERIAL.Wood,
      canCollide: true,
    });

    add({
      name: "ShopLantern",
      size: [1.8, 1.8, 1.8],
      position: local(side * (W / 2 + 3), 12.6, D / 2 + 4),
      rotation: [0, facing, 0],
      color: PALETTE.Gold,
      material: MATERIAL.Neon,
      shape: "Ball",
    });
  }

  // цветочные ящики у входа
  for (const side of [-1, 1]) {
    add({
      name: "Planter",
      size: [4, 2, 2.4],
      position: local(side * (W / 2 - 1), 2.4, D / 2 + 2.5),
      rotation: [0, facing, 0],
      color: PALETTE.WoodDark,
      material: MATERIAL.WoodPlanks,
      canCollide: true,
    });

    // цветы в ящике
    const flowerColors = [PALETTE.Red, PALETTE.Gold, PALETTE.Purple];
    for (let f = 0; f < 3; f++) {
      add({
        name: "PlanterFlower",
        size: [0.9, 0.9, 0.9],
        position: local(side * (W / 2 - 1) + (f - 1) * 1.2, 3.9, D / 2 + 2.5),
        rotation: [0, 0, 0],
        color: flowerColors[f],
        material: MATERIAL.Grass,
        shape: "Ball",
      });
    }
  }

  return folder("Shop", parts);
}

module.exports = { buildShop, part, folder, PALETTE, MATERIAL, colorInt, escapeXml };
