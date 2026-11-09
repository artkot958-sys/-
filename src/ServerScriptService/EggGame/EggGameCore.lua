--[[
	EggGameCore — вся игровая логика на сервере.

	Место в Studio: ServerScriptService -> ModuleScript "EggGameCore"

	ЦИКЛ ИГРЫ
	  1. На рынке в центре постоянно появляются яйца (4 редкости).
	  2. Идёшь по ним — яйца сами запрыгивают в стопку над головой.
	  3. Несёшь на свою базу — яйца сами заносятся на склад.
	  4. Яйца на складе приносят монеты каждую секунду.
	  5. Другие игроки могут украсть яйца у тебя из рюкзака (зажать E рядом)
	     или обокрасть твой склад (зажать E у склада).
	  6. Монеты тратятся в магазине на улучшения.

	Клиент ничего не решает — только просит, сервер проверяет всё сам.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("EggGameConfig"))
local function findModule(name)
	local direct = script.Parent and script.Parent:FindFirstChild(name)
	if direct then
		return direct
	end
	local service = game:GetService("ServerScriptService")
	local anywhere = service:FindFirstChild(name, true)
	if anywhere then
		return anywhere
	end
	return script.Parent:WaitForChild(name)
end

local Data = require(findModule("EggGameData"))
local Map = require(findModule("EggGameMap"))

local Core = {}

local RNG = Random.new()

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================

local state = {
	map = nil,
	bases = {},         -- [baseId] = baseState
	playerBase = {},    -- [Player] = baseId
	groundEggs = {},    -- { { Part = part, Type = string }, ... }
	carried = {},       -- [Player] = { Parts = {}, Types = {}, Count, LockUntil }
	cooldowns = {},     -- [Player] = { Raid = number }
	depositing = {},    -- [Player] = true
	vaultFullWarned = {},
	remotes = {},
}

-- ============================================================
-- МЕЛКИЕ УТИЛИТЫ
-- ============================================================

local function getRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function horizontalDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function getCooldown(player)
	local cooldown = state.cooldowns[player]
	if not cooldown then
		cooldown = { Raid = 0 }
		state.cooldowns[player] = cooldown
	end
	return cooldown
end

local function getCarried(player)
	local carried = state.carried[player]
	if not carried then
		carried = { Parts = {}, Types = {}, Count = 0, LockUntil = 0 }
		state.carried[player] = carried
	end
	return carried
end

local function getBackpackCapacity(player)
	return math.max(1, math.floor(Data.getUpgradeValue(player, "Backpack")))
end

local function getVaultCapacity(base)
	if #base.Owners == 0 then
		return Config.VaultCapacityBase
	end

	local best = Config.VaultCapacityBase
	for _, owner in ipairs(base.Owners) do
		best = math.max(best, math.floor(Data.getUpgradeValue(owner, "Vault")))
	end
	return best
end

--[[
	Выбор типа яйца по весам.

	luck — множитель «удачи»: >1 повышает шанс редких яиц.
	Как работает: вес каждого яйца умножается на luck^(индекс редкости),
	поэтому редкие растут быстрее обычных. При luck=1 всё как в конфиге.
]]
local function pickEggType(luck)
	luck = luck or 1

	local order = Config.EggOrder
	local weights = {}
	local total = 0

	for index, name in ipairs(order) do
		local eggType = Config.EggTypes[name]
		if eggType then
			-- Редкие яйца получают больший буст от удачи
			local boost = luck ^ (index - 1)
			local weight = eggType.Weight * boost
			weights[name] = weight
			total += weight
		end
	end

	if total <= 0 then
		return "Common"
	end

	local roll = RNG:NextNumber() * total
	for _, name in ipairs(order) do
		local weight = weights[name] or 0
		roll -= weight
		if roll <= 0 then
			return name
		end
	end

	return "Common"
end

-- Выбор яйца между двумя типами (для ивентов)
local function pickEggBetween(minType, maxType)
	local order = Config.EggOrder
	local minIndex, maxIndex = 1, #order

	for index, name in ipairs(order) do
		if name == minType then
			minIndex = index
		end
		if name == maxType then
			maxIndex = index
		end
	end

	if maxIndex < minIndex then
		minIndex, maxIndex = maxIndex, minIndex
	end

	local name = order[RNG:NextInteger(minIndex, maxIndex)]
	return name or "Common"
end

-- ============================================================
-- УВЕДОМЛЕНИЯ
-- ============================================================

--[[
	Безопасная отправка на клиент.

	Если remote ещё не создан, или клиент отключился, или (в редких случаях)
	remote не является RemoteEvent — сервер НЕ должен падать.
	Любая ошибка здесь не должна ломать игровую логику.
]]
local function fireClient(remoteName, player, ...)
	local remote = state.remotes[remoteName]

	if not remote or not player or not player.Parent then
		return false
	end

	local args = table.pack(...)
	local ok = pcall(function()
		remote:FireClient(player, table.unpack(args, 1, args.n))
	end)

	return ok
end

-- То же для RemoteFunction, отвечающего клиенту
Core.fireClient = fireClient

function Core.notify(player, text, color)
	fireClient("Notify", player, text, color)
end

-- ============================================================
-- БАЗЫ: ВИЗУАЛ И НАЗНАЧЕНИЕ
-- ============================================================

local function vaultValueOf(base)
	local value = 0
	for eggTypeName, count in pairs(base.Vault) do
		local eggType = Config.EggTypes[eggTypeName]
		if eggType then
			value += eggType.Value * count
		end
	end
	return value
end

local function getBaseIncomePerSecond(base, player)
	if base.VaultTotal <= 0 then
		return 0
	end

	local ownerCount = math.max(1, #base.Owners)
	local rate = vaultValueOf(base) * Config.IncomeRate

	-- Буст от донат-покупки прибавляется к множителю дохода
	local function boostOf(owner)
		return 1 + (state.boostPerPlayer[owner] or 0)
	end

	if player then
		return (rate * Data.getUpgradeValue(player, "Income") * boostOf(player)) / ownerCount
	end

	local total = 0
	for _, owner in ipairs(base.Owners) do
		total += (rate * Data.getUpgradeValue(owner, "Income") * boostOf(owner)) / ownerCount
	end
	return total
end

Core.getBaseIncomePerSecond = getBaseIncomePerSecond

local function updateBaseVisuals(base)
	local owners = base.Owners
	local ownerCount = #owners

	if ownerCount == 0 then
		if base.ClaimLabel then
			base.ClaimLabel.Text = "🏠 Занять"
			base.ClaimTop.Color = Config.Colors.MyBase
		end
		base.Platform.Color = Config.Colors.FreeBase
		base.Glow.Color = Config.Colors.FreeBase
		base.SignLabel.Text = "Свободная база"
		base.SignLabel.TextColor3 = Color3.fromRGB(225, 228, 235)
		base.VaultLabel.Text = string.format("🏦 %d", base.VaultTotal)
		base.VaultTop.Color = Color3.fromRGB(132, 110, 82)
		base.VaultGlow.Color = Config.Colors.FreeBase
		return
	end

	-- Стойка больше не нужна: база занята
	if base.ClaimLabel then
		if ownerCount < Config.BaseMaxOwners then
			base.ClaimLabel.Text = "＋ Подселиться"
			base.ClaimTop.Color = Color3.fromRGB(255, 210, 110)
		else
			base.ClaimLabel.Text = "🔒 Занято"
			base.ClaimTop.Color = Color3.fromRGB(150, 150, 160)
		end
	end

	base.Platform.Color = Config.Colors.MyBase
	base.Glow.Color = Config.Colors.MyBase
	base.VaultTop.Color = Color3.fromRGB(150, 122, 88)
	base.VaultGlow.Color = Config.Colors.Vault

	local names = {}
	for index, owner in ipairs(owners) do
		if index <= 3 then
			table.insert(names, owner.DisplayName)
		end
	end
	if ownerCount > 3 then
		table.insert(names, "+" .. (ownerCount - 3))
	end

	base.SignLabel.Text = table.concat(names, ", ")
	base.SignLabel.TextColor3 = Color3.fromRGB(200, 255, 220)

	local rate = getBaseIncomePerSecond(base, owners[1])
	base.VaultLabel.Text = string.format("🏦 %d / %d   💰 %.1f/сек", base.VaultTotal, getVaultCapacity(base), rate)
end

-- ============================================================
-- СИНХРОНИЗАЦИЯ С КЛИЕНТОМ
-- ============================================================

function Core.syncCoins(player)
	local base = Core.getBaseForPlayerFor(player)
	local income = base and getBaseIncomePerSecond(base, player) or 0

	fireClient("CoinsUpdate", player, Data.getCoins(player), income)
end

function Core.syncCarried(player)
	local carried = getCarried(player)
	fireClient("CarriedUpdate", player, carried.Count, getBackpackCapacity(player), carried.Types)
end

function Core.syncBaseInfo(player)
	local base = Core.getBaseForPlayerFor(player)
	if not base then
		fireClient("BaseInfo", player, nil)
		return
	end

	fireClient("BaseInfo", player, {
		BaseId = base.Id,
		VaultTotal = base.VaultTotal,
		Capacity = getVaultCapacity(base),
		Income = getBaseIncomePerSecond(base, player),
		Owners = #base.Owners,
	})
end

-- ============================================================
-- НАЗНАЧЕНИЕ БАЗ
-- ============================================================

function Core.getBaseForPlayerFor(player)
	local baseId = state.playerBase[player]
	if not baseId then
		return nil
	end
	return state.bases[baseId]
end

function Core.assignBase(player)
	local existing = state.playerBase[player]
	if existing then
		return existing
	end

	-- Игрок возвращается: отдаём ту же базу, если она ещё свободна или уже его
	local data = Data.get(player)
	local preferredId = data and data.BaseId

	if preferredId then
		local preferred = state.bases[preferredId]
		if preferred then
			local ownedByOther = false
			for _, owner in ipairs(preferred.Owners) do
				if owner ~= player then
					ownedByOther = true
					break
				end
			end

			if not ownedByOther then
				local alreadyThere = false
				for _, owner in ipairs(preferred.Owners) do
					if owner == player then
						alreadyThere = true
						break
					end
				end

				if not alreadyThere then
					table.insert(preferred.Owners, player)
				end

				state.playerBase[player] = preferred.Id
				updateBaseVisuals(preferred)
				Core.syncBaseInfo(player)
				return preferred.Id
			end
		end
	end

	-- Ищем базу с наименьшим числом владельцев (сначала пустые)
	local bestBase, bestCount = nil, math.huge
	for _, base in ipairs(state.map.BasesData) do
		local count = #base.Owners
		if count < bestCount then
			bestCount, bestBase = count, base
		end
		if count == 0 then
			break
		end
	end

	if not bestBase then
		return nil
	end

	table.insert(bestBase.Owners, player)
	state.playerBase[player] = bestBase.Id

	local data = Data.get(player)
	if data then
		data.BaseId = bestBase.Id
	end

	updateBaseVisuals(bestBase)

	Core.syncBaseInfo(player)

	return bestBase.Id
end

--[[
	Занять конкретную базу.
	Игрок подходит к стойке и зажимает E. Раньше база выдавалась только
	автоматически при входе — занять выбранную было нельзя.
]]
function Core.claimBase(player, baseId)
	local base = state.bases[baseId]
	if not base then
		return false, "Базы не существует"
	end

	if not Data.isLoaded(player) then
		return false, "Данные ещё загружаются"
	end

	local currentId = state.playerBase[player]
	if currentId == baseId then
		return false, "Это уже твоя база"
	end

	-- Освобождаем прошлую базу этого игрока
	if currentId then
		Core.releaseBase(player, true)
	end

	-- На свободную базу может встать кто угодно
	local count = #base.Owners
	if count >= Config.BaseMaxOwners then
		-- возвращаем игрока на прежнюю базу, чтобы он не остался без склада
		Core.assignBase(player)
		return false, string.format("База занята (%d/%d)", count, Config.BaseMaxOwners)
	end

	table.insert(base.Owners, player)
	state.playerBase[player] = base.Id

	local data = Data.get(player)
	if data then
		data.BaseId = base.Id
	end

	updateBaseVisuals(base)
	Core.syncBaseInfo(player)
	Core.syncCoins(player)

	return true, string.format("Твоя база №%d", base.Id)
end

-- Нажатие на стойку «Занять базу»
function Core.onClaimPrompt(player, baseId)
	local ok, message = Core.claimBase(player, baseId)

	local color
	if ok then
		color = Color3.fromRGB(120, 240, 160)
	else
		color = Color3.fromRGB(255, 190, 120)
	end

	Core.notify(player, message, color)
end

function Core.releaseBase(player, keepPreference)
	local baseId = state.playerBase[player]
	state.playerBase[player] = nil

	if not baseId then
		return
	end

	local base = state.bases[baseId]
	if not base then
		return
	end

	for index, owner in ipairs(base.Owners) do
		if owner == player then
			table.remove(base.Owners, index)
			break
		end
	end

	base.RateAccum[player] = nil
	updateBaseVisuals(base)

	if not keepPreference then
		local data = Data.get(player)
		if data then
			data.BaseId = nil
		end
	end
end

-- ============================================================
-- ДОНАТ (ПОКУПКИ ЗА ROBUX)
-- ============================================================

-- Находим товар по Developer Product ID
local function findDonationByProductId(productId)
	for _, item in ipairs(Config.Donations) do
		if item.ProductId == productId and productId > 0 then
			return item
		end
	end
	return nil
end

-- Находим товар по строковому Id (для интерфейса)
function Core.findDonation(itemId)
	for _, item in ipairs(Config.Donations) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

-- Выдаём содержимое покупки
function Core.grantDonation(player, item)
	if not item then
		return false
	end

	if item.Coins and item.Coins > 0 then
		Data.addCoins(player, item.Coins)
		Core.syncCoins(player)
	end

	if item.Eggs then
		-- Яйца доната идут сразу в рюкзак, даже если он переполнен
		local carried = getCarried(player)
		local capacity = getBackpackCapacity(player)

		for _ = 1, item.Eggs.Count do
			local part = Map.makeEggPart(item.Eggs.Type, state.map.Carried)
			part.Size = part.Size * Config.CarriedEggScale
			part.Anchored = true

			table.insert(carried.Parts, part)
			carried.Types[item.Eggs.Type] = (carried.Types[item.Eggs.Type] or 0) + 1
			carried.Count += 1
		end

		-- Если рюкзак переполнен — лишнее уходит в склад на базе
		if carried.Count > capacity then
			Core.startDeposit(player)
		end

		refreshStack(player)
		Core.syncCarried(player)
	end

	if item.Boost then
		state.boostPerPlayer[player] = (state.boostPerPlayer[player] or 0) + item.Boost
		Core.syncCoins(player)
	end

	Core.notify(player, string.format("%s %s — получено!", item.Icon or "🎁", item.Name),
		Color3.fromRGB(140, 255, 180))

	return true
end

--[[
	Покупка за Robux.

	Если ProductId = 0, значит товар ещё не создан в опыте —
	вежливо отказываем и подсказываем, что делать. Игра не ломается.
]]
function Core.purchaseDonation(player, itemId)
	local item = Core.findDonation(itemId)
	if not item then
		return false, "Товар не найден"
	end

	if not item.ProductId or item.ProductId == 0 then
		Core.notify(player,
			"Этот товар ещё не настроен. Создай Developer Product в Roblox и вставь ID в Config.Donations.",
			Color3.fromRGB(255, 200, 120))
		return false, "Товар не настроен (нужен Developer Product ID)"
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, item.ProductId)
	end)

	if not ok then
		warn("[EggGame] Ошибка покупки: " .. tostring(err))
		return false, "Не удалось открыть окно покупки"
	end

	return true, "Открываю окно покупки..."
