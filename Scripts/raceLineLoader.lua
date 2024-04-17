dofile "Timer.lua" 
dofile "globals.lua"

-- Copyright (c) 2020 SaltySeraph --
--raceLineLoaderr.lua 
--[[
	- Allows users to press 'e' to export/save any generated racing lines
    - Allows users to press 'g' to load any saved racing lines
]]

Loader = class( nil )
Loader.maxChildCount = -1
Loader.maxParentCount = -1
Loader.connectionInput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
Loader.connectionOutput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
Loader.colorNormal = sm.color.new( 0xffc0cbff )
Loader.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)



-- Local helper functions utilities
function round( value )
	return math.floor( value + 0.5 )
end

function Loader.client_onCreate( self ) 
	self:client_init()
	print("Created Track Loader")
end

function Loader.client_onDestroy(self)
    print("Loader destroyed")
    if self.effect:isPlaying() then
        self.effect:stop()
    end
    self:stopVisualization()
end

function Loader.client_init( self )  -- Only do if server side???
    self.trackData = nil -- Will be loaded and set on network

    self.nodeChain = {}
    self.effectChain = {}
    self.debugEffects = {}
    self.effect = sm.effect.createEffect("Loot - GlowItem")
    self.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.effect:setPosition(self.location)
    self.visualizing = false
    self.showSpeeds = false
    self.showSegments = true
    
    self.debug =false  -- Debug flag
   


     -- GUI stuff?
    self.trackName = "unnamed track" -- TODO
    self.trackuid = 1234 -- TODO
    -- error states
    self.scanError = false
    self.errorLocation = nil

    self.showWalls = false -- show wall effects (reduces total allowed effects)
	print("Track Loader V2.0 Client Initialized")
end


function Loader.client_onRefresh( self )
	self:client_onDestroy()
	self:client_init()
end

function Loader.server_onRefresh(self)
    self:server_onDestroy()
    self:server_init()
end


function Loader.server_onCreate(self)
    self:server_init()

end

function Loader.server_init(self)
    self.trackName = "Unnamed"
    self.trackID = 123 -- TODO: generate UUID
    self.location = sm.shape.getWorldPosition(self.shape)
    self.direction = self.shape.at

    -- Saved Track data loading
    self.trackData = self.storage:load()  -- Loads any existing data when placed:
                                            -- N: "Track Name"
                                            -- I: "uuid"
                                            -- C: [Simplified Node chain goes here]
                                            -- O: Origin position: (position of this block when placed and saved)
                                            -- D: Origin Direction: (Direction of this block when placed and saved)
    if self.trackData == nil then -- IDK just do nothing for now
        print("No previous track data found")
    else -- Just automaticallly import and show what is saved
        print("Loading track",self.trackData.N)
        -- Reads in track, calculates offset and places nodes in offset position
        -- Saves track to world
        self:sv_loadTrack()

        -- creates visuals for clientside
        self.network:setClientData({"nodeChain" = self.nodeChain})
    end
end



function Loader.client_onClientDataUpdate( self, data ) -- Loads client data
    print("client loading data")
    self.nodeChain = data.nodeChain
    self:cl_loadTrack()
end


function Loader.cl_loadTrack() -- validates and loads visualization of track
    if self.nodeChain == nil then
        print("cl load track: Data is Nil")
        return
    end

    for k=1, #self.nodeChain do local v=self.nodeChain[k] do -- Add effect to nodeChain
        v.effect = self:generateEffect(v.location)
    end
    self:hardUpdateVisual()
end

function Loader.sv_loadTrack() -- Validates and saves track to world 
    if self.trackData == nil then
        print("sv load track: Data is Nil")
        return
    end
    -- Calculate offsets
    local res = calculateOffset(self.trackData.O,self.location, self.trackData.D,self.direciton) -- gets offset x,y,z location and rotation from origin
    local offset = res[1]
    local radians = res[2]
    self:applyNodeChainOffset(ofset,radians) -- Should mutate sv nodeChain
    local data = {channel = TRACK_DATA, raceLine = true} -- Eventually have metaData too?
    self:sv_saveData(data)
    sm.gui.displayAlertText("Saved track to world")
