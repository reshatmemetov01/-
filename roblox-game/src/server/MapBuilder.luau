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
-- камни подземного мира: тёплый песчаник и серый камень (как древние плиты)
local ROCKS = { RGB(150, 120, 95), RGB(130, 110, 100), RGB(165, 135, 105), RGB(115, 105, 110), RGB(140, 125, 115) }
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

-- Новые материалы Roblox (если в старой версии их нет — берём запасной)
local function matOr(name, fallback)
	local ok, v = pcall(function()
		return Enum.Material[name]
	end)
	return ok and v or fallback
end
local MAT_PLASTER = matOr("Plaster", Enum.Material.SmoothPlastic)
local MAT_ROOF = matOr("RoofShingles", Enum.Material.Slate)
local MAT_PAVE = matOr("Pavement", Enum.Material.Cobblestone)

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

-- 📦 спрятанный сундук-сокровище (всего 5 на всю игру)
local function treasureChest(cf, n)
	local m = makeChest(cf, "treasure" .. n, "Treasure")
	local pl = Instance.new("PointLight")
	pl.Color = RGB(255, 215, 90)
	pl.Range = 14
	pl.Brightness = 2
	pl.Parent = m.PrimaryPart
	return m
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
	elseif zone == 4 then -- 🌋 скалистый островок: трава сверху, скала снизу, лава стекает
		if r:NextNumber() < 0.65 then
			walk = part({ Size = V3(w, 1, d), CFrame = L(ctx, x, top - 0.5, z), Color = RGB(100, 175, 70) })
			part({ Size = V3(w - 0.4, 2.4, d - 0.4), CFrame = L(ctx, x, top - 2.2, z), Color = RGB(120, 100, 85), Material = M.Slate })
			part({ Size = V3(w * 0.7, 3, d * 0.7), CFrame = L(ctx, x, top - 4.6, z) * CFrame.Angles(0, 0.3, 0), Color = RGB(95, 80, 72), Material = M.Slate })
			if r:NextNumber() < 0.5 then -- красный гриб
				part({ Size = V3(0.5, 1.4, 0.5), CFrame = L(ctx, x + w / 2 - 0.8, top + 0.7, z - d / 2 + 0.8), Color = RGB(245, 235, 220), CanCollide = false })
				part({ Shape = CYL, Size = V3(0.6, 1.8, 1.8), CFrame = L(ctx, x + w / 2 - 0.8, top + 1.5, z - d / 2 + 0.8) * ROT_UP, Color = RGB(220, 40, 40), CanCollide = false })
			end
			if r:NextNumber() < 0.4 then -- лава стекает по краю
				part({ Size = V3(1.2, 6, 0.3), CFrame = L(ctx, x + r:NextNumber(-w / 3, w / 3), top - 4, z - d / 2 - 0.1), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
			end
			column(ctx, x, z, LAVA_BOTTOM, top - 6, w * 0.4, d * 0.4, RGB(80, 66, 60), M.Basalt)
		else
			local dia = math.min(w, d) + 0.5
			walk = part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, z) * ROT_UP, Color = RGB(70, 58, 55), Material = M.Basalt })
			part({ Shape = CYL, Size = V3(0.4, dia + 0.6, dia + 0.6), CFrame = L(ctx, x, top - 1.4, z) * ROT_UP, Color = RGB(255, 100, 20), Material = M.Neon })
			column(ctx, x, z, LAVA_BOTTOM, top - 1.6, dia - 0.6, dia - 0.6, RGB(55, 46, 44), M.Basalt, true)
		end
	elseif r:NextNumber() < 0.5 then -- ☁️ пастельный островок (розовая глазурь / зелёная / оранжевая трава)
		local topCol = pick(r, { RGB(255, 170, 215), RGB(120, 230, 110), RGB(255, 185, 80), RGB(150, 230, 210) })
		walk = part({ Size = V3(w, 1.2, d), CFrame = L(ctx, x, top - 0.6, z), Color = topCol })
		for i = 0, 5 do -- «потёки» глазури по краю
			local a = i / 6 * 2 * PI
			part({ Shape = BALL, Size = V3(1.6, 1.6, 1.6), CFrame = L(ctx, x + math.cos(a) * (w / 2 - 0.4), top - 1.2, z + math.sin(a) * (d / 2 - 0.4)), Color = topCol, CanCollide = false })
		end
		part({ Size = V3(w - 0.6, 2.4, d - 0.6), CFrame = L(ctx, x, top - 2.4, z), Color = RGB(160, 110, 80) })
		part({ Size = V3(w * 0.6, 2.4, d * 0.6), CFrame = L(ctx, x, top - 4.6, z) * CFrame.Angles(0, 0.4, 0), Color = RGB(135, 95, 70) })
		if r:NextNumber() < 0.5 then -- голубой кристаллик
			part({ Size = V3(0.8, 2.2, 0.8), CFrame = L(ctx, x - w / 2 + 0.8, top + 1, z + d / 2 - 0.8) * CFrame.Angles(0.2, 0, 0.2), Color = RGB(110, 170, 255), Material = M.Glass, CanCollide = false })
		end
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
	elseif zone == 4 then -- деревянный мост на верёвках
		p = part({ Size = V3(w, 0.8, len), CFrame = L(ctx, x, top - 0.4, zc), Color = RGB(150, 105, 65), Material = M.WoodPlanks })
		for i = 0, math.floor(len / 2.5) do
			part({ Size = V3(w + 0.6, 0.2, 0.4), CFrame = L(ctx, x, top + 0.02, zc - len / 2 + i * 2.5), Color = RGB(115, 78, 48), Material = M.Wood, CanCollide = false })
		end
		for sx = -1, 1, 2 do
			for i = 0, math.floor(len / 6) do
				part({ Size = V3(0.5, 3, 0.5), CFrame = L(ctx, x + sx * (w / 2 + 0.3), top + 1.2, zc - len / 2 + i * 6), Color = RGB(110, 75, 45), Material = M.Wood, CanCollide = false })
			end
			part({ Size = V3(0.25, 0.25, len), CFrame = L(ctx, x + sx * (w / 2 + 0.3), top + 2.4, zc), Color = RGB(200, 170, 120), Material = M.Fabric, CanCollide = false })
		end
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
		local strOff = CF(0, 12, 0)
		local str = part({ Size = V3(0.15, 23, 0.15), CFrame = base * strOff, Color = Color3.new(1, 1, 1), CanCollide = false })
		local balOff = CF(0, 26, 0)
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

-- ============ 🍬 КОНФЕТНЫЕ ПРЕПЯТСТВИЯ (мир 2) ============
local MACARON = { RGB(255, 150, 200), RGB(170, 230, 210), RGB(200, 160, 255), RGB(255, 220, 140), RGB(140, 200, 255) }

-- макарун-платформа: две «крышечки» и крем
local function macaronPad(ctx, x, top, z, dia, col)
	local walk = part({ Shape = CYL, Size = V3(1.3, dia, dia), CFrame = L(ctx, x, top - 0.65, z) * ROT_UP, Color = col })
	part({ Shape = CYL, Size = V3(0.3, dia + 0.25, dia + 0.25), CFrame = L(ctx, x, top - 1.35, z) * ROT_UP, Color = col:Lerp(Color3.new(1, 1, 1), 0.25), CanCollide = false })
	part({ Shape = CYL, Size = V3(0.7, dia - 0.5, dia - 0.5), CFrame = L(ctx, x, top - 1.75, z) * ROT_UP, Color = RGB(255, 248, 235) })
	part({ Shape = CYL, Size = V3(1.3, dia, dia), CFrame = L(ctx, x, top - 2.75, z) * ROT_UP, Color = col })
	stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 3.4, 1.4, col, Color3.new(1, 1, 1), 1.5)
	addPath(L(ctx, x, top, z).Position)
	return walk
end

-- лесенка из макарунов зигзагом вверх
function Obstacles.macarons(ctx)
	local r = ctx.rng
	local n = r:NextInteger(4, 6)
	local side = r:NextNumber() < 0.5 and -1 or 1
	for i = 1, n do
		local dia = r:NextNumber(7.5 - 1.5 * ctx.diff, 8.5 - 1.5 * ctx.diff)
		local rise = r:NextNumber(0.4, 1.8)
		local gap = r:NextNumber(2.5, 3 + 1.5 * ctx.diff)
		local x = side * r:NextNumber(2, 3.5)
		side = -side
		local top = ctx.y + rise
		local zc = ctx.z + gap + dia / 2
		macaronPad(ctx, x, top, zc, dia, MACARON[((i - 1) % #MACARON) + 1])
		maybeCoin(ctx, x, top, zc)
		ctx.x, ctx.y, ctx.z = x, top, zc + dia / 2
	end
end

-- круглый леденец-площадка
local function lollipopPad(ctx, x, top, z, dia)
	part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = Color3.new(1, 1, 1) })
	for k = 1, 3 do
		local d = dia * (1 - k * 0.25)
		part({ Shape = CYL, Size = V3(1.02 + k * 0.01, d, d), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = (k % 2 == 1) and RGB(255, 80, 150) or Color3.new(1, 1, 1), CanCollide = false })
	end
	stripedColumn(ctx, x, z, LAVA_BOTTOM, top - 1, 1.2, Color3.new(1, 1, 1), RGB(255, 80, 150), 1.5)
	addPath(L(ctx, x, top, z).Position)
end

-- бревно-балансир из полосатой карамельной трости между леденцами
function Obstacles.canes(ctx)
	local r = ctx.rng
	local segs = r:NextInteger(2, 3)
	local width = math.max(1.6, 2.6 - 0.9 * ctx.diff)
	local top = ctx.y
	local jx, jz = ctx.x, ctx.z + 3 + 2.5
	lollipopPad(ctx, jx, top, jz, 5)
	local side = r:NextNumber() < 0.5 and -1 or 1
	for _ = 1, segs do
		local nx = math.clamp(jx + side * r:NextNumber(5, 8), -12, 12)
		local nz = jz + r:NextNumber(11, 14)
		local a = L(ctx, jx, top - width / 2, jz).Position
		local b = L(ctx, nx, top - width / 2, nz).Position
		local len = (b - a).Magnitude
		local n = math.max(4, math.floor(len / 1.6))
		for k = 0, n - 1 do
			local p = a:Lerp(b, (k + 0.5) / n)
			part({ Shape = CYL, Size = V3(len / n + 0.02, width, width), CFrame = CFrame.lookAt(p, b) * CFrame.Angles(0, PI / 2, 0), Color = (k % 2 == 0) and RGB(230, 30, 50) or Color3.new(1, 1, 1) })
		end
		addPath((a + b) / 2)
		jx, jz = nx, nz
		lollipopPad(ctx, jx, top, jz, 5)
		maybeCoin(ctx, jx, top, jz, 0.5)
		side = -side
	end
	-- крючок трости над последним леденцом (декор)
	for i = 0, 7 do
		local a = i / 7 * PI
		part({ Shape = BALL, Size = V3(1.3, 1.3, 1.3), CFrame = L(ctx, jx + math.cos(a) * 2.2 + 2.2, top + 4 + math.sin(a) * 2.2, jz + 2.5), Color = (i % 2 == 0) and RGB(230, 30, 50) or Color3.new(1, 1, 1), CanCollide = false })
	end
	ctx.x, ctx.y, ctx.z = jx, top, jz + 2.5
end

-- лежащий пончик: приземляйся на кольцо, дырка посередине — в лаву
local function donutPad(ctx, x, top, zc, R, icing)
	local ringW = 3
	local rr = R - ringW / 2
	local segs = 16
	local center = L(ctx, x, top, zc).Position
	for i = 0, segs - 1 do
		local a0, a1 = i / segs * 2 * PI, (i + 1) / segs * 2 * PI
		local p0 = L(ctx, x + math.cos(a0) * rr, top - 0.8, zc + math.sin(a0) * rr).Position
		local p1 = L(ctx, x + math.cos(a1) * rr, top - 0.8, zc + math.sin(a1) * rr).Position
		local mid = (p0 + p1) / 2
		local chord = (p1 - p0).Magnitude + 0.4
		part({ Size = V3(ringW, 1.6, chord), CFrame = CFrame.lookAt(mid, p1), Color = RGB(215, 160, 95) })
		local ic = part({ Size = V3(ringW - 0.4, 0.3, chord - 0.1), CFrame = CFrame.lookAt(mid, p1) * CF(0, 0.9, 0), Color = icing, CanCollide = false })
		if i % 2 == 0 then
			part({ Size = V3(0.5, 0.15, 0.15), CFrame = ic.CFrame * CF(0.4, 0.2, 0) * CFrame.Angles(0, i, 0), Color = PARTY[(i % #PARTY) + 1], CanCollide = false })
		end
		if i % 4 == 0 then
			local base = L(ctx, x + math.cos(a0) * rr, top - 1.6, zc + math.sin(a0) * rr)
			part({ Shape = CYL, Size = V3(top - 1.6 - LAVA_BOTTOM, 1, 1), CFrame = base * CF(0, -(top - 1.6 - LAVA_BOTTOM) / 2, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
		end
	end
	addPath(center)
	addPath(L(ctx, x, top, zc - R).Position)
	addPath(L(ctx, x, top, zc + R).Position)
end

function Obstacles.donuts(ctx)
	local r = ctx.rng
	local n = r:NextInteger(3, 4)
	for _ = 1, n do
		local R = r:NextNumber(5.5, 6.5)
		local gap = r:NextNumber(2.5, 3.2 + 1.2 * ctx.diff)
		local x = math.clamp(ctx.x + r:NextNumber(-4, 4), -10, 10)
		local top = ctx.y + r:NextNumber(-0.5, 1.2)
		local zc = ctx.z + gap + R
		donutPad(ctx, x, top, zc, R, pick(r, CANDY))
		maybeCoin(ctx, x, top, zc - R + 1.5)
		ctx.x, ctx.y, ctx.z = x, top, zc + R
	end
end

-- ============ УНИКАЛЬНЫЕ ПРЕПЯТСТВИЯ КАЖДОГО МИРА ============

-- 🎢 МИР 1: бег по рельсам американских горок (шпалы, местами пропуски)
function Obstacles.coasterTrack(ctx)
	local r = ctx.rng
	local len = r:NextInteger(34, 44)
	local x = ctx.x
	local z0 = ctx.z + 3
	local base = ctx.y
	local step = 1.7
	local n = math.floor(len / step)
	local holeAt = {}
	for _ = 1, 2 + math.floor(ctx.diff * 2) do
		local h = r:NextInteger(4, n - 5)
		holeAt[h] = true
		holeAt[h + 1] = true
		if ctx.diff > 0.3 then
			holeAt[h + 2] = true
		end
	end
	local function yAt(t)
		return base + math.sin(t * PI) * 5 - math.sin(t * PI * 2) * 1.5
	end
	for i = 0, n - 1 do
		local t = i / (n - 1)
		local z = z0 + i * step
		local y = yAt(t)
		if not holeAt[i] then
			part({ Size = V3(5, 0.5, 1.1), CFrame = L(ctx, x, y - 0.25, z), Color = RGB(150, 100, 60), Material = M.WoodPlanks })
		end
		-- рельсы (узкие, по ним тоже можно бежать)
		local y2 = yAt(math.min(1, (i + 1) / (n - 1)))
		local a = L(ctx, x, y + 0.1, z).Position
		local b = L(ctx, x, y2 + 0.1, z + step).Position
		for sx = -1, 1, 2 do
			local off = ctx.F.RightVector * sx * 2.2
			part({ Size = V3(0.5, 0.5, (b - a).Magnitude + 0.1), CFrame = CFrame.lookAt((a + b) / 2 + off, b + off), Color = RGB(230, 40, 50), Material = M.Metal })
		end
		if i % 6 == 0 and not ctx.sky then
			column(ctx, x, z, LAVA_BOTTOM, y - 0.6, 1, 1, RGB(90, 90, 105), M.Metal)
		end
		if i % 3 == 0 then
			addPath(L(ctx, x, y, z).Position)
		end
		if i % 8 == 4 then
			maybeCoin(ctx, x, y, z, 0.6)
		end
	end
	local endZ = z0 + n * step
	local size = 8
	themedPlatform(ctx, x, base, endZ + 2 + size / 2, size, size)
	ctx.x, ctx.y, ctx.z = x, base, endZ + 2 + size
end

-- 🍫 МИР 2: шоколадный мост «угадай плитку» — в каждом ряду одна плитка ненастоящая
-- (подсказка: на настоящих плитках есть посыпка)
function Obstacles.chocoBridge(ctx)
	local r = ctx.rng
	local rows = r:NextInteger(4, 6)
	local x = ctx.x
	local top = ctx.y
	local z = ctx.z + 3
	for _ = 1, rows do
		local zc = z + 2.5
		local realSide = r:NextNumber() < 0.5 and -1 or 1
		for sx = -1, 1, 2 do
			local real = sx == realSide
			local tile = part({ Size = V3(5, 1, 5), CFrame = L(ctx, x + sx * 3.3, top - 0.5, zc), Color = RGB(110, 60, 30), CanCollide = real })
			for k = -1, 1, 2 do
				part({ Size = V3(0.15, 1.04, 5), CFrame = L(ctx, x + sx * 3.3 + k * 0.85, top - 0.5, zc), Color = RGB(80, 42, 20), CanCollide = false })
			end
			if real then
				for _ = 1, 5 do
					part({ Size = V3(0.5, 0.1, 0.15), CFrame = L(ctx, x + sx * 3.3 + r:NextNumber(-2, 2), top + 0.02, zc + r:NextNumber(-2, 2)) * CFrame.Angles(0, r:NextNumber(0, 3), 0), Color = pick(r, PARTY), CanCollide = false })
				end
			end
			tile.CanQuery = real
		end
		addPath(L(ctx, x, top, zc).Position)
		z = zc + 2.5 + 2.2
	end
	local size = 9
	themedPlatform(ctx, x, top, z + 1 + size / 2, size, size)
	maybeCoin(ctx, x, top, z + 1 + size / 2, 0.8)
	ctx.x, ctx.y, ctx.z = x, top, z + 1 + size
end

-- ⛏ МИР 3: вагонетки на рельсах — прыгай с вагонетки на вагонетку, некоторые катаются
function Obstacles.minecart(ctx)
	local r = ctx.rng
	local n = r:NextInteger(3, 5)
	local x = math.clamp(ctx.x, -4, 4)
	local top = ctx.y
	local z0 = ctx.z + 2
	local totalLen = n * 10 + 2
	-- рельсы под вагонетками (на них стоять нельзя — лава рядом)
	for sx = -1, 1, 2 do
		part({ Size = V3(0.4, 0.4, totalLen), CFrame = L(ctx, x + sx * 2, top - 3.6, z0 + totalLen / 2), Color = RGB(120, 120, 130), Material = M.Metal, CanCollide = false })
	end
	for i = 0, math.floor(totalLen / 3) do
		part({ Size = V3(6, 0.3, 0.8), CFrame = L(ctx, x, top - 3.9, z0 + i * 3), Color = RGB(90, 60, 40), Material = M.Wood, CanCollide = false })
	end
	if not ctx.sky then
		column(ctx, x, z0 + totalLen / 2, LAVA_BOTTOM, top - 4.1, 6, totalLen * 0.3, RGB(70, 62, 66), M.Slate)
	end
	local z = z0
	for i = 1, n do
		local zc = z + 2.5 + 3
		local base = L(ctx, x, top - 1.6, zc)
		local cart = part({ Size = V3(5, 3, 6), CFrame = base, Color = RGB(110, 75, 50), Material = M.WoodPlanks })
		local rim = part({ Size = V3(5.3, 0.5, 6.3), CFrame = base * CF(0, 1.3, 0), Color = RGB(80, 80, 90), Material = M.Metal, CanCollide = false })
		local ore = part({ Size = V3(4, 0.6, 5), CFrame = base * CF(0, 1.5, 0), Color = pick(r, { RGB(255, 200, 60), RGB(90, 220, 255), RGB(200, 90, 255) }), Material = M.Neon, CanCollide = false })
		local moving = ctx.diff > 0.2 and i % 2 == 0
		if moving then
			local amp, speed, phase = 2 + 2 * ctx.diff, 0.9 + 0.5 * ctx.diff, r:NextNumber(0, 2 * PI)
			for _, p in ipairs({ cart, rim, ore }) do
				table.insert(info.movers, { part = p, base = p.CFrame, axis = ctx.F.LookVector, amp = amp, speed = speed, phase = phase })
			end
		end
		maybeCoin(ctx, x, top, zc, 0.4)
		addPath(base.Position)
		z = zc + 3 + r:NextNumber(1.2, 2 + 1.5 * ctx.diff)
	end
	local size = 9
	themedPlatform(ctx, x, top, z + 2 + size / 2, size, size)
	ctx.x, ctx.y, ctx.z = x, top, z + 2 + size
end

-- 🌉 МИР 4: шаткий верёвочный мост с дырами (часть досок рассыпается)
function Obstacles.plankBridge(ctx)
	local r = ctx.rng
	local len = r:NextInteger(30, 40)
	local x = ctx.x
	local top = ctx.y
	local z0 = ctx.z + 2
	themedPlatform(ctx, x, top, z0 + 2, 4, 4)
	local step = 1.5
	local n = math.floor(len / step)
	local sag = 2.5
	local missing = {}
	for _ = 1, 2 + math.floor(ctx.diff * 2) do
		local m = r:NextInteger(3, n - 4)
		missing[m] = true
		missing[m + 1] = true
	end
	for i = 0, n - 1 do
		local t = i / (n - 1)
		local y = top - math.sin(t * PI) * sag
		local z = z0 + 4 + i * step
		if not missing[i] then
			local p = part({ Size = V3(5, 0.4, 1.2), CFrame = L(ctx, x, y - 0.2, z) * CFrame.Angles(r:NextNumber(-0.04, 0.04), 0, r:NextNumber(-0.05, 0.05)), Color = RGB(150, 105, 65), Material = M.WoodPlanks })
			if ctx.diff > 0.35 and r:NextNumber() < 0.15 then
				p.Color = RGB(120, 85, 55)
				tag(p, "Vanish")
			end
		end
		if i % 2 == 0 then
			for sx = -1, 1, 2 do
				part({ Size = V3(0.25, 0.25, step * 2 + 0.1), CFrame = L(ctx, x + sx * 2.8, y + 2.2, z + step / 2), Color = RGB(200, 170, 120), CanCollide = false })
				part({ Size = V3(0.15, 2.2, 0.15), CFrame = L(ctx, x + sx * 2.8, y + 1.1, z), Color = RGB(200, 170, 120), CanCollide = false })
			end
		end
		if i % 4 == 0 then
			addPath(L(ctx, x, y, z).Position)
		end
	end
	local endZ = z0 + 4 + n * step
	local size = 8
	themedPlatform(ctx, x, top, endZ + size / 2, size, size)
	maybeCoin(ctx, x, top, endZ + size / 2, 0.7)
	ctx.x, ctx.y, ctx.z = x, top, endZ + size
end

-- 🔥 МИР 4: лавопады поперёк дорожки — в каждой завесе только один проход
function Obstacles.lavaCurtains(ctx)
	local r = ctx.rng
	local count = r:NextInteger(4, 5)
	local w = 13
	local len = count * 7 + 6
	local x = 0
	local z0 = ctx.z + 3
	local zc = z0 + len / 2
	local top = ctx.y
	walkway(ctx, x, top, zc, w, len)
	for i = 1, count do
		local z = z0 + i * 7
		local gapW = 3.6 - 0.8 * ctx.diff
		local gx = r:NextNumber(-w / 2 + gapW / 2 + 0.5, w / 2 - gapW / 2 - 0.5)
		local leftW = (gx - gapW / 2) - (-w / 2)
		local rightW = (w / 2) - (gx + gapW / 2)
		local h = 14
		if leftW > 0.2 then
			killPart({ Size = V3(leftW, h, 0.6), CFrame = L(ctx, -w / 2 + leftW / 2, top + h / 2, z), Color = RGB(255, 110, 10), Material = M.Neon, Transparency = 0.15 })
		end
		if rightW > 0.2 then
			killPart({ Size = V3(rightW, h, 0.6), CFrame = L(ctx, w / 2 - rightW / 2, top + h / 2, z), Color = RGB(255, 110, 10), Material = M.Neon, Transparency = 0.15 })
		end
		-- каменный уступ, с которого течёт лава
		part({ Size = V3(w + 2, 2, 3), CFrame = L(ctx, 0, top + h + 1, z), Color = RGB(90, 75, 70), Material = M.Basalt })
		part({ Size = V3(gapW, 0.3, 0.8), CFrame = L(ctx, gx, top + 0.2, z), Color = RGB(255, 230, 120), Material = M.Neon, CanCollide = false })
		addPath(L(ctx, gx, top, z).Position)
	end
	for sx = -1, 1, 2 do
		part({ Size = V3(2, 16, len), CFrame = L(ctx, sx * (w / 2 + 1), top + 8, zc), Color = RGB(100, 85, 80), Material = M.Basalt })
	end
	maybeCoin(ctx, 0, top, z0 + len - 2, 0.7)
	ctx.x, ctx.z = 0, z0 + len
end

-- 🌈 МИР 5: радужная винтовая лестница вокруг облачной башни
function Obstacles.cloudSteps(ctx)
	local r = ctx.rng
	local n = r:NextInteger(9, 12)
	local R = 7
	local x = ctx.x
	local zc = ctx.z + 3 + R + 2
	local top = ctx.y
	local center = L(ctx, x, top, zc)
	part({ Shape = CYL, Size = V3(n * 1.4 + 10, 6, 6), CFrame = center * CF(0, (n * 1.4) / 2 - 3, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
	local rainbow = { RGB(255, 70, 70), RGB(255, 170, 40), RGB(255, 240, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	local a0 = -PI / 2
	local last
	for i = 0, n - 1 do
		local a = a0 + i * (2 * PI / 9)
		local y = top + i * 1.4
		local cf = center * CFrame.Angles(0, -a, 0) * CF(R, y - top - 0.5, 0)
		last = part({ Size = V3(4.4, 1, 3.4 - ctx.diff * 0.8), CFrame = cf, Color = rainbow[(i % #rainbow) + 1] })
		addPath(last.Position)
		if i % 4 == 2 then
			coinAt(CF(last.Position + V3(0, 3, 0)))
		end
	end
	local topY = top + (n - 1) * 1.4
	local exitZ = zc + R + 2
	local size = 8
	themedPlatform(ctx, x, topY, exitZ + size / 2, size, size)
	ctx.x, ctx.y, ctx.z = x, topY, exitZ + size
end

-- ⭐ МИР 5: прыжки по звёздам, часть звёзд качается вверх-вниз
function Obstacles.starHop(ctx)
	local r = ctx.rng
	local n = r:NextInteger(4, 6)
	for i = 1, n do
		local gap = r:NextNumber(2.8, 3.4 + 1.2 * ctx.diff)
		local x = math.clamp(ctx.x + r:NextNumber(-5, 5), -10, 10)
		local zc = ctx.z + gap + 3
		local base = L(ctx, x, ctx.y - 0.5, zc)
		local parts = {}
		table.insert(parts, part({ Shape = CYL, Size = V3(1, 4.4, 4.4), CFrame = base * ROT_UP, Color = RGB(255, 220, 60) }))
		for k = 0, 4 do
			local a = k / 5 * 2 * PI
			table.insert(parts, part({ Size = V3(1.8, 1, 2.6), CFrame = base * CFrame.Angles(0, a, 0) * CF(0, 0, -2.9), Color = RGB(255, 200, 40) }))
		end
		table.insert(parts, part({ Shape = CYL, Size = V3(0.3, 2, 2), CFrame = base * CF(0, 0.5, 0) * ROT_UP, Color = RGB(255, 250, 200), Material = M.Neon, CanCollide = false }))
		if ctx.diff > 0.15 and i % 2 == 0 then
			local amp, speed, phase = 2 + 1.5 * ctx.diff, 0.8 + 0.5 * ctx.diff, r:NextNumber(0, 2 * PI)
			for _, p in ipairs(parts) do
				table.insert(info.movers, { part = p, base = p.CFrame, axis = V3(0, 1, 0), amp = amp, speed = speed, phase = phase })
			end
		end
		addPath(base.Position)
		maybeCoin(ctx, x, ctx.y, zc, 0.35)
		ctx.x, ctx.z = x, zc + 3
	end
end

-- ============ 💎 ПЕЩЕРНЫЕ ПРЕПЯТСТВИЯ (мир 3) ============
local CAVE_STONE = RGB(78, 92, 98)

-- 🔥 круглая лавовая яма (как на картинке): камни-ступеньки, часть из них ныряет в лаву
function Obstacles.lavaPit(ctx)
	local r = ctx.rng
	local R = 14
	local x = 0
	local top = ctx.y
	local zc = ctx.z + 3 + R
	local center = L(ctx, x, top, zc)
	lavaPart({ Shape = CYL, Size = V3(1, R * 2, R * 2), CFrame = center * CF(0, -1.6, 0) * ROT_UP, Color = RGB(255, 120, 20), Material = M.CrackedLava })
	part({ Shape = CYL, Size = V3(3, R * 2 + 3, R * 2 + 3), CFrame = center * CF(0, -3.4, 0) * ROT_UP, Color = darker(CAVE_STONE, 0.7), Material = M.Slate })
	if not ctx.sky then
		column(ctx, x, zc, LAVA_BOTTOM, top - 4.9, R * 1.4, R * 1.4, darker(CAVE_STONE, 0.6), M.Slate, true)
	end
	-- высокий каменный бортик со входом и выходом (по нему не пройти)
	local segs = 24
	for i = 0, segs - 1 do
		local a = i / segs * 2 * PI
		if math.abs(math.sin(a)) > 0.3 then -- проёмы спереди и сзади
			local p = center * CF(math.sin(a) * (R + 0.8), 3, -math.cos(a) * (R + 0.8))
			part({ Size = V3(2, 10, 2 * PI * R / segs + 0.6), CFrame = CFrame.lookAt(p.Position, center.Position + V3(0, 3, 0)) * CFrame.Angles(0, PI / 2, 0), Color = CAVE_STONE, Material = M.Slate })
		end
	end
	-- ступеньки зигзагом через яму
	local n = 4 + math.floor(ctx.diff * 2)
	for i = 1, n do
		local s = r:NextNumber(3.6, 4.4) - ctx.diff * 0.6
		local sx = (i % 2 == 0 and 1 or -1) * r:NextNumber(2, 5)
		local zz = -R + (i - 0.5) * (2 * R) / n
		local base = L(ctx, x + sx, top - 0.6 + r:NextNumber(-0.3, 0.6), zc + zz)
		local stone = part({ Size = V3(s, 1.2, s), CFrame = base * CFrame.Angles(0, r:NextNumber(-0.3, 0.3), 0), Color = RGB(150, 110, 85), Material = M.Slate })
		if ctx.diff > 0.2 and i % 2 == 1 then
			-- этот камень медленно уходит в лаву и поднимается
			table.insert(info.movers, { part = stone, base = stone.CFrame * CF(0, -1.3, 0), axis = V3(0, 1, 0), amp = 1.6, speed = 0.9, phase = r:NextNumber(0, 2 * PI) })
		end
		addPath(base.Position)
	end
	local size = 8
	themedPlatform(ctx, x, top, zc + R + 2 + size / 2, size, size)
	maybeCoin(ctx, x, top, zc + R + 2 + size / 2, 0.7)
	ctx.x, ctx.y, ctx.z = x, top, zc + R + 2 + size
end

-- 💎 мигающие кристаллы: зелёные и фиолетовые по очереди становятся твёрдыми
function Obstacles.crystalBlink(ctx)
	local r = ctx.rng
	local n = r:NextInteger(5, 7)
	local cols = { RGB(90, 255, 140), RGB(200, 90, 255) }
	for i = 1, n do
		local group = i % 2
		local size = 5.5 - ctx.diff
		local gap = r:NextNumber(2.4, 3.2)
		local x = math.clamp(ctx.x + r:NextNumber(-4, 4), -10, 10)
		local zc = ctx.z + gap + size / 2
		local p = part({ Size = V3(size, 1.2, size), CFrame = L(ctx, x, ctx.y - 0.6, zc) * CFrame.Angles(0, PI / 4, 0), Color = cols[group + 1], Material = M.Neon, Transparency = 0.1 })
		table.insert(info.blinkers, { part = p, group = group, solid = true })
		-- кристаллики снизу
		for k = 1, 3 do
			part({ Size = V3(1, 3, 1), CFrame = L(ctx, x + r:NextNumber(-1.5, 1.5), ctx.y - 2.5, zc + r:NextNumber(-1.5, 1.5)) * CFrame.Angles(PI + r:NextNumber(-0.4, 0.4), 0, r:NextNumber(-0.4, 0.4)), Color = cols[group + 1], Material = M.Glass, Transparency = 0.2, CanCollide = false })
		end
		addPath(p.Position)
		ctx.x, ctx.z = x, zc + size / 2
	end
	local size = 8
	themedPlatform(ctx, ctx.x, ctx.y, ctx.z + 3 + size / 2, size, size)
	ctx.z = ctx.z + 3 + size
end

-- 🏛 зал древнего храма: колонны мешают бежать, в полу провалы в лаву
function Obstacles.templeHall(ctx)
	local r = ctx.rng
	local len = r:NextInteger(36, 46)
	local w = 14
	local x = 0
	local top = ctx.y
	local z0 = ctx.z + 3
	local zc = z0 + len / 2
	local stone = RGB(170, 160, 140)
	-- пол из плит с провалами
	local tile = 3.5
	local rows = math.floor(len / tile)
	for i = 0, rows - 1 do
		local hole = i > 1 and i < rows - 2 and (i % 3 == 1) and r:NextNumber() < 0.75
		local holeX = r:NextInteger(-1, 1)
		for j = -1, 1 do
			if not (hole and (j == holeX or (ctx.diff > 0.4 and j == -holeX))) then
				part({ Size = V3(w / 3 - 0.15, 1.4, tile - 0.15), CFrame = L(ctx, x + j * w / 3, top - 0.7, z0 + (i + 0.5) * tile), Color = ((i + j) % 2 == 0) and stone or darker(stone, 0.88), Material = M.Slate })
			end
		end
		if i % 3 == 0 then
			addPath(L(ctx, x, top, z0 + (i + 0.5) * tile).Position)
		end
	end
	if not ctx.sky then
		column(ctx, x, zc, LAVA_BOTTOM, top - 1.4, w * 0.6, len * 0.6, darker(stone, 0.6), M.Slate)
	end
	-- колонны по краям и в середине (в шахматном порядке)
	for i = 1, math.floor(len / 7) do
		local z = z0 + i * 7 - 2
		for sx = -1, 1, 2 do
			part({ Shape = CYL, Size = V3(16, 2.4, 2.4), CFrame = L(ctx, x + sx * (w / 2 + 0.6), top + 8, z) * ROT_UP, Color = stone, Material = M.Marble })
		end
		local mx = (i % 2 == 0) and -2.5 or 2.5
		part({ Shape = CYL, Size = V3(16, 2.2, 2.2), CFrame = L(ctx, x + mx, top + 8, z) * ROT_UP, Color = stone, Material = M.Marble })
		part({ Size = V3(3, 1, 3), CFrame = L(ctx, x + mx, top + 0.5, z), Color = darker(stone, 0.8), Material = M.Slate })
	end
	-- крыша-балки
	part({ Size = V3(w + 4, 2, len), CFrame = L(ctx, x, top + 17, zc), Color = darker(stone, 0.85), Material = M.Slate })
	for i = 0, 3 do
		local l = Instance.new("PointLight")
		l.Color = RGB(255, 190, 110)
		l.Range = 18
		l.Brightness = 1.5
		l.Parent = part({ Size = V3(0.8, 1.2, 0.8), CFrame = L(ctx, x + w / 2 - 0.5, top + 6, z0 + 5 + i * len / 4), Color = RGB(255, 200, 110), Material = M.Neon, CanCollide = false })
	end
	maybeCoin(ctx, x, top, zc, 0.8)
	ctx.x, ctx.z = x, z0 + len
end

-- 🪟 Стеклянный мост «как в Игре в кальмара»: 5 рядов по 2 стекла (слева и справа).
-- В каждом ряду одно стекло держит, другое разбивается. Какое — решает сервер,
-- и раз в час расклад меняется.
local glassBridgeCount = 0
function Obstacles.glassBridge(ctx)
	glassBridgeCount += 1
	local bridgeId = glassBridgeCount
	local rows = 5
	local x = ctx.x
	local top = ctx.y
	local tile = 5
	local gapZ = 2.6
	local laneX = 3.4
	local z0 = ctx.z + 3
	themedPlatform(ctx, x, top, z0 + 2, 6, 4)
	local zStart = z0 + 4 + gapZ
	local len = rows * (tile + gapZ)
	-- стальная рама моста (по ней не пройти — она ниже стёкол и без столкновений)
	for _, sx in ipairs({ -laneX - tile / 2 - 0.3, -laneX + tile / 2 + 0.3, laneX - tile / 2 - 0.3, laneX + tile / 2 + 0.3 }) do
		part({ Size = V3(0.4, 0.6, len + 2), CFrame = L(ctx, x + sx, top - 0.9, zStart + len / 2 - gapZ / 2), Color = RGB(70, 75, 85), Material = M.DiamondPlate, CanCollide = false })
	end
	for i = 0, rows do
		part({ Size = V3(laneX * 2 + tile + 1, 0.5, 0.4), CFrame = L(ctx, x, top - 0.9, zStart - gapZ / 2 + i * (tile + gapZ)), Color = RGB(70, 75, 85), Material = M.DiamondPlate, CanCollide = false })
	end
	if not ctx.sky then
		for _, z in ipairs({ zStart, zStart + len - tile }) do
			column(ctx, x, z, LAVA_BOTTOM, top - 1.2, 1.4, 1.4, RGB(70, 75, 85), M.Metal)
		end
	end
	for row = 1, rows do
		local zc = zStart + (row - 1) * (tile + gapZ) + tile / 2
		for _, side in ipairs({ -1, 1 }) do
			local g = part({ Name = "GlassTile", Size = V3(tile, 0.4, tile), CFrame = L(ctx, x + side * laneX, top - 0.2, zc), Color = RGB(190, 235, 255), Material = M.Glass, Transparency = 0.35, Reflectance = 0.15 })
			g:SetAttribute("Bridge", bridgeId)
			g:SetAttribute("Row", row)
			g:SetAttribute("Side", side)
			tag(g, "GlassTile")
		end
		addPath(L(ctx, x, top, zc).Position)
	end
	-- табличка
	makeSign(L(ctx, x, top + 8, z0 + 1), V3(10, 2.4, 0.4), "sign_glass", RGB(30, 40, 60), RGB(190, 235, 255), Enum.NormalId.Back)
	part({ Size = V3(0.4, 9, 0.4), CFrame = L(ctx, x - 5.5, top + 4.5, z0 + 1), Color = RGB(70, 75, 85), Material = M.Metal })
	part({ Size = V3(0.4, 9, 0.4), CFrame = L(ctx, x + 5.5, top + 4.5, z0 + 1), Color = RGB(70, 75, 85), Material = M.Metal })
	local endZ = zStart + len
	local size = 9
	themedPlatform(ctx, x, top, endZ + size / 2, size, size)
	maybeCoin(ctx, x, top, endZ + size / 2, 0.9)
	ctx.x, ctx.y, ctx.z = x, top, endZ + size
end

-- У каждого мира СВОЙ набор препятствий — они не повторяются между мирами
local POOLS = {
	{ "jumps", "stripes", "balloons", "bounce", "spinner", "coasterTrack" }, -- 🎡 парк
	{ "macarons", "canes", "donuts", "glassBridge", "glassBridge", "pushers" }, -- 🍭 Candy Land
	{ "lavaPit", "crystalBlink", "templeHall", "minecart", "cave", "lasers", "pendulum" }, -- 💎 хрустальные пещеры
	{ "plankBridge", "lavaCurtains", "geysers", "vanish", "movers" }, -- 🌋 острова вулкана
	{ "cloudSteps", "starHop", "rope", "disks", "conveyor" }, -- ☁️ небо
}

local CLIMBING = { climb = true, bounce = true, cloudSteps = true }

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
	pp.MaxActivationDistance = 20
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

-- ============ ДЕТАЛИ ОКРУЖЕНИЯ (мультяшный стиль) ============
local LEAVES = { RGB(80, 190, 70), RGB(100, 210, 80), RGB(60, 170, 60), RGB(120, 215, 90) }

-- Кубическое дерево (как на картинках): ствол + 2–3 куба листвы
local function blockyTree(cf, rng, scale, leafColor)
	scale = scale or 1
	local h = rng:NextNumber(5, 8) * scale
	part({ Size = V3(1.6 * scale, h, 1.6 * scale), CFrame = cf * CF(0, h / 2, 0), Color = RGB(125, 82, 48), Material = M.Wood })
	local leaf = leafColor or pick(rng, LEAVES)
	local s1 = 7 * scale
	part({ Size = V3(s1, s1 * 0.8, s1), CFrame = cf * CF(0, h + s1 * 0.25, 0) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = leaf, Material = M.Grass })
	local s2 = 5 * scale
	part({ Size = V3(s2, s2 * 0.8, s2), CFrame = cf * CF(rng:NextNumber(-0.8, 0.8) * scale, h + s1 * 0.7 + s2 * 0.2, rng:NextNumber(-0.8, 0.8) * scale) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = leaf:Lerp(Color3.new(1, 1, 1), 0.12), Material = M.Grass })
	if rng:NextNumber() < 0.5 then
		local s3 = 3 * scale
		part({ Size = V3(s3, s3 * 0.8, s3), CFrame = cf * CF(0, h + s1 * 1.05 + s2 * 0.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = leaf:Lerp(Color3.new(1, 1, 1), 0.22), Material = M.Grass })
	end
end

local function bush(cf, rng)
	local s = rng:NextNumber(2, 3.5)
	part({ Size = V3(s, s * 0.8, s), CFrame = cf * CF(0, s * 0.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = pick(rng, LEAVES), Material = M.Grass, CanCollide = false })
	if rng:NextNumber() < 0.6 then
		part({ Size = V3(0.6, 0.6, 0.6), CFrame = cf * CF(s * 0.3, s * 0.85, 0), Color = pick(rng, PARTY), CanCollide = false })
	end
end

local function flower(cf, rng)
	part({ Size = V3(0.2, 1, 0.2), CFrame = cf * CF(0, 0.5, 0), Color = RGB(60, 160, 60), CanCollide = false })
	part({ Size = V3(0.7, 0.4, 0.7), CFrame = cf * CF(0, 1.1, 0) * CFrame.Angles(0, 0.7, 0), Color = pick(rng, PARTY), CanCollide = false })
end

local function lamp(cf)
	part({ Size = V3(0.6, 7, 0.6), CFrame = cf * CF(0, 3.5, 0), Color = RGB(40, 40, 50), Material = M.Metal })
	part({ Size = V3(1.6, 0.4, 1.6), CFrame = cf * CF(0, 7.2, 0), Color = RGB(40, 40, 50), Material = M.Metal })
	local bulb = part({ Size = V3(1.2, 1.4, 1.2), CFrame = cf * CF(0, 8.1, 0), Color = RGB(255, 225, 140), Material = M.Neon })
	part({ Size = V3(1.6, 0.3, 1.6), CFrame = cf * CF(0, 8.9, 0), Color = RGB(40, 40, 50), Material = M.Metal })
	local l = Instance.new("PointLight")
	l.Range = 20
	l.Brightness = 1.4
	l.Color = RGB(255, 210, 150)
	l.Parent = bulb
end

local function fence(a, b)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 4))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		part({ Size = V3(0.5, 2.4, 0.5), CFrame = CF(p + V3(0, 1.2, 0)), Color = RGB(150, 100, 60), Material = M.Wood })
	end
	for _, y in ipairs({ 1.0, 1.9 }) do
		local pa, pb = a + V3(0, y, 0), b + V3(0, y, 0)
		part({ Size = V3(0.3, 0.3, len), CFrame = CFrame.lookAt((pa + pb) / 2, pb), Color = RGB(170, 115, 70), Material = M.Wood })
	end
end

-- Домик с двускатной крышей; передняя сторона смотрит по LookVector cf
local function house(cf, w, d, h, wallColor, roofColor)
	part({ Size = V3(w, h, d), CFrame = cf * CF(0, h / 2, 0), Color = wallColor })
	local rh = math.min(w, d) * 0.4
	local roofTop = cf * CF(0, h, 0)
	local w1 = Instance.new("WedgePart")
	w1.Anchored = true
	w1.Size = V3(w + 1.5, rh, d / 2 + 0.8)
	w1.CFrame = roofTop * CF(0, rh / 2, -(d / 2 + 0.8) / 2)
	w1.Color = roofColor
	w1.Parent = currentFolder
	local w2 = w1:Clone()
	w2.CFrame = roofTop * CF(0, rh / 2, (d / 2 + 0.8) / 2) * CFrame.Angles(0, PI, 0)
	w2.Parent = currentFolder
	-- дверь и окна
	part({ Size = V3(3.2, 5, 0.3), CFrame = cf * CF(0, 2.5, -d / 2 - 0.1), Color = RGB(110, 70, 40), Material = M.Wood })
	for sx = -1, 1, 2 do
		part({ Size = V3(2.4, 2.4, 0.3), CFrame = cf * CF(sx * w * 0.3, h * 0.55, -d / 2 - 0.1), Color = RGB(130, 210, 255), Material = M.Neon })
	end
end

-- Скала-остров (слоями, сужается вниз), сверху трава
local function floatingIsland(cf, rng, size, grassColor)
	part({ Size = V3(size, 2, size), CFrame = cf * CF(0, -1, 0), Color = grassColor or RGB(110, 205, 80), Material = M.SmoothPlastic })
	local s = size
	local h = math.max(3, size * 0.12) -- большие острова — толще
	for i = 1, 4 do
		s = s * 0.78
		part({ Size = V3(s, h, s), CFrame = cf * CF(rng:NextNumber(-1, 1), -2 - (i - 0.5) * h, rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), Color = (i % 2 == 0) and RGB(150, 110, 75) or RGB(130, 95, 65) })
	end
end

-- Пруд с водой
local function pond(cf, r)
	part({ Shape = CYL, Size = V3(0.6, r * 2 + 2, r * 2 + 2), CFrame = cf * CF(0, 0.2, 0) * ROT_UP, Color = RGB(160, 160, 170), Material = M.Slate })
	part({ Shape = CYL, Size = V3(0.5, r * 2, r * 2), CFrame = cf * CF(0, 0.35, 0) * ROT_UP, Color = RGB(70, 170, 255), Material = M.Glass, Transparency = 0.15, CanCollide = false })
end

-- Водопад со скалы в пруд
local function waterfallFx(top, bottom, width)
	local h = (top - bottom).Magnitude
	local fall = part({ Size = V3(width, h, 1), CFrame = CF((top + bottom) / 2) * CFrame.Angles(0, 0, 0), Color = RGB(120, 205, 255), Material = M.Neon, Transparency = 0.3, CanCollide = false, CanQuery = false })
	local holder = part({ Size = V3(width, 1, 1), CFrame = CF(bottom + V3(0, 1, -1)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1))
	mist.Transparency = NumberSequence.new(0.3, 1)
	mist.Size = NumberSequence.new(1.5, 4)
	mist.Speed = NumberRange.new(2, 4)
	mist.Lifetime = NumberRange.new(1, 2)
	mist.Rate = 20
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.Parent = holder
	return fall
end

-- Портал-кольцо с диском (декор или рабочий портал с тегом)
local function portalGate(cf, R, colA, colB, discColor, tagName, worldNum)
	local segs = 24
	for i = 0, segs - 1 do
		local a0, a1 = i / segs * 2 * PI, (i + 1) / segs * 2 * PI
		local mid = (a0 + a1) / 2
		if math.sin(mid) > -0.6 then
			local p0 = (cf * CF(math.cos(a0) * R, math.sin(a0) * R, 0)).Position
			local p1 = (cf * CF(math.cos(a1) * R, math.sin(a1) * R, 0)).Position
			part({ Size = V3(1.8, 1.8, (p1 - p0).Magnitude + 0.3), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = (i % 2 == 0) and colA or colB })
			if i % 2 == 0 then
				part({ Shape = BALL, Size = V3(0.9, 0.9, 0.9), CFrame = CF(p0), Color = Color3.new(1, 1, 1), Material = M.Neon, CanCollide = false })
			end
		end
	end
	for sx = -1, 1, 2 do
		part({ Size = V3(2.6, R * 0.6, 2.6), CFrame = cf * CF(sx * R * 0.82, -R + R * 0.3, 0), Color = colA })
	end
	local disc = part({ Shape = CYL, Size = V3(tagName and 3 or 0.5, 2 * R - 1.2, 2 * R - 1.2), CFrame = cf * CFrame.Angles(0, PI / 2, 0), Color = discColor, Material = M.Neon, Transparency = 0.3, CanCollide = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), discColor)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.7, 0)
	pe.Speed = NumberRange.new(2, 4)
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Rate = 25
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = disc
	local l = Instance.new("PointLight")
	l.Color = discColor
	l.Range = 24
	l.Brightness = 2
	l.Parent = disc
	if tagName then
		tag(disc, tagName)
		disc:SetAttribute("World", worldNum)
	else
		disc.CanTouch = false
	end
	return disc
end

local function bench(cf)
	part({ Size = V3(5, 0.5, 1.6), CFrame = cf * CF(0, 1.4, 0), Color = RGB(150, 100, 60), Material = M.WoodPlanks })
	part({ Size = V3(5, 1.4, 0.3), CFrame = cf * CF(0, 2.2, 0.8), Color = RGB(150, 100, 60), Material = M.WoodPlanks })
	for sx = -1, 1, 2 do
		part({ Size = V3(0.3, 1.2, 1.4), CFrame = cf * CF(sx * 2.2, 0.6, 0), Color = RGB(50, 50, 60), Material = M.Metal })
	end
end

-- ============ КРАСИВЫЕ ДОМИКИ ЛОББИ ============
local function wedgeAt(size, cf, color, mat)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Material = mat or M.SmoothPlastic
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Parent = currentFolder
	return w
end

local function neonLine(a, b, color, thick)
	thick = thick or 0.3
	return part({ Size = V3(thick, thick, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Material = M.Neon, CanCollide = false, CanQuery = false })
end

-- двускатная крыша с полосками «черепицы», коньком и неоновыми краями
local function gableRoof(base, w, d, rh, colA, colB, glow)
	local W, D = w + 2.4, d / 2 + 1.4
	local n = math.max(3, math.floor(W / 2.6))
	local seg = W / n
	for side = -1, 1, 2 do
		for i = 0, n - 1 do
			local cf = base * CF(-W / 2 + seg * (i + 0.5), rh / 2, side * D / 2)
			if side == 1 then
				cf = cf * CFrame.Angles(0, PI, 0)
			end
			wedgeAt(V3(seg + 0.02, rh, D), cf, (i % 2 == 0) and colA or colB, MAT_ROOF)
		end
		-- торцевые неоновые линии
		for sx = -1, 1, 2 do
			neonLine((base * CF(sx * W / 2, 0.15, side * D)).Position, (base * CF(sx * W / 2, rh + 0.15, 0)).Position, glow)
		end
		neonLine((base * CF(-W / 2, 0.1, side * D)).Position, (base * CF(W / 2, 0.1, side * D)).Position, glow)
	end
	part({ Size = V3(W + 0.6, 0.9, 0.9), CFrame = base * CF(0, rh + 0.2, 0), Color = darker(colA, 0.7) })
	for sx = -1, 1, 2 do
		part({ Shape = BALL, Size = V3(1.4, 1.4, 1.4), CFrame = base * CF(sx * (W / 2 + 0.3), rh + 0.3, 0), Color = glow, Material = M.Neon })
	end
end

-- Нарядное здание: цоколь, двухцветные стены, колонны, витрины, полосатый навес,
-- фонарики, ящики с цветами, крыша с черепицей и вывеска в рамке с лампочками.
-- Фасад смотрит в сторону -Z (к центру площади). Возвращает дверь.
local function prettyBuilding(cf, o)
	local w, d, h = o.w, o.d, o.h
	local F = -d / 2
	local trim = o.trim or Color3.new(1, 1, 1)
	part({ Size = V3(w + 2, 0.5, d + 2), CFrame = cf * CF(0, 0.25, 0), Color = RGB(150, 140, 165), Material = MAT_PAVE })
	part({ Size = V3(w, h, d), CFrame = cf * CF(0, 0.5 + h / 2, 0), Color = o.wall, Material = MAT_PLASTER })
	part({ Size = V3(w + 0.3, 2.2, d + 0.3), CFrame = cf * CF(0, 1.6, 0), Color = o.band, Material = M.Brick })
	part({ Size = V3(w + 0.4, 0.4, d + 0.4), CFrame = cf * CF(0, 2.8, 0), Color = trim })
	-- углы-колонны
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			part({ Size = V3(1.4, h + 0.4, 1.4), CFrame = cf * CF(sx * w / 2, 0.5 + h / 2, sz * d / 2), Color = trim })
		end
	end
	-- карниз + неоновая полоска
	part({ Size = V3(w + 1.2, 0.9, d + 1.2), CFrame = cf * CF(0, 0.5 + h, 0), Color = trim })
	part({ Size = V3(w + 1.25, 0.25, 0.25), CFrame = cf * CF(0, 0.5 + h - 0.2, F - 0.62), Color = o.glow, Material = M.Neon, CanCollide = false })
	-- дверь в рамке
	part({ Size = V3(5, 7.2, 0.4), CFrame = cf * CF(0, 0.5 + 3.6, F - 0.1), Color = trim })
	local door = part({ Size = V3(3.8, 6.4, 0.4), CFrame = cf * CF(0, 0.5 + 3.2, F - 0.25), Color = o.door, Material = M.WoodPlanks })
	part({ Size = V3(3, 1.6, 0.2), CFrame = cf * CF(0, 0.5 + 5.2, F - 0.45), Color = RGB(170, 230, 255), Material = M.Neon, Transparency = 0.2, CanCollide = false })
	part({ Shape = BALL, Size = V3(0.5, 0.5, 0.5), CFrame = cf * CF(1.3, 0.5 + 3, F - 0.5), Color = GOLD, Material = M.Foil })
	part({ Size = V3(6, 0.5, 1.6), CFrame = cf * CF(0, 0.25, F - 1.8), Color = RGB(200, 190, 215), Material = M.Cobblestone })
	-- витрины по бокам двери
	local winW, winH = math.max(3, w * 0.27), math.min(5, h * 0.42)
	for sx = -1, 1, 2 do
		local wx = sx * (w * 0.28 + 0.6)
		local wy = 0.5 + 3.4 + winH / 2
		part({ Size = V3(winW + 0.8, winH + 0.8, 0.4), CFrame = cf * CF(wx, wy, F - 0.1), Color = trim })
		part({ Size = V3(winW, winH, 0.3), CFrame = cf * CF(wx, wy, F - 0.2), Color = o.glass or RGB(150, 225, 255), Material = M.Neon, Transparency = 0.15, CanCollide = false })
		part({ Size = V3(0.25, winH, 0.3), CFrame = cf * CF(wx, wy, F - 0.35), Color = trim, CanCollide = false })
		part({ Size = V3(winW, 0.25, 0.3), CFrame = cf * CF(wx, wy, F - 0.35), Color = trim, CanCollide = false })
		-- ящик с цветами под окном
		part({ Size = V3(winW + 0.6, 0.9, 1.1), CFrame = cf * CF(wx, wy - winH / 2 - 0.7, F - 0.6), Color = o.band, Material = M.WoodPlanks, CanCollide = false })
		for i = 0, 4 do
			local fx = wx - winW / 2 + (i + 0.5) * winW / 5
			part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = cf * CF(fx, wy - winH / 2 - 0.05, F - 0.6), Color = PARTY[(i % #PARTY) + 1], CanCollide = false })
		end
		-- фонарик у двери
		part({ Size = V3(0.3, 0.3, 0.9), CFrame = cf * CF(sx * 3.1, 0.5 + 5.6, F - 0.5), Color = RGB(40, 40, 50), Material = M.Metal, CanCollide = false })
		local lan = part({ Size = V3(0.8, 1.1, 0.8), CFrame = cf * CF(sx * 3.1, 0.5 + 5.1, F - 0.95), Color = RGB(255, 220, 130), Material = M.Neon, CanCollide = false })
		local pl = Instance.new("PointLight")
		pl.Color = RGB(255, 210, 140)
		pl.Range = 10
		pl.Parent = lan
	end
	-- окна второго этажа со ставнями
	local upY = 0.5 + h - 2
	for i = -1, 1 do
		local ux = i * w * 0.3
		part({ Size = V3(2.4, 2.2, 0.3), CFrame = cf * CF(ux, upY, F - 0.15), Color = RGB(255, 230, 150), Material = M.Neon, CanCollide = false })
		part({ Size = V3(3, 0.35, 0.6), CFrame = cf * CF(ux, upY - 1.25, F - 0.3), Color = trim, CanCollide = false })
		for sx = -1, 1, 2 do
			part({ Size = V3(0.9, 2.4, 0.25), CFrame = cf * CF(ux + sx * 1.75, upY, F - 0.2), Color = o.roofA, CanCollide = false })
		end
	end
	-- полосатый навес над витринами
	local n = math.floor(w / 2.4)
	local seg = (w + 1) / n
	for i = 0, n - 1 do
		local x = -(w + 1) / 2 + seg * (i + 0.5)
		local col = (i % 2 == 0) and o.awnA or o.awnB
		wedgeAt(V3(seg + 0.02, 1.8, 3.2), cf * CF(x, upY - 3.1, F - 1.6), col)
		part({ Shape = BALL, Size = V3(seg * 0.9, seg * 0.9, 0.4), CFrame = cf * CF(x, upY - 4.05, F - 3.15), Color = col, CanCollide = false })
	end
	-- крыша
	local rh = math.min(w, d) * 0.45
	gableRoof(cf * CF(0, 0.95 + h, 0), w, d, rh, o.roofA, o.roofB, o.glow)
	-- труба
	if o.chimney ~= false then
		part({ Size = V3(2, rh + 1, 2), CFrame = cf * CF(w * 0.3, 0.95 + h + rh * 0.55, d * 0.22), Color = RGB(170, 90, 70), Material = M.Brick })
		part({ Size = V3(2.6, 0.6, 2.6), CFrame = cf * CF(w * 0.3, 0.95 + h + rh * 1.05 + 0.3, d * 0.22), Color = RGB(60, 55, 65) })
	end
	-- вывеска в рамке с лампочками (стоит на карнизе перед крышей)
	local sw, sh = o.signW or w * 0.75, 4.4
	local scf = cf * CF(0, 0.95 + h + sh / 2 + 0.3, F - 1.9)
	part({ Size = V3(sw + 1.2, sh + 1.2, 0.5), CFrame = scf * CF(0, 0, 0.45), Color = o.signFrame or GOLD, Material = M.Foil })
	makeSign(scf, V3(sw, sh, 0.6), o.signKey, o.signBg, o.signFg or Color3.new(1, 1, 1), Enum.NormalId.Front)
	local bulbs = math.floor(sw / 1.6)
	for i = 0, bulbs do
		local x = -sw / 2 - 0.3 + i * (sw + 0.6) / bulbs
		for sy = -1, 1, 2 do
			part({ Shape = BALL, Size = V3(0.45, 0.45, 0.45), CFrame = scf * CF(x, sy * (sh / 2 + 0.3), -0.1), Color = RGB(255, 240, 180), Material = M.Neon, CanCollide = false, CanQuery = false })
		end
	end
	return door, rh
end

-- ============ ЛОББИ (как на картинке: амфитеатр с порталами, вулканом и статуей) ============
local LOBBY_PURPLE = RGB(185, 170, 205)
local LOBBY_PINK = RGB(255, 160, 210)

local function lobbyCrystal(cf, rng, scale)
	scale = scale or 1
	local col = pick(rng, { RGB(190, 100, 255), RGB(220, 140, 255), RGB(150, 90, 240) })
	for i = 1, 5 do
		local h = rng:NextNumber(2.5, 6) * scale
		part({ Size = V3(1.3 * scale, h, 1.3 * scale), CFrame = cf * CF(rng:NextNumber(-1.2, 1.2) * scale, h / 2 - 0.5, rng:NextNumber(-1.2, 1.2) * scale) * CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, PI), rng:NextNumber(-0.45, 0.45)), Color = col, Material = M.Neon, Transparency = 0.1, CanCollide = false })
	end
end

local function lobbyBalloon(cf, rng)
	local c1, c2 = pick(rng, PARTY), pick(rng, PARTY)
	for i = 0, 5 do
		local p = part({ Size = V3(14, 16, 3), CFrame = cf * CFrame.Angles(0, i / 6 * PI, 0), Color = (i % 2 == 0) and c1 or c2, CanCollide = false, CastShadow = false })
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	part({ Size = V3(3.5, 2.6, 3.5), CFrame = cf * CF(0, -12.5, 0), Color = RGB(150, 100, 60), Material = M.Wood, CanCollide = false })
end

-- Блочный человечек (статуя), держит кубок над головой
local function trophyStatue(cf, k)
	local skin, shirt, pants = RGB(255, 205, 150), RGB(220, 40, 50), RGB(45, 45, 60)
	part({ Size = V3(1 * k, 2 * k, 1 * k), CFrame = cf * CF(-0.5 * k, 1 * k, 0), Color = pants })
	part({ Size = V3(1 * k, 2 * k, 1 * k), CFrame = cf * CF(0.5 * k, 1 * k, 0), Color = pants })
	part({ Size = V3(2 * k, 2 * k, 1 * k), CFrame = cf * CF(0, 3 * k, 0), Color = shirt })
	part({ Size = V3(0.8 * k, 0.8 * k, 0.05 * k), CFrame = cf * CF(0, 3.2 * k, -0.52 * k), Color = Color3.new(1, 1, 1) })
	part({ Size = V3(1 * k, 2 * k, 1 * k), CFrame = cf * CF(-1.5 * k, 3 * k, 0), Color = shirt })
	part({ Size = V3(1 * k, 2 * k, 1 * k), CFrame = cf * CF(1.5 * k, 4.6 * k, 0) * CFrame.Angles(0, 0, 0.15), Color = shirt }) -- поднятая рука
	part({ Size = V3(1.2 * k, 1.2 * k, 1.2 * k), CFrame = cf * CF(0, 4.6 * k, 0), Color = skin })
	part({ Size = V3(1.25 * k, 0.4 * k, 1.25 * k), CFrame = cf * CF(0, 5.25 * k, 0), Color = RGB(120, 70, 40) })
	part({ Size = V3(1.3 * k, 0.25 * k, 0.3 * k), CFrame = cf * CF(0, 4.9 * k, -0.55 * k), Color = RGB(40, 40, 45) }) -- очки
	-- кубок в поднятой руке
	local cup = cf * CF(1.65 * k, 6.3 * k, 0)
	part({ Shape = CYL, Size = V3(0.4 * k, 0.8 * k, 0.8 * k), CFrame = cup * CF(0, -0.6 * k, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
	local c = part({ Shape = CYL, Size = V3(1.2 * k, 1.4 * k, 1.4 * k), CFrame = cup * CF(0, 0.3 * k, 0) * ROT_UP, Color = GOLD, Material = M.Neon })
	for sx = -1, 1, 2 do
		part({ Shape = CYL, Size = V3(0.15 * k, 0.6 * k, 0.6 * k), CFrame = cup * CF(sx * 0.75 * k, 0.4 * k, 0), Color = GOLD, Material = M.Foil })
	end
	local l = Instance.new("PointLight")
	l.Color = GOLD
	l.Range = 30
	l.Brightness = 2
	l.Parent = c
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = GOLD
	sp.Parent = c
end

-- 🏆 Гигантский золотой кубок со звездой
local function giantTrophy(cf, k)
	part({ Shape = CYL, Size = V3(1.5 * k, 8 * k, 8 * k), CFrame = cf * CF(0, 0.75 * k, 0) * ROT_UP, Color = RGB(60, 40, 30) })
	part({ Size = V3(6 * k, 3 * k, 6 * k), CFrame = cf * CF(0, 3 * k, 0), Color = RGB(80, 50, 35), Material = M.Wood })
	part({ Size = V3(6.3 * k, 0.6 * k, 6.3 * k), CFrame = cf * CF(0, 4.6 * k, 0), Color = GOLD, Material = M.Foil })
	part({ Shape = CYL, Size = V3(3 * k, 1.6 * k, 1.6 * k), CFrame = cf * CF(0, 6.4 * k, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
	part({ Shape = BALL, Size = V3(2.6 * k, 2.6 * k, 2.6 * k), CFrame = cf * CF(0, 8 * k, 0), Color = GOLD, Material = M.Foil })
	for i = 0, 4 do
		local d = (3.6 + i * 0.95) * k
		part({ Shape = CYL, Size = V3(1.2 * k, d, d), CFrame = cf * CF(0, (9.3 + i * 1.15) * k, 0) * ROT_UP, Color = GOLD, Material = i == 4 and M.Neon or M.Foil })
	end
	for sx = -1, 1, 2 do
		for j = 0, 6 do
			local a = -PI / 2 + j / 6 * PI
			part({ Shape = BALL, Size = V3(1 * k, 1 * k, 1 * k), CFrame = cf * CF(sx * (4.3 * k + math.cos(a) * 1.9 * k), (11.6 + math.sin(a) * 2.1) * k, 0), Color = GOLD, Material = M.Foil })
		end
	end
	local star = cf * CF(0, 18.2 * k, 0)
	for i = 0, 4 do
		local a = i / 5 * 2 * PI
		part({ Size = V3(1 * k, 3.6 * k, 0.7 * k), CFrame = star * CFrame.Angles(0, 0, a) * CF(0, 1.6 * k, 0), Color = RGB(255, 230, 90), Material = M.Neon })
	end
	local glow = part({ Shape = BALL, Size = V3(1.6 * k, 1.6 * k, 1.6 * k), CFrame = star, Color = Color3.new(1, 1, 1), Material = M.Neon })
	local l = Instance.new("PointLight")
	l.Color = GOLD
	l.Range = 40
	l.Brightness = 3
	l.Parent = glow
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = GOLD
	sp.Parent = glow
end

-- Рельсы горок по списку точек
local function coasterRails(pts, groundY)
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dir = b - a
		local side = dir:Cross(V3(0, 1, 0))
		if side.Magnitude < 0.01 then
			side = V3(1, 0, 0)
		end
		side = side.Unit * 1.4
		for sgn = -1, 1, 2 do
			local ra, rb = a + side * sgn, b + side * sgn
			part({ Size = V3(0.6, 0.6, (rb - ra).Magnitude + 0.3), CFrame = CFrame.lookAt((ra + rb) / 2, rb), Color = RGB(220, 40, 50), Material = M.Metal })
		end
		part({ Size = V3(3.4, 0.3, 0.5), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(70, 70, 80), Material = M.Metal })
		if groundY and i % 3 == 0 and a.Y - groundY > 2 then
			local h = a.Y - groundY
			part({ Size = V3(1, h, 1), CFrame = CF(a.X, groundY + h / 2, a.Z), Color = RGB(80, 80, 95), Material = M.Metal })
		end
	end
end

local function buildLobby(ctx)
	local top = 12
	local rng = Random.new(Config.MAP_SEED + 5)
	local center = L(ctx, 0, top, 0)
	local cpos = center.Position
	local function facing(x, z, y)
		local p = L(ctx, x, y or top, z).Position
		return CFrame.lookAt(p, V3(cpos.X, p.Y, cpos.Z))
	end

	-- 🪨 пол площади (каменные плиты), остров со скалами снизу
	local floor = part({ Name = "LobbyFloor", Size = V3(150, 2, 150), CFrame = L(ctx, 0, top - 1, 0), Color = LOBBY_PURPLE, Material = M.Cobblestone })
	info.lobbyFloor = floor
	local s = 150
	for i = 1, 4 do
		s *= 0.86
		part({ Size = V3(s, 5, s), CFrame = L(ctx, rng:NextNumber(-2, 2), top - 2 - i * 5 + 2.5, rng:NextNumber(-2, 2)), Color = (i % 2 == 0) and RGB(150, 140, 165) or RGB(125, 115, 140), Material = M.Slate })
	end
	column(ctx, 0, 0, LAVA_BOTTOM, top - 22, 40, 40, RGB(110, 100, 120), M.Slate)
	-- газоны по краям
	for _, g in ipairs({ { -62, -40, 24, 60 }, { 62, -40, 24, 60 }, { -40, -68, 40, 14 }, { 40, -68, 40, 14 } }) do
		part({ Size = V3(g[3], 0.4, g[4]), CFrame = L(ctx, g[1], top + 0.15, g[2]), Color = RGB(110, 205, 80), CanCollide = false })
	end

	-- 🔥 светящиеся линии на полу: кольцо вокруг статуи и лучи к порталам
	local ringR = 24
	for i = 0, 35 do
		local a0, a1 = i / 36 * 2 * PI, (i + 1) / 36 * 2 * PI
		local p0, p1 = L(ctx, math.cos(a0) * ringR, top + 0.08, math.sin(a0) * ringR).Position, L(ctx, math.cos(a1) * ringR, top + 0.08, math.sin(a1) * ringR).Position
		-- аккуратный каменный бортик вместо жёлтой неоновой полосы
		part({ Size = V3(1.2, 0.35, (p1 - p0).Magnitude + 0.25), CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CF(0, 0.1, 0), Color = RGB(150, 135, 165), Material = M.Slate, CanQuery = false })
	end
	part({ Shape = CYL, Size = V3(0.15, ringR * 2 - 2, ringR * 2 - 2), CFrame = L(ctx, 0, top + 0.06, 0) * ROT_UP, Color = RGB(235, 90, 20), Material = M.CrackedLava, CanCollide = false })

	-- 🗿 статуя на лавовой скале
	for i = 0, 3 do
		local w = 34 - i * 5
		part({ Size = V3(w, 3, w), CFrame = L(ctx, 0, top + 1.5 + i * 3, 0) * CFrame.Angles(0, i * 0.4, 0), Color = RGB(90, 70, 65), Material = M.Basalt })
		part({ Size = V3(w + 0.2, 0.4, 0.8), CFrame = L(ctx, 0, top + 2.2 + i * 3, 0) * CFrame.Angles(0, i * 0.4 + 0.7, 0), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
	end
	giantTrophy(L(ctx, 0, top + 12, 0), 3.2) -- огромный кубок, видно отовсюду

	-- 🧍 точка появления (спереди), смотрит на порталы
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LavaSpawn"
	spawn.Anchored = true
	spawn.Size = V3(8, 0.4, 8)
	spawn.CFrame = L(ctx, 0, top + 0.2, -58)
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = currentFolder
	info.lobbySpawn = L(ctx, 0, top + 3.5, -58)
	for i = 0, 3 do
		local p = L(ctx, 0, top, -50 + i * 6).Position
		for sx = -1, 1, 2 do
			part({ Size = V3(0.8, 0.12, 4), CFrame = CFrame.lookAt(p, p + L(ctx, 0, top, 1).Position - L(ctx, 0, top, 0).Position) * CF(sx * 1.4, 0.1, 0.8) * CFrame.Angles(0, sx * 0.75, 0), Color = RGB(255, 200, 60), Material = M.Neon, CanCollide = false, CanQuery = false })
		end
	end

	-- 🏔 задняя скала с водопадами, вулкан и логотип
	local wallZ, wallH = 70, 34
	part({ Size = V3(152, wallH, 16), CFrame = L(ctx, 0, top + wallH / 2, wallZ), Color = RGB(140, 125, 150), Material = M.Slate })
	part({ Size = V3(152, 2, 18), CFrame = L(ctx, 0, top + wallH + 1, wallZ), Color = RGB(110, 205, 80) })
	for i = 1, 14 do
		part({ Size = V3(rng:NextNumber(6, 12), rng:NextNumber(8, 16), 4), CFrame = L(ctx, rng:NextNumber(-72, 72), top + rng:NextNumber(4, wallH - 6), wallZ - 8.5), Color = RGB(160, 145, 170), Material = M.Slate })
	end
	for _, wx in ipairs({ -66, -40, 40, 66 }) do
		local baseY = math.abs(wx) < 58 and (top + 4) or top -- у середины стены — терраса
		local t0 = L(ctx, wx, top + wallH, wallZ - 11).Position
		waterfallFx(t0, L(ctx, wx, baseY, wallZ - 11).Position, 6)
		pond(L(ctx, wx, baseY, wallZ - 16), 5)
	end
	for i = 1, 10 do
		local tx = rng:NextNumber(-70, 70)
		blockyTree(L(ctx, tx, top + wallH + 2, wallZ + rng:NextNumber(-5, 5)), rng, rng:NextNumber(1.1, 1.6), pick(rng, { LOBBY_PINK, RGB(90, 200, 80) }))
	end
	-- 🦆 уточка №1 за водопадом
	makeDuck(L(ctx, -66, top + 1.5, wallZ - 9.4), 1)
	-- вулкан за стеной
	local vz = 125
	local layers = 9
	for i = 0, layers - 1 do
		local rr = 52 * (1 - i / (layers + 1.5))
		part({ Shape = CYL, Size = V3(13, rr * 2, rr * 2), CFrame = L(ctx, 0, top - 10 + (i + 0.5) * 13, vz) * ROT_UP, Color = darker(RGB(115, 92, 85), 1 - i * 0.04), Material = M.Basalt })
	end
	for k = 0, 4 do
		local a = -PI / 2 + (k - 2) * 0.35
		for i = 0, layers - 2 do
			local rr = 52 * (1 - (i + 0.5) / (layers + 1.5))
			local p = L(ctx, math.cos(a) * rr, top - 10 + (i + 0.5) * 13, vz + math.sin(a) * rr).Position
			part({ Size = V3(3, 13.6, 1), CFrame = CFrame.lookAt(p, p + (p - L(ctx, 0, p.Y, vz).Position).Unit), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
		end
	end
	local crater = part({ Shape = CYL, Size = V3(1, 20, 20), CFrame = L(ctx, 0, top - 10 + layers * 13 + 0.5, vz) * ROT_UP, Color = RGB(255, 110, 0), Material = M.Neon })
	local em = Instance.new("ParticleEmitter")
	em.Name = "Eruption"
	em.Color = ColorSequence.new(RGB(255, 230, 80), RGB(255, 50, 0))
	em.LightEmission = 1
	em.Size = NumberSequence.new(4, 1)
	em.Speed = NumberRange.new(50, 75)
	em.SpreadAngle = Vector2.new(20, 20)
	em.Acceleration = V3(0, -40, 0)
	em.Lifetime = NumberRange.new(2.5, 4)
	em.Rate = 10
	em.EmissionDirection = Enum.NormalId.Right
	em.Parent = crater
	tag(crater, "Eruptor")
	local sm = Instance.new("Smoke")
	sm.Size = 40
	sm.Opacity = 0.35
	sm.RiseVelocity = 16
	sm.Color = RGB(60, 55, 55)
	sm.Parent = crater
	local cf0 = Instance.new("Fire")
	cf0.Size = 18
	cf0.Parent = crater
	-- логотип
	local logo = part({ Size = V3(130, 48, 1), CFrame = L(ctx, 0, top + wallH + 30, wallZ - 6), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local lsg = Instance.new("SurfaceGui")
	lsg.Face = Enum.NormalId.Back
	lsg.LightInfluence = 0
	lsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	lsg.PixelsPerStud = 20
	for i, info2 in ipairs({ { "THE FLOOR IS", 0, 0.32, RGB(240, 220, 255), RGB(110, 40, 170) }, { "LAVA", 0.3, 0.7, RGB(255, 170, 30), RGB(150, 30, 0) } }) do
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(0, info2[2])
		lbl.Size = UDim2.fromScale(1, info2[3])
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.Text = info2[1]
		lbl.TextColor3 = info2[4]
		lbl.AutoLocalize = false
		local st = Instance.new("UIStroke")
		st.Thickness = 8
		st.Color = info2[5]
		st.Parent = lbl
		if i == 2 then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(RGB(255, 230, 80), RGB(255, 80, 0))
			g.Rotation = 90
			g.Parent = lbl
		end
		lbl.Parent = lsg
	end
	lsg.Parent = logo

	-- 🌀 терраса с 5 порталами в арках
	local tz, tH = 50, 4
	part({ Size = V3(116, tH, 22), CFrame = L(ctx, 0, top + tH / 2, tz), Color = RGB(170, 160, 190), Material = M.Cobblestone })
	for w = 1, #Config.Zones do
		local px = (w - 3) * 23
		local col = ACCENT[w]
		local gate = L(ctx, px, top + tH + 7.6, tz + 2)
		-- каменная арка вокруг портала
		for sx = -1, 1, 2 do
			part({ Size = V3(3, 19, 3), CFrame = gate * CF(sx * 9, 0.5, 0), Color = RGB(150, 135, 165), Material = M.Slate })
			part({ Size = V3(0.6, 16, 0.6), CFrame = gate * CF(sx * 7.7, 0.5, -1.4), Color = col, Material = M.Neon, CanCollide = false })
		end
		part({ Size = V3(21, 3, 3), CFrame = gate * CF(0, 10.5, 0), Color = RGB(150, 135, 165), Material = M.Slate })
		portalGate(gate, 7, col, Color3.new(1, 1, 1), col, "WorldPortal", w)
		local zinfo = Config.Zones[w]
		makeSign(gate * CF(0, 14.5, -1.6), V3(20, 5, 0.6), "sign_world", col, Color3.new(1, 1, 1), Enum.NormalId.Back, nil, { tostring(w), zinfo.emoji, "@zone_" .. w })
		local first = (w - 1) * PER_ZONE + 1
		makeSign(gate * CF(0, 10.5, -1.7), V3(14, 2.4, 0.3), "sign_stages", RGB(40, 30, 60), Color3.new(1, 1, 1), Enum.NormalId.Back, nil, { tostring(first), tostring(first + PER_ZONE - 1) })
		-- замок (клиент прячет, если мир открыт)
		local lock = part({ Name = "PortalLock", Size = V3(9, 9, 0.6), CFrame = gate * CF(0, 0, -0.8), Color = RGB(40, 35, 55), Transparency = 0.15, CanCollide = false, CanTouch = false })
		lock:SetAttribute("World", w)
		tag(lock, "PortalLock")
		local lg = Instance.new("SurfaceGui")
		lg.Face = Enum.NormalId.Back
		lg.LightInfluence = 0
		lg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		lg.PixelsPerStud = 30
		local ll = Instance.new("TextLabel")
		ll.Size = UDim2.fromScale(1, 1)
		ll.BackgroundTransparency = 1
		ll.TextScaled = true
		ll.Font = Enum.Font.GothamBlack
		ll.TextColor3 = Color3.new(1, 1, 1)
		ll.Text = "🔒"
		ll.Parent = lg
		lg.Parent = lock
		-- ступени и стрелки к порталу
		for i = 1, 4 do
			part({ Size = V3(14, i, 1.6), CFrame = L(ctx, px, top + i / 2, tz - 11 - (4 - i) * 1.6 - 0.8), Color = RGB(180, 170, 200), Material = M.Cobblestone })
		end
		for i = 0, 2 do
			local p = L(ctx, px, top, tz - 18 - i * 5).Position
			local dir = (L(ctx, px, top, tz).Position - L(ctx, px, top, tz - 10).Position).Unit
			for sx = -1, 1, 2 do
				part({ Size = V3(0.8, 0.12, 3.6), CFrame = CFrame.lookAt(p, p + dir) * CF(sx * 1.3, 0.1, 0.7) * CFrame.Angles(0, sx * 0.75, 0), Color = col, Material = M.Neon, CanCollide = false, CanQuery = false })
			end
		end
		-- светящаяся линия от кольца к ступеням
		local a = L(ctx, px * 0.6, top + 0.08, ringR).Position
		local b = L(ctx, px, top + 0.08, tz - 18).Position
		part({ Size = V3(0.8, 0.1, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(255, 150, 40), Material = M.Neon, CanCollide = false, CanQuery = false })
		lobbyCrystal(L(ctx, px + 11, top + tH, tz - 6), rng, 1.2)
	end

	-- ⬅ ЛЕВАЯ СТОРОНА: доска заданий, магазин, питомцы
	local dCf = facing(-52, 22)
	local dboard = part({ Name = "ChallengeBoard", Size = V3(26, 15, 1), CFrame = dCf * CF(0, 11, 0), Color = RGB(35, 28, 50) })
	part({ Size = V3(27, 16, 0.6), CFrame = dCf * CF(0, 11, 0.6), Color = RGB(255, 170, 40), Material = M.Neon })
	for sx = -1, 1, 2 do
		part({ Size = V3(1.4, 4, 1.4), CFrame = dCf * CF(sx * 10, 2, 0), Color = RGB(90, 70, 60), Material = M.Wood })
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 25
	local lst = Instance.new("Frame")
	lst.Size = UDim2.fromScale(1, 1)
	lst.BackgroundTransparency = 1
	lst.Parent = sg
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0.02, 0)
	lay.Parent = lst
	for i = 0, 3 do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 0.22)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = i == 0 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		lbl.TextColor3 = i == 0 and GOLD or Color3.new(1, 1, 1)
		lbl.TextXAlignment = i == 0 and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		lbl.AutoLocalize = false
		lbl.LayoutOrder = i
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.Parent = lbl
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
	prompt(dboard, "prompt_open", "prompt_tasks", "OpenTasks", true)

	-- 🛒 магазин: нарядная лавка с навесом, прилавком и подарком на крыше
	local shopCf = facing(-56, -8)
	local _, shopRh = prettyBuilding(shopCf, {
		w = 22, d = 14, h = 12,
		wall = RGB(255, 236, 200), band = RGB(190, 90, 70), trim = Color3.new(1, 1, 1),
		roofA = RGB(150, 60, 200), roofB = RGB(185, 100, 235), glow = RGB(255, 120, 230),
		awnA = RGB(230, 50, 60), awnB = Color3.new(1, 1, 1), door = RGB(150, 60, 200),
		signKey = "sign_shop", signBg = RGB(150, 60, 200), signW = 15,
	})
	local counter = part({ Size = V3(16, 3, 2.6), CFrame = shopCf * CF(0, 1.5, -12.5), Color = RGB(170, 115, 70), Material = M.WoodPlanks })
	part({ Size = V3(16.6, 0.4, 3), CFrame = shopCf * CF(0, 3.2, -12.5), Color = RGB(255, 236, 200) })
	prompt(counter, "prompt_open", "prompt_shop", "OpenShop", "trails")
	-- товары на прилавке
	for i = 0, 6 do
		local gx = -6.6 + i * 2.2
		if i % 3 == 0 then
			part({ Size = V3(1.3, 1.3, 1.3), CFrame = shopCf * CF(gx, 4.05, -12.5) * CFrame.Angles(0, 0.4, 0), Color = PARTY[(i % #PARTY) + 1] })
			part({ Size = V3(1.35, 1.35, 0.3), CFrame = shopCf * CF(gx, 4.05, -12.5) * CFrame.Angles(0, 0.4, 0), Color = GOLD })
		elseif i % 3 == 1 then
			part({ Shape = BALL, Size = V3(1.3, 1.3, 1.3), CFrame = shopCf * CF(gx, 4.05, -12.5), Color = PARTY[(i % #PARTY) + 1], Material = M.Neon })
			part({ Size = V3(0.5, 0.6, 0.5), CFrame = shopCf * CF(gx, 4.9, -12.5), Color = RGB(150, 100, 60) })
		else
			part({ Shape = CYL, Size = V3(1.6, 1.2, 1.2), CFrame = shopCf * CF(gx, 4.2, -12.5) * ROT_UP, Color = RGB(130, 220, 255), Material = M.Glass, Transparency = 0.2 })
		end
	end
	-- полосатый зонтик над прилавком
	for sx = -1, 1, 2 do
		part({ Size = V3(0.5, 7, 0.5), CFrame = shopCf * CF(sx * 7.6, 3.5, -13.6), Color = Color3.new(1, 1, 1) })
	end
	for i = 0, 7 do
		wedgeAt(V3(2.15, 1.4, 3.6), shopCf * CF(-7.55 + i * 2.15, 7.3, -12.8), (i % 2 == 0) and RGB(230, 50, 60) or Color3.new(1, 1, 1))
	end
	-- подарок на крыше
	local giftCf = shopCf * CF(-4, 12.95 + shopRh + 1.5, 0)
	part({ Size = V3(6, 5, 6), CFrame = giftCf, Color = RGB(230, 50, 60) })
	part({ Size = V3(6.1, 5.1, 1.2), CFrame = giftCf, Color = GOLD })
	part({ Size = V3(1.2, 5.1, 6.1), CFrame = giftCf, Color = GOLD })
	for sx = -1, 1, 2 do
		part({ Shape = BALL, Size = V3(2.2, 2.2, 2.2), CFrame = giftCf * CF(sx * 1, 3.1, 0), Color = GOLD })
	end
	-- бочки и ящики у стены
	for i, off in ipairs({ { -13, -4 }, { -13.5, 0 }, { 13, -3 } }) do
		if i == 3 then
			part({ Size = V3(2.4, 2.4, 2.4), CFrame = shopCf * CF(off[1], 1.2, off[2]) * CFrame.Angles(0, 0.3, 0), Color = RGB(170, 115, 70), Material = M.WoodPlanks })
		else
			part({ Shape = CYL, Size = V3(3, 2.4, 2.4), CFrame = shopCf * CF(off[1], 1.5, off[2]) * ROT_UP, Color = RGB(150, 95, 55), Material = M.Wood })
			part({ Shape = CYL, Size = V3(0.3, 2.5, 2.5), CFrame = shopCf * CF(off[1], 2.3, off[2]) * ROT_UP, Color = RGB(60, 60, 70), Material = M.Metal })
		end
	end

	-- 🐾 зоомагазин: домик с лапкой на крыше, будкой и загончиком
	local petsCf = facing(-54, -38)
	local _, petsRh = prettyBuilding(petsCf, {
		w = 18, d = 13, h = 11,
		wall = RGB(200, 225, 255), band = RGB(90, 120, 200), trim = Color3.new(1, 1, 1),
		roofA = RGB(255, 140, 60), roofB = RGB(255, 175, 90), glow = RGB(120, 220, 255),
		awnA = RGB(80, 160, 255), awnB = Color3.new(1, 1, 1), door = RGB(90, 120, 200),
		glass = RGB(200, 160, 255), signKey = "sign_petshop", signBg = RGB(80, 160, 255), signW = 13,
	})
	local petsDoor = part({ Size = V3(5, 6.6, 0.4), CFrame = petsCf * CF(0, 3.8, -7.1), Color = RGB(200, 120, 255), Material = M.Neon, Transparency = 0.4, CanCollide = false })
	prompt(petsDoor, "prompt_open", "prompt_petshop", "OpenShop", "pets")
	-- лапка на коньке крыши
	local paw = petsCf * CF(-3, 11.95 + petsRh + 2.6, 0)
	part({ Shape = BALL, Size = V3(3.2, 3.2, 1.2), CFrame = paw, Color = RGB(255, 120, 180), Material = M.Neon })
	for i = -1, 1 do
		part({ Shape = BALL, Size = V3(1.4, 1.4, 1), CFrame = paw * CF(i * 1.4, 2.1 - math.abs(i) * 0.4, 0), Color = RGB(255, 120, 180), Material = M.Neon })
	end
	-- загончик с питомцами перед домиком
	local pen = petsCf * CF(0, 0, -13)
	part({ Size = V3(16, 0.3, 6), CFrame = pen * CF(0, 0.15, 0), Color = RGB(120, 210, 90) })
	for _, e in ipairs({ { -8, 0, 0.2, 6 }, { 8, 0, 0.2, 6 } }) do
		part({ Size = V3(e[3] + 0.3, 1.6, e[4]), CFrame = pen * CF(e[1], 0.8, e[2]), Color = Color3.new(1, 1, 1), Material = M.WoodPlanks })
	end
	for sx = -1, 1, 2 do
		part({ Size = V3(5.5, 1.6, 0.3), CFrame = pen * CF(sx * 5.25, 0.8, -3), Color = Color3.new(1, 1, 1), Material = M.WoodPlanks })
	end
	for i = -1, 1 do
		part({ Shape = CYL, Size = V3(1.6, 2.4, 2.4), CFrame = pen * CF(i * 4.5, 0.8, 0) * ROT_UP, Color = PARTY[i + 3] })
		part({ Shape = BALL, Size = V3(1.6, 1.6, 1.6), CFrame = pen * CF(i * 4.5, 2.4, 0), Color = PARTY[i + 4], Material = M.Neon })
	end
	-- будка
	local kennel = petsCf * CF(12.5, 0, -2) * CFrame.Angles(0, -0.5, 0)
	part({ Size = V3(4, 3, 4), CFrame = kennel * CF(0, 1.5, 0), Color = RGB(230, 70, 70), Material = M.WoodPlanks })
	part({ Size = V3(1.8, 2, 0.2), CFrame = kennel * CF(0, 1, -2.05), Color = RGB(40, 30, 30) })
	wedgeAt(V3(4.6, 1.6, 2.4), kennel * CF(0, 3.8, -1.2), RGB(255, 175, 90))
	wedgeAt(V3(4.6, 1.6, 2.4), kennel * CF(0, 3.8, 1.2) * CFrame.Angles(0, PI, 0), RGB(255, 175, 90))
	part({ Shape = CYL, Size = V3(0.4, 1.4, 1.4), CFrame = kennel * CF(0, 0.2, -3.2) * ROT_UP, Color = RGB(80, 160, 255) })

	-- 👑 VIP на скале слева сзади
	local vx, vz = -64, 40
	local plH = 12
	part({ Size = V3(24, plH, 26), CFrame = L(ctx, vx, top + plH / 2, vz), Color = RGB(150, 135, 165), Material = M.Slate })
	part({ Size = V3(24.4, 1.2, 26.4), CFrame = L(ctx, vx, top + plH + 0.6, vz), Color = RGB(110, 205, 80) })
	for i = 1, 6 do
		part({ Size = V3(6, i * 2, 2), CFrame = L(ctx, vx + 9, top + i, vz - 13 - (7 - i) * 2 + 1), Color = RGB(170, 160, 190), Material = M.Cobblestone })
	end
	local vipCf = CFrame.lookAt(L(ctx, vx - 2, top + plH + 1.2, vz + 1).Position, L(ctx, vx - 2, top + plH + 1.2, vz - 20).Position)
	local hw, hd, hh = 13, 12, 9
	part({ Size = V3(hw, hh, 1), CFrame = vipCf * CF(0, hh / 2, hd / 2), Color = GOLD, Material = M.Foil })
	part({ Size = V3(1, hh, hd), CFrame = vipCf * CF(-hw / 2, hh / 2, 0), Color = GOLD, Material = M.Foil })
	part({ Size = V3(1, hh, hd), CFrame = vipCf * CF(hw / 2, hh / 2, 0), Color = GOLD, Material = M.Foil })
	part({ Size = V3(4.5, hh, 1), CFrame = vipCf * CF(-4.25, hh / 2, -hd / 2), Color = GOLD, Material = M.Foil })
	part({ Size = V3(4.5, hh, 1), CFrame = vipCf * CF(4.25, hh / 2, -hd / 2), Color = GOLD, Material = M.Foil })
	part({ Size = V3(4, 2, 1), CFrame = vipCf * CF(0, hh - 1, -hd / 2), Color = GOLD, Material = M.Foil })
	part({ Size = V3(hw + 2, 1, hd + 2), CFrame = vipCf * CF(0, hh + 0.5, 0), Color = RGB(150, 60, 200) })
	local door = part({ Name = "VipDoor", Size = V3(4, hh - 2, 0.6), CFrame = vipCf * CF(0, (hh - 2) / 2, -hd / 2), Color = GOLD, Material = M.Neon, Transparency = 0.35 })
	tag(door, "VipDoor")
	prompt(door, "prompt_buyvip", "sign_vip", "BuyVip", true)
	makeSign(vipCf * CF(0, hh + 5, -1), V3(10, 4, 0.8), "sign_vip", RGB(150, 60, 200), GOLD, Enum.NormalId.Front)
	local crownCf = vipCf * CF(0, hh + 9.5, 0)
	part({ Shape = CYL, Size = V3(1.6, 6, 6), CFrame = crownCf * ROT_UP, Color = GOLD, Material = M.Foil })
	for i = 0, 4 do
		local a = i / 5 * 2 * PI
		part({ Shape = BALL, Size = V3(1.2, 1.2, 1.2), CFrame = crownCf * CF(math.cos(a) * 2.6, 1.6, math.sin(a) * 2.6), Color = (i % 2 == 0) and RGB(255, 60, 80) or RGB(80, 160, 255), Material = M.Neon })
	end
	-- нарядный вход: колонны, портик с фронтоном, ковровая дорожка, кадки с кустами
	local MARBLE = RGB(250, 245, 255)
	local pz = -hd / 2 - 3.2
	for sx = -1, 1, 2 do
		part({ Size = V3(2, 0.6, 2), CFrame = vipCf * CF(sx * 3.6, 0.3, pz), Color = GOLD, Material = M.Foil })
		part({ Shape = CYL, Size = V3(hh - 0.6, 1.3, 1.3), CFrame = vipCf * CF(sx * 3.6, hh / 2, pz) * ROT_UP, Color = MARBLE, Material = M.Marble })
		part({ Size = V3(2, 0.6, 2), CFrame = vipCf * CF(sx * 3.6, hh - 0.3, pz), Color = GOLD, Material = M.Foil })
		-- кадка с кустом
		part({ Size = V3(2, 1.6, 2), CFrame = vipCf * CF(sx * 6.2, 0.8, pz - 0.6), Color = GOLD, Material = M.Foil })
		part({ Shape = BALL, Size = V3(2.6, 2.6, 2.6), CFrame = vipCf * CF(sx * 6.2, 2.5, pz - 0.6), Color = RGB(90, 200, 80) })
		-- окна по бокам
		part({ Size = V3(0.3, 3.4, 4), CFrame = vipCf * CF(sx * (hw / 2 + 0.55), hh * 0.55, 0), Color = RGB(130, 210, 255), Material = M.Neon, CanCollide = false })
		part({ Size = V3(0.4, 0.5, 4.8), CFrame = vipCf * CF(sx * (hw / 2 + 0.6), hh * 0.55 - 1.9, 0), Color = MARBLE, CanCollide = false })
	end
	part({ Size = V3(10, 0.9, 5), CFrame = vipCf * CF(0, hh + 0.05, pz + 0.6), Color = MARBLE, Material = M.Marble })
	for sx = -1, 1, 2 do
		wedgeAt(V3(0.8, 2.6, 5), vipCf * CF(sx * 2.5, hh + 1.8, pz - 1.5) * CFrame.Angles(0, sx * -PI / 2, 0), MARBLE, M.Marble)
	end
	part({ Shape = BALL, Size = V3(1.6, 1.6, 0.6), CFrame = vipCf * CF(0, hh + 1.6, pz - 1.95), Color = RGB(255, 60, 80), Material = M.Neon })
	part({ Size = V3(3.2, 0.12, 6), CFrame = vipCf * CF(0, 0.06, pz + 0.2), Color = RGB(200, 30, 50), Material = M.Fabric, CanCollide = false })
	-- неоновый контур крыши и башенки по углам
	local rw, rd = (hw + 2) / 2, (hd + 2) / 2
	for _, e in ipairs({ { -rw, -rd, rw, -rd }, { rw, -rd, rw, rd }, { rw, rd, -rw, rd }, { -rw, rd, -rw, -rd } }) do
		neonLine((vipCf * CF(e[1], hh + 1.05, e[2])).Position, (vipCf * CF(e[3], hh + 1.05, e[4])).Position, RGB(255, 120, 230), 0.35)
	end
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			local tcf = vipCf * CF(sx * (rw - 0.8), hh + 1, sz * (rd - 0.8))
			part({ Shape = CYL, Size = V3(3.4, 2.2, 2.2), CFrame = tcf * CF(0, 1.7, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
			part({ Shape = BALL, Size = V3(2.6, 2.6, 2.6), CFrame = tcf * CF(0, 3.6, 0), Color = RGB(150, 60, 200) })
			part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = tcf * CF(0, 5, 0), Color = GOLD, Material = M.Neon })
		end
	end
	makeChest(vipCf * CF(3.5, 0, 3) * CFrame.Angles(0, PI, 0), "vip", "VipChest")
	-- 📦 сокровище №1: за VIP-домиком на скале
	treasureChest(vipCf * CF(-4, 0, 9.5) * CFrame.Angles(0, PI, 0), 1)
	makeSign(vipCf * CF(-hw / 2 + 0.6, 5, 0), V3(0.4, 3, 8), "sign_vipchest", RGB(70, 25, 100), GOLD, Enum.NormalId.Right)

	-- ➡ ПРАВАЯ СТОРОНА: топ игроков, награды, перерождение, рекорды
	local tCf = facing(54, 22)
	info.leaderboardRows = makeBoard(tCf * CF(0, 11, 0), V3(26, 17, 1), Enum.NormalId.Front, "sign_top")
	for sx = -1, 1, 2 do
		part({ Size = V3(1.4, 4, 1.4), CFrame = tCf * CF(sx * 10, 2, 0), Color = RGB(90, 70, 60), Material = M.Wood })
	end
	local crown = tCf * CF(0, 22, 0)
	part({ Shape = CYL, Size = V3(2, 8, 8), CFrame = crown * ROT_UP, Color = GOLD, Material = M.Foil })
	for i = 0, 4 do
		local a = i / 5 * 2 * PI
		part({ Size = V3(1.6, 3, 1.6), CFrame = crown * CF(math.cos(a) * 3.4, 2, math.sin(a) * 3.4), Color = GOLD, Material = M.Foil })
	end
	part({ Shape = BALL, Size = V3(1.8, 1.8, 1.8), CFrame = crown * CF(0, 0, -4), Color = RGB(255, 60, 80), Material = M.Neon })
	-- 🎁 награды (ежедневные задания и награда)
	local rCf = facing(54, -10)
	part({ Size = V3(16, 2, 12), CFrame = rCf * CF(0, 1, 0), Color = RGB(170, 160, 190), Material = M.Cobblestone })
	local bigChest = makeChest(rCf * CF(0, 2, 0) * CFrame.Angles(0, PI, 0), "rewards", "DailyStand")
	bigChest:ScaleTo(2)
	prompt(bigChest.PrimaryPart, "prompt_open", "prompt_tasks", "OpenTasks", true)
	makeSign(rCf * CF(0, 13, 0), V3(16, 4.5, 0.8), "sign_rewards", RGB(150, 60, 200), GOLD, Enum.NormalId.Front)
	-- 🔁 перерождение
	local rbCf = facing(50, -38)
	part({ Shape = CYL, Size = V3(0.6, 14, 14), CFrame = rbCf * CF(0, 0.3, 0) * ROT_UP, Color = RGB(200, 40, 50) })
	local rbPad = part({ Shape = CYL, Size = V3(0.8, 9, 9), CFrame = rbCf * CF(0, 0.5, 0) * ROT_UP, Color = RGB(255, 80, 90), Material = M.Neon })
	makeSign(rbCf * CF(0, 7.5, 4), V3(11, 3.5, 0.6), "sign_rebirth", RGB(200, 40, 50), Color3.new(1, 1, 1), Enum.NormalId.Front)
	prompt(rbPad, "prompt_open", "prompt_rebirth", "OpenRebirth", true)
	-- ⏱ рекорды по времени (у точки появления справа)
	local timeCf = CFrame.lookAt(L(ctx, 26, top, -58).Position, L(ctx, 26, top, 0).Position)
	info.timeRows = makeBoard(timeCf * CF(0, 8, 0), V3(16, 12, 1), Enum.NormalId.Front, "sign_top_time")

	-- 🎢 горки на правой скале
	local side = 76
	part({ Size = V3(10, 26, 100), CFrame = L(ctx, side, top + 13, 10), Color = RGB(140, 125, 150), Material = M.Slate })
	part({ Size = V3(10, 26, 100), CFrame = L(ctx, -side, top + 13, 10), Color = RGB(140, 125, 150), Material = M.Slate })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Size = V3(12, 2, 102), CFrame = L(ctx, sx * side, top + 27, 10), Color = RGB(110, 205, 80) })
		for i = 1, 5 do
			blockyTree(L(ctx, sx * side + rng:NextNumber(-3, 3), top + 28, -30 + i * 16), rng, rng:NextNumber(1, 1.4), pick(rng, { LOBBY_PINK, RGB(90, 200, 80) }))
		end
	end
	local pts = {}
	for i = 0, 40 do
		local t = i / 40
		local z = -40 + t * 110
		local y = top + 34 + math.sin(t * PI * 3) * 10 + t * 8
		local x = side + 2 + math.sin(t * PI * 2) * 6
		table.insert(pts, L(ctx, x, y, z).Position)
	end
	-- петля в конце
	local lp = pts[#pts]
	for i = 1, 20 do
		local ph = i / 20 * 2 * PI
		table.insert(pts, lp + V3(0, 14 - 14 * math.cos(ph), 0) + (L(ctx, 0, 0, 1).Position - L(ctx, 0, 0, 0).Position) * (14 * math.sin(ph)) + V3(i * 0.3, 0, 0))
	end
	coasterRails(pts, top + 27)

	-- 🌸 деревья, кристаллы, лавочки, фонари по площади
	local function freeSpot(x, z)
		if math.abs(x) < 10 and z < -20 then
			return false -- проход от точки появления
		end
		if x * x + z * z < 30 * 30 then
			return false
		end
		if z > 30 then
			return false -- терраса с порталами
		end
		local zones = { { -52, 22, 16 }, { -56, -8, 19 }, { -54, -38, 18 }, { -64, 40, 18 }, { 54, 22, 16 }, { 54, -10, 12 }, { 50, -38, 10 }, { 26, -58, 10 } }
		for _, zz in ipairs(zones) do
			if (x - zz[1]) ^ 2 + (z - zz[2]) ^ 2 < zz[3] ^ 2 then
				return false
			end
		end
		-- только по краям площади: центр и дороги остаются свободными
		if math.abs(x) < 58 and z > -62 then
			return false
		end
		return math.abs(x) < 70 and z > -72
	end
	local placed = 0
	for _ = 1, 900 do
		if placed >= 34 then
			break
		end
		local x, z = rng:NextNumber(-70, 70), rng:NextNumber(-72, 30)
		if freeSpot(x, z) then
			placed += 1
			local cf = L(ctx, x, top, z)
			local roll = rng:NextNumber()
			if roll < 0.2 then
				blockyTree(cf, rng, rng:NextNumber(1, 1.4), pick(rng, { LOBBY_PINK, LOBBY_PINK, RGB(90, 200, 80) }))
			elseif roll < 0.5 then
				lobbyCrystal(cf, rng, rng:NextNumber(0.9, 1.5))
			elseif roll < 0.78 then
				bush(cf, rng)
			else
				for _ = 1, 3 do
					flower(cf * CF(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), rng)
				end
			end
		end
	end
	-- 🛣 широкая аллея: точка появления → кубок → порталы, и дорожки к магазинам
	local AVENUE = RGB(225, 215, 235)
	part({ Size = V3(18, 0.12, 44), CFrame = L(ctx, 0, top + 0.07, -50), Color = AVENUE, Material = M.Cobblestone, CanQuery = false })
	part({ Size = V3(18, 0.12, 14), CFrame = L(ctx, 0, top + 0.07, 33), Color = AVENUE, Material = M.Cobblestone, CanQuery = false })
	part({ Size = V3(116, 0.12, 10), CFrame = L(ctx, 0, top + 0.07, 34), Color = AVENUE, Material = M.Cobblestone, CanQuery = false })
	for sx = -1, 1, 2 do
		part({ Size = V3(0.8, 0.3, 44), CFrame = L(ctx, sx * 9.3, top + 0.15, -50), Color = RGB(200, 185, 215), Material = M.Slate, CanQuery = false })
		-- боковые дорожки к постройкам (слева магазин/питомцы, справа награды/перерождение)
		for _, zz in ipairs({ -38, -10, 20 }) do
			part({ Size = V3(26, 0.12, 7), CFrame = L(ctx, sx * 40, top + 0.07, zz), Color = AVENUE, Material = M.Cobblestone, CanQuery = false })
		end
		for i = 0, 3 do
			lamp(L(ctx, sx * 11, top, -68 + i * 12))
		end
	end
	for _, p in ipairs({ { -30, -10 }, { 30, -10 }, { -30, 20 }, { 30, 20 } }) do
		bench(facing(p[1], p[2]))
	end
	for _, p in ipairs({ { -24, 8 }, { 24, 8 }, { -40, 34 }, { 40, 34 } }) do
		lamp(L(ctx, p[1], top, p[2]))
	end
	fence(L(ctx, -74, top, -74).Position, L(ctx, -12, top, -74).Position)
	fence(L(ctx, 12, top, -74).Position, L(ctx, 74, top, -74).Position)

	-- ☁️ большие парящие острова и воздушные шары
	local skyRng = Random.new(Config.MAP_SEED + 77)
	for i = 0, 9 do
		local a = i / 10 * 2 * PI + 0.3
		local dist = skyRng:NextNumber(115, 170)
		local y = top + skyRng:NextNumber(30, 85)
		local icf = L(ctx, math.cos(a) * dist, y, math.sin(a) * dist)
		local size = skyRng:NextNumber(24, 42)
		floatingIsland(icf, skyRng, size, pick(skyRng, { RGB(110, 205, 80), LOBBY_PINK }))
		for _ = 1, 3 do
			blockyTree(icf * CF(skyRng:NextNumber(-size / 3, size / 3), 0, skyRng:NextNumber(-size / 3, size / 3)), skyRng, skyRng:NextNumber(1.1, 1.6), pick(skyRng, { LOBBY_PINK, RGB(90, 200, 80) }))
		end
		if i % 2 == 0 then
			waterfallFx(icf.Position + V3(size / 2 - 2, -1, 0), icf.Position + V3(size / 2 - 2, -55, 0), 4)
		end
	end
	for i = 1, 3 do
		lobbyBalloon(L(ctx, skyRng:NextNumber(-90, 90), top + skyRng:NextNumber(55, 85), skyRng:NextNumber(-20, 110)), skyRng)
	end

	addPath(L(ctx, 0, top, 0).Position)
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			addPath(L(ctx, sx * 72, top, sz * 72).Position)
		end
	end
	ctx.x, ctx.y, ctx.z = 0, top, 75
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

-- ============ ОСТРОВА-ДЕКОРАЦИИ ВОКРУГ ТРАССЫ ============
-- Каждый мир окружён плотными тематическими островами, как на картинках.

local function egg(size, cf, color, material, extra)
	local p = part({ Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic, CanCollide = false })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	return p
end

-- --- реквизит парка ---
local function popcornStand(cf, rng)
	part({ Size = V3(4, 4, 3), CFrame = cf * CF(0, 2, 0), Color = RGB(230, 40, 50) })
	for i = -1, 1 do
		part({ Size = V3(0.6, 4.05, 3.05), CFrame = cf * CF(i * 1.3, 2, 0), Color = Color3.new(1, 1, 1) })
	end
	part({ Size = V3(4.6, 0.6, 3.6), CFrame = cf * CF(0, 4.3, 0), Color = RGB(255, 210, 50) })
	for i = 1, 6 do
		part({ Shape = BALL, Size = V3(1, 1, 1), CFrame = cf * CF(rng:NextNumber(-1.5, 1.5), 4.9 + rng:NextNumber(0, 0.6), rng:NextNumber(-1, 1)), Color = RGB(255, 245, 210), CanCollide = false })
	end
	part({ Size = V3(0.3, 4, 0.3), CFrame = cf * CF(1.8, 6, 1.3), Color = RGB(220, 220, 230), Material = M.Metal })
	part({ Size = V3(5, 0.3, 4), CFrame = cf * CF(0, 8, 0), Color = RGB(230, 40, 50) })
end

local function ticketBooth(cf, rng)
	part({ Size = V3(5, 6, 4), CFrame = cf * CF(0, 3, 0), Color = pick(rng, PARTY) })
	part({ Size = V3(3, 2, 0.3), CFrame = cf * CF(0, 3.6, -2.1), Color = RGB(130, 210, 255), Material = M.Neon })
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = V3(6, 2, 5)
	w.CFrame = cf * CF(0, 7, 0)
	w.Color = Color3.new(1, 1, 1)
	w.Parent = currentFolder
	part({ Shape = BALL, Size = V3(1.2, 1.2, 1.2), CFrame = cf * CF(0, 8.4, 1.8), Color = RGB(255, 210, 50), Material = M.Neon })
end

local function balloonCart(cf, rng)
	part({ Size = V3(3, 2, 2), CFrame = cf * CF(0, 1.4, 0), Color = RGB(80, 170, 255) })
	for sx = -1, 1, 2 do
		part({ Shape = CYL, Size = V3(0.3, 1, 1), CFrame = cf * CF(sx * 1.6, 0.5, 0), Color = RGB(40, 40, 50) })
	end
	local knot = (cf * CF(0, 2.4, 0)).Position
	for i = 1, 6 do
		local bp = (cf * CF(rng:NextNumber(-2, 2), rng:NextNumber(6, 9), rng:NextNumber(-2, 2))).Position
		part({ Shape = BALL, Size = V3(1.8, 1.8, 1.8), CFrame = CF(bp), Color = PARTY[(i % #PARTY) + 1], CanCollide = false, Reflectance = 0.1 })
		part({ Size = V3(0.06, 0.06, (bp - knot).Magnitude), CFrame = CFrame.lookAt((bp + knot) / 2, bp), Color = Color3.new(1, 1, 1), CanCollide = false })
	end
end

local function teacupRide(cf, rng)
	part({ Shape = CYL, Size = V3(0.6, 14, 14), CFrame = cf * CF(0, 0.3, 0) * ROT_UP, Color = RGB(255, 220, 120) })
	for i = 0, 3 do
		local a = i / 4 * 2 * PI
		local c = cf * CF(math.cos(a) * 4, 0, math.sin(a) * 4)
		local col = PARTY[i + 1]
		part({ Shape = CYL, Size = V3(2.2, 3.4, 3.4), CFrame = c * CF(0, 1.7, 0) * ROT_UP, Color = col })
		part({ Shape = CYL, Size = V3(0.3, 4.4, 4.4), CFrame = c * CF(0, 0.75, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
		part({ Size = V3(0.4, 1.4, 0.4), CFrame = c * CF(2, 2, 0), Color = col })
	end
	part({ Size = V3(1, 6, 1), CFrame = cf * CF(0, 3, 0), Color = RGB(230, 40, 50) })
	part({ Shape = CYL, Size = V3(1, 6, 6), CFrame = cf * CF(0, 6.5, 0) * ROT_UP, Color = RGB(80, 170, 255) })
end


-- --- реквизит сладостей ---
local function lollipopTree(cf, rng, scale)
	scale = scale or 1
	local h = rng:NextNumber(5, 8) * scale
	part({ Shape = CYL, Size = V3(h, 0.6 * scale, 0.6 * scale), CFrame = cf * CF(0, h / 2, 0) * ROT_UP, Color = Color3.new(1, 1, 1), CanCollide = false })
	local c1, c2 = pick(rng, CANDY), pick(rng, PARTY)
	local d = 4.5 * scale
	local disc = cf * CF(0, h + d / 2 - 0.3, 0) * CFrame.Angles(0, rng:NextNumber(0, PI), 0)
	part({ Shape = CYL, Size = V3(0.8 * scale, d, d), CFrame = disc * CFrame.Angles(0, PI / 2, 0), Color = c1, CanCollide = false })
	part({ Shape = CYL, Size = V3(0.85 * scale, d * 0.65, d * 0.65), CFrame = disc * CFrame.Angles(0, PI / 2, 0), Color = c2, CanCollide = false })
	part({ Shape = CYL, Size = V3(0.9 * scale, d * 0.3, d * 0.3), CFrame = disc * CFrame.Angles(0, PI / 2, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
end

local function smallCane(cf, rng, scale)
	scale = scale or 1
	local h = rng:NextNumber(4, 7) * scale
	for i = 0, math.floor(h) - 1 do
		part({ Shape = CYL, Size = V3(1, 0.9 * scale, 0.9 * scale), CFrame = cf * CF(0, i + 0.5, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(230, 30, 50) or Color3.new(1, 1, 1), CanCollide = false })
	end
	part({ Size = V3(0.9 * scale, 0.9 * scale, 1.8 * scale), CFrame = cf * CF(0, h + 0.2, 0.6 * scale), Color = RGB(230, 30, 50), CanCollide = false })
end

local function gumdrop(cf, rng)
	local col = pick(rng, CANDY)
	for k = 0, 2 do
		local d = 3 * (1 - k * 0.3)
		part({ Shape = CYL, Size = V3(0.8, d, d), CFrame = cf * CF(0, 0.4 + k * 0.8, 0) * ROT_UP, Color = col, Material = M.Glass, Transparency = 0.1, CanCollide = false })
	end
end

local function iceCream(cf, rng)
	local cone = cf * CF(0, 0, 0)
	for k = 0, 3 do
		local d = 0.6 + k * 0.5
		part({ Shape = CYL, Size = V3(1, d, d), CFrame = cone * CF(0, 0.5 + k, 0) * ROT_UP, Color = RGB(225, 170, 100), CanCollide = false })
	end
	part({ Shape = BALL, Size = V3(2.6, 2.6, 2.6), CFrame = cone * CF(0, 4.6, 0), Color = pick(rng, CANDY), CanCollide = false })
	part({ Shape = BALL, Size = V3(2.2, 2.2, 2.2), CFrame = cone * CF(0, 6.2, 0), Color = pick(rng, CANDY), CanCollide = false })
	part({ Shape = BALL, Size = V3(0.7, 0.7, 0.7), CFrame = cone * CF(0, 7.4, 0), Color = RGB(220, 20, 40), CanCollide = false })
end

local function donut(cf, rng)
	local dough, glaze = RGB(225, 165, 95), pick(rng, CANDY)
	for i = 0, 11 do
		local a = i / 12 * 2 * PI
		part({ Shape = BALL, Size = V3(1.8, 1.8, 1.8), CFrame = cf * CF(math.cos(a) * 1.8, 1, math.sin(a) * 1.8), Color = dough, CanCollide = false })
		part({ Shape = BALL, Size = V3(1.5, 1.5, 1.5), CFrame = cf * CF(math.cos(a) * 1.8, 1.4, math.sin(a) * 1.8), Color = glaze, CanCollide = false })
	end
end

local function cottonCandyTree(cf, rng)
	local h = rng:NextNumber(5, 8)
	part({ Size = V3(0.6, h, 0.6), CFrame = cf * CF(0, h / 2, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
	local col = pick(rng, { RGB(255, 160, 210), RGB(150, 210, 255), RGB(200, 170, 255) })
	for i = 1, 4 do
		local s = rng:NextNumber(2.5, 4)
		part({ Shape = BALL, Size = V3(s, s, s), CFrame = cf * CF(rng:NextNumber(-1.2, 1.2), h + rng:NextNumber(0, 2), rng:NextNumber(-1.2, 1.2)), Color = col, CanCollide = false })
	end
end

-- --- реквизит подземелья ---
local function crystalSmall(cf, rng)
	local col = pick(rng, { RGB(90, 255, 140), RGB(200, 90, 255), RGB(90, 220, 255), RGB(160, 255, 90) })
	for i = 1, 4 do
		local h = rng:NextNumber(2.5, 6)
		part({ Size = V3(1.2, h, 1.2), CFrame = cf * CF(rng:NextNumber(-1, 1), h / 2 - 0.4, rng:NextNumber(-1, 1)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, PI), rng:NextNumber(-0.5, 0.5)), Color = col, Material = M.Neon, Transparency = 0.15, CanCollide = false })
	end
	local l = Instance.new("PointLight")
	l.Color = col
	l.Range = 16
	l.Brightness = 1.6
	l.Parent = part({ Size = V3(0.5, 0.5, 0.5), CFrame = cf * CF(0, 3, 0), Transparency = 1, CanCollide = false })
end

local function mushroomSmall(cf, rng)
	local cap = pick(rng, { RGB(80, 220, 255), RGB(200, 90, 255), RGB(90, 255, 160) })
	local h = rng:NextNumber(2, 4)
	part({ Shape = CYL, Size = V3(h, 0.8, 0.8), CFrame = cf * CF(0, h / 2, 0) * ROT_UP, Color = RGB(235, 225, 210), CanCollide = false })
	egg(V3(3, 1.4, 3), cf * CF(0, h + 0.3, 0), cap, M.Neon)
end

local function templeRuin(cf, rng)
	local stone = RGB(165, 150, 130)
	part({ Size = V3(12, 1, 8), CFrame = cf * CF(0, 0.5, 0), Color = stone, Material = M.Slate })
	for i = 0, 3 do
		local h = (i == 2) and 4 or 8 -- одна колонна сломана
		part({ Shape = CYL, Size = V3(h, 1.4, 1.4), CFrame = cf * CF(-4.5 + i * 3, 1 + h / 2, -2.5) * ROT_UP, Color = stone, Material = M.Marble })
	end
	part({ Size = V3(6.5, 1, 2.6), CFrame = cf * CF(-3, 9.5, -2.5), Color = stone, Material = M.Marble })
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = V3(6.5, 1.6, 1.4)
	w.CFrame = cf * CF(-3, 10.8, -2.5)
	w.Color = stone
	w.Parent = currentFolder
	crystalSmall(cf * CF(3, 1, 2), rng)
end

local function torch(cf)
	part({ Size = V3(0.5, 4, 0.5), CFrame = cf * CF(0, 2, 0), Color = RGB(90, 60, 40), Material = M.Wood })
	local t = part({ Size = V3(0.8, 0.8, 0.8), CFrame = cf * CF(0, 4.3, 0), Color = RGB(255, 170, 60), Material = M.Neon, CanCollide = false })
	local f = Instance.new("Fire")
	f.Size = 2
	f.Heat = 4
	f.Parent = t
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 160, 80)
	l.Range = 18
	l.Brightness = 1.5
	l.Parent = t
end

-- --- реквизит вулкана ---
local function redMushroom(cf, rng)
	local h = rng:NextNumber(1.5, 3)
	part({ Shape = CYL, Size = V3(h, 0.8, 0.8), CFrame = cf * CF(0, h / 2, 0) * ROT_UP, Color = RGB(245, 235, 220), CanCollide = false })
	egg(V3(3, 1.6, 3), cf * CF(0, h + 0.3, 0), RGB(225, 40, 40))
	for i = 1, 3 do
		local a = i * 2.1
		part({ Shape = BALL, Size = V3(0.5, 0.5, 0.5), CFrame = cf * CF(math.cos(a) * 0.9, h + 0.85, math.sin(a) * 0.9), Color = Color3.new(1, 1, 1), CanCollide = false })
	end
end

local function rockSpike(cf, rng, _, col)
	local h = rng:NextNumber(3, 7)
	for k = 0, 2 do
		local s = 2.6 * (1 - k * 0.3)
		part({ Size = V3(s, h / 3 + 0.4, s), CFrame = cf * CF(0, k * h / 3 + h / 6, 0) * CFrame.Angles(0, k * 0.5, 0), Color = col or RGB(110, 95, 88), Material = M.Slate, CanCollide = false })
	end
end

local function lavaPool(cf)
	part({ Shape = CYL, Size = V3(0.4, 6, 6), CFrame = cf * CF(0, 0.15, 0) * ROT_UP, Color = RGB(90, 75, 70), Material = M.Slate, CanCollide = false })
	local lp = part({ Shape = CYL, Size = V3(0.45, 4.6, 4.6), CFrame = cf * CF(0, 0.2, 0) * ROT_UP, Color = RGB(255, 120, 0), Material = M.Neon, CanCollide = false })
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 120, 30)
	l.Range = 14
	l.Parent = lp
end

local function deadTree(cf, rng)
	local h = rng:NextNumber(5, 8)
	part({ Size = V3(0.8, h, 0.8), CFrame = cf * CF(0, h / 2, 0) * CFrame.Angles(0, 0, 0.1), Color = RGB(60, 45, 40), Material = M.Wood, CanCollide = false })
	for i = 1, 3 do
		part({ Size = V3(0.4, 3, 0.4), CFrame = cf * CF(0, h * (0.5 + i * 0.12), 0) * CFrame.Angles(0, i * 2, 0.9), Color = RGB(60, 45, 40), Material = M.Wood, CanCollide = false })
	end
end

-- --- реквизит неба ---
local function mushroomTree(cf, rng)
	local h = rng:NextNumber(4, 7)
	part({ Size = V3(0.7, h, 0.7), CFrame = cf * CF(0, h / 2, 0), Color = RGB(240, 230, 220), CanCollide = false })
	egg(V3(4.5, 1.8, 4.5), cf * CF(0, h + 0.4, 0), pick(rng, { RGB(255, 170, 60), RGB(255, 200, 80), RGB(255, 140, 180) }))
	if rng:NextNumber() < 0.5 then
		local h2 = h * 0.6
		part({ Size = V3(0.5, h2, 0.5), CFrame = cf * CF(1.2, h2 / 2, 0.6), Color = RGB(240, 230, 220), CanCollide = false })
		egg(V3(2.6, 1.2, 2.6), cf * CF(1.2, h2 + 0.3, 0.6), RGB(255, 190, 70))
	end
end

local function roundTree(cf, rng)
	local h = rng:NextNumber(3, 5)
	part({ Size = V3(0.8, h, 0.8), CFrame = cf * CF(0, h / 2, 0), Color = RGB(140, 90, 55), CanCollide = false })
	part({ Size = V3(3.6, 3.6, 3.6), CFrame = cf * CF(0, h + 1.6, 0) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Color = pick(rng, { RGB(60, 200, 80), RGB(80, 220, 90), RGB(40, 180, 90) }), CanCollide = false })
end

local function blueCrystal(cf, rng)
	for i = 1, 3 do
		local h = rng:NextNumber(2, 4.5)
		part({ Size = V3(0.9, h, 0.9), CFrame = cf * CF(rng:NextNumber(-0.8, 0.8), h / 2, rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, PI), rng:NextNumber(-0.3, 0.3)), Color = RGB(110, 170, 255), Material = M.Glass, Transparency = 0.1, CanCollide = false })
	end
end

local function blueRock(cf, rng)
	part({ Size = V3(rng:NextNumber(2.5, 4), rng:NextNumber(1.5, 2.5), rng:NextNumber(2.5, 4)), CFrame = cf * CF(0, 0.8, 0) * CFrame.Angles(0.1, rng:NextNumber(0, PI), 0.1), Color = RGB(110, 150, 230), CanCollide = false })
end

-- Наборы реквизита и стиль островов для каждого мира
local SCENERY = {
	{ -- 🎡 парк
		top = { RGB(110, 205, 80), RGB(120, 215, 90) },
		cliff = { RGB(150, 110, 75), RGB(125, 92, 62) },
		props = {
			{ blockyTree, 4 },
			{ bush, 3 },
			{ flower, 3 },
			{ lamp, 1 },
			{ popcornStand, 1 },
			{ ticketBooth, 1 },
			{ balloonCart, 1 },
			{ bench, 1 },
		},
		big = { teacupRide },
	},
	{ -- 🍭 сладости
		top = { RGB(255, 160, 210), RGB(255, 200, 230), RGB(150, 230, 210) },
		cliff = { RGB(140, 80, 45), RGB(110, 60, 35) },
		drip = true,
		props = {
			{ lollipopTree, 4 },
			{ smallCane, 2 },
			{ gumdrop, 3 },
			{ iceCream, 2 },
			{ donut, 1 },
			{ cottonCandyTree, 3 },
		},
	},
	{ -- 💎 подземелье
		top = { RGB(95, 85, 85), RGB(110, 95, 90) },
		cliff = { RGB(70, 62, 62), RGB(55, 50, 52) },
		props = {
			{ crystalSmall, 4 },
			{ mushroomSmall, 3 },
			{ rockSpike, 2 },
			{ torch, 1 },
		},
		big = { templeRuin },
	},
	{ -- 🌋 вулкан
		top = { RGB(100, 175, 70), RGB(85, 150, 60), RGB(90, 78, 70) },
		cliff = { RGB(115, 95, 82), RGB(90, 76, 68) },
		props = {
			{ redMushroom, 3 },
			{ rockSpike, 2 },
			{ blockyTree, 2 },
			{ deadTree, 1 },
			{ lavaPool, 1 },
		},
		lavafall = true,
	},
	{ -- 🏰 небо
		top = { RGB(255, 170, 215), RGB(120, 230, 110), RGB(255, 185, 80), RGB(150, 230, 210) },
		cliff = { RGB(160, 110, 80), RGB(135, 95, 70) },
		drip = true,
		props = {
			{ mushroomTree, 3 },
			{ roundTree, 3 },
			{ blueCrystal, 2 },
			{ blueRock, 2 },
			{ flower, 2 },
		},
	},
}

local function pickProp(list, rng)
	local total = 0
	for _, p in ipairs(list) do
		total += p[2]
	end
	local r = rng:NextNumber(0, total)
	for _, p in ipairs(list) do
		r -= p[2]
		if r <= 0 then
			return p[1]
		end
	end
	return list[1][1]
end

-- Остров-декорация: верх (с «глазурью» для сладостей и неба), скалы слоями, реквизит сверху
local function sceneryIsland(cf, rng, size, zone)
	local st = SCENERY[zone]
	local topCol = pick(rng, st.top)
	local round = rng:NextNumber() < 0.4
	if round then
		part({ Shape = CYL, Size = V3(2, size, size), CFrame = cf * CF(0, -1, 0) * ROT_UP, Color = topCol })
	else
		part({ Size = V3(size, 2, size), CFrame = cf * CF(0, -1, 0), Color = topCol })
	end
	if st.drip then
		local n = math.floor(size / 2.2)
		for i = 0, n - 1 do
			local a = i / n * 2 * PI
			local rr = size / 2 - 0.6
			local ex, ez = math.cos(a) * rr, math.sin(a) * rr
			if not round then
				local k = math.max(math.abs(math.cos(a)), math.abs(math.sin(a)))
				ex, ez = ex / k, ez / k
			end
			local ds = rng:NextNumber(1.4, 2.4)
			part({ Shape = BALL, Size = V3(ds, ds, ds), CFrame = cf * CF(ex, -2 - rng:NextNumber(0, 0.6), ez), Color = topCol, CanCollide = false })
		end
	end
	local s = size
	for i = 1, 3 do
		s *= 0.8
		local c = st.cliff[(i % #st.cliff) + 1]
		if round then
			part({ Shape = CYL, Size = V3(3, s, s), CFrame = cf * CF(0, -2 - i * 3 + 1.5, 0) * ROT_UP, Color = c })
		else
			part({ Size = V3(s, 3, s), CFrame = cf * CF(rng:NextNumber(-1, 1), -2 - i * 3 + 1.5, rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0), Color = c })
		end
	end
	if st.lavafall and rng:NextNumber() < 0.5 then
		part({ Size = V3(2.2, 26, 0.4), CFrame = cf * CF(rng:NextNumber(-size / 4, size / 4), -14, -size / 2 + 0.3), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
	end
	-- реквизит
	local count = math.floor(size * size / 45)
	for _ = 1, count do
		local px, pz = rng:NextNumber(-size / 2 + 2, size / 2 - 2), rng:NextNumber(-size / 2 + 2, size / 2 - 2)
		if not round or (px * px + pz * pz) < (size / 2 - 2) ^ 2 then
			local fn = pickProp(st.props, rng)
			fn(cf * CF(px, 0, pz) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0), rng, rng:NextNumber(0.8, 1.2))
		end
	end
	if st.big and size >= 22 and rng:NextNumber() < 0.5 then
		local fn = st.big[rng:NextInteger(1, #st.big)]
		fn(cf * CF(0, 0, 0) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0), rng)
	end
end

-- 🎈 дирижабль для неба
local function blimp(base, rng, pathY)
	local cf = base * CF(0, pathY + rng:NextNumber(20, 40), 0)
	egg(V3(10, 10, 26), cf, RGB(255, 140, 50))
	for i = -2, 2 do
		egg(V3(10.2, 10.2, 2.4), cf * CF(0, 0, i * 4), (i % 2 == 0) and RGB(255, 210, 60) or RGB(170, 120, 255))
	end
	part({ Size = V3(3, 2, 6), CFrame = cf * CF(0, -6, 0), Color = RGB(60, 120, 255) })
	for _, a in ipairs({ 0, PI / 2, PI, -PI / 2 }) do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.Size = V3(0.6, 4, 4)
		w.CFrame = cf * CF(0, 0, 12) * CFrame.Angles(0, 0, a) * CF(0, 4, 0) * CFrame.Angles(0, PI, 0)
		w.Color = RGB(60, 120, 255)
		w.Parent = currentFolder
	end
end

-- 🌈 большая радуга
local function bigRainbow(base, rng, pathY)
	local R = 34
	local cf = base * CF(0, pathY - 20, 0)
	local bands = { RGB(255, 60, 60), RGB(255, 160, 40), RGB(255, 235, 60), RGB(70, 210, 90), RGB(60, 140, 255), RGB(150, 80, 230) }
	for b, col in ipairs(bands) do
		local rr = R - (b - 1) * 2.4
		local prev
		for i = 0, 18 do
			local a = (i / 18) * PI
			local pt = (cf * CF(math.cos(a) * rr, math.sin(a) * rr, 0)).Position
			if prev then
				part({ Size = V3(3, 2.5, (pt - prev).Magnitude + 0.5), CFrame = CFrame.lookAt((pt + prev) / 2, pt), Color = col, CanCollide = false, CastShadow = false })
			end
			prev = pt
		end
	end
	for sx = -1, 1, 2 do
		for i = 1, 5 do
			local s = rng:NextNumber(8, 13)
			part({ Shape = BALL, Size = V3(s, s, s), CFrame = cf * CF(sx * (R - 6) + rng:NextNumber(-4, 4), rng:NextNumber(-2, 3), rng:NextNumber(-4, 4)), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
		end
	end
end

-- Декор вокруг трассы. big = true — крупная достопримечательность (колесо, замок и т.п.)
local LANDMARKS = {
	{ ferrisWheel, circusTent, carousel, coaster },
	{ lollipop, candyCane, cupcake, gumdrops },
	{ waterfall, giantMushroom, crystals, crystals },
	{ miniVolcano, lavaRock, lavaRock, miniVolcano },
	{ skyIsland, skyTower, blimp, bigRainbow },
}
local BIG = { [ferrisWheel] = 46, [circusTent] = 34, [carousel] = 30, [coaster] = 44, [miniVolcano] = 40, [waterfall] = 30, [cupcake] = 26, [blimp] = 26, [bigRainbow] = 40 }

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
	Lighting.ShadowSoftness = 0.15 -- чёткие тени
	pcall(function()
		Lighting.Technology = Enum.Technology.Future -- самый чёткий свет (если Roblox разрешит из скрипта)
	end)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.12
	atmo.Offset = 0
	atmo.Color = RGB(200, 225, 255)
	atmo.Decay = RGB(255, 200, 170)
	atmo.Glare = 0
	atmo.Haze = 0.1
	atmo.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 12
	bloom.Threshold = 2.2
	bloom.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.2
	cc.Contrast = 0.14
	cc.Brightness = 0
	cc.TintColor = RGB(255, 252, 245)
	cc.Parent = Lighting
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = 0.02
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- ============ МИР 1: ПАРК РАЗВЛЕЧЕНИЙ (большой парящий остров) ============
-- R — радиус острова, ring — радиус спирали трассы в начале (растёт к краю на ringGrow)
-- lavaY — уровень земли парка (лава течёт по ней реками), top — верх площадок.
-- R — радиус острова; трасса идёт по краю (ring) и чуть закручивается внутрь (ringGrow < 0).
local PARK = { lavaY = 70, top = 84, R = 390, ring = 305, ringGrow = -55, plateaus = {} }
local PARK_STONE = RGB(185, 180, 195)
local PARK_CLIFF = { RGB(135, 125, 150), RGB(115, 105, 130) }

-- ярмарочная палатка с полосатым навесом
local function marketStall(cf, rng, col)
	col = col or pick(rng, { RGB(230, 50, 60), RGB(60, 120, 230), RGB(255, 110, 190) })
	part({ Size = V3(7, 3, 4), CFrame = cf * CF(0, 1.5, 0), Color = RGB(175, 120, 75), Material = M.WoodPlanks })
	part({ Size = V3(7.4, 0.4, 4.4), CFrame = cf * CF(0, 3.2, 0), Color = Color3.new(1, 1, 1) })
	for i = -2, 2 do
		part({ Size = V3(0.9, 0.9, 0.9), CFrame = cf * CF(i * 1.3, 3.85, 0) * CFrame.Angles(0, i, 0), Color = pick(rng, PARTY), CanCollide = false })
	end
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			part({ Size = V3(0.4, 7, 0.4), CFrame = cf * CF(sx * 3.4, 3.5, sz * 1.9), Color = Color3.new(1, 1, 1) })
		end
	end
	local stripes = 6
	local sw = 7.8 / stripes
	for i = 0, stripes - 1 do
		local c = (i % 2 == 0) and col or Color3.new(1, 1, 1)
		local w1 = Instance.new("WedgePart")
		w1.Anchored = true
		w1.Size = V3(sw, 1.8, 2.8)
		w1.CFrame = cf * CF(-3.9 + (i + 0.5) * sw, 7.9, -1.4)
		w1.Color = c
		w1.Parent = currentFolder
		local w2 = w1:Clone()
		w2.CFrame = cf * CF(-3.9 + (i + 0.5) * sw, 7.9, 1.4) * CFrame.Angles(0, PI, 0)
		w2.Parent = currentFolder
	end
	part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = cf * CF(0, 9, 0), Color = RGB(255, 220, 60), Material = M.Neon, CanCollide = false })
end

-- столик под зонтиком
local function umbrellaTable(cf, rng)
	part({ Shape = CYL, Size = V3(0.3, 3.2, 3.2), CFrame = cf * CF(0, 2.4, 0) * ROT_UP, Color = Color3.new(1, 1, 1) })
	part({ Size = V3(0.3, 2.4, 0.3), CFrame = cf * CF(0, 1.2, 0), Color = RGB(80, 80, 90) })
	part({ Size = V3(0.2, 3.5, 0.2), CFrame = cf * CF(0, 4.2, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
	local col = pick(rng, { RGB(255, 110, 190), RGB(230, 50, 60), RGB(60, 150, 255) })
	for k = 0, 2 do
		local d = 7 * (1 - k * 0.32)
		part({ Shape = CYL, Size = V3(0.5, d, d), CFrame = cf * CF(0, 5.6 + k * 0.45, 0) * ROT_UP, Color = (k % 2 == 0) and col or Color3.new(1, 1, 1), CanCollide = false })
	end
	for sx = -1, 1, 2 do
		part({ Shape = CYL, Size = V3(1.4, 1.2, 1.2), CFrame = cf * CF(sx * 2.4, 0.7, 0) * ROT_UP, Color = col })
	end
end

-- указатель со стрелками (фиолетовый неон, как на картинке)
local function arrowSign(cf)
	part({ Size = V3(0.4, 3, 0.4), CFrame = cf * CF(0, 1.5, 0), Color = RGB(70, 60, 90) })
	local p = makeSign(cf * CF(0, 4, 0), V3(5, 2, 0.4), "sign_arrows", RGB(150, 70, 230), RGB(255, 255, 255), Enum.NormalId.Back)
	part({ Size = V3(5.4, 2.4, 0.3), CFrame = p.CFrame * CF(0, 0, 0.1), Color = RGB(220, 120, 255), Material = M.Neon, CanCollide = false })
end

-- круглая площадка-чекпоинт парка: трава, брусчатка, скалы до лавы, ларьки по краям
local function parkPlateau(ctx, stageNum, padX, padTop, padZc, size, isEnd, noProps)
	local rng = Random.new(Config.MAP_SEED + stageNum * 31)
	local cf = L(ctx, padX, padTop, padZc)
	table.insert(PARK.plateaus, { pos = cf.Position, size = size })
	local topPart = part({ Name = "Checkpoint" .. stageNum, Shape = CYL, Size = V3(2, size, size), CFrame = cf * CF(0, -1, 0) * ROT_UP, Color = RGB(115, 210, 85), Material = M.Grass })
	if not isEnd then
		topPart:SetAttribute("Stage", stageNum)
		tag(topPart, "Checkpoint")
		info.checkpoints[stageNum] = topPart
	end
	-- брусчатка: круг в центре + дорожка насквозь
	part({ Shape = CYL, Size = V3(0.2, size * 0.5, size * 0.5), CFrame = cf * CF(0, 0.05, 0) * ROT_UP, Color = PARK_STONE, Material = M.Cobblestone, CanCollide = false })
	part({ Size = V3(8, 0.2, size - 1), CFrame = cf * CF(0, 0.06, 0), Color = PARK_STONE, Material = M.Cobblestone, CanCollide = false })
	if not isEnd then
		local glow = part({ Shape = CYL, Size = V3(0.25, 7, 7), CFrame = cf * CF(0, 0.12, 0) * ROT_UP, Color = RGB(255, 200, 60), Material = M.Neon, CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = Color3.new(0.1, 0.05, 0)
		lbl.Text = tostring(stageNum)
		lbl.Parent = sg
		sg.Parent = glow
	end
	-- скалы под площадкой до лавы
	local s = size
	for i = 1, 3 do
		s *= 0.9
		part({ Shape = CYL, Size = V3(5, s, s), CFrame = cf * CF(rng:NextNumber(-0.6, 0.6), -2 - (i - 0.5) * 5, rng:NextNumber(-0.6, 0.6)) * ROT_UP, Color = PARK_CLIFF[(i % 2) + 1], Material = M.Slate })
	end
	local bottomTop = padTop - 17
	if bottomTop > LAVA_BOTTOM + 1 then
		part({ Shape = CYL, Size = V3(bottomTop - LAVA_BOTTOM, s * 0.85, s * 0.85), CFrame = cf * CF(0, (LAVA_BOTTOM + bottomTop) / 2 - padTop, 0) * ROT_UP, Color = PARK_CLIFF[2], Material = M.Slate })
	end
	-- травяная «кайма» по краю
	part({ Shape = CYL, Size = V3(1.2, size + 0.6, size + 0.6), CFrame = cf * CF(0, -2.2, 0) * ROT_UP, Color = RGB(90, 180, 70), CanCollide = false })
	-- реквизит по бокам (центральный коридор свободен)
	local propsN = noProps and 0 or math.floor(size / 6)
	for i = 1, propsN do
		local side = (i % 2 == 0) and 1 or -1
		local px = side * rng:NextNumber(9.5, size / 2 - 4)
		local pz = rng:NextNumber(-size / 5, size / 5)
		if px * px + pz * pz < (size / 2 - 3) ^ 2 then
			local pcf = cf * CF(px, 0, pz) * CFrame.Angles(0, side > 0 and PI / 2 or -PI / 2, 0)
			local roll = rng:NextNumber()
			if roll < 0.25 then
				marketStall(pcf, rng)
			elseif roll < 0.4 then
				umbrellaTable(pcf, rng)
			elseif roll < 0.55 then
				blockyTree(pcf, rng, rng:NextNumber(0.9, 1.2))
			elseif roll < 0.67 then
				bench(pcf)
			elseif roll < 0.77 then
				popcornStand(pcf, rng)
			elseif roll < 0.85 then
				balloonCart(pcf, rng)
			else
				lamp(pcf)
			end
		end
	end
	-- фонари у выхода и указатель
	for sx = -1, 1, 2 do
		lamp(cf * CF(sx * 5.5, 0, size / 2 - 2.5))
	end
	if not isEnd then
		arrowSign(cf * CF(6.5, 0, size / 2 - 1.5))
	end
	for k = 0, 3 do
		local a = k / 4 * 2 * PI
		addPath((cf * CF(math.cos(a) * size / 2, 0, math.sin(a) * size / 2)).Position)
	end
	addPath(cf.Position)
	return topPart, cf
end

-- ⭐ гигантское колесо обозрения со звездой
local function giantFerrisWheel(base, R)
	local k = R / 48 -- всё растёт вместе с радиусом
	local center = base * CF(0, R + 10 * k, 0)
	local frame = RGB(150, 80, 230)
	for sz = -1, 1, 2 do
		for sx = -1, 1, 2 do
			local foot = (base * CF(sx * R * 0.6, 0, sz * 7 * k)).Position
			local hub = (center * CF(0, 0, sz * 5 * k)).Position
			part({ Size = V3(2.2 * k, 2.2 * k, (hub - foot).Magnitude), CFrame = CFrame.lookAt((foot + hub) / 2, hub), Color = frame, Material = M.Metal })
		end
	end
	part({ Shape = CYL, Size = V3(12 * k, 5 * k, 5 * k), CFrame = center * CFrame.Angles(0, PI / 2, 0), Color = RGB(80, 70, 100), Material = M.Metal })
	-- звезда в центре (крутится вместе с колесом)
	for i = 0, 4 do
		local a = i / 5 * 2 * PI
		rotor(part({ Size = V3(2.2 * k, 9 * k, 1.2 * k), CFrame = center * CF(0, 0, -2.5 * k) * CFrame.Angles(0, 0, a) * CF(0, 4 * k, 0), Color = RGB(255, 220, 60), Material = M.Neon }), center, "z", 0.08)
	end
	local segs = 40
	for ring = 0, 1 do
		local rr = ring == 0 and R or R - 4 * k
		for i = 0, segs - 1 do
			local a0, a1 = i / segs * 2 * PI, (i + 1) / segs * 2 * PI
			for sz = -1, 1, 2 do
				local p0 = (center * CF(math.cos(a0) * rr, math.sin(a0) * rr, sz * 2.5 * k)).Position
				local p1 = (center * CF(math.cos(a1) * rr, math.sin(a1) * rr, sz * 2.5 * k)).Position
				rotor(part({ Size = V3(1.2 * k, 1.2 * k, (p1 - p0).Magnitude + 0.3 * k), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = frame }), center, "z", 0.08)
			end
			if ring == 0 and i % 2 == 0 then
				local bp = (center * CF(math.cos(a0) * (R + 0.8 * k), math.sin(a0) * (R + 0.8 * k), 0)).Position
				rotor(part({ Shape = BALL, Size = V3(1.6 * k, 1.6 * k, 1.6 * k), CFrame = CF(bp), Color = (i % 4 == 0) and RGB(255, 120, 220) or RGB(255, 230, 120), Material = M.Neon }), center, "z", 0.08)
			end
		end
	end
	local cabins = 16
	for i = 0, cabins - 1 do
		local a = i / cabins * 2 * PI
		local rim = (center * CF(math.cos(a) * R, math.sin(a) * R, 0)).Position
		rotor(part({ Size = V3(0.8 * k, 0.8 * k, R), CFrame = CFrame.lookAt((center.Position + rim) / 2, rim), Color = RGB(220, 200, 255), Material = M.Metal }), center, "z", 0.08)
		local col = PARTY[(i % #PARTY) + 1]
		rotor(part({ Size = V3(5 * k, 4 * k, 5 * k), CFrame = CF(rim - V3(0, 4.2 * k, 0)) * center.Rotation, Color = col }), center, "z", 0.08, 4.2 * k)
		rotor(part({ Size = V3(5.6 * k, 0.8 * k, 5.6 * k), CFrame = CF(rim - V3(0, 1.8 * k, 0)) * center.Rotation, Color = col:Lerp(Color3.new(1, 1, 1), 0.4) }), center, "z", 0.08, 1.8 * k)
		rotor(part({ Size = V3(4 * k, 1.6 * k, 0.2 * k), CFrame = CF(rim - V3(0, 4 * k, 0)) * center.Rotation * CF(0, 0, -2.6 * k), Color = RGB(150, 220, 255), Material = M.Neon }), center, "z", 0.08, 4 * k)
	end
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 200, 120)
	l.Range = math.min(60 * k, 60)
	l.Brightness = 2
	l.Parent = part({ Size = V3(1, 1, 1), CFrame = center, Transparency = 1, CanCollide = false })
end

-- 🎢 американские горки с петлёй вокруг части острова
local function parkCoaster(C, a0, a1, rr, baseY, groundY)
	local pts = {}
	local n = 70
	for i = 0, n do
		local t = i / n
		local a = a0 + (a1 - a0) * t
		local y = baseY + 18 + math.sin(t * PI * 4) * 12 + math.sin(t * PI) * 10
		table.insert(pts, V3(C.X + math.cos(a) * rr, y, C.Z + math.sin(a) * rr))
	end
	-- вертикальная петля посередине
	local mid = math.floor(n / 2)
	local p = pts[mid]
	local tangent = (pts[mid + 1] - pts[mid - 1]).Unit
	local outward = V3(p.X - C.X, 0, p.Z - C.Z).Unit
	local loop = {}
	for i = 0, 24 do
		local ph = i / 24 * 2 * PI
		table.insert(loop, p + tangent * (16 * math.sin(ph)) + V3(0, 16 - 16 * math.cos(ph), 0) + outward * (i / 24 * 6))
	end
	local function rails(list, startIdx)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local dir = b - a
			if dir.Magnitude > 0.1 then
				local side = dir:Cross(V3(0, 1, 0))
				if side.Magnitude < 0.01 then
					side = V3(1, 0, 0)
				end
				side = side.Unit * 1.4
				for sgn = -1, 1, 2 do
					local ra, rb = a + side * sgn, b + side * sgn
					part({ Size = V3(0.6, 0.6, (rb - ra).Magnitude + 0.3), CFrame = CFrame.lookAt((ra + rb) / 2, rb), Color = RGB(220, 40, 50), Material = M.Metal })
				end
				part({ Size = V3(3.4, 0.3, 0.5), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(70, 70, 80), Material = M.Metal })
				if (i + startIdx) % 4 == 0 and list == pts then
					local h = a.Y - groundY
					part({ Size = V3(1, h, 1), CFrame = CF(a.X, groundY + h / 2, a.Z), Color = RGB(200, 200, 215), Material = M.Metal })
				end
			end
		end
	end
	rails(pts, 0)
	rails(loop, 0)
	-- вагончики
	for k = 0, 2 do
		local a, b = pts[12 + k * 3], pts[13 + k * 3]
		local cfc = CFrame.lookAt(a, b) * CF(0, 1.4, 0)
		part({ Size = V3(3.2, 1.8, 4), CFrame = cfc, Color = PARTY[k + 1] })
		part({ Size = V3(3.2, 1.2, 0.6), CFrame = cfc * CF(0, 1.4, -1.6), Color = RGB(255, 230, 80) })
	end
end

-- 🗼 башня свободного падения (кольцо с сиденьями ездит вверх-вниз)
local function dropTower(base, h)
	for i = 0, math.floor(h / 6) - 1 do
		part({ Shape = CYL, Size = V3(6, 6, 6), CFrame = base * CF(0, i * 6 + 3, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(150, 80, 230) or Color3.new(1, 1, 1) })
	end
	part({ Shape = CYL, Size = V3(3, 12, 12), CFrame = base * CF(0, h + 1.5, 0) * ROT_UP, Color = RGB(255, 200, 60) })
	local tip = part({ Shape = BALL, Size = V3(4, 4, 4), CFrame = base * CF(0, h + 5, 0), Color = RGB(120, 220, 255), Material = M.Neon })
	local l = Instance.new("PointLight")
	l.Color = RGB(120, 220, 255)
	l.Range = 40
	l.Parent = tip
	local ringBase = base * CF(0, h * 0.5, 0)
	local ring = part({ Shape = CYL, Size = V3(2, 14, 14), CFrame = ringBase * ROT_UP, Color = RGB(255, 80, 120), CanCollide = false })
	table.insert(info.movers, { part = ring, base = ringBase * ROT_UP, axis = V3(0, 1, 0), amp = h * 0.38, speed = 0.7, phase = 0 })
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		local seatBase = ringBase * CF(math.cos(a) * 7.5, -0.5, math.sin(a) * 7.5)
		local seat = part({ Size = V3(1.6, 2, 1.6), CFrame = seatBase, Color = PARTY[(i % #PARTY) + 1], CanCollide = false })
		table.insert(info.movers, { part = seat, base = seatBase, axis = V3(0, 1, 0), amp = h * 0.38, speed = 0.7, phase = 0 })
	end
end

-- 🌋 большой извергающийся вулкан
local function bigVolcano(base, R, H)
	local layers = 9
	for i = 0, layers - 1 do
		local rr = R * (1 - i / (layers + 1.5))
		part({ Shape = CYL, Size = V3(H / layers + 0.5, rr * 2, rr * 2), CFrame = base * CF(0, (i + 0.5) * H / layers, 0) * ROT_UP, Color = darker(RGB(105, 85, 78), 1 - i * 0.04), Material = M.Basalt })
	end
	for k = 0, 5 do
		local a = k / 6 * 2 * PI + 0.3
		local dir = V3(math.cos(a), 0, math.sin(a))
		for i = 0, layers - 2 do
			local rr = R * (1 - (i + 0.5) / (layers + 1.5))
			local pos = base.Position + dir * (rr + 0.3) + V3(0, (i + 0.5) * H / layers, 0)
			part({ Size = V3(3, H / layers + 0.6, 1), CFrame = CFrame.lookAt(pos, pos + dir), Color = RGB(255, 110, 0), Material = M.Neon, CanCollide = false })
		end
	end
	local topR = R * (1 - (layers - 0.5) / (layers + 1.5))
	local crater = part({ Name = "ParkCrater", Shape = CYL, Size = V3(1, topR * 1.6, topR * 1.6), CFrame = base * CF(0, H + 0.3, 0) * ROT_UP, Color = RGB(255, 110, 0), Material = M.Neon })
	local em = Instance.new("ParticleEmitter")
	em.Name = "Eruption"
	em.Color = ColorSequence.new(RGB(255, 230, 80), RGB(255, 50, 0))
	em.LightEmission = 1
	em.Size = NumberSequence.new(4, 1)
	em.Speed = NumberRange.new(50, 80)
	em.SpreadAngle = Vector2.new(20, 20)
	em.Acceleration = V3(0, -45, 0)
	em.Lifetime = NumberRange.new(2.5, 4)
	em.Rate = 12
	em.EmissionDirection = Enum.NormalId.Right
	em.Parent = crater
	tag(crater, "Eruptor")
	local sm = Instance.new("Smoke")
	sm.Size = 40
	sm.Opacity = 0.35
	sm.RiseVelocity = 18
	sm.Color = RGB(50, 45, 45)
	sm.Parent = crater
	local f = Instance.new("Fire")
	f.Size = 20
	f.Heat = 20
	f.Parent = crater
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 120, 40)
	l.Range = 60
	l.Brightness = 3
	l.Parent = crater
end

-- 🏰 замок с фиолетовыми башнями
local function worldTower(cf, dia, h, roofColor, stone)
	part({ Shape = CYL, Size = V3(h, dia, dia), CFrame = cf * CF(0, h / 2, 0) * ROT_UP, Color = stone })
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		part({ Size = V3(1.6, 1.8, 1.6), CFrame = cf * CF(math.cos(a) * dia / 2, h + 0.9, math.sin(a) * dia / 2), Color = stone })
	end
	local layers = 7
	for i = 0, layers - 1 do
		local d = (dia + 1.5) * (1 - i / layers)
		part({ Shape = CYL, Size = V3(1.8, d, d), CFrame = cf * CF(0, h + 2 + i * 1.8, 0) * ROT_UP, Color = (i % 2 == 0) and roofColor or roofColor:Lerp(Color3.new(1, 1, 1), 0.2) })
	end
	local tipY = h + 2 + layers * 1.8
	part({ Size = V3(0.25, 5, 0.25), CFrame = cf * CF(0, tipY + 2, 0), Color = RGB(80, 80, 90) })
	local flag = part({ Size = V3(0.1, 2, 3.4), CFrame = cf * CF(0, tipY + 3.8, 1.75), Color = RGB(230, 50, 80), CanCollide = false })
	flag:SetAttribute("Wave", true)
	for i = 0, 3 do
		local a = i / 4 * 2 * PI + PI / 4
		part({ Size = V3(0.3, 3, 1.4), CFrame = cf * CF(math.cos(a) * dia / 2, h * 0.65, math.sin(a) * dia / 2) * CFrame.Angles(0, -a, 0), Color = RGB(255, 210, 120), Material = M.Neon, CanCollide = false })
	end
end

local function parkCastle(cf)
	local stone = RGB(200, 195, 210)
	local roof = RGB(140, 70, 220)
	part({ Size = V3(44, 16, 34), CFrame = cf * CF(0, 8, 0), Color = stone })
	for i = -10, 10 do
		part({ Size = V3(1.6, 2, 1.6), CFrame = cf * CF(i * 2.1, 17, -17), Color = stone })
	end
	part({ Size = V3(9, 12, 1), CFrame = cf * CF(0, 6, -17.2), Color = RGB(70, 50, 40), Material = M.Wood })
	part({ Size = V3(11, 1.4, 1.4), CFrame = cf * CF(0, 12.6, -17.4), Color = RGB(255, 210, 90), Material = M.Neon })
	for sx = -1, 1, 2 do
		part({ Size = V3(5, 10, 0.3), CFrame = cf * CF(sx * 12, 9, -17.2), Color = RGB(140, 60, 210), CanCollide = false })
		part({ Size = V3(2, 2, 0.35), CFrame = cf * CF(sx * 12, 10, -17.3), Color = RGB(255, 210, 90), Material = M.Neon, CanCollide = false })
	end
	worldTower(cf * CF(-22, 0, -17), 10, 26, roof, stone)
	worldTower(cf * CF(22, 0, -17), 10, 26, roof, stone)
	worldTower(cf * CF(-22, 0, 17), 10, 26, roof, stone)
	worldTower(cf * CF(22, 0, 17), 10, 26, roof, stone)
	worldTower(cf * CF(0, 16, 4), 14, 26, roof, stone)
	worldTower(cf * CF(-10, 16, 10), 7, 18, RGB(220, 80, 200), stone)
	worldTower(cf * CF(10, 16, 10), 7, 18, RGB(220, 80, 200), stone)
end

-- 🏴‍☠️ пиратский корабль в пруду
local function pirateShip(cf)
	local wood, dark = RGB(140, 90, 50), RGB(95, 60, 35)
	part({ Size = V3(12, 7, 30), CFrame = cf * CF(0, 3.5, 0), Color = wood, Material = M.WoodPlanks })
	part({ Size = V3(12.4, 1.2, 30.4), CFrame = cf * CF(0, 7, 0), Color = dark, Material = M.Wood })
	local bow = Instance.new("WedgePart")
	bow.Anchored = true
	bow.Size = V3(12, 7, 9)
	bow.CFrame = cf * CF(0, 3.5, -19.5)
	bow.Color = wood
	bow.Material = M.WoodPlanks
	bow.Parent = currentFolder
	part({ Size = V3(12, 5, 8), CFrame = cf * CF(0, 9.5, 11), Color = wood, Material = M.WoodPlanks })
	for _, mz in ipairs({ -6, 4 }) do
		local mh = 26
		part({ Shape = CYL, Size = V3(mh, 1.2, 1.2), CFrame = cf * CF(0, 7 + mh / 2, mz) * ROT_UP, Color = dark, Material = M.Wood })
		part({ Size = V3(13, 10, 0.4), CFrame = cf * CF(0, 18, mz - 0.6), Color = RGB(25, 25, 30), Material = M.Fabric })
		-- череп и кости
		part({ Shape = BALL, Size = V3(3.2, 3.2, 3.2), CFrame = cf * CF(0, 19, mz - 0.9), Color = Color3.new(1, 1, 1), CanCollide = false })
		for sx = -1, 1, 2 do
			part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = cf * CF(sx * 0.7, 19.3, mz - 2.3), Color = RGB(20, 20, 20), CanCollide = false })
			part({ Size = V3(7, 0.8, 0.2), CFrame = cf * CF(0, 16, mz - 0.9) * CFrame.Angles(0, 0, sx * 0.6), Color = Color3.new(1, 1, 1), CanCollide = false })
		end
		local flag = part({ Size = V3(0.1, 2.2, 3.6), CFrame = cf * CF(0, 7 + mh + 1, mz + 1.8), Color = RGB(20, 20, 20), CanCollide = false })
		flag:SetAttribute("Wave", true)
	end
	for i = -2, 2 do
		part({ Shape = CYL, Size = V3(2, 1, 1), CFrame = cf * CF(6.3, 4.5, i * 4) * CFrame.Angles(0, 0, 0), Color = RGB(30, 30, 35), Material = M.Metal })
	end
end

-- 🛝 водяная горка-труба вокруг башни
local function waterSlide(base, h)
	part({ Size = V3(8, h, 8), CFrame = base * CF(0, h / 2, 0), Color = RGB(80, 170, 255) })
	part({ Size = V3(10, 1, 10), CFrame = base * CF(0, h + 0.5, 0), Color = Color3.new(1, 1, 1) })
	local turns, segs = 2.2, 44
	local prev
	for i = 0, segs do
		local t = i / segs
		local a = t * turns * 2 * PI
		local pt = (base * CF(math.cos(a) * 11, h - t * (h - 3), math.sin(a) * 11)).Position
		if prev then
			part({ Shape = CYL, Size = V3((pt - prev).Magnitude + 0.6, 5, 5), CFrame = CFrame.lookAt((pt + prev) / 2, pt) * CFrame.Angles(0, PI / 2, 0), Color = RGB(190, 120, 255), Material = M.Glass, Transparency = 0.35, CanCollide = false })
		end
		prev = pt
	end
	part({ Shape = CYL, Size = V3(1, 18, 18), CFrame = base * CF(11, 0.6, 0) * ROT_UP, Color = RGB(70, 170, 255), Material = M.Glass, Transparency = 0.15, CanCollide = false })
end

-- 🎠 большая карусель
local function bigCarousel(base)
	part({ Shape = CYL, Size = V3(2.4, 34, 34), CFrame = base * CF(0, 1.2, 0) * ROT_UP, Color = RGB(255, 190, 220) })
	part({ Shape = CYL, Size = V3(0.6, 35, 35), CFrame = base * CF(0, 2.5, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
	part({ Shape = CYL, Size = V3(16, 3, 3), CFrame = base * CF(0, 10, 0) * ROT_UP, Color = GOLD, Material = M.Foil })
	for i = 0, 5 do
		local d = 38 * (1 - i / 6)
		part({ Shape = CYL, Size = V3(1.8, d, d), CFrame = base * CF(0, 18.5 + i * 1.8, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(255, 110, 190) or Color3.new(1, 1, 1) })
	end
	part({ Shape = BALL, Size = V3(3, 3, 3), CFrame = base * CF(0, 30, 0), Color = GOLD, Material = M.Neon })
	for i = 0, 23 do
		local a = i / 24 * 2 * PI
		part({ Shape = BALL, Size = V3(1, 1, 1), CFrame = base * CF(math.cos(a) * 18.6, 18, math.sin(a) * 18.6), Color = (i % 2 == 0) and RGB(255, 230, 120) or RGB(255, 120, 220), Material = M.Neon, CanCollide = false })
	end
	local stand = base * CF(0, 2.5, 0)
	for i = 0, 11 do
		local a = i / 12 * 2 * PI
		local hp = stand * CFrame.Angles(0, a, 0) * CF(0, 0, -12)
		local col = PARTY[(i % #PARTY) + 1]
		rotor(part({ Size = V3(0.4, 15, 0.4), CFrame = hp * CF(0, 7.5, 0), Color = GOLD, Material = M.Foil }), stand, "y", 0.45)
		rotor(part({ Size = V3(1.6, 2.2, 4.4), CFrame = hp * CF(0, 5, 0), Color = Color3.new(1, 1, 1) }), stand, "y", 0.45)
		rotor(part({ Size = V3(1.4, 2.4, 1.6), CFrame = hp * CF(0, 6.6, -2.2) * CFrame.Angles(-0.4, 0, 0), Color = Color3.new(1, 1, 1) }), stand, "y", 0.45)
		rotor(part({ Size = V3(0.5, 1.8, 2), CFrame = hp * CF(0, 6.8, -1), Color = col }), stand, "y", 0.45)
		rotor(part({ Size = V3(1.7, 0.6, 1.6), CFrame = hp * CF(0, 6.2, 0.3), Color = col }), stand, "y", 0.45)
	end
end

-- 🎈 воздушный шар
local function hotAirBalloon(cf, rng)
	local c1, c2 = pick(rng, PARTY), pick(rng, PARTY)
	for i = 0, 5 do
		local a = i / 6 * PI
		local p = part({ Size = V3(16, 18, 3), CFrame = cf * CFrame.Angles(0, a, 0), Color = (i % 2 == 0) and c1 or c2, CanCollide = false, CastShadow = false })
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	part({ Size = V3(4, 3, 4), CFrame = cf * CF(0, -14, 0), Color = RGB(150, 100, 60), Material = M.Wood, CanCollide = false })
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			local a = (cf * CF(sx * 1.8, -12.5, sz * 1.8)).Position
			local b = (cf * CF(sx * 4, -7, sz * 4)).Position
			part({ Size = V3(0.12, 0.12, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RGB(80, 60, 40), CanCollide = false })
		end
	end
end

-- остров под достопримечательность (трава + скалы до лавы)
local function parkIsland(pos, w, d, top, rng, faceCf)
	local cf = faceCf or CF(pos.X, top, pos.Z)
	part({ Size = V3(w, 2, d), CFrame = cf * CF(0, -1, 0), Color = RGB(115, 210, 85) })
	part({ Size = V3(w + 0.6, 1.2, d + 0.6), CFrame = cf * CF(0, -2.2, 0), Color = RGB(90, 180, 70), CanCollide = false })
	local h = top - 2 - LAVA_BOTTOM
	part({ Size = V3(w * 0.94, h, d * 0.94), CFrame = cf * CF(0, LAVA_BOTTOM + h / 2 - top, 0), Color = PARK_CLIFF[1], Material = M.Slate })
	for i = 1, 6 do
		local sx, sz = rng:NextNumber(-w / 2, w / 2), rng:NextNumber(-d / 2, d / 2)
		part({ Size = V3(rng:NextNumber(4, 8), rng:NextNumber(6, 12), rng:NextNumber(4, 8)), CFrame = CF(pos.X + sx, top - 8, pos.Z + sz) * CFrame.Angles(0, rng:NextNumber(0, PI), 0), Color = PARK_CLIFF[2], Material = M.Slate })
	end
	addPath(pos)
	return cf
end

-- 🌄 Великаны на горизонте вокруг парка: огромный вулкан, колесо, замок, острова-горы
local function parkSkyline(C, rng, GY)
	local function polar(a, r)
		return V3(C.X + math.cos(a) * r, 0, C.Z + math.sin(a) * r)
	end
	local function faceCenter(pos, y)
		return CFrame.lookAt(V3(pos.X, y, pos.Z), V3(C.X, y, C.Z))
	end
	-- 🌋 гигантский вулкан из облаков
	local vp = polar(PI / 2, 760)
	bigVolcano(CF(vp.X, GY - 160, vp.Z), 120, 320)
	-- ⭐ гигантское колесо обозрения на острове
	local fp = polar(0.3, 720)
	local fcf = faceCenter(fp, GY + 10)
	floatingIsland(fcf, rng, 170, RGB(110, 205, 80))
	giantFerrisWheel(fcf, 95)
	for _ = 1, 8 do
		blockyTree(fcf * CF(rng:NextNumber(-70, 70), 0, rng:NextNumber(20, 70)), rng, rng:NextNumber(3, 4.5), pick(rng, { RGB(255, 160, 210), RGB(90, 200, 80) }))
	end
	-- 🏰 гигантский замок на острове
	local cp = polar(PI * 0.82, 720)
	local ccf = faceCenter(cp, GY + 20)
	floatingIsland(ccf, rng, 180, RGB(110, 205, 80))
	local castle = Instance.new("Model")
	castle.Name = "GiantCastle"
	castle.Parent = currentFolder
	local prev = currentFolder
	currentFolder = castle
	parkCastle(ccf)
	currentFolder = prev
	castle.WorldPivot = ccf
	castle:ScaleTo(3)
	-- 🏝 острова-горы с водопадами
	for i = 0, 7 do
		local a = i / 8 * 2 * PI + 0.2
		if math.abs(a - PI / 2) > 0.4 and math.abs(a - 0.3) > 0.4 and math.abs(a - PI * 0.82) > 0.4 then
			local p = polar(a, rng:NextNumber(760, 900))
			local icf = CF(p.X, GY + rng:NextNumber(-20, 90), p.Z)
			local size = rng:NextNumber(90, 140)
			floatingIsland(icf, rng, size, pick(rng, { RGB(110, 205, 80), RGB(255, 170, 215) }))
			for _ = 1, 5 do
				blockyTree(icf * CF(rng:NextNumber(-size / 3, size / 3), 0, rng:NextNumber(-size / 3, size / 3)), rng, rng:NextNumber(3, 5), pick(rng, { RGB(255, 160, 210), RGB(90, 200, 80) }))
			end
			waterfallFx(icf.Position + V3(size / 2 - 6, -1, 0), icf.Position + V3(size / 2 - 6, -200, 0), 16)
		end
	end
end

local function buildParkScenery(C, rng, stageFrames)
	local T, GY = PARK.top, PARK.lavaY
	local function polar(a, r)
		return V3(C.X + math.cos(a) * r, 0, C.Z + math.sin(a) * r)
	end
	local function ground(a, r)
		local p = polar(a, r)
		return CF(p.X, GY, p.Z)
	end
	local function faceCenter(pos, y)
		return CFrame.lookAt(V3(pos.X, y, pos.Z), V3(C.X, y, C.Z))
	end
	local busy = {} -- занятые места (чтобы реквизит не залезал на аттракционы)
	local function reserve(pos, r)
		table.insert(busy, { p = pos, r = r })
	end
	local function isFree(pos, r)
		for _, b in ipairs(busy) do
			local dx, dz = b.p.X - pos.X, b.p.Z - pos.Z
			if dx * dx + dz * dz < (b.r + r) ^ 2 then
				return false
			end
		end
		return true
	end

	-- 🌱 земля парка: трава, под ней скалы
	part({ Name = "ParkGround", Shape = CYL, Size = V3(4, PARK.R * 2, PARK.R * 2), CFrame = CF(C.X, GY - 2, C.Z) * ROT_UP, Color = RGB(110, 205, 80), Material = M.Grass })
	local s = PARK.R * 2
	for i = 1, 5 do
		s *= 0.82
		part({ Shape = CYL, Size = V3(14, s, s), CFrame = CF(C.X + rng:NextNumber(-6, 6), GY - 4 - i * 14 + 7, C.Z + rng:NextNumber(-6, 6)) * ROT_UP, Color = PARK_CLIFF[(i % 2) + 1], Material = M.Slate })
	end

	-- 🔥 лавовые реки вдоль трассы и озёра под площадками
	local riverW = 74
	for i, sf in ipairs(stageFrames) do
		if sf.zone == 1 then
			local y = GY + 0.2 + i * 0.01
			local bed = part({ Size = V3(riverW, 0.4, sf.len + 10), CFrame = sf.F * CF(0, y, -sf.len / 2), Color = RGB(235, 70, 10), Material = M.CrackedLava })
			tag(bed, "Lava")
			local glow = part({ Size = V3(riverW - 6, 0.3, sf.len + 4), CFrame = sf.F * CF(0, y + 0.12, -sf.len / 2), Color = RGB(255, 80, 15), Material = M.Neon, Transparency = 0.78, CanCollide = false, CanQuery = false })
			tag(glow, "Lava")
			-- каменные берега
			for sx = -1, 1, 2 do
				part({ Size = V3(2.5, 1.6, sf.len + 10), CFrame = sf.F * CF(sx * (riverW / 2 + 1), GY + 0.6, -sf.len / 2), Color = RGB(150, 140, 160), Material = M.Cobblestone })
			end
		end
	end
	for _, pl in ipairs(PARK.plateaus) do
		local pool = part({ Shape = CYL, Size = V3(0.5, pl.size + 30, pl.size + 30), CFrame = CF(pl.pos.X, GY + 0.25, pl.pos.Z) * ROT_UP, Color = RGB(235, 70, 10), Material = M.CrackedLava })
		tag(pool, "Lava")
		local g2 = part({ Shape = CYL, Size = V3(0.3, pl.size + 26, pl.size + 26), CFrame = CF(pl.pos.X, GY + 0.4, pl.pos.Z) * ROT_UP, Color = RGB(255, 80, 15), Material = M.Neon, Transparency = 0.78, CanCollide = false, CanQuery = false })
		tag(g2, "Lava")
	end
	-- смертельная зона далеко внизу (если упал с острова)
	local kill = part({ Name = "ParkVoid", Size = V3(2400, 4, 2400), CFrame = CF(C.X, GY - 150, C.Z), Transparency = 1, CanCollide = false, CanQuery = false })
	tag(kill, "Lava")

	-- 🏞 каменный обод с деревьями и водопадами в облака
	local segs = 84
	for i = 0, segs - 1 do
		local a = i / segs * 2 * PI
		local p = polar(a, PARK.R + 8)
		local cf = faceCenter(p, GY + 3)
		local wSeg = 2 * PI * (PARK.R + 8) / segs + 1
		part({ Size = V3(wSeg, 2, 18), CFrame = cf * CF(0, -1, 0), Color = RGB(115, 210, 85) })
		part({ Size = V3(wSeg, 30, 16), CFrame = cf * CF(0, -17, 1), Color = PARK_CLIFF[(i % 2) + 1], Material = M.Slate })
		if rng:NextNumber() < 0.6 then
			blockyTree(cf * CF(rng:NextNumber(-wSeg / 3, wSeg / 3), 0, rng:NextNumber(0, 5)), rng, rng:NextNumber(1.1, 1.7), pick(rng, { RGB(80, 190, 70), RGB(255, 160, 210), RGB(100, 210, 80) }))
		end
		if i % 5 == 0 then
			local top = (cf * CF(0, 0, 8)).Position
			waterfallFx(top + V3(0, -1, 0), top + V3(0, -120, 0), 7)
		end
	end
	for _ = 1, 40 do
		local a = rng:NextNumber(0, 2 * PI)
		local r = rng:NextNumber(220, 520)
		local sz = rng:NextNumber(30, 60)
		part({ Shape = BALL, Size = V3(sz, sz, sz), CFrame = CF(C.X + math.cos(a) * r, GY - rng:NextNumber(80, 140), C.Z + math.sin(a) * r), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	end

	-- 🛤 сеть дорожек внутри парка: кольцо + лучи к центру
	local stone = PARK_STONE
	local ringR = 175
	for i = 0, 59 do
		local a0, a1 = i / 60 * 2 * PI, (i + 1) / 60 * 2 * PI
		local p0, p1 = polar(a0, ringR), polar(a1, ringR)
		part({ Size = V3(9, 0.3, (p1 - p0).Magnitude + 1), CFrame = CFrame.lookAt(V3((p0.X + p1.X) / 2, GY + 0.1, (p0.Z + p1.Z) / 2), V3(p1.X, GY + 0.1, p1.Z)), Color = stone, Material = M.Cobblestone, CanCollide = false })
	end
	for k = 0, 5 do
		local a = k / 6 * 2 * PI + 0.25
		local p0, p1 = polar(a, 24), polar(a, ringR)
		part({ Size = V3(8, 0.3, (p1 - p0).Magnitude), CFrame = CFrame.lookAt(V3((p0.X + p1.X) / 2, GY + 0.1, (p0.Z + p1.Z) / 2), V3(p1.X, GY + 0.1, p1.Z)), Color = stone, Material = M.Cobblestone, CanCollide = false })
		for t = 0.3, 0.9, 0.3 do
			local lp = p0:Lerp(p1, t)
			lamp(CF(lp.X, GY, lp.Z) * CF(5.5, 0, 0))
		end
	end

	-- 🎠 центр: карусель на круглой площади
	part({ Shape = CYL, Size = V3(0.4, 52, 52), CFrame = CF(C.X, GY + 0.15, C.Z) * ROT_UP, Color = stone, Material = M.Cobblestone, CanCollide = false })
	bigCarousel(CF(C.X, GY, C.Z))
	reserve(C, 26)
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		lamp(CF(C.X + math.cos(a) * 24, GY, C.Z + math.sin(a) * 24))
	end
	-- ⭐ колесо обозрения
	-- помощник: построить группу и увеличить её целиком
	local function bigger(k, pivot, fn)
		local m = Instance.new("Model")
		m.Parent = currentFolder
		local prev = currentFolder
		currentFolder = m
		fn()
		currentFolder = prev
		m.WorldPivot = pivot
		m:ScaleTo(k)
	end
	local fw = polar(0.45, 135)
	giantFerrisWheel(faceCenter(fw, GY), 64)
	reserve(fw, 70)
	-- 🌋 вулкан сзади + лавовый ручей от него
	local vp = polar(PI / 2, 150)
	bigVolcano(CF(vp.X, GY, vp.Z), 44, 140)
	reserve(vp, 48)
	-- 🗼 башня свободного падения
	local dp = polar(1.0, 85)
	dropTower(CF(dp.X, GY, dp.Z), 130)
	reserve(dp, 12)
	-- 🏰 замок на холме
	local cp = polar(PI * 0.82, 140)
	local cCf = faceCenter(cp, GY)
	bigger(1.7, cCf, function()
		part({ Size = V3(60, 4, 50), CFrame = cCf * CF(0, 2, 0), Color = RGB(115, 210, 85) })
		part({ Size = V3(58, 4, 48), CFrame = cCf * CF(0, -0.2, 0), Color = PARK_CLIFF[1], Material = M.Slate })
		parkCastle(cCf * CF(0, 4, 4))
	end)
	reserve(cp, 58)
	-- 🏴‍☠️ пиратский корабль в пруду
	local sp = polar(PI * 1.22, 140)
	local sCf = faceCenter(sp, GY)
	bigger(1.6, sCf, function()
		part({ Shape = CYL, Size = V3(1, 50, 50), CFrame = sCf * CF(0, 0.3, 0) * ROT_UP, Color = RGB(70, 170, 255), Material = M.Glass, Transparency = 0.15, CanCollide = false })
		part({ Shape = CYL, Size = V3(0.8, 54, 54), CFrame = sCf * CF(0, 0.2, 0) * ROT_UP, Color = stone, Material = M.Cobblestone })
		pirateShip(sCf * CF(0, -1.5, 0) * CFrame.Angles(0, PI / 2, 0))
	end)
	reserve(sp, 44)
	-- 🛝 водяная горка
	local wp = polar(-0.2, 140)
	bigger(1.6, faceCenter(wp, GY), function()
		waterSlide(faceCenter(wp, GY), 32)
	end)
	reserve(wp, 36)
	-- 🎢 горки: дуга по внутреннему кольцу (южная часть)
	parkCoaster(C, PI * 1.38, PI * 1.82, 165, GY + 10, GY)
	for t = 0, 1, 0.1 do
		reserve(polar(PI * 1.38 + (PI * 0.44) * t, 165), 14)
	end
	-- 🎪 шатёр цирка и карусель-чашки
	local tp = polar(PI * 1.55, 88)
	bigger(1.5, CF(tp.X, GY, tp.Z), function()
		circusTent(CF(tp.X, GY, tp.Z), rng, 24)
	end)
	reserve(tp, 26)

	-- 🗼 смотровая башня с винтовой лестницей (можно забраться наверх)
	local lp = polar(-PI / 2 + 0.45, 215)
	local lcf = CF(lp.X, GY, lp.Z)
	local lh = 52
	part({ Shape = CYL, Size = V3(lh, 9, 9), CFrame = lcf * CF(0, lh / 2, 0) * ROT_UP, Color = RGB(200, 190, 215), Material = M.Cobblestone })
	local steps = 44
	for i = 0, steps - 1 do
		local a = i / steps * 4 * PI
		local y = (i + 1) * (lh / steps)
		part({ Size = V3(7, 1, 3.2), CFrame = lcf * CFrame.Angles(0, a, 0) * CF(7.6, y - 0.5, 0), Color = PARTY[(i % #PARTY) + 1] })
	end
	-- верхняя площадка из секторов, с проёмом там, где выходит лестница
	local aLast = ((steps - 1) / steps * 4 * PI) % (2 * PI)
	for i = 0, 15 do
		local a = i / 16 * 2 * PI
		local da = math.abs(((a - aLast + PI) % (2 * PI)) - PI)
		if da > 0.45 then
			part({ Size = V3(10, 1.5, 5.6), CFrame = lcf * CFrame.Angles(0, a, 0) * CF(9, lh + 0.75, 0), Color = RGB(255, 210, 60) })
			part({ Size = V3(0.6, 3.5, 5.2), CFrame = lcf * CFrame.Angles(0, a, 0) * CF(13.6, lh + 3.2, 0), Color = Color3.new(1, 1, 1) })
		end
	end
	local lflag = part({ Size = V3(0.2, 3, 5), CFrame = lcf * CF(0, lh + 14, 2.5), Color = RGB(230, 50, 80), CanCollide = false })
	lflag:SetAttribute("Wave", true)
	part({ Size = V3(0.4, 12, 0.4), CFrame = lcf * CF(0, lh + 7.5, 0), Color = RGB(80, 80, 90) })
	-- 📦 сокровище №2: на самом верху смотровой башни
	treasureChest(lcf * CFrame.Angles(0, aLast + PI, 0) * CF(9, lh + 1.5, 0) * CFrame.Angles(0, PI / 2, 0), 2)
	reserve(lp, 18)

	-- 🦘 площадка с батутами: прыгай по парящим платформам
	local jp = polar(-PI / 2 + 0.8, 215)
	local jcf = CFrame.lookAt(V3(jp.X, GY, jp.Z), V3(C.X, GY, C.Z))
	for i = 0, 3 do
		local pcf = jcf * CF((i - 1.5) * 12, 0, 0)
		local pad = part({ Shape = CYL, Size = V3(0.8, 7, 7), CFrame = pcf * CF(0, 0.4, 0) * ROT_UP, Color = PARTY[i + 1], Material = M.Neon })
		pad:SetAttribute("Launch", V3(0, 85, 0))
		tag(pad, "Bounce")
		part({ Shape = CYL, Size = V3(0.6, 8.4, 8.4), CFrame = pcf * CF(0, 0.3, 0) * ROT_UP, Color = RGB(40, 40, 50) })
	end
	for i = 0, 6 do
		local h = 10 + i * 4
		local a = i / 7 * 2 * PI
		part({ Size = V3(7, 1, 7), CFrame = jcf * CF(math.cos(a) * 10, h, -18 + math.sin(a) * 10), Color = PARTY[(i % #PARTY) + 1] })
	end
	part({ Size = V3(12, 1, 12), CFrame = jcf * CF(0, 40, -18), Color = GOLD, Material = M.Foil })
	coinAt(jcf * CF(0, 43, -18))
	reserve(jp, 32)

	local cup = polar(PI * 0.2, 75)
	teacupRide(CF(cup.X, GY, cup.Z), rng)
	reserve(cup, 9)

	-- 🌳 плотное заполнение: деревья, ларьки, клумбы, лавочки, фонари
	local placed = 0
	for gx = -PARK.R, PARK.R, 9 do
		for gz = -PARK.R, PARK.R, 9 do
			local x, z = gx + rng:NextNumber(-3, 3), gz + rng:NextNumber(-3, 3)
			local r = math.sqrt(x * x + z * z)
			local pos = V3(C.X + x, 0, C.Z + z)
			local ent = PARK.plateaus[1] and PARK.plateaus[1].pos
			local nearEntrance = ent and (V3(ent.X, 0, ent.Z) - pos).Magnitude < 70
			if r < PARK.R - 6 and r > 28 and not nearEntrance and rng:NextNumber() < 0.4 then
				local nearRing = math.abs(r - ringR) < 6
				if not nearRing and farFromPath(pos, riverW / 2 + 6) and isFree(pos, 4) then
					local cf = CF(pos.X, GY, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
					local roll = rng:NextNumber()
					placed += 1
					if roll < 0.2 then
						blockyTree(cf, rng, rng:NextNumber(0.9, 1.5), pick(rng, { RGB(80, 190, 70), RGB(100, 210, 80), RGB(255, 160, 210), RGB(60, 170, 60) }))
					elseif roll < 0.55 then
						bush(cf, rng)
						bush(cf * CF(2, 0, 1), rng)
					elseif roll < 0.68 then
						for _ = 1, 4 do
							flower(cf * CF(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5)), rng)
						end
					elseif roll < 0.76 then
						marketStall(CFrame.lookAt(V3(pos.X, GY, pos.Z), V3(C.X, GY, C.Z)), rng)
						reserve(pos, 5)
					elseif roll < 0.83 then
						umbrellaTable(cf, rng)
					elseif roll < 0.89 then
						bench(cf)
					elseif roll < 0.93 then
						popcornStand(cf, rng)
					elseif roll < 0.96 then
						balloonCart(cf, rng)
					else
						lamp(cf)
					end
				end
			end
		end
	end

	parkSkyline(C, rng, GY)

	-- 🎈 воздушные шары и парящие острова вокруг
	for _ = 1, 6 do
		local a = rng:NextNumber(0, 2 * PI)
		local p = polar(a, rng:NextNumber(60, 300))
		hotAirBalloon(CF(p.X, T + rng:NextNumber(60, 110), p.Z), rng)
	end
	for i = 0, 9 do
		local a = i / 10 * 2 * PI + rng:NextNumber(-0.2, 0.2)
		local p = polar(a, rng:NextNumber(470, 560))
		local icf = CF(p.X, T + rng:NextNumber(-10, 60), p.Z)
		floatingIsland(icf, rng, rng:NextNumber(18, 30), pick(rng, { RGB(110, 205, 80), RGB(255, 170, 215) }))
		blockyTree(icf, rng, 1.3, pick(rng, { RGB(90, 200, 80), RGB(255, 160, 210) }))
		if i % 3 == 0 then
			waterfallFx(icf.Position + V3(8, -1, 0), icf.Position + V3(8, -60, 0), 3)
		end
	end
end

-- ============ ВХОД И ВЫХОД МИРОВ ============
-- Светящаяся стрелка-«галочка» на земле; cf смотрит туда, куда указывает стрелка
local function groundArrow(cf, color)
	color = color or RGB(255, 220, 60)
	for sx = -1, 1, 2 do
		part({ Size = V3(0.7, 0.15, 3.2), CFrame = cf * CF(sx * 0.9, 0.1, 0.6) * CFrame.Angles(0, sx * 0.75, 0), Color = color, Material = M.Neon, CanCollide = false, CanQuery = false, CanTouch = false })
	end
end

-- Дорожка из стрелок от точки a до точки b (обе в мировых координатах, y — высота земли)
local function arrowTrail(a, b, step, color)
	local dist = (b - a).Magnitude
	local n = math.max(1, math.floor(dist / (step or 5)))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		groundArrow(CFrame.lookAt(p, p + (b - a).Unit), color)
	end
end

-- 🎡 Вход в парк: большая площадь с аркой «THE FLOOR IS LAVA», ларьки, магазин
local function parkEntrance(ctx, first)
	local top = ctx.y
	local size = 64
	parkPlateau(ctx, first, 0, top, 0, size, false, true) -- без случайных ларьков: тут путь от портала
	local rng = Random.new(Config.MAP_SEED + 1001)
	-- точка прибытия (со стороны края острова), смотрит на арку
	info.spawnCF[first] = L(ctx, -24, top + 3.5, 0) * CFrame.Angles(0, -PI / 2, 0)
	portalGate(L(ctx, -29, top + 7, 0) * CFrame.Angles(0, -PI / 2, 0), 6, RGB(150, 80, 230), RGB(255, 140, 220), RGB(200, 120, 255))
	-- клетчатая линия старта
	for ix = 0, 3 do
		for iz = 0, 9 do
			part({ Size = V3(1, 0.12, 1.8), CFrame = L(ctx, -15.5 + ix, top + 0.1, -8.1 + iz * 1.8), Color = ((ix + iz) % 2 == 0) and Color3.new(1, 1, 1) or RGB(25, 25, 30), CanCollide = false })
		end
	end
	-- арка с огнём
	local stone = RGB(150, 145, 160)
	for _, sz in ipairs({ -11, 11 }) do
		part({ Size = V3(6, 22, 6), CFrame = L(ctx, -13, top + 11, sz), Color = stone, Material = M.Slate })
		part({ Size = V3(0.4, 9, 3.6), CFrame = L(ctx, -16.1, top + 9, sz), Color = RGB(255, 120, 20), Material = M.Neon })
		local fire = part({ Size = V3(1, 1, 1), CFrame = L(ctx, -16.5, top + 7, sz), Transparency = 1, CanCollide = false })
		local f = Instance.new("Fire")
		f.Size = 5
		f.Heat = 8
		f.Parent = fire
		lamp(L(ctx, -13, top + 22, sz))
	end
	part({ Size = V3(7, 6, 30), CFrame = L(ctx, -13, top + 25, 0), Color = stone, Material = M.Slate })
	makeSign(L(ctx, -16.7, top + 25, 0), V3(0.6, 5.4, 27), "sign_park_title", RGB(60, 45, 70), RGB(255, 170, 40), Enum.NormalId.Left)
	part({ Size = V3(0.4, 6, 29), CFrame = L(ctx, -16.5, top + 25, 0), Color = RGB(255, 130, 30), Material = M.Neon, Transparency = 0.5, CanCollide = false })
	-- ларьки и магазин вокруг площади
	-- ларьки только по бокам: проход от точки появления (−x) и выход к трассе (+z) свободны
	local shop = { -0.35, 0.35, 0.95, -1.0, -1.6, -2.2 }
	for i, a in ipairs(shop) do
		local px, pz = math.cos(a) * 24, math.sin(a) * 24
		local cf = CFrame.lookAt(L(ctx, px, top, pz).Position, L(ctx, 0, top, 0).Position)
		if i == 3 then
			marketStall(cf, rng, RGB(60, 120, 230))
			local counter = part({ Size = V3(6, 0.6, 1), CFrame = cf * CF(0, 3.6, -2.2), Color = RGB(255, 220, 60), Material = M.Neon })
			prompt(counter, "prompt_open", "prompt_shop", "OpenShop", "trails")
			makeSign(cf * CF(0, 11, 0), V3(7, 2.4, 0.5), "sign_shop", RGB(60, 120, 230), Color3.new(1, 1, 1), Enum.NormalId.Front)
		elseif i % 2 == 0 then
			marketStall(cf, rng)
		else
			popcornStand(cf, rng)
		end
	end
	for _, a in ipairs({ -0.75, 0.75, -1.3, -2.0 }) do
		local p = L(ctx, math.cos(a) * 17, top, math.sin(a) * 17)
		local cf = CFrame.lookAt(p.Position, L(ctx, 0, top, 0).Position)
		if rng:NextNumber() < 0.5 then
			umbrellaTable(cf, rng)
		else
			bench(cf)
		end
	end
	balloonCart(L(ctx, 10, top, -18), rng)
	-- 🌉 мост и лестница внутрь парка: там можно гулять, на трассу оттуда не попасть
	local bx0, bx1 = size / 2 - 2, size / 2 + 36
	part({ Size = V3(bx1 - bx0, 1, 10), CFrame = L(ctx, (bx0 + bx1) / 2, top - 0.5, 0), Color = RGB(165, 115, 70), Material = M.WoodPlanks })
	for _, sz in ipairs({ -4.8, 4.8 }) do
		part({ Size = V3(bx1 - bx0, 0.4, 0.4), CFrame = L(ctx, (bx0 + bx1) / 2, top + 2.6, sz), Color = RGB(120, 80, 50), Material = M.Wood })
		for i = 0, 6 do
			part({ Size = V3(0.5, 2.8, 0.5), CFrame = L(ctx, bx0 + i * (bx1 - bx0) / 6, top + 1.4, sz), Color = RGB(120, 80, 50), Material = M.Wood })
		end
	end
	local nSteps = math.ceil(top - PARK.lavaY)
	for i = 1, nSteps do
		local h = top - i
		part({ Size = V3(1.6, math.max(h - PARK.lavaY, 0.2), 10), CFrame = L(ctx, bx1 + (i - 0.5) * 1.6, (h + PARK.lavaY) / 2, 0), Color = PARK_STONE, Material = M.Cobblestone })
	end
	part({ Size = V3(0.5, 6, 0.5), CFrame = L(ctx, bx0, top + 3, 6.5), Color = RGB(120, 80, 50), Material = M.Wood })
	makeSign(L(ctx, bx0, top + 6.6, 6.5), V3(0.4, 2.4, 9), "sign_walk_park", RGB(60, 150, 90), Color3.new(1, 1, 1), Enum.NormalId.Left)

	-- 👉 стрелки: от точки появления через арку к центру и дальше к началу трассы
	arrowTrail(L(ctx, -21, top, 0).Position, L(ctx, -4, top, 0).Position, 4)
	arrowTrail(L(ctx, 0, top, 4).Position, L(ctx, 0, top, size / 2 - 2).Position, 4)
	ctx.x, ctx.y, ctx.z = 0, top, size / 2
end

-- Вход в мир 2–5: площадка с аркой мира и порталом прибытия
local function worldEntry(ctx, w, first)
	local top = ctx.y
	local size = 36
	local pad = part({ Name = "Checkpoint" .. first, Size = V3(size, 2, size), CFrame = L(ctx, 0, top - 1, 0), Color = darker(ACCENT[w], 0.6) })
	pad:SetAttribute("Stage", first)
	tag(pad, "Checkpoint")
	info.checkpoints[first] = pad
	part({ Shape = CYL, Size = V3(0.2, 16, 16), CFrame = L(ctx, 0, top + 0.05, 0) * ROT_UP, Color = ACCENT[w], Material = M.Neon, CanCollide = false })
	if w ~= 5 then
		column(ctx, 0, 0, LAVA_BOTTOM, top - 2, size - 4, size - 4, darker(ACCENT[w], 0.4), M.Slate)
	end
	info.spawnCF[first] = L(ctx, 0, top + 3.5, -10)
	portalGate(L(ctx, 0, top + 7, -16), 6, ACCENT[w], Color3.new(1, 1, 1), ACCENT[w])
	arrowTrail(L(ctx, 0, top, -6).Position, L(ctx, 0, top, size / 2 - 2).Position, 4)
	ctx.x, ctx.y, ctx.z = 0, top, size / 2
	zoneGate(ctx, w)
	addPath(L(ctx, 0, top, 0).Position)
end

-- Конец мира 2–4: площадка без чекпоинта
local function worldEndPad(ctx, x, top, zc, size)
	part({ Size = V3(size, 2, size), CFrame = L(ctx, x, top - 1, zc), Color = RGB(255, 210, 80), Material = M.Foil })
	if not ctx.sky then
		column(ctx, x, zc, LAVA_BOTTOM, top - 2, size - 4, size - 4, RGB(150, 120, 60), M.Slate)
	end
	addPath(L(ctx, x, top, zc).Position)
end

-- Портал «мир пройден → в лобби»
local function worldFinishPortal(ctx, w)
	local top = ctx.y
	local z = ctx.z - 5
	portalGate(L(ctx, 0, top + 8.6, z), 7, RGB(255, 200, 50), RGB(255, 120, 40), RGB(255, 220, 90), "WorldFinish", w)
	makeSign(L(ctx, 0, top + 19, z), V3(22, 6, 1), "sign_world_done", RGB(60, 30, 90), RGB(255, 215, 80), Enum.NormalId.Back)
	makeChest(L(ctx, -8, top, z - 4) * CFrame.Angles(0, PI, 0), "deco_w" .. w, "DecoChest")
	makeChest(L(ctx, 8, top, z - 4) * CFrame.Angles(0, PI, 0), "deco2_w" .. w, "DecoChest")
	local rainbow = { RGB(255, 70, 70), RGB(255, 170, 40), RGB(255, 240, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	for i, c in ipairs(rainbow) do
		local pe = part({ Size = V3(1, 1, 1), CFrame = L(ctx, -12 + (i - 1) * 4.8, top + 0.5, -8), Transparency = 1, CanCollide = false })
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(c)
		em.LightEmission = 0.8
		em.Size = NumberSequence.new(0.5)
		em.Speed = NumberRange.new(22, 30)
		em.SpreadAngle = Vector2.new(15, 15)
		em.Acceleration = V3(0, -20, 0)
		em.Lifetime = NumberRange.new(2, 3)
		em.Rate = 10
		em.EmissionDirection = Enum.NormalId.Top
		em.Parent = pe
	end
end

-- ============ МИР 2: CANDY LAND (огромное лавовое озеро, трасса змейкой) ============
-- Трасса идёт «змейкой»: туда-обратно четырьмя рядами через лавовое озеро,
-- в конце — розовый замок. Вокруг озера — берега с гигантскими сладостями.
local CANDYLAND = { lavaY = 40, top = 54, plateaus = {}, entrance = nil, castle = nil }
local FROST = { RGB(255, 245, 250), RGB(255, 170, 210), RGB(175, 235, 215), RGB(110, 65, 40), RGB(210, 180, 255) }
local SPONGE = RGB(240, 205, 150)
local CHOC = RGB(105, 60, 35)
local WHITE = Color3.new(1, 1, 1)

-- 🎂 капли глазури по краю прямоугольника (cf — центр верхней грани)
local function icingDrips(cf, w, d, color, rng, maxLen)
	for _, side in ipairs({ { 0, -1, w }, { 0, 1, w }, { -1, 0, d }, { 1, 0, d } }) do
		local len = side[3]
		local n = math.floor(len / 2.6)
		for i = 0, n - 1 do
			local t = -len / 2 + (i + 0.5) * len / n
			local h = rng:NextNumber(0.8, maxLen or 3.5)
			local x = side[1] ~= 0 and side[1] * (w / 2 + 0.2) or t
			local z = side[2] ~= 0 and side[2] * (d / 2 + 0.2) or t
			local sx = side[1] ~= 0 and 0.5 or len / n + 0.05
			local sz = side[2] ~= 0 and 0.5 or len / n + 0.05
			part({ Size = V3(sx, h, sz), CFrame = cf * CF(x, -h / 2, z), Color = color, CanCollide = false, CanQuery = false })
			if i % 2 == 0 then
				part({ Shape = BALL, Size = V3(1, 1, 1), CFrame = cf * CF(x, -h, z), Color = color, CanCollide = false, CanQuery = false })
			end
		end
	end
end

local function sprinkles(cf, w, d, n, rng)
	for _ = 1, n do
		part({ Size = V3(0.7, 0.12, 0.22), CFrame = cf * CF(rng:NextNumber(-w / 2 + 0.8, w / 2 - 0.8), 0.06, rng:NextNumber(-d / 2 + 0.8, d / 2 - 0.8)) * CFrame.Angles(0, rng:NextNumber(0, PI), 0), Color = pick(rng, PARTY), CanCollide = false, CanQuery = false })
	end
end

-- 🍓 клубничка / вишенка
local function berry(cf, k, cherry)
	part({ Shape = BALL, Size = V3(2 * k, 2.2 * k, 2 * k), CFrame = cf * CF(0, 1.1 * k, 0), Color = cherry and RGB(200, 20, 40) or RGB(235, 40, 60) })
	if cherry then
		part({ Size = V3(0.15 * k, 1.6 * k, 0.15 * k), CFrame = cf * CF(0.2 * k, 2.8 * k, 0) * CFrame.Angles(0, 0, -0.3), Color = RGB(80, 140, 50), CanCollide = false })
	else
		for i = 0, 4 do
			part({ Size = V3(0.9 * k, 0.15 * k, 0.35 * k), CFrame = cf * CF(0, 2.15 * k, 0) * CFrame.Angles(0, i / 5 * 2 * PI, 0) * CF(0.35 * k, 0, 0), Color = RGB(80, 170, 60), CanCollide = false })
		end
	end
end

-- 🍦 завиток взбитых сливок
local function creamSwirl(cf, k, col)
	col = col or WHITE
	for i = 0, 4 do
		local d = (3.2 - i * 0.6) * k
		part({ Shape = CYL, Size = V3(0.9 * k, d, d), CFrame = cf * CF(0, (0.45 + i * 0.75) * k, 0) * CFrame.Angles(0, i * 0.7, 0) * ROT_UP, Color = col, CanCollide = false })
	end
	part({ Shape = BALL, Size = V3(0.7 * k, 0.9 * k, 0.7 * k), CFrame = cf * CF(0, 4.3 * k, 0), Color = col, CanCollide = false })
end

-- 🍭 леденец на палочке (стоит вертикально), k — масштаб
local function lollipop(cf, k, c1, c2)
	c1, c2 = c1 or RGB(255, 80, 150), c2 or WHITE
	local h = 9 * k
	part({ Shape = CYL, Size = V3(h, 0.6 * k, 0.6 * k), CFrame = cf * CF(0, h / 2, 0) * ROT_UP, Color = WHITE })
	local head = cf * CF(0, h + 2.6 * k, 0)
	part({ Shape = CYL, Size = V3(1 * k, 5.6 * k, 5.6 * k), CFrame = head * CFrame.Angles(0, PI / 2, 0), Color = c2 })
	for i = 1, 3 do
		local d = 5.6 * k * (1 - i * 0.24)
		part({ Shape = CYL, Size = V3(1.02 * k + i * 0.02, d, d), CFrame = head * CFrame.Angles(0, PI / 2, 0), Color = (i % 2 == 1) and c1 or c2, CanCollide = false })
	end
	-- спираль из шариков
	for i = 0, 11 do
		local a = i / 12 * 2 * PI * 1.5
		local rr = (0.4 + i / 12 * 2.1) * k
		part({ Shape = BALL, Size = V3(0.5 * k, 0.5 * k, 0.5 * k), CFrame = head * CF(math.cos(a) * rr, math.sin(a) * rr, -0.55 * k), Color = c1:Lerp(WHITE, 0.2), CanCollide = false })
	end
end

-- 🧁 капкейк
local function cupcake(cf, k, frost)
	frost = frost or RGB(255, 170, 210)
	local n = 14
	for i = 0, n - 1 do
		local a = i / n * 2 * PI
		part({ Size = V3(1.4 * k, 4 * k, 0.6 * k), CFrame = cf * CFrame.Angles(0, a, 0) * CF(0, 2 * k, -2.6 * k) * CFrame.Angles(-0.12, 0, 0), Color = (i % 2 == 0) and RGB(255, 120, 170) or RGB(255, 200, 220) })
	end
	part({ Shape = CYL, Size = V3(4 * k, 5 * k, 5 * k), CFrame = cf * CF(0, 2 * k, 0) * ROT_UP, Color = SPONGE })
	for i = 0, 3 do
		local d = (6.4 - i * 1.3) * k
		part({ Shape = CYL, Size = V3(1.4 * k, d, d), CFrame = cf * CF(0, (4.4 + i * 1.1) * k, 0) * ROT_UP, Color = frost })
	end
	berry(cf * CF(0, 8.2 * k, 0), k * 0.8, true)
	for i = 0, 9 do
		local a = i / 10 * 2 * PI
		part({ Size = V3(0.5 * k, 0.15 * k, 0.2 * k), CFrame = cf * CF(math.cos(a) * 2.6 * k, 5.2 * k + (i % 3) * 0.6 * k, math.sin(a) * 2.6 * k) * CFrame.Angles(0, a, 0.4), Color = PARTY[(i % #PARTY) + 1], CanCollide = false })
	end
end

-- 🍩 огромный пончик (стоит на ребре)
local function giantDonut(cf, R, icing)
	local tube = R * 0.36
	local n = 28
	for i = 0, n - 1 do
		local a = i / n * 2 * PI
		local p = cf * CF(math.cos(a) * R, R + tube + math.sin(a) * R, 0)
		part({ Shape = BALL, Size = V3(tube * 2, tube * 2, tube * 2), CFrame = p, Color = RGB(220, 165, 100), CastShadow = false })
		part({ Shape = BALL, Size = V3(tube * 1.7, tube * 1.7, tube * 1.7), CFrame = p * CF(0, 0, -tube * 0.4), Color = icing, CastShadow = false })
		if i % 2 == 0 then
			part({ Size = V3(tube * 0.4, tube * 0.12, tube * 0.12), CFrame = p * CF(tube * 0.3, tube * 0.2, -tube * 1.2) * CFrame.Angles(0, 0, i), Color = PARTY[(i % #PARTY) + 1], CanCollide = false })
			part({ Size = V3(tube * 0.4, tube * 0.12, tube * 0.12), CFrame = p * CF(-tube * 0.35, -tube * 0.25, -tube * 1.15) * CFrame.Angles(0, 0, -i), Color = PARTY[((i + 2) % #PARTY) + 1], CanCollide = false })
		end
	end
end

-- 🍬 автомат с жвачкой
local function gumballMachine(cf, k)
	part({ Size = V3(10 * k, 3 * k, 10 * k), CFrame = cf * CF(0, 1.5 * k, 0), Color = RGB(220, 30, 40) })
	part({ Size = V3(8 * k, 9 * k, 8 * k), CFrame = cf * CF(0, 7.5 * k, 0), Color = RGB(230, 40, 50) })
	part({ Size = V3(3 * k, 3 * k, 0.6 * k), CFrame = cf * CF(0, 6 * k, -4.2 * k), Color = RGB(200, 200, 210), Material = M.Metal })
	part({ Shape = CYL, Size = V3(0.8 * k, 2 * k, 2 * k), CFrame = cf * CF(0, 9 * k, -4.3 * k) * CFrame.Angles(0, PI / 2, 0), Color = GOLD, Material = M.Foil })
	local globe = cf * CF(0, 18 * k, 0)
	part({ Shape = BALL, Size = V3(17 * k, 17 * k, 17 * k), CFrame = globe, Color = RGB(220, 240, 255), Material = M.Glass, Transparency = 0.55, CastShadow = false })
	local grng = Random.new(77)
	for _ = 1, 40 do
		local v = V3(grng:NextNumber(-1, 1), grng:NextNumber(-1, 0.5), grng:NextNumber(-1, 1))
		if v.Magnitude > 0 then
			v = v.Unit * grng:NextNumber(0, 6 * k)
			part({ Shape = BALL, Size = V3(2.4 * k, 2.4 * k, 2.4 * k), CFrame = globe * CF(v), Color = pick(grng, PARTY), CanCollide = false, CastShadow = false })
		end
	end
	part({ Shape = CYL, Size = V3(2 * k, 6 * k, 6 * k), CFrame = cf * CF(0, 26.5 * k, 0) * ROT_UP, Color = RGB(220, 30, 40) })
	part({ Shape = BALL, Size = V3(2.4 * k, 2.4 * k, 2.4 * k), CFrame = cf * CF(0, 28.5 * k, 0), Color = RGB(220, 30, 40) })
end

-- 🍭 гигантская карамельная трость (арка)
local function giantCane(cf, k)
	local h = 30 * k
	local n = math.floor(h / (2 * k))
	for i = 0, n - 1 do
		part({ Shape = CYL, Size = V3(h / n + 0.05, 3 * k, 3 * k), CFrame = cf * CF(0, (i + 0.5) * h / n, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(230, 30, 50) or WHITE })
	end
	for i = 0, 10 do
		local a = i / 10 * PI
		local p = cf * CF(4 * k - math.cos(a) * 4 * k, h + math.sin(a) * 4 * k, 0)
		part({ Shape = BALL, Size = V3(3.1 * k, 3.1 * k, 3.1 * k), CFrame = p, Color = (i % 2 == 0) and RGB(230, 30, 50) or WHITE, CanCollide = false })
	end
end

-- 🍦 рожок мороженого
local function iceCream(cf, k)
	for i = 0, 5 do
		local d = (1 + i * 1.1) * k
		part({ Shape = CYL, Size = V3(2.2 * k, d, d), CFrame = cf * CF(0, (1 + i * 2) * k, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(225, 165, 90) or RGB(205, 140, 70) })
	end
	local cols = { RGB(255, 170, 210), RGB(175, 235, 215), RGB(255, 245, 230) }
	for i, c in ipairs(cols) do
		part({ Shape = BALL, Size = V3(7 * k, 6.4 * k, 7 * k), CFrame = cf * CF(0, (13 + (i - 1) * 4.6) * k, 0), Color = c })
	end
	berry(cf * CF(0, 24.5 * k, 0), k, true)
end

-- 🌸 сахарная вата на палочке (дерево)
local function cottonTree(cf, rng, k)
	part({ Shape = CYL, Size = V3(8 * k, 0.9 * k, 0.9 * k), CFrame = cf * CF(0, 4 * k, 0) * ROT_UP, Color = RGB(250, 245, 235) })
	local col = pick(rng, { RGB(255, 175, 215), RGB(190, 220, 255), RGB(220, 190, 255) })
	for _ = 1, 6 do
		local s = rng:NextNumber(3.5, 5.5) * k
		part({ Shape = BALL, Size = V3(s, s, s), CFrame = cf * CF(rng:NextNumber(-2, 2) * k, rng:NextNumber(8.5, 11.5) * k, rng:NextNumber(-2, 2) * k), Color = col, CanCollide = false })
	end
end

-- 🏠 пряничный домик
local function gingerHouse(cf, k)
	local gb = RGB(185, 110, 60)
	part({ Size = V3(10 * k, 8 * k, 9 * k), CFrame = cf * CF(0, 4 * k, 0), Color = gb })
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = V3(11.5 * k, 5 * k, 5.4 * k)
		w.CFrame = cf * CF(0, 10.5 * k, side * 2.7 * k) * (side == 1 and CFrame.Angles(0, PI, 0) or CFrame.new())
		w.Color = WHITE
		w.Parent = currentFolder
	end
	part({ Size = V3(2.6 * k, 4.4 * k, 0.4 * k), CFrame = cf * CF(0, 2.2 * k, -4.6 * k), Color = RGB(230, 40, 60) })
	for sx = -1, 1, 2 do
		part({ Size = V3(2 * k, 2 * k, 0.3 * k), CFrame = cf * CF(sx * 3 * k, 5 * k, -4.6 * k), Color = RGB(255, 230, 140), Material = M.Neon })
		part({ Size = V3(0.5 * k, 8 * k, 0.4 * k), CFrame = cf * CF(sx * 5 * k, 4 * k, -4.6 * k), Color = WHITE, CanCollide = false })
	end
	for i = -2, 2 do
		part({ Shape = BALL, Size = V3(1 * k, 1 * k, 1 * k), CFrame = cf * CF(i * 2 * k, 8.2 * k, -4.7 * k), Color = PARTY[i + 3], CanCollide = false })
	end
end

-- 🍫 водопад из «лавы-карамели» (светящийся)
local function caramelFall(top, bottom, width)
	local fall = waterfallFx(top, bottom, width)
	fall.Color = RGB(255, 170, 40)
	return fall
end

-- 🎂 площадка-торт: глазурь, бисквит, крем; на углах — ягоды, сливки и леденцы
local function candyPlateau(ctx, stageNum, padX, padTop, padZc, size, isEnd, noProps)
	local rng = Random.new(Config.MAP_SEED + stageNum * 53)
	local cf = L(ctx, padX, padTop, padZc)
	table.insert(CANDYLAND.plateaus, { pos = cf.Position, size = size })
	local frost = FROST[(stageNum % #FROST) + 1]
	local topPart = part({ Name = "Checkpoint" .. stageNum, Size = V3(size, 1.6, size), CFrame = cf * CF(0, -0.8, 0), Color = frost })
	if not isEnd then
		topPart:SetAttribute("Stage", stageNum)
		tag(topPart, "Checkpoint")
		info.checkpoints[stageNum] = topPart
	end
	icingDrips(cf * CF(0, -0.8, 0), size, size, frost, rng, 4)
	-- слои торта
	part({ Size = V3(size - 0.6, 4, size - 0.6), CFrame = cf * CF(0, -3.6, 0), Color = SPONGE })
	part({ Size = V3(size - 0.4, 1.2, size - 0.4), CFrame = cf * CF(0, -6.2, 0), Color = (frost == CHOC) and WHITE or RGB(255, 210, 230) })
	part({ Size = V3(size - 0.6, 4, size - 0.6), CFrame = cf * CF(0, -8.8, 0), Color = CHOC })
	local bottom = padTop - 10.8
	if bottom > LAVA_BOTTOM then
		part({ Size = V3(size * 0.75, bottom - LAVA_BOTTOM, size * 0.75), CFrame = CF(cf.Position.X, (bottom + LAVA_BOTTOM) / 2, cf.Position.Z) * (cf - cf.Position), Color = RGB(215, 160, 95), Material = M.WoodPlanks })
	end
	sprinkles(cf, size, size, math.floor(size * 0.9), rng)
	-- дорожка из «пастилы» через центр
	part({ Size = V3(7, 0.12, size - 2), CFrame = cf * CF(0, 0.06, 0), Color = RGB(255, 225, 240), CanCollide = false })
	if not isEnd then
		local glow = part({ Shape = CYL, Size = V3(0.25, 7, 7), CFrame = cf * CF(0, 0.14, 0) * ROT_UP, Color = RGB(255, 120, 200), Material = M.Neon, CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = WHITE
		lbl.Text = tostring(stageNum)
		lbl.Parent = sg
		sg.Parent = glow
	end
	-- угловые украшения (центр и дорожки свободны)
	if not noProps then
		local c = size / 2 - 3.2
		local corners = { { -c, -c }, { c, -c }, { -c, c }, { c, c } }
		for i, p in ipairs(corners) do
			local pcf = cf * CF(p[1], 0, p[2])
			local roll = (i + stageNum) % 4
			if roll == 0 then
				berry(pcf, 1.3, false)
			elseif roll == 1 then
				creamSwirl(pcf, 1.1)
			elseif roll == 2 then
				lollipop(pcf, 0.55, pick(rng, { RGB(255, 80, 150), RGB(90, 170, 255), RGB(140, 220, 90) }))
			else
				cupcake(pcf, 0.45)
			end
		end
	end
	for sx = -1, 1, 2 do
		lamp(cf * CF(sx * 5, 0, size / 2 - 2.5))
	end
	if not isEnd then
		arrowSign(cf * CF(6.5, 0, size / 2 - 1.5))
	end
	local h = size / 2
	for _, p in ipairs({ { -h, -h }, { h, -h }, { -h, h }, { h, h }, { 0, 0 } }) do
		addPath((cf * CF(p[1], 0, p[2])).Position)
	end
	return topPart, cf
end

-- 🍭 Вход в Candy Land: площадь-торт, арка из карамельных тростей с вывеской
local function candyEntrance(ctx, first)
	local top = ctx.y
	local size = 60
	candyPlateau(ctx, first, 0, top, 0, size, false, true)
	CANDYLAND.entrance = { cf = L(ctx, 0, top, 0), size = size, top = top }
	info.spawnCF[first] = L(ctx, 0, top + 3.5, -20)
	portalGate(L(ctx, 0, top + 7, -25), 6, RGB(255, 90, 170), WHITE, RGB(255, 140, 220))
	-- арка: две трости и шоколадная вывеска с глазурью
	local archZ = -6
	for sx = -1, 1, 2 do
		local base = L(ctx, sx * 13, top, archZ)
		local n = 12
		for i = 0, n - 1 do
			part({ Shape = CYL, Size = V3(2.2, 4.2, 4.2), CFrame = base * CF(0, 1.1 + i * 2.2, 0) * ROT_UP, Color = (i % 2 == 0) and RGB(230, 30, 50) or WHITE })
		end
		creamSwirl(base * CF(0, 26.4, 0), 1.3)
		lamp(L(ctx, sx * 18, top, archZ - 4))
		lollipop(L(ctx, sx * 22, top, archZ + 6), 1.1, sx < 0 and RGB(255, 80, 150) or RGB(90, 170, 255))
	end
	local boardCf = L(ctx, 0, top + 24, archZ)
	part({ Size = V3(32, 13, 2.5), CFrame = boardCf, Color = CHOC })
	icingDrips(boardCf * CF(0, 6.5, 0), 32, 2.5, WHITE, Random.new(5), 3)
	part({ Size = V3(32.4, 1.4, 2.9), CFrame = boardCf * CF(0, 6.2, 0), Color = WHITE })
	makeSign(boardCf * CF(0, 1.6, -1.35), V3(29, 6, 0.3), "sign_candy_logo", CHOC, RGB(255, 200, 60), Enum.NormalId.Back)
	makeSign(boardCf * CF(0, 1.6, 1.35), V3(29, 6, 0.3), "sign_candy_logo", CHOC, RGB(255, 200, 60), Enum.NormalId.Front)
	local ribbon = boardCf * CF(0, -5.5, 0)
	makeSign(ribbon * CF(0, 0, -1.5), V3(26, 4.4, 0.4), "sign_candy_land", RGB(255, 90, 170), WHITE, Enum.NormalId.Back)
	makeSign(ribbon * CF(0, 0, 1.5), V3(26, 4.4, 0.4), "sign_candy_land", RGB(255, 90, 170), WHITE, Enum.NormalId.Front)
	for _, sx in ipairs({ -1, 1 }) do
		berry(boardCf * CF(sx * 14, 6.9, 0), 1.2, false)
	end
	-- клумбы-конфеты по бокам площади (проход свободен)
	local rng = Random.new(Config.MAP_SEED + 2002)
	for _, p in ipairs({ { -22, -18 }, { 22, -18 }, { -24, 12 }, { 24, 12 }, { -20, 24 }, { 20, 24 } }) do
		local roll = rng:NextNumber()
		local pcf = L(ctx, p[1], top, p[2])
		if roll < 0.35 then
			cupcake(pcf, 0.7)
		elseif roll < 0.65 then
			cottonTree(pcf, rng, 0.9)
		else
			iceCream(pcf, 0.4)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		bench(L(ctx, sx * 10, top, -16) * CFrame.Angles(0, sx * PI / 2, 0))
	end
	arrowTrail(L(ctx, 0, top, -18).Position, L(ctx, 0, top, size / 2 - 2).Position, 4, RGB(255, 140, 220))
	ctx.x, ctx.y, ctx.z = 0, top, size / 2
end

-- 🏰 розовый замок из сладостей за финишной площадкой
local function candyCastle(ccf, k)
	local PINK, PINK2, CONE = RGB(255, 190, 220), RGB(255, 150, 200), RGB(220, 160, 90)
	local ROOF = { RGB(200, 90, 230), RGB(255, 110, 180), RGB(230, 170, 80) }
	-- терраса и парадная лестница (фронт замка — сторона -Z)
	local tW, tD, tH = 120 * k, 80 * k, 12 * k
	part({ Size = V3(tW, tH, tD), CFrame = ccf * CF(0, tH / 2, tD / 2 + 6 * k), Color = PINK })
	icingDrips(ccf * CF(0, tH, tD / 2 + 6 * k), tW, tD, WHITE, Random.new(9), 5 * k)
	local steps = math.floor(tH / 1.2)
	for i = 1, steps do
		part({ Size = V3(26 * k, i * 1.2, 2.2), CFrame = ccf * CF(0, i * 0.6, 6 * k - (steps - i) * 2.2 - 1.1), Color = (i % 2 == 0) and WHITE or RGB(255, 220, 235) })
	end
	local depth = ccf.Position.Y - LAVA_BOTTOM
	part({ Size = V3(tW - 2, depth, tD - 2), CFrame = ccf * CF(0, -depth / 2, tD / 2 + 6 * k), Color = SPONGE })
	part({ Size = V3(tW - 1, 3, tD - 1), CFrame = ccf * CF(0, -6, tD / 2 + 6 * k), Color = CHOC })
	local base = ccf * CF(0, tH, tD / 2 + 6 * k)
	-- 📦 сокровище №3: в углу террасы замка, за башней
	treasureChest(base * CF(-52 * k, 0, -33 * k) * CFrame.Angles(0, PI / 2, 0), 3)
	-- главная башня-торт
	local keepW, keepH = 50 * k, 34 * k
	part({ Size = V3(keepW, keepH, 34 * k), CFrame = base * CF(0, keepH / 2, 4 * k), Color = PINK })
	part({ Size = V3(keepW + 2, 3 * k, 36 * k), CFrame = base * CF(0, keepH, 4 * k), Color = WHITE })
	icingDrips(base * CF(0, keepH - 1, 4 * k), keepW + 2, 36 * k, WHITE, Random.new(11), 4 * k)
	for i = -4, 4 do
		part({ Size = V3(3.5 * k, 4 * k, 3.5 * k), CFrame = base * CF(i * 5.6 * k, keepH + 3.5 * k, 4 * k - 17 * k), Color = PINK2 })
	end
	-- ворота (светятся)
	part({ Size = V3(14 * k, 20 * k, 1), CFrame = base * CF(0, 10 * k, 4 * k - 17 * k - 0.6), Color = WHITE })
	part({ Size = V3(11 * k, 17 * k, 1), CFrame = base * CF(0, 8.5 * k, 4 * k - 17 * k - 1.1), Color = RGB(255, 230, 120), Material = M.Neon })
	for i = -2, 2 do
		if i ~= 0 then
			part({ Size = V3(4 * k, 6 * k, 0.6), CFrame = base * CF(i * 9 * k, 22 * k, 4 * k - 17 * k - 0.4), Color = RGB(255, 235, 150), Material = M.Neon })
		end
	end
	-- верхний ярус + огромный завиток сливок с вишней
	part({ Shape = CYL, Size = V3(16 * k, 30 * k, 30 * k), CFrame = base * CF(0, keepH + 9 * k, 6 * k) * ROT_UP, Color = PINK2 })
	part({ Shape = CYL, Size = V3(2 * k, 32 * k, 32 * k), CFrame = base * CF(0, keepH + 17 * k, 6 * k) * ROT_UP, Color = WHITE })
	creamSwirl(base * CF(0, keepH + 18 * k, 6 * k), 4.5 * k)
	berry(base * CF(0, keepH + 37 * k, 6 * k), 3 * k, true)
	-- башни с конусами-рожками и флагами
	local towers = { { -32, -14, 60, 1 }, { 32, -14, 60, 2 }, { -40, 22, 48, 3 }, { 40, 22, 48, 1 }, { -16, -22, 40, 2 }, { 16, -22, 40, 3 } }
	for _, t in ipairs(towers) do
		local tcf = base * CF(t[1] * k, 0, t[2] * k)
		local h, dia = t[3] * k, 12 * k
		part({ Shape = CYL, Size = V3(h, dia, dia), CFrame = tcf * CF(0, h / 2, 0) * ROT_UP, Color = PINK })
		part({ Shape = CYL, Size = V3(2.4 * k, dia + 2, dia + 2), CFrame = tcf * CF(0, h, 0) * ROT_UP, Color = WHITE })
		for i = 1, 3 do
			part({ Size = V3(2.2 * k, 3.4 * k, 0.6), CFrame = tcf * CF(0, h * (0.35 + i * 0.17), -dia / 2 - 0.2), Color = RGB(255, 235, 150), Material = M.Neon })
		end
		local roofCol = ROOF[t[4]]
		for i = 0, 6 do
			local d = (dia + 2) * (1 - i / 7)
			part({ Shape = CYL, Size = V3(2.6 * k, d, d), CFrame = tcf * CF(0, h + 1.3 * k + i * 2.6 * k, 0) * ROT_UP, Color = (i % 2 == 0) and roofCol or roofCol:Lerp(WHITE, 0.25) })
		end
		local flagTop = h + 20 * k
		part({ Size = V3(0.5, 7 * k, 0.5), CFrame = tcf * CF(0, flagTop, 0), Color = WHITE })
		local flag = part({ Size = V3(5 * k, 3 * k, 0.3), CFrame = tcf * CF(2.5 * k, flagTop + 2 * k, 0), Color = RGB(255, 90, 170), CanCollide = false })
		flag:SetAttribute("Wave", true)
	end
	-- стены между башнями с зубцами
	for _, wseg in ipairs({ { -32, -14, -16, -22 }, { 16, -22, 32, -14 }, { -40, 22, -32, -14 }, { 32, -14, 40, 22 } }) do
		local a = (base * CF(wseg[1] * k, 0, wseg[2] * k)).Position
		local b = (base * CF(wseg[3] * k, 0, wseg[4] * k)).Position
		local len = (b - a).Magnitude
		local wcf = CFrame.lookAt((a + b) / 2, b) * CF(0, 10 * k, 0)
		part({ Size = V3(3 * k, 20 * k, len), CFrame = wcf, Color = PINK2 })
		part({ Size = V3(3.6 * k, 1.6 * k, len), CFrame = wcf * CF(0, 10 * k, 0), Color = WHITE })
	end
	for _, p in ipairs({ { -60, 6 }, { 60, 6 }, { -60, 86 }, { 60, 86 }, { 0, 46 }, { -60, 46 }, { 60, 46 }, { 0, 86 } }) do
		addPath((ccf * CF(p[1] * k, 0, p[2] * k)).Position)
	end
	-- карамельные водопады с террасы в лаву
	for _, sx in ipairs({ -1, 1 }) do
		local tp = (ccf * CF(sx * 45 * k, tH, 6 * k - 0.5)).Position
		caramelFall(tp, V3(tp.X, CANDYLAND.lavaY, tp.Z), 8 * k)
	end
end

-- 🌍 берега, озеро и гигантские сладости вокруг трассы Candy Land
local function buildCandyScenery(C, rng, pFirst, pLast)
	local LY = CANDYLAND.lavaY
	local GY = LY + 4 -- уровень берега
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = pFirst, pLast do
		local p = info.pathPoints[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local margin = 45
	local lx0, lx1, lz0, lz1 = minX - margin, maxX + margin, minZ - margin, maxZ + margin
	local lcx, lcz = (lx0 + lx1) / 2, (lz0 + lz1) / 2
	local lw, ld = lx1 - lx0, lz1 - lz0
	-- 🔥 лавовое озеро
	local lake = part({ Name = "CandyLake", Size = V3(lw, 1, ld), CFrame = CF(lcx, LY - 0.5, lcz), Color = RGB(255, 110, 20), Material = M.CrackedLava })
	tag(lake, "Lava")
	local glow = part({ Size = V3(lw, 0.3, ld), CFrame = CF(lcx, LY + 0.2, lcz), Color = RGB(255, 140, 30), Material = M.Neon, Transparency = 0.72, CanCollide = false, CanQuery = false })
	tag(glow, "Lava")
	local kill = part({ Name = "CandyVoid", Size = V3(2048, 4, 2048), CFrame = CF(lcx, LY - 160, lcz), Transparency = 1, CanCollide = false, CanQuery = false })
	tag(kill, "Lava")
	-- 🌱 берега вокруг озера (мятная «трава» и розовая глазурь по краю)
	local SW = 230
	local MINT = RGB(165, 235, 200)
	local shores = {
		{ lcx, lz0 - SW / 2, lw + SW * 2, SW },
		{ lcx, lz1 + SW / 2, lw + SW * 2, SW },
		{ lx0 - SW / 2, lcz, SW, ld },
		{ lx1 + SW / 2, lcz, SW, ld },
	}
	for _, sh in ipairs(shores) do
		part({ Size = V3(sh[3], 4, sh[4]), CFrame = CF(sh[1], GY - 2, sh[2]), Color = MINT })
		part({ Size = V3(sh[3] - 4, 14, sh[4] - 4), CFrame = CF(sh[1], GY - 11, sh[2]), Color = SPONGE })
		part({ Size = V3(sh[3] - 8, 4, sh[4] - 8), CFrame = CF(sh[1], GY - 20, sh[2]), Color = RGB(255, 200, 225) })
		part({ Size = V3(sh[3] - 12, 24, sh[4] - 12), CFrame = CF(sh[1], GY - 34, sh[2]), Color = CHOC })
	end
	-- глазурь, стекающая с берегов в озеро
	icingDrips(CF(lcx, GY, lcz), lw, ld, RGB(255, 170, 210), rng, 4)
	for _, e in ipairs({ { lcx, lz0, lw, 1 }, { lcx, lz1, lw, 1 }, { lx0, lcz, ld, 0 }, { lx1, lcz, ld, 0 } }) do
		local n = math.floor(e[3] / 70)
		for i = 1, n do
			local t = -e[3] / 2 + i * e[3] / (n + 1)
			local x, z = e[1], e[2]
			if e[4] == 1 then
				x += t
			else
				z += t
			end
			if rng:NextNumber() < 0.5 then
				caramelFall(V3(x, GY, z), V3(x, LY, z), 6)
			end
		end
	end
	-- облака под островом
	for _ = 1, 30 do
		local a = rng:NextNumber(0, 2 * PI)
		local r = rng:NextNumber(200, 600)
		local sz = rng:NextNumber(40, 70)
		part({ Shape = BALL, Size = V3(sz, sz, sz), CFrame = CF(lcx + math.cos(a) * r, LY - rng:NextNumber(90, 150), lcz + math.sin(a) * r), Color = (rng:NextNumber() < 0.3) and RGB(255, 225, 240) or WHITE, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	end

	-- занятость мест
	local busy = {}
	local function isFree(pos, r)
		if pos.X > lx0 - r and pos.X < lx1 + r and pos.Z > lz0 - r and pos.Z < lz1 + r then
			return false -- в озере
		end
		for _, b in ipairs(busy) do
			if (b.p.X - pos.X) ^ 2 + (b.p.Z - pos.Z) ^ 2 < (b.r + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function reserve(pos, r)
		table.insert(busy, { p = pos, r = r })
	end
	local function faceLake(pos)
		return CFrame.lookAt(V3(pos.X, GY, pos.Z), V3(lcx, GY, lcz))
	end
	-- мост от входа на берег: можно погулять по стране сладостей
	if CANDYLAND.entrance then
		local e = CANDYLAND.entrance
		local right = e.cf.RightVector
		local startP = (e.cf * CF(e.size / 2 - 1, 0, 0)).Position
		local len = 0
		for d = 10, 400, 5 do
			local p = startP + right * d
			if p.X < lx0 - 6 or p.X > lx1 + 6 or p.Z < lz0 - 6 or p.Z > lz1 + 6 then
				len = d
				break
			end
		end
		if len > 0 then
			local endP = startP + right * len
			local bcf = CFrame.lookAt((startP + endP) / 2, endP)
			part({ Size = V3(10, 1, len), CFrame = bcf * CF(0, -0.5, 0), Color = RGB(255, 200, 225) })
			for _, sx in ipairs({ -4.8, 4.8 }) do
				local n = math.max(4, math.floor(len / 2))
				for i = 0, n - 1 do
					part({ Shape = CYL, Size = V3(len / n + 0.02, 0.8, 0.8), CFrame = bcf * CF(sx, 2.6, -len / 2 + (i + 0.5) * len / n) * CFrame.Angles(0, PI / 2, 0), Color = (i % 2 == 0) and RGB(230, 30, 50) or WHITE })
				end
				for i = 0, 6 do
					part({ Shape = CYL, Size = V3(2.8, 0.6, 0.6), CFrame = bcf * CF(sx, 1.2, -len / 2 + i * len / 6) * ROT_UP, Color = WHITE })
				end
			end
			-- спуск на берег
			local drop = e.top - GY
			local nS = math.max(1, math.ceil(drop / 1))
			for i = 1, nS do
				local h = e.top - i
				part({ Size = V3(10, math.max(h - (GY - 1), 0.2), 1.6), CFrame = CFrame.lookAt(endP, endP + right) * CF(0, (h + GY - 1) / 2 - e.top, -(i - 0.5) * 1.6), Color = (i % 2 == 0) and WHITE or RGB(255, 220, 235) })
			end
			local sp = startP + right * 2 + V3(0, 7, 0)
			makeSign(CFrame.lookAt(sp, sp - right), V3(9, 2.4, 0.4), "sign_walk_park", RGB(255, 90, 170), WHITE, Enum.NormalId.Front)
			reserve(endP + right * 12, 16)
		end
	end
	-- 🎢 розовые американские горки вдоль дальнего берега
	local pts = {}
	local cz = lz1 + SW * 0.45
	for i = 0, 60 do
		local t = i / 60
		local x = lx0 - SW * 0.5 + t * (lw + SW)
		local y = GY + 22 + math.sin(t * PI * 5) * 12 + math.sin(t * PI * 13) * 3
		local z = cz + math.sin(t * PI * 3) * 30
		table.insert(pts, V3(x, y, z))
	end
	local ok = true
	for _, p in ipairs(pts) do
		if not isFree(p, 2) then
			ok = false
			break
		end
	end
	if ok then
		coasterRails(pts, GY)
		for k = 1, #pts, 3 do
			reserve(pts[k], 8)
		end
	end
	-- 🍰 гигантские сладости вокруг озера: по кругу на берегу
	local giants = {
		function(cf) giantDonut(cf, 30, RGB(255, 150, 200)) end,
		function(cf) gumballMachine(cf, 2.4) end,
		function(cf) lollipop(cf, 5, RGB(255, 80, 150)) end,
		function(cf) cupcake(cf, 4.5, RGB(175, 235, 215)) end,
		function(cf) iceCream(cf, 2.6) end,
		function(cf) giantCane(cf, 2.2) end,
		function(cf) lollipop(cf, 4.2, RGB(90, 170, 255)) end,
		function(cf) cupcake(cf, 3.8, RGB(210, 180, 255)) end,
		function(cf) giantDonut(cf, 24, RGB(110, 65, 40)) end,
		function(cf) gingerHouse(cf, 2.6) end,
		function(cf) lollipop(cf, 4.6, RGB(140, 220, 90)) end,
		function(cf) iceCream(cf, 2.2) end,
	}
	local giantR = { 42, 32, 20, 26, 24, 20, 18, 22, 34, 22, 18, 20 }
	local perim = 2 * (lw + ld)
	local count = 26
	for i = 0, count - 1 do
		local t = (i + 0.5) / count * perim
		local px, pz, nx, nz
		if t < lw then
			px, pz, nx, nz = lx0 + t, lz0, 0, -1
		elseif t < lw + ld then
			px, pz, nx, nz = lx1, lz0 + (t - lw), 1, 0
		elseif t < 2 * lw + ld then
			px, pz, nx, nz = lx1 - (t - lw - ld), lz1, 0, 1
		else
			px, pz, nx, nz = lx0, lz1 - (t - 2 * lw - ld), -1, 0
		end
		local gi = (i % #giants) + 1
		local need = giantR[gi]
		local out = need + 18 + rng:NextNumber(0, 40)
		local pos = V3(px + nx * out, 0, pz + nz * out)
		if isFree(pos, need) then
			reserve(pos, need)
			giants[gi](faceLake(pos))
		end
	end
	-- 🏰 замок пустой не бывает: дальний ряд — горы-мороженое и домики
	for i = 0, 15 do
		local a = i / 16 * 2 * PI
		local dist = math.max(lw, ld) / 2 + SW - 30
		local pos = V3(lcx + math.cos(a) * dist, 0, lcz + math.sin(a) * dist)
		if pos.X > lx0 - SW + 10 and pos.X < lx1 + SW - 10 and pos.Z > lz0 - SW + 10 and pos.Z < lz1 + SW - 10 and isFree(pos, 26) then
			reserve(pos, 26)
			local cf = faceLake(pos)
			if i % 3 == 0 then
				-- гора из шариков мороженого
				local cols = { RGB(255, 170, 210), RGB(175, 235, 215), RGB(255, 245, 230), RGB(210, 180, 255) }
				for k = 0, 3 do
					local s = 46 - k * 9
					part({ Shape = BALL, Size = V3(s, s * 0.85, s), CFrame = cf * CF(rng:NextNumber(-4, 4), 12 + k * 15, rng:NextNumber(-4, 4)), Color = cols[k + 1] })
				end
				berry(cf * CF(0, 68, 0), 4, true)
			elseif i % 3 == 1 then
				gingerHouse(cf, 2)
			else
				giantCane(cf, 1.6)
			end
		end
	end
	-- 🍬 заполнение берегов: немного деревьев-ваты, конфеты, лавочки, фонари
	for gx = lx0 - SW + 10, lx1 + SW - 10, 16 do
		for gz = lz0 - SW + 10, lz1 + SW - 10, 16 do
			local pos = V3(gx + rng:NextNumber(-5, 5), 0, gz + rng:NextNumber(-5, 5))
			if rng:NextNumber() < 0.18 and isFree(pos, 5) then
				reserve(pos, 5)
				local cf = CF(pos.X, GY, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
				local roll = rng:NextNumber()
				if roll < 0.2 then
					cottonTree(cf, rng, rng:NextNumber(1, 1.6))
				elseif roll < 0.45 then
					lollipop(cf, rng:NextNumber(0.6, 1.2), pick(rng, { RGB(255, 80, 150), RGB(90, 170, 255), RGB(140, 220, 90), RGB(255, 170, 40) }))
				elseif roll < 0.6 then
					cupcake(cf, rng:NextNumber(0.6, 1))
				elseif roll < 0.72 then
					berry(cf, rng:NextNumber(1.5, 2.5), false)
				elseif roll < 0.82 then
					creamSwirl(cf, rng:NextNumber(1.2, 2))
				elseif roll < 0.91 then
					bench(cf)
				else
					lamp(cf)
				end
			end
		end
	end
	-- 🍭 леденцы и вафли, торчащие из лавы (далеко от трассы)
	for _ = 1, 60 do
		local pos = V3(rng:NextNumber(lx0 + 10, lx1 - 10), 0, rng:NextNumber(lz0 + 10, lz1 - 10))
		if farFromPath(pos, 26) then
			local cf = CF(pos.X, LY, pos.Z) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 2 * PI), rng:NextNumber(-0.25, 0.25))
			if rng:NextNumber() < 0.6 then
				lollipop(cf, rng:NextNumber(0.8, 1.6), pick(rng, { RGB(255, 80, 150), RGB(90, 170, 255), RGB(255, 170, 40) }))
			else
				local w = rng:NextNumber(6, 10)
				part({ Size = V3(w, 3, w * 0.6), CFrame = cf * CF(0, 1, 0), Color = RGB(225, 175, 105), Material = M.WoodPlanks })
				part({ Size = V3(w + 0.2, 0.5, w * 0.6 + 0.2), CFrame = cf * CF(0, 2.6, 0), Color = pick(rng, { RGB(255, 170, 210), WHITE, CHOC }) })
			end
		end
	end
	-- 🎈 воздушные шары и острова-торты в небе
	for i = 0, 9 do
		local a = i / 10 * 2 * PI + rng:NextNumber(-0.2, 0.2)
		local dist = rng:NextNumber(math.max(lw, ld) * 0.4, math.max(lw, ld) * 0.5 + SW)
		local pos = V3(lcx + math.cos(a) * dist, LY + rng:NextNumber(70, 140), lcz + math.sin(a) * dist)
		if i % 2 == 0 then
			hotAirBalloon(CF(pos) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0), rng)
		else
			local s = rng:NextNumber(26, 40)
			floatingIsland(CF(pos), rng, s, RGB(255, 200, 225))
			cupcake(CF(pos), s / 14, pick(rng, { RGB(255, 170, 210), RGB(175, 235, 215) }))
		end
	end
end

-- ============ ОБЩЕЕ ДЛЯ МИРОВ 4 И 5: летающие острова ============
local VOLC = { lavaY = 30, top = 110, plateaus = {}, entrance = nil }
local SKYK = { cloudY = 70, top = 150, plateaus = {}, entrance = nil }
local GRASS = RGB(105, 190, 70)
local DIRT = RGB(150, 100, 65)
local ROCK = RGB(120, 108, 100)
local WATER = RGB(70, 170, 255)

-- 🌲 ёлка из квадратных ярусов
local function pineTree(cf, k, col)
	col = col or RGB(50, 140, 70)
	part({ Size = V3(1.2 * k, 4 * k, 1.2 * k), CFrame = cf * CF(0, 2 * k, 0), Color = RGB(110, 75, 45), Material = M.Wood })
	for i = 0, 3 do
		local s = (6.5 - i * 1.5) * k
		part({ Size = V3(s, 2.2 * k, s), CFrame = cf * CF(0, (4 + i * 2) * k, 0) * CFrame.Angles(0, i * 0.4, 0), Color = col:Lerp(Color3.new(1, 1, 1), i * 0.04) })
	end
end

-- 🍄 большой гриб
local function bigMushroom(cf, k, capCol)
	capCol = capCol or RGB(220, 40, 40)
	part({ Shape = CYL, Size = V3(5 * k, 1.6 * k, 1.6 * k), CFrame = cf * CF(0, 2.5 * k, 0) * ROT_UP, Color = RGB(245, 235, 220) })
	local cap = part({ Shape = BALL, Size = V3(6 * k, 3.2 * k, 6 * k), CFrame = cf * CF(0, 5.4 * k, 0), Color = capCol })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = cap
	for i = 0, 5 do
		local a = i / 6 * 2 * PI
		part({ Shape = BALL, Size = V3(0.9 * k, 0.5 * k, 0.9 * k), CFrame = cf * CF(math.cos(a) * 1.9 * k, 6.2 * k, math.sin(a) * 1.9 * k), Color = WHITE, CanCollide = false })
	end
end

-- 🍄 плоский оранжевый гриб-дерево (как на небесных островах)
local function flatMushroom(cf, k, capCol)
	capCol = capCol or RGB(255, 170, 40)
	part({ Shape = CYL, Size = V3(7 * k, 0.8 * k, 0.8 * k), CFrame = cf * CF(0, 3.5 * k, 0) * ROT_UP, Color = RGB(245, 230, 200) })
	part({ Shape = CYL, Size = V3(0.9 * k, 4.6 * k, 4.6 * k), CFrame = cf * CF(0, 7.2 * k, 0) * ROT_UP, Color = capCol })
	part({ Shape = CYL, Size = V3(0.6 * k, 3.4 * k, 3.4 * k), CFrame = cf * CF(0, 7.8 * k, 0) * ROT_UP, Color = capCol:Lerp(WHITE, 0.2) })
	part({ Shape = CYL, Size = V3(0.6 * k, 3 * k, 3 * k), CFrame = cf * CF(0.6 * k, 4.6 * k, 0) * ROT_UP, Color = capCol:Lerp(RGB(255, 100, 80), 0.3), CanCollide = false })
end

-- 💎 кристаллы
local function crystalCluster(cf, k, col)
	col = col or RGB(90, 170, 255)
	for i = 1, 6 do
		local h = (2.5 + (i % 3) * 1.6) * k
		local a = i / 6 * 2 * PI
		part({ Size = V3(1.4 * k, h, 1.4 * k), CFrame = cf * CF(math.cos(a) * 1.2 * k, h / 2 - 0.4, math.sin(a) * 1.2 * k) * CFrame.Angles(math.sin(a) * 0.35, a, math.cos(a) * 0.35), Color = col, Material = M.Glass, Transparency = 0.15 })
	end
	local l = Instance.new("PointLight")
	l.Color = col
	l.Range = 12 * k
	l.Parent = part({ Size = V3(1, 1, 1), CFrame = cf * CF(0, 2 * k, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
end

-- 🏛 древние руины: колонны, арка, обломки
local function ruinArch(cf, k)
	local stone = RGB(175, 165, 150)
	for sx = -1, 1, 2 do
		local h = (sx < 0 and 14 or 10) * k
		part({ Size = V3(3 * k, h, 3 * k), CFrame = cf * CF(sx * 6 * k, h / 2, 0), Color = stone, Material = M.Cobblestone })
		part({ Size = V3(3.8 * k, 1 * k, 3.8 * k), CFrame = cf * CF(sx * 6 * k, 0.5 * k, 0), Color = darker(stone, 0.85), Material = M.Slate })
	end
	part({ Size = V3(15 * k, 2.4 * k, 3.4 * k), CFrame = cf * CF(-1 * k, 15 * k, 0) * CFrame.Angles(0, 0, -0.12), Color = stone, Material = M.Slate })
	for i = 1, 4 do
		part({ Size = V3(2.6 * k, 2 * k, 2.4 * k), CFrame = cf * CF((i - 2.5) * 3.5 * k, 1 * k, (i % 2 == 0 and 4 or -4) * k) * CFrame.Angles(0.2 * i, i, 0.1), Color = stone, Material = M.Cobblestone })
	end
	part({ Size = V3(1.2 * k, 3 * k, 1.2 * k), CFrame = cf * CF(-6 * k, 15.5 * k, 0), Color = RGB(80, 160, 60), CanCollide = false })
end

-- 💧 голубой водопад с края острова (с брызгами внизу)
local function blueFall(top, bottom, width)
	local fall = waterfallFx(top, bottom, width)
	fall.Color = RGB(120, 200, 255)
	return fall
end

-- 🏝 большой летающий остров (декор). style: "volcano" | "sky"
-- cf — центр верхней грани, faceDir не важен. Возвращает верхнюю часть.
local function bigIsle(cf, rng, size, style, bottomY)
	local sky = style == "sky"
	local topCol = sky and pick(rng, { RGB(255, 170, 215), RGB(120, 230, 110), RGB(255, 185, 80) }) or GRASS
	local isRound = not sky and rng:NextNumber() < 0.6
	local top
	if isRound then
		top = part({ Shape = CYL, Size = V3(2.4, size, size), CFrame = cf * CF(0, -1.2, 0) * ROT_UP, Color = topCol, Material = M.Grass })
	else
		top = part({ Size = V3(size, 2.4, size), CFrame = cf * CF(0, -1.2, 0), Color = topCol, Material = (sky and topCol ~= RGB(120, 230, 110)) and M.SmoothPlastic or M.Grass })
	end
	if sky then
		-- волнистая «глазурь» по краю
		local n = math.floor(size / 3)
		for _, side in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
			for i = 0, n - 1 do
				local t = -size / 2 + (i + 0.5) * size / n
				local x = side[1] ~= 0 and side[1] * size / 2 or t
				local z = side[2] ~= 0 and side[2] * size / 2 or t
				part({ Shape = BALL, Size = V3(3.4, 3.4, 3.4), CFrame = cf * CF(x, -2.4, z), Color = topCol, CanCollide = false })
			end
		end
	end
	-- скалы под островом, сужаются вниз
	local s = size
	local y = -2.4
	local layers = sky and 4 or 5
	for i = 1, layers do
		local h = math.max(4, size * 0.14)
		s *= 0.8
		local col = sky and ((i % 2 == 0) and RGB(165, 110, 80) or RGB(145, 95, 70)) or ((i % 2 == 0) and ROCK or darker(ROCK, 0.85))
		if isRound then
			part({ Shape = CYL, Size = V3(h, s, s), CFrame = cf * CF(rng:NextNumber(-2, 2), y - h / 2, rng:NextNumber(-2, 2)) * ROT_UP, Color = col, Material = sky and M.SmoothPlastic or M.Slate })
		else
			part({ Size = V3(s, h, s), CFrame = cf * CF(rng:NextNumber(-2, 2), y - h / 2, rng:NextNumber(-2, 2)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), Color = col, Material = sky and M.SmoothPlastic or M.Slate })
		end
		y -= h
	end
	-- украшения на острове
	local n = math.floor(size / 7)
	for _ = 1, n do
		local px, pz = rng:NextNumber(-size * 0.38, size * 0.38), rng:NextNumber(-size * 0.38, size * 0.38)
		local pcf = cf * CF(px, 0, pz) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
		local roll = rng:NextNumber()
		if sky then
			if roll < 0.3 then
				flatMushroom(pcf, rng:NextNumber(1, 1.8), pick(rng, { RGB(255, 170, 40), RGB(255, 140, 60), RGB(255, 200, 70) }))
			elseif roll < 0.5 then
				blockyTree(pcf, rng, rng:NextNumber(1, 1.5), pick(rng, { RGB(90, 210, 70), RGB(60, 190, 80) }))
			elseif roll < 0.75 then
				crystalCluster(pcf, rng:NextNumber(0.8, 1.4), pick(rng, { RGB(110, 170, 255), RGB(140, 200, 255) }))
			else
				bush(pcf, rng)
			end
		else
			if roll < 0.35 then
				pineTree(pcf, rng:NextNumber(1, 1.7))
			elseif roll < 0.55 then
				bigMushroom(pcf, rng:NextNumber(1, 1.8))
			elseif roll < 0.65 then
				crystalCluster(pcf, rng:NextNumber(1, 1.6))
			elseif roll < 0.75 then
				ruinArch(pcf, rng:NextNumber(0.7, 1))
			elseif roll < 0.88 then
				part({ Size = V3(rng:NextNumber(3, 7), rng:NextNumber(2, 4), rng:NextNumber(3, 6)), CFrame = pcf * CF(0, 1, 0), Color = ROCK, Material = M.Slate })
			else
				bush(pcf, rng)
			end
		end
	end
	-- речка через остров и водопад с края
	if size > 40 and rng:NextNumber() < 0.7 then
		local a = rng:NextNumber(0, 2 * PI)
		local dir = V3(math.cos(a), 0, math.sin(a))
		local from = cf.Position - dir * size * 0.2
		local to = cf.Position + dir * (size / 2)
		part({ Size = V3(6, 0.3, (to - from).Magnitude), CFrame = CFrame.lookAt(from, to) * CF(0, 0.05, -(to - from).Magnitude / 2), Color = WATER, Material = M.Glass, Transparency = 0.2, CanCollide = false })
		blueFall(to + V3(0, -0.5, 0), V3(to.X, bottomY or (to.Y - 120), to.Z), 6)
	end
	return top
end

-- 🌉 верёвочный мост-декор между двумя точками (провисает)
local function ropeBridge(a, b)
	local n = math.max(6, math.floor((b - a).Magnitude / 2.2))
	local sag = (b - a).Magnitude * 0.06
	local prev
	for i = 0, n do
		local t = i / n
		local p = a:Lerp(b, t) - V3(0, math.sin(t * PI) * sag, 0)
		if prev then
			local cfp = CFrame.lookAt((prev + p) / 2, p)
			part({ Size = V3(5, 0.4, (p - prev).Magnitude * 0.8), CFrame = cfp, Color = RGB(160, 115, 70), Material = M.WoodPlanks })
			for sx = -1, 1, 2 do
				part({ Size = V3(0.25, 0.25, (p - prev).Magnitude + 0.1), CFrame = cfp * CF(sx * 2.6, 2.2, 0), Color = RGB(200, 170, 120), CanCollide = false })
			end
		end
		prev = p
	end
end

-- 🌋 ПЛОЩАДКА-ОСТРОВ мира 4: трава, скалы, ёлки и грибы по краям
local function islePlateau(ctx, stageNum, padX, padTop, padZc, size, isEnd, noProps)
	local rng = Random.new(Config.MAP_SEED + stageNum * 71)
	local cf = L(ctx, padX, padTop, padZc)
	table.insert(VOLC.plateaus, { cf = cf, size = size })
	local topPart = part({ Name = "Checkpoint" .. stageNum, Shape = CYL, Size = V3(2, size, size), CFrame = cf * CF(0, -1, 0) * ROT_UP, Color = GRASS, Material = M.Grass })
	if not isEnd then
		topPart:SetAttribute("Stage", stageNum)
		tag(topPart, "Checkpoint")
		info.checkpoints[stageNum] = topPart
	end
	part({ Shape = CYL, Size = V3(0.2, size * 0.45, size * 0.45), CFrame = cf * CF(0, 0.05, 0) * ROT_UP, Color = RGB(170, 160, 150), Material = M.Cobblestone, CanCollide = false })
	part({ Size = V3(7, 0.2, size - 1), CFrame = cf * CF(0, 0.06, 0), Color = RGB(170, 160, 150), Material = M.Cobblestone, CanCollide = false })
	-- скалы вниз, сужаются (летающий остров) + каменная опора до лавы
	local s, y = size, -2
	for i = 1, 4 do
		s *= 0.82
		local h = 5
		part({ Shape = CYL, Size = V3(h, s, s), CFrame = cf * CF(rng:NextNumber(-0.8, 0.8), y - h / 2, rng:NextNumber(-0.8, 0.8)) * ROT_UP, Color = (i % 2 == 0) and ROCK or darker(ROCK, 0.85), Material = M.Slate })
		y -= h
	end
	local bottom = padTop + y
	if bottom > LAVA_BOTTOM then
		part({ Size = V3(s * 0.55, bottom - LAVA_BOTTOM, s * 0.55), CFrame = CF(cf.Position.X, (bottom + LAVA_BOTTOM) / 2, cf.Position.Z), Color = RGB(90, 82, 80), Material = M.Slate })
	end
	if not isEnd then
		local glow = part({ Shape = CYL, Size = V3(0.25, 7, 7), CFrame = cf * CF(0, 0.12, 0) * ROT_UP, Color = RGB(255, 140, 40), Material = M.Neon, CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = RGB(40, 20, 0)
		lbl.Text = tostring(stageNum)
		lbl.Parent = sg
		sg.Parent = glow
	end
	if not noProps then
		for i = 1, 4 do
			local a = (i - 0.5) / 4 * 2 * PI + PI / 4
			local pcf = cf * CF(math.cos(a) * (size / 2 - 4), 0, math.sin(a) * (size / 2 - 4))
			local roll = (i + stageNum) % 4
			if roll == 0 then
				pineTree(pcf, 1.1)
			elseif roll == 1 then
				bigMushroom(pcf, 0.9)
			elseif roll == 2 then
				crystalCluster(pcf, 0.9)
			else
				part({ Size = V3(4, 3, 3.5), CFrame = pcf * CF(0, 1.2, 0) * CFrame.Angles(0.2, i, 0.1), Color = ROCK, Material = M.Slate })
				flower(pcf * CF(2.5, 0, 0), rng)
			end
		end
		-- небольшой водопад с края острова (с некоторых площадок)
		if rng:NextNumber() < 0.5 then
			local a = rng:NextNumber() < 0.5 and 0 or PI
			local edge = (cf * CF(math.cos(a) * size / 2, -0.5, 0)).Position
			blueFall(edge, V3(edge.X, VOLC.lavaY, edge.Z), 4)
		end
	end
	for sx = -1, 1, 2 do
		lamp(cf * CF(sx * 5.5, 0, size / 2 - 2.5))
	end
	if not isEnd then
		arrowSign(cf * CF(6.5, 0, size / 2 - 1.5))
	end
	for k = 0, 3 do
		local a = k / 4 * 2 * PI
		addPath((cf * CF(math.cos(a) * size / 2, 0, math.sin(a) * size / 2)).Position)
	end
	addPath(cf.Position)
	return topPart, cf
end

-- ☁️ ПЛОЩАДКА мира 5: квадратный остров с розовой глазурью, травой, грибами и кристаллами
local function skyPlateau(ctx, stageNum, padX, padTop, padZc, size, isEnd, noProps)
	local rng = Random.new(Config.MAP_SEED + stageNum * 83)
	local cf = L(ctx, padX, padTop, padZc)
	table.insert(SKYK.plateaus, { cf = cf, size = size })
	local topCol = ({ RGB(255, 170, 215), RGB(120, 230, 110), RGB(255, 185, 80) })[(stageNum % 3) + 1]
	local topPart = part({ Name = "Checkpoint" .. stageNum, Size = V3(size, 2, size), CFrame = cf * CF(0, -1, 0), Color = topCol })
	if not isEnd then
		topPart:SetAttribute("Stage", stageNum)
		tag(topPart, "Checkpoint")
		info.checkpoints[stageNum] = topPart
	end
	local n = math.floor(size / 3)
	for _, side in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		for i = 0, n - 1 do
			local t = -size / 2 + (i + 0.5) * size / n
			local x = side[1] ~= 0 and side[1] * size / 2 or t
			local z = side[2] ~= 0 and side[2] * size / 2 or t
			part({ Shape = BALL, Size = V3(3, 3, 3), CFrame = cf * CF(x, -2.2, z), Color = topCol, CanCollide = false, CanQuery = false })
		end
	end
	local s, y = size - 1, -2
	for i = 1, 3 do
		s *= 0.8
		part({ Size = V3(s, 4, s), CFrame = cf * CF(0, y - 2, 0) * CFrame.Angles(0, i * 0.3, 0), Color = (i % 2 == 0) and RGB(165, 110, 80) or RGB(145, 95, 70) })
		y -= 4
	end
	-- облачко под островом
	for i = 0, 3 do
		local a = i / 4 * 2 * PI
		part({ Shape = BALL, Size = V3(size * 0.45, size * 0.3, size * 0.45), CFrame = cf * CF(math.cos(a) * size * 0.25, y - 2, math.sin(a) * size * 0.25), Color = (i % 2 == 0) and WHITE or RGB(220, 235, 255), CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	end
	part({ Size = V3(7, 0.12, size - 2), CFrame = cf * CF(0, 0.06, 0), Color = RGB(255, 245, 250), CanCollide = false })
	if not isEnd then
		local glow = part({ Shape = CYL, Size = V3(0.25, 7, 7), CFrame = cf * CF(0, 0.14, 0) * ROT_UP, Color = RGB(120, 200, 255), Material = M.Neon, CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = WHITE
		lbl.Text = tostring(stageNum)
		lbl.Parent = sg
		sg.Parent = glow
	end
	if not noProps then
		local c = size / 2 - 3.5
		for i, p in ipairs({ { -c, -c }, { c, -c }, { -c, c }, { c, c } }) do
			local pcf = cf * CF(p[1], 0, p[2]) * CFrame.Angles(0, i, 0)
			local roll = (i + stageNum) % 4
			if roll == 0 then
				flatMushroom(pcf, 0.9)
			elseif roll == 1 then
				crystalCluster(pcf, 0.8, RGB(110, 170, 255))
			elseif roll == 2 then
				blockyTree(pcf, rng, 1, RGB(90, 210, 70))
			else
				bush(pcf, rng)
				flower(pcf * CF(2, 0, 1), rng)
			end
		end
	end
	for sx = -1, 1, 2 do
		lamp(cf * CF(sx * 5, 0, size / 2 - 2.5))
	end
	if not isEnd then
		arrowSign(cf * CF(6.5, 0, size / 2 - 1.5))
	end
	local h = size / 2
	for _, p in ipairs({ { -h, -h }, { h, -h }, { -h, h }, { h, h }, { 0, 0 } }) do
		addPath((cf * CF(p[1], 0, p[2])).Position)
	end
	return topPart, cf
end

-- 🚪 вход в мир 4/5: большой остров, портал прибытия, арка с названием
local function isleEntrance(ctx, first, style)
	local top = ctx.y
	local size = 60
	if style == "sky" then
		skyPlateau(ctx, first, 0, top, 0, size, false, true)
		SKYK.entrance = L(ctx, 0, top, 0)
	else
		islePlateau(ctx, first, 0, top, 0, size, false, true)
		VOLC.entrance = L(ctx, 0, top, 0)
	end
	info.spawnCF[first] = L(ctx, 0, top + 3.5, -20)
	local pc = style == "sky" and RGB(120, 200, 255) or RGB(255, 120, 40)
	portalGate(L(ctx, 0, top + 7, -25), 6, pc, WHITE, pc)
	-- арка с вывеской
	local archZ = -6
	for sx = -1, 1, 2 do
		local base = L(ctx, sx * 13, top, archZ)
		if style == "sky" then
			for i = 0, 5 do
				part({ Shape = BALL, Size = V3(6 - i * 0.3, 5, 6 - i * 0.3), CFrame = base * CF(0, 2.5 + i * 4, 0), Color = (i % 2 == 0) and WHITE or RGB(220, 235, 255) })
			end
		else
			part({ Size = V3(5, 24, 5), CFrame = base * CF(0, 12, 0), Color = RGB(150, 140, 130), Material = M.Cobblestone })
			local fire = part({ Size = V3(1, 1, 1), CFrame = base * CF(0, 25, 0), Transparency = 1, CanCollide = false })
			local f = Instance.new("Fire")
			f.Size = 5
			f.Heat = 9
			f.Parent = fire
		end
		lamp(L(ctx, sx * 18, top, archZ - 4))
	end
	local boardCf = L(ctx, 0, top + 25, archZ)
	part({ Size = V3(32, 9, 2.5), CFrame = boardCf, Color = style == "sky" and RGB(120, 190, 255) or RGB(90, 70, 60), Material = style == "sky" and M.SmoothPlastic or M.Slate })
	local key = style == "sky" and "sign_sky_title" or "sign_isles_title"
	local fg = style == "sky" and WHITE or RGB(255, 190, 60)
	local bg = style == "sky" and RGB(90, 150, 240) or RGB(60, 45, 40)
	makeSign(boardCf * CF(0, 0, -1.35), V3(29, 6.5, 0.3), key, bg, fg, Enum.NormalId.Back)
	makeSign(boardCf * CF(0, 0, 1.35), V3(29, 6.5, 0.3), key, bg, fg, Enum.NormalId.Front)
	if style == "sky" then
		-- радуга над аркой
		local cols = { RGB(255, 60, 60), RGB(255, 160, 40), RGB(255, 235, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
		for b, c in ipairs(cols) do
			local R = 22 - b * 1.2
			for i = 0, 17 do
				local a0, a1 = i / 18 * PI, (i + 1) / 18 * PI
				local p0 = (boardCf * CF(math.cos(a0) * R, math.sin(a0) * R + 3, 0)).Position
				local p1 = (boardCf * CF(math.cos(a1) * R, math.sin(a1) * R + 3, 0)).Position
				part({ Size = V3(1.25, 1.2, (p1 - p0).Magnitude + 0.2), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = c, CanCollide = false })
			end
		end
	else
		ruinArch(L(ctx, -22, top, 14) * CFrame.Angles(0, 0.4, 0), 0.8)
	end
	local rng = Random.new(Config.MAP_SEED + (style == "sky" and 5050 or 4040))
	for _, p in ipairs({ { -22, -18 }, { 22, -18 }, { 24, 12 }, { -20, 24 }, { 20, 24 } }) do
		local pcf = L(ctx, p[1], top, p[2]) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
		if style == "sky" then
			if rng:NextNumber() < 0.5 then
				flatMushroom(pcf, 1.3)
			else
				crystalCluster(pcf, 1.2, RGB(110, 170, 255))
			end
		else
			if rng:NextNumber() < 0.5 then
				pineTree(pcf, 1.4)
			else
				bigMushroom(pcf, 1.2)
			end
		end
	end
	arrowTrail(L(ctx, 0, top, -18).Position, L(ctx, 0, top, size / 2 - 2).Position, 4, style == "sky" and RGB(120, 200, 255) or RGB(255, 200, 60))
	ctx.x, ctx.y, ctx.z = 0, top, size / 2
end

-- маленький секретный островок с сундуком: от площадки ведут камни-ступеньки в сторону
local function hiddenNook(plateau, n, style)
	local cf, size = plateau.cf, plateau.size
	for _, sgn in ipairs({ 1, -1 }) do
		local dir = cf.RightVector * sgn
		local islePos = cf.Position + dir * (size / 2 + 26)
		if farFromPath(islePos, 16) and farFromPath(cf.Position + dir * (size / 2 + 12), 9) then
			for i = 1, 3 do
				local p = cf.Position + dir * (size / 2 + 1 + i * 6)
				if style == "sky" then
					part({ Shape = CYL, Size = V3(1.4, 4, 4), CFrame = CF(p + V3(0, -0.7 + i * 0.6, 0)) * ROT_UP, Color = WHITE })
				else
					part({ Size = V3(4, 1.4, 4), CFrame = CF(p + V3(0, -0.7 + i * 0.6, 0)) * CFrame.Angles(0, i, 0), Color = ROCK, Material = M.Slate })
				end
			end
			local icf = CFrame.lookAt(islePos + V3(0, 2.4, 0), cf.Position + V3(0, 2.4, 0))
			bigIsle(icf, Random.new(n * 13), 12, style, style == "sky" and (SKYK.cloudY) or VOLC.lavaY)
			treasureChest(icf * CF(0, 0, 2), n)
			if style == "sky" then
				flatMushroom(icf * CF(-4, 0, 3), 0.8)
			else
				crystalCluster(icf * CF(-4, 0, 3), 1, RGB(90, 170, 255))
				crystalCluster(icf * CF(4, 0, 3), 0.8, RGB(170, 100, 255))
			end
			addPath(islePos)
			return true
		end
	end
	return false
end

-- 🌋 огромные острова, мосты, вулкан и закатные горы вокруг трассы мира 4
local function buildIslesScenery(rng, pFirst, pLast, endCF)
	local LY = VOLC.lavaY
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = pFirst, pLast do
		local p = info.pathPoints[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local ext = math.max(maxX - minX, maxZ - minZ)
	-- 🔥 лавовое море
	for ix = -1, 1 do
		for iz = -1, 1 do
			local sea = part({ Name = "IslesLava", Size = V3(2000, 1, 2000), CFrame = CF(cx + ix * 2000, LY - 0.5, cz + iz * 2000), Color = RGB(255, 100, 20), Material = M.CrackedLava })
			tag(sea, "Lava")
			local glow = part({ Size = V3(2000, 0.3, 2000), CFrame = CF(cx + ix * 2000, LY + 0.2, cz + iz * 2000), Color = RGB(255, 120, 30), Material = M.Neon, Transparency = 0.75, CanCollide = false, CanQuery = false })
			tag(glow, "Lava")
		end
	end
	-- 🌋 огромный вулкан за финишем
	if endCF then
		local vp = (endCF * CF(0, 0, -200)).Position
		local base = CF(vp.X, LY, vp.Z)
		bigVolcano(base, 170, 260)
		for i = 0, 5 do
			local a = i / 6 * 2 * PI + 0.2
			local p = base.Position + V3(math.cos(a) * 60, 230, math.sin(a) * 60)
			local fall = caramelFall(p, V3(p.X, LY, p.Z), 7)
			fall.Color = RGB(255, 110, 0)
		end
		-- огромный столб дыма из шаров
		for i = 0, 7 do
			local s = 40 + i * 14
			part({ Shape = BALL, Size = V3(s, s, s), CFrame = base * CF(math.sin(i) * 12 + i * 6, 290 + i * 34, math.cos(i) * 10), Color = RGB(70 + i * 6, 65 + i * 6, 70 + i * 6), Transparency = 0.15 + i * 0.07, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
		end
		addPath(vp)
	end
	-- 🏝 большие острова по обе стороны трассы
	local isles = {}
	for _ = 1, 140 do
		if #isles >= 22 then
			break
		end
		local pos = V3(rng:NextNumber(minX - 220, maxX + 220), 0, rng:NextNumber(minZ - 220, maxZ + 220))
		local size = rng:NextNumber(40, 95)
		if farFromPath(pos, size / 2 + 26) then
			local ok = true
			for _, il in ipairs(isles) do
				if (il.p - pos).Magnitude < (il.s + size) / 2 + 20 then
					ok = false
					break
				end
			end
			if ok then
				local y = VOLC.top + rng:NextNumber(-40, 25)
				local icf = CF(pos.X, y, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
				bigIsle(icf, rng, size, "volcano", LY)
				-- опорная колонна-скала до лавы (как на картинке)
				if rng:NextNumber() < 0.5 then
					part({ Size = V3(size * 0.25, y - 30 - LY, size * 0.25), CFrame = CF(pos.X, (y - 30 + LY) / 2, pos.Z), Color = darker(ROCK, 0.8), Material = M.Slate })
				end
				-- пещера с синими кристаллами
				if rng:NextNumber() < 0.35 then
					local ccf = icf * CF(0, 0, 0)
					part({ Size = V3(18, 14, 12), CFrame = ccf * CF(0, 7, 0), Color = darker(ROCK, 0.7), Material = M.Slate })
					part({ Size = V3(10, 9, 6), CFrame = ccf * CF(0, 4.5, -4), Color = RGB(25, 20, 35) })
					crystalCluster(ccf * CF(-2, 0, -6.5), 1.3, RGB(90, 170, 255))
					crystalCluster(ccf * CF(3, 0, -6.5), 1, RGB(140, 110, 255))
				end
				table.insert(isles, { p = V3(pos.X, y, pos.Z), s = size })
			end
		end
	end
	-- 🌉 мосты между соседними островами
	for i = 1, #isles do
		for j = i + 1, #isles do
			local a, b = isles[i], isles[j]
			local d = (V3(a.p.X, 0, a.p.Z) - V3(b.p.X, 0, b.p.Z)).Magnitude
			local gap = d - (a.s + b.s) / 2
			if gap > 10 and gap < 70 and math.abs(a.p.Y - b.p.Y) < 25 then
				local dir = (V3(b.p.X, 0, b.p.Z) - V3(a.p.X, 0, a.p.Z)).Unit
				local pa = a.p + dir * (a.s / 2 - 2)
				local pb = b.p - dir * (b.s / 2 - 2)
				local mid = (pa + pb) / 2
				if farFromPath(V3(mid.X, 0, mid.Z), 25) then
					ropeBridge(pa, pb)
				end
			end
		end
	end
	-- ☁️ маленькие острова в небе и горы на закате вокруг
	for _ = 1, 16 do
		local pos = V3(rng:NextNumber(minX - 300, maxX + 300), VOLC.top + rng:NextNumber(60, 160), rng:NextNumber(minZ - 300, maxZ + 300))
		if farFromPath(pos, 40) then
			local s = rng:NextNumber(14, 26)
			bigIsle(CF(pos), rng, s, "volcano", pos.Y - 200)
		end
	end
	for i = 0, 23 do
		local a = i / 24 * 2 * PI
		local r = ext / 2 + 650 + rng:NextNumber(-60, 60)
		local h = rng:NextNumber(160, 320)
		local w = rng:NextNumber(140, 240)
		local base = CF(cx + math.cos(a) * r, LY, cz + math.sin(a) * r)
		for k = 0, 3 do
			local s = w * (1 - k * 0.22)
			part({ Size = V3(s, h / 4 + 1, s), CFrame = base * CF(0, (k + 0.5) * h / 4, 0) * CFrame.Angles(0, a + k * 0.3, 0), Color = RGB(130 - k * 8, 95 - k * 6, 120 - k * 4), Material = M.Slate, CastShadow = false })
		end
	end
	-- 📦 сундук-сокровище №4: на тайном островке у площадки 35
	local pl = VOLC.plateaus[6] or VOLC.plateaus[#VOLC.plateaus]
	if pl then
		hiddenNook(pl, 4, "volcano")
	end
end

-- 🌈 огромная радуга
local function giantRainbow(cf, R)
	local cols = { RGB(255, 60, 60), RGB(255, 160, 40), RGB(255, 235, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	local band = R * 0.07
	for b, c in ipairs(cols) do
		local rr = R - (b - 1) * band
		local n = 30
		for i = 0, n - 1 do
			local a0, a1 = i / n * PI, (i + 1) / n * PI
			local p0 = (cf * CF(math.cos(a0) * rr, math.sin(a0) * rr, 0)).Position
			local p1 = (cf * CF(math.cos(a1) * rr, math.sin(a1) * rr, 0)).Position
			part({ Size = V3(band * 1.6, band, (p1 - p0).Magnitude + 0.4), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = c, CanCollide = false, CastShadow = false, CanQuery = false })
		end
	end
	for sx = -1, 1, 2 do
		for i = 0, 5 do
			local s = R * 0.22 * (1 - i * 0.08)
			part({ Shape = BALL, Size = V3(s, s * 0.8, s), CFrame = cf * CF(sx * (R - band * 2.5) + (i - 2.5) * s * 0.35, s * 0.2, (i % 2) * s * 0.3), Color = (i % 2 == 0) and WHITE or RGB(225, 238, 255), CanCollide = false, CastShadow = false, CanQuery = false })
		end
	end
end

-- 🛩 дирижабль, который летает по кругу (анимирует клиент как «ротор»)
local function flyingBlimp(center, radius, height, k, speed, startAngle)
	local holder = Instance.new("Model")
	holder.Name = "Blimp"
	local prev = currentFolder
	currentFolder = holder
	local a = startAngle or 0
	local pos = center.Position + V3(math.cos(a) * radius, height, math.sin(a) * radius)
	local tangent = V3(-math.sin(a), 0, math.cos(a))
	local cf = CFrame.lookAt(pos, pos + tangent)
	egg(V3(10 * k, 10 * k, 26 * k), cf, RGB(255, 140, 50))
	for i = -2, 2 do
		egg(V3(10.3 * k, 10.3 * k, 2.4 * k), cf * CF(0, 0, i * 4 * k), (i % 2 == 0) and RGB(255, 210, 60) or RGB(170, 120, 255))
	end
	part({ Size = V3(3.4 * k, 2.4 * k, 7 * k), CFrame = cf * CF(0, -6 * k, 0), Color = RGB(60, 120, 255) })
	for i = -1, 1 do
		part({ Size = V3(3.5 * k, 0.8 * k, 1.2 * k), CFrame = cf * CF(0, -6 * k, i * 2 * k), Color = RGB(255, 240, 160), Material = M.Neon })
	end
	for _, ang in ipairs({ 0, PI / 2, PI, -PI / 2 }) do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = V3(0.6 * k, 4.5 * k, 4.5 * k)
		w.CFrame = cf * CF(0, 0, 12 * k) * CFrame.Angles(0, 0, ang) * CF(0, 4.5 * k, 0) * CFrame.Angles(0, PI, 0)
		w.Color = RGB(60, 120, 255)
		w.Parent = holder
	end
	currentFolder = prev
	for _, p in ipairs(holder:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CastShadow = false
			rotor(p, center, "y", speed)
		end
	end
	holder.Parent = currentFolder
end

-- ☁️ облака, острова-конфетки, радуги, дирижабли и речки мира 5
local function buildSkyScenery(rng, pFirst, pLast)
	local CY = SKYK.cloudY
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = pFirst, pLast do
		local p = info.pathPoints[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local ext = math.max(maxX - minX, maxZ - minZ)
	-- смерть при падении в облака
	for ix = -1, 1 do
		for iz = -1, 1 do
			local kill = part({ Name = "SkyVoid", Size = V3(2000, 4, 2000), CFrame = CF(cx + ix * 2000, CY - 25, cz + iz * 2000), Transparency = 1, CanCollide = false, CanQuery = false })
			tag(kill, "Lava")
		end
	end
	-- ☁️ море облаков (розовые, голубые, белые)
	local cloudCols = { WHITE, WHITE, RGB(255, 210, 235), RGB(200, 225, 255), RGB(170, 210, 255) }
	for _ = 1, 260 do
		local x = rng:NextNumber(minX - 500, maxX + 500)
		local z = rng:NextNumber(minZ - 500, maxZ + 500)
		local s = rng:NextNumber(50, 110)
		part({ Shape = BALL, Size = V3(s, s * 0.6, s), CFrame = CF(x, CY + rng:NextNumber(-10, 12), z), Color = pick(rng, cloudCols), CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	end
	-- 🏝 большой центральный луг с четырьмя розовыми островами по углам (как на картинке)
	local function findSpot(minDist, tries)
		for _ = 1, tries do
			local p = V3(rng:NextNumber(minX - 200, maxX + 200), 0, rng:NextNumber(minZ - 200, maxZ + 200))
			if farFromPath(p, minDist) then
				return p
			end
		end
		return nil
	end
	local busyIsles = {}
	local mp = findSpot(140, 300)
	if mp then
		local my = SKYK.top - 10
		local mcf = CF(mp.X, my, mp.Z)
		part({ Size = V3(180, 3, 180), CFrame = mcf * CF(0, -1.5, 0), Color = RGB(110, 225, 90) })
		part({ Size = V3(176, 10, 176), CFrame = mcf * CF(0, -8, 0), Color = RGB(150, 100, 70) })
		part({ Size = V3(140, 12, 140), CFrame = mcf * CF(0, -19, 0), Color = RGB(135, 90, 65) })
		part({ Size = V3(90, 12, 90), CFrame = mcf * CF(0, -31, 0), Color = RGB(120, 80, 60) })
		for _, c in ipairs({ { -62, -62 }, { 62, -62 }, { -62, 62 }, { 62, 62 } }) do
			local icf = mcf * CF(c[1], 14, c[2])
			bigIsle(icf, rng, 52, "sky", CY)
			part({ Size = V3(50, 14, 50), CFrame = mcf * CF(c[1], 7, c[2]), Color = RGB(160, 105, 75) })
		end
		-- речка по лугу и водопады в облака
		part({ Size = V3(10, 0.3, 180), CFrame = mcf * CF(0, 0.1, 0), Color = WATER, Material = M.Glass, Transparency = 0.15, CanCollide = false })
		part({ Size = V3(180, 0.3, 10), CFrame = mcf * CF(0, 0.12, 0), Color = WATER, Material = M.Glass, Transparency = 0.15, CanCollide = false })
		for _, e in ipairs({ { 0, 90 }, { 0, -90 }, { 90, 0 }, { -90, 0 } }) do
			local p = (mcf * CF(e[1], -0.5, e[2])).Position
			blueFall(p, V3(p.X, CY, p.Z), 10)
		end
		for _ = 1, 26 do
			local pcf = mcf * CF(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
			local px, pz = pcf.Position.X - mp.X, pcf.Position.Z - mp.Z
			if math.abs(px) > 8 and math.abs(pz) > 8 and not (math.abs(px) > 36 and math.abs(pz) > 36) then
				local roll = rng:NextNumber()
				if roll < 0.35 then
					flatMushroom(pcf, rng:NextNumber(1.2, 2), pick(rng, { RGB(255, 170, 40), RGB(255, 200, 70) }))
				elseif roll < 0.6 then
					crystalCluster(pcf, rng:NextNumber(1, 1.6), RGB(110, 170, 255))
				elseif roll < 0.8 then
					blockyTree(pcf, rng, rng:NextNumber(1, 1.6), RGB(90, 210, 70))
				else
					bush(pcf, rng)
				end
			end
		end
		table.insert(busyIsles, { p = mp, s = 200 })
	end
	-- 🏝 ещё острова вокруг трассы
	for _ = 1, 160 do
		if #busyIsles >= 20 then
			break
		end
		local size = rng:NextNumber(36, 80)
		local p = findSpot(size / 2 + 26, 6)
		if p then
			local ok = true
			for _, b in ipairs(busyIsles) do
				if (V3(b.p.X, 0, b.p.Z) - p).Magnitude < (b.s + size) / 2 + 16 then
					ok = false
					break
				end
			end
			if ok then
				local y = SKYK.top + rng:NextNumber(-45, 30)
				bigIsle(CF(p.X, y, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng, size, "sky", CY)
				table.insert(busyIsles, { p = p, s = size })
			end
		end
	end
	-- 🌈 радуги
	for i = 1, 2 do
		local p = findSpot(80, 200)
		if p then
			local R = i == 1 and 120 or 80
			giantRainbow(CFrame.lookAt(V3(p.X, CY + 5, p.Z), V3(cx, CY + 5, cz)), R)
		end
	end
	-- 🛩 дирижабли кружат над миром
	local center = CF(cx, 0, cz)
	flyingBlimp(center, ext / 2 + 160, SKYK.top + 70, 2.4, 0.025, 0)
	flyingBlimp(center, ext / 2 + 260, SKYK.top + 110, 3, -0.018, PI)
	-- 🎈 воздушные шары
	for _ = 1, 10 do
		local p = findSpot(40, 30)
		if p then
			hotAirBalloon(CF(p.X, SKYK.top + rng:NextNumber(40, 120), p.Z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng)
		end
	end
	-- 📦 сундук-сокровище №5: тайный облачный островок у площадки 44
	local pl = SKYK.plateaus[4] or SKYK.plateaus[#SKYK.plateaus]
	if pl then
		hiddenNook(pl, 5, "sky")
	end
end

-- ============ МИР 3: ХРУСТАЛЬНЫЕ ПЕЩЕРЫ (огромная пещера, трасса волнами вниз) ============
local CAVEW = { lavaY = 20, top = 80, plateaus = {}, entrance = nil, endCF = nil }
local CRYSTAL_COLS = { RGB(90, 255, 140), RGB(200, 90, 255), RGB(90, 220, 255) }
local TEMPLE_STONE = RGB(170, 160, 140)

-- 🏛 греческий храм: ступени, колонны, фронтон, кристалл-алтарь внутри
local function greekTemple(cf, k, broken)
	local W, D = 30 * k, 22 * k
	for i = 0, 2 do
		part({ Size = V3(W + (3 - i) * 3 * k, 1.2 * k, D + (3 - i) * 3 * k), CFrame = cf * CF(0, (i + 0.5) * 1.2 * k, 0), Color = darker(TEMPLE_STONE, 0.9 + i * 0.03), Material = M.Slate })
	end
	local baseY = 3.6 * k
	local colH = 14 * k
	for row = -1, 1, 2 do
		for i = 0, 5 do
			local cx = -W / 2 + 2 * k + i * (W - 4 * k) / 5
			local h = colH
			if broken and row == 1 and (i == 1 or i == 4) then
				h = colH * 0.45
			end
			part({ Size = V3(2.8 * k, 1 * k, 2.8 * k), CFrame = cf * CF(cx, baseY + 0.5 * k, row * (D / 2 - 2 * k)), Color = darker(TEMPLE_STONE, 0.85), Material = M.Slate })
			part({ Shape = CYL, Size = V3(h, 2.2 * k, 2.2 * k), CFrame = cf * CF(cx, baseY + 1 * k + h / 2, row * (D / 2 - 2 * k)) * ROT_UP, Color = TEMPLE_STONE, Material = M.Marble })
			if h == colH then
				part({ Size = V3(3 * k, 1 * k, 3 * k), CFrame = cf * CF(cx, baseY + 1.5 * k + colH, row * (D / 2 - 2 * k)), Color = darker(TEMPLE_STONE, 0.9), Material = M.Slate })
			else
				-- упавший кусок колонны рядом
				part({ Shape = CYL, Size = V3(colH * 0.4, 2.2 * k, 2.2 * k), CFrame = cf * CF(cx + 3 * k, baseY + 1.1 * k, row * (D / 2 + 3 * k)) * CFrame.Angles(0, 0.6, 0), Color = TEMPLE_STONE, Material = M.Marble })
			end
		end
	end
	local topY = baseY + 2 * k + colH
	if not broken then
		part({ Size = V3(W + 1 * k, 2 * k, D + 1 * k), CFrame = cf * CF(0, topY + 1 * k, 0), Color = darker(TEMPLE_STONE, 0.92), Material = M.Slate })
		for sx = -1, 1, 2 do
			local w = Instance.new("WedgePart")
			w.Anchored = true
			w.Size = V3(D + 1 * k, 6 * k, W / 2 + 0.5 * k)
			w.CFrame = cf * CF(sx * (W / 4 + 0.25 * k), topY + 5 * k, 0) * CFrame.Angles(0, sx * -PI / 2, 0)
			w.Color = TEMPLE_STONE
			w.Material = M.Slate
			w.Parent = currentFolder
		end
	else
		part({ Size = V3(W * 0.6, 2 * k, D + 1 * k), CFrame = cf * CF(-W * 0.2, topY + 1 * k, 0) * CFrame.Angles(0, 0, 0.05), Color = darker(TEMPLE_STONE, 0.92), Material = M.Slate })
	end
	-- светящийся кристалл-алтарь
	part({ Size = V3(4 * k, 3 * k, 4 * k), CFrame = cf * CF(0, baseY + 1.5 * k, 0), Color = darker(TEMPLE_STONE, 0.8), Material = M.Slate })
	crystalCluster(cf * CF(0, baseY + 3 * k, 0), 1.4 * k, CRYSTAL_COLS[1])
	-- мох
	for i = 1, 6 do
		part({ Size = V3(3 * k, 0.4 * k, 2 * k), CFrame = cf * CF((i - 3.5) * 4 * k, 3.7 * k, (i % 2 == 0 and 1 or -1) * D / 2), Color = RGB(70, 150, 90), CanCollide = false })
	end
end

-- 💎 гигантский кристалл (с подсветкой)
local function giantCrystal(cf, k, col, light)
	for i = 1, 5 do
		local h = (8 + (i % 3) * 5) * k
		local a = i / 5 * 2 * PI
		local tilt = (i == 1) and 0 or 0.35
		local shard = cf * CF(math.cos(a) * 2 * k * (i > 1 and 1 or 0), 0, math.sin(a) * 2 * k * (i > 1 and 1 or 0)) * CFrame.Angles(math.sin(a) * tilt, a, math.cos(a) * tilt)
		part({ Size = V3(3 * k, h, 3 * k), CFrame = shard * CF(0, h / 2 - 0.5 * k, 0), Color = col, Material = M.Glass, Transparency = 0.25 })
		part({ Size = V3(1.6 * k, h * 0.85, 1.6 * k), CFrame = shard * CF(0, h / 2 - 0.5 * k, 0), Color = col, Material = M.Neon, Transparency = 0.2, CanCollide = false })
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.Size = V3(3 * k, 2.5 * k, 3 * k)
		w.CFrame = shard * CF(0, h - 0.5 * k + 1.25 * k, 0)
		w.Color = col
		w.Material = M.Glass
		w.Transparency = 0.25
		w.Parent = currentFolder
	end
	if light then
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 40 * math.min(k, 1.5)
		l.Brightness = 2.5
		l.Parent = part({ Size = V3(1, 1, 1), CFrame = cf * CF(0, 8 * k, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	end
end

-- 🍄 светящийся гриб
local function glowShroom(cf, k, col)
	part({ Shape = CYL, Size = V3(4 * k, 1 * k, 1 * k), CFrame = cf * CF(0, 2 * k, 0) * ROT_UP, Color = RGB(230, 225, 210) })
	part({ Shape = CYL, Size = V3(1.2 * k, 4.4 * k, 4.4 * k), CFrame = cf * CF(0, 4.3 * k, 0) * ROT_UP, Color = col, Material = M.Neon })
	part({ Shape = CYL, Size = V3(0.8 * k, 3 * k, 3 * k), CFrame = cf * CF(0, 5 * k, 0) * ROT_UP, Color = col:Lerp(WHITE, 0.3), Material = M.Neon, CanCollide = false })
end

-- 🪨 сталактит (висит вниз от точки cf)
local function stalactite(cf, h, w, col)
	for i = 0, 3 do
		local s = w * (1 - i * 0.22)
		part({ Size = V3(s, h / 4 + 0.2, s), CFrame = cf * CF(0, -(i + 0.5) * h / 4, 0) * CFrame.Angles(0, i * 0.5, 0), Color = col or RGB(70, 66, 72), Material = M.Slate, CanCollide = false, CastShadow = false })
	end
end

local function stalagmite(cf, h, w, col)
	for i = 0, 3 do
		local s = w * (1 - i * 0.22)
		part({ Size = V3(s, h / 4 + 0.2, s), CFrame = cf * CF(0, (i + 0.5) * h / 4, 0) * CFrame.Angles(0, i * 0.5, 0), Color = col or RGB(85, 80, 86), Material = M.Slate })
	end
end

-- ⛏ деревянная крепь шахты с фонарём
local function mineSupport(cf, k)
	local wood = RGB(120, 85, 55)
	for sx = -1, 1, 2 do
		part({ Size = V3(1.4 * k, 12 * k, 1.4 * k), CFrame = cf * CF(sx * 5 * k, 6 * k, 0), Color = wood, Material = M.Wood })
	end
	part({ Size = V3(12 * k, 1.4 * k, 1.6 * k), CFrame = cf * CF(0, 12.2 * k, 0), Color = wood, Material = M.Wood })
	part({ Size = V3(0.2, 2 * k, 0.2), CFrame = cf * CF(0, 10.6 * k, 0), Color = RGB(40, 40, 40), CanCollide = false })
	local lan = part({ Size = V3(1 * k, 1.4 * k, 1 * k), CFrame = cf * CF(0, 9.2 * k, 0), Color = RGB(255, 200, 110), Material = M.Neon, CanCollide = false })
	local l = Instance.new("PointLight")
	l.Color = RGB(255, 190, 110)
	l.Range = 18 * k
	l.Brightness = 1.6
	l.Parent = lan
end

-- 💎 площадка-чекпоинт пещеры: круглый каменный пол, мох, кристаллы и фонари
local function cavePlateau(ctx, stageNum, padX, padTop, padZc, size, isEnd, noProps)
	local rng = Random.new(Config.MAP_SEED + stageNum * 97)
	local cf = L(ctx, padX, padTop, padZc)
	table.insert(CAVEW.plateaus, { cf = cf, size = size })
	local topPart = part({ Name = "Checkpoint" .. stageNum, Shape = CYL, Size = V3(2, size, size), CFrame = cf * CF(0, -1, 0) * ROT_UP, Color = CAVE_STONE, Material = M.Slate })
	if not isEnd then
		topPart:SetAttribute("Stage", stageNum)
		tag(topPart, "Checkpoint")
		info.checkpoints[stageNum] = topPart
	end
	-- плиточный круг и дорожка
	part({ Shape = CYL, Size = V3(0.2, size * 0.55, size * 0.55), CFrame = cf * CF(0, 0.05, 0) * ROT_UP, Color = RGB(120, 125, 120), Material = M.Cobblestone, CanCollide = false })
	part({ Size = V3(7, 0.2, size - 1), CFrame = cf * CF(0, 0.06, 0), Color = RGB(120, 125, 120), Material = M.Cobblestone, CanCollide = false })
	-- мох по краю
	for i = 0, 11 do
		local a = i / 12 * 2 * PI
		part({ Size = V3(rng:NextNumber(3, 6), 0.4, rng:NextNumber(2, 3)), CFrame = cf * CFrame.Angles(0, a, 0) * CF(size / 2 - 1.5, 0.1, 0), Color = RGB(70, 150, 90), CanCollide = false })
	end
	-- скала-столб до лавы
	local s, y = size, -2
	for i = 1, 3 do
		s *= 0.85
		part({ Shape = CYL, Size = V3(5, s, s), CFrame = cf * CF(rng:NextNumber(-0.8, 0.8), y - 2.5, rng:NextNumber(-0.8, 0.8)) * ROT_UP, Color = darker(CAVE_STONE, 0.85 - i * 0.05), Material = M.Slate })
		y -= 5
	end
	local bottom = padTop + y
	if bottom > LAVA_BOTTOM then
		part({ Size = V3(s * 0.6, bottom - LAVA_BOTTOM, s * 0.6), CFrame = CF(cf.Position.X, (bottom + LAVA_BOTTOM) / 2, cf.Position.Z), Color = darker(CAVE_STONE, 0.6), Material = M.Slate })
	end
	if not isEnd then
		local glow = part({ Shape = CYL, Size = V3(0.25, 7, 7), CFrame = cf * CF(0, 0.12, 0) * ROT_UP, Color = RGB(90, 255, 140), Material = M.Neon, CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = RGB(10, 40, 20)
		lbl.Text = tostring(stageNum)
		lbl.Parent = sg
		sg.Parent = glow
	end
	if not noProps then
		for i = 1, 4 do
			local a = (i - 0.5) / 4 * 2 * PI + PI / 4
			local pcf = cf * CF(math.cos(a) * (size / 2 - 4), 0, math.sin(a) * (size / 2 - 4)) * CFrame.Angles(0, a, 0)
			local roll = (i + stageNum) % 4
			if roll == 0 then
				crystalCluster(pcf, 1.1, pick(rng, CRYSTAL_COLS))
			elseif roll == 1 then
				glowShroom(pcf, 0.9, pick(rng, { RGB(90, 220, 255), RGB(200, 90, 255) }))
			elseif roll == 2 then
				part({ Shape = CYL, Size = V3(rng:NextNumber(3, 7), 2.2, 2.2), CFrame = pcf * CF(0, 2, 0) * ROT_UP, Color = TEMPLE_STONE, Material = M.Marble })
			else
				crystalCluster(pcf, 0.8, pick(rng, CRYSTAL_COLS))
				part({ Size = V3(3, 2, 2.5), CFrame = pcf * CF(2, 1, 0) * CFrame.Angles(0.2, 1, 0), Color = darker(CAVE_STONE, 0.8), Material = M.Slate })
			end
		end
	end
	-- фонари у выхода (тёплый свет в тёмной пещере)
	for sx = -1, 1, 2 do
		lamp(cf * CF(sx * 5.5, 0, size / 2 - 2.5))
	end
	if not isEnd then
		arrowSign(cf * CF(6.5, 0, size / 2 - 1.5))
	end
	for k = 0, 3 do
		local a = k / 4 * 2 * PI
		addPath((cf * CF(math.cos(a) * size / 2, 0, math.sin(a) * size / 2)).Position)
	end
	addPath(cf.Position)
	return topPart, cf
end

-- 🚪 вход в пещеры: шахтные ворота, вагонетки, ящики, фонари
local function caveEntrance(ctx, first)
	local top = ctx.y
	local size = 60
	cavePlateau(ctx, first, 0, top, 0, size, false, true)
	CAVEW.entrance = L(ctx, 0, top, 0)
	info.spawnCF[first] = L(ctx, 0, top + 3.5, -20)
	portalGate(L(ctx, 0, top + 7, -25), 6, RGB(90, 255, 140), WHITE, RGB(90, 255, 140))
	-- ворота шахты с вывеской
	local gate = L(ctx, 0, top, -6)
	mineSupport(gate * CF(-8, 0, 0), 1.6)
	mineSupport(gate * CF(8, 0, 0), 1.6)
	part({ Size = V3(36, 3, 3), CFrame = gate * CF(0, 21, 0), Color = RGB(110, 75, 50), Material = M.Wood })
	local board = gate * CF(0, 26, 0)
	part({ Size = V3(32, 8, 2), CFrame = board, Color = RGB(60, 50, 55), Material = M.Slate })
	makeSign(board * CF(0, 0, -1.1), V3(29, 6, 0.3), "sign_cave_title", RGB(30, 40, 45), RGB(120, 255, 170), Enum.NormalId.Back)
	makeSign(board * CF(0, 0, 1.1), V3(29, 6, 0.3), "sign_cave_title", RGB(30, 40, 45), RGB(120, 255, 170), Enum.NormalId.Front)
	for sx = -1, 1, 2 do
		giantCrystal(L(ctx, sx * 22, top, -12), 0.9, sx < 0 and CRYSTAL_COLS[1] or CRYSTAL_COLS[2], true)
	end
	-- рельсы и вагонетка с кристаллами
	for sx = -1, 1, 2 do
		part({ Size = V3(0.4, 0.3, 30), CFrame = L(ctx, 20 + sx * 1.8, top + 0.15, 10), Color = RGB(130, 130, 140), Material = M.Metal })
	end
	part({ Size = V3(4.6, 2.6, 5.6), CFrame = L(ctx, 20, top + 1.6, 12), Color = RGB(110, 75, 50), Material = M.WoodPlanks })
	part({ Size = V3(3.8, 0.6, 4.6), CFrame = L(ctx, 20, top + 3, 12), Color = CRYSTAL_COLS[3], Material = M.Neon })
	for i, p in ipairs({ { -21, 8 }, { -23, 12 }, { -20, 16 } }) do
		part({ Size = V3(3, 3, 3), CFrame = L(ctx, p[1], top + 1.5 + (i == 3 and 3 or 0), p[2]) * CFrame.Angles(0, i, 0), Color = RGB(150, 110, 70), Material = M.WoodPlanks })
	end
	arrowTrail(L(ctx, 0, top, -18).Position, L(ctx, 0, top, size / 2 - 2).Position, 4, RGB(90, 255, 140))
	ctx.x, ctx.y, ctx.z = 0, top, size / 2
end

-- 🕳 сама пещера: купол, стены, сталактиты, храмы, кристаллы, река, шахта, выход к свету
local function buildCaveScenery(rng, pFirst, pLast)
	local LY = CAVEW.lavaY
	-- выход из пещеры: точки добавляем заранее, чтобы стены пещеры его обошли
	local ep, exitP
	if CAVEW.endCF then
		ep = (CAVEW.endCF * CF(0, 0, -70)).Position
		exitP = (CAVEW.endCF * CF(0, 14, -150)).Position
		addPath(ep)
		addPath(exitP)
		pLast = #info.pathPoints
	end
	local minX, maxX, minZ, maxZ, maxY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for i = pFirst, pLast do
		local p = info.pathPoints[i]
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		maxY = math.max(maxY, p.Y)
	end
	local M_ = 110 -- от трассы до стен
	local x0, x1, z0, z1 = minX - M_, maxX + M_, minZ - M_, maxZ + M_
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local W, D = x1 - x0, z1 - z0
	local ceilY = maxY + 55
	local function tiles(fn)
		local nx, nz = math.ceil(W / 1800), math.ceil(D / 1800)
		for ix = 0, nx - 1 do
			for iz = 0, nz - 1 do
				local tw, td = W / nx, D / nz
				fn(x0 + (ix + 0.5) * tw, z0 + (iz + 0.5) * td, tw, td)
			end
		end
	end
	-- 🔥 лавовое дно и тёмный купол
	tiles(function(x, z, tw, td)
		local lava = part({ Name = "CaveLava", Size = V3(tw + 2, 1, td + 2), CFrame = CF(x, LY - 0.5, z), Color = RGB(255, 100, 20), Material = M.CrackedLava })
		tag(lava, "Lava")
		local g = part({ Size = V3(tw + 2, 0.3, td + 2), CFrame = CF(x, LY + 0.2, z), Color = RGB(255, 120, 30), Material = M.Neon, Transparency = 0.8, CanCollide = false, CanQuery = false })
		tag(g, "Lava")
		part({ Size = V3(tw + 2, 24, td + 2), CFrame = CF(x, ceilY + 12, z), Color = RGB(45, 42, 50), Material = M.Slate })
	end)
	-- стены
	local wallH = ceilY - LY + 30
	for _, w in ipairs({ { cx, z0 - 15, W + 60, 30 }, { cx, z1 + 15, W + 60, 30 }, { x0 - 15, cz, 30, D }, { x1 + 15, cz, 30, D } }) do
		part({ Size = V3(math.min(w[3], 2048), wallH, math.min(w[4], 2048)), CFrame = CF(w[1], LY - 10 + wallH / 2, w[2]), Color = RGB(60, 58, 66), Material = M.Slate })
	end
	-- уступы-берега вдоль стен (на них храмы, кристаллы, шахта)
	local LEDGE = 60
	local ledgeY = LY + 8
	local ledges = {
		{ cx, z0 + LEDGE / 2, W, LEDGE },
		{ cx, z1 - LEDGE / 2, W, LEDGE },
		{ x0 + LEDGE / 2, cz, LEDGE, D - LEDGE * 2 },
		{ x1 - LEDGE / 2, cz, LEDGE, D - LEDGE * 2 },
	}
	for _, l in ipairs(ledges) do
		part({ Size = V3(math.min(l[3], 2048), ledgeY - LY + 10, math.min(l[4], 2048)), CFrame = CF(l[1], (ledgeY + LY - 10) / 2, l[2]), Color = RGB(70, 72, 78), Material = M.Slate })
	end
	-- места на уступах
	local spots = {}
	local function ledgeSpot()
		local side = rng:NextInteger(1, 4)
		local l = ledges[side]
		local x = l[1] + rng:NextNumber(-l[3] / 2 + 15, l[3] / 2 - 15)
		local z = l[2] + rng:NextNumber(-l[4] / 2 + 15, l[4] / 2 - 15)
		return V3(x, ledgeY, z)
	end
	local function free(p, r)
		for _, s in ipairs(spots) do
			if (s.p - p).Magnitude < s.r + r then
				return false
			end
		end
		return true
	end
	local function faceIn(p)
		return CFrame.lookAt(p, V3(cx, p.Y, cz))
	end
	-- 🏛 храмы
	local temples = 0
	for _ = 1, 80 do
		if temples >= 6 then
			break
		end
		local p = ledgeSpot()
		local k = rng:NextNumber(1, 1.5)
		if free(p, 28 * k) then
			table.insert(spots, { p = p, r = 28 * k })
			greekTemple(faceIn(p), k, temples % 2 == 1)
			temples += 1
		end
	end
	-- 💎 гигантские кристаллы (на уступах и из лавы)
	local lights = 0
	for _ = 1, 120 do
		local p = ledgeSpot()
		if free(p, 12) then
			table.insert(spots, { p = p, r = 12 })
			lights += 1
			giantCrystal(faceIn(p) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(1.2, 2.4), pick(rng, CRYSTAL_COLS), lights <= 18)
		end
		if lights >= 26 then
			break
		end
	end
	for _ = 1, 50 do
		local p = V3(rng:NextNumber(x0 + LEDGE + 10, x1 - LEDGE - 10), LY, rng:NextNumber(z0 + LEDGE + 10, z1 - LEDGE - 10))
		if farFromPath(p, 24) then
			local roll = rng:NextNumber()
			local cf = CF(p) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
			if roll < 0.45 then
				part({ Size = V3(rng:NextNumber(10, 18), rng:NextNumber(8, 16), rng:NextNumber(10, 18)), CFrame = cf * CF(0, 3, 0), Color = RGB(80, 76, 84), Material = M.Slate })
				giantCrystal(cf * CF(0, 9, 0), rng:NextNumber(0.6, 1.1), pick(rng, CRYSTAL_COLS), false)
			else
				stalagmite(cf, rng:NextNumber(14, 34), rng:NextNumber(5, 9))
			end
		end
	end
	-- 🍄 светящиеся грибы, ⛏ шахтные крепи, рельсы
	for _ = 1, 140 do
		local p = ledgeSpot()
		if free(p, 6) then
			table.insert(spots, { p = p, r = 6 })
			local roll = rng:NextNumber()
			local cf = faceIn(p) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0)
			if roll < 0.4 then
				glowShroom(cf, rng:NextNumber(1, 2.4), pick(rng, { RGB(90, 220, 255), RGB(200, 90, 255), RGB(90, 255, 160) }))
			elseif roll < 0.6 then
				mineSupport(cf, rng:NextNumber(1, 1.4))
			elseif roll < 0.8 then
				stalagmite(cf, rng:NextNumber(8, 20), rng:NextNumber(3, 6))
			else
				crystalCluster(cf, rng:NextNumber(1, 1.8), pick(rng, CRYSTAL_COLS))
			end
		end
	end
	-- 🪨 сталактиты на потолке
	for _ = 1, 160 do
		local p = V3(rng:NextNumber(x0, x1), ceilY, rng:NextNumber(z0, z1))
		local h = rng:NextNumber(10, 40)
		local tip = p.Y - h
		if tip > maxY + 12 or farFromPath(p, 12) then
			stalactite(CF(p), h, rng:NextNumber(4, 10))
		end
	end
	-- 💧 подземная река вдоль уступа и водопад со стены
	local rz = z1 - LEDGE * 0.5
	part({ Size = V3(math.min(W - 40, 2048), 0.4, 10), CFrame = CF(cx, ledgeY + 0.15, rz), Color = RGB(60, 190, 255), Material = M.Neon, Transparency = 0.35, CanCollide = false })
	for i = 0, 2 do
		local fx = x0 + W * (0.25 + i * 0.25)
		blueFall(V3(fx, ceilY - 4, z1 - 2), V3(fx, ledgeY, z1 - 2), 10)
	end
	-- ☀️ свет на выходе из пещеры: огромная скала с сияющим проёмом + храм у выхода
	if ep then
		local look = CAVEW.endCF.LookVector
		local rockCf = CFrame.lookAt(exitP, exitP + look)
		part({ Size = V3(90, ceilY - LY + 10, 30), CFrame = CF(exitP.X, (ceilY + LY) / 2, exitP.Z) * (rockCf - rockCf.Position) * CF(0, 0, -16), Color = RGB(60, 58, 66), Material = M.Slate })
		local exitDisc = part({ Shape = CYL, Size = V3(1, 44, 44), CFrame = rockCf * CF(0, 0, -0.5) * CFrame.Angles(0, PI / 2, 0), Color = RGB(225, 248, 255), Material = M.Neon, CanCollide = false })
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Right
		l.Range = 60
		l.Angle = 80
		l.Brightness = 5
		l.Color = RGB(220, 245, 255)
		l.Parent = exitDisc
		local base = V3(ep.X, ep.Y - 20, ep.Z)
		part({ Size = V3(70, base.Y - LY, 50), CFrame = CF(base.X, (base.Y + LY) / 2, base.Z), Color = RGB(70, 72, 78), Material = M.Slate })
		greekTemple(CFrame.lookAt(base, base - look), 1.6, false)
	end
	-- ✨ пыль, светлячки в воздухе
	for _ = 1, 8 do
		local p = V3(rng:NextNumber(minX, maxX), maxY - 10, rng:NextNumber(minZ, maxZ))
		local holder = part({ Size = V3(80, 30, 80), CFrame = CF(p), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(RGB(150, 255, 200), RGB(200, 150, 255))
		em.LightEmission = 1
		em.Size = NumberSequence.new(0.25)
		em.Speed = NumberRange.new(0.5, 1.5)
		em.Lifetime = NumberRange.new(4, 7)
		em.Rate = 6
		em.SpreadAngle = Vector2.new(180, 180)
		em.Parent = holder
	end
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

	local lobby = Instance.new("Model")
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
	LAVA_BOTTOM = -2
	buildLobby(ctx)
	-- 🌍 масштаб: всё лобби становится в несколько раз больше, персонаж — прежний
	lobby.WorldPivot = CF(0, 12, 0)
	lobby:ScaleTo(Config.LOBBY_SCALE)
	local sp = lobby:FindFirstChild("LavaSpawn", true)
	if sp then
		info.lobbySpawn = sp.CFrame + V3(0, 3.5, 0)
	end

	local stageFrames = {}
	local prevPlan = {}

	-- Один этап: препятствия + следующий чекпоинт (или конец мира)
	local function buildStage(s, first, last)
		local folder = Instance.new("Folder")
		folder.Name = string.format("Stage_%02d", s)
		folder.Parent = map
		currentFolder = folder

		ctx.stage = s
		ctx.zone = Config.ZoneOfStage(s)
		ctx.diff = ((s - 1) / (TOTAL - 1)) ^ 1.6 -- плавный рост: начало лёгкое
		ctx.sky = ctx.zone == 5
		ctx.flat = ctx.zone == 4 and not ctx.isles
		ctx.rng = Random.new(Config.MAP_SEED + s * 7919)
		local r = ctx.rng
		local stageFrame = ctx.F
		local pStart = #info.pathPoints + 1
		local stageStartY = ctx.y

		local lowered = 0
		if ctx.zone == 4 and not ctx.isles then
			ctx.y -= 3
			lowered = 3
		end

		local plan = {}
		if s == (4 * PER_ZONE + 1) and not ctx.skyland then
			plan = { "bounce", "bounce", "jumps" } -- взлёт в небо
		else
			local pool = POOLS[ctx.zone]
			local count = 2 + ((ctx.diff > 0.35) and 1 or 0)
			local used = {}
			for _ = 1, count do
				local name
				for _ = 1, 20 do
					name = pool[r:NextInteger(1, #pool)]
					local tooHigh = CLIMBING[name] and (ctx.y - (ctx.baseY or 12)) > 60
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

		local isWorldEnd = s == last
		local isFinish = isWorldEnd and last == TOTAL
		-- в Candy Land «боковые» этапы не короче 58, чтобы ряды змейки не задевали друг друга
		local kk = s - first + 1
		if ctx.candy and (kk == 3 or kk == 6 or kk == 9) and ctx.z < 58 then
			local len = 58 - ctx.z
			walkway(ctx, ctx.x, ctx.y, ctx.z + len / 2, 9, len)
			ctx.z = 58
		end
		local nextStage = s + 1
		local padSize
		if ctx.candy then
			padSize = isWorldEnd and 56 or r:NextInteger(26, 32)
		elseif ctx.park then
			padSize = isWorldEnd and 44 or r:NextInteger(28, 34)
		elseif (ctx.isles or ctx.skyland or ctx.cavew) and not isFinish then
			padSize = isWorldEnd and 50 or r:NextInteger(26, 32)
		else
			padSize = isWorldEnd and 30 or 14
		end
		local padTop = ctx.y + lowered
		if ctx.cavew then
			padTop = ctx.y - 3 -- пещера уходит всё глубже
		end
		local padZc = ctx.z + 4.5 + padSize / 2
		local padX = ctx.x
		if ctx.candy then
			candyPlateau(ctx, nextStage, padX, padTop, padZc, padSize, isWorldEnd)
		elseif ctx.park then
			parkPlateau(ctx, nextStage, padX, padTop, padZc, padSize, isWorldEnd)
		elseif ctx.isles then
			islePlateau(ctx, nextStage, padX, padTop, padZc, padSize, isWorldEnd)
		elseif ctx.cavew then
			cavePlateau(ctx, nextStage, padX, padTop, padZc, padSize, isWorldEnd)
		elseif ctx.skyland and not isFinish then
			skyPlateau(ctx, nextStage, padX, padTop, padZc, padSize, isWorldEnd)
		elseif isWorldEnd and not isFinish then
			worldEndPad(ctx, padX, padTop, padZc, padSize)
		else
			checkpointPad(ctx, nextStage, padX, padTop, padZc, padSize, isFinish)
		end

		-- 🍫 шоколадная река под фабрикой сладостей (смертельная, как лава)
		if ctx.zone == 2 and not ctx.candy then
			local river = part({
				Name = "ChocolateRiver",
				Size = V3(150, 2, padZc + 70),
				CFrame = L(ctx, 0, 0.4 + s * 0.003, padZc / 2),
				Color = RGB(105, 55, 25),
				Material = M.SmoothPlastic,
				Reflectance = 0.12,
			})
			tag(river, "Lava")
		end

		-- волна лавы в зоне 4
		if ctx.zone == 4 and not ctx.isles then
			local lowY = ctx.y
			local z0, z1 = 5, padZc - padSize / 2 + 2
			local restTop = lowY - 14
			local low = L(ctx, 0, restTop - 5, (z0 + z1) / 2)
			local wave = part({ Name = "LavaWave", Size = V3(70, 10, z1 - z0), CFrame = low, Color = RGB(255, 100, 0), Material = M.Neon, Transparency = 0.05 })
			tag(wave, "Lava")
			table.insert(info.waves, { part = wave, low = low, high = low + V3(0, (lowY + 1.5) - restTop, 0) })
		end

		table.insert(stageFrames, { F = stageFrame, len = padZc, y = stageStartY, zone = ctx.zone, pStart = pStart, pEnd = #info.pathPoints })

		-- поворот: в парке трасса идёт кольцом вокруг центра, в других мирах — один поворот
		if ctx.park then
			local C = ctx.parkCenter
			local pp = (ctx.F * CF(padX, 0, -padZc)).Position
			local a = math.atan2(pp.Z - C.Z, pp.X - C.X)
			local prog = (s - first + 1) / (last - first + 1)
			local rr = PARK.ring + PARK.ringGrow * prog -- спираль: каждый этап дальше от центра
			local tgt = V3(C.X + math.cos(a + 0.5) * rr, 0, C.Z + math.sin(a + 0.5) * rr)
			ctx.F = CFrame.lookAt(V3(pp.X, 0, pp.Z), tgt)
		elseif ctx.cavew then
			-- мир 3: волны — три поворота вправо, три влево
			local kk3 = s - first + 1
			local turn = isWorldEnd and 0 or ((math.floor((kk3 - 1) / 3) % 2 == 0) and PI / 6 or -PI / 6)
			ctx.F = ctx.F * CF(padX, 0, -padZc) * CFrame.Angles(0, turn, 0)
		elseif ctx.isles or ctx.skyland then
			-- мир 4: зигзаг по 45°; мир 5: «лесенка» по 90°
			local kk2 = s - first + 1
			local ang = ctx.isles and PI / 4 or PI / 2
			local turn = isWorldEnd and 0 or (((kk2 % 2 == 1) and 1 or -1) * ang)
			ctx.F = ctx.F * CF(padX, 0, -padZc) * CFrame.Angles(0, turn, 0)
		elseif ctx.candy then
			-- змейка: туда → вбок → обратно → вбок → туда → вбок к замку
			local CANDY_TURNS = { [2] = 1, [3] = 1, [5] = -1, [6] = -1, [8] = 1 }
			local turn = (CANDY_TURNS[s - first + 1] or 0) * PI / 2
			ctx.F = ctx.F * CF(padX, 0, -padZc) * CFrame.Angles(0, turn, 0)
		else
			local turn = (not isWorldEnd and (s - first + 1) == 5) and -PI / 2 or 0
			ctx.F = ctx.F * CF(padX, 0, -padZc) * CFrame.Angles(0, turn, 0)
		end
		ctx.x, ctx.y, ctx.z = 0, padTop, padSize / 2
		if not isWorldEnd or isFinish then
			info.spawnCF[nextStage] = ctx.F * CF(0, padTop + 3.5, 0)
		end

		if isFinish then
			buildFinish(ctx)
		elseif isWorldEnd then
			worldFinishPortal(ctx, ctx.zone)
			if ctx.isles then
				VOLC.endCF = ctx.F
			end
			if ctx.cavew then
				CAVEW.endCF = ctx.F + V3(0, ctx.y, 0)
			end
			if ctx.candy then
				candyCastle(L(ctx, 0, ctx.y, ctx.z + 17) * CFrame.Angles(0, PI, 0), 1)
			end
		elseif Specials[nextStage] and not ctx.park then
			Specials[nextStage](ctx)
		end
	end

	-- 🌍 миры: каждый на своём месте, вход из лобби через портал
	info.worldOrigins = {}
	local snakePoints = {}
	for w = 1, #Config.Zones do
		local first = (w - 1) * PER_ZONE + 1
		local last = math.min(w * PER_ZONE, TOTAL)
		local origin = V3(Config.WORLD_SPACING * w, 0, 0)
		info.worldOrigins[w] = origin
		local wf = Instance.new("Folder")
		wf.Name = "World_" .. w
		wf.Parent = map
		currentFolder = wf
		ctx.zone = w
		ctx.sky = w == 5
		ctx.flat = w == 4
		ctx.stage = first
		ctx.rng = Random.new(Config.MAP_SEED + w * 101)
		prevPlan = {}
		local pFirst = #info.pathPoints + 1
		ctx.candy = false
		ctx.isles = false
		ctx.skyland = false
		ctx.cavew = false
		if w == 3 then
			LAVA_BOTTOM = CAVEW.lavaY - 1
			ctx.park = false
			ctx.cavew = true
			ctx.baseY = CAVEW.top
			ctx.F = CFrame.lookAt(origin, origin + V3(0, 0, -1))
			ctx.x, ctx.y, ctx.z = 0, CAVEW.top, 0
			caveEntrance(ctx, first)
		elseif w == 4 or w == 5 then
			local isSky = w == 5
			LAVA_BOTTOM = isSky and (SKYK.cloudY - 20) or (VOLC.lavaY - 1)
			ctx.park = false
			ctx.isles = not isSky
			ctx.skyland = isSky
			ctx.baseY = isSky and SKYK.top or VOLC.top
			ctx.F = CFrame.lookAt(origin, origin + V3(0, 0, -1))
			ctx.x, ctx.y, ctx.z = 0, ctx.baseY, 0
			isleEntrance(ctx, first, isSky and "sky" or "volcano")
		elseif w == 2 then
			LAVA_BOTTOM = CANDYLAND.lavaY - 1
			ctx.park = false
			ctx.candy = true
			ctx.baseY = CANDYLAND.top
			ctx.F = CFrame.lookAt(origin, origin + V3(0, 0, -1))
			ctx.x, ctx.y, ctx.z = 0, CANDYLAND.top, 0
			candyEntrance(ctx, first)
		elseif w == 1 then
			LAVA_BOTTOM = PARK.lavaY - 1
			ctx.park = true
			ctx.parkCenter = origin
			ctx.baseY = PARK.top
			local a0 = -PI / 2
			local p0 = V3(origin.X + math.cos(a0) * PARK.ring, 0, origin.Z + math.sin(a0) * PARK.ring)
			local tgt = V3(origin.X + math.cos(a0 + 0.5) * PARK.ring, 0, origin.Z + math.sin(a0 + 0.5) * PARK.ring)
			ctx.F = CFrame.lookAt(p0, tgt)
			ctx.x, ctx.y, ctx.z = 0, PARK.top, 0
			parkEntrance(ctx, first)
		else
			LAVA_BOTTOM = -2
			ctx.park = false
			ctx.baseY = 12
			ctx.F = CF(origin)
			ctx.x, ctx.y, ctx.z = 0, 12, 0
			worldEntry(ctx, w, first)
		end
		for s = first, last do
			buildStage(s, first, last)
		end
		if w == 1 then
			local pf = Instance.new("Folder")
			pf.Name = "ParkScenery"
			pf.Parent = map
			currentFolder = pf
			buildParkScenery(origin, Random.new(Config.MAP_SEED + 4242), stageFrames)
			-- 🦆 уточка №2: островок рядом с площадкой этапа 6 (два прыжка над лавой)
			local cp = info.checkpoints[6]
			if cp then
				local pp = cp.Position
				local rad = cp.Size.Y / 2
				local topY = pp.Y + 1
				for _, sgn in ipairs({ 1, -1 }) do
					local dir = V3(origin.X - pp.X, 0, origin.Z - pp.Z).Unit * sgn
					local islPos = pp + dir * (rad + 10)
					if farFromPath(V3(islPos.X, 0, islPos.Z), 5) then
						local rockPos = pp + dir * (rad + 3.6)
						part({ Size = V3(3, 1, 3), CFrame = CF(rockPos.X, topY - 0.5, rockPos.Z), Color = PARK_CLIFF[1], Material = M.Slate })
						part({ Size = V3(6, 1, 6), CFrame = CF(islPos.X, topY + 0.5, islPos.Z), Color = RGB(115, 210, 85) })
						makeDuck(CF(islPos.X, topY + 2.5, islPos.Z), 2)
						break
					end
				end
			end
			ctx.park = false
		elseif w == 2 then
			local cf2 = Instance.new("Folder")
			cf2.Name = "CandyScenery"
			cf2.Parent = map
			currentFolder = cf2
			buildCandyScenery(origin, Random.new(Config.MAP_SEED + 2525), pFirst, #info.pathPoints)
			ctx.candy = false
		elseif w == 3 then
			local sf3 = Instance.new("Folder")
			sf3.Name = "CaveScenery"
			sf3.Parent = map
			currentFolder = sf3
			buildCaveScenery(Random.new(Config.MAP_SEED + 3333), pFirst, #info.pathPoints)
			ctx.cavew = false
		elseif w == 4 or w == 5 then
			local sf2 = Instance.new("Folder")
			sf2.Name = w == 4 and "IslesScenery" or "SkyScenery"
			sf2.Parent = map
			currentFolder = sf2
			if w == 4 then
				buildIslesScenery(Random.new(Config.MAP_SEED + 4444), pFirst, #info.pathPoints, VOLC.endCF)
			else
				buildSkyScenery(Random.new(Config.MAP_SEED + 5555), pFirst, #info.pathPoints)
			end
			ctx.isles = false
			ctx.skyland = false
		else
			for i = pFirst, #info.pathPoints do
				table.insert(snakePoints, { w = w, p = info.pathPoints[i] })
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
		if sf.zone >= 1 then -- у всех миров теперь свой декор
			continue -- у парка и Candy Land свой декор
		end
		for _ = 1, 9 do
			if sf.zone == 3 then
				break -- в пещере дальние объекты не видны, там свой декор
			end
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

	-- 🏝 острова-декорации вдоль трассы + пещера + облака
	local srng = Random.new(Config.MAP_SEED + 321)
	local sceneFolder = Instance.new("Folder")
	sceneFolder.Name = "Scenery"
	sceneFolder.Parent = map
	currentFolder = sceneFolder
	for _, sf in ipairs(stageFrames) do
		if sf.zone >= 1 then -- у всех миров теперь свой декор
			continue
		end
		local minY, maxY = math.huge, -math.huge
		for i = sf.pStart, sf.pEnd do
			local p = info.pathPoints[i]
			if p then
				minY = math.min(minY, p.Y)
				maxY = math.max(maxY, p.Y)
			end
		end
		if minY == math.huge then
			minY, maxY = sf.y, sf.y
		end
		local function at(x, y, z)
			return sf.F * CF(x, y, -z)
		end

		if sf.zone == 3 then
			-- 🕳 пещера: стены и потолок (у поворотов — проёмы)
			local z0, z1 = 26, sf.len - 26
			if z1 - z0 > 10 then
				local segLen = z1 - z0
				local zc = (z0 + z1) / 2
				local wallTop = maxY + 26
				for sx = -1, 1, 2 do
					part({ Size = V3(8, wallTop + 2, segLen), CFrame = at(sx * 38, wallTop / 2 - 1, zc), Color = RGB(70, 62, 66), Material = M.Slate })
					-- неровности стены
					for i = 1, 5 do
						local bz = z0 + srng:NextNumber(0, segLen)
						local by = srng:NextNumber(minY - 10, maxY + 18)
						part({ Size = V3(srng:NextNumber(3, 6), srng:NextNumber(6, 14), srng:NextNumber(6, 12)), CFrame = at(sx * 33.5, by, bz) * CFrame.Angles(0, 0, srng:NextNumber(-0.3, 0.3)), Color = RGB(85, 76, 80), Material = M.Slate })
					end
					-- кристаллы на стенах
					for i = 1, 3 do
						local cz = z0 + srng:NextNumber(0, segLen)
						local cy = srng:NextNumber(minY - 4, maxY + 14)
						local col = pick(srng, { RGB(90, 255, 140), RGB(200, 90, 255), RGB(90, 220, 255) })
						for k = 1, 4 do
							local h = srng:NextNumber(3, 8)
							part({ Size = V3(1.6, h, 1.6), CFrame = at(sx * 33.5, cy, cz + srng:NextNumber(-2, 2)) * CFrame.Angles(0, 0, -sx * srng:NextNumber(0.6, 1.3)) * CF(0, h / 2, 0), Color = col, Material = M.Neon, Transparency = 0.1, CanCollide = false })
						end
						local l = Instance.new("PointLight")
						l.Color = col
						l.Range = 30
						l.Brightness = 2
						l.Parent = part({ Size = V3(1, 1, 1), CFrame = at(sx * 30, cy + 2, cz), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
					end
					-- подземный водопад по стене
					if srng:NextNumber() < 0.6 then
						local wz = z0 + srng:NextNumber(4, segLen - 4)
						local fall = part({ Size = V3(0.6, wallTop, 6), CFrame = at(sx * 33.8, wallTop / 2, wz), Color = RGB(120, 205, 255), Material = M.Neon, Transparency = 0.35, CanCollide = false, CanQuery = false })
						local mist = Instance.new("ParticleEmitter")
						mist.Color = ColorSequence.new(Color3.new(1, 1, 1), RGB(150, 210, 255))
						mist.Transparency = NumberSequence.new(0.4, 1)
						mist.Size = NumberSequence.new(2, 5)
						mist.Speed = NumberRange.new(2, 4)
						mist.Lifetime = NumberRange.new(1.5, 2.5)
						mist.Rate = 12
						mist.Parent = part({ Size = V3(1, 1, 6), CFrame = at(sx * 32, 2, wz), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
						local fl = Instance.new("PointLight")
						fl.Color = RGB(120, 205, 255)
						fl.Range = 24
						fl.Parent = fall
					end
				end
				-- потолок со сталактитами
				part({ Size = V3(84, 6, segLen), CFrame = at(0, wallTop + 2, zc), Color = RGB(60, 54, 58), Material = M.Slate })
				for i = 1, 12 do
					local sz = z0 + srng:NextNumber(0, segLen)
					local sxp = srng:NextNumber(-30, 30)
					local h = srng:NextNumber(5, 12)
					for k = 0, 2 do
						local w = 3.4 * (1 - k * 0.3)
						part({ Size = V3(w, h / 3 + 0.3, w), CFrame = at(sxp, wallTop - 1 - k * h / 3 - h / 6, sz) * CFrame.Angles(0, k * 0.6, 0), Color = RGB(80, 72, 76), Material = M.Slate, CanCollide = false })
					end
				end
			end
			-- уступы с кристаллами, грибами и руинами внутри пещеры
			for _ = 1, 5 do
				local size = srng:NextNumber(9, 13)
				local side = srng:NextNumber() < 0.5 and -1 or 1
				local x = side * srng:NextNumber(24, 28)
				local z = srng:NextNumber(10, sf.len - 10)
				local pos = (at(x, 0, z)).Position
				if farFromPath(pos, size / 2 + 6) then
					sceneryIsland(at(x, srng:NextNumber(minY - 6, minY + 2), z), srng, size, 3)
				end
			end
		else
			for _ = 1, 5 do
				local size = srng:NextNumber(14, 26)
				local side = srng:NextNumber() < 0.5 and -1 or 1
				local x = side * (size / 2 + srng:NextNumber(28, 52))
				local z = srng:NextNumber(0, sf.len)
				local pos = (at(x, 0, z)).Position
				local free = farFromPath(pos, size / 2 + 10)
				if free then
					for _, dp in ipairs(decorSpots) do
						local dx, dz = dp.pos.X - pos.X, dp.pos.Z - pos.Z
						if dx * dx + dz * dz < (dp.r + size / 2 + 2) ^ 2 then
							free = false
							break
						end
					end
				end
				if free then
					table.insert(decorSpots, { pos = pos, r = size / 2 + 2 })
					local y = sf.zone == 5 and (minY + srng:NextNumber(-20, 6)) or (minY + srng:NextNumber(-14, 0))
					sceneryIsland(at(x, math.max(y, 6), z), srng, size, sf.zone)
				end
			end
		end

		if sf.zone == 5 then
			-- ☁️ море облаков под небесным королевством
			for _ = 1, 22 do
				local s = srng:NextNumber(18, 34)
				local col = pick(srng, { Color3.new(1, 1, 1), Color3.new(1, 1, 1), RGB(255, 225, 240), RGB(215, 235, 255) })
				part({ Shape = BALL, Size = V3(s, s, s), CFrame = at(srng:NextNumber(-90, 90), minY - 45 + srng:NextNumber(-6, 6), srng:NextNumber(-10, sf.len + 10)), Color = col, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
			end
		end
	end

	-- лава и вулкан под мирами 2–5 (у парка своя лава внутри острова)
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = map
	currentFolder = world
	LAVA_BOTTOM = -2
	for w = 2, #Config.Zones do
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, sp in ipairs(snakePoints) do
			if sp.w == w then
				minX = math.min(minX, sp.p.X)
				maxX = math.max(maxX, sp.p.X)
				minZ = math.min(minZ, sp.p.Z)
				maxZ = math.max(maxZ, sp.p.Z)
			end
		end
		if minX < math.huge then
			buildLavaSea(minX - 500, maxX + 500, minZ - 500, maxZ + 500)
			if w == 4 then
				buildVolcano(V3(minX - 380, 0, (minZ + maxZ) / 2))
			end
		end
	end
	buildEmbers(Random.new(Config.MAP_SEED + 99))
	setupLighting()

	info.totalStages = TOTAL
	info.finishStage = TOTAL + 1
	return info
end

return MapBuilder