end

-- Список товаров для интерфейса
function Core.getDonationList()
	local list = {}
	for _, item in ipairs(Config.Donations) do
		table.insert(list, {
			Id = item.Id,
			Name = item.Name,
			Icon = item.Icon,
			Description = item.Description,
			Price = item.Price,
			Color = item.Color,
			Configured = (item.ProductId or 0) > 0,
		})
	end
	return list
end

-- Обработчик чеков Roblox (обязателен для Developer Products)
function Core.setupMarketplace()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local item = findDonationByProductId(receiptInfo.ProductId)
		if not item then
			warn("[EggGame] Неизвестный ProductId: " .. tostring(receiptInfo.ProductId))
			-- Возвращаем NotProcessedYet — Roblox попробует позже
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local ok, err = pcall(function()
			Core.grantDonation(player, item)
		end)

		if not ok then
			warn("[EggGame] Не удалось выдать покупку: " .. tostring(err))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		print(string.format("[EggGame] %s купил %s за %d R$",
			player.Name, item.Name, item.Price or 0))

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

-- ============================================================
-- ИВЕНТЫ (каждые 2 минуты)
-- ============================================================

state.currentEvent = nil
state.eventEggs = {}

local function broadcast(text, color)
	for _, player in ipairs(Players:GetPlayers()) do
		Core.notify(player, text, color)
	end
