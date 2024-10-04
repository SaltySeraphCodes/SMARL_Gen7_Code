SmarlCamera = class()
--MOD_FOLDER = "$CONTENT_DATA/" -- folder
dofile "$CONTENT_DATA/Scripts/globals.lua" -- load smar globals?
--print("hjelloo??")
-- WHEN Loading tools manually, put this into toolsets.json:
--"$CONTENT_5411dc77-fa28-4c61-af84-bcb1415e3476/Tools/Database/ToolSets/smarltools.toolset"
function SmarlCamera.client_onCreate( self )
	self:client_init()
	--print("client create??")
end
--TODO CAMERA ACTIONS
-- Gymbol lock: keep x/y/z axis aligned while able to aim 
-- movement speed change
-- smooth ler--p speed change
-- part lock: lock pos to part/body
--fake shake (horizontal & veryical) kinda done
--side tilt?
--zooming /soom speed
--free cam on locked part
--drine cam type )
-- set cam points
-- Camera modes: (Freecam, Pinned to shape, drone/helicopter)
-- camera settings (shake when near car?, )
-- Have presets for certain modes (shake, action shake, smooth shake)
-- auto focus on targets
-- auto change camera
-- auto zoom
-- auto shake?
-- set drone height and speed
-- increment shake/sped amounts


-- setting focus via external controls
-- Mode Switching:

function SmarlCamera.client_init( self )
	self.angle = 0
	self.offsetPos = 0
	self.zoomStrength = 60
	self.zoomIn = false
	self.zoomOut= false
	self.zoomSpeed = 0.04 -- how fast to zoom in
	self.zoomAccel = 0.002 -- how quick to ramp it
	self.raceStatus = 0
	self.gameWorld = sm.world.getCurrentWorld()
	self.player = sm.localPlayer.getPlayer()
	self.character = self.player:getCharacter()
	--print(self.player)
	self.location = self.character:getWorldPosition()
	self.primaryState = false
	self.secondaryState = false
	print("Smarl camera loaded",self.player,self.location)
	self.freeCamLocation = self.location
	self.freeCamDirection = sm.camera.getDirection()
	self.freeCamActive = false
	self.freeCamOffset = sm.vec3.new(0,0,0)

	self.raceCamActive = false
	self.raceCamDirection = sm.camera.getDirection()
	self.raceCamLocation = self.location

	self.droneCamActive = false
	
	self.hoodCamActive = false

	self.network:sendToServer("server_init")

	self.shakeVector = { -- camera shake vector
		xStrength = 0.0, -- amount
		xBump = 0.0, -- baked lerp
		yStrength = 0.0,
		yBump = 0.0,
		zStrength = 0.0,
		zBump = 0.0,

		rStrengthX = 0.01,
		rBumpX = 0.01,
		rStrengthY = 0.01,
		rBumpY = 0.01,
		rStrengthZ = 0.01,
		rBumpZ = 0.01,

	}
	self.feezeCam = false
	self.moveDir = sm.vec3.new(0,0,0)
	self.moveSpeed = 15 -- 1 is default, 0 is none, can increment by 0.01?
	self.moveAccel = sm.vec3.new(0,0,0) -- rate of movement
	self.lockMove = false -- locks whatever current move ment 
	self.debugCounter = 0
	self.fovValue = 70

	self.externalControlsEnabled = false -- whether kepyress reader is active
	self.clickCamOn = false -- Whether the user used left click to turn on freecam (allows teleporting)

	-- GUI 
	--print("loading gui")
	self.guiOpen = false
	self.RaceControlGUI = sm.gui.createGuiFromLayout( MOD_FOLDER.."Gui/Layouts/RaceControl.layout",false )
	
	if self.selectedColorButton == nil then
		self.selectedColorButton = "ColorButtonRed"
	end

	--self.RaceControlGUI:setButtonCallback( "StopRaceBtn", "client_buttonPress" )
	--self.RaceControlGUI:setButtonCallback( "StartRaceBtn", "client_buttonPress" )
	--self.RaceControlGUI:setButtonCallback( "CautionRaceBtn", "client_buttonPress" )

	self.RaceControlGUI:setButtonCallback( "ColorButtonRed", "cl_onColorButtonClick" )
	self.RaceControlGUI:setButtonCallback( "ColorButtonYellow", "cl_onColorButtonClick" )
	self.RaceControlGUI:setButtonCallback( "ColorButtonGreen", "cl_onColorButtonClick" )
	self.RaceControlGUI:setButtonCallback( "ColorButtonWhite", "cl_onColorButtonClick" )



	-- etc...
	self.RaceControlGUI:setButtonCallback( "ResetRace", "client_buttonPress" )
	self.RaceControlGUI:setButtonCallback("PopUpYNYes", "client_buttonPress")
	self.RaceControlGUI:setButtonCallback("PopUpYNNo", "client_buttonPress")
	self.RaceControlGUI:setOnCloseCallback( "client_onRaceControlGUIClose" )

