/**
 * Полная симуляция запуска игры: дерево объектов Roblox + реальный Lua.
 *
 * Запускает EggGameMain точно так же, как это сделал бы Roblox,
 * и сообщает об ошибках. Именно так ловятся баги, из-за которых
 * карта не строится.
 *
 * Запуск: node tools/simulate.js
 */

const fs = require("fs");
const path = require("path");
const { lauxlib, lualib, lua, to_luastring } = require("fengari");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");

const shim = fs.readFileSync(path.join(ROOT, "tools", "roblox-shim.lua"), "utf8");

const sources = {
  EggGameConfig: fs.readFileSync(path.join(SRC, "ReplicatedStorage/EggGameConfig.lua"), "utf8"),
  EggGameMap: fs.readFileSync(path.join(SRC, "ServerScriptService/EggGame/EggGameMap.lua"), "utf8"),
  EggGameData: fs.readFileSync(path.join(SRC, "ServerScriptService/EggGame/EggGameData.lua"), "utf8"),
  EggGameCore: fs.readFileSync(path.join(SRC, "ServerScriptService/EggGame/EggGameCore.lua"), "utf8"),
  EggGameMain: fs.readFileSync(path.join(SRC, "ServerScriptService/EggGameMain.server.lua"), "utf8"),
};

// ============================================================
// LUA-ОБВЯЗКА
// ============================================================

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function runLua(name, code) {
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (status !== 0) {
    const err = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    console.log(`\n❌ ОШИБКА (${name}):\n   ${err}\n`);
    return { ok: false, error: err };
  }
  return { ok: true };
}

// ============================================================
// 1. ЗАГЛУШКА ROBLOX
// ============================================================

let result = runLua("roblox-shim.lua", shim);
if (!result.ok) process.exit(1);

// ============================================================
// 2. СТРОИМ ДЕРЕВО ОБЪЕКТОВ КАК В STUDIO
// ============================================================

const treeSetup = `
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ReplicatedStorage.EggGameConfig
local configModule = Instance.new("ModuleScript", ReplicatedStorage)
configModule.Name = "EggGameConfig"

-- ServerScriptService.EggGame (папка с тремя модулями)
local eggFolder = Instance.new("Folder", ServerScriptService)
eggFolder.Name = "EggGame"

local mapModule = Instance.new("ModuleScript", eggFolder)
mapModule.Name = "EggGameMap"

local dataModule = Instance.new("ModuleScript", eggFolder)
dataModule.Name = "EggGameData"

local coreModule = Instance.new("ModuleScript", eggFolder)
coreModule.Name = "EggGameCore"

-- ServerScriptService.EggGameMain
local mainScript = Instance.new("Script", ServerScriptService)
mainScript.Name = "EggGameMain"

-- Сохраняем ссылки для JS
_G.__tree = {
  config = configModule,
  folder = eggFolder,
  map = mapModule,
  data = dataModule,
  core = coreModule,
  main = mainScript,
}
_G.__modules = {}
_G.__cache = {}
`;

result = runLua("дерево объектов", treeSetup);
if (!result.ok) process.exit(1);

// ============================================================
// 3. РЕГИСТРИРУЕМ КОД МОДУЛЕЙ И ПОДМЕНЯЕМ require
// ============================================================

// Каждый модуль грузим отдельно, чтобы `script` указывал на него
const moduleNames = ["EggGameConfig", "EggGameMap", "EggGameData", "EggGameCore"];

for (const name of moduleNames) {
  const source = sources[name];
  const key = `__chunk_${name}`;

  // Оборачиваем исходник в функцию и сохраняем её в Lua-таблицу
  const loadCode = `
_G.__chunks = _G.__chunks or {}
_G.__chunks[${JSON.stringify(name)}] = function()
${source}
end
`;

  const loaded = runLua(`компиляция ${name}`, loadCode);
  if (!loaded.ok) {
    console.log(`   ^ ошибка компиляции модуля ${name}`);
    process.exit(1);
  }
}

const requireShim = `
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local tree = _G.__tree
local cache = _G.__cache
local chunks = _G.__chunks

-- require(instance) -> выполняет модуль с правильным script
function require(target)
  if type(target) == "string" then
    return nil
  end

  local existing = cache[target]
  if existing ~= nil then
    return existing
  end

  local name = target.Name
  local chunk = chunks[name]
  if not chunk then
    error("Module not found: " .. tostring(name))
  end

  -- подменяем глобальный script на этот модуль
  local prevScript = _G.script
  _G.script = target

  local ok, value = pcall(chunk)

  _G.script = prevScript

  if not ok then
    error("Ошибка в модуле " .. name .. ": " .. tostring(value))
  end

  cache[target] = value
  return value
end
`;

result = runLua("require", requireShim);
if (!result.ok) process.exit(1);

// ============================================================
// 4. ЗАПУСКАЕМ EggGameMain
// ============================================================

const mainCode = `
local tree = _G.__tree
_G.script = tree.main

print("")
print("=== ЗАПУСК EggGameMain ===")
print("")

local ok, err = pcall(function()
${sources.EggGameMain}
end)

if not ok then
  error(err, 0)
end
`;

result = runLua("EggGameMain", mainCode);

if (!result.ok) {
  console.log("────────── ДИАГНОЗ ──────────");
  console.log("Игра падает при запуске. Это и есть причина,");
  console.log("по которой карта не строится.");
  process.exit(1);
}

// ============================================================
// 5. ПРОВЕРЯЕМ, ЧТО КАРТА РЕАЛЬНО ПОСТРОИЛАСЬ
// ============================================================

const verification = `
local workspace = game:GetService("Workspace")
local egg = workspace:FindFirstChild("EggGame")

print("")
print("=== ПРОВЕРКА РЕЗУЛЬТАТА ===")

if not egg then
  error("Карта EggGame не создана!")
end

local function count(folderName)
  local f = egg:FindFirstChild(folderName)
  if not f then return 0 end
  return #f:GetChildren()
end

print(string.format("  Частей в Arena:      %d", count("Arena")))
print(string.format("  Яиц на рынке:        %d", count("Eggs")))
print(string.format("  Баз:                 %d", count("Bases")))
print(string.format("  Деревьев:            %d", count("Nature")))

local bases = egg:FindFirstChild("Bases")
if bases and #bases:GetChildren() > 0 then
  local first = bases:GetChildren()[1]
  print("  Первая база: " .. first.Name)
  local platform = first:FindFirstChild("Platform")
  if platform then
    print("    ✓ площадка на месте (позиция " .. tostring(platform.Position) .. ")")
  else
    print("    ✗ НЕТ площадки!")
  end
  if first:FindFirstChild("SignBoard") then
    print("    ✓ вывеска на месте")
  else
    print("    ✗ НЕТ вывески!")
  end
  if first:FindFirstChild("VaultTop") then
    print("    ✓ склад на месте")
  else
    print("    ✗ НЕТ склада!")
  end
end

-- спвн-локация
local market = egg:FindFirstChild("Market")
local spawn = market and market:FindFirstChild("PlayerSpawn")
if spawn then
  print("  ✓ SpawnLocation есть: " .. tostring(spawn.Position))
else
  print("  ✗ SpawnLocation НЕ СОЗДАН — игрок будет падать в пустоту!")
end
`;

result = runLua("проверка результата", verification);

if (result.ok) {
  console.log("");
  console.log("✅ Симуляция прошла: игра запускается и строит карту.");
} else {
  process.exit(1);
}
