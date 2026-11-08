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
		pet = "",
		daily = 0,
		streak = 0,
		finishedRun = false,
		vipChest = 0,
		receipts = {},
	}
end

local function notify(player, text, color)
	NotifyRE:FireClient(player, text, color)
end

local function notifyAll(text, color)
	NotifyRE:FireAllClients(text, color)
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
	if player:GetAttribute("PassDoubleCoins") then
		m *= 2
	end
	if player:GetAttribute("PassVIP") then
		m *= Config.VIP_COIN_BONUS
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
	player:SetAttribute("NextGift", s.nextGift)
	player:SetAttribute("Multiplier", multiplier(player, s))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["Этап"].Value = math.min(d.stage, Config.TOTAL_STAGES)
		ls["Монеты"].Value = d.coins
		ls["Перерожд."].Value = d.rebirths
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
	local cf = map.spawnCF[s.data.stage] or map.spawnCF[1]
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(cf)
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
	local material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	local i = 0
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			i += 1
			if d:IsA("MeshPart") and d:FindFirstAncestorOfClass("Accessory") then
				d.TextureID = ""
			end
			d.Color = skin.colors and skin.colors[(i % #skin.colors) + 1] or skin.color
			d.Material = material
		end
	end
end

-- ============ ПИТОМЦЫ ============
local petFolder = Instance.new("Folder")
petFolder.Name = "LavaPets"
petFolder.Parent = workspace

local function petPart(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = model
	return p
end

local BALL = Enum.PartType.Ball
local function eyes(model, at, spread)
	for sx = -1, 1, 2 do
		petPart(model, { Shape = BALL, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = at * CFrame.new(sx * spread, 0, 0), Color = Color3.new(0, 0, 0) })
	end
end

local function buildPet(pet)
	local model = Instance.new("Model")
	model.Name = pet.id
	local c = pet.color
	local o = CFrame.new()
	local root
	if pet.id == "duckling" or pet.id == "goldduck" then
		local mat = pet.id == "goldduck" and Enum.Material.Foil or Enum.Material.SmoothPlastic
		root = petPart(model, { Shape = BALL, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = o, Color = c, Material = mat })
		petPart(model, { Shape = BALL, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = o * CFrame.new(0, 0.9, -0.5), Color = c, Material = mat })
		petPart(model, { Size = Vector3.new(0.5, 0.25, 0.6), CFrame = o * CFrame.new(0, 0.85, -1.15), Color = Color3.fromRGB(255, 130, 20) })
		eyes(model, o * CFrame.new(0, 1.1, -0.95), 0.25)
		if pet.id == "goldduck" then
			Instance.new("Sparkles").Parent = root
		end
	elseif pet.id == "flame" then
		root = petPart(model, { Shape = BALL, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = o, Color = c, Material = Enum.Material.Neon })
		local f = Instance.new("Fire")
		f.Size = 2
		f.Heat = 4
		f.Parent = root
		eyes(model, o * CFrame.new(0, 0.15, -0.65), 0.25)
	elseif pet.id == "cubecat" then
		root = petPart(model, { Size = Vector3.new(1.6, 1.6, 1.6), CFrame = o, Color = c })
		petPart(model, { Size = Vector3.new(0.4, 0.5, 0.3), CFrame = o * CFrame.new(-0.5, 1, 0), Color = c })
		petPart(model, { Size = Vector3.new(0.4, 0.5, 0.3), CFrame = o * CFrame.new(0.5, 1, 0), Color = c })
		petPart(model, { Size = Vector3.new(0.3, 0.2, 0.05), CFrame = o * CFrame.new(0, -0.1, -0.81), Color = Color3.fromRGB(255, 130, 160) })
		eyes(model, o * CFrame.new(0, 0.25, -0.8), 0.35)
	elseif pet.id == "slime" then
		root = petPart(model, { Shape = BALL, Size = Vector3.new(1.8, 1.8, 1.8), CFrame = o, Color = c, Material = Enum.Material.CrackedLava })
		eyes(model, o * CFrame.new(0, 0.3, -0.85), 0.3)
		local l = Instance.new("PointLight")
		l.Color = c
		l.Range = 8
		l.Parent = root
	elseif pet.id == "phoenix" then
		root = petPart(model, { Shape = BALL, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = o, Color = c, Material = Enum.Material.Neon })
		for sx = -1, 1, 2 do
			petPart(model, { Size = Vector3.new(1.6, 0.15, 0.9), CFrame = o * CFrame.new(sx * 1.2, 0.2, 0.2) * CFrame.Angles(0, 0, sx * 0.4), Color = Color3.fromRGB(255, 80, 30), Material = Enum.Material.Neon })
		end
		local f = Instance.new("Fire")
		f.Size = 2
		f.Color = Color3.fromRGB(255, 200, 60)
		f.Parent = root
		eyes(model, o * CFrame.new(0, 0.2, -0.65), 0.25)
	else -- dragon
		root = petPart(model, { Size = Vector3.new(1.2, 1.1, 1.8), CFrame = o, Color = c })
		petPart(model, { Size = Vector3.new(0.9, 0.8, 0.9), CFrame = o * CFrame.new(0, 0.6, -1.2), Color = c })
		petPart(model, { Size = Vector3.new(0.5, 0.4, 0.5), CFrame = o * CFrame.new(0, 0.45, -1.8), Color = Color3.fromRGB(60, 150, 70) })
		for sx = -1, 1, 2 do
			petPart(model, { Size = Vector3.new(1.8, 0.12, 1), CFrame = o * CFrame.new(sx * 1.4, 0.5, 0) * CFrame.Angles(0, 0, sx * 0.5), Color = Color3.fromRGB(255, 200, 60) })
			petPart(model, { Size = Vector3.new(0.15, 0.4, 0.15), CFrame = o * CFrame.new(sx * 0.25, 1.15, -1.1), Color = Color3.fromRGB(255, 240, 200) })
		end
		petPart(model, { Size = Vector3.new(0.4, 0.4, 1.4), CFrame = o * CFrame.new(0, -0.1, 1.5), Color = c })
		eyes(model, o * CFrame.new(0, 0.8, -1.66), 0.25)
		Instance.new("Sparkles").Parent = root
	end
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

local function applyCharacter(player)
	local _, hum = getCharacterParts(player)
	if hum then
		hum.WalkSpeed = player:GetAttribute("PassSpeed") and Config.SPEED_WALKSPEED or Config.NORMAL_WALKSPEED
		hum.UseJumpPower = false
		hum.JumpHeight = player:GetAttribute("PassSuperJump") and Config.SUPER_JUMP or Config.NORMAL_JUMP
	end
	applyTrail(player)
	applySkin(player)
	applyPet(player)
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
	task.delay(1.5, function()
		if player.Character == char then
			applySkin(player)
		end
	end)
end

-- ============ ЭТАПЫ ============
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
		if (n - 1) % Config.STAGES_PER_ZONE == 0 and n < FINISH then
			local zone = Config.Zones[Config.ZoneOfStage(n)]
			EffectRE:FireClient(player, "zone", Config.ZoneOfStage(n))
			notify(player, "Новая зона: " .. zone.emoji .. " " .. zone.name, zone.color)
		end
	end
	if n == FINISH and not d.finishedRun then
		d.finishedRun = true
		local gained = addCoins(player, Config.FINISH_REWARD, true)
		awardBadge(player, Config.Badges.Finish)
		EffectRE:FireClient(player, "finish")
		notify(player, "🏆 ТЫ ПРОШЁЛ ИГРУ! +" .. gained .. " 🪙", Color3.fromRGB(255, 215, 80))
		notifyAll("🏆 " .. player.DisplayName .. " прошёл всю лаву!", Color3.fromRGB(255, 215, 80))
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

local function kill(hum)
	if not hum or hum.Health <= 0 then
		return
	end
	local owner = Players:GetPlayerFromCharacter(hum.Parent)
	if owner and (owner:GetAttribute("ShieldUntil") or 0) > os.time() then
		return -- 🛡 щит от лавы
	end
	hum.Health = 0
end

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
end)

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
	notifyAll("🌊 " .. byName .. " превратил лаву в воду на " .. seconds .. " сек!", Color3.fromRGB(90, 190, 255))
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
		notifyAll("🔥 Лава вернулась!", Color3.fromRGB(255, 120, 40))
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
				notify(player, "⏳ Кнопка перезаряжается: " .. math.ceil(buttonReadyAt - now) .. " сек")
			end
			return
		end
		buttonReadyAt = now + Config.WATER_BUTTON_COOLDOWN
		setWater(Config.WATER_BUTTON_DURATION, player.DisplayName)
	end)
end

-- ============ МОНЕТЫ, УТКИ, СЕКРЕТЫ ============
for _, coin in ipairs(CollectionService:GetTagged("Coin")) do
	local id = coin:GetAttribute("CoinId")
	coin.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if not s or not s.loaded then
			return
		end
		local last = s.collected[id]
		if last and os.clock() - last < Config.COIN_RESPAWN then
			return
		end
		s.collected[id] = os.clock()
		addCoins(player, Config.COIN_VALUE, true)
		CoinRE:FireClient(player, id)
	end)
