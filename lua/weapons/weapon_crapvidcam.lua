AddCSLuaFile()

--[[

    "I'm going CRAZY with the amount of sausage I'm making!"
		-Alsmiffy

--]]

local VidCamMdl = "models/dav0r/camera.mdl"

-- terrible workaround to stop crashes from clicking with gmod_camera while recording
CreateConVar("__crapvidcam_recording", "0", FCVAR_ARCHIVE + FCVAR_USERINFO, "jpeg crash fix, don't worry about it :)", 0, 1)
hook.Add("InitPostEntity", "CrapVidCam.FixCameraCrash", function()
	local gmodcam = weapons.GetStored("gmod_camera")
	if gmodcam then
		function gmodcam:PrimaryAttack()
			self:DoShootEffect()
			if not game.SinglePlayer() and SERVER then return end
			if CLIENT and not IsFirstTimePredicted() then return end
			local ply = self:GetOwner()
			if ply:GetInfoNum("__crapvidcam_recording", 0) ~= 0 then return end
			ply:ConCommand("jpeg")
		end
	end
end)

sound.Add({
	name = "CrapVidCam.ToggleCamera",
	channel = CHAN_WEAPON,
	volume = 0.5,
	level = 70,
	pitch = 112,
	sound = "buttons/lightswitch2.wav",
})

