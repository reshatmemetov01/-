-- GameServer (Script в ServerScriptService)
-- Строит карту и управляет игрой: чекпоинты, лава, сохранения, монеты,
-- пасхалки, покупки за Robux, перерождения и таблица лидеров.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local BadgeService = game:GetService("BadgeService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LavaConfig"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

Players.RespawnTime = 1

-- ============ REMOTES (создаём до постройки карты) ============
local remotes = Instance.new("Folder")
remotes.Name = "LavaRemotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local NotifyRE = remote("Notify") -- сервер → клиент: текст
local CoinRE = remote("CoinHidden") -- сервер → клиент: спрятать монетку
local EffectRE = remote("Effect") -- сервер → клиент: эффекты
local ActionRE = remote("Action") -- клиент → сервер: действия игрока
remotes.Parent = ReplicatedStorage

local map = MapBuilder.Build()
workspace:SetAttribute("MapReady", true)
local FINISH = map.finishStage

-- ============ ДАННЫЕ ============
local store, topStore
pcall(function()
	store = DataStoreService:GetDataStore(Config.DATA_KEY)
	topStore = DataStoreService:GetOrderedDataStore(Config.LEADERBOARD_KEY)
end)

local sessions = {}

local function defaultData()
	return {
		stage = 1,
		maxStage = 1,
		coins = 0,
		rebirths = 0,
		ducks = {},
		secrets = {},
		trails = {},
		trail = "",
		skins = {},
		skin = "",
		pets = {},
		auras = {},
		aura = "",
		perks = {},
		pet = "",
		daily = 0,
		streak = 0,
		finishedRun = false,
		vipChest = 0,
		receipts = {},
		autoEquipped = {},
		chDay = 0, -- задания дня
		chProgress = {},
		chDone = {},
		dcDay = 0, -- сундуки дня
		dcFound = {},
		bestTime = 0, -- лучшее время прохождения (сек)
	}
end

-- Сообщения отправляются «ключом» из LavaText, клиент переводит на язык игрока.
local function notify(player, key, color, ...)
	NotifyRE:FireClient(player, key, color, { ... })
end

local function notifyAll(key, color, ...)
	NotifyRE:FireAllClients(key, color, { ... })
end

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function csvKeys(t)
	local list = {}
	for k in pairs(t) do
		table.insert(list, tostring(k))
	end
	table.sort(list)
	return table.concat(list, ",")
end

local ownsItem -- объявлена ниже

local function multiplier(player, s)
	local m = 1 + s.data.rebirths * Config.REBIRTH_BONUS
	local pet = Config.GetItem("pets", s.data.pet)
	if pet and ownsItem and ownsItem(player, s, "pets", pet) then
		m *= 1 + pet.bonus
	end
	if s.data.perks.lucky then
		m *= Config.PERK_LUCKY_BONUS
	end
	if player:GetAttribute("PassDoubleCoins") then
		m *= 2
	end
	if player:GetAttribute("PassVIP") then
		m *= Config.VIP_COIN_BONUS
	end
	if workspace:GetAttribute("Event") == "golden" then
		m *= 2 -- 💰 золотой час
	end
	return m
end

local function syncAttributes(player)
	local s = sessions[player]
	if not s then
		return
	end
	local d = s.data
	player:SetAttribute("Stage", d.stage)
	player:SetAttribute("MaxStage", d.maxStage)
	player:SetAttribute("Coins", d.coins)
	player:SetAttribute("Rebirths", d.rebirths)
	player:SetAttribute("Ducks", countKeys(d.ducks))
	player:SetAttribute("DucksList", csvKeys(d.ducks))
	player:SetAttribute("Trails", csvKeys(d.trails))
	player:SetAttribute("Trail", d.trail)
	player:SetAttribute("Skins", csvKeys(d.skins))
	player:SetAttribute("Skin", d.skin)
	player:SetAttribute("Pets", csvKeys(d.pets))
	player:SetAttribute("Pet", d.pet)
	player:SetAttribute("Auras", csvKeys(d.auras))
	player:SetAttribute("Aura", d.aura)
	player:SetAttribute("Perks", csvKeys(d.perks))
	player:SetAttribute("NextGift", s.nextGift)
	player:SetAttribute("Multiplier", multiplier(player, s))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["Stage"].Value = math.min(d.stage, Config.TOTAL_STAGES)
		ls["Coins"].Value = d.coins
		ls["Rebirths"].Value = d.rebirths
	end
end

-- ============ ЗАДАНИЯ ДНЯ ============
local HttpService = game:GetService("HttpService")

local function today()
	return math.floor(os.time() / 86400)
end

local challengeCache = {}
local function todaysChallenges(day)
	if challengeCache[day] then
		return challengeCache[day]
	end
	local rng = Random.new(day * 7349 + 11)
	local pool = table.clone(Config.Challenges)
	local list, usedKinds = {}, {}
	while #list < Config.CHALLENGES_PER_DAY and #pool > 0 do
		local c = table.remove(pool, rng:NextInteger(1, #pool))
		if not usedKinds[c.kind] then
			usedKinds[c.kind] = true
			table.insert(list, c)
		end
	end
	challengeCache[day] = list
	return list
end

local function ensureChallengeDay(s)
	local d = s.data
	local day = today()
	if d.chDay ~= day then
		d.chDay = day
		d.chProgress = {}
		d.chDone = {}
	end
end

local function syncChallenges(player)
	local s = sessions[player]
	if not s then
		return
	end
	ensureChallengeDay(s)
	local out = {}
	for _, c in ipairs(todaysChallenges(s.data.chDay)) do
		table.insert(out, {
			id = c.id,
			kind = c.kind,
			goal = c.goal,
			reward = c.reward,
			progress = math.min(s.data.chProgress[c.id] or 0, c.goal),
			done = s.data.chDone[c.id] == true,
		})
	end
	player:SetAttribute("Challenges", HttpService:JSONEncode(out))
end

-- absolute = true: прогресс — это текущее значение (например, серия без смертей)
local function progressChallenge(player, kind, amount, absolute)
	local s = sessions[player]
	if not s or not s.loaded then
		return
	end
	ensureChallengeDay(s)
	local changed = false
	for _, c in ipairs(todaysChallenges(s.data.chDay)) do
		if c.kind == kind and not s.data.chDone[c.id] then
			local cur = s.data.chProgress[c.id] or 0
			local new = absolute and math.max(cur, amount) or (cur + amount)
			if new ~= cur then
				s.data.chProgress[c.id] = new
				changed = true
			end
			if new >= c.goal then
				s.data.chDone[c.id] = true
				s.data.coins += c.reward
				notify(player, "n_challenge_done", Color3.fromRGB(120, 255, 140), c.reward)
				EffectRE:FireClient(player, "duck")
				changed = true
			end
		end
	end
	if changed then
		syncChallenges(player)
		syncAttributes(player)
	end
end

local function addCoins(player, amount, useMultiplier)
	local s = sessions[player]
	if not s then
		return 0
	end
	local gained = useMultiplier and math.floor(amount * multiplier(player, s) + 0.5) or amount
	s.data.coins += gained
	syncAttributes(player)
	if useMultiplier then
		progressChallenge(player, "coins", gained)
	end
	return gained
end

local function awardBadge(player, badgeId)
	if badgeId and badgeId ~= 0 then
		task.spawn(function()
			pcall(function()
				BadgeService:AwardBadge(player.UserId, badgeId)
			end)
		end)
	end
end

local function saveData(player)
	local s = sessions[player]
	if not s or not s.loaded or s.noSave or not store then
		return
	end
	local d = s.data
	local ok, err = pcall(function()
		store:UpdateAsync("u_" .. player.UserId, function()
			return d
		end)
	end)
	if not ok then
		warn("[LavaObby] Не удалось сохранить", player.Name, err)
	end
	if topStore then
		pcall(function()
			topStore:SetAsync(tostring(player.UserId), d.rebirths * 1000 + math.min(d.maxStage, FINISH))
		end)
	end
end

local function loadData(player)
	local data = nil
	local ok = false
	if store then
		for attempt = 1, 3 do
			ok = pcall(function()
				data = store:GetAsync("u_" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
	end
	local result = defaultData()
	if type(data) == "table" then
		for k, v in pairs(data) do
			result[k] = v
		end
	end
	result.stage = math.clamp(math.floor(tonumber(result.stage) or 1), 1, FINISH)
	result.maxStage = math.clamp(math.floor(tonumber(result.maxStage) or 1), result.stage, FINISH)
	return result, ok
end

-- ============ ПЕРСОНАЖ ============
local function getCharacterParts(player)
	local char = player.Character
	if not char then
		return nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function teleportToStage(player)
	local s = sessions[player]
	local char, hum, root = getCharacterParts(player)
	if not s or not char or not root then
		return
	end
	local cf
	if s.inLobby then
		cf = map.lobbySpawn
	else
		cf = map.spawnCF[s.data.stage] or map.spawnCF[1]
	end
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(cf)
	s.lastSafe = cf
end

-- 🏠 лобби / 🌍 мир
local function setInLobby(player, inLobby)
	local s = sessions[player]
	if not s then
		return
	end
	s.inLobby = inLobby
	player:SetAttribute("InLobby", inLobby)
end

local function worldRange(w)
	local first = (w - 1) * Config.STAGES_PER_ZONE + 1
	return first, math.min(w * Config.STAGES_PER_ZONE, Config.TOTAL_STAGES)
end

local function applyTrail(player)
	local s = sessions[player]
	local _, _, root = getCharacterParts(player)
	if not s or not root then
		return
	end
	local old = root:FindFirstChild("LavaTrail")
	if old then
		old:Destroy()
	end
	for _, a in ipairs(root:GetChildren()) do
		if a.Name == "LavaTrailAtt" then
			a:Destroy()
		end
	end
	local t = Config.GetTrail(s.data.trail)
	if not t or not ownsItem(player, s, "trails", t) then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "LavaTrailAtt"
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "LavaTrailAtt"
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "LavaTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.LightEmission = 0.7
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0, 1)
	local kps = {}
	local n = #t.colors
	for i, c in ipairs(t.colors) do
		table.insert(kps, ColorSequenceKeypoint.new(n == 1 and 0 or (i - 1) / (n - 1), c))
	end
	if n == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, t.colors[1]))
	end
	trail.Color = ColorSequence.new(kps)
	trail.Parent = root
end

local function applyOverhead(player)
	local s = sessions[player]
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not s or not head then
		return
	end
	local old = head:FindFirstChild("LavaTag")
	if old then
		old:Destroy()
	end
	local parts = {}
	if player:GetAttribute("PassVIP") then
		table.insert(parts, "👑 VIP")
	end
	if s.data.rebirths > 0 then
		table.insert(parts, "🔁 " .. s.data.rebirths)
	end
	if countKeys(s.data.ducks) >= Config.DUCK_COUNT then
		table.insert(parts, "🦆")
	end
	if #parts == 0 then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "LavaTag"
	bb.Size = UDim2.fromOffset(160, 30)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 80
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = Color3.fromRGB(255, 215, 80)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = table.concat(parts, "  ")
	lbl.Parent = bb
	bb.Parent = head
end

-- ============ СКИНЫ ============
-- ============ ДЕТАЛИ ДЛЯ ПИТОМЦЕВ И СКИНОВ ============
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local MAT = Enum.Material
local RGB = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local UPR = CFrame.Angles(0, 0, math.pi / 2) -- цилиндр «стоя»

-- kind: "block" | "ball" | "egg" (овал) | "cyl" | "wedge"
local function shape(parent, kind, size, cf, color, material, extra)
	local p = kind == "wedge" and Instance.new("WedgePart") or Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or MAT.SmoothPlastic
	p.Color = color
	if kind == "ball" then
		p.Shape = BALL
	elseif kind == "cyl" then
		p.Shape = CYL
	end
	p.Size = size
	p.CFrame = cf
	if kind == "egg" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Мультяшный глаз с бликом
local function cuteEye(model, cf, r)
	shape(model, "ball", V(r, r, r), cf, RGB(20, 20, 28))
	shape(model, "ball", V(r * 0.4, r * 0.4, r * 0.4), cf * CF(r * 0.18, r * 0.2, -r * 0.36), RGB(255, 255, 255), MAT.Neon)
end

-- Деталь, которая машет (крылья, хвост). Клиент её анимирует.
local function flap(part, hinge, amp, speed, axis)
	part:SetAttribute("Hinge", hinge)
	part:SetAttribute("FromHinge", hinge:Inverse() * part.CFrame)
	part:SetAttribute("Flap", amp)
	part:SetAttribute("FlapSpeed", speed or 8)
	part:SetAttribute("FlapAxis", axis or "z")
	return part
end

local function addLight(part, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 8
	l.Brightness = 1.2
	l.Parent = part
end

-- ============ СКИНЫ ============
local function torsoOf(char)
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

local function clearSkinExtras(char)
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "LavaSkinExtra" then
			d:Destroy()
		end
	end
end

-- Деталь, приваренная к голове: offset — относительно центра головы
local function headExtra(head, kind, size, offset, color, material, extra)
	local p = shape(head.Parent, kind, size, head.CFrame * offset, color, material, extra)
	p.Anchored = false
	p.Name = "LavaSkinExtra"
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = p
	w.Parent = p
	return p
end

local function skinFx(parent, className, props)
	local fx = Instance.new(className)
	fx.Name = "LavaSkinExtra"
	for k, v in pairs(props) do
		fx[k] = v
	end
	fx.Parent = parent
	return fx
end

local function particles(parent, colors, rate, size)
	local kps = {}
	for i, c in ipairs(colors) do
		table.insert(kps, ColorSequenceKeypoint.new(#colors == 1 and 0 or (i - 1) / (#colors - 1), c))
	end
	if #colors == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return skinFx(parent, "ParticleEmitter", {
		Color = ColorSequence.new(kps),
		LightEmission = 0.8,
		Size = NumberSequence.new(size or 0.3, 0),
		Lifetime = NumberRange.new(0.8, 1.5),
		Rate = rate or 10,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
	})
end

local function addSkinExtras(char, skin)
	local head = char:FindFirstChild("Head")
	local torso = torsoOf(char)
	if not head or not torso then
		return
	end
	local hy, hx, hz = head.Size.Y, head.Size.X, head.Size.Z
	local k = hy / 1.2
	local topY = hy / 2
	local front = -hz / 2
	local id = skin.id
	if id == "gold" then -- корона
		headExtra(head, "cyl", V(0.35 * k, 1.15 * k, 1.15 * k), CF(0, topY + 0.12 * k, 0) * UPR, RGB(255, 200, 50), MAT.Foil)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			headExtra(head, "wedge", V(0.22 * k, 0.4 * k, 0.12 * k), CF(math.sin(a) * 0.5 * k, topY + 0.48 * k, math.cos(a) * 0.5 * k) * ANG(0, a, 0), RGB(255, 210, 60), MAT.Foil)
		end
		local gems = { RGB(255, 40, 60), RGB(40, 150, 255), RGB(60, 230, 90) }
		for i, c in ipairs(gems) do
			headExtra(head, "ball", V(0.16 * k, 0.16 * k, 0.16 * k), CF((i - 2) * 0.3 * k, topY + 0.14 * k, -0.56 * k), c, MAT.Neon)
		end
		skinFx(head, "Sparkles", { SparkleColor = RGB(255, 220, 90) })
	elseif id == "ice" then -- ледяная корона
		for i = 0, 6 do
			local a = i / 7 * math.pi * 2
			local h = (i % 2 == 0) and 0.7 or 0.45
			headExtra(head, "block", V(0.16 * k, h * k, 0.16 * k), CF(math.sin(a) * 0.45 * k, topY + h * 0.4 * k, math.cos(a) * 0.45 * k) * ANG(math.cos(a) * 0.25, 0, -math.sin(a) * 0.25), RGB(190, 235, 255), MAT.Glass, { Transparency = 0.2 })
		end
		particles(torso, { RGB(255, 255, 255), RGB(160, 220, 255) }, 8, 0.25)
	elseif id == "robot" then -- визор и антенна
		headExtra(head, "block", V(hx * 1.04, 0.26 * k, 0.12), CF(0, 0.08 * k, front - 0.03), RGB(60, 230, 255), MAT.Neon)
		headExtra(head, "block", V(0.08, 0.5 * k, 0.08), CF(0.25 * k, topY + 0.25 * k, 0), RGB(120, 125, 135), MAT.Metal)
		local tip = headExtra(head, "ball", V(0.22, 0.22, 0.22), CF(0.25 * k, topY + 0.55 * k, 0), RGB(255, 50, 50), MAT.Neon)
		addLight(tip, RGB(255, 60, 60), 6)
	elseif id == "shadow" then -- красные глаза и дым
		for sx = -1, 1, 2 do
			local e = headExtra(head, "ball", V(0.2 * k, 0.2 * k, 0.2 * k), CF(sx * 0.2 * k, 0.12 * k, front - 0.02), RGB(255, 30, 30), MAT.Neon)
			if sx == 1 then
				addLight(e, RGB(255, 40, 40), 6)
			end
		end
		skinFx(torso, "Smoke", { Color = RGB(20, 20, 25), Size = 1.5, Opacity = 0.2, RiseVelocity = 1 })
	elseif id == "duckskin" then -- утиный клюв и хохолок
		headExtra(head, "egg", V(0.7 * k, 0.2 * k, 0.5 * k), CF(0, -0.08 * k, front - 0.15 * k), RGB(255, 140, 20))
		headExtra(head, "egg", V(0.1 * k, 0.45 * k, 0.25 * k), CF(0, topY + 0.15 * k, 0) * ANG(-0.3, 0, 0), RGB(255, 225, 40))
	elseif id == "marble" then -- лавровый венок
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			headExtra(head, "egg", V(0.12 * k, 0.12 * k, 0.32 * k), CF(math.sin(a) * 0.58 * k, 0.32 * k, math.cos(a) * 0.58 * k) * ANG(0, a + 0.6, 0.4), RGB(90, 160, 70))
		end
	elseif id == "grass" then -- цветок на голове
		headExtra(head, "block", V(0.06, 0.45 * k, 0.06), CF(0, topY + 0.22 * k, 0), RGB(60, 150, 50))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			headExtra(head, "ball", V(0.2 * k, 0.2 * k, 0.2 * k), CF(math.sin(a) * 0.15 * k, topY + 0.5 * k, math.cos(a) * 0.15 * k), RGB(255, 120, 180))
		end
		headExtra(head, "ball", V(0.16 * k, 0.16 * k, 0.16 * k), CF(0, topY + 0.52 * k, 0), RGB(255, 220, 50))
	elseif id == "wood" then -- росток
		headExtra(head, "block", V(0.06, 0.35 * k, 0.06), CF(0, topY + 0.17 * k, 0), RGB(80, 140, 50))
		headExtra(head, "egg", V(0.4 * k, 0.06, 0.2 * k), CF(0.18 * k, topY + 0.35 * k, 0) * ANG(0, 0, 0.4), RGB(90, 190, 70))
		headExtra(head, "egg", V(0.4 * k, 0.06, 0.2 * k), CF(-0.18 * k, topY + 0.32 * k, 0) * ANG(0, 0, -0.4), RGB(90, 190, 70))
	elseif id == "metal" then -- шлем рыцаря с пером
		headExtra(head, "block", V(hx * 1.08, 0.08 * k, 0.1), CF(0, 0.12 * k, front - 0.02), RGB(40, 40, 45))
		headExtra(head, "egg", V(0.15 * k, 0.8 * k, 0.5 * k), CF(0, topY + 0.3 * k, 0.1 * k) * ANG(-0.3, 0, 0), RGB(210, 30, 40))
	elseif id == "lava" then
		skinFx(torso, "Fire", { Size = 3, Heat = 4, Color = RGB(255, 120, 20), SecondaryColor = RGB(255, 40, 0) })
		particles(torso, { RGB(255, 220, 80), RGB(255, 60, 0) }, 10, 0.3)
	elseif id == "neon" or id == "toxicneon" then
		addLight(torso, skin.color, 12)
		torso:FindFirstChildOfClass("PointLight").Name = "LavaSkinExtra"
	elseif id == "ghost" then
		addLight(torso, RGB(180, 220, 255), 10)
		torso:FindFirstChildOfClass("PointLight").Name = "LavaSkinExtra"
		particles(torso, { RGB(220, 240, 255) }, 6, 0.4)
	elseif id == "diamond" then
		skinFx(torso, "Sparkles", { SparkleColor = RGB(200, 245, 255) })
	elseif id == "galaxy" then
		particles(torso, { RGB(255, 255, 255), RGB(180, 120, 255), RGB(80, 60, 200) }, 14, 0.25)
	elseif id == "rainbow" then
		particles(torso, { RGB(255, 60, 60), RGB(255, 200, 40), RGB(60, 220, 90), RGB(60, 140, 255), RGB(190, 80, 255) }, 14, 0.3)
	end
end

local function applySkin(player)
	local s = sessions[player]
	local char = player.Character
	if not s or not char then
		return
	end
	local skin = Config.GetItem("skins", s.data.skin)
	if not skin or not ownsItem(player, s, "skins", skin) then
		return
	end
	clearSkinExtras(char)
	local okMat, material = pcall(function()
		return Enum.Material[skin.material]
	end)
	if not okMat or not material then
		material = Enum.Material.SmoothPlastic
	end
	local i = 0
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("SurfaceAppearance") then
			-- SurfaceAppearance (новые головы/тела) закрывает цвет — убираем
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			i += 1
			if d:IsA("MeshPart") then
				pcall(function()
					d.TextureID = ""
				end)
			end
			d.Color = skin.colors and skin.colors[(i % #skin.colors) + 1] or skin.color
			d.Material = material
		end
	end
	local ok, err = pcall(addSkinExtras, char, skin)
	if not ok then
		warn("[LavaObby] skin extras:", err)
	end
end

-- ============ ПИТОМЦЫ ============
local petFolder = Instance.new("Folder")
petFolder.Name = "LavaPets"
petFolder.Parent = workspace

local PetBuilders = {}

local function duckBase(m, gold)
	local mat = gold and MAT.Foil or MAT.SmoothPlastic
	local yellow = gold and RGB(255, 200, 40) or RGB(255, 222, 50)
	local root = shape(m, "egg", V(1.5, 1.25, 1.8), CF(), yellow, mat)
	shape(m, "egg", V(1.15, 0.8, 1.3), CF(0, -0.2, -0.1), yellow:Lerp(Color3.new(1, 1, 1), 0.25), mat)
	shape(m, "ball", V(1.05, 1.05, 1.05), CF(0, 0.85, -0.6), yellow, mat)
	shape(m, "egg", V(0.62, 0.2, 0.55), CF(0, 0.72, -1.15), RGB(255, 140, 20))
	shape(m, "egg", V(0.5, 0.12, 0.42), CF(0, 0.6, -1.1), RGB(235, 110, 10))
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.26, 0.95, -1.02), 0.2)
		shape(m, "egg", V(0.22, 0.12, 0.06), CF(sx * 0.38, 0.75, -1.0), RGB(255, 150, 160))
		local hinge = CF(sx * 0.62, 0.3, 0)
		flap(shape(m, "egg", V(0.25, 0.75, 1.05), CF(sx * 0.78, 0.02, 0.05) * ANG(0, 0, sx * 0.15), yellow:Lerp(RGB(255, 170, 0), 0.3), mat), hinge, sx * 0.35, 9)
		shape(m, "egg", V(0.42, 0.12, 0.5), CF(sx * 0.3, -0.66, -0.2), RGB(255, 140, 20))
	end
	shape(m, "wedge", V(0.5, 0.45, 0.45), CF(0, 0.25, 0.95) * ANG(0, math.pi, 0), yellow, mat)
	return root
end

PetBuilders.duckling = function(m)
	local root = duckBase(m, false)
	shape(m, "egg", V(0.1, 0.38, 0.22), CF(0, 1.45, -0.55) * ANG(-0.3, 0, 0), RGB(255, 222, 50))
	return root
end

PetBuilders.goldduck = function(m)
	local root = duckBase(m, true)
	shape(m, "cyl", V(0.25, 0.7, 0.7), CF(0, 1.42, -0.6) * UPR, RGB(255, 200, 40), MAT.Foil)
	for i = -1, 1 do
		shape(m, "ball", V(0.16, 0.16, 0.16), CF(i * 0.2, 1.62, -0.6), i == 0 and RGB(255, 40, 60) or RGB(60, 160, 255), MAT.Neon)
	end
	Instance.new("Sparkles").Parent = root
	return root
end

PetBuilders.frog = function(m)
	local green, light = RGB(90, 200, 70), RGB(190, 240, 150)
	local root = shape(m, "egg", V(1.8, 1.1, 1.6), CF(), green)
	shape(m, "egg", V(1.3, 0.7, 1.1), CF(0, -0.15, -0.35), light)
	for sx = -1, 1, 2 do
		shape(m, "ball", V(0.65, 0.65, 0.65), CF(sx * 0.45, 0.6, -0.35), green)
		shape(m, "ball", V(0.5, 0.5, 0.5), CF(sx * 0.45, 0.66, -0.48), RGB(255, 255, 255))
		cuteEye(m, CF(sx * 0.45, 0.68, -0.68), 0.26)
		shape(m, "egg", V(0.26, 0.12, 0.05), CF(sx * 0.58, 0.08, -0.74), RGB(255, 140, 150))
		shape(m, "egg", V(0.5, 0.4, 0.95), CF(sx * 0.82, -0.35, 0.3), green:Lerp(Color3.new(0, 0, 0), 0.1))
		shape(m, "egg", V(0.26, 0.45, 0.26), CF(sx * 0.5, -0.45, -0.55), green)
		shape(m, "egg", V(0.4, 0.08, 0.35), CF(sx * 0.55, -0.68, -0.65), light)
	end
	shape(m, "egg", V(0.9, 0.06, 0.12), CF(0, 0.02, -0.78), RGB(160, 40, 60))
	return root
end

PetBuilders.penguin = function(m)
	local black, white = RGB(30, 32, 42), RGB(250, 250, 250)
	local root = shape(m, "egg", V(1.4, 1.8, 1.3), CF(), black)
	shape(m, "egg", V(1.05, 1.4, 0.7), CF(0, -0.12, -0.35), white)
	shape(m, "egg", V(0.95, 0.62, 0.5), CF(0, 0.45, -0.45), white)
	shape(m, "wedge", V(0.26, 0.2, 0.35), CF(0, 0.36, -0.82), RGB(255, 160, 30))
	shape(m, "egg", V(1.5, 0.25, 1.4), CF(0, 0.12, 0), RGB(220, 40, 50))
	shape(m, "block", V(0.25, 0.55, 0.08), CF(0.35, -0.2, -0.66) * ANG(0, 0, 0.15), RGB(220, 40, 50))
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.2, 0.56, -0.66), 0.18)
		shape(m, "egg", V(0.18, 0.1, 0.05), CF(sx * 0.33, 0.38, -0.66), RGB(255, 150, 170))
		flap(shape(m, "egg", V(0.18, 0.9, 0.45), CF(sx * 0.74, -0.05, 0) * ANG(0, 0, sx * 0.25), black), CF(sx * 0.62, 0.35, 0), sx * 0.4, 7)
		shape(m, "egg", V(0.4, 0.12, 0.5), CF(sx * 0.28, -0.92, -0.2), RGB(255, 160, 30))
	end
	return root
end

PetBuilders.flame = function(m)
	local root = shape(m, "ball", V(1.1, 1.1, 1.1), CF(), RGB(255, 130, 30), MAT.Neon)
	shape(m, "ball", V(1.5, 1.5, 1.5), CF(), RGB(255, 210, 60), MAT.Neon, { Transparency = 0.65 })
	flap(shape(m, "egg", V(0.85, 1.05, 0.85), CF(0, 0.75, 0.05), RGB(255, 150, 30), MAT.Neon, { Transparency = 0.15 }), CF(0, 0.4, 0), 0.12, 6, "x")
	flap(shape(m, "egg", V(0.5, 0.8, 0.5), CF(0, 1.3, 0.1), RGB(255, 220, 70), MAT.Neon), CF(0, 0.9, 0), 0.2, 7, "x")
	flap(shape(m, "egg", V(0.25, 0.5, 0.25), CF(0, 1.72, 0.15), RGB(255, 250, 200), MAT.Neon), CF(0, 1.4, 0), 0.3, 8, "x")
	for sx = -1, 1, 2 do
		shape(m, "egg", V(0.18, 0.28, 0.1), CF(sx * 0.2, 0.1, -0.56), RGB(40, 20, 10))
	end
	shape(m, "egg", V(0.3, 0.08, 0.06), CF(0, -0.15, -0.55), RGB(40, 20, 10))
	local f = Instance.new("Fire")
	f.Size = 2.5
	f.Heat = 5
	f.Parent = root
	addLight(root, RGB(255, 150, 50), 10)
	return root
end

PetBuilders.bee = function(m)
	local yellow, black = RGB(255, 200, 30), RGB(30, 25, 20)
	local root = shape(m, "egg", V(1.3, 1.2, 1.7), CF(), yellow)
	shape(m, "egg", V(1.33, 1.23, 0.32), CF(0, 0, 0.12), black)
	shape(m, "egg", V(1.2, 1.1, 0.3), CF(0, 0, 0.55), black)
	shape(m, "ball", V(0.95, 0.95, 0.95), CF(0, 0.15, -0.95), yellow)
	shape(m, "wedge", V(0.14, 0.14, 0.35), CF(0, -0.05, 1.02), black)
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.22, 0.26, -1.36), 0.2)
		shape(m, "egg", V(0.2, 0.1, 0.05), CF(sx * 0.33, 0.06, -1.37), RGB(255, 140, 150))
		shape(m, "block", V(0.06, 0.6, 0.06), CF(sx * 0.2, 0.78, -1.08) * ANG(-0.3, 0, -sx * 0.3), black)
		shape(m, "ball", V(0.18, 0.18, 0.18), CF(sx * 0.3, 1.06, -1.18), black)
		flap(shape(m, "egg", V(0.95, 0.06, 0.55), CF(sx * 0.62, 0.68, 0), RGB(210, 240, 255), MAT.Glass, { Transparency = 0.35 }), CF(sx * 0.18, 0.62, 0), sx * 0.6, 24)
	end
	return root
