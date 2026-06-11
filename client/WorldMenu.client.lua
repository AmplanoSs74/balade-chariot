-- ===================== COTE CLIENT : menu MONDES (admin) =====================
-- Bouton "🌍 MONDES" en bas a gauche -> liste des mondes -> clic = teleportation
-- de TOUT le serveur vers ce monde (le serveur verifie aussi que tu es admin).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local ADMINS = { Alexskoow = true }   -- ajoute ici le pseudo de ton pote (et garde le serveur synchro !)
if not ADMINS[plr.Name] then return end

local askWorld = ReplicatedStorage:WaitForChild("AskWorld")

local MONDES = {
	{ nom = "ENFER",    emoji = "🔥", col = Color3.fromRGB(255, 110, 60) },
	{ nom = "GROTTE",   emoji = "🔮", col = Color3.fromRGB(140, 120, 255) },
	{ nom = "VILLE",    emoji = "🏙️", col = Color3.fromRGB(110, 190, 255) },
	{ nom = "MONTAGNE", emoji = "🏔️", col = Color3.fromRGB(180, 215, 255) },
	{ nom = "PARADIS",  emoji = "☁️", col = Color3.fromRGB(255, 225, 130) },
}

local gui = Instance.new("ScreenGui")
gui.Name = "WorldMenu"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

-- bouton d'ouverture, en bas a gauche
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, 130, 0, 40)
openBtn.Position = UDim2.new(0, 12, 1, -52)
openBtn.BackgroundColor3 = Color3.fromRGB(28, 26, 40)
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBlack
openBtn.TextSize = 16
openBtn.Text = "🌍 MONDES"
openBtn.Parent = gui
local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn
local os_ = Instance.new("UIStroke"); os_.Color = Color3.fromRGB(120, 200, 255); os_.Thickness = 1.6; os_.Parent = openBtn

-- panneau de la liste
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 190, 0, #MONDES * 46 + 54)
panel.Position = UDim2.new(0, 12, 1, -52 - 8 - (#MONDES * 46 + 54))
panel.BackgroundColor3 = Color3.fromRGB(22, 20, 32)
panel.Visible = false
panel.Parent = gui
local pc_ = Instance.new("UICorner"); pc_.CornerRadius = UDim.new(0, 12); pc_.Parent = panel
local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(120, 200, 255); ps.Thickness = 1.6; ps.Parent = panel

local titre = Instance.new("TextLabel")
titre.Size = UDim2.new(1, 0, 0, 40)
titre.BackgroundTransparency = 1
titre.Font = Enum.Font.GothamBlack
titre.TextSize = 16
titre.TextColor3 = Color3.new(1, 1, 1)
titre.Text = "🌍 TÉLÉPORTATION"
titre.Parent = panel

for i, m in ipairs(MONDES) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -16, 0, 38)
	b.Position = UDim2.new(0, 8, 0, 40 + (i - 1) * 46)
	b.BackgroundColor3 = m.col
	b.TextColor3 = Color3.fromRGB(20, 18, 28)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 15
	b.Text = m.emoji .. "  MONDE " .. i .. " · " .. m.nom
	b.Parent = panel
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = b
	b.Activated:Connect(function()
		askWorld:FireServer(i)
		panel.Visible = false
	end)
end

openBtn.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
