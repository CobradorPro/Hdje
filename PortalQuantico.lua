--[[
	PORTAL QUÂNTICO - LocalScript (PC e Mobile)
	-------------------------------------------------
	• Cria um Tool na Backpack (RequiresHandle = false) e o recria ao renascer.
	• Ao equipar: holograma neon segue a mira (mouse no PC / centro da tela no celular).
	• Ao ativar: constrói um portal com animação épica e teletransporta o jogador.
	• Sem assets externos. LocalScript: só o jogador local vê os efeitos.
	Coloque em StarterPlayerScripts (ou execute no cliente).
]]

---------------------------------------------------------------------
-- CONFIGURAÇÕES (edite à vontade)
---------------------------------------------------------------------
local CONFIG = {
	NOME_TOOL          = "Portal Quântico",
	COR_PRINCIPAL      = Color3.fromRGB(0, 200, 255),   -- cor neon
	COR_METAL          = Color3.fromRGB(28, 30, 38),    -- metal escuro
	ALCANCE_MIRA       = 350,     -- distância máxima do raycast
	RAIO_PORTAL        = 7,       -- raio do anel do portal
	SEGMENTOS_ANEL     = 18,      -- quantidade de peças no anel
	TEMPO_ENTRE_PECAS  = 0.06,    -- intervalo entre a queda de cada peça
	ALTURA_QUEDA       = 45,      -- de qual altura as peças caem
	DURACAO_QUEDA      = 0.55,    -- tempo de queda de cada peça
	TRANSP_HOLOGRAMA   = 0.55,    -- transparência base do holograma
	TEMPO_PORTAL_ATIVO = 8,       -- segundos até o portal se desfazer
	FORCA_TREMOR       = 0.7,     -- intensidade do tremor de câmera
	DURACAO_TREMOR     = 0.6,     -- duração do tremor
	FAISCAS_POR_PECA   = 14,      -- partículas emitidas por peça
}

---------------------------------------------------------------------
-- SERVIÇOS
---------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local jogador = Players.LocalPlayer
local camera  = workspace.CurrentCamera

---------------------------------------------------------------------
-- LIMPEZA (_G cleanup) caso o script seja executado de novo
---------------------------------------------------------------------
if _G.PortalQuantico_Cleanup then
	pcall(_G.PortalQuantico_Cleanup)
end

local conexoes = {}      -- conexões globais do script
local instancias = {}    -- instâncias criadas pelo script

local function rastrear(inst)
	table.insert(instancias, inst)
	return inst
end

local pastaEfeitos = rastrear(Instance.new("Folder"))
pastaEfeitos.Name = "PortalQuantico_Efeitos"
pastaEfeitos.Parent = workspace

local pastaHolograma = rastrear(Instance.new("Folder"))
pastaHolograma.Name = "PortalQuantico_Holograma"
pastaHolograma.Parent = workspace

-- Tela de flash
local guiFlash = rastrear(Instance.new("ScreenGui"))
guiFlash.Name = "PortalQuantico_Flash"
guiFlash.IgnoreGuiInset = true
guiFlash.ResetOnSpawn = false
guiFlash.Parent = jogador:WaitForChild("PlayerGui")

local frameFlash = Instance.new("Frame")
frameFlash.Size = UDim2.fromScale(1, 1)
frameFlash.BackgroundColor3 = Color3.new(1, 1, 1)
frameFlash.BackgroundTransparency = 1
frameFlash.BorderSizePixel = 0
frameFlash.Parent = guiFlash

local toolAtual = nil
local construindo = false   -- trava anti-spam
local conexaoHolo = nil     -- loop do holograma

_G.PortalQuantico_Cleanup = function()
	if conexaoHolo then conexaoHolo:Disconnect() conexaoHolo = nil end
	for _, c in ipairs(conexoes) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conexoes)
	if toolAtual then pcall(function() toolAtual:Destroy() end) end
	for _, inst in ipairs(instancias) do
		pcall(function() inst:Destroy() end)
	end
	table.clear(instancias)
	local char = jogador.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.CameraOffset = Vector3.zero end
	_G.PortalQuantico_Cleanup = nil
end