SWEP.PrintName = "Crappy Video Camera"
SWEP.Instructions = [[
<color=green>[LMB]</color> Start/stop recording

<color=#00ffff>Videos will be saved in your garrysmod/videos folder in WEBM format.</color>]]

if CLIENT then
	SWEP.WepSelectIcon = surface.GetTextureID("crapvidcam/vidcamicon")

	VIDCAM_CVARS = {
		HOLSTER_STOP = CreateClientConVar("crapvidcam_holsterstop", "0", true, false, "Stop recording after changing weapons", 0, 1),
		DEATH_DROP = CreateClientConVar("crapvidcam_deathdrop", "1", true, false, "Drop camera on death and continue recording until you respawn", 0, 1),
		FOV = CreateClientConVar("crapvidcam_fov", "0.5", true, false, "How much to zoom the camera in. Smaller number = More zoomed in", 0.05, 1),
		ONLY_AUDIO = CreateClientConVar("crapvidcam_onlyaudio", "0", true, false, "Record only audio (NO VIDEO) in .ogv format", 0, 1),
		LOCK_FPS = CreateClientConVar("crapvidcam_lockfps", "0", true, false, "If non-zero, lock fps to this number", 0, 60),
		BITRATE = CreateClientConVar("crapvidcam_bitrate", "30", true, false, "Video recording bitrate, in bits per second", 0, 65536),
		WIDTH = CreateClientConVar("crapvidcam_width", "480", true, false, "Video width override, in pixels. 0 = automatic", 0, 7680),
		DSP = CreateClientConVar("crapvidcam_dsp", "38", true, false, "Type of distortion to apply to recorded sound. See https://wiki.facepunch.com/gmod/DSP_Presets", 0, 133),
	}
end

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.HoldType = "rpg"

SWEP.WorldModel = VidCamMdl
SWEP.ViewModel = VidCamMdl
SWEP.ViewModelFOV = 55
SWEP.UseHands = false

SWEP.Slot = 4
SWEP.SlotPos = 3

SWEP.Primary.Ammo = "none"
SWEP.Primary.Automatic = false
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1

SWEP.Secondary.Ammo = "none"
SWEP.Secondary.Automatic = false
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1

SWEP.DrawCrosshair = false
SWEP.CrappyVideoCamera = true

function SWEP:Initialize()
	self:SetHoldType("rpg")
end

function SWEP:CanSecondaryAttack() return false end

function SWEP:PrimaryAttack()
	if SERVER and game.SinglePlayer() then
		self:CallOnClient("PrimaryAttack")
		return
	end

	local curtime = CurTime()
	if curtime < self:GetNextPrimaryFire() then return end
	self:SetNextPrimaryFire(curtime + 0.1)
	self:EmitSound("CrapVidCam.ToggleCamera")

	if CLIENT and (IsFirstTimePredicted() or game.SinglePlayer()) then
		VIDCAM_TOGGLE()
	end
end

function SWEP:Holster()
	if SERVER and game.SinglePlayer() then
		self:CallOnClient("Holster")
	end

	if CLIENT and VIDCAM_CVARS.HOLSTER_STOP:GetBool() then
		if (IsFirstTimePredicted() or game.SinglePlayer()) and LocalPlayer() == self:GetOwner() and VIDCAM_WRITER then
			VIDCAM_TOGGLE()
		end
	end

	return true
end

if SERVER then return end

--[[

=============================================================================================================================
=============================================================================================================================
	clientside bullshit beyond this point
=============================================================================================================================
=============================================================================================================================

--]]

function SWEP:ShouldDrawViewModel()
	return not VIDCAM_WRITER
end

function SWEP:DrawWorldModel()
	local ply = self:GetOwner()
	if IsValid(ply) then
		local attid = ply:LookupAttachment("anim_attachment_RH")
		if attid > 0 then
			local att = ply:GetAttachment(attid)
			if att then
				local ang = att.Ang
				self:SetPos(att.Pos + ang:Up() * 10 + ang:Right() + ang:Forward() * 2)
				self:SetAngles(ang)
				self:SetupBones()
			end
		end
	end
	self:DrawModel()
end

local camPos = Vector(16, 30, -6)

function SWEP:GetViewModelPosition(pos, ang)
	pos:Add(camPos[1] * ang:Right())
	pos:Add(camPos[2] * ang:Forward())
	pos:Add(camPos[3] * ang:Up())
	return pos, ang
end

local clrErr, clrSave = Color(255, 0, 0), Color(0, 255, 255)
VIDCAM_CONFIG = {video = "vp8", audio = "vorbis", quality = 0}

function VIDCAM_TOGGLE(trySimpleRes)
	local ply = LocalPlayer()
	local bAudio = VIDCAM_CVARS.ONLY_AUDIO:GetBool()
	if VIDCAM_WRITER then
		hook.Remove("PreDrawHUD", "CrapVidCam")
		chat.AddText(clrSave, "Saved " .. (bAudio and "audio" or "video") .. " to garrysmod/videos/" .. VIDCAM_CONFIG.name .. "." .. (bAudio and "ogv" or "webm"))
		VIDCAM_WRITER:Finish()
		VIDCAM_WRITER = nil -- memory leak???
		ply:SetDSP(0, true)
		if IsValid(VIDCAM_DATA.DEATH_CAMERA) then
			SafeRemoveEntityDelayed(VIDCAM_DATA.DEATH_CAMERA, 0)
		end
		ply:ConCommand("__crapvidcam_recording 0")
	else
		VIDCAM_CONFIG.container = bAudio and "ogg" or "webm"
		VIDCAM_CONFIG.name = "vidcam-" .. util.DateStamp()
		VIDCAM_CONFIG.bitrate = VIDCAM_CVARS.BITRATE:GetInt()
		local fps = VIDCAM_CVARS.LOCK_FPS:GetInt()
		VIDCAM_CONFIG.fps = fps > 0 and fps or 24
		VIDCAM_CONFIG.lockfps = fps > 0
		if trySimpleRes then
			VIDCAM_CONFIG.width = 480
			VIDCAM_CONFIG.height = 360
		else
			VIDCAM_CONFIG.width = VIDCAM_CVARS.WIDTH:GetInt()
			local w, h = ScrW(), ScrH()
			if VIDCAM_CONFIG.width == 0 or VIDCAM_CONFIG.width > w then
				VIDCAM_CONFIG.width = w
			end
			VIDCAM_CONFIG.height = VIDCAM_CONFIG.width * (h / w)
		end
		VIDCAM_WRITER, VIDCAM_ERROR = video.Record(VIDCAM_CONFIG)
		if VIDCAM_WRITER and VIDCAM_ERROR then
			VIDCAM_WRITER:Finish()
			VIDCAM_WRITER = nil
		end
		if VIDCAM_WRITER then
			chat.AddText(clrSave, "Started recording at " .. VIDCAM_CONFIG.width .. "x" .. VIDCAM_CONFIG.height .. "...")
			VIDCAM_WRITER:SetRecordSound(true)
			VIDCAM_DATA = {
				DEATH_TIME = 0,
				DEATH_CAMERA = NULL,
				VIEW_POS = Vector(0, 0, 0),
				VIEW_VEL = Vector(0, 0, 0),
				VIEW_ANG = Angle(0, 0, 0),
			}
			hook.Add("PreDrawHUD", "CrapVidCam", function()
				if VIDCAM_WRITER then
					local ft = FrameTime()
					if ply:Alive() and ply:Health() > 0 then
						if IsValid(VIDCAM_DATA.DEATH_CAMERA) then
							VIDCAM_TOGGLE()
							return
						end
						VIDCAM_DATA.VIEW_VEL:Set(ply:GetVelocity())
						VIDCAM_DATA.VIEW_POS:Set(ply:EyePos())
						VIDCAM_DATA.VIEW_ANG:Set(ply:EyeAngles())
					else
						if VIDCAM_CVARS.DEATH_DROP:GetBool() then
							if not IsValid(VIDCAM_DATA.DEATH_CAMERA) then
								VIDCAM_DATA.DEATH_CAMERA = ents.CreateClientProp(VidCamMdl)
								VIDCAM_DATA.DEATH_CAMERA:SetPos(VIDCAM_DATA.VIEW_POS)
								VIDCAM_DATA.DEATH_CAMERA:SetAngles(VIDCAM_DATA.VIEW_ANG)
								VIDCAM_DATA.DEATH_CAMERA:SetNoDraw(true)
								VIDCAM_DATA.DEATH_CAMERA:Spawn()
								local phys = VIDCAM_DATA.DEATH_CAMERA:GetPhysicsObject()
								if IsValid(phys) then
									phys:SetVelocity(VIDCAM_DATA.VIEW_VEL)
								end
								return
							end
						else
							VIDCAM_DATA.DEATH_TIME = VIDCAM_DATA.DEATH_TIME + ft
							if VIDCAM_DATA.DEATH_TIME >= 0.2 then
								VIDCAM_TOGGLE()
								return
							end
						end
					end
					VIDCAM_WRITER:AddFrame(ft, true)
					ply:SetDSP(VIDCAM_CVARS.DSP:GetInt(), true)
				end
			end)
			if math.random(1337) == 420 then
				surface.PlaySound("crappy_video_camera.mp3")
				-- find my pages
				--    0
				--   /|\
				--  / | \
				-- | /\ |
				--  /  \
				-- |   |
			end
			ply:ConCommand("__crapvidcam_recording 1")
		else
			chat.AddText(clrErr, "Couldn't record video (" .. VIDCAM_CONFIG.width .. "x" .. VIDCAM_CONFIG.height .. "): " .. VIDCAM_ERROR)
			if not trySimpleRes then
				chat.AddText(clrErr, "Retrying with 480x360 resolution...")
				VIDCAM_TOGGLE(true)
			end
		end
	end
end

concommand.Add("crapvidcam_record", function(ply, cmd, args)
	VIDCAM_TOGGLE()
end, nil, "Start/stop recording")

local clrRec, clrRecB = Color(255, 100, 100), Color(20, 20, 20)
hook.Add("HUDPaint", "CrapVidCam", function()
	if VIDCAM_WRITER then
		if math.sin(CurTime() * 8) > 0 then
			draw.SimpleTextOutlined("RECORDING", "DermaLarge", ScrW() * 0.5, 0, clrRec, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, clrRecB)
		end
	end
end)

hook.Add("CalcView", "CrapVidCam", function(ply, pos, ang, fov)
	if VIDCAM_WRITER then
		if ply:Health() < 1 or not ply:Alive() then
			if IsValid(VIDCAM_DATA.DEATH_CAMERA) then
				pos:Set(VIDCAM_DATA.DEATH_CAMERA:GetPos())
				ang:Set(VIDCAM_DATA.DEATH_CAMERA:GetAngles())
			else
				pos:Set(VIDCAM_DATA.VIEW_POS)
				ang:Set(VIDCAM_DATA.VIEW_ANG)
			end
		end
		return {
			origin = pos,
			angles = ang,
			fov = fov * VIDCAM_CVARS.FOV:GetFloat()
		}
	end
end)

local defaultCvars = {
	crapvidcam_holsterstop = 0,
	crapvidcam_deathdrop = 1,
	crapvidcam_fov = 0.5,
	crapvidcam_onlyaudio = 0,
	crapvidcam_lockfps = 0,
	crapvidcam_bitrate = 30,
	crapvidcam_width = 480,
	crapvidcam_dsp = 38,
}

hook.Add("PopulateToolMenu", "CrapVidCam.Options", function()
	spawnmenu.AddToolMenuOption("Utilities", "User", "CrapVidCam", "#Crappy Video Camera", "", "", function(form)
		form:Help("Clientside Video Camera settings. These settings save over multiple sessions.")
		form:ToolPresets("util_crapvidcam_cl", defaultCvars)
		form:ControlHelp("These settings are experimental and only here due to popular demand. If something goes wrong after adjusting these settings, it's on you!")
		form:NumSlider("Zoom level (FOV)", "crapvidcam_fov", 0.05, 1)
		form:Help("Note: Locking FPS below 30 requires sv_cheats 1.")
		form:NumSlider("Lock FPS (0 = don't lock)", "crapvidcam_lockfps", 0, 60, 0)
		form:NumSlider("Bitrate", "crapvidcam_bitrate", 0, 65536, 0)
		form:Help("Note: You must use a lower resolution than you are running the game.")
		local resBoxW = form:ComboBox("Video width", "crapvidcam_width")
		resBoxW:SetSortItems(false)
		resBoxW:AddChoice("Auto", 0)
		resBoxW:AddChoice("60px", 60)
		resBoxW:AddChoice("120px", 120)
		resBoxW:AddChoice("180px", 180)
		resBoxW:AddChoice("240px", 240)
		resBoxW:AddChoice("360px", 360)
		resBoxW:AddChoice("480px", 480)
		resBoxW:AddChoice("640px", 640)
		resBoxW:AddChoice("720px", 720)
		resBoxW:AddChoice("960px", 960)
		resBoxW:AddChoice("1080px", 1080)
		resBoxW:AddChoice("1280px", 1280)
		resBoxW:AddChoice("1440px", 1440)
		resBoxW:AddChoice("1920px", 1920)
		local dspBox = form:ComboBox("Sound distortion", "crapvidcam_dsp")
		dspBox:AddChoice("Extra clean", 0)
		dspBox:AddChoice("No distortion", 1)
		dspBox:AddChoice("Crunchy (default)", 38)
		dspBox:AddChoice("Weird 1", 26)
		dspBox:AddChoice("Weird 2", 47)
		dspBox:AddChoice("Speaker tiny", 56)
		dspBox:AddChoice("Speaker small", 58)
		dspBox:AddChoice("Speaker medium", 55)
		dspBox:AddChoice("Speaker large", 57)
		form:CheckBox("Stop recording when holstered", "crapvidcam_holsterstop")
		form:CheckBox("Drop camera on death", "crapvidcam_deathdrop")
		form:CheckBox("ONLY record audio (NO video)", "crapvidcam_onlyaudio")
	end)
end)