end

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
		notify(player, "🦆 Уточка найдена! " .. found .. "/" .. Config.DUCK_COUNT .. "  +" .. gained .. " 🪙", Color3.fromRGB(255, 225, 60))
		if found >= Config.DUCK_COUNT then
			addCoins(player, Config.ALL_DUCKS_REWARD, false)
			awardBadge(player, Config.Badges.AllDucks)
			notify(player, "👑 ВСЕ УТОЧКИ! +" .. Config.ALL_DUCKS_REWARD .. " 🪙 и след «Золотая утка»!", Color3.fromRGB(255, 200, 40))
			notifyAll("🦆 " .. player.DisplayName .. " нашёл всех уточек!", Color3.fromRGB(255, 225, 60))
			applyOverhead(player)
		end
		syncAttributes(player)
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
		notify(player, "🎁 Секретный сундук! +" .. gained .. " 🪙", Color3.fromRGB(255, 200, 80))
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
			notify(player, "👑 Сундук только для VIP")
			return
		end
		local left = s.data.vipChest + Config.VIP_CHEST_COOLDOWN - os.time()
		if left > 0 then
			notify(player, "⏳ VIP-сундук откроется через " .. math.ceil(left / 60) .. " мин")
			return
		end
		s.data.vipChest = os.time()
		local gained = addCoins(player, Config.VIP_CHEST_REWARD, true)
		EffectRE:FireClient(player, "duck")
		notify(player, "👑 VIP-сундук: +" .. gained .. " 🪙", Color3.fromRGB(255, 215, 80))
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

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for key, id in pairs(Config.GamePasses) do
		if id == passId then
			player:SetAttribute("Pass" .. key, true)
			notify(player, "Спасибо за покупку! ❤️", Color3.fromRGB(120, 255, 140))
			local nice = key
			for _, sp in ipairs(Config.ShopPasses) do
				if sp.key == key then
					nice = sp.name
				end
			end
			notifyAll("💎 " .. player.DisplayName .. " купил " .. nice .. "!", Color3.fromRGB(190, 140, 255))
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
	if id == P.SkipStage then
		local n = math.min(d.stage + 1, FINISH)
		setStage(player, n)
		teleportToStage(player)
		notify(player, "⏭ Этап пропущен!", Color3.fromRGB(120, 255, 140))
	elseif id == P.SkipZone then
		local n = math.min(math.max(Config.ZoneOfStage(math.min(d.stage, Config.TOTAL_STAGES)) * Config.STAGES_PER_ZONE + 1, d.stage + 1), FINISH)
		setStage(player, n)
		teleportToStage(player)
		notify(player, "⏩ Зона пропущена!", Color3.fromRGB(120, 255, 140))
	elseif id == P.LavaShield then
		local untilT = math.max(player:GetAttribute("ShieldUntil") or 0, os.time()) + Config.SHIELD_DURATION
		player:SetAttribute("ShieldUntil", untilT)
		local char = player.Character
		if char and not char:FindFirstChild("LavaShieldFF") then
			local ff = Instance.new("ForceField")
			ff.Name = "LavaShieldFF"
			ff.Parent = char
		end
		task.delay(untilT - os.time() + 0.5, function()
			if (player:GetAttribute("ShieldUntil") or 0) <= os.time() and player.Character then
				local ff = player.Character:FindFirstChild("LavaShieldFF")
				if ff then
					ff:Destroy()
				end
			end
		end)
		notify(player, "🛡 Щит от лавы на " .. Config.SHIELD_DURATION .. " сек!", Color3.fromRGB(120, 220, 255))
	elseif id == P.Coins500 or id == P.Coins2500 or id == P.Coins10000 then
		local amount = (id == P.Coins500 and 500) or (id == P.Coins2500 and 2500) or 10000
		addCoins(player, amount, false)
		notify(player, "💰 +" .. amount .. " монет!", Color3.fromRGB(255, 215, 80))
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
	end