---------------------------------------------------------------------
-- GEOMETRIA DO PORTAL (lista de peças com offsets relativos à base)
---------------------------------------------------------------------
local function obterPecas()
	local pecas = {}
	local R = CONFIG.RAIO_PORTAL
	local centroY = R + 2  -- altura do centro do anel

	-- Plataforma base (metal)
	table.insert(pecas, {
		nome = "Base", forma = Enum.PartType.Cylinder, material = Enum.Material.Metal,
		cor = CONFIG.COR_METAL, tamanho = Vector3.new(1, R * 2.6, R * 2.6),
		offset = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), transp = 0,
	})
	-- Anel neon da base
	table.insert(pecas, {
		nome = "BaseNeon", forma = Enum.PartType.Cylinder, material = Enum.Material.Neon,
		cor = CONFIG.COR_PRINCIPAL, tamanho = Vector3.new(0.2, R * 2.2, R * 2.2),
		offset = CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), transp = 0.3,
	})
	-- Pilares laterais
	for _, lado in ipairs({-1, 1}) do
		table.insert(pecas, {
			nome = "Pilar", forma = Enum.PartType.Block, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(1.6, centroY, 2),
			offset = CFrame.new(lado * (R + 0.8), centroY / 2 + 1, 0), transp = 0,
		})
		table.insert(pecas, {
			nome = "PilarNeon", forma = Enum.PartType.Block, material = Enum.Material.Neon,
			cor = CONFIG.COR_PRINCIPAL, tamanho = Vector3.new(0.3, centroY - 1, 2.2),
			offset = CFrame.new(lado * (R + 0.8), centroY / 2 + 1, 0), transp = 0,
		})
	end
	-- Segmentos do anel (metal + filete neon)
	local N = CONFIG.SEGMENTOS_ANEL
	local comprimento = (2 * math.pi * R / N) * 1.08
	for i = 0, N - 1 do
		local a = (i / N) * math.pi * 2
		local cf = CFrame.new(0, centroY, 0)
			* CFrame.new(math.cos(a) * R, math.sin(a) * R, 0)
			* CFrame.Angles(0, 0, a)
		table.insert(pecas, {
			nome = "Anel", forma = Enum.PartType.Block, material = Enum.Material.Metal,
			cor = CONFIG.COR_METAL, tamanho = Vector3.new(1.4, comprimento, 1.8),
			offset = cf, transp = 0,
		})
		table.insert(pecas, {
			nome = "AnelNeon", forma = Enum.PartType.Block, material = Enum.Material.Neon,
			cor = CONFIG.COR_PRINCIPAL, tamanho = Vector3.new(0.35, comprimento, 2),
			offset = cf * CFrame.new(-0.75, 0, 0), transp = 0,
		})
	end
	-- Superfície do portal (disco de energia)
	table.insert(pecas, {
		nome = "Energia", forma = Enum.PartType.Cylinder, material = Enum.Material.Neon,
		cor = CONFIG.COR_PRINCIPAL, tamanho = Vector3.new(0.2, R * 2 - 1.2, R * 2 - 1.2),
		offset = CFrame.new(0, centroY, 0) * CFrame.Angles(0, math.rad(90), 0), transp = 0.45,
		ultima = true,
	})
	return pecas, centroY
end

local function criarParte(spec, parent)
	local p = Instance.new("Part")
	p.Name = spec.nome
	p.Shape = spec.forma
	p.Material = spec.material
	p.Color = spec.cor
	p.Size = spec.tamanho
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

---------------------------------------------------------------------
-- MIRA (mouse no PC / centro da tela no celular) + Raycast filtrado
---------------------------------------------------------------------
local function usandoToque()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function obterAlvo()
	local pontoTela
	if usandoToque() then
		pontoTela = camera.ViewportSize / 2
	else
		pontoTela = UserInputService:GetMouseLocation()
	end
	local raio = camera:ViewportPointToRay(pontoTela.X, pontoTela.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filtro = { pastaHolograma, pastaEfeitos }
	if jogador.Character then table.insert(filtro, jogador.Character) end
	params.FilterDescendantsInstances = filtro

	local resultado = workspace:Raycast(raio.Origin, raio.Direction * CONFIG.ALCANCE_MIRA, params)
	if resultado then
		return resultado.Position
	end
	return nil
end

-- CFrame da base: no ponto mirado, virado para o jogador (só rotação Y)
local function cframeBase(posicao)
	local char = jogador.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origem = hrp and hrp.Position or camera.CFrame.Position
	local dir = Vector3.new(origem.X - posicao.X, 0, origem.Z - posicao.Z)
	if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, 1) end
	return CFrame.lookAt(posicao, posicao + dir.Unit)
end

---------------------------------------------------------------------
-- HOLOGRAMA
---------------------------------------------------------------------
local holoPartes = {}
local holoScan = nil

local function destruirHolograma()
	if conexaoHolo then conexaoHolo:Disconnect() conexaoHolo = nil end
	pastaHolograma:ClearAllChildren()
	table.clear(holoPartes)
	holoScan = nil
end

