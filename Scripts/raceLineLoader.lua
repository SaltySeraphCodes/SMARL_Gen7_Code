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
    --self.trackData = nil -- Will be loaded and set on network

    --self.nodeChain = {}
    self.effectChain = {}
    self.debugEffects = {}
    self.effect = sm.effect.createEffect("Loot - GlowItem")
    self.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.effect:setPosition(self.location)
    self.visualizing = false
    self.showSpeeds = false
    self.showSegments = true
    
    self.debug =true  -- TODO: remove, should always be true
   


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

function Loader.server_onDestroy(self)

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
    self.direction = self.shape:getAt()
    
    -- Saved Track data loading
    local storedTrack = self.storage:load()  -- Loads any existing data when placed:
                                            -- N: "Track Name"
                                            -- I: "uuid"
                                            -- C: [Simplified Node chain]
                                            -- O: Origin position: (position of this block when placed and saved)
                                            -- D: Origin Direction: (Direction of this block when placed and saved)
    if storedTrack == nil then -- IDK just do nothing for now
        print("No previous track data found")
    else -- Just automaticallly import and show what is saved
        print("Loaded track",storedTrack.N)
        self.trackData = storedTrack
        -- Reads in track, calculates offset and places nodes in offset position
        -- Saves track to world
        self:sv_loadTrack() -- for initial placement
        --print("finished load")
        -- creates visuals for clientside
        print("Post init")
        print(self.trackData.O)
    end
end

function Loader.cl_receiveTrackData(self,data)
    --print("client Recieved data",data)
    -- Instead of refreshing everything, we will update the nodes
    if self.effectChain ~= nil and #self.effectChain >1 then -- if exists and has length
        for k=1, #data do local v=data[k] -- Add effect to nodeChain
            if self.effectChain[k] ~=nil then -- if "matching" point
                self.effectChain[k].location = v.location
            end
        end
    else
        self.effectChain = data.nodeChain
    end
    self:cl_loadTrack()
end


function Loader.cl_loadTrack(self) -- validates and loads visualization of track
    if self.effectChain == nil or #self.effectChain <=1 then
        print("cl load track: Data is Nil",self.effectChain)
        return
    end
    
    for k=1, #self.effectChain do local v=self.effectChain[k] -- Add effect to nodeChain
        if v.effect == nil then
            v.effect = self:generateEffect(v.location)
        else
            -- set location?
        end
    end
    self:hardUpdateVisual()
end


function Loader.sv_loadTrack(self) -- Validates and saves track to world 
    if self.trackData == nil then
        print("sv load track: Data is Nil")
        return
    end
    -- Set sself nodechain
    self.nodeChain = self.trackData.C
    -- Calculate offsets direction
    local res = calculateOffset(self.trackData.O,self.location, self.trackData.D,self.direction) -- gets offset x,y,z location and rotation from origin
    local offset = res[1]
    local radians = res[2]
    self:applyNodeChainOffset(offset,radians) -- Should mutate sv nodeChain
    local simpChain = self:simplifyNodeChain(self.nodeChain)
    --print("setting clientdata",simpChain)
    self.network:sendToClients("cl_receiveTrackData",{nodeChain = simpChain})
    --self:sv_sendAlert("Track Data loaded") -- TODO: only show once
    
end


function Loader.simplifyNodeChain(self,chain) 
    local simpChain = {}
    --sm.log.info("simping node chain") -- TODO: make sure all seg IDs are consistance
    for k=1, #chain do local v=self.nodeChain[k]
        local newNode = {location = v.location, segType = v.segType.TYPE, effect = nil}
        table.insert(simpChain,newNode)
    end
    return simpChain
end


function Loader.sv_saveTrack(self) -- Reads simplified node chain and saves it
    local worldNodeChain = self:sv_loadWorldTrackData(TRACK_DATA)
    if worldNodeChain == nil then
        print("Could not find World Track data")
        return 
    end
    self.trackData = {
        ["N"] = self.trackName,
        ["I"] = self.trackID,
       [ "C"] = worldNodeChain,
       [ "O"] = self.location,
       [ "D"] = self.direction -- self.shape.at
    }
    self.storage:save(self.trackData)
end


function Loader.sv_saveWoldTrackData(self)
    debugPrint(self.debug,"Saving track data")
    local channel = TRACK_DATA
    data = self.nodeChain
    sm.storage.save(channel,data) -- track was channel
    saveData(data,channel) -- Goes into global for no reason...?
    print("Track Saved")
