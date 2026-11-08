-- LavaClient (LocalScript в StarterPlayer > StarterPlayerScripts)
-- Интерфейс игрока: этап, монеты, магазин, подарки, перерождение,
-- а также батуты, вращение монет, VIP-дверь и эффекты.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("LavaConfig"))
local remotes = ReplicatedStorage:WaitForChild("LavaRemotes")
local NotifyRE = remotes:WaitForChild("Notify")
local CoinRE = remotes:WaitForChild("CoinHidden")
local EffectRE = remotes:WaitForChild("Effect")
local ActionRE = remotes:WaitForChild("Action")

local TOTAL = Config.TOTAL_STAGES
local FINISH = TOTAL + 1

-- ============ UI-ПОМОЩНИКИ ============
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

local function outline(o, color, thick)
	new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function textStroke(o)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, o)
end

local DARK = Color3.fromRGB(30, 20, 25)
local GOLD = Color3.fromRGB(255, 205, 60)
local scales = {}

local function scaled(o)
	local s = new("UIScale", { Scale = 1 }, o)
	table.insert(scales, s)
	return o
end

local function button(props, parent)
	local b = new("TextButton", {
		AutoButtonColor = true,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = props.color or Color3.fromRGB(255, 120, 40),
		Size = props.size or UDim2.new(1, 0, 0, 46),
		Position = props.position or UDim2.new(),
		Text = props.text or "",
		LayoutOrder = props.order or 0,
	}, parent)
	corner(b, 12)
	outline(b, Color3.new(0, 0, 0), 2)
	textStroke(b)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, b)
	return b
end

local gui = new("ScreenGui", { Name = "LavaUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- ============ ВЕРХНЯЯ ПАНЕЛЬ: ЭТАП ============
local top = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(300, 70),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
}, gui))
corner(top, 14)
outline(top, Color3.fromRGB(255, 120, 40), 2)
local stageLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.fromOffset(0, 4),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Этап 1 / " .. TOTAL,
}, top)
textStroke(stageLabel)
local zoneLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.fromOffset(0, 36),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 200, 120),
	Text = "",
}, top)
local barBack = new("Frame", { Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 57), BackgroundColor3 = Color3.fromRGB(60, 40, 40) }, top)
corner(barBack, 4)
local barFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 40) }, barBack)
corner(barFill, 4)

local prevBtn = button({ text = "◀", size = UDim2.fromOffset(50, 50), position = UDim2.new(0, -58, 0, 10), color = Color3.fromRGB(80, 60, 70) }, top)
local nextBtn = button({ text = "▶", size = UDim2.fromOffset(50, 50), position = UDim2.new(1, 8, 0, 10), color = Color3.fromRGB(80, 60, 70) }, top)

-- ============ ЛЕВАЯ КОЛОНКА: КНОПКИ ============
local left = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.45, 0),
	Size = UDim2.fromOffset(160, 400),
	BackgroundTransparency = 1,
}, gui))
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, left)
local shopBtn = button({ text = "🛒 Магазин", color = Color3.fromRGB(60, 170, 90), order = 1 }, left)
local vipBtn = button({ text = "👑 VIP", color = Color3.fromRGB(230, 170, 20), order = 2 }, left)
local giftBtn = button({ text = "🎁 5:00", color = Color3.fromRGB(150, 90, 200), order = 3 }, left)
local skipBtn = button({ text = "⏭ Пропуск", color = Color3.fromRGB(230, 140, 30), order = 4 }, left)
local shieldBtn = button({ text = "🛡 Щит", color = Color3.fromRGB(40, 130, 230), order = 5 }, left)
local respawnBtn = button({ text = "↩ К чекпоинту", color = Color3.fromRGB(90, 90, 100), order = 5 }, left)
local rebirthBtn = button({ text = "🔁 Перерождение", color = Color3.fromRGB(200, 60, 200), order = 6 }, left)
rebirthBtn.Visible = false

-- ============ ПРАВАЯ КОЛОНКА: СЧЁТЧИКИ ============
local right = scaled(new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.4, 0),
	Size = UDim2.fromOffset(160, 150),
	BackgroundTransparency = 1,
}, gui))
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
local function counter(text, order)
	local f = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		LayoutOrder = order,
	}, right)
	corner(f, 10)
	textStroke(f)
	new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, f)
	return f
