print("sh_combat_roll loaded")

local clientInMultiplayer = (CLIENT and !game.SinglePlayer())
local singleplayer = game.SinglePlayer()
local pingCorrected = false -- client var

CreateConVar("sv_combatroll_fraction", 1.3, {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast the rolling action will happen.")
CreateConVar("sv_combatroll_maxspeed_offset", -100, {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "On landing if you have higher speed than a certain value, you wont be able to roll and you will die. You can offset it and save yourself! (only works with realistic fall damage enabled. otherwise you can roll always)")

sound.Add( {
	name = "sound_combatroll",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 55,
	pitch = {95, 110},
	sound = {"combatroll/roll1.wav","combatroll/roll2.wav","combatroll/roll3.wav","combatroll/roll4.wav"}
} )

sound.Add( {
	name = "sound_combatroll_land",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 70,
	pitch = {95, 110},
	sound = {"combatroll/land.wav"}
} )

if SERVER then
	util.AddNetworkString("combat_roll")
	util.AddNetworkString("singleplayer_gay_networking")

	local function sendUpdate(ply)
		net.Start("combat_roll")
			net.WriteFloat(ply.cr_time)
		net.Send(ply)
	end

	hook.Add("PlayerSpawn", "combat_roll_playerspawn", function(ply,transition)
		ply.cr_time = 1
		sendUpdate(ply)
	end)

	hook.Add("PlayerDeath", "combat_roll_sanity", function(ply, inflictor, attacker) 
		ply.cr_time = 1
		sendUpdate(ply)
	end)

	hook.Add("GetFallDamage", "combat_roll_falldamage", function(ply,speed)
		if ply.cr_time != 1 then
			return 0
		end

        local tracedown = util.TraceLine( {
            start = ply:EyePos(),
            endpos = ply:EyePos() + Vector(0, 0, -1000),
            filter = ply
        } )

        if IsValid(tracedown.Entity) then
        	if string.match(tracedown.Entity:GetModel(), "wood_pallet") or string.match(tracedown.Entity:GetModel(), "wood_crate") then
        		tracedown.Entity:SetHealth(1000)
        		ply:ViewPunch(Angle(10, math.random(-10, 10), math.random(-10, 10)))
        		ply:EmitSound("sound_combatroll_land")
        		timer.Simple(1, function()
        			tracedown.Entity:SetHealth(tracedown.Entity:GetMaxHealth())
        		end)
        		return 0
        	end
        end
	end)

	hook.Add("OnPlayerHitGround", "combat_roll_hitground", function(ply, inWater, onFloater, speed)
		local minSpeed = 300
		-- we got 92250 by solving this equation ( x - 526.5 ) * ( 100 / 396 ) = 100
		local maxSpeed = 92250 / ply:Health() + GetConVar("sv_combatroll_maxspeed_offset"):GetFloat()

		if not GetConVar("mp_falldamage"):GetBool() then maxSpeed = 1000000 end

		if ply:KeyDown(IN_DUCK) and speed >= minSpeed and speed <= maxSpeed then
			local vel = ply:GetVelocity()
			vel.z = 0
			local altSpeed = vel:Length()
			if altSpeed <= 150 then ply:ViewPunch(Angle(10,0,0)) end

			ply.cr_time = 0
    		ply:EmitSound("sound_combatroll")

			sendUpdate(ply)
		end
	end)
end

if CLIENT then 
	local is_calc = false
	local rollAnim = false

	hook.Add("InitPostEntity", "combat_roll_sanity_client", function()
		LocalPlayer().cr_time = 0
	end)

	if singleplayer then
		net.Receive("singleplayer_gay_networking", function() 
			LocalPlayer().cr_time = net.ReadFloat()
		end)
	end

	net.Receive("combat_roll", function() 
		LocalPlayer().cr_time = net.ReadFloat()
	end)

	hook.Add("CalcView", "combat_roll_calcview", function(ply, origin, angles, fov, znear, zfar)
		if ply.cr_time != 1 and ply.cr_time != 0 then
			if in_mantle == nil then in_mantle = false end
			if is_calc or in_mantle then return end
			is_calc = true
			local view = hook.Run("CalcView", ply, origin, angles, fov, znear, zfar) or {} 
			is_calc = false
			view.origin	= view.origin or pos							   
			view.angles	= view.angles or ang
			view.fov = view.fov or fov
			view.znear = view.znear or znear
			view.zfar = view.zfar or zfar

			local vel = ply:GetVelocity()
			vel.z = 0
			local altSpeed = vel:Length()
			if altSpeed > 150 then rollAnim = true end

			if rollAnim then 
				ply.cr_lerpFrom = view.angles
				ply.cr_lerpTo = ply.cr_lerpFrom + Angle(360,0,0)
				view.angles = Lerp(math.ease.OutCubic(ply.cr_time), ply.cr_lerpFrom, ply.cr_lerpTo)
			end

			return view
		else
			rollAnim = false
		end
	end)
end

hook.Add("SetupMove", "combat_roll_setupmove", function(ply,mv,cmd)
	if clientInMultiplayer then if ply != LocalPlayer() then return end end

	if ply.cr_time != 1 then
		if not mv:KeyDown(IN_DUCK) then mv:AddKey(IN_DUCK) end
		mv:SetSideSpeed(0)
		mv:SetForwardSpeed(0)

		local vel = mv:GetVelocity()
		local dir = cmd:GetViewAngles():Forward()
		dir.z = 0
		local newVel = vel + dir * 20

		local maxlength = 400
		local currentlength = (newVel):Length()
		if currentlength > maxlength then
			newVel = newVel * (maxlength/currentlength)
		end

		mv:SetVelocity(newVel)
	end

	ply.cr_time = math.Clamp(ply.cr_time + GetConVar("sv_combatroll_fraction"):GetFloat() * FrameTime(), 0, 1)

	if singleplayer then
		net.Start("singleplayer_gay_networking")
		net.WriteFloat(ply.cr_time)
		net.Send(ply)
	end
end)

hook.Add("PlayerFootstep", "combat_roll_playerfootstep", function(ply, pos, foot, sound, volume, rf)
	if clientInMultiplayer then if ply != LocalPlayer() then return end end
	if ply.cr_time != 1 then return true end
end)