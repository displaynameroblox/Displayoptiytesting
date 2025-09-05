-- Next Spotify - Full LocalScript
-- Place in StarterPlayerScripts (LocalScript) or StarterGui -> ScreenGui -> LocalScript

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- ========== Utility ==========
local function normalizeDecal(input)
	if not input or input == "" then return "" end
	if tostring(input):find("rbxassetid://") then return tostring(input) end
	local numeric = tostring(input):match("(%d+)")
	if numeric then return "rbxassetid://"..numeric end
	return tostring(input)
end

local function normalizeSoundId(id)
	if not id or id == "" then return nil end
	local numeric = tostring(id):match("(%d+)")
	if numeric then
		return "rbxassetid://"..numeric
	end
	-- إذا وصلنا هنا، المعطى مو رقم واضح، جرّبه مباشرة
	return tostring(id)
end

local function safeSetClipboard(str)
	if setclipboard then
		pcall(setclipboard, str)
		return true
	end
	return false
end

-- ========== Data ==========
local playlists = {} -- playlists[name] = { songs = { { id = "12345", decal = "rbxassetid://...", title = "Song" } } }
local settings = {
	theme = "Dark",
	toggleKey = Enum.KeyCode.M
}

-- Default playlist
playlists["Default"] = { songs = {} }

-- Forward declares لتفادي مشاكل الترتيب
local refreshSongsGrid
local rebuildPlaylistList

-- selected playlist لازم يتعرّف بدري
local selectedPlaylist = nil

-- ========== Themes ==========
local Themes = {
	Dark = {
		bg = Color3.fromRGB(18,18,18),
		panel = Color3.fromRGB(25,25,25),
		button = Color3.fromRGB(40,40,40),
		text = Color3.fromRGB(240,240,240),
		muted = Color3.fromRGB(160,160,160),
		accent = Color3.fromRGB(30,215,96)
	},
	Light = {
		bg = Color3.fromRGB(245,245,245),
		panel = Color3.fromRGB(230,230,230),
		button = Color3.fromRGB(250,250,250),
		text = Color3.fromRGB(20,20,20),
		muted = Color3.fromRGB(90,90,90),
		accent = Color3.fromRGB(30,144,255)
	}
}

-- ========== GUI Root ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NextSpotifyGUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ========== Loading Overlay ==========
local loadingFrame = Instance.new("Frame")
loadingFrame.Name = "LoadingOverlay"
loadingFrame.Size = UDim2.fromScale(1,1)
loadingFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
loadingFrame.BackgroundTransparency = 0
loadingFrame.Parent = screenGui
local lfCorner = Instance.new("UICorner", loadingFrame)
lfCorner.CornerRadius = UDim.new(0,0)

local blur = Instance.new("BlurEffect")
blur.Size = 18
blur.Parent = Lighting

local loadingLabel = Instance.new("TextLabel")
loadingLabel.Size = UDim2.fromScale(1,0)
loadingLabel.Position = UDim2.new(0,0,0.45,0)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Font = Enum.Font.GothamBlack
loadingLabel.TextScaled = true
loadingLabel.Text = "Loading..."
loadingLabel.TextColor3 = Color3.fromRGB(255,255,255)
loadingLabel.Parent = loadingFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.fromScale(1,0)
statusLabel.Position = UDim2.new(0,0,0.55,0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextScaled = true
statusLabel.Text = "Preparing UI"
statusLabel.TextColor3 = Color3.fromRGB(220,220,220)
statusLabel.Parent = loadingFrame

-- أنيميشن بسيطة لثلاث نقاط
local alive = true
task.spawn(function()
	local dots = 0
	while alive do
		dots = (dots % 3) + 1
		loadingLabel.Text = "Loading"..string.rep(".", dots)
		task.wait(0.4)
	end
end)

local function setStatus(txt)
	statusLabel.Text = txt
end

-- ========== Main Window ==========
setStatus("Building window")

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Name = "Main"
mainFrame.Size = UDim2.fromOffset(980,720)
mainFrame.Position = UDim2.new(0.5, -490, 0.1, 0)
mainFrame.BackgroundColor3 = Themes[settings.theme].bg
mainFrame.ClipsDescendants = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,14)

local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Thickness = 2
mainStroke.Color = Themes[settings.theme].panel
mainStroke.Transparency = 0.7

local minConstraint = Instance.new("UISizeConstraint", mainFrame)
minConstraint.MinSize = Vector2.new(700, 500)

-- ========== Top Bar (drag) ==========
local topBar = Instance.new("Frame", mainFrame)
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1,0,0,86)
topBar.Position = UDim2.new(0,0,0,0)
topBar.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0,14)
local topPad = Instance.new("UIPadding", topBar)
topPad.PaddingLeft = UDim.new(0,18)
topPad.PaddingRight = UDim.new(0,18)