end

function Loader.sv_saveTrack(self) -- Reads simplified node chain and saves it
    local worldNodeChain = self:sv_loadWorldTrackData(TRACK_DATA)
    if worldNodeChain == nil then
        print("Could not find World Track data")
        return 
    end
    self.trackData = {
        "N" = self.trackName
        "I" = self.trackID
        "C" = worldNodeChain
        "O" = self.location 
        "D" = self.direction -- self.shape.at
    }
    self.storage:save(self.trackData)
end

function Loader.sv_exportTrack(self) -- Exports track as a .json file

end

function Loader.sv_importTrack(self) -- Imports .json file

end


function Control.sv_loadWorldTrackData(self,channel) -- Loads any saved track data (simplified nodechain only) from world storage
    local worldNodeChain = sm.storage.load(channel)
    if worldNodeChain == nil then
        print("Server did not find track data") 
        if self.trackLoadError then
        else
            print("Track Data not found")
            self.trackLoadError = true
        end
    else
        --print("Server found track data") 
        if self.trackLoadError then
            print("Track Loaded")
            self.trackLoadError = false
        else
            --print("Track Loaded, initial")
        end
        return worldNodeChain
    end
end

-- Helpers
--TODO: move these to global
function calculateOffset(pos1,pos2, dir1, dir2) -- calculate full offset between two vectors, will need original and new rotations?
    local radDif = vectorAngleDiff(dir1,dir2)
    local offset = pos1 - pos2 -- Might have to do a pi/2 or /180
    print("rotationDif", radDif, "offset",offset)
    return {offset,radDif}
end

function sleep(n)  -- freezes game
  local t0 = clock()
  while clock() - t0 <= n do end
end

function Loader.getNewCoordinates(self,point,offset,angle) -- tak
     -- apply rotation (and pos offset?)
     local originValue = point -- Originvalue vec3
     local offsetX = offset[1]
     local offsetY = offset[2]
     local differenceFromOrigin = {
         x: x - originValue.x,
         y: y - originValue.y
     };
     
    print("originVal",originValue,differenceFromOrigin)
     
     local rotatedPoint = sm.vec3.new(0,0,0);
     ---local angle = rads * Math.PI / 180.0; Angle is already radians
     --local angle = rads -- TODO: just rename
 
     rotatedPoint.x = Math.cos(angle) * (offsetX) - Math.sin(angle) * (offsetY) + (originValue.x);
     rotatedPoint.y = Math.sin(angle) * (offsetX) + Math.cos(angle) * (offsetY) + (originValue.y);
     
     print("neaw point",rotatedPoint)
     
     return rotatedPoint; 
end

function Loader.rotateVector()

function Loader.applyNodeChainOffset(self,offset,rads) -- Applys tranform to all chains in offset
    if self.nodeChain == nil then
        print("ApplyNCO: No node chain")
        return 
    end

    for k=1, #self.nodeChain do local node=self.nodeChain[k]
        -- move points around origin
        local newLocation = self:getNewCoordinates(node.location,offset,rads)
        local newMid = self:getNewCoordinates(node.mid,offset,rads)
        node.location =newLocation
        node.mid = newMid

        -- rotate out vector, in vector and perp vector
        node.perpVector = node.perpVector:rotateZ(rads)
        node.outVector = node.outVector:rotateZ(rads)
    end 
end


--visualization helpers
function Loader.stopVisualization(self) -- Stops all effects in node chain (specify in future?)
    debugPrint(self.debug,'Stoppionng visualizaition')
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            v.effect:stop()
        end
        if v.lEffect ~= nil then
            if not v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if not v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    

        if v.lEffect ~= nil then
            if not v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if not v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    end

    
    for k=1, #self.debugEffects do local v=self.debugEffects[k]
        if v ~= nil then
            if not v:isPlaying() then
                --print("debugStop")
                v:stop()
            end
        end
    end
    

    if self.errorNode then
        self.errorNode:stop()
    end
    self.visualizing = false