local function criarHolograma()
	destruirHolograma()
	local pecas, centroY = obterPecas()
	for _, spec in ipairs(pecas) do
		local p = criarParte(spec, pastaHolograma)
		p.Material = Enum.Material.Neon
		p.Color = CONFIG.COR_PRINCIPAL
		p.Transparency = CONFIG.TRANSP_HOLOGRAMA
		table.insert(holoPartes, { parte = p, offset = spec.offset })
	end
	-- Linha de scan animada
	holoScan = Instance.new("Part")
	holoScan.Name = "Scan"
	holoScan.Anchored = true
	holoScan.CanCollide = false
	holoScan.CanQuery = false
	holoScan.CanTouch = false
	holoScan.Material = Enum.Material.Neon
	holoScan.Color = Color3.new(1, 1, 1)
	holoScan.Size = Vector3.new(CONFIG.RAIO_PORTAL * 2.4, 0.12, 0.25)
	holoScan.Transparency = 0.2
	holoScan.Parent = pastaHolograma

	local inicio = os.clock()
	conexaoHolo = RunService.RenderStepped:Connect(function()
		local alvo = obterAlvo()
		local visivel = alvo ~= nil
		local t = os.clock() - inicio
		local pulso = CONFIG.TRANSP_HOLOGRAMA + math.sin(t * 5) * 0.18
		if visivel then
			local base = cframeBase(alvo)
			for _, h in ipairs(holoPartes) do
				h.parte.CFrame = base * h.offset
				h.parte.Transparency = math.clamp(pulso, 0, 1)
			end
			local yScan = centroY + math.sin(t * 2.5) * (CONFIG.RAIO_PORTAL + 1)
			holoScan.CFrame = base * CFrame.new(0, math.max(yScan, 1.2), 0)
			holoScan.Transparency = 0.2
		else
			for _, h in ipairs(holoPartes) do h.parte.Transparency = 1 end
			holoScan.Transparency = 1
		end
	end)
end

---------------------------------------------------------------------
-- EFEITOS
---------------------------------------------------------------------
local function emitirFaiscas(posicao, quantidade)
	local ancora = Instance.new("Part")
	ancora.Anchored = true
	ancora.CanCollide = false
	ancora.CanQuery = false
	ancora.Transparency = 1
	ancora.Size = Vector3.new(0.2, 0.2, 0.2)
	ancora.Position = posicao
	ancora.Parent = pastaEfeitos

	local emissor = Instance.new("ParticleEmitter")
	emissor.Color = ColorSequence.new(Color3.new(1, 1, 1), CONFIG.COR_PRINCIPAL)
	emissor.LightEmission = 1
	emissor.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emissor.Lifetime = NumberRange.new(0.3, 0.7)
	emissor.Speed = NumberRange.new(12, 28)
	emissor.SpreadAngle = Vector2.new(180, 180)
	emissor.Acceleration = Vector3.new(0, -40, 0)
	emissor.Drag = 2
	emissor.Rate = 0
	emissor.Parent = ancora
	emissor:Emit(quantidade)

	task.delay(1.2, function() ancora:Destroy() end)
end

local function ondaDeChoque(cfBase)
	local onda = Instance.new("Part")
	onda.Shape = Enum.PartType.Cylinder
	onda.Material = Enum.Material.Neon
	onda.Color = CONFIG.COR_PRINCIPAL
	onda.Anchored = true
	onda.CanCollide = false
	onda.CanQuery = false
	onda.Size = Vector3.new(0.3, 2, 2)
	onda.CFrame = cfBase * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	onda.Transparency = 0.1
	onda.Parent = pastaEfeitos

	local tw = TweenService:Create(onda,
		TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, CONFIG.RAIO_PORTAL * 9, CONFIG.RAIO_PORTAL * 9), Transparency = 1 })
	tw:Play()
	tw.Completed:Connect(function() onda:Destroy() end)
end

local function tremerCamera(duracao, forca)
	local char = jogador.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local inicio = os.clock()
	local con
	con = RunService.RenderStepped:Connect(function()
		local passado = os.clock() - inicio
		if passado >= duracao or not hum.Parent then
			con:Disconnect()
			hum.CameraOffset = Vector3.zero
			return
		end
		local f = forca * (1 - passado / duracao)
		hum.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * f,
			(math.random() - 0.5) * 2 * f,
			(math.random() - 0.5) * 2 * f)
	end)
	table.insert(conexoes, con)
end