end 

function SmarlCamera.server_init(self)
	self.cameraLoaded = false -- whether tool is loaded into global
	self.externalControlsEnabled = false -- whether kepyress reader is active
	self.sv_dataUpdated = false -- Flag for if data gets updated
	print("SMAR Version ",SMAR_VERSION, "Loaded")
end

function SmarlCamera.load_camera(self) -- attatches camera to smar globals
	print("loading smar cam?",SMAR_CAM)
	if setSmarCam ~= nil then
		setSmarCam(self)
		--print("set smar cam")
		self.cameraLoaded = true
	else
		print("globals not loaded")
		-- set globals load error true
	end
end

function SmarlCamera.client_onDestroy(self)
	if self.RaceControlGUI then
		self.RaceControlGUI:close()
		self.RaceControlGUI:destroy()
	end
end


function SmarlCamera.server_createCam(self,player)
	local cam = self.curCam
	print("teleporting to",self.curCam)
	local normalVec = sm.vec3.normalize(self.freeCamDirection)
	local degreeAngle = math.atan2(normalVec.x,normalVec.y) --+ 1.5708 -- Hopefully accounts for xaxis woes, could switch y and x
	local newChar = sm.character.createCharacter( player, self.gameWorld, sm.vec3.new(cam.x,cam.y,cam.z), -degreeAngle)--cam.angle )	
	self.character = newChar
	player:setCharacter(newChar)

end

function SmarlCamera.cl_recieveCommand(self,com) -- takes in string commands and runs them
	--print("cam recieved",com,com.command,com.value)
	if com.command == "setMode" then
		--print("got set",com)
		if com.value == 0 then
			self:activateFreecam()
			self:deactivateRaceCam()
		elseif com.value == 1 then
			--self:deactivateFreecam()
			self:activateRaceCam()
		end -- Add drone cam??
	elseif com.command == "ExitCam" then
		if self.freeCamActive then
			self:exitFreecam()
		end	
	elseif com.command == "EnterCam" then
		if not self.freeCamActive then
			self:EnterFreecam()
		end
	elseif com.command == "SetZoom" then
		self:cl_setZoom(com.value)
	elseif com.command == "MoveCamera" then
		self:cl_setMoveDir(com.value)
	elseif com.command == "setPos" then
		--print("setting pos",com.value)
		self:cl_setPosition(com.value)
	elseif com.command == "setDir" then
		--print("setting dir",com.value)
		self:cl_setDirection(com.value)
	elseif com.command == "forceDir" then
		--print("forcing dir",com.value)
		self:cl_forceDirection(com.value) -- Freezes camera in state??
	end


end

function SmarlCamera.sv_recieveCommand(self,com)
	--print("cam sv_recieved",com,com.command,com.value)
	if com.command == "test" then -- switch??
		print("foff")
	elseif com.command == "setRaceMode" then
		--print("star update race mode icon")
		self.sv_colorIndex = com.value
		self.sv_dataUpdated = true;
	end
end


function SmarlCamera.sv_ping(self,ping) -- get ing
    print("SmCam got sv ping",ping)
end

function SmarlCamera.cl_ping(self,ping) -- get ing
    print("SmCam got cl ping",ping) -- cant do sandbox violations of course but can set events/commands to be read by server
	--self.tool:updateFpCamera( 30.0, sm.vec3.new( 0.0, 0.0, 0.0 ), 1, 1 ) -- aimwaiit?
	--self.tool:updateCamera( 2.8, 30.0, sm.vec3.new( 0.65, 0.0, 0.05 ), 1 )
    --self.network:sendToServer("sv_ping",ping)
end

