--[[
	EggGameUI — весь интерфейс игры (LocalScript).

	Место в Studio:
	  StarterPlayer -> StarterPlayerScripts -> LocalScript с именем "EggGameUI"

	Показывает:
	  • Монеты и доход в секунду
	  • Рюкзак: сколько яиц несёшь / сколько влезает
	  • Склад: сколько яиц лежит на твоей базе
	  • Кнопку магазина улучшений (клавиша B)
	  • Всплывающие уведомления
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("EggGameRemotes")
local notifyRemote = remotesFolder:WaitForChild("Notify")
local coinsRemote = remotesFolder:WaitForChild("CoinsUpdate")
local shopRemote = remotesFolder:WaitForChild("ShopUpdate")
local carriedRemote = remotesFolder:WaitForChild("CarriedUpdate")
local baseInfoRemote = remotesFolder:WaitForChild("BaseInfo")
local buyRemote = remotesFolder:WaitForChild("BuyUpgrade")
local getShopRemote = remotesFolder:WaitForChild("GetShop")

-- ============================================================
-- ПАЛИТРА И ШРИФТЫ
-- ============================================================

local C = {
	Bg = Color3.fromRGB(22, 25, 35),
	BgDeep = Color3.fromRGB(14, 16, 24),
	Row = Color3.fromRGB(38, 43, 59),
	RowHover = Color3.fromRGB(48, 55, 74),
	Accent = Color3.fromRGB(255, 186, 64),
	AccentSoft = Color3.fromRGB(255, 214, 130),
	Good = Color3.fromRGB(96, 224, 144),
	Bad = Color3.fromRGB(255, 116, 106),
	Text = Color3.fromRGB(240, 244, 255),
	Dim = Color3.fromRGB(160, 172, 196),
	Stroke = Color3.fromRGB(66, 76, 100),
}

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local FONT_BLACK = Enum.Font.GothamBlack

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or C.Stroke
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function pad(parent, all)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft = UDim.new(0, all)
	p.PaddingRight = UDim.new(0, all)
	p.Parent = parent
	return p
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = C.Text
	l.TextSize = 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in pairs(props or {}) do
		l[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = C.Row
	b.BorderSizePixel = 0
	b.Font = FONT_BLACK
	b.TextColor3 = C.Text
	b.TextSize = 16
	for key, value in pairs(props or {}) do
		b[key] = value
	end
	b.Parent = parent
	corner(b, 10)
	return b
end

-- Красивое число: 1234 -> 1.2K
local function fmt(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e5 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function getViewport()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ============================================================
-- КОРНЕВОЙ GUI
-- ============================================================

local existing = playerGui:FindFirstChild("EggGameUI")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "EggGameUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = playerGui

-- ============================================================
-- ВЕРХНЯЯ ЛЕВАЯ ПАНЕЛЬ: МОНЕТЫ
-- ============================================================

local coinPanel = Instance.new("Frame")
coinPanel.Name = "CoinPanel"
coinPanel.Position = UDim2.fromOffset(14, 14)
coinPanel.Size = UDim2.fromOffset(220, 92)
coinPanel.BackgroundColor3 = C.Bg
coinPanel.BackgroundTransparency = 0.08
coinPanel.BorderSizePixel = 0
coinPanel.Parent = gui
corner(coinPanel, 16)
stroke(coinPanel, C.Accent, 2, 0.3)
pad(coinPanel, 12)

local coinRow = Instance.new("Frame")
coinRow.Size = UDim2.new(1, 0, 0, 44)
coinRow.BackgroundTransparency = 1
coinRow.Parent = coinPanel

label(coinRow, {
	Text = "💰",
	TextSize = 30,
	Size = UDim2.fromOffset(40, 44),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local coinText = label(coinRow, {
	Text = "0",
	Font = FONT_BLACK,
	TextSize = 32,
	TextColor3 = C.Accent,
	Position = UDim2.fromOffset(44, 0),
	Size = UDim2.new(1, -44, 1, 0),
	TextTruncate = Enum.TextTruncate.AtEnd,
})

local incomeText = label(coinPanel, {
	Text = "+0 / сек",
	Font = FONT_BOLD,
	TextSize = 14,
	TextColor3 = C.Dim,
	Position = UDim2.new(0, 2, 1, -22),
	Size = UDim2.new(1, -4, 0, 20),
})

-- ============================================================
-- ВЕРХНЯЯ ПРАВАЯ ПАНЕЛЬ: РЮКЗАК И СКЛАД
-- ============================================================

local infoPanel = Instance.new("Frame")
infoPanel.Name = "InfoPanel"
infoPanel.AnchorPoint = Vector2.new(1, 0)
infoPanel.Position = UDim2.new(1, -14, 0, 14)
infoPanel.Size = UDim2.fromOffset(236, 132)
infoPanel.BackgroundColor3 = C.Bg
infoPanel.BackgroundTransparency = 0.08
infoPanel.BorderSizePixel = 0
infoPanel.Parent = gui
corner(infoPanel, 16)
stroke(infoPanel, C.Stroke, 1.5, 0.2)
pad(infoPanel, 12)

local carriedText = label(infoPanel, {
	Text = "🎒 Рюкзак: 0 / 3",
	Font = FONT_BLACK,
	TextSize = 16,
	Size = UDim2.new(1, 0, 0, 20),
})

local barBg = Instance.new("Frame")
barBg.Position = UDim2.fromOffset(0, 24)
barBg.Size = UDim2.new(1, 0, 0, 9)
barBg.BackgroundColor3 = C.BgDeep
barBg.BorderSizePixel = 0
barBg.Parent = infoPanel
corner(barBg, 5)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = C.Accent
barFill.BorderSizePixel = 0
barFill.Parent = barBg
corner(barFill, 5)

local vaultText = label(infoPanel, {
	Text = "🏦 Склад: 0",
	Font = FONT_BOLD,
	TextSize = 15,
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 0, 18),
})

local incomeBaseText = label(infoPanel, {
	Text = "💰 Доход: 0 / сек",
	Font = FONT,
	TextSize = 14,
	TextColor3 = C.Good,
	Position = UDim2.fromOffset(0, 60),
	Size = UDim2.new(1, 0, 0, 18),
})

local hintText = label(infoPanel, {
	Text = "Собирай яйца на рынке",
	Font = FONT,
	TextSize = 12,
	TextColor3 = C.Dim,
	TextWrapped = true,
	Position = UDim2.fromOffset(0, 82),
	Size = UDim2.new(1, 0, 0, 32),
})

-- ============================================================
-- КНОПКА МАГАЗИНА
-- ============================================================

local shopButton = button(gui, {
	Name = "ShopButton",
	Text = "🛒  МАГАЗИН",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(230, 54),
	BackgroundColor3 = C.Accent,
	TextColor3 = Color3.fromRGB(38, 26, 6),
	TextSize = 20,
})
corner(shopButton, 14)
stroke(shopButton, C.AccentSoft, 2, 0.15)

local shopHint = label(shopButton, {
	Text = "[B]",
	Font = FONT_BOLD,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(60, 44, 14),
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(1, -34, 0, 6),
	Size = UDim2.fromOffset(28, 16),
})

-- ============================================================
-- УВЕДОМЛЕНИЯ
-- ============================================================

local toastArea = Instance.new("Frame")
toastArea.Name = "Toasts"
toastArea.AnchorPoint = Vector2.new(0.5, 0)
toastArea.Position = UDim2.new(0.5, 0, 0, 120)
toastArea.Size = UDim2.fromOffset(420, 250)
toastArea.BackgroundTransparency = 1
toastArea.Parent = gui

local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Padding = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Parent = toastArea

local toastIndex = 0

local function toast(text, color)
	toastIndex += 1
	local myIndex = toastIndex

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(370, 38)
	frame.BackgroundColor3 = C.Bg
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = myIndex
	frame.Parent = toastArea
	corner(frame, 10)
	stroke(frame, color or C.Accent, 2, 0.25)

	local textLabel = label(frame, {
		Text = tostring(text),
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = color or C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	pad(frame, 6)

	task.spawn(function()
		task.wait(2.5)
		local fade = TweenService:Create(frame, TweenInfo.new(0.3), {
			BackgroundTransparency = 1,
		})
		TweenService:Create(textLabel, TweenInfo.new(0.3), {
			TextTransparency = 1,
		}):Play()
		fade:Play()
		fade.Completed:Wait()
		frame:Destroy()
	end)
end

notifyRemote.OnClientEvent:Connect(function(text, color)
	toast(text, color)
end)

-- ============================================================
-- МАГАЗИН
-- ============================================================

-- Оверлей — кнопка на весь экран: клик мимо панели закрывает магазин
local shopOverlay = Instance.new("TextButton")
shopOverlay.Name = "ShopOverlay"
shopOverlay.Text = ""
shopOverlay.AutoButtonColor = false
shopOverlay.Size = UDim2.fromScale(1, 1)
shopOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
shopOverlay.BackgroundTransparency = 0.5
shopOverlay.BorderSizePixel = 0
shopOverlay.Visible = false
shopOverlay.ZIndex = 20
shopOverlay.Parent = gui

-- TextButton, а не Frame: так панель перехватывает клики
-- и магазин не закрывается при нажатии на пустое место внутри него
local shopPanel = Instance.new("TextButton")
shopPanel.Name = "ShopPanel"
shopPanel.Text = ""
shopPanel.AutoButtonColor = false
shopPanel.AnchorPoint = Vector2.new(0.5, 0.5)
shopPanel.Position = UDim2.fromScale(0.5, 0.5)
shopPanel.BackgroundColor3 = C.Bg
shopPanel.BorderSizePixel = 0
shopPanel.ZIndex = 21
shopPanel.Parent = shopOverlay
corner(shopPanel, 20)
stroke(shopPanel, C.Accent, 2, 0.25)

local shopHeader = Instance.new("Frame")
shopHeader.Size = UDim2.new(1, 0, 0, 74)
shopHeader.BackgroundTransparency = 1
shopHeader.ZIndex = 22
shopHeader.Parent = shopPanel

label(shopHeader, {
	Text = "🛒  МАГАЗИН УЛУЧШЕНИЙ",
	Font = FONT_BLACK,
	TextSize = 21,
	TextColor3 = C.Accent,
	Position = UDim2.fromOffset(20, 14),
	Size = UDim2.new(1, -110, 0, 26),
	ZIndex = 22,
})

local shopCoinsText = label(shopHeader, {
	Text = "💰 0",
	Font = FONT_BLACK,
	TextSize = 17,
	TextColor3 = C.AccentSoft,
	Position = UDim2.fromOffset(20, 42),
	Size = UDim2.new(1, -110, 0, 20),
	ZIndex = 22,
})

local closeButton = button(shopHeader, {
	Text = "✕",
	Size = UDim2.fromOffset(42, 42),
	Position = UDim2.new(1, -56, 0, 14),
	BackgroundColor3 = C.Bad,
	TextColor3 = C.Text,
	TextSize = 20,
	ZIndex = 22,
})
corner(closeButton, 12)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(14, 78)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = C.Accent
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 22
scroll.Parent = shopPanel

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 8)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

local isShopOpen = false
local cachedEntries = {}
local cachedCoins = 0


local function resizeShop()
	local viewport = getViewport()
	local width = math.min(560, viewport.X * 0.94)
	local height = math.min(600, viewport.Y * 0.88)

	shopPanel.Size = UDim2.fromOffset(width, height)
	scroll.Size = UDim2.new(1, -28, 1, -92)
end

local function updateBuyButtonState(buyButton, entry, coins)
	if not entry.Cost then
		buyButton.Text = "МАКС"
		buyButton.BackgroundColor3 = C.BgDeep
		buyButton.TextColor3 = C.Dim
		return false
	end

	buyButton.Text = "💰 " .. fmt(entry.Cost)

	local affordable = coins >= entry.Cost
	if affordable then
		buyButton.BackgroundColor3 = C.Good
		buyButton.TextColor3 = Color3.fromRGB(16, 40, 24)
	else
		buyButton.BackgroundColor3 = C.BgDeep
		buyButton.TextColor3 = C.Dim
	end

	return affordable
end

local function renderShop(entries, coins)
	cachedEntries = entries or {}
	cachedCoins = coins or 0

	shopCoinsText.Text = "💰 " .. fmt(cachedCoins)

	-- Пересоздаём строки
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for index, entry in ipairs(cachedEntries) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, 86)
		row.BackgroundColor3 = C.Row
		row.BackgroundTransparency = 0.05
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.ZIndex = 22
		row.Parent = scroll
		corner(row, 12)
		stroke(row, C.Stroke, 1, 0.4)

		label(row, {
			Text = entry.Icon or "⭐",
			TextSize = 30,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(46, 86),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 22,
		})

		label(row, {
			Text = entry.DisplayName,
			Font = FONT_BLACK,
			TextSize = 17,
			Position = UDim2.fromOffset(60, 10),
			Size = UDim2.new(1, -180, 0, 20),
			ZIndex = 22,
		})

		label(row, {
			Text = entry.Description,
			Font = FONT,
			TextSize = 12,
			TextColor3 = C.Dim,
			TextWrapped = true,
			Position = UDim2.fromOffset(60, 30),
			Size = UDim2.new(1, -180, 0, 30),
			ZIndex = 22,
		})

		local levelText = string.format(
			"Уровень %d / %d   •   сейчас: %.1f %s",
			entry.Level,
			entry.MaxLevel,
			entry.Value,
			entry.Unit or ""
		)
		if not entry.Cost then
			levelText = string.format("Уровень %d / %d   •   МАКСИМУМ", entry.Level, entry.MaxLevel)
		end

		label(row, {
			Text = levelText,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = entry.Cost and C.AccentSoft or C.Good,
			Position = UDim2.fromOffset(60, 62),
			Size = UDim2.new(1, -180, 0, 16),
			ZIndex = 22,
		})

		local buyButton = button(row, {
			Text = "—",
			TextSize = 15,
			Size = UDim2.fromOffset(104, 48),
			Position = UDim2.new(1, -116, 0.5, -24),
			BackgroundColor3 = C.BgDeep,
			TextColor3 = C.Dim,
			ZIndex = 23,
		})

		local affordable = updateBuyButtonState(buyButton, entry, cachedCoins)

		if affordable then
			buyButton.MouseButton1Click:Connect(function()
				if buyButton:GetAttribute("busy") then
					return
				end
				buyButton:SetAttribute("busy", true)

				local previousText = buyButton.Text
				buyButton.Text = "..."

				local success, message = buyRemote:InvokeServer(entry.Name)
				buyButton:SetAttribute("busy", false)

				if success then
					toast(message or "Куплено!", C.Good)

					-- Обновляем строку сразу, не дожидаясь ответа сервера
					local refreshed = getShopRemote:InvokeServer()
					if refreshed then
						cachedEntries = refreshed.Upgrades or cachedEntries
						cachedCoins = refreshed.Coins or cachedCoins
						renderShop(cachedEntries, cachedCoins)
					end
				else
					toast(message or "Не получилось", C.Bad)
					buyButton.Text = previousText
					task.delay(0.6, function()
						if buyButton.Parent then
							updateBuyButtonState(buyButton, entry, cachedCoins)
						end
					end)
				end
			end)
		end
	end
end

-- Сервер присылает обновлённый магазин после покупки и периодически
shopRemote.OnClientEvent:Connect(function(entries, coins)
	cachedEntries = entries or cachedEntries
	cachedCoins = tonumber(coins) or cachedCoins

	if isShopOpen then
		renderShop(cachedEntries, cachedCoins)
	end
end)

local function openShop()
	isShopOpen = true
	shopOverlay.Visible = true
	renderShop(cachedEntries, cachedCoins)

	task.spawn(function()
		local payload = getShopRemote:InvokeServer()
		if isShopOpen and payload then
			renderShop(payload.Upgrades, payload.Coins)
		end
	end)
end

local function closeShop()
	isShopOpen = false
	shopOverlay.Visible = false
end

shopButton.MouseEnter:Connect(function()
	TweenService:Create(shopButton, TweenInfo.new(0.12), {
		BackgroundColor3 = C.AccentSoft,
	}):Play()
end)

shopButton.MouseLeave:Connect(function()
	TweenService:Create(shopButton, TweenInfo.new(0.12), {
		BackgroundColor3 = C.Accent,
	}):Play()
end)

shopButton.MouseButton1Click:Connect(function()
	if isShopOpen then
		closeShop()
	else
		openShop()
	end
end)

closeButton.MouseButton1Click:Connect(closeShop)

shopOverlay.MouseButton1Click:Connect(closeShop)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		if isShopOpen then
			closeShop()
		else
			openShop()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape and isShopOpen then
		closeShop()
	end
end)

-- ============================================================
-- ОБНОВЛЕНИЕ ДАННЫХ
-- ============================================================

local displayedCoins = 0
local targetCoins = 0

RunService.RenderStepped:Connect(function(dt)
	if displayedCoins ~= targetCoins then
		local difference = targetCoins - displayedCoins
		displayedCoins += difference * math.min(1, dt * 9)

		if math.abs(targetCoins - displayedCoins) < 0.7 then
			displayedCoins = targetCoins
		end

		coinText.Text = fmt(displayedCoins)
	end
end)

coinsRemote.OnClientEvent:Connect(function(coins, income)
	targetCoins = tonumber(coins) or 0

	if income and income > 0 then
		incomeBaseText.Text = string.format("💰 Доход: %.1f / сек", income)
		incomeBaseText.TextColor3 = C.Good
	else
		incomeBaseText.Text = "💰 Доход: 0 / сек"
		incomeBaseText.TextColor3 = C.Dim
	end
end)

carriedRemote.OnClientEvent:Connect(function(count, capacity, types)
	count = tonumber(count) or 0
	capacity = tonumber(capacity) or 1

	carriedText.Text = string.format("🎒 Рюкзак: %d / %d", count, capacity)

	local ratio = capacity > 0 and math.clamp(count / capacity, 0, 1) or 0
	TweenService:Create(barFill, TweenInfo.new(0.18), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()

	if ratio >= 1 then
		barFill.BackgroundColor3 = C.Bad
	elseif ratio > 0.65 then
		barFill.BackgroundColor3 = Color3.fromRGB(255, 206, 96)
	else
		barFill.BackgroundColor3 = C.Accent
	end

	if count == 0 then
		hintText.Text = "Собирай яйца на рынке в центре"
	elseif ratio >= 1 then
		hintText.Text = "Рюкзак полон — беги на свою базу!"
	else
		hintText.Text = "Яйца крадут другие игроки — успей донести"
	end
end)

-- Показываем маркер «МОЯ БАЗА» только над своей базой
local currentBaseId = nil

local function updateBaseMarker(baseId)
	if baseId == currentBaseId then
		return
	end

	local map = workspace:FindFirstChild("EggGame")
	local basesFolder = map and map:FindFirstChild("Bases")

	if not basesFolder then
		-- Карта ещё не построена — повторим через секунду
		task.delay(1, function()
			updateBaseMarker(baseId)
		end)
		return
	end

	if basesFolder then
		for _, model in ipairs(basesFolder:GetChildren()) do
			if model:IsA("Model") then
				local marker = model:FindFirstChild("MyBaseMarker")
				if marker then
					local markerGui = marker:FindFirstChild("MarkerGui")
					local isMine = (model.Name == "Base_" .. tostring(baseId))
					marker.Transparency = isMine and 0.35 or 1
					if markerGui then
						markerGui.Enabled = isMine
					end
				end
			end
		end
	end

	currentBaseId = baseId
end

baseInfoRemote.OnClientEvent:Connect(function(info)
	if not info then
		vaultText.Text = "🏦 Склада нет"
		updateBaseMarker(nil)
		return
	end

	vaultText.Text = string.format("🏦 Склад: %d / %d", info.VaultTotal or 0, info.Capacity or 0)

	if info.Owners and info.Owners > 1 then
		vaultText.Text ..= string.format("  (общая на %d)", info.Owners)
	end

	updateBaseMarker(info.BaseId)
end)

-- Подгоняем размеры под экран
local function onViewportChanged()
	local viewport = getViewport()
	local scale = math.clamp(viewport.X / 1280, 0.82, 1)

	coinPanel.Size = UDim2.fromOffset(220 * scale, 92 * scale)
	infoPanel.Size = UDim2.fromOffset(236 * scale, 132 * scale)
	shopButton.Size = UDim2.fromOffset(230 * scale, 54 * scale)

	if isMobile() then
		shopHint.Visible = false
	else
		shopHint.Visible = true
	end

	resizeShop()
end

onViewportChanged()

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
end

-- ============================================================
-- ПРИВЕТСТВИЕ
-- ============================================================

task.spawn(function()
	task.wait(1.2)
	toast("🥚 Собирай яйца! 🥚", C.Accent)
	task.wait(2.6)
	toast("Неси их на свою базу 🏦", C.Good)
	task.wait(2.6)
	toast("Магазин улучшений — клавиша B", C.AccentSoft)
end)
