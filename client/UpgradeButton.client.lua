-- ===================== COTE CLIENT : menu CHARIOTS =====================
-- Le bouton "🛒 AMELIORER" ouvre/ferme le menu. Dans le menu :
--   ◀ ▶    = feuilleter les 10 chariots (apercu 3D + stats)
--   grand bouton = ACHETER (prochain) ou PRENDRE/JOUER (chariot deja a toi), selon l'attribut "Action"
--   ✖      = ferme.
-- La camera de l'APERCU 3D est geree ICI (cote client) : c'est plus fiable que cote serveur.
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local askUpgrade = ReplicatedStorage:WaitForChild("AskUpgrade")
local askBrowse  = ReplicatedStorage:WaitForChild("AskBrowse")

local gui = plr:WaitForChild("PlayerGui"):WaitForChild("ChariotHUD")
local openBtn  = gui:WaitForChild("UpgradeBtn")
local menu     = gui:WaitForChild("CartMenu")
local buyBtn   = menu:WaitForChild("MenuBuy")
local closeBtn = menu:WaitForChild("MenuClose")
local prevBtn  = menu:WaitForChild("MenuPrev")
local nextBtn  = menu:WaitForChild("MenuNext")

local function setOpen(open)
	menu.Visible = open
	if open then
		askBrowse:FireServer(0)   -- a l'ouverture : revenir au prochain chariot + rafraichir la carte
	end
end

openBtn.Activated:Connect(function() setOpen(not menu.Visible) end)
closeBtn.Activated:Connect(function() setOpen(false) end)
buyBtn.Activated:Connect(function()
	-- le serveur a dit quoi faire via l'attribut "Action" : acheter le prochain, ou juste fermer
	-- (chariot deja a toi -> "PRENDRE / JOUER"). "none" = rien (verrouille / pas assez de pieces).
	local action = buyBtn:GetAttribute("Action")
	if action == "buy" then
		askUpgrade:FireServer()
	elseif action == "close" then
		setOpen(false)
	end
end)
prevBtn.Activated:Connect(function() askBrowse:FireServer(-1) end)
nextBtn.Activated:Connect(function() askBrowse:FireServer(1) end)

-- ===================== APERCU 3D : camera de la vignette (cote client = fiable) =====================
-- Le serveur fabrique le ViewportFrame + un clone du chariot (restyle selon le niveau). Ici, on
-- reprend la camera du viewport, on la CADRE pour que tout le chariot tienne dedans, et on le
-- fait tourner lentement (effet "showroom") pour bien le voir en 3D.
local card  = menu:WaitForChild("Card")
local vp    = card:WaitForChild("Preview")
local vcam  = vp:WaitForChild("PreviewCam")
vp.CurrentCamera = vcam   -- on RE-affirme cote client (sinon parfois la camera serveur ne "prend" pas)

local spin = 0
RunService.RenderStepped:Connect(function(dt)
	if not menu.Visible then return end
	local pv = vp:FindFirstChild("PreviewCart")
	if not pv then return end
	spin = spin + dt * 0.5   -- rotation lente "showroom"
	local cfb, size = pv:GetBoundingBox()
	local maxe = math.max(size.X, size.Y, size.Z)
	local dist = maxe * 1.8 + 3
	local dir  = (CFrame.Angles(0, spin, 0) * Vector3.new(0.55, 0.4, -1)).Unit
	vcam.CFrame = CFrame.lookAt(cfb.Position + dir * dist, cfb.Position + Vector3.new(0, size.Y * 0.15, 0))
end)
