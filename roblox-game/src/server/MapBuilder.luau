-- MapBuilder (ModuleScript в ServerScriptService)
-- Строит всю карту «Пол — это лава» из блоков: лобби, 50 этапов в 5 зонах,
-- финиш, пасхалки, декор, вулкан и лавовое море. Вызывается из GameServer.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LavaConfig"))
local Text = require(ReplicatedStorage:WaitForChild("LavaText"))

local MapBuilder = {}

local PI = math.pi
local V3 = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB
local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local ROT_UP = CFrame.Angles(0, 0, PI / 2) -- цилиндр «стоя»
local LAVA_BOTTOM = -2 -- куда уходят опоры (лава на высоте 0)

local TOTAL = Config.TOTAL_STAGES
local PER_ZONE = Config.STAGES_PER_ZONE

local currentFolder = nil
local coinCounter = 0
local info = nil

-- ============ ПАЛИТРА ============
local WOOD = RGB(156, 102, 62)
local WOOD_DARK = RGB(96, 60, 36)
local GOLD = RGB(255, 200, 50)
local LAVA_COLOR = RGB(255, 85, 0)
local FABRICS = { RGB(70, 110, 190), RGB(190, 70, 80), RGB(90, 160, 110), RGB(220, 170, 70), RGB(150, 90, 170) }
local BOOKS = { RGB(200, 50, 50), RGB(50, 90, 200), RGB(40, 150, 80), RGB(230, 180, 40), RGB(130, 60, 160), RGB(240, 120, 40) }
local PLATE_RIMS = { RGB(80, 140, 230), RGB(230, 80, 90), RGB(90, 190, 120), RGB(250, 190, 60) }
-- разноцветные «кристаллические» камни пещер
local ROCKS = { RGB(130, 95, 190), RGB(70, 150, 190), RGB(170, 100, 200), RGB(90, 120, 200), RGB(60, 170, 160) }
local ACCENT = {
	RGB(255, 170, 40),
	RGB(255, 110, 200),
	RGB(130, 140, 255),
	RGB(255, 80, 30),
	RGB(255, 230, 110),
}
local PARTY = {
	RGB(255, 90, 150),
	RGB(80, 210, 255),
	RGB(255, 220, 60),
	RGB(120, 230, 90),
	RGB(180, 110, 255),
	RGB(255, 150, 50),
}
local CANDY = { RGB(255, 140, 200), RGB(140, 240, 210), RGB(255, 235, 120), RGB(200, 160, 255), RGB(255, 170, 110), RGB(140, 210, 255) }

-- ============ БАЗОВЫЕ ПОМОЩНИКИ ============
local function tag(inst, name)
	CollectionService:AddTag(inst, name)
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = M.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = parent or currentFolder
	return p
end

local function darker(c, k)
	k = k or 0.7
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

-- Локальные координаты этапа: x — вправо, y — высота (мировая), z — вперёд.
local function L(ctx, x, y, z)
	return ctx.F * CF(x, y, -z)
end

local function addPath(pos)
	table.insert(info.pathPoints, pos)
end

local function column(ctx, x, z, y0, y1, w, d, color, mat, round)
	if y1 - y0 < 0.2 then
		return nil
	end
	local h = y1 - y0
	local cy = (y0 + y1) / 2
	if round then
		return part({ Shape = CYL, Size = V3(h, w, w), CFrame = L(ctx, x, cy, z) * ROT_UP, Color = color, Material = mat })
	end
	return part({ Size = V3(w, h, d), CFrame = L(ctx, x, cy, z), Color = color, Material = mat })
end

-- key — ключ текста из LavaText; клиент переведёт табличку на язык игрока
local function makeSign(cf, size, key, bg, fg, face, parent, args)
	local p = part({ Size = size, CFrame = cf, Color = bg, Material = M.SmoothPlastic }, parent)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = fg or Color3.new(1, 1, 1)
	lbl.Text = Text.Format("en", key, args)
	lbl.AutoLocalize = false
	lbl:SetAttribute("TextKey", key)
	if args then
		lbl:SetAttribute("TextArgs", table.concat(args, "|"))
	end
	tag(lbl, "LocText")
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.Parent = lbl
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.new(0, 0, 0)
	st.Parent = lbl
	lbl.Parent = sg
	sg.Parent = p
	return p, lbl
end

local function coinAt(cf)
	coinCounter += 1
	local c = part({
		Name = "Coin",
		Shape = CYL,
		Size = V3(0.4, 2.4, 2.4),
		CFrame = cf,
		Color = GOLD,
		Material = M.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	c:SetAttribute("CoinId", coinCounter)
	tag(c, "Coin")
	return c
end

local function maybeCoin(ctx, x, top, z, chance)
	if ctx.rng:NextNumber() < (chance or 0.35) then
		coinAt(CF(L(ctx, x, top + 2.6, z).Position))
	end
end

local function lavaPart(props)
	local p = part(props)
	p.Material = props.Material or M.Neon
	p.Color = props.Color or LAVA_COLOR
	tag(p, "Lava")
	return p
end

local function killPart(props)
	local p = part(props)
	tag(p, "Kill")
	return p
end

-- ============ УТКИ, СУНДУКИ ============
local function makeDuck(cf, id, parent)
	local model = Instance.new("Model")
	model.Name = "Duck" .. id
	local body = part({ Name = "Body", Shape = BALL, Size = V3(3, 3, 3), CFrame = cf, Color = RGB(255, 220, 40), CanCollide = false }, model)
	part({ Shape = BALL, Size = V3(2, 2, 2), CFrame = cf * CF(0, 1.6, -0.9), Color = RGB(255, 220, 40), CanCollide = false }, model)
	part({ Size = V3(0.9, 0.4, 1), CFrame = cf * CF(0, 1.5, -2.1), Color = RGB(255, 130, 20), CanCollide = false }, model)
	part({ Shape = BALL, Size = V3(0.4, 0.4, 0.4), CFrame = cf * CF(0.5, 1.9, -1.75), Color = RGB(10, 10, 10), CanCollide = false }, model)
	part({ Shape = BALL, Size = V3(0.4, 0.4, 0.4), CFrame = cf * CF(-0.5, 1.9, -1.75), Color = RGB(10, 10, 10), CanCollide = false }, model)
	local light = Instance.new("PointLight")
	light.Color = RGB(255, 230, 120)
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = body
	model.PrimaryPart = body
	body:SetAttribute("DuckId", id)
	tag(body, "Duck")
	model.Parent = parent or currentFolder
	return model
end

local function makeChest(cf, secretId, tagName, parent)
	local model = Instance.new("Model")
	model.Name = "Chest_" .. secretId
	local base = part({ Name = "Base", Size = V3(4, 2.4, 3), CFrame = cf * CF(0, 1.2, 0), Color = RGB(120, 70, 30), Material = M.Wood }, model)
	part({ Size = V3(4.2, 1, 3.2), CFrame = cf * CF(0, 2.9, 0), Color = GOLD, Material = M.Metal }, model)
	part({ Size = V3(1, 1, 0.3), CFrame = cf * CF(0, 2.2, -1.6), Color = RGB(255, 240, 120), Material = M.Neon }, model)
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = RGB(255, 220, 90)
	sparkle.Parent = base
	base:SetAttribute("SecretId", secretId)
	tag(base, tagName or "Secret")
	model.PrimaryPart = base
	model.Parent = parent or currentFolder
	return model
end

-- ============ ТЕМАТИЧЕСКИЕ ПЛАТФОРМЫ ============
-- Полосатая колонна (цирк, карамель): полоски только сверху, ниже — сплошная
local function stripedColumn(ctx, x, z, y0, y1, dia, c1, c2, seg)
	seg = seg or 2.5
	local yStart = math.max(y0, y1 - 12)
	if yStart > y0 + 0.2 then
		column(ctx, x, z, y0, yStart, dia, dia, c2, M.SmoothPlastic, true)
	end
	local y, i = yStart, 0
	while y < y1 - 0.05 do
		local h = math.min(seg, y1 - y)
		column(ctx, x, z, y, y + h, dia, dia, (i % 2 == 0) and c1 or c2, M.SmoothPlastic, true)
		y += h
		i += 1
	end
end

-- Деталь, которая крутится (колесо обозрения, карусель, леденец). Анимирует клиент.
local function rotor(p, center, axis, speed, hang)
	p.CanCollide = false
	p:SetAttribute("RotorCenter", center)
	if hang then
		-- кабинки колеса: висят вертикально под точкой крепления
		p:SetAttribute("RotorOffset", center:Inverse() * CF(p.Position + V3(0, hang, 0)))
		p:SetAttribute("RotorHang", hang)
	else
		p:SetAttribute("RotorOffset", center:Inverse() * p.CFrame)
	end
	p:SetAttribute("RotorAxis", axis)
	p:SetAttribute("RotorSpeed", speed)
	tag(p, "Rotor")
	return p
end

-- Возвращает часть, по которой ходят. Верх платформы = top.
local function themedPlatform(ctx, x, top, z, w, d)
	local zone = ctx.zone
	local r = ctx.rng
	local walk
	if zone == 1 then -- 🎡 парк развлечений
		local kind = r:NextInteger(1, 4)
		local col = pick(r, PARTY)
		if kind == 1 then -- цирковая тумба
			local dia = math.min(w, d) + 0.5
			walk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = col })
			part({ Shape = CYL, Size = V3(0.4, dia + 0.5, dia + 0.5), CFrame = L(ctx, x, top - 1.1, z) * ROT_UP, Color = GOLD, Material = M.Foil })
			stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 1.3, dia * 0.7, RGB(230, 40, 50), RGB(255, 255, 255))
		elseif kind == 2 then -- чашка с аттракциона «чашки»
			local dia = math.min(w, d) + 0.5
			walk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = col:Lerp(Color3.new(1, 1, 1), 0.35) })
			part({ Shape = CYL, Size = V3(2.4, dia * 0.85, dia * 0.85), CFrame = L(ctx, x, top - 2.2, z) * ROT_UP, Color = col })
			for i = 0, 5 do
				local a = i / 6 * 2 * PI
				part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = L(ctx, x + math.cos(a) * dia * 0.42, top - 2, z + math.sin(a) * dia * 0.42), Color = Color3.new(1, 1, 1), CanCollide = false })
			end
			part({ Shape = CYL, Size = V3(0.5, dia + 1.5, dia + 1.5), CFrame = L(ctx, x, top - 3.6, z) * ROT_UP, Color = Color3.new(1, 1, 1) })
			column(ctx, x, z, LAVA_BOTTOM, top - 3.85, 1.6, 1.6, RGB(160, 165, 175), M.Metal, true)
		elseif kind == 3 then -- машинка с автодрома
			walk = part({ Size = V3(w, 1.2, d), CFrame = L(ctx, x, top - 0.6, z), Color = col })
			part({ Size = V3(w + 0.8, 0.7, d + 0.8), CFrame = L(ctx, x, top - 1.4, z), Color = RGB(30, 30, 35) })
			part({ Size = V3(0.3, 4, 0.3), CFrame = L(ctx, x, top + 2, z + d / 2 - 0.5), Color = RGB(160, 165, 175), Material = M.Metal, CanCollide = false })
			part({ Shape = BALL, Size = V3(0.6, 0.6, 0.6), CFrame = L(ctx, x, top + 4.1, z + d / 2 - 0.5), Color = RGB(255, 230, 80), Material = M.Neon, CanCollide = false })
			column(ctx, x, z, LAVA_BOTTOM, top - 1.75, 2, 2, RGB(160, 165, 175), M.Metal, true)
		else -- ящик с призами
			walk = part({ Size = V3(w, 1.4, d), CFrame = L(ctx, x, top - 0.7, z), Color = WOOD, Material = M.WoodPlanks })
			for sz = -1, 1, 2 do
				part({ Size = V3(w + 0.1, 0.4, 0.5), CFrame = L(ctx, x, top - 0.7, z + sz * (d / 2 - 0.25)), Color = col, CanCollide = false })
			end
			stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 1.4, 2.2, col, RGB(255, 255, 255))
		end
	elseif zone == 2 then -- 🍭 фабрика сладостей
		local kind = r:NextInteger(1, 4)
		if kind == 1 then -- печенье с шоколадной крошкой
			local dia = math.min(w, d) + 1
			walk = part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, z) * ROT_UP, Color = RGB(215, 160, 95), Material = M.Sand })
			for i = 1, 6 do
				local a = r:NextNumber(0, 2 * PI)
				local rr = r:NextNumber(0.5, dia * 0.38)
				part({ Shape = BALL, Size = V3(0.7, 0.7, 0.7), CFrame = L(ctx, x + math.cos(a) * rr, top - 0.15, z + math.sin(a) * rr), Color = RGB(70, 40, 20), CanCollide = false })
			end
			stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 1.2, 1.6, RGB(230, 30, 50), RGB(255, 255, 255), 1.5)
		elseif kind == 2 then -- кусок торта
			local dia = math.min(w, d) + 0.5
			local frosting = pick(r, CANDY)
			walk = part({ Shape = CYL, Size = V3(0.8, dia, dia), CFrame = L(ctx, x, top - 0.4, z) * ROT_UP, Color = frosting })
			part({ Shape = CYL, Size = V3(2.2, dia - 0.3, dia - 0.3), CFrame = L(ctx, x, top - 1.9, z) * ROT_UP, Color = RGB(240, 210, 160) })
			part({ Shape = CYL, Size = V3(0.6, dia - 0.2, dia - 0.2), CFrame = L(ctx, x, top - 2.0, z) * ROT_UP, Color = frosting })
			part({ Shape = BALL, Size = V3(1.2, 1.2, 1.2), CFrame = L(ctx, x + dia * 0.35, top + 0.4, z), Color = RGB(220, 20, 40), CanCollide = false })
			stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 3, 1.8, frosting, RGB(255, 255, 255), 1.5)
		elseif kind == 3 then -- конфета в фантике
			local col = pick(r, CANDY)
			walk = part({ Size = V3(w, 1.6, d), CFrame = L(ctx, x, top - 0.8, z), Color = col })
			part({ Size = V3(w + 0.05, 1.65, 0.6), CFrame = L(ctx, x, top - 0.8, z - d / 4), Color = Color3.new(1, 1, 1), CanCollide = false })
			part({ Size = V3(w + 0.05, 1.65, 0.6), CFrame = L(ctx, x, top - 0.8, z + d / 4), Color = Color3.new(1, 1, 1), CanCollide = false })
			for sx = -1, 1, 2 do
				local wedge = Instance.new("WedgePart")
				wedge.Anchored = true
				wedge.CanCollide = false
				wedge.Size = V3(d * 0.8, 1.6, 1.6)
				wedge.CFrame = L(ctx, x + sx * (w / 2 + 0.8), top - 0.8, z) * CFrame.Angles(0, sx * PI / 2, 0)
				wedge.Color = col:Lerp(Color3.new(1, 1, 1), 0.3)
				wedge.Parent = currentFolder
			end
			column(ctx, x, z, LAVA_BOTTOM, top - 1.6, 1, 1, Color3.new(1, 1, 1), M.SmoothPlastic, true)
		else -- шоколадка
			walk = part({ Size = V3(w, 1.2, d), CFrame = L(ctx, x, top - 0.6, z), Color = RGB(110, 60, 30) })
			for i = -1, 1, 2 do
				part({ Size = V3(0.2, 1.24, d), CFrame = L(ctx, x + i * w / 6, top - 0.6, z), Color = RGB(80, 42, 20), CanCollide = false })
				part({ Size = V3(w, 1.24, 0.2), CFrame = L(ctx, x, top - 0.6, z + i * d / 6), Color = RGB(80, 42, 20), CanCollide = false })
			end
			part({ Size = V3(w * 0.6, 0.3, d + 0.4), CFrame = L(ctx, x, top - 1.3, z), Color = RGB(200, 30, 40), CanCollide = false })
			column(ctx, x, z, LAVA_BOTTOM, top - 1.2, w * 0.4, d * 0.4, RGB(90, 50, 25), M.SmoothPlastic)
		end
	elseif zone == 3 then -- 💎 подземный мир
		if r:NextNumber() < 0.45 then -- светящийся гриб
			local dia = math.min(w, d) + 1
			local cap = pick(r, { RGB(80, 220, 255), RGB(200, 90, 255), RGB(90, 255, 160), RGB(255, 110, 200) })
			walk = part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, z) * ROT_UP, Color = cap })
			part({ Shape = CYL, Size = V3(0.5, dia - 1.5, dia - 1.5), CFrame = L(ctx, x, top + 0.2, z) * ROT_UP, Color = cap:Lerp(Color3.new(1, 1, 1), 0.2), CanCollide = false })
			local glow = part({ Shape = CYL, Size = V3(0.3, dia - 0.4, dia - 0.4), CFrame = L(ctx, x, top - 1.3, z) * ROT_UP, Color = cap, Material = M.Neon, CanCollide = false })
			for i = 1, 4 do
				local a = i / 4 * 2 * PI + 0.4
				part({ Shape = BALL, Size = V3(0.9, 0.9, 0.9), CFrame = L(ctx, x + math.cos(a) * dia * 0.3, top - 0.05, z + math.sin(a) * dia * 0.3), Color = Color3.new(1, 1, 1), CanCollide = false })
			end
			local pl = Instance.new("PointLight")
			pl.Color = cap
			pl.Range = 14
			pl.Brightness = 1.5
			pl.Parent = glow
			column(ctx, x, z, LAVA_BOTTOM, top - 1.2, dia * 0.35, dia * 0.35, RGB(235, 225, 210), M.SmoothPlastic, true)
		else -- камень с кристаллами
			local rock = pick(r, ROCKS)
			walk = part({ Size = V3(w, 1.6, d), CFrame = L(ctx, x, top - 0.8, z), Color = rock, Material = M.Slate })
			part({ Size = V3(w * 0.8, 2, d * 0.8), CFrame = L(ctx, x, top - 2.4, z) * CFrame.Angles(0, r:NextNumber(-0.4, 0.4), 0), Color = darker(rock), Material = M.Slate })
			local cc = pick(r, { RGB(90, 230, 255), RGB(220, 100, 255), RGB(255, 120, 200), RGB(120, 255, 170) })
			for i = 1, 2 do
				local sx = (i == 1) and -1 or 1
				part({ Size = V3(0.8, r:NextNumber(1.8, 3), 0.8), CFrame = L(ctx, x + sx * (w / 2 - 0.3), top + 0.4, z + r:NextNumber(-d / 3, d / 3)) * CFrame.Angles(0, 0, sx * 0.4), Color = cc, Material = M.Neon, CanCollide = false })
			end
			column(ctx, x, z, LAVA_BOTTOM, top - 3.2, w * 0.55, d * 0.55, darker(rock, 0.6), M.Basalt)
		end
	elseif zone == 4 then -- 🌋 базальтовая колонна
		local dia = math.min(w, d) + 0.5
		walk = part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, z) * ROT_UP, Color = RGB(58, 48, 46), Material = M.Basalt })
		part({ Shape = CYL, Size = V3(0.4, dia + 0.6, dia + 0.6), CFrame = L(ctx, x, top - 1.4, z) * ROT_UP, Color = RGB(255, 100, 20), Material = M.Neon })
		column(ctx, x, z, LAVA_BOTTOM, top - 1.6, dia - 0.6, dia - 0.6, RGB(45, 38, 36), M.Basalt, true)
	else -- ☁️ облако или парящий остров
		if r:NextNumber() < 0.5 then
			local dia = math.max(w, d) + 1
			walk = part({ Shape = CYL, Size = V3(1.5, dia, dia), CFrame = L(ctx, x, top - 0.75, z) * ROT_UP, Color = RGB(250, 250, 255) })
			for i = 1, 4 do
				local a = (i / 4) * 2 * PI + r:NextNumber(0, 1)
				local s = r:NextNumber(2.5, 3.5)
				part({ Shape = BALL, Size = V3(s, s, s), CFrame = L(ctx, x + math.cos(a) * dia * 0.45, top - 1.8, z + math.sin(a) * dia * 0.45), Color = RGB(255, 255, 255), CanCollide = false, CastShadow = false })
			end
		else
			local dia = math.max(w, d) + 0.5
			walk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = RGB(110, 210, 90), Material = M.Grass })
			part({ Shape = CYL, Size = V3(1.6, dia - 0.6, dia - 0.6), CFrame = L(ctx, x, top - 1.8, z) * ROT_UP, Color = RGB(150, 105, 70), Material = M.Ground })
			part({ Shape = CYL, Size = V3(1.6, dia * 0.6, dia * 0.6), CFrame = L(ctx, x, top - 3.4, z) * ROT_UP, Color = RGB(130, 90, 60), Material = M.Ground })
			part({ Shape = CYL, Size = V3(1.6, dia * 0.3, dia * 0.3), CFrame = L(ctx, x, top - 5, z) * ROT_UP, Color = RGB(115, 80, 55), Material = M.Ground })
			if r:NextNumber() < 0.5 then
				part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = L(ctx, x + dia * 0.35, top + 0.2, z), Color = pick(r, PARTY), CanCollide = false })
			end
		end
	end
	addPath(L(ctx, x, top, z).Position)
	return walk
