--[[
	EggGameMap — строит всю карту кодом. Руками ничего расставлять не нужно.

	Место в Studio: ServerScriptService -> ModuleScript "EggGameMap"

	Создаёт в Workspace/EggGame:
	  Arena       — пол, стены, деревья
	  Market      — рынок в центре, точка спавна игроков
	  Bases       — 16 баз по кругу: площадка, склад, вывеска
	  Eggs        — яйца, лежащие на рынке
	  VaultEggs   — яйца, лежащие на складах баз
	  Carried     — яйца в руках/за спиной игроков
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("EggGameConfig"))

local Map = {}

local RNG = Random.new()

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================

local function newPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

-- Плоский цилиндр, лежащий горизонтально (ось цилиндра смотрит вверх)
local function newDisc(name, position, radius, height, color, parent)
	local disc = newPart({
		Name = name,
		Size = Vector3.new(height, radius * 2, radius * 2),
		Color = color,
		CanCollide = true,
		Material = Enum.Material.Slate,
	})
	disc.Shape = Enum.PartType.Cylinder
	disc.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = parent
	return disc
end

local function makeBillboard(adornee, text, color, size, offset)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = size or UDim2.fromOffset(280, 46)
	gui.StudsOffset = offset or Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
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

-- ============================================================
-- ЯЙЦО КАК ЧАСТЬ
-- ============================================================

function Map.makeEggPart(eggTypeName, parent)
	local eggType = Config.EggTypes[eggTypeName]
	if not eggType then
		eggTypeName = "Common"
		eggType = Config.EggTypes.Common
	end

	-- Шар: в Roblox шар рендерится по минимальной оси,
	-- поэтому берём ровный размер, чтобы не было сюрпризов
	local diameter = math.max(eggType.Size.X, eggType.Size.Z)

	local part = newPart({
		Name = "Egg_" .. eggTypeName,
		Size = Vector3.new(diameter, diameter, diameter),
		Color = eggType.Color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	-- SpecialMesh со сферой + растяжение по Y даёт форму яйца
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.32, 1)
	mesh.Parent = part

	part.Parent = parent

	if eggTypeName == "Epic" or eggTypeName == "Legendary" then
		local light = Instance.new("PointLight")
		light.Color = eggType.Color
		light.Range = (eggTypeName == "Legendary") and 14 or 9
		light.Brightness = (eggTypeName == "Legendary") and 2 or 1
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
-- ПОСТРОЙКА КАРТЫ
-- ============================================================

function Map.build()
	local oldMap = Workspace:FindFirstChild("EggGame")
	if oldMap then
		oldMap:Destroy()
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == "Baseplate" or child.Name == "SpawnLocation" then
			child:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "EggGame"
	root.Parent = Workspace

	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	local arenaFolder = folder("Arena")
	local marketFolder = folder("Market")
	local basesFolder = folder("Bases")
	local eggsFolder = folder("Eggs")
	local vaultEggsFolder = folder("VaultEggs")
	local carriedFolder = folder("Carried")

	-- ===================== СВЕТ =====================
	Lighting.Ambient = Color3.fromRGB(96, 102, 128)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 138, 168)
	Lighting.Brightness = 2.5
	Lighting.ClockTime = 15.2
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 1400
	Lighting.FogStart = 400

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(205, 214, 232)
	atmosphere.Decay = Color3.fromRGB(125, 145, 185)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4

	-- ===================== ПОЛ И СТЕНЫ =====================
	local arenaSize = Config.ArenaSize

	local floor = newPart({
		Name = "Floor",
		Size = Vector3.new(arenaSize, 6, arenaSize),
		Position = Vector3.new(0, -3, 0),
		Color = Config.Colors.Floor,
		Material = Enum.Material.Grass,
		CanCollide = true,
	})
	floor.Parent = arenaFolder

	local baseRing = newDisc("BaseRing", Vector3.new(0, 0.05, 0), Config.BaseRingRadius + 30, 0.12, Color3.fromRGB(88, 100, 120), arenaFolder)
	baseRing.CanCollide = false
	baseRing.Material = Enum.Material.Concrete

	local wallHeight = 20
	local wallThickness = 5
	local halfSize = arenaSize / 2
	local wallDefs = {
		{ Vector3.new(0, wallHeight / 2, -halfSize), Vector3.new(arenaSize + wallThickness, wallHeight, wallThickness) },
		{ Vector3.new(0, wallHeight / 2, halfSize), Vector3.new(arenaSize + wallThickness, wallHeight, wallThickness) },
		{ Vector3.new(-halfSize, wallHeight / 2, 0), Vector3.new(wallThickness, wallHeight, arenaSize) },
		{ Vector3.new(halfSize, wallHeight / 2, 0), Vector3.new(wallThickness, wallHeight, arenaSize) },
	}
	for index, def in ipairs(wallDefs) do
		local wall = newPart({
			Name = "Wall" .. index,
			Size = def[2],
			Position = def[1],
			Color = Config.Colors.Wall,
			Material = Enum.Material.Concrete,
			CanCollide = true,
		})
		wall.Parent = arenaFolder
	end

	-- ===================== РЫНОК =====================
	local marketFloor = newDisc("MarketFloor", Vector3.new(0, 0.3, 0), Config.MarketRadius + 5, 1.2, Color3.fromRGB(126, 112, 96), marketFolder)
	marketFloor.Material = Enum.Material.Cobblestone

	local marketGlow = newDisc("MarketGlow", Vector3.new(0, 0.95, 0), Config.MarketRadius + 6.5, 0.14, Config.Colors.Market, marketFolder)
	marketGlow.Material = Enum.Material.Neon
	marketGlow.CanCollide = false

	-- Центральный постамент с огромным яйцом-памятником
	local pedestal = newDisc("Pedestal", Vector3.new(0, 1.6, 0), 5.5, 2.6, Color3.fromRGB(152, 134, 114), marketFolder)
	pedestal.Material = Enum.Material.Marble

	local statue = Map.makeEggPart("Legendary", marketFolder)
	statue.Name = "MarketStatue"
	statue.Size = Vector3.new(4.6, 5.4, 4.6)
	statue.Position = Vector3.new(0, 6.4, 0)

	-- Фонари по кругу
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (Config.MarketRadius + 3.5)

		local post = newPart({
			Name = "LanternPost",
			Size = Vector3.new(0.9, 10, 0.9),
			Position = position + Vector3.new(0, 5, 0),
			Color = Color3.fromRGB(46, 42, 40),
			Material = Enum.Material.Metal,
			CanCollide = true,
		})
		post.Parent = marketFolder

		local bulb = newPart({
			Name = "Lantern",
			Size = Vector3.new(1.9, 1.9, 1.9),
			Position = position + Vector3.new(0, 10.4, 0),
			Color = Config.Colors.Market,
			Material = Enum.Material.Neon,
		})
		bulb.Shape = Enum.PartType.Ball
		bulb.Parent = marketFolder

		local light = Instance.new("PointLight")
		light.Color = Config.Colors.Market
		light.Range = 30
		light.Brightness = 1.6
		light.Parent = bulb
	end

	-- Точка спавна игроков
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "PlayerSpawn"
	spawnLocation.Size = Vector3.new(16, 1, 16)
	spawnLocation.Position = Vector3.new(0, 1.4, 16)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 0.6
	spawnLocation.Color = Config.Colors.Market
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = marketFolder

	-- ===================== БАЗЫ =====================
	local bases = {}

	for index = 1, Config.BasesCount do
		local angle = ((index - 1) / Config.BasesCount) * math.pi * 2
		local center = Vector3.new(math.cos(angle) * Config.BaseRingRadius, 0, math.sin(angle) * Config.BaseRingRadius)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local model = Instance.new("Model")
		model.Name = "Base_" .. index
		model.Parent = basesFolder

		local platform = newDisc("Platform", center + Vector3.new(0, 0.4, 0), Config.BaseZoneRadius + 1.5, 0.9, Config.Colors.FreeBase, model)
		platform.Material = Enum.Material.Sand
		platform.CanCollide = true

		local glow = newDisc("Glow", center + Vector3.new(0, 0.09, 0), Config.BaseZoneRadius + 2.6, 0.12, Config.Colors.FreeBase, model)
		glow.Material = Enum.Material.Neon
		glow.CanCollide = false

		-- Вывеска владельца
		local signPost = newPart({
			Name = "SignPost",
			Size = Vector3.new(1, 13, 1),
			Position = center - outward * (Config.BaseZoneRadius - 1) + Vector3.new(0, 7, 0),
			Color = Color3.fromRGB(62, 56, 50),
			Material = Enum.Material.Wood,
			CanCollide = true,
		})
		signPost.Parent = model

		local signBoard = newPart({
			Name = "SignBoard",
			Size = Vector3.new(13, 5.5, 0.6),
			Position = center - outward * (Config.BaseZoneRadius - 1) + Vector3.new(0, 14, 0),
			Color = Color3.fromRGB(42, 36, 30),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		signBoard.CFrame = CFrame.new(signBoard.Position, Vector3.new(0, signBoard.Position.Y, 0))
		signBoard.Parent = model

		local _, signLabel = makeBillboard(signBoard, "Свободная база", Color3.new(1, 1, 1), UDim2.fromOffset(320, 62), Vector3.new(0, 0.2, 0.7))

		-- Склад: стол + поверхность с яйцами
		local stand = newPart({
			Name = "VaultStand",
			Size = Vector3.new(10, 3.6, 10),
			Position = center + Vector3.new(0, 2.2, 0),
			Color = Color3.fromRGB(112, 88, 62),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		})
		stand.Parent = model

		local vaultTop = newPart({
			Name = "VaultTop",
			Size = Vector3.new(9.4, 0.6, 9.4),
			Position = center + Vector3.new(0, 4.3, 0),
			Color = Color3.fromRGB(148, 118, 84),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		})
		vaultTop.Parent = model

		local vaultGlow = newPart({
			Name = "VaultGlow",
			Size = Vector3.new(10.2, 0.22, 10.2),
			Position = center + Vector3.new(0, 4.68, 0),
			Color = Config.Colors.Vault,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		vaultGlow.Parent = model

		local _, vaultLabel = makeBillboard(vaultTop, "🏦 0", Color3.fromRGB(255, 226, 140), UDim2.fromOffset(240, 44), Vector3.new(0, 3.4, 0))
		local stealPrompt = makePrompt(vaultTop, "Украсть яйца", "Чужой склад", 12, Config.RaidHoldTime)

		-- Декоративные украшения базы
		for side = 1, 2 do
			local sideAngle = angle + (side == 1 and 0.45 or -0.45)
			local sidePos = Vector3.new(math.cos(sideAngle), 0, math.sin(sideAngle)) * (Config.BaseRingRadius + Config.BaseZoneRadius - 2)
			local crate = newPart({
				Name = "Crate",
				Size = Vector3.new(3, 3, 3),
				Position = sidePos + Vector3.new(0, 1.9, 0),
				Color = Color3.fromRGB(124, 96, 64),
				Material = Enum.Material.WoodPlanks,
				CanCollide = true,
			})
			crate.CFrame = crate.CFrame * CFrame.Angles(0, math.rad(side * 22 + index * 7), 0)
			crate.Parent = model
		end

		-- Персональный маркер: каждый клиент видит его только над своей базой
		local marker = newPart({
			Name = "MyBaseMarker",
			Size = Vector3.new(7, 7, 7),
			Position = center + Vector3.new(0, 40, 0),
			Color = Config.Colors.MyBase,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
		})
		marker.Shape = Enum.PartType.Ball
		marker.Transparency = 1
		marker.Parent = model

		local markerGui = Instance.new("BillboardGui")
		markerGui.Name = "MarkerGui"
		markerGui.Size = UDim2.fromOffset(220, 54)
		markerGui.StudsOffset = Vector3.new(0, 6, 0)
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
		markerLabel.TextStrokeTransparency = 0.2
		markerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		markerLabel.Parent = markerGui

		table.insert(bases, {
			Id = index,
			Model = model,
			Center = center,
			Platform = platform,
			Glow = glow,
			SignLabel = signLabel,
			Marker = marker,
			MarkerGui = markerGui,
			VaultTop = vaultTop,
			VaultGlow = vaultGlow,
			VaultLabel = vaultLabel,
			StealPrompt = stealPrompt,
			Owners = {},          -- массив Player
			Vault = {},           -- [typeName] = count
			VaultTotal = 0,
			VisualEggs = {},
			IncomeAccum = 0,
			IncomePerSecond = 0,
		})
	end

	-- ===================== ДЕРЕВЬЯ =====================
	local natureFolder = folder("Nature")

	local maxTreeRadius = halfSize - 16
	for _ = 1, 30 do
		local angle = RNG:NextNumber() * math.pi * 2
		local radius = Config.BaseRingRadius + 26 + RNG:NextNumber() * (maxTreeRadius - Config.BaseRingRadius - 26)
		radius = math.min(radius, maxTreeRadius)
		local position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		local trunkHeight = 7 + RNG:NextNumber() * 6

		local trunk = newPart({
			Name = "Trunk",
			Size = Vector3.new(2.2, trunkHeight, 2.2),
			Color = Color3.fromRGB(98, 70, 48),
			Material = Enum.Material.Wood,
			CanCollide = true,
		})
		trunk.Shape = Enum.PartType.Cylinder
		trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = natureFolder

		for leaf = 1, 3 do
			local leafSize = 8 - leaf * 1.4 + RNG:NextNumber() * 1.4
			local crown = newPart({
				Name = "Crown",
				Size = Vector3.new(leafSize, leafSize * 0.8, leafSize),
				Position = position + Vector3.new(
					(RNG:NextNumber() - 0.5) * 2.5,
					trunkHeight + (leaf - 1) * 2.6 - 1.5,
					(RNG:NextNumber() - 0.5) * 2.5
				),
				Color = Color3.fromRGB(58, 138, 78):Lerp(Color3.fromRGB(96, 180, 108), RNG:NextNumber()),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
			crown.Shape = Enum.PartType.Ball
			crown.Parent = natureFolder
		end
	end

	-- ===================== ТАБЛО ЛИДЕРОВ =====================
	local boardStand = newPart({
		Name = "LeaderboardStand",
		Size = Vector3.new(1.4, 16, 1.4),
		Position = Vector3.new(-Config.MarketRadius - 8, 8, 0),
		Color = Color3.fromRGB(50, 45, 42),
		Material = Enum.Material.Metal,
		CanCollide = true,
	})
	boardStand.Parent = marketFolder

	local board = newPart({
		Name = "Leaderboard",
		Size = Vector3.new(18, 12, 1),
		Position = Vector3.new(-Config.MarketRadius - 8, 20, 0),
		Color = Color3.fromRGB(24, 26, 34),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	board.CFrame = CFrame.new(board.Position, Vector3.new(0, board.Position.Y, 0))
	board.Parent = marketFolder

	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardGui"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(600, 400)
	surface.LightInfluence = 0
	surface.Adornee = board
	surface.Parent = board

	local boardFrame = Instance.new("Frame")
	boardFrame.Size = UDim2.fromScale(1, 1)
	boardFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	boardFrame.BorderSizePixel = 0
	boardFrame.Parent = surface

	local boardTitle = Instance.new("TextLabel")
	boardTitle.Size = UDim2.new(1, 0, 0.18, 0)
	boardTitle.BackgroundTransparency = 1
	boardTitle.Font = Enum.Font.GothamBlack
	boardTitle.Text = "🏆 ЛУЧШИЕ ВОРЫ ЯИЦ"
	boardTitle.TextScaled = true
	boardTitle.TextColor3 = Color3.fromRGB(255, 214, 90)
	boardTitle.Parent = boardFrame

	local boardList = Instance.new("TextLabel")
	boardList.Position = UDim2.new(0.05, 0, 0.2, 0)
	boardList.Size = UDim2.new(0.9, 0, 0.78, 0)
	boardList.BackgroundTransparency = 1
	boardList.Font = Enum.Font.GothamBold
	boardList.TextXAlignment = Enum.TextXAlignment.Left
	boardList.TextYAlignment = Enum.TextYAlignment.Top
	boardList.TextSize = 24
	boardList.TextWrapped = true
	boardList.TextColor3 = Color3.fromRGB(235, 240, 255)
	boardList.Text = "Ждём игроков..."
	boardList.Parent = boardFrame

	return {
		Root = root,
		Arena = arenaFolder,
		Market = marketFolder,
		BasesFolder = basesFolder,
		Eggs = eggsFolder,
		VaultEggs = vaultEggsFolder,
		Carried = carriedFolder,
		Nature = natureFolder,
		BasesData = bases,
		MarketCenter = Vector3.new(0, 0, 0),
		LeaderboardList = boardList,
	}
end

return Map
