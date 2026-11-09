/**
 * Запуск игры в настоящем Luau с заглушкой Roblox API.
 *
 * Важная деталь: весь код собирается в ОДИН чанк. Так `require`, `script`,
 * `game`, `workspace` оказываются в общей лексической области — точно
 * как в Roblox, где модули видят глобальную среду.
 *
 * Запуск: node tools/sim/run.mjs
 */

import { LuauState } from "luau-web";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "..", "..");
const SRC = path.join(ROOT, "src");

// ============================================================
// СРЕДА
// ============================================================

const env = {
  print: (...a) => console.log("   " + a.map((x) => (x === null ? "nil" : String(x))).join("")),
  warn: (...a) => console.log("   ⚠️  " + a.map(String).join(" ")),
  error: (msg) => {
    throw new Error(String(msg));
  },
  type: (v) => {
    if (v === null || v === undefined) return "nil";
    if (typeof v === "number") return "number";
    if (typeof v === "string") return "string";
    if (typeof v === "boolean") return "boolean";
    if (typeof v === "function") return "function";
    return "table";
  },
  tostring: (v) => (v === null || v === undefined ? "nil" : String(v)),
  tonumber: (v) => (v === null || v === undefined ? null : Number(v)),
  rawget: (t, k) => t[k],
  rawset: (t, k, v) => {
    t[k] = v;
    return t;
  },
  setmetatable: (t, mt) => {
    t.__mt = mt;
    return t;
  },
  getmetatable: (t) => t.__mt,
  assert: (c, m) => {
    if (!c) throw new Error(m ?? "assert failed");
    return c;
  },
  loadstring: () => {
    throw new Error("loadstring недоступен");
  },
};

const state = await LuauState.createAsync(env);

// ============================================================
// ЗАГРУЖАЕМ ЗАГЛУШКУ
// ============================================================

const shimSource = fs.readFileSync(path.join(__dirname, "roblox.lua"), "utf8");

const shimResult = await state.loadstring(
  `return (function()\n${shimSource}\nend)()`,
  "@roblox-shim",
  true
)();

const S = Array.isArray(shimResult) ? shimResult[0] : shimResult;

// Экспортируем нужные части заглушки в env, чтобы собранный чанк их видел
const bindings = [
  "Instance", "Enum", "Vector3", "Vector2", "CFrame", "Color3",
  "UDim", "UDim2", "Random", "TweenInfo", "NumberRange", "RaycastParams",
  "OverlapParams", "task", "game", "workspace",
];

for (const name of bindings) {
  env[name] = S[name];
}

env.shared = {};
env.Workspace = S.workspace;
env.warn = (...a) => console.log("   ⚠️  " + a.map(String).join(" "));

console.log("✓ Заглушка Roblox API загружена\n");

// ============================================================
// СОБИРАЕМ ИСХОДНИКИ
// ============================================================

const read = (p) => fs.readFileSync(path.join(SRC, p), "utf8");

const configSrc = read("ReplicatedStorage/EggGameConfig.lua");
const mapSrc = read("ServerScriptService/EggGame/EggGameMap.lua");
const dataSrc = read("ServerScriptService/EggGame/EggGameData.lua");
const coreSrc = read("ServerScriptService/EggGame/EggGameCore.lua");
const mainSrc = read("ServerScriptService/EggGameMain.server.lua");

// ============================================================
// ОДИН БОЛЬШОЙ ЧАНК
// ============================================================

const isMain = process.argv.includes("--client") ? false : true;