end

-- Длинная дорожка (для полос лавы, маятников, лазеров и т.п.)
local function walkway(ctx, x, top, zc, w, len)
	local zone = ctx.zone
	local p
	if zone == 1 then -- деревянный настил с цветными бортиками
		p = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, top - 0.5, zc), Color = RGB(190, 135, 85), Material = M.WoodPlanks })
		part({ Size = V3(0.6, 1.2, len), CFrame = L(ctx, x - w / 2 + 0.3, top - 0.45, zc), Color = RGB(230, 40, 50) })
		part({ Size = V3(0.6, 1.2, len), CFrame = L(ctx, x + w / 2 - 0.3, top - 0.45, zc), Color = RGB(255, 200, 40) })
	elseif zone == 2 then -- розовая лента с глазурью и посыпкой
		p = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, top - 0.5, zc), Color = RGB(255, 150, 200) })
		part({ Size = V3(0.8, 1.15, len), CFrame = L(ctx, x - w / 2 + 0.4, top - 0.48, zc), Color = Color3.new(1, 1, 1) })
		part({ Size = V3(0.8, 1.15, len), CFrame = L(ctx, x + w / 2 - 0.4, top - 0.48, zc), Color = Color3.new(1, 1, 1) })
		for i = 1, math.floor(len / 2) do
			part({ Size = V3(0.6, 0.1, 0.2), CFrame = L(ctx, x + ctx.rng:NextNumber(-w / 2 + 1, w / 2 - 1), top + 0.02, zc - len / 2 + i * 2) * CFrame.Angles(0, ctx.rng:NextNumber(0, PI), 0), Color = pick(ctx.rng, PARTY), CanCollide = false })
		end
	elseif zone == 3 then -- каменный мост со светящимися краями
		p = part({ Size = V3(w, 1.6, len), CFrame = L(ctx, x, top - 0.8, zc), Color = pick(ctx.rng, ROCKS), Material = M.Slate })
		part({ Size = V3(0.3, 0.3, len), CFrame = L(ctx, x - w / 2, top - 0.2, zc), Color = RGB(90, 230, 255), Material = M.Neon, CanCollide = false })
		part({ Size = V3(0.3, 0.3, len), CFrame = L(ctx, x + w / 2, top - 0.2, zc), Color = RGB(220, 100, 255), Material = M.Neon, CanCollide = false })
	elseif zone == 4 then
		p = part({ Size = V3(w, 1.2, len), CFrame = L(ctx, x, top - 0.6, zc), Color = RGB(55, 46, 44), Material = M.Basalt })
		part({ Size = V3(0.4, 0.3, len), CFrame = L(ctx, x - w / 2, top - 1.2, zc), Color = LAVA_COLOR, Material = M.Neon })
		part({ Size = V3(0.4, 0.3, len), CFrame = L(ctx, x + w / 2, top - 1.2, zc), Color = LAVA_COLOR, Material = M.Neon })
	else -- радужный мост
		p = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, top - 0.6, zc), Color = Color3.new(1, 1, 1) })
		local stripes = { RGB(255, 80, 80), RGB(255, 170, 50), RGB(255, 235, 70), RGB(90, 220, 100), RGB(80, 160, 255), RGB(170, 100, 255) }
		local sw = w / #stripes
		for i, c in ipairs(stripes) do
			part({ Size = V3(sw, 0.12, len), CFrame = L(ctx, x - w / 2 + (i - 0.5) * sw, top - 0.04, zc), Color = c, CanCollide = false })
		end
	end
	if not ctx.sky then
		local sc = zone == 1 and RGB(230, 40, 50) or (zone == 2 and RGB(255, 255, 255) or RGB(60, 50, 60))
		column(ctx, x, zc - len / 2 + 2, LAVA_BOTTOM, top - 1, 2.5, 2.5, sc, M.SmoothPlastic)
		column(ctx, x, zc + len / 2 - 2, LAVA_BOTTOM, top - 1, 2.5, 2.5, sc, M.SmoothPlastic)
	end
	for k = 0, 2 do
		addPath(L(ctx, x, top, zc - len / 2 + k * len / 2).Position)
	end
	return p
end

-- ============ ПРЕПЯТСТВИЯ ============
local Obstacles = {}

function Obstacles.jumps(ctx)
	local r = ctx.rng
	local n = r:NextInteger(3, 5)
	for _ = 1, n do
		local rise = 0
		if not ctx.flat then
			rise = r:NextNumber(ctx.y < 14 and 0 or -0.5, 2)
		end
		local gap = r:NextNumber(3, 3.5 + 2 * ctx.diff) - math.max(rise, 0) * 0.4
		local size = r:NextNumber(8.5 - 2 * ctx.diff, 10 - 2 * ctx.diff)
		local x = math.clamp(ctx.x + r:NextNumber(-5, 5), -10, 10)
		local top = ctx.y + rise
		local zc = ctx.z + gap + size / 2
		themedPlatform(ctx, x, top, zc, size, size)
		maybeCoin(ctx, x, top, zc)
		ctx.x, ctx.y, ctx.z = x, top, zc + size / 2
	end
end

function Obstacles.stripes(ctx)
	local r = ctx.rng
	local len = r:NextInteger(26, 36)
	local w = 9
	local z0 = ctx.z + 4
	local zc = z0 + len / 2
	local x = ctx.x
	walkway(ctx, x, ctx.y, zc, w, len)
	local zz = z0 + 6
	local group = 0
	while zz < z0 + len - 6 do
		local depth = 1.6 + 1.2 * ctx.diff
		local tile = lavaPart({ Size = V3(w, 0.4, depth), CFrame = L(ctx, x, ctx.y + 0.2, zz + depth / 2) })
		if ctx.zone == 2 then
			tile.Color = RGB(255, 60, 30) -- конфорки плиты
		end
		if ctx.diff > 0.45 and r:NextNumber() < 0.5 then
			group = 1 - group
			table.insert(info.blinkers, { part = tile, group = group })
		end
		local after = zz + depth + 2
		if after < z0 + len - 2 then
			maybeCoin(ctx, x, ctx.y, after, 0.5)
		end
		zz += depth + r:NextNumber(4, 5.5)
	end
	ctx.x, ctx.z = x, z0 + len
end

function Obstacles.movers(ctx)
	local r = ctx.rng
	local n = r:NextInteger(2, 3)
	local x = math.clamp(ctx.x, -6, 6)
	for _ = 1, n do
		local size = 7
		local zc = ctx.z + 3 + size / 2
		local base = L(ctx, x, ctx.y - 0.5, zc)
		local p = part({ Size = V3(size, 1, size), CFrame = base, Color = ACCENT[ctx.zone], Material = M.SmoothPlastic })
		local glowBase = base * CF(0, -0.55, 0)
		local glow = part({ Size = V3(size + 0.2, 0.3, size + 0.2), CFrame = glowBase, Color = Color3.new(1, 1, 1), Material = M.Neon, CanCollide = false })
		local amp = 4 + 4 * ctx.diff
		local speed = 0.8 + 0.6 * ctx.diff
		local phase = r:NextNumber(0, 2 * PI)
		table.insert(info.movers, { part = p, base = base, axis = ctx.F.RightVector, amp = amp, speed = speed, phase = phase })
		table.insert(info.movers, { part = glow, base = glowBase, axis = ctx.F.RightVector, amp = amp, speed = speed, phase = phase })
		addPath(base.Position)
		ctx.z = zc + size / 2
	end
	-- статичная площадка после движущихся
	local size = 8
	local zc = ctx.z + 3.5 + size / 2
	themedPlatform(ctx, x, ctx.y, zc, size, size)
	maybeCoin(ctx, x, ctx.y, zc, 0.6)
	ctx.x, ctx.z = x, zc + size / 2
end

function Obstacles.vanish(ctx)
	local r = ctx.rng
	local n = r:NextInteger(4, 6)
	local colors = {
		RGB(255, 170, 200), -- воздушные подушки
		RGB(255, 235, 245), -- зефир
		RGB(150, 110, 80), -- рассыпающийся камень
		RGB(70, 30, 90), -- обсидиан
		RGB(235, 245, 255), -- облачка
	}
	for _ = 1, n do
		local size = 6
		local gap = 2.5 + 1.5 * ctx.diff
		local x = math.clamp(ctx.x + r:NextNumber(-4, 4), -10, 10)
		local zc = ctx.z + gap + size / 2
		local p = part({
			Size = V3(size, 1, size),
			CFrame = L(ctx, x, ctx.y - 0.5, zc),
			Color = colors[ctx.zone],
			Material = ctx.zone == 4 and M.Glass or M.SmoothPlastic,
		})
		tag(p, "Vanish")
		addPath(p.Position)
		ctx.x, ctx.z = x, zc + size / 2
	end
end

function Obstacles.spinner(ctx)
	local dia = 24
	local zc = ctx.z + 4 + dia / 2
	local x = ctx.x
	local top = ctx.y
	part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, zc) * ROT_UP, Color = ctx.zone == 2 and RGB(230, 230, 235) or RGB(50, 45, 45), Material = ctx.zone == 2 and M.SmoothPlastic or M.Basalt })
	if not ctx.sky then
		column(ctx, x, zc, LAVA_BOTTOM, top - 1.2, 5, 5, RGB(70, 70, 75), M.Metal, true)
	end
	part({ Shape = CYL, Size = V3(3.4, 3, 3), CFrame = L(ctx, x, top + 1.7, zc) * ROT_UP, Color = RGB(80, 80, 90), Material = M.Metal })
	local center = L(ctx, x, top + 1.3, zc)
	local speed = 0.7 + 0.8 * ctx.diff
	local bars = ctx.diff > 0.6 and 2 or 1
	for i = 1, bars do
		local offset = CFrame.Angles(0, (i - 1) * PI / 2, 0)
		local bar = killPart({ Size = V3(dia - 1, 0.9, 0.9), CFrame = center * offset, Color = RGB(255, 40, 40), Material = M.Neon })
		table.insert(info.spinners, { part = bar, base = center, speed = speed, offset = offset })
		table.insert(info.killers, { part = bar })
	end
	addPath(L(ctx, x, top, zc).Position)
	addPath(L(ctx, x + 10, top, zc).Position)
	addPath(L(ctx, x - 10, top, zc).Position)
	coinAt(CF(L(ctx, x + 7, top + 2.6, zc).Position))
	ctx.x, ctx.z = x, zc + dia / 2
end