end
local coinsLabel = counter("🪙 0", 1)
local ducksLabel = counter("🦆 0/" .. Config.DUCK_COUNT, 2)
local multLabel = counter("x1", 3)
local shieldLabel = counter("🛡 0", 4)
shieldLabel.Visible = false

-- ============ УВЕДОМЛЕНИЯ ============
local toastArea = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 90),
	Size = UDim2.new(0.6, 0, 0, 220),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastArea)
local toastOrder = 0

local function toast(text, color)
	toastOrder += 1
	local t = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color or Color3.new(1, 1, 1),
		Text = text,
		LayoutOrder = toastOrder,
	}, toastArea)
	corner(t, 10)
	textStroke(t)
	new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, t)
	local kids = {}
	for _, c in ipairs(toastArea:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids > 5 then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	task.delay(4.5, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			t:Destroy()
		end
	end)
end

NotifyRE.OnClientEvent:Connect(toast)

-- ============ БОЛЬШОЙ БАННЕР ============
local banner = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.new(0.8, 0, 0, 90),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	Text = "",
}, gui)
local bannerStroke = new("UIStroke", { Thickness = 4, Color = Color3.new(0, 0, 0), Transparency = 1 }, banner)

local function showBanner(text, color)
	banner.Text = text
	banner.TextColor3 = color or Color3.new(1, 1, 1)
	banner.TextTransparency = 0
	bannerStroke.Transparency = 0
	banner.Size = UDim2.new(0.5, 0, 0, 60)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 90) }):Play()
	task.delay(2.6, function()
		if banner.Text == text then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			TweenService:Create(bannerStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
end

local warnLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(0.7, 0, 0, 50),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 80, 40),
	Text = "",
	Visible = false,
}, gui)
textStroke(warnLabel)

-- ============ МАГАЗИН ============
local shop = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(580, 420),
	BackgroundColor3 = Color3.fromRGB(40, 28, 34),
	Visible = false,
	ZIndex = 5,
}, gui))
corner(shop, 18)
outline(shop, Color3.fromRGB(255, 140, 50), 3)
local shopTitle = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -80, 0, 44),
	Position = UDim2.fromOffset(16, 8),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = GOLD,
	Text = "🛒 МАГАЗИН",
	ZIndex = 6,
}, shop)
textStroke(shopTitle)
local closeBtn = button({ text = "✕", size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -56, 0, 10), color = Color3.fromRGB(200, 50, 50) }, shop)
closeBtn.ZIndex = 6
local TABS = { { "trails", "✨ Следы" }, { "skins", "🎨 Скины" }, { "pets", "🐾 Питомцы" }, { "robux", "💎 Robux" } }
local tabButtons = {}
for i, t in ipairs(TABS) do
	local b = button({ text = t[2], size = UDim2.fromOffset(128, 38), position = UDim2.fromOffset(16 + (i - 1) * 136, 60), color = Color3.fromRGB(90, 70, 80) }, shop)
	b.ZIndex = 6
	tabButtons[t[1]] = b
end
local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 110),
	Size = UDim2.new(1, -32, 1, -126),
	BackgroundTransparency = 1,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 6,
}, shop)
new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 160), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local currentTab = "trails"

local function csvSet(str)
	local set = {}
	for id in string.gmatch(str or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function attrGetter(name)
	return player:GetAttribute(name)
end
local CAT_ATTR = { trails = { "Trails", "Trail" }, skins = { "Skins", "Skin" }, pets = { "Pets", "Pet" } }

local function ownsItem(category, item)
	if item.unlock then
		return Config.UnlockMet(item.unlock, attrGetter)
	end
	return csvSet(player:GetAttribute(CAT_ATTR[category][1]))[item.id] == true
end

local function card(order, title, desc, colors, btnText, btnColor, onClick)
	local c = new("Frame", { BackgroundColor3 = Color3.fromRGB(60, 45, 52), LayoutOrder = order, ZIndex = 6 }, list)
	corner(c, 12)
	if colors then
		local strip = new("Frame", { Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, c)
		corner(strip, 7)
		local kps = {}
		for i, col in ipairs(colors) do
			table.insert(kps, ColorSequenceKeypoint.new(#colors == 1 and 0 or (i - 1) / (#colors - 1), col))
		end
		if #colors == 1 then
			table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
		end
		new("UIGradient", { Color = ColorSequence.new(kps) }, strip)
	end
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 26),
		Size = UDim2.new(1, -16, 0, 28),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = title,
		ZIndex = 7,
	}, c)
	textStroke(t)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 56),
		Size = UDim2.new(1, -16, 0, 50),
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(230, 220, 220),
		Text = desc,
		ZIndex = 7,
	}, c)
	local b = button({ text = btnText, size = UDim2.new(1, -16, 0, 40), position = UDim2.new(0, 8, 1, -48), color = btnColor }, c)
	b.ZIndex = 7
	b.Activated:Connect(onClick)