function SmarlCamera.cl_setZoom(self,ammount) -- zooms the camere
	if ammount < 0 then
		self.zoomOut = true
		--print("zooming out")
	elseif ammount > 0 then
			self.zoomIn = true
			--print("zoom in")
	elseif ammount == 0 then
		self.zoomIn = false
		self.zoomOut = false
	end
	if self.fovValue < 10 then --?
		self.fovValue = 10
	
	end
	if self.fovValue > 90 then 
		self.fovValue = 90 
		
	end
	--print("zoom",self.zoomSpeed,self.fovValue)
end

function SmarlCamera.cl_setMoveDir(self,move) -- normalized vector to indicate movementDirection
	self.moveDir = move
	-- any fancy things can go here
end

function SmarlCamera.cl_setPosition(self,position) -- sets race camera to specified -position, resets zoom to 70
	if not self.feezeCam then
		sm.camera.setPosition(position) -- sets position immediately was commented out for some reason (possibly for camera shake reasons)
		self.raceCamLocation = position
		self.freeCamLocation = position
	end
	--print("setPosR",self.raceCamLocation,self.raceCamDirection)
	--print("setPosA",sm.camera.getPosition(),sm.camera.getDirection())
end

function SmarlCamera.cl_setDirection(self,direciton) -- sets race camera to specified -position, resets zoom to 70
	if not self.feezeCam then 
		sm.camera.setDirection(direciton)
		self.raceCamDirection = direciton
		self.freeCamDirection = direciton
	end
	--print("setDirR",self.raceCamLocation,self.raceCamDirection)
	--print("setDirA",sm.camera.getPosition(),sm.camera.getDirection())
end

function SmarlCamera.cl_forceDirection(self,direciton)-- Freezes cam in direction and disables all other movement until sent to freecam
	--print('forcing cl direction',direciton)
	self.feezeCam = true
	self.raceCamDirection = direciton
	sm.camera.setDirection(direciton)
end


function SmarlCamera.cl_setMoveSpeed(self,speed) -- int that sets movement speed
	self.moveSpeed = speed
end

function SmarlCamera.cl_setShakeStrength(self,strength) --sets shake distance - ammount
	self.shakeStrength = speed
end


function SmarlCamera.cl_setShakeSpeed(self,speed) -- int sets shake speed (bumpiness) (disable xyz?)
	self.shakeSpeed = speed
end

function SmarlCamera.cl_setShakePreset(self,preset) -- int Presets for shaking modes (speed and strength)
	self.shakePreset = preset
end

function SmarlCamera.server_teleportPlayer(self,location)
	print("teleporting to",location)	
	local player = self.player
	local normalVec = sm.vec3.normalize(self.freeCamDirection)
	local degreeAngle = math.atan2(normalVec.x,normalVec.y) --+ 1.5708 -- Hopefully accounts for xaxis woes, could switch y and x
	local newChar = sm.character.createCharacter( player, self.gameWorld,location,-degreeAngle)
	self.character = newChar
	player:setCharacter(newChar)

end

function SmarlCamera.client_onRefresh( self )
	print("refresh smarlCam")
	self:client_init()
end

function SmarlCamera.client_onWorldCreated( self, world )
	print("created world",world)
end


function SmarlCamera.client_onEvent( self, world )
	print("OnEvenr",world)
end

--[[
function SmarlCamera.client_onToggle(self, backwards) check this
	local dir = 1
	if backwards then
		dir = -1
	end
	self:toggleCamera(dir)
	
end]]

function SmarlCamera.switchCam(self,cam) -- Actually does the teleporting
	local player = self.player
	self.network:sendToServer( "server_createCam", player)
	
end


function SmarlCamera.cl_teleportCharacter(self,location) -- Client teleports character to vec3 location
	self.network:sendToServer( "server_teleportPlayer", location)
end

function SmarlCamera.toggleCamera(self,dir) -- Determines next Cam and then causes telepoirt dir [-1,1] direction in list of cams
	print("Toggleing",dir,curCamID,"next:",nextCamID)
	--self:setZoom(self.curCam.zoom)
end


function SmarlCamera.client_onEquip( self )
	print("on SMARL CONtoller Tool",self.location)
	sm.audio.play( "PotatoRifle - Equip" )

end

function SmarlCamera.client_onUnequip( self )

end


function SmarlCamera.client_onPrimaryUse( self, state )
	print("test")
	if state == 1 then
		self.zooming = true
	elseif state == 2 then
		self.zoomAccel = self.zoomAccel + 0.003
		self.accelZoom = true
	elseif state == 0 then
		self.zooming = false
		self.zoomAccel = 0
		self.zoomSpeed = 0.01
		self.accelZoom = false
	end
	
	return true
