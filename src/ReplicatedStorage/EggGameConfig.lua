--[[
	EggGameConfig — все числа баланса игры в одном месте.
	Хочешь игру быстрее/медленнее, дороже/дешевле — меняй только этот файл.

	Место в Studio: ReplicatedStorage -> ModuleScript с именем "EggGameConfig"
]]

local Config = {}

-- ===================== ЯЙЦА =====================

--[[
	СИСТЕМА ПОЛУЧЕНИЯ ЯИЦ
	Раньше яйца просто валялись по карте. Теперь их добывают кликером:
	подходишь к гнезду и жмёшь E (или тапаешь в интерфейсе).
]]
Config.MaxGroundEggs = 0   -- разбросанные яйца отключены
Config.SpawnInterval = 999 -- (не используется, оставлено для совместимости)

-- ===================== КЛИКЕР =====================

-- Сколько гнёзд-кликеров стоит на рынке
Config.NestsCount = 6

-- Удары по гнезду: сколько нужно кликнуть, чтобы выпало яйцо
Config.NestHitsPerEgg = 1

-- Пауза между кликами по одному гнезду (секунды)
Config.NestCooldown = 0.12

-- Радиус, в котором работает клик по гнезду
Config.NestRange = 18

-- Бонус за серию кликов подряд (комбо)
Config.ComboWindow = 1.6      -- сколько ждать между кликами, чтобы серия жила
Config.ComboStep = 0.06       -- +6% к шансу редкого за каждый клик серии
Config.ComboMax = 2.5         -- максимум +150%

-- Шанс, что клик выбьет яйцо выше обычного (сверх обычного веса)
Config.CritChance = 0.05
Config.CritMultiplier = 3

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

--[[
	Типы яиц. Weight — относительный шанс, Value — цена и сила дохода.
	Чем реже — тем дороже и ярче. Раскраска идёт по полю Color.
]]
Config.EggTypes = {
	Common = {
		DisplayName = "Обычное",
		Weight = 5000,
		Value = 1,
		Color = Color3.fromRGB(255, 245, 220),
		Size = Vector3.new(2.1, 2.1, 2.1),
		Rarity = Color3.fromRGB(235, 235, 235),
		Glow = false,
	},
	Uncommon = {
		DisplayName = "Необычное",
		Weight = 2600,
		Value = 3,
		Color = Color3.fromRGB(140, 235, 140),
		Size = Vector3.new(2.15, 2.15, 2.15),
		Rarity = Color3.fromRGB(120, 220, 120),
		Glow = false,
	},
	Rare = {
		DisplayName = "Редкое",
		Weight = 1400,
		Value = 8,
		Color = Color3.fromRGB(110, 190, 255),
		Size = Vector3.new(2.2, 2.2, 2.2),
		Rarity = Color3.fromRGB(90, 170, 255),
		Glow = false,
	},
	Epic = {
		DisplayName = "Эпическое",
		Weight = 700,
		Value = 25,
		Color = Color3.fromRGB(185, 115, 255),
		Size = Vector3.new(2.35, 2.35, 2.35),
		Rarity = Color3.fromRGB(170, 90, 255),
		Glow = true,
	},
	Legendary = {
		DisplayName = "Легендарное",
		Weight = 220,
		Value = 90,
		Color = Color3.fromRGB(255, 190, 40),
		Size = Vector3.new(2.6, 2.6, 2.6),
		Rarity = Color3.fromRGB(255, 170, 30),
		Glow = true,
	},
	Mythic = {
		DisplayName = "Мифическое",
		Weight = 60,
		Value = 350,
		Color = Color3.fromRGB(255, 90, 160),
		Size = Vector3.new(2.8, 2.8, 2.8),
		Rarity = Color3.fromRGB(255, 70, 140),
		Glow = true,
	},
	Divine = {
		DisplayName = "Божественное",
		Weight = 15,
		Value = 1500,
		Color = Color3.fromRGB(120, 255, 250),
		Size = Vector3.new(3.0, 3.0, 3.0),
		Rarity = Color3.fromRGB(90, 245, 240),
		Glow = true,
	},
	Cosmic = {
		DisplayName = "Космическое",
		Weight = 4,
		Value = 7500,
		Color = Color3.fromRGB(180, 130, 255),
		Size = Vector3.new(3.2, 3.2, 3.2),
		Rarity = Color3.fromRGB(200, 150, 255),
		Glow = true,
		Rainbow = true,
	},
}

-- Порядок от частого к редкому (для интерфейса и ивентов)
Config.EggOrder = {
	"Common", "Uncommon", "Rare", "Epic",
	"Legendary", "Mythic", "Divine", "Cosmic",
}

-- ===================== КАРТА =====================

Config.ArenaSize = 400
Config.MarketRadius = 36
Config.BasesCount = 16
Config.BaseRingRadius = 134
Config.BaseZoneRadius = 15

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

