--[[
	EggGameConfig — все числа баланса игры в одном месте.
	Хочешь игру быстрее/медленнее, дороже/дешевле — меняй только этот файл.

	Место в Studio: ReplicatedStorage -> ModuleScript с именем "EggGameConfig"
]]

local Config = {}

-- ===================== ЯЙЦА =====================

-- Сколько яиц одновременно лежит на рынке в центре карты
Config.MaxGroundEggs = 40

-- Как часто (в секундах) рынок пополняется новым яйцом
Config.SpawnInterval = 0.85

-- Сколько секунд яйца в рюкзаке нельзя украсть сразу после подбора
-- (чтобы вор не отбирал только что собранное)
Config.StealLockTime = 2.5

-- Размер и расположение стопки яиц над головой
Config.StackBaseHeight = 3.4   -- на сколько выше головы начинается стопка
Config.StackHeight = 1.85      -- расстояние между рядами
Config.StackBackOffset = 1.2   -- сдвиг назад от центра персонажа
Config.StackSpread = 1.55      -- расстояние между яйцами в ряду
Config.StackColumns = 3        -- яиц в ряду
Config.MaxVisibleStack = 15    -- больше не рисуем (остальные невидимы)

-- Во сколько раз уменьшаем яйцо в стопке и на складе
Config.CarriedEggScale = 0.7
Config.VaultEggScale = 0.55

-- Типы яиц: Weight — шанс выпадения, Value — цена и «сила» дохода
Config.EggTypes = {
	Common = {
		DisplayName = "Обычное",
		Weight = 70,
		Value = 1,
		Color = Color3.fromRGB(255, 245, 220),
		Size = Vector3.new(2.1, 2.1, 2.1),
		Rarity = Color3.fromRGB(235, 235, 235),
	},
	Rare = {
		DisplayName = "Редкое",
		Weight = 20,
		Value = 5,
		Color = Color3.fromRGB(110, 190, 255),
		Size = Vector3.new(2.2, 2.2, 2.2),
		Rarity = Color3.fromRGB(90, 170, 255),
	},
	Epic = {
		DisplayName = "Эпическое",
		Weight = 8,
		Value = 20,
		Color = Color3.fromRGB(185, 115, 255),
		Size = Vector3.new(2.35, 2.35, 2.35),
		Rarity = Color3.fromRGB(170, 90, 255),
	},
	Legendary = {
		DisplayName = "Легендарное",
		Weight = 2,
		Value = 100,
		Color = Color3.fromRGB(255, 190, 40),
		Size = Vector3.new(2.6, 2.6, 2.6),
		Rarity = Color3.fromRGB(255, 170, 30),
	},
}

-- ===================== КАРТА =====================

Config.ArenaSize = 340
Config.MarketRadius = 34
Config.BasesCount = 16
Config.BaseRingRadius = 116
Config.BaseZoneRadius = 14

-- ===================== ПОДБОР / КРАЖА =====================

-- Базовый радиус подбора яйца
Config.PickupRadius = 7


-- Пауза между кражами у одного игрока
Config.StealCooldown = 1.5

-- Сколько секунд держать кнопку, чтобы обокрасть другого игрока
Config.PlayerStealHoldTime = 0.9

-- Сколько секунд держать кнопку, чтобы обокрасть базу
Config.RaidHoldTime = 1.4

-- Урон/отбрасывание вора? нет — просто отбираем яйца

-- ===================== ЭКОНОМИКА =====================

-- Доход одного яйца в секунду = Value * IncomeRate
Config.IncomeRate = 0.14

-- Сколько секунд уходит на «занос» одного яйца в склад
Config.DepositTime = 0.22

-- Начальный капитал
Config.StartingCoins = 0


-- Начальная вместимость склада (без улучшений)
Config.VaultCapacityBase = 20

-- Вместимость склада при общем владении делится? нет — общая на базу

-- ===================== УЛУЧШЕНИЯ =====================

Config.Upgrades = {
	Backpack = {
		DisplayName = "Рюкзак",
		Description = "Больше яиц помещается за спиной",
		Icon = "🎒",
		BaseCost = 25,
		CostGrowth = 1.55,
		MaxLevel = 10,
		BaseValue = 3,
		PerLevel = 2,
		Unit = "яиц",
	},
	Speed = {
		DisplayName = "Скорость",
		Description = "Быстрее бегаешь — сложнее догнать",
		Icon = "⚡",
		BaseCost = 40,
		CostGrowth = 1.7,
		MaxLevel = 8,
		BaseValue = 16,
		PerLevel = 1.3,
		Unit = "",
	},
	Magnet = {
		DisplayName = "Магнит",
		Description = "Яйца подбираются с большего расстояния",
		Icon = "🧲",
		BaseCost = 60,
		CostGrowth = 1.8,
		MaxLevel = 6,
		BaseValue = 0,
		PerLevel = 1.7,
		Unit = "",
	},
	Steal = {
		DisplayName = "Ловкость",
		Description = "За одну кражу уносишь больше яиц",
		Icon = "🥷",
		BaseCost = 90,
		CostGrowth = 1.9,
		MaxLevel = 5,
		BaseValue = 1,
		PerLevel = 1,
		Unit = "яиц",
	},
	Vault = {
		DisplayName = "Склад",
		Description = "На базе помещается больше яиц",
		Icon = "🏦",
		BaseCost = 100,
		CostGrowth = 1.85,
		MaxLevel = 8,
		BaseValue = 20,
		PerLevel = 15,
		Unit = "яиц",
	},
	Income = {
		DisplayName = "Доход",
		Description = "Каждое яйцо на складе приносит больше",
		Icon = "💎",
		BaseCost = 120,
		CostGrowth = 1.95,
		MaxLevel = 8,
		BaseValue = 1,
		PerLevel = 0.2,
		Unit = "x",
	},
}

-- ===================== ПРОЧЕЕ =====================

Config.SaveFolder = "EggGamePlayerData"
Config.DataVersion = 1
Config.AutosaveInterval = 90

Config.Colors = {
	Floor = Color3.fromRGB(58, 66, 82),
	Wall = Color3.fromRGB(38, 44, 56),
	Market = Color3.fromRGB(255, 170, 60),
	MyBase = Color3.fromRGB(70, 230, 140),
	FreeBase = Color3.fromRGB(150, 160, 175),
	Vault = Color3.fromRGB(255, 205, 90),
	Text = Color3.fromRGB(255, 255, 255),
}

return Config