end

function Loader.sv_exportTrack(self) -- Exports track as a .json file
end

function Loader.sv_importTrack(self) -- Imports .json file
end


function Loader.sv_loadWorldTrackData(self,channel) -- Loads any saved track data (simplified nodechain only) from world storage
    local worldNodeChain = sm.storage.load(channel)
    if worldNodeChain == nil then
        print("Server did not find track data") 
        if self.trackLoadError then
        else
            print("Track Data not found")
            self.trackLoadError = true
        end
    else
        print("Found Track Data",#worldNodeChain)
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
    local offset = pos2 - pos1 -- Might have to do a pi/2 or /180
    print("rotationDif", radDif, "offset",offset)
    return {offset,radDif}
end

function Loader.getNewCoordinates(self,point,origin,offset,angle) -- tak
    -- apply rotation (and pos offset?)
    local rotatedPoint = sm.vec3.new(0,0,0);
    rotatedPoint.x = math.cos(angle) * (offset.x) - math.sin(angle) * (offset.y) + (origin.x);
    rotatedPoint.y = math.sin(angle) * (offset.x) + math.cos(angle) * (offset.y) + (origin.y);
    rotatedPoint.z = point.z -- Set back original z value
    --print("old",point)
    --print("new",rotatedPoint)

    return rotatedPoint; 
end

function Loader.applyNodeChainOffset(self,offset,rads) -- Applys tranform to all chains in offset
    if self.nodeChain == nil or #self.nodeChain <=1 then
        print("ApplyNCO: No node chain")
        return 
    end
    --print("applying offset to new coords",offset,rads)
    for k=1, #self.nodeChain do local node=self.nodeChain[k]
        -- move points around origin
        local newLocation = self:getNewCoordinates(node.location,self.trackData.O,offset,rads)
        local newMid = self:getNewCoordinates(node.mid,offset,rads)
        node.location =newLocation
        node.mid = newMid

        -- rotate out vector, in vector and perp vector
        node.perp = node.perp:rotateZ(rads)
        node.outVector = node.outVector:rotateZ(rads)
    end 
end

--visualization helpers

function Loader.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    self.network:sendToClients("cl_showAlert",msg)
end

function Loader.cl_showAlert(self,msg) -- client recieves alert
    print("Displaying",msg)
    sm.gui.displayAlertText(msg,3)
end


function Loader.toggleVisual(self,nodeChain)
    print("displaying",self.visualizing)
    if self.visualizing then
        self:stopVisualization()
        self.visualizing = false
    else
        self:showVisualization()
        self.visualizing = true
    end
end

function Loader.stopVisualization(self) -- Stops all effects in node chain (specify in future?)
    --debugPrint(self.debug,'Stoppionng visualizaition')
    for k=1, #self.effectChain do local v=self.effectChain[k]
        if v.effect ~= nil then
            v.effect:stop()
        end
    end
    --TODO: have error catching for too large client data size (chunk data by 250? nodes)
    self.visualizing = false
end

function Loader.showVisualization(self) -- Clientstarts all effects
    --print("showing vis",self.nodeChain)
    for k=1, #self.effectChain do local v=self.effectChain[k]
        if v.effect ~= nil then
            if not v.effect:isPlaying() then
                v.effect:start()
            end
        end
    end
    self.visualizing = true
end

function Loader.updateVisualization(self) -- moves/updates effects according to nodeChain
    for k=1, #self.effectChain do local v=self.effectChain[k]
        if v.effect ~= nil then
            if v.location ~= nil then -- possibly only trigger on change
                v.effect:setPosition(v.location)
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

function Loader.server_onFixedUpdate(self, timeStep)
    local location = sm.shape.getWorldPosition(self.shape)
    local direction = self.shape.at
    if self.trackData == nil then
        --print("No Track Data")
    else
        if (location ~= self.location or direciton ~= self.direciton) then
            if sm.shape.getVelocity(self.shape):length() ==0 then
                self.location = location
                self.direction = direction
                self:sv_loadTrack()
            else
                --self:stopVisualization()
            end
        end
    end

end

function Loader.client_onFixedUpdate( self, timeStep ) 
    self:updateVisualization()
end


function Loader.client_canTinker( self, character )
    --print("canTinker")
	return true
end

function Loader.client_onTinker( self, character, state )
    --print('onTinker')
	if state then
        self.network:sendToServer('sv_saveData')
	end
end