-- ===================== ИВЕНТЫ =====================
--[[
	Каждые EventInterval секунд на рынке происходит событие.
	Игроки, которые в нём поучаствуют, получают яйца РЕДКЕЕ обычных.
]]
Config.EventInterval = 120      -- период между ивентами (2 минуты)
Config.EventDuration = 25       -- сколько ивент активен
Config.EventWarnBefore = 8      -- предупреждение за N секунд до старта

Config.Events = {
	{
		Id = "GoldenRain",
		Name = "Золотой дождь",
		Description = "На рынке падают легендарные яйца — успей подобрать!",
		Color = Color3.fromRGB(255, 200, 60),
		EggsCount = 14,
		MinType = "Epic",
		MaxType = "Legendary",
	},
	{
		Id = "MeteorShower",
		Name = "Метеоритный дождь",
		Description = "С неба валятся мифические яйца",
		Color = Color3.fromRGB(255, 120, 90),
		EggsCount = 10,
		MinType = "Legendary",
		MaxType = "Mythic",
	},
	{
		Id = "DivineGift",
		Name = "Дар богов",
		Description = "Божественные яйца ждут на площади",
		Color = Color3.fromRGB(120, 255, 250),
		EggsCount = 6,
		MinType = "Mythic",
		MaxType = "Divine",
	},
	{
		Id = "CosmicRift",
		Name = "Космический разлом",
		Description = "Редчайший шанс — космические яйца!",
		Color = Color3.fromRGB(190, 140, 255),
		EggsCount = 3,
		MinType = "Divine",
		MaxType = "Cosmic",
	},
	{
		Id = "EggRush",
		Name = "Яичная лихорадка",
		Description = "Клик по гнёздам даёт втрое больше яиц!",
		Color = Color3.fromRGB(255, 170, 220),
		EggsCount = 0,
		Multiplier = 3,
		MinType = "Rare",
		MaxType = "Epic",
	},
}

-- ===================== ДОНАТ (РОБУКСЫ) =====================
--[[
	Покупки за Robux через MarketplaceService.

	ВАЖНО: чтобы они реально работали, нужны Developer Product ID,
	созданные в твоём опыте (Monetization -> Developer Products).
	Пока ID не задан, вкладка показывает товары, а покупка вежливо
	отказывает с подсказкой — игра не ломается.
]]
Config.Donations = {
	{
		Id = "StarterPack",
		Name = "Набор новичка",
		Icon = "🎁",
		Description = "2500 монет + 5 легендарных яиц",
		Price = 25,
		ProductId = 0,
		Coins = 2500,
		Eggs = { Type = "Legendary", Count = 5 },
		Color = Color3.fromRGB(120, 220, 150),
	},
	{
		Id = "CoinChest",
		Name = "Сундук монет",
		Icon = "💰",
		Description = "15000 монет сразу на склад",
		Price = 75,
		ProductId = 0,
		Coins = 15000,
		Color = Color3.fromRGB(255, 205, 90),
	},
	{
		Id = "MythicEgg",
		Name = "Мифическое яйцо",
		Icon = "🔮",
		Description = "Гарантированное мифическое яйцо",
		Price = 49,
		ProductId = 0,
		Coins = 0,
		Eggs = { Type = "Mythic", Count = 1 },
		Color = Color3.fromRGB(255, 90, 160),
	},
	{
		Id = "DivineBlessing",
		Name = "Благословение",
		Icon = "✨",
		Description = "Божественное яйцо + 5000 монет",
		Price = 149,
		ProductId = 0,
		Coins = 5000,
		Eggs = { Type = "Divine", Count = 1 },
		Color = Color3.fromRGB(120, 255, 250),
	},
	{
		Id = "CosmicBundle",
		Name = "Космический набор",
		Icon = "🌌",
		Description = "Космическое яйцо + 25000 монет",
		Price = 499,
		ProductId = 0,
		Coins = 25000,
		Eggs = { Type = "Cosmic", Count = 1 },
		Color = Color3.fromRGB(180, 130, 255),
	},
	{
		Id = "PermanentBoost",
		Name = "Вечный буст",
		Icon = "🚀",
		Description = "Навсегда +50% к доходу базы",
		Price = 299,
		ProductId = 0,
		Coins = 0,
		Boost = 0.5,
		Color = Color3.fromRGB(90, 200, 255),
	},
}

-- ===================== ПРОЧЕЕ =====================

Config.SaveFolder = "EggGamePlayerData"
Config.DataVersion = 1
Config.AutosaveInterval = 90

-- Сколько игроков может делить одну базу
Config.BaseMaxOwners = 2

--[[
	Музыка. Пустая строка = взять публичный трек Roblox автоматически.
	Свой трек: загрузи .mp3 на roblox.com/create -> Audio,
	скопируй число из ссылки и вставь сюда: "rbxassetid://1234567890"
]]
Config.MusicId = ""

-- Тихий фоновый эмбиент (ветер, природа). Пусто = выключено
Config.AmbientSoundId = ""

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
