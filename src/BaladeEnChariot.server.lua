--[[ ============================================================
     BALADE EN CHARIOT  -  version 3
     ------------------------------------------------------------
     OU LE METTRE :
       Explorer -> clic droit sur "ServerScriptService"
       -> Insert Object -> Script. Efface tout et colle ce fichier.
       Puis bouton "Play".

     COMMANDES (assis dans le chariot) :
       Z / W = avancer / accelerer
       S     = freiner puis MARCHE ARRIERE
       Le chariot s'incline dans les virages (de plus en plus vite = plus
       penche). Trop vite dans un virage serre = il se detache et tombe.
       Loopings, bosses et tunnels ne font jamais derailler.
   ============================================================ ]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Lighting   = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Terrain    = Workspace.Terrain

-- ===================== REGLAGES =====================
local SEGMENT_LENGTH = 8
local START_HEIGHT   = 10   -- voie basse : on roule au milieu du decor
local TRACK_WIDTH    = 6
local GAUGE          = 2.2
local RAIL_Y         = 0.5
local RAIL_W         = 0.35
local RAIL_H         = 0.5
local RAIL_COLOR     = Color3.fromRGB(196, 40, 28)   -- rails : rouge "Lego" (change la couleur ici)
local RAIL_MAT       = Enum.Material.SmoothPlastic    -- plastique lisse brillant, facon Lego
local RAIL_STEP      = 3                               -- finesse des rails (plus petit = plus lisse, plus de pieces)
local RIDE_HEIGHT    = 2.4
-- VOIES DE DEPART (multijoueur) : chaque joueur apparait sur SA voie laterale, qui rejoint la voie
-- centrale en douceur sur les premiers studs. Offset 0 = voie principale (1er joueur).
local START_LANE_OFFSETS = { 0, -12, 12 }
local MERGE_DIST = 70
local function laneFade(d, L) local sw = MERGE_DIST * 0.5; if d < sw then return 1 end; local x = math.clamp((MERGE_DIST - d) / (MERGE_DIST - sw), 0, 1); return x * x * (3 - 2 * x) end  -- voies PARALLELES puis aiguillage COURT a la fin (comme de vrais rails, pas un eventail)