end

local function clearEventEggs()
	for _, part in ipairs(state.eventEggs) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	state.eventEggs = {}
end

-- Раскладываем яйца ивента по рынку
local function spawnEventEggs(event)
	local mapData = state.map
	local folder = mapData and mapData.EventEggs
	if not folder then
		return
	end

	clearEventEggs()

	for i = 1, (event.EggsCount or 0) do
		local offset = Map.randomPointInDisc(Config.MarketRadius - 8)
		local eggTypeName = pickEggBetween(event.MinType, event.MaxType)
		local eggType = Config.EggTypes[eggTypeName]

		local part = Map.makeEggPart(eggTypeName, folder)
		part.Name = "EventEgg"
		part.Position = Vector3.new(offset.X, 3.4 + (eggType.Size.Y or 2) * 0.4, offset.Z)
		part.Anchored = true

		-- Светящаяся подложка, чтобы яйцо было видно издалека
		local halo = Instance.new("Part")
		halo.Name = "Halo"
		halo.Shape = Enum.PartType.Ball
		halo.Size = Vector3.new(7, 7, 7)
		halo.Position = part.Position
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.Material = Enum.Material.Neon
		halo.Color = event.Color or eggType.Color
		halo.Transparency = 0.55
		halo.Parent = folder

		table.insert(state.eventEggs, part)
		table.insert(state.eventEggs, halo)

		-- Автоподбор при касании
		part.Touched:Connect(function(hit)
			if not part.Parent then
				return
			end
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end

			if Core.addEggToBackpack(player, eggTypeName, 1) then
				Core.notify(player, string.format(
					"%s %s яйцо!", eggType.Icon or "🥚", eggType.DisplayName
				), eggType.Rarity)
				part:Destroy()
				if halo.Parent then
					halo:Destroy()
				end
			end
		end)
	end