function Obstacles.climb(ctx)
	local r = ctx.rng
	local land = 8
	local x = ctx.x
	local zl = ctx.z + 4 + land / 2
	themedPlatform(ctx, x, ctx.y, zl, land, land)
	local H = 2 * r:NextInteger(6, 9)
	local trussZ = zl + land / 2 + 1
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = V3(2, H, 2)
	truss.CFrame = L(ctx, x, ctx.y + H / 2, trussZ)
	truss.Color = ({ RGB(255, 200, 40), RGB(255, 255, 255), RGB(90, 230, 255), RGB(90, 90, 95), RGB(255, 255, 255) })[ctx.zone]
	truss.Parent = currentFolder
	local towerD = 8
	local tz = trussZ + 1 + towerD / 2
	local newTop = ctx.y + H
	local towerColor, towerMat
	if ctx.zone == 1 then
		towerColor, towerMat = RGB(230, 45, 55), M.SmoothPlastic -- цирковая башня
	elseif ctx.zone == 2 then
		towerColor, towerMat = RGB(255, 150, 200), M.SmoothPlastic -- торт-башня
	else
		towerColor, towerMat = pick(r, ROCKS), M.Slate -- скала
	end
	column(ctx, x, tz, LAVA_BOTTOM, newTop, 8, towerD, towerColor, towerMat)
	local bands = math.floor(H / 4)
	for i = 1, bands do
		local y = ctx.y + i * 4 - 2
		if ctx.zone == 1 then -- жёлтые пояса со звёздами-огоньками
			part({ Size = V3(8.2, 0.8, towerD + 0.2), CFrame = L(ctx, x, y, tz), Color = RGB(255, 210, 50), CanCollide = false })
			for sx = -1, 1, 2 do
				part({ Shape = BALL, Size = V3(0.7, 0.7, 0.7), CFrame = L(ctx, x + sx * 4.2, y + 1.6, tz), Color = pick(r, PARTY), Material = M.Neon, CanCollide = false })
			end
		elseif ctx.zone == 2 then -- белые слои крема
			part({ Size = V3(8.3, 0.7, towerD + 0.3), CFrame = L(ctx, x, y, tz), Color = Color3.new(1, 1, 1), CanCollide = false })
		elseif ctx.zone == 3 then -- кристаллы на скале
			part({ Size = V3(0.7, 2.2, 0.7), CFrame = L(ctx, x + 4.1, y, tz + r:NextNumber(-2, 2)) * CFrame.Angles(0, 0, 0.5), Color = RGB(90, 230, 255), Material = M.Neon, CanCollide = false })
		end
	end
	if ctx.zone == 2 then -- вишенка на торте
		part({ Shape = BALL, Size = V3(1.6, 1.6, 1.6), CFrame = L(ctx, x + 2.8, newTop + 0.6, tz + 2.8), Color = RGB(220, 20, 40), CanCollide = false })
	end
	addPath(L(ctx, x, newTop, tz).Position)
	maybeCoin(ctx, x, newTop, tz, 0.8)
	ctx.y, ctx.z = newTop, tz + towerD / 2
end

function Obstacles.bounce(ctx)
	local land = 9
	local x = ctx.x
	local zl = ctx.z + 4 + land / 2
	themedPlatform(ctx, x, ctx.y, zl, land, land)
	local padZ = zl + 1.5
	local padColor = ({ RGB(80, 170, 255), RGB(255, 90, 180), RGB(90, 255, 200), RGB(255, 140, 40), RGB(90, 255, 140) })[ctx.zone]
	local pad = part({ Size = V3(5, 0.6, 5), CFrame = L(ctx, x, ctx.y + 0.3, padZ), Color = padColor, Material = M.Neon })
	pad:SetAttribute("Launch", ctx.F.LookVector * 22 + V3(0, 95, 0))
	tag(pad, "Bounce")
	-- рамка батута
	part({ Shape = CYL, Size = V3(0.5, 6.4, 6.4), CFrame = L(ctx, x, ctx.y + 0.15, padZ) * ROT_UP, Color = ctx.zone == 2 and Color3.new(1, 1, 1) or RGB(40, 40, 45), CanCollide = false })
	local rise = 15
	local depth = 16
	local tzc = padZ + 10 + depth / 2
	local newTop = ctx.y + rise
	themedPlatform(ctx, x, newTop, tzc, 12, depth)
	maybeCoin(ctx, x, newTop, tzc, 0.7)
	ctx.y, ctx.z = newTop, tzc + depth / 2
end

function Obstacles.rope(ctx)
	local r = ctx.rng
	local segs = r:NextInteger(3, 4)
	local width = math.max(1.4, 2.4 - 0.9 * ctx.diff)
	local rainbow = { RGB(255, 70, 70), RGB(255, 170, 40), RGB(255, 240, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	local beamColors = { RGB(230, 50, 60), RGB(200, 30, 70), RGB(90, 200, 255), RGB(60, 55, 55) }
	local top = ctx.y
	local function joint(jx, jz)
		part({ Size = V3(3, 1, 3), CFrame = L(ctx, jx, top - 0.5, jz), Color = ACCENT[ctx.zone] })
		addPath(L(ctx, jx, top, jz).Position)
	end
	local jx, jz = ctx.x, ctx.z + 3 + 1.5
	joint(jx, jz)
	local side = r:NextNumber() < 0.5 and -1 or 1
	for i = 1, segs do
		local nx = math.clamp(jx + side * r:NextNumber(4, 7), -12, 12)
		local nz = jz + r:NextNumber(7, 10)
		local a = L(ctx, jx, top - 0.5, jz).Position
		local b = L(ctx, nx, top - 0.5, nz).Position
		local len = (b - a).Magnitude
		part({
			Size = V3(width, 1, len),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = ctx.zone == 5 and rainbow[((i - 1) % #rainbow) + 1] or beamColors[ctx.zone],
			Material = ctx.zone == 5 and M.Neon or M.SmoothPlastic,
		})
		addPath((a + b) / 2)
		joint(nx, nz)
		if r:NextNumber() < 0.5 then
			coinAt(CF(((a + b) / 2) + V3(0, 3, 0)))
		end
		jx, jz = nx, nz
		side = -side
	end
	ctx.x, ctx.z = jx, jz + 1.5
end

function Obstacles.posts(ctx)
	local r = ctx.rng
	local n = r:NextInteger(4, 6)
	local colors = {
		pick(r, PARTY), -- цветные столбики
		pick(r, CANDY), -- карамельные палочки
		RGB(100, 88, 82), -- сталагмиты
		RGB(42, 36, 36), -- базальт
		RGB(250, 250, 255), -- облачные столбы
	}
	for _ = 1, n do
		local dia = 4.4 - 1.2 * ctx.diff
		local gap = 2.5 + 1.5 * ctx.diff
		local x = math.clamp(ctx.x + r:NextNumber(-3, 3), -10, 10)
		local top = ctx.y + (ctx.flat and 0 or r:NextNumber(ctx.y < 14 and 0 or -0.5, 1.5))
		local zc = ctx.z + gap + dia / 2
		local bottom = ctx.sky and (top - 6) or LAVA_BOTTOM
		if ctx.zone == 1 or ctx.zone == 2 then
			stripedColumn(ctx, x, zc, bottom, top, dia, ctx.zone == 1 and pick(r, PARTY) or pick(r, CANDY), Color3.new(1, 1, 1), 1.5)
			-- лампочка на верхушке
			part({ Shape = BALL, Size = V3(0.7, 0.7, 0.7), CFrame = L(ctx, x + dia / 2, top - 0.4, zc), Color = pick(r, PARTY), Material = M.Neon, CanCollide = false })
		else
			column(ctx, x, zc, bottom, top, dia, dia, colors[ctx.zone], ctx.zone == 3 and M.Slate or M.SmoothPlastic, true)
		end
		addPath(L(ctx, x, top, zc).Position)
		ctx.x, ctx.y, ctx.z = x, top, zc + dia / 2
	end
end

function Obstacles.conveyor(ctx)
	local r = ctx.rng
	local len = r:NextInteger(24, 32)
	local w = 8
	local zc = ctx.z + 4 + len / 2
	local x = ctx.x
	local belt = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, ctx.y - 0.5, zc), Color = RGB(45, 45, 50), Material = M.DiamondPlate })
	local sideways = r:NextNumber() < 0.5
	local dir
	if sideways then
		dir = ctx.F.RightVector * (r:NextNumber() < 0.5 and -1 or 1) * (3 + 3 * ctx.diff)
	else
		dir = -ctx.F.LookVector * (4 + 6 * ctx.diff)
	end
	belt.AssemblyLinearVelocity = dir
	for i = 0, math.floor(len / 4) - 1 do
		part({ Size = V3(w, 0.1, 0.6), CFrame = L(ctx, x, ctx.y + 0.05, zc - len / 2 + 2 + i * 4), Color = RGB(255, 200, 0), Material = M.Neon, CanCollide = false })
	end
	if not ctx.sky then
		column(ctx, x, zc - len / 2 + 2, LAVA_BOTTOM, ctx.y - 1, 2.5, 2.5, RGB(70, 70, 75), M.Metal)
		column(ctx, x, zc + len / 2 - 2, LAVA_BOTTOM, ctx.y - 1, 2.5, 2.5, RGB(70, 70, 75), M.Metal)
	end
	for k = 0, 2 do
		addPath(L(ctx, x, ctx.y, zc - len / 2 + k * len / 2).Position)
	end
	maybeCoin(ctx, x, ctx.y, zc, 0.8)
	ctx.x, ctx.z = x, zc + len / 2
end

function Obstacles.cave(ctx)
	local r = ctx.rng
	local len = r:NextInteger(36, 44)
	local w = 8
	local zc = ctx.z + 4 + len / 2
	local x = ctx.x
	local top = ctx.y
	walkway(ctx, x, top, zc, w, len)
	-- потолок пещеры со сталактитами
	part({ Size = V3(w + 12, 3, len + 6), CFrame = L(ctx, x, top + 23.5, zc), Color = RGB(55, 48, 46), Material = M.Slate })
	for i = 1, 6 do
		local s = r:NextNumber(1.5, 3)
		part({ Size = V3(s, r:NextNumber(3, 6), s), CFrame = L(ctx, x + r:NextNumber(-8, 8), top + 20, zc + r:NextNumber(-len / 2, len / 2)), Color = RGB(70, 60, 58), Material = M.Slate, CanCollide = false })
	end
	local count = 3 + math.floor(ctx.diff * 2)
	for i = 1, count do
		local sz = zc - len / 2 + (i / (count + 1)) * len
		local sx = x + r:NextNumber(-2.5, 2.5)
		local high = L(ctx, sx, top + 18, sz)
		local low = L(ctx, sx, top - 25, sz)
		local color = RGB(110, 90, 80)
		local s = killPart({ Size = V3(2.5, 6, 2.5), CFrame = high, Color = color, Material = M.Slate })
		table.insert(info.stalactites, { part = s, high = high, low = low, color = color, delay = r:NextNumber(0, 3), interval = r:NextNumber(1.5, 3.5) })
	end
	maybeCoin(ctx, x, top, zc, 0.9)
	ctx.x, ctx.z = x, zc + len / 2
end

function Obstacles.disks(ctx)
	local r = ctx.rng
	local n = r:NextInteger(2, 3)
	local x = ctx.x
	for i = 1, n do
		local dia = 13 - 2 * ctx.diff
		local zc = ctx.z + 3 + dia / 2
		local center = L(ctx, x, ctx.y - 0.5, zc)
		local disk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = center * ROT_UP, Color = ACCENT[ctx.zone] })
		local stripeOffset = CF(0, 0.55, 0)
		local stripe = part({ Size = V3(dia - 1, 0.2, 1.4), CFrame = center * stripeOffset, Color = Color3.new(1, 1, 1), Material = M.Neon, CanCollide = false })
		local speed = (0.4 + 0.6 * ctx.diff) * ((i % 2 == 0) and -1 or 1)
		table.insert(info.spinners, { part = disk, base = center, speed = speed, offset = ROT_UP })
		table.insert(info.spinners, { part = stripe, base = center, speed = speed, offset = stripeOffset })
		addPath(center.Position)
		if r:NextNumber() < 0.4 then
			coinAt(CF(center.Position + V3(0, 3.1, 0)))
		end
		ctx.z = zc + dia / 2
	end
	ctx.x = x
end

-- ============ НОВЫЕ ПРЕПЯТСТВИЯ ============

-- Маятники: шары качаются поперёк дорожки
function Obstacles.pendulum(ctx)
	local r = ctx.rng
	local len = r:NextInteger(26, 32)
	local w = 9
	local zc = ctx.z + 4 + len / 2
	local x = ctx.x
	local top = ctx.y
	walkway(ctx, x, top, zc, w, len)
	local H = 13
	local count = 2 + ((ctx.diff > 0.5) and 1 or 0)
	local frameColor = ACCENT[ctx.zone]
	for i = 1, count do
		local pz = zc - len / 2 + (i / (count + 1)) * len
		part({ Size = V3(1, H + 1, 1), CFrame = L(ctx, x - w / 2 - 1, top + H / 2, pz), Color = darker(frameColor, 0.75) })
		part({ Size = V3(1, H + 1, 1), CFrame = L(ctx, x + w / 2 + 1, top + H / 2, pz), Color = darker(frameColor, 0.75) })
		part({ Size = V3(w + 3, 1, 1), CFrame = L(ctx, x, top + H + 0.5, pz), Color = frameColor })
		local pivot = L(ctx, x, top + H, pz)
		local armLen = H - 3
		local armOffset = CF(0, -armLen / 2, 0)
		local arm = part({ Size = V3(0.4, armLen, 0.4), CFrame = pivot * armOffset, Color = RGB(90, 90, 100), Material = M.Metal, CanCollide = false })
		local headOffset = CF(0, -(armLen + 1), 0)
		local head = killPart({ Shape = BALL, Size = V3(3.6, 3.6, 3.6), CFrame = pivot * headOffset, Color = RGB(255, 60, 70), Material = M.Neon })
		local amp = 1.0 + 0.2 * ctx.diff
		local speed = 1.3 + 0.8 * ctx.diff
		local phase = i * 1.7
		table.insert(info.pendulums, { part = arm, pivot = pivot, offset = armOffset, amp = amp, speed = speed, phase = phase })
		table.insert(info.pendulums, { part = head, pivot = pivot, offset = headOffset, amp = amp, speed = speed, phase = phase })
		table.insert(info.killers, { part = head })
	end
	maybeCoin(ctx, x, top, zc, 0.8)
	ctx.x, ctx.z = x, zc + len / 2
end