end

local function doRebirth(player, s)
	local d = s.data
	if d.maxStage < FINISH then
		notify(player, "Сначала дойди до финиша 🏆")
		return
	end
	d.rebirths += 1
	d.stage = 1
	d.maxStage = 1
	d.finishedRun = false
	local bonus = Config.REBIRTH_COINS * d.rebirths
	d.coins += bonus
	awardBadge(player, Config.Badges.Rebirth)
	syncAttributes(player)
	teleportToStage(player)
	applyOverhead(player)
	EffectRE:FireClient(player, "finish")
	notify(player, "🔁 Перерождение " .. d.rebirths .. "! Монеты x" .. string.format("%.1f", 1 + d.rebirths * Config.REBIRTH_BONUS) .. "  +" .. bonus .. " 🪙", Color3.fromRGB(200, 130, 255))
	notifyAll("🔁 " .. player.DisplayName .. " переродился (" .. d.rebirths .. ")!", Color3.fromRGB(200, 130, 255))
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
		if n >= 1 and n <= d.maxStage then
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
		if action == "EquipItem" and id == "" then
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
				notify(player, "Не хватает монет 🪙 Собирай монетки на этапах или купи набор 💰")
				return
			end
			d.coins -= item.price
			d[cat.owned][item.id] = true
			notify(player, "✨ Куплено: «" .. item.name .. "»!", Color3.fromRGB(120, 255, 140))
			task.spawn(saveData, player)
		elseif not ownsItem(player, s, category, item) then
			return
		end
		d[cat.equipped] = item.id
		syncAttributes(player)
		applyCategory(player, category)
	elseif action == "ClaimGift" then
		if os.time() < s.nextGift then
			return
		end
		s.giftCount += 1
		local amount = Config.GIFT_REWARDS[math.min(s.giftCount, #Config.GIFT_REWARDS)]
		local gained = addCoins(player, amount, true)
		s.nextGift = os.time() + Config.GIFT_INTERVAL
		syncAttributes(player)
		EffectRE:FireClient(player, "duck")
		notify(player, "🎁 Подарок: +" .. gained .. " 🪙  Следующий через 5 минут!", Color3.fromRGB(255, 215, 80))
	elseif action == "Rebirth" then
		doRebirth(player, s)
	elseif action == "Respawn" then
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
			notify(player, "📅 Ежедневная награда (день " .. d.streak .. "): +" .. gained .. " 🪙  Заходи завтра!", Color3.fromRGB(255, 215, 80))
		end
	end)
end

local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in ipairs({ "Этап", "Монеты", "Перерожд." }) do
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
	}
	sessions[player] = s

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
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
		notify(player, "⚠️ Не удалось загрузить прогресс. Сохранение в этой сессии отключено.", Color3.fromRGB(255, 120, 80))
	end
	giveDaily(player, s)
	syncAttributes(player)
	player:SetAttribute("Loaded", true)
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
								name = okName and res or "Игрок"
								nameCache[uid] = name
							end
							local reb = math.floor(e.value / 1000)
							local st = e.value % 1000
							local stText = st >= FINISH and "🏆" or ("этап " .. st)
							row.Text = string.format("%d. %s — 🔁%d · %s", i, name or "Игрок", reb, stText)
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