end

PetBuilders.snowman = function(m)
	local white, coal = RGB(245, 250, 255), RGB(25, 25, 30)
	local root = shape(m, "ball", V(1.5, 1.5, 1.5), CF(), white)
	shape(m, "ball", V(1.1, 1.1, 1.1), CF(0, 1.0, 0), white)
	shape(m, "ball", V(0.8, 0.8, 0.8), CF(0, 1.75, 0), white)
	shape(m, "egg", V(1.05, 0.22, 1.05), CF(0, 1.42, 0), RGB(220, 40, 50))
	shape(m, "block", V(0.22, 0.5, 0.06), CF(0.3, 1.2, -0.5) * ANG(0, 0, 0.2), RGB(220, 40, 50))
	shape(m, "cyl", V(0.5, 0.14, 0.14), CF(0, 1.72, -0.58) * ANG(0, math.pi / 2, 0), RGB(255, 130, 30))
	shape(m, "cyl", V(0.08, 0.85, 0.85), CF(0, 2.12, 0) * UPR, coal)
	shape(m, "cyl", V(0.5, 0.55, 0.55), CF(0, 2.38, 0) * UPR, coal)
	shape(m, "cyl", V(0.1, 0.57, 0.57), CF(0, 2.2, 0) * UPR, RGB(200, 30, 40))
	for sx = -1, 1, 2 do
		shape(m, "ball", V(0.13, 0.13, 0.13), CF(sx * 0.15, 1.86, -0.36), coal)
		flap(shape(m, "block", V(0.07, 0.9, 0.07), CF(sx * 0.82, 1.2, 0) * ANG(0, 0, sx * 0.9), RGB(110, 70, 40)), CF(sx * 0.5, 1.0, 0), sx * 0.25, 5)
	end
	for i, y in ipairs({ 1.2, 0.9, 0.35 }) do
		shape(m, "ball", V(0.14, 0.14, 0.14), CF(0, y, i == 3 and -0.74 or -0.54), coal)
	end
	return root