end

local function startEvent()
	local events = Config.Events
	local event = events[RNG:NextInteger(1, #events)]
	if not event then
		return
	end

	state.currentEvent = event
	state.eventMultiplier = event.Multiplier or 1

	broadcast(string.format("🎉 ИВЕНТ: %s — %s", event.Name, event.Description), event.Color)

	-- Показываем баннер в интерфейсе
	for _, player in ipairs(Players:GetPlayers()) do
		fireClient("EventUpdate", player, {
			Name = event.Name,
			Description = event.Description,
			Color = event.Color,
		})
	end

	spawnEventEggs(event)

	task.delay(Config.EventDuration, function()
		if state.currentEvent ~= event then
			return
		end

		state.currentEvent = nil
		state.eventMultiplier = 1
		clearEventEggs()

		broadcast("⌛ Ивент закончился. Следующий через 2 минуты!", Color3.fromRGB(200, 200, 220))

		for _, player in ipairs(Players:GetPlayers()) do
			fireClient("EventUpdate", player, nil)
		end
	end)
end

function Core.startEventLoop()
	task.spawn(function()
		while true do
			task.wait(Config.EventInterval - Config.EventWarnBefore)

			if #Players:GetPlayers() > 0 then
				broadcast("⚡ Через 8 секунд начнётся ивент!", Color3.fromRGB(255, 230, 140))
			end

			task.wait(Config.EventWarnBefore)

			-- Не запускаем ивент в пустом сервере
			if #Players:GetPlayers() > 0 then
				startEvent()
			end

			task.wait(Config.EventDuration)
		end
	end)
end

-- Данные активного ивента для интерфейса
function Core.getEventInfo()
	local event = state.currentEvent
	if not event then
		return nil
	end
	return {
		Name = event.Name,
		Description = event.Description,
		Color = event.Color,
	}
end

-- ============================================================
-- КЛИКЕР: ГНЁЗДА
-- ============================================================

state.nests = {}          -- { { Model=, Prompt=, Position=, LastHit={player->time} }, ... }
state.combo = {}          -- player -> { Count = int, LastHit = number }
state.eventMultiplier = 1 -- множитель яиц от активного ивента
state.boostPerPlayer = {} -- player -> суммарный буст дохода (донат)

--[[
	Клик по гнезду.
	Игрок подходит и жмёт E. Каждый клик может выбить яйцо, а серия
	кликов подряд повышает шанс редкого (комбо).
]]
function Core.hitNest(player, nestIndex)
	local nest = state.nests[nestIndex]
	if not nest then
		return false, "Гнездо не найдено"
	end

	if not Data.isLoaded(player) then
		return false, "Данные ещё загружаются"
	end

	local root = getRoot(player)
	if not root then
		return false, "Персонаж не готов"
	end

	-- Проверка дистанции: нельзя кликать гнездо с другого конца карты
	if horizontalDistance(root.Position, nest.Position) > Config.NestRange then
		return false, "Подойди ближе к гнезду"
	end

	-- Кулдаун на гнездо для конкретного игрока
	local now = os.clock()
	nest.LastHit = nest.LastHit or {}
	local last = nest.LastHit[player]
	if last and now - last < Config.NestCooldown then
		return false, nil
	end
	nest.LastHit[player] = now

	-- Комбо: серия кликов подряд повышает удачу
	local combo = state.combo[player]
	if not combo or now - combo.LastHit > Config.ComboWindow then
		combo = { Count = 0, LastHit = now }
		state.combo[player] = combo
	end
	combo.Count += 1
	combo.LastHit = now

	local luck = 1 + math.min(Config.ComboMax - 1, (combo.Count - 1) * Config.ComboStep)

	-- Крит: резкий скачок удачи
	local isCrit = RNG:NextNumber() < Config.CritChance
	if isCrit then
		luck *= Config.CritMultiplier
	end

	local eggType = pickEggType(luck)

	-- Множитель от активного ивента
	local amount = math.max(1, math.floor((state.eventMultiplier or 1)))

	-- Во время ивента клик иногда даёт яйцо из события
	if state.currentEvent and state.currentEvent.MinType then
		local eventChance = 0.5
		if RNG:NextNumber() < eventChance then
			eggType = pickEggBetween(state.currentEvent.MinType, state.currentEvent.MaxType)
		end
	end

	local added = Core.addEggToBackpack(player, eggType, amount)

	-- Обратная связь клиенту: анимация и звук
	fireClient("NestHit", player, {
		NestIndex = nestIndex,
		EggType = eggType,
		Amount = amount,
		Combo = combo.Count,
		Crit = isCrit,
		Added = added,
	})

	return true, eggType
end

-- Серия кликов сбрасывается, если игрок перестал кликать
function Core.getCombo(player)
	local combo = state.combo[player]
	if not combo then
		return 0
	end
	if os.clock() - combo.LastHit > Config.ComboWindow then
		return 0
	end
	return combo.Count
end

function Core.registerNests(mapData)
	state.nests = {}

	local nestsFolder = mapData.Nests
	if not nestsFolder then
		warn("[EggGame] Папка гнёзд не найдена — кликер не работает")
		return
	end

	for _, model in ipairs(nestsFolder:GetChildren()) do
		if model:IsA("Model") then
			local prompt = model:FindFirstChild("HitPrompt", true)
			local base = model:FindFirstChild("NestBase", true)

			local index = #state.nests + 1
			local nest = {
				Model = model,
				Prompt = prompt,
				Position = base and base.Position or model:GetPivot().Position,
				Index = index,
				LastHit = {},
			}

			table.insert(state.nests, nest)

			if prompt then
				prompt.Triggered:Connect(function(player)
					Core.hitNest(player, index)
				end)
			end
		end
	end

	print("[EggGame] Гнёзд-кликеров: " .. tostring(#state.nests))
end

-- ============================================================
-- ЯЙЦА НА РЫНКЕ
-- ============================================================

function Core.spawnGroundEgg()
	if #state.groundEggs >= Config.MaxGroundEggs then
		return nil
	end

	local offset = Map.randomPointInDisc(Config.MarketRadius - 6)

	-- Не кладём яйца друг на друга
	for _ = 1, 6 do
		local tooClose = false
		for _, groundEgg in ipairs(state.groundEggs) do
			if groundEgg.Part and groundEgg.Part.Parent then
				local delta = groundEgg.Part.Position - offset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude < 3.4 then
					tooClose = true
					break
				end
			end
		end
		if not tooClose then
			break
		end
		offset = Map.randomPointInDisc(Config.MarketRadius - 6)
	end

	local eggTypeName = pickEggType()
	local part = Map.makeEggPart(eggTypeName, state.map.Eggs)
	part.Position = Vector3.new(offset.X, 2.3, offset.Z)

	local groundEgg = { Part = part, Type = eggTypeName }
	table.insert(state.groundEggs, groundEgg)

	return groundEgg
end

local function removeGroundEgg(groundEgg)
	for index, candidate in ipairs(state.groundEggs) do
		if candidate == groundEgg then
			table.remove(state.groundEggs, index)
			return
		end
	end
end

-- ============================================================
-- РЮКЗАК: СТОПКА НАД ГОЛОВОЙ
-- ============================================================

local function refreshStack(player)
	local carried = state.carried[player]
	if not carried then
		return
	end

	local root = getRoot(player)
	if not root then
		return
	end

	local columns = Config.StackColumns
	local shown = 0

	for _, part in ipairs(carried.Parts) do
		if part and part.Parent then
			shown += 1

			if shown <= Config.MaxVisibleStack then
				local row = math.floor((shown - 1) / columns)
				local column = (shown - 1) % columns
				local columnOffset = (column - (columns - 1) / 2) * Config.StackSpread

				local offset = Vector3.new(
					columnOffset,
					Config.StackBaseHeight + row * Config.StackHeight,
					-Config.StackBackOffset
				)

				part.CFrame = root.CFrame * CFrame.new(offset)
				part.Anchored = true
				part.CanCollide = false
				part.Transparency = 0
			else
				part.Transparency = 1
			end
		end
	end
end

local function refreshAllStacks()
	for player in pairs(state.carried) do
		refreshStack(player)
	end
end

function Core.addEggToBackpack(player, eggTypeName, count)
	count = count or 1

	local carried = getCarried(player)
	local capacity = getBackpackCapacity(player)

	local added = 0
	for _ = 1, count do
		if carried.Count >= capacity then
			break
		end

		local part = Map.makeEggPart(eggTypeName, state.map.Carried)
		part.Size = part.Size * Config.CarriedEggScale
		part.Anchored = true

		table.insert(carried.Parts, part)
		carried.Types[eggTypeName] = (carried.Types[eggTypeName] or 0) + 1
		carried.Count += 1
		added += 1
	end

	if added > 0 then
		carried.LockUntil = os.clock() + Config.StealLockTime
		refreshStack(player)
		Core.syncCarried(player)
	end

	return added
end

-- Убирает count яиц из рюкзака. Возвращает ({[type]=count}, всего)
function Core.takeEggsFromBackpack(player, count)
	local carried = state.carried[player]
	if not carried then
		return {}, 0
	end

	local taken = {}
	local takenTotal = 0

	for _ = 1, count do
		if carried.Count <= 0 then
			break
		end

		local part = table.remove(carried.Parts)
		if part then
			part:Destroy()
		end

		-- Берём тип, которого в рюкзаке больше всего
		local chosenType, chosenCount = nil, 0
		for eggTypeName, typeCount in pairs(carried.Types) do
			if typeCount > chosenCount then
				chosenType, chosenCount = eggTypeName, typeCount
			end
		end

		if chosenType then
			carried.Types[chosenType] -= 1
			if carried.Types[chosenType] <= 0 then
				carried.Types[chosenType] = nil
			end
			taken[chosenType] = (taken[chosenType] or 0) + 1
		end

		carried.Count -= 1
		takenTotal += 1
	end

	if takenTotal > 0 then
		refreshStack(player)
		Core.syncCarried(player)
	end

	return taken, takenTotal
end

function Core.dropAllCarried(player, position)
	local carried = state.carried[player]
	if not carried or carried.Count <= 0 then
		return
	end

	local root = getRoot(player)
	local dropPosition = position or (root and root.Position) or Vector3.new(0, 2, 0)

	for _, part in ipairs(carried.Parts) do
		if part then
			part:Destroy()
		end
	end
	carried.Parts = {}

	for eggTypeName, count in pairs(carried.Types) do
		for _ = 1, count do
			local offset = Map.randomPointInDisc(5)
			local part = Map.makeEggPart(eggTypeName, state.map.Eggs)
			part.Position = dropPosition + offset + Vector3.new(0, 1.8, 0)
			table.insert(state.groundEggs, { Part = part, Type = eggTypeName })
		end
	end

	carried.Types = {}
	carried.Count = 0
	Core.syncCarried(player)
end

function Core.getCarriedCount(player)
	local carried = state.carried[player]
	return carried and carried.Count or 0
end

-- ============================================================
-- ПОДБОР ЯИЦ (автоматический)
-- ============================================================

local function isInsideOwnBase(player)
	local base = Core.getBaseForPlayerFor(player)
	local root = getRoot(player)
	if not base or not root then
		return false
	end
	return horizontalDistance(root.Position, base.Center) <= Config.BaseZoneRadius + 1
end

local function startPickupLoop()
	task.spawn(function()
		while true do
			task.wait(0.15)

			for _, player in ipairs(Players:GetPlayers()) do
				local root = getRoot(player)
				local carried = state.carried[player]

				if root and carried and Data.isLoaded(player) and carried.Count < getBackpackCapacity(player) then
					-- Если стоишь на своей базе, яйца не подбираем — они сразу уходят в склад
					if not isInsideOwnBase(player) then
						local radius = Config.PickupRadius
						local magnetLevel = Data.getLevel(player, "Magnet")
						if magnetLevel > 0 then
							radius += Data.getUpgradeValue(player, "Magnet")
						end

						local nearest, nearestDistance = nil, math.huge
						for _, groundEgg in ipairs(state.groundEggs) do
							local part = groundEgg.Part
							if part and part.Parent then
								local horizontal = horizontalDistance(part.Position, root.Position)
								local vertical = math.abs(part.Position.Y - root.Position.Y)

								if horizontal <= radius and vertical <= 14 and horizontal < nearestDistance then
									nearest, nearestDistance = groundEgg, horizontal
								end
							end
						end

						if nearest then
							local eggTypeName = nearest.Type
							removeGroundEgg(nearest)
							if nearest.Part then
								nearest.Part:Destroy()
							end

							local added = Core.addEggToBackpack(player, eggTypeName, 1)
							if added > 0 then
								Data.addStat(player, "EggsCollected", 1)
							end
						end
					end
				end
			end
		end
	end)
end

-- ============================================================
-- СКЛАД: ВИЗУАЛ И СДАЧА
-- ============================================================

function Core.refreshVaultVisuals(base)
	for _, part in ipairs(base.VisualEggs) do
		if part then
			part:Destroy()
		end
	end
	base.VisualEggs = {}

	local maxVisual = 12
	local shown = 0

	for eggTypeName, count in pairs(base.Vault) do
		local toShow = math.min(count, maxVisual - shown)

		for index = 1, toShow do
			local part = Map.makeEggPart(eggTypeName, state.map.VaultEggs)
			part.Size = part.Size * Config.VaultEggScale
			part.Anchored = true

			local row = math.floor(shown / 4)
			local column = shown % 4
			local jitter = (RNG:NextNumber() - 0.5) * 0.5

			part.Position = base.Center + Vector3.new(
				(column - 1.5) * 2.1,
				5.3 + row * 1.3,
				-1.4 + (row % 2) * 0.8 + jitter
			)

			table.insert(base.VisualEggs, part)
			shown += 1
		end

		if shown >= maxVisual then
			break
		end
	end
end

function Core.startDeposit(player)
	if state.depositing[player] then
		return
	end
	state.depositing[player] = true

	task.spawn(function()
		while true do
			task.wait(Config.DepositTime)

			local carried = state.carried[player]
			if not carried or carried.Count <= 0 then
				break
			end

			local base = Core.getBaseForPlayerFor(player)
			if not base or not isInsideOwnBase(player) then
				break
			end

			if base.VaultTotal >= getVaultCapacity(base) then
				if not state.vaultFullWarned[player] then
					state.vaultFullWarned[player] = true
					Core.notify(player, "Склад полон! Улучши «Склад» в магазине", Color3.fromRGB(255, 170, 120))
				end
				break
			end

			state.vaultFullWarned[player] = nil

			local taken, takenTotal = Core.takeEggsFromBackpack(player, 1)
			if takenTotal <= 0 then
				break
			end

			for eggTypeName, count in pairs(taken) do
				base.Vault[eggTypeName] = (base.Vault[eggTypeName] or 0) + count
				base.VaultTotal += count
			end

			Core.refreshVaultVisuals(base)
			updateBaseVisuals(base)

			Core.syncCarried(player)
			Core.syncBaseInfo(player)
		end

		state.depositing[player] = nil
	end)
end

-- ============================================================
-- КРАЖА С ЧУЖОГО СКЛАДА
-- ============================================================

function Core.tryRaid(player, baseId)
	baseId = tonumber(baseId)
	if not baseId then
		return false, "Неверная база"
	end

	local base = state.bases[baseId]
	if not base then
		return false, "Нет такой базы"
	end

	if not Data.isLoaded(player) then
		return false, "Подожди загрузку"
	end

	for _, owner in ipairs(base.Owners) do
		if owner == player then
			return false, "Это твоя база"
		end
	end

	if base.VaultTotal <= 0 then
		return false, "Склад пуст"
	end

	local cooldown = getCooldown(player)
	if os.clock() < cooldown.Raid then
		return false, "Рано"
	end

	local root = getRoot(player)
	if not root then
		return false, "Нет персонажа"
	end

	if horizontalDistance(root.Position, base.Center) > Config.BaseZoneRadius + 10 then
		return false, "Подойди ближе"
	end

	local carried = getCarried(player)
	local capacity = getBackpackCapacity(player) - carried.Count
	if capacity <= 0 then
		return false, "Рюкзак полон"
	end

	local stealPower = math.max(1, math.floor(Data.getUpgradeValue(player, "Steal")))
	local amount = math.min(stealPower, capacity, base.VaultTotal)

	local takenTotal = 0
	local takenValue = 0

	-- Забираем самые дорогие яйца
	for _ = 1, amount do
		local bestType, bestValue = nil, -1
		for eggTypeName, count in pairs(base.Vault) do
			if count > 0 then
				local eggType = Config.EggTypes[eggTypeName]
				if eggType and eggType.Value > bestValue then
					bestType, bestValue = eggTypeName, eggType.Value
				end
			end
		end

		if not bestType then
			break
		end

		base.Vault[bestType] -= 1
		if base.Vault[bestType] <= 0 then
			base.Vault[bestType] = nil
		end
		base.VaultTotal -= 1

		Core.addEggToBackpack(player, bestType, 1)
		takenTotal += 1
		takenValue += bestValue
	end

	cooldown.Raid = os.clock() + Config.StealCooldown

	if takenTotal <= 0 then
		return false, "Не удалось ничего взять"
	end

	Core.refreshVaultVisuals(base)
	updateBaseVisuals(base)
	Data.addStat(player, "EggsStolen", takenTotal)

	Core.notify(player, string.format("🥷 Украдено %d яиц (≈%d 💰)", takenTotal, takenValue), Color3.fromRGB(255, 210, 90))

	for _, owner in ipairs(base.Owners) do
		Data.addStat(owner, "EggsLost", takenTotal)
		Core.notify(owner, string.format("⚠️ %s украл %d яиц с твоей базы!", player.DisplayName, takenTotal), Color3.fromRGB(255, 110, 100))
		Core.syncBaseInfo(owner)
	end

	Core.syncBaseInfo(player)
	return true, "Украдено " .. takenTotal
end

-- ============================================================
-- КРАЖА ИЗ РЮКЗАКА ИГРОКА
-- ============================================================

function Core.tryStealFromPlayer(thief, victim)
	if thief == victim then
		return false, "Себя обкрадывать не нужно"
	end

	if not Data.isLoaded(thief) or not Data.isLoaded(victim) then
		return false, "Подожди загрузку"
	end

	local cooldown = getCooldown(thief)
	if os.clock() < cooldown.Raid then
		return false, "Рано"
	end

	local victimCarried = state.carried[victim]
	if not victimCarried or victimCarried.Count <= 0 then
		Core.notify(thief, "У него пусто", Color3.fromRGB(200, 210, 230))
		return false, "У него пусто"
	end

	if os.clock() < victimCarried.LockUntil then
		Core.notify(thief, "Он держит яйца крепко — подожди", Color3.fromRGB(255, 190, 120))
		return false, "Он держит крепко"
	end

	local thiefRoot = getRoot(thief)
	local victimRoot = getRoot(victim)
	if not thiefRoot or not victimRoot then
		return false, "Далеко"
	end

	if horizontalDistance(thiefRoot.Position, victimRoot.Position) > 10 then
		return false, "Подойди ближе"
	end

	local carried = getCarried(thief)
	local capacity = getBackpackCapacity(thief) - carried.Count
	if capacity <= 0 then
		Core.notify(thief, "Твой рюкзак полон", Color3.fromRGB(255, 170, 120))
		return false, "Твой рюкзак полон"
	end

	local stealPower = math.max(1, math.floor(Data.getUpgradeValue(thief, "Steal")))
	local amount = math.min(stealPower, capacity, victimCarried.Count)

	local taken, takenTotal = Core.takeEggsFromBackpack(victim, amount)
	if takenTotal <= 0 then
		return false, "Не удалось"
	end

	for eggTypeName, count in pairs(taken) do
		Core.addEggToBackpack(thief, eggTypeName, count)
	end

	cooldown.Raid = os.clock() + Config.StealCooldown

	Data.addStat(thief, "EggsStolen", takenTotal)
	Data.addStat(victim, "EggsLost", takenTotal)

	Core.notify(thief, string.format("🥷 Украл %d яиц у %s!", takenTotal, victim.DisplayName), Color3.fromRGB(255, 210, 90))
	Core.notify(victim, string.format("⚠️ %s украл у тебя %d яиц!", thief.DisplayName, takenTotal), Color3.fromRGB(255, 110, 100))

	return true, "Украдено " .. takenTotal
end

local function attachPlayerStealPrompt(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end

	local oldPrompt = character:FindFirstChild("StealFromMe")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealFromMe"
	prompt.ActionText = "Украсть яйца"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = Config.PlayerStealHoldTime
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = root

	prompt.Triggered:Connect(function(thief)
		Core.tryStealFromPlayer(thief, player)
	end)
end

-- ============================================================
-- ДОХОД
-- ============================================================

local function startIncomeLoop()
	task.spawn(function()
		while true do
			task.wait(1)

			for _, base in ipairs(state.map.BasesData) do
				local ownerCount = #base.Owners

				if ownerCount > 0 and base.VaultTotal > 0 then
					local rate = vaultValueOf(base) * Config.IncomeRate
					local totalIncome = 0

					for _, owner in ipairs(base.Owners) do
						local incomeMultiplier = Data.getUpgradeValue(owner, "Income")
						local share = (rate * incomeMultiplier) / ownerCount

						base.RateAccum[owner] = (base.RateAccum[owner] or 0) + share

						local whole = math.floor(base.RateAccum[owner])
						if whole > 0 then
							base.RateAccum[owner] -= whole
							Data.addCoins(owner, whole)
						end

						totalIncome += share
					end

					base.IncomePerSecond = totalIncome
					updateBaseVisuals(base)

					for _, owner in ipairs(base.Owners) do
						Core.syncCoins(owner)
						Core.syncBaseInfo(owner)
					end
				else
					base.IncomePerSecond = 0
					if base.VaultTotal == 0 then
						base.RateAccum = {}
					end
				end
			end
		end
	end)
end

-- ============================================================
-- СКОРОСТЬ ПЕРСОНАЖА
-- ============================================================

local function startSpeedLoop()
	task.spawn(function()
		while true do
			task.wait(0.5)

			for _, player in ipairs(Players:GetPlayers()) do
				if Data.isLoaded(player) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")

					if humanoid then
						local carried = state.carried[player]
						local penalty = 0

						if carried and carried.Count > 0 then
							penalty = math.min(6, carried.Count * 0.3)
						end

						local targetSpeed = math.max(8, Data.getUpgradeValue(player, "Speed") - penalty)

						if math.abs(humanoid.WalkSpeed - targetSpeed) > 0.2 then
							humanoid.WalkSpeed = targetSpeed
						end
					end
				end
			end
		end
	end)
end

-- ============================================================
-- ТАБЛО ЛИДЕРОВ
-- ============================================================

local function startLeaderboardLoop()
	task.spawn(function()
		while true do
			task.wait(3)

			local board = state.map and state.map.LeaderboardList
			if board then
				local entries = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if Data.isLoaded(player) then
						local data = Data.get(player)
						table.insert(entries, {
							Name = player.DisplayName,
							Score = data.TotalEarned,
						})
					end
				end

				table.sort(entries, function(a, b)
					return a.Score > b.Score
				end)

				local lines = {}
				for index = 1, math.min(8, #entries) do
					local entry = entries[index]
					local medal = (index == 1 and "🥇")
						or (index == 2 and "🥈")
						or (index == 3 and "🥉")
						or (index .. ".")
					table.insert(lines, string.format("%s  %s  —  %d 💰", medal, entry.Name, math.floor(entry.Score)))
				end

				board.Text = (#lines > 0) and table.concat(lines, "\n") or "Ждём игроков..."
			end
		end
	end)
end

-- ============================================================
-- ЖИЗНЕННЫЙ ЦИКЛ ИГРОКА
-- ============================================================

function Core.onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		task.wait(0.1)
		Core.dropAllCarried(player)
		state.depositing[player] = nil
	end)

	attachPlayerStealPrompt(player, character)
	refreshStack(player)
	Core.syncCarried(player)
end

function Core.cleanupPlayer(player)
	Core.dropAllCarried(player)
	Core.releaseBase(player, true)

	state.carried[player] = nil
	state.cooldowns[player] = nil
	state.depositing[player] = nil
	state.vaultFullWarned[player] = nil
end

-- ============================================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================================

local function startStackLoop()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 30 then
			return
		end
		accumulator = 0
		refreshAllStacks()
	end)
end

function Core.init(mapData, remotes)
	state.map = mapData
	state.remotes = remotes
	state.vaultFullWarned = {}

	for _, base in ipairs(mapData.BasesData) do
		base.RateAccum = {}
		base.IncomePerSecond = 0
		state.bases[base.Id] = base

		updateBaseVisuals(base)
		Core.refreshVaultVisuals(base)

		base.StealPrompt.Triggered:Connect(function(player)
			Core.tryRaid(player, base.Id)
		end)

		-- Стойка «Занять базу»
		if base.ClaimPrompt then
			base.ClaimPrompt.Triggered:Connect(function(player)
				Core.onClaimPrompt(player, base.Id)
			end)
		end
	end

	-- Наполняем рынок сразу, чтоб не было пусто на старте
	for _ = 1, 12 do
		Core.spawnGroundEgg()
	end

	task.spawn(function()
		while true do
			Core.spawnGroundEgg()
			task.wait(Config.SpawnInterval)
		end
	end)

	startPickupLoop()
	startIncomeLoop()
	startSpeedLoop()
	startLeaderboardLoop()

	-- Автоматическая сдача яиц при входе в свою базу
	task.spawn(function()
		while true do
			task.wait(0.3)

			for _, player in ipairs(Players:GetPlayers()) do
				if Data.isLoaded(player) then
					local carried = state.carried[player]
					if carried and carried.Count > 0 then
						if isInsideOwnBase(player) then
							Core.startDeposit(player)
						end
					end
				end
			end
		end
	end)

	startStackLoop()

	return Core
end

-- Доступ к внутреннему состоянию (для тестов и отладки)
function Core.getCtx()
	return state
end

-- Совместимость: старые вызовы
Core.getBaseForPlayer = Core.getBaseForPlayerFor
Core.spawnEggLoop = function() end

return Core