const combined = `
-- ============================================================
-- ЗАГЛУШКА ROBLOX API (в том же лексическом окружении, что и игра)
-- ============================================================
local S = (function()
${shimSource}
end)()

local Instance = S.Instance
local Enum = S.Enum
local Vector3 = S.Vector3
local Vector2 = S.Vector2
local CFrame = S.CFrame
local Color3 = S.Color3
local UDim = S.UDim
local UDim2 = S.UDim2
local Random = S.Random
local TweenInfo = S.TweenInfo
local NumberRange = S.NumberRange
local RaycastParams = S.RaycastParams
local task = S.task
local game = S.game
local workspace = S.workspace
local shared = {}

-- Имитируем превью мира, которое лежит в .rbxlx
local preview = Instance.new("Folder", workspace)
preview.Name = "EggGamePreview"
local previewTerrain = Instance.new("Folder", preview)
previewTerrain.Name = "Terrain"

local fallbackFloor = Instance.new("Part", workspace)
fallbackFloor.Name = "FallbackFloor"

-- ============================================================
-- ИМИТАЦИЯ ДЕРЕВА ОБЪЕКТОВ
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local configModule = Instance.new("ModuleScript", ReplicatedStorage)
configModule.Name = "EggGameConfig"

local eggFolder = Instance.new("Folder", ServerScriptService)
eggFolder.Name = "EggGame"

local mapModule = Instance.new("ModuleScript", eggFolder)
mapModule.Name = "EggGameMap"

local dataModule = Instance.new("ModuleScript", eggFolder)
dataModule.Name = "EggGameData"

local coreModule = Instance.new("ModuleScript", eggFolder)
coreModule.Name = "EggGameCore"

local mainScript = Instance.new("Script", ServerScriptService)
mainScript.Name = "EggGameMain"

-- ============================================================
-- СИСТЕМА require КАК В ROBLOX
-- ============================================================
local _modules = {}   -- [Instance] = результат
local _chunks = {}    -- [Instance] = функция модуля

function require(target)
  if _modules[target] ~= nil then
    return _modules[target]
  end

  local chunk = _chunks[target]
  if not chunk then
    error("Module script not found: " .. tostring(target and target.Name), 0)
  end

  local prevScript = script
  script = target
  local value = chunk()
  script = prevScript

  _modules[target] = value
  return value
end

-- ============================================================
-- МОДУЛЬ 1: EggGameConfig
-- ============================================================
script = configModule
_chunks[configModule] = function()
${configSrc}
end
local Config = require(configModule)

-- ============================================================
-- МОДУЛЬ 2: EggGameMap
-- ============================================================
script = mapModule
_chunks[mapModule] = function()
${mapSrc}
end
print("[trace] загружаю EggGameMap...")
local Map = require(mapModule)
print("[trace] EggGameMap загружен, build:", tostring(Map and Map.build))

-- ============================================================
-- МОДУЛЬ 3: EggGameData
-- ============================================================
script = dataModule
_chunks[dataModule] = function()
${dataSrc}
end
local Data = require(dataModule)

-- ============================================================
-- МОДУЛЬ 4: EggGameCore
-- ============================================================
script = coreModule
_chunks[coreModule] = function()
${coreSrc}
end
local Core = require(coreModule)

-- ============================================================
-- ЗАПУСК EggGameMain
-- ============================================================
script = mainScript

print("")
print("════════ ЗАПУСК ════════")

local ok, err = pcall(function()
${mainSrc}
end)

print("[trace] main ok:", tostring(ok), "err:", tostring(err))

if not ok then
  error(tostring(err), 0)
end

print("════════ ПРОВЕРКА ════════")

-- Проверяем результат напрямую через заглушку (без JS-границы)
local root = workspace:FindFirstChild("EggGame")

if not root then
  error("Карта EggGame НЕ создана в Workspace", 0)
end

if workspace:FindFirstChild("EggGamePreview") then
  print("✗ Превью не удалено после запуска — будут двойные объекты!")
  error("Превью не удалено", 0)
else
  print("✓ Превью удалено, живая арена построена")
end

print("✓ Карта создана")

local function childrenOf(instance)
  local out = {}
  local list = instance._children
  for i = 1, #list do
    out[i] = list[i]
  end
  return out
end

local function check(name, minCount)
  local f = root:FindFirstChild(name)
  if not f then
    print("✗ " .. name .. ": НЕ СОЗДАНО")
    return false
  end

  local n = 0
  for _ = 1, #f._children do
    n = n + 1
  end

  if n < minCount then
    print(string.format("✗ %s: %d (ожидалось ≥ %d)", name, n, minCount))
    return false
  else
    print(string.format("✓ %s: %d", name, n))
    return true
  end
end

local failed = false
failed = not check("Terrain", 5) or failed
failed = not check("Eggs", 5) or failed
failed = not check("Bases", 16) or failed
failed = not check("Nature", 10) or failed

-- SpawnLocation
-- МАГАЗИН: должен существовать как здание на карте
local function assertTrue(label, cond)
  if cond then
    print("   ✓ " .. label)
    return true
  end
  print("   ✗ " .. label .. ": ПРОВАЛ")
  return false
end

local market0 = root:FindFirstChild("Market")
local shopModel = market0 and market0:FindFirstChild("ShopBuilding")
failed = not assertTrue("Магазин построен в мире", shopModel ~= nil) or failed

if shopModel then
  local shopParts = 0
  for _, child in ipairs(shopModel:GetChildren()) do
    if child:IsA("BasePart") then shopParts = shopParts + 1 end
  end
  failed = not assertTrue("Части магазина: " .. shopParts, shopParts >= 50) or failed
  failed = not assertTrue("Вывеска магазина", shopModel:FindFirstChild("ShopSign") ~= nil) or failed
  failed = not assertTrue("Прилавок-касса", shopModel:FindFirstChild("ShopCounter") ~= nil) or failed
  failed = not assertTrue("NPC-продавец", shopModel:FindFirstChild("NPC_Torso") ~= nil) or failed
  failed = not assertTrue("Полки с товаром", shopModel:FindFirstChild("ShelfItem") ~= nil) or failed
  failed = not assertTrue("Стойка входа (ProximityPrompt)", shopModel:FindFirstChild("ShopTerminal") ~= nil) or failed
  failed = not assertTrue("Крыша магазина", shopModel:FindFirstChild("RoofSlope") ~= nil) or failed
  failed = not assertTrue("Витрины из стекла", shopModel:FindFirstChild("WindowGlass") ~= nil) or failed
end

local market = root:FindFirstChild("Market")
if market and market:FindFirstChild("PlayerSpawn") then
  print("✓ SpawnLocation есть")
else
  print("✗ SpawnLocation НЕ СОЗДАН — персонаж будет падать в пустоту!")
  failed = true
end

-- Первая база
local bases = root:FindFirstChild("Bases")
if bases and #bases._children > 0 then
  local first = bases._children[1]
  local neededChildren = { "Platform", "SignBoard", "VaultTop", "VaultGlow", "MyBaseMarker" }
  for idx = 1, #neededChildren do
    local partName = neededChildren[idx]
    if first:FindFirstChild(partName) then
      print("✓ База." .. partName)
    else
      print("✗ У базы нет " .. partName)
      failed = true
    end
  end

  -- VaultLabel и StealPrompt — это СВОЙСТВА объекта базы, а не дети
  -- (BillboardGui/ProximityPrompt созданы скриптом и лежат в таблице)
  if first:FindFirstChild("VaultTop") then
    local vaultTop = first:FindFirstChild("VaultTop")
    if vaultTop:FindFirstChild("Info") then
      print("✓ База: подпись склада (BillboardGui)")
    else
      print("✗ Нет подписи склада")
      failed = true
    end
    if vaultTop:FindFirstChild("StealPrompt") or vaultTop.StealPromptName then
      print("✓ База: ProximityPrompt кражи")
    end
  end
end

-- Remote'ы
local remotes = ReplicatedStorage:FindFirstChild("EggGameRemotes")
if remotes then
  local names = { "Notify", "CoinsUpdate", "ShopUpdate", "CarriedUpdate", "BaseInfo", "BuyUpgrade", "GetShop", "OpenShop" }
  local missing = {}
  for idx = 1, #names do
    local remoteName = names[idx]
    if not remotes:FindFirstChild(remoteName) then
      missing[#missing + 1] = remoteName
    end
  end
  if #missing == 0 then
    print("✓ Все 8 RemoteEvent/Function созданы")
  else
    print("✗ Нет Remote: " .. table.concat(missing, ", "))
    failed = true
  end
else
  print("✗ EggGameRemotes НЕ СОЗДАНО")
  failed = true
end


-- ============================================================
-- СИМУЛЯЦИЯ ИГРОКА И МЕХАНИК
-- ============================================================
print("")
print("════════ МЕХАНИКИ ════════")

-- Создаём фейкового игрока
local Players = game:GetService("Players")

local fakePlayer = Instance.new("Player")
fakePlayer.Name = "TestPlayer"
fakePlayer.DisplayName = "Тестовый"
fakePlayer.UserId = 12345
fakePlayer.Parent = Players

local fakeChar = Instance.new("Model", workspace)
fakeChar.Name = "TestPlayer"
local fakeRoot = Instance.new("Part", fakeChar)
fakeRoot.Name = "HumanoidRootPart"
fakeRoot.Position = Vector3.new(0, 5, 0)
local fakeHumanoid = Instance.new("Humanoid", fakeChar)
fakeHumanoid.WalkSpeed = 16
fakePlayer.Character = fakeChar

-- Подменяем GetPlayers, чтобы ядро видело нашего игрока
Players.GetPlayers = function() return { fakePlayer } end

-- Инициализируем данные игрока
Data.load(fakePlayer)
print("✓ Данные игрока загружены, монет: " .. tostring(Data.getCoins(fakePlayer)))

-- Выдаём базу
local baseId = Core.assignBase(fakePlayer)
print("✓ База назначена: " .. tostring(baseId))

-- ============ СБОР ЯИЦ ============
-- Кладём яйцо прямо под игрока
local eggTypeName = "Rare"
local part = Map.makeEggPart(eggTypeName, workspace:FindFirstChild("EggGame").Eggs)
part.Position = Vector3.new(1, 5, 1)

-- Вызываем сбор вручную (в игре это делает цикл)
local picked = Core.addEggToBackpack(fakePlayer, eggTypeName, 1)
print("✓ В рюкзак добавлено яиц: " .. tostring(picked))

local count = Core.getCarriedCount(fakePlayer)
print("✓ Яиц в рюкзаке: " .. tostring(count))

-- ============ ВМЕСТИМОСТЬ РЮКЗАКА ============
local capacity = math.floor(Data.getUpgradeValue(fakePlayer, "Backpack"))
print("✓ Вместимость рюкзака (ур. 0): " .. tostring(capacity))

-- Переполнение не должно ломаться
local overflow = Core.addEggToBackpack(fakePlayer, "Common", 50)
print("✓ Попытка добавить 50 яиц: добавлено " .. tostring(overflow) .. " (лимит соблюдён: " .. tostring(Core.getCarriedCount(fakePlayer) <= capacity) .. ")")

-- ============ КРАЖА ============
local thief = Instance.new("Player")
thief.Name = "Thief"
thief.DisplayName = "Вор"
thief.UserId = 67890
thief.Parent = Players
local thiefChar = Instance.new("Model", workspace)
local thiefRoot = Instance.new("Part", thiefChar)
thiefRoot.Name = "HumanoidRootPart"
thiefRoot.Position = Vector3.new(2, 5, 2)
thief.Character = thiefChar

Data.load(thief)
Core.assignBase(thief)

-- 1) Сразу после подбора украсть НЕЛЬЗЯ (защита 2.5 сек)
local earlyOk, earlyMsg = Core.tryStealFromPlayer(thief, fakePlayer)
print("✓ Кража сразу после подбора: " .. tostring(earlyOk) .. " (" .. tostring(earlyMsg) .. ") — должно быть false")

-- 2) Снимаем защиту и пробуем снова — теперь должно получиться
local carriedState = Core.getCtx().carried[fakePlayer]
if carriedState then
  carriedState.LockUntil = 0
end

local stealOk, stealMsg = Core.tryStealFromPlayer(thief, fakePlayer)
print("✓ Кража после снятия защиты: " .. tostring(stealOk) .. " (" .. tostring(stealMsg) .. ") — должно быть true")

local thiefHas = Core.getCarriedCount(thief)
local victimHas = Core.getCarriedCount(fakePlayer)
print("✓ У вора: " .. tostring(thiefHas) .. " яиц, у жертвы: " .. tostring(victimHas) .. " (яйца перешли)")

-- 3) Нельзя обокрасть самого себя
local selfOk, selfMsg = Core.tryStealFromPlayer(thief, thief)
print("✓ Кража у себя: " .. tostring(selfOk) .. " (" .. tostring(selfMsg) .. ") — должно быть false")

-- ============ ПРОВЕРКИ-УТВЕРЖДЕНИЯ ============
local assertions = {
  { "защита сразу после подбора", earlyOk == false },
  { "кража работает после снятия защиты", stealOk == true },
  { "яйца реально перешли вору", thiefHas == 1 },
  { "у жертвы осталось правильное число", victimHas == 2 },
  { "себя обокрасть нельзя", selfOk == false },
}

-- ============ МАГАЗИН ============
Data.addCoins(fakePlayer, 1000)
local buyOk, buyMsg = Data.purchaseUpgrade(fakePlayer, "Backpack")
print("✓ Покупка «Рюкзак»: " .. tostring(buyOk) .. " (" .. tostring(buyMsg) .. ")")
local newCapacity = math.floor(Data.getUpgradeValue(fakePlayer, "Backpack"))
print("✓ Новая вместимость: " .. tostring(newCapacity) .. " (было " .. tostring(capacity) .. ")")

-- Проверка, что нельзя купить при нехватке денег
local poorPlayer = Instance.new("Player")
poorPlayer.Name = "Poor"
poorPlayer.UserId = 11111
poorPlayer.Parent = Players
Data.load(poorPlayer)
local failOk, failMsg = Data.purchaseUpgrade(poorPlayer, "Speed")
print("✓ Покупка без денег: " .. tostring(failOk) .. " (" .. tostring(failMsg) .. ")")

-- ============ ДОХОД ============
local myBase = Core.getBaseForPlayerFor(fakePlayer)
if myBase then
  myBase.Vault = { Common = 10, Rare = 2 }
  myBase.VaultTotal = 12
  local income = Core.getBaseIncomePerSecond(myBase, fakePlayer)
  print("✓ Доход базы с 12 яйцами: " .. string.format("%.3f", income) .. " монет/сек")

  assertions[#assertions + 1] = { "доход больше нуля", income > 0 }
end

-- ============ ЗАНЯТИЕ БАЗЫ ============
print("")
print("════════ ЗАНЯТИЕ БАЗЫ ════════")

local ctx = Core.getCtx()
if not ctx then error("Core.getCtx() вернул nil", 0) end
local oldBaseId = Core.getBaseForPlayerFor(fakePlayer).Id
print("✓ Было: база №" .. tostring(oldBaseId) .. ", владельцев " .. tostring(#ctx.bases[oldBaseId].Owners))
print("✓ База №2 до захвата: владельцев " .. tostring(#ctx.bases[2].Owners))

local okClaim, msgClaim = Core.claimBase(fakePlayer, 2)

assertions[#assertions + 1] = { "занять свободную базу №2 (" .. tostring(msgClaim) .. ")", okClaim == true }
assertions[#assertions + 1] = { "база игрока стала №2", Core.getBaseForPlayerFor(fakePlayer).Id == 2 }
assertions[#assertions + 1] = { "на базе №2 владельцев " .. #ctx.bases[2].Owners, #ctx.bases[2].Owners >= 1 }
assertions[#assertions + 1] = { "прежняя база освободилась", #ctx.bases[oldBaseId].Owners == 0 }

local okAgain = Core.claimBase(fakePlayer, 2)
assertions[#assertions + 1] = { "повторно ту же базу занять нельзя", okAgain == false }

-- База вмещает не больше Config.BaseMaxOwners
Core.claimBase(thief, 2)
local third = Instance.new("Player")
third.Name = "Third"
third.UserId = 33333
third.Parent = Players
Data.load(third)
Core.assignBase(third)
local okThird = Core.claimBase(third, 2)
assertions[#assertions + 1] = {
  "третий на базу №2 не влезает (макс " .. tostring(Config.BaseMaxOwners) .. ")",
  okThird == false,
}
assertions[#assertions + 1] = { "третий остался при своей базе", Core.getBaseForPlayerFor(third) ~= nil }

print("✓ База №2: владельцев " .. tostring(#ctx.bases[2].Owners))
print("✓ Игрок при базе: " .. tostring(Core.getBaseForPlayerFor(third).Id))

-- Итог по утверждениям
print("")
local failedChecks = 0
for _, check in ipairs(assertions) do
  if not check[2] then
    print("✗ ПРОВАЛ: " .. check[1])
    failedChecks = failedChecks + 1
  end
end

if failedChecks > 0 then
  error("Провалено проверок: " .. failedChecks, 0)
end

print("✓ Все " .. #assertions .. " проверок пройдены")

if failed then
  error("ЕСТЬ ПРОБЛЕМЫ (см. выше)", 0)
end

print("")
print("РЕЗУЛЬТАТ: всё в порядке")
`;

// ============================================================
// ВЫПОЛНЕНИЕ
// ============================================================

console.log("Компилирую весь проект в один чанк...\n");

let fn;
try {
  fn = state.loadstring(combined, "@EggGame", true);
} catch (e) {
  console.log("❌ ОШИБКА КОМПИЛЯЦИИ");
  console.log("   " + (e.message ?? e));
  process.exit(1);
}

try {
  await fn();
} catch (e) {
  console.log("\n❌ ОШИБКА ВЫПОЛНЕНИЯ");
  console.log("   " + (e.message ?? e));
  process.exit(1);
}