end

local function clearList()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

local function notConfigured()
	toast("⚙️ Эта покупка ещё не настроена (см. README)", Color3.fromRGB(255, 200, 120))
end

local function promptProduct(key)
	local id = Config.Products[key]
	if not id or id == 0 then
		notConfigured()
		return
	end
	MarketplaceService:PromptProductPurchase(player, id)
end

local function promptPass(key)
	local id = Config.GamePasses[key]
	if not id or id == 0 then
		notConfigured()
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, id)
end

local function refreshShop()
	if not shop.Visible then
		return
	end
	clearList()
	if currentTab ~= "robux" then
		local category = currentTab
		local cat = Config.ItemCategories[category]
		local equipped = player:GetAttribute(CAT_ATTR[category][2]) or ""
		local noneText = { trails = "Без следа", skins = "Обычный вид", pets = "Без питомца" }
		card(0, noneText[category], "Снять то, что надето.", nil, equipped == "" and "Выбрано ✓" or "Снять", Color3.fromRGB(90, 90, 100), function()
			ActionRE:FireServer("EquipItem", { category = category, id = "" })
		end)
		for i, item in ipairs(Config[cat.list]) do
			local owned = ownsItem(category, item)
			local colors = item.colors or (item.color and { item.color }) or nil
			local desc
			if item.price then
				desc = owned and "Твоё ✨" or ("Цена: " .. item.price .. " 🪙")
			else
				desc = Config.UnlockText[item.unlock] or ""
			end
			if item.bonus then
				desc = "+" .. math.floor(item.bonus * 100 + 0.5) .. "% к монетам\n" .. desc
			end
			local btnText, btnColor, action
			if equipped == item.id and owned then
				btnText, btnColor = "Надето ✓", Color3.fromRGB(60, 170, 90)
				action = function() end
			elseif owned then
				btnText, btnColor = "Надеть", Color3.fromRGB(60, 140, 230)
				action = function()
					ActionRE:FireServer("EquipItem", { category = category, id = item.id })
				end
			elseif item.price then
				btnText, btnColor = "Купить " .. item.price .. " 🪙", Color3.fromRGB(255, 140, 40)
				action = function()
					ActionRE:FireServer("BuyItem", { category = category, id = item.id })
				end
			elseif item.unlock == "vip" or string.sub(item.unlock or "", 1, 5) == "pass:" then
				local key = item.unlock == "vip" and "VIP" or string.sub(item.unlock, 6)
				btnText, btnColor = "💎 Получить", Color3.fromRGB(0, 170, 110)
				action = function()
					promptPass(key)
				end
			else
				btnText, btnColor = "🔒 Закрыто", Color3.fromRGB(80, 70, 75)
				action = function()
					toast("🔒 " .. (Config.UnlockText[item.unlock] or ""))
				end
			end
			card(i, item.name, desc, colors, btnText, btnColor, action)
		end
	else
		local order = 0
		for _, p in ipairs(Config.ShopPasses) do
			order += 1
			local owned = player:GetAttribute("Pass" .. p.key) == true
			card(order, p.name, p.desc, nil, owned and "Куплено ✓" or "Купить 💎", owned and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(0, 170, 110), function()
				if not owned then
					promptPass(p.key)
				end
			end)
		end
		for _, p in ipairs(Config.ShopProducts) do
			order += 1
			card(order, p.name, p.desc, nil, "Купить 💎", Color3.fromRGB(0, 170, 110), function()
				promptProduct(p.key)
			end)
		end
	end
