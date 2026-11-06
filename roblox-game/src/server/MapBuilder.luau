-- MapBuilder (ModuleScript в ServerScriptService)
-- Строит всю карту «Пол — это лава» из блоков: лобби, 50 этапов в 5 зонах,
-- финиш, пасхалки, декор, вулкан и лавовое море. Вызывается из GameServer.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LavaConfig"))

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
local ROCKS = { RGB(90, 80, 78), RGB(105, 92, 85), RGB(78, 70, 72), RGB(115, 100, 90) }
local ACCENT = {
	RGB(255, 170, 70),
	RGB(90, 200, 255),
	RGB(170, 110, 255),
	RGB(255, 70, 30),
	RGB(255, 235, 120),
}

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

local function makeSign(cf, size, text, bg, fg, face, parent)
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
	lbl.Text = text
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
	model.Parent = parent or currentFolder
	return model
end

-- ============ ТЕМАТИЧЕСКИЕ ПЛАТФОРМЫ ============
-- Возвращает часть, по которой ходят. Верх платформы = top.
local function themedPlatform(ctx, x, top, z, w, d)
	local zone = ctx.zone
	local r = ctx.rng
	local walk
	if zone == 1 then
		local kind = r:NextInteger(1, 4)
		if kind == 1 then -- стол
			walk = part({ Size = V3(w, 1, d), CFrame = L(ctx, x, top - 0.5, z), Color = WOOD, Material = M.Wood })
			for sx = -1, 1, 2 do
				for sz = -1, 1, 2 do
					column(ctx, x + sx * (w / 2 - 0.7), z + sz * (d / 2 - 0.7), LAVA_BOTTOM, top - 1, 1, 1, WOOD_DARK, M.Wood)
				end
			end
		elseif kind == 2 then -- диван
			local fabric = pick(r, FABRICS)
			walk = part({ Size = V3(w, 1.4, d), CFrame = L(ctx, x, top - 0.7, z), Color = fabric, Material = M.Fabric })
			column(ctx, x, z, LAVA_BOTTOM, top - 1.4, w, d, darker(fabric), M.Fabric)
			local side = (r:NextNumber() < 0.5) and -1 or 1
			part({ Size = V3(1.4, 4, d), CFrame = L(ctx, x + side * (w / 2 + 0.7), top + 0.6, z), Color = darker(fabric, 0.85), Material = M.Fabric })
		elseif kind == 3 then -- табурет
			local dia = math.min(w, d)
			walk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = pick(r, FABRICS), Material = M.Fabric })
			column(ctx, x, z, LAVA_BOTTOM, top - 1, 1.6, 1.6, RGB(60, 60, 65), M.Metal, true)
		else -- стопка книг на полке
			walk = part({ Size = V3(w, 1, d), CFrame = L(ctx, x, top - 0.5, z), Color = pick(r, BOOKS) })
			part({ Size = V3(w + 0.6, 1, d - 0.6), CFrame = L(ctx, x, top - 1.5, z), Color = pick(r, BOOKS) })
			part({ Size = V3(w - 0.4, 1.2, d + 0.6), CFrame = L(ctx, x, top - 2.6, z), Color = pick(r, BOOKS) })
			column(ctx, x, z, LAVA_BOTTOM, top - 3.2, w + 1.2, d + 1.2, WOOD_DARK, M.Wood)
		end
	elseif zone == 2 then
		local kind = r:NextInteger(1, 4)
		if kind == 1 then -- тарелка на стакане
			local dia = math.min(w, d) + 1
			walk = part({ Shape = CYL, Size = V3(0.8, dia, dia), CFrame = L(ctx, x, top - 0.4, z) * ROT_UP, Color = RGB(245, 245, 240) })
			part({ Shape = CYL, Size = V3(0.3, dia + 0.8, dia + 0.8), CFrame = L(ctx, x, top - 0.95, z) * ROT_UP, Color = pick(r, PLATE_RIMS) })
			local glass = column(ctx, x, z, LAVA_BOTTOM, top - 1.1, dia * 0.55, dia * 0.55, RGB(170, 220, 255), M.Glass, true)
			if glass then
				glass.Transparency = 0.45
			end
		elseif kind == 2 then -- разделочная доска на шкафчике
			walk = part({ Size = V3(w, 0.8, d), CFrame = L(ctx, x, top - 0.4, z), Color = RGB(205, 155, 100), Material = M.Wood })
			column(ctx, x, z, LAVA_BOTTOM, top - 0.8, w - 1, d - 1, RGB(235, 235, 235), M.SmoothPlastic)
		elseif kind == 3 then -- сковородка
			local dia = math.min(w, d) + 1
			walk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = L(ctx, x, top - 0.5, z) * ROT_UP, Color = RGB(45, 45, 50), Material = M.Metal })
			part({ Size = V3(dia * 0.6, 0.5, 1), CFrame = L(ctx, x + dia / 2 + dia * 0.3, top - 0.5, z), Color = RGB(30, 30, 30) })
			column(ctx, x, z, LAVA_BOTTOM, top - 1, dia * 0.4, dia * 0.4, RGB(90, 90, 95), M.Metal, true)
		else -- кусок сыра на шпажке
			walk = part({ Size = V3(w, 2, d), CFrame = L(ctx, x, top - 1, z), Color = RGB(250, 200, 60) })
			part({ Shape = BALL, Size = V3(1.4, 1.4, 1.4), CFrame = L(ctx, x + w / 2 - 0.3, top - 1, z - 1), Color = RGB(215, 165, 40), CanCollide = false })
			part({ Shape = BALL, Size = V3(1, 1, 1), CFrame = L(ctx, x - w / 2 + 0.3, top - 1.2, z + 1), Color = RGB(215, 165, 40), CanCollide = false })
			column(ctx, x, z, LAVA_BOTTOM, top - 2, 1, 1, RGB(220, 220, 225), M.Metal, true)
		end
	elseif zone == 3 then -- камень
		local rock = pick(r, ROCKS)
		walk = part({ Size = V3(w, 1.6, d), CFrame = L(ctx, x, top - 0.8, z), Color = rock, Material = M.Slate })
		part({
			Size = V3(w * 0.8, 2, d * 0.8),
			CFrame = L(ctx, x + r:NextNumber(-0.5, 0.5), top - 2.4, z) * CFrame.Angles(0, r:NextNumber(-0.4, 0.4), 0),
			Color = darker(rock),
			Material = M.Slate,
		})
		column(ctx, x, z, LAVA_BOTTOM, top - 3.2, w * 0.55, d * 0.55, darker(rock, 0.6), M.Basalt)
	elseif zone == 4 then -- базальтовая колонна
		local dia = math.min(w, d) + 0.5
		walk = part({ Shape = CYL, Size = V3(1.2, dia, dia), CFrame = L(ctx, x, top - 0.6, z) * ROT_UP, Color = RGB(48, 42, 42), Material = M.Basalt })
		part({ Shape = CYL, Size = V3(0.4, dia + 0.6, dia + 0.6), CFrame = L(ctx, x, top - 1.4, z) * ROT_UP, Color = RGB(255, 90, 20), Material = M.Neon })
		column(ctx, x, z, LAVA_BOTTOM, top - 1.6, dia - 0.6, dia - 0.6, RGB(35, 30, 30), M.Basalt, true)
	else -- облако
		local dia = math.max(w, d) + 1
		walk = part({ Shape = CYL, Size = V3(1.5, dia, dia), CFrame = L(ctx, x, top - 0.75, z) * ROT_UP, Color = RGB(250, 250, 255) })
		for i = 1, 4 do
			local a = (i / 4) * 2 * PI + r:NextNumber(0, 1)
			local s = r:NextNumber(2.5, 3.5)
			part({
				Shape = BALL,
				Size = V3(s, s, s),
				CFrame = L(ctx, x + math.cos(a) * dia * 0.45, top - 1.8, z + math.sin(a) * dia * 0.45),
				Color = RGB(255, 255, 255),
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
	addPath(L(ctx, x, top, z).Position)
	return walk
end

-- Длинная дорожка (для полос лавы, конвейера и т.п.)
local function walkway(ctx, x, top, zc, w, len)
	local zone = ctx.zone
	local p
	if zone == 1 then
		p = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, top - 0.5, zc), Color = RGB(160, 30, 40), Material = M.Fabric })
		part({ Size = V3(0.6, 1.1, len), CFrame = L(ctx, x - w / 2 + 0.3, top - 0.5, zc), Color = GOLD, Material = M.Fabric })
		part({ Size = V3(0.6, 1.1, len), CFrame = L(ctx, x + w / 2 - 0.3, top - 0.5, zc), Color = GOLD, Material = M.Fabric })
	elseif zone == 2 then
		p = part({ Size = V3(w, 1, len), CFrame = L(ctx, x, top - 0.5, zc), Color = RGB(60, 60, 66), Material = M.Metal })
	elseif zone == 3 then
		p = part({ Size = V3(w, 1.6, len), CFrame = L(ctx, x, top - 0.8, zc), Color = pick(ctx.rng, ROCKS), Material = M.Slate })
	elseif zone == 4 then
		p = part({ Size = V3(w, 1.2, len), CFrame = L(ctx, x, top - 0.6, zc), Color = RGB(40, 35, 35), Material = M.Basalt })
		part({ Size = V3(0.4, 0.3, len), CFrame = L(ctx, x - w / 2, top - 1.2, zc), Color = LAVA_COLOR, Material = M.Neon })
		part({ Size = V3(0.4, 0.3, len), CFrame = L(ctx, x + w / 2, top - 1.2, zc), Color = LAVA_COLOR, Material = M.Neon })
	else
		p = part({ Size = V3(w, 1.4, len), CFrame = L(ctx, x, top - 0.7, zc), Color = RGB(250, 250, 255) })
	end
	if not ctx.sky then
		local sc = zone == 1 and WOOD_DARK or (zone == 2 and RGB(230, 230, 230) or RGB(45, 38, 36))
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
		local gap = r:NextNumber(3.5, 4 + 2.5 * ctx.diff) - math.max(rise, 0) * 0.5
		local size = r:NextNumber(7 - 2.5 * ctx.diff, 8.5 - 2.5 * ctx.diff)
		local x = math.clamp(ctx.x + r:NextNumber(-6, 6), -10, 10)
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
		local depth = 2 + 1.5 * ctx.diff
		local tile = lavaPart({ Size = V3(w, 0.4, depth), CFrame = L(ctx, x, ctx.y + 0.2, zz + depth / 2) })
		if ctx.zone == 2 then
			tile.Color = RGB(255, 60, 30) -- конфорки плиты
		end
		if ctx.diff > 0.3 and r:NextNumber() < 0.5 then
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
		local size = 6
		local zc = ctx.z + 3.5 + size / 2
		local base = L(ctx, x, ctx.y - 0.5, zc)
		local p = part({ Size = V3(size, 1, size), CFrame = base, Color = ACCENT[ctx.zone], Material = M.SmoothPlastic })
		local glowBase = base * CF(0, -0.55, 0)
		local glow = part({ Size = V3(size + 0.2, 0.3, size + 0.2), CFrame = glowBase, Color = Color3.new(1, 1, 1), Material = M.Neon, CanCollide = false })
		local amp = 6 + 4 * ctx.diff
		local speed = 1 + 0.8 * ctx.diff
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
		RGB(255, 200, 220), -- подушки
		RGB(225, 180, 120), -- тосты
		RGB(150, 110, 80), -- рассыпающийся камень
		RGB(70, 30, 90), -- обсидиан
		RGB(235, 245, 255), -- облачка
	}
	for _ = 1, n do
		local size = 5
		local gap = 3 + 1.5 * ctx.diff
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
	local speed = 0.9 + 0.9 * ctx.diff
	local bars = ctx.diff > 0.5 and 2 or 1
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
	truss.Color = ctx.zone == 3 and RGB(60, 110, 50) or RGB(200, 200, 200)
	truss.Parent = currentFolder
	local towerD = 8
	local tz = trussZ + 1 + towerD / 2
	local newTop = ctx.y + H
	local towerColor, towerMat
	if ctx.zone == 1 then
		towerColor, towerMat = WOOD_DARK, M.Wood -- книжный шкаф
	elseif ctx.zone == 2 then
		towerColor, towerMat = RGB(240, 240, 245), M.SmoothPlastic -- холодильник
	else
		towerColor, towerMat = RGB(80, 72, 70), M.Slate -- скала
	end
	column(ctx, x, tz, LAVA_BOTTOM, newTop, 8, towerD, towerColor, towerMat)
	if ctx.zone == 1 then
		-- корешки книг по бокам шкафа
		local shelves = math.floor(H / 4)
		for i = 1, shelves do
			local y = ctx.y + i * 4 - 2
			for sx = -1, 1, 2 do
				part({ Size = V3(0.4, 2.6, towerD - 1), CFrame = L(ctx, x + sx * 4.1, y, tz), Color = pick(r, BOOKS), CanCollide = false })
			end
		end
	elseif ctx.zone == 2 then
		part({ Size = V3(0.6, 6, 0.6), CFrame = L(ctx, x + 4.2, newTop - 5, tz - 2), Color = RGB(160, 160, 165), Material = M.Metal })
		part({ Size = V3(8.1, 0.3, towerD + 0.1), CFrame = L(ctx, x, newTop - 7, tz), Color = RGB(200, 200, 205), CanCollide = false })
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
	local padColor = ctx.zone == 1 and RGB(120, 170, 255) or (ctx.zone == 2 and RGB(200, 200, 205) or RGB(90, 255, 140))
	local pad = part({ Size = V3(5, 0.6, 5), CFrame = L(ctx, x, ctx.y + 0.3, padZ), Color = padColor, Material = M.Neon })
	pad:SetAttribute("Launch", ctx.F.LookVector * 22 + V3(0, 95, 0))
	tag(pad, "Bounce")
	if ctx.zone == 2 then
		-- тостер вокруг батута
		part({ Size = V3(1, 2, 7), CFrame = L(ctx, x - 3, ctx.y + 1, padZ), Color = RGB(190, 190, 195), Material = M.Metal })
		part({ Size = V3(1, 2, 7), CFrame = L(ctx, x + 3, ctx.y + 1, padZ), Color = RGB(190, 190, 195), Material = M.Metal })
	end
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
	local width = math.max(1.2, 1.8 - 0.6 * ctx.diff)
	local rainbow = { RGB(255, 70, 70), RGB(255, 170, 40), RGB(255, 240, 60), RGB(80, 220, 90), RGB(70, 150, 255), RGB(170, 90, 255) }
	local beamColors = { RGB(200, 160, 60), RGB(240, 210, 120), RGB(95, 85, 80), RGB(60, 55, 55) }
	local top = ctx.y
	local function joint(jx, jz)
		part({ Size = V3(3, 1, 3), CFrame = L(ctx, jx, top - 0.5, jz), Color = ACCENT[ctx.zone] })
		addPath(L(ctx, jx, top, jz).Position)
	end
	local jx, jz = ctx.x, ctx.z + 3 + 1.5
	joint(jx, jz)
	local side = r:NextNumber() < 0.5 and -1 or 1
	for i = 1, segs do
		local nx = math.clamp(jx + side * r:NextNumber(5, 9), -12, 12)
		local nz = jz + r:NextNumber(8, 12)
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
	local n = r:NextInteger(5, 7)
	local colors = {
		RGB(240, 235, 220), -- свечи
		pick(r, PLATE_RIMS), -- банки
		RGB(100, 88, 82), -- сталагмиты
		RGB(42, 36, 36), -- базальт
		RGB(250, 250, 255), -- облачные столбы
	}
	for _ = 1, n do
		local dia = 3.4 - 0.8 * ctx.diff
		local gap = 3 + 1.5 * ctx.diff
		local x = math.clamp(ctx.x + r:NextNumber(-3, 3), -10, 10)
		local top = ctx.y + (ctx.flat and 0 or r:NextNumber(ctx.y < 14 and 0 or -0.5, 1.5))
		local zc = ctx.z + gap + dia / 2
		local bottom = ctx.sky and (top - 6) or LAVA_BOTTOM
		column(ctx, x, zc, bottom, top, dia, dia, ctx.zone == 2 and pick(r, PLATE_RIMS) or colors[ctx.zone], ctx.zone == 3 and M.Slate or M.SmoothPlastic, true)
		if ctx.zone == 1 then
			-- огонёк свечи сбоку
			local flame = part({ Shape = BALL, Size = V3(0.8, 0.8, 0.8), CFrame = L(ctx, x + dia / 2 + 0.3, top - 0.6, zc), Color = RGB(255, 180, 60), Material = M.Neon, CanCollide = false })
			local pl = Instance.new("PointLight")
			pl.Color = RGB(255, 170, 80)
			pl.Range = 8
			pl.Parent = flame
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
		dir = ctx.F.RightVector * (r:NextNumber() < 0.5 and -1 or 1) * (4 + 4 * ctx.diff)
	else
		dir = -ctx.F.LookVector * (6 + 6 * ctx.diff)
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
		local dia = 12 - 2 * ctx.diff
		local zc = ctx.z + 3.5 + dia / 2
		local center = L(ctx, x, ctx.y - 0.5, zc)
		local disk = part({ Shape = CYL, Size = V3(1, dia, dia), CFrame = center * ROT_UP, Color = ACCENT[ctx.zone] })
		local stripeOffset = CF(0, 0.55, 0)
		local stripe = part({ Size = V3(dia - 1, 0.2, 1.4), CFrame = center * stripeOffset, Color = Color3.new(1, 1, 1), Material = M.Neon, CanCollide = false })
		local speed = (0.5 + 0.7 * ctx.diff) * ((i % 2 == 0) and -1 or 1)
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