end

PetBuilders.cubecat = function(m)
	local white, pink, gray = RGB(245, 245, 245), RGB(255, 160, 180), RGB(170, 170, 180)
	local root = shape(m, "block", V(1.5, 1.3, 1.4), CF(), white)
	for i = -1, 1 do
		shape(m, "block", V(0.18, 0.04, 0.6), CF(i * 0.35, 0.66, 0.2), gray)
	end
	for sx = -1, 1, 2 do
		shape(m, "wedge", V(0.42, 0.48, 0.3), CF(sx * 0.45, 0.88, -0.2), white)
		shape(m, "wedge", V(0.22, 0.28, 0.08), CF(sx * 0.45, 0.82, -0.36), pink)
		cuteEye(m, CF(sx * 0.32, 0.15, -0.72), 0.27)
		shape(m, "egg", V(0.24, 0.12, 0.04), CF(sx * 0.5, -0.12, -0.71), pink)
		shape(m, "block", V(0.5, 0.03, 0.03), CF(sx * 0.62, -0.08, -0.71) * ANG(0, 0, sx * 0.15), RGB(60, 60, 60))
		shape(m, "block", V(0.5, 0.03, 0.03), CF(sx * 0.62, -0.18, -0.71) * ANG(0, 0, -sx * 0.1), RGB(60, 60, 60))
		shape(m, "egg", V(0.35, 0.25, 0.35), CF(sx * 0.4, -0.65, -0.5), white)
	end
	shape(m, "ball", V(0.14, 0.14, 0.14), CF(0, -0.05, -0.72), pink)
	local tailHinge = CF(0, -0.3, 0.7)
	flap(shape(m, "block", V(0.2, 0.2, 0.45), CF(0, -0.25, 0.9), white), tailHinge, 0.3, 4, "y")
	flap(shape(m, "block", V(0.2, 0.45, 0.2), CF(0, 0.0, 1.1), white), tailHinge, 0.3, 4, "y")
	flap(shape(m, "block", V(0.2, 0.2, 0.2), CF(0, 0.25, 1.1), gray), tailHinge, 0.3, 4, "y")
	return root
end

PetBuilders.ghostpet = function(m)
	local c = RGB(225, 240, 255)
	local root = shape(m, "egg", V(1.4, 1.6, 1.4), CF(), c, MAT.Neon, { Transparency = 0.3 })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		shape(m, "ball", V(0.55, 0.55, 0.55), CF(math.sin(a) * 0.42, -0.72, math.cos(a) * 0.42), c, MAT.Neon, { Transparency = 0.3 })
	end
	for sx = -1, 1, 2 do
		shape(m, "egg", V(0.22, 0.36, 0.1), CF(sx * 0.25, 0.22, -0.66), RGB(25, 25, 40))
		shape(m, "ball", V(0.08, 0.08, 0.08), CF(sx * 0.22, 0.3, -0.71), RGB(255, 255, 255), MAT.Neon)
		shape(m, "egg", V(0.22, 0.1, 0.05), CF(sx * 0.42, 0.0, -0.62), RGB(255, 170, 200))
		flap(shape(m, "egg", V(0.28, 0.5, 0.28), CF(sx * 0.75, -0.05, -0.1) * ANG(0, 0, sx * 0.5), c, MAT.Neon, { Transparency = 0.3 }), CF(sx * 0.6, 0.1, 0), sx * 0.4, 5)
	end
	shape(m, "egg", V(0.2, 0.26, 0.08), CF(0, -0.12, -0.68), RGB(25, 25, 40))
	addLight(root, RGB(190, 220, 255), 10)
	return root
end