local logo = Instance.new("TextLabel", topBar)
logo.Size = UDim2.new(1,0,1,0)
logo.BackgroundTransparency = 1
logo.Font = Enum.Font.GothamBlack
logo.Text = "🎵 Next Spotify"
logo.TextScaled = true
logo.TextColor3 = Themes[settings.theme].text
logo.TextXAlignment = Enum.TextXAlignment.Center

-- Drag logic (top bar only)
do
	local dragging = false
	local startPos = nil
	local startMouse = nil
	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			startPos = mainFrame.Position
			startMouse = input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - startMouse
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- Resize Handle bottom-right
local resizeHandle = Instance.new("Frame", mainFrame)
resizeHandle.Name = "ResizeHandle"
resizeHandle.Size = UDim2.fromOffset(22,22)
resizeHandle.AnchorPoint = Vector2.new(1,1)
resizeHandle.Position = UDim2.new(1, -8, 1, -8)
resizeHandle.BackgroundColor3 = Themes[settings.theme].accent
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0,6)

do
	local resizing = false
	local startMouse, startSize
	resizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			startMouse = input.Position
			startSize = mainFrame.AbsoluteSize
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - startMouse
			local newW = math.max(minConstraint.MinSize.X, startSize.X + delta.X)
			local newH = math.max(minConstraint.MinSize.Y, startSize.Y + delta.Y)
			mainFrame.Size = UDim2.fromOffset(newW, newH)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = false
		end
	end)
end

-- ========== Tabs Row ==========
local tabsRow = Instance.new("Frame", mainFrame)
tabsRow.Name = "TabsRow"
tabsRow.Size = UDim2.new(1, -28, 0, 64)
tabsRow.Position = UDim2.new(0, 14, 0, 92)
tabsRow.BackgroundTransparency = 1
local tabsLayout = Instance.new("UIListLayout", tabsRow)
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0,12)
tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local function makeTabButton(name)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 220, 1, -12)
	b.Text = name
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.BackgroundColor3 = Themes[settings.theme].button
	b.TextColor3 = Themes[settings.theme].text
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,12)
	b.Parent = tabsRow
	return b
end

local musicTabBtn = makeTabButton("Music")
local playlistsTabBtn = makeTabButton("Playlists")
local settingsTabBtn = makeTabButton("Settings")

-- ========== Content Area ==========
local content = Instance.new("Frame", mainFrame)
content.Name = "Content"
content.Size = UDim2.new(1, -28, 1, -200)
content.Position = UDim2.new(0, 14, 0, 168)
content.BackgroundTransparency = 1

-- Create pages
local function makePage(name)
	local p = Instance.new("Frame", content)
	p.Name = name
	p.Size = UDim2.fromScale(1,1)
	p.BackgroundTransparency = 1
	p.Visible = false
	return p
end

local musicPage = makePage("Music")
local playlistsPage = makePage("Playlists")
local settingsPage = makePage("Settings")
musicPage.Visible = true

local function showPage(page)
	musicPage.Visible = false
	playlistsPage.Visible = false
	settingsPage.Visible = false
	page.Visible = true
end

musicTabBtn.MouseButton1Click:Connect(function() showPage(musicPage) end)
playlistsTabBtn.MouseButton1Click:Connect(function() showPage(playlistsPage) end)
settingsTabBtn.MouseButton1Click:Connect(function() showPage(settingsPage) end)

-- ========== Music Page ==========
setStatus("Setting up Music page")

-- Now Playing container
local nowFrame = Instance.new("Frame", musicPage)
nowFrame.Size = UDim2.new(1,0,0,360)
nowFrame.Position = UDim2.new(0,0,0,0)
nowFrame.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", nowFrame).CornerRadius = UDim.new(0,12)
local nowPad = Instance.new("UIPadding", nowFrame)
nowPad.PaddingTop = UDim.new(0,12)
nowPad.PaddingLeft = UDim.new(0,12)
nowPad.PaddingRight = UDim.new(0,12)

local nowLayout = Instance.new("UIListLayout", nowFrame)
nowLayout.FillDirection = Enum.FillDirection.Horizontal
nowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
nowLayout.Padding = UDim.new(0,12)

local nowArt = Instance.new("ImageLabel", nowFrame)
nowArt.Size = UDim2.fromOffset(280,280)
nowArt.BackgroundTransparency = 1
nowArt.Image = "rbxassetid://154834668"

local nowInfo = Instance.new("Frame", nowFrame)
nowInfo.Size = UDim2.new(1, -300, 1, 0)
nowInfo.BackgroundTransparency = 1
local infoLayout = Instance.new("UIListLayout", nowInfo)
infoLayout.Padding = UDim.new(0,10)
infoLayout.FillDirection = Enum.FillDirection.Vertical
infoLayout.VerticalAlignment = Enum.VerticalAlignment.Top