local function pulsoDeLuz(posicao)
	local ancora = Instance.new("Part")
	ancora.Anchored = true
	ancora.CanCollide = false
	ancora.CanQuery = false
	ancora.Transparency = 1
	ancora.Size = Vector3.new(0.2, 0.2, 0.2)
	ancora.Position = posicao
	ancora.Parent = pastaEfeitos

	local luz = Instance.new("PointLight")
	luz.Color = CONFIG.COR_PRINCIPAL
	luz.Brightness = 0
	luz.Range = 60
	luz.Parent = ancora

	local subir = TweenService:Create(luz, TweenInfo.new(0.15), { Brightness = 12 })
	local descer = TweenService:Create(luz, TweenInfo.new(1, Enum.EasingStyle.Quad), { Brightness = 0 })
	subir:Play()
	subir.Completed:Connect(function() descer:Play() end)
	descer.Completed:Connect(function() ancora:Destroy() end)
end

local function flashTela()
	frameFlash.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(CONFIG.COR_PRINCIPAL, 0.3)
	frameFlash.BackgroundTransparency = 0
	TweenService:Create(frameFlash,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
end

---------------------------------------------------------------------
-- CONSTRUÇÃO + TELETRANSPORTE
---------------------------------------------------------------------
local function construirPortal(posicao)
	construindo = true
	local base = cframeBase(posicao)
	local pecas, centroY = obterPecas()
	local modelo = Instance.new("Model")
	modelo.Name = "PortalConstruido"
	modelo.Parent = pastaEfeitos
	local partes = {}

	-- Peças caindo uma a uma
	for _, spec in ipairs(pecas) do
		local p = criarParte(spec, modelo)
		local destino = base * spec.offset
		p.CFrame = destino + Vector3.new(0, CONFIG.ALTURA_QUEDA, 0)
		p.Transparency = 1
		table.insert(partes, p)

		local tw = TweenService:Create(p,
			TweenInfo.new(CONFIG.DURACAO_QUEDA, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = destino, Transparency = spec.transp })
		tw:Play()
		task.delay(CONFIG.DURACAO_QUEDA * 0.6, function()
			emitirFaiscas(destino.Position, CONFIG.FAISCAS_POR_PECA)
		end)
		task.wait(CONFIG.TEMPO_ENTRE_PECAS)
	end

	task.wait(CONFIG.DURACAO_QUEDA)

	-- Final épico: onda de choque, tremor e pulso de luz
	local centro = (base * CFrame.new(0, centroY, 0)).Position
	ondaDeChoque(base)
	tremerCamera(CONFIG.DURACAO_TREMOR, CONFIG.FORCA_TREMOR)
	pulsoDeLuz(centro)
	emitirFaiscas(centro, 60)
	task.wait(0.35)

	-- Teletransporte com flash
	local char = jogador.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		flashTela()
		local destinoJogador = base * CFrame.new(0, 3.5, 6)
		char:PivotTo(CFrame.lookAt(destinoJogador.Position,
			destinoJogador.Position + base.LookVector))
		emitirFaiscas(destinoJogador.Position, 40)
	end

	-- Libera novo uso
	construindo = false

	-- Portal se desfaz depois de um tempo
	task.delay(CONFIG.TEMPO_PORTAL_ATIVO, function()
		for i, p in ipairs(partes) do
			if p.Parent then
				TweenService:Create(p,
					TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In),
					{ Transparency = 1, CFrame = p.CFrame + Vector3.new(0, 6, 0) }):Play()
			end
			if i % 4 == 0 then task.wait(0.03) end
		end
		task.wait(0.6)
		if modelo.Parent then modelo:Destroy() end
	end)
end

---------------------------------------------------------------------
-- TOOL (criação e recriação ao renascer)
---------------------------------------------------------------------
local function criarTool()
	if toolAtual then pcall(function() toolAtual:Destroy() end) end
	local mochila = jogador:WaitForChild("Backpack")

	local tool = Instance.new("Tool")
	tool.Name = CONFIG.NOME_TOOL
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Toque/clique para abrir um portal"
	tool.Parent = mochila
	toolAtual = tool

	tool.Equipped:Connect(function()
		criarHolograma()
	end)

	tool.Unequipped:Connect(function()
		destruirHolograma()
	end)

	tool.Activated:Connect(function()
		if construindo then return end  -- anti-spam
		local alvo = obterAlvo()
		if not alvo then return end
		task.spawn(construirPortal, alvo)
	end)

	tool.Destroying:Connect(function()
		destruirHolograma()
	end)
end

table.insert(conexoes, jogador.CharacterAdded:Connect(function(char)
	construindo = false
	char:WaitForChild("Humanoid")
	task.wait(0.1)
	criarTool()
end))

if jogador.Character then
	criarTool()
end