end

function SmarlCamera.client_onSecondaryUse( self, state )
	--print('help')
	sm.camera.setCameraPullback( 1, 1 )
	if state == 1 then
		self.zoomoutg = true
	elseif state == 2 then
		self.zoomAccel = self.zoomAccel + 0.003
		self.accelZoom = true
	elseif state == 0 then
		self.zoomoutg = false
		self.zoomAccel = 0
		self.zoomSpeed = 0.01
		self.accelZoom = false
	end
	
	return true
end

function SmarlCamera.client_onReload(self)
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching() 
	local dir = 1
	local raceStatus = self.raceStatus
	print("Checking ", SMAR_VERSION)
	if isCrouching then
		dir = -1
	end
	sm.gui.chatMessage( "SMAR VERSON: " ..SMAR_VERSION )
	raceStatus = raceStatus + dir
	--print("Setting race status",raceStatus,dir)
	--print(sm.smarlFunctions)
	self.raceStatus = raceStatus
	return true
end

function SmarlCamera.client_onFixedUpdate( self, timeStep )
	
	--print(sm.tool.interactState)
end

function SmarlCamera.client_onClientDataUpdate(self,clientData)
	local selectedColor -- Set default as self.selectedColorButton
	if clientData.colorIndex then
		if clientData.colorIndex == 0 then -- red
			selectedColor = "ColorButtonRed"
		elseif clientData.colorIndex == 2 then -- yellow
			selectedColor = "ColorButtonYellow"
		elseif clientData.colorIndex == 1 then -- Green
			selectedColor = "ColorButtonGreen"
		elseif clientData.colorIndex == 3 then -- white
			selectedColor = "ColorButtonWhite"
		else --Fall Back
			selectedColor = "ColorButtonRed"
		end
	end

	if self.RaceControlGUI then
		self:cl_updateColorButton( selectedColor )
	else
		self.selectedColorButton = selectedColorButton
	end
end