PetBuilders.slime = function(m)
	local root = shape(m, "egg", V(1.9, 1.35, 1.9), CF(), RGB(255, 110, 20), MAT.SmoothPlastic, { Transparency = 0.2 })
	shape(m, "egg", V(1.25, 0.8, 1.25), CF(0, -0.1, 0), RGB(255, 60, 0), MAT.Neon)
	shape(m, "ball", V(0.55, 0.55, 0.55), CF(0.35, 0.68, 0.25), RGB(255, 130, 30), MAT.SmoothPlastic, { Transparency = 0.2 })
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.36, 0.25, -0.85), 0.28)
		shape(m, "egg", V(0.26, 0.12, 0.06), CF(sx * 0.6, 0.0, -0.8), RGB(255, 180, 160))
		shape(m, "egg", V(0.22, 0.35, 0.22), CF(sx * 0.6, -0.65, sx * 0.3), RGB(255, 90, 10), MAT.Neon)
	end
	shape(m, "egg", V(0.4, 0.12, 0.06), CF(0, -0.1, -0.92), RGB(80, 20, 10))
	addLight(root, RGB(255, 110, 30), 10)
	return root
end

PetBuilders.robocube = function(m)
	local metal, cyan = RGB(165, 170, 180), RGB(60, 230, 255)
	local root = shape(m, "block", V(1.5, 1.5, 1.5), CF(), metal, MAT.DiamondPlate)
	shape(m, "block", V(1.2, 0.8, 0.06), CF(0, 0.1, -0.76), RGB(20, 25, 35))
	shape(m, "block", V(0.06, 0.6, 0.08), CF(0, 1.05, 0), RGB(120, 125, 135), MAT.Metal)
	local tip = shape(m, "ball", V(0.26, 0.26, 0.26), CF(0, 1.4, 0), RGB(255, 50, 50), MAT.Neon)
	addLight(tip, RGB(255, 60, 60), 6)
	shape(m, "block", V(0.5, 0.06, 0.04), CF(0, -0.12, -0.8), cyan, MAT.Neon)
	for sx = -1, 1, 2 do
		shape(m, "block", V(0.3, 0.22, 0.04), CF(sx * 0.27, 0.2, -0.8), cyan, MAT.Neon)
		shape(m, "cyl", V(0.15, 0.45, 0.45), CF(sx * 0.82, 0.1, 0), RGB(200, 205, 215), MAT.Metal)
		shape(m, "cyl", V(0.3, 0.45, 0.45), CF(sx * 0.4, -0.9, 0) * UPR, RGB(70, 75, 85), MAT.Metal)
		flap(shape(m, "egg", V(0.3, 0.55, 0.3), CF(sx * 0.4, -1.3, 0), cyan, MAT.Neon, { Transparency = 0.2 }), CF(sx * 0.4, -1.05, 0), 0.15, 20, "x")
	end
	return root
end

PetBuilders.minivolcano = function(m)
	local rock = RGB(70, 55, 50)
	local root = shape(m, "cyl", V(0.7, 2.0, 2.0), CF() * UPR, rock, MAT.Basalt)
	shape(m, "cyl", V(0.6, 1.5, 1.5), CF(0, 0.6, 0) * UPR, rock:Lerp(Color3.new(0, 0, 0), 0.1), MAT.Basalt)
	shape(m, "cyl", V(0.5, 1.05, 1.05), CF(0, 1.1, 0) * UPR, rock:Lerp(Color3.new(0, 0, 0), 0.2), MAT.Basalt)
	local crater = shape(m, "cyl", V(0.12, 0.8, 0.8), CF(0, 1.37, 0) * UPR, RGB(255, 90, 0), MAT.Neon)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.5
		shape(m, "block", V(0.14, 0.9, 0.08), CF(math.sin(a) * 0.62, 0.8, math.cos(a) * 0.62) * ANG(0, a, 0), RGB(255, 110, 0), MAT.Neon)
	end
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.35, 0.3, -0.98), 0.24)
		shape(m, "egg", V(0.24, 0.12, 0.05), CF(sx * 0.6, 0.1, -0.92), RGB(255, 140, 120))
	end
	shape(m, "egg", V(0.35, 0.1, 0.05), CF(0, 0.08, -1.0), RGB(255, 90, 0), MAT.Neon)
	local f = Instance.new("Fire")
	f.Size = 2.5
	f.Heat = 7
	f.Parent = crater
	local sm = Instance.new("Smoke")
	sm.Size = 1
	sm.Opacity = 0.15
	sm.RiseVelocity = 3
	sm.Parent = crater
	addLight(crater, RGB(255, 110, 30), 10)
	return root
end

PetBuilders.phoenix = function(m)
	local red, orange, yellow, gold = RGB(225, 45, 20), RGB(255, 125, 20), RGB(255, 215, 70), RGB(255, 190, 40)
	local root = shape(m, "egg", V(1.25, 1.15, 1.7), CF(), orange)
	shape(m, "egg", V(0.95, 0.85, 1.15), CF(0, -0.15, -0.3), yellow)
	shape(m, "ball", V(0.95, 0.95, 0.95), CF(0, 0.75, -0.75), orange)
	shape(m, "wedge", V(0.26, 0.26, 0.42), CF(0, 0.62, -1.32), gold, MAT.Foil)
	for i = -1, 1 do
		local col = i == 0 and red or orange
		shape(m, "egg", V(0.12, 0.7, 0.26), CF(i * 0.14, 1.3, -0.62) * ANG(0.45, 0, -i * 0.35), col)
		shape(m, "ball", V(0.16, 0.16, 0.16), CF(i * 0.27, 1.62, -0.48), yellow, MAT.Neon)
	end
	for sx = -1, 1, 2 do
		cuteEye(m, CF(sx * 0.27, 0.86, -1.1), 0.21)
		local hinge = CF(sx * 0.5, 0.28, -0.1)
		flap(shape(m, "egg", V(1.6, 0.12, 0.75), CF(sx * 1.25, 0.3, -0.1), red), hinge, sx * 0.55, 6)
		flap(shape(m, "egg", V(1.3, 0.12, 0.6), CF(sx * 1.12, 0.33, 0.28), orange), hinge, sx * 0.55, 6)
		flap(shape(m, "egg", V(1.0, 0.1, 0.45), CF(sx * 0.98, 0.36, 0.6), yellow, MAT.Neon), hinge, sx * 0.55, 6)
	end
	local tailHinge = CF(0, 0, 0.75)
	local tail
	for i = -2, 2 do
		local col = (i % 2 == 0) and red or orange
		local feather = shape(m, "egg", V(0.2, 0.12, 1.8), CF(i * 0.18, -0.15 - math.abs(i) * 0.05, 1.55) * ANG(0.3, i * 0.22, 0), col)
		flap(feather, tailHinge, 0.15, 3, "x")
		local tipCf = feather.CFrame * CF(0, 0, 0.85)
		flap(shape(m, "ball", V(0.26, 0.26, 0.26), tipCf, yellow, MAT.Neon), tailHinge, 0.15, 3, "x")
		if i == 0 then
			tail = feather
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 4
	fire.Color = RGB(255, 160, 40)
	fire.SecondaryColor = RGB(255, 60, 0)
	fire.Parent = tail
	addLight(root, RGB(255, 150, 60), 10)
	return root
end

PetBuilders.dragon = function(m)
	local green, belly, dark = RGB(80, 195, 90), RGB(210, 240, 150), RGB(50, 140, 60)
	local root = shape(m, "egg", V(1.3, 1.1, 2.0), CF(), green)
	shape(m, "egg", V(0.95, 0.8, 1.6), CF(0, -0.2, -0.05), belly)
	shape(m, "egg", V(0.7, 0.9, 0.7), CF(0, 0.55, -0.85) * ANG(0.4, 0, 0), green)
	shape(m, "egg", V(0.95, 0.8, 1.0), CF(0, 0.95, -1.25), green)
	shape(m, "egg", V(0.72, 0.5, 0.72), CF(0, 0.82, -1.75), belly)
	for sx = -1, 1, 2 do
		shape(m, "ball", V(0.1, 0.1, 0.1), CF(sx * 0.15, 0.95, -2.1), RGB(30, 30, 30))
		cuteEye(m, CF(sx * 0.3, 1.12, -1.6), 0.24)
		shape(m, "egg", V(0.15, 0.5, 0.15), CF(sx * 0.25, 1.45, -1.05) * ANG(-0.5, 0, sx * 0.2), RGB(255, 240, 200))
		local hinge = CF(sx * 0.45, 0.45, -0.2)
		flap(shape(m, "egg", V(1.9, 0.08, 1.15), CF(sx * 1.35, 0.6, 0.05) * ANG(0, 0, -sx * 0.15), RGB(255, 170, 60)), hinge, sx * 0.5, 6)
		flap(shape(m, "block", V(1.9, 0.12, 0.12), CF(sx * 1.35, 0.65, -0.5) * ANG(0, 0, -sx * 0.15), dark), hinge, sx * 0.5, 6)
		for sz = -1, 1, 2 do
			shape(m, "egg", V(0.35, 0.5, 0.35), CF(sx * 0.45, -0.55, sz * 0.55), dark)
		end
	end
	for i = 0, 3 do
		local z = -0.45 + i * 0.4
		shape(m, "wedge", V(0.1, 0.35 - i * 0.05, 0.38), CF(0, 0.62 - i * 0.04, z), RGB(255, 150, 40))
	end
	local tailHinge = CF(0, 0, 0.9)
	flap(shape(m, "egg", V(0.6, 0.5, 0.85), CF(0, -0.05, 1.2), green), tailHinge, 0.25, 3, "y")
	flap(shape(m, "egg", V(0.45, 0.38, 0.7), CF(0, 0.05, 1.75), green), tailHinge, 0.25, 3, "y")
	flap(shape(m, "egg", V(0.3, 0.26, 0.6), CF(0, 0.2, 2.25), green), tailHinge, 0.25, 3, "y")
	flap(shape(m, "wedge", V(0.12, 0.45, 0.45), CF(0, 0.3, 2.62), RGB(255, 150, 40)), tailHinge, 0.25, 3, "y")
	Instance.new("Sparkles").Parent = root
	return root
end

-- Если в ReplicatedStorage есть папка LavaPetModels с моделью, названной как id питомца
-- (например "phoenix"), игра возьмёт эту модель вместо встроенной.
local function customPetModel(pet)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("LavaPetModels")
	local src = folder and folder:FindFirstChild(pet.id)
	if not src or not src:IsA("Model") then
		return nil
	end
	local model = src:Clone()
	local first
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			first = first or d
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- чужие скрипты из Toolbox не нужны
		end
	end
	if not first then
		return nil
	end
	model.PrimaryPart = model.PrimaryPart or first
	-- подгоняем размер: питомец примерно 2 стада
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > 0 then
		pcall(function()
			model:ScaleTo(model:GetScale() * (2.2 / biggest))
		end)
	end
	model:PivotTo(CFrame.new())
	return model
end

local function buildPet(pet)
	local custom = customPetModel(pet)
	if custom then
		custom.Name = pet.id
		return custom
	end
	local model = Instance.new("Model")
	model.Name = pet.id
	-- невидимая «опора» в центре: за неё клиент двигает питомца и машет крыльями
	local root = shape(model, "block", V(0.2, 0.2, 0.2), CF(), RGB(255, 255, 255), nil, { Transparency = 1, Name = "PetRoot" })
	local builder = PetBuilders[pet.id] or PetBuilders.duckling
	builder(model)
	model.PrimaryPart = root
	return model
end

local function applyPet(player)
	local s = sessions[player]
	for _, m in ipairs(petFolder:GetChildren()) do
		if m:GetAttribute("OwnerId") == player.UserId then
			m:Destroy()
		end
	end
	if not s then
		return
	end
	local pet = Config.GetItem("pets", s.data.pet)
	local _, _, root = getCharacterParts(player)
	if not pet or not root or not ownsItem(player, s, "pets", pet) then
		return
	end
	local model = buildPet(pet)
	model:SetAttribute("OwnerId", player.UserId)
	model:PivotTo(root.CFrame * CFrame.new(2.5, 1.5, 2))
	model.Parent = petFolder
end

-- ============ АУРЫ ============
local function colorSeq(colors)
	local kps = {}
	local n = #colors
	for i, c in ipairs(colors) do
		table.insert(kps, ColorSequenceKeypoint.new(n == 1 and 0 or (i - 1) / (n - 1), c))
	end
	if n == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return ColorSequence.new(kps)