end

local function setTab(tab)
	currentTab = tab
	for key, b in pairs(tabButtons) do
		b.BackgroundColor3 = key == tab and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(90, 70, 80)
	end
	refreshShop()
end
setTab("trails")

shopBtn.Activated:Connect(function()
	shop.Visible = not shop.Visible
	refreshShop()
end)
closeBtn.Activated:Connect(function()
	shop.Visible = false
end)
for key, b in pairs(tabButtons) do
	b.Activated:Connect(function()
		setTab(key)
	end)
end

local function openShop(tab)
	shop.Visible = true
	setTab(tab)
end

-- ============ ОКНО ПЕРЕРОЖДЕНИЯ ============
local rebirthWin = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(400, 220),
	BackgroundColor3 = Color3.fromRGB(45, 25, 55),
	Visible = false,
	ZIndex = 8,
}, gui))
corner(rebirthWin, 18)
outline(rebirthWin, Color3.fromRGB(200, 90, 255), 3)
local rebirthText = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 130),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	ZIndex = 9,
}, rebirthWin)
local yesBtn = button({ text = "🔁 Да!", size = UDim2.new(0.5, -24, 0, 48), position = UDim2.new(0, 16, 1, -62), color = Color3.fromRGB(200, 60, 200) }, rebirthWin)
local noBtn = button({ text = "Позже", size = UDim2.new(0.5, -24, 0, 48), position = UDim2.new(0.5, 8, 1, -62), color = Color3.fromRGB(90, 90, 100) }, rebirthWin)
yesBtn.ZIndex = 9
noBtn.ZIndex = 9

rebirthBtn.Activated:Connect(function()
	local reb = (player:GetAttribute("Rebirths") or 0) + 1
	rebirthText.Text = "Перерождение " .. reb .. "\nТы начнёшь с 1 этапа, но монеты будут x"
		.. string.format("%.1f", 1 + reb * Config.REBIRTH_BONUS)
		.. " навсегда и +" .. (Config.REBIRTH_COINS * reb) .. " 🪙 сразу!"
	rebirthWin.Visible = true
end)
yesBtn.Activated:Connect(function()
	rebirthWin.Visible = false
	ActionRE:FireServer("Rebirth")
end)
noBtn.Activated:Connect(function()
	rebirthWin.Visible = false
end)

-- ============ КНОПКИ ============
prevBtn.Activated:Connect(function()
	local st = player:GetAttribute("Stage") or 1
	if st > 1 then
		ActionRE:FireServer("Teleport", st - 1)
	end
end)
nextBtn.Activated:Connect(function()
	local st = player:GetAttribute("Stage") or 1
	local mx = player:GetAttribute("MaxStage") or 1
	if st < mx then
		ActionRE:FireServer("Teleport", st + 1)
	else
		toast("Сначала пройди этот этап 💪")
	end
end)
skipBtn.Activated:Connect(function()
	promptProduct("SkipStage")
end)
shieldBtn.Activated:Connect(function()
	promptProduct("LavaShield")
end)
vipBtn.Activated:Connect(function()
	if Config.GamePasses.VIP ~= 0 then
		promptPass("VIP")
	else
		openShop("robux")
	end
end)
respawnBtn.Activated:Connect(function()
	ActionRE:FireServer("Respawn")
end)
giftBtn.Activated:Connect(function()
	local nextGift = player:GetAttribute("NextGift") or 0
	if os.time() >= nextGift then
		ActionRE:FireServer("ClaimGift")
	else
		toast("🎁 Подарок будет доступен совсем скоро!")
	end
end)

-- ============ ОБНОВЛЕНИЕ HUD ============
local lastZone = nil