local nowTitle = Instance.new("TextLabel", nowInfo)
nowTitle.Size = UDim2.new(1,0,0,60)
nowTitle.Font = Enum.Font.GothamBlack
nowTitle.TextScaled = true
nowTitle.Text = "Now Playing: None"
nowTitle.TextColor3 = Themes[settings.theme].text
nowTitle.BackgroundTransparency = 1

local nowControls = Instance.new("Frame", nowInfo)
nowControls.Size = UDim2.new(1,0,0,120)
nowControls.BackgroundTransparency = 1
local ctrlLayout = Instance.new("UIListLayout", nowControls)
ctrlLayout.FillDirection = Enum.FillDirection.Horizontal
ctrlLayout.Padding = UDim.new(0,14)
ctrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local function makeCtrl(txt)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 140, 0, 72)
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.BackgroundColor3 = Themes[settings.theme].button
	b.TextColor3 = Themes[settings.theme].text
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,10)
	b.Parent = nowControls
	return b
end

local playPauseBtn = makeCtrl("▶ / ⏸")
local nextBtn = makeCtrl("⏭ Next")

-- Playlist dropdown and quick play
local plRow = Instance.new("Frame", musicPage)
plRow.Size = UDim2.new(1,0,0,64)
plRow.Position = UDim2.new(0,0,0,380)
plRow.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", plRow).CornerRadius = UDim.new(0,12)
local plPad = Instance.new("UIPadding", plRow)
plPad.PaddingLeft = UDim.new(0,12); plPad.PaddingRight = UDim.new(0,12)

local plLabel = Instance.new("TextLabel", plRow)
plLabel.Size = UDim2.new(0,80,1,0)
plLabel.BackgroundTransparency = 1
plLabel.Text = "Playlist:"
plLabel.Font = Enum.Font.GothamBold
plLabel.TextScaled = true
plLabel.TextColor3 = Themes[settings.theme].text

local plDropdown = Instance.new("TextButton", plRow)
plDropdown.Size = UDim2.new(0, 220, 1, -12)
plDropdown.Position = UDim2.new(0, 90, 0, 6)
plDropdown.Text = "None"
plDropdown.Font = Enum.Font.Gotham
plDropdown.TextScaled = true
plDropdown.BackgroundColor3 = Themes[settings.theme].button
plDropdown.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", plDropdown).CornerRadius = UDim.new(0,8)

local dropPanel = Instance.new("Frame", musicPage)
dropPanel.Size = UDim2.new(1,0,0,200)
dropPanel.Position = UDim2.new(0,0,0, 450)
dropPanel.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", dropPanel).CornerRadius = UDim.new(0,12)
dropPanel.Visible = false

local dropScroll = Instance.new("ScrollingFrame", dropPanel)
dropScroll.Size = UDim2.new(1, -18, 1, -18)
dropScroll.Position = UDim2.new(0,9,0,9)
dropScroll.BackgroundTransparency = 1
dropScroll.ScrollBarThickness = 6
dropScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local dropLayout = Instance.new("UIListLayout", dropScroll)
dropLayout.Padding = UDim.new(0,8)

