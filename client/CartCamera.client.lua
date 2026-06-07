-- ===================== CAMERA DU CHARIOT (cote client) =====================
-- Sur le wagon, la camera reste LIBRE : on tourne / regarde autour exactement COMME A PIED
-- (orbite a la souris / clic droit). On la fait juste suivre le SIEGE (une piece ANCREE =
-- stable, pas le perso qui vibre) -> suivi doux, et la vue ne se retourne pas dans les loopings
-- (la camera normale de Roblox garde toujours le "haut" du monde).
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer

RunService.Heartbeat:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- camera NORMALE de Roblox (libre, comme a pied)
	if cam.CameraType ~= Enum.CameraType.Custom then
		cam.CameraType = Enum.CameraType.Custom
	end

	if hum.Sit and hum.SeatPart then
		-- assis dans le wagon : on suit le SIEGE (ancre, stable) au lieu du perso (qui vibre un peu)
		if cam.CameraSubject ~= hum.SeatPart then cam.CameraSubject = hum.SeatPart end
	else
		-- a pied : camera sur le perso (comportement normal)
		if cam.CameraSubject ~= hum then cam.CameraSubject = hum end
	end
end)