local function refreshHud()
	local st = player:GetAttribute("Stage") or 1
	local mx = player:GetAttribute("MaxStage") or 1
	if st >= FINISH then
		stageLabel.Text = "🏆 ФИНИШ!"
		zoneLabel.Text = "Ты прошёл все " .. TOTAL .. " этапов"
		barFill.Size = UDim2.fromScale(1, 1)
	else
		stageLabel.Text = "Этап " .. st .. " / " .. TOTAL
		local z = Config.ZoneOfStage(st)
		local zone = Config.Zones[z]
		zoneLabel.Text = zone.emoji .. " " .. zone.name
		zoneLabel.TextColor3 = zone.color
		barFill.Size = UDim2.fromScale((st - 1) / TOTAL, 1)
		barFill.BackgroundColor3 = zone.color
	end
	prevBtn.Visible = st > 1
	nextBtn.Visible = st < mx
	rebirthBtn.Visible = mx >= FINISH
	coinsLabel.Text = "🪙 " .. (player:GetAttribute("Coins") or 0)
	ducksLabel.Text = "🦆 " .. (player:GetAttribute("Ducks") or 0) .. "/" .. Config.DUCK_COUNT
	local mult = player:GetAttribute("Multiplier") or 1
	local reb = player:GetAttribute("Rebirths") or 0
	multLabel.Text = "x" .. string.format("%.2g", mult) .. " 🪙" .. (reb > 0 and ("  🔁" .. reb) or "")
	skipBtn.Visible = st < FINISH
	vipBtn.Visible = player:GetAttribute("PassVIP") ~= true
end

for _, attr in ipairs({ "Stage", "MaxStage", "Coins", "Ducks", "Multiplier", "Rebirths", "PassVIP" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
for _, attr in ipairs({
	"Coins", "Trails", "Trail", "Skins", "Skin", "Pets", "Pet", "Ducks", "Rebirths",
	"PassVIP", "PassSpeed", "PassSuperJump", "PassDoubleCoins", "PassSkinPack", "PassDragonPet",
}) do
	player:GetAttributeChangedSignal(attr):Connect(refreshShop)
end
refreshHud()

-- таймер подарка
task.spawn(function()
	while true do
		local nextGift = player:GetAttribute("NextGift")
		if nextGift then
			local leftSec = nextGift - os.time()
			if leftSec <= 0 then
				giftBtn.Text = "🎁 ЗАБРАТЬ!"
				giftBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 30)
			else
				giftBtn.Text = string.format("🎁 %d:%02d", math.floor(leftSec / 60), leftSec % 60)
				giftBtn.BackgroundColor3 = Color3.fromRGB(150, 90, 200)
			end
		end
		task.wait(0.5)
	end
end)

-- ============ ЭФФЕКТЫ ============
local function burst(count, colors)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local att = new("Attachment", {}, root)
	local kps = {}
	for i, c in ipairs(colors) do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	if #kps == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
	end
	local em = new("ParticleEmitter", {
		Color = ColorSequence.new(kps),
		LightEmission = 0.6,
		Size = NumberSequence.new(0.5, 0.1),
		Speed = NumberRange.new(15, 30),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -35, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 0,
	}, att)
	em:Emit(count)
	task.delay(3, function()
		att:Destroy()
	end)
end

local CONFETTI = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 210, 50), Color3.fromRGB(70, 220, 100), Color3.fromRGB(70, 150, 255), Color3.fromRGB(200, 90, 255) }

EffectRE.OnClientEvent:Connect(function(kind, arg)
	if kind == "checkpoint" then
		burst(25, { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 120, 40) })
	elseif kind == "zone" then
		local zone = Config.Zones[arg]
		if zone then
			showBanner("ЗОНА " .. arg .. ": " .. zone.emoji .. " " .. zone.name, zone.color)
		end
		burst(60, CONFETTI)
	elseif kind == "finish" then
		showBanner("🏆 ПОБЕДА! 🏆", GOLD)
		burst(150, CONFETTI)
	elseif kind == "duck" then
		burst(40, { Color3.fromRGB(255, 230, 60), Color3.new(1, 1, 1) })
	end
end)

-- ============ ВОЛНА ЛАВЫ / ВОДА ============
local function inZone4()
	local st = player:GetAttribute("Stage") or 1
	return Config.ZoneOfStage(math.min(st, TOTAL)) == 4 and st <= TOTAL
end