plDropdown.MouseButton1Click:Connect(function()
	for _,c in pairs(dropScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	for name,_ in pairs(playlists) do
		local b = Instance.new("TextButton", dropScroll)
		b.Size = UDim2.new(1, -12, 0, 36)
		b.Position = UDim2.new(0,6,0,0)
		b.Text = name
		b.Font = Enum.Font.Gotham
		b.TextScaled = true
		b.BackgroundColor3 = Themes[settings.theme].button
		b.TextColor3 = Themes[settings.theme].text
		Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
		b.MouseButton1Click:Connect(function()
			plDropdown.Text = name
			dropPanel.Visible = false
		end)
	end
	dropPanel.Visible = not dropPanel.Visible
end)

-- ========== Music playback ==========
local currentPlaylistName = nil
local currentIndex = 0
local currentSound : Sound? = nil

local function playSong(song)
	if currentSound then
		currentSound:Stop()
		currentSound:Destroy()
		currentSound = nil
	end

	local sid = normalizeSoundId(song.id)
	if not sid then
		nowTitle.Text = "Now Playing: Invalid ID"
		return
	end

	local s = Instance.new("Sound")
	s.Name = "NextSpotifySound"
	s.SoundId = sid
	s.Volume = 1
	s.Parent = SoundService

	local ok, err = pcall(function() s:Play() end)
	if not ok then
		nowTitle.Text = "Now Playing: Failed ("..tostring(err)..")"
		if s then s:Destroy() end
		return
	end
	currentSound = s

	-- Update Now Playing album art + title with fallback
	if song.decal and song.decal ~= "" then
		nowArt.Image = normalizeDecal(song.decal)
	else
		nowArt.Image = "rbxassetid://154834668" -- placeholder album art
	end
	nowTitle.Text = "Now Playing: "..(song.title ~= "" and song.title or tostring(song.id))
end

playPauseBtn.MouseButton1Click:Connect(function()
	if currentSound then
		if currentSound.IsPlaying then
			currentSound:Pause()
		else
			-- Resume إذا كان ممكن
			local ok = pcall(function() currentSound:Resume() end)
			if not ok then currentSound:Play() end
		end
	else
		-- حاول يشغّل أول أغنية من البلاي-ليست المختارة
		local name = plDropdown.Text
		if playlists[name] and playlists[name].songs and #playlists[name].songs > 0 then
			currentPlaylistName = name
			currentIndex = 1
			playSong(playlists[name].songs[1])
		end
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	if not currentPlaylistName then
		local chosen = plDropdown.Text
		if playlists[chosen] then currentPlaylistName = chosen end
	end
	if not currentPlaylistName or not playlists[currentPlaylistName] then return end
	local list = playlists[currentPlaylistName].songs
	if #list == 0 then return end
	currentIndex = (currentIndex % #list) + 1
	playSong(list[currentIndex])
end)

-- ========== Playlists Page ==========
setStatus("Setting up Playlists page")

local leftCol = Instance.new("Frame", playlistsPage)
leftCol.Size = UDim2.new(0.34, 0, 1, 0)
leftCol.Position = UDim2.new(0,0,0,0)
leftCol.BackgroundTransparency = 1

local rightCol = Instance.new("Frame", playlistsPage)
rightCol.Size = UDim2.new(0.66, -12, 1, 0)
rightCol.Position = UDim2.new(0.34, 12, 0, 0)
rightCol.BackgroundTransparency = 1

local createRow = Instance.new("Frame", leftCol)
createRow.Size = UDim2.new(1,0,0,60)
createRow.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", createRow).CornerRadius = UDim.new(0,10)
local createPad = Instance.new("UIPadding", createRow)
createPad.PaddingLeft = UDim.new(0,10); createPad.PaddingRight = UDim.new(0,10)
local createLayout = Instance.new("UIListLayout", createRow)
createLayout.FillDirection = Enum.FillDirection.Horizontal
createLayout.Padding = UDim.new(0,8)
createLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local newPlBox = Instance.new("TextBox", createRow)
newPlBox.Size = UDim2.new(1,-110,1,-12)
newPlBox.PlaceholderText = "New Playlist Name"
newPlBox.Font = Enum.Font.Gotham
newPlBox.TextScaled = true
newPlBox.BackgroundColor3 = Themes[settings.theme].button
newPlBox.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", newPlBox).CornerRadius = UDim.new(0,8)

local addPlButton = Instance.new("TextButton", createRow)
addPlButton.Size = UDim2.new(0,100,1,-12)
addPlButton.Text = "Add"
addPlButton.Font = Enum.Font.GothamBold
addPlButton.TextScaled = true
addPlButton.BackgroundColor3 = Themes[settings.theme].accent
addPlButton.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", addPlButton).CornerRadius = UDim.new(0,8)

local plList = Instance.new("ScrollingFrame", leftCol)
plList.Size = UDim2.new(1,0,1,-80)
plList.Position = UDim2.new(0,0,0,80)
plList.BackgroundTransparency = 1
plList.ScrollBarThickness = 6
plList.AutomaticCanvasSize = Enum.AutomaticSize.Y
local plListLayout = Instance.new("UIListLayout", plList)
plListLayout.Padding = UDim.new(0,8)

addPlButton.MouseButton1Click:Connect(function()
	local name = string.gsub(newPlBox.Text or "", "^%s*(.-)%s*$", "%1")
	if name ~= "" then
		if not playlists[name] then
			playlists[name] = { songs = {} }
			newPlBox.Text = ""
			if plDropdown.Text == "None" then plDropdown.Text = name end
			rebuildPlaylistList()
		end
	end
end)

rebuildPlaylistList = function()
	for _,c in pairs(plList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	for name,_ in pairs(playlists) do
		local b = Instance.new("TextButton", plList)
		b.Size = UDim2.new(1, -10, 0, 44)
		b.Position = UDim2.new(0,5,0,0)
		b.Text = name
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.BackgroundColor3 = Themes[settings.theme].button
		b.TextColor3 = Themes[settings.theme].text
		Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
		b.MouseButton1Click:Connect(function()
			plDropdown.Text = name
			selectedPlaylist = name
			currentPlaylistName = name
			refreshSongsGrid()
		end)
	end
end

-- Right column: add song + songs grid
local addSongRow = Instance.new("Frame", rightCol)
addSongRow.Size = UDim2.new(1,0,0,64)
addSongRow.BackgroundColor3 = Themes[settings.theme].panel
Instance.new("UICorner", addSongRow).CornerRadius = UDim.new(0,10)
local addPad = Instance.new("UIPadding", addSongRow)
addPad.PaddingLeft = UDim.new(0,10); addPad.PaddingRight = UDim.new(0,10)
local addLayout = Instance.new("UIListLayout", addSongRow)
addLayout.FillDirection = Enum.FillDirection.Horizontal
addLayout.Padding = UDim.new(0,8)
addLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local songTitleBox = Instance.new("TextBox", addSongRow)
songTitleBox.Size = UDim2.new(0.30,0,1,-12)
songTitleBox.PlaceholderText = "Title (optional)"
songTitleBox.Font = Enum.Font.Gotham
songTitleBox.TextScaled = true
songTitleBox.BackgroundColor3 = Themes[settings.theme].button
songTitleBox.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", songTitleBox).CornerRadius = UDim.new(0,8)

local songIdBox = Instance.new("TextBox", addSongRow)
songIdBox.Size = UDim2.new(0.25,0,1,-12)
songIdBox.PlaceholderText = "Song ID"
songIdBox.Font = Enum.Font.Gotham
songIdBox.TextScaled = true
songIdBox.BackgroundColor3 = Themes[settings.theme].button
songIdBox.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", songIdBox).CornerRadius = UDim.new(0,8)

local decalBox = Instance.new("TextBox", addSongRow)
decalBox.Size = UDim2.new(0.30,0,1,-12)
decalBox.PlaceholderText = "Album Decal ID/URL"
decalBox.Font = Enum.Font.Gotham
decalBox.TextScaled = true
decalBox.BackgroundColor3 = Themes[settings.theme].button
decalBox.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", decalBox).CornerRadius = UDim.new(0,8)

local addSongButton = Instance.new("TextButton", addSongRow)
addSongButton.Size = UDim2.new(0.12,0,1,-12)
addSongButton.Text = "Add Song"
addSongButton.Font = Enum.Font.GothamBold
addSongButton.TextScaled = true
addSongButton.BackgroundColor3 = Themes[settings.theme].accent
addSongButton.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", addSongButton).CornerRadius = UDim.new(0,8)

local songsPanel = Instance.new("ScrollingFrame", rightCol)
songsPanel.Size = UDim2.new(1,0,1,-84)
songsPanel.Position = UDim2.new(0,0,0,84)
songsPanel.BackgroundTransparency = 1
songsPanel.ScrollBarThickness = 8
songsPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
local grid = Instance.new("UIGridLayout", songsPanel)
grid.CellPadding = UDim2.new(0,12,0,12)
grid.CellSize = UDim2.new(0, 420, 0, 100)
grid.SortOrder = Enum.SortOrder.LayoutOrder

addSongButton.MouseButton1Click:Connect(function()
	if not selectedPlaylist then
		-- إذا ما اخترنا بلاي-ليست، خليه الافتراضي أو اللي في الدروبداون
		selectedPlaylist = plDropdown.Text ~= "None" and plDropdown.Text or "Default"
		if not playlists[selectedPlaylist] then playlists[selectedPlaylist] = { songs = {} } end
	end
	local id = string.gsub(songIdBox.Text or "", "^%s*(.-)%s*$", "%1")
	if id == "" then return end
	local title = string.gsub(songTitleBox.Text or "", "^%s*(.-)%s*$", "%1")
	local decal = string.gsub(decalBox.Text or "", "^%s*(.-)%s*$", "%1")
	table.insert(playlists[selectedPlaylist].songs, {
		id = id,
		decal = decal,
		title = title
	})
	songIdBox.Text, songTitleBox.Text, decalBox.Text = "", "", ""
	refreshSongsGrid()
end)

refreshSongsGrid = function()
	for _,c in pairs(songsPanel:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	if not selectedPlaylist or not playlists[selectedPlaylist] then return end
	for i, song in ipairs(playlists[selectedPlaylist].songs) do
		local card = Instance.new("Frame", songsPanel)
		card.Size = UDim2.new(1,0,0,100)
		card.BackgroundColor3 = Themes[settings.theme].panel
		Instance.new("UICorner", card).CornerRadius = UDim.new(0,10)

		local pad = Instance.new("UIPadding", card)
		pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10); pad.PaddingTop = UDim.new(0,10); pad.PaddingBottom = UDim.new(0,10)

		local list = Instance.new("UIListLayout", card)
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0,10)
		list.VerticalAlignment = Enum.VerticalAlignment.Center

		-- Album art (with fallback)
		local art = Instance.new("ImageLabel", card)
		art.Size = UDim2.new(0,80,1,-20)
		art.BackgroundTransparency = 1
		if song.decal and song.decal ~= "" then
			art.Image = normalizeDecal(song.decal)
		else
			art.Image = "rbxassetid://154834668"
		end

		-- Info (title + ID)
		local info = Instance.new("Frame", card)
		info.Size = UDim2.new(1, -240, 1, 0)
		info.BackgroundTransparency = 1
		local v = Instance.new("UIListLayout", info)
		v.FillDirection = Enum.FillDirection.Vertical
		v.Padding = UDim.new(0,6)

		local titleL = Instance.new("TextLabel", info)
		titleL.Size = UDim2.new(1,0,0,28)
		titleL.BackgroundTransparency = 1
		titleL.Font = Enum.Font.GothamBold
		titleL.TextScaled = true
		titleL.TextXAlignment = Enum.TextXAlignment.Left
		titleL.Text = (song.title and song.title ~= "" and song.title or ("ID: "..tostring(song.id)))
		titleL.TextColor3 = Themes[settings.theme].text

		local idL = Instance.new("TextLabel", info)
		idL.Size = UDim2.new(1,0,0,20)
		idL.BackgroundTransparency = 1
		idL.Font = Enum.Font.Gotham
		idL.TextScaled = true
		idL.TextXAlignment = Enum.TextXAlignment.Left
		idL.Text = "Song ID: "..tostring(song.id)
		idL.TextColor3 = Themes[settings.theme].muted

		-- Actions (Play + Remove)
		local actions = Instance.new("Frame", card)
		actions.Size = UDim2.new(0,200,1,0)
		actions.BackgroundTransparency = 1
		local actionsList = Instance.new("UIListLayout", actions)
		actionsList.FillDirection = Enum.FillDirection.Vertical
		actionsList.Padding = UDim.new(0,8)
		actionsList.VerticalAlignment = Enum.VerticalAlignment.Center

		local playB = Instance.new("TextButton", actions)
		playB.Size = UDim2.new(1,0,0,28)
		playB.Text = "Play"
		playB.Font = Enum.Font.GothamBold
		playB.TextScaled = true
		playB.BackgroundColor3 = Themes[settings.theme].accent
		playB.TextColor3 = Color3.fromRGB(255,255,255)
		Instance.new("UICorner", playB).CornerRadius = UDim.new(0,6)
		playB.MouseButton1Click:Connect(function()
			currentPlaylistName = selectedPlaylist
			currentIndex = i
			playSong(song)
		end)

		local rmB = Instance.new("TextButton", actions)
		rmB.Size = UDim2.new(1,0,0,28)
		rmB.Text = "Remove"
		rmB.Font = Enum.Font.Gotham
		rmB.TextScaled = true
		rmB.BackgroundColor3 = Themes[settings.theme].button
		rmB.TextColor3 = Themes[settings.theme].text
		Instance.new("UICorner", rmB).CornerRadius = UDim.new(0,6)
		rmB.MouseButton1Click:Connect(function()
			table.remove(playlists[selectedPlaylist].songs, i)
			refreshSongsGrid()
		end)
	end
end

-- ========== Settings Page ==========
setStatus("Setting up Settings page")

local function section(titleText, parent)
	parent = parent or settingsPage
	local f = Instance.new("Frame", parent)
	f.Size = UDim2.new(1,0,0,86)
	f.BackgroundColor3 = Themes[settings.theme].panel
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,12)
	local label = Instance.new("TextLabel", f)
	label.Size = UDim2.new(1,-24,0,38)
	label.Position = UDim2.new(0,12,0,8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = titleText
	label.TextColor3 = Themes[settings.theme].text
	return f, label
end

-- Theme section
local themeFrame, _ = section("Theme")
themeFrame.Position = UDim2.new(0,0,0,0)
local themeButtons = Instance.new("Frame", themeFrame)
themeButtons.Size = UDim2.new(1,-24,0,40)
themeButtons.Position = UDim2.new(0,12,0,44)
themeButtons.BackgroundTransparency = 1
local themeLayout = Instance.new("UIListLayout", themeButtons)
themeLayout.FillDirection = Enum.FillDirection.Horizontal
themeLayout.Padding = UDim.new(0,12)

local darkBtn = Instance.new("TextButton", themeButtons)
darkBtn.Size = UDim2.new(0.5,0,1,0)
darkBtn.Text = "Dark"
darkBtn.Font = Enum.Font.GothamBold
darkBtn.TextScaled = true
darkBtn.BackgroundColor3 = Themes.Dark.panel
darkBtn.TextColor3 = Themes.Dark.text
Instance.new("UICorner", darkBtn).CornerRadius = UDim.new(0,10)

local lightBtn = Instance.new("TextButton", themeButtons)
lightBtn.Size = UDim2.new(0.5,0,1,0)
lightBtn.Text = "Light"
lightBtn.Font = Enum.Font.GothamBold
lightBtn.TextScaled = true
lightBtn.BackgroundColor3 = Themes.Light.panel
lightBtn.TextColor3 = Themes.Light.text
Instance.new("UICorner", lightBtn).CornerRadius = UDim.new(0,10)

-- Keybind section
local keyFrame, keyLabel = section("Toggle Keybind")
keyFrame.Position = UDim2.new(0,0,0,110)
local kbRow = Instance.new("TextButton", keyFrame)
kbRow.Size = UDim2.new(1,-24,0,44)
kbRow.Position = UDim2.new(0,12,0,40)
kbRow.Text = "Current: "..tostring(settings.toggleKey).."  (Click to set)"
kbRow.Font = Enum.Font.Gotham
kbRow.TextScaled = true
kbRow.BackgroundColor3 = Themes[settings.theme].panel
kbRow.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", kbRow).CornerRadius = UDim.new(0,10)

-- JSON export/import section
local jsonFrame, jsonLabel = section("Export / Import")
jsonFrame.Position = UDim2.new(0,0,0,220)
local jsonBox = Instance.new("TextBox", jsonFrame)
jsonBox.Size = UDim2.new(1,-150,0,118)
jsonBox.Position = UDim2.new(0,12,0, 44)
jsonBox.MultiLine = true
jsonBox.ClearTextOnFocus = false
jsonBox.Text = ""
jsonBox.PlaceholderText = "Exported JSON will appear here"
jsonBox.Font = Enum.Font.Code
jsonBox.TextScaled = true
jsonBox.BackgroundColor3 = Themes[settings.theme].button
jsonBox.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", jsonBox).CornerRadius = UDim.new(0,8)

local exportBtn = Instance.new("TextButton", jsonFrame)
exportBtn.Size = UDim2.new(0,120,0,48)
exportBtn.Position = UDim2.new(1,-130,0,44)
exportBtn.Text = "Export"
exportBtn.Font = Enum.Font.GothamBold
exportBtn.TextScaled = true
exportBtn.BackgroundColor3 = Themes[settings.theme].accent
exportBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", exportBtn).CornerRadius = UDim.new(0,8)

local importBtn = Instance.new("TextButton", jsonFrame)
importBtn.Size = UDim2.new(0,120,0,48)
importBtn.Position = UDim2.new(1,-130,0,100)
importBtn.Text = "Import"
importBtn.Font = Enum.Font.GothamBold
importBtn.TextScaled = true
importBtn.BackgroundColor3 = Themes[settings.theme].button
importBtn.TextColor3 = Themes[settings.theme].text
Instance.new("UICorner", importBtn).CornerRadius = UDim.new(0,8)

local statusLabelSettings = Instance.new("TextLabel", jsonFrame)
statusLabelSettings.Size = UDim2.new(0,120,0,28)
statusLabelSettings.Position = UDim2.new(1,-130,0,156)
statusLabelSettings.BackgroundTransparency = 1
statusLabelSettings.Font = Enum.Font.Gotham
statusLabelSettings.TextScaled = true
statusLabelSettings.TextColor3 = Themes[settings.theme].text
statusLabelSettings.Text = ""

-- ========== Settings logic ==========
local function applyTheme(themeName)
	if not Themes[themeName] then return end
	settings.theme = themeName
	local th = Themes[themeName]

	-- basics
	mainFrame.BackgroundColor3 = th.bg
	topBar.BackgroundColor3 = th.panel
	mainStroke.Color = th.panel
	resizeHandle.BackgroundColor3 = th.accent
	logo.TextColor3 = th.text

	-- update elements recursively
	local function applyRecursive(obj)
		for _,c in ipairs(obj:GetChildren()) do
			if c:IsA("TextLabel") then c.TextColor3 = th.text
			elseif c:IsA("TextBox") then c.BackgroundColor3 = th.button; c.TextColor3 = th.text
			elseif c:IsA("TextButton") then
				if c == exportBtn or c == addPlButton or c == addSongButton or c == playPauseBtn or c == nextBtn then
					c.BackgroundColor3 = th.accent
					c.TextColor3 = Color3.new(1,1,1)
				else
					c.BackgroundColor3 = th.button
					c.TextColor3 = th.text
				end
			elseif c:IsA("Frame") then
				if c.BackgroundTransparency < 1 then
					c.BackgroundColor3 = th.panel
				end
			end
			applyRecursive(c)
		end
	end
	applyRecursive(mainFrame)
end

darkBtn.MouseButton1Click:Connect(function() applyTheme("Dark") end)
lightBtn.MouseButton1Click:Connect(function() applyTheme("Light") end)

-- Keybind setting
kbRow.MouseButton1Click:Connect(function()
	kbRow.Text = "Press any key..."
	local conn
	conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			settings.toggleKey = input.KeyCode
			kbRow.Text = "Current: "..tostring(settings.toggleKey).."  (Click to set)"
			conn:Disconnect()
		end
	end)
end)

-- Toggle UI on keypress
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == settings.toggleKey then
		screenGui.Enabled = not screenGui.Enabled
	end
end)

