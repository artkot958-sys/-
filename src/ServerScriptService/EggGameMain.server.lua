--[[
	EggGameMain — точка входа сервера.

	Место в Studio: ServerScriptService -> Script с именем "EggGameMain"
	ВАЖНО: это обычный Script (с иконкой «пьедестала»), а не LocalScript.

	Порядок работы:
	  1. Строит карту (EggGameMap)
	  2. Создаёт RemoteEvent'ы для клиента
	  3. Подключает игроков: данные, база, магазин
	  4. Запускает игровые циклы (EggGameCore)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("EggGameConfig"))
local Map = require(script.Parent:WaitForChild("EggGameMap"))
local Data = require(script.Parent:WaitForChild("EggGameData"))
local Core = require(script.Parent:WaitForChild("EggGameCore"))

-- ============================================================
-- 1. КАРТА
-- ============================================================

local mapData = Map.build()

-- ============================================================
-- 2. REMOTES
-- ============================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("EggGameRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "EggGameRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemote(className, name)
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local remotes = {
	Notify = ensureRemote("RemoteEvent", "Notify"),
	CoinsUpdate = ensureRemote("RemoteEvent", "CoinsUpdate"),
	ShopUpdate = ensureRemote("RemoteEvent", "ShopUpdate"),
	CarriedUpdate = ensureRemote("RemoteEvent", "CarriedUpdate"),
	BaseInfo = ensureRemote("RemoteEvent", "BaseInfo"),
	BuyUpgrade = ensureRemote("RemoteFunction", "BuyUpgrade"),
	GetShop = ensureRemote("RemoteFunction", "GetShop"),
}

-- ============================================================
-- 3. ИГРОВАЯ ЛОГИКА
-- ============================================================

Core.init(mapData, remotes)

-- ============================================================
-- 4. МАГАЗИН
-- ============================================================

local function buildShopPayload(player)
	local entries = {}

	for upgradeName, upgradeConfig in pairs(Config.Upgrades) do
		table.insert(entries, {
			Name = upgradeName,
			DisplayName = upgradeConfig.DisplayName,
			Description = upgradeConfig.Description,
			Icon = upgradeConfig.Icon,
			Level = Data.getLevel(player, upgradeName),
			MaxLevel = upgradeConfig.MaxLevel,
			Cost = Data.getUpgradeCost(player, upgradeName),
			Value = Data.getUpgradeValue(player, upgradeName),
			Unit = upgradeConfig.Unit,
		})
	end

	table.sort(entries, function(a, b)
		local aCost = a.Cost or math.huge
		local bCost = b.Cost or math.huge
		if aCost == bCost then
			return a.DisplayName < b.DisplayName
		end
		return aCost < bCost
	end)

	return {
		Coins = Data.getCoins(player),
		Upgrades = entries,
	}
end

-- Обновление магазина на клиенте

local function syncShop(player)
	local remote = remotes.ShopUpdate
	if not remote or not player.Parent then
		return
	end
	if not Data.isLoaded(player) then
		return
	end
	remote:FireClient(player, buildShopPayload(player).Upgrades, Data.getCoins(player))
end

remotes.GetShop.OnServerInvoke = function(player)
	if not Data.isLoaded(player) then
		return nil
	end
	return buildShopPayload(player)
end

remotes.BuyUpgrade.OnServerInvoke = function(player, upgradeName)
	if type(upgradeName) ~= "string" then
		return false, "Неверный запрос"
	end

	if not Data.isLoaded(player) then
		return false, "Данные ещё грузятся"
	end

	local success, message = Data.purchaseUpgrade(player, upgradeName)

	if success then
		Core.syncCoins(player)
		Core.syncCarried(player)
		Core.syncBaseInfo(player)
		syncShop(player)
	else
		Core.notify(player, message, Color3.fromRGB(255, 140, 120))
	end

	return success, message
end

-- ============================================================
-- 5. ИГРОКИ
-- ============================================================

local function setupPlayer(player)
	Data.load(player)

	-- База
	Core.assignBase(player)

	-- Персонаж
	local function onCharacter(character)
		Core.onCharacterAdded(player, character)
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Отправляем стартовое состояние на клиент
	task.delay(0.6, function()
		if not player.Parent then
			return
		end
		Core.syncCoins(player)
		Core.syncCarried(player)
		Core.syncBaseInfo(player)
		syncShop(player)
		Core.notify(player, "Собирай яйца на рынке и неси на свою базу! 🥚", Color3.fromRGB(150, 230, 255))
	end)

	-- Периодическое обновление интерфейса
	task.spawn(function()
		while player.Parent do
			task.wait(1)
			if Data.isLoaded(player) then
				Core.syncCoins(player)
				Core.syncBaseInfo(player)
			end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	Core.cleanupPlayer(player)
	Data.release(player)
end)

-- Сохраняем всё при закрытии сервера
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			Data.save(player, true)
		end)
	end
	task.wait(2)
end)

Data.startAutosave()

-- ============================================================
-- 6. ОТЧЁТ В OUTPUT
-- ============================================================

print("================================================")
print("[EggGame] Сервер запущен")
print(string.format("[EggGame] Баз: %d | Яиц на рынке: %d", #mapData.BasesData, Config.MaxGroundEggs))
print("[EggGame] Сохранение: " .. (Data.isStoreAvailable() and "ВКЛЮЧЕНО" or "ВЫКЛЮЧЕНО (Studio -> Enable Studio Access to API Services)"))
print("================================================")