-- Гейзеры: из лавы между платформами бьют огненные столбы
function Obstacles.geysers(ctx)
	local r = ctx.rng
	local n = r:NextInteger(3, 4)
	local x = ctx.x
	for i = 1, n do
		local gap = 4.5
		local gz = ctx.z + gap / 2
		local low = L(ctx, x, ctx.y - 16, gz) * ROT_UP
		local high = L(ctx, x, ctx.y + 3, gz) * ROT_UP
		local g = killPart({ Shape = CYL, Size = V3(14, 3.4, 3.4), CFrame = low, Color = RGB(255, 130, 0), Material = M.Neon })
		local holder = part({ Size = V3(3, 0.5, 3), CFrame = L(ctx, x, ctx.y - 7, gz), Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(RGB(255, 230, 90), RGB(255, 80, 0))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new(0.7, 0)
		pe.Speed = NumberRange.new(6, 10)
		pe.Lifetime = NumberRange.new(0.6, 1)
		pe.Rate = 0
		pe.EmissionDirection = Enum.NormalId.Top
		pe.SpreadAngle = Vector2.new(15, 15)
		pe.Parent = holder
		table.insert(info.geysers, { part = g, low = low, high = high, delay = i * 0.8 + r:NextNumber(0, 0.5), bubbles = pe })
		local size = 7
		local zc = ctx.z + gap + size / 2
		themedPlatform(ctx, x, ctx.y, zc, size, size)
		maybeCoin(ctx, x, ctx.y, zc, 0.4)
		ctx.z = zc + size / 2
	end
end

-- Лазерные ворота: красные лучи ездят вверх-вниз
function Obstacles.lasers(ctx)
	local r = ctx.rng
	local len = r:NextInteger(26, 32)
	local w = 9
	local zc = ctx.z + 4 + len / 2
	local x = ctx.x
	local top = ctx.y
	walkway(ctx, x, top, zc, w, len)
	local gates = 3
	for i = 1, gates do
		local gz = zc - len / 2 + (i / (gates + 1)) * len
		for sx = -1, 1, 2 do
			part({ Size = V3(1.2, 9.5, 1.2), CFrame = L(ctx, x + sx * (w / 2 + 0.8), top + 4.75, gz), Color = RGB(50, 50, 60), Material = M.Metal })
			part({ Size = V3(1.3, 0.6, 1.3), CFrame = L(ctx, x + sx * (w / 2 + 0.8), top + 9.6, gz), Color = RGB(255, 40, 80), Material = M.Neon })
		end
		local base = L(ctx, x, top + 4.5, gz)
		local beam = killPart({ Size = V3(w + 1.6, 0.4, 0.4), CFrame = base, Color = RGB(255, 30, 70), Material = M.Neon, CanCollide = false })
		table.insert(info.movers, { part = beam, base = base, axis = V3(0, 1, 0), amp = 3.9, speed = 1.2 + 0.8 * ctx.diff, phase = i * 2.1 + r:NextNumber(0, 1) })
		table.insert(info.killers, { part = beam })
	end
	maybeCoin(ctx, x, top, zc, 0.8)
	ctx.x, ctx.z = x, zc + len / 2
end

-- Платформы на воздушных шариках (покачиваются)
function Obstacles.balloons(ctx)
	local r = ctx.rng
	local n = r:NextInteger(4, 5)
	for i = 1, n do
		local size = 6.5
		local zc = ctx.z + 3.5 + size / 2
		local x = math.clamp(ctx.x + r:NextNumber(-5, 5), -10, 10)
		local top = ctx.y + ((ctx.flat or ctx.y < 14) and 0 or r:NextNumber(0, 1.5))
		local col = PARTY[r:NextInteger(1, #PARTY)]
		local base = L(ctx, x, top - 0.5, zc)
		local amp, speed, phase = 1.2, 1 + 0.5 * ctx.diff, i * 1.3
		local plat = part({ Size = V3(size, 1, size), CFrame = base, Color = col })
		local strOff = CF(0, 5, 0)
		local str = part({ Size = V3(0.15, 9, 0.15), CFrame = base * strOff, Color = Color3.new(1, 1, 1), CanCollide = false })
		local balOff = CF(0, 11.5, 0)
		local bal = part({ Shape = BALL, Size = V3(6, 6, 6), CFrame = base * balOff, Color = col, CanCollide = false, Reflectance = 0.1 })
		for _, pp in ipairs({ { plat, CF() }, { str, strOff }, { bal, balOff } }) do
			table.insert(info.movers, { part = pp[1], base = base * pp[2], axis = V3(0, 1, 0), amp = amp, speed = speed, phase = phase })
		end
		addPath(base.Position)
		maybeCoin(ctx, x, top + 1.2, zc, 0.4)
		ctx.x, ctx.y, ctx.z = x, top, zc + size / 2
	end
end

-- Толкающие стены: яркие блоки ездят поперёк дорожки
function Obstacles.pushers(ctx)
	local r = ctx.rng
	local len = r:NextInteger(28, 34)
	local w = 10
	local zc = ctx.z + 4 + len / 2
	local x = ctx.x
	local top = ctx.y
	walkway(ctx, x, top, zc, w, len)
	local count = 3
	for i = 1, count do
		local pz = zc - len / 2 + (i / (count + 1)) * len
		local base = L(ctx, x, top + 2, pz)
		local block = part({ Size = V3(4, 4, 3), CFrame = base, Color = PARTY[((i + ctx.stage) % #PARTY) + 1] })
		table.insert(info.movers, { part = block, base = base, axis = ctx.F.RightVector, amp = 3.2, speed = 1.1 + 0.8 * ctx.diff, phase = i * 2 + r:NextNumber(0, 1) })
	end
	maybeCoin(ctx, x, top, zc, 0.8)
	ctx.x, ctx.z = x, zc + len / 2
end

-- Безопасный островок над волной лавы (только зона 4)
local function island(ctx)
	local size = 7
	local zc = ctx.z + 3.5 + size / 2
	themedPlatform(ctx, ctx.x, ctx.y + 3, zc, size, size)
	ctx.z = zc + size / 2
end

local POOLS = {
	{ "jumps", "stripes", "climb", "rope", "posts", "vanish", "movers", "bounce", "pendulum", "balloons", "pushers", "disks", "spinner" },
	{ "jumps", "conveyor", "spinner", "bounce", "climb", "rope", "movers", "stripes", "pushers", "lasers", "geysers", "disks" },
	{ "jumps", "cave", "vanish", "posts", "climb", "rope", "disks", "geysers", "lasers", "pendulum" },
	{ "jumps", "movers", "spinner", "vanish", "disks", "posts", "conveyor", "stripes", "geysers", "lasers", "pushers" },
	{ "jumps", "bounce", "rope", "movers", "vanish", "disks", "posts", "balloons", "pendulum", "pushers" },
}

local CLIMBING = { climb = true, bounce = true }

-- ============ ЧЕКПОИНТЫ, ВОРОТА ЗОН ============
local function checkpointPad(ctx, stageNum, x, top, zc, size, isFinish)
	local zone = Config.ZoneOfStage(math.min(stageNum, TOTAL))
	local baseColor = isFinish and GOLD or darker(ACCENT[zone], 0.55)
	local pad = part({
		Name = "Checkpoint" .. stageNum,
		Size = V3(size, 1.2, size),
		CFrame = L(ctx, x, top - 0.6, zc),
		Color = baseColor,
		Material = isFinish and M.Foil or M.SmoothPlastic,
	})
	pad:SetAttribute("Stage", stageNum)
	tag(pad, "Checkpoint")
	local glow = part({
		Size = V3(6, 0.2, 6),
		CFrame = L(ctx, x, top + 0.1, zc),
		Color = isFinish and RGB(255, 255, 255) or ACCENT[zone],
		Material = M.Neon,
		CanCollide = false,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = Color3.new(0, 0, 0)
	lbl.Text = isFinish and "🏆" or tostring(stageNum)
	lbl.Parent = sg
	sg.Parent = glow
	if not ctx.sky then
		column(ctx, x, zc, LAVA_BOTTOM, top - 1.2, size - 2, size - 2, darker(baseColor, 0.6), M.SmoothPlastic)
	end
	info.checkpoints[stageNum] = pad
	addPath(L(ctx, x, top, zc).Position)
	return pad
end

local function zoneGate(ctx, zone)
	local top = ctx.y
	local z = ctx.z
	local col = ACCENT[zone]
	part({ Size = V3(2, 15, 2), CFrame = L(ctx, -8.5, top + 6.5, z), Color = darker(col, 0.6) })
	part({ Size = V3(2, 15, 2), CFrame = L(ctx, 8.5, top + 6.5, z), Color = darker(col, 0.6) })
	local zinfo = Config.Zones[zone]
	makeSign(L(ctx, 0, top + 15, z), V3(20, 5, 1.5), "sign_zone", col, Color3.new(1, 1, 1), Enum.NormalId.Back, nil, { tostring(zone), zinfo.emoji, "@zone_" .. zone })
end

-- ============ ЛОББИ ============
-- Табло лидеров: возвращает строки, которые обновляет сервер
local function makeBoard(cf, size, face, titleKey)
	local board = part({ Size = size, CFrame = cf, Color = RGB(30, 22, 40) })
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	local list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.Parent = sg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.16)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = GOLD
	title.Text = Text.Get("en", titleKey)
	title.AutoLocalize = false
	title:SetAttribute("TextKey", titleKey)
	tag(title, "LocText")
	title.LayoutOrder = 0
	title.Parent = list
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.fromScale(1, 0.084)
		row.BackgroundTransparency = 1
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = i <= 3 and ({ GOLD, RGB(220, 220, 235), RGB(230, 160, 90) })[i] or Color3.new(1, 1, 1)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = i .. ". ---"
		row.AutoLocalize = false
		row.LayoutOrder = i
		row.Parent = list
		rows[i] = row
	end
	sg.Parent = board
	-- неоновая рамка
	local fs = size + V3(0.2, 0.6, 0.6)
	part({ Size = fs, CFrame = cf, Color = RGB(255, 170, 40), Material = M.Neon, Transparency = 0.6, CanCollide = false })
	return rows
end

local function prompt(parentPart, actionKey, objectKey, attrName, attrValue)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = Text.Get("en", actionKey)
	pp.ObjectText = Text.Get("en", objectKey)
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("ActionKey", actionKey)
	pp:SetAttribute("ObjectKey", objectKey)
	pp:SetAttribute(attrName, attrValue)
	tag(pp, "LocPrompt")
	pp.Parent = parentPart
	return pp
end

-- Кольцо портала из сегментов. plane: "xy" (смотрит вперёд) или "zy" (смотрит вбок)
local function portalRing(ctx, cx, cy, cz, R, plane, colA, colB, skipBottom)
	local segs = 24
	local function pt(a)
		if plane == "xy" then
			return L(ctx, cx + math.cos(a) * R, cy + math.sin(a) * R, cz).Position
		end
		return L(ctx, cx, cy + math.sin(a) * R, cz + math.cos(a) * R).Position
	end
	for i = 0, segs - 1 do
		local a0 = i / segs * 2 * PI
		local a1 = (i + 1) / segs * 2 * PI
		local mid = (a0 + a1) / 2
		if not (skipBottom and math.sin(mid) < -0.6) then
			local p0, p1 = pt(a0), pt(a1)
			part({ Size = V3(1.8, 1.8, (p1 - p0).Magnitude + 0.3), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = (i % 2 == 0) and colA or colB, Material = M.SmoothPlastic })
			part({ Shape = BALL, Size = V3(0.9, 0.9, 0.9), CFrame = CF(p0), Color = (i % 3 == 0) and RGB(255, 255, 255) or colB, Material = M.Neon, CanCollide = false })
		end
	end
end

local function buildLobby(ctx)
	local top = 12
	local floor = part({ Name = "LobbyFloor", Size = V3(80, 2, 80), CFrame = L(ctx, 0, top - 1, 0), Color = RGB(250, 242, 230) })
	floor:SetAttribute("Stage", 1)
	info.checkpoints[1] = floor
	-- цветная плитка
	local tiles = { RGB(255, 190, 80), RGB(255, 140, 200), RGB(130, 190, 255), RGB(140, 225, 140) }
	for ix = 0, 3 do
		for iz = 0, 3 do
			if (ix + iz) % 2 == 0 then
				part({ Size = V3(19.6, 0.1, 19.6), CFrame = L(ctx, -30 + ix * 20, top + 0.03, -30 + iz * 20), Color = tiles[((ix + iz * 2) % #tiles) + 1], CanCollide = false })
			end
		end
	end
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			stripedColumn(ctx, sx * 34, sz * 34, LAVA_BOTTOM, top - 2, 7, RGB(230, 45, 55), RGB(255, 255, 255), 3)
		end
	end
	-- ограждение по краю (спереди проход к порталу)
	for i = -4, 4 do
		local c = PARTY[((i + 4) % #PARTY) + 1]
		for _, side in ipairs({ { 40, 0 }, { -40, 0 } }) do
			part({ Size = V3(0.8, 3, 0.8), CFrame = L(ctx, side[1], top + 1.5, i * 9), Color = c })
		end
		part({ Size = V3(0.8, 3, 0.8), CFrame = L(ctx, i * 9, top + 1.5, -40), Color = c })
		if math.abs(i) >= 2 then
			part({ Size = V3(0.8, 3, 0.8), CFrame = L(ctx, i * 9, top + 1.5, 40), Color = c })
		end
	end
	part({ Size = V3(0.5, 0.5, 80), CFrame = L(ctx, 40, top + 3, 0), Color = RGB(255, 255, 255) })
	part({ Size = V3(0.5, 0.5, 80), CFrame = L(ctx, -40, top + 3, 0), Color = RGB(255, 255, 255) })
	part({ Size = V3(80, 0.5, 0.5), CFrame = L(ctx, 0, top + 3, -40), Color = RGB(255, 255, 255) })

	-- точка появления
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LavaSpawn"
	spawn.Anchored = true
	spawn.Size = V3(8, 1, 8)
	spawn.CFrame = L(ctx, 0, top + 0.5, -26)
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Color = RGB(255, 170, 60)
	spawn.Material = M.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = currentFolder
	info.spawnCF[1] = L(ctx, 0, top + 4, -26)

	-- 💦 фонтан и лавочки — место, где общаются игроки
	part({ Shape = CYL, Size = V3(1.6, 16, 16), CFrame = L(ctx, 0, top + 0.8, 0) * ROT_UP, Color = RGB(200, 200, 215), Material = M.Marble })
	part({ Shape = CYL, Size = V3(0.3, 14.5, 14.5), CFrame = L(ctx, 0, top + 1.5, 0) * ROT_UP, Color = RGB(90, 180, 255), Material = M.Glass, Transparency = 0.25 })
	part({ Shape = CYL, Size = V3(5, 2, 2), CFrame = L(ctx, 0, top + 3.5, 0) * ROT_UP, Color = RGB(200, 200, 215), Material = M.Marble })
	local bowl = part({ Shape = CYL, Size = V3(0.8, 6, 6), CFrame = L(ctx, 0, top + 6.2, 0) * ROT_UP, Color = RGB(255, 200, 80), Material = M.Foil })
	local water = Instance.new("ParticleEmitter")
	water.Color = ColorSequence.new(RGB(200, 240, 255), RGB(90, 180, 255))
	water.Size = NumberSequence.new(0.5, 0.2)
	water.Transparency = NumberSequence.new(0.1, 0.8)
	water.Speed = NumberRange.new(10, 14)
	water.SpreadAngle = Vector2.new(25, 25)
	water.Acceleration = V3(0, -30, 0)
	water.Lifetime = NumberRange.new(0.8, 1.2)
	water.Rate = 60
	water.EmissionDirection = Enum.NormalId.Top
	water.Parent = bowl
	for i = 0, 3 do
		local a = i / 4 * 2 * PI + PI / 4
		local bx, bz = math.cos(a) * 13, math.sin(a) * 13
		local bcf = L(ctx, bx, top, bz) * CFrame.Angles(0, -a + PI / 2, 0)
		part({ Size = V3(6, 0.6, 2), CFrame = bcf * CF(0, 1.4, 0), Color = WOOD, Material = M.WoodPlanks })
		part({ Size = V3(6, 1.8, 0.4), CFrame = bcf * CF(0, 2.4, 1), Color = WOOD, Material = M.WoodPlanks })
		for sx = -1, 1, 2 do
			part({ Size = V3(0.4, 1.1, 1.8), CFrame = bcf * CF(sx * 2.6, 0.55, 0), Color = RGB(60, 60, 70), Material = M.Metal })
		end
	end

	-- 🌀 ГЛАВНЫЙ ПОРТАЛ: 50 этапов
	local pz, pR, pcy = 38, 9, top + 10.6
	portalRing(ctx, 0, pcy, pz, pR, "xy", RGB(255, 200, 50), RGB(255, 110, 30), true)
	for sx = -1, 1, 2 do
		part({ Size = V3(2.4, 4, 2.4), CFrame = L(ctx, sx * 7.6, top + 2, pz), Color = RGB(255, 140, 30) })
	end
	local swirl = part({ Shape = CYL, Size = V3(0.4, 2 * pR - 1, 2 * pR - 1), CFrame = L(ctx, 0, pcy, pz) * CFrame.Angles(0, PI / 2, 0), Color = RGB(255, 120, 30), Material = M.Neon, Transparency = 0.35, CanCollide = false, CanTouch = false, CanQuery = false })
	part({ Shape = CYL, Size = V3(0.5, pR, pR), CFrame = L(ctx, 0, pcy, pz) * CFrame.Angles(0, PI / 2, 0), Color = RGB(255, 230, 120), Material = M.Neon, Transparency = 0.3, CanCollide = false, CanTouch = false, CanQuery = false })
	local sw = Instance.new("ParticleEmitter")
	sw.Color = ColorSequence.new(RGB(255, 240, 150), RGB(255, 90, 20))
	sw.LightEmission = 1
	sw.Size = NumberSequence.new(0.8, 0)
	sw.Speed = NumberRange.new(2, 5)
	sw.Lifetime = NumberRange.new(1, 2)
	sw.Rate = 40
	sw.SpreadAngle = Vector2.new(180, 180)
	sw.Parent = swirl
	local pl = Instance.new("PointLight")
	pl.Color = RGB(255, 160, 60)
	pl.Range = 30
	pl.Brightness = 2
	pl.Parent = swirl
	local startLine = part({ Name = "StartLine", Size = V3(16, 14, 2), CFrame = L(ctx, 0, top + 7, pz), Transparency = 1, CanCollide = false })
	tag(startLine, "StartLine")
	makeSign(L(ctx, 0, top + 22.5, pz), V3(22, 4, 1.5), "sign_portal", RGB(255, 110, 30), Color3.new(1, 1, 1), Enum.NormalId.Back)

	-- 🔒 секретный портал (часть 2)
	portalRing(ctx, -34, top + 7.2, 24, 6, "zy", RGB(170, 90, 255), RGB(90, 230, 255), true)
	part({ Shape = CYL, Size = V3(0.4, 11, 11), CFrame = L(ctx, -34, top + 7.2, 24), Color = RGB(150, 70, 255), Material = M.Neon, Transparency = 0.4, CanCollide = true })
	makeSign(L(ctx, -33.4, top + 15.5, 24), V3(0.5, 3.5, 12), "sign_secret_portal", RGB(60, 25, 90), RGB(220, 190, 255), Enum.NormalId.Right)

	-- 🏆 таблицы лидеров (левая стена)
	info.leaderboardRows = makeBoard(L(ctx, -38.5, top + 9, -12), V3(1, 13, 17), Enum.NormalId.Right, "sign_top")
	info.timeRows = makeBoard(L(ctx, -38.5, top + 9, 7), V3(1, 13, 17), Enum.NormalId.Right, "sign_top_time")

	-- 🔥 приветственная табличка + уточка №1 на ней (лестница сзади)
	local post = RGB(80, 50, 30)
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, -30, top + 2, -37), Color = post })
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, -14, top + 2, -37), Color = post })
	makeSign(L(ctx, -22, top + 9, -37), V3(18, 12, 1), "sign_welcome", RGB(60, 20, 10), RGB(255, 210, 90), Enum.NormalId.Front)
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = V3(2, 16, 2)
	truss.CFrame = L(ctx, -16, top + 8, -39.5)
	truss.Color = RGB(255, 200, 40)
	truss.Parent = currentFolder
	part({ Size = V3(6, 1, 4), CFrame = L(ctx, -16, top + 15.5, -36.4), Color = post })
	makeDuck(L(ctx, -17, top + 17.5, -36.4), 1)

	-- 🐾 магазин питомцев (справа спереди)
	local kx, kz = 32, 22
	local counter = part({ Size = V3(3, 3, 12), CFrame = L(ctx, kx - 2, top + 1.5, kz), Color = RGB(255, 140, 200) })
	part({ Size = V3(3.4, 0.4, 12.4), CFrame = L(ctx, kx - 2, top + 3.2, kz), Color = Color3.new(1, 1, 1) })
	for _, c in ipairs({ { -3.5, -6 }, { -3.5, 6 }, { 3.5, -6 }, { 3.5, 6 } }) do
		part({ Size = V3(0.6, 8, 0.6), CFrame = L(ctx, kx + c[1], top + 4, kz + c[2]), Color = Color3.new(1, 1, 1) })
	end
	for i = 0, 5 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = V3(2, 1.6, 8.6)
		w.CFrame = L(ctx, kx, top + 8.6, kz - 5 + i * 2) * CFrame.Angles(0, PI / 2, 0)
		w.Color = (i % 2 == 0) and RGB(255, 90, 150) or Color3.new(1, 1, 1)
		w.Parent = currentFolder
	end
	makeSign(L(ctx, kx - 4.4, top + 10.8, kz), V3(0.4, 2.6, 12), "sign_petshop", RGB(255, 90, 150), Color3.new(1, 1, 1), Enum.NormalId.Left)
	prompt(counter, "prompt_open", "prompt_petshop", "OpenShop", "pets")
	-- витрина: три цветных постамента
	for i = -1, 1 do
		part({ Shape = CYL, Size = V3(2, 2.2, 2.2), CFrame = L(ctx, kx + 1.5, top + 1, kz + i * 3.5) * ROT_UP, Color = PARTY[i + 2] })
		part({ Shape = BALL, Size = V3(1.6, 1.6, 1.6), CFrame = L(ctx, kx + 1.5, top + 2.8, kz + i * 3.5), Color = PARTY[i + 4], Material = M.Neon })
	end

	-- 📋 стойка заданий дня (справа посередине)
	local dx, dz = 34, -2
	local dailyChest = makeChest(L(ctx, dx - 4, top, dz) * CFrame.Angles(0, PI / 2, 0), "dailystand", "DailyStand")
	prompt(dailyChest.PrimaryPart or dailyChest:FindFirstChild("Base"), "prompt_open", "prompt_tasks", "OpenTasks", true)
	local dboard = part({ Name = "ChallengeBoard", Size = V3(0.6, 9, 14), CFrame = L(ctx, dx + 3, top + 6, dz), Color = RGB(30, 40, 70) })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	local lst = Instance.new("Frame")
	lst.Size = UDim2.fromScale(1, 1)
	lst.BackgroundTransparency = 1
	lst.Parent = sg
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = lst
	for i = 0, 3 do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, i == 0 and 0.25 or 0.25)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = i == 0 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		lbl.TextColor3 = i == 0 and GOLD or Color3.new(1, 1, 1)
		lbl.AutoLocalize = false
		lbl.LayoutOrder = i
		if i == 0 then
			lbl.Text = Text.Get("en", "sign_daily")
			lbl:SetAttribute("TextKey", "sign_daily")
			tag(lbl, "LocText")
		else
			lbl.Name = "Row" .. i
			lbl.Text = "..."
			tag(lbl, "ChallengeRow")
		end
		lbl.Parent = lst
	end
	sg.Parent = dboard
	part({ Size = V3(0.8, 9.6, 14.6), CFrame = L(ctx, dx + 3.2, top + 6, dz), Color = RGB(90, 200, 255), Material = M.Neon, Transparency = 0.6, CanCollide = false })

	-- 👑 VIP-комната (сзади справа)
	local wallC = RGB(110, 50, 150)
	local h = 10
	local cx, cz = 29, -29
	part({ Size = V3(18, h, 1), CFrame = L(ctx, cx, top + h / 2, cz - 9), Color = wallC })
	part({ Size = V3(1, h, 18), CFrame = L(ctx, cx + 9, top + h / 2, cz), Color = wallC })
	part({ Size = V3(18, h, 1), CFrame = L(ctx, cx, top + h / 2, cz + 9), Color = wallC })
	part({ Size = V3(1, h, 6), CFrame = L(ctx, cx - 9, top + h / 2, cz - 6), Color = wallC })
	part({ Size = V3(1, h, 6), CFrame = L(ctx, cx - 9, top + h / 2, cz + 6), Color = wallC })
	part({ Size = V3(1, 1, 6), CFrame = L(ctx, cx - 9, top + h - 0.5, cz), Color = wallC })
	part({ Size = V3(19, 1, 19), CFrame = L(ctx, cx, top + h + 0.5, cz), Color = GOLD, Material = M.Foil })
	local door = part({ Name = "VipDoor", Size = V3(1, h - 1, 6), CFrame = L(ctx, cx - 9, top + (h - 1) / 2, cz), Color = GOLD, Material = M.Neon, Transparency = 0.35 })
	tag(door, "VipDoor")
	makeSign(L(ctx, cx - 9.7, top + h + 2.5, cz), V3(0.5, 3, 8), "sign_vip", RGB(110, 50, 150), GOLD, Enum.NormalId.Left)
	makeChest(L(ctx, cx + 5, top, cz - 5) * CFrame.Angles(0, -PI / 2, 0), "vip", "VipChest")
	makeSign(L(ctx, cx + 8.4, top + 6, cz), V3(0.4, 4, 12), "sign_vipchest", RGB(70, 25, 100), GOLD, Enum.NormalId.Left)
	local vipLight = part({ Size = V3(2, 0.4, 2), CFrame = L(ctx, cx, top + h - 0.2, cz), Color = GOLD, Material = M.Neon, CanCollide = false })
	local vl = Instance.new("PointLight")
	vl.Range = 18
	vl.Color = GOLD
	vl.Parent = vipLight

	-- фонари
	for _, p in ipairs({ { -20, 20 }, { 20, 30 }, { -20, -20 }, { 20, -14 }, { 0, 20 } }) do
		part({ Shape = CYL, Size = V3(9, 0.8, 0.8), CFrame = L(ctx, p[1], top + 4.5, p[2]) * ROT_UP, Color = RGB(50, 50, 60), Material = M.Metal })
		local bulb = part({ Shape = BALL, Size = V3(2, 2, 2), CFrame = L(ctx, p[1], top + 9.5, p[2]), Color = RGB(255, 230, 160), Material = M.Neon })
		local l = Instance.new("PointLight")
		l.Range = 24
		l.Color = RGB(255, 210, 150)
		l.Parent = bulb
	end

	addPath(L(ctx, 0, top, 0).Position)
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			addPath(L(ctx, sx * 36, top, sz * 36).Position)
		end
	end
	ctx.x, ctx.y, ctx.z = 0, top, 40
end

-- ============ ОСОБЫЕ МЕСТА (ПАСХАЛКИ) ============
local Specials = {}

-- Чекпоинт 7: тайная уточка сбоку
Specials[7] = function(ctx)
	local top = ctx.y
	part({ Size = V3(4, 1, 4), CFrame = L(ctx, -11.5, top + 0.5, 2), Color = WOOD, Material = M.Wood })
	part({ Size = V3(5, 1, 5), CFrame = L(ctx, -18, top + 2, -1), Color = WOOD, Material = M.Wood })
	makeDuck(L(ctx, -18, top + 4, -1), 2)
	addPath(L(ctx, -18, top, -1).Position)
end

-- Чекпоинт 15: кнопка «лава → вода»
Specials[15] = function(ctx)
	local top = ctx.y
	part({ Size = V3(6, 1, 6), CFrame = L(ctx, 13, top - 0.5, 0), Color = RGB(235, 235, 235) })
	if not ctx.sky then
		column(ctx, 13, 0, LAVA_BOTTOM, top - 1, 2, 2, RGB(200, 200, 200), M.Metal)
	end
	part({ Size = V3(2, 2, 2), CFrame = L(ctx, 14, top + 1, 0), Color = RGB(60, 60, 65), Material = M.Metal })
	local button = part({ Name = "LavaButton", Shape = CYL, Size = V3(0.6, 2.4, 2.4), CFrame = L(ctx, 14, top + 2.3, 0) * ROT_UP, Color = RGB(255, 30, 30), Material = M.Neon })
	tag(button, "LavaButton")
	makeSign(L(ctx, 16.3, top + 4, 0), V3(0.4, 3, 6), "sign_button", RGB(20, 20, 20), RGB(255, 80, 80), Enum.NormalId.Left)
	addPath(L(ctx, 13, top, 0).Position)
end

-- Чекпоинт 23: секретная комната за лавопадом
Specials[23] = function(ctx)
	local top = ctx.y
	local rock = RGB(60, 52, 50)
	part({ Size = V3(15, 1, 12), CFrame = L(ctx, 14.5, top - 0.5, 0), Color = rock, Material = M.Slate })
	part({ Size = V3(1, 10, 12), CFrame = L(ctx, 22.5, top + 5, 0), Color = rock, Material = M.Slate })
	part({ Size = V3(16, 10, 1), CFrame = L(ctx, 14.5, top + 5, 6.5), Color = rock, Material = M.Slate })
	part({ Size = V3(16, 10, 1), CFrame = L(ctx, 14.5, top + 5, -6.5), Color = rock, Material = M.Slate })
	part({ Size = V3(16, 1, 14), CFrame = L(ctx, 14.5, top + 10.5, 0), Color = rock, Material = M.Slate })
	if not ctx.sky then
		column(ctx, 14.5, 0, LAVA_BOTTOM, top - 1, 6, 6, RGB(40, 35, 34), M.Basalt)
	end
	-- подземный водопад: через него можно пройти насквозь
	local fall = part({
		Name = "Lavafall",
		Size = V3(0.6, 42, 12),
		CFrame = L(ctx, 7.6, top - 9, 0),
		Color = RGB(90, 190, 255),
		Material = M.Neon,
		Transparency = 0.3,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	})
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(RGB(220, 245, 255), RGB(90, 180, 255))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.6, 0)
	pe.Speed = NumberRange.new(2, 5)
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Rate = 15
	pe.Parent = fall
	makeChest(L(ctx, 19, top, 0) * CFrame.Angles(0, PI / 2, 0), "lavafall")
	makeDuck(L(ctx, 18, top + 1.5, 4.5) * CFrame.Angles(0, PI / 2, 0), 3)
	makeSign(L(ctx, 21.9, top + 6, 0), V3(0.4, 3, 9), "sign_secret", RGB(30, 20, 20), GOLD, Enum.NormalId.Left)
	local torch = part({ Size = V3(0.6, 2, 0.6), CFrame = L(ctx, 21.5, top + 4, -4.5), Color = WOOD_DARK, CanCollide = false })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Parent = torch
	local tl = Instance.new("PointLight")
	tl.Color = RGB(255, 150, 60)
	tl.Range = 16
	tl.Parent = torch
	addPath(L(ctx, 14.5, top, 0).Position)
end

-- Чекпоинт 28: «НЕ ПРЫГАЙ СЮДА» — внизу тайная пещера
Specials[28] = function(ctx)
	local top = ctx.y
	part({ Size = V3(0.5, 3.5, 0.5), CFrame = L(ctx, -6.5, top + 1.75, -6.5), Color = WOOD_DARK })
	makeSign(L(ctx, -6.5, top + 4.3, -6.5), V3(6, 2, 0.4), "sign_dontjump", RGB(250, 220, 40), RGB(20, 20, 20), Enum.NormalId.Back)
	local caveTop = math.max(top - 14, 5)
	local rock = RGB(50, 44, 44)
	part({ Size = V3(17, 1, 16), CFrame = L(ctx, -15.5, caveTop - 0.5, 0), Color = rock, Material = M.Slate })
	column(ctx, -15.5, 0, LAVA_BOTTOM, caveTop - 1, 6, 6, RGB(40, 35, 34), M.Basalt)
	part({ Size = V3(1, 10, 16), CFrame = L(ctx, -24.5, caveTop + 5, 0), Color = rock, Material = M.Slate })
	part({ Size = V3(18, 10, 1), CFrame = L(ctx, -15.5, caveTop + 5, 8.5), Color = rock, Material = M.Slate })
	part({ Size = V3(18, 10, 1), CFrame = L(ctx, -15.5, caveTop + 5, -8.5), Color = rock, Material = M.Slate })
	makeSign(L(ctx, -23.9, caveTop + 5, 0), V3(0.4, 4, 12), "sign_jumped", RGB(30, 25, 25), RGB(255, 220, 90), Enum.NormalId.Right)
	makeChest(L(ctx, -21, caveTop, -4) * CFrame.Angles(0, -PI / 2, 0), "dontjump")
	makeDuck(L(ctx, -19, caveTop + 1.5, 3) * CFrame.Angles(0, -PI / 2, 0), 4)
	local tp = part({ Name = "Teleporter", Size = V3(4, 0.4, 4), CFrame = L(ctx, -12, caveTop + 0.2, 5), Color = RGB(60, 230, 255), Material = M.Neon })
	tag(tp, "Teleport")
	makeSign(L(ctx, -12, caveTop + 3.5, 7.9), V3(5, 1.6, 0.3), "sign_back", RGB(20, 60, 80), Color3.new(1, 1, 1), Enum.NormalId.Back)
	local cl = part({ Size = V3(1, 1, 1), CFrame = L(ctx, -15, caveTop + 8, 0), Transparency = 1, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range = 20
	pl.Color = RGB(255, 140, 70)
	pl.Parent = cl
	addPath(L(ctx, -15.5, caveTop, 0).Position)
end

-- Чекпоинт 45: радужная тропинка к последней уточке
Specials[45] = function(ctx)
	local top = ctx.y
	local a = L(ctx, 7, top - 0.5, 0).Position
	local b = L(ctx, 24, top + 1.5, 0).Position
	part({ Size = V3(1.2, 1, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(255, 120, 220), Material = M.Neon })
	part({ Shape = CYL, Size = V3(1.5, 8, 8), CFrame = L(ctx, 27.5, top + 1.25, 0) * ROT_UP, Color = RGB(255, 255, 255) })
	makeDuck(L(ctx, 27.5, top + 3.5, 0) * CFrame.Angles(0, PI / 2, 0), 5)
	addPath(L(ctx, 27.5, top, 0).Position)
end

-- 🏰 Финиш: золотой замок в облаках
local function castleTower(ctx, x, top, z, dia, h, roofColor)
	local stone = RGB(255, 225, 140)
	part({ Shape = CYL, Size = V3(h, dia, dia), CFrame = L(ctx, x, top + h / 2, z) * ROT_UP, Color = stone })
	part({ Shape = CYL, Size = V3(1, dia + 1, dia + 1), CFrame = L(ctx, x, top + h + 0.5, z) * ROT_UP, Color = GOLD, Material = M.Foil })
	-- зубцы
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		part({ Size = V3(1.2, 1.4, 1.2), CFrame = L(ctx, x + math.cos(a) * dia / 2, top + h + 1.7, z + math.sin(a) * dia / 2), Color = stone })
	end
	-- конусная крыша из колец
	local layers = 6
	for i = 0, layers - 1 do
		local d = (dia + 1) * (1 - i / layers)
		part({ Shape = CYL, Size = V3(1.6, d, d), CFrame = L(ctx, x, top + h + 2 + i * 1.6, z) * ROT_UP, Color = (i % 2 == 0) and roofColor or roofColor:Lerp(Color3.new(1, 1, 1), 0.25) })
	end
	local tipY = top + h + 2 + layers * 1.6
	part({ Shape = BALL, Size = V3(1.4, 1.4, 1.4), CFrame = L(ctx, x, tipY, z), Color = GOLD, Material = M.Foil })
	part({ Size = V3(0.2, 4, 0.2), CFrame = L(ctx, x, tipY + 2.5, z), Color = RGB(80, 80, 90) })
	local flag = part({ Size = V3(0.1, 1.6, 2.6), CFrame = L(ctx, x, tipY + 3.6, z + 1.35), Color = PARTY[(math.floor(x + z) % #PARTY) + 1], CanCollide = false })
	flag:SetAttribute("Wave", true)
	-- окна
	for i = 0, 3 do
		local a = i / 4 * 2 * PI + PI / 4
		part({ Size = V3(0.3, 2, 1.2), CFrame = L(ctx, x + math.cos(a) * dia / 2, top + h * 0.6, z + math.sin(a) * dia / 2) * CFrame.Angles(0, -a, 0), Color = RGB(90, 170, 255), Material = M.Neon, CanCollide = false })
	end
end

local function buildFinish(ctx)
	local top = ctx.y
	local stone = RGB(255, 225, 140)
	-- кубок на постаменте перед замком
	part({ Size = V3(6, 3, 6), CFrame = L(ctx, 0, top + 1.5, 6), Color = RGB(250, 245, 235), Material = M.Marble })
	part({ Shape = CYL, Size = V3(3, 1.6, 1.6), CFrame = L(ctx, 0, top + 4.5, 6) * ROT_UP, Color = GOLD, Material = M.Foil })
	local cup = part({ Shape = CYL, Size = V3(4, 5, 5), CFrame = L(ctx, 0, top + 8, 6) * ROT_UP, Color = GOLD, Material = M.Neon })
	for sx = -1, 1, 2 do
		part({ Shape = CYL, Size = V3(0.6, 2.4, 2.4), CFrame = L(ctx, sx * 3, top + 8.5, 6), Color = GOLD, Material = M.Foil, CanCollide = false })
	end
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = GOLD
	sp.Parent = cup
	local cl = Instance.new("PointLight")
	cl.Color = GOLD
	cl.Range = 25
	cl.Brightness = 2
	cl.Parent = cup

	-- двор замка (по нему можно ходить)
	part({ Size = V3(50, 2, 36), CFrame = L(ctx, 0, top - 1, 33), Color = RGB(250, 245, 235), Material = M.Marble })
	part({ Size = V3(8, 0.2, 36), CFrame = L(ctx, 0, top + 0.05, 33), Color = RGB(220, 40, 60), Material = M.Fabric, CanCollide = false })
	-- облака под замком
	for i = 1, 10 do
		local a = i / 10 * 2 * PI
		local s = 14 + (i % 3) * 4
		part({ Shape = BALL, Size = V3(s, s, s), CFrame = L(ctx, math.cos(a) * 24, top - 7, 30 + math.sin(a) * 18), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
	end

	-- стены
	local wh = 14
	part({ Size = V3(19, wh, 3), CFrame = L(ctx, -15.5, top + wh / 2, 16.5), Color = stone })
	part({ Size = V3(19, wh, 3), CFrame = L(ctx, 15.5, top + wh / 2, 16.5), Color = stone })
	part({ Size = V3(12, 4, 3), CFrame = L(ctx, 0, top + wh - 2, 16.5), Color = stone })
	part({ Size = V3(3, wh, 36), CFrame = L(ctx, -25.5, top + wh / 2, 33), Color = stone })
	part({ Size = V3(3, wh, 36), CFrame = L(ctx, 25.5, top + wh / 2, 33), Color = stone })
	part({ Size = V3(50, wh, 3), CFrame = L(ctx, 0, top + wh / 2, 49.5), Color = stone })
	for i = -8, 8 do
		if math.abs(i) > 1 then
			part({ Size = V3(1.6, 1.6, 3), CFrame = L(ctx, i * 3, top + wh + 0.8, 16.5), Color = stone })
		end
	end
	-- золотая арка ворот и знамёна
	part({ Size = V3(13, 1.2, 3.4), CFrame = L(ctx, 0, top + wh - 4.2, 16.5), Color = GOLD, Material = M.Foil })
	for sx = -1, 1, 2 do
		part({ Size = V3(1.2, wh - 4, 3.4), CFrame = L(ctx, sx * 6.2, top + (wh - 4) / 2, 16.5), Color = GOLD, Material = M.Foil })
		part({ Size = V3(4, 8, 0.2), CFrame = L(ctx, sx * 13, top + 8, 14.9), Color = RGB(200, 30, 50), CanCollide = false })
		part({ Size = V3(1.6, 1.6, 0.25), CFrame = L(ctx, sx * 13, top + 9, 14.8), Color = GOLD, Material = M.Neon, CanCollide = false })
	end
	makeSign(L(ctx, 0, top + wh + 4, 15.2), V3(26, 4, 0.6), "sign_castle", RGB(120, 40, 160), GOLD, Enum.NormalId.Back)
	makeSign(L(ctx, 0, top + wh + 9, 15.2), V3(30, 5, 0.6), "sign_finish", RGB(50, 20, 80), GOLD, Enum.NormalId.Back)

	-- башни по углам и главная башня
	local roof = RGB(90, 120, 255)
	castleTower(ctx, -25.5, top, 16.5, 8, 20, roof)
	castleTower(ctx, 25.5, top, 16.5, 8, 20, roof)
	castleTower(ctx, -25.5, top, 49.5, 8, 20, RGB(200, 90, 255))
	castleTower(ctx, 25.5, top, 49.5, 8, 20, RGB(200, 90, 255))
	part({ Size = V3(22, 22, 14), CFrame = L(ctx, 0, top + 11, 40), Color = stone })
	for i = -1, 1 do
		part({ Size = V3(2.4, 4, 0.3), CFrame = L(ctx, i * 6, top + 14, 32.9), Color = RGB(90, 170, 255), Material = M.Neon, CanCollide = false })
	end
	castleTower(ctx, 0, top + 22, 40, 11, 14, RGB(255, 90, 150))

	-- салют
	local rainbow = { RGB(255, 70, 70), RGB(255, 170, 40), RGB(255, 240, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	for i, c in ipairs(rainbow) do
		local pe = part({ Size = V3(1, 1, 1), CFrame = L(ctx, -14 + (i - 1) * 5.6, top + 0.5, -14), Transparency = 1, CanCollide = false })
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(c)
		em.LightEmission = 0.8
		em.Size = NumberSequence.new(0.5)
		em.Speed = NumberRange.new(25, 35)
		em.SpreadAngle = Vector2.new(15, 15)
		em.Acceleration = V3(0, -20, 0)
		em.Lifetime = NumberRange.new(2, 3)
		em.Rate = 12
		em.EmissionDirection = Enum.NormalId.Top
		em.Parent = pe
	end
	-- радуга над замком
	local a0 = L(ctx, 0, top, 33)
	local bands = { RGB(255, 70, 70), RGB(255, 200, 50), RGB(80, 220, 90), RGB(80, 160, 255) }
	for b, col in ipairs(bands) do
		local R = 48 - (b - 1) * 2.2
		local prev
		for i = 0, 16 do
			local a = (i / 16) * PI
			local pt = (a0 * CF(math.cos(a) * R, math.sin(a) * R * 0.75, 4)).Position
			if prev then
				part({ Size = V3(2.2, 1.2, (pt - prev).Magnitude + 0.4), CFrame = CFrame.lookAt((pt + prev) / 2, pt), Color = col, Material = M.Neon, CanCollide = false, CastShadow = false })
			end
			prev = pt
		end
	end
end

-- ============ ДЕКОР ============
local function farFromPath(pos, minDist)
	local m2 = minDist * minDist
	for _, p in ipairs(info.pathPoints) do
		local dx, dz = p.X - pos.X, p.Z - pos.Z
		if dx * dx + dz * dz < m2 then
			return false
		end
	end
	return true
end

local FESTIVE = {
	RGB(255, 90, 150),
	RGB(80, 210, 255),
	RGB(255, 220, 60),
	RGB(120, 230, 90),
	RGB(180, 110, 255),
	RGB(255, 150, 50),
}

-- Праздничный декор во всех зонах: связки шариков и гирлянды флажков
local function festive(pos, rng, pathY)
	local base = CF(pos.X, 0, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
	if rng:NextNumber() < 0.5 then
		local knot = base * CF(0, pathY + rng:NextNumber(0, 8), 0)
		for i = 1, rng:NextInteger(5, 8) do
			local s = rng:NextNumber(3.5, 5.5)
			local off = V3(rng:NextNumber(-3, 3), rng:NextNumber(7, 12), rng:NextNumber(-3, 3))
			local bp = (knot * CF(off)).Position
			part({ Shape = BALL, Size = V3(s, s, s), CFrame = CF(bp), Color = FESTIVE[((i - 1) % #FESTIVE) + 1], CanCollide = false, Reflectance = 0.1, CastShadow = false })
			local a = knot.Position
			part({ Size = V3(0.1, 0.1, (bp - a).Magnitude), CFrame = CFrame.lookAt((a + bp) / 2, bp), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
		end
	else
		local h = pathY + rng:NextNumber(6, 14)
		local span = rng:NextNumber(24, 36)
		local a = (base * CF(-span / 2, h, 0)).Position
		local b = (base * CF(span / 2, h, 0)).Position
		for _, p in ipairs({ a, b }) do
			part({ Shape = CYL, Size = V3(h + 2, 1.2, 1.2), CFrame = CF(p.X, (h - 2) / 2, p.Z) * ROT_UP, Color = RGB(250, 250, 255) })
			part({ Shape = BALL, Size = V3(2, 2, 2), CFrame = CF(p), Color = FESTIVE[rng:NextInteger(1, #FESTIVE)], Material = M.Neon })
		end
		local sag = V3(0, -3, 0)
		local flags = 10
		local prev = a
		for i = 1, flags do
			local t = i / flags
			local pt = a:Lerp(b, t) + sag * (4 * t * (1 - t))
			part({ Size = V3(0.08, 0.08, (pt - prev).Magnitude), CFrame = CFrame.lookAt((prev + pt) / 2, pt), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
			local w = Instance.new("WedgePart")
			w.Anchored = true
			w.CanCollide = false
			w.CastShadow = false
			w.Size = V3(0.1, 2.2, 1.6)
			w.CFrame = CFrame.lookAt(pt, pt + (b - a).Unit) * CF(0, -1.1, 0) * CFrame.Angles(PI, 0, 0)
			w.Color = FESTIVE[(i % #FESTIVE) + 1]
			w.Parent = currentFolder
			prev = pt
		end
	end
end

-- ============ ДОСТОПРИМЕЧАТЕЛЬНОСТИ МИРОВ ============
-- Колесо обозрения (крутится, кабинки висят ровно)
local function ferrisWheel(base, rng, pathY)
	local R = 22
	local cy = math.max(pathY - 4, R + 6)
	local center = base * CF(0, cy, 0)
	-- опоры буквой «А»
	for sz = -1, 1, 2 do
		for sx = -1, 1, 2 do
			local foot = (base * CF(sx * 14, 0, sz * 4)).Position
			local hub = (center * CF(0, 0, sz * 3)).Position
			part({ Size = V3(1.4, 1.4, (hub - foot).Magnitude), CFrame = CFrame.lookAt((foot + hub) / 2, hub), Color = Color3.new(1, 1, 1), Material = M.Metal })
		end
	end
	part({ Shape = CYL, Size = V3(8, 3, 3), CFrame = center * CFrame.Angles(0, PI / 2, 0), Color = RGB(80, 80, 90), Material = M.Metal })
	local segs = 24
	for i = 0, segs - 1 do
		local a0, a1 = i / segs * 2 * PI, (i + 1) / segs * 2 * PI
		local p0 = (center * CF(math.cos(a0) * R, math.sin(a0) * R, 0)).Position
		local p1 = (center * CF(math.cos(a1) * R, math.sin(a1) * R, 0)).Position
		rotor(part({ Size = V3(1, 1, (p1 - p0).Magnitude + 0.2), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = RGB(255, 255, 255) }), center, "z", 0.15)
		rotor(part({ Shape = BALL, Size = V3(1.1, 1.1, 1.1), CFrame = CF(p0), Color = PARTY[(i % #PARTY) + 1], Material = M.Neon }), center, "z", 0.15)
	end
	local cabins = 12
	for i = 0, cabins - 1 do
		local a = i / cabins * 2 * PI
		local rim = (center * CF(math.cos(a) * R, math.sin(a) * R, 0)).Position
		rotor(part({ Size = V3(0.5, 0.5, R), CFrame = CFrame.lookAt((center.Position + rim) / 2, rim), Color = RGB(220, 220, 230), Material = M.Metal }), center, "z", 0.15)
		local col = PARTY[(i % #PARTY) + 1]
		rotor(part({ Size = V3(3.2, 2.6, 3.2), CFrame = CF(rim - V3(0, 2.6, 0)) * center.Rotation, Color = col }), center, "z", 0.15, 2.6)
		rotor(part({ Size = V3(3.6, 0.5, 3.6), CFrame = CF(rim - V3(0, 1.1, 0)) * center.Rotation, Color = col:Lerp(Color3.new(1, 1, 1), 0.4) }), center, "z", 0.15, 1.1)
	end
end

-- Шатёр цирка в полоску
local function circusTent(base, rng, pathY)
	local R = 14
	local h = math.max(10, pathY - 8)
	local panels = 16
	for i = 0, panels - 1 do
		local a = i / panels * 2 * PI
		local p = base * CFrame.Angles(0, a, 0) * CF(0, h / 2, -R)
		part({ Size = V3(2 * PI * R / panels + 0.3, h, 0.6), CFrame = p, Color = (i % 2 == 0) and RGB(230, 40, 50) or Color3.new(1, 1, 1) })
	end
	local layers = 7
	for i = 0, layers - 1 do
		local d = (2 * R + 2) * (1 - i / layers)
		part({ Shape = CYL, Size = V3(2.2, d, d), CFrame = base * CF(0, h + 1.1 + i * 2.2, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(230, 40, 50) or RGB(255, 210, 50) })
	end
	local tipY = h + 2 + layers * 2.2
	part({ Size = V3(0.3, 6, 0.3), CFrame = base * CF(0, tipY + 3, 0), Color = RGB(80, 80, 90) })
	local flag = part({ Size = V3(0.1, 2, 3.4), CFrame = base * CF(0, tipY + 5, 1.7), Color = RGB(255, 210, 50), CanCollide = false })
	flag:SetAttribute("Wave", true)
	-- вход и гирлянда лампочек
	part({ Size = V3(6, 7, 1), CFrame = base * CF(0, 3.5, -R - 0.1), Color = RGB(30, 20, 40) })
	for i = 0, 23 do
		local a = i / 24 * 2 * PI
		local b = part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = base * CFrame.Angles(0, a, 0) * CF(0, h + 0.3, -R - 0.8), Color = PARTY[(i % #PARTY) + 1], Material = M.Neon, CanCollide = false })
		if i % 6 == 0 then
			local pl = Instance.new("PointLight")
			pl.Color = b.Color
			pl.Range = 14
			pl.Parent = b
		end
	end
end

-- Карусель с лошадками (крутится)
local function carousel(base, rng, pathY)
	local y = math.max(2, pathY - 16)
	local stand = base * CF(0, y, 0)
	part({ Shape = CYL, Size = V3(y + 2, 4, 4), CFrame = base * CF(0, y / 2 - 1, 0) * ROT_UP, Color = RGB(255, 210, 60) })
	part({ Shape = CYL, Size = V3(1.4, 22, 22), CFrame = stand * ROT_UP, Color = RGB(255, 140, 200) })
	part({ Shape = CYL, Size = V3(10, 1.6, 1.6), CFrame = stand * CF(0, 5, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
	for i = 0, 4 do
		local d = 24 * (1 - i / 5)
		part({ Shape = CYL, Size = V3(1.4, d, d), CFrame = stand * CF(0, 10.7 + i * 1.4, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(80, 170, 255) or Color3.new(1, 1, 1) })
	end
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		local hp = stand * CFrame.Angles(0, a, 0) * CF(0, 0, -8)
		local col = PARTY[(i % #PARTY) + 1]
		rotor(part({ Size = V3(0.3, 10, 0.3), CFrame = hp * CF(0, 5, 0), Color = GOLD, Material = M.Foil }), stand, "y", 0.6)
		rotor(part({ Size = V3(1.2, 1.6, 3.2), CFrame = hp * CF(0, 4, 0), Color = col }), stand, "y", 0.6)
		rotor(part({ Size = V3(1, 1.8, 1.2), CFrame = hp * CF(0, 5.2, -1.6) * CFrame.Angles(-0.4, 0, 0), Color = col }), stand, "y", 0.6)
		rotor(part({ Size = V3(0.4, 1.4, 1.4), CFrame = hp * CF(0, 5.4, -0.8), Color = Color3.new(1, 1, 1) }), stand, "y", 0.6)
	end
end

-- Американские горки (холмы рельсов на опорах)
local function coaster(base, rng, pathY)
	local h0 = math.max(8, pathY - 6)
	local prev
	for i = 0, 20 do
		local t = i / 20
		local x = -36 + 72 * t
		local y = h0 + math.sin(t * PI * 3) * 8 + 8
		local pt = base * CF(x, y, 0)
		if prev then
			for sz = -1, 1, 2 do
				local a = (prev * CF(0, 0, sz * 1.2)).Position
				local b = (pt * CF(0, 0, sz * 1.2)).Position
				part({ Size = V3(0.5, 0.5, (b - a).Magnitude + 0.2), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(255, 60, 80), Material = M.Metal })
			end
			local mid = prev.Position:Lerp(pt.Position, 0.5)
			part({ Size = V3(0.4, 0.3, 3), CFrame = CF(mid) * base.Rotation, Color = RGB(240, 240, 240) })
		end
		if i % 4 == 0 then
			part({ Size = V3(0.8, y, 0.8), CFrame = base * CF(x, y / 2, 0), Color = Color3.new(1, 1, 1), Material = M.Metal })
		end
		prev = pt
	end
	-- вагончик
	local car = base * CF(-6, h0 + math.sin(0.3 * PI * 3) * 8 + 9.4, 0)
	part({ Size = V3(4, 1.8, 3), CFrame = car, Color = RGB(255, 210, 50) })
	part({ Size = V3(1, 1.4, 3.2), CFrame = car * CF(-1.6, 1, 0), Color = RGB(255, 80, 120) })
end

-- Гигантский леденец (спираль крутится)
local function lollipop(base, rng, pathY)
	local h = math.max(12, pathY + rng:NextNumber(-6, 8))
	part({ Shape = CYL, Size = V3(h, 1.6, 1.6), CFrame = base * CF(0, h / 2, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
	local center = base * CF(0, h + 7, 0)
	local c1, c2 = pick(rng, CANDY), pick(rng, CANDY)
	part({ Shape = CYL, Size = V3(1.6, 15, 15), CFrame = center * CFrame.Angles(0, PI / 2, 0), Color = c1 })
	for i = 0, 5 do
		local a = i / 6 * 2 * PI
		rotor(part({ Size = V3(1.7, 1.6, 7.4), CFrame = center * CFrame.Angles(0, 0, a) * CF(0, 3.6, 0) * CFrame.Angles(0, PI / 2, 0) * CFrame.Angles(0.35, 0, 0), Color = (i % 2 == 0) and c2 or Color3.new(1, 1, 1) }), center, "z", 0.8)
	end
	rotor(part({ Shape = BALL, Size = V3(2.2, 2.2, 2.2), CFrame = center, Color = Color3.new(1, 1, 1) }), center, "z", 0.8)
end

-- Карамельная трость
local function candyCane(base, rng, pathY)
	local h = math.max(12, pathY + rng:NextNumber(-4, 10))
	local seg = 3
	for i = 0, math.floor(h / seg) - 1 do
		part({ Shape = CYL, Size = V3(seg, 3, 3), CFrame = base * CF(0, i * seg + seg / 2, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(230, 30, 50) or Color3.new(1, 1, 1) })
	end
	local hookC = base * CF(3, h, 0)
	local prev
	for i = 0, 8 do
		local a = PI - i / 8 * PI
		local pt = (hookC * CF(math.cos(a) * 3, math.sin(a) * 3, 0)).Position
		if prev then
			part({ Size = V3(3, 3, (pt - prev).Magnitude + 0.6), CFrame = CFrame.lookAt((pt + prev) / 2, pt), Color = (i % 2 == 0) and RGB(230, 30, 50) or Color3.new(1, 1, 1) })
		end
		prev = pt
	end
end

-- Кекс с кремом и вишенкой
local function cupcake(base, rng, pathY)
	local h = math.max(8, pathY - 4)
	local d = 16
	local cup = pick(rng, CANDY)
	part({ Shape = CYL, Size = V3(h, d, d), CFrame = base * CF(0, h / 2, 0) * ROT_UP, Color = cup })
	for i = 0, 11 do
		local a = i / 12 * 2 * PI
		part({ Size = V3(0.8, h, 1), CFrame = base * CFrame.Angles(0, a, 0) * CF(0, h / 2, -d / 2), Color = cup:Lerp(Color3.new(1, 1, 1), 0.4) })
	end
	local cream = pick(rng, CANDY)
	for i = 0, 3 do
		local dd = (d + 2) * (1 - i * 0.22)
		part({ Shape = CYL, Size = V3(3, dd, dd), CFrame = base * CF(0, h + 1.5 + i * 2.6, 0) * ROT_UP, Color = (i % 2 == 0) and cream or Color3.new(1, 1, 1) })
	end
	part({ Shape = BALL, Size = V3(4, 4, 4), CFrame = base * CF(0, h + 13, 0), Color = RGB(220, 20, 40) })
	for i = 1, 14 do
		local a = rng:NextNumber(0, 2 * PI)
		local rr = rng:NextNumber(2, d / 2)
		part({ Size = V3(1, 0.4, 0.4), CFrame = base * CF(math.cos(a) * rr, h + 3.1, math.sin(a) * rr) * CFrame.Angles(0, a, 0), Color = pick(rng, PARTY), CanCollide = false })
	end
end

-- Мармеладки (полупрозрачные конусы)
local function gumdrops(base, rng, pathY)
	for i = 1, 3 do
		local b = base * CF(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8))
		local col = pick(rng, CANDY)
		local h = math.max(6, pathY - 10) * rng:NextNumber(0.4, 0.8)
		for k = 0, 4 do
			local d = 10 * (1 - k / 5)
			part({ Shape = CYL, Size = V3(h / 5, d, d), CFrame = b * CF(0, k * h / 5 + h / 10, 0) * ROT_UP, Color = col, Material = M.Glass, Transparency = 0.15 })
		end
	end
end

-- Подземный водопад
local function waterfall(base, rng, pathY)
	local h = pathY + rng:NextNumber(10, 25)
	local rock = pick(rng, ROCKS)
	part({ Size = V3(16, h, 10), CFrame = base * CF(0, h / 2, 6), Color = darker(rock, 0.7), Material = M.Slate })
	local fall = part({ Size = V3(8, h, 1), CFrame = base * CF(0, h / 2, 0.6), Color = RGB(110, 200, 255), Material = M.Neon, Transparency = 0.35, CanCollide = false })
	part({ Shape = CYL, Size = V3(1, 18, 18), CFrame = base * CF(0, 1.5, -6) * ROT_UP, Color = RGB(70, 170, 255), Material = M.Glass, Transparency = 0.2, CanCollide = false })
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1), RGB(150, 210, 255))
	mist.Transparency = NumberSequence.new(0.3, 1)
	mist.Size = NumberSequence.new(2, 5)
	mist.Speed = NumberRange.new(2, 4)
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Rate = 20
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Parent = part({ Size = V3(8, 1, 1), CFrame = base * CF(0, 2, -1), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local pl = Instance.new("PointLight")
	pl.Color = RGB(110, 200, 255)
	pl.Range = 30
	pl.Brightness = 1.5
	pl.Parent = fall
	for i = 1, 3 do
		part({ Size = V3(1.2, rng:NextNumber(4, 8), 1.2), CFrame = base * CF(rng:NextNumber(-7, 7), h + 1, rng:NextNumber(2, 10)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), Color = RGB(200, 100, 255), Material = M.Neon })
	end
end

-- Гигантский светящийся гриб
local function giantMushroom(base, rng, pathY)
	local h = math.max(10, pathY + rng:NextNumber(-8, 6))
	local cap = pick(rng, { RGB(80, 220, 255), RGB(200, 90, 255), RGB(90, 255, 160), RGB(255, 110, 200) })
	part({ Shape = CYL, Size = V3(h, 4, 4), CFrame = base * CF(0, h / 2, 0) * ROT_UP, Color = RGB(240, 230, 215) })
	part({ Shape = CYL, Size = V3(2.5, 18, 18), CFrame = base * CF(0, h + 1, 0) * ROT_UP, Color = cap })
	part({ Shape = CYL, Size = V3(2.5, 12, 12), CFrame = base * CF(0, h + 3, 0) * ROT_UP, Color = cap })
	part({ Shape = CYL, Size = V3(2, 6, 6), CFrame = base * CF(0, h + 5, 0) * ROT_UP, Color = cap })
	local glow = part({ Shape = CYL, Size = V3(0.4, 17, 17), CFrame = base * CF(0, h - 0.4, 0) * ROT_UP, Color = cap, Material = M.Neon })
	for i = 0, 6 do
		local a = i / 7 * 2 * PI
		part({ Shape = BALL, Size = V3(2, 2, 2), CFrame = base * CF(math.cos(a) * 6.5, h + 2.4, math.sin(a) * 6.5), Color = Color3.new(1, 1, 1) })
	end
	local pl = Instance.new("PointLight")
	pl.Color = cap
	pl.Range = 30
	pl.Brightness = 2
	pl.Parent = glow
end

-- Россыпь кристаллов
local function crystals(base, rng, pathY)
	local cols = { RGB(90, 230, 255), RGB(220, 100, 255), RGB(255, 120, 200), RGB(120, 255, 170), RGB(255, 230, 120) }
	local main = pick(rng, cols)
	local scale = math.max(1, (pathY + 10) / 25)
	for i = 1, 7 do
		local h = rng:NextNumber(6, 18) * scale
		part({
			Size = V3(2.6 * scale, h, 2.6 * scale),
			CFrame = base * CF(rng:NextNumber(-5, 5), h / 2 - 1, rng:NextNumber(-5, 5)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, PI), rng:NextNumber(-0.5, 0.5)),
			Color = (i % 3 == 0) and pick(rng, cols) or main,
			Material = M.Neon,
			Transparency = 0.1,
		})
	end
	local l = Instance.new("PointLight")
	l.Color = main
	l.Range = 35
	l.Brightness = 2
	l.Parent = part({ Size = V3(1, 1, 1), CFrame = base * CF(0, 8, 0), Transparency = 1, CanCollide = false })
end

-- Маленький извергающийся вулкан
local function miniVolcano(base, rng, pathY)
	local h = math.max(14, pathY - 4)
	local layers = 6
	for i = 0, layers - 1 do
		local d = 30 * (1 - i / (layers + 1))
		part({ Shape = CYL, Size = V3(h / layers, d, d), CFrame = base * CF(0, (i + 0.5) * h / layers, 0) * ROT_UP, Color = darker(RGB(90, 70, 62), 1 - i * 0.05), Material = M.Basalt })
	end
	local crater = part({ Shape = CYL, Size = V3(0.6, 10, 10), CFrame = base * CF(0, h + 0.2, 0) * ROT_UP, Color = RGB(255, 110, 0), Material = M.Neon })
	for i = 0, 3 do
		local a = i / 4 * 2 * PI + 0.3
		part({ Size = V3(2, h, 1), CFrame = base * CFrame.Angles(0, a, 0) * CF(0, h / 2, -10) * CFrame.Angles(-0.32, 0, 0), Color = RGB(255, 100, 0), Material = M.Neon, CanCollide = false })
	end
	local em = Instance.new("ParticleEmitter")
	em.Name = "Eruption"
	em.Color = ColorSequence.new(RGB(255, 230, 80), RGB(255, 50, 0))
	em.LightEmission = 1
	em.Size = NumberSequence.new(2.5, 0.5)
	em.Speed = NumberRange.new(40, 60)
	em.SpreadAngle = Vector2.new(20, 20)
	em.Acceleration = V3(0, -45, 0)
	em.Lifetime = NumberRange.new(2, 3)
	em.Rate = 15
	em.EmissionDirection = Enum.NormalId.Right
	em.Parent = crater
	tag(crater, "Eruptor")
	local sm = Instance.new("Smoke")
	sm.Size = 20
	sm.Opacity = 0.2
	sm.RiseVelocity = 12
	sm.Color = RGB(60, 55, 55)
	sm.Parent = crater
	local f = Instance.new("Fire")
	f.Size = 12
	f.Parent = crater
end

-- Парящий камень с лавопадом
local function lavaRock(base, rng, pathY)
	local y = pathY + rng:NextNumber(8, 20)
	local rk = part({ Size = V3(12, 6, 10), CFrame = base * CF(0, y, 0) * CFrame.Angles(0, rng:NextNumber(0, PI), 0.1), Color = RGB(70, 58, 55), Material = M.Basalt })
	part({ Size = V3(8, 4, 7), CFrame = base * CF(0, y - 4, 0), Color = RGB(60, 50, 48), Material = M.Basalt })
	part({ Size = V3(2.5, y - 2, 1), CFrame = base * CF(2, (y - 2) / 2, -3), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 120, 30)
	l.Range = 20
	l.Parent = rk
end

-- Парящий остров с деревом
local function skyIsland(base, rng, pathY)
	local y = pathY + rng:NextNumber(-10, 18)
	local d = rng:NextNumber(16, 24)
	part({ Shape = CYL, Size = V3(2, d, d), CFrame = base * CF(0, y, 0) * ROT_UP, Color = RGB(110, 215, 90), Material = M.Grass })
	for i = 1, 4 do
		local dd = d * (1 - i * 0.22)
		part({ Shape = CYL, Size = V3(2.4, dd, dd), CFrame = base * CF(0, y - 1 - i * 2.2, 0) * ROT_UP, Color = darker(RGB(160, 115, 75), 1 - i * 0.06), Material = M.Ground })
	end
	part({ Size = V3(1.6, 9, 1.6), CFrame = base * CF(0, y + 5, 0), Color = RGB(110, 75, 45), Material = M.Wood })
	local leaf = pick(rng, { RGB(255, 160, 210), RGB(120, 220, 110), RGB(255, 210, 90) })
	for i = 1, 4 do
		local s = rng:NextNumber(5, 8)
		part({ Shape = BALL, Size = V3(s, s, s), CFrame = base * CF(rng:NextNumber(-2.5, 2.5), y + 10 + rng:NextNumber(-1, 2), rng:NextNumber(-2.5, 2.5)), Color = leaf, Material = M.Grass })
	end
	part({ Size = V3(0.4, y - 1, 0.4), CFrame = base * CF(d / 2 - 1, (y - 1) / 2, 0), Color = RGB(150, 210, 255), Material = M.Neon, Transparency = 0.5, CanCollide = false })
end

-- Небесная башенка
local function skyTower(base, rng, pathY)
	local y = pathY + rng:NextNumber(-6, 10)
	part({ Shape = CYL, Size = V3(3, 14, 14), CFrame = base * CF(0, y, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
	local h = 16
	part({ Shape = CYL, Size = V3(h, 7, 7), CFrame = base * CF(0, y + h / 2 + 1.5, 0) * ROT_UP, Color = RGB(255, 235, 170) })
	local roof = pick(rng, { RGB(90, 120, 255), RGB(255, 90, 150), RGB(170, 100, 255) })
	for i = 0, 4 do
		local d = 9 * (1 - i / 5)
		part({ Shape = CYL, Size = V3(1.6, d, d), CFrame = base * CF(0, y + h + 2.3 + i * 1.6, 0) * ROT_UP, Color = roof })
	end
	local flag = part({ Size = V3(0.1, 1.4, 2.4), CFrame = base * CF(0, y + h + 12, 1.2), Color = pick(rng, PARTY), CanCollide = false })
	flag:SetAttribute("Wave", true)
	part({ Size = V3(0.2, 3.5, 0.2), CFrame = base * CF(0, y + h + 11, 0), Color = RGB(80, 80, 90) })
end

-- Декор вокруг трассы. big = true — крупная достопримечательность (колесо, замок и т.п.)
local LANDMARKS = {
	{ ferrisWheel, circusTent, carousel, coaster },
	{ lollipop, candyCane, cupcake, gumdrops },
	{ waterfall, giantMushroom, crystals, crystals },
	{ miniVolcano, lavaRock, lavaRock, miniVolcano },
	{ skyIsland, skyTower, skyIsland, skyTower },
}
local BIG = { [ferrisWheel] = 46, [circusTent] = 34, [carousel] = 30, [coaster] = 44, [miniVolcano] = 40, [waterfall] = 30, [cupcake] = 26 }

local function decor(zone, pos, rng, pathY)
	if (zone == 1 or zone == 2 or zone == 5) and rng:NextNumber() < 0.3 then
		festive(pos, rng, pathY)
		return
	end
	local list = LANDMARKS[zone]
	local fn = list[rng:NextInteger(1, #list)]
	local base = CF(pos.X, 0, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
	fn(base, rng, pathY)
end

local function buildVolcano(center)
	local folder = currentFolder
	local layers = 8
	local layerH = 32
	for i = 0, layers - 1 do
		local r = 260 - i * 28
		part({ Shape = CYL, Size = V3(layerH, r * 2, r * 2), CFrame = CF(center + V3(0, i * layerH + layerH / 2 - 4, 0)) * ROT_UP, Color = darker(RGB(70, 55, 50), 1 - i * 0.04), Material = M.Basalt }, folder)
		for k = 0, 4 do
			local a = k * (2 * PI / 5) + i * 0.15
			local dir = V3(math.cos(a), 0, math.sin(a))
			local pos = center + dir * (r + 0.2) + V3(0, i * layerH + layerH / 2 - 4, 0)
			part({ Size = V3(10, layerH, 1), CFrame = CFrame.lookAt(pos, pos + dir), Color = LAVA_COLOR, Material = M.Neon, CanCollide = false, CastShadow = false }, folder)
		end
	end
	local topY = layers * layerH - 4
	local crater = part({ Shape = CYL, Size = V3(2, 90, 90), CFrame = CF(center + V3(0, topY + 1, 0)) * ROT_UP, Color = LAVA_COLOR, Material = M.Neon }, folder)
	crater.Name = "VolcanoCrater"
	local erupt = Instance.new("ParticleEmitter")
	erupt.Name = "Eruption"
	erupt.Color = ColorSequence.new(RGB(255, 230, 80), RGB(255, 50, 0))
	erupt.LightEmission = 1
	erupt.Size = NumberSequence.new(8, 2)
	erupt.Speed = NumberRange.new(80, 130)
	erupt.SpreadAngle = Vector2.new(25, 25)
	erupt.Acceleration = V3(0, -60, 0)
	erupt.Lifetime = NumberRange.new(3, 5)
	erupt.Rate = 10
	erupt.EmissionDirection = Enum.NormalId.Right
	erupt.Parent = crater
	tag(crater, "Eruptor")
	local fire = Instance.new("Fire")
	fire.Size = 30
	fire.Heat = 25
	fire.Parent = crater
	local smoke = Instance.new("Smoke")
	smoke.Size = 50
	smoke.RiseVelocity = 20
	smoke.Opacity = 0.3
	smoke.Color = RGB(70, 60, 60)
	smoke.Parent = crater
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 3
	light.Color = RGB(255, 120, 40)
	light.Parent = crater
end

local function buildLavaSea(minX, maxX, minZ, maxZ)
	local tile = 1000
	for x = minX, maxX, tile do
		for z = minZ, maxZ, tile do
			local p = part({
				Name = "LavaSea",
				Size = V3(tile, 6, tile),
				CFrame = CF(x + tile / 2, -3, z + tile / 2),
				Color = RGB(255, 90, 10),
				Material = M.CrackedLava,
			})
			tag(p, "Lava")
		end
	end
end

local function buildEmbers(rng)
	local points = info.pathPoints
	for i = 1, 60 do
		local p = points[rng:NextInteger(1, #points)]
		local holder = part({ Size = V3(20, 1, 20), CFrame = CF(p.X + rng:NextNumber(-25, 25), 0.5, p.Z + rng:NextNumber(-25, 25)), Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(RGB(255, 210, 90), RGB(255, 60, 0))
		em.LightEmission = 1
		em.Size = NumberSequence.new(0.5, 0)
		em.Speed = NumberRange.new(4, 9)
		em.Lifetime = NumberRange.new(2, 4)
		em.Rate = 5
		em.Acceleration = V3(0, 3, 0)
		em.SpreadAngle = Vector2.new(30, 30)
		em.EmissionDirection = Enum.NormalId.Top
		em.Parent = holder
	end
end

local function setupLighting()
	-- яркий солнечный день: сочные цвета, видно далеко
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.Ambient = RGB(130, 120, 140)
	Lighting.OutdoorAmbient = RGB(170, 160, 180)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.22
	atmo.Offset = 0
	atmo.Color = RGB(200, 225, 255)
	atmo.Decay = RGB(255, 200, 170)
	atmo.Glare = 0.2
	atmo.Haze = 0.4
	atmo.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.3
	cc.Contrast = 0.08
	cc.Brightness = 0.03
	cc.TintColor = RGB(255, 252, 245)
	cc.Parent = Lighting
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- ============ ГЛАВНАЯ ФУНКЦИЯ ============
function MapBuilder.Build()
	info = {
		checkpoints = {},
		spawnCF = {},
		movers = {},
		spinners = {},
		killers = {},
		stalactites = {},
		waves = {},
		blinkers = {},
		pendulums = {},
		geysers = {},
		pathPoints = {},
		leaderboardRows = {},
		timeRows = {},
	}
	coinCounter = 0

	-- убираем стандартную плиту и спавн из шаблона Baseplate
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Baseplate" or (child:IsA("SpawnLocation") and child.Name ~= "LavaSpawn") then
			child:Destroy()
		end
	end
	local old = workspace:FindFirstChild("LavaMap")
	if old then
		old:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "LavaMap"
	map.Parent = workspace

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = map
	currentFolder = lobby

	local ctx = {
		F = CFrame.new(),
		x = 0,
		y = 12,
		z = 32,
		zone = 1,
		diff = 0,
		stage = 1,
		rng = Random.new(Config.MAP_SEED),
		sky = false,
		flat = false,
	}
	buildLobby(ctx)

	local stageFrames = {}
	local prevPlan = {}
	local pattern = { -1, -1, 1, 1 } -- направо, направо, налево, налево — «змейка»

	for s = 1, TOTAL do
		local folder = Instance.new("Folder")
		folder.Name = string.format("Stage_%02d", s)
		folder.Parent = map
		currentFolder = folder

		ctx.stage = s
		ctx.zone = Config.ZoneOfStage(s)
		ctx.diff = ((s - 1) / (TOTAL - 1)) ^ 1.6 -- плавный рост: начало лёгкое
		ctx.sky = ctx.zone == 5
		ctx.flat = ctx.zone == 4
		ctx.rng = Random.new(Config.MAP_SEED + s * 7919)
		local r = ctx.rng
		local stageFrame = ctx.F
		local stageStartY = ctx.y

		local lowered = 0
		if ctx.zone == 4 then
			ctx.y -= 3
			lowered = 3
		end

		local plan = {}
		if s == (4 * PER_ZONE + 1) then
			plan = { "bounce", "bounce", "jumps" } -- взлёт в небо
		else
			local pool = POOLS[ctx.zone]
			local count = 2 + ((ctx.diff > 0.35) and 1 or 0)
			local used = {}
			for _ = 1, count do
				local name
				for _ = 1, 20 do
					name = pool[r:NextInteger(1, #pool)]
					local tooHigh = CLIMBING[name] and ctx.y > 60 * ctx.zone
					-- без повторов внутри этапа и с прошлым этапом — так карта разнообразнее
					if not used[name] and not prevPlan[name] and not tooHigh then
						break
					end
				end
				table.insert(plan, name)
				used[name] = true
			end
		end

		prevPlan = {}
		for _, name in ipairs(plan) do
			prevPlan[name] = true
		end
		for i, name in ipairs(plan) do
			Obstacles[name](ctx)
			if ctx.zone == 4 and i < #plan then
				island(ctx)
			end
		end

		-- следующий чекпоинт
		local nextStage = s + 1
		local isFinish = nextStage == TOTAL + 1
		local padSize = isFinish and 30 or 14
		local padTop = ctx.y + lowered
		local padZc = ctx.z + 4.5 + padSize / 2
		local padX = ctx.x
		checkpointPad(ctx, nextStage, padX, padTop, padZc, padSize, isFinish)

		-- 🍫 шоколадная река под фабрикой сладостей (смертельная, как лава)
		if ctx.zone == 2 then
			local river = part({
				Name = "ChocolateRiver",
				Size = V3(150, 2, padZc + 70),
				CFrame = L(ctx, 0, 0.4 + s * 0.003, padZc / 2),
				Color = RGB(105, 55, 25),
				Material = M.SmoothPlastic,
				Reflectance = 0.12,
			})
			tag(river, "Lava")
			for i = 1, 4 do
				local bub = part({ Size = V3(40, 0.5, 40), CFrame = L(ctx, ctx.rng:NextNumber(-50, 50), 1.6, ctx.rng:NextNumber(0, padZc)), Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
				local em = Instance.new("ParticleEmitter")
				em.Color = ColorSequence.new(RGB(150, 90, 50), RGB(90, 45, 20))
				em.Size = NumberSequence.new(1.2, 0)
				em.Speed = NumberRange.new(1, 3)
				em.Lifetime = NumberRange.new(1, 2)
				em.Rate = 6
				em.EmissionDirection = Enum.NormalId.Top
				em.Parent = bub
			end
		end

		-- волна лавы в зоне 4
		if ctx.zone == 4 then
			local lowY = ctx.y
			local z0, z1 = 5, padZc - padSize / 2 + 2
			local restTop = lowY - 14
			local low = L(ctx, 0, restTop - 5, (z0 + z1) / 2)
			local wave = part({ Name = "LavaWave", Size = V3(70, 10, z1 - z0), CFrame = low, Color = RGB(255, 100, 0), Material = M.Neon, Transparency = 0.05 })
			tag(wave, "Lava")
			table.insert(info.waves, { part = wave, low = low, high = low + V3(0, (lowY + 1.5) - restTop, 0) })
		end

		table.insert(stageFrames, { F = stageFrame, len = padZc, y = stageStartY, zone = ctx.zone })

		local turn = 0
		if not isFinish and nextStage % 5 == 1 then
			local k = (nextStage - 1) / 5
			turn = pattern[((k - 1) % 4) + 1] * PI / 2
		end
		ctx.F = ctx.F * CF(padX, 0, -padZc) * CFrame.Angles(0, turn, 0)
		ctx.x, ctx.y, ctx.z = 0, padTop, padSize / 2
		info.spawnCF[nextStage] = ctx.F * CF(0, padTop + 3.5, 0)

		if isFinish then
			buildFinish(ctx)
		else
			if nextStage % PER_ZONE == 1 then
				zoneGate(ctx, Config.ZoneOfStage(nextStage))
			end
			if Specials[nextStage] then
				local saveZone = ctx.zone
				ctx.zone = Config.ZoneOfStage(nextStage)
				ctx.sky = ctx.zone == 5
				Specials[nextStage](ctx)
				ctx.zone = saveZone
			end
		end
	end

	-- декор по сторонам трассы
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Decor"
	decoFolder.Parent = map
	currentFolder = decoFolder
	local drng = Random.new(Config.MAP_SEED + 99)
	local decorSpots = {}
	for _, sf in ipairs(stageFrames) do
		for _ = 1, 9 do
			local isFestive = (sf.zone == 1 or sf.zone == 2 or sf.zone == 5) and drng:NextNumber() < 0.3
			local list = LANDMARKS[sf.zone]
			local fn = (not isFestive) and list[drng:NextInteger(1, #list)] or nil
			local need = fn and (BIG[fn] or 22) or 22
			local z = drng:NextNumber(0, sf.len)
			local side = drng:NextNumber() < 0.5 and -1 or 1
			local x = side * drng:NextNumber(need + 8, need + 36)
			local pos = (sf.F * CF(x, 0, -z)).Position
			local free = farFromPath(pos, need + 4)
			if free then
				for _, dp in ipairs(decorSpots) do
					local dx, dz = dp.pos.X - pos.X, dp.pos.Z - pos.Z
					if dx * dx + dz * dz < (dp.r + need) ^ 2 then
						free = false
						break
					end
				end
			end
			if free then
				table.insert(decorSpots, { pos = pos, r = need })
				if fn then
					fn(CF(pos.X, 0, pos.Z) * CFrame.Angles(0, drng:NextNumber(0, 2 * PI), 0), drng, sf.y)
				else
					festive(pos, drng, sf.y)
				end
			end
		end
	end

	-- границы карты
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(info.pathPoints) do
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = map
	currentFolder = world
	buildVolcano(V3(minX - 400, 0, (minZ + maxZ) / 2))
	buildLavaSea(minX - 800, maxX + 400, minZ - 400, maxZ + 400)
	buildEmbers(drng)
	setupLighting()

	info.totalStages = TOTAL
	info.finishStage = TOTAL + 1
	return info
end

return MapBuilder