function SmarlCamera.client_onUpdate( self, timeStep )
	--print("Actual",sm.camera.getPosition(),sm.camera.getDirection())
	self.location = self.character:getWorldPosition() -- Make this only move according to camera mode
	

	if not self.freeCamActive then -- if nothing active  
		--print("wut")
		self.freeCamLocation = self.character:getWorldPosition()
		self.freeCamLocation.z = self.freeCamLocation.z + 2
	else
		self.freeCamDirection = sm.camera.getDirection() -- only allow mouse move when mouse move abvle
	end

	--print(sm.camera.getCameraState())
	local goalPos = sm.vec3.new(self.freeCamLocation.x,self.freeCamLocation.y,self.freeCamLocation.z)
	local goalDir = nil-- self.character:getDirection()
	
	-- shake setup
	
	local xBump = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.xBump
	local yBump = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.yBump
	local zBump = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.zBump

	local rBumpX = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.rBumpX
	local rBumpY = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.rBumpY
	local rBumpZ = sm.noise.floatNoise2d(self.debugCounter*1, 10, 1 ) * self.shakeVector.rBumpZ

	local xNoise = sm.noise.floatNoise2d(self.debugCounter*xBump+3, 10, 5 ) * self.shakeVector.xStrength
	local yNoise = sm.noise.floatNoise2d(self.debugCounter*yBump+6, 10, 6 ) * self.shakeVector.yStrength
	local zNoise = sm.noise.floatNoise2d(self.debugCounter*zBump+8, 10, 7 ) * self.shakeVector.zStrength

	local xNoiseR = sm.noise.floatNoise2d(self.debugCounter*self.shakeVector.rBumpX, 10, 4 ) * self.shakeVector.rStrengthX
	local yNoiseR = sm.noise.floatNoise2d(self.debugCounter*self.shakeVector.rBumpY, 10, 3 ) * self.shakeVector.rStrengthY
	local zNoiseR = sm.noise.floatNoise2d(self.debugCounter*self.shakeVector.rBumpZ, 10, 2 ) * self.shakeVector.rStrengthZ
	--print(self.freeCamActive,self.raceCamActive)
	if self.freeCamActive then -- movable free cam
		local moveDir = self.moveDir--self.tool:getRelativeMoveDirection()
		moveDir = sm.vec3.lerp(self.moveAccel,moveDir,timeStep*4)
		self.moveAccel = moveDir
		--*print(self.moveAccel)
		
		-- movement shake
		goalPos = self.freeCamLocation + moveDir * self.moveSpeed--* movespeed
		goalPos.x = goalPos.x + xNoise
		goalPos.y = goalPos.y + yNoise
		goalPos.z = goalPos.z + zNoise

		-- rotation noise
		--print(self.freeCamOffset)
		goalDir = self.character:getDirection()  --  TODO: Fix issue here... free cam toggle on always points to char position which does not follow cur cam
		goalDir.x = goalDir.x + xNoiseR
		goalDir.y = goalDir.y + yNoiseR
		goalDir.z = goalDir.z + zNoiseR

		if self.freeCamActive then 
			--print("update1",self.freeCamDirection,sm.localPlayer.getDirection())
			self.freeCamLocation = sm.vec3.lerp(self.freeCamLocation,goalPos,timeStep)--*2)
			self.freeCamDirection = sm.vec3.lerp(self.freeCamDirection,goalDir,timeStep*2)--*2)	
			sm.camera.setPosition(self.freeCamLocation) -- FAULT: Camera shake will not be triggered or be bumpy since camera is being set on immediate callback, both are called onUpdate, this is being called after
														-- TODO: Fix: bake this into the direct clientCall ( separate this whole thing into separete function and call directly with new pos as param)
														--print("FREcam",self.freeCamDirection, sm.camera.getDirection())
			sm.camera.setDirection(self.freeCamDirection)--self.freeCamDirection) -- less shaky in dir (tacky)
			--print("update2",self.freeCamDirection,sm.localPlayer.getDirection())

		end
		
	elseif self.raceCamActive then -- this is controlled by racecontrol I believe -- Problem: Setting race cam position here breaks things?
		--print("racecam?")
		--sm.camera.setPosition(self.raceCamLocation)
		--print("raceCam",self.raceCamDirection, sm.camera.getDirection())
		--sm.camera.setDirection(self.raceCamDirection)
	end
	-- TODO: have specific drone cam mode?

	--zoom
	local zoomAmmount = 0
	if self.zoomIn then 
		--print("zoomin")
		zoomAmmount = -0.6
	elseif self.zoomOut then
		--print("zoomOut")
		zoomAmmount = 0.6
	end
	if zoomAmmount ~= 0 then 
		self.zoomSpeed = sm.util.lerp(self.zoomSpeed,zoomAmmount,0.1)
	else
		self.zoomSpeed = sm.util.lerp(self.zoomSpeed,zoomAmmount,0.1) --0,m  
	end
	self.fovValue = sm.util.lerp(self.fovValue,self.fovValue + self.zoomSpeed,0.5)
	if self.fovValue < 15 then --?
		self.fovValue = 15
	
	end
	if self.fovValue > 75 then 
		self.fovValue = 75 
		
	end
	sm.camera.setFov(self.fovValue) -- TODO: clean this up into fewer functions
	self.debugCounter = self.debugCounter + 1
	--print("Cinecamera cl Update After")

	-- GUIL Setting
	if RACE_CONTROL then -- Need better connector for RACE_CONTROL
		local raceStat = " - "
		local lapStat = " - "
		local statusText = ""
		if RACE_CONTROL.raceStatus == 1 then
			raceStat = "Race Status: #11ee11Racing"
		elseif RACE_CONTROL.raceStatus == 0 then
			raceStat = "Race Status: #ff2222Stopped"
		elseif RACE_CONTROL.raceStatus == 2 then
			raceStat = "Race Status: #ffff11Caution"
		
		elseif RACE_CONTROL.raceStatus == 3 then
			raceStat = "Race Status: #fafafaFormation"
		
		end
		if RACE_CONTROL.raceFinished then
			raceStat = "Race Status: #99FF99Finished"
		end    

		if RACE_CONTROL.currentLap ~= nil then
			lapStat = "Lap ".. RACE_CONTROL.currentLap .. " of " .. RACE_CONTROL.targetLaps
		end

		if self.RaceControlGUI then
			self.RaceControlGUI:setText("StatusText", raceStat )
			self.RaceControlGUI:setText("LapStat", lapStat )
		end
	end

end