end

local function applyAura(player)
	local s = sessions[player]
	local _, _, root = getCharacterParts(player)
	if not s or not root then
		return
	end
	for _, c in ipairs(root:GetChildren()) do
		if c.Name == "LavaAura" then
			c:Destroy()
		end
	end
	local aura = Config.GetItem("auras", s.data.aura)
	if not aura or not ownsItem(player, s, "auras", aura) then
		return
	end
	local fx
	if aura.kind == "sparkles" then
		fx = Instance.new("Sparkles")
		fx.SparkleColor = aura.colors[1]
	elseif aura.kind == "fire" then
		fx = Instance.new("Fire")
		fx.Color = aura.colors[1]
		fx.SecondaryColor = aura.colors[2] or aura.colors[1]
		fx.Size = 4
		fx.Heat = 6
	elseif aura.kind == "smoke" then
		fx = Instance.new("Smoke")
		fx.Color = aura.colors[1]
		fx.Size = 2
		fx.Opacity = 0.25
		fx.RiseVelocity = 2
	else
		fx = Instance.new("ParticleEmitter")
		fx.Color = colorSeq(aura.colors)
		fx.LightEmission = 0.8
		fx.Size = NumberSequence.new(0.35, 0)
		fx.Transparency = NumberSequence.new(0, 1)
		fx.Lifetime = NumberRange.new(0.8, 1.4)
		fx.Rate = aura.fast and 40 or 18
		fx.Speed = NumberRange.new(aura.fast and 6 or 2, aura.fast and 10 or 4)
		fx.SpreadAngle = Vector2.new(180, 180)
		fx.Acceleration = Vector3.new(0, 2, 0)
	end
	fx.Name = "LavaAura"
	fx.Parent = root
end

local function hasPerk(player, id)
	local s = sessions[player]
	return s ~= nil and s.data.perks[id] == true
end

local function applyCharacter(player)
	local _, hum = getCharacterParts(player)
	if hum then
		local speed = player:GetAttribute("PassSpeed") and Config.SPEED_WALKSPEED or Config.NORMAL_WALKSPEED
		if hasPerk(player, "swift") then
			speed += Config.PERK_SWIFT_BONUS
		end
		hum.WalkSpeed = speed
		hum.UseJumpPower = false
		hum.JumpHeight = player:GetAttribute("PassSuperJump") and Config.SUPER_JUMP or Config.NORMAL_JUMP
	end
	applyTrail(player)
	applySkin(player)
	applyPet(player)
	applyAura(player)
	applyOverhead(player)
end

local function onCharacter(player, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	local s = sessions[player]
	local t0 = os.clock()
	while (not s or not s.loaded) and os.clock() - t0 < 15 do
		task.wait(0.2)
		s = sessions[player]
	end
	if not root or not char.Parent then
		return
	end
	task.wait()
	teleportToStage(player)
	applyCharacter(player)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			local ss = sessions[player]
			if ss then
				ss.noDeathStreak = 0
			end
		end)
	end
	task.delay(1.5, function()
		if player.Character == char then
			applySkin(player)
		end
	end)
end

-- ============ ЭТАПЫ ============
-- ⏱ Время забега: от портала в лобби до кубка
local finishRun
local timeStore
pcall(function()
	timeStore = DataStoreService:GetOrderedDataStore(Config.TIME_LEADERBOARD_KEY)
end)

local function fmtTime(t)
	local m = math.floor(t / 60)
	local sec = t - m * 60
	return string.format("%02d:%05.2f", m, sec)
end

finishRun = function(player, s)
	if not s.runStart then
		return
	end
	local t = workspace:GetServerTimeNow() - s.runStart
	s.runStart = nil
	player:SetAttribute("RunStart", nil)
	player:SetAttribute("RunTime", t)
	notify(player, "n_run_time", Color3.fromRGB(150, 220, 255), fmtTime(t))
	if s.runValid and (s.data.bestTime == 0 or t < s.data.bestTime) then
		s.data.bestTime = t
		player:SetAttribute("BestTime", t)
		notify(player, "n_new_record", Color3.fromRGB(255, 215, 80), fmtTime(t))
		if timeStore and not s.noSave then
			task.spawn(function()
				pcall(function()
					timeStore:SetAsync(tostring(player.UserId), math.floor(t * 100))
				end)
			end)
		end
	end
end

local function setStage(player, n)
	local s = sessions[player]
	if not s then
		return
	end
	local d = s.data
	local isNewMax = n > d.maxStage
	d.stage = n
	if isNewMax then
		d.maxStage = n
		if n < FINISH then
			addCoins(player, Config.STAGE_REWARD, true)
		end
		s.noDeathStreak = (s.noDeathStreak or 0) + 1
		progressChallenge(player, "stages", 1)
		progressChallenge(player, "nodeath", s.noDeathStreak, true)
		if (n - 1) % Config.STAGES_PER_ZONE == 0 and n < FINISH then
			local zone = Config.Zones[Config.ZoneOfStage(n)]
			EffectRE:FireClient(player, "zone", Config.ZoneOfStage(n))
			notify(player, "n_new_zone", zone.color, zone.emoji, "@zone_" .. Config.ZoneOfStage(n))
			progressChallenge(player, "zone", 1)
		end
	end
	if n == FINISH and not d.finishedRun then
		d.finishedRun = true
		finishRun(player, s)
		local gained = addCoins(player, Config.FINISH_REWARD, true)
		awardBadge(player, Config.Badges.Finish)
		EffectRE:FireClient(player, "finish")
		notify(player, "n_finish", Color3.fromRGB(255, 215, 80), gained)
		notifyAll("n_all_finish", Color3.fromRGB(255, 215, 80), player.DisplayName)
		task.spawn(saveData, player)
	elseif isNewMax then
		EffectRE:FireClient(player, "checkpoint")
	end
	syncAttributes(player)
end

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return Players:GetPlayerFromCharacter(model), hum
end

-- 🛡 Щит: вместо смерти возвращаем игрока на последнюю платформу, где он стоял
local function rescue(player)
	local s = sessions[player]
	if not s or os.clock() - (s.lastRescue or 0) < 1 then
		return
	end
	s.lastRescue = os.clock()
	local char, _, root = getCharacterParts(player)
	if not char or not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(s.lastSafe or map.spawnCF[s.data.stage] or map.spawnCF[1])
end

local function kill(hum)
	if not hum or hum.Health <= 0 then
		return
	end
	local owner = Players:GetPlayerFromCharacter(hum.Parent)
	if owner and (owner:GetAttribute("ShieldUntil") or 0) > os.time() then
		-- 🛡 со щитом лава не мешает: бежишь дальше. Возвращаем назад,
		-- только если игрок провалился глубоко вниз (в лавовое море).
		local s = sessions[owner]
		local root = hum.Parent:FindFirstChild("HumanoidRootPart")
		if s and root and s.lastSafe and root.Position.Y < s.lastSafe.Position.Y - 8 then
			rescue(owner)
		end
		return
	end
	hum.Health = 0
end

-- Запоминаем последнюю безопасную точку (неподвижная платформа, не лава)
local safeParams = RaycastParams.new()
safeParams.FilterType = Enum.RaycastFilterType.Exclude
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, p in ipairs(Players:GetPlayers()) do
			local s = sessions[p]
			local char, hum, root = getCharacterParts(p)
			if s and char and hum and root and hum.Health > 0 then
				safeParams.FilterDescendantsInstances = { char, petFolder }
				local res = workspace:Raycast(root.Position, Vector3.new(0, -5, 0), safeParams)
				local hit = res and res.Instance
				if
					hit
					and hit.Anchored
					and not CollectionService:HasTag(hit, "Lava")
					and not CollectionService:HasTag(hit, "Kill")
					and not CollectionService:HasTag(hit, "Vanish")
					and hit.AssemblyLinearVelocity.Magnitude < 0.1
					and hit.AssemblyAngularVelocity.Magnitude < 0.1
				then
					s.lastSafe = CFrame.new(res.Position + Vector3.new(0, 3.2, 0)) * root.CFrame.Rotation
				end
			end
		end
	end
end)

for _, cp in ipairs(CollectionService:GetTagged("Checkpoint")) do
	cp.Touched:Connect(function(hit)
		local player, hum = playerFromHit(hit)
		if not player or not hum or hum.Health <= 0 then
			return
		end
		local s = sessions[player]
		if not s or not s.loaded then
			return
		end
		local n = cp:GetAttribute("Stage")
		if n and n > s.data.stage and n <= s.data.maxStage + 1 then
			setStage(player, n)
		end
	end)
end

-- ============ ЛАВА И ОПАСНОСТИ ============
local function isWater()
	return workspace:GetAttribute("LavaIsWater") == true
end

for _, lava in ipairs(CollectionService:GetTagged("Lava")) do
	lava.Touched:Connect(function(hit)
		if isWater() or lava:GetAttribute("Off") then
			return
		end
		local _, hum = playerFromHit(hit)
		kill(hum)
	end)
end

for _, k in ipairs(CollectionService:GetTagged("Kill")) do
	k.Touched:Connect(function(hit)
		local _, hum = playerFromHit(hit)
		kill(hum)
	end)
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

local function refreshOverlap()
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	overlap.FilterDescendantsInstances = chars
	return #chars > 0
end

local function killInside(partToCheck)
	for _, hit in ipairs(workspace:GetPartsInPart(partToCheck, overlap)) do
		local _, hum = playerFromHit(hit)
		kill(hum)
	end
end

-- Движущиеся платформы и вращение
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, m in ipairs(map.movers) do
		local k = math.sin(t * m.speed + m.phase)
		m.part.CFrame = m.base + m.axis * (k * m.amp)
		m.part.AssemblyLinearVelocity = m.axis * (math.cos(t * m.speed + m.phase) * m.amp * m.speed)
	end
	for _, sp in ipairs(map.spinners) do
		sp.part.CFrame = sp.base * CFrame.Angles(0, t * sp.speed, 0) * sp.offset
		sp.part.AssemblyAngularVelocity = Vector3.new(0, sp.speed, 0)
	end
	for _, pd in ipairs(map.pendulums) do
		pd.part.CFrame = pd.pivot * CFrame.Angles(0, 0, pd.amp * math.sin(t * pd.speed + pd.phase)) * pd.offset
	end
end)

-- Гейзеры лавы: пузырьки → огненный столб → вниз
for _, g in ipairs(map.geysers) do
	task.spawn(function()
		task.wait(g.delay)
		local upInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local downInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		while true do
			g.bubbles.Rate = 30 -- предупреждение
			task.wait(1)
			g.bubbles.Rate = 0
			g.active = true
			TweenService:Create(g.part, upInfo, { CFrame = g.high }):Play()
			task.wait(1.3)
			TweenService:Create(g.part, downInfo, { CFrame = g.low }):Play()
			task.wait(0.6)
			g.active = false
			task.wait(2)
		end
	end)
end

-- Падающие сталактиты
for _, st in ipairs(map.stalactites) do
	task.spawn(function()
		task.wait(st.delay)
		local fallInfo = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		while true do
			st.part.Color = Color3.fromRGB(255, 60, 30)
			st.part.Material = Enum.Material.Neon
			task.wait(1)
			st.falling = true
			local tw = TweenService:Create(st.part, fallInfo, { CFrame = st.low })
			tw:Play()
			tw.Completed:Wait()
			st.falling = false
			st.part.Transparency = 1
			st.part.CFrame = st.high
			st.part.Color = st.color
			st.part.Material = Enum.Material.Slate
			task.wait(1)
			st.part.Transparency = 0
			task.wait(st.interval)
		end
	end)
end

-- Мигающие полосы лавы
task.spawn(function()
	local groupOn = 0
	while true do
		task.wait(2.5)
		groupOn = 1 - groupOn
		local anyone = refreshOverlap()
		for _, b in ipairs(map.blinkers) do
			local on = b.group == groupOn
			b.part:SetAttribute("Off", not on)
			b.part.Transparency = on and 0 or 0.85
			if on and anyone and not isWater() then
				killInside(b.part)
			end
		end
	end
end)