end

function Loader.showVisualization(self) --starts all effects
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            if not v.effect:isPlaying() then
                v.effect:start()
            end
        end
        if self.showWalls then
            if v.lEffect ~= nil then
                if not v.lEffect:isPlaying() then
                    v.lEffect:start()
                end
            end
            if v.rEffect ~= nil then
                if not v.rEffect:isPlaying() then
                    v.rEffect:start()
                end
            end
        end
    end

    if self.debug then -- only show up on debug for now
        for k=1, #self.debugEffects do local v=self.debugEffects[k]
            if not v:isPlaying() then
                v:start()
            end
        end
    end
    self.visualizing = true
end

function Loader.updateVisualization(self) -- moves/updates effects according to nodeChain
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            if v.pos ~= nil then -- possibly only trigger on change
                v.effect:setPosition(v.pos)
                if self.showSpeeds then
                    if v.vMax ~= nil then
                        local color = getSpeedColorScale(self.maxSpeed,self.minSpeed,v.vMax)
                        v.effect:setParameter( "Color", color )
                    end
                end
                if self.showSegments then
                    if v.segType ~= nil then
                        local color = sm.color.new(v.segType.COLOR)
                        v.effect:setParameter( "Color", color )
                    end
                end

                if self.visualizing then
                    if not v.effect:isPlaying() then
                        v.effect:start()
                    end
                else
                    v.effect:stop()
                end
                if self.showWalls then
                    if v.lEffect ~= nil then
                        if not v.lEffect:isPlaying() then
                            v.lEffect:start()
                        end
                    end
                    if v.rEffect ~= nil then
                        if not v.rEffect:isPlaying() then
                            v.rEffect:start()
                        end
                    end
                end
            end
        end
    end

    if self.errorNode then
        if not self.errorNode:isPlaying() then
            self.errorNode:start()
        end 
    end

    if self.visualizing then -- only show up on debug for now
        for k=1, #self.debugEffects do local effect=self.debugEffects[k]
            if not effect:isPlaying() then
                effect:start()
            end
        end
    end
end

function Loader.hardUpdateVisual(self) -- toggle visuals to gain color
    self:stopVisualization()
    self:showVisualization()
end

function Loader.generateEffect(self,location,color) -- Creates new effect at param location
    
    local effect = sm.effect.createEffect("Loot - GlowItem")
    effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    effect:setScale(sm.vec3.new(0,0,0))
    local color = (color or sm.color.new("AFAFAFFF"))
    
   -- local testUUID = sm.uuid.new("42c8e4fc-0c38-4aa8-80ea-1835dd982d7c")
    --effect:setParameter( "uuid", testUUID) -- Eventually trade out to calculate from force
    --effect:setParameter( "Color", color )
    if location == nil then
        effect:setPosition(sm.vec3.new(0,0,0)) -- remove too
        effect:setParameter( "Color", sm.color.new("ff3333FF") )
        return effect
    end
    effect:setPosition(location) -- remove too
    effect:setParameter( "Color", color )
    return effect
end

function Loader.createEfectLine(self,from,to,color) --
    local distance = getDistance(from,to)
    local direction = (to - from):normalize()
    local step = 3
    for k = 0, distance,step do
        local pos = from +(direction * k)
        table.insert(self.debugEffects,self:generateEffect(pos,(color or sm.color.new('00ffffff'))))
    end

end


function Loader.printNodeChain(self)
    for k, v in pairs(self.nodeChain) do
		print(v.id,v.segID)
    end
end

function Loader.client_onInteract(self,character,state)
     if state then
		if character:isCrouching() then -- I guess toggle visuals?
            self.debug = not self.debug -- togle debug
            self:toggleVisual(self.nodeChain)
		else -- Save track
			self.network:sendToServer("sv_saveTrack")
		end
	end
end
