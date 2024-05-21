-- Copyright (c) 2019 Seraph --
--dofile "../Libs/GameImprovements/interactable.lua"
-- read in maps
if  sm.isHost then -- Just avoid anythign that isnt the host for now
	dofile "globals.lua"
end
-- Reverse Lights
-- Turns on when car starts braking
DownforceBlock = class( nil )
DownforceBlock.maxChildCount = -1
DownforceBlock.maxParentCount = -1
DownforceBlock.connectionInput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
DownforceBlock.connectionOutput =sm.interactable.connectionType.logic
DownforceBlock.colorNormal = sm.color.new( 0x7c0000ff )
DownforceBlock.colorHighlight = sm.color.new( 0x7c000fff )
DownforceBlock.poseWeightCount = 2


function DownforceBlock.client_onCreate( self ) 
	self:client_init()
end

function DownforceBlock.client_onDestroy(self)
	
end

function DownforceBlock.client_init( self ) 
	
end

function DownforceBlock.server_onDestroy(self)

end

function DownforceBlock.server_init( self ) 
	self.forceStrength = 0
end

function DownforceBlock.client_onRefresh( self )
	self:client_onDestroy()
	--dofile "globals.lua" removed because it may erase stored data
	self:client_init()

end


function DownforceBlock.server_onRefresh( self )
	self:server_onDestroy()
	--dofile "globals.lua" removed because it may erase stored data
	self:server_init()

end

function DownforceBlock.perform_downforce(self) -- SV
    --print('downforce?',self.forceStrength)
    if self.forceStrength == nil then self.forceStrength = 0 end
    local velocity = sm.shape.getVelocity(self.shape)
    local speed = velocity:length()
    local maxForce = -1200
    local minForce = -500
    local offset = 0.05 -- offset towards/from front to push down

    --local speedAdj = -maxForce + 0.1*self.speed^2.3
    --local force = sm.vec3.new(0,0,1) * -(self.speed^1.7)  -- -- invert so slower has higher? TODO: Check for wedges/aero parts, tire warmth factor too
    local force = self.shape.up * -self.forceStrength -- -- invert so slower has higher? TODO: Check for wedges/aero parts, tire warmth factor too
    --force.z = mathClamp(maxForce,minForce,force.z) - bankAdjust
    --print(self.speed,speedAdj,force.z)
   -- print("df:",force.z)
   sm.physics.applyImpulse(self.shape.body,force,true)--,--self.shape.at)
end

function DownforceBlock.server_onFixedUpdate( self, timeStep )
	--[[if not sm.isHost then -- Just avoid anythign that isnt the host for now
		return
	end]]
	self:perform_downforce()
	
end

function DownforceBlock.cl_notifyChat(self,message)
    sm.gui.chatMessage(message)
end



function DownforceBlock.sv_update_force(self,ammount)
    self.forceStrength = self.forceStrength + ammount
    self.network:sendToClients("cl_notifyChat","Set Force Strength:" .. tostring(self.forceStrength))
end

function DownforceBlock.client_canTinker( self, character )
    --print("canTinker")
	return true -- Any conditions when it cant? like on 
end

function DownforceBlock.client_onTinker( self, character, state )
    --print('onTinker')
	if state then
       
	end
end



function DownforceBlock.client_onInteract(self,character,state)
    -- if driver active, then toggle userControl
    --print("client onInteract")
    if state then
        if character:isCrouching() then
           self.network:sendToServer("sv_update_force",-100) -- TDOO have adjustable ammounts
        else -- if character is not aiming and not crouching
            self.network:sendToServer("sv_update_force",100)
        end
    end    
end

-- Downforce Detection and helpers
function Driver.sv_onInteract(self,params) -- so far for only for downforce detection
    --print(self.userSeated,self.userControl)
    local state = params.state
    local crouch = params.crouch
    if state and not self.userSeated then -- E pressed
        if self.downforceDetect == false then -- if not already detecting
            if self.speed <= 1 then -- maybe smaller?
                if self.onLift == false then
                    print("Detecting Downforce")
                    self:sv_sendAlert("Detecting Downforce...")
                    self.downforceDetect = true
                    self.dfTestVect.z = 0 -- reset test vec
                else
                    print("Car shjould not be onlift")
                end
            else
                print("Car should be still")
            end
        else
            print("already detecting downforce...",self.downforceDetect)
            self.downforceDetect = false
        end
    end
end
