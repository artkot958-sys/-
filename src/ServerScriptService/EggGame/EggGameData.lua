--[[
	EggGameData — данные игроков, сохранение и покупка улучшений.

	Место в Studio: ServerScriptService -> ModuleScript "EggGameData"

	Внутри хранит таблицу:
	{
		Coins = 0,
		TotalEarned = 0,
		EggsCollected = 0,
		EggsStolen = 0,
		EggsLost = 0,
		Levels = { Backpack = 0, Speed = 0, Magnet = 0, Steal = 0, Vault = 0, Income = 0 },
	}
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("EggGameConfig"))

local Data = {}

local store = nil
local storeBlocked = false

local cache = {}       -- [Player] = data
local loaded = {}      -- [Player] = true

-- ============================================================
-- ХРАНИЛИЩЕ
-- ============================================================

local function getStore()
	if store then
		return store
	end
	if storeBlocked then
		return nil
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.SaveFolder)
	end)

	if ok and result then
		store = result
		return store
	end

	storeBlocked = true
	warn("[EggGame] DataStore недоступен — прогресс не сохраняется. " ..
		"В Studio включи Game Settings -> Security -> Enable Studio Access to API Services. Ошибка: " .. tostring(result))
	return nil
end

local function defaultData()
	local levels = {}
	for upgradeName in pairs(Config.Upgrades) do
		levels[upgradeName] = 0
	end

	return {
		Coins = Config.StartingCoins,
		TotalEarned = 0,
		EggsCollected = 0,
		EggsStolen = 0,
		EggsLost = 0,
		BaseId = nil,
		Levels = levels,
	}
end

-- Приводим сохранение к актуальной схеме, защищаемся от мусора в данных
local function sanitize(raw)
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end

	data.Coins = math.clamp(tonumber(raw.Coins) or 0, 0, 1e12)
	data.TotalEarned = math.max(0, tonumber(raw.TotalEarned) or 0)
	data.EggsCollected = math.max(0, tonumber(raw.EggsCollected) or 0)
	data.EggsStolen = math.max(0, tonumber(raw.EggsStolen) or 0)
	data.EggsLost = math.max(0, tonumber(raw.EggsLost) or 0)

	if raw.BaseId ~= nil then
		local baseId = math.floor(tonumber(raw.BaseId) or 0)
		if baseId >= 1 and baseId <= Config.BasesCount then
			data.BaseId = baseId
		end
	end

	if type(raw.Levels) == "table" then
		for upgradeName, upgradeConfig in pairs(Config.Upgrades) do
			local level = math.floor(tonumber(raw.Levels[upgradeName]) or 0)
			data.Levels[upgradeName] = math.clamp(level, 0, upgradeConfig.MaxLevel)
		end
	end

	return data
end

-- ============================================================
-- БАЗОВЫЕ ОПЕРАЦИИ
-- ============================================================

function Data.get(player)
	return cache[player]
end

function Data.isLoaded(player)
	return loaded[player] == true
end

function Data.getCoins(player)
	local data = cache[player]
	return data and data.Coins or 0
end

function Data.addCoins(player, amount)
	local data = cache[player]
	if not data then
		return
	end
	data.Coins = math.max(0, data.Coins + amount)
	if amount > 0 then
		data.TotalEarned += amount
	end
end

function Data.addStat(player, statName, amount)
	local data = cache[player]
	if not data or type(data[statName]) ~= "number" then
		return
	end
	data[statName] += amount
end

function Data.getLevel(player, upgradeName)
	local data = cache[player]
	if not data then
		return 0
	end
	return data.Levels[upgradeName] or 0
end

-- Итоговое значение улучшения по его текущему уровню
function Data.getUpgradeValue(player, upgradeName)
	local upgradeConfig = Config.Upgrades[upgradeName]
	if not upgradeConfig then
		return 0
	end
	return upgradeConfig.BaseValue + Data.getLevel(player, upgradeName) * upgradeConfig.PerLevel
end

-- Цена следующего уровня (nil, если уже максимум)
function Data.getUpgradeCost(player, upgradeName)
	local upgradeConfig = Config.Upgrades[upgradeName]
	if not upgradeConfig then
		return nil
	end

	local level = Data.getLevel(player, upgradeName)
	if level >= upgradeConfig.MaxLevel then
		return nil
	end

	return math.floor(upgradeConfig.BaseCost * (upgradeConfig.CostGrowth ^ level) + 0.5)
end

-- Возвращает success, message
function Data.purchaseUpgrade(player, upgradeName)
	local upgradeConfig = Config.Upgrades[upgradeName]
	if not upgradeConfig then
		return false, "Такого улучшения нет"
	end

	local data = cache[player]
	if not data then
		return false, "Данные ещё грузятся"
	end

	local level = data.Levels[upgradeName] or 0
	if level >= upgradeConfig.MaxLevel then
		return false, "Уже максимальный уровень"
	end

	local cost = Data.getUpgradeCost(player, upgradeName)
	if not cost then
		return false, "Уже максимальный уровень"
	end

	if data.Coins < cost then
		return false, "Не хватает монет"
	end

	data.Coins -= cost
	data.Levels[upgradeName] = level + 1

	return true, "Куплено: " .. upgradeConfig.DisplayName
end

-- ============================================================
-- ЗАГРУЗКА И СОХРАНЕНИЕ
-- ============================================================

function Data.load(player)
	local data = nil
	local targetStore = getStore()

	if targetStore then
		local key = "Player_" .. tostring(player.UserId)
		local ok, result = pcall(function()
			return targetStore:GetAsync(key)
		end)

		if ok then
			data = sanitize(result)
		else
			warn("[EggGame] Ошибка загрузки данных " .. player.Name .. ": " .. tostring(result))
		end
	end

	cache[player] = data or defaultData()
	loaded[player] = true

	return cache[player]
end

function Data.save(player, isFinal)
	local data = cache[player]
	if not data then
		return
	end

	local targetStore = getStore()
	if not targetStore then
		return
	end

	local payload = {
		Coins = data.Coins,
		TotalEarned = data.TotalEarned,
		EggsCollected = data.EggsCollected,
		EggsStolen = data.EggsStolen,
		EggsLost = data.EggsLost,
		BaseId = data.BaseId,
		Levels = data.Levels,
		DataVersion = Config.DataVersion,
	}

	local key = "Player_" .. tostring(player.UserId)

	local ok, result = pcall(function()
		return targetStore:UpdateAsync(key, function()
			return payload
		end)
	end)

	if not ok then
		warn("[EggGame] Ошибка сохранения данных " .. player.Name .. ": " .. tostring(result))
	end
end

function Data.release(player)
	Data.save(player, true)
	cache[player] = nil
	loaded[player] = nil
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in pairs(cache) do
				if player.Parent then
					task.spawn(function()
						Data.save(player)
					end)
				end
			end
		end
	end)
end

function Data.isStoreAvailable()
	return getStore() ~= nil
end

return Data