-- Export JSON
exportBtn.MouseButton1Click:Connect(function()
	local data = {
		settings = {
			theme = settings.theme,
			toggleKey = tostring(settings.toggleKey)
		},
		playlists = playlists
	}
	local encoded = HttpService:JSONEncode(data)
	jsonBox.Text = encoded
	statusLabelSettings.Text = safeSetClipboard(encoded) and "Copied to clipboard" or "Exported (no clipboard)"
	task.delay(2, function() statusLabelSettings.Text = "" end)
end)

-- helper لتحويل النص إلى KeyCode
local function keycodeFromString(keyName)
	if Enum.KeyCode[keyName] then
		return Enum.KeyCode[keyName]
	end
	for _,k in ipairs(Enum.KeyCode:GetEnumItems()) do
		if k.Name == keyName then
			return k
		end
	end
	return nil
end

-- Import JSON
importBtn.MouseButton1Click:Connect(function()
	local text = jsonBox.Text
	if not text or text == "" then
		statusLabelSettings.Text = "Paste JSON into box"
		task.delay(2, function() statusLabelSettings.Text = "" end)
		return
	end
	local ok, parsed = pcall(function() return HttpService:JSONDecode(text) end)
	if not ok or type(parsed) ~= "table" then
		statusLabelSettings.Text = "Invalid JSON"
		task.delay(2, function() statusLabelSettings.Text = "" end)
		return
	end
	-- apply settings
	if parsed.settings then
		if parsed.settings.theme and Themes[parsed.settings.theme] then settings.theme = parsed.settings.theme end
		if parsed.settings.toggleKey and type(parsed.settings.toggleKey) == "string" then
			local keyName = tostring(parsed.settings.toggleKey):gsub("Enum.KeyCode.", "")
			local kc = keycodeFromString(keyName)
			if kc then settings.toggleKey = kc end
		end
	end
	-- apply playlists (validate basic structure)
	if parsed.playlists and type(parsed.playlists) == "table" then
		playlists = {}
		for name,info in pairs(parsed.playlists) do
			if type(info) == "table" and type(info.songs) == "table" then
				playlists[name] = { songs = {} }
				for _,s in ipairs(info.songs) do
					if s.id then
						table.insert(playlists[name].songs, {
							id = tostring(s.id),
							decal = normalizeDecal(s.decal or ""),
							title = tostring(s.title or "")
						})
					end
				end
			end
		end
	end
	rebuildPlaylistList()
	refreshSongsGrid()
	applyTheme(settings.theme)
	statusLabelSettings.Text = "Imported"
	task.delay(2, function() statusLabelSettings.Text = "" end)
end)