local MAX_SPEED   = 85   -- (ancienne base, remplacee par les CHARIOTS ci-dessous)
-- 10 CHARIOTS a acheter avec des pieces. Chacun : va plus vite (max ~ km/h), tient mieux
-- les virages ET decolle/crashe moins (plus stable). Le joueur FARM pour passer au suivant.
-- chaque chariot : max(km/h), grip, prix, + un LOOK (body/trim/matiere) et un SON (pitch
-- de plus en plus aigu/puissant ; sound = ID custom optionnel, ex: le son du Legendaire).
local CARTS = {
	-- DEBUT faible + cheap (dopamine : on upgrade vite), puis de + en + cher (le dernier = gros
	-- farm, vise 15-20h). Prix a AFFINER via les logs (je mesure le revenu reel et j'ajuste).
	{ name="Chariot Bois",  max=42,  grip=0.00, brake=14,  price=0,        body=Color3.fromRGB(124,78,46),   trim=Color3.fromRGB(92,60,34),   mat=Enum.Material.WoodPlanks, pitch=0.82 },
	{ name="Chariot Fer",   max=58,  grip=0.06, brake=24,  price=150,      body=Color3.fromRGB(108,82,58),   trim=Color3.fromRGB(120,122,130),mat=Enum.Material.WoodPlanks, pitch=0.90 },
	{ name="Chariot Acier", max=76,  grip=0.13, brake=36,  price=600,      body=Color3.fromRGB(120,126,134), trim=Color3.fromRGB(185,190,196),mat=Enum.Material.Metal,      pitch=0.98 },
	{ name="Bolide",        max=95,  grip=0.22, brake=48,  price=2500,     body=Color3.fromRGB(190,40,40),   trim=Color3.fromRGB(235,235,240),mat=Enum.Material.Metal,      pitch=1.05 },
	{ name="Turbo",         max=115, grip=0.32, brake=62,  price=10000,    body=Color3.fromRGB(255,120,30),  trim=Color3.fromRGB(40,42,48),   mat=Enum.Material.Metal,      pitch=1.12 },
	{ name="Fusee",         max=135, grip=0.43, brake=76,  price=45000,    body=Color3.fromRGB(235,235,245), trim=Color3.fromRGB(255,90,30),  mat=Enum.Material.Metal,      pitch=1.18 },
	{ name="Plasma",        max=155, grip=0.55, brake=90,  price=200000,   body=Color3.fromRGB(70,200,255),  trim=Color3.fromRGB(255,255,255),mat=Enum.Material.Neon,       pitch=1.24 },
	{ name="Quantum",       max=175, grip=0.68, brake=104, price=1000000,  body=Color3.fromRGB(170,90,255),  trim=Color3.fromRGB(235,205,255),mat=Enum.Material.Neon,       pitch=1.30 },
	{ name="Cosmic",        max=195, grip=0.82, brake=118, price=8000000,  body=Color3.fromRGB(40,255,180),  trim=Color3.fromRGB(205,255,238),mat=Enum.Material.Neon,       pitch=1.36 },
	{ name="Legendaire",    max=215, grip=0.98, brake=132, price=60000000, body=Color3.fromRGB(255,215,40),  trim=Color3.fromRGB(255,255,255),mat=Enum.Material.Neon,       pitch=1.45, legend=true },
}
local KMH = 1.0   -- facteur studs/s -> km/h (1 stud ~ 1 km/h)

-- Bouton "AMELIORATION CHARIOT" a l'ecran : le clic vient du CLIENT (script client/),
-- qui envoie ce RemoteEvent au serveur. upgradeFn (defini par buildEconomy) fait l'achat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local askUpgrade = Instance.new("RemoteEvent")
askUpgrade.Name = "AskUpgrade"
askUpgrade.Parent = ReplicatedStorage
-- le menu CHARIOTS feuillete les chariots (fleches ◀ ▶) : le client envoie -1/+1 (ou 0 = revenir
-- au prochain chariot a l'ouverture du menu) ; le serveur change la carte affichee.
local askBrowse = Instance.new("RemoteEvent")
askBrowse.Name = "AskBrowse"
askBrowse.Parent = ReplicatedStorage
local upgradeFn   -- (re)defini par buildEconomy
local REVERSE_MAX = 28
local ACCEL       = 30
local BRAKE       = 60
local FRICTION    = 16
local SAFE_GENTLE = 58
local SAFE_SHARP  = 36
local DERAIL_MARGIN = 1.12
local LOOP_GRAVITY   = 30   -- looping : force qui te ralentit en montant (la descente AVANT donne deja l'elan)
local WORLD_GRAVITY  = 80   -- GRAVITE forte facon cart-ride : DESCENTES = ca FONCE (le feeling). (Roblox de base = 196.2)
local BASE_CLIMB     = 0.6  -- capacite de MONTEE de base (TOUS chariots) : reduit la gravite en MONTEE pour que le
                            -- chariot grimpe sans caler (la DESCENTE garde la gravite pleine). Meilleur chariot = grimpe encore mieux.
local LOOP_MIN_SPEED = 9    -- looping : sous cette vitesse dans le haut = on tombe
-- DECOLLAGE : au sommet d'une bosse la voie pique vers le bas ; trop vite = le chariot
-- ne suit plus la courbe et s'envole. Plus LAUNCH_FORCE est BAS, plus ca decolle facilement.
local LAUNCH_MIN_SPEED = 42   -- en dessous de cette vitesse, jamais de decollage
local LAUNCH_FORCE     = 55   -- seuil d'envol au sommet d'une bosse (plus BAS = decolle + souvent)
-- MODE DEBUG : ecrit ce qui se passe dans la Sortie (decollages, atterrissages, vitesse).
-- Copie-colle la Sortie a Claude pour qu'il "voie" ce que fait la physique. (false = silence)
local DEBUG = true
local function dbg(msg) if DEBUG then print("[DBG] " .. msg) end end
local LEAN_MAX    = math.rad(26)
local LEAN_SMOOTH = 8   -- douceur de l'inclinaison du wagon (plus petit = plus mou/progressif)
local GRIP_TILT    = math.rad(45)  -- bascule MAX vers l'exterieur quand on perd l'adherence
local GRIP_RATE    = 3     -- vitesse de perte d'adherence en virage trop rapide
local GRIP_RECOVER = 1.6   -- vitesse de recuperation quand on ralentit (rattrapage possible)
-- AMELIORATIONS pendant la course : UNE seule au Monde 1, +1 de plus a chaque monde
-- suivant (Monde 2 = 2 paliers, Monde 3 = 3...). Le nombre de paliers = numero du monde.
-- A chaque palier : un peu plus de vitesse max + un peu plus d'adherence (deraille moins).
local BOOST_SPEED_STEP = 6      -- +vitesse max par palier
local BOOST_GRIP_STEP  = 0.08   -- +adherence par palier
-- ADHERENCE EN PENTE : un meilleur chariot (grip eleve) GRIMPE mieux -> la gravite qui freine
-- en montee est reduite par son "adherence". 0 = aucune aide ; plus haut = grimpe bien mieux.
local CLIMB_ASSIST = 0.6
-- PIECES qui GRANDISSENT avec la progression : chaque niveau de chariot et chaque monde
-- franchi augmentent les pieces gagnees par segment (0 = comme avant, gain fixe).
local CART_COIN_STEP  = 1   -- +pieces par niveau de chariot au-dessus du Bois
local WORLD_COIN_STEP = 1   -- +pieces par monde au-dela du 1er
-- XP : systeme de progression independant des pieces (on monte en niveau en jouant).
-- XP_PER_SEG     = XP gagne par segment franchi. XP_LEVEL_BASE = XP requis pour le niveau 1 ;
-- le niveau N requiert N * XP_LEVEL_BASE XP (ex: niv.1 = 400, niv.2 = 800, niv.3 = 1200...).
local XP_PER_SEG    = 3     -- XP par segment (augmente vite pour que ca soit gratifiant)
local XP_STAGE_BONUS = 60   -- XP bonus en finissant une etape
local XP_WORLD_BONUS = 250  -- XP bonus en finissant un monde entier
local XP_LEVEL_BASE  = 400  -- XP requis pour le niveau 1 (chaque niveau suivant = +400)
local XP_LEVEL_COIN_BONUS = 0.5  -- UTILITE DU NIVEAU : +0.5x de pieces par niveau gagne (monter sert a gagner +)
local DEATH_Y = 4   -- sous cette hauteur Y = tombe dans l'herbe/le vide -> respawn (la voie est toujours > 8)
local CP_SPACING = 600   -- on valide un CHECKPOINT (point de respawn) tous les X studs parcourus
local SEED        = 20
local SOUND_DING  = "rbxasset://sounds/electronicpingshort.wav"  -- son du "+1" (remplacable par un son de la Toolbox)
-- SONS : pour l'instant DESACTIVES (le placeholder etait le "ding" strident deteste).
-- Quand tu importes tes vrais sons dans Studio, donne-moi les IDs : je mets le SoundId
-- (rbxassetid://<ID>) ET je passe le _READY a true.
local COIN_SOUND       = "rbxasset://sounds/electronicpingshort.wav"  -- a remplacer par TON son de pieces
local COIN_STEP        = 500     -- son de pieces a chaque palier de 500
local COIN_SOUND_READY = false   -- passe a true quand le vrai son de pieces est mis
local ROLL_SOUND       = "rbxassetid://75555857201184"  -- "wagon clatter" (roulement, en boucle)
local ROLL_SOUND_READY = true    -- son de rail ACTIF
local ZONE_BASE   = {1, 10, 100, 1000}  -- points de base par zone (x multiplicateur de tour)

-- LES 4 MONDES = une ASCENSION : Enfer (en bas) -> Ville -> Montagne -> Paradis (tout en haut).
local ZONES = {
	{ name = "Enfer",    terrain = Enum.Material.CrackedLava, bed = Color3.fromRGB(48,20,18) },   -- 1
	{ name = "Ville",    terrain = Enum.Material.Pavement,    bed = Color3.fromRGB(78,82,92) },    -- 2
	{ name = "Montagne", terrain = Enum.Material.Rock,        bed = Color3.fromRGB(112,120,132) }, -- 3
	{ name = "Paradis",  terrain = Enum.Material.Grass,       bed = Color3.fromRGB(120,205,120) }, -- 4
}

-- ORDRE DES MONDES : ENFER -> VILLE -> MONTAGNE -> PARADIS (l'ascension), puis on reboucle + dur.
-- zone = index dans ZONES ; seed = graine du trace ; accent = couleur d'ambiance du monde.
local WORLDS = {
	{ zone = 1, name = "ENFER",    seed = 101, accent = Color3.fromRGB(255,  90,  45) },
	{ zone = 2, name = "VILLE",    seed = 202, accent = Color3.fromRGB(120, 200, 255) },
	{ zone = 3, name = "MONTAGNE", seed = 303, accent = Color3.fromRGB(175, 210, 255) },
	{ zone = 4, name = "PARADIS",  seed = 404, accent = Color3.fromRGB(255, 235, 150) },
}
local NSTAGES = 3   -- le circuit est decoupe en 3 grandes etapes (zones safe)
local currentWorldIndex = 1   -- numero du monde courant (peut depasser #WORLDS)
local function worldCfg(w) return WORLDS[((w - 1) % #WORLDS) + 1] end  -- les themes rebouclent

-- theme courant (suit le monde courant). Tout le decor/sol/ballast suit CURRENT_ZONE.
local CURRENT_ZONE = 1

local rng = Random.new(SEED)   -- re-graine par monde dans genTrack()

-- ===================== GENERATION DU TRACE (reperes 3D) =====================
-- Ces variables sont (RE)REMPLIES par genTrack() a chaque monde -> trace rejouable.
local nodes, bank, segMeta, cursor
local obstacleDists, obstacleBlades   -- OBSTACLES : grandes lames qui balaient la voie (timing)
local obstaclePhase = 0
local NSEG, renderNodes, cumDist, TOTAL_DIST, STAGE_LEN, checkpoints

local function addSegment(yaw, pitch, kind, safe, derailable, bk, leanDir)
	cursor = cursor * CFrame.Angles(pitch, yaw, 0) * CFrame.new(0, 0, -SEGMENT_LENGTH)
	table.insert(nodes, cursor)
	table.insert(bank, bk or 0)
	table.insert(segMeta, {
		kind = kind,
		safe = safe or math.huge,
		derailable = derailable or false,
		leanDir = leanDir or 0,
	})
end

local function straight(n)
	for _ = 1, n do addSegment(0, 0, "straight", math.huge, false, 0, 0) end
end

local function tunnel(n)
	for _ = 1, n do addSegment(0, 0, "tunnel", math.huge, false, 0, 0) end
end

-- virage DUR a l'interieur d'un tunnel : kind="tunnel" (donc les murs/plafond se
-- construisent autour) MAIS derailable + incline, donc dur a passer dans le noir.
local function tunnelTurn(dir, n)
	local yawPer = math.rad(10) * dir
	local bkMax  = math.rad(20) * dir
	for k = 1, n do
		local ramp = math.sin(math.pi * k / n)
		addSegment(yawPer, 0, "tunnel", SAFE_SHARP, true, bkMax * ramp, dir)
	end
end

local function sweep(dir, n) -- long virage doux et releve
	local yawPer = math.rad(5) * dir
	local bkMax  = math.rad(14) * dir
	for k = 1, n do
		local ramp = math.sin(math.pi * k / n)
		addSegment(yawPer, 0, "turn", SAFE_GENTLE, true, bkMax * ramp, dir)
	end
end

local function hardTurn(dir) -- virage serre (peut faire derailler)
	local n = 7
	local yawPer = math.rad(14) * dir
	local bkMax  = math.rad(24) * dir
	for k = 1, n do
		local ramp = math.sin(math.pi * k / n)
		addSegment(yawPer, 0, "turn", SAFE_SHARP, true, bkMax * ramp, dir)
	end
end

local function hill(updown) -- grosse bosse : monte puis descend (relief plus marque)
	local n = 5
	local p = math.rad(7) * updown
	for _ = 1, n do addSegment(0,  p, "hill", math.huge, false, 0, 0) end
	for _ = 1, n do addSegment(0, -p, "hill", math.huge, false, 0, 0) end
end

local function dip() -- creux : descend puis remonte
	hill(-1)
end

-- GRANDE colline : grande montee suivie d'une grande descente (relief spectaculaire).
-- Reglages : nUp/p plus grands = plus haut/plus raide. (passe encore avec de l'elan)
local function bigHill()
	local n = 7
	local p = math.rad(8)
	for _ = 1, n do addSegment(0,  p, "hill", math.huge, false, 0, 0) end   -- grande montee
	for _ = 1, n do addSegment(0, -p, "hill", math.huge, false, 0, 0) end   -- grande descente
end

local function loopDeLoop()
	-- vrai looping (tete en bas) mais legerement vrille sur le cote, facon parc
	-- d'attraction : un petit lacet (yaw) a chaque segment transforme le cercle
	-- plat en spirale -> la sortie tombe A COTE de l'entree, donc la voie ne se
	-- retraverse jamais (fini le passage a travers les rails).
	local N = 20
	local pitchPer = (2 * math.pi) / N
	local yawPer   = math.rad(4)
	for _ = 1, N do addSegment(yawPer, pitchPer, "loop", math.huge, false, 0, 0) end
end

-- looping AVEC ELAN : une descente avant (le chariot prend de la vitesse), puis le looping,
-- puis on remonte. Comme ca meme le petit chariot a l'elan pour passer la boucle.
local function loopRun()
	straight(2)
	for _ = 1, 5 do addSegment(0, math.rad(-11), "hill", math.huge, false, 0, 0) end  -- DESCENTE = elan
	loopDeLoop()
	for _ = 1, 4 do addSegment(0, math.rad(9),  "hill", math.huge, false, 0, 0) end   -- on remonte apres
	straight(2)
end

-- RAILS FANTOMES : une ligne droite ou les rails APPARAISSENT / DISPARAISSENT en rythme.
-- Si tu y es quand ils ont disparu -> tu tombes. Il faut TIMER ton passage (foncer quand ils sont la).
local function phantomRun(n)
	straight(2)
	for _ = 1, n do addSegment(0, 0, "phantom", math.huge, false, 0, 0) end
	straight(2)
end

-- ----- LE PARCOURS (genere) -----
-- genLayout : la SEQUENCE du circuit. DEBUT = tunnel avec virages durs (le S serre),
-- puis une suite pseudo-aleatoire (selon la graine du monde) de virages/relief/loopings,
-- et une longue ligne d'arrivee plate (pour la plateforme de fin). Chaque monde a donc
-- un circuit DIFFERENT et plus long (nFeatures monte avec le numero de monde).
local function genLayout(world)
	-- 1) DEBUT : long DROIT plat (plus de tunnel) -> les voies de depart convergent proprement ici
	straight(16)
	-- 2) SEQUENCE SIGNATURE : grande montee + grande descente -> looping -> virages
	bigHill()
	straight(4)
	loopRun()
	straight(4)
	sweep(1, 12)
	hardTurn(-1)
	sweep(-1, 12)
	straight(4)
	phantomRun(6)   -- NOUVEAU : ligne a RAILS FANTOMES (timing)
	straight(4)
	-- 3) SUITE : LONGUE et TRES vallonnee (grandes montees/descentes + virages + loopings).
	--    nFeatures bien augmente -> parcours beaucoup plus long. Monte avec le monde.
	local nFeatures = 44 + world * 4
	for _ = 1, nFeatures do
		local p = rng:NextNumber()
		local dir = (rng:NextNumber() < 0.5) and 1 or -1
		if p < 0.20 then bigHill()                          -- grande montee/descente
		elseif p < 0.34 then hill(1)                        -- bosse
		elseif p < 0.44 then dip()                          -- creux
		elseif p < 0.64 then sweep(dir, rng:NextInteger(8, 14))   -- long virage
		elseif p < 0.80 then hardTurn(dir)                  -- virage serre
		elseif p < 0.88 then loopRun()                      -- looping AVEC elan (descente avant)
		elseif p < 0.95 then phantomRun(rng:NextInteger(4, 7))   -- rails fantomes (timing)
		else straight(rng:NextInteger(5, 9)) end
		straight(rng:NextInteger(2, 5))   -- petit droit entre les features (ca respire)
	end
	straight(10)   -- ligne d'arrivee plate (plateforme de fin posee dessus)
end

-- genTrack : (re)genere TOUT le trace du monde donne -> remplit nodes/renderNodes/...
local function genTrack(world)
	currentWorldIndex = world
	CURRENT_ZONE = worldCfg(world).zone
	rng = Random.new(worldCfg(world).seed)
	nodes = { CFrame.new(0, START_HEIGHT, 0) }
	bank = { 0 }
	segMeta = {}
	cursor = nodes[1]
	genLayout(world)
	-- ANTI sous-terrain : le sol est a y=0. Si un creux/descente passe sous ~8, on
	-- REMONTE tout le trace d'un bloc pour que le point le plus bas reste au-dessus du sol.
	local minY = math.huge
	for _, n in ipairs(nodes) do if n.Position.Y < minY then minY = n.Position.Y end end
	if minY < 8 then
		local lift = 8 - minY
		for i, n in ipairs(nodes) do nodes[i] = n + Vector3.new(0, lift, 0) end
	end
	NSEG = #nodes - 1
	renderNodes = {}
	for i = 1, #nodes do renderNodes[i] = nodes[i] * CFrame.Angles(0, 0, bank[i]) end
	cumDist = { 0 }
	for i = 1, NSEG do cumDist[i + 1] = cumDist[i] + (nodes[i + 1].Position - nodes[i].Position).Magnitude end
	TOTAL_DIST = cumDist[#nodes]
	STAGE_LEN = TOTAL_DIST / NSTAGES
end

genTrack(1)   -- MONDE 1 (Prairie) : trace de depart

local function zoneForSegment(seg)
	-- mono-theme : tout le circuit appartient au monde courant
	return CURRENT_ZONE
end

-- courbe douce (Catmull-Rom) passant par 4 reperes : la trajectoire devient
-- arrondie au lieu de segments droits bout a bout -> virages fluides (fini le
-- clac-clac / l'impression de teleportation).
local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * (
		(2 * p1)
		+ (-p0 + p2) * t
		+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
		+ (-p0 + 3 * p1 - 3 * p2 + p3) * t3
	)
end

local function renderAtDistance(d)
	d = math.clamp(d, 0, TOTAL_DIST)
	local seg = 1
	while seg < NSEG and cumDist[seg+1] < d do
		seg = seg + 1
	end
	local segLen = cumDist[seg+1] - cumDist[seg]
	local t = segLen > 0 and math.clamp((d - cumDist[seg]) / segLen, 0, 1) or 0
	-- orientation : interpolation lisse des reperes (gere aussi les loopings)
	local rot = renderNodes[seg]:Lerp(renderNodes[seg+1], t)
	-- position : courbe douce a travers les reperes voisins
	local p0 = renderNodes[math.max(seg - 1, 1)].Position
	local p1 = renderNodes[seg].Position
	local p2 = renderNodes[seg + 1].Position
	local p3 = renderNodes[math.min(seg + 2, #renderNodes)].Position
	local pos = catmullRom(p0, p1, p2, p3, t)
	local cf = CFrame.new(pos) * rot.Rotation
	return cf * CFrame.new(0, RIDE_HEIGHT, 0), seg
end

-- ===================== CONSTRUCTION DE LA VOIE =====================
local trackFolder = Instance.new("Folder")
trackFolder.Name = "Voie"
trackFolder.Parent = Workspace

local function makePart(size, cframe, color, mat, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or trackFolder
	return p
end

-- ===================== MESHES PAR CODE (vrais modeles 3D, EditableMesh) =====================
-- On genere de VRAIS modeles 3D PAR CODE (pas d'asset externe qui peut disparaitre/etre modere) :
-- un cone LISSE pour le VOLCAN, une LAME double-tranchant pour la HACHE. Tout est protege par
-- pcall : si l'API mesh n'est pas dispo, on renvoie nil et l'appelant retombe sur un plan B en blocs.
local AssetService = game:GetService("AssetService")

-- buildMesh : fabrique un MeshPart depuis des sommets (Vector3) + triangles ({a,b,c} 1-based).
-- Renvoie le MeshPart (Anchored, sans collision, centre sur l'origine) ou nil si echec.
local function buildMesh(verts, tris, color, material)
	local ok, mp = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local ids = table.create(#verts)
		for i = 1, #verts do ids[i] = em:AddVertex(verts[i]) end
		for _, t in ipairs(tris) do
			em:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
			em:AddTriangle(ids[t[1]], ids[t[3]], ids[t[2]])   -- double-face : visible des 2 cotes (sens des faces indifferent)
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(em))
	end)
	if not ok or not mp then
		warn("[Balade] mesh non genere (plan B blocs) :", mp)
		return nil
	end
	mp.Anchored = true
	mp.CanCollide = false
	mp.Color = color
	mp.Material = material
	-- on FORCE la taille reelle (securite : si CreateMeshPartAsync ne met pas la bonne echelle, le mesh
	-- pourrait sortir minuscule donc invisible). On calcule la boite englobante des sommets.
	local mn, mx = verts[1], verts[1]
	for _, v in ipairs(verts) do
		mn = Vector3.new(math.min(mn.X, v.X), math.min(mn.Y, v.Y), math.min(mn.Z, v.Z))
		mx = Vector3.new(math.max(mx.X, v.X), math.max(mx.Y, v.Y), math.max(mx.Z, v.Z))
	end
	pcall(function() mp.Size = mx - mn end)
	return mp
end

-- buildConeMesh : tronc de cone LISSE (base R, sommet rTop, hauteur H, segs facettes) + petit
-- cratere creux au sommet. Centre sur l'origine (base a -H/2, sommet a +H/2).
local function buildConeMesh(R, rTop, H, segs, color, material, craterDip)
	craterDip = craterDip or 18
	local verts, tris = {}, {}
	local y0 = -H / 2
	for i = 0, segs - 1 do
		local a = (i / segs) * math.pi * 2
		verts[#verts + 1] = Vector3.new(math.cos(a) * R, y0, math.sin(a) * R)          -- anneau de base
	end
	for i = 0, segs - 1 do
		local a = (i / segs) * math.pi * 2
		verts[#verts + 1] = Vector3.new(math.cos(a) * rTop, y0 + H, math.sin(a) * rTop) -- anneau du sommet
	end
	local craterC = #verts + 1
	verts[craterC] = Vector3.new(0, y0 + H - craterDip, 0)                              -- fond du cratere
	for i = 0, segs - 1 do
		local bi, bi1 = i + 1, (i + 1) % segs + 1
		local ti, ti1 = segs + i + 1, segs + (i + 1) % segs + 1
		tris[#tris + 1] = { bi, ti, ti1 }      -- paroi exterieure
		tris[#tris + 1] = { bi, ti1, bi1 }
		tris[#tris + 1] = { craterC, ti1, ti } -- cratere (face vers le haut)
	end
	return buildMesh(verts, tris, color, material)
end

-- buildExtrudeMesh : extrude un contour 2D (points {x,y} en sens anti-horaire) sur une epaisseur
-- 'thick' en Z. Sert a la LAME de hache (silhouette propre). Centre sur l'origine.
local function buildExtrudeMesh(pts, thick, color, material)
	local verts, tris = {}, {}
	local n = #pts
	local hz = thick / 2
	for _, p in ipairs(pts) do verts[#verts + 1] = Vector3.new(p[1], p[2], hz) end      -- face avant (+Z)
	for _, p in ipairs(pts) do verts[#verts + 1] = Vector3.new(p[1], p[2], -hz) end     -- face arriere (-Z)
	local cF = #verts + 1; verts[cF] = Vector3.new(0, 0, hz)
	local cB = #verts + 1; verts[cB] = Vector3.new(0, 0, -hz)
	for i = 0, n - 1 do
		local a = i + 1
		local b = (i + 1) % n + 1
		tris[#tris + 1] = { cF, a, b }            -- face avant
		tris[#tris + 1] = { cB, b + n, a + n }    -- face arriere
		tris[#tris + 1] = { a, a + n, b + n }     -- paroi laterale
		tris[#tris + 1] = { a, b + n, b }
	end
	return buildMesh(verts, tris, color, material)
end

-- Silhouette de la LAME de hache (contour 2D anti-horaire) ; extrudee a NEUF a chaque obstacle.
-- (On ne clone PAS les meshes : un clone d'EditableMesh peut etre vide -> on regenere a chaque fois.)
local AXE_BLADE_PTS = {
	{ 8, 0 }, { 7.6, 3 }, { 2.6, 3.4 }, { 1.2, 5.6 }, { -1.2, 5.6 }, { -2.6, 3.4 }, { -7.6, 3 },
	{ -8, 0 }, { -7.6, -3 }, { -2.6, -3.4 }, { -1.2, -5.6 }, { 1.2, -5.6 }, { 2.6, -3.4 }, { 7.6, -3 },
}

-- buildTrack : (re)construit ballast/traverses/rails/tunnel/checkpoints + plateforme
-- d'arrivee. Rejouable a chaque monde (tout va dans trackFolder, vide avant chaque build).
-- buildStartLanes : voies de depart laterales (multijoueur) qui CONVERGENT vers la voie centrale,
-- pour que chaque joueur apparaisse sur sa voie sans se superposer aux autres.
local function buildStartLanes()
	local z0 = ZONES[zoneForSegment(1)]
	local step = RAIL_STEP * 2
	for _, L in ipairs(START_LANE_OFFSETS) do
		if L ~= 0 then
			local d = 0
			while d < MERGE_DIST - 1e-3 do
				local d2 = math.min(d + step, MERGE_DIST)
				local f1 = (renderAtDistance(d)) * CFrame.new(0, -RIDE_HEIGHT, 0)
				local f2 = (renderAtDistance(d2)) * CFrame.new(0, -RIDE_HEIGHT, 0)
				local o1, o2 = L * laneFade(d, L), L * laneFade(d2, L)
				local ba = (f1 * CFrame.new(o1, -0.35, 0)).Position
				local bb = (f2 * CFrame.new(o2, -0.35, 0)).Position
				local bl = (bb - ba).Magnitude
				if bl > 1e-3 then makePart(Vector3.new(TRACK_WIDTH, 0.6, bl + 0.4), CFrame.lookAt((ba + bb) / 2, bb), z0.bed, Enum.Material.Slate) end
				for _, side in ipairs({ GAUGE, -GAUGE }) do
					local a = (f1 * CFrame.new(o1 + side, RAIL_Y, 0)).Position
					local b = (f2 * CFrame.new(o2 + side, RAIL_Y, 0)).Position
					local rl = (b - a).Magnitude
					if rl > 1e-3 then makePart(Vector3.new(RAIL_W, RAIL_H, rl + 0.1), CFrame.lookAt((a + b) / 2, b), RAIL_COLOR, RAIL_MAT) end
				end
				-- TRAVERSE en bois (comme la voie principale) -> les voies ont l'air de vraies rails
				local sc = (f1 * CFrame.new(o1, 0.05, 0)).Position
				local sn = (f2 * CFrame.new(o2, 0.05, 0)).Position
				makePart(Vector3.new(TRACK_WIDTH - 0.4, 0.4, 1.1), CFrame.lookAt(sc, sn), Color3.fromRGB(96, 60, 33), Enum.Material.Wood)
				d = d2
			end
		end
	end
end

local function buildTrack()
	buildStartLanes()
for i = 1, NSEG do
	local posA = renderNodes[i].Position
	local posB = renderNodes[i+1].Position
	local up   = renderNodes[i].UpVector
	local midPos = (posA + posB) / 2
	local len = (posB - posA).Magnitude
	-- la direction de marche est toujours perpendiculaire a "up" -> lookAt sur
	-- toute orientation (y compris loopings verticaux), sans cas degenere
	local segFrame = CFrame.lookAt(midPos, posB, up)
	local z = ZONES[zoneForSegment(i)]
	local L = len + 0.2

	-- ballast (+ traverses) ; on TAG les sections "phantom" pour les faire disparaitre en rythme
	local isPhantom = segMeta[i].kind == "phantom"
	local ballast = makePart(Vector3.new(TRACK_WIDTH, 0.6, L), segFrame * CFrame.new(0, -0.35, 0), z.bed, Enum.Material.Slate)
	if isPhantom then ballast:SetAttribute("Phantom", true); ballast.CanCollide = false end
	-- traverses
	for _, zoff in ipairs({ -len/4, len/4 }) do
		local tr = makePart(Vector3.new(TRACK_WIDTH - 0.4, 0.4, 1.1), segFrame * CFrame.new(0, 0.05, zoff),
			Color3.fromRGB(96,60,33), Enum.Material.Wood)
		if isPhantom then tr:SetAttribute("Phantom", true); tr.CanCollide = false end
	end
	-- (les rails ET le tunnel sont construits a part, en suivant la courbe lisse,
	--  pour eviter les trous dans les virages : voir "RAILS LISSES" / "TUNNEL LISSE".)

	-- pilier (parties horizontales en hauteur)
	if up:Dot(Vector3.yAxis) > 0.65 and midPos.Y > 8 and i % 2 == 0 then
		local h = midPos.Y
		makePart(Vector3.new(1.4, h, 1.4), CFrame.new(midPos.X, h/2, midPos.Z),
			Color3.fromRGB(85,85,92), Enum.Material.Concrete)
	end
end

-- ===================== RAILS LISSES =====================
-- On echantillonne la courbe douce en petits pas (RAIL_STEP) et on relie chaque
-- point au suivant : les rails epousent la trajectoire -> nets dans les virages,
-- sans trous. Couleur/matiere = look Lego (voir RAIL_COLOR / RAIL_MAT).
do
	local function railFrame(d)
		return (renderAtDistance(d)) * CFrame.new(0, -RIDE_HEIGHT, 0)
	end
	for _, side in ipairs({ GAUGE, -GAUGE }) do
		local d = 0
		while d < TOTAL_DIST - 1e-3 do
			local d2 = math.min(d + RAIL_STEP, TOTAL_DIST)
			local a = (railFrame(d)  * CFrame.new(side, RAIL_Y, 0)).Position
			local b = (railFrame(d2) * CFrame.new(side, RAIL_Y, 0)).Position
			local L = (b - a).Magnitude
			if L > 1e-3 then
				local mid = (a + b) / 2
				local up  = railFrame((d + d2) / 2).UpVector
				local railPart = makePart(Vector3.new(RAIL_W, RAIL_H, L + 0.1), CFrame.lookAt(mid, b, up), RAIL_COLOR, RAIL_MAT)
				local _, segAt = renderAtDistance((d + d2) / 2)
				if segMeta[segAt] and segMeta[segAt].kind == "phantom" then
					railPart:SetAttribute("Phantom", true)
					railPart.CanCollide = false
					railPart.Color = Color3.fromRGB(120, 220, 255)   -- rails fantomes = CYAN (pour les reperer)
				end
			end
			d = d2
		end
	end
end

-- ===================== TUNNEL LISSE =====================
-- Murs + plafond construits en suivant la COURBE (comme les rails), avec des pieces
-- qui se chevauchent legerement -> AUCUN trou, meme dans les virages serres.
do
	local wallCol = Color3.fromRGB(52, 50, 58)
	local roofCol = Color3.fromRGB(38, 36, 44)
	local half = TRACK_WIDTH / 2 + 1.5
	local STEP = 4
	local function tf(d) return (renderAtDistance(d)) * CFrame.new(0, -RIDE_HEIGHT, 0) end
	local function inTunnel(d)
		local _, seg = renderAtDistance(d)
		return segMeta[seg] ~= nil and segMeta[seg].kind == "tunnel"
	end
	local d = 0
	local lampAccum = 0
	while d < TOTAL_DIST - 1e-3 do
		local d2 = math.min(d + STEP, TOTAL_DIST)
		local dm = (d + d2) / 2
		if inTunnel(dm) then
			local fa, fb = tf(d), tf(d2)
			local up = tf(dm).UpVector
			-- murs gauche + droite (pieces qui se chevauchent -> pas de trou)
			for _, sgn in ipairs({ -1, 1 }) do
				local a = (fa * CFrame.new(sgn * half, 5, 0)).Position
				local b = (fb * CFrame.new(sgn * half, 5, 0)).Position
				local L = (b - a).Magnitude
				if L > 1e-3 then
					makePart(Vector3.new(1, 12, L + 1.2), CFrame.lookAt((a + b) / 2, b, up), wallCol, Enum.Material.Slate)
				end
			end
			-- plafond
			local ra = (fa * CFrame.new(0, 11, 0)).Position
			local rb = (fb * CFrame.new(0, 11, 0)).Position
			local Lr = (rb - ra).Magnitude
			if Lr > 1e-3 then
				makePart(Vector3.new(TRACK_WIDTH + 5, 1.4, Lr + 1.2), CFrame.lookAt((ra + rb) / 2, rb, up), roofCol, Enum.Material.Slate)
			end
			-- lampe au plafond environ tous les 12 studs
			lampAccum = lampAccum + STEP
			if lampAccum >= 12 then
				lampAccum = 0
				local lp = (tf(dm) * CFrame.new(0, 10, 0)).Position
				local lamp = makePart(Vector3.new(1.4, 0.4, 1.4), CFrame.new(lp), Color3.fromRGB(255, 214, 150), Enum.Material.Neon)
				local pl = Instance.new("PointLight")
				pl.Color = Color3.fromRGB(255, 198, 140); pl.Range = 22; pl.Brightness = 2.6
				pl.Parent = lamp
			end
		else
			lampAccum = 0
		end
		d = d2
	end
end

-- checkpoints : poses sur un segment PLAT et DROIT (jamais dans un looping ni un
-- virage), au plus pres du debut de chaque zone.
local function flatStraightFrom(startSeg)
	for s = startSeg, NSEG do
		if segMeta[s].kind == "straight" and renderNodes[s].UpVector.Y > 0.95 then return s end
	end
	for s = startSeg, 1, -1 do
		if segMeta[s].kind == "straight" and renderNodes[s].UpVector.Y > 0.95 then return s end
	end
	return startSeg
end
-- ZONES SAFE : une a la FIN de chaque etape (1/3, 2/3, fin), posee sur du plat
checkpoints = {}
for s = 1, NSTAGES do
	local bd = math.min(s * STAGE_LEN, TOTAL_DIST - 1)
	local seg0 = 1
	while seg0 < NSEG and cumDist[seg0 + 1] < bd do seg0 = seg0 + 1 end
	local cpSeg = flatStraightFrom(seg0)
	table.insert(checkpoints, {dist = cumDist[cpSeg], stage = s})
	local cf = renderNodes[cpSeg]
	-- MINI-HUB CHECKPOINT : PLATEFORME (station) + sol lumineux + arche + lumiere (point de respawn)
	makePart(Vector3.new(TRACK_WIDTH + 16, 1.2, 18), cf * CFrame.new(0, RAIL_Y - 1, 0), Color3.fromRGB(46, 56, 78), Enum.Material.Metal)
	makePart(Vector3.new(TRACK_WIDTH + 6, 0.4, 8), cf * CFrame.new(0, RAIL_Y + 0.3, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	makePart(Vector3.new(1.4, 11, 1.4), cf * CFrame.new(-(TRACK_WIDTH/2 + 3), 5.5, 0), Color3.fromRGB(120,220,255), Enum.Material.Neon)
	makePart(Vector3.new(1.4, 11, 1.4), cf * CFrame.new( (TRACK_WIDTH/2 + 3), 5.5, 0), Color3.fromRGB(120,220,255), Enum.Material.Neon)
	makePart(Vector3.new(TRACK_WIDTH + 8, 1.4, 1.4), cf * CFrame.new(0, 11, 0), Color3.fromRGB(120,220,255), Enum.Material.Neon)
	local cpMark = makePart(Vector3.new(2.4, 0.7, 2.4), cf * CFrame.new(0, 11, 0), Color3.fromRGB(160,240,255), Enum.Material.Neon)
	local cpL = Instance.new("PointLight"); cpL.Range = 34; cpL.Brightness = 2.6; cpL.Color = Color3.fromRGB(150,220,255); cpL.Parent = cpMark
	-- trophee dore (le "Win" de l'etape) flottant
	local tCol = Color3.fromRGB(255, 205, 40)
	makePart(Vector3.new(2.6, 0.5, 2.6), cf * CFrame.new(0, RIDE_HEIGHT + 2.2, 0), tCol, Enum.Material.Neon)
	makePart(Vector3.new(0.6, 1.4, 0.6), cf * CFrame.new(0, RIDE_HEIGHT + 3.1, 0), tCol, Enum.Material.Neon)
	local cup = makePart(Vector3.new(2.6, 2.4, 2.6), cf * CFrame.new(0, RIDE_HEIGHT + 4.3, 0), tCol, Enum.Material.Neon)
	cup.Shape = Enum.PartType.Ball
end

	-- ---- OBSTACLES : grandes LAMES qui balaient la voie (timing facon "wipeout") ----
	-- Posees sur du plat droit, espacees. Elles tournent (boucle plus bas) ; etre dessous au
	-- mauvais moment = chute. obstacleDists/obstacleBlades sont remplis a CHAQUE monde.
	obstacleDists = {}
	obstacleBlades = {}
	local lastObs = -1e9
	for oseg = 14, NSEG - 5 do
		if segMeta[oseg].kind == "straight" and renderNodes[oseg].UpVector.Y > 0.95 and cumDist[oseg] - lastObs > 650 then
			lastObs = cumDist[oseg]
			local ocf = renderNodes[oseg]
			makePart(Vector3.new(1.2, 11, 1.2), ocf * CFrame.new(-5.5, 5.5, 0), Color3.fromRGB(38, 30, 28), Enum.Material.Metal)
			makePart(Vector3.new(1.2, 11, 1.2), ocf * CFrame.new( 5.5, 5.5, 0), Color3.fromRGB(38, 30, 28), Enum.Material.Metal)
			makePart(Vector3.new(13, 1.2, 1.2), ocf * CFrame.new(0, 11, 0), Color3.fromRGB(38, 30, 28), Enum.Material.Metal)
			local axleCF = ocf * CFrame.new(0, 11, 0)
			-- HACHE GEANTE : manche bois (cylindre) + LAME double-tranchant (vrai mesh 3D) + moyeu acier.
			-- L'ensemble tourne autour de l'axe (voir la boucle de rotation des lames plus bas).
			local aparts = {}
			local hOff = CFrame.new(0, -8, 0) * CFrame.Angles(0, 0, math.rad(90))   -- manche vertical
			local handle = makePart(Vector3.new(15, 1.3, 1.3), axleCF * hOff, Color3.fromRGB(78, 50, 30), Enum.Material.Wood)
			handle.Shape = Enum.PartType.Cylinder; handle.CanCollide = false
			table.insert(aparts, { part = handle, off = hOff })
			-- TETE de hache DOUBLE-TRANCHANT en pieces solides (garanti visible), evasee facon vraie hache.
				local headBase = CFrame.new(0, -14.5, 0)
				local function bladePart(size, loc, color, mat)
					local off = headBase * loc
					local pp = makePart(size, axleCF * off, color, mat)
					pp.CanCollide = false
					table.insert(aparts, { part = pp, off = off })
				end
				bladePart(Vector3.new(2.8, 4.6, 2.4), CFrame.new(0, 0, 0), Color3.fromRGB(58, 60, 70), Enum.Material.Metal)   -- oeil central
				for _, s in ipairs({ -1, 1 }) do
					bladePart(Vector3.new(5.8, 3.0, 0.8), CFrame.new(s * 4.4,  1.5, 0) * CFrame.Angles(0, 0, math.rad( 12 * s)), Color3.fromRGB(150, 154, 166), Enum.Material.Metal)
					bladePart(Vector3.new(5.8, 3.0, 0.8), CFrame.new(s * 4.4, -1.5, 0) * CFrame.Angles(0, 0, math.rad(-12 * s)), Color3.fromRGB(150, 154, 166), Enum.Material.Metal)
					bladePart(Vector3.new(1.0, 7.4, 1.3), CFrame.new(s * 7.5,  0,   0), Color3.fromRGB(216, 222, 234), Enum.Material.Metal)
				end
			table.insert(obstacleDists, cumDist[oseg])
			table.insert(obstacleBlades, { parts = aparts, axle = axleCF })
		end
	end

	-- PLATEFORME D'ARRIVEE (au tout bout du circuit) : grand pad lumineux + portail.
	-- C'est ici qu'on declenche le passage au monde suivant.
	local acc = worldCfg(currentWorldIndex).accent
	local fcf = renderAtDistance(TOTAL_DIST)
	makePart(Vector3.new(TRACK_WIDTH + 16, 1, 18), fcf * CFrame.new(0, -RIDE_HEIGHT + 0.6, -5), acc, Enum.Material.Neon)
	makePart(Vector3.new(2, 18, 2), fcf * CFrame.new(-(TRACK_WIDTH / 2 + 5), 7, -5), acc, Enum.Material.Neon)
	makePart(Vector3.new(2, 18, 2), fcf * CFrame.new( (TRACK_WIDTH / 2 + 5), 7, -5), acc, Enum.Material.Neon)
	makePart(Vector3.new(TRACK_WIDTH + 14, 2.2, 2), fcf * CFrame.new(0, 16, -5), acc, Enum.Material.Neon)
end
buildTrack()

-- ===================== TERRAIN (sol par zone, sans scintillement) =====================
local function buildTerrain()
	Terrain:Clear()
	-- ENFER : on rend la LAVE (CrackedLava) BRILLANTE comme la reference (sol orange ardent)
	Terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(255, 100, 40))
	Terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(108, 106, 113))   -- volcan = ROCHER GRIS (fort contraste avec la lave jaune, comme la ref)
	-- La voie est SURELEVEE. Regle d'or : aucun relief ne doit toucher la voie (sinon
	-- ca traverse / ca clignote). On ne place collines/montagnes/eau que LOIN de tous
	-- les points de la voie (verif de distance) ; le sol reste plat et propre dessous.
	-- Zone INTERDITE autour du hub (sinon une montagne rentre dans le hub) :
	local hubPos = (renderAtDistance(0) * CFrame.new(0, 0, 44)).Position
	local function farFromTrack(x, z, clearance)
		-- jamais de relief qui touche le hub. clearance inclut deja le RAYON du relief,
		-- donc on rejette tout point a moins de (clearance + marge) du centre du hub :
		-- meme une grosse montagne (gros rayon) reste loin et ne deborde plus dedans.
		local hdx, hdz = x - hubPos.X, z - hubPos.Z
		local hubKeep = clearance + 60
		if (hdx * hdx + hdz * hdz) < hubKeep * hubKeep then return false end
		local c2 = clearance * clearance
		for n = 1, #nodes, 2 do
			local p = nodes[n].Position
			local dx, dz = p.X - x, p.Z - z
			if dx * dx + dz * dz < c2 then return false end
		end
		return true
	end

	-- 1) sol plat par zone (top a y=0 ; la voie flotte au-dessus, la deco se pose dessus)
	for i = 1, NSEG, 3 do
		local zi = zoneForSegment(i)
		local p = nodes[i].Position
		Terrain:FillBlock(CFrame.new(p.X, -15, p.Z), Vector3.new(220, 30, 220), ZONES[zi].terrain)
	end

	-- SOL DE LAVE BRILLANTE (ENFER) : une vraie nappe de dalles Neon orange ardent par-dessus le
	-- terrain (la CrackedLava reste trop sombre). On couvre toute la zone ou passe la voie.
	if CURRENT_ZONE == 1 then
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, n in ipairs(nodes) do
			local p = n.Position
			minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
			minZ = math.min(minZ, p.Z); maxZ = math.max(maxZ, p.Z)
		end
		local step = 360
		for x = minX - 160, maxX + 160, step do
			for z = minZ - 160, maxZ + 160, step do
				makePart(Vector3.new(step + 40, 1, step + 40), CFrame.new(x, 0.4, z), Color3.fromRGB(255, 95, 28), Enum.Material.Neon)
			end
		end
	end

	-- 2) reliefs UNIQUEMENT loin de la voie
	for zi = 1, #ZONES do
		local segMid = math.floor((zi - 0.5) / #ZONES * NSEG) + 1
		local base = nodes[math.clamp(segMid, 1, #nodes)].Position
		-- les 4 ancres servent juste a repartir le relief le long du circuit ;
		-- la MATIERE, elle, est toujours celle du monde courant (mono-theme).
		local mat = ZONES[CURRENT_ZONE].terrain

		-- collines en boules : PAS en Enfer (la ref a un sol de lave PLAT, sans boules grises)
		for _ = 1, (CURRENT_ZONE == 1 and 0 or 16) do
			local ang = rng:NextNumber(0, 6.28)
			local dist = 100 + rng:NextNumber(0, 110)
			local cx = base.X + math.cos(ang) * dist
			local cz = base.Z + math.sin(ang) * dist
			local rMain = 16 + rng:NextNumber(0, 16)
			if farFromTrack(cx, cz, rMain + 60) then
				for _ = 1, 4 do
					local ox = rng:NextNumber(-rMain * 0.7, rMain * 0.7)
					local oz = rng:NextNumber(-rMain * 0.7, rMain * 0.7)
					local rr = rMain * (0.55 + rng:NextNumber(0, 0.5))
					Terrain:FillBall(Vector3.new(cx + ox, -rr * 0.5, cz + oz), rr, mat)
				end
			end
		end

		-- montagnes a l'horizon : PAS en Enfer (sol plat de lave + le volcan suffit comme repere)
		for _ = 1, (CURRENT_ZONE == 1 and 0 or 8) do
			local ang = rng:NextNumber(0, 6.28)
			local dist = 250 + rng:NextNumber(0, 200)
			local cx = base.X + math.cos(ang) * dist
			local cz = base.Z + math.sin(ang) * dist
			local r = 70 + rng:NextNumber(0, 80)
			if farFromTrack(cx, cz, r + 60) then
				local mmat = (CURRENT_ZONE == 1) and Enum.Material.Basalt or Enum.Material.Rock
				Terrain:FillBlock(CFrame.new(cx, -15, cz), Vector3.new(r * 2 + 40, 30, r * 2 + 40), mmat)
				for _ = 1, 3 do
					local rr = r * (0.7 + rng:NextNumber(0, 0.4))
					Terrain:FillBall(Vector3.new(cx + rng:NextNumber(-r * 0.4, r * 0.4), rr * 0.25, cz + rng:NextNumber(-r * 0.4, r * 0.4)), rr, mmat)
				end
				if CURRENT_ZONE == 3 then   -- MONTAGNE : sommets enneiges
					Terrain:FillBall(Vector3.new(cx, r * 0.7, cz), r * 0.5, Enum.Material.Snow)
				end
			end
		end

		-- un plan d'eau de la zone (eau / lave / glace), loin de la voie
		local wmat
		if CURRENT_ZONE == 1 then wmat = Enum.Material.CrackedLava   -- ENFER : lacs de lave
		elseif CURRENT_ZONE == 3 then wmat = Enum.Material.Ice        -- MONTAGNE : lacs geles
		elseif CURRENT_ZONE == 4 then wmat = Enum.Material.Water end   -- PARADIS : eau pure
		if wmat then
			for _ = 1, 10 do
				local ang = rng:NextNumber(0, 6.28)
				local dist = 100 + rng:NextNumber(0, 70)
				local cx = base.X + math.cos(ang) * dist
				local cz = base.Z + math.sin(ang) * dist
				if farFromTrack(cx, cz, 55) then
					Terrain:FillBlock(CFrame.new(cx, -4, cz), Vector3.new(70, 9, 70), wmat)
					break
				end
			end
		end
	end

	-- nuages pour la profondeur du ciel
	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(242, 242, 248)
	clouds.Parent = Terrain
end
buildTerrain()

-- ===================== DECOR =====================
local decorFolder = Instance.new("Folder")
decorFolder.Name = "Decor"
decorFolder.Parent = Workspace

local function part(size, cf, color, mat, shape)
	local p = makePart(size, cf, color, mat, decorFolder)
	if shape then p.Shape = shape end
	return p
end

local BALL = Enum.PartType.Ball
local CYL  = Enum.PartType.Cylinder

local function tree(pos)
	local h = 8 + rng:NextNumber(0, 4)
	part(Vector3.new(1.6, h, 1.6), CFrame.new(pos + Vector3.new(0, h/2, 0)), Color3.fromRGB(92,58,32), Enum.Material.Wood)
	local g = Color3.fromRGB(50 + rng:NextInteger(0,30), 120 + rng:NextInteger(0,40), 50)
	part(Vector3.new(8,7,8),  CFrame.new(pos + Vector3.new(0, h, 0)),     g, Enum.Material.Grass, BALL)
	part(Vector3.new(6,6,6),  CFrame.new(pos + Vector3.new(0, h+3.5, 0)), g, Enum.Material.Grass, BALL)
	part(Vector3.new(4,4,4),  CFrame.new(pos + Vector3.new(0, h+6, 0)),   g, Enum.Material.Grass, BALL)
end

local function bush(pos)
	local g = Color3.fromRGB(60, 130 + rng:NextInteger(0,30), 55)
	part(Vector3.new(3.5,3,3.5), CFrame.new(pos + Vector3.new(0,1.2,0)), g, Enum.Material.Grass, BALL)
	part(Vector3.new(2.5,2.5,2.5), CFrame.new(pos + Vector3.new(1.5,1,1)), g, Enum.Material.Grass, BALL)
end

local function cactus(pos)
	local g = Color3.fromRGB(64,112,58)
	part(Vector3.new(1.6, 9, 1.6), CFrame.new(pos + Vector3.new(0,4.5,0)), g, Enum.Material.Grass)
	part(Vector3.new(1.2, 3, 1.2), CFrame.new(pos + Vector3.new(1.8,5,0)), g, Enum.Material.Grass)
	part(Vector3.new(1.2, 3, 1.2), CFrame.new(pos + Vector3.new(-1.8,6,0)), g, Enum.Material.Grass)
end

local function desertRock(pos)
	part(Vector3.new(5,3.5,6), CFrame.new(pos + Vector3.new(0,1.5,0)) * CFrame.Angles(0, rng:NextNumber(0,6), 0),
		Color3.fromRGB(170,140,95), Enum.Material.Sandstone)
end

local function volcanoRock(pos)
	-- amas de roche noire ANGULAIRE (blocs inclines, pas une boule) + une veine de lave a la base
	for k = 1, 3 do
		local s = 3 + rng:NextNumber(0, 4)
		local off = Vector3.new(rng:NextNumber(-2, 2), s * 0.4, rng:NextNumber(-2, 2))
		part(Vector3.new(s, s * 0.9, s * 1.1), CFrame.new(pos + off) * CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 6), rng:NextNumber(0, 0.5)), Color3.fromRGB(34, 26, 26), Enum.Material.Basalt)
	end
	part(Vector3.new(6, 0.4, 6), CFrame.new(pos + Vector3.new(0, 0.2, 0)), Color3.fromRGB(255, 85, 20), Enum.Material.Neon)
end

local function lavaPool(pos)
	part(Vector3.new(12,0.5,12), CFrame.new(pos + Vector3.new(0,0.3,0)), Color3.fromRGB(255,80,15), Enum.Material.Neon, CYL)
end

local function iceSpike(pos)
	local h = 10 + rng:NextNumber(0,6)
	part(Vector3.new(2.4, h, 2.4), CFrame.new(pos + Vector3.new(0,h/2,0)) * CFrame.Angles(rng:NextNumber(-0.1,0.1),0,0),
		Color3.fromRGB(195,228,245), Enum.Material.Ice)
	part(Vector3.new(1, 4, 1), CFrame.new(pos + Vector3.new(0,h+1.5,0)), Color3.fromRGB(220,240,255), Enum.Material.Ice)
end

local function snowMound(pos)
	part(Vector3.new(8,5,8), CFrame.new(pos + Vector3.new(0,0.5,0)), Color3.fromRGB(235,245,255), Enum.Material.Snow, BALL)
end

-- deco supplementaire (plus de variete par zone)
local function pine(pos)
	local h = 5 + rng:NextNumber(0, 3)
	part(Vector3.new(1.2, h, 1.2), CFrame.new(pos + Vector3.new(0, h/2, 0)), Color3.fromRGB(80,52,30), Enum.Material.Wood)
	local g = Color3.fromRGB(30, 90 + rng:NextInteger(0,40), 45)
	for k = 0, 3 do
		local s = 7 - k * 1.6
		part(Vector3.new(s, 2.4, s), CFrame.new(pos + Vector3.new(0, h + k * 2.1, 0)), g, Enum.Material.Grass)
	end
end

local function flower(pos)
	part(Vector3.new(0.3, 1.6, 0.3), CFrame.new(pos + Vector3.new(0, 0.8, 0)), Color3.fromRGB(60,140,60), Enum.Material.Grass)
	local cols = { Color3.fromRGB(240,90,90), Color3.fromRGB(245,210,70), Color3.fromRGB(180,110,230), Color3.fromRGB(250,250,255) }
	part(Vector3.new(1.1, 1.1, 1.1), CFrame.new(pos + Vector3.new(0, 1.7, 0)), cols[rng:NextInteger(1, #cols)], Enum.Material.SmoothPlastic, BALL)
end

local function rock(pos)
	local s = 2 + rng:NextNumber(0, 3)
	part(Vector3.new(s, s * 0.8, s * 1.1), CFrame.new(pos + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(rng:NextNumber(0, 0.4), rng:NextNumber(0, 6), 0), Color3.fromRGB(120,120,128), Enum.Material.Rock)
end

local function mesa(pos)
	local h = 13 + rng:NextNumber(0, 9)
	part(Vector3.new(12, h, 12), CFrame.new(pos + Vector3.new(0, h/2, 0)), Color3.fromRGB(176,120,80), Enum.Material.Sandstone)
	part(Vector3.new(14, 2, 14), CFrame.new(pos + Vector3.new(0, h, 0)), Color3.fromRGB(150,98,64), Enum.Material.Sandstone)
end

local function deadTree(pos)
	local h = 7 + rng:NextNumber(0, 4)
	part(Vector3.new(1, h, 1), CFrame.new(pos + Vector3.new(0, h/2, 0)) * CFrame.Angles(0, 0, rng:NextNumber(-0.12, 0.12)), Color3.fromRGB(35,28,26), Enum.Material.Wood)
	part(Vector3.new(0.6, 3, 0.6), CFrame.new(pos + Vector3.new(0.8, h * 0.7, 0)) * CFrame.Angles(0, 0, math.rad(50)), Color3.fromRGB(35,28,26), Enum.Material.Wood)
end

local function smoker(pos)
	part(Vector3.new(3, 4, 3), CFrame.new(pos + Vector3.new(0, 2, 0)), Color3.fromRGB(30,24,24), Enum.Material.Basalt)
	part(Vector3.new(2.4, 0.6, 2.4), CFrame.new(pos + Vector3.new(0, 4, 0)), Color3.fromRGB(255,100,25), Enum.Material.Neon)
	part(Vector3.new(1.6, 1.6, 1.6), CFrame.new(pos + Vector3.new(0, 5.2, 0)), Color3.fromRGB(255,140,40), Enum.Material.Neon, BALL)
end

local function snowyPine(pos)
	local h = 5 + rng:NextNumber(0, 3)
	part(Vector3.new(1.2, h, 1.2), CFrame.new(pos + Vector3.new(0, h/2, 0)), Color3.fromRGB(70,46,28), Enum.Material.Wood)
	for k = 0, 3 do
		local s = 7 - k * 1.6
		part(Vector3.new(s, 2.4, s), CFrame.new(pos + Vector3.new(0, h + k * 2.1, 0)), Color3.fromRGB(40,95,60), Enum.Material.Grass)
		part(Vector3.new(s * 0.92, 0.6, s * 0.92), CFrame.new(pos + Vector3.new(0, h + k * 2.1 + 1.2, 0)), Color3.fromRGB(245,250,255), Enum.Material.Snow)
	end
end

-- ===== NOUVEAUX DECORS PAR THEME (Enfer / Ville / Montagne / Paradis) =====
-- ENFER : pics de roche noire a base rougeoyante + colonnes de feu
local function hellSpike(pos)
	local h = 8 + rng:NextNumber(0, 9)
	part(Vector3.new(2.6, h, 2.6), CFrame.new(pos + Vector3.new(0, h/2, 0)) * CFrame.Angles(rng:NextNumber(-0.12,0.12), rng:NextNumber(0,6), 0), Color3.fromRGB(26,18,20), Enum.Material.Basalt)
	part(Vector3.new(3, 1, 3), CFrame.new(pos + Vector3.new(0, 0.5, 0)), Color3.fromRGB(255,70,18), Enum.Material.Neon)
end
local function fireColumn(pos)
	-- TORCHE-TOUR (style donjon, comme la reference) : tour de pierre crenelee + grande flamme
	local h = 10 + rng:NextNumber(0, 4)
	part(Vector3.new(3.2, h, 3.2), CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color3.fromRGB(72, 58, 54), Enum.Material.Slate)        -- tour
	part(Vector3.new(3.8, 0.8, 3.8), CFrame.new(pos + Vector3.new(0, h - 0.4, 0)), Color3.fromRGB(60, 48, 44), Enum.Material.Slate)    -- corniche
	for a = 0, 3 do                                                                                                                    -- creneaux
		local ang = a * math.pi / 2
		part(Vector3.new(1, 1.6, 1), CFrame.new(pos + Vector3.new(math.cos(ang) * 1.3, h + 0.6, math.sin(ang) * 1.3)), Color3.fromRGB(82, 66, 60), Enum.Material.Slate)
	end
	local bowl = part(Vector3.new(2, 1, 2), CFrame.new(pos + Vector3.new(0, h + 1.3, 0)), Color3.fromRGB(48, 40, 38), Enum.Material.Slate)
	local fx = Instance.new("Fire"); fx.Size = 17; fx.Heat = 14; fx.Color = Color3.fromRGB(255,155,50); fx.SecondaryColor = Color3.fromRGB(255,70,15); fx.Parent = bowl
	local glow = part(Vector3.new(2, 1.6, 2), CFrame.new(pos + Vector3.new(0, h + 2.2, 0)), Color3.fromRGB(255,130,50), Enum.Material.Neon)
	local pl = Instance.new("PointLight"); pl.Range = 28; pl.Brightness = 3; pl.Color = Color3.fromRGB(255,150,70); pl.Parent = glow
end
-- VILLE : immeubles a fenetres lumineuses + lampadaires
local function building(pos)
	local h = 22 + rng:NextNumber(0, 48)
	local w = 8 + rng:NextNumber(0, 7)
	local body = Color3.fromRGB(52 + rng:NextInteger(0,40), 58 + rng:NextInteger(0,40), 74 + rng:NextInteger(0,42))
	part(Vector3.new(w, h, w), CFrame.new(pos + Vector3.new(0, h/2, 0)), body, Enum.Material.Concrete)
	for k = 1, math.floor(h / 6) do
		part(Vector3.new(w * 0.72, 1.6, 0.3), CFrame.new(pos + Vector3.new(0, k * 6, -w/2 - 0.05)), Color3.fromRGB(255,235,150), Enum.Material.Neon)
	end
	part(Vector3.new(w + 1, 1, w + 1), CFrame.new(pos + Vector3.new(0, h, 0)), Color3.fromRGB(40,44,56), Enum.Material.Metal)
end
local function streetLamp(pos)
	part(Vector3.new(0.6, 12, 0.6), CFrame.new(pos + Vector3.new(0, 6, 0)), Color3.fromRGB(45,48,58), Enum.Material.Metal)
	local head = part(Vector3.new(2.2, 0.9, 2.2), CFrame.new(pos + Vector3.new(0, 12, 0)), Color3.fromRGB(255,240,200), Enum.Material.Neon)
	local pl = Instance.new("PointLight"); pl.Range = 22; pl.Brightness = 1.5; pl.Color = Color3.fromRGB(255,235,190); pl.Parent = head
end
-- MONTAGNE : pic rocheux a sommet enneige
local function peakRock(pos)
	local h = 10 + rng:NextNumber(0, 12)
	part(Vector3.new(9, h, 9), CFrame.new(pos + Vector3.new(0, h/2, 0)) * CFrame.Angles(0, rng:NextNumber(0,6), 0), Color3.fromRGB(108,114,128), Enum.Material.Rock)
	part(Vector3.new(7, 3, 7), CFrame.new(pos + Vector3.new(0, h, 0)), Color3.fromRGB(240,248,255), Enum.Material.Snow, BALL)
end
-- PARADIS : nuages, piliers dores, fleurs lumineuses
local function cloudPuff(pos)
	local y = 3 + rng:NextNumber(0, 6)
	part(Vector3.new(9, 5, 9), CFrame.new(pos + Vector3.new(0, y, 0)), Color3.new(1,1,1), Enum.Material.SmoothPlastic, BALL)
	part(Vector3.new(6, 4, 6), CFrame.new(pos + Vector3.new(4, y, 1)), Color3.new(1,1,1), Enum.Material.SmoothPlastic, BALL)
	part(Vector3.new(6, 4, 6), CFrame.new(pos + Vector3.new(-4, y, -1)), Color3.new(1,1,1), Enum.Material.SmoothPlastic, BALL)
end
local function goldPillar(pos)
	local h = 12 + rng:NextNumber(0, 9)
	part(Vector3.new(3.4, 1, 3.4), CFrame.new(pos + Vector3.new(0, 0.5, 0)), Color3.fromRGB(255,240,205), Enum.Material.Marble)
	part(Vector3.new(2, h, 2), CFrame.new(pos + Vector3.new(0, h/2, 0)), Color3.fromRGB(248,240,222), Enum.Material.Marble)
	local cap = part(Vector3.new(3.6, 1.2, 3.6), CFrame.new(pos + Vector3.new(0, h, 0)), Color3.fromRGB(255,215,90), Enum.Material.Neon)
	local pl = Instance.new("PointLight"); pl.Range = 18; pl.Brightness = 1.2; pl.Color = Color3.fromRGB(255,225,140); pl.Parent = cap
end
local function glowFlower(pos)
	part(Vector3.new(0.3, 2, 0.3), CFrame.new(pos + Vector3.new(0, 1, 0)), Color3.fromRGB(120,200,120), Enum.Material.Grass)
	local cols = { Color3.fromRGB(255,180,220), Color3.fromRGB(180,220,255), Color3.fromRGB(255,240,160), Color3.fromRGB(190,255,200) }
	part(Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos + Vector3.new(0, 2.2, 0)), cols[rng:NextInteger(1,#cols)], Enum.Material.Neon, BALL)
end

-- props par zone (forte densite, varie) : index = monde (1 Enfer, 2 Ville, 3 Montagne, 4 Paradis)
local zoneProps = {
	{ volcanoRock, lavaPool, hellSpike, fireColumn, hellSpike, volcanoRock, lavaPool, fireColumn },
	{ building, streetLamp, building, building, streetLamp, building, building },
	{ pine, snowyPine, peakRock, snowMound, iceSpike, rock, snowyPine, peakRock },
	{ cloudPuff, goldPillar, glowFlower, tree, cloudPuff, glowFlower, goldPillar, flower },
}

-- buildDecorProps : pose les arbres/rochers/etc. du monde courant le long de la voie.
local function buildDecorProps()
	-- une deco ne doit JAMAIS tomber sur la voie. Le trace se replie sur lui-meme,
	-- donc on verifie la distance a TOUS les reperes (pas juste au segment courant) :
	-- si la position est a moins de ~11 studs d'un bout de voie quelconque, on annule.
	local function clearOfTrack(px, pz)
		for n = 1, #nodes do
			local q = nodes[n].Position
			local dx, dz = q.X - px, q.Z - pz
			if dx * dx + dz * dz < 324 then return false end   -- 18 studs de marge (avant 11) : plus de clipping
		end
		return true
	end
	for i = 2, NSEG do
		local cf = renderNodes[i]
		if cf.UpVector:Dot(Vector3.yAxis) > 0.7 and segMeta[i].kind ~= "tunnel" then
			local zi = zoneForSegment(i)
			local list = zoneProps[zi]
			for _, side in ipairs({ -1, 1 }) do
				-- 1er plan : pres de la voie
				if rng:NextNumber() < 0.32 then
					local dist = 18 + rng:NextNumber(0, 16)
					local gp = Vector3.new(cf.Position.X, 0, cf.Position.Z) + cf.RightVector * (dist * side)
					if clearOfTrack(gp.X, gp.Z) then list[rng:NextInteger(1, #list)](gp) end
				end
				-- 2e plan : plus loin, pour la profondeur (moins souvent)
				if rng:NextNumber() < 0.3 then
					local dist = 32 + rng:NextNumber(0, 24)
					local gp = Vector3.new(cf.Position.X, 0, cf.Position.Z) + cf.RightVector * (dist * side)
					if clearOfTrack(gp.X, gp.Z) then list[rng:NextInteger(1, #list)](gp) end
				end
				-- 3e plan : arriere-plan LOINTAIN (profondeur + richesse), encore moins souvent
				if rng:NextNumber() < 0.22 then
					local dist = 62 + rng:NextNumber(0, 55)
					local gp = Vector3.new(cf.Position.X, 0, cf.Position.Z) + cf.RightVector * (dist * side)
					if clearOfTrack(gp.X, gp.Z) then list[rng:NextInteger(1, #list)](gp) end
				end
			end
		end
	end
end  -- fin buildDecorProps

-- montagnes / arriere-plan par zone
-- collines / dunes / volcans arrondis a l'arriere-plan (plus de cubes !)
local function backdrop(zi)
	-- le relief est en vrai Terrain sculpte ; ici on pose le GRAND repere marquant du monde.
	local segMid = math.floor((zi - 0.5)/#ZONES * NSEG) + 1
	local base = nodes[math.clamp(segMid,1,#nodes)].Position
	-- le landmark est ENORME : on cherche un emplacement LOIN de TOUTE la voie (jamais sur les rails)
	local function farFromTrack(px, pz)
		for n = 1, #nodes, 2 do
			local q = nodes[n].Position
			local dx, dz = q.X - px, q.Z - pz
			if dx * dx + dz * dz < 160 * 160 then return false end
		end
		return true
	end
	-- position DETERMINISTE (le volcan ne bouge plus a chaque modif) : on scanne des angles FIXES
	-- et on prend le 1er emplacement loin de la voie -> meme endroit a chaque partie.
	local lp
	for _, ang in ipairs({ 0.7, 5.6, 1.4, 4.9, 2.1, 4.2, 0.0, 3.14159 }) do
		for _, d in ipairs({ 360, 320, 420, 300 }) do
			local cand = Vector3.new(base.X + math.cos(ang) * d, 0, base.Z + math.sin(ang) * d)
			if farFromTrack(cand.X, cand.Z) then lp = cand; break end
		end
		if lp then break end
	end
	lp = lp or Vector3.new(base.X + 420, 0, base.Z)   -- secours si rien trouve
	if zi == 1 then            -- ENFER : VOLCAN = vrai cone 3D LISSE (mesh par code) + cratere de lave
		-- VOLCAN sculpte en TERRAIN (lisse, plus HAUT et plus FIN qu'avant) : boules degressives empilees
		for i = 0, 23 do
			local frac = i / 24
			Terrain:FillBall(lp + Vector3.new(0, frac * 310 + 6, 0), 135 - frac * 110, Enum.Material.Basalt)
		end
		Terrain:FillBall(lp + Vector3.new(0, 318, 0), 30, Enum.Material.CrackedLava)   -- cratere de lave (terrain brillant)
		-- cratere de lave brillant au sommet + grosse fumee + feu
		local crater = part(Vector3.new(12, 24, 24), CFrame.new(lp + Vector3.new(0, 314, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 150, 30), Enum.Material.Neon, CYL)
		local smoke = Instance.new("Smoke"); smoke.Color = Color3.fromRGB(40, 32, 28); smoke.Size = 240; smoke.RiseVelocity = 32; smoke.Opacity = 0.5; smoke.Parent = crater
		local cfire = Instance.new("Fire"); cfire.Size = 36; cfire.Heat = 14; cfire.Color = Color3.fromRGB(255, 120, 40); cfire.SecondaryColor = Color3.fromRGB(255, 55, 15); cfire.Parent = crater
		-- LAVE : coulees DISTINCTES bien marquees du haut vers le bas (comme la ref) - jaune-orange sur roche grise
		for k = 0, 5 do
			local ang = k * (2 * math.pi / 6) + 0.25
			local up = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local function surf(tt) local aa = ang + math.sin(tt * 7 + k * 1.7) * 0.13; local r = 147 - tt * 114; return lp + Vector3.new(math.cos(aa) * r, 6 + tt * 310, math.sin(aa) * r) end
			local cuts = { 0.88, 0.74, 0.60, 0.46, 0.32, 0.18, 0.04 }
			for s = 1, #cuts - 1 do
				local a, b = surf(cuts[s]), surf(cuts[s + 1])
				local mid = (a + b) / 2
				local len = (b - a).Magnitude
				local w = 11 + (1 - cuts[s + 1]) * 12
				part(Vector3.new(w, 2.2, len + 1.5), CFrame.lookAt(mid, b, up), Color3.fromRGB(255, 160, 30), Enum.Material.Neon)
				part(Vector3.new(w * 0.4, 2.6, len + 1.5), CFrame.lookAt(mid, b, up), Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
			end
			local pool = part(Vector3.new(26, 2.6, 26), CFrame.new(surf(0.02) + Vector3.new(0, -1, 0)), Color3.fromRGB(255, 150, 35), Enum.Material.Neon, BALL)
			local pl = Instance.new("PointLight"); pl.Range = 28; pl.Brightness = 2.2; pl.Color = Color3.fromRGB(255, 130, 40); pl.Parent = pool
		end
	elseif zi == 2 then        -- VILLE : gratte-ciels lumineux au loin
		for k = -2, 2 do
			local hh = 120 + rng:NextNumber(0, 90)
			local off = lp + Vector3.new(k * 38, 0, rng:NextNumber(-30, 30))
			part(Vector3.new(30, hh, 30), CFrame.new(off + Vector3.new(0, hh/2, 0)), Color3.fromRGB(58,64,82), Enum.Material.Concrete)
			part(Vector3.new(31, 2, 31), CFrame.new(off + Vector3.new(0, hh, 0)), Color3.fromRGB(255,90,90), Enum.Material.Neon)
		end
	elseif zi == 3 then        -- MONTAGNE : pic enneige geant
		local H = 210
		part(Vector3.new(220, H, 220), CFrame.new(lp + Vector3.new(0, H*0.3, 0)), Color3.fromRGB(94,102,116), Enum.Material.Rock, BALL)
		part(Vector3.new(130, 76, 130), CFrame.new(lp + Vector3.new(0, H*0.72, 0)), Color3.fromRGB(240,248,255), Enum.Material.Snow, BALL)
	else                       -- PARADIS : grande porte doree lumineuse
		for _, sx in ipairs({ -24, 24 }) do
			part(Vector3.new(11, 150, 11), CFrame.new(lp + Vector3.new(sx, 75, 0)), Color3.fromRGB(255,225,120), Enum.Material.Neon)
		end
		part(Vector3.new(70, 13, 13), CFrame.new(lp + Vector3.new(0, 150, 0)), Color3.fromRGB(255,235,150), Enum.Material.Neon)
	end
end
-- buildLandmarks : GRANDES structures DELIBEREES le long de la voie (comble le "vide"), par theme.
-- ENFER : de grandes arches de roche noire que la VOIE TRAVERSE, avec une veine de lave au sommet.
local function buildLandmarks()
	local zi = CURRENT_ZONE
	for i = 12, NSEG - 5, 24 do   -- ~tous les 190 studs, uniquement sur du PLAT DROIT
		local cf = renderNodes[i]
		if cf.UpVector.Y > 0.9 and segMeta[i].kind == "straight" then
			if zi == 1 then
				for _, sx in ipairs({ -1, 1 }) do
					part(Vector3.new(4.5, 26, 5), cf * CFrame.new(sx * (TRACK_WIDTH / 2 + 5), 11, 0), Color3.fromRGB(34, 26, 26), Enum.Material.Basalt)
				end
				part(Vector3.new(TRACK_WIDTH + 16, 5, 6), cf * CFrame.new(0, 24, 0), Color3.fromRGB(40, 30, 30), Enum.Material.Basalt)
				part(Vector3.new(TRACK_WIDTH + 12, 0.7, 1.2), cf * CFrame.new(0, 21.3, 0), Color3.fromRGB(255, 80, 20), Enum.Material.Neon)
			end
		end
	end
end

-- buildDecor : vide l'ancien decor, repose les props + les landmarks + le grand repere du monde.
local function buildDecor()
	decorFolder:ClearAllChildren()
	buildDecorProps()
	buildLandmarks()
	backdrop(CURRENT_ZONE)
end
buildDecor()

-- applyLighting : ciel/ambiance teintes selon le monde (glace = bleu, magma = orange...).
local function applyLighting()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	if CURRENT_ZONE == 1 then            -- ENFER : crepuscule rouge ardent (mais on VOIT bien)
		Lighting.ClockTime = 17.2; Lighting.Brightness = 2.9
		Lighting.OutdoorAmbient = Color3.fromRGB(145, 85, 68)
		atmo.Color = Color3.fromRGB(185, 95, 62); atmo.Haze = 2;   atmo.Density = 0.32
	elseif CURRENT_ZONE == 2 then        -- VILLE : crepuscule urbain
		Lighting.ClockTime = 18.5; Lighting.Brightness = 2.2
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 112, 132)
		atmo.Color = Color3.fromRGB(205, 200, 225); atmo.Haze = 2.4; atmo.Density = 0.4
	elseif CURRENT_ZONE == 3 then        -- MONTAGNE : grand jour froid et vif
		Lighting.ClockTime = 11;   Lighting.Brightness = 3
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 165, 190)
		atmo.Color = Color3.fromRGB(225, 240, 255); atmo.Haze = 1.4; atmo.Density = 0.3
	else                                  -- PARADIS : lumiere doree, douce
		Lighting.ClockTime = 14;   Lighting.Brightness = 3.2
		Lighting.OutdoorAmbient = Color3.fromRGB(200, 192, 160)
		atmo.Color = Color3.fromRGB(255, 244, 212); atmo.Haze = 1.8; atmo.Density = 0.3
	end
	atmo.Parent = Lighting
end
applyLighting()

-- point d'apparition : voir le HUB plus bas (cree apres le chariot)

-- ===================== LE CHARIOT =====================
local function buildCart()
	local model = Instance.new("Model")
	model.Name = "Chariot"

	local WOOD  = Color3.fromRGB(124, 78, 46)
	local WOOD2 = Color3.fromRGB(100, 62, 38)
	local METAL = Color3.fromRGB(58, 60, 68)

	local function piece(name, size, offset, color, mat, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.Color = color
		p.Material = mat or Enum.Material.WoodPlanks
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = CFrame.new(offset)
		if shape then p.Shape = shape end
		p.Parent = model
		return p
	end

	-- chassis metallique (sert de PrimaryPart / pivot)
	local base = piece("Base", Vector3.new(4.6, 0.7, 6.6), Vector3.new(0, 0, 0), METAL, Enum.Material.Metal)
	model.PrimaryPart = base

	-- caisse en bois : plancher + 4 parois (dessus ouvert)
	piece("Plancher", Vector3.new(4.3, 0.4, 6.3), Vector3.new(0, 0.55, 0), WOOD2, Enum.Material.WoodPlanks)
	piece("Avant",    Vector3.new(4.5, 2.0, 0.4), Vector3.new(0, 1.5, -3.05), WOOD, Enum.Material.WoodPlanks)
	piece("Arriere",  Vector3.new(4.5, 2.0, 0.4), Vector3.new(0, 1.5,  3.05), WOOD, Enum.Material.WoodPlanks)
	piece("Gauche",   Vector3.new(0.4, 2.0, 6.5), Vector3.new(-2.25, 1.5, 0), WOOD, Enum.Material.WoodPlanks)
	piece("Droite",   Vector3.new(0.4, 2.0, 6.5), Vector3.new( 2.25, 1.5, 0), WOOD, Enum.Material.WoodPlanks)

	-- cerclage metallique + cadre du rebord (dessus reste ouvert)
	for _, zz in ipairs({ -1.7, 1.7 }) do
		piece("Cercle", Vector3.new(4.8, 0.4, 0.45), Vector3.new(0, 1.6, zz), METAL, Enum.Material.Metal)
	end
	piece("RebordAv", Vector3.new(4.85, 0.3, 0.5), Vector3.new(0, 2.6, -3.05), METAL, Enum.Material.Metal)
	piece("RebordAr", Vector3.new(4.85, 0.3, 0.5), Vector3.new(0, 2.6,  3.05), METAL, Enum.Material.Metal)
	piece("RebordG",  Vector3.new(0.5, 0.3, 6.7),  Vector3.new(-2.25, 2.6, 0), METAL, Enum.Material.Metal)
	piece("RebordD",  Vector3.new(0.5, 0.3, 6.7),  Vector3.new( 2.25, 2.6, 0), METAL, Enum.Material.Metal)

	-- lanterne avant (eclaire la voie, sympa dans les tunnels)
	local lantern = piece("Lanterne", Vector3.new(0.9, 1.0, 0.9), Vector3.new(0, 1.9, -3.35),
		Color3.fromRGB(255, 224, 150), Enum.Material.Neon)
	local ll = Instance.new("PointLight")
	ll.Range = 16
	ll.Brightness = 1.6
	ll.Color = Color3.fromRGB(255, 214, 150)
	ll.Parent = lantern

	-- 4 roues (cylindres, axe gauche-droite) posees PILE sur les rails (ecartement = GAUGE)
	local wheelY = -0.8
	for _, x in ipairs({ -GAUGE, GAUGE }) do
		for _, zz in ipairs({ -2.2, 2.2 }) do
			piece("Roue", Vector3.new(0.5, 1.7, 1.7), Vector3.new(x, wheelY, zz),
				Color3.fromRGB(26, 26, 30), Enum.Material.Metal, Enum.PartType.Cylinder)
			piece("Moyeu", Vector3.new(0.55, 0.7, 0.7), Vector3.new(x, wheelY, zz),
				Color3.fromRGB(150, 150, 160), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	-- essieux
	for _, zz in ipairs({ -2.2, 2.2 }) do
		piece("Essieu", Vector3.new(GAUGE * 2 + 0.4, 0.28, 0.28), Vector3.new(0, wheelY, zz), METAL, Enum.Material.Metal)
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Pilote"
	seat.Size = Vector3.new(3, 0.6, 2.6)
	seat.Anchored = true
	seat.Color = Color3.fromRGB(72, 50, 34)
	seat.Material = Enum.Material.WoodPlanks
	seat.CFrame = CFrame.new(0, 1.0, 0.4)
	seat.MaxSpeed = 50
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model

	-- on soude toutes les pieces a la base : a la chute, le chariot tombe d'un bloc.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= base then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = base
			wc.Part1 = p
			wc.Parent = base
		end
	end
	return model, seat
end

-- ===================== MULTI-CHARIOTS (un chariot PAR JOUEUR) =====================
-- playerCarts[player] = pc  (contexte par joueur). Chaque pc a SON chariot, SON siege,
-- SES effets (son/etincelles/halo) et SON etat (state). Le monde/la voie restent PARTAGES.
-- pc = { player, cart, seat, base, rollSound, sparkEmitter, legendLight, legendFX,
--        cartPitch, state, spawned, conns }
local playerCarts = {}

-- creation des EFFETS par chariot (avant : globaux ; maintenant : un jeu par chariot).
-- On parente a la PrimaryPart du chariot du joueur. Identique a l'ancien reglage.
local function makeCartFX(pc)
	-- SON de rail : un petit "clac" GRAVE et discret, joue regulierement quand le wagon
	-- roule (cadence = vitesse). Son GARANTI (rbxasset), a basse hauteur pour faire "toc-toc".
	local rollSound = Instance.new("Sound")
	rollSound.SoundId = ROLL_SOUND
	rollSound.Looped = true   -- le "wagon clatter" tourne en boucle ; le volume suit la vitesse
	rollSound.Volume = 0
	rollSound.Parent = pc.cart.PrimaryPart
	if ROLL_SOUND_READY then rollSound:Play() end

	-- ETINCELLES de derapage (s'allument quand on perd l'adherence en virage).
	local sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 120, 30))
	sparkEmitter.Size = NumberSequence.new(0.5, 0)
	sparkEmitter.Lifetime = NumberRange.new(0.18, 0.4)
	sparkEmitter.Speed = NumberRange.new(9, 18)
	sparkEmitter.SpreadAngle = Vector2.new(50, 50)
	sparkEmitter.Acceleration = Vector3.new(0, -32, 0)
	sparkEmitter.Rate = 140
	sparkEmitter.LightEmission = 1
	sparkEmitter.Enabled = false
	sparkEmitter.Parent = pc.cart.PrimaryPart

	-- effet "LEGENDAIRE" : halo dore + etincelles, uniquement sur le meilleur chariot.
	local legendLight = Instance.new("PointLight")
	legendLight.Color = Color3.fromRGB(255, 215, 60); legendLight.Range = 20; legendLight.Brightness = 0
	legendLight.Parent = pc.cart.PrimaryPart
	local legendFX = Instance.new("ParticleEmitter")
	legendFX.Color = ColorSequence.new(Color3.fromRGB(255, 235, 130), Color3.fromRGB(255, 170, 30))
	legendFX.Size = NumberSequence.new(0.7, 0)
	legendFX.Lifetime = NumberRange.new(0.4, 0.9)
	legendFX.Speed = NumberRange.new(2, 6)
	legendFX.Rate = 28
	legendFX.LightEmission = 1
	legendFX.Enabled = false
	legendFX.Parent = pc.cart.PrimaryPart

	pc.rollSound = rollSound
	pc.sparkEmitter = sparkEmitter
	pc.legendLight = legendLight
	pc.legendFX = legendFX
end

-- applyCartStyle : REPEINT le chariot selon le niveau (look qui evolue : bois -> metal ->
-- neon -> dore legendaire) + regle le SON (pitch par niveau, son custom si fourni).
-- buildAccessories : AJOUTE/RETIRE des pieces selon le niveau -> le chariot change de FORME
-- (pas juste de couleur) : jupes, aileron, pots, nez, ailes, reacteurs. Legendaire = imposant.
local function buildAccessories(tier, m)
	if not m then return end
	for _, p in ipairs(m:GetChildren()) do
		if p:GetAttribute("Accessory") then p:Destroy() end
	end
	local base = m.PrimaryPart
	if not base then return end
	local c = CARTS[tier]
	local trimMat = (c.mat == Enum.Material.Neon) and Enum.Material.Neon or Enum.Material.Metal
	local function acc(size, coff, color, mat, shape)
		local p = Instance.new("Part")
		p:SetAttribute("Accessory", true)
		p.Size = size; p.Color = color; p.Material = mat or Enum.Material.Metal
		p.Anchored = true; p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then p.Shape = shape end
		p.CFrame = base.CFrame * coff
		p.Parent = m
		local wc = Instance.new("WeldConstraint"); wc.Part0 = base; wc.Part1 = p; wc.Parent = p
		return p
	end
	if tier >= 3 then  -- jupes laterales
		for _, sx in ipairs({ -1, 1 }) do
			acc(Vector3.new(0.3, 0.8, 5.6), CFrame.new(sx * 2.55, 0.15, 0), c.trim, trimMat)
		end
	end
	if tier >= 4 then  -- AILERON arriere (grandit avec le niveau)
		local h = 1.8 + tier * 0.16
		acc(Vector3.new(0.35, h, 0.4), CFrame.new(-2, 1.6 + h / 2, 3.5), c.trim, trimMat)
		acc(Vector3.new(0.35, h, 0.4), CFrame.new( 2, 1.6 + h / 2, 3.5), c.trim, trimMat)
		acc(Vector3.new(5.6, 0.4, 1.5), CFrame.new(0, 1.6 + h, 3.5), c.body, c.mat)
	end
	if tier >= 5 then  -- pots d'echappement
		for _, sx in ipairs({ -1.1, 1.1 }) do
			acc(Vector3.new(2.2, 0.7, 0.7), CFrame.new(sx, -0.15, 3.9) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(55, 56, 62), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	if tier >= 6 then  -- nez aero a l'avant
		acc(Vector3.new(4.2, 1.3, 1.8), CFrame.new(0, 0.5, -3.8) * CFrame.Angles(math.rad(-22), 0, 0), c.trim, trimMat)
	end
	if tier >= 7 then  -- bande lumineuse sous le chariot
		acc(Vector3.new(4.4, 0.3, 6.4), CFrame.new(0, -0.95, 0), c.body, Enum.Material.Neon)
	end
	if tier >= 8 then  -- ailes laterales relevees
		for _, sx in ipairs({ -1, 1 }) do
			acc(Vector3.new(3.6, 0.35, 3), CFrame.new(sx * 3.7, 1.3, 0.4) * CFrame.Angles(0, 0, math.rad(sx * -10)), c.trim, trimMat)
		end
	end
	if tier >= 9 then  -- reacteurs arriere lumineux
		for _, sx in ipairs({ -1.3, 1.3 }) do
			acc(Vector3.new(1.6, 1.3, 1.3), CFrame.new(sx, 0.6, 3.9) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end
	if tier >= 10 then  -- LEGENDAIRE imposant : grandes ailes dorees + couronne + gros reacteur
		for _, sx in ipairs({ -1, 1 }) do
			acc(Vector3.new(5.5, 0.45, 4), CFrame.new(sx * 5, 2, 0.4) * CFrame.Angles(0, 0, math.rad(sx * -24)), Color3.fromRGB(255, 215, 40), Enum.Material.Neon)
		end
		for _, ix in ipairs({ -1.5, 0, 1.5 }) do
			acc(Vector3.new(0.45, 1.8, 0.45), CFrame.new(ix, 3.5, 0), Color3.fromRGB(255, 235, 120), Enum.Material.Neon)
		end
		acc(Vector3.new(2.6, 2, 2), CFrame.new(0, 0.7, 4.1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 180, 40), Enum.Material.Neon, Enum.PartType.Cylinder)
	end
end

-- styleModel : peint la caisse + bordures d'UN modele de chariot (le vrai OU un clone d'apercu)
-- et lui (re)met les accessoires du niveau. Sert au chariot du jeu ET a l'apercu 3D du menu.
local function styleModel(m, tier)
	local c = CARTS[tier]
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			local n = p.Name
			if n == "Plancher" or n == "Avant" or n == "Arriere" or n == "Gauche" or n == "Droite" then
				p.Color = c.body; p.Material = c.mat
			elseif n == "Cercle" or string.sub(n, 1, 6) == "Rebord" then
				p.Color = c.trim
				p.Material = (c.mat == Enum.Material.Neon) and Enum.Material.Neon or Enum.Material.Metal
			end
		end
	end
	buildAccessories(tier, m)   -- change la FORME selon le niveau
end

-- applyCartStyle : restyle le chariot D'UN JOUEUR (pc) au niveau donne + regle SON son/halo.
local function applyCartStyle(pc, tier)
	if not pc then return end
	local cart = pc.cart
	local legendLight, legendFX, rollSound = pc.legendLight, pc.legendFX, pc.rollSound
	local c = CARTS[tier]
	styleModel(cart, tier)
	legendLight.Brightness = c.legend and 3 or 0
	legendFX.Enabled = c.legend == true
	pc.cartPitch = c.pitch or 1
	local sid = c.sound or ROLL_SOUND
	if rollSound.SoundId ~= sid then
		rollSound.SoundId = sid
		if ROLL_SOUND_READY then rollSound:Play() end
	end
end

-- templateCart : UN chariot "modele" cree une fois, garde hors-jeu (ReplicatedStorage), stylise
-- au niveau 1. L'apercu 3D du menu CHARIOTS en CLONE une copie (avant : il clonait le chariot du
-- joueur, ce qui dependait d'un chariot vivant). Ainsi le menu marche meme avant tout spawn.
local templateCart = (buildCart())
templateCart.Name = "ChariotTemplate"
styleModel(templateCart, 1)
templateCart.Parent = ReplicatedStorage

-- ===================== HUB / LOBBY (la ou les joueurs arrivent) =====================
-- spawnPlayerCart / makePlayerCart sont definis plus bas (apres makeGui/connectSeat) ; goToCart
-- (pad ▶ JOUER) declenche spawnPlayerCart. Declares ici en avance car buildHub/le pad y font reference.
local spawnPlayerCart   -- forward declaration (assigne plus bas)
local makePlayerCart    -- forward declaration (assigne plus bas)
local function goToCart(player)
	if spawnPlayerCart then spawnPlayerCart(player) end
end

-- buildHub : (re)construit le hub au depart du circuit courant. Rejouable a chaque monde.
local function buildHub()
	local cf0 = renderAtDistance(0)
	-- HUB THEMATISE : version ENFER (pierre sombre + lave) sinon version normale (bleu), selon le monde.
	local hell  = (CURRENT_ZONE == 1)
	local FLA   = hell and Color3.fromRGB(58, 44, 42)  or Color3.fromRGB(56, 60, 82)
	local FLB   = hell and Color3.fromRGB(38, 28, 28)  or Color3.fromRGB(40, 44, 62)
	local STONE = hell and Color3.fromRGB(64, 50, 48)  or Color3.fromRGB(88, 92, 108)
	local WOOD  = hell and Color3.fromRGB(52, 40, 38)  or Color3.fromRGB(120, 78, 46)
	local ACC   = hell and Color3.fromRGB(255, 95, 30) or Color3.fromRGB(120, 200, 255)
	local GOLD  = hell and Color3.fromRGB(255, 150, 40) or Color3.fromRGB(255, 205, 60)
	local DEFMAT = hell and Enum.Material.Slate or Enum.Material.SmoothPlastic
	local function hp(size, off, color, mat)
		return makePart(size, cf0 * off, color, mat or DEFMAT, trackFolder)
	end
	-- PANNEAU lisible : texte IMPRIME sur une plaque (recto-verso, centre, ajuste)
	local hubCenter = (cf0 * CFrame.new(0, 6, 46)).Position
	local function sign(offCF, w, h, text, txtColor, bgColor)
		local pos = (cf0 * offCF).Position
		local part = makePart(Vector3.new(w, h, 0.5),
			CFrame.lookAt(pos, Vector3.new(hubCenter.X, pos.Y, hubCenter.Z)),
			bgColor or Color3.fromRGB(18, 22, 34), Enum.Material.SmoothPlastic, trackFolder)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 40
			sg.Adornee = part; sg.Parent = part
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(0.92, 0, 0.84, 0); t.Position = UDim2.new(0.04, 0, 0.08, 0)
			t.BackgroundTransparency = 1; t.TextScaled = true; t.TextWrapped = true
			t.TextXAlignment = Enum.TextXAlignment.Center; t.TextYAlignment = Enum.TextYAlignment.Center
			t.Font = Enum.Font.GothamBlack; t.TextColor3 = txtColor or Color3.new(1, 1, 1); t.TextStrokeTransparency = 0.4
			t.Text = text; t.Parent = sg
		end
		return part
	end

	-- ---- SOL (GRAND, agrandi) : dalle + damier + bordures neon ----
	local HW = 62               -- demi-largeur du hub (avant 49 -> plus grand)
	local FZ, BZ = -4, 92
	local CZ, D = (FZ + BZ) / 2, BZ - FZ
	hp(Vector3.new(HW * 2 + 2, 2, D), CFrame.new(0, -3.4, CZ), FLB)
	for ix = -7, 7 do
		for iz = 0, 10 do
			if (ix + iz) % 2 == 0 then
				hp(Vector3.new(8.6, 0.3, 8.6), CFrame.new(ix * 8.7, -2.3, 4 + iz * 8.7), FLA)
			end
		end
	end
	hp(Vector3.new(HW * 2 + 2, 0.5, 1.4), CFrame.new(0, -2.1, FZ + 0.5), ACC, Enum.Material.Neon)
	hp(Vector3.new(HW * 2 + 2, 0.5, 1.4), CFrame.new(0, -2.1, BZ - 0.5), ACC, Enum.Material.Neon)
	hp(Vector3.new(1.4, 0.5, D), CFrame.new(-(HW + 0.5), -2.1, CZ), ACC, Enum.Material.Neon)
	hp(Vector3.new(1.4, 0.5, D), CFrame.new(HW + 0.5, -2.1, CZ), ACC, Enum.Material.Neon)

	-- ---- GRILLE GOTHIQUE (enfer) ----
	if hell then
		local bar = Color3.fromRGB(26, 20, 20)
		for fx = -HW, HW, 6 do
			hp(Vector3.new(0.4, 4.5, 0.4), CFrame.new(fx, 0.3, FZ + 0.5), bar, Enum.Material.Metal)
			hp(Vector3.new(0.4, 4.5, 0.4), CFrame.new(fx, 0.3, BZ - 0.5), bar, Enum.Material.Metal)
		end
		for fz = FZ + 1, BZ - 1, 6 do
			hp(Vector3.new(0.4, 4.5, 0.4), CFrame.new(-(HW + 0.5), 0.3, fz), bar, Enum.Material.Metal)
			hp(Vector3.new(0.4, 4.5, 0.4), CFrame.new(HW + 0.5, 0.3, fz), bar, Enum.Material.Metal)
		end
		hp(Vector3.new(HW * 2, 0.4, 0.4), CFrame.new(0, 2, FZ + 0.5), bar, Enum.Material.Metal)
		hp(Vector3.new(HW * 2, 0.4, 0.4), CFrame.new(0, 2, BZ - 0.5), bar, Enum.Material.Metal)
		hp(Vector3.new(0.4, 0.4, D), CFrame.new(-(HW + 0.5), 2, CZ), bar, Enum.Material.Metal)
		hp(Vector3.new(0.4, 0.4, D), CFrame.new(HW + 0.5, 2, CZ), bar, Enum.Material.Metal)
	end

	-- ---- PILIERS + lampes + VERRIERE ----
	for _, px in ipairs({ -(HW - 6), HW - 6 }) do
		for _, pz in ipairs({ 4, 44, 84 }) do
			hp(Vector3.new(3, 26, 3), CFrame.new(px, 9, pz), STONE)
			local cap = hp(Vector3.new(5, 1.6, 5), CFrame.new(px, 21, pz), ACC, Enum.Material.Neon)
			local pl = Instance.new("PointLight"); pl.Range = 30; pl.Brightness = 2.4
			pl.Color = hell and Color3.fromRGB(255, 150, 70) or Color3.fromRGB(255, 240, 210); pl.Parent = cap
			if hell then local f = Instance.new("Fire"); f.Size = 13; f.Heat = 12; f.Color = Color3.fromRGB(255, 150, 45); f.SecondaryColor = Color3.fromRGB(255, 70, 15); f.Parent = cap end
		end
	end
	hp(Vector3.new(HW * 2 + 4, 1.6, D + 4), CFrame.new(0, 22, CZ), Color3.fromRGB(38, 42, 58))
	hp(Vector3.new(HW * 2 - 4, 0.5, D - 4), CFrame.new(0, 22.9, CZ), ACC, Enum.Material.Neon)
	hp(Vector3.new(HW * 2, 28, 1.6), CFrame.new(0, 8, BZ - 0.3), STONE)
	hp(Vector3.new(HW * 2, 0.7, 1.8), CFrame.new(0, 22, BZ - 0.3), ACC, Enum.Material.Neon)

	-- ---- PANNEAUX (texte court, centre, lisible) ----
	sign(CFrame.new(0, 15, 6), 54, 9, "🚂 BALADE EN CHARIOT", ACC, Color3.fromRGB(24, 28, 42))
	-- panneau classement : UNE seule ligne (fini le "coupe en deux"). Le vrai
	-- classement reste la liste native en haut a droite.
	sign(CFrame.new(-22, 8, 88), 24, 6, "🏆 CLASSEMENT", GOLD, Color3.fromRGB(20, 24, 38))

	-- ---- KIOSQUES ----
	local function kiosk(off, label, col)
		hp(Vector3.new(13, 7, 8), off, WOOD, Enum.Material.WoodPlanks)
		hp(Vector3.new(14, 1.4, 9), off * CFrame.new(0, 4.2, 0), col, Enum.Material.Neon)
		sign(off * CFrame.new(0, 8, 0), 14, 4, label, Color3.new(1, 1, 1), Color3.fromRGB(22, 26, 40))
	end
	kiosk(CFrame.new(36, 0, 64), "🛒 CHARIOTS", Color3.fromRGB(90, 200, 120))
	kiosk(CFrame.new(36, 0, 48), "✨ RENAISSANCE", Color3.fromRGB(190, 120, 230))

	-- ---- BANCS ----
	for _, bx in ipairs({ -18, 18 }) do
		hp(Vector3.new(9, 0.6, 2.6), CFrame.new(bx, -1.7, 36), WOOD, Enum.Material.WoodPlanks)
		hp(Vector3.new(9, 1.8, 0.5), CFrame.new(bx, -0.8, 37), WOOD, Enum.Material.WoodPlanks)
	end

	-- ---- TROPHEE CENTRAL : une vraie COUPE doree (socle + pied + bol + 2 anses) ----
	hp(Vector3.new(10, 1.6, 10), CFrame.new(0, -2.4, 80), STONE)                       -- socle pierre
	hp(Vector3.new(5, 1.2, 5), CFrame.new(0, -1.4, 80), GOLD, Enum.Material.Neon)      -- plaque doree
	hp(Vector3.new(1.6, 3.5, 1.6), CFrame.new(0, 0.6, 80), GOLD, Enum.Material.Neon)   -- pied
	local bowl = hp(Vector3.new(7, 4.5, 7), CFrame.new(0, 4, 80), GOLD, Enum.Material.Neon)  -- coupe (bol)
	bowl.Shape = Enum.PartType.Ball
	hp(Vector3.new(1, 3.4, 1), CFrame.new(-4, 4.2, 80) * CFrame.Angles(0, 0, math.rad(22)),  GOLD, Enum.Material.Neon)  -- anse gauche
	hp(Vector3.new(1, 3.4, 1), CFrame.new( 4, 4.2, 80) * CFrame.Angles(0, 0, math.rad(-22)), GOLD, Enum.Material.Neon)  -- anse droite
	sign(CFrame.new(0, 9, 80), 12, 3.5, "🏆 TROPHEES", GOLD, Color3.fromRGB(20, 24, 38))      -- etiquette claire
	local tlight = Instance.new("PointLight"); tlight.Range = 26; tlight.Brightness = 2.4; tlight.Color = GOLD; tlight.Parent = bowl
	local spk = Instance.new("Sparkles"); spk.SparkleColor = Color3.fromRGB(255, 220, 120); spk.Parent = bowl

	-- ---- PLANTES en pots ----
	local function pot(off)
		if hell then   -- obelisque de roche noire a pointe de lave (au lieu d'une plante verte)
			hp(Vector3.new(2.4, 8, 2.4), off * CFrame.new(0, 3, 0), Color3.fromRGB(40, 30, 30), Enum.Material.Basalt)
			hp(Vector3.new(2.8, 0.7, 2.8), off * CFrame.new(0, 7.3, 0), Color3.fromRGB(255, 90, 30), Enum.Material.Neon)
		else
			hp(Vector3.new(3, 2.6, 3), off, Color3.fromRGB(74, 52, 40), Enum.Material.Wood)
			local lv = hp(Vector3.new(4.6, 4.6, 4.6), off * CFrame.new(0, 3, 0), Color3.fromRGB(70, 155, 70), Enum.Material.Grass)
			lv.Shape = Enum.PartType.Ball
		end
	end
	pot(CFrame.new(-40, -1.3, 22)); pot(CFrame.new(40, -1.3, 22))
	pot(CFrame.new(-40, -1.3, 66)); pot(CFrame.new(40, -1.3, 66))

	-- ---- POINT D'APPARITION (grand) ----
	local sp = Instance.new("SpawnLocation")
	sp.Size = Vector3.new(22, 1, 22); sp.Anchored = true; sp.Neutral = true
	sp.CFrame = cf0 * CFrame.new(0, -2.4, 56)
	sp.Color = ACC; sp.Material = Enum.Material.Neon; sp.Transparency = 0.4
	sp.Parent = trackFolder

	-- ---- PADS D'APPARITION DU CHARIOT (style ref : on monte sur un pad colore -> son chariot apparait) ----
	sign(CFrame.new(0, 9, 6), 52, 5.5, "🚂 MONTE SUR UN PAD POUR FAIRE APPARAÎTRE TON CHARIOT", Color3.new(1, 1, 1), Color3.fromRGB(20, 24, 38))
	-- arche doree au-dessus de la zone de spawn
	hp(Vector3.new(2.4, 16, 2.4), CFrame.new(-28, 4.5, 19), GOLD, Enum.Material.Neon)
	hp(Vector3.new(2.4, 16, 2.4), CFrame.new( 28, 4.5, 19), GOLD, Enum.Material.Neon)
	hp(Vector3.new(60, 3, 2.4), CFrame.new(0, 12, 19), GOLD, Enum.Material.Neon)
	-- 3 pads colores : monter dessus = faire apparaitre son chariot (+ s'y asseoir)
	local spawnCols = { { -18, Color3.fromRGB(90, 220, 120) }, { 0, Color3.fromRGB(90, 200, 255) }, { 18, Color3.fromRGB(225, 120, 235) } }
	local cdpad = {}
	for _, e in ipairs(spawnCols) do
		local px, col = e[1], e[2]
		hp(Vector3.new(10.6, 1, 10.6), CFrame.new(px, -2.9, 16), Color3.fromRGB(16, 16, 22), Enum.Material.SmoothPlastic)
		local pad = hp(Vector3.new(8.8, 1.4, 8.8), CFrame.new(px, -2.4, 16), col, Enum.Material.Neon)
		local pl = Instance.new("PointLight"); pl.Range = 16; pl.Brightness = 2.6; pl.Color = col; pl.Parent = pad
		hp(Vector3.new(1.2, 6, 1.2), CFrame.new(px, 1, 16), col, Enum.Material.Neon)        -- mat
		hp(Vector3.new(4, 1.2, 1.2), CFrame.new(px, 3.4, 16), col, Enum.Material.Neon)      -- barre (fleche)
		pad.Touched:Connect(function(hit)
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if plr and not cdpad[plr] then cdpad[plr] = true; spawnPlayerCart(plr); task.delay(2.5, function() cdpad[plr] = nil end) end
		end)
	end
end
buildHub()

local function setCartAnchored(pc, anchored)
	if not pc then return end
	for _, p in ipairs(pc.cart:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = anchored end
	end
end

-- makeFreshState : RENVOIE un etat NEUF (un par joueur). Identique a l'ancien literal global.
-- Chaque joueur a donc ses propres pieces/XP/chariot/course (popups = table fraiche aussi).
-- (Le champ "world" a disparu : le monde est PARTAGE -> on lit currentWorldIndex.)
local function makeFreshState()
	return { distance = 0, speed = 0, checkpointDist = 0, derailing = false,
		score = 0, lap = 1, mult = 1, lastSeg = 0, combo = 0, comboT = 0, popups = {},
		etape = 1, wins = 0, curStage = 1, stageStart = 0, respawnDist = 0,
		maxSpeed = MAX_SPEED, vitLevel = 0, reb = 0, gainMul = 1,
		cartTier = 1,   -- chariot possede (1..#CARTS) ; achete avec des pieces
		-- XP et niveau de joueur (independant des pieces ; persiste entre les mondes)
		xp = 0, xpLevel = 1,
		-- paliers de boost de la course en cours (re-gagnes a chaque tour)
		boostLevel = 0, boostSpeed = 0, boostGrip = 0, maxReached = 0 }
end

-- vitesse max = vitesse du CHARIOT possede + boosts du parcours
local function recomputeMaxSpeed(pc)
	if not pc then return end
	local state = pc.state
	state.maxSpeed = CARTS[state.cartTier].max + state.boostSpeed
end

-- ===================== INTERFACE (HUD) =====================
local guis = {}

-- retrouve le pc (contexte joueur) a partir d'un ScreenGui (parente au PlayerGui du joueur).
local function pcFromGui(g)
	local pg = g and g.Parent            -- PlayerGui
	local plr = pg and pg.Parent         -- Player
	return plr and playerCarts[plr] or nil, plr
end

-- libelle court de l'adherence (le grip va de 0 a ~1)
local function gripLabel(gr)
	if gr < 0.1 then return "faible"
	elseif gr < 0.3 then return "correcte"
	elseif gr < 0.55 then return "bonne"
	elseif gr < 0.8 then return "très bonne"
	else return "excellente" end
end

-- refreshMenu : remplit la GRANDE CARTE du menu CHARIOTS pour le chariot feuillete
-- (state.menuView) : apercu 3D + barres de stats + etat + bouton d'action. Le bouton porte
-- un attribut "Action" (buy / close / none) lu par le client. Par defaut = PROCHAIN chariot.
local function refreshMenu(g)
	local pc = pcFromGui(g); if not pc then return end
	local state = pc.state
	local menu = g:FindFirstChild("CartMenu"); if not menu then return end
	local nextTier = math.min(state.cartTier + 1, #CARTS)
	local view = math.clamp(state.menuView or nextTier, 1, #CARTS)
	local c = CARTS[view]

	-- apercu 3D : on restyle le clone du chariot au niveau feuillete (couleur + forme) PUIS on
	-- RECADRE la camera du viewport sur la boite englobante -> tout le chariot tient dans la
	-- vignette (du petit Bois au gros Legendaire), vu de 3/4 avant.
	local pv = menu:FindFirstChild("PreviewCart", true)
	if pv then
		pv:PivotTo(CFrame.new(0, 0, 0))
		styleModel(pv, view)
		local vpf = menu:FindFirstChild("Preview", true)
		local vcam = vpf and vpf.CurrentCamera
		if vcam then
			local cfb, size = pv:GetBoundingBox()
			local maxe = math.max(size.X, size.Y, size.Z)
			local dir = Vector3.new(0.6, 0.42, -1).Unit   -- 3/4 avant-droit, un peu en hauteur
			vcam.CFrame = CFrame.lookAt(cfb.Position + dir * (maxe * 1.8 + 3), cfb.Position)
		end
	end

	local title = menu:FindFirstChild("CartTitle", true)
	if title then title.Text = string.upper(c.name) end
	local idx = menu:FindFirstChild("CartIdx", true)
	if idx then idx.Text = "chariot " .. view .. " / " .. #CARTS end

	local maxSpeed = CARTS[#CARTS].max
	local maxBrake = CARTS[#CARTS].brake
	local function setBar(fillName, valName, frac, txt)
		local fill = menu:FindFirstChild(fillName, true)
		if fill then fill.Size = UDim2.new(math.clamp(frac, 0.05, 1), 0, 1, 0) end
		local v = menu:FindFirstChild(valName, true)
		if v then v.Text = txt end
	end
	setBar("SpeedFill", "SpeedVal", c.max / maxSpeed,   c.max .. " km/h")
	setBar("GripFill",  "GripVal",  c.grip,             gripLabel(c.grip))
	setBar("BrakeFill", "BrakeVal", c.brake / maxBrake, tostring(c.brake))

	local line = menu:FindFirstChild("StateLine", true)
	local buy  = menu:FindFirstChild("MenuBuy")
	local GREEN = Color3.fromRGB(40, 170, 75)
	local GREY  = Color3.fromRGB(70, 74, 88)
	if view <= state.cartTier then
		-- chariot DEJA possede (ou de depart) : le bouton = PRENDRE/JOUER (ferme le menu)
		if line then
			if c.price == 0 then line.Text = "🎁 chariot de départ — GRATUIT"; line.TextColor3 = Color3.fromRGB(130, 230, 150)
			elseif view == state.cartTier then line.Text = "🚂 ton chariot actuel"; line.TextColor3 = Color3.fromRGB(255, 225, 90)
			else line.Text = "✅ déjà possédé"; line.TextColor3 = Color3.fromRGB(120, 210, 120) end
		end
		if buy then
			buy.Text = (c.price == 0) and "🎁 PRENDRE — GRATUIT" or "▶ JOUER"
			buy.BackgroundColor3 = GREEN; buy.AutoButtonColor = true; buy.Active = true
			buy:SetAttribute("Action", "close")
		end
	elseif view == state.cartTier + 1 then
		if line then line.Text = "Prix : " .. c.price .. " pièces"; line.TextColor3 = Color3.fromRGB(120, 220, 255) end
		if buy then
			if state.score >= c.price then
				buy.Text = "⬆ ACHETER — " .. c.price .. " pièces"
				buy.BackgroundColor3 = GREEN; buy.AutoButtonColor = true; buy.Active = true
				buy:SetAttribute("Action", "buy")
			else
				buy.Text = "manque " .. (c.price - math.floor(state.score)) .. " pièces"
				buy.BackgroundColor3 = Color3.fromRGB(190, 120, 40); buy.AutoButtonColor = false; buy.Active = false
				buy:SetAttribute("Action", "none")
			end
		end
	else
		if line then line.Text = "🔒 verrouillé — " .. c.price .. " pièces"; line.TextColor3 = Color3.fromRGB(160, 160, 172) end
		if buy then
			buy.Text = "🔒 achète les précédents d'abord"
			buy.BackgroundColor3 = GREY; buy.AutoButtonColor = false; buy.Active = false
			buy:SetAttribute("Action", "none")
		end
	end
end

local function makeGui(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ChariotHUD"
	gui.ResetOnSpawn = false
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Size = UDim2.new(0,400,0,40)
	info.Position = UDim2.new(0.5,-200,0,10)
	info.BackgroundTransparency = 0.3
	info.BackgroundColor3 = Color3.fromRGB(0,0,0)
	info.TextColor3 = Color3.fromRGB(255,255,255)
	info.TextScaled = true
	info.Font = Enum.Font.GothamBold
	info.Text = "Marche sur le pad ▶ JOUER pour monter dans le chariot   |   Z = avancer   S = freiner"
	info.Parent = gui
	local center = Instance.new("TextLabel")
	center.Name = "Center"
	center.Size = UDim2.new(0,680,0,90)
	center.Position = UDim2.new(0.5,-340,0.34,0)
	center.BackgroundTransparency = 1
	center.TextColor3 = Color3.fromRGB(255,80,80)
	center.TextScaled = true
	center.Font = Enum.Font.GothamBlack
	center.Text = ""
	center.Parent = gui
	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.Size = UDim2.new(0, 320, 0, 72)
	score.Position = UDim2.new(0.5, -160, 0, 56)
	score.BackgroundTransparency = 1
	score.TextColor3 = Color3.fromRGB(255, 240, 90)
	score.TextStrokeTransparency = 0.35
	score.TextScaled = true
	score.Font = Enum.Font.GothamBlack
	score.Text = "0"
	score.Visible = false
	score.Parent = gui
	local etape = Instance.new("TextLabel")
	etape.Name = "Etape"
	etape.AnchorPoint = Vector2.new(1, 0)
	etape.Size = UDim2.new(0, 200, 0, 30)
	etape.Position = UDim2.new(1, -16, 0, 218)   -- a DROITE, sous le panneau pieces/XP
	etape.BackgroundTransparency = 1
	etape.TextColor3 = Color3.fromRGB(120, 235, 255)
	etape.TextStrokeTransparency = 0.3
	etape.TextScaled = true
	etape.TextXAlignment = Enum.TextXAlignment.Right
	etape.Font = Enum.Font.GothamBlack
	etape.Text = "ÉTAPE 1"
	etape.Visible = false
	etape.Parent = gui
	local wins = Instance.new("TextLabel")
	wins.Name = "Wins"
	wins.Size = UDim2.new(0, 220, 0, 44)
	wins.Position = UDim2.new(0, 12, 0, 12)
	wins.BackgroundTransparency = 0.35
	wins.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	wins.TextColor3 = Color3.fromRGB(255, 215, 0)
	wins.TextScaled = true
	wins.Font = Enum.Font.GothamBold
	wins.Text = "🏆 Wins : 0"
	wins.Visible = false
	wins.Parent = gui
	-- ===== COMPTEUR DE VITESSE a aiguille (km/h), en bas a droite =====
	local gauge = Instance.new("Frame")
	gauge.Name = "Gauge"
	gauge.AnchorPoint = Vector2.new(1, 1)
	gauge.Position = UDim2.new(1, -18, 1, -18)
	gauge.Size = UDim2.new(0, 150, 0, 150)
	gauge.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	gauge.BackgroundTransparency = 0.2
	gauge.BorderSizePixel = 0
	gauge.Visible = false
	gauge.Parent = gui
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1, 0); gc.Parent = gauge
	local gsk = Instance.new("UIStroke"); gsk.Color = Color3.fromRGB(120, 200, 255); gsk.Thickness = 3; gsk.Parent = gauge
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 1)
	needle.Position = UDim2.new(0.5, 0, 0.5, 0)
	needle.Size = UDim2.new(0, 5, 0, 58)
	needle.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	needle.BorderSizePixel = 0
	needle.Rotation = -120
	needle.Parent = gauge
	local nc = Instance.new("UICorner"); nc.CornerRadius = UDim.new(1, 0); nc.Parent = needle
	local moyeu = Instance.new("Frame")
	moyeu.AnchorPoint = Vector2.new(0.5, 0.5); moyeu.Position = UDim2.new(0.5, 0, 0.5, 0)
	moyeu.Size = UDim2.new(0, 16, 0, 16); moyeu.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	moyeu.BorderSizePixel = 0; moyeu.Parent = gauge
	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(1, 0); mc.Parent = moyeu
	local kmh = Instance.new("TextLabel")
	kmh.Name = "Kmh"
	kmh.AnchorPoint = Vector2.new(0.5, 0); kmh.Position = UDim2.new(0.5, 0, 0.6, 0)
	kmh.Size = UDim2.new(0.8, 0, 0, 32); kmh.BackgroundTransparency = 1
	kmh.TextColor3 = Color3.fromRGB(255, 255, 255); kmh.Font = Enum.Font.GothamBlack
	kmh.TextScaled = true; kmh.Text = "0"; kmh.Parent = gauge
	local unit = Instance.new("TextLabel")
	unit.AnchorPoint = Vector2.new(0.5, 0); unit.Position = UDim2.new(0.5, 0, 0.84, 0)
	unit.Size = UDim2.new(0.6, 0, 0, 14); unit.BackgroundTransparency = 1
	unit.TextColor3 = Color3.fromRGB(170, 190, 220); unit.Font = Enum.Font.GothamBold
	unit.TextScaled = true; unit.Text = "km/h"; unit.Parent = gauge
	local cartName = Instance.new("TextLabel")
	cartName.Name = "CartName"
	cartName.AnchorPoint = Vector2.new(1, 1); cartName.Position = UDim2.new(1, -18, 1, -174)
	cartName.Size = UDim2.new(0, 210, 0, 26); cartName.BackgroundTransparency = 0.4
	cartName.BackgroundColor3 = Color3.fromRGB(18, 20, 28); cartName.BorderSizePixel = 0
	cartName.TextColor3 = Color3.fromRGB(120, 220, 255); cartName.Font = Enum.Font.GothamBold
	cartName.TextScaled = true; cartName.Text = "🛒 Chariot Bois"; cartName.Visible = false
	cartName.Parent = gui
	-- ===== BOUTON "AMELIORER" a l'ecran (a droite) : OUVRE le menu CHARIOTS =====
	local upBtn = Instance.new("TextButton")
	upBtn.Name = "UpgradeBtn"
	upBtn.AnchorPoint = Vector2.new(1, 0.5)
	upBtn.Position = UDim2.new(1, -16, 0.5, 0)
	upBtn.Size = UDim2.new(0, 168, 0, 58)
	upBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	upBtn.BackgroundTransparency = 0.05
	upBtn.AutoButtonColor = true
	upBtn.BorderSizePixel = 0
	upBtn.Font = Enum.Font.GothamBlack
	upBtn.TextScaled = true
	upBtn.TextColor3 = Color3.fromRGB(120, 220, 255)
	upBtn.Text = "🛒 AMÉLIORER"
	upBtn.Parent = gui
	local ubc = Instance.new("UICorner"); ubc.CornerRadius = UDim.new(0, 14); ubc.Parent = upBtn
	local ubs = Instance.new("UIStroke"); ubs.Color = Color3.fromRGB(120, 200, 255); ubs.Thickness = 2.5; ubs.Parent = upBtn
	local ubp = Instance.new("UIPadding")
	ubp.PaddingLeft = UDim.new(0, 12); ubp.PaddingRight = UDim.new(0, 12)
	ubp.PaddingTop = UDim.new(0, 12); ubp.PaddingBottom = UDim.new(0, 12); ubp.Parent = upBtn
	-- ===== PANNEAU PIECES + XP (en haut a droite, toujours visible) =====
	local wp = Instance.new("Frame")
	wp.Name = "WalletPanel"
	wp.AnchorPoint = Vector2.new(1, 0)
	wp.Position = UDim2.new(1, -16, 0, 104)   -- descendu sous la liste des joueurs (haut a droite)
	wp.Size = UDim2.new(0, 210, 0, 104)
	wp.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
	wp.BackgroundTransparency = 0.08
	wp.BorderSizePixel = 0
	wp.Parent = gui
	local wpc = Instance.new("UICorner"); wpc.CornerRadius = UDim.new(0, 14); wpc.Parent = wp
	local wps = Instance.new("UIStroke"); wps.Color = Color3.fromRGB(120, 200, 255); wps.Thickness = 2; wps.Parent = wp
	-- ligne 1 : icone pieces + montant en gros
	local coinsLbl = Instance.new("TextLabel")
	coinsLbl.Name = "CoinsLbl"
	coinsLbl.Position = UDim2.new(0, 14, 0, 10)
	coinsLbl.Size = UDim2.new(1, -28, 0, 38)
	coinsLbl.BackgroundTransparency = 1
	coinsLbl.Font = Enum.Font.GothamBlack
	coinsLbl.TextScaled = true
	coinsLbl.TextXAlignment = Enum.TextXAlignment.Left
	coinsLbl.TextColor3 = Color3.fromRGB(255, 225, 80)
	coinsLbl.TextStrokeTransparency = 0.3
	coinsLbl.Text = "🪙  0"
	coinsLbl.Parent = wp
	-- separateur
	local sep = Instance.new("Frame")
	sep.Position = UDim2.new(0, 14, 0, 52); sep.Size = UDim2.new(1, -28, 0, 2)
	sep.BackgroundColor3 = Color3.fromRGB(60, 65, 88); sep.BorderSizePixel = 0; sep.Parent = wp
	-- ligne 2 : label XP (niveau + xp/total)
	local xpLbl = Instance.new("TextLabel")
	xpLbl.Name = "XPLbl"
	xpLbl.Position = UDim2.new(0, 14, 0, 57)
	xpLbl.Size = UDim2.new(1, -28, 0, 20)
	xpLbl.BackgroundTransparency = 1
	xpLbl.Font = Enum.Font.GothamBold
	xpLbl.TextScaled = true
	xpLbl.TextXAlignment = Enum.TextXAlignment.Left
	xpLbl.TextColor3 = Color3.fromRGB(200, 220, 255)
	xpLbl.Text = "⭐ Niv. 1   0 / 400"
	xpLbl.Parent = wp
	-- barre de progression XP
	local xpBg = Instance.new("Frame")
	xpBg.Position = UDim2.new(0, 14, 0, 80); xpBg.Size = UDim2.new(1, -28, 0, 14)
	xpBg.BackgroundColor3 = Color3.fromRGB(40, 44, 60); xpBg.BorderSizePixel = 0; xpBg.Parent = wp
	local xpBgc = Instance.new("UICorner"); xpBgc.CornerRadius = UDim.new(1, 0); xpBgc.Parent = xpBg
	local xpFill = Instance.new("Frame")
	xpFill.Name = "XPFill"; xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(130, 200, 255); xpFill.BorderSizePixel = 0; xpFill.Parent = xpBg
	local xpFc = Instance.new("UICorner"); xpFc.CornerRadius = UDim.new(1, 0); xpFc.Parent = xpFill
	-- ===== MENU CHARIOTS : GRANDE CARTE (focus) avec APERCU 3D du chariot =====
	-- Fleches ◀ ▶ = feuilleter ; le grand bouton agit selon l'attribut "Action" (buy/close) ; ✖ ferme.
	local PANEL  = Color3.fromRGB(22, 24, 34)
	local ACCENT = Color3.fromRGB(120, 200, 255)
	local menu = Instance.new("Frame")
	menu.Name = "CartMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5); menu.Position = UDim2.new(0.5, 0, 0.5, 0)
	menu.Size = UDim2.new(0, 460, 0, 458)
	menu.BackgroundColor3 = PANEL; menu.BackgroundTransparency = 0.03
	menu.BorderSizePixel = 0; menu.Visible = false; menu.Parent = gui
	local mco = Instance.new("UICorner"); mco.CornerRadius = UDim.new(0, 16); mco.Parent = menu
	local mst = Instance.new("UIStroke"); mst.Color = ACCENT; mst.Thickness = 3; mst.Parent = menu
	local mtitle = Instance.new("TextLabel")
	mtitle.Size = UDim2.new(1, -70, 0, 40); mtitle.Position = UDim2.new(0, 16, 0, 12)
	mtitle.BackgroundTransparency = 1; mtitle.Font = Enum.Font.GothamBlack; mtitle.TextScaled = true
	mtitle.TextXAlignment = Enum.TextXAlignment.Left
	mtitle.TextColor3 = ACCENT; mtitle.Text = "🛒 CHARIOTS"; mtitle.Parent = menu
	local mclose = Instance.new("TextButton")
	mclose.Name = "MenuClose"; mclose.AnchorPoint = Vector2.new(1, 0); mclose.Position = UDim2.new(1, -12, 0, 12)
	mclose.Size = UDim2.new(0, 40, 0, 40); mclose.BackgroundColor3 = Color3.fromRGB(210, 70, 70); mclose.BorderSizePixel = 0
	mclose.Font = Enum.Font.GothamBlack; mclose.TextScaled = true; mclose.TextColor3 = Color3.new(1, 1, 1); mclose.Text = "✖"; mclose.Parent = menu
	local mcc = Instance.new("UICorner"); mcc.CornerRadius = UDim.new(0, 10); mcc.Parent = mclose
	-- ---- la grande carte ----
	local card = Instance.new("Frame")
	card.Name = "Card"; card.Position = UDim2.new(0, 16, 0, 60); card.Size = UDim2.new(1, -32, 0, 322)
	card.BackgroundColor3 = Color3.fromRGB(30, 33, 46); card.BorderSizePixel = 0; card.Parent = menu
	local cardc = Instance.new("UICorner"); cardc.CornerRadius = UDim.new(0, 12); cardc.Parent = card
	-- APERCU 3D : un ViewportFrame avec un CLONE du chariot, restyle par refreshMenu selon le niveau
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"; vp.Position = UDim2.new(0, 14, 0, 14); vp.Size = UDim2.new(0, 184, 0, 150)
	vp.BackgroundColor3 = Color3.fromRGB(16, 18, 28); vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(150, 150, 160); vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5); vp.Parent = card
	local vpc = Instance.new("UICorner"); vpc.CornerRadius = UDim.new(0, 10); vpc.Parent = vp
	local vps = Instance.new("UIStroke"); vps.Color = ACCENT; vps.Thickness = 1.5; vps.Transparency = 0.4; vps.Parent = vp
	local vpCam = Instance.new("Camera")
	vpCam.Name = "PreviewCam"
	vpCam.CFrame = CFrame.lookAt(Vector3.new(8, 5, -10), Vector3.new(0, 0.6, 0))
	vpCam.Parent = vp; vp.CurrentCamera = vpCam
	local pv = templateCart:Clone()   -- apercu : clone du chariot MODELE (plus de chariot vivant requis)
	pv.Name = "PreviewCart"
	local pseat = pv:FindFirstChild("Pilote"); if pseat then pseat:Destroy() end
	for _, d in ipairs(pv:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("ParticleEmitter") or d:IsA("SurfaceGui") then d:Destroy() end
	end
	pv:PivotTo(CFrame.new(0, 0, 0))
	pv.Parent = vp
	-- nom + index (a droite de l'apercu)
	local cTitle = Instance.new("TextLabel")
	cTitle.Name = "CartTitle"; cTitle.Position = UDim2.new(0, 210, 0, 24); cTitle.Size = UDim2.new(1, -226, 0, 36)
	cTitle.BackgroundTransparency = 1; cTitle.Font = Enum.Font.GothamBlack; cTitle.TextScaled = true
	cTitle.TextXAlignment = Enum.TextXAlignment.Left; cTitle.TextColor3 = Color3.new(1, 1, 1); cTitle.Text = "CHARIOT FER"; cTitle.Parent = card
	local cIdx = Instance.new("TextLabel")
	cIdx.Name = "CartIdx"; cIdx.Position = UDim2.new(0, 212, 0, 62); cIdx.Size = UDim2.new(1, -226, 0, 18)
	cIdx.BackgroundTransparency = 1; cIdx.Font = Enum.Font.Gotham; cIdx.TextScaled = true
	cIdx.TextXAlignment = Enum.TextXAlignment.Left; cIdx.TextColor3 = Color3.fromRGB(150, 160, 180); cIdx.Text = "chariot 2 / 10"; cIdx.Parent = card
	-- barres de stats (sous l'apercu, pleine largeur)
	local function statBar(yOff, label, fillName, valName, fillColor)
		local lbl = Instance.new("TextLabel")
		lbl.Position = UDim2.new(0, 16, 0, yOff); lbl.Size = UDim2.new(0, 92, 0, 20)
		lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextColor3 = Color3.fromRGB(205, 215, 235); lbl.Text = label; lbl.Parent = card
		local bg = Instance.new("Frame")
		bg.Position = UDim2.new(0, 112, 0, yOff); bg.Size = UDim2.new(1, -210, 0, 20)
		bg.BackgroundColor3 = Color3.fromRGB(46, 50, 68); bg.BorderSizePixel = 0; bg.Parent = card
		local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(1, 0); bgc.Parent = bg
		local fill = Instance.new("Frame")
		fill.Name = fillName; fill.Size = UDim2.new(0.3, 0, 1, 0)
		fill.BackgroundColor3 = fillColor; fill.BorderSizePixel = 0; fill.Parent = bg
		local fillc = Instance.new("UICorner"); fillc.CornerRadius = UDim.new(1, 0); fillc.Parent = fill
		local val = Instance.new("TextLabel")
		val.Name = valName; val.AnchorPoint = Vector2.new(1, 0); val.Position = UDim2.new(1, -12, 0, yOff); val.Size = UDim2.new(0, 84, 0, 20)
		val.BackgroundTransparency = 1; val.Font = Enum.Font.GothamBold; val.TextScaled = true
		val.TextXAlignment = Enum.TextXAlignment.Right; val.TextColor3 = Color3.new(1, 1, 1); val.Text = ""; val.Parent = card
	end
	statBar(184, "Vitesse",   "SpeedFill", "SpeedVal", Color3.fromRGB(90, 200, 255))
	statBar(220, "Adhérence", "GripFill",  "GripVal",  Color3.fromRGB(90, 220, 120))
	statBar(256, "Frein",     "BrakeFill", "BrakeVal", Color3.fromRGB(255, 170, 60))
	local stateLine = Instance.new("TextLabel")
	stateLine.Name = "StateLine"; stateLine.Position = UDim2.new(0, 16, 0, 290); stateLine.Size = UDim2.new(1, -32, 0, 28)
	stateLine.BackgroundTransparency = 1; stateLine.Font = Enum.Font.GothamBlack; stateLine.TextScaled = true
	stateLine.TextXAlignment = Enum.TextXAlignment.Left; stateLine.TextColor3 = ACCENT; stateLine.Text = "Prix : 150 pièces"; stateLine.Parent = card
	-- ---- fleches de navigation + bouton d'action (en bas) ----
	local function navBtn(name, xPos, txt)
		local b = Instance.new("TextButton")
		b.Name = name; b.Position = UDim2.new(0, xPos, 0, 392); b.Size = UDim2.new(0, 54, 0, 54)
		b.BackgroundColor3 = Color3.fromRGB(40, 44, 60); b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBlack; b.TextScaled = true; b.TextColor3 = ACCENT; b.Text = txt; b.Parent = menu
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = b
		local bs = Instance.new("UIStroke"); bs.Color = ACCENT; bs.Thickness = 1.5; bs.Transparency = 0.3; bs.Parent = b
	end
	navBtn("MenuPrev", 16, "◀")
	navBtn("MenuNext", 390, "▶")
	local mbuy = Instance.new("TextButton")
	mbuy.Name = "MenuBuy"; mbuy.Position = UDim2.new(0, 82, 0, 392); mbuy.Size = UDim2.new(0, 296, 0, 54)
	mbuy.BackgroundColor3 = Color3.fromRGB(40, 170, 75); mbuy.BorderSizePixel = 0
	mbuy.Font = Enum.Font.GothamBlack; mbuy.TextScaled = true; mbuy.TextColor3 = Color3.new(1, 1, 1); mbuy.Text = "⬆ ACHETER"; mbuy.Parent = menu
	mbuy:SetAttribute("Action", "buy")
	local mbc2 = Instance.new("UICorner"); mbc2.CornerRadius = UDim.new(0, 12); mbc2.Parent = mbuy
	local mbp = Instance.new("UIPadding"); mbp.PaddingTop = UDim.new(0, 12); mbp.PaddingBottom = UDim.new(0, 12); mbp.Parent = mbuy
	gui.Parent = player:WaitForChild("PlayerGui")
	refreshMenu(gui)
	return gui
end

-- HUD de jeu (Etape / score) visible UNIQUEMENT quand on conduit (cache dans le hub).
-- connectSeat : branche le handler "Occupant" sur le SIEGE D'UN JOUEUR (pc.seat). Chaque
-- chariot a le sien -> on ne touche QUE le HUD de SON proprietaire (sinon on cacherait le
-- HUD d'un autre joueur qui conduit son propre chariot).
local function connectSeat(pc)
	local seat = pc.seat
	local state = pc.state
	pc.conns = pc.conns or {}
	local conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local owner = pc.player
		-- un nouveau conducteur monte (et ce n'est PAS la reinstallation apres un
		-- deraillement, qui doit rester au checkpoint) : on demarre une course neuve,
		-- distance + boosts remis a zero. Les Wins / Etapes, eux, sont conserves.
		if occ and not state.derailing then
			state.distance = 0; state.speed = 0; state.lastSeg = 0
			state.curStage = 1; state.stageStart = 0; state.respawnDist = 0
			state.grip = 0; state.lean = 0; state.lastLean = nil
			state.boostLevel = 0; state.boostSpeed = 0; state.boostGrip = 0; state.maxReached = 0
			recomputeMaxSpeed(pc)
		end
		local g = owner and guis[owner]
		if g then
			local on = occ ~= nil
			g.Score.Visible = false   -- plus de score au CENTRE (il est deja en haut a droite)
			g.Etape.Visible = on
			g.Gauge.Visible = on        -- compteur de vitesse
			g.CartName.Visible = on     -- nom du chariot
		end
	end)
	table.insert(pc.conns, conn)
end

-- ===================== CREATION / APPARITION D'UN CHARIOT JOUEUR =====================
-- makePlayerCart : fabrique le contexte (pc) D'UN joueur : son chariot + siege + effets + etat.
-- Le chariot N'EST PAS encore parente au monde (pc.spawned = false) -> il n'apparait qu'au
-- declenchement (spawnPlayerCart). Branche aussi le handler du siege. Idempotent (renvoie le pc existant).
function makePlayerCart(player)
	if playerCarts[player] then return playerCarts[player] end
	local cart, seat = buildCart()
	cart.Name = "Chariot_" .. player.UserId
	local pc = {
		player = player,
		cart = cart,
		seat = seat,
		base = cart.PrimaryPart,
		spawned = false,
		conns = {},
	}
	makeCartFX(pc)                 -- son / etincelles / halo legendaire (par chariot)
	pc.state = makeFreshState()
	-- MODE TEST : on demarre riche pour essayer tous les chariots sans farmer (par joueur).
	if DEBUG then pc.state.score = 1000000 end
	playerCarts[player] = pc
	applyCartStyle(pc, 1)          -- look + son du chariot de depart
	connectSeat(pc)               -- HUD du proprietaire visible quand il conduit son chariot
	return pc
end

-- spawnPlayerCart : fait APPARAITRE le chariot du joueur (le parente au monde, le pose au depart),
-- remet sa course a zero et y assoit le joueur. Cree le pc au besoin.
function spawnPlayerCart(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pc = playerCarts[player] or makePlayerCart(player)
	-- VOIE DE DEPART : on attribue la 1ere voie libre (gardee pour la session) -> chacun son cote
	if not pc.laneX then
		local taken = {}
		for _, o in pairs(playerCarts) do if o ~= pc and o.laneSlot then taken[o.laneSlot] = true end end
		local slot = 1
		for i = 1, #START_LANE_OFFSETS do if not taken[i] then slot = i; break end end
		pc.laneSlot = slot; pc.laneX = START_LANE_OFFSETS[slot]
	end
	local cart, seat = pc.cart, pc.seat
	if cart.Parent ~= Workspace then cart.Parent = Workspace end
	cart:PivotTo((renderAtDistance(0)) * CFrame.new(pc.laneX, 0, 0))
	pc.spawned = true
	-- course remise a zero (comme le faisait l'ancien handler du siege a l'embarquement)
	local state = pc.state
	state.distance = 0; state.speed = 0; state.lastSeg = 0
	state.curStage = 1; state.stageStart = 0; state.respawnDist = 0
	state.grip = 0; state.lean = 0; state.lastLean = nil
	state.boostLevel = 0; state.boostSpeed = 0; state.boostGrip = 0; state.maxReached = 0
	state.derailing = false; state.airborne = false
	recomputeMaxSpeed(pc)
	-- on place le perso sur le chariot puis on l'assoit
	char:PivotTo((renderAtDistance(0)) * CFrame.new(pc.laneX, 3, 0))
	task.wait(0.12)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then seat:Sit(hum) end
end

local function showCenter(player, text, color)
	local g = guis[player]; if not g then return end
	g.Center.Text = text
	if color then g.Center.TextColor3 = color end
end

local function flashCenter(player, text, color, dur)
	showCenter(player, text, color)
	task.delay(dur or 1.2, function()
		local g = guis[player]
		if g and g.Center.Text == text then g.Center.Text = "" end
	end)
end

-- ===================== SCORE / EFFET SATISFAISANT (+1, +1, ...) =====================
local dingSound = Instance.new("Sound")
dingSound.Name = "DingChariot"
dingSound.SoundId = SOUND_DING
dingSound.Volume = 0.28
dingSound.Parent = SoundService

-- son joue a chaque palier de COIN_STEP pieces (pas en boucle)
local coinSound = Instance.new("Sound")
coinSound.Name = "CoinChariot"
coinSound.SoundId = COIN_SOUND
coinSound.Volume = 0.45
coinSound.Parent = SoundService

local function formatScore(n)
	if n >= 1e9 then return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(math.floor(n)) end
end

local function setScore(player)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local g = guis[player]; if not g then return end
	g.Score.Text = formatScore(state.score)
end

-- setWallet : met a jour le panneau pièces + XP en haut a droite.
local function setWallet(player)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local g = guis[player]; if not g then return end
	local wp = g:FindFirstChild("WalletPanel")
	if not wp then return end
	-- pieces
	local cl = wp:FindFirstChild("CoinsLbl")
	if cl then cl.Text = "🪙  " .. formatScore(state.score) end
	-- XP : barre de progression + label
	local needed = state.xpLevel * XP_LEVEL_BASE
	local frac   = math.clamp(state.xp / needed, 0, 1)
	local xf = wp:FindFirstChild("XPFill")
	if xf then xf.Size = UDim2.new(frac, 0, 1, 0) end
	local xl = wp:FindFirstChild("XPLbl")
	if xl then xl.Text = "⭐ Niv. " .. state.xpLevel .. "   " .. state.xp .. " / " .. needed end
end

-- addXp : donne des XP au joueur et verifie le passage de niveau.
local function addXp(player, amount)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	state.xp = state.xp + amount
	local levelled = false
	while state.xp >= state.xpLevel * XP_LEVEL_BASE do
		state.xp = state.xp - state.xpLevel * XP_LEVEL_BASE
		state.xpLevel = state.xpLevel + 1
		levelled = true
	end
	if levelled and player then
		flashCenter(player, "⭐ NIVEAU " .. state.xpLevel .. " !   tu gagnes + de pièces 🪙", Color3.fromRGB(255, 220, 80), 2.4)
	end
	setWallet(player)
end

-- un petit "+N" jaune qui apparait et monte en s'estompant
local function spawnPopup(player, n)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local g = guis[player]; if not g then return end
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 220, 0, 60)
	lbl.Position = UDim2.new(0.5, -110 + math.random(-70, 70), 0.5, math.random(-30, 50))
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = Color3.fromRGB(255, 240, 90)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = "+" .. formatScore(n)
	lbl.Parent = g
	table.insert(state.popups, { lbl = lbl, t = 0 })
end

local function updatePopups(player, dt)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	for i = #state.popups, 1, -1 do
		local pu = state.popups[i]
		pu.t = pu.t + dt
		local k = pu.t / 0.8
		if k >= 1 then
			pu.lbl:Destroy()
			table.remove(state.popups, i)
		else
			pu.lbl.Position = pu.lbl.Position - UDim2.new(0, 0, 0, 80 * dt)
			pu.lbl.TextTransparency = k
			pu.lbl.TextStrokeTransparency = 0.2 + k * 0.8
		end
	end
end

-- updateLeaderstats : ecrit le classement (Pieces/Vitesse/Wins/Renaissance) DU joueur depuis
-- son pc.state. Appele a chaque gain (award/completeStage/renaissance) et une fois par frame.
local function updateLeaderstats(player)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Wins.Value = state.wins
		ls.Pieces.Value = math.floor(state.score)
		ls.Vitesse.Value = math.floor(state.maxSpeed)
		ls.Renaissance.Value = state.reb
	end
end

local function award(player, n)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local before = state.score
	state.score = state.score + n
	-- son de pieces a chaque palier de COIN_STEP (ex: 500, 1000...) -> PAS en boucle.
	-- (joue seulement quand TON vrai son est mis ; sinon silence, pas de "ding".)
	if COIN_SOUND_READY and math.floor(state.score / COIN_STEP) > math.floor(before / COIN_STEP) then
		coinSound:Play()
	end
	if player then
		spawnPopup(player, n)
		setScore(player)
		setWallet(player)   -- panneau pièces+XP toujours a jour
		updateLeaderstats(player)
	end
end

-- ===================== ETAPES : completion d'une etape (= 1 Win) =====================
local trophyData = {}  -- conserve pour le nettoyage joueur (PlayerRemoving)
local function completeStage(player)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	state.wins = state.wins + 1
	state.etape = state.etape + 1
	award(player, 30 * state.etape * state.gainMul)   -- bonus de pieces pour l'etape finie
	addXp(player, XP_STAGE_BONUS)                     -- bonus XP pour l'etape
	if player then
		local g = guis[player]
		if g then
			g.Wins.Text = "🏆 Wins : " .. state.wins
			g.Etape.Text = "ÉTAPE " .. state.etape
		end
		flashCenter(player, "ÉTAPE " .. (state.etape - 1) .. " TERMINEE !   +1 Win 🏆", Color3.fromRGB(120, 255, 140), 2.6)
		updateLeaderstats(player)
	end
	dingSound.PlaybackSpeed = 0.7
	dingSound:Play()
end

local function updateInfo(player, seg, speed)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local g = guis[player]; if not g then return end
	local meta = segMeta[seg]
	local maxTxt = meta.derailable and tostring(meta.safe) or "libre"
	g.Info.Text = string.format("Zone : %s   |   Vitesse : %d   |   Max sur : %s",
		ZONES[zoneForSegment(seg)].name, math.floor(speed), maxTxt)
	-- COMPTEUR a aiguille : l'aiguille balaie -120deg (0) -> +120deg (vitesse max du chariot)
	if g.Gauge then
		local frac = math.clamp(math.abs(speed) / math.max(state.maxSpeed, 1), 0, 1)
		g.Gauge.Needle.Rotation = -120 + 240 * frac
		g.Gauge.Kmh.Text = tostring(math.floor(math.abs(speed) * KMH))
		g.CartName.Text = "🛒 " .. CARTS[state.cartTier].name .. "  (" .. CARTS[state.cartTier].max .. " km/h)"
	end
end

-- ===================== APPARITION (HUB) + CLASSEMENT (leaderstats) =====================
-- On apparait dans le hub (SpawnLocation), puis pad "JOUER" pour monter dans le chariot.
-- leaderstats Wins/Vitesse -> liste classement native de Roblox (en haut a droite).
-- A l'apparition, on FORCE le joueur dans le hub. Pourquoi : le SpawnLocation du hub
-- est cree tard (apres tout le terrain + le decor). Au lancement, le perso peut donc
-- apparaitre a l'origine du monde (0,0,0) -> "dans l'herbe", ~44 studs devant et ~10
-- sous le hub, AVANT meme que ce SpawnLocation existe. On replace donc le perso sur le
-- point d'apparition du hub des que son corps est charge (et une 2e fois 0.15s apres,
-- au cas ou le moteur le repositionne juste apres son apparition).
local function placeInHub(char)
	if not char:FindFirstChild("HumanoidRootPart") then
		char:WaitForChild("HumanoidRootPart", 5)
	end
	local function toHub()
		if char.Parent and char.PrimaryPart then
			char:PivotTo((renderAtDistance(0)) * CFrame.new(0, 2, 56))
		end
	end
	toHub()
	task.delay(0.15, toHub)
	if char.PrimaryPart then
		local p = char:GetPivot().Position
		dbg(string.format("APPARITION joueur -> hub (%.0f, %.0f, %.0f)", p.X, p.Y, p.Z))
	end
	-- PREMIER spawn de la partie : on ouvre le menu CHARIOTS sur le 1er chariot (gratuit) pour
	-- accueillir le joueur. state.welcomed (par joueur) evite de le rouvrir aux apparitions suivantes.
	local plr = Players:GetPlayerFromCharacter(char)
	local pc = plr and playerCarts[plr]
	if pc and not pc.state.welcomed then
		pc.state.welcomed = true
		task.delay(1.2, function()
			pc.state.menuView = 1
			local g = plr and guis[plr]
			if g then
				refreshMenu(g)
				local m = g:FindFirstChild("CartMenu")
				if m then m.Visible = true end
			end
		end)
	end
end

local function setupPlayer(player)
	makePlayerCart(player)   -- cree le contexte (pc.state) AVANT le HUD : le menu/wallet en ont besoin
	guis[player] = makeGui(player)
	setWallet(player)   -- initialise le panneau pièces + XP (le HUD existe maintenant)
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	for _, n in ipairs({ "Pieces", "Vitesse", "Wins", "Renaissance" }) do
		local v = Instance.new("IntValue"); v.Name = n; v.Parent = ls
	end
	player.CharacterAdded:Connect(placeInHub)
	if player.Character then task.spawn(placeInHub, player.Character) end
end
Players.PlayerAdded:Connect(setupPlayer)
-- nettoyage joueur : detruit son chariot, debranche ses connexions, oublie son contexte.
Players.PlayerRemoving:Connect(function(player)
	local pc = playerCarts[player]
	if pc then
		if pc.conns then for _, c in ipairs(pc.conns) do c:Disconnect() end end
		if pc.cart then pc.cart:Destroy() end
		playerCarts[player] = nil
	end
	guis[player] = nil
	trophyData[player] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do
	if not playerCarts[p] then setupPlayer(p) end
end

-- ===================== DERAILLEMENT (chute physique) =====================
local function derail(player, fallSide, launch)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local cart, seat = pc.cart, pc.seat
	local sparkEmitter = pc.sparkEmitter
	if state.derailing then return end
	state.derailing = true
	if sparkEmitter then sparkEmitter.Enabled = false end

	local cf = cart:GetPivot()
	local side = fallSide or ((math.random() < 0.5) and 1 or -1)

	setCartAnchored(pc, false)
	local base = cart.PrimaryPart
	if base then
		if launch then
			-- DECOLLAGE : pris la bosse trop vite -> le chariot part en AVANT (horizontal)
			-- et surtout EN L'AIR (forte poussee verticale), puis retombe. On IGNORE la
			-- composante vers le bas de la voie pour qu'il s'envole vraiment.
			local fwd = cf.LookVector
			local horiz = Vector3.new(fwd.X, 0, fwd.Z)
			horiz = (horiz.Magnitude > 0.01) and horiz.Unit or Vector3.new(0, 0, -1)
			base.AssemblyLinearVelocity = horiz * (state.speed * 0.9) + Vector3.new(0, math.max(state.speed * 1.1, 65), 0)
			base.AssemblyAngularVelocity = cf.RightVector * 4
		else
			-- perte d'adherence en virage : il bascule sur le cote et tombe (pas d'a-coup).
			base.AssemblyLinearVelocity = cf.LookVector * (state.speed * 0.5) + cf.RightVector * (9 * side)
			base.AssemblyAngularVelocity = cf.LookVector * (4 * side)
		end
	end

	task.delay(launch and 3.2 or 2.6, function()
		-- retour au dernier checkpoint
		setCartAnchored(pc, true)
		-- on annule toute vitesse residuelle du chariot (sinon ca repart en vrille)
		local b = cart.PrimaryPart
		if b then b.AssemblyLinearVelocity = Vector3.zero; b.AssemblyAngularVelocity = Vector3.zero end
		state.grip = 0
		state.lean = 0
		state.lastLean = nil
		state.distance = math.max(state.stageStart, state.respawnDist)
		state.speed = 0
		local rcf = renderAtDistance(state.distance)
		cart:PivotTo(rcf)
		if player then flashCenter(player, "↩️ Retour au checkpoint", Color3.fromRGB(150, 220, 255), 1.6) end
		if player then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp then
				-- on sort le perso de tout etat "coince" (ce qui bloquait la camera) + on
				-- annule sa vitesse/rotation residuelle (sinon camera qui part en vrille).
				if hum then hum.Sit = false; hum.PlatformStand = false end
				char:PivotTo(rcf * CFrame.new(0, 4, 0))
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				task.wait(0.1)
				if hum then seat:Sit(hum) end
			end
		end
		state.derailing = false
	end)
end

-- returnToCheckpoint : remet INSTANTANEMENT le chariot + le conducteur au dernier checkpoint
-- (sert a l'anti-herbe : "on tombe -> on respawn"). Pas de fling ni de delai, contrairement a derail.
local function returnToCheckpoint(player)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local cart, seat = pc.cart, pc.seat
	if state.derailing then return end
	state.derailing = true
	state.airborne = false
	setCartAnchored(pc, true)
	local b = cart.PrimaryPart
	if b then b.AssemblyLinearVelocity = Vector3.zero; b.AssemblyAngularVelocity = Vector3.zero end
	state.grip = 0; state.lean = 0; state.lastLean = nil
	state.distance = math.max(state.stageStart, state.respawnDist)
	state.speed = 0
	local rcf = renderAtDistance(state.distance)
	cart:PivotTo(rcf)
	if player then flashCenter(player, "↩️ Retour au checkpoint", Color3.fromRGB(150, 220, 255), 1.6) end
	if player then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp then
			if hum then hum.Sit = false; hum.PlatformStand = false end
			char:PivotTo(rcf * CFrame.new(0, 4, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.1)
			if hum then seat:Sit(hum) end
		end
	end
	state.derailing = false
end

-- ===================== EN L'AIR (decollage realiste) =====================
-- cherche, le long du circuit entre dFrom et dTo, le point de voie le plus proche de pos.
local function nearestOnTrack(pos, dFrom, dTo)
	local bestD, best2 = nil, math.huge
	local d = dFrom
	while d <= dTo do
		local p = (renderAtDistance(d)).Position
		local dx, dy, dz = p.X - pos.X, p.Y - pos.Y, p.Z - pos.Z
		local s2 = dx * dx + dy * dy + dz * dz
		if s2 < best2 then best2 = s2; bestD = d end
		d = d + 4
	end
	return bestD, math.sqrt(best2)
end

-- Le chariot vole librement (vraie physique). On essaie de le RACCROCHER a la voie quand
-- il redescend pres des rails (-> on continue !). Sinon (trop longtemps / tombe trop bas)
-- -> deraillement classique -> retour au checkpoint. C'est le "avec de la chance" demande.
local function updateAirborne(player, dt)
	local pc = playerCarts[player]; if not pc then return end
	local state = pc.state
	local cart = pc.cart
	local rollSound, sparkEmitter = pc.rollSound, pc.sparkEmitter
	rollSound.Volume = 0
	sparkEmitter.Enabled = false
	state.airTime = (state.airTime or 0) + dt
	local b = cart.PrimaryPart
	if not b then state.airborne = false; return end
	local pos = b.Position
	local vel = b.AssemblyLinearVelocity
	local dFrom = state.launchDist or 0
	local bestD, gap = nearestOnTrack(pos, dFrom, math.min(dFrom + 80, TOTAL_DIST))
	local trackCF = bestD and renderAtDistance(bestD) or nil
	-- garde-fou : trop longtemps en l'air, ou tombe nettement sous la voie -> CRASH
	local floorY = trackCF and trackCF.Position.Y or pos.Y
	if state.airTime > 2.6 or pos.Y < floorY - 30 then
		dbg(string.format("ENVOL PERDU -> CRASH  (vol=%.1fs)", state.airTime))
		state.airborne = false; derail(player, nil, false); return
	end
	-- on attend de RE-DESCENDRE au niveau de la voie (apres un petit vol) pour decider.
	if state.airTime > 0.3 and vel.Y < 0 and trackCF and pos.Y <= trackCF.Position.Y + 2 then
		-- "AVEC DE LA CHANCE" : petit saut -> on se raccroche ; enorme saut -> crash quasi
		-- sur ; ENTRE LES DEUX -> chance (plus tu as saute fort, moins de chances).
		-- On ne RACCROCHE que si l'atterrissage est PROPRE : saut pas trop gros (chance),
		-- on retombe PRES des rails (gap petit) ET le chariot est a l'endroit (pas capote).
		-- Sinon = vrai CRASH. (Avant, un gros vol se "snappait" sur les rails -> bug.)
		local ratio = state.launchRatio or 1
		local upY = b.CFrame.UpVector.Y
		local reRail
		if ratio < 1.3 then reRail = true                -- petit saut -> on se raccroche
		elseif ratio > 1.8 then reRail = false            -- gros saut -> crash
		else reRail = math.random() < (1.8 - ratio) / 0.5 end   -- entre les deux : chance
		reRail = reRail and gap < 3.5 and upY > 0.35      -- propre + pres + a l'endroit
		if reRail then
			setCartAnchored(pc, true)
			b.AssemblyLinearVelocity = Vector3.zero
			b.AssemblyAngularVelocity = Vector3.zero
			state.distance = bestD
			state.speed = math.clamp(Vector3.new(vel.X, 0, vel.Z).Magnitude, 12, state.maxSpeed)
			state.grip = 0; state.lean = 0; state.lastLean = nil; state.lastLookY = nil
			state.airborne = false
			dbg(string.format("RACCROCHE  (gap=%.1f  ratio=%.2f  upY=%.2f  vol=%.1fs)", gap, ratio, upY, state.airTime))
		else
			dbg(string.format("CRASH  (gap=%.1f  ratio=%.2f  upY=%.2f  vol=%.1fs)", gap, ratio, upY, state.airTime))
			state.airborne = false
			derail(player, nil, false)
		end
		return
	end
end

-- ===================== ECONOMIE : Boutique / Renaissance =====================
-- On touche un pad dans le hub pour acheter. (Economie partagee = 1 chariot ; une
-- boutique accessible a tout moment + la sauvegarde viendront ensuite.)
-- buildEconomy : (re)pose les pads Boutique/Renaissance dans le hub. Rejouable.
local function buildEconomy()
	local cf0 = renderAtDistance(0)
	local function buyCart(player)
		local pc = playerCarts[player]; if not pc then return end
		local state = pc.state
		if state.cartTier >= #CARTS then
			if player then flashCenter(player, "🏁 Tu as deja le MEILLEUR chariot !", Color3.fromRGB(255, 215, 90), 2.5) end
			return
		end
		local nxt = CARTS[state.cartTier + 1]
		if state.score >= nxt.price then
			state.score = state.score - nxt.price
			state.cartTier = state.cartTier + 1
			recomputeMaxSpeed(pc)
			applyCartStyle(pc, state.cartTier)   -- nouveau look + nouveau son
			setWallet(player); updateLeaderstats(player)
			if player then flashCenter(player, "🛒 NOUVEAU CHARIOT : " .. nxt.name .. " !  (" .. nxt.max .. " km/h)", Color3.fromRGB(120, 255, 140), 3) end
		elseif player then
			local manque = nxt.price - math.floor(state.score)
			flashCenter(player, "🔒 " .. nxt.name .. " = " .. nxt.price .. " pieces  (encore " .. manque .. ")", Color3.fromRGB(255, 150, 120), 2.8)
		end
	end
	local function doRebirth(player)
		local pc = playerCarts[player]; if not pc then return end
		local state = pc.state
		local cost = 1000 * (state.reb + 1)
		if state.score >= cost then
			state.reb = state.reb + 1
			state.score = 0
			state.vitLevel = 0
			recomputeMaxSpeed(pc)
			state.gainMul = 1 + 0.5 * state.reb
			setWallet(player); updateLeaderstats(player)
			if player then flashCenter(player, "✨ RENAISSANCE !   Gains x" .. state.gainMul, Color3.fromRGB(205, 140, 255), 3) end
		elseif player then
			flashCenter(player, "❌ Renaissance : " .. cost .. " pieces requises", Color3.fromRGB(255, 120, 120), 2.5)
		end
	end
	local function buyPad(off, col, fn)
		local p = makePart(Vector3.new(9, 0.5, 6), cf0 * off, col, Enum.Material.Neon, trackFolder)
		local cdb = {}
		p.Touched:Connect(function(hit)
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if plr and not cdb[plr] then cdb[plr] = true; fn(plr); task.delay(1.2, function() cdb[plr] = nil end) end
		end)
	end
	-- ===== BOUTON "AMELIORER" cliquable : un clic achete le chariot suivant DIRECT =====
	local upgPos = (cf0 * CFrame.new(36, 6, 56)).Position
	local ctrPos = (cf0 * CFrame.new(0, 6, 46)).Position
	local upgPart = makePart(Vector3.new(13, 6.5, 0.6),
		CFrame.lookAt(upgPos, Vector3.new(ctrPos.X, upgPos.Y, ctrPos.Z)),
		Color3.fromRGB(36, 150, 64), Enum.Material.Neon, trackFolder)
	local usg = Instance.new("SurfaceGui")
	usg.Face = Enum.NormalId.Front; usg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	usg.PixelsPerStud = 35; usg.Adornee = upgPart; usg.Parent = upgPart
	local ulbl = Instance.new("TextLabel")
	ulbl.Size = UDim2.new(0.92, 0, 0.84, 0); ulbl.Position = UDim2.new(0.04, 0, 0.08, 0)
	ulbl.BackgroundTransparency = 1; ulbl.TextScaled = true; ulbl.TextWrapped = true
	ulbl.TextXAlignment = Enum.TextXAlignment.Center; ulbl.TextYAlignment = Enum.TextYAlignment.Center
	ulbl.Font = Enum.Font.GothamBlack; ulbl.TextColor3 = Color3.new(1, 1, 1); ulbl.TextStrokeTransparency = 0.4
	-- panneau GENERIQUE : avec un chariot PAR JOUEUR, on ne peut plus afficher UN seul prix.
	-- Le panneau dit juste "AMELIORER" ; le vrai parcours d'achat (par joueur) est le menu a l'ecran.
	ulbl.Text = "⬆ AMELIORER\nchariot suivant"; ulbl.Parent = usg
	-- doUpgrade(plr) : achete le PROCHAIN chariot DU joueur qui clique, puis rafraichit SON menu.
	local function doUpgrade(plr)
		local pc = playerCarts[plr]; if not pc then return end
		buyCart(plr)
		pc.state.menuView = nil   -- sa carte revient a son nouveau "prochain chariot"
		local gg = guis[plr]; if gg then refreshMenu(gg) end
	end
	upgradeFn = doUpgrade   -- le bouton ecran (RemoteEvent) appellera ca
	local ucd = Instance.new("ClickDetector"); ucd.MaxActivationDistance = 50; ucd.Parent = upgPart
	ucd.MouseClick:Connect(doUpgrade)
	buyPad(CFrame.new(30, -2.4, 64), Color3.fromRGB(90, 220, 120), doUpgrade)
	buyPad(CFrame.new(30, -2.4, 48), Color3.fromRGB(200, 130, 240), doRebirth)
	-- pad TEST (mode debug seulement) : recharge l'argent pour essayer les chariots.
	if DEBUG then
		buyPad(CFrame.new(30, -2.4, 32), Color3.fromRGB(255, 180, 60), function(player)
			local pc = playerCarts[player]; if not pc then return end
			pc.state.score = pc.state.score + 1000000
			setWallet(player); updateLeaderstats(player)
			if player then flashCenter(player, "🧪 TEST : +1 000 000 pieces", Color3.fromRGB(255, 210, 90), 2) end
		end)
	end
end
buildEconomy()

-- le bouton ecran "AMELIORATION CHARIOT" (cote client) envoie ce RemoteEvent -> on upgrade.
askUpgrade.OnServerEvent:Connect(function(plr)
	if upgradeFn then upgradeFn(plr) end
end)

-- les fleches ◀ ▶ du menu CHARIOTS : on change le chariot AFFICHE (0 = revenir au prochain
-- chariot, ce que le client envoie a l'ouverture du menu). C'est de l'AFFICHAGE seulement :
-- l'achat (doUpgrade) reste toujours sur le PROCHAIN chariot.
askBrowse.OnServerEvent:Connect(function(plr, dir)
	if typeof(dir) ~= "number" then return end
	local pc = playerCarts[plr]; if not pc then return end
	local state = pc.state
	local nextTier = math.min(state.cartTier + 1, #CARTS)
	if dir == 0 then
		state.menuView = nextTier
	else
		state.menuView = math.clamp((state.menuView or nextTier) + (dir > 0 and 1 or -1), 1, #CARTS)
	end
	local gg = guis[plr]; if gg then refreshMenu(gg) end
end)

-- ===================== MONDES : (re)construction + passage au monde suivant =====================
-- clearWorld vide la voie+hub+economie ; buildWorld regenere TOUT pour le monde donne.
local function clearWorld()
	trackFolder:ClearAllChildren()
end
-- buildWorld : regenere TOUT le decor du monde (PARTAGE). Ne touche PLUS a un chariot unique :
-- ce sont les joueurs (advanceWorld) qui repositionnent ensuite chacun leur chariot.
local function buildWorld(world)
	clearWorld()
	genTrack(world)        -- nouveau trace + CURRENT_ZONE du monde
	buildTrack()           -- ballast/rails/tunnel/checkpoints/plateforme d'arrivee
	buildTerrain()         -- sol + reliefs du theme
	buildDecor()           -- arbres/rochers/... du theme
	applyLighting()        -- ciel/ambiance du theme
	buildHub()             -- nouveau hub au depart
	buildEconomy()         -- pads boutique
end

-- rebuilding : VRAI pendant la reconstruction du monde (PARTAGEE). stepCart sort tot tant que
-- c'est vrai -> evite qu'un 2e joueur redeclenche le passage de monde pendant qu'on reconstruit.
local rebuilding = false

-- advanceWorld : fin du circuit -> on passe TOUT LE MONDE au monde suivant (decor partage).
-- Ejecte TOUS les conducteurs, reconstruit le monde UNE fois, puis replace+rassoit chaque joueur.
local function advanceWorld(triggerPlayer)
	if rebuilding then return end
	rebuilding = true
	local nextW = currentWorldIndex + 1
	local cfg = worldCfg(nextW)
	-- felicitations a tout le monde (le monde change pour tous)
	for _, gg in pairs(guis) do
		gg.Center.Text = "✅ NIVEAU REUSSI !   →   MONDE " .. nextW .. " : " .. cfg.name
		gg.Center.TextColor3 = Color3.fromRGB(255, 225, 110)
		local txt = gg.Center.Text
		task.delay(4, function() if gg and gg.Center.Text == txt then gg.Center.Text = "" end end)
	end
	-- ejection bulletproof de CHAQUE conducteur (le weld colle le joueur au chariot)
	for _, pc in pairs(playerCarts) do
		local seat = pc.seat
		local hum = seat.Occupant
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then weld:Destroy() end
		if hum then hum.Sit = false; hum.Jump = true end
		seat.Disabled = true
	end
	buildWorld(nextW)   -- on regenere TOUT le decor UNE seule fois (genTrack met a jour currentWorldIndex)
	-- replace CHAQUE chariot au depart + remet SA course a zero, puis rassoit le joueur dans le nouveau hub.
	local hubCF = (renderAtDistance(0)) * CFrame.new(0, 5, 56)
	for _, pc in pairs(playerCarts) do
		local state = pc.state
		state.distance = 0; state.speed = 0; state.curStage = 1; state.stageStart = 0; state.respawnDist = 0; state.lastSeg = 0
		state.boostLevel = 0; state.boostSpeed = 0; state.boostGrip = 0; state.maxReached = 0
		state.grip = 0; state.lean = 0; state.lastLean = nil
		state.derailing = false; state.airborne = false
		recomputeMaxSpeed(pc)
		if pc.spawned and pc.cart then pc.cart:PivotTo((renderAtDistance(0)) * CFrame.new(pc.laneX or 0, 0, 0)) end
		local player = pc.player
		local seat = pc.seat
		local char = player and player.Character
		local function toHub()
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				char:PivotTo(hubCF)
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end
		task.delay(0.2, toHub)
		task.delay(0.7, function() toHub(); seat.Disabled = false end)
	end
	task.delay(0.7, function() rebuilding = false end)
end

-- ===================== RAILS FANTOMES : cycle apparition / disparition =====================
-- Les parties de voie taggees "Phantom" (cyan) clignotent puis DISPARAISSENT en rythme.
-- phantomSolid dit si elles sont praticables MAINTENANT ; la boucle principale fait tomber qui
-- est dessus quand elles ont disparu. (Leger : on ne change la transparence que quelques fois/cycle.)
local phantomSolid = true
local function setPhantomParts(transp)
	for _, p in ipairs(trackFolder:GetChildren()) do
		if p:GetAttribute("Phantom") then p.Transparency = transp end
	end
end
task.spawn(function()
	while true do
		phantomSolid = true
		setPhantomParts(0)                 -- PRESENTS (pleins)
		task.wait(2.8)
		for _ = 1, 3 do                    -- avertissement : 3 clignotements avant la disparition
			setPhantomParts(0.7); task.wait(0.13)
			setPhantomParts(0);   task.wait(0.13)
		end
		phantomSolid = false
		setPhantomParts(0.92)              -- DISPARUS (fantomes)
		task.wait(1.7)
	end
end)

-- ===================== OBSTACLES : rotation des lames (tournent en continu) =====================
RunService.Heartbeat:Connect(function(dt)
	obstaclePhase = (obstaclePhase + dt * 3.0) % (2 * math.pi)
	if obstacleBlades then
		for _, ob in ipairs(obstacleBlades) do
			local rot = ob.axle * CFrame.Angles(0, 0, obstaclePhase)
			for _, pp in ipairs(ob.parts) do
				if pp.part.Parent then pp.part.CFrame = rot * pp.off end
			end
		end
	end
end)

-- ===================== BOUCLE PRINCIPALE (par chariot) =====================
-- stepCart : fait avancer LE chariot d'UN joueur (pc) pour une frame. Corps quasi identique a
-- l'ancienne boucle unique : les alias state/cart/seat/FX pointent vers le contexte du joueur.
local function stepCart(pc, dt)
	local state = pc.state
	local cart, seat = pc.cart, pc.seat
	local rollSound, sparkEmitter = pc.rollSound, pc.sparkEmitter
	local cartPitch = pc.cartPitch
	local occupant = seat.Occupant
	if not occupant then
		rollSound.Volume = 0; sparkEmitter.Enabled = false
		if state.airborne then state.airborne = false; setCartAnchored(pc, true) end  -- jamais bloque en vol
		return
	end
	if state.derailing then sparkEmitter.Enabled = false; return end

	local player = Players:GetPlayerFromCharacter(occupant.Parent)
	-- en plein vol (apres un decollage) : on gere le vol/rattrapage a part, puis on sort
	if state.airborne then updateAirborne(player, dt); return end
	local throttle = seat.ThrottleFloat

	if throttle > 0 then
		state.speed = state.speed + ACCEL * dt
	elseif throttle < 0 then
		state.speed = state.speed - CARTS[state.cartTier].brake * dt   -- freinage = celui du chariot
	else
		if state.speed > 0 then
			state.speed = math.max(0, state.speed - FRICTION * dt)
		else
			state.speed = math.min(0, state.speed + FRICTION * dt)
		end
	end
	state.speed = math.clamp(state.speed, -REVERSE_MAX, state.maxSpeed)
	state.distance = math.clamp(state.distance + state.speed * dt, 0, TOTAL_DIST)

	if state.distance >= TOTAL_DIST then
		-- FIN DU MONDE : felicitations + passage au MONDE SUIVANT (nouveau trace,
		-- nouveau theme, nouveau hub) genere de zero par advanceWorld (partage, tous les joueurs).
		print("[BALADE] Fin du monde atteinte -> MONDE SUIVANT")
		if player then
			award(player, math.floor(80 * state.gainMul))
			addXp(player, XP_WORLD_BONUS)   -- gros bonus XP pour avoir fini un monde
		end
		advanceWorld(player)   -- le garde "rebuilding" empeche un double declenchement
		return
	end

	local cf, seg = renderAtDistance(state.distance)
	-- VOIES DE DEPART : on rejoint le centre en douceur (decale au depart -> 0 apres MERGE_DIST)
	local laneOff = (pc.laneX or 0) * laneFade(state.distance, pc.laneX)
	if laneOff ~= 0 then cf = cf * CFrame.new(laneOff, 0, 0) end
	local meta = segMeta[seg]

	-- RAILS FANTOMES : si on est sur une section "phantom" alors qu'elle a DISPARU -> on TOMBE
	-- pour de vrai (le chariot chute dans le vide), puis derail le ramene au dernier checkpoint.
	if meta.kind == "phantom" and not phantomSolid then
		if player then flashCenter(player, "⏱️ Raté ! Les rails ont disparu...", Color3.fromRGB(255, 130, 120), 2) end
		derail(player)   -- chute reelle, puis retour au checkpoint (gere par derail)
		return
	end

	-- OBSTACLES : si une LAME est BASSE (dans la voie) au moment ou on passe dessous -> on tombe.
	if obstacleDists and math.cos(obstaclePhase) > 0.72 then
		for _, od in ipairs(obstacleDists) do
			if math.abs(state.distance - od) < 4 then
				if player then flashCenter(player, "🪓 La lame t'a eu !", Color3.fromRGB(255, 120, 120), 1.8) end
				derail(player)
				return
			end
		end
	end

	-- (Le respawn vise desormais le dernier CHECKPOINT VISIBLE franchi = state.stageStart, ou le
	-- hub du debut si aucun. Voir derail / returnToCheckpoint. Plus de "checkpoint invisible".)

	-- fin d'une etape : on atteint la zone safe de l'etape en cours -> +1 Win + etape suivante
	local cp = checkpoints[state.curStage]
	if cp and state.distance >= cp.dist then
		completeStage(player)
		state.stageStart = cp.dist
		state.curStage = state.curStage + 1
	end

	-- Les gains de VITESSE / ADHERENCE pendant la course ont ete RETIRES : ces stats s'obtiennent
	-- UNIQUEMENT en achetant un meilleur chariot. boostSpeed/boostGrip restent donc a 0 ->
	-- maxSpeed = vitesse du chariot, gripMul = adherence du chariot, et rien d'autre.

	-- physique du looping : la gravite te ralentit en montant et t'accelere en
	-- descendant. Il faut donc de l'elan pour passer le haut ; pas assez de
	-- vitesse dans la partie haute (penchee) = on tombe du looping (comme en vrai).
	if meta.kind == "loop" then
		state.speed = math.clamp(state.speed - LOOP_GRAVITY * cf.LookVector.Y * dt, -REVERSE_MAX, state.maxSpeed)
		if cf.UpVector.Y < 0.4 and state.speed < LOOP_MIN_SPEED then
			derail(player)
			return
		end
	else
		-- gravite douce sur le relief : on ralentit en montant, on accelere en descendant.
		-- ADHERENCE EN MONTEE : un meilleur chariot grimpe mieux -> on REDUIT la gravite qui
		-- freine quand la voie monte (LookVector.Y > 0), selon son adherence (grip du chariot
		-- + boosts de la course). En descente, la gravite reste (l'elan est un atout).
		local grav = WORLD_GRAVITY
		if cf.LookVector.Y > 0 then
			local power = math.min(0.85, BASE_CLIMB + (CARTS[state.cartTier].grip + state.boostGrip) * CLIMB_ASSIST)
			grav = grav * (1 - power)
		end
		local ns = state.speed - grav * cf.LookVector.Y * dt
		-- en roue libre (pas de frein), une cote ne te fait PAS partir en arriere : tu cales
		-- a 0 (sinon on glisse en arriere a toute vitesse = la sensation "bizarre").
		if throttle >= 0 and state.speed > 0 and ns < 0 then ns = 0 end
		state.speed = math.clamp(ns, -REVERSE_MAX, state.maxSpeed)
	end

	-- DECOLLAGE (hors looping) : au sommet d'une bosse prise trop vite, le chariot quitte
	-- les rails avec son ELAN REEL + un PETIT saut (pas un envol geant). Ensuite il vole
	-- librement : soit il retombe sur la voie et on continue (avec de la chance), soit il
	-- deraille. Tout le vol est gere par updateAirborne.
	local lookY = cf.LookVector.Y
	local prevY = state.lastLookY or lookY
	state.lastLookY = lookY
	-- lookY < 0.4 = on est au SOMMET ou en debut de descente (pas en pleine montee).
	if meta.kind ~= "loop" and state.speed > LAUNCH_MIN_SPEED and lookY < 0.4 then
		local ds = math.max(state.speed * dt, 0.001)
		local downCurve = (prevY - lookY) / ds        -- > 0 = la voie se met a descendre (crete)
		local launchE = state.speed * state.speed * downCurve
		-- seuil d'envol RELEVE par l'adherence (chariot + boosts) : un meilleur chariot "colle"
		-- mieux a la voie en descente -> il s'envole / crashe moins involontairement sur les bosses.
		local launchThreshold = LAUNCH_FORCE * (1 + (CARTS[state.cartTier].grip + state.boostGrip) * 1.4)
		if downCurve > 0 and launchE > launchThreshold then
			state.airborne = true
			state.airTime = 0
			state.launchDist = state.distance
			state.launchRatio = launchE / launchThreshold   -- a quel point on a saute fort (1 = pile au seuil)
			setCartAnchored(pc, false)
			local b = cart.PrimaryPart
			if b then
				-- elan reel + pop vertical PROPORTIONNEL a la force du choc : juste au seuil =
				-- petit saut (rattrapable), tres rapide/raide = gros envol (souvent un crash).
				local pop = math.clamp(14 + (launchE / launchThreshold - 1) * 42, 14, 72)
				b.AssemblyLinearVelocity = cf.LookVector * state.speed + Vector3.new(0, pop, 0)
				b.AssemblyAngularVelocity = Vector3.zero
				dbg(string.format("DECOLLAGE  dist=%d  vit=%d  force=%.0f (seuil %d)  saut=%d",
					math.floor(state.distance), math.floor(state.speed), launchE, LAUNCH_FORCE, math.floor(pop)))
			end
			return
		end
	end

	-- effet satisfaisant : +N a chaque nouveau segment franchi en avancant. N GRANDIT avec la
	-- PROGRESSION : meilleur chariot (cartTier) + monde atteint (world), en plus de l'etape en
	-- cours et du multiplicateur de renaissance -> on upgrade / on avance, et on gagne plus.
	if state.speed > 0 and seg > state.lastSeg then
		local progMul = 1 + (state.cartTier - 1) * CART_COIN_STEP + (currentWorldIndex - 1) * WORLD_COIN_STEP
			+ (state.xpLevel - 1) * XP_LEVEL_COIN_BONUS   -- + ton NIVEAU booste les gains
		local segs = seg - state.lastSeg
		local gained = segs * state.etape * state.gainMul * progMul
		state.combo = state.combo + 1
		state.comboT = 0
		state.lastSeg = seg
		award(player, gained)
		addXp(player, segs * XP_PER_SEG)   -- XP par segment (independant des pieces)
	elseif seg < state.lastSeg then
		state.lastSeg = seg
	end
	state.comboT = state.comboT + dt
	if state.comboT > 0.5 then state.combo = 0 end
	updatePopups(player, dt)

	-- log debug periodique : vitesse / position / type de voie (pour que Claude "voie")
	if DEBUG then
		state.dbgT = (state.dbgT or 0) + dt
		if state.dbgT > 1.5 then
			state.dbgT = 0
			dbg(string.format("roule  dist=%d/%d  vit=%d  voie=%s", math.floor(state.distance), math.floor(TOTAL_DIST), math.floor(state.speed), tostring(meta.kind)))
		end
	end

	-- perte d'adherence progressive : en virage trop rapide on accumule du
	-- "danger" (state.grip 0->1). On RECUPERE en ralentissant -> on peut se rattraper.
	-- l'adherence gagnee en avancant releve la vitesse "sure" en virage -> on deraille moins
	local gripMul = 0.8 + state.boostGrip + CARTS[state.cartTier].grip   -- 0.8 = chariot de base moins stable
	-- MONDES + DURS : plus le monde est avance, plus les virages sont SERRES (vitesse sure
	-- plus basse) -> un chariot faible deraille direct, il FAUT un meilleur chariot.
	local worldSafe = math.max(0.45, 1 - (currentWorldIndex - 1) * 0.12)
	local over = 0
	if meta.derailable and meta.safe > 0 and state.speed > 0 then
		over = state.speed / (meta.safe * worldSafe * DERAIL_MARGIN * gripMul)   -- > 1 = au-dela de la limite
	end
	if over > 1 then
		state.grip = math.min(1, (state.grip or 0) + (over - 1) * GRIP_RATE * dt)
	else
		state.grip = math.max(0, (state.grip or 0) - GRIP_RECOVER * dt)
	end

	-- SON de roulement (le "wagon clatter" en BOUCLE) : le volume + la hauteur montent
	-- avec la vitesse, silence a l'arret. Actif seulement quand le vrai son est mis.
	if ROLL_SOUND_READY then
		local spdFrac = math.clamp(math.abs(state.speed) / math.max(state.maxSpeed, 1), 0, 1)
		rollSound.Volume = spdFrac * 0.5
		rollSound.PlaybackSpeed = (0.85 + spdFrac * 0.4) * cartPitch   -- son + aigu selon le chariot
	end
	-- ETINCELLES quand on perd l'adherence (derapage en virage)
	sparkEmitter.Enabled = (state.grip or 0) > 0.18

	-- inclinaison : bank normal dans le virage + bascule vers l'EXTERIEUR selon la
	-- perte d'adherence ; on s'en approche en douceur (pas d'a-coup).
	local targetLean = 0
	if meta.leanDir ~= 0 then
		local frac = math.clamp(state.speed / (meta.safe * gripMul), 0, 1.3)
		targetLean = meta.leanDir * LEAN_MAX * frac
		targetLean = targetLean - meta.leanDir * (state.grip or 0) * GRIP_TILT
	end
	state.lean = (state.lean or 0) + (targetLean - (state.lean or 0)) * math.clamp(dt * LEAN_SMOOTH, 0, 1)
	local lean = state.lean

	-- secousses quand on perd l'adherence (avertissement avant la chute)
	local extra = CFrame.new()
	if (state.grip or 0) > 0.12 then
		local a = state.grip * 0.05
		extra = CFrame.Angles(rng:NextNumber(-a, a), 0, rng:NextNumber(-a, a))
	end

	if math.abs(state.speed) > 0.05 or math.abs(lean - (state.lastLean or 0)) > 0.0005 or (state.grip or 0) > 0.12 then
		cart:PivotTo(cf * CFrame.Angles(0, 0, lean) * extra)
		state.lastLean = lean
	end

	-- (la progression d'etape + les Wins sont geres plus haut, a l'entree de chaque zone safe)

	if player then updateInfo(player, seg, state.speed) end
	-- maj du classement (leaderstats) du conducteur (depuis son pc.state)
	if player then updateLeaderstats(player) end

	-- chute : seulement quand l'adherence est TOTALEMENT perdue (apres l'avertissement)
	if (state.grip or 0) >= 1 then
		derail(player, -meta.leanDir)
	end
end

-- une SEULE boucle qui anime TOUS les chariots apparus (le decor/obstacles/fantomes restent
-- des boucles partagees, separees). Pendant la reconstruction d'un monde, on saute (rebuilding).
RunService.Heartbeat:Connect(function(dt)
	if rebuilding then return end
	for _, pc in pairs(playerCarts) do
		if pc.spawned then stepCart(pc, dt) end
	end
end)

-- ===================== ANTI-HERBE : tomber dans l'herbe / le vide -> respawn =====================
-- La voie flotte TOUJOURS au-dessus de DEATH_Y. Donc si le CHARIOT (en conduite) ou un PERSO
-- (a pied) passe sous DEATH_Y, c'est qu'il est tombe : on le renvoie au dernier checkpoint s'il
-- conduisait, ou au hub s'il etait a pied. (Filet de securite contre les chutes "coincees".)
RunService.Heartbeat:Connect(function()
	-- chaque chariot apparu : tombe sous DEATH_Y en conduisant -> retour a SON checkpoint.
	for _, pc in pairs(playerCarts) do
		if pc.spawned then
			local seat = pc.seat
			local base = pc.cart.PrimaryPart
			local state = pc.state
			if seat.Occupant and base and not state.derailing and not state.airborne and base.Position.Y < DEATH_Y then
				returnToCheckpoint(Players:GetPlayerFromCharacter(seat.Occupant.Parent))
			end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and not hum.Sit and hrp.Position.Y < DEATH_Y then
			placeInHub(char)   -- a pied et tombe -> retour au hub
		end
	end
end)

print("============================================================")
print("✅ [BALADE v31] Looping PASSABLE (elan/descente avant + gravite loop reduite) ; chariot")
print("   1 moins stable. Le bouton AMELIORATION ouvre un MENU listant les 10 chariots (achat).")
print("   Si le menu ne s'ouvre pas -> relance LANCER-ROJO.bat (pour synchroniser client/).")
print("   Monde 1 : " .. math.floor(TOTAL_DIST) .. " studs, " .. NSEG .. " segments.")
print("============================================================")