-- Волны лавы в зоне 4
local waveDanger = false
task.spawn(function()
	if #map.waves == 0 then
		return
	end
	local moveInfo = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	while true do
		workspace:SetAttribute("WaveState", "calm")
		task.wait(10)
		workspace:SetAttribute("WaveState", "warn")
		task.wait(2.5)
		workspace:SetAttribute("WaveState", "up")
		waveDanger = true
		for _, w in ipairs(map.waves) do
			TweenService:Create(w.part, moveInfo, { CFrame = w.high }):Play()
		end
		task.wait(5.5)
		workspace:SetAttribute("WaveState", "down")
		for _, w in ipairs(map.waves) do
			TweenService:Create(w.part, moveInfo, { CFrame = w.low }):Play()
		end
		task.wait(2)
		waveDanger = false
		task.wait(1)
	end
end)

-- Проверка движущихся убийц (крутилки, сталактиты, волны)
task.spawn(function()
	local tick = 0
	while true do
		task.wait(0.1)
		tick += 1
		if refreshOverlap() then
			for _, k in ipairs(map.killers) do
				killInside(k.part)
			end
			for _, st in ipairs(map.stalactites) do
				if st.falling then
					killInside(st.part)
				end
			end
			for _, g in ipairs(map.geysers) do
				if g.active then
					killInside(g.part)
				end
			end
			if waveDanger and not isWater() and tick % 2 == 0 then
				for _, w in ipairs(map.waves) do
					killInside(w.part)
				end
			end
		end
	end
end)

-- Исчезающие платформы
for _, v in ipairs(CollectionService:GetTagged("Vanish")) do
	local baseT = v.Transparency
	v.Touched:Connect(function(hit)
		if v:GetAttribute("Busy") then
			return
		end
		local _, hum = playerFromHit(hit)
		if not hum then
			return
		end
		v:SetAttribute("Busy", true)
		TweenService:Create(v, TweenInfo.new(1), { Transparency = 0.7 }):Play()
		task.delay(1, function()
			v.CanCollide = false
			v.Transparency = 1
			task.wait(2.5)
			v.CanCollide = true
			v.Transparency = baseT
			v:SetAttribute("Busy", false)
		end)
	end)
end

-- ============ ЛАВА → ВОДА ============
local lavaOriginal = {}
for _, lava in ipairs(CollectionService:GetTagged("Lava")) do
	lavaOriginal[lava] = { color = lava.Color, material = lava.Material, transparency = lava.Transparency }
end
local waterUntil = 0
local buttonReadyAt = 0

local function killPlayersStandingOnLava()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, p in ipairs(Players:GetPlayers()) do
		local char, hum, root = getCharacterParts(p)
		if char and hum and root then
			params.FilterDescendantsInstances = { char }
			local res = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
			if res and CollectionService:HasTag(res.Instance, "Lava") and not res.Instance:GetAttribute("Off") then
				kill(hum)
			end
		end
	end
end

local function setWater(seconds, byName)
	local now = os.clock()
	local wasWater = isWater()
	waterUntil = math.max(waterUntil, now) + seconds
	workspace:SetAttribute("WaterUntil", os.time() + math.ceil(waterUntil - now))
	notifyAll("n_water", Color3.fromRGB(90, 190, 255), byName, seconds)
	if wasWater then
		return
	end
	workspace:SetAttribute("LavaIsWater", true)
	for lava in pairs(lavaOriginal) do
		lava.Color = Color3.fromRGB(40, 140, 255)
		lava.Material = Enum.Material.Glass
		lava.Transparency = math.max(lava.Transparency, 0.25)
	end
	task.spawn(function()
		while os.clock() < waterUntil do
			task.wait(0.25)
		end
		for lava, o in pairs(lavaOriginal) do
			lava.Color = o.color
			lava.Material = o.material
			lava.Transparency = lava:GetAttribute("Off") and 0.85 or o.transparency
		end
		workspace:SetAttribute("LavaIsWater", false)
		notifyAll("n_lava_back", Color3.fromRGB(255, 120, 40))
		killPlayersStandingOnLava()
	end)
end

for _, btn in ipairs(CollectionService:GetTagged("LavaButton")) do
	btn.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if not player then
			return
		end
		local now = os.clock()
		if now < buttonReadyAt then
			local s = sessions[player]
			if s and now - (s.lastButtonMsg or 0) > 3 then
				s.lastButtonMsg = now
				notify(player, "n_button_cd", nil, math.ceil(buttonReadyAt - now))
			end
			return
		end
		buttonReadyAt = now + Config.WATER_BUTTON_COOLDOWN
		setWater(Config.WATER_BUTTON_DURATION, player.DisplayName)
	end)
end

-- ============ МОНЕТЫ, УТКИ, СЕКРЕТЫ ============
local allCoins = CollectionService:GetTagged("Coin")

local function collectCoin(player, coin)
	local s = sessions[player]
	if not s or not s.loaded then
		return
	end
	local id = coin:GetAttribute("CoinId")
	local last = s.collected[id]
	if last and os.clock() - last < Config.COIN_RESPAWN then
		return
	end
	s.collected[id] = os.clock()
	addCoins(player, Config.COIN_VALUE, true)
	CoinRE:FireClient(player, id)
end

for _, coin in ipairs(allCoins) do
	coin.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			collectCoin(player, coin)
		end
	end)
end

-- 🧲 Привилегия «Магнит»: монетки рядом собираются сами
task.spawn(function()
	local r2 = Config.PERK_MAGNET_RADIUS * Config.PERK_MAGNET_RADIUS
	while true do
		task.wait(0.3)
		for _, p in ipairs(Players:GetPlayers()) do
			if hasPerk(p, "magnet") then
				local _, hum, root = getCharacterParts(p)
				if root and hum and hum.Health > 0 then
					local pos = root.Position
					for _, coin in ipairs(allCoins) do
						local d = coin.Position - pos
						if d.X * d.X + d.Y * d.Y + d.Z * d.Z < r2 then
							collectCoin(p, coin)
						end
					end
				end
			end
		end
	end
end)

for _, duck in ipairs(CollectionService:GetTagged("Duck")) do
	local id = duck:GetAttribute("DuckId")
	duck.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded or s.data.ducks[tostring(id)] then
			return
		end
		s.data.ducks[tostring(id)] = true
		local found = countKeys(s.data.ducks)
		local gained = addCoins(player, Config.DUCK_REWARD, true)
		EffectRE:FireClient(player, "duck")
		notify(player, "n_duck", Color3.fromRGB(255, 225, 60), found, Config.DUCK_COUNT, gained)
		if found >= Config.DUCK_COUNT then
			addCoins(player, Config.ALL_DUCKS_REWARD, false)
			awardBadge(player, Config.Badges.AllDucks)
			notify(player, "n_all_ducks", Color3.fromRGB(255, 200, 40), Config.ALL_DUCKS_REWARD)
			notifyAll("n_all_ducks_all", Color3.fromRGB(255, 225, 60), player.DisplayName)
			applyOverhead(player)
		end
		syncAttributes(player)
		progressChallenge(player, "secret", 1)
		task.spawn(saveData, player)
	end)
end

local SECRET_BADGES = { lavafall = "SecretRoom", dontjump = "DontJump" }
for _, chest in ipairs(CollectionService:GetTagged("Secret")) do
	local id = chest:GetAttribute("SecretId")
	chest.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded or s.data.secrets[id] then
			return
		end
		s.data.secrets[id] = true
		local gained = addCoins(player, Config.SECRET_REWARD, true)
		awardBadge(player, Config.Badges[SECRET_BADGES[id] or ""])
		EffectRE:FireClient(player, "duck")
		notify(player, "n_secret", Color3.fromRGB(255, 200, 80), gained)
		progressChallenge(player, "secret", 1)
	end)
end

for _, chest in ipairs(CollectionService:GetTagged("VipChest")) do
	chest.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded then
			return
		end
		local now = os.clock()
		if now - (s.lastChestMsg or 0) < 3 then
			return
		end
		s.lastChestMsg = now
		if not player:GetAttribute("PassVIP") then
			notify(player, "n_vip_only")
			return
		end
		local left = s.data.vipChest + Config.VIP_CHEST_COOLDOWN - os.time()
		if left > 0 then
			notify(player, "n_vip_chest_wait", nil, math.ceil(left / 60))
			return
		end
		s.data.vipChest = os.time()
		local gained = addCoins(player, Config.VIP_CHEST_REWARD, true)
		EffectRE:FireClient(player, "duck")
		notify(player, "n_vip_chest", Color3.fromRGB(255, 215, 80), gained)
	end)
end

for _, tp in ipairs(CollectionService:GetTagged("Teleport")) do
	tp.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or os.clock() - (s.lastTp or 0) < 1 then
			return
		end
		s.lastTp = os.clock()
		teleportToStage(player)
	end)
end

-- ============ МОНЕТИЗАЦИЯ ============
local function checkPasses(player)
	for key, id in pairs(Config.GamePasses) do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			player:SetAttribute("Pass" .. key, ok and owns or false)
		else
			player:SetAttribute("Pass" .. key, false)
		end
	end
end

-- После покупки пропуска сразу надеваем его вещи (один раз), чтобы игрок увидел, за что платил
local AUTO_EQUIP = {
	VIP = { skins = "gold", pets = "phoenix", trails = "vip", auras = "golden" },
	SkinPack = { skins = "rainbow" },
	DragonPet = { pets = "dragon" },
}

local function autoEquip(player, key)
	local s = sessions[player]
	local set = AUTO_EQUIP[key]
	if not s or not s.loaded or not set or s.data.autoEquipped[key] then
		return
	end
	s.data.autoEquipped[key] = true
	for category, id in pairs(set) do
		s.data[Config.ItemCategories[category].equipped] = id
	end
	syncAttributes(player)
	applyCharacter(player)
	task.spawn(saveData, player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for key, id in pairs(Config.GamePasses) do
		if id == passId then
			player:SetAttribute("Pass" .. key, true)
			notify(player, "n_thanks", Color3.fromRGB(120, 255, 140))
			notifyAll("n_bought_pass", Color3.fromRGB(190, 140, 255), player.DisplayName, "@pass_" .. key)
			syncAttributes(player)
			autoEquip(player, key)
		end
	end
	applyCharacter(player)
	syncAttributes(player)
end)