function SmarlCamera.server_onFixedUpdate( self, timeStep )
	--print(CLOCK)
	--print("rc_server FIxed update before")
	if not self.cameraLoaded then
		self:load_camera()
	else
		-- Check for data update flag?
	if	self.sv_dataUpdated then
		self:sv_updateIcon({colorIndex = self.sv_colorIndex})
		self.sv_dataUpdated = false
	end

	end
	--print("rc_server FIxed update after")

end

function SmarlCamera.client_onEquippedUpdate( self, primaryState, secondaryState )
	--print(primaryState,secondaryState)
	if primaryState ~= self.primaryState then
		if primaryState == 1 then
			print("left clicked",primaryState)
			self:activateFreecam()
			self.clickCamOn = true
		end
		self.primaryState = primaryState
	end

	if secondaryState ~= self.secondaryState then
		if secondaryState == 1 then
			print("right clicked",secondaryState)
			if self.clickCamOn then 
				self:deactivateFreecam()
				self.clickCamOn = false
			end
		end
		self.secondaryState = secondaryState
	end

	return true, true
end

function SmarlCamera.client_onToggle( self)
	--print("toggle",self.guiOpen)
	self.RaceControlGUI:open()
	self.guiOpen = true
	-- TODO: Make a switch that opens and closes on toggle
end

function SmarlCamera.client_onAction(self, input, active)
	print("action",input,active)
end


function SmarlCamera.activateFreecam(self)
	--print("activate1",self.freeCamDirection,sm.localPlayer.getDirection())
	self.feezeCam = false -- disable freezecam in case
	self.debugCounter = 0
	if self.freeCamLocation == nil then 
		self.freeCamLocation = sm.camera.getPosition()
	else -- use last or current pos?

	end
	if self.freeCamDirection == nil then 
		self.freeCamDirection = sm.camera.getDirection() -- Free cam should activate wherever player is facing
	else
		-- use last or current direction?>
		
	end
	print("freecam Activated",self.freeCamDirection)

	--sm.localPlayer.setDirection(self.freeCamDirection)
	self.freeCamOffset = self.freeCamDirection
	--print("activate2",self.freeCamDirection,sm.localPlayer.getDirection())
	--sm.camera.setPosition(self.freeCamLocation) 
	--sm.camera.setDirection(self.freeCamDirection)
	sm.camera.setCameraState(2)
	--self.character:setLockingInteractable(self.interactable)
	self.freeCamActive = true

end

function SmarlCamera.activateRaceCam(self)
	--sm.camera.setPosition(self.location)
	--sm.camera.setDirection(self.freeCamDirection)
	self.raceCamActive = true
end

function SmarlCamera.deactivateRaceCam(self)

	self.raceCamActive = false
end

function SmarlCamera.deactivateFreecam(self)
	self.freeCamActive = false
	print("freecam Deacivated")
	self.character:setLockingInteractable(nil)
	self.tool:updateFpCamera( 70.0, sm.vec3.new( 0.0, 0.0, 0.0 ), 1, 1 ) -- aimwaiit?
	sm.camera.setCameraState(1)
	self:cl_teleportCharacter(self.freeCamLocation) -- teleports char to cam loc
end

function SmarlCamera.exitFreecam(self)
	print("freecam exited")
	self.freezecam = false
	self.character:setLockingInteractable(nil)
	self.tool:updateFpCamera( 70.0, sm.vec3.new( 0.0, 0.0, 0.0 ), 1, 1 ) -- aimwaiit?
	sm.camera.setCameraState(1)
	self.freeCamActive = false
end

function SmarlCamera.EnterFreecam(self)
	print("freecam Entered")
	self.debugCounter = 0
	sm.camera.setPosition(self.location)
	sm.camera.setDirection(self.freeCamDirection)
	sm.camera.setCameraState(2)
	--self.character:setLockingInteractable(self.interactable)
	self.freeCamActive = true
	self.raceCamActive = false
end



-- Json and keypress reader
function SmarlCamera.sv_ReadJson(self)
    local jsonData = sm.json.open(MOD_FOLDER.."JsonData/cameraInput.json")
   
    if jsonData == nil or jsonData == {} or not jsonData or #jsonData == 0 or jsonData == "{}" then
        print("NO data")
        return
	else
		print("data",jsonData)
		self:parseJsonData(jsonData)
	end
	
end

function SmarlCamera.parseJsonData(self)
	
end



-- GUI Functions

function SmarlCamera.sv_updateIcon( self, params ) -- Up[dates colors]
	if params.colorIndex then
		self.colorIndex = params.colorIndex
	end
	self.network:setClientData( {colorIndex = self.colorIndex } )