local function refreshWarn()
	local state = workspace:GetAttribute("WaveState")
	if workspace:GetAttribute("LavaIsWater") then
		local leftSec = (workspace:GetAttribute("WaterUntil") or 0) - os.time()
		warnLabel.Visible = true
		warnLabel.TextColor3 = Color3.fromRGB(90, 190, 255)
		warnLabel.Text = "🌊 ЛАВА — ЭТО ВОДА! " .. math.max(leftSec, 0) .. " сек"
		return
	end
	warnLabel.TextColor3 = Color3.fromRGB(255, 80, 40)
	if inZone4() and (state == "warn" or state == "up") then
		warnLabel.Visible = true
		warnLabel.Text = state == "warn" and "⚠️ ЛАВА ПОДНИМАЕТСЯ! НА ОСТРОВОК!" or "🔥 ВОЛНА ЛАВЫ! 🔥"
	else
		warnLabel.Visible = false
	end
end
workspace:GetAttributeChangedSignal("WaveState"):Connect(refreshWarn)
workspace:GetAttributeChangedSignal("LavaIsWater"):Connect(refreshWarn)
task.spawn(function()
	while true do
		task.wait(1)
		if workspace:GetAttribute("LavaIsWater") then
			refreshWarn()
		end
	end
end)

-- ============ МОНЕТЫ: ВРАЩЕНИЕ И СКРЫТИЕ ============
local coins = {}
local coinById = {}

local function registerCoin(c)
	if coins[c] then
		return
	end
	coins[c] = c.CFrame
	local id = c:GetAttribute("CoinId")
	if id then
		coinById[id] = c
	end
end
for _, c in ipairs(CollectionService:GetTagged("Coin")) do
	registerCoin(c)
end
CollectionService:GetInstanceAddedSignal("Coin"):Connect(registerCoin)

RunService.RenderStepped:Connect(function()
	local a = os.clock() * 2
	local rot = CFrame.Angles(0, a, 0)
	local bob = math.sin(a * 1.5) * 0.3
	for c, base in pairs(coins) do
		if c.Parent then
			c.CFrame = (base + Vector3.new(0, bob, 0)) * rot
		end
	end
end)

CoinRE.OnClientEvent:Connect(function(id)
	local c = coinById[id]
	if c then
		c.Transparency = 1
		task.delay(Config.COIN_RESPAWN, function()
			c.Transparency = 0
		end)
	end
end)

-- ============ УТКИ: СКРЫВАЕМ НАЙДЕННЫХ ============
local function refreshDucks()
	local found = csvSet(player:GetAttribute("DucksList"))
	for _, body in ipairs(CollectionService:GetTagged("Duck")) do
		local id = tostring(body:GetAttribute("DuckId"))
		local model = body.Parent
		if found[id] and model then
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 0.85
				elseif p:IsA("PointLight") then
					p.Enabled = false
				end
			end
		end
	end
end
player:GetAttributeChangedSignal("DucksList"):Connect(refreshDucks)
CollectionService:GetInstanceAddedSignal("Duck"):Connect(refreshDucks)
refreshDucks()

-- ============ VIP-ДВЕРЬ ============
local function refreshVipDoor()
	local vip = player:GetAttribute("PassVIP") == true
	for _, door in ipairs(CollectionService:GetTagged("VipDoor")) do
		door.CanCollide = not vip
		door.Transparency = vip and 0.75 or 0.35
	end
end
player:GetAttributeChangedSignal("PassVIP"):Connect(refreshVipDoor)
CollectionService:GetInstanceAddedSignal("VipDoor"):Connect(refreshVipDoor)
refreshVipDoor()

-- ============ БАТУТЫ ============
local lastBounce = 0
local function registerBounce(pad)
	pad.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) then
			return
		end
		if os.clock() - lastBounce < 0.4 then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not root or hum.Health <= 0 then
			return
		end
		lastBounce = os.clock()
		local launch = pad:GetAttribute("Launch") or Vector3.new(0, 95, 0)
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = launch
	end)
end
for _, pad in ipairs(CollectionService:GetTagged("Bounce")) do
	registerBounce(pad)
end
CollectionService:GetInstanceAddedSignal("Bounce"):Connect(registerBounce)

-- ============ МАСШТАБ ПОД ЭКРАН (телефоны) ============
local function rescale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local k = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.1)
	for _, s in ipairs(scales) do
		s.Scale = k
	end
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