local function hasReceipt(d, purchaseId)
	for _, r in ipairs(d.receipts) do
		if r == purchaseId then
			return true
		end
	end
	return false
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local s = player and sessions[player]
	if not s or not s.loaded then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = s.data
	if hasReceipt(d, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local id = receipt.ProductId
	local P = Config.Products
	if id == P.SkipStage or id == P.SkipZone then
		s.runValid = false -- забег с пропусками не идёт в таблицу рекордов
		player:SetAttribute("RunValid", false)
		setInLobby(player, false)
	end
	if id == P.SkipStage then
		local n = math.min(d.stage + 1, FINISH)
		setStage(player, n)
		teleportToStage(player)
		notify(player, "n_skipped_stage", Color3.fromRGB(120, 255, 140))
	elseif id == P.SkipZone then
		local n = math.min(math.max(Config.ZoneOfStage(math.min(d.stage, Config.TOTAL_STAGES)) * Config.STAGES_PER_ZONE + 1, d.stage + 1), FINISH)
		setStage(player, n)
		teleportToStage(player)
		notify(player, "n_skipped_zone", Color3.fromRGB(120, 255, 140))
	elseif id == P.LavaShield then
		local duration = Config.SHIELD_DURATION + (hasPerk(player, "shieldplus") and Config.PERK_SHIELD_BONUS or 0)
		local untilT = math.max(player:GetAttribute("ShieldUntil") or 0, os.time()) + duration
		player:SetAttribute("ShieldUntil", untilT)
		-- лёгкие голубые искорки вместо шара: дорогу видно
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not root:FindFirstChild("LavaShieldFX") then
			local fx = Instance.new("Sparkles")
			fx.Name = "LavaShieldFX"
			fx.SparkleColor = Color3.fromRGB(120, 210, 255)
			fx.Parent = root
		end
		task.delay(untilT - os.time() + 0.5, function()
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if (player:GetAttribute("ShieldUntil") or 0) <= os.time() and r then
				local fx = r:FindFirstChild("LavaShieldFX")
				if fx then
					fx:Destroy()
				end
			end
		end)
		notify(player, "n_shield", Color3.fromRGB(120, 220, 255), duration)
	elseif id == P.Coins500 or id == P.Coins2500 or id == P.Coins10000 then
		local amount = (id == P.Coins500 and 500) or (id == P.Coins2500 and 2500) or 10000
		addCoins(player, amount, false)
		notify(player, "n_coins", Color3.fromRGB(255, 215, 80), amount)
	elseif id == P.UnlockWorld then
		local unlocked = false
		for w = 2, #Config.Zones do
			local first = worldRange(w)
			if d.maxStage < first then
				d.maxStage = first
				notify(player, "n_world_unlocked", Color3.fromRGB(120, 255, 140), w)
				unlocked = true
				break
			end
		end
		if not unlocked then
			addCoins(player, 500, false) -- всё уже открыто — компенсируем монетами
		end
	elseif id == P.LavaToWater then
		setWater(Config.WATER_PRODUCT_DURATION, player.DisplayName)
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(d.receipts, receipt.PurchaseId)
	while #d.receipts > 50 do
		table.remove(d.receipts, 1)
	end
	syncAttributes(player)
	task.spawn(saveData, player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============ ДЕЙСТВИЯ ИГРОКА ============
ownsItem = function(player, s, category, item)
	if item.unlock then
		return Config.UnlockMet(item.unlock, function(name)
			if name == "Ducks" then
				return countKeys(s.data.ducks)
			elseif name == "Rebirths" then
				return s.data.rebirths
			end
			return player:GetAttribute(name)
		end)
	end
	local cat = Config.ItemCategories[category]
	return s.data[cat.owned][item.id] == true
end

local function applyCategory(player, category)
	if category == "trails" then
		applyTrail(player)
	elseif category == "skins" then
		if sessions[player] and sessions[player].data.skin == "" then
			-- вернуть обычный вид: перезагружаем персонажа на его чекпоинте
			task.spawn(function()
				player:LoadCharacter()
			end)
		else
			applySkin(player)
		end
	elseif category == "pets" then
		applyPet(player)
	elseif category == "auras" then
		applyAura(player)
	elseif category == "perks" then
		applyCharacter(player)
	end
end

local function doRebirth(player, s)
	local d = s.data
	if d.maxStage < FINISH then
		notify(player, "n_finish_first")
		return
	end
	d.rebirths += 1
	d.stage = 1
	d.maxStage = 1
	d.finishedRun = false
	s.runStart = nil
	player:SetAttribute("RunStart", nil)
	setInLobby(player, true)
	local bonus = Config.REBIRTH_COINS * d.rebirths
	d.coins += bonus
	awardBadge(player, Config.Badges.Rebirth)
	syncAttributes(player)
	teleportToStage(player)
	applyOverhead(player)
	EffectRE:FireClient(player, "finish")
	notify(player, "n_rebirth", Color3.fromRGB(200, 130, 255), d.rebirths, string.format("%.1f", 1 + d.rebirths * Config.REBIRTH_BONUS), bonus)
	notifyAll("n_rebirth_all", Color3.fromRGB(200, 130, 255), player.DisplayName, d.rebirths)
	task.spawn(saveData, player)
end

ActionRE.OnServerEvent:Connect(function(player, action, arg)
	local s = sessions[player]
	if not s or not s.loaded or type(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (s.lastAction or 0) < 0.25 then
		return
	end
	s.lastAction = now
	local d = s.data

	if action == "Teleport" then
		local n = tonumber(arg)
		if not n then
			return
		end
		n = math.floor(n)
		-- перемещаться можно только внутри текущего мира
		local sameWorld = Config.ZoneOfStage(math.min(n, Config.TOTAL_STAGES)) == Config.ZoneOfStage(math.min(d.stage, Config.TOTAL_STAGES))
		if not s.inLobby and sameWorld and n >= 1 and n <= d.maxStage then
			d.stage = n
			syncAttributes(player)
			teleportToStage(player)
		end
	elseif action == "BuyItem" or action == "EquipItem" then
		if type(arg) ~= "table" then
			return
		end
		local category, id = arg.category, arg.id
		local cat = Config.ItemCategories[category]
		if not cat or type(id) ~= "string" then
			return
		end
		if action == "EquipItem" and (id == "" or not cat.equipped) then
			if not cat.equipped then
				return
			end
			d[cat.equipped] = ""
			syncAttributes(player)
			applyCategory(player, category)
			return
		end
		local item = Config.GetItem(category, id)
		if not item then
			return
		end
		if action == "BuyItem" then
			if not item.price or ownsItem(player, s, category, item) then
				return
			end
			if d.coins < item.price then
				notify(player, "n_no_coins")
				return
			end
			d.coins -= item.price
			d[cat.owned][item.id] = true
			notify(player, "n_bought_item", Color3.fromRGB(120, 255, 140), "@item_" .. category .. "_" .. item.id)
			task.spawn(saveData, player)
		elseif not ownsItem(player, s, category, item) then
			return
		end
		if cat.equipped then
			d[cat.equipped] = item.id
			if action == "EquipItem" then
				notify(player, "n_equipped", Color3.fromRGB(120, 220, 255), "@item_" .. category .. "_" .. item.id)
			end
		end
		syncAttributes(player)
		applyCategory(player, category)
	elseif action == "ClaimGift" then
		if os.time() < s.nextGift then
			return
		end
		s.giftCount += 1
		local amount = Config.GIFT_REWARDS[math.min(s.giftCount, #Config.GIFT_REWARDS)]
		local gained = addCoins(player, amount, true)
		s.nextGift = os.time() + (hasPerk(player, "fastgift") and Config.PERK_FASTGIFT_INTERVAL or Config.GIFT_INTERVAL)
		syncAttributes(player)
		EffectRE:FireClient(player, "duck")
		notify(player, "n_gift", Color3.fromRGB(255, 215, 80), gained)
		progressChallenge(player, "gift", 1)
	elseif action == "Rebirth" then
		doRebirth(player, s)
	elseif action == "Respawn" then
		teleportToStage(player)
	elseif action == "ToLobby" then
		setInLobby(player, true)
		teleportToStage(player)
	end
end)

-- ============ ВХОД / ВЫХОД ============
local function giveDaily(player, s)
	local d = s.data
	local today = math.floor(os.time() / 86400)
	if d.daily >= today then
		return
	end
	if d.daily == today - 1 then
		d.streak = (d.streak % #Config.DAILY_REWARDS) + 1
	else
		d.streak = 1
	end
	d.daily = today
	local amount = Config.DAILY_REWARDS[d.streak]
	local gained = addCoins(player, amount, true)
	task.delay(3, function()
		if player.Parent then
			notify(player, "n_daily", Color3.fromRGB(255, 215, 80), d.streak, gained)
		end
	end)
end

local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in ipairs({ "Stage", "Coins", "Rebirths" }) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player

	local s = {
		data = defaultData(),
		loaded = false,
		collected = {},
		giftCount = 0,
		nextGift = os.time() + Config.GIFT_INTERVAL,
		inLobby = true, -- игрок появляется в лобби и выбирает портал
	}
	sessions[player] = s
	player:SetAttribute("InLobby", true)

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		task.wait(0.2)
		applySkin(player)
	end)

	checkPasses(player)
	local data, ok = loadData(player)
	if not player.Parent then
		return
	end
	s.data = data
	s.noSave = not ok
	s.loaded = true
	if not ok then
		notify(player, "n_load_fail", Color3.fromRGB(255, 120, 80))
	end
	giveDaily(player, s)
	syncAttributes(player)
	syncChallenges(player)
	if s.data.dcDay ~= today() then
		s.data.dcDay = today()
		s.data.dcFound = {}
	end
	player:SetAttribute("DailyFound", csvKeys(s.data.dcFound))
	player:SetAttribute("BestTime", s.data.bestTime)
	task.delay(6, function()
		if player.Parent then
			notify(player, "n_daily_chests", Color3.fromRGB(255, 215, 80), Config.DAILY_CHESTS)
		end
	end)
	player:SetAttribute("Loaded", true)
	-- пропуск могли купить на странице игры, не заходя в неё
	for key in pairs(AUTO_EQUIP) do
		if player:GetAttribute("Pass" .. key) then
			autoEquip(player, key)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	for _, m in ipairs(petFolder:GetChildren()) do
		if m:GetAttribute("OwnerId") == player.UserId then
			m:Destroy()
		end
	end
	saveData(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	local list = Players:GetPlayers()
	local done = 0
	for _, p in ipairs(list) do
		task.spawn(function()
			saveData(p)
			done += 1
		end)
	end
	local t0 = os.clock()
	while done < #list and os.clock() - t0 < 20 do
		task.wait(0.2)
	end
end)

-- автосохранение
task.spawn(function()
	while true do
		task.wait(120)
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, p)
		end
	end
end)

-- ============ ЛИНИЯ СТАРТА: запуск таймера забега ============
for _, line in ipairs(CollectionService:GetTagged("StartLine")) do
	line.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded or s.runStart then
			return
		end
		-- таймер идёт только в «чистом» забеге: с 1 этапа, без открытых этапов дальше
		if s.data.stage <= 1 and s.data.maxStage <= 1 then
			s.runStart = workspace:GetServerTimeNow()
			s.runValid = true
			player:SetAttribute("RunStart", s.runStart)
			player:SetAttribute("RunValid", true)
			player:SetAttribute("RunTime", nil)
		end
	end)
end

-- ============ ПОРТАЛЫ МИРОВ ============
for _, disc in ipairs(CollectionService:GetTagged("WorldPortal")) do
	local w = disc:GetAttribute("World")
	disc.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded or not s.inLobby then
			return
		end
		local now = os.clock()
		if now - (s.lastPortal or 0) < 1.5 then
			return
		end
		s.lastPortal = now
		local d = s.data
		local first, last = worldRange(w)
		if d.maxStage < first then
			notify(player, "n_portal_locked", Color3.fromRGB(255, 160, 80), w - 1)
			return
		end
		-- продолжаем с самого дальнего этапа в этом мире; пройденный мир — заново с начала
		if d.maxStage <= last then
			d.stage = math.max(first, d.maxStage)
		else
			d.stage = first
		end
		-- ⏱ забег на время начинается в портале 1 у новичков
		if w == 1 and d.maxStage <= 1 and not s.runStart then
			s.runStart = workspace:GetServerTimeNow()
			s.runValid = true
			player:SetAttribute("RunStart", s.runStart)
			player:SetAttribute("RunValid", true)
			player:SetAttribute("RunTime", nil)
		end
		setInLobby(player, false)
		syncAttributes(player)
		teleportToStage(player)
		EffectRE:FireClient(player, "zone", w)
	end)
end

for _, disc in ipairs(CollectionService:GetTagged("WorldFinish")) do
	local w = disc:GetAttribute("World")
	disc.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded or s.inLobby then
			return
		end
		local d = s.data
		if Config.ZoneOfStage(math.min(d.stage, Config.TOTAL_STAGES)) ~= w then
			return
		end
		local _, last = worldRange(w)
		local nextFirst = last + 1
		if d.maxStage < nextFirst then
			-- мир пройден впервые: открываем следующий портал
			setStage(player, nextFirst)
			local gained = addCoins(player, Config.WORLD_REWARD, true)
			notify(player, "n_world_done", Color3.fromRGB(255, 215, 80), w, gained)
			EffectRE:FireClient(player, "finish")
			task.spawn(saveData, player)
		else
			d.stage = nextFirst
		end
		setInLobby(player, true)
		syncAttributes(player)
		task.delay(1.2, function()
			if player.Parent then
				teleportToStage(player)
			end
		end)
	end)
end

-- ============ МЕТЕОРИТЫ ============
local meteorFolder = Instance.new("Folder")
meteorFolder.Name = "LavaMeteors"
meteorFolder.Parent = workspace
local meteorParams = RaycastParams.new()
meteorParams.FilterType = Enum.RaycastFilterType.Exclude
local lobbyPos = map.lobbySpawn.Position

local function inLobby(pos)
	local dx, dz = pos.X - lobbyPos.X, pos.Z - lobbyPos.Z
	return dx * dx + dz * dz < 80 * 80
end

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = meteorFolder
	return p
end

local function spawnMeteor(targetPos)
	local ignore = { meteorFolder, petFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	meteorParams.FilterDescendantsInstances = ignore
	local res = workspace:Raycast(targetPos + Vector3.new(0, 30, 0), Vector3.new(0, -90, 0), meteorParams)
	if not res then
		return
	end
	local ground = res.Position
	-- красный круг-предупреждение
	local warnRing = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 9, 9),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	TweenService:Create(warnRing, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.15 }):Play()
	-- сам метеорит
	local start = ground + Vector3.new(math.random(-25, 25), 85, math.random(-25, 25))
	local rock = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.5, 4.5, 4.5),
		CFrame = CFrame.new(start),
		Color = Color3.fromRGB(70, 50, 45),
		Material = Enum.Material.Basalt,
	})
	local f = Instance.new("Fire")
	f.Size = 8
	f.Heat = 20
	f.Parent = rock
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 120, 30)
	l.Range = 18
	l.Brightness = 2
	l.Parent = rock
	TweenService:Create(rock, TweenInfo.new(1.4, Enum.EasingStyle.Linear), { CFrame = CFrame.new(ground) }):Play()
	task.delay(1.4, function()
		local blast = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), CFrame = CFrame.new(ground), Transparency = 1 })
		if refreshOverlap() then
			killInside(blast)
		end
		local ex = Instance.new("Explosion")
		ex.Position = ground
		ex.BlastPressure = 0
		ex.BlastRadius = 0
		ex.DestroyJointRadiusPercent = 0
		ex.Parent = workspace
		warnRing:Destroy()
		rock:Destroy()
		task.delay(0.2, function()
			blast:Destroy()
		end)
	end)