end

function SmarlCamera.client_buttonPress( self, buttonName )
    --print("clButton",buttonName)
    -- if not self.cl and cl2 then self.cl = cl2 end -- Verify if game data exits
	if buttonName == "StartRaceBtn" then
		print("yes")
		-- Trigger btn
	
    elseif buttonName == "ResetRace" then
        if (self.raceStatus == 1 or self.raceStatus == 2 or self.raceStatus == 3 )and not self.raceFinished then -- Mid race
            self.RaceControlGUI:setText("PopUpYNMessage", "Still Racing, Reset?")
            self.RaceControlGUI:setVisible("PopUpYNMainPanel", true)
		    self.RaceControlGUI:setVisible("CreateRacePanel", false)
            self.PopUpYNOpen = true
        else
            --self.RaceMenu:setText("PopUpYNMessage", "Start Game?")
            --self.RaceMenu:setVisible("CreateRacePanel", false)
            self.RaceControlGUI:close()
            self:cl_send_resetRace()
        end
		
    
    elseif buttonName == "PopUpYNYes" then
            --print("resetting race match")
            self.RaceControlGUI:setVisible("CreateRacePanel", true)
            self.RaceControlGUI:setVisible("PopUpYNMainPanel", false)
            self.RaceControlGUI:close()
            self:cl_send_resetRace() -- reset race
            self.PopUpYNOpen = false
            --print("Resetting mid race")    
	elseif buttonName == "PopUpYNNo" then
		self.RaceControlGUI:setVisible("CreateRacePanel", true)
		self.RaceControlGUI:setVisible("PopUpYNMainPanel", false)
		self.PopUpYNOpen = false
    else
        print("buton not recognized")
    end
end

function SmarlCamera.client_OnOffButton( self, buttonName, state )
	self.RaceMenu:setButtonState(buttonName.. "On", state)
	self.RaceMenu:setButtonState(buttonName.. "Off", not state)
end



function SmarlCamera.cl_updateColorButton( self, colorButtonName )
	if self.selectedColorButton ~= colorButtonName then
		self.RaceControlGUI:setButtonState( self.selectedColorButton, false )
		self.selectedColorButton = colorButtonName
	end
	self.RaceControlGUI:setButtonState( self.selectedColorButton, true )
end


function SmarlCamera.cl_onColorButtonClick( self, name )
	local colorIndex = 0 -- Race State
	if name == "ColorButtonRed" then 
		colorIndex = 0
	elseif name == "ColorButtonYellow" then
		colorIndex = 2
	elseif name == "ColorButtonGreen" then
		colorIndex = 1
	elseif name == "ColorButtonWhite" then
		colorIndex = 3
	end

	self:cl_set_RaceMode(colorIndex) -- Sends Racemode update to Race Control (if exists)
	self.network:sendToServer( "sv_updateIcon", { colorIndex = colorIndex } )
end


-- Race Control control from GUI press
function SmarlCamera.cl_send_resetRace(self)
	if RACE_CONTROL then
		self.network:sendToServer("sv_setResetRace")
	else
		print("no race control")
		--TODO: GUI alert
	end
end

function SmarlCamera.sv_setResetRace(self)
	if RACE_CONTROL then
		RACE_CONTROL:sv_resetRace()
	else
		print("No server Race Control")
	end
end

function SmarlCamera.cl_set_RaceMode(self,status)
	if RACE_CONTROL then
		self.network:sendToServer("sv_setRaceMode",status)
	else
		print("No Race Control Detected")
		--TODO GUI alert?
	end
end

function SmarlCamera.sv_setRaceMode(self,status)
	if RACE_CONTROL then
        RACE_CONTROL:sv_toggleRaceMode(status)
	else
		print("No Server Race control")
	end
end


function SmarlCamera.client_onRaceControlGUIClose( self )
    --print("MenuOnclose")
    if PopUpYNOpen then
		self.RaceControlGUI:open()
		self.RaceControlGUI:setVisible("ControlRacePanel", true)
		self.RaceControlGUI:setVisible("PopUpYNMainPanel", false)
		PopUpYNOpen = false
    end
    --self.RaceMenu:destroy()
    --self.RaceMenu = sm.gui.createGuiFromLayout( "$CONTENT_"..MOD_UUID.."/Gui/Layouts/RaceMenu.layout",false )

end