-- ============ ПИТОМЦЫ ЛЕТАЮТ ЗА ХОЗЯЕВАМИ ============
local petFolder = workspace:WaitForChild("LavaPets", 30)
local petState = {}
RunService.RenderStepped:Connect(function(dt)
	if not petFolder then
		return
	end
	local t = os.clock()
	for _, model in ipairs(petFolder:GetChildren()) do
		local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
		local char = owner and owner.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and model.PrimaryPart then
			local target = root.CFrame * CFrame.new(2.6, 1.2 + math.sin(t * 3) * 0.4, 2.2)
			local cur = petState[model] or target
			cur = cur:Lerp(target, math.clamp(dt * 8, 0, 1))
			petState[model] = cur
			model:PivotTo(cur)
		end
	end
	for model in pairs(petState) do
		if not model.Parent then
			petState[model] = nil
		end
	end
end)

-- ============ ЩИТ: ТАЙМЕР ============
task.spawn(function()
	while true do
		local leftSec = (player:GetAttribute("ShieldUntil") or 0) - os.time()
		shieldLabel.Visible = leftSec > 0
		if leftSec > 0 then
			shieldLabel.Text = "🛡 " .. leftSec .. " сек"
		end
		task.wait(0.5)
	end
end)

-- ============ «СЛОЖНО? ПРОПУСТИ ЭТАП» ПОСЛЕ 3 СМЕРТЕЙ ============
local helpWin = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(380, 230),
	BackgroundColor3 = Color3.fromRGB(45, 28, 30),
	Visible = false,
	ZIndex = 8,
}, gui))
corner(helpWin, 18)
outline(helpWin, Color3.fromRGB(255, 140, 50), 3)
local helpTitle = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -24, 0, 60),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Сложный этап? 😅\nМожно пропустить!",
	ZIndex = 9,
}, helpWin)
textStroke(helpTitle)
local helpSkip = button({ text = "⏭ Пропустить этап", size = UDim2.new(1, -24, 0, 44), position = UDim2.fromOffset(12, 78), color = Color3.fromRGB(230, 140, 30) }, helpWin)
local helpShield = button({ text = "🛡 Щит от лавы", size = UDim2.new(0.5, -18, 0, 44), position = UDim2.fromOffset(12, 130), color = Color3.fromRGB(40, 130, 230) }, helpWin)
local helpJump = button({ text = "🦘 Супер-прыжок", size = UDim2.new(0.5, -18, 0, 44), position = UDim2.new(0.5, 6, 0, 130), color = Color3.fromRGB(60, 170, 90) }, helpWin)
local helpClose = button({ text = "Попробую ещё 💪", size = UDim2.new(1, -24, 0, 36), position = UDim2.new(0, 12, 1, -46), color = Color3.fromRGB(90, 90, 100) }, helpWin)
for _, b in ipairs({ helpSkip, helpShield, helpJump, helpClose }) do
	b.ZIndex = 9
end
helpSkip.Activated:Connect(function()
	helpWin.Visible = false
	promptProduct("SkipStage")
end)
helpShield.Activated:Connect(function()
	helpWin.Visible = false
	promptProduct("LavaShield")
end)
helpJump.Activated:Connect(function()
	helpWin.Visible = false
	promptPass("SuperJump")
end)
helpClose.Activated:Connect(function()
	helpWin.Visible = false
end)

local deathsOnStage = 0
local deathStage = 0
local function watchDeaths(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		local st = player:GetAttribute("Stage") or 1
		if st ~= deathStage then
			deathStage = st
			deathsOnStage = 0
		end
		deathsOnStage += 1
		if deathsOnStage % 3 == 0 and st < FINISH then
			task.delay(1.2, function()
				helpJump.Visible = player:GetAttribute("PassSuperJump") ~= true
				helpWin.Visible = true
			end)
		end
	end)
end
if player.Character then
	task.spawn(watchDeaths, player.Character)
end
player.CharacterAdded:Connect(watchDeaths)

-- приветствие
task.delay(2, function()
	showBanner("🔥 ПОЛ — ЭТО ЛАВА! 🔥", Color3.fromRGB(255, 140, 50))
end)