-- Безопасный островок над волной лавы (только зона 4)
local function island(ctx)
	local size = 7
	local zc = ctx.z + 3.5 + size / 2
	themedPlatform(ctx, ctx.x, ctx.y + 3, zc, size, size)
	ctx.z = zc + size / 2
end

local POOLS = {
	{ "jumps", "stripes", "climb", "rope", "posts", "vanish", "movers", "bounce" },
	{ "jumps", "conveyor", "spinner", "bounce", "climb", "rope", "movers", "stripes" },
	{ "jumps", "cave", "vanish", "posts", "climb", "rope", "disks", "cave" },
	{ "jumps", "movers", "spinner", "vanish", "disks", "posts", "conveyor", "stripes" },
	{ "jumps", "bounce", "rope", "movers", "vanish", "disks", "posts" },
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
	makeSign(L(ctx, 0, top + 15, z), V3(20, 5, 1.5), "ЗОНА " .. zone .. "  " .. zinfo.emoji .. " " .. zinfo.name, col, Color3.new(1, 1, 1), Enum.NormalId.Back)
end

-- ============ ЛОББИ ============
local function buildLobby(ctx)
	local top = 12
	local floor = part({ Name = "LobbyFloor", Size = V3(64, 2, 64), CFrame = L(ctx, 0, top - 1, 0), Color = RGB(170, 115, 70), Material = M.WoodPlanks })
	floor:SetAttribute("Stage", 1)
	info.checkpoints[1] = floor
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			column(ctx, sx * 28, sz * 28, LAVA_BOTTOM, top - 2, 6, 6, WOOD_DARK, M.Wood)
		end
	end
	-- ковёр
	part({ Size = V3(30, 0.2, 26), CFrame = L(ctx, 0, top + 0.1, 0), Color = RGB(150, 40, 50), Material = M.Fabric, CanCollide = false })
	part({ Size = V3(26, 0.25, 22), CFrame = L(ctx, 0, top + 0.12, 0), Color = RGB(200, 160, 60), Material = M.Fabric, CanCollide = false })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LavaSpawn"
	spawn.Anchored = true
	spawn.Size = V3(8, 1, 8)
	spawn.CFrame = L(ctx, 0, top + 0.5, -20)
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Color = RGB(255, 170, 60)
	spawn.Material = M.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = currentFolder
	info.spawnCF[1] = L(ctx, 0, top + 4, -20)

	-- приветственная табличка
	local post = RGB(80, 50, 30)
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, -26, top + 2, 20), Color = post })
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, -10, top + 2, 20), Color = post })
	makeSign(
		L(ctx, -18, top + 10, 20),
		V3(18, 12, 1),
		"🔥 ПОЛ — ЭТО ЛАВА! 🔥\n50 этапов · 5 зон\nНайди 5 секретных уточек 🦆",
		RGB(60, 20, 10),
		RGB(255, 210, 90),
		Enum.NormalId.Back
	)
	-- уточка №1 на табличке + лестница к ней сзади
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = V3(2, 16, 2)
	truss.CFrame = L(ctx, -12, top + 8, 24)
	truss.Parent = currentFolder
	part({ Size = V3(6, 1, 4), CFrame = L(ctx, -12, top + 15.5, 21), Color = post })
	makeDuck(L(ctx, -13, top + 17.5, 21) * CFrame.Angles(0, PI, 0), 1)

	-- таблица лидеров
	local board = part({ Name = "LeaderboardBoard", Size = V3(18, 14, 1), CFrame = L(ctx, 18, top + 11, 20), Color = RGB(25, 20, 30) })
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, 11, top + 2, 20), Color = post })
	part({ Size = V3(1.5, 4, 1.5), CFrame = L(ctx, 25, top + 2, 20), Color = post })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
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
	title.Text = "🏆 ЛУЧШИЕ ИГРОКИ"
	title.LayoutOrder = 0
	title.Parent = list
	info.leaderboardRows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.fromScale(1, 0.084)
		row.BackgroundTransparency = 1
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = i .. ". ---"
		row.LayoutOrder = i
		row.Parent = list
		info.leaderboardRows[i] = row
	end
	sg.Parent = board

	-- VIP-комната
	local wallC = RGB(90, 40, 120)
	local h = 10
	part({ Size = V3(16, h, 1), CFrame = L(ctx, 23, top + h / 2, -31), Color = wallC })
	part({ Size = V3(1, h, 16), CFrame = L(ctx, 31, top + h / 2, -23), Color = wallC })
	part({ Size = V3(16, h, 1), CFrame = L(ctx, 23, top + h / 2, -15), Color = wallC })
	part({ Size = V3(1, h, 5), CFrame = L(ctx, 15, top + h / 2, -28.5), Color = wallC })
	part({ Size = V3(1, h, 5), CFrame = L(ctx, 15, top + h / 2, -17.5), Color = wallC })
	part({ Size = V3(1, 1, 6), CFrame = L(ctx, 15, top + h - 0.5, -23), Color = wallC })
	part({ Size = V3(17, 1, 17), CFrame = L(ctx, 23, top + h + 0.5, -23), Color = GOLD, Material = M.Foil })
	local door = part({ Name = "VipDoor", Size = V3(1, h - 1, 6), CFrame = L(ctx, 15, top + (h - 1) / 2, -23), Color = GOLD, Material = M.Neon, Transparency = 0.35 })
	tag(door, "VipDoor")
	makeSign(L(ctx, 14.3, top + h + 2.5, -23), V3(0.5, 3, 8), "👑 VIP", RGB(90, 40, 120), GOLD, Enum.NormalId.Left)
	makeChest(L(ctx, 26, top, -27) * CFrame.Angles(0, -PI / 2, 0), "vip", "VipChest")
	makeSign(L(ctx, 30.4, top + 6, -23), V3(0.4, 4, 12), "👑 VIP-сундук\nкаждые 10 минут", RGB(60, 20, 90), GOLD, Enum.NormalId.Left)
	local vipLight = part({ Size = V3(2, 0.4, 2), CFrame = L(ctx, 23, top + h - 0.2, -23), Color = GOLD, Material = M.Neon, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range = 18
	pl.Color = GOLD
	pl.Parent = vipLight

	-- лампы по углам лобби
	for _, p in ipairs({ { -28, -28 }, { 28, 28 }, { -28, 28 } }) do
		part({ Shape = CYL, Size = V3(10, 1, 1), CFrame = L(ctx, p[1], top + 5, p[2]) * ROT_UP, Color = RGB(60, 60, 60), Material = M.Metal })
		local bulb = part({ Shape = BALL, Size = V3(2.5, 2.5, 2.5), CFrame = L(ctx, p[1], top + 11, p[2]), Color = RGB(255, 220, 150), Material = M.Neon })
		local l = Instance.new("PointLight")
		l.Range = 25
		l.Color = RGB(255, 200, 140)
		l.Parent = bulb
	end

	-- арка «СТАРТ»
	part({ Size = V3(2, 14, 2), CFrame = L(ctx, -9, top + 7, 31), Color = RGB(200, 60, 20) })
	part({ Size = V3(2, 14, 2), CFrame = L(ctx, 9, top + 7, 31), Color = RGB(200, 60, 20) })
	makeSign(L(ctx, 0, top + 15, 31), V3(20, 4, 1.5), "СТАРТ ▶", RGB(255, 90, 20), Color3.new(1, 1, 1), Enum.NormalId.Back)

	addPath(L(ctx, 0, top, 0).Position)
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			addPath(L(ctx, sx * 28, top, sz * 28).Position)
		end
	end
	ctx.x, ctx.y, ctx.z = 0, top, 32
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
	makeSign(L(ctx, 16.3, top + 4, 0), V3(0.4, 3, 6), "НЕ НАЖИМАЙ! 😈", RGB(20, 20, 20), RGB(255, 80, 80), Enum.NormalId.Left)
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
	-- «лавопад»: выглядит смертельно, но проходится насквозь
	local fall = part({
		Name = "Lavafall",
		Size = V3(0.6, 42, 12),
		CFrame = L(ctx, 7.6, top - 9, 0),
		Color = LAVA_COLOR,
		Material = M.Neon,
		Transparency = 0.15,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	})
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(RGB(255, 200, 60), RGB(255, 60, 0))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.6, 0)
	pe.Speed = NumberRange.new(2, 5)
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Rate = 15
	pe.Parent = fall
	makeChest(L(ctx, 19, top, 0) * CFrame.Angles(0, PI / 2, 0), "lavafall")
	makeDuck(L(ctx, 18, top + 1.5, 4.5) * CFrame.Angles(0, PI / 2, 0), 3)
	makeSign(L(ctx, 21.9, top + 6, 0), V3(0.4, 3, 9), "🤫 Секретная комната!", RGB(30, 20, 20), GOLD, Enum.NormalId.Left)
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
	makeSign(L(ctx, -6.5, top + 4.3, -6.5), V3(6, 2, 0.4), "⬅ НЕ ПРЫГАЙ СЮДА", RGB(250, 220, 40), RGB(20, 20, 20), Enum.NormalId.Back)
	local caveTop = math.max(top - 14, 5)
	local rock = RGB(50, 44, 44)
	part({ Size = V3(17, 1, 16), CFrame = L(ctx, -15.5, caveTop - 0.5, 0), Color = rock, Material = M.Slate })
	column(ctx, -15.5, 0, LAVA_BOTTOM, caveTop - 1, 6, 6, RGB(40, 35, 34), M.Basalt)
	part({ Size = V3(1, 10, 16), CFrame = L(ctx, -24.5, caveTop + 5, 0), Color = rock, Material = M.Slate })
	part({ Size = V3(18, 10, 1), CFrame = L(ctx, -15.5, caveTop + 5, 8.5), Color = rock, Material = M.Slate })
	part({ Size = V3(18, 10, 1), CFrame = L(ctx, -15.5, caveTop + 5, -8.5), Color = rock, Material = M.Slate })
	makeSign(L(ctx, -23.9, caveTop + 5, 0), V3(0.4, 4, 12), "Ты всё-таки прыгнул 😏", RGB(30, 25, 25), RGB(255, 220, 90), Enum.NormalId.Right)
	makeChest(L(ctx, -21, caveTop, -4) * CFrame.Angles(0, -PI / 2, 0), "dontjump")
	makeDuck(L(ctx, -19, caveTop + 1.5, 3) * CFrame.Angles(0, -PI / 2, 0), 4)
	local tp = part({ Name = "Teleporter", Size = V3(4, 0.4, 4), CFrame = L(ctx, -12, caveTop + 0.2, 5), Color = RGB(60, 230, 255), Material = M.Neon })
	tag(tp, "Teleport")
	makeSign(L(ctx, -12, caveTop + 3.5, 7.9), V3(5, 1.6, 0.3), "↩ Назад", RGB(20, 60, 80), Color3.new(1, 1, 1), Enum.NormalId.Back)
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

local function buildFinish(ctx)
	local top = ctx.y
	part({ Size = V3(6, 3, 6), CFrame = L(ctx, 0, top + 1.5, 9), Color = RGB(60, 40, 20), Material = M.Wood })
	part({ Shape = CYL, Size = V3(3, 1.6, 1.6), CFrame = L(ctx, 0, top + 4.5, 9) * ROT_UP, Color = GOLD, Material = M.Foil })
	local cup = part({ Shape = CYL, Size = V3(4, 5, 5), CFrame = L(ctx, 0, top + 8, 9) * ROT_UP, Color = GOLD, Material = M.Neon })
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = GOLD
	sp.Parent = cup
	makeSign(L(ctx, 0, top + 16, 14), V3(26, 8, 1), "🏆 ТЫ ПРОШЁЛ «ПОЛ — ЭТО ЛАВА»!\nЖми 🔁 Перерождение", RGB(50, 20, 80), GOLD, Enum.NormalId.Back)
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

local function decor(zone, pos, rng, pathY)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, 2 * PI), 0)
	local base = CF(pos.X, 0, pos.Z) * yaw
	local h = math.max(12, pathY + rng:NextNumber(-12, 14))
	local function at(x, y, z)
		return base * CF(x, y, z)
	end
	local kind = rng:NextInteger(1, 3)
	if zone == 1 then
		if kind == 1 then -- торшер
			part({ Shape = CYL, Size = V3(h + 2, 1.6, 1.6), CFrame = at(0, (h - 2) / 2, 0) * ROT_UP, Color = RGB(70, 70, 75), Material = M.Metal })
			part({ Shape = CYL, Size = V3(7, 11, 11), CFrame = at(0, h + 2, 0) * ROT_UP, Color = RGB(250, 230, 190), Material = M.Fabric })
			local bulb = part({ Shape = BALL, Size = V3(3, 3, 3), CFrame = at(0, h - 1.5, 0), Color = RGB(255, 230, 160), Material = M.Neon, CanCollide = false })
			local l = Instance.new("PointLight")
			l.Range = 40
			l.Brightness = 1.5
			l.Color = RGB(255, 200, 140)
			l.Parent = bulb
		elseif kind == 2 then -- цветок в горшке
			part({ Shape = CYL, Size = V3(h + 2, 12, 12), CFrame = at(0, (h - 2) / 2, 0) * ROT_UP, Color = RGB(190, 95, 55) })
			for i = 1, 5 do
				local s = rng:NextNumber(7, 11)
				part({ Shape = BALL, Size = V3(s, s, s), CFrame = at(rng:NextNumber(-4, 4), h + rng:NextNumber(2, 7), rng:NextNumber(-4, 4)), Color = RGB(60, 150 + i * 10, 70), Material = M.Grass })
			end
		else -- шкаф с книгами
			part({ Size = V3(12, h + 2, 7), CFrame = at(0, (h - 2) / 2, 0), Color = WOOD_DARK, Material = M.Wood })
			for i = 1, math.floor(h / 6) do
				for j = 0, 3 do
					part({ Size = V3(2.2, 3.6, 0.5), CFrame = at(-4.2 + j * 2.8, i * 6 - 2, -3.6), Color = pick(rng, BOOKS), CanCollide = false })
				end
			end
		end
	elseif zone == 2 then
		if kind == 1 then -- кружка
			part({ Shape = CYL, Size = V3(h + 2, 14, 14), CFrame = at(0, (h - 2) / 2, 0) * ROT_UP, Color = pick(rng, PLATE_RIMS) })
			part({ Shape = CYL, Size = V3(0.5, 12.5, 12.5), CFrame = at(0, h + 0.1, 0) * ROT_UP, Color = RGB(90, 50, 25), CanCollide = false })
			part({ Size = V3(2, 8, 2), CFrame = at(8.5, h - 6, 0), Color = Color3.new(1, 1, 1) })
		elseif kind == 2 then -- вилка
			part({ Size = V3(2.5, h + 2, 1), CFrame = at(0, (h - 2) / 2, 0), Color = RGB(200, 200, 210), Material = M.Metal })
			part({ Size = V3(7, 3, 1), CFrame = at(0, h + 1.5, 0), Color = RGB(200, 200, 210), Material = M.Metal })
			for i = 0, 3 do
				part({ Size = V3(0.9, 8, 0.9), CFrame = at(-3 + i * 2, h + 7, 0), Color = RGB(200, 200, 210), Material = M.Metal })
			end
		else -- стопка тарелок
			part({ Shape = CYL, Size = V3(h + 2, 10, 10), CFrame = at(0, (h - 2) / 2, 0) * ROT_UP, Color = RGB(230, 230, 235) })
			for i = 1, 5 do
				part({ Shape = CYL, Size = V3(1, 16, 16), CFrame = at(0, h + i * 1.2, 0) * ROT_UP, Color = i % 2 == 0 and Color3.new(1, 1, 1) or pick(rng, PLATE_RIMS) })
			end
		end
	elseif zone == 3 then
		if kind == 1 then -- скала с огнём
			local w = rng:NextNumber(8, 14)
			local rp = part({ Size = V3(w, h + 2, w), CFrame = at(0, (h - 2) / 2, 0), Color = pick(rng, ROCKS), Material = M.Slate })
			local f = Instance.new("Fire")
			f.Size = 10
			f.Heat = 15
			f.Parent = rp
		elseif kind == 2 then -- кристаллы
			for i = 1, 4 do
				part({
					Size = V3(2.5, rng:NextNumber(10, 22), 2.5),
					CFrame = at(rng:NextNumber(-4, 4), 4, rng:NextNumber(-4, 4)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)),
					Color = i % 2 == 0 and RGB(170, 90, 255) or RGB(80, 220, 255),
					Material = M.Neon,
				})
			end
		else -- сталагмит
			local w = 12
			for i = 0, 3 do
				part({ Size = V3(w - i * 3, h / 4 + 2, w - i * 3), CFrame = at(0, i * h / 4 + h / 8, 0), Color = darker(RGB(110, 95, 88), 1 - i * 0.08), Material = M.Slate })
			end
		end
	elseif zone == 4 then
		if kind == 1 then -- базальтовые столбы
			for i = 1, 4 do
				local ch = rng:NextNumber(h * 0.4, h)
				local d = rng:NextNumber(4, 7)
				part({ Shape = CYL, Size = V3(ch, d, d), CFrame = at(rng:NextNumber(-5, 5), ch / 2 - 1, rng:NextNumber(-5, 5)) * ROT_UP, Color = RGB(40, 35, 35), Material = M.Basalt })
			end
		elseif kind == 2 then -- лавовый гейзер
			local g = part({ Size = V3(6, 1, 6), CFrame = at(0, 0.3, 0), Color = RGB(60, 30, 20), Material = M.Basalt })
			local em = Instance.new("ParticleEmitter")
			em.Color = ColorSequence.new(RGB(255, 220, 80), RGB(255, 50, 0))
			em.LightEmission = 1
			em.Size = NumberSequence.new(2.5, 0.5)
			em.Speed = NumberRange.new(40, 70)
			em.SpreadAngle = Vector2.new(10, 10)
			em.Acceleration = V3(0, -40, 0)
			em.Lifetime = NumberRange.new(1.5, 2.5)
			em.Rate = 40
			em.EmissionDirection = Enum.NormalId.Top
			em.Parent = g
			local f = Instance.new("Fire")
			f.Size = 8
			f.Parent = g
		else -- обсидиан
			part({ Size = V3(5, rng:NextNumber(14, 26), 5), CFrame = at(0, 6, 0) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), Color = RGB(50, 20, 70), Material = M.Glass })
		end
	else
		if kind == 1 then -- облако
			local y = pathY - rng:NextNumber(15, 40)
			for i = 1, 6 do
				local s = rng:NextNumber(8, 16)
				part({ Shape = BALL, Size = V3(s, s, s), CFrame = at(i * 5 - 15, y + rng:NextNumber(-2, 3), rng:NextNumber(-4, 4)), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
			end
		elseif kind == 2 then -- парящий остров с деревом
			local y = pathY + rng:NextNumber(8, 25)
			part({ Shape = CYL, Size = V3(2, 18, 18), CFrame = at(0, y, 0) * ROT_UP, Color = RGB(90, 180, 80), Material = M.Grass })
			part({ Shape = CYL, Size = V3(6, 14, 14), CFrame = at(0, y - 4, 0) * ROT_UP, Color = RGB(110, 80, 55), Material = M.Ground })
			part({ Size = V3(1.5, 8, 1.5), CFrame = at(0, y + 5, 0), Color = RGB(100, 70, 40), Material = M.Wood })
			part({ Shape = BALL, Size = V3(8, 8, 8), CFrame = at(0, y + 10, 0), Color = RGB(255, 160, 200), Material = M.Grass })
		else -- радуга
			local R = 30
			local y = pathY - 30
			local bands = { RGB(255, 70, 70), RGB(255, 200, 50), RGB(80, 160, 255) }
			for b, col in ipairs(bands) do
				local rr = R - (b - 1) * 3
				local prev = nil
				for i = 0, 12 do
					local a = (i / 12) * PI
					local pt = (base * CF(math.cos(a) * rr, y + math.sin(a) * rr, 0)).Position
					if prev then
						part({ Size = V3(3, 1.5, (pt - prev).Magnitude + 0.5), CFrame = CFrame.lookAt((pt + prev) / 2, pt), Color = col, Material = M.Neon, CanCollide = false, CastShadow = false })
					end
					prev = pt
				end
			end
		end
	end
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
	Lighting.ClockTime = 17.8
	Lighting.Brightness = 2
	Lighting.Ambient = RGB(90, 60, 50)
	Lighting.OutdoorAmbient = RGB(150, 100, 80)
	Lighting.EnvironmentDiffuseScale = 0.5
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.32
	atmo.Offset = 0.25
	atmo.Color = RGB(255, 150, 90)
	atmo.Decay = RGB(120, 60, 40)
	atmo.Glare = 0.3
	atmo.Haze = 1.6
	atmo.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.TintColor = RGB(255, 245, 235)
	cc.Parent = Lighting
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
		pathPoints = {},
		leaderboardRows = {},
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
	local pattern = { -1, -1, 1, 1 } -- направо, направо, налево, налево — «змейка»

	for s = 1, TOTAL do
		local folder = Instance.new("Folder")
		folder.Name = string.format("Stage_%02d", s)
		folder.Parent = map
		currentFolder = folder

		ctx.stage = s
		ctx.zone = Config.ZoneOfStage(s)
		ctx.diff = (s - 1) / (TOTAL - 1)
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
			local last = nil
			for _ = 1, count do
				local name
				for _ = 1, 10 do
					name = pool[r:NextInteger(1, #pool)]
					local tooHigh = CLIMBING[name] and ctx.y > 60 * ctx.zone
					if name ~= last and not tooHigh then
						break
					end
				end
				table.insert(plan, name)
				last = name
			end
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
	for _, sf in ipairs(stageFrames) do
		for _ = 1, 6 do
			local z = drng:NextNumber(0, sf.len)
			local side = drng:NextNumber() < 0.5 and -1 or 1
			local x = side * drng:NextNumber(32, 60)
			local pos = (sf.F * CF(x, 0, -z)).Position
			if farFromPath(pos, 26) then
				decor(sf.zone, pos, drng, sf.y)
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
