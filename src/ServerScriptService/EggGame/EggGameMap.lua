--[[
	EggGameMap — строит весь мир игры кодом.

	Место в Studio: ServerScriptService -> ModuleScript "EggGameMap"

	МИР:
	  • Круглая арена с ландшафтом (трава, песок, камень)
	  • Рынок в центре: шатры, прилавки, фонари, статуя яйца
	  • 16 баз по кругу с заборами, ящиками и вывесками
	  • Горы по краям, деревья, камни, кусты
	  • Деревянный настил-дорога от рынка к базам
	  • Освещение, атмосфера, небо

	Всё создаётся из частей — никаких внешних моделей не нужно.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("EggGameConfig"))

local Map = {}

-- Реестры объектов, которые анимируются: собираются при постройке,
-- крутятся в отдельном цикле (чтобы не плодить потоки)
Map.AnimatedFlames = {}
Map.AnimatedFires = {}
Map.AnimatedLanterns = {}
Map.Statue = nil

local RNG = Random.new()

-- ============================================================
-- ПАЛИТРА МИРА
-- ============================================================

local PALETTE = {
	GrassDark = Color3.fromRGB(64, 122, 62),
	GrassMid = Color3.fromRGB(84, 146, 76),
	GrassLight = Color3.fromRGB(104, 168, 88),
	Sand = Color3.fromRGB(206, 184, 132),
	SandDark = Color3.fromRGB(178, 154, 104),
	Stone = Color3.fromRGB(126, 128, 134),
	StoneDark = Color3.fromRGB(92, 94, 102),
	Rock = Color3.fromRGB(108, 110, 118),
	Dirt = Color3.fromRGB(128, 100, 72),
	DirtDark = Color3.fromRGB(100, 78, 56),
	Wood = Color3.fromRGB(124, 90, 58),
	WoodDark = Color3.fromRGB(88, 62, 40),
	WoodLight = Color3.fromRGB(158, 120, 78),
	RoofRed = Color3.fromRGB(168, 64, 54),
	RoofOrange = Color3.fromRGB(206, 112, 48),
	RoofBlue = Color3.fromRGB(62, 104, 158),
	Canvas = Color3.fromRGB(232, 218, 186),
	CanvasDark = Color3.fromRGB(198, 178, 142),
	Gold = Color3.fromRGB(255, 196, 64),
	LanternGlow = Color3.fromRGB(255, 212, 132),
	Water = Color3.fromRGB(78, 152, 196),
	LeafA = Color3.fromRGB(58, 138, 78),
	LeafB = Color3.fromRGB(96, 180, 108),
	LeafC = Color3.fromRGB(44, 112, 66),
}

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================

local function newPart(props, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	if parent then
		part.Parent = parent
	end
	return part
end

-- Часть с учётом формы: в Roblox шар/цилиндр масштабируются
-- по минимальной оси, поэтому размер приводим к корректному
local function shapePart(shape, diameter, height, props, parent)
	local part = newPart(props, parent)

	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(diameter, diameter, diameter)
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
		-- Цилиндр в Roblox «лежит» вдоль X
		part.Size = Vector3.new(height, diameter, diameter)
	else
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(diameter, height, diameter)
	end

	return part
end

-- Плоский цилиндр, ось которого смотрит вверх (диск)
local function newDisc(props, parent)
	local part = newPart(props, parent)
	part.Shape = Enum.PartType.Cylinder

	local diameter = props.Radius and props.Radius * 2 or part.Size.Z
	local height = props.Height or 1

	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = (props.CFrame or CFrame.new(props.Position or Vector3.new()))
		* CFrame.Angles(0, 0, math.rad(90))

	return part
end

local function makeBillboard(adornee, text, color, size, offset, font)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = size or UDim2.fromOffset(280, 46)
	gui.StudsOffset = offset or Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = text
	label.Parent = gui

	return gui, label
end

local function makePrompt(parent, actionText, objectText, distance, holdTime)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance or 10
	prompt.HoldDuration = holdTime or 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

-- Точка на окружности
local function ringPoint(radius, angle, y)
	return Vector3.new(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
end

-- ============================================================
-- ЯЙЦО КАК ЧАСТЬ
-- ============================================================

function Map.makeEggPart(eggTypeName, parent)
	local eggType = Config.EggTypes[eggTypeName]
	if not eggType then
		eggTypeName = "Common"
		eggType = Config.EggTypes.Common
	end

	local diameter = math.max(eggType.Size.X, eggType.Size.Z)

	local part = newPart({
		Name = "Egg_" .. eggTypeName,
		Size = Vector3.new(diameter, diameter, diameter),
		Color = eggType.Color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, parent)

	-- Сфера + растяжение по Y = форма яйца
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.34, 1)
	mesh.Parent = part

	-- Блик, чтобы яйцо читалось объёмным
	local shine = Instance.new("Highlight")
	shine.FillColor = eggType.Color
	shine.FillTransparency = 0.82
	shine.OutlineTransparency = 1
	shine.DepthMode = Enum.HighlightDepthMode.Occluded
	shine.Parent = part

	if eggTypeName == "Epic" or eggTypeName == "Legendary" then
		local light = Instance.new("PointLight")
		light.Color = eggType.Color
		light.Range = (eggTypeName == "Legendary") and 16 or 10
		light.Brightness = (eggTypeName == "Legendary") and 2.2 or 1.2
		light.Parent = part
	end

	return part
end

function Map.randomPointInDisc(radius)
	local angle = RNG:NextNumber() * math.pi * 2
	local distance = math.sqrt(RNG:NextNumber()) * radius
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- ============================================================
-- ЛАНДШАФТ
-- ============================================================

local function buildTerrain(folder)
	local size = Config.ArenaSize
	local half = size / 2

	-- Основание (плита под всем, чтобы не было дыр)
	local base = newPart({
		Name = "WorldBase",
		Size = Vector3.new(size + 60, 24, size + 60),
		Position = Vector3.new(0, -13, 0),
		Color = PALETTE.StoneDark,
		Material = Enum.Material.Rock,
		CanCollide = true,
	}, folder)

	-- Основное травяное поле
	local ground = newPart({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		Position = Vector3.new(0, -2, 0),
		Color = PALETTE.GrassMid,
		Material = Enum.Material.Grass,
		CanCollide = true,
	}, folder)

	-- Пятна травы разных оттенков (для живости, без коллизий)
	for i = 1, 46 do
		local point = Map.randomPointInDisc(half - 12)
		local patchSize = 18 + RNG:NextNumber() * 42

		newDisc({
			Name = "GrassPatch",
			Radius = patchSize / 2,
			Height = 0.3,
			Position = Vector3.new(point.X, 0.12, point.Z),
			Color = (i % 3 == 0 and PALETTE.GrassLight)
				or (i % 3 == 1 and PALETTE.GrassDark)
				or PALETTE.GrassMid,
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- Песчаная дорога-кольцо вокруг баз
	newDisc({
		Name = "RingRoad",
		Radius = Config.BaseRingRadius + 26,
		Height = 0.6,
		Position = Vector3.new(0, 0.2, 0),
		Color = PALETTE.SandDark,
		Material = Enum.Material.Sand,
		CanCollide = false,
		CanQuery = false,
	}, folder)

	-- Каменная площадь под рынком
	newDisc({
		Name = "MarketPlaza",
		Radius = Config.MarketRadius + 10,
		Height = 0.9,
		Position = Vector3.new(0, 0.3, 0),
		Color = PALETTE.Stone,
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	}, folder)

	-- Дорожки от рынка к каждой базе
	for i = 1, Config.BasesCount do
		local angle = ((i - 1) / Config.BasesCount) * math.pi * 2
		local from = Config.MarketRadius + 8
		local to = Config.BaseRingRadius - Config.BaseZoneRadius - 2
		local length = to - from
		local middle = (from + to) / 2

		local path = newPart({
			Name = "Path",
			Size = Vector3.new(9, 0.35, length),
			CFrame = CFrame.new(ringPoint(middle, angle, 0.28))
				* CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = PALETTE.Dirt,
			Material = Enum.Material.Ground,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- ===================== ГОРЫ ПО КРАЯМ =====================
	local mountainCount = 26
	for i = 1, mountainCount do
		local angle = (i / mountainCount) * math.pi * 2 + RNG:NextNumber() * 0.15
		local distance = half - RNG:NextNumber() * 26 - 8
		local point = ringPoint(distance, angle, 0)

		local height = 34 + RNG:NextNumber() * 56
		local width = 26 + RNG:NextNumber() * 26

		-- Основание горы
		shapePart("Cylinder", width, height, {
			Name = "Mountain",
			CFrame = CFrame.new(Vector3.new(point.X, height / 2 - 3, point.Z))
				* CFrame.Angles(0, RNG:NextNumber() * math.pi, math.rad(90)),
			Color = PALETTE.Rock:Lerp(PALETTE.StoneDark, RNG:NextNumber()),
			Material = Enum.Material.Rock,
			CanCollide = true,
		}, folder)

		-- Вершина (снег)
		shapePart("Ball", width * 0.55, width * 0.55, {
			Name = "Peak",
			Position = Vector3.new(point.X, height - 6, point.Z),
			Color = Color3.fromRGB(232, 238, 245),
			Material = Enum.Material.Snow,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- ===================== СТЕНЫ ПО ПЕРИМЕТРУ =====================
	-- Невысокие, чтобы не закрывать вид на горы
	local wallHeight = 26
	local wallThickness = 8
	local wallDefs = {
		{ Vector3.new(0, wallHeight / 2 - 1, -half - wallThickness / 2), Vector3.new(size + wallThickness * 2, wallHeight, wallThickness) },
		{ Vector3.new(0, wallHeight / 2 - 1, half + wallThickness / 2), Vector3.new(size + wallThickness * 2, wallHeight, wallThickness) },
		{ Vector3.new(-half - wallThickness / 2, wallHeight / 2 - 1, 0), Vector3.new(wallThickness, wallHeight, size) },
		{ Vector3.new(half + wallThickness / 2, wallHeight / 2 - 1, 0), Vector3.new(wallThickness, wallHeight, size) },
	}

	for index, def in ipairs(wallDefs) do
		newPart({
			Name = "BoundaryWall" .. index,
			Size = def[2],
			Position = def[1],
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Rock,
			CanCollide = true,
		}, folder)
	end
end

-- ============================================================
-- РЫНОК
-- ============================================================

local function buildMarket(folder)
	local R = Config.MarketRadius

	-- Центральный постамент
	newDisc({
		Name = "PedestalBase",
		Radius = 7,
		Height = 3.2,
		Position = Vector3.new(0, 2, 0),
		Color = PALETTE.Stone,
		Material = Enum.Material.Marble,
		CanCollide = true,
	}, folder)

	newDisc({
		Name = "PedestalTop",
		Radius = 5.2,
		Height = 1.2,
		Position = Vector3.new(0, 4, 0),
		Color = PALETTE.StoneDark,
		Material = Enum.Material.Marble,
		CanCollide = true,
	}, folder)

	-- Статуя яйца
	local statue = Map.makeEggPart("Legendary", folder)
	statue.Name = "MarketStatue"
	statue.Size = Vector3.new(4.4, 4.4, 4.4)
	statue.Position = Vector3.new(0, 7.4, 0)

	-- Свечение вокруг статуи
	local statueLight = Instance.new("PointLight")
	statueLight.Color = PALETTE.Gold
	statueLight.Range = 40
	statueLight.Brightness = 3
	statueLight.Parent = statue

	Map.Statue = statue

	-- ===================== ШАТРЫ =====================
	local tentsCount = 8
	for i = 1, tentsCount do
		local angle = ((i - 1) / tentsCount) * math.pi * 2 + math.pi / tentsCount
		local point = ringPoint(R - 4, angle, 0)

		local tent = Instance.new("Model")
		tent.Name = "Tent_" .. i
		tent.Parent = folder

		-- основание
		newPart({
			Name = "Floor",
			Size = Vector3.new(15, 0.7, 15),
			CFrame = CFrame.new(point + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.WoodLight,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		}, tent)

		-- 4 столба
		for pillar = 1, 4 do
			local offsetX = (pillar <= 2) and -6.2 or 6.2
			local offsetZ = (pillar % 2 == 1) and -6.2 or 6.2

			local local_ = CFrame.new(point) * CFrame.Angles(0, -angle, 0)

			newPart({
				Name = "Pillar",
				Size = Vector3.new(0.9, 12, 0.9),
				Position = (local_ * CFrame.new(offsetX, 6.4, offsetZ)).Position,
				Color = PALETTE.Wood,
				Material = Enum.Material.Wood,
				CanCollide = true,
			}, tent)
		end

		-- навес
		local canopyColors = { PALETTE.RoofRed, PALETTE.RoofOrange, PALETTE.RoofBlue }
		newPart({
			Name = "Canopy",
			Size = Vector3.new(16, 1.1, 16),
			CFrame = CFrame.new(point + Vector3.new(0, 12.6, 0)) * CFrame.Angles(0, -angle, 0),
			Color = canopyColors[(i % 3) + 1],
			Material = Enum.Material.Fabric,
			CanCollide = true,
		}, tent)

		-- верхушка навеса
		newPart({
			Name = "CanopyTop",
			Size = Vector3.new(9, 2.4, 9),
			CFrame = CFrame.new(point + Vector3.new(0, 14, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.CanvasDark,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CanQuery = false,
		}, tent)

		-- прилавок внутри
		newPart({
			Name = "Counter",
			Size = Vector3.new(7, 3, 2.2),
			CFrame = CFrame.new(point + Vector3.new(0, 3.4, 3.4)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.WoodDark,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		}, tent)

		-- товар на прилавке (декоративные яйца)
		for item = 1, 3 do
			local egg = Map.makeEggPart(({ "Common", "Rare", "Epic" })[item], tent)
			egg.Anchored = true
			egg.Size = egg.Size * 0.42
			egg.Position = (CFrame.new(point + Vector3.new(0, 5.2, 3.4)) * CFrame.Angles(0, -angle, 0)
				* CFrame.new((item - 2) * 2, 0, 0)).Position
		end

		-- флажок
		newPart({
			Name = "Flag",
			Size = Vector3.new(3.4, 2, 0.3),
			CFrame = CFrame.new(point + Vector3.new(0, 16.4, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.Gold,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CanQuery = false,
		}, tent)
	end

	-- ===================== ФОНАРИ =====================
	local lanternCount = 12
	for i = 1, lanternCount do
		local angle = ((i - 1) / lanternCount) * math.pi * 2
		local point = ringPoint(R + 6, angle, 0)

		-- столб
		newPart({
			Name = "LanternPost",
			Size = Vector3.new(0.8, 13, 0.8),
			Position = point + Vector3.new(0, 6.5, 0),
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, folder)

		-- светильник
		local bulb = shapePart("Ball", 2.2, 2.2, {
			Name = "Lantern",
			Position = point + Vector3.new(0, 13.6, 0),
			Color = PALETTE.LanternGlow,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, folder)

		local light = Instance.new("PointLight")
		light.Color = PALETTE.LanternGlow
		light.Range = 34
		light.Brightness = 1.8
		light.Shadows = true
		light.Parent = bulb

		table.insert(Map.AnimatedLanterns, bulb)
		table.insert(Map.AnimatedFires, light)
	end

	-- ===================== ГИРЛЯНДА =====================
	-- Провисающие лампочки между фонарями
	for i = 1, lanternCount do
		local angleA = ((i - 1) / lanternCount) * math.pi * 2
		local angleB = (i / lanternCount) * math.pi * 2

		local pointA = ringPoint(R + 6, angleA, 12.6)
		local pointB = ringPoint(R + 6, angleB, 12.6)

		local segments = 5
		for segment = 1, segments do
			local t1 = (segment - 1) / segments
			local t2 = segment / segments

			local function lerpDrop(t, point)
				local sag = math.sin(t * math.pi) * 1.8
				return point + Vector3.new(0, -sag, 0)
			end

			local a = pointA:Lerp(pointB, t1)
			local b = pointA:Lerp(pointB, t2)
			a = lerpDrop(t1, a)
			b = lerpDrop(t2, b)

			local middle = (a + b) / 2
			local length = (b - a).Magnitude

			local wire = newPart({
				Name = "Wire",
				Size = Vector3.new(length, 0.14, 0.14),
				CFrame = CFrame.new(middle, b),
				Color = PALETTE.StoneDark,
				Material = Enum.Material.Metal,
				CanCollide = false,
				CanQuery = false,
			}, folder)

			if segment == 3 then
				local bulb = shapePart("Ball", 0.85, 0.85, {
					Name = "Bulb",
					Position = a,
					Color = PALETTE.Gold,
					Material = Enum.Material.Neon,
					CanCollide = false,
					CanQuery = false,
				}, folder)

				table.insert(Map.AnimatedLanterns, bulb)
			end
		end
	end

	-- ===================== СПАВН =====================
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "PlayerSpawn"
	spawnLocation.Size = Vector3.new(18, 1.2, 18)
	spawnLocation.Position = Vector3.new(0, 1.4, 18)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 0.55
	spawnLocation.Color = PALETTE.Gold
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = folder

	-- кольцо вокруг спавна
	newDisc({
		Name = "SpawnRing",
		Radius = 11,
		Height = 0.35,
		Position = Vector3.new(0, 0.85, 18),
		Color = PALETTE.Gold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	}, folder)
end

-- ============================================================
-- БАЗЫ
-- ============================================================

local function buildBases(folder)
	local bases = {}

	for index = 1, Config.BasesCount do
		local angle = ((index - 1) / Config.BasesCount) * math.pi * 2
		local center = ringPoint(Config.BaseRingRadius, angle, 0)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local inward = -outward
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))

		local model = Instance.new("Model")
		model.Name = "Base_" .. index
		model.Parent = folder

		local zoneR = Config.BaseZoneRadius

		-- ===================== ПЛОЩАДКА =====================
		local platform = newDisc({
			Name = "Platform",
			Radius = zoneR + 2,
			Height = 1.2,
			Position = center + Vector3.new(0, 0.6, 0),
			Color = PALETTE.Sand,
			Material = Enum.Material.Sand,
			CanCollide = true,
		}, model)

		-- каменная окантовка
		local glow = newDisc({
			Name = "Glow",
			Radius = zoneR + 3.4,
			Height = 0.25,
			Position = center + Vector3.new(0, 0.8, 0),
			Color = Color3.fromRGB(180, 190, 200),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, model)

		-- ===================== СКЛАД =====================
		-- деревянный стол
		newPart({
			Name = "VaultStand",
			Size = Vector3.new(11, 3.6, 11),
			CFrame = CFrame.new(center + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.DirtDark,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		}, model)

		local vaultTop = newPart({
			Name = "VaultTop",
			Size = Vector3.new(10.4, 0.9, 10.4),
			CFrame = CFrame.new(center + Vector3.new(0, 4.9, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.WoodLight,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		}, model)

		local vaultGlow = newPart({
			Name = "VaultGlow",
			Size = Vector3.new(11.4, 0.3, 11.4),
			CFrame = CFrame.new(center + Vector3.new(0, 5.3, 0)) * CFrame.Angles(0, -angle, 0),
			Color = PALETTE.Gold,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, model)

		local _, vaultLabel = makeBillboard(
			vaultTop, "🏦 0", Color3.fromRGB(255, 232, 156), UDim2.fromOffset(300, 52), Vector3.new(0, 3.6, 0)
		)

		local stealPrompt = makePrompt(vaultTop, "Украсть яйца", "Чужой склад", 13, Config.RaidHoldTime)

		-- ===================== ВЫВЕСКА =====================
		local signPos = center + inward * (zoneR - 1)

		newPart({
			Name = "SignPost",
			Size = Vector3.new(1.1, 15, 1.1),
			CFrame = CFrame.new(signPos + Vector3.new(0, 8, 0)),
			Color = PALETTE.WoodDark,
			Material = Enum.Material.Wood,
			CanCollide = true,
		}, model)

		local signBoard = newPart({
			Name = "SignBoard",
			Size = Vector3.new(15, 6, 0.9),
			CFrame = CFrame.new(signPos + Vector3.new(0, 16, 0), Vector3.new(0, signPos.Y + 16, 0)),
			Color = PALETTE.WoodDark,
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
		}, model)

		local _, signLabel = makeBillboard(
			signBoard, "Свободная база", Color3.new(1, 1, 1), UDim2.fromOffset(360, 74), Vector3.new(0, 0, 0.7)
		)

		-- ===================== ЗАБОР =====================
		local fenceSegments = 14
		for fence = 1, fenceSegments do
			local fenceAngle = (fence / fenceSegments) * math.pi * 2
			local fencePoint = center + Vector3.new(
				math.cos(fenceAngle) * (zoneR + 1.4),
				1.1,
				math.sin(fenceAngle) * (zoneR + 1.4)
			)

			-- оставляем проход со стороны рынка
			local toMarket = (Math and 0) or 0
			local angleToMarket = math.atan2(-center.Z, -center.X)
			local diff = math.abs(((fenceAngle - angleToMarket + math.pi) % (math.pi * 2)) - math.pi)

			if diff > 0.42 then
				newPart({
					Name = "FencePost",
					Size = Vector3.new(0.7, 3.4, 0.7),
					CFrame = CFrame.new(fencePoint),
					Color = PALETTE.WoodDark,
					Material = Enum.Material.Wood,
					CanCollide = false,
					CanQuery = false,
				}, model)
			end
		end

		-- ===================== ЯЩИКИ И БОЧКИ =====================
		for crate = 1, 3 do
			local side = (crate == 1) and 1 or -1
			local crateAngle = angle + side * (0.5 + crate * 0.12)
			local cratePoint = ringPoint(Config.BaseRingRadius + zoneR - 3, crateAngle, 0)

			if crate == 3 then
				-- бочка
				shapePart("Cylinder", 3.2, 4.2, {
					Name = "Barrel",
					CFrame = CFrame.new(cratePoint + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = PALETTE.WoodDeep or PALETTE.Wood,
					Material = Enum.Material.Wood,
					CanCollide = true,
				}, model)
			else
				newPart({
					Name = "Crate",
					Size = Vector3.new(3.4, 3.4, 3.4),
					CFrame = CFrame.new(cratePoint + Vector3.new(0, 2.5, 0))
						* CFrame.Angles(0, math.rad(crate * 24 + index * 13), 0),
					Color = PALETTE.Wood,
					Material = Enum.Material.WoodPlanks,
					CanCollide = true,
				}, model)
			end
		end

		-- ===================== КОСТЁР =====================
		local firePos = center + ringPoint(zoneR + 7, angle + 0.7, 0) - center
		firePos = center + Vector3.new(firePos.X, 0, firePos.Z)

		local fireBase = shapePart("Cylinder", 4.6, 0.9, {
			Name = "CampfireBase",
			CFrame = CFrame.new(firePos + Vector3.new(0, 0.7, 0)),
			Color = PALETTE.Stone,
			Material = Enum.Material.Cobblestone,
			CanCollide = false,
		}, model)

		local flame = shapePart("Ball", 1.9, 1.9, {
			Name = "Flame",
			Position = firePos + Vector3.new(0, 2.2, 0),
			Color = Color3.fromRGB(255, 146, 46),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, model)

		local fireLight = Instance.new("PointLight")
		fireLight.Color = Color3.fromRGB(255, 156, 60)
		fireLight.Range = 26
		fireLight.Brightness = 2
		fireLight.Parent = flame

		-- поленья
		for log = 1, 4 do
			local logAngle = (log / 4) * math.pi * 2
			newPart({
				Name = "Log",
				Size = Vector3.new(1.1, 1.1, 4.6),
				CFrame = CFrame.new(firePos + Vector3.new(math.cos(logAngle) * 1.4, 1.2, math.sin(logAngle) * 1.4))
					* CFrame.Angles(math.rad(20), logAngle, 0),
				Color = PALETTE.WoodDark,
				Material = Enum.Material.Wood,
				CanCollide = false,
				CanQuery = false,
			}, model)
		end

			-- костёр регистрируем для анимации мерцания
		table.insert(Map.AnimatedFlames, flame)
		table.insert(Map.AnimatedFires, fireLight)

		-- ===================== МАРКЕР «МОЯ БАЗА» =====================
		local marker = shapePart("Ball", 6, 6, {
			Name = "MyBaseMarker",
			Position = center + Vector3.new(0, 44, 0),
			Color = Config.Colors.MyBase,
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		}, model)

		local markerGui = Instance.new("BillboardGui")
		markerGui.Name = "MarkerGui"
		markerGui.Size = UDim2.fromOffset(240, 58)
		markerGui.StudsOffset = Vector3.new(0, 6.5, 0)
		markerGui.AlwaysOnTop = true
		markerGui.MaxDistance = 900
		markerGui.LightInfluence = 0
		markerGui.Adornee = marker
		markerGui.Enabled = false
		markerGui.Parent = marker

		local markerLabel = Instance.new("TextLabel")
		markerLabel.Size = UDim2.fromScale(1, 1)
		markerLabel.BackgroundTransparency = 1
		markerLabel.Font = Enum.Font.GothamBlack
		markerLabel.Text = "МОЯ БАЗА"
		markerLabel.TextScaled = true
		markerLabel.TextColor3 = Config.Colors.MyBase
		markerLabel.TextStrokeTransparency = 0.15
		markerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		markerLabel.Parent = markerGui

		table.insert(bases, {
			Id = index,
			Model = model,
			Center = center,
			Platform = platform,
			Glow = glow,
			SignLabel = signLabel,
			VaultTop = vaultTop,
			VaultGlow = vaultGlow,
			VaultLabel = vaultLabel,
			StealPrompt = stealPrompt,
			Marker = marker,
			MarkerGui = markerGui,
			Owners = {},
			Vault = {},
			VaultTotal = 0,
			VisualEggs = {},
			RateAccum = {},
			IncomePerSecond = 0,
			FirePos = firePos,
		})
	end

	return bases
end

-- ============================================================
-- ПРИРОДА
-- ============================================================

local function buildTree(folder, position, scale)
	scale = scale or 1

	local trunkHeight = (9 + RNG:NextNumber() * 7) * scale
	local trunkWidth = (2.4 + RNG:NextNumber() * 1.2) * scale

	local tree = Instance.new("Model")
	tree.Name = "Tree"
	tree.Parent = folder

	-- ствол
	shapePart("Cylinder", trunkWidth, trunkHeight, {
		Name = "Trunk",
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.Wood:Lerp(PALETTE.WoodDark, RNG:NextNumber()),
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, tree)

	-- крона из 3 шаров
	local leafColors = { PALETTE.LeafA, PALETTE.LeafB, PALETTE.LeafC }

	for layer = 1, 3 do
		local layerSize = (10 - layer * 2.2 + RNG:NextNumber() * 1.6) * scale

		shapePart("Ball", layerSize, layerSize, {
			Name = "Leaves",
			Position = position + Vector3.new(
				(RNG:NextNumber() - 0.5) * 2.6 * scale,
				trunkHeight + (layer - 1) * 2.8 * scale - 1.6 * scale,
				(RNG:NextNumber() - 0.5) * 2.6 * scale
			),
			Color = leafColors[RNG:NextInteger(1, 3)],
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, tree)
	end

	return tree
end

local function buildNature(folder)
	local half = Config.ArenaSize / 2

	-- ===================== ДЕРЕВЬЯ =====================
	local treeCount = 52
	for i = 1, treeCount do
		local angle = RNG:NextNumber() * math.pi * 2
		local distance = Config.BaseRingRadius + Config.BaseZoneRadius + 16
			+ RNG:NextNumber() * (half - Config.BaseRingRadius - Config.BaseZoneRadius - 40)

		distance = math.min(distance, half - 22)
		local point = ringPoint(distance, angle, 0)

		buildTree(folder, point, 0.8 + RNG:NextNumber() * 0.7)
	end

	-- пара деревьев внутри кольца баз (для уюта)
	for i = 1, 8 do
		local point = Map.randomPointInDisc(Config.BaseRingRadius - Config.BaseZoneRadius - 14)
		if point.Magnitude > Config.MarketRadius + 12 then
			buildTree(folder, point, 0.7 + RNG:NextNumber() * 0.5)
		end
	end

	-- ===================== КАМНИ =====================
	for i = 1, 60 do
		local angle = RNG:NextNumber() * math.pi * 2
		local distance = Config.MarketRadius + 14 + RNG:NextNumber() * (half - Config.MarketRadius - 40)
		local point = ringPoint(distance, angle, 0)

		local rockSize = 2 + RNG:NextNumber() * 5
		shapePart("Ball", rockSize, rockSize, {
			Name = "Rock",
			CFrame = CFrame.new(point + Vector3.new(0, rockSize / 3, 0))
				* CFrame.Angles(RNG:NextNumber(), RNG:NextNumber(), RNG:NextNumber()),
			Color = PALETTE.Rock:Lerp(PALETTE.Stone, RNG:NextNumber()),
			Material = Enum.Material.Rock,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- ===================== КУСТЫ =====================
	for i = 1, 80 do
		local angle = RNG:NextNumber() * math.pi * 2
		local distance = Config.MarketRadius + 10 + RNG:NextNumber() * (half - Config.MarketRadius - 30)
		local point = ringPoint(distance, angle, 0)

		local bushSize = 1.8 + RNG:NextNumber() * 2.2
		shapePart("Ball", bushSize, bushSize, {
			Name = "Bush",
			CFrame = CFrame.new(point + Vector3.new(0, bushSize / 2.4, 0))
				* CFrame.Angles(RNG:NextNumber(), RNG:NextNumber(), RNG:NextNumber()),
			Color = PALETTE.LeafC:Lerp(PALETTE.LeafA, RNG:NextNumber()),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- ===================== ЦВЕТЫ =====================
	local flowerColors = {
		Color3.fromRGB(255, 120, 140),
		Color3.fromRGB(255, 216, 96),
		Color3.fromRGB(196, 132, 255),
		Color3.fromRGB(120, 200, 255),
		Color3.fromRGB(255, 255, 255),
	}

	for i = 1, 140 do
		local angle = RNG:NextNumber() * math.pi * 2
		local distance = Config.MarketRadius + 8 + RNG:NextNumber() * (half - Config.MarketRadius - 30)
		local point = ringPoint(distance, angle, 0)

		shapePart("Ball", 0.75, 0.75, {
			Name = "Flower",
			Position = point + Vector3.new(0, 1.1, 0),
			Color = flowerColors[RNG:NextInteger(1, #flowerColors)],
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end

	-- ===================== ПРУД =====================
	local pondPos = Vector3.new(-Config.BaseRingRadius - 8, 0, Config.BaseRingRadius - 30)

	newDisc({
		Name = "PondEdge",
		Radius = 24,
		Height = 0.8,
		Position = pondPos + Vector3.new(0, 0.4, 0),
		Color = PALETTE.SandDark,
		Material = Enum.Material.Sand,
		CanCollide = false,
		CanQuery = false,
	}, folder)

	local pond = newDisc({
		Name = "PondWater",
		Radius = 21,
		Height = 0.5,
		Position = pondPos + Vector3.new(0, 0.55, 0),
		Color = PALETTE.Water,
		Material = Enum.Material.Glass,
		CanCollide = false,
		CanQuery = false,
	}, folder)
	pond.Transparency = 0.25

	-- камыши
	for i = 1, 12 do
		local a = RNG:NextNumber() * math.pi * 2
		local r = 19 + RNG:NextNumber() * 3
		newPart({
			Name = "Reed",
			Size = Vector3.new(0.34, 3 + RNG:NextNumber() * 2, 0.34),
			Position = pondPos + Vector3.new(math.cos(a) * r, 2, math.sin(a) * r),
			Color = PALETTE.LeafC,
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end
end

-- ============================================================
-- Освещение и атмосфера
-- ============================================================

local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(104, 110, 136)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 180)
	Lighting.Brightness = 2.6
	Lighting.ClockTime = 14.6
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.45
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 1800
	Lighting.FogStart = 700
	Lighting.ShadowSoftness = 0.4

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.18
	atmosphere.Color = Color3.fromRGB(212, 220, 238)
	atmosphere.Decay = Color3.fromRGB(126, 148, 190)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.1

	-- Blur и Bloom делают картинку «дороже»
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.05

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = 0.14
	colorCorrection.TintColor = Color3.fromRGB(255, 250, 244)

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Parent = Lighting
	end
	sunRays.Intensity = 0.12
	sunRays.Spread = 0.9
end

-- ============================================================
-- Табло лидеров
-- ============================================================

local function buildLeaderboard(folder, position, facing)
	local stand = newPart({
		Name = "LeaderboardStand",
		Size = Vector3.new(1.6, 20, 1.6),
		Position = position + Vector3.new(0, 10, 0),
		Color = PALETTE.StoneDark,
		Material = Enum.Material.Metal,
		CanCollide = true,
	}, folder)

	local board = newPart({
		Name = "Leaderboard",
		Size = Vector3.new(24, 15, 1.2),
		CFrame = CFrame.new(position + Vector3.new(0, 25, 0), facing),
		Color = Color3.fromRGB(24, 28, 38),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, folder)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardGui"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(640, 400)
	surface.LightInfluence = 0
	surface.Adornee = board
	surface.Parent = board

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 19, 27)
	frame.BorderSizePixel = 0
	frame.Parent = surface

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "🏆 ЛУЧШИЕ ВОРЫ ЯИЦ"
	title.TextScaled = true
	title.TextColor3 = PALETTE.Gold
	title.Parent = frame

	local list = Instance.new("TextLabel")
	list.Position = UDim2.new(0.05, 0, 0.19, 0)
	list.Size = UDim2.new(0.9, 0, 0.76, 0)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.GothamBold
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextSize = 22
	list.TextWrapped = true
	list.TextColor3 = Color3.fromRGB(238, 242, 255)
	list.Text = "Ждём игроков..."
	list.Parent = frame

	return list
end

-- ============================================================
-- ГЛАВНАЯ СБОРКА
-- ============================================================

function Map.build()
	local oldMap = Workspace:FindFirstChild("EggGame")
	if oldMap then
		oldMap:Destroy()
	end

	-- Убираем всё лишнее: стандартные объекты и статичное превью мира,
	-- которое лежало в файле для отображения без запуска игры
	for _, child in ipairs(Workspace:GetChildren()) do
		local name = child.Name
		if name == "Baseplate"
			or name == "SpawnLocation"
			or name == "FallbackFloor"
			or name == "FallbackSpawn"
			or name == "EggGamePreview" then
			child:Destroy()
		end
	end

	setupLighting()

	local root = Instance.new("Folder")
	root.Name = "EggGame"
	root.Parent = Workspace

	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	local terrainFolder = folder("Terrain")
	local marketFolder = folder("Market")
	local basesFolder = folder("Bases")
	local natureFolder = folder("Nature")
	local eggsFolder = folder("Eggs")
	local vaultEggsFolder = folder("VaultEggs")
	local carriedFolder = folder("Carried")

	buildTerrain(terrainFolder)
	buildMarket(marketFolder)

	local bases = buildBases(basesFolder)

	buildNature(natureFolder)

	-- Табло ставим сбоку от рынка, лицом к спавну
	local boardPos = Vector3.new(-Config.MarketRadius - 14, 0, 4)
	local leaderboardList = buildLeaderboard(
		marketFolder,
		boardPos,
		Vector3.new(0, boardPos.Y + 25, 0)
	)

	return {
		Root = root,
		Terrain = terrainFolder,
		Market = marketFolder,
		BasesFolder = basesFolder,
		Nature = natureFolder,
		Eggs = eggsFolder,
		VaultEggs = vaultEggsFolder,
		Carried = carriedFolder,
		BasesData = bases,
		MarketCenter = Vector3.new(0, 0, 0),
		LeaderboardList = leaderboardList,
	}
end

-- ============================================================
-- АНИМАЦИЯ МИРА
-- ============================================================

--[[
	Одна функция на весь мир: вращает статую, мерцает кострами,
	пульсирует фонарями. Запускается один раз, работает на RunService.

	CFrame статуи и Transparency меняются на сервере — клиенты видят
	результат без задержек, потому что части Anchored.
]]
function Map.startAnimations()
	local RunService = game:GetService("RunService")

	local elapsed = 0

	-- Базовые значения, чтобы мерцание было вокруг них
	local fireBase = {}
	for index, light in ipairs(Map.AnimatedFires) do
		fireBase[index] = light.Brightness or 1.5
	end

	local lanternBase = {}
	for index, bulb in ipairs(Map.AnimatedLanterns) do
		lanternBase[index] = bulb.Color or PALETTE.LanternGlow
	end

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		-- 1. Статуя медленно вращается
		local statue = Map.Statue
		if statue and statue.Parent then
			statue.CFrame = CFrame.new(statue.Position)
				* CFrame.Angles(0, elapsed * 0.55, math.rad(12 * math.sin(elapsed * 0.6)))
		end

		-- 2. Костры мерцают (яркость + лёгкое покачивание)
		for index, light in ipairs(Map.AnimatedFires) do
			if light.Parent then
				local base = fireBase[index] or 1.5
				local wobble = math.sin(elapsed * 7.3 + index * 1.7) * 0.28
					+ math.sin(elapsed * 13.1 + index * 2.9) * 0.14
				light.Brightness = math.max(0.2, base + wobble)
			end
		end

		-- 3. Пламя чуть «дышит»
		for index, flame in ipairs(Map.AnimatedFlames) do
			if flame.Parent then
				local pulse = 1 + math.sin(elapsed * 5.5 + index * 2.1) * 0.09
				flame.Size = Vector3.new(1.9, 1.9, 1.9) * pulse
			end
		end

		-- 4. Лампочки гирлянды плавно перемигиваются
		for index, bulb in ipairs(Map.AnimatedLanterns) do
			if bulb.Parent then
				local base = lanternBase[index] or PALETTE.LanternGlow
				local phase = math.sin(elapsed * 2.2 + index * 0.9) * 0.5 + 0.5
				bulb.Color = base:Lerp(Color3.fromRGB(255, 252, 236), phase * 0.45)
			end
		end
	end)
end

return Map