-- ========== Misc init ==========
setStatus("Finalizing")
rebuildPlaylistList()
refreshSongsGrid()
applyTheme(settings.theme)

-- Click-away closing for dropdown
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if dropPanel.Visible then
		local m = UserInputService:GetMouseLocation()
		local inDrop = (m.X >= dropPanel.AbsolutePosition.X and m.X <= dropPanel.AbsolutePosition.X + dropPanel.AbsoluteSize.X and
			m.Y >= dropPanel.AbsolutePosition.Y and m.Y <= dropPanel.AbsolutePosition.Y + dropPanel.AbsoluteSize.Y)
		local inBtn = (m.X >= plDropdown.AbsolutePosition.X and m.X <= plDropdown.AbsolutePosition.X + plDropdown.AbsoluteSize.X and
			m.Y >= plDropdown.AbsolutePosition.Y and m.Y <= plDropdown.AbsolutePosition.Y + plDropdown.AbsoluteSize.Y)
		if not inDrop and not inBtn then dropPanel.Visible = false end
	end
end)

-- ========== Finish loading (fade out) ==========
setStatus("Ready")
task.wait(0.15)
alive = false
local t1 = TweenService:Create(loadingFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
t1:Play()
t1.Completed:Wait()
loadingFrame:Destroy()
blur:Destroy()

-- End of script