end

-- метеорит рядом с игроком (с упреждением по его скорости)
local function meteorNear(p)
	local _, hum, root = getCharacterParts(p)
	local s = sessions[p]
	if not root or not hum or hum.Health <= 0 or not s or s.data.stage >= FINISH or inLobby(root.Position) then
		return
	end
	local v = root.AssemblyLinearVelocity
	local target = root.Position + Vector3.new(v.X, 0, v.Z) * 1.2 + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
	task.spawn(spawnMeteor, target)
end

-- 🌋 Остров вулкана: метеориты падают всегда
task.spawn(function()
	while true do
		task.wait(Config.ZONE4_METEOR_INTERVAL)
		for _, p in ipairs(Players:GetPlayers()) do
			local s = sessions[p]
			if s and s.data.stage <= Config.TOTAL_STAGES and Config.ZoneOfStage(s.data.stage) == 4 then
				meteorNear(p)
			end
		end
	end
end)

-- ============ ГЛОБАЛЬНЫЕ СОБЫТИЯ ============
local EVENT_ORDER = { "eruption", "night", "meteors", "icestorm", "golden" }
local eventRunning = false

local function setEruptors(mult)
	for _, crater in ipairs(CollectionService:GetTagged("Eruptor")) do
		local em = crater:FindFirstChild("Eruption")
		if em then
			local base = em:GetAttribute("BaseRate") or em.Rate
			em:SetAttribute("BaseRate", base)
			em.Rate = base * mult
		end
	end
end

local function runEvent(name)
	local def = Config.Events[name]
	if not def or eventRunning then
		return
	end
	eventRunning = true
	workspace:SetAttribute("Event", name)
	workspace:SetAttribute("EventEnds", workspace:GetServerTimeNow() + def.duration)
	notifyAll("ev_" .. name, Color3.fromRGB(255, 200, 80))
	if name == "eruption" then
		setEruptors(6)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		syncAttributes(p) -- обновить множитель монет (золотой час)
	end
	local endsAt = os.clock() + def.duration
	while os.clock() < endsAt do
		if name == "meteors" then
			for _, p in ipairs(Players:GetPlayers()) do
				meteorNear(p)
			end
			task.wait(1.6)
		else
			task.wait(1)
		end
	end
	if name == "eruption" then
		setEruptors(1)
	end
	workspace:SetAttribute("Event", nil)
	workspace:SetAttribute("EventEnds", nil)
	notifyAll("ev_over", Color3.fromRGB(150, 255, 160))
	for _, p in ipairs(Players:GetPlayers()) do
		local _, hum = getCharacterParts(p)
		if hum and hum.Health > 0 then
			progressChallenge(p, "event", 1)
		end
		syncAttributes(p)
	end
	eventRunning = false
end

task.spawn(function()
	if not Config.EVENTS_ENABLED then
		return
	end
	task.wait(Config.EVENT_FIRST_DELAY)
	local last
	while true do
		local name
		repeat
			name = EVENT_ORDER[math.random(1, #EVENT_ORDER)]
		until name ~= last
		last = name
		runEvent(name)
		task.wait(math.random(Config.EVENT_INTERVAL_MIN, Config.EVENT_INTERVAL_MAX))
	end
end)

-- ============ СУНДУКИ ДНЯ ============
local dailyFolder = Instance.new("Folder")
dailyFolder.Name = "LavaDailyChests"
dailyFolder.Parent = workspace
local dailyDay = -1

local function onDailyChest(player, id)
	local s = sessions[player]
	if not s or not s.loaded then
		return
	end
	local d = s.data
	local day = today()
	if d.dcDay ~= day then
		d.dcDay = day
		d.dcFound = {}
	end
	if d.dcFound[id] then
		return
	end
	d.dcFound[id] = true
	local found = countKeys(d.dcFound)
	local gained = addCoins(player, math.random(Config.DAILY_CHEST_MIN, Config.DAILY_CHEST_MAX), true)
	notify(player, "n_daily_chest", Color3.fromRGB(255, 215, 80), found, Config.DAILY_CHESTS, gained)
	if math.random() < Config.DAILY_CHEST_TRAIL_CHANCE then
		local options = {}
		for _, t in ipairs(Config.Trails) do
			if t.price and not d.trails[t.id] then
				table.insert(options, t)
			end
		end
		if #options > 0 then
			local t = options[math.random(1, #options)]
			d.trails[t.id] = true
			notify(player, "n_daily_chest_trail", Color3.fromRGB(200, 150, 255), "@item_trails_" .. t.id)
		end
	end
	EffectRE:FireClient(player, "duck")
	player:SetAttribute("DailyFound", csvKeys(d.dcFound))
	progressChallenge(player, "secret", 1)
	syncAttributes(player)
	task.spawn(saveData, player)
end

local function buildDailyChests()
	local day = today()
	if day == dailyDay then
		return false
	end
	dailyDay = day
	dailyFolder:ClearAllChildren()
	local rng = Random.new(day * 917 + 3)
	local candidates = {}
	for n = 3, Config.TOTAL_STAGES do
		if map.checkpoints[n] then
			table.insert(candidates, n)
		end
	end
	for _ = 1, math.min(Config.DAILY_CHESTS, #candidates) do
		local n = table.remove(candidates, rng:NextInteger(1, #candidates))
		local pad = map.checkpoints[n]
		local spawnCf = map.spawnCF[n] or pad.CFrame
		local cf = spawnCf * CFrame.new(5, -3.5, 5)
		local id = "d" .. day .. "_" .. n
		local model = Instance.new("Model")
		model.Name = "DailyChest"
		local function cp(size, offset, color, material)
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.Size = size
			p.CFrame = cf * offset
			p.Color = color
			p.Material = material or Enum.Material.SmoothPlastic
			p.Parent = model
			return p
		end
		local base = cp(Vector3.new(3.4, 2.2, 2.6), CFrame.new(0, 1.1, 0), Color3.fromRGB(160, 90, 255))
		cp(Vector3.new(3.6, 0.9, 2.8), CFrame.new(0, 2.6, 0), Color3.fromRGB(255, 210, 60), Enum.Material.Foil)
		cp(Vector3.new(0.9, 0.9, 0.3), CFrame.new(0, 2, -1.35), Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
		-- золотой луч света, видно издалека
		local beam = cp(Vector3.new(80, 2.2, 2.2), CFrame.new(0, 42, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
		beam.Shape = Enum.PartType.Cylinder
		beam.Transparency = 0.6
		beam.CanTouch = false
		beam.CanQuery = false
		beam.CastShadow = false
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = Color3.fromRGB(255, 220, 90)
		sp.Parent = base
		base:SetAttribute("ChestId", id)
		CollectionService:AddTag(base, "DailyChest")
		model.PrimaryPart = base
		model.Parent = dailyFolder
		base.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player then
				onDailyChest(player, id)
			end
		end)
	end
	return true
end

buildDailyChests()
task.spawn(function()
	while true do
		task.wait(60)
		if buildDailyChests() then
			for _, p in ipairs(Players:GetPlayers()) do
				local s = sessions[p]
				if s then
					s.data.dcFound = {}
					s.data.dcDay = today()
					p:SetAttribute("DailyFound", "")
					syncChallenges(p)
				end
				notify(p, "n_daily_chests", Color3.fromRGB(255, 215, 80), Config.DAILY_CHESTS)
			end
		end
	end
end)

-- ============ КОМАНДЫ ДЛЯ ТЕСТА (только владелец игры или Studio) ============
-- В чате: /event eruption | night | meteors | icestorm | golden
local function canAdmin(player)
	return RunService:IsStudio() or player.UserId == game.CreatorId
end

local function onChat(player, msg)
	if not canAdmin(player) then
		return
	end
	local name = string.match(msg, "^/event%s+(%w+)")
	if name and Config.Events[name] then
		task.spawn(runEvent, name)
	end
	-- /world 3 — открыть миры до 3-го и перенестись туда (для проверки)
	local wn = tonumber(string.match(msg, "^/world%s+(%d+)"))
	local s = sessions[player]
	if wn and s and wn >= 1 and wn <= #Config.Zones then
		local first = worldRange(wn)
		s.data.maxStage = math.max(s.data.maxStage, first)
		s.data.stage = first
		setInLobby(player, false)
		syncAttributes(player)
		teleportToStage(player)
	end
end

Players.PlayerAdded:Connect(function(p)
	p.Chatted:Connect(function(msg)
		onChat(p, msg)
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.Chatted:Connect(function(msg)
		onChat(p, msg)
	end)
end

-- ============ ТАБЛИЦА ЛИДЕРОВ ============
local nameCache = {}
task.spawn(function()
	while true do
		if topStore then
			local ok, pages = pcall(function()
				return topStore:GetSortedAsync(false, 10)
			end)
			if ok and pages then
				local entries = pages:GetCurrentPage()
				for i = 1, 10 do
					local row = map.leaderboardRows[i]
					local e = entries[i]
					if row then
						if e then
							local uid = tonumber(e.key)
							local name = nameCache[uid]
							if not name and uid then
								local okName, res = pcall(function()
									return Players:GetNameFromUserIdAsync(uid)
								end)
								name = okName and res or "Player"
								nameCache[uid] = name
							end
							local reb = math.floor(e.value / 1000)
							local st = e.value % 1000
							local stText = st >= FINISH and "🏆" or tostring(st)
							row.Text = string.format("%d. %s — 🔁%d · 🏁 %s", i, name or "Player", reb, stText)
						else
							row.Text = i .. ". ---"
						end
					end
				end
			end
		end
		if timeStore then
			local ok, pages = pcall(function()
				return timeStore:GetSortedAsync(true, 10)
			end)
			if ok and pages then
				local entries = pages:GetCurrentPage()
				for i = 1, 10 do
					local row = map.timeRows[i]
					local e = entries[i]
					if row then
						if e then
							local uid = tonumber(e.key)
							local name = nameCache[uid]
							if not name and uid then
								local okName, res = pcall(function()
									return Players:GetNameFromUserIdAsync(uid)
								end)
								name = okName and res or "Player"
								nameCache[uid] = name
							end
							row.Text = string.format("%d. %s — %s", i, name or "Player", fmtTime(e.value / 100))
						else
							row.Text = i .. ". ---"
						end
					end
				end
			end
		end
		task.wait(90)
	end
end)

print("[LavaObby] Карта построена. Этапов: " .. map.totalStages)
