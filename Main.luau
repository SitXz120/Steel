if game.PlaceId ~= 107778070777162 then return end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- EGG ATLAS | Steal An Egg | 2026-09-14
local SCRIPT_VERSION="11.31.1"
local UI=...
assert(type(UI)=="table" and UI.ApiVersion==1 and UI.Version==SCRIPT_VERSION,
    "UI module missing or incompatible. Run Loader.luau or the standalone EggAtlas.luau.")
-- Selected-egg runner: normal walking, one carry request, then confirmed safe return.
-- Difficulty order uses configured guard WalkSpeed, not a guarantee of escape.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player=Players.LocalPlayer
end
local function beginAtlasLaunch(environment,job,version,now,hasUI)
    local previous=environment.EggAtlasLaunch
    if previous and previous.job==job and previous.version==version then
        if previous.loading and now-previous.started<30 then return nil end
        if hasUI and not previous.loading and now-(previous.readyAt or previous.started)<2 then return nil end
    end
    local ticket={job=job,version=version,started=now,loading=true}
    environment.EggAtlasLaunch=ticket
    return ticket
end
local launchTicket
do
    local environment=type(getgenv)=="function" and getgenv() or _G
    local holder=player:FindFirstChildOfClass("PlayerGui")
    local existing=holder and holder:FindFirstChild("EggAtlasUI")
    launchTicket=beginAtlasLaunch(environment,game.JobId,SCRIPT_VERSION,os.clock(),existing and existing:GetAttribute("Version")==SCRIPT_VERSION)
    if not launchTicket then return end
end
local State = require(RS.Client.EggState)
local Records = require(RS.Shared.Util.EggRecords)
local Earnings = require(RS.Shared.Util.AssetEarnings)
local Assets = require(RS.Data.Assets)
local Areas = require(RS.Data.Areas)
local Guards = require(RS.Data.Guards)
local SpeedUtil = require(RS.Shared.Util.TreadmillUtil)
local SpeedProjection = require(RS.Client.SpeedPowerProjection)
local GameNumbers = require(RS.Shared.Utils.Numbers)
local TweenService = game:GetService("TweenService")
local parent = player:WaitForChild("PlayerGui")
local previousConfig
for _, child in ipairs(parent:GetChildren()) do
    local window = child:FindFirstChild("Window")
    local riftPage = window and window:FindFirstChild("RiftPage")
    local isLegacyAtlas = child:GetAttribute("Version") == "11.5-treadmill-route-recovery"
        and child:GetAttribute("AreaIconMode") == "Pet"
        and riftPage and riftPage:FindFirstChild("RiftAutoToggle")
        and window:FindFirstChild("AreaPage")
    if child:IsA("ScreenGui") and (child.Name == "EggAtlasUI" or isLegacyAtlas) then
        -- Import existing UI choices on the first upgrade, before removing the old UI.
        local ok,rules=pcall(function()
            return game:GetService("HttpService"):JSONDecode(child:GetAttribute("AreaWatchRules") or "")
        end)
        if ok and type(rules)=="table" then
            local imported={}
            for _,rule in ipairs(rules) do
                if type(rule)=="table" and type(rule.AreaId)=="string" and type(rule.Rarities)=="table" then
                    local rarities={}
                    for _,name in ipairs(rule.Rarities) do if type(name)=="string" then rarities[name]=true end end
                    imported[rule.AreaId]={enabled=rule.Enabled==true,rarities=rarities}
                end
            end
            local oldSearch=window and window:FindFirstChild("Search",true)
            previousConfig={rules=imported,editingArea=child:GetAttribute("AreaWatchEditingArea"),
                selectedArea=child:GetAttribute("SelectedArea"),tab=child:GetAttribute("ActiveTab"),
                autoArea=child:GetAttribute("AreaWatchEnabled")==true,rift=child:GetAttribute("RiftActive")==true,
                search=oldSearch and oldSearch:IsA("TextBox") and oldSearch.Text or "",
                position=window and {x=window.Position.X.Offset,y=window.Position.Y.Offset} or nil}
            local indexOK,indexAreas=pcall(function()return game:GetService("HttpService"):JSONDecode(child:GetAttribute("IndexAreas") or "")end)
            if indexOK and type(indexAreas)=="table" then previousConfig.indexAreas=indexAreas end
            local targetsOK,indexTargets=pcall(function()return game:GetService("HttpService"):JSONDecode(child:GetAttribute("IndexTargets") or "")end)
            if targetsOK and type(indexTargets)=="table" then previousConfig.indexTargets=indexTargets end
            previousConfig.riftBanner=child:GetAttribute("RiftWantedBanner")
            previousConfig.indexStrategy=child:GetAttribute("IndexStrategy")
            previousConfig.indexCompletion=child:GetAttribute("IndexCompletion")
            local priorityOK,priorityOrder=pcall(function()return game:GetService("HttpService"):JSONDecode(child:GetAttribute("PriorityOrder") or "")end)
            if priorityOK and type(priorityOrder)=="table" then previousConfig.priorityOrder=priorityOrder end
            previousConfig.notifications=child:GetAttribute("NotificationsEnabled")
            for key,attribute in pairs({autoArea="AutoAreaWanted",rift="RiftWanted",autoEvent="EventWanted",autoIndex="IndexWanted"}) do
                local wanted=child:GetAttribute(attribute)
                if type(wanted)=="boolean" then previousConfig[key]=wanted end
            end
        end
        child:Destroy()
    end
end

-- UI 11.29: overview, configurable priorities and targeted collections.
local C=UI.Theme
local suffixes = {"", "K", "M", "B", "T", "Q", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
local function compact(value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return "N/A" end
    local sign, amount, i = value < 0 and "-" or "", math.abs(value), 1
    while amount >= 1000 and i < #suffixes do amount /= 1000; i += 1 end
    amount = math.round(amount * 100) / 100
    if amount >= 1000 and i < #suffixes then amount /= 1000; i += 1 end
    if amount >= 1000 then return string.format("%.2e", value) end
    return sign .. string.format("%.2f", amount):gsub("0+$", ""):gsub("%.$", "") .. suffixes[i]
end
local function petRarity(category)
    local config = category and Assets.Directory[category]
    local rarity = config and config.Rarity
    if type(rarity) ~= "table" then return "Unknown", C.muted end
    local name = rarity.DisplayName or rarity._id or "Unknown"
    local color = typeof(rarity.Color) == "Color3" and rarity.Color or C.muted
    -- Lift dark rarity colors so they remain readable on the card background.
    return name, color:Lerp(Color3.new(1, 1, 1), 0.35)
end
local function isCollectible(r)
    return type(r) == "table" and (r.State == "Slot" or r.State == "Dropped")
        and type(r.AreaId) == "string" and type(r.NestId) == "string"
        and r.CarrierUserId == nil and r.OwnerUserId == nil and r.Placement == nil
end
local function isContestable(egg)
    if type(egg)~="table" or egg.State~="Carried" or type(egg.CarrierUserId)~="number"
        or egg.CarrierUserId==player.UserId or egg.OwnerUserId~=nil or egg.Placement~=nil
        or type(egg.AreaId)~="string" or type(egg.NestId)~="string" then return false end
    local other=Players:GetPlayerByUserId(egg.CarrierUserId)
    local ch=other and other.Character
    local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if not other or not ch or not hum or hum.Health<=0 or other:GetAttribute("InBossArena") then return false end
    local Guard=require(RS.Client.ToolGameplayGuard)
    return Guard.IsInsideArena(other) and not Guard.IsInsideSafeZone(other)
end
local function fieldEggIncome(egg)
    local ok,rate=pcall(Earnings.MutationOnlyRatePerSecond,{
        Category=egg.AssetCategory,Scale=egg.AssetScale,Mutations=egg.Mutations or {},
        BaseMutation=egg.BaseMutation,CreatorTemporary=egg.CreatorTemporary,
    })
    if ok and type(rate)=="number" and rate==rate and math.abs(rate)<math.huge then return rate end
    return nil
end

type AreaInfo = {id: string,name: string,speed: number?,config: any,rank: number,color: Color3,requiredPower: number?,requiredWalk: number?}
local areaList: {AreaInfo} = {}
local areaById: {[string]: AreaInfo} = {}
for id, config in pairs(Areas.Directory) do
    local guard = Guards.Directory[config.GuardId or id]
    local a = {id = id, name = config.DisplayName or id,
        speed = guard and tonumber(guard.WalkSpeed), config = config,rank=0,color=C.mint}
    table.insert(areaList, a)
    areaById[id] = a
end
table.sort(areaList, function(a, b)
    if (a.speed or math.huge) == (b.speed or math.huge) then return a.id < b.id end
    return (a.speed or math.huge) < (b.speed or math.huge)
end)
for i, a in ipairs(areaList) do
    a.rank = i
    a.color = C.mint:Lerp(Color3.fromRGB(244, 132, 154), (i - 1) / math.max(#areaList - 1, 1))
end

-- Use the live game sign, whose recommendation is based on the guard's home position.
local function updateAreaRequirements()
    local objects=workspace:FindFirstChild("__OBJECTS")
    local areas=objects and objects:FindFirstChild("Areas")
    local folder=areas and areas:FindFirstChild("GuardAreas")
    for _,a in ipairs(areaList) do
        local model=folder and folder:FindFirstChild(a.id)
        local sign=model and model:FindFirstChild("RequiredSpeedSign")
        local speedLabel=sign and sign:FindFirstChild("Speed",true)
        if speedLabel and speedLabel:IsA("TextLabel") then
            local value=speedLabel.Text:gsub("<[^>]->","")
            local ok,power=pcall(GameNumbers.Parse,value)
            if ok and type(power)=="number" and power>=0 then
                a.requiredPower=power
                a.requiredWalk=SpeedUtil.SpeedPowerToWalkSpeed(power)
            end
        end
    end
end
updateAreaRequirements()

local window=UI.CreateWindow(parent,SCRIPT_VERSION)
local gui,panel=window.gui,window.panel
gui:SetAttribute("AreaIconMode","Pet")
gui:SetAttribute("PortalAvoidance",true)
local connections, alive = {}, true
local runner, selectedTarget, riftController, eventController
local sessionOverview
local function recordEvent(kind: string,message: string)
    if sessionOverview then sessionOverview.record(kind,(message:gsub("^.-:%d+: ",""))) end
end
local manualStarting=false
local areaWatch={enabled=false,busy=false,rules={},editing=nil,area="",rarity="per-area rarities",completed={}}
-- Auto Index options 11.29.0
type IndexOptions = {targets: {[string]: {[string]: boolean}},strategy: string,completion: string}
local function readIndexOptions(data: any,areas: {{id: string,config: any}}): IndexOptions
    local result: IndexOptions={targets={},strategy="income",completion="train"}
    if type(data)~="table" then return result end
    if data.indexStrategy=="nearest" or data.indexStrategy=="rarity" then result.strategy=data.indexStrategy end
    if data.indexCompletion=="stop" then result.completion="stop" end
    if type(data.indexTargets)=="table" then
        for _,area in ipairs(areas) do
            local saved=data.indexTargets[area.id]
            if type(saved)=="table" then
                local choices: {[string]: boolean}={}
                for _,drop in ipairs(area.config.DropTable or {}) do
                    if type(drop[1])=="string" and type(saved[drop[1]])=="boolean" then choices[drop[1]]=saved[drop[1]] end
                end
                result.targets[area.id]=choices
            end
        end
    end
    return result
end

local indexWatch: {enabled: boolean,busy: boolean,areas: {[string]: boolean},message: string,options: IndexOptions}={enabled=false,busy=false,areas={},message="OFF",options={targets={},strategy="income",completion="train"}}
local setWatchEnabled
local function connect(signal, callback)
    local c = signal:Connect(function(...)
        if alive then return callback(...) end
        return nil
    end)
    table.insert(connections, c)
    return c
end
-- Local settings only; no game remotes or activity simulation.
local function createConfigStore(io)
    local api={data={},ready=false,closed=false,status="CONFIG NEW"}
    local pending=false
    local revision=0
    local snapshot
    local function status(value,err)
        api.status=value
        io.status(value,err)
    end
    if type(io.read)~="function" or type(io.write)~="function" then
        status("CONFIG UNAVAILABLE","Local readfile/writefile support is required")
        io.write=nil
    else
        local exists=true
        if type(io.exists)=="function" then
            local ok,result=pcall(io.exists,io.path)
            if ok then exists=result end
        end
        if exists then
            local ok,result=pcall(function()return io.decode(io.read(io.path))end)
            if ok and type(result)=="table" and result.schema==1
                and result.placeId==io.placeId and result.userId==io.userId then
                api.data=result
                status("CONFIG LOADED")
            elseif ok then
                status("CONFIG INCOMPATIBLE","Unrecognized config; existing file will be preserved")
                io.write=nil
            else
                status("CONFIG LOAD ERROR",tostring(result))
            end
        end
    end
    function api.flush()
        if api.closed or not api.ready or not pending or type(io.write)~="function" then return end
        pending=false
        local ok,err=pcall(function()
            local value=snapshot()
            value.schema=1;value.placeId=io.placeId;value.userId=io.userId
            io.write(io.path,io.encode(value))
        end)
        status(ok and "CONFIG SAVED" or "CONFIG SAVE ERROR",not ok and tostring(err) or nil)
        if not ok then pending=true end
    end
    function api.request()
        if api.closed or not api.ready or type(io.write)~="function" then return end
        pending=true;revision+=1
        local token=revision
        status("CONFIG SAVING")
        io.delay(.4,function()
            if api.closed or token~=revision then return end
            api.flush()
        end)
    end
    function api.start(capture)
        snapshot=capture;api.ready=true
        -- A damaged/unreadable file is only replaced after the user changes a setting.
        if api.status=="CONFIG NEW" then api.request() end
    end
    function api.destroy()
        api.flush()
        api.closed=true;revision+=1
    end
    return api
end
local configStore=createConfigStore({
    path="EggAtlas-"..game.PlaceId.."-"..player.UserId..".json",
    placeId=game.PlaceId,userId=player.UserId,
    read=readfile,write=writefile,exists=isfile,delay=task.delay,
    encode=function(value)return game:GetService("HttpService"):JSONEncode(value)end,
    decode=function(value)return game:GetService("HttpService"):JSONDecode(value)end,
    status=function(value,err)
        gui:SetAttribute("ConfigStatus",value);gui:SetAttribute("ConfigError",err)
    end,
})
if configStore.status=="CONFIG NEW" and previousConfig then configStore.data=previousConfig end
local togglePreference={autoArea=configStore.data.autoArea==true,rift=configStore.data.rift==true,autoEvent=configStore.data.autoEvent==true,}
for _,area in ipairs(areaList)do
    local saved=configStore.data.indexAreas
    indexWatch.areas[area.id]=type(saved)~="table" or saved[area.id]==true
end
do
    local settingsAreas={}
    for _,area in ipairs(areaList) do table.insert(settingsAreas,{id=area.id,config=area.config}) end
    indexWatch.options=readIndexOptions(configStore.data,settingsAreas)
end
togglePreference.autoIndex=configStore.data.autoIndex==true
gui:SetAttribute("IndexWanted",togglePreference.autoIndex)
gui:SetAttribute("IndexEnabled",false)
local restoringConfig=true
gui:SetAttribute("AutoAreaWanted",togglePreference.autoArea)
gui:SetAttribute("RiftWanted",togglePreference.rift)
gui:SetAttribute("EventWanted",togglePreference.autoEvent)
local function rememberToggle(key,on)
    togglePreference[key]=on==true
    gui:SetAttribute(key=="autoIndex" and "IndexWanted" or key=="autoArea" and "AutoAreaWanted" or (key=="autoEvent" and "EventWanted" or "RiftWanted"),on==true)
    -- Explicit toggle choices must survive an immediate rejoin, without the UI debounce.
    configStore.request()
    configStore.flush()
end
local function createPriorityPolicy(saved)
    local defaults={"Event","Area","Index","Rift"}
    local order,seen={},{}
    if type(saved)=="table" then
        for _,savedName in ipairs(saved)do
            local name=savedName=="Boss" and "Event" or savedName
            if table.find(defaults,name) and not seen[name] then seen[name]=true;table.insert(order,name)end
        end
    end
    for _,name in ipairs(defaults)do if not seen[name]then table.insert(order,name)end end
    local api={order=order}
    function api.before(a: string,b: string): boolean
        return (table.find(api.order,a) or 99)<(table.find(api.order,b) or 99)
    end
    function api.choose(ready: (string)->boolean,owner: string?): string?
        for _,name in ipairs(api.order)do
            if name==owner then break end
            if ready(name)then return name end
        end
        return nil
    end
    function api.move(index: number,direction: number): boolean
        local target=index+direction
        if index<1 or index>#api.order or target<1 or target>#api.order then return false end
        api.order[index],api.order[target]=api.order[target],api.order[index]
        return true
    end
    return api
end
local priorities=createPriorityPolicy(configStore.data.priorityOrder)
local featureReady: ((string)->boolean)?=nil
local function higherPriorityWork(owner: string): boolean
    return featureReady~=nil and priorities.choose(featureReady,owner)~=nil
end
gui:SetAttribute("PriorityOrder",game:GetService("HttpService"):JSONEncode(priorities.order))
-- Merge a burst of egg updates into one redraw; never queue work after closing.
local function refreshScheduler(callback,interval)
    local queued,last=false,-math.huge
    return function()
        if queued or not alive then return end
        queued=true
        task.delay(math.max(0,interval-(os.clock()-last)),function()
            queued=false
            if not alive then return end
            last=os.clock()
            callback()
        end)
    end
end
local eggRevision=0
local requestRiftRefresh
local mountedWindow=UI.MountWindow({
    configStore=configStore,connect=connect,Input=Input,
    getViewport=function()
        return workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    end,
    onDestroy=function()
    configStore.destroy()
    alive = false
    areaWatch.enabled=false;indexWatch.enabled=false
    if eventController then eventController.destroy() end
    if riftController then riftController.stop("Closed","UI closed") end
    if runner then runner.destroy() end
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    end,
},window)
local fit,header,close=mountedWindow.fit,mountedWindow.header,mountedWindow.close
local featureNav,live=mountedWindow.featureNav,mountedWindow.live

local selected = areaById[configStore.data.selectedArea] and configStore.data.selectedArea or "All"
local snapshotGroups={}
local render
local areaView=UI.CreateAreaBrowser({panel=panel,areaById=areaById,areaList=areaList,configStore=configStore,compact=compact,connect=connect,
    onSelect=function(id)selected=id;if render then render(true)end end})
local subheading=areaView.subheading
local search=areaView.search
local targetLabel=areaView.targetLabel
local runStatus=areaView.runStatus
local runDetail=areaView.runDetail
local stopTrip=areaView.stopTrip
local watchRarities={{id="Any",label="All rarities",rank=-math.huge}}
local rarityNames={}
for category,asset in pairs(Assets.Directory) do
    local name=petRarity(category)
    if name~="Unknown" then
        local rank=tonumber(asset.Rarity.RarityNumber) or math.huge
        rarityNames[name]=math.min(rarityNames[name] or math.huge,rank)
    end
end
for name,rank in pairs(rarityNames) do table.insert(watchRarities,{id=name,label=name,rank=rank}) end
-- Use the game's rarity tiers, from common to rarest, rather than alphabetical order.
table.sort(watchRarities,function(a,b)
    if a.rank~=b.rank then return a.rank<b.rank end
    return a.label<b.label
end)
local areaFilters=UI.CreateAreaFilters({panel=panel,gui=gui,areaList=areaList,areaById=areaById,areaWatch=areaWatch,
    configStore=configStore,watchRarities=watchRarities,connect=connect,TweenService=TweenService,
    changed=function()eggRevision+=1 end,setEnabled=function(on)if setWatchEnabled then setWatchEnabled(on)end end})
local watchPanel=areaFilters.panel
local watchMessage,watchSwitch=areaFilters.message,areaFilters.switch

-- Smooth path following and recovery of the same field egg.
-- Boss portals are navigation obstacles, not interaction targets.
-- Use the game's schedule and reset wall, including live schedule overrides.
local Cycle=require(RS.Shared.Util.AreaEggCycle)
local ResetWall=require(RS.Client.AreaEggResetWall)
local FieldCycle={epoch=0,period=Cycle.ActivePeriodIndexAt(workspace:GetServerTimeNow()),dayStartsAt=0,fadeUntil=0}
function FieldCycle.read()
    local now=workspace:GetServerTimeNow()
    local period=Cycle.ActivePeriodIndexAt(now)
    local adminDay=workspace:GetAttribute("Event_AdminAbuse")==true
    if period~=FieldCycle.period then
        FieldCycle.period=period
        if not adminDay then FieldCycle.epoch+=1 end
    end
    local night=not adminDay and Cycle.IsNightPhase(now)
    local blocked=night or now<FieldCycle.dayStartsAt or now<FieldCycle.fadeUntil or ResetWall.IsSealed()
    return {epoch=FieldCycle.epoch,blocked=blocked,
        remaining=night and Cycle.SecondsUntilPhaseEnd(now) or math.max(0,FieldCycle.dayStartsAt-now)}
end
connect(State.ResetCountdown,function(payload)
    if payload.DayStartsAt>FieldCycle.dayStartsAt then
        FieldCycle.dayStartsAt=payload.DayStartsAt;FieldCycle.epoch+=1
    end
end)
connect(State.ResetFade,function()
    FieldCycle.epoch+=1;FieldCycle.fadeUntil=workspace:GetServerTimeNow()+5
end)
local RESET_INTERRUPTED={} -- Identity token for an interrupted field-egg trip.
local PRIORITY_INTERRUPTED={}
local TARGET_UNAVAILABLE={}
local fieldRetry={epoch=-1,eggs={}}
local function fieldRetryReady(egg)
    local epoch=FieldCycle.read().epoch
    if fieldRetry.epoch~=epoch then fieldRetry.epoch=epoch;table.clear(fieldRetry.eggs) end
    local skipped=fieldRetry.eggs[egg.Uid]
    return not skipped or skipped.version~=egg.Version or os.clock()>=skipped.untilTime
end
local function deferFieldEgg(uid)
    local egg=State.ReadFieldEgg(uid)
    if egg then
        fieldRetryReady(egg)
        fieldRetry.eggs[uid]={version=egg.Version,untilTime=os.clock()+30}
        eggRevision+=1
    end
end
local priorityCache,priorityRevision,priorityAt,priorityEpoch=nil,-1,0,-1
local function matchesAreaRule(egg)
    local rule=areaWatch.rules[egg.AreaId]
    return rule~=nil and rule.enabled and (rule.rarities.Any==true or rule.rarities[petRarity(egg.AssetCategory)]==true)
end
local function priorityEgg()
    local cycle=FieldCycle.read()
    if priorityEpoch~=cycle.epoch then
        priorityEpoch=cycle.epoch;areaWatch.completed={};priorityRevision=-1
    end
    if not areaWatch.enabled or cycle.blocked then return nil end
    if priorityRevision==eggRevision and os.clock()<priorityAt then return priorityCache end
    priorityRevision=eggRevision;priorityAt=os.clock()+.2;priorityCache=nil
    local bestIncome,bestRarity=-math.huge,-math.huge
    for _,egg in pairs(State.ReadFieldEggs().Records) do
        if isCollectible(egg) and fieldRetryReady(egg) and not areaWatch.completed[egg.Uid]
            and matchesAreaRule(egg) then
            local income=fieldEggIncome(egg) or -math.huge
            local asset=Assets.Directory[egg.AssetCategory]
            local rarity=asset and asset.Rarity and tonumber(asset.Rarity.RarityNumber) or -math.huge
            -- Compare the raw game income across every enabled area, before formatting K/M/etc.
            if not priorityCache or income>bestIncome
                or (income==bestIncome and (rarity>bestRarity
                    or (rarity==bestRarity and egg.Uid<priorityCache.Uid))) then
                priorityCache=egg;bestIncome=income;bestRarity=rarity
            end
        end
    end
    return priorityCache
end
local function resetInterruptsTrip(r,cycle,egg,userId)
    if not r.uid or r.resetReturning then return false end
    if r.resetTeleported then return true end
    if egg and egg.State=="Carried" and egg.CarrierUserId==userId then return false end
    return (cycle.blocked and not r.requestSent)
        or (not egg and (cycle.blocked or cycle.epoch~=r.resetEpoch))
end
local function reserveAreaReset()
    if not areaWatch.enabled or not FieldCycle.read().blocked then return false end
    for _,rule in pairs(areaWatch.rules) do
        if rule.enabled then
            for _,on in pairs(rule.rarities) do if on==true then return true end end
        end
    end
    return false
end
local function createPortalAvoidance()
    local api={}
    local cache,tracked,links={}, {}, {}
    local changed=true
    local sampled=0
    local function inside(p,b,pad)
        pad=pad or 0
        return p.X>=b.x0-pad and p.X<=b.x1+pad and p.Z>=b.z0-pad and p.Z<=b.z1+pad
    end
    -- Continuous segment/rectangle intersection; catches crossing at high speed.
    local function intersects(a: Vector3,b: Vector3,box: {x0: number,x1: number,z0: number,z1: number},pad: number?): boolean
        local padding: number=pad or 0
        local t0,t1=0,1
        for _,axis in ipairs({"X","Z"}) do
            local lo=axis=="X" and box.x0-padding or box.z0-padding
            local hi=axis=="X" and box.x1+padding or box.z1+padding
            local start=axis=="X" and a.X or a.Z
            local finish=axis=="X" and b.X or b.Z
            local delta=finish-start
            if math.abs(delta)<.00001 then
                if start<lo or start>hi then return false end
            else
                local x,y=(lo-start)/delta,(hi-start)/delta
                if x>y then x,y=y,x end
                t0=math.max(t0,x);t1=math.min(t1,y)
                if t0>t1 then return false end
            end
        end
        return true
    end
    function api.segmentSafe(a,b,zones)
        for _,zone in ipairs(zones) do
            if intersects(a,b,zone,5) then
                -- A portal can spawn near us: permit departure from its outer buffer
                -- only when heading away, never through the actual portal body.
                local center=Vector3.new((zone.x0+zone.x1)/2,a.Y,(zone.z0+zone.z1)/2)
                local delta=(b-a)*Vector3.new(1,0,1)
                local outward=(a-center)*Vector3.new(1,0,1)
                if not (inside(a,zone,5) and not inside(a,zone,3)
                    and outward:Dot(delta)>0 and not intersects(a,b,zone,3)) then return false end
            end
        end
        return true
    end
    function api.route(start,goal,zones)
        for _,b in ipairs(zones) do
            assert(not inside(start,b,3),"Too close to a boss portal; movement stopped")
            assert(not inside(goal,b,5),"Destination overlaps a boss portal; waiting for it to disappear is safer")
        end
        if api.segmentSafe(start,goal,zones) then return {start,goal} end
        local nodes={start,goal}
        for _,b in ipairs(zones) do
            -- Extra corner clearance absorbs waypoint tolerance and turning momentum.
            for _,x in ipairs({b.x0-12,b.x1+12}) do
                for _,z in ipairs({b.z0-12,b.z1+12}) do
                    local p=Vector3.new(x,start.Y,z)
                    local usable=true
                    for _,other in ipairs(zones) do if inside(p,other,5) then usable=false;break end end
                    if usable then table.insert(nodes,p) end
                end
            end
        end
        local dist,previous,visited={[1]=0},{},{}
        for _=1,#nodes do
            local at,best=nil,math.huge
            for i=1,#nodes do if not visited[i] and (dist[i] or math.huge)<best then at,best=i,dist[i] end end
            if not at then break end
            if at==2 then
                local result={goal}
                repeat at=previous[at];assert(at,"Portal route is incomplete");table.insert(result,1,nodes[at])until at==1
                return result
            end
            visited[at]=true
            for i,p in ipairs(nodes) do
                if not visited[i] and api.segmentSafe(nodes[at],p,zones) then
                    local distance=best+((p-nodes[at])*Vector3.new(1,0,1)).Magnitude
                    if distance<(dist[i] or math.huge) then dist[i]=distance;previous[i]=at end
                end
            end
        end
        error("No route around boss portals; movement stopped",0)
    end
    -- Full-input steering: predict turning drift and choose the smallest clear turn.
    function api.dodge(position,direction,velocity,speed,zones,preferredSide)
        if #zones==0 or direction.Magnitude<.01 then return direction,false,preferredSide end
        local function clear(candidate)
            local previous=position
            for _,seconds in ipairs({.12,.24,.4,.6}) do
                local intended=candidate*speed
                local point=position+intended*seconds+(velocity-intended)*(.18*(1-math.exp(-seconds/.18)))
                if not api.segmentSafe(previous,point,zones) then return false end
                previous=point
            end
            return true
        end
        if clear(direction) then return direction,false,preferredSide end
        local best,bestScore,bestSide=nil,-math.huge,preferredSide
        for _,degrees in ipairs({20,35,50,70,90,120,160,180}) do
            for _,side in ipairs({-1,1}) do
                local angle=math.rad(degrees)*side
                local candidate=Vector3.new(direction.X*math.cos(angle)-direction.Z*math.sin(angle),0,
                    direction.X*math.sin(angle)+direction.Z*math.cos(angle)).Unit
                if clear(candidate) then
                    local score=candidate:Dot(direction)+(preferredSide==side and .03 or 0)
                    if score>bestScore then best,bestScore,bestSide=candidate,score,side end
                end
            end
        end
        if best then return best,true,bestSide end
        -- If a portal appears extremely close, keep moving away from its center.
        local away,nearest=nil,math.huge
        for _,box in ipairs(zones) do
            local delta=position-Vector3.new((box.x0+box.x1)/2,position.Y,(box.z0+box.z1)/2)
            if delta.Magnitude<nearest and delta.Magnitude>.01 then away,nearest=delta.Unit,delta.Magnitude end
        end
        return away or -direction,true,preferredSide
    end
    local function watch(v)
        if v.Name~="BossArenaTeleport" or not v:IsA("Model") or tracked[v] then return end
        tracked[v]=true;changed=true
        table.insert(links,v.DescendantAdded:Connect(function()changed=true end))
        table.insert(links,v.DescendantRemoving:Connect(function()changed=true end))
    end
    table.insert(links,workspace.ChildAdded:Connect(watch))
    table.insert(links,workspace.ChildRemoved:Connect(function(v)if tracked[v]then tracked[v]=nil;changed=true end end))
    for _,v in ipairs(workspace:GetChildren()) do watch(v) end
    function api.snapshot()
        if not changed and os.clock()-sampled<.1 then return cache end
        changed=false;sampled=os.clock();cache={}
        for model in pairs(tracked) do
            if model.Parent==workspace then
                local hitbox=model:FindFirstChild("Hitbox",true)
                local ok,cf,size
                if hitbox and hitbox:IsA("BasePart") then ok,cf,size=true,hitbox.CFrame,hitbox.Size
                else ok,cf,size=pcall(model.GetBoundingBox,model) end
                if ok and size.Magnitude>0 then
                    local box={x0=math.huge,x1=-math.huge,z0=math.huge,z1=-math.huge}
                    for _,x in ipairs({-1,1})do for _,y in ipairs({-1,1})do for _,z in ipairs({-1,1})do
                        local p=cf:PointToWorldSpace(size*Vector3.new(x,y,z)*.5)
                        box.x0=math.min(box.x0,p.X);box.x1=math.max(box.x1,p.X)
                        box.z0=math.min(box.z0,p.Z);box.z1=math.max(box.z1,p.Z)
                    end end end
                    table.insert(cache,box)
                end
            end
        end
        return cache
    end
    function api.destroy()for _,c in ipairs(links)do c:Disconnect()end;table.clear(links)end
    return api
end
-- Movement-only watchdog: interaction waits and temporarily disabled physics do not count as stuck.
local function createProgressWatch(now: number)
    local idleAt: number?=nil
    local progressAt=now
    local best=math.huge
    local waypoint=-1
    return function(at: number,moved: number,remaining: number,index: number,driving: boolean,speed: number): string?
        if not driving then idleAt=nil;progressAt=at;best=remaining;waypoint=index;return nil end
        if index~=waypoint or remaining<best-.4 then progressAt=at;best=remaining;waypoint=index end
        local minimum=math.clamp(speed*.25*.15,.05,.6)
        if moved<minimum then idleAt=idleAt or at else idleAt=nil end
        if idleAt and at-idleAt>=1.5 then return "Movement blocked" end
        if at-progressAt>=5 then return "No progress toward the next waypoint" end
        return nil
    end
end
local function createRunner(onStatus)
    local Run = game:GetService("RunService")
    local PF = game:GetService("PathfindingService")
    local Geo = require(RS.Shared.Util.GuardAreaGeometry)
    local Barriers = require(RS.Shared.Util.SafeZoneBarriers)
    local Identity = require(RS.Shared.Util.AreaEggSlotIdentity)
    local controls = require(player.PlayerScripts.PlayerModule):GetControls()
    local portals=createPortalAvoidance()
    local api={active=false,phase="Idle",collectedUid=nil :: string?}
    local current,disposed,serial=nil,false,0
    local connections={}
    local function flat(v) return Vector3.new(v.X,0,v.Z) end
    local function say(phase,message)
        api.phase=phase
        if phase=="Going" or phase=="Returning" or phase=="Travelling" or phase=="Picking" then gui:SetAttribute("WaitReason",nil)end
        if not disposed then onStatus(phase,message,api.active) end
        print("EGG_RUN_PHASE",phase,message)
    end
    local boundary=workspace:WaitForChild("__OBJECTS"):WaitForChild("Areas"):WaitForChild("SeparationLine")
    assert(boundary:IsA("BasePart"),"Area separation line is unavailable")
    local function line()return boundary end
    local function depth(pos) return Geo.SignedDistanceToLine(line(),pos) end
    local function findEgg(uid)
        if not uid then return nil end
        for _,r in pairs(State.ReadFieldEggs().Records) do if r.Uid==uid then return r end end
        return nil
    end
    local function canPick(r)
        return type(r)=="table" and (r.State=="Slot" or r.State=="Dropped")
            and r.CarrierUserId==nil and r.OwnerUserId==nil and r.Placement==nil
    end
    local function tracked(r)
        return findEgg(r.carriedUid or r.uid)
    end
    local function boxDistance(egg,pos)
        local p=egg.BoundsCFrame:PointToObjectSpace(pos)
        local h=egg.BoundsSize*0.5
        local q=Vector3.new(math.clamp(p.X,-h.X,h.X),math.clamp(p.Y,-h.Y,h.Y),math.clamp(p.Z,-h.Z,h.Z))
        return (pos-egg.BoundsCFrame:PointToWorldSpace(q)).Magnitude
    end
    local function pickupGoal(egg)
        local n=flat(line().CFrame.LookVector).Unit
        local cf,h=egg.BoundsCFrame,egg.BoundsSize*0.5
        local radius=math.abs(n:Dot(cf.RightVector))*h.X+math.abs(n:Dot(cf.UpVector))*h.Y+math.abs(n:Dot(cf.LookVector))*h.Z
        local p=egg.BottomCFrame.Position-n*(radius+2.5)
        p=Vector3.new(p.X,egg.BottomCFrame.Y+3,p.Z)
        local d=depth(p)
        if d<3 then p+=n*(3-d) end
        return p
    end
    local function safeGoal(pos)
        return pos-flat(line().CFrame.LookVector).Unit*(depth(pos)+18)
    end
    function api.safeReturnPoint()
        local ch=player.Character
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        if not player:GetAttribute("InBossArena") and root and depth(root.Position)>-12 then
            return safeGoal(root.Position)
        end
        return nil
    end
    local function valid(r)
        if disposed or current~=r or not api.active or r.token~=serial then error("CANCELLED",0) end
        if player:GetAttribute("InBossArena") then error("Entered the boss arena. Auto movement stopped.",0) end
        if player.Character~=r.character or not r.root.Parent or r.hum.Health<=0 then error("Character changed or died",0) end
        if os.clock()>r.expires then error("Run exceeded 5 minutes. Manual control restored.",0) end
        if r.uid and not r.ownedUid and resetInterruptsTrip(r,FieldCycle.read(),tracked(r),player.UserId) then error(RESET_INTERRUPTED,0) end
        if r.priorityCheck
            and ((not r.requestSent and not r.carryConfirmed) or r.ownedUid)
            and r.priorityCheck() then error(PRIORITY_INTERRUPTED,0) end
    end
    local function halt(r)
        r.path=nil
        if r.hum.Parent then r.hum:Move(Vector3.zero,false) end
    end
    local function release(r)
        if not r or r.released then return end
        r.released=true
        halt(r)
        if r.disabled then pcall(function()controls:Enable()end);r.disabled=false end
    end
    function api.stop(reason)
        if not current then return end
        local r=current
        serial+=1
        api.resumeTarget=r.uid
        api.resumeUid=r.carriedUid or r.uid
        current=nil
        api.active=false
        release(r)
        say("Stopped",reason or "Stopped. Manual control restored; held egg is kept.")
    end
    local function waitFor(r,seconds)
        local stop=os.clock()+seconds
        repeat valid(r);Run.Heartbeat:Wait() until os.clock()>=stop
    end
    local function isOwned(r)
        if r.ownedUid then return true end
        for _,owner in pairs(State.ReadOwnedEggs()) do
            if owner.OwnerUserId==player.UserId then
                for key,egg in pairs(owner.Records or {}) do
                    if not r.before[key] and egg.AssetCategory==r.category
                        and type(egg.AssetScale)=="number" and math.abs(egg.AssetScale-r.scale)<0.0001 then
                        r.ownedUid=tostring(key)
                        return true
                    end
                end
            end
        end
        return false
    end
    local function observe(r)
        local egg=tracked(r)
        if egg then
            r.lastSeen=os.clock()
            if egg.State=="Carried" and egg.CarrierUserId==player.UserId then r.seenCarriedRecord=true end
            if egg.State=="Dropped" then r.everDropped=true end
            if egg.State~=r.lastEggState then
                print("EGG_RUN_EGG_STATE",egg.State,egg.Uid,depth(r.root.Position))
                r.lastEggState=egg.State
            end
        end
        return egg
    end
    local function reachable(r,egg)
        return egg and canPick(egg) and boxDistance(egg,r.root.Position)<=6
            and depth(r.root.Position)>0
            and not Barriers.Separates(r.root.Position,egg.BoundsCFrame.Position,Barriers.IsFencedUid(egg.Uid))
    end
    local function pickupChanged(r,egg)
        -- A successful re-pick may arrive before the old Dropped record is replaced.
        -- Only a newer field record or a subsequent carry-clear confirms another drop.
        return r.carryLost or (egg and (egg.Version or 0)>(r.pickVersion or 0))
    end
    -- Compute the complete route before pickup. No pathfinder waits while escaping.
    local function navigationZones(r)
        local zones=table.clone(portals.snapshot())
        if r.avoidZones then
            for _,zone in ipairs(r.avoidZones()) do table.insert(zones,zone) end
        end
        return zones
    end
    local function computeSafePath(r,from,target)
        local path=PF:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=14})
        local ok,err=pcall(function()path:ComputeAsync(from,target)end)
        valid(r)
        if not ok then return nil,tostring(err),nil end
        if path.Status~=Enum.PathStatus.Success then return nil,"NO_PATH",nil end
        local candidate=path:GetWaypoints()
        if #candidate<2 then return nil,"Path has no usable waypoints",nil end
        local zones=navigationZones(r)
        local previous=from
        for i=2,#candidate do
            for _,zone in ipairs(zones) do
                if not portals.segmentSafe(previous,candidate[i].Position,{zone}) then
                    return nil,"Path crosses a navigation obstacle",zone
                end
            end
            previous=candidate[i].Position
        end
        return candidate,nil,nil
    end
    local function detourPath(r,start,goal,obstacle)
        -- Navigation paths can curve into a treadmill even when the straight
        -- line misses it. Validate the actual paths between detour corners.
        local zones=navigationZones(r)
        local nodes={start,goal}
        for _,padding in ipairs({12,24}) do
            for _,x in ipairs({obstacle.x0-padding,obstacle.x1+padding}) do
                for _,z in ipairs({obstacle.z0-padding,obstacle.z1+padding}) do
                    local point=Vector3.new(x,start.Y,z)
                    if portals.segmentSafe(point,point,zones) then table.insert(nodes,point) end
                end
            end
        end
        local distances,visited,previous,edges={[1]=0},{},{},{}
        local computations=0
        for _=1,#nodes do
            valid(r)
            local at,best=nil,math.huge
            for i,node in ipairs(nodes) do
                local score=(distances[i] or math.huge)+flat(goal-node).Magnitude
                if not visited[i] and score<best then at,best=i,score end
            end
            if not at then break end
            if at==2 then
                local legs={}
                while at~=1 do table.insert(legs,1,edges[at]);at=previous[at] end
                local points={{Position=start,Action=Enum.PathWaypointAction.Walk}}
                for _,leg in ipairs(legs) do
                    for i=2,#leg do table.insert(points,leg[i]) end
                end
                -- A portal may have spawned while the graph was being searched.
                zones=navigationZones(r)
                for i=2,#points do
                    if not portals.segmentSafe(points[i-1].Position,points[i].Position,zones) then return nil end
                end
                return points
            end
            visited[at]=true
            for i,target in ipairs(nodes) do
                if visited[i] or (at==1 and i==2) then continue end
                if not portals.segmentSafe(nodes[at],target,zones) then continue end
                if computations>=40 then continue end
                computations+=1
                local path=computeSafePath(r,nodes[at],target)
                if path then
                    local distance=distances[at]
                    local position=nodes[at]
                    for j=2,#path do distance+=flat(path[j].Position-position).Magnitude;position=path[j].Position end
                    if distance<(distances[i] or math.huge) then
                        distances[i]=distance;previous[i]=at;edges[i]=path
                    end
                end
            end
        end
        return nil
    end
    local function plan(r,start,destination)
        valid(r)
        if r.exitPoint then
            local exit=r.exitPoint
            local avoid=r.avoidZones
            r.exitPoint=nil;r.avoidZones=nil
            local ok,departure=pcall(plan,r,start,exit)
            r.avoidZones=avoid
            if not ok then r.exitPoint=exit;error(departure,0) end
            local onwardOK,onward=pcall(plan,r,exit,destination)
            if not onwardOK then r.exitPoint=exit;error(onward,0) end
            for i=2,#onward do table.insert(departure,onward[i]) end
            return departure
        end
        local zones=navigationZones(r)
        local anchors=portals.route(start,destination,zones)
        local points={{Position=start,Action=Enum.PathWaypointAction.Walk}}
        local from=start
        for leg=2,#anchors do
            local goal=anchors[leg]
            local reached=false
            for _=1,80 do
                local delta=flat(goal-from)
                if delta.Magnitude<1 then reached=true;break end
                -- A fixed 450-stud endpoint may land outside the walkable floor
                -- when leaving a plot. Try other endpoints before rejecting the route.
                local spans={math.min(450,delta.Magnitude)}
                if delta.Magnitude<=3000 then table.insert(spans,delta.Magnitude) end
                for _,span in ipairs({900,1800,2700,225}) do table.insert(spans,math.min(span,delta.Magnitude)) end
                local tried={}
                local wp,finishesLeg=nil,false
                local lastError="NO_PATH"
                local triedDetour=false
                for _,span in ipairs(spans) do
                    if tried[span] then continue end
                    tried[span]=true
                    local target=goal
                    if span<delta.Magnitude then
                        local p=from+delta.Unit*span
                        target=Vector3.new(p.X,goal.Y,p.Z)
                    end
                    local candidate,reason,obstacle=computeSafePath(r,from,target)
                    if not candidate and obstacle and not triedDetour then
                        triedDetour=true
                        candidate=detourPath(r,from,target,obstacle)
                    end
                    if not candidate then lastError=tostring(reason).." ("..math.round(span).." studs)";continue end
                    wp=candidate;finishesLeg=span>=delta.Magnitude
                    break
                end
                assert(wp,"No route from "..tostring(from).." toward "..tostring(goal)..": "..lastError)
                for i=2,#wp do table.insert(points,wp[i]) end
                from=wp[#wp].Position
                if finishesLeg then reached=true;break end
            end
            assert(reached,"NO_PATH")
        end
        return points
    end
    -- Pure steering calculation: progress along segments, look ahead on straight runs,
    -- and retain full unit input. It never lowers WalkSpeed or zeros input at waypoints.
    local function steer(path,pos,speed,dt)
        local pts=path.points
        local index=path.index
        local reach=math.clamp(speed*math.min(dt,0.05)*0.7,1.2,4)
        while index<=#pts do
            local a,b=pts[index-1].Position,pts[index].Position
            local segment=flat(b-a)
            local d=flat(b-pos)
            local passed=segment.Magnitude<0.01 or flat(pos-a):Dot(segment.Unit)>=segment.Magnitude
            if d.Magnitude<=reach or passed then index+=1 else break end
        end
        path.index=index
        if index>#pts then path.done=true;return Vector3.zero,false end
        local a,b=pts[index-1].Position,pts[index].Position
        local target=b
        local forward=flat(b-a)
        local budget=math.clamp(speed*0.22,8,48)
        local remaining=flat(b-pos).Magnitude
        local j=index
        -- Don't cut across corners or skip a jump.
        while remaining<budget and j<#pts and forward.Magnitude>0.01 do
            local nextSegment=flat(pts[j+1].Position-pts[j].Position)
            if nextSegment.Magnitude<0.01 then j+=1;continue end
            if pts[j+1].Action==Enum.PathWaypointAction.Jump
                or nextSegment.Unit:Dot(forward.Unit)<0.97 then break end
            local step=math.min(nextSegment.Magnitude,budget-remaining)
            target=pts[j].Position+nextSegment.Unit*step
            remaining+=step
            if step<nextSegment.Magnitude then break end
            forward=nextSegment
            j+=1
        end
        local direction=flat(target-pos)
        local jump=pts[index].Action==Enum.PathWaypointAction.Jump
        return direction.Magnitude>0.1 and direction.Unit or Vector3.zero,jump,target
    end
    local function move(r,destination,interrupt,prepared,approach,retarget)
        local replans=0
        local points=prepared
        while true do
            valid(r)
            if retarget then destination=retarget() or destination end
            if r.resetMotion then
                r.resetMotion=false;r.exitPoint=nil;points=nil
                if r.resetReturning then destination=safeGoal(r.root.Position) end
            end
            local signal=interrupt and interrupt()
            if signal then halt(r);return signal end
            if flat(destination-r.root.Position).Magnitude<=3 then halt(r);return "arrived" end
            if not points then
                local ok,result=pcall(plan,r,r.root.Position,destination)
                if not ok then
                    valid(r)
                    replans+=1
                    if replans>5 then error("No usable path after 5 attempts: "..tostring(result),0) end
                    say(r.phase,"Route blocked; retrying from current position ("..replans.."/5)")
                    recordEvent("replan","Route blocked / attempt "..replans.." of 5")
                    waitFor(r,0.3)
                    continue
                end
                points=result
            end
            -- Planning yields. Entry/cancellation may complete before it returns.
            valid(r)
            signal=interrupt and interrupt()
            if signal then halt(r);return signal end
            if r.resetMotion then points=nil;continue end
            local path={points=points,index=2,done=false,approach=approach,goal=destination,intent=0}
            r.path=path
            points=nil
            local sampleAt,lastPos=os.clock(),r.root.Position
            local progress=createProgressWatch(sampleAt)
            while true do
                valid(r)
                -- PreSimulation can clear r.path as soon as the arena flag arrives.
                -- Observe the transition before examining the old route or replanning.
                signal=interrupt and interrupt()
                if signal then halt(r);return signal end
                if r.path~=path or path.done then break end
                if retarget then
                    local latest=retarget()
                    if latest and flat(latest-destination).Magnitude>math.clamp(r.hum.WalkSpeed*.15,12,40) then
                        -- A moving carrier is not a cancellation. Keep this path
                        -- steering while the next path computes, even if the target
                        -- moved during that computation. Otherwise it can starve
                        -- movement by cancelling every newly computed path.
                        destination=latest
                        break
                    end
                end
                if r.portalReplan then
                    r.portalReplan=nil
                    -- Keep steering around the hitbox while the new path computes.
                    say(r.phase,"Dodging the portal at full input; updating the route")
                    recordEvent("replan","Route updated around a portal")
                    break
                end
                Run.Heartbeat:Wait()
                if os.clock()-sampleAt>=0.25 then
                    local travelled=flat(r.root.Position-lastPos).Magnitude
                    local state=r.hum:GetState()
                    local driving=path.intent>.05 and r.hum.WalkSpeed>0 and not r.root.Anchored and not r.hum.PlatformStand and not r.hum.Sit
                        and r.hum.FloorMaterial~=Enum.Material.Air and state~=Enum.HumanoidStateType.GettingUp
                        and state~=Enum.HumanoidStateType.Ragdoll and state~=Enum.HumanoidStateType.FallingDown
                        and state~=Enum.HumanoidStateType.Physics
                    local waypoint=path.points[path.index]
                    local remaining=waypoint and flat(waypoint.Position-r.root.Position).Magnitude or 0
                    local reason=progress(os.clock(),travelled,remaining,path.index,driving,r.hum.WalkSpeed)
                    lastPos,sampleAt=r.root.Position,os.clock()
                    if reason then
                        replans+=1
                        if replans>5 then error("Blocked after 5 route recoveries. Manual control restored.",0) end
                        print("EGG_RUN_REPLAN",r.phase,tostring(r.root.Position),r.hum.WalkSpeed,tostring(r.hum:GetState()))
                        say(r.phase,reason.."; recovering route ("..replans.."/5)")
                        recordEvent("replan",reason.." / attempt "..replans.." of 5")
                        break
                    end
                end
            end
            -- Preserve steering until the replacement path has finished computing.
            if r.path==path and path.done then halt(r) end
        end
    end
    table.insert(connections,Run.PreSimulation:Connect(function(dt)
        local r=current
        if not r or not api.active or r.released then return end
        if player.Character~=r.character or not r.root.Parent or r.hum.Health<=0 then return end
        local now=os.clock()
        if r.motionAt then
            local dtMotion=now-r.motionAt
            if (r.root.Position-r.motionPos).Magnitude>math.max(90,r.hum.WalkSpeed*dtMotion*3+20) then
                local cycle=FieldCycle.read()
                if not player:GetAttribute("InBossArena")
                    and (r.resetReturning or cycle.epoch~=r.resetEpoch or (cycle.blocked and not r.startedBlocked)) then
                    -- Reset relocation can land near either side of the boundary, or
                    -- interrupt a treadmill trip. Rebuild from the actual position.
                    r.resetTeleported=r.uid~=nil and not r.ownedUid
                    r.resetMotion=true
                    if not r.resetTeleported then r.resetEpoch=cycle.epoch;r.startedBlocked=cycle.blocked end
                    if r.path then r.path.done=true end
                else api.stop("Unexpected teleport detected. Auto movement stopped.");return end
            end
        end
        r.motionAt,r.motionPos=now,r.root.Position
        if not r.path then r.hum:Move(Vector3.zero,false);return end
        local commandedSpeed=r.hum.WalkSpeed
        local fraction=1
        if r.path.approach then
            local remaining=flat(r.path.goal-r.root.Position).Magnitude
            local brakingZone=math.clamp(r.hum.WalkSpeed*0.4,28,95)
            if remaining<brakingZone then
                commandedSpeed=math.min(r.hum.WalkSpeed,math.max(6,remaining*2.2))
                fraction=commandedSpeed/math.max(r.hum.WalkSpeed,0.001)
            end
        end
        local zones=navigationZones(r)
        local direction,jump,target=steer(r.path,r.root.Position,commandedSpeed,dt)
        if target and #zones>0 then
            local adjusted,avoiding,side=portals.dodge(r.root.Position,direction,
                flat(r.root.AssemblyLinearVelocity or Vector3.zero),commandedSpeed,zones,r.portalSide)
            direction=adjusted;r.portalSide=side
            if avoiding and now-(r.lastPortalReplan or 0)>.75 then
                r.portalReplan=true;r.lastPortalReplan=now
            end
        end
        -- Ease only the last approach; travel and escape retain full input.
        local input=direction*fraction*(r.path.inputScale or 1)
        r.path.intent=input.Magnitude
        r.hum:Move(input,false)
        if jump then r.hum.Jump=true end
    end))
    table.insert(connections,State.CarryChanged:Connect(function(payload)
        local r=current
        if not r then return end
        if payload.IsCarrying and payload.AreaId==r.area and payload.AssetCategory==r.category then
            r.carriedUid=payload.Uid or r.carriedUid
            r.carryConfirmed=true
            r.carryLost=false
        elseif payload.IsCarrying==false and r.carryConfirmed then
            r.carryConfirmed=false
            r.carryLost=true
            if depth(r.root.Position)>0 then recordEvent("drop","Dropped "..r.category.." / recovering the same egg") end
        end
        print("EGG_RUN_CARRY",payload.IsCarrying,payload.Uid,payload.SpeedMultiplier,depth(r.root.Position))
        -- Carry-clear is not deletion and is never a completion or stop condition.
    end))
    table.insert(connections,State.FieldClaimed:Connect(function(payload)
        local r=current
        if r and r.requestSent and payload.AssetCategory==r.category then
            r.claimFeedback=true
            print("EGG_RUN_CLAIM",payload.AssetCategory,depth(r.root.Position))
        end
    end))
    table.insert(connections,Input.InputBegan:Connect(function(input)
        if not api.active or Input:GetFocusedTextBox() then return end
        local k=input.KeyCode
        if k==Enum.KeyCode.W or k==Enum.KeyCode.A or k==Enum.KeyCode.S or k==Enum.KeyCode.D
            or k==Enum.KeyCode.Up or k==Enum.KeyCode.Down or k==Enum.KeyCode.Left
            or k==Enum.KeyCode.Right or k==Enum.KeyCode.Escape then
            api.stop("Stopped by keyboard. Manual control restored.")
        end
    end))
    local function createPursuit(r)
        local active,pending=true,false
        local nextPlan,serial=0,0
        local computed,direct=nil,nil
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.RespectCanCollide=true
        local function filters()
            local ignored={}
            for _,p in ipairs(Players:GetPlayers()) do
                if p.Character then table.insert(ignored,p.Character) end
            end
            params.FilterDescendantsInstances=ignored
        end
        local function clearStep(from,goal)
            if not portals.segmentSafe(from,goal,navigationZones(r)) then return false end
            local delta=flat(goal-from)
            if delta.Magnitude<.1 then return true end
            if workspace:Blockcast(CFrame.new(from),Vector3.new(3,3,3),delta,params) then return false end
            local side=Vector3.new(-delta.Unit.Z,0,delta.Unit.X)*1.5
            -- A clear ray alone is insufficient: reject gaps and steep terrain.
            for i=1,math.max(1,math.ceil(delta.Magnitude/10)) do
                local p=from+delta*(i/math.max(1,math.ceil(delta.Magnitude/10)))
                for _,offset in ipairs({Vector3.zero,side,-side}) do
                    local hit=workspace:Raycast(p+offset+Vector3.yAxis*5,-Vector3.yAxis*13,params)
                    if not hit or hit.Normal.Y<.65 or math.abs(hit.Position.Y-(from.Y-3))>4 then return false end
                end
            end
            return true
        end
        local api={}
        function api.step(goal,velocity,range,stopDistance)
            filters()
            local from=r.root.Position
            local delta=flat(goal-from)
            local distance=delta.Magnitude
            local lead=math.clamp(distance/math.max(r.hum.WalkSpeed,1)*.25,.02,.12)
            local ahead=flat(velocity)*lead
            if ahead.Magnitude>12 then ahead=ahead.Unit*12 end
            local projected=goal+ahead
            local direction=flat(projected-from)
            local horizon=math.clamp(r.hum.WalkSpeed*.35,24,96)
            local step=direction.Magnitude>horizon and from+direction.Unit*horizon or Vector3.new(projected.X,from.Y,projected.Z)
            if clearStep(from,step) then
                -- Keep pursuing during swings/cooldowns; match a nearby carrier
                -- instead of stopping at the old half-bat-range threshold.
                -- Match motion along the interception direction. An incoming
                -- carrier needs less closing speed, not their speed added to ours.
                local following=direction.Magnitude>.01 and flat(velocity):Dot(direction.Unit) or 0
                local standOff=stopDistance or math.clamp(range*.35,4,12)
                local speed=math.max(0,(distance-standOff)*8+following)
                direct={points={{Position=from},{Position=step}},index=2,done=false,goal=step,
                    inputScale=math.clamp(speed/math.max(r.hum.WalkSpeed,1),0,1)}
                r.path=direct
                computed=nil
                return
            end
            if r.path==direct then halt(r);direct=nil end
            if computed and not computed.done then r.path=computed end
            local now=os.clock()
            if pending or now<nextPlan then return end
            pending=true;nextPlan=now+.35;serial+=1
            local ticket=serial
            local target=goal
            -- Compute a local leg, not a full egg-return route to a moving player.
            if delta.Magnitude>256 then target=from+delta.Unit*256 end
            task.spawn(function()
                local ok,points=pcall(computeSafePath,r,from,target)
                if not active or ticket~=serial or current~=r then return end
                pending=false
                if not ok or not points then return end
                local path={points=points,index=2,done=false,goal=target}
                computed=path
                -- Do not replace a newer unobstructed pursuit with an old detour.
                if r.path~=direct or not direct then r.path=path end
            end)
        end
        function api.stop()
            active=false;serial+=1
            if current==r then halt(r) end
        end
        return api
    end
    local carrierSwingAt=setmetatable({},{__mode="k"})
    local function chaseCarrier(r)
        local Guard=require(RS.Client.ToolGameplayGuard)
        local Ragdoll=require(RS.Shared.Modules.Ragdoll)
        local Gears=require(RS.Data.Gears)
        local BatConfig=require(RS.Shared.Modules.BatController.Config)
        local previous=r.character:FindFirstChildOfClass("Tool")
        local usedBat=nil
        local pursuit=createPursuit(r)
        local missingSince=nil
        local function contender()
            local egg=tracked(r)
            if not egg then
                missingSince=missingSince or os.clock()
                return nil,nil,os.clock()-missingSince<.6 and "sync" or "gone"
            end
            missingSince=nil
            if canPick(egg) or egg.CarrierUserId==player.UserId then return nil,nil,"available" end
            if egg.State=="GuardCarried" then return nil,nil,"available" end
            if egg.State~="Carried" or not egg.CarrierUserId then return nil,nil,"gone" end
            local other=Players:GetPlayerByUserId(egg.CarrierUserId)
            local ch=other and other.Character
            local root=ch and ch:FindFirstChild("HumanoidRootPart")
            local hum=ch and ch:FindFirstChildOfClass("Humanoid")
            if not other or not root or not hum or hum.Health<=0 then return nil,nil,"gone" end
            if other:GetAttribute("InBossArena") or not Guard.IsInsideArena(other) or Guard.IsInsideSafeZone(other) then return nil,nil,"claimed" end
            return other,root,nil
        end
        local function findBat()
            local best,range=nil,0
            for _,container in ipairs({r.character,player:FindFirstChildOfClass("Backpack")}) do
                for _,tool in ipairs(container and container:GetChildren() or {}) do
                    if tool:IsA("Tool") and tool:GetAttribute("IsBat")==true then
                        local cfg=Gears.Directory[tool:GetAttribute("GearName")]
                        local reach=(BatConfig.Range+BatConfig.HitTolerance+(cfg and cfg.BatControllerData and cfg.BatControllerData.RangeBonus or 0))*BatConfig.GetHitboxScalar()
                        if reach>range then best,range=tool,reach end
                    end
                end
            end
            return best,range
        end
        local function swing(other,root,tool,range)
            if not Guard.IsInsideArena(player) or Guard.IsInsideSafeZone(player) then return end
            -- Nominate only while currently inside the game's real selection
            -- radius. A predicted crossing alone cannot make a valid Bat target.
            if (root.Position-r.root.Position).Magnitude>range or Ragdoll.IsRagdolled(r.character) or Ragdoll.IsRagdolled(other.Character) then return end
            if tool.Parent~=r.character then r.hum:EquipTool(tool);usedBat=tool;return end
            -- The game's Bat selects the nearest eligible player. Close the gap
            -- if a bystander is nearer instead of swinging at the wrong player.
            local distance=(root.Position-r.root.Position).Magnitude
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=player and p~=other and not p:GetAttribute("InBossArena") then
                    local ch=p.Character
                    local pr=ch and ch:FindFirstChild("HumanoidRootPart")
                    local ph=ch and ch:FindFirstChildOfClass("Humanoid")
                    if pr and ph and ph.Health>0 and not Ragdoll.IsRagdolled(ch)
                        and Guard.IsInsideArena(p) and (pr.Position-r.root.Position).Magnitude<=distance+.01 then return end
                end
            end
            local cooldown=tool:GetAttribute("CooldownEndTime")
            -- The Bat server applies 0.7 seconds. Replicated cooldown remains
            -- authoritative; the local floor also prevents duplicate frame sends.
            if tool.Enabled and not tool:GetAttribute("CooldownActive") and (type(cooldown)~="number" or cooldown<=workspace:GetServerTimeNow()) and os.clock()-(carrierSwingAt[tool] or -math.huge)>=.7 then
                carrierSwingAt[tool]=os.clock();tool:Activate()
            end
        end
        local attackError=nil
        local function attackNow()
            if current~=r or player.Character~=r.character or r.hum.Health<=0 then return end
            local other,root,outcome=contender()
            if outcome or not other or not root then return end
            local tool,range=findBat()
            if tool then swing(other,root,tool,range) end
        end
        -- Catch the post-physics crossing before the next pursuit iteration.
        -- Re-read the egg carrier each time; never retain a stale victim.
        local attackConnection=Run.PostSimulation:Connect(function()
            local success,err=pcall(attackNow)
            if not success then attackError=err end
        end)
        local ok,result=pcall(function()
            r.phase="Contesting";say("Contesting","Following the player carrying this egg; stop at the safe zone.")
            while true do
                valid(r)
                if attackError then error(attackError,0) end
                local other,root,outcome=contender()
                if outcome=="sync" then halt(r);Run.Heartbeat:Wait();continue end
                if outcome then return outcome end
                local tool,range=findBat()
                if not tool then return "no bat" end
                if tool.Parent~=r.character then r.hum:EquipTool(tool);usedBat=tool end
                swing(other,root,tool,range)
                pursuit.step(root.Position,root.AssemblyLinearVelocity or Vector3.zero,range)
                Run.Heartbeat:Wait()
            end
        end)
        attackConnection:Disconnect()
        pursuit.stop()
        -- Restore equipment only while this trip still owns the character.
        if current==r and usedBat and usedBat.Parent==r.character then
            r.hum:UnequipTools()
            if previous and previous.Parent==player:FindFirstChildOfClass("Backpack") then r.hum:EquipTool(previous) end
        end
        if not ok then error(result,0) end
        return result
    end

    local function defendPickup(r,egg)
        local Guard=require(RS.Client.ToolGameplayGuard)
        local Ragdoll=require(RS.Shared.Modules.Ragdoll)
        if not Guard.IsInsideArena(player) or Guard.IsInsideSafeZone(player) or Ragdoll.IsRagdolled(r.character) then return end
        local rival=nil
        for _,other in ipairs(Players:GetPlayers()) do
            if other~=player and not other:GetAttribute("InBossArena") then
                local ch=other.Character
                local root=ch and ch:FindFirstChild("HumanoidRootPart")
                local hum=ch and ch:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health>0 and not Ragdoll.IsRagdolled(ch)
                    and Guard.IsInsideArena(other) and not Guard.IsInsideSafeZone(other)
                    and boxDistance(egg,root.Position)<=8 and (root.Position-r.root.Position).Magnitude<=12 then rival=other;break end
            end
        end
        if not rival then return end
        local backpack=player:FindFirstChildOfClass("Backpack")
        local batTool=nil
        for _,container in ipairs({r.character,backpack}) do
            for _,tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("IsBat")==true then batTool=tool;break end
            end
            if batTool then break end
        end
        if not batTool then return end
        local previous=r.character:FindFirstChildOfClass("Tool")
        local equipped=batTool.Parent~=r.character
        if equipped then r.hum:EquipTool(batTool);Run.Heartbeat:Wait() end
        valid(r)
        local root=rival.Character and rival.Character:FindFirstChild("HumanoidRootPart")
        local fresh=tracked(r)
        local cooldown=batTool:GetAttribute("CooldownEndTime")
        if fresh and canPick(fresh) and root and boxDistance(fresh,root.Position)<=8
            and (root.Position-r.root.Position).Magnitude<=12 and Guard.IsInsideArena(rival) and not Guard.IsInsideSafeZone(rival)
            and not rival:GetAttribute("InBossArena") and not Ragdoll.IsRagdolled(rival.Character)
            and batTool.Enabled and not batTool:GetAttribute("CooldownActive")
            and (type(cooldown)~="number" or cooldown<=workspace:GetServerTimeNow()) then
            batTool:Activate();waitFor(r,.1)
        end
        if equipped and current==r then
            r.hum:UnequipTools()
            if previous and previous.Parent==backpack then r.hum:EquipTool(previous) end
        end
    end
    local function execute(r,initial)
        valid(r)
        controls:Disable()
        r.disabled=true
        local egg=initial
        local function returnRoute()
            r.safe=safeGoal(r.root.Position)
            local points=plan(r,r.root.Position,r.safe)
            if r.delivery then
                -- Plan both legs before pickup; the safe boundary is a waypoint,
                -- so controls remain owned by this runner through the whole return.
                local onward=plan(r,r.safe,r.delivery.destination)
                for i=2,#onward do table.insert(points,onward[i]) end
            end
            return points
        end
        local attempt=0
        while attempt<8 do
            valid(r)
            egg=observe(r) or egg
            local localCarry=egg and egg.State=="Carried" and egg.CarrierUserId==player.UserId
            local returnPath=nil
            if not localCarry then
                if egg and canPick(egg) then
                    r.phase=attempt==0 and "Going" or "Recovering"
                    say(r.phase,(attempt==0 and "Running to " or "Recovering the same egg: ")..r.category.." / "..r.area)
                    local result=move(r,pickupGoal(egg),function()
                        local latest=observe(r)
                        if latest and reachable(r,latest) then return "ready" end
                        if latest and not canPick(latest) then return "changed" end
                        if latest and flat(latest.BottomCFrame.Position-egg.BottomCFrame.Position).Magnitude>8 then return "changed" end
                        if not latest and os.clock()-r.lastSeen>3 then return "changed" end
                        return nil
                    end,nil,true)
                    egg=observe(r)
                    if result=="changed" or not egg or not reachable(r,egg) then continue end
                    -- Settle momentum before planning and starting the pickup hold.
                    local settleUntil=os.clock()+0.8
                    repeat
                        valid(r)
                        local velocity=r.root.AssemblyLinearVelocity
                        if velocity and flat(velocity).Magnitude<=2 then break end
                        waitFor(r,0.04)
                    until os.clock()>=settleUntil
                    egg=observe(r)
                    if not egg or not reachable(r,egg) then continue end
                    r.phase="Preparing"
                    say("Preparing","Preparing the escape route before pickup")
                    returnPath=returnRoute()
                    egg=observe(r)
                    if not egg or not reachable(r,egg) then continue end
                    r.phase="Picking"
                    defendPickup(r,egg)
                    valid(r)
                    say("Picking","Picking up "..r.category.." (attempt "..(attempt+1).."/8)")
                    waitFor(r,workspace:GetAttribute("FastEggPickupTime") and 0.25 or 1.2)
                    egg=observe(r)
                    if not egg or not reachable(r,egg) then continue end
                    local key=Identity.LooksLikeFirstAreaUid(egg.Uid) and Identity.SlotKey(egg.AreaId,egg.NestId) or nil
                    r.requestSent=true
                    r.carryConfirmed=false
                    r.carryLost=false
                    r.seenCarriedRecord=false
                    r.everDropped=false
                    r.pickVersion=egg.Version or 0
                    attempt+=1
                    local ok=State.CarryFieldEgg(egg.Uid,key)
                    valid(r)
                    if not ok then
                        say("Recovering","Pickup declined; checking the same egg again")
                        waitFor(r,0.4)
                        continue
                    end
                    local timeout=os.clock()+4
                    while not r.carryConfirmed do
                        valid(r)
                        local latest=observe(r)
                        if latest and latest.CarrierUserId==player.UserId then r.carryConfirmed=true;break end
                        if latest and pickupChanged(r,latest) and (latest.State=="Dropped" or latest.State=="GuardCarried") then break end
                        if os.clock()>timeout then break end
                        Run.Heartbeat:Wait()
                    end
                elseif egg and egg.State=="GuardCarried" then
                    r.phase="Waiting"
                    say("Waiting","Monster is carrying this egg home. Waiting for it to be placed.")
                    if depth(r.root.Position)>-12 then
                        move(r,safeGoal(r.root.Position),function()
                            local e=observe(r)
                            if e and canPick(e) then return "available" end
                            return nil
                        end)
                    end
                    local timeout=os.clock()+35
                    repeat
                        valid(r)
                        egg=observe(r)
                        if egg and canPick(egg) then break end
                        waitFor(r,0.2)
                    until os.clock()>timeout
                    continue
                elseif egg and egg.State=="Carried" then
                    local outcome=chaseCarrier(r)
                    if outcome=="available" then r.safe=nil;continue end
                    r.phase="Returning"
                    say("Returning","Contest ended ("..tostring(outcome).."). Returning safely and checking another egg.")
                    move(r,safeGoal(r.root.Position),function()
                        if depth(r.root.Position)<=-12 then return "safe" end
                        return nil
                    end)
                    error(TARGET_UNAVAILABLE,0)
                else
                    r.phase="Returning"
                    say("Returning","Checking the egg status while returning safely.")
                end
            end
            r.phase="Returning"
            r.safe=r.safe or safeGoal(r.root.Position)
            if r.delivery and not returnPath then returnPath=returnRoute() end
            say("Returning","Running at current game speed; recovering this egg if it drops.")
            local result=move(r,r.delivery and r.delivery.destination or r.safe,function()
                if r.delivery and depth(r.root.Position)<=-8 and isOwned(r) then
                    if r.delivery.priorityCheck and r.delivery.priorityCheck() then error(PRIORITY_INTERRUPTED,0) end
                    if r.phase~="Delivering" then
                        r.phase="Delivering"
                        say("Delivering","Egg received. Continuing directly to the hatching space.")
                    end
                    return nil
                end
                local latest=observe(r)
                local stalePickup=r.carryConfirmed and not pickupChanged(r,latest)
                if latest and canPick(latest) and not stalePickup and not r.claimFeedback
                    and (latest.State=="Dropped" or r.seenCarriedRecord or r.everDropped or (latest.Version or 0)>(r.pickVersion or 0)) then return "recover" end
                if latest and latest.State=="Carried" and latest.CarrierUserId~=player.UserId and not stalePickup and not r.claimFeedback then return "contest" end
                if latest and latest.State=="GuardCarried" and not stalePickup and not r.claimFeedback then return "guard" end
                if not r.delivery and depth(r.root.Position)<=-12 then return "safe" end
                return nil
            end,returnPath,r.delivery~=nil)
            if result=="recover" or result=="guard" or result=="contest" then
                r.safe=nil
                egg=observe(r)
                continue
            end
            if depth(r.root.Position)<=-8 then
                r.phase="Confirming"
                say("Confirming","Inside the safe zone. Waiting for the egg in your inventory.")
                local timeout=os.clock()+10
                repeat
                    valid(r)
                    if isOwned(r) then
                        print("EGG_RUN_COMPLETE_INVENTORY",r.category,depth(r.root.Position))
                        return
                    end
                    egg=observe(r)
                    if egg and canPick(egg) then break end
                    waitFor(r,0.2)
                until os.clock()>timeout
                if egg and (canPick(egg) or egg.State=="GuardCarried") then r.safe=nil;continue end
                error("Safe zone reached, but inventory did not confirm the egg.",0)
            end
        end
        r.phase="Returning"
        say("Returning","Pickup retry limit reached. Returning safely before checking other eggs.")
        move(r,safeGoal(r.root.Position),function()
            if depth(r.root.Position)<=-12 then return "safe" end
            return nil
        end)
        if isOwned(r) then return end
        local remaining=tracked(r)
        if (remaining and remaining.CarrierUserId==player.UserId) or (r.carryConfirmed and not r.carryLost) then
            error("Safe zone reached, but a carried egg still needs confirmation.",0)
        end
        error(TARGET_UNAVAILABLE,0)
    end
    function api.start(uid,expectedCycle,delivery)
        if disposed or api.active then return end
        local cycle=FieldCycle.read()
        if cycle.blocked or (expectedCycle and expectedCycle~=cycle.epoch) then
            say("ResetWait","Night/reset in progress. Waiting for the new field eggs.");return
        end
        local ok,egg=pcall(findEgg,uid)
        if ok and not egg and uid==api.resumeTarget then egg=findEgg(api.resumeUid) end
        if not ok or not egg or not (canPick(egg) or isContestable(egg) or (egg.State=="Carried" and egg.CarrierUserId==player.UserId)) then say("Unavailable","This egg is no longer available.");return end
        local ch=player.Character
        local hum=ch and ch:FindFirstChildOfClass("Humanoid")
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        if not hum or not root or hum.Health<=0 then say("Unavailable","Character is not ready.");return end
        local carried=nil
        for _,v in pairs(State.ReadFieldEggs().Records) do
            if v.CarrierUserId==player.UserId then carried=v;break end
        end
        if carried and carried.Uid~=egg.Uid then
            say("Unavailable","Already carrying another egg. Finish returning it first.");return
        end
        local before={}
        for _,owner in pairs(State.ReadOwnedEggs()) do
            if owner.OwnerUserId==player.UserId then for key in pairs(owner.Records or {}) do before[key]=true end end
        end
        serial+=1
        api.collectedUid=nil
        local r = {
            token = serial,
            uid = egg.Uid,
            category = egg.AssetCategory,
            area = egg.AreaId,
            scale = egg.AssetScale,
            character = ch,
            hum = hum,
            root = root,
            before = before,
            phase = "Going",
            lastSeen = os.clock(),
            expires = os.clock() + 300,
            resetEpoch = FieldCycle.read().epoch,
            startedBlocked = false,
            requestSent = false,
            delivery = delivery and delivery.destination and delivery or nil,
            priorityCheck = delivery and delivery.priorityCheck,
            avoidZones = delivery and delivery.avoidZones,
            exitPoint = delivery and delivery.exitPoint,
            carryConfirmed = egg.State=="Carried" and egg.CarrierUserId==player.UserId,
            carryLost = false,
            ownedUid = nil :: string?,
        }
        current,api.active=r,true
        say("Going","Starting "..r.category.." / "..r.area)
        task.spawn(function()
            local success,err=pcall(execute,r,egg)
            local resetWait=false
            if not success and err==RESET_INTERRUPTED then
                success,err=pcall(function()
                    r.resetReturning=true;r.path=nil;r.phase="Returning"
                    say("Returning","Field eggs reset. Returning safely before waiting for the next cycle.")
                    move(r,safeGoal(r.root.Position),function()
                        if depth(r.root.Position)<=-12 then return "safe" end
                        return nil
                    end)
                    local deadline=os.clock()+(r.requestSent and 5 or .3)
                    repeat
                        valid(r)
                        if isOwned(r) then return end
                        waitFor(r,.1)
                    until os.clock()>=deadline
                    resetWait=true
                end)
            end
            release(r)
            if current~=r then return end
            current,api.active=nil,false
            api.collectedUid=r.ownedUid
            if r.ownedUid then recordEvent("trip","Delivered "..r.category.." to inventory") end
            if not success and err==PRIORITY_INTERRUPTED then
                local message=r.ownedUid
                    and "Egg delivered. Continuing the next feature in your priority order."
                    or "Yielding before pickup to a higher-priority ready feature."
                say("Yielded",message)
            elseif not success and err==TARGET_UNAVAILABLE then say("RetryWait","Safely returned; this target is unavailable. Checking other eggs while it refreshes.")
            elseif success and resetWait then say("ResetWait","Safely returned after field reset. Ready to wait for the next cycle.")
            elseif success then say("Complete","Egg is in your inventory and you are inside the safe zone.")
            else
                if not r.ownedUid then deferFieldEgg(r.uid) end
                local message=tostring(err):gsub("^.-:%d+: ","")
                say("Stopped",message)
            end
        end)
    end
    -- Shared movement for the Rift plot and machine trips; one movement owner.
    function api.carriedReturnPoint()
        for _,egg in pairs(State.ReadFieldEggs().Records) do
            if egg.CarrierUserId==player.UserId then
                local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if root then return safeGoal(root.Position) end
            end
        end
        return nil
    end
    function api.travel(destination, label, interrupt, avoidZones,exitPoint)
        assert(not disposed and not api.active,"Another trip is already active")
        local ch=player.Character
        local hum=ch and ch:FindFirstChildOfClass("Humanoid")
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        assert(hum and root and hum.Health>0,"Character is not ready")
        serial+=1
        local r = {
            token = serial,
            character = ch,
            hum = hum,
            root = root,
            phase = "Travelling",
            expires = os.clock() + 180,
            resetEpoch = FieldCycle.read().epoch,
            startedBlocked = FieldCycle.read().blocked,
            avoidZones = avoidZones,
            exitPoint = exitPoint,
            requestSent = false,
        }
        current,api.active=r,true
        say("Travelling",label or "Travelling")
        local outcome
        local ok,err=pcall(function()
            controls:Disable();r.disabled=true
            outcome=move(r,destination,interrupt,nil,true)
        end)
        release(r)
        if current==r then
            current,api.active=nil,false
            say(ok and "Arrived" or "Stopped",ok and "Destination reached" or tostring(err))
        end
        if not ok then error(err,0) end
        return outcome
    end
    function api.follow(readTarget,label,avoidZones)
        assert(not disposed and not api.active,"Another trip is already active")
        local ch=player.Character
        local hum=ch and ch:FindFirstChildOfClass("Humanoid")
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        assert(hum and root and hum.Health>0,"Character is not ready")
        serial+=1
        local r={token=serial,character=ch,hum=hum,root=root,phase="Travelling",expires=os.clock()+90,
            resetEpoch=FieldCycle.read().epoch,requestSent=false,avoidZones=avoidZones}
        current,api.active=r,true
        say("Travelling",label)
        local pursuit=createPursuit(r)
        local ok,err=pcall(function()
            controls:Disable();r.disabled=true
            while true do
                valid(r)
                local point,velocity,range=readTarget()
                if not point then break end
                pursuit.step(point,velocity or Vector3.zero,range or 6,math.max(.5,range or 6))
                Run.Heartbeat:Wait()
            end
        end)
        pursuit.stop();release(r)
        if current==r then current=nil;api.active=false;say(ok and "Arrived" or "Stopped",ok and "Target finished" or tostring(err)) end
        if not ok then error(err,0) end
    end
    function api.destroy()
        api.stop("Closed")
        disposed=true
        portals.destroy()
        for _,c in ipairs(connections) do c:Disconnect() end
    end
    table.insert(connections,player:GetAttributeChangedSignal("InBossArena"):Connect(function()
        if player:GetAttribute("InBossArena") then
            api.stop("Entered the boss arena. Auto movement stopped.")
            if riftController then riftController.interruptForRecovery("Inside the boss arena") end
        end
    end))
    return api
end

runner = createRunner(function(phase,message,active)
    if not alive then return end
    runStatus.Text=string.upper(phase)
    runDetail.Text=message
    runStatus.TextColor3=(phase=="Stopped" or phase=="Unavailable") and Color3.fromRGB(244,132,154) or C.mint
    stopTrip.Visible=manualStarting or (active and not areaWatch.enabled and not indexWatch.enabled and not (riftController and riftController.active))
    gui:SetAttribute("RunnerActive",active)
    gui:SetAttribute("RunnerPhase",phase)
    gui:SetAttribute("RunnerMessage",message)
end)
gui:SetAttribute("RunnerActive",false)
gui:SetAttribute("RunnerPhase","Idle")
local function selectEgg(row)
    if (eventController and eventController.busy) or runner.active or manualStarting then runDetail.Text="A trip is already in progress. Wait or use STOP TRIP.";return end
    if areaWatch.enabled or indexWatch.enabled or (riftController and (riftController.active or riftController.committing)) then
        runDetail.Text="Pause Auto Area, Auto Index and The Rift before starting a manual collection.";return
    end
    selectedTarget={uid=row.uid}
    gui:SetAttribute("SelectedEggUid",row.uid)
    targetLabel.Text=row.pet.."  /  "..row.rarity.."  /  "..row.area.."  /  "..row.nest
    runStatus.Text="STARTING"
    runDetail.Text=row.carrierId and "Following the carrier until this egg drops; then returning safely." or "Starting your collection trip..."
    if riftController then riftController.collectOnce(row.uid) else runner.start(row.uid) end
    render(false)
end
connect(stopTrip.Activated,function()
    if eventController and eventController.busy then runDetail.Text="DR Scramble owns this trip. Use its toggle to leave, or WASD for manual control.";return end
    if areaWatch.enabled or indexWatch.enabled or (riftController and riftController.active) then
        runDetail.Text="This trip belongs to automation. Use its feature toggle or WASD to stop.";return
    end
    if riftController then riftController.stop("Manual trip stopped","Manual")
    elseif runner.active then runner.stop("Manual trip stopped. Held egg is kept.") end
end)
local function readSnapshot()
    local groups = {}
    for _, a in ipairs(areaList) do groups[a.id] = {} end
    local field = State.ReadFieldEggs()
    assert(type(field) == "table" and type(field.Records) == "table", "Field records unavailable")
    for key, r in pairs(field.Records) do
        if (isCollectible(r) or isContestable(r)) and groups[r.AreaId] then
            local config = Assets.Directory[r.AssetCategory]
            local mutations = r.Mutations or {}
            local weightOK, weight = pcall(Records.WeightKgForScale, r.AssetCategory, r.AssetScale)
            local rate = fieldEggIncome(r)
            local icon = config and config.Icon
            local pet = config and config.DisplayName or r.AssetCategory
            local rarity, rarityColor = petRarity(r.AssetCategory)
            local mutation = #mutations > 0 and table.concat(mutations, ", ") or "Normal"
            table.insert(groups[r.AreaId], {
                uid = tostring(r.Uid or key), pet = pet, mutation = mutation,
                carrierId=r.CarrierUserId,carrierName=r.CarrierUserId and (Players:GetPlayerByUserId(r.CarrierUserId) and Players:GetPlayerByUserId(r.CarrierUserId).DisplayName or tostring(r.CarrierUserId)) or nil,
                rarity = rarity, rarityColor = rarityColor,
                nest = r.NestId, state = r.State, area = r.AreaId, weight = weightOK and weight or nil,
                rate = rate, icon = type(icon) == "string" and icon or "",
                query = (pet .. " " .. r.AssetCategory .. " " .. rarity .. " " .. r.AreaId .. " " .. areaById[r.AreaId].name .. " " .. r.NestId .. " " .. mutation):lower(),
            })
        end
    end
    for _, rows in pairs(groups) do
        table.sort(rows, function(a, b)
            if (a.rate or -1) == (b.rate or -1) then return a.uid < b.uid end
            return (a.rate or -1) > (b.rate or -1)
        end)
    end
    return groups
end
local snapshotRevision=0
local function areasVisible(): boolean
    local tab=gui:GetAttribute("ActiveTab")
    return panel.Visible and (tab==nil or tab=="Areas")
end
render = function(resetScroll)
    if not alive or not areasVisible() then return end
    local yourPower=SpeedProjection.ReadProjected()
    local character=player.Character
    local hum=character and character:FindFirstChildOfClass("Humanoid")
    UI.RenderAreas({gui=gui,areaView=areaView,snapshotGroups=snapshotGroups,selected=selected,selectedTarget=selectedTarget,
        runner=runner,manualStarting=manualStarting,areaWatch=areaWatch,indexWatch=indexWatch,riftController=riftController,
        snapshotRevision=snapshotRevision,areaList=areaList,areaById=areaById,compact=compact,selectEgg=selectEgg,
        yourPower=yourPower,walkSpeed=hum and hum.WalkSpeed or SpeedUtil.SpeedPowerToWalkSpeed(yourPower),
        isAlive=function()return alive end,isVisible=areasVisible},resetScroll)
end
local lastSnapshotKey: string?=nil
local function snapshotKey(groups)
    local parts={}
    for _,area in ipairs(areaList) do
        table.insert(parts,area.id..":"..tostring(area.requiredPower))
        for _,row in ipairs(groups[area.id] or {}) do
            table.insert(parts,table.concat({row.uid,row.query,row.state,tostring(row.carrierId),tostring(row.carrierName),tostring(row.weight),tostring(row.rate),row.icon},"\31"))
        end
    end
    return table.concat(parts,"\30")
end
local function refresh()
    fit()
    -- Collection decisions use EggState directly, independent of the visible list.
    if not areasVisible() then return end
    updateAreaRequirements()
    local ok, result = pcall(readSnapshot)
    if not alive then return end
    if ok then
        snapshotGroups = result
        live.Text = "LIVE"
        live.TextColor3 = C.mint
        local key=snapshotKey(result)
        if key~=lastSnapshotKey then snapshotRevision+=1 end
        lastSnapshotKey=key
        render(false)
    else
        snapshotGroups = {}
        lastSnapshotKey=nil
        snapshotRevision+=1
        render(false)
        live.Text = "DATA ERROR"
        live.TextColor3 = Color3.fromRGB(244, 132, 154)
        subheading.Text = "Unable to read current eggs. Retrying automatically."
    end
end
connect(search:GetPropertyChangedSignal("Text"), function() render(true) end)
connect(panel:GetPropertyChangedSignal("Visible"), function()
    if panel.Visible then refresh() end
end)
local requestRefresh=refreshScheduler(refresh,.1)
connect(gui:GetAttributeChangedSignal("ActiveTab"),requestRefresh)
local function eggChanged()
    eggRevision+=1
    requestRefresh()
    if requestRiftRefresh then requestRiftRefresh() end
end
for _,signal in ipairs({State.FieldRefreshed,State.FieldShifted,State.FieldGone,
    State.SnapshotRefreshed,State.CarryChanged,State.FieldClaimed,State.ResetCountdown,State.ResetFade}) do
    connect(signal,eggChanged)
end
refresh()
print("EGG_ATLAS_READY", gui:GetAttribute("RecordCount"), "eggs", #areaList, "areas")
task.spawn(function()
    while alive do
        -- Backup for timer boundaries and missed events; reads local state only.
        task.wait(.5)
        if alive then requestRefresh() end
    end
end)

-- DR Scramble: replicated personal targets, normal movement and game-owned attacks.
local function createScrambleModel(owner)
    local api={snapshot=nil :: any,latestState=nil :: any,drones={},drops={},droneRevision=-1,stateRevision=-1,fullRevision=-1,ready=false,pending={}}
    function api.applyDrones(packet)
        if type(packet)~="table" or packet.OwnerUserId~=owner or type(packet.Revision)~="number" or packet.Revision<=api.droneRevision then return end
        if not api.ready and not packet.Full then api.pending[packet.Revision]=packet;return end
        api.ready=true;api.droneRevision=packet.Revision
        if packet.Full then table.clear(api.drones) end
        for _,id in ipairs(packet.Removed or {}) do api.drones[id]=nil end
        for _,drone in ipairs(packet.Upserts or {}) do
            if drone.OwnerUserId==owner and type(drone.Id)=="string" then api.drones[drone.Id]=drone end
        end
        local revisions={}
        for revision in pairs(api.pending) do table.insert(revisions,revision) end
        table.sort(revisions)
        for _,revision in ipairs(revisions) do local queued=api.pending[revision];api.pending[revision]=nil;api.applyDrones(queued) end
    end
    function api.addDrops(drops)
        for _,drop in ipairs(drops or {}) do
            if type(drop.Id)=="string" and (drop.OwnerUserId==nil or drop.OwnerUserId==owner) then api.drops[drop.Id]=drop end
        end
    end
    function api.apply(value)
        if type(value)~="table" or type(value.Revision)~="number" then return end
        if value.Drones then api.applyDrones(value.Drones) end
        if not value.Patch and value.Revision>api.fullRevision then
            api.fullRevision=value.Revision
            api.snapshot=table.clone(value)
            api.addDrops(value.Drops)
        end
        if value.Revision>api.stateRevision then
            api.stateRevision=value.Revision
            api.latestState={State=value.State,Ready=value.Ready}
        end
        if api.snapshot and api.latestState then api.snapshot.State=api.latestState.State;api.snapshot.Ready=api.latestState.Ready end
    end
    function api.available(now)
        local s=api.snapshot
        return s~=nil and s.Ready==true and s.Enabled==true and s.WorldReady==true
            and type(s.EventEndsAt)=="number" and now<s.EventEndsAt
    end
    function api.quest(now,blocked): string?
        if not api.available(now) then return nil end
        local s=api.snapshot
        local state=s.State
        if type(state)~="table" or state.Completed then return nil end
        if not state.Discovered then return not blocked.Discover and "Discover" or nil end
        for _,id in ipairs({"LostPart1","LostPart2"}) do
            if not (state.LostParts or {})[id] and not blocked[id] then return id end
        end
        if state.TotalParts==5 and s.VaultRewardReady==true and not blocked.Vault then return "Vault" end
        return nil
    end
    function api.active(now)
        local s=api.snapshot
        return api.available(now) and type(s.Window)=="table" and s.Window.Active==true
            and type(s.Window.EndsAt)=="number" and now<s.Window.EndsAt
    end
    return api
end

local function createScrambleController(page)
    local remotes=require(RS.Shared.Remotes).Scramble
    local Motion=require(RS.Shared.Util.ScrambleDroneMotion)
    local Run=game:GetService("RunService")
    local model=createScrambleModel(player.UserId)
    local view=UI.CreateEventWidgets(page)
    local api={enabled=false,busy=false,phase="Off",message=""}
    local disposed=false
    local cancelled=false
    local nextAttempt=0
    local eventRevision=0
    local delayed={}
    local motionCache={}
    local fetching=false
    local lastFetch=-math.huge
    local startSamples=nil
    local function character()
        local ch=player.Character
        local hum=ch and ch:FindFirstChildOfClass("Humanoid")
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        if hum and hum.Health>0 and root then return root end
        return nil
    end
    local function position(drone)
        local attrs=drone.Attributes or {}
        local encoded=attrs.DroneMotion
        local cached=motionCache[drone.Id]
        if not cached or cached.encoded~=encoded then
            local ok,value=pcall(Motion.Decode,encoded)
            cached={encoded=encoded,value=ok and value or nil};motionCache[drone.Id]=cached
        end
        local motion=cached.value
        if motion then
            local alpha=math.clamp((workspace:GetServerTimeNow()-motion.At)/math.max(motion.Duration,.001),0,1)
            if motion.Name=="Knockback" then alpha=alpha*alpha*(3-2*alpha) end
            return motion.From:Lerp(motion.To,alpha).Position
        end
        return typeof(drone.CFrame)=="CFrame" and drone.CFrame.Position or nil
    end
    local function target()
        local root=character()
        if not root then return nil end
        local best,score=nil,math.huge
        local now=workspace:GetServerTimeNow()
        for id,drone in pairs(model.drones) do
            if type(drone.Health)=="number" and drone.Health>0 and (not drone.ExpiresAt or now<drone.ExpiresAt)
                and os.clock()>=(delayed[id] or 0) then
                local p=position(drone)
                if p then
                    local distance=(p-root.Position).Magnitude
                    if distance<score then best,score=drone,distance end
                end
            end
        end
        return best
    end
    local function groundDrop()
        local root=character()
        if not root then return nil end
        local best,distance=nil,math.huge
        local now=workspace:GetServerTimeNow()
        for id,drop in pairs(model.drops) do
            if type(drop.ExpiresAt)~="number" or drop.ExpiresAt<=now then model.drops[id]=nil
            elseif not drop.MagnetAt and typeof(drop.Position)=="Vector3" and os.clock()>=(delayed[id] or 0) then
                local d=(drop.Position-root.Position).Magnitude
                if d<distance then best,distance=drop,d end
            end
        end
        return best
    end
    local function say(phase,message)
        api.phase,api.message=phase,message
        if not alive or disposed then return end
        view.stateText.Text=string.upper(phase);view.detail.Text=message
        gui:SetAttribute("EventPhase",phase);gui:SetAttribute("EventMessage",message)
        if api.busy then gui:SetAttribute("WaitReason",phase=="Waiting" and message or nil) end
    end
    local function caveTeleporter()
        local objects=workspace:FindFirstChild("__OBJECTS")
        local secret=objects and objects:FindFirstChild("SecretZones")
        local cave=secret and secret:FindFirstChild("Cave")
        return cave and cave:FindFirstChild("Teleporter")
    end
    local function insideCave()
        local root=character()
        local gates=caveTeleporter()
        local arrival=gates and gates:FindFirstChild("EntryTp")
        return root~=nil and arrival~=nil and arrival:IsA("BasePart")
            and math.abs(root.Position.Y-arrival.Position.Y)<65 and (root.Position-arrival.Position).Magnitude<180
    end
    local function questJob(): string?
        local blocked={}
        for id,untilTime in pairs(delayed) do if untilTime>os.clock() then blocked[id]=true end end
        return model.quest(workspace:GetServerTimeNow(),blocked)
    end
    function api.hasOpportunity(): boolean
        return api.enabled and not disposed and not cancelled and not manualStarting and not player:GetAttribute("InBossArena")
            and (insideCave() or (os.clock()>=nextAttempt and (questJob()~=nil
                or (model.active(workspace:GetServerTimeNow()) and (target()~=nil or groundDrop()~=nil)))))
    end
    function api.needsExit(): boolean
        return api.enabled and not disposed and not cancelled and not manualStarting and insideCave()
    end
    local function check()
        if not alive or disposed or cancelled or not api.enabled then error("EVENT_CANCELLED",0) end
    end
    local function fetch()
        if fetching then return end
        fetching=true;lastFetch=os.clock()
        local revision=eventRevision
        local ok,value=pcall(function()return remotes.Request:InvokeServer("Snapshot")end)
        fetching=false
        if not disposed and alive and ok and type(value)=="table" then
            -- Revisions protect state/drones. Drops have no revision, so a newer
            -- removal must win over an older in-flight snapshot of those drops.
            if revision~=eventRevision then value=table.clone(value);value.Drops=nil end
            model.apply(value)
        end
        if not ok and not api.busy then say("Retrying","Event data unavailable; retrying while your toggle stays on.") end
    end
    local function questPoint(id)
        local s=model.snapshot
        local info=s and s.Quest and s.Quest[id]
        if info and typeof(info.Position)=="Vector3" then return info.Position end
        local folder=workspace:FindFirstChild("DrScrambleEvent")
        local object=folder and folder:FindFirstChild(id)
        local interaction=object and object:FindFirstChild("InteractionPoint",true)
        if interaction and interaction:IsA("Attachment") then return interaction.WorldPosition end
        if object and object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart.Position end
        return nil
    end
    local function questDone(id): boolean
        local state=model.snapshot and model.snapshot.State
        if not state then return false end
        if id=="Discover" then return state.Discovered==true end
        if id=="Vault" then return state.Completed==true end
        return state.Completed==true or (state.LostParts or {})[id]==true
    end
    local function crossCave(enter,zones)
        if insideCave()==enter then return end
        local gates=caveTeleporter()
        local trigger=gates and gates:FindFirstChild(enter and "Entry" or "Exit")
        local landing=gates and gates:FindFirstChild(enter and "EntryTp" or "ExitTp")
        assert(trigger and trigger:IsA("BasePart") and landing and landing:IsA("BasePart"),"Waiting for the cave entrance to load")
        local prompt=trigger:FindFirstChild("SecretZonePrompt",true)
        assert(prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled,"Cave interaction is unavailable")
        local attachment=prompt.Parent
        local point=attachment and attachment:IsA("Attachment") and attachment.WorldPosition or trigger.Position
        local deadline=os.clock()+45
        local function arrived(pos)
            return math.abs(pos.Y-landing.Position.Y)<12
                and (pos-landing.Position).Magnitude<22
        end
        local root=character()
        assert(root,"Character is not ready")
        local near=Vector3.new(point.X,root.Position.Y,point.Z)
        runner.travel(near,enter and "Approaching the secret cave" or "Approaching the cave exit",function()
            check()
            if os.clock()>deadline then error("Cave approach timed out",0) end
            local current=character()
            if current and (current.Position-point).Magnitude<math.min(7,prompt.MaxActivationDistance-2) then return "At cave gate" end
            return nil
        end,zones)
        -- The gate uses a ProximityPrompt, not touch. Movement is released before
        -- the game's transport, so normal unexpected-teleport protection remains intact.
        check()
        root=character()
        assert(root and (root.Position-point).Magnitude<=prompt.MaxActivationDistance,"Outside cave interaction range")
        say("Quest",enter and "Entering the secret cave" or "Leaving the secret cave")
        for attempt=1,5 do
            check()
            root=character()
            assert(root,"Character is not ready")
            if arrived(root.Position) then return end
            assert(prompt.Enabled and (root.Position-point).Magnitude<=prompt.MaxActivationDistance,"Outside cave interaction range")
            prompt:InputHoldBegin()
            local ok,err=pcall(function()
                local untilTime=os.clock()+prompt.HoldDuration+.15
                while os.clock()<untilTime do
                    check()
                    local current=character()
                    assert(current,"Character is not ready")
                    if arrived(current.Position) then break end
                    assert((current.Position-point).Magnitude<=prompt.MaxActivationDistance,"Moved away from the cave entrance")
                    Run.Heartbeat:Wait()
                end
            end)
            prompt:InputHoldEnd()
            if not ok then error(err,0) end
            -- A prompt immediately after arrival may still be on the game's cooldown.
            deadline=os.clock()+3
            repeat
                check()
                local current=character()
                assert(current,"Character is not ready")
                if arrived(current.Position) then return end
                Run.Heartbeat:Wait()
            until os.clock()>=deadline
            if attempt==5 then error("Cave entrance did not transport the character",0) end
        end
    end
    local function doQuest(id,zones)
        if questDone(id) then return end
        local underground=id=="Discover" or id=="Vault"
        crossCave(underground,zones)
        check()
        local key=id=="Discover" and "EscapedExperiment" or id=="Vault" and "ExperimentVault" or id
        local point=questPoint(key)
        assert(point,"Quest location has not loaded: "..key)
        local label=id=="Discover" and "Talking to Escaped Experiment" or id=="Vault" and "Repairing the Vault / claiming The Scrambler"
            or "Collecting "..(id=="LostPart1" and "Mechanical Gear" or "Wiring Harness")
        say("Quest",label)
        local root=character()
        assert(root,"Character is not ready")
        local goal=Vector3.new(point.X,root.Position.Y,point.Z)
        runner.travel(goal,label,function()
            check()
            if not model.available(workspace:GetServerTimeNow()) then error("Event is unavailable",0) end
            if questDone(id) then return "Already collected" end
            return nil
        end,zones)
        check()
        if questDone(id) then return end
        root=character()
        point=questPoint(key)
        assert(root and point,"Quest target disappeared")
        if underground then
            local s=model.snapshot
            local radius=(s.Interactions or {})[id=="Discover" and "NpcRadius" or "VaultRadius"] or 12
            assert((root.Position-point).Magnitude<=radius,"Outside quest interaction range")
            if id=="Vault" then assert(s.State.Discovered and s.State.TotalParts==5 and s.VaultRewardReady,"Vault is not ready") end
            local result=remotes.Request:InvokeServer(id)
            check()
            assert(type(result)=="table" and result.Ok==true,"Quest request was not accepted: "..tostring(type(result)=="table" and (result.Reason or result.Error) or result))
            model.apply(result.Snapshot)
        else
            local folder=workspace:FindFirstChild("DrScrambleEvent")
            local object=folder and folder:FindFirstChild(id)
            local prompt=object and object:FindFirstChild("ClaimLostPart",true)
            assert(prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled,"Part is not ready to collect")
            assert((root.Position-point).Magnitude<=prompt.MaxActivationDistance,"Outside part pickup range")
            prompt:InputHoldBegin()
            local ok,err=pcall(function()
                local untilTime=os.clock()+prompt.HoldDuration+.15
                while os.clock()<untilTime do
                    check()
                    local current=character()
                    assert(current and (current.Position-point).Magnitude<=prompt.MaxActivationDistance,"Moved away from the part")
                    Run.Heartbeat:Wait()
                end
            end)
            prompt:InputHoldEnd()
            if not ok then error(err,0) end
        end
        -- The server owns progress. Never mark a part or reward claimed locally.
        fetch()
        local deadline=os.clock()+4
        while not questDone(id) and os.clock()<deadline do check();Run.Heartbeat:Wait() end
        assert(questDone(id),"Waiting for the server to confirm "..id)
    end
    local function run()
        local zones,exitPoint=riftController.pauseForEvent(function()return disposed or not alive or cancelled or not api.enabled end)
        check()
        local safe=runner.carriedReturnPoint()
        if safe then
            say("Returning","Delivering the held egg before collecting Samples.")
            runner.travel(safe,"Delivering the held egg before DR Scramble",function()check();return nil end,zones,exitPoint)
            exitPoint=nil
            local deadline=os.clock()+6
            while runner.carriedReturnPoint() and os.clock()<deadline do check();Run.Heartbeat:Wait() end
            assert(not runner.carriedReturnPoint(),"Waiting for the held egg to reach inventory")
        end
        while true do
            check()
            if higherPriorityWork("Event") then break end
            local job=questJob()
            if job then
                if exitPoint then runner.travel(exitPoint,"Leaving the treadmill for the quest",function()check();return nil end,zones,exitPoint);exitPoint=nil end
                local ok,err=pcall(doQuest,job,zones)
                check()
                if not ok then delayed[job]=os.clock()+30;say("Retrying",tostring(err).." / quest will retry") end
                continue
            end
            if insideCave() then crossCave(false,zones) end
            if not model.active(workspace:GetServerTimeNow()) then break end
            local drop=groundDrop()
            local drone=target()
            if not drop and not drone then break end
            local id=drop and drop.Id or drone.Id
            local lastHealth=drone and drone.Health
            local progressAt=os.clock()
            local begun=os.clock()
            local label=drop and "Collecting dropped Samples / parts" or ("Following "..tostring((drone.Attributes or {}).ScrambleTier).." / "..tostring((drone.Attributes or {}).ScrambleArea))
            say(drop and "Collecting" or "Hunting",label)
            local ok,err=pcall(function()
                if exitPoint then
                    runner.travel(exitPoint,"Leaving the treadmill for DR Scramble",function()check();return nil end,zones,exitPoint)
                    exitPoint=nil
                end
                runner.follow(function()
                    check()
                    if not model.active(workspace:GetServerTimeNow()) or higherPriorityWork("Event") then return nil end
                    if drop then
                        local current=model.drops[id]
                        if not current or workspace:GetServerTimeNow()>=current.ExpiresAt then return nil end
                        if os.clock()-begun>6 then delayed[id]=os.clock()+8;return nil end
                        return current.Position,Vector3.zero,math.max(.5,math.min((current.Radius or 3)*.35,2))
                    end
                    local current=model.drones[id]
                    if not current or current.Health<=0 then return nil end
                    if current.Health~=lastHealth then lastHealth=current.Health;progressAt=os.clock() end
                    if os.clock()-progressAt>25 then delayed[id]=os.clock()+12;return nil end
                    local p=position(current)
                    if not p then return nil end
                    local root=character()
                    return Vector3.new(p.X,root and root.Position.Y or p.Y,p.Z),Vector3.zero,6
                end,label,zones)
            end)
            check()
            if not ok then delayed[id]=os.clock()+12;say("Retrying",tostring(err).." / trying another reachable target") end
            -- The game's client collects magnetized rewards itself. Do not send duplicate collect requests.
            local untilTime=os.clock()+.35
            repeat check();Run.Heartbeat:Wait() until os.clock()>=untilTime
        end
        check()
        if insideCave() then crossCave(false,zones) end
        local safePoint=runner.safeReturnPoint()
        if safePoint then
            say("Returning","Returning safely; your enabled features resume next.")
            runner.travel(safePoint,"Returning from DR Scramble",function()check();return nil end,zones)
        end
    end
    function api.setEnabled(on)
        api.enabled=on==true;cancelled=not api.enabled
        if not restoringConfig then rememberToggle("autoEvent",api.enabled) end
        view.sw:SetAttribute("On",api.enabled);gui:SetAttribute("EventEnabled",api.enabled)
        TweenService:Create(view.sw,TweenInfo.new(.18),{BackgroundColor3=api.enabled and Color3.fromRGB(52,199,89) or Color3.fromRGB(67,76,91)}):Play()
        TweenService:Create(view.dot,TweenInfo.new(.18),{Position=UDim2.fromOffset(api.enabled and 31 or 3,3)}):Play()
        if not api.enabled and api.busy and runner.active then runner.stop("DR Scramble disabled") end
        if not api.busy then say(api.enabled and "Waiting" or "Off",api.enabled and "Other features continue until your personal drones appear." or "DR Scramble automation is off.") end
    end
    function api.destroy()
        disposed=true;cancelled=true;api.enabled=false
        if api.busy and runner.active then runner.stop("DR Scramble closed") end
        table.clear(model.drones);table.clear(model.drops);table.clear(motionCache)
    end
    connect(view.sw.Activated,function()api.setEnabled(not api.enabled)end)
    connect(remotes.State.OnClientEvent,function(value)eventRevision+=1;model.apply(value);eggRevision+=1 end)
    connect(remotes.Drones.OnClientEvent,function(value)
        eventRevision+=1
        model.applyDrones(value)
        for id in pairs(motionCache) do if not model.drones[id] then motionCache[id]=nil end end
    end)
    connect(remotes.Drops.OnClientEvent,function(value)eventRevision+=1;model.addDrops(value)end)
    connect(remotes.RemoveDrops.OnClientEvent,function(ids)eventRevision+=1;for _,id in ipairs(ids)do model.drops[id]=nil end end)
    connect(Input.InputBegan,function(input)
        if not api.busy or Input:GetFocusedTextBox() then return end
        local k=input.KeyCode
        if k==Enum.KeyCode.W or k==Enum.KeyCode.A or k==Enum.KeyCode.S or k==Enum.KeyCode.D or k==Enum.KeyCode.Escape
            or k==Enum.KeyCode.Up or k==Enum.KeyCode.Down or k==Enum.KeyCode.Left or k==Enum.KeyCode.Right then api.setEnabled(false) end
    end)
    local nextPaint=0
    connect(Run.Heartbeat,function()
        if disposed or os.clock()<nextPaint then return end
        nextPaint=os.clock()+.2
        if not fetching and os.clock()-lastFetch>=5 then task.spawn(fetch) end
        local ok,err=pcall(function()
                local s=model.snapshot
                if s then
                    local state=s.State or {}
                    local samples=state.Samples or 0
                    startSamples=startSamples or samples
                    view.samples.Text=compact(samples).." SAMPLES"
                    view.parts.Text=state.Completed and "VAULT CLAIMED" or tostring(state.TotalParts or 0).." / 5 parts"
                    local lost=state.LostParts or {}
                    view.questText.Text=string.format("Mechanical Gear: %s   /   Wiring Harness: %s   /   Drone parts: %d / 3\n%s",
                        lost.LostPart1 and "Collected" or "Missing",lost.LostPart2 and "Collected" or "Missing",state.DroneParts or 0,
                        state.Completed and "The Scrambler claimed. Drone collection continues during outbreaks."
                        or not state.Discovered and "Next: visit Escaped Experiment in the secret cave."
                        or state.TotalParts==5 and "Next: return to the Vault and claim The Scrambler."
                        or "Missing map parts are collected between rounds; drone parts come from outbreaks.")
                    gui:SetAttribute("EventQuestParts",state.TotalParts or 0);gui:SetAttribute("EventQuestCompleted",state.Completed==true)
                    local count=0;for _,d in pairs(model.drones)do if d.Health>0 then count+=1 end end
                    view.targets.Text=tostring(count).." personal drones"
                    local active=model.active(workspace:GetServerTimeNow())
                    local boundary=s.Window and (active and s.Window.EndsAt or s.Window.NextAt)
                    local remaining=type(boundary)=="number" and math.max(0,math.ceil(boundary-workspace:GetServerTimeNow())) or 0
                    view.timeText.Text=string.format(active and "ROUND ENDS  %02d:%02d" or "NEXT ROUND  %02d:%02d",remaining//60,remaining%60)
                    gui:SetAttribute("EventSamples",samples);gui:SetAttribute("EventDrones",count)
                    gui:SetAttribute("EventRoundActive",active)
                    gui:SetAttribute("EventSamplesGained",math.max(0,samples-startSamples))
                end
        end)
        if not ok and not api.busy then say("Retrying",tostring(err)) end
    end)
    task.spawn(function()
        while alive and not disposed do
            local ok,err=pcall(function()
                if not restoringConfig and not api.busy and os.clock()>=nextAttempt and api.hasOpportunity() and not higherPriorityWork("Event") then
                    api.busy=true;cancelled=false;gui:SetAttribute("EventBusy",true);gui:SetAttribute("AutomationOwner","Event")
                    local success,failure=pcall(run)
                    if runner.active then runner.stop("DR Scramble trip finished") end
                    api.busy=false
                    if not alive or disposed then return end
                    gui:SetAttribute("EventBusy",false);gui:SetAttribute("AutomationOwner",nil)
                    riftController.resumeAfterEvent()
                    nextAttempt=os.clock()+(success and .5 or 3)
                    if not success and not cancelled then say("Retrying",tostring(failure).." / toggle stays on")
                    else say(api.enabled and "Waiting" or "Off",api.enabled and "Other features resumed; waiting for personal drones or the next round." or "DR Scramble automation is off.") end
                end
            end)
            if not ok and alive and not disposed then
                if api.busy then
                    if runner.active then runner.stop("Recovering DR Scramble") end
                    api.busy=false;gui:SetAttribute("EventBusy",false)
                    riftController.resumeAfterEvent()
                end
                say("Retrying",tostring(err));nextAttempt=os.clock()+3
            end
            task.wait(.2)
        end
    end)
    api.setEnabled(false)
    return api
end


-- The game's Index is discovery; IndexClaimedCategories only tracks reward claims.
type IndexJob = {kind: string,category: string,entry: {uid: string,egg: any}?,egg: any?}
type IndexAreaProgress = {id: string,name: string,total: number,found: number,targetTotal: number,targetFound: number,selected: boolean,
    missing: {{category: string,name: string,icon: string,state: string,selected: boolean}}}
type IndexPlan = {areas: {IndexAreaProgress},wanted: {[string]: boolean},total: number,found: number,
    missing: number,selected: number,collectionTotal: number,collectionFound: number,job: IndexJob?}
type IndexDependencies = {
    save: () -> any,owned: () -> {[string]: any},field: () -> {[any]: any},
    areas: {{id: string,name: string,config: any}},assets: {[string]: any},
    ready: (string) -> boolean,pending: (string) -> boolean,
    collectible: (any) -> boolean,retry: (any) -> boolean,rate: (any) -> number?,distance: ((any) -> number)?,
}
local function createIndexCollection(deps: IndexDependencies)
    local api={}
    function api.scan(selected: {[string]: boolean},blocked: boolean,options: IndexOptions?): IndexPlan
        local save=deps.save()
        assert(type(save)=="table" and type(save.Index)=="table","Waiting for the game's Index data")
        local owned=deps.owned()
        local targets=options and options.targets or {}
        local strategy=options and options.strategy or "income"
        local function selectedTarget(area: string,category: string): boolean
            local choices=targets[area]
            return not choices or choices[category]~=false
        end
        local have,inventory={},{}
        for uid,egg in pairs(owned) do
            local list=have[egg.AssetCategory] or {};have[egg.AssetCategory]=list
            table.insert(list,{uid=uid,egg=egg})
        end
        for _,item in pairs(save.Inventory or {}) do inventory[item.Category]=true end
        local result: IndexPlan={areas={},wanted={},total=0,found=0,missing=0,selected=0,collectionTotal=0,collectionFound=0,job=nil}
        local ordered={}
        for _,area in ipairs(deps.areas) do
            local row: IndexAreaProgress={id=area.id,name=area.name,total=0,found=0,targetTotal=0,targetFound=0,missing={},selected=selected[area.id]==true}
            local seen={}
            for _,drop in ipairs(area.config.DropTable or {}) do
                local category=drop[1]
                local asset=deps.assets[category]
                if type(drop[2])=="number" and drop[2]>0 and asset and asset.DontRoll~=true and not seen[category] then
                    seen[category]=true;row.total+=1
                    local chosen=selectedTarget(area.id,category)
                    if chosen then row.targetTotal+=1 end
                    if save.Index[category]==true then
                        row.found+=1
                        if chosen then row.targetFound+=1 end
                    else
                        local state=inventory[category] and "SYNCING INDEX" or "WAITING FOR SPAWN"
                        local list=have[category]
                        if deps.pending(category) then state="HATCHING"
                        elseif list and #list>0 then
                            local growing,ready=false,false
                            for _,entry in ipairs(list) do
                                if entry.egg.Placement then
                                    growing=true
                                    if deps.ready(entry.uid) then ready=true end
                                end
                            end
                            state=ready and "READY TO HATCH" or (growing and "GROWING" or "READY TO PLACE")
                        end
                        table.insert(row.missing,{category=category,name=asset.DisplayName or category,icon=asset.Icon or "",state=state,selected=chosen})
                        if row.selected and chosen and not result.wanted[category] then
                            result.wanted[category]=true;table.insert(ordered,category)
                        end
                    end
                end
            end
            if row.selected then
                result.selected+=1;result.total+=row.targetTotal;result.found+=row.targetFound
                result.missing+=row.targetTotal-row.targetFound
                result.collectionTotal+=row.total;result.collectionFound+=row.found
            end
            table.insert(result.areas,row)
        end
        -- Use one existing egg of each selected missing species before collecting another.
        for _,category in ipairs(ordered) do
            if not deps.pending(category) and not inventory[category] then
                local list=have[category] or {}
                table.sort(list,function(a,b)
                    local ar=a.egg.Placement~=nil and deps.ready(a.uid)
                    local br=b.egg.Placement~=nil and deps.ready(b.uid)
                    if ar~=br then return ar end
                    if (a.egg.Placement==nil)~=(b.egg.Placement==nil) then return a.egg.Placement~=nil end
                    return tostring(a.uid)<tostring(b.uid)
                end)
                local entry=list[1]
                if entry then
                    if not entry.egg.Placement then result.job={kind="plant",entry=entry,category=category};return result end
                    if deps.ready(entry.uid) then result.job={kind="hatch",entry=entry,category=category};return result end
                end
            end
        end
        if blocked then return result end
        local best,bestScore,bestRate,bestUid=nil,-math.huge,-math.huge,""
        for key,egg in pairs(deps.field()) do
            local category=egg.AssetCategory
            if selected[egg.AreaId] and selectedTarget(egg.AreaId,category) and result.wanted[category] and not have[category] and not inventory[category]
                and not deps.pending(category) and deps.collectible(egg) and deps.retry(egg) then
                local rate=deps.rate(egg) or -math.huge
                local score=rate
                if strategy=="nearest" then score=deps.distance and -deps.distance(egg) or -math.huge
                elseif strategy=="rarity" then
                    local asset=deps.assets[category]
                    score=asset and asset.Rarity and tonumber(asset.Rarity.RarityNumber) or -math.huge
                end
                local uid=tostring(egg.Uid or key)
                if not best or score>bestScore or (score==bestScore and (rate>bestRate or (rate==bestRate and uid<bestUid))) then
                    best=egg;bestScore=score;bestRate=rate;bestUid=uid
                end
            end
        end
        if best then result.job={kind="collect",egg=best,category=best.AssetCategory} end
        return result
    end
    return api
end


-- Index presentation is owned by the UI module.
local function createIndexPage(page: Frame,controller: {changed: () -> (),setEnabled: (boolean) -> ()})
    return UI.CreateIndexPage({
        indexWatch=indexWatch,areaList=areaList,gui=gui,connect=connect,
        TweenService=TweenService,petRarity=petRarity,
    },page,controller)
end

-- Read-only placed-egg statistics; never starts a hatch or changes automation.
local function createEggStatsPage(page: Frame)
    local pageConnections={}
    local function connect(signal,callback)
        local connection=signal:Connect(callback)
        table.insert(pageConnections,connection)
        return connection
    end
    local Mutations=require(RS.Shared.Modules.Mutations)
    local statsView=UI.CreateStatsWidgets({parent=player:WaitForChild("PlayerGui")},page)
    local note=statsView.note
    local espGui=statsView.espGui
    local anchor=statsView.anchor
    local highlight=statsView.highlight
    local billboard=statsView.billboard
    local billboardText=statsView.billboardText
    local edge=statsView.edge
    local arrow=statsView.arrow
    local edgeText=statsView.edgeText
    local stop=statsView.stop
    local cards={}
    local selectedUid: string?=nil
    local selectedName=""
    local Plot=require(RS.Client.PlotState)
    local Renderer=require(RS.Shared.Eggs.PlacedEggRenderer)
    local function clearSelection()
        selectedUid=nil;selectedName=""
        page:SetAttribute("SelectedEggUid",nil)
        highlight.Enabled=false;highlight.Adornee=nil;billboard.Enabled=false;edge.Visible=false;stop.Visible=false
        for _,ui in pairs(cards) do ui.card.BackgroundColor3=C.card end
    end
    local function updateLocator()
        if not selectedUid then return end
        local egg=State.ReadOwnedEgg(player.UserId,selectedUid)
        if not egg or not egg.Placement then clearSelection();return end
        local folder=Renderer.GetRenderFolder()
        local model=folder and folder:FindFirstChild(tostring(player.UserId).."_"..selectedUid)
        local plot=Plot.ResolvePlot()
        local position: Vector3?=nil
        if plot and plot.CenterPoint and typeof(egg.Placement.LocalCFrame)=="CFrame" then
            position=(plot.CenterPoint.CFrame*egg.Placement.LocalCFrame).Position
        end
        if model and model:IsA("Model") then
            position=model:GetPivot().Position
            highlight.Adornee=model;highlight.Enabled=true
        else highlight.Adornee=nil;highlight.Enabled=false end
        stop.Visible=true
        stop.Text="ESP: "..selectedName.."  /  click to clear"
        if not position then billboard.Enabled=false;edge.Visible=false;stop.Text="ESP: waiting for your plot  /  clear";return end
        anchor.WorldPosition=position
        billboard.Enabled=true
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local distance=root and root:IsA("BasePart") and math.floor((root.Position-position).Magnitude) or nil
        local distanceText=distance and (tostring(distance).." studs") or "Your egg"
        billboardText.Text=selectedName.."\n#"..selectedUid:sub(1,8).."  /  "..distanceText
        local camera=workspace.CurrentCamera
        if camera then
            local projected,onScreen=camera:WorldToViewportPoint(position)
            edge.Visible=not onScreen
            if not onScreen then
                local viewport=camera.ViewportSize
                local half=viewport*.5
                local direction=Vector2.new(projected.X,projected.Y)-half
                if projected.Z<0 then direction=-direction end
                if direction.Magnitude<.01 then direction=Vector2.new(0,-1) end
                local margin=Vector2.new(math.max(1,half.X-84),math.max(1,half.Y-76))
                local factor=math.min(margin.X/math.max(.001,math.abs(direction.X)),margin.Y/math.max(.001,math.abs(direction.Y)))
                local point=half+direction*factor
                edge.Position=UDim2.fromOffset(point.X,point.Y)
                arrow.Rotation=math.deg(math.atan2(direction.Y,direction.X))
                edgeText.Text=selectedName.." / "..distanceText
            end
        else edge.Visible=false end
    end
    local function selectEgg(uid: string,pet: string)
        if selectedUid==uid then clearSelection();return end
        selectedUid=uid;selectedName=pet
        page:SetAttribute("SelectedEggUid",uid)
        for id,ui in pairs(cards) do ui.card.BackgroundColor3=id==uid and C.selected or C.card end
        updateLocator()
    end
    connect(stop.Activated,clearSelection)
    local locatorAt=0
    connect(game:GetService("RunService").RenderStepped,function()
        if not selectedUid or os.clock()<locatorAt then return end
        locatorAt=os.clock()+.05
        local ok,err=pcall(updateLocator)
        if not ok then
            highlight.Enabled=false;billboard.Enabled=false;edge.Visible=false
            page:SetAttribute("LocatorError",tostring(err))
        else page:SetAttribute("LocatorError",nil) end
    end)
    connect(page.Destroying,function()
        clearSelection();espGui:Destroy();anchor:Destroy()
    end)
    connect(page.Destroying,function()
        for _,connection in ipairs(pageConnections) do connection:Disconnect() end
        table.clear(pageConnections)
    end)
    local function duration(seconds: number?)
        if seconds==nil then return "Time unavailable" end
        local t=math.max(0,math.ceil(seconds))
        local h=math.floor(t/3600)
        local m=math.floor(t%3600/60)
        return h>0 and string.format("%dh %02dm %02ds",h,m,t%60) or string.format("%dm %02ds",m,t%60)
    end
    type StatsEggRow = {uid: string,pet: string,icon: string,rate: number?,weight: number?,rarity: string,color: Color3,mutation: string,remaining: number?,ready: boolean,status: string}
    local function readRows(): {StatsEggRow}
        local rows: {StatsEggRow}={}
        local now=workspace:GetServerTimeNow()
        local environment=type(getgenv)=="function" and getgenv() or _G
        local store=environment.EggAtlasHatches
        local entries=store and store.owner==player.UserId and store.job==game.JobId and store.entries or {}
        for uid,egg in pairs(State.ReadOwnerEggs(player.UserId)) do
            if egg.Placement then
                local config=Assets.Directory[egg.AssetCategory]
                local rate=config and fieldEggIncome(egg) or nil
                local timerOK,remaining,ready=pcall(function()
                    local speed=egg.GrowthSpeedMultiplier
                    local credit=Records.CurrentNightCredit(egg,now,speed)
                    -- Use the game's night credit and player growth boosts as IsReadyToHatch does.
                    local seconds=Records.GrowthSecondsRemaining(egg,now,speed,credit,player)/speed
                    assert(type(seconds)=="number" and seconds==seconds and seconds<math.huge)
                    return math.max(0,seconds),Records.IsGrown(egg,now,speed,credit,player)
                end)
                local weightOK,weight=pcall(Records.WeightKgForScale,egg.AssetCategory,egg.AssetScale)
                local rarity,color=petRarity(egg.AssetCategory)
                local receipt=entries[uid]
                local hatching=receipt and receipt.started and receipt.running
                local mutations=table.clone(egg.Mutations or {})
                if type(egg.BaseMutation)=="string" and not table.find(mutations,egg.BaseMutation) then table.insert(mutations,1,egg.BaseMutation) end
                local labels={}
                for _,id in ipairs(mutations) do
                    if id~="None" then table.insert(labels,Mutations.LabelOf(id)) end
                end
                local row: StatsEggRow={uid=tostring(uid),pet=egg.AssetCategory,icon="",rate=rate,
                    weight=nil,rarity=rarity,color=color,mutation="None (Normal)",remaining=nil,ready=false,status="GROWING"}
                if config then
                    row.pet=config.DisplayName or egg.AssetCategory
                    if type(config.Icon)=="string" then row.icon=config.Icon end
                end
                if weightOK then row.weight=weight end
                if #labels>0 then row.mutation=table.concat(labels," + ") end
                if timerOK then
                    row.remaining=remaining;row.ready=ready==true
                    if row.ready then row.status="READY TO HATCH" end
                end
                if hatching then row.status="HATCHING" end
                table.insert(rows,row)
            end
        end
        table.sort(rows,function(a,b)
            if a.rate~=b.rate then return (a.rate or -math.huge)>(b.rate or -math.huge) end
            return a.uid<b.uid
        end)
        return rows
    end
    local function refresh()
        UI.RenderStats({view=statsView,page=page,cards=cards,selectedUid=selectedUid,selectEgg=selectEgg,compact=compact,duration=duration},readRows())
    end
    local dirty=true
    local nextRefresh=0
    local function invalidate()dirty=true end
    connect(State.OwnerRefreshed,function(owner)if owner==player.UserId then invalidate()end end)
    connect(State.OwnerCleared,function(owner)if owner==player.UserId then invalidate()end end)
    connect(State.SnapshotRefreshed,invalidate)
    local function update()
        if not alive or not page.Parent or not panel.Visible or not page.Visible then return end
        local now=os.clock()
        if now<nextRefresh then return end
        if not dirty and now<(page:GetAttribute("NextTimerRefresh") or 0) then return end
        nextRefresh=now+.1
        dirty=false
        page:SetAttribute("NextTimerRefresh",now+1)
        local ok,err=pcall(refresh)
        if not ok then
            note.Text="Stats unavailable; retrying..."
            page:SetAttribute("StatsError",tostring(err))
        else page:SetAttribute("StatsError",nil) end
    end
    connect(page:GetPropertyChangedSignal("Visible"),function()dirty=true;nextRefresh=0;update()end)
    connect(game:GetService("RunService").Heartbeat,update)
    return {refresh=refresh,readRows=readRows,selectEgg=selectEgg,clearSelection=clearSelection,updateLocator=updateLocator}
end


-- A renderer activation yields through the full animation and normal FinishHatch.
-- Keep that game-owned sequence alive independently of movement/UI lifetimes.
type HatchReceipt = {category: string,before: {[string]: boolean},at: number,running: boolean,started: boolean,returnedAt: number?,reason: string?}
type HatchQueue = {refresh: () -> (),contains: (string) -> boolean,pending: (string) -> boolean,start: ({uid: string,egg: any}) -> boolean}
local function createHatchQueue(state: any,readSave: () -> any,activate: (string) -> (any,any),owner: number,entries: {[string]: HatchReceipt},notify: () -> ()): HatchQueue
    local api={}
    function api.refresh()
        if next(entries)==nil then return end
        local inventory=readSave().Inventory or {}
        local eggs=state.ReadOwnerEggs(owner)
        local changed=false
        for uid,receipt in pairs(entries) do
            if receipt.running then continue end
            local confirmed=nil
            for id,item in pairs(inventory) do
                if not receipt.before[id] and item.Category==receipt.category then confirmed=id;break end
            end
            local elapsed=os.clock()-(receipt.returnedAt or receipt.at)
            if confirmed or (not eggs[uid] and elapsed>=45) or (eggs[uid] and elapsed>=(receipt.started and 15 or 3)) then
                entries[uid]=nil;changed=true
                if confirmed then print("RIFT_HATCH_CONFIRMED",receipt.category,confirmed)
                else warn("RIFT_HATCH_RECHECK",uid,receipt.reason or "Inventory has not confirmed; rechecking current game state") end
            end
        end
        if changed then notify() end
    end
    function api.contains(uid)return entries[uid]~=nil end
    function api.pending(category)
        for _,receipt in pairs(entries) do if receipt.category==category then return true end end
        return false
    end
    function api.start(entry)
        if entries[entry.uid] then return false end
        local egg=state.ReadOwnerEggs(owner)[entry.uid]
        if not egg or not egg.Placement or not state.IsReadyToHatch(entry.uid) then return false end
        local before={}
        for uid in pairs(readSave().Inventory or {}) do before[uid]=true end
        local receipt={category=egg.AssetCategory,before=before,at=os.clock(),running=true,started=false}
        entries[entry.uid]=receipt
        notify()
        task.spawn(function()
            -- Check once more inside the task: never enter the paid skip-growth path.
            local ok,result,reason=pcall(function()
                if not state.IsReadyToHatch(entry.uid) then return false,"Egg is no longer ready" end
                return activate(entry.uid)
            end)
            receipt.returnedAt=os.clock()
            receipt.running=false
            receipt.reason=not ok and tostring(result) or (result~=true and tostring(reason) or nil)
            if receipt.reason then warn("RIFT_HATCH_RESPONSE",entry.uid,receipt.reason) end
            notify()
        end)
        return true
    end
    return api
end

type OverviewAPI = {record: (string,string) -> ()}
local function createOverviewPage(page: Frame): OverviewAPI
    return UI.CreateOverviewPage({
        configStore=configStore,gui=gui,panel=panel,connect=connect,
        isAlive=function() return alive end,
    },page)
end

-- Continuous Rift recipes, with a server/inventory barrier after each trade.
local function initializeRift()
    local Save=require(RS.Shared.Save)
    local Remotes=require(RS.Shared.Remotes)
    local Rift=require(RS.Data.Rift)
    local Recipes=require(RS.Shared.Modules.RiftRecipes)
    local Kernel=require(RS.Shared.Util.FuseKernel)
    local Items=require(RS.Shared.Util.AssetItems)
    local Plot=require(RS.Client.PlotState)
    local Renderer=require(RS.Shared.Eggs.PlacedEggRenderer)
    local Sequence=require(player.PlayerScripts.GUI.RiftTradeIn.RiftSequence)
    -- Game presentation modules perform lazy requires in normal LocalScript context.
    local function gameCall(fn,...)
        local previous=getthreadidentity()
        setthreadidentity(2)
        local result=table.pack(pcall(fn,...))
        setthreadidentity(previous)
        if not result[1] then error(result[2],0) end
        return table.unpack(result,2,result.n)
    end
    local purple=Color3.fromRGB(185,151,255)
    local featurePages=UI.CreatePages({
        gui=gui,panel=panel,header=header,close=close,watchPanel=watchPanel,
        featureNav=featureNav,connect=connect,savedTab=configStore.data.tab,
    })
    local page,overviewPage,eventPage=featurePages.page,featurePages.overviewPage,featurePages.eventPage
    local statsPage,indexPage=featurePages.statsPage,featurePages.indexPage
    sessionOverview=createOverviewPage(overviewPage)
    UI.CreatePriorityControls({order=priorities.order,connect=connect,shift=function(index,direction)
        if not priorities.move(index,direction)then return end
        eggRevision+=1
        gui:SetAttribute("PriorityOrder",game:GetService("HttpService"):JSONEncode(priorities.order))
        configStore.request();configStore.flush()
        recordEvent("setting","Priority: "..table.concat(priorities.order," > "))
    end},overviewPage:FindFirstChild("OverviewPriority"))
    createEggStatsPage(statsPage)
    local riftView=UI.CreateRiftWidgets(page,Rift.Banners)
    local banner=riftView.banner
    local timer=riftView.timer
    local odds=riftView.odds
    local rows=riftView.rows
    local status=riftView.status
    local detail=riftView.detail
    local sw=riftView.sw
    local dot=riftView.dot
    local cycleLabel=riftView.cycleLabel
    local api={
        active=false,
        phase="Ready",
        rounds=0,
        message="",
        committing=false,
        retryAt=0,
        failures=0,
        tradeRecovery=configStore.data.pendingRiftTrade,
        eventPaused=false,
        commitToken=nil :: number?,
    }
    riftController=api
    local wantedBanner=type(configStore.data.riftBanner)=="string" and configStore.data.riftBanner or "Any"
    if wantedBanner~="Any" and not Rift.GetBanner(wantedBanner) then wantedBanner="Any" end
    local function acceptsBanner(s)
        return s~=nil and (wantedBanner=="Any" or s.BannerId==wantedBanner)
    end
    local function paintBannerChoice()
        gui:SetAttribute("RiftWantedBanner",wantedBanner)
        for id,choice in pairs(riftView.bannerButtons) do
            choice.BackgroundColor3=id==wantedBanner and C.selected or C.card
            choice.TextColor3=id==wantedBanner and C.mint or C.muted
            choice:SetAttribute("Selected",id==wantedBanner)
        end
    end
    paintBannerChoice()
    for id,choice in pairs(riftView.bannerButtons) do
        connect(choice.Activated,function()
            wantedBanner=id;eggRevision+=1;paintBannerChoice()
            configStore.request();configStore.flush()
        end)
    end
    local generation=0
    local schedulerRunning=false
    local ensureWorkflow
    local heartbeat=game:GetService("RunService").Heartbeat
    local liveState: any=nil
    local lastFetch,fetching=0,false
    local recipeDirty=true
    local updateUI
    local hatchEnvironment=type(getgenv)=="function" and getgenv() or _G
    local hatchStore=hatchEnvironment.EggAtlasHatches
    if not hatchStore or hatchStore.job~=game.JobId or hatchStore.owner~=player.UserId then
        hatchStore={job=game.JobId,owner=player.UserId,entries={}}
        hatchEnvironment.EggAtlasHatches=hatchStore
    end
    local hatchQueue=createHatchQueue(State,Save.Get,function(uid)
        return gameCall(Renderer.ActivateLocalEgg,uid)
    end,player.UserId,hatchStore.entries,function()
        if not alive then return end
        eggRevision+=1
        if requestRiftRefresh then requestRiftRefresh() end
    end)
    connect(Renderer.LocalEggHatchStarted,function(uid)
        local receipt=hatchStore.entries[uid]
        if receipt then receipt.started=true end
    end)
    local indexAreas={}
    for _,area in ipairs(areaList) do table.insert(indexAreas,{id=area.id,name=area.name,config=area.config})end
    local indexPlanner=createIndexCollection({
        save=Save.Get,owned=function()return State.ReadOwnerEggs(player.UserId)end,
        field=function()return State.ReadFieldEggs().Records end,areas=indexAreas,assets=Assets.Directory,
        ready=State.IsReadyToHatch,pending=hatchQueue.pending,collectible=isCollectible,retry=fieldRetryReady,rate=fieldEggIncome,
        distance=function(egg)
            local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local target=egg.BottomCFrame or egg.BoundsCFrame
            if not root or not root:IsA("BasePart") or typeof(target)~="CFrame" then return math.huge end
            local offset=target.Position-root.Position
            return Vector3.new(offset.X,0,offset.Z).Magnitude
        end,
    })
    local indexData: IndexPlan?=nil
    local indexCompletionSeen=false
    local indexRevision,indexNext=-1,0
    local paintIndex
    local function indexScan(force: boolean): IndexPlan
        if force or indexRevision~=eggRevision or os.clock()>=indexNext then
            indexData=indexPlanner.scan(indexWatch.areas,FieldCycle.read().blocked,indexWatch.options)
            indexRevision=eggRevision;indexNext=os.clock()+.25
        end
        return assert(indexData)
    end
    local function indexJob(): IndexJob?
        if not indexWatch.enabled or (priorities.before("Area","Index") and reserveAreaReset()) then return nil end
        return indexScan(false).job
    end
    local function indexMessage(message)
        indexWatch.message=message
        gui:SetAttribute("IndexMessage",message)
        if paintIndex then paintIndex(indexData) end
    end
    local function indexChanged()
        indexCompletionSeen=false
        indexRevision=-1;eggRevision+=1
        configStore.request()
        gui:SetAttribute("IndexAreas",game:GetService("HttpService"):JSONEncode(indexWatch.areas))
        gui:SetAttribute("IndexTargets",game:GetService("HttpService"):JSONEncode(indexWatch.options.targets))
        gui:SetAttribute("IndexStrategy",indexWatch.options.strategy)
        gui:SetAttribute("IndexCompletion",indexWatch.options.completion)
        local ok,data=pcall(indexScan,true)
        if ok and paintIndex then paintIndex(data) end
        if ensureWorkflow then ensureWorkflow() end
    end
    function api.setIndexEnabled(on)
        indexWatch.enabled=on==true
        if not restoringConfig then rememberToggle("autoIndex",indexWatch.enabled) end
        gui:SetAttribute("IndexEnabled",indexWatch.enabled)
        indexMessage(indexWatch.enabled and "CHECKING / missing species" or (indexWatch.busy and "FINISHING / returning the current egg" or "OFF"))
        indexChanged()
    end
    function api.finishIndexIfComplete(): boolean
        if not indexWatch.enabled or indexWatch.busy then return false end
        local data=indexScan(false)
        if data.total<=0 or data.missing>0 then return false end
        if not indexCompletionSeen then
            indexCompletionSeen=true
            recordEvent("collection","Auto Index / all selected targets discovered")
        end
        if indexWatch.options.completion~="stop" then return false end
        api.setIndexEnabled(false)
        indexMessage("COMPLETE / selected targets discovered; Index switched off")
        return true
    end
    paintIndex=createIndexPage(indexPage,{changed=indexChanged,setEnabled=api.setIndexEnabled})
    connect(Save.FieldSignal("Index"),function()indexRevision=-1;eggRevision+=1 end)
    indexChanged()

    local Registry=require(RS.Client.Modules.RuntimeInstanceRegistry)
    local Treadmills=require(RS.Data.Treadmills)
    local training: {
        owner: number?,
        belt: string?,
        leaving: boolean,
        entering: boolean,
    } = {owner=nil,belt=nil,leaving=false,entering=false}
    local initialSaveOK,initialSave=pcall(Save.Get)
    local initialBelt=initialSaveOK and type(initialSave)=="table" and type(initialSave.TreadmillUpgradeLevel)=="number"
        and Treadmills.GetByUpgradeLevel(initialSave.TreadmillUpgradeLevel)
    if initialBelt and Registry.Peek("Treadmill",initialBelt._id) then training.belt=initialBelt._id end
    connect(Remotes.Treadmill.AssignedBeltShifted.OnClientEvent,function(id)
        training.belt=id
        if alive then
            gui:SetAttribute("RiftTraining",training.owner~=nil and id~=nil)
        end
    end)
    gui:SetAttribute("RiftTrainWhileWaiting",true)
    gui:SetAttribute("RiftTraining",false)
    local function stopTraining(token)
        if training.owner==nil or (token and training.owner~=token) then return end
        if training.leaving then
            local deadline=os.clock()+7
            repeat heartbeat:Wait() until not training.leaving or os.clock()>deadline
            assert(not training.leaving,"Treadmill exit is still pending")
            return
        end
        training.leaving=true
        local ok,err=pcall(function()
            -- Static entry is a server round trip and can finish just after cancellation.
            if training.entering and not training.belt then
                local deadline=os.clock()+2
                repeat heartbeat:Wait() until training.belt or os.clock()>deadline
            end
            if training.belt then
                assert(Remotes.Treadmill.AskDoff:InvokeServer()==true,"The game refused to leave the treadmill")
                local deadline=os.clock()+5
                repeat
                    local ch=player.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart")
                    if not training.belt and (not root or not root.Anchored) then break end
                    heartbeat:Wait()
                until os.clock()>deadline
                local ch=player.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart")
                assert(not training.belt and (not root or not root.Anchored),"Treadmill exit did not confirm; movement stopped")
            end
            training.owner=nil
            training.entering=false
            if alive then gui:SetAttribute("RiftTraining",false) end
        end)
        training.leaving=false
        if not ok then error(err,0) end
    end
    local function switchOn(on)
        sw:SetAttribute("On",on);gui:SetAttribute("RiftActive",on)
        TweenService:Create(sw,TweenInfo.new(.18),{BackgroundColor3=on and Color3.fromRGB(52,199,89) or Color3.fromRGB(67,76,91)}):Play()
        TweenService:Create(dot,TweenInfo.new(.18),{Position=UDim2.fromOffset(on and 31 or 3,3)}):Play()
    end
    local function say(phase,message)
        local changed=api.phase~=phase or api.message~=message
        api.phase=phase
        api.message=message
        if alive then
            local waiting=phase=="Waiting" or phase=="Training" or phase=="Loading" or phase=="Retrying"
            if not (eventController and eventController.busy) then gui:SetAttribute("WaitReason",waiting and message or nil)end
            status.Text=string.upper(phase);detail.Text=message
            gui:SetAttribute("RiftPhase",phase);gui:SetAttribute("RiftMessage",message)
        end
        if changed then print("RIFT_AUTO",phase,message) end
    end
    local function recordStop(source,reason)
        if alive then
            gui:SetAttribute("RiftLastStopSource",source)
            gui:SetAttribute("RiftLastStopReason",reason)
            gui:SetAttribute("RiftLastStopPhase",api.phase)
            gui:SetAttribute("RiftLastStopAt",workspace:GetServerTimeNow())
        end
        print("RIFT_STOP",source,api.phase,reason)
    end
    function api.stop(reason,source)
        recordStop(source or "System",reason or "Stopped")
        if (areaWatch.busy or indexWatch.busy) and source=="Toggle" then
            api.active=false;switchOn(false)
            say("Stopped","The Rift is off. The current collection trip is finishing.")
            return
        end
        generation+=1;api.active=false
        if runner.active and not (eventController and eventController.busy) then runner.stop(reason or "Rift stopped") end
        local ok,err=pcall(stopTraining)
        if not ok then reason=tostring(err) end
        if alive then switchOn(false);say("Stopped",reason or "Stopped. Your collected eggs and pets are kept.") end
    end
    local function check(token: number): ()
        if not alive or not (api.active or areaWatch.enabled or areaWatch.busy or indexWatch.enabled or indexWatch.busy or manualStarting) or token~=generation then error("CANCELLED",0) end
        assert(not player:GetAttribute("InBossArena"),"Inside the boss arena; Auto Rift stopped")
        local ch=player.Character;local h=ch and ch:FindFirstChildOfClass("Humanoid")
        assert(h and h.Health>0,"Character changed or died; waiting to resume")
    end
    local function pause(token: number,seconds: number): ()
        local untilTime=os.clock()+seconds
        repeat check(token);task.wait(.15) until os.clock()>=untilTime
    end
    local function waitForEggChange(token: number,seconds: number): ()
        local revision=eggRevision
        local deadline=os.clock()+seconds
        repeat
            check(token)
            heartbeat:Wait()
        until eggRevision~=revision or os.clock()>=deadline
        check(token)
    end
    local function riftShouldYield()
        local owner=areaWatch.busy and "Area" or (indexWatch.busy and "Index" or "Rift")
        return (owner=="Rift" and not acceptsBanner(liveState)) or higherPriorityWork(owner) or (owner~="Area" and priorities.before("Area",owner) and reserveAreaReset())
    end
    local function checkRiftPriority(token: number): ()
        check(token)
        if riftShouldYield() then error(PRIORITY_INTERRUPTED,0) end
    end
    local function pauseRift(token: number,seconds: number): ()
        local deadline=os.clock()+seconds
        repeat checkRiftPriority(token);heartbeat:Wait() until os.clock()>=deadline
        checkRiftPriority(token)
    end
    local function fetch()
        -- Serialize workflow and UI reads so an older response cannot overwrite a new recipe.
        while fetching do task.wait(.05) end
        fetching=true;recipeDirty=false
        local ok,result=pcall(function()return Remotes.Rift.AskState:InvokeServer()end)
        fetching=false
        if not ok then recipeDirty=true;error(result,0) end
        assert(type(result)=="table" and type(result.Requirements)=="table","Rift state unavailable")
        liveState=result;lastFetch=os.clock()
        if alive then
            gui:SetAttribute("RiftRecipe",tostring(result.BannerId).."|"..table.concat(result.Requirements,"|"))
            if updateUI then updateUI() end
        end
        return result
    end
    local function signature(s)
        return tostring(s.BannerId).."|"..table.concat(s.Requirements,"|")
    end
    -- Pure inventory selection: distinct UIDs, game eligibility, lowest income first.
    local function selectInputs(requirements: {string},save: any): ({[number]: {uid: string,item: any,rate: number}}, {number})
        local equipped,used,chosen,counts={},{},{},{}
        for _,uid in pairs(save.EquippedAssets or {}) do equipped[uid]=true end
        for index,category in ipairs(requirements) do
            local candidates={}
            for uid,item in pairs(save.Inventory or {}) do
                if item.Category==category and not equipped[uid] and not used[uid] then
                    local ok,allowed=pcall(Kernel.MayEnterRift,uid,item)
                    if ok and allowed then
                        local rateOK,rate=pcall(Earnings.MutationOnlyRatePerSecond,item)
                        table.insert(candidates,{uid=uid,item=item,rate=rateOK and rate or math.huge})
                    end
                end
            end
            table.sort(candidates,function(a,b)
                if a.rate~=b.rate then return a.rate<b.rate end
                if (a.item.Scale or 1)~=(b.item.Scale or 1) then return (a.item.Scale or 1)<(b.item.Scale or 1) end
                return a.uid<b.uid
            end)
            counts[index]=#candidates
            if candidates[1] then chosen[index]=candidates[1];used[candidates[1].uid]=true end
        end
        return chosen,counts
    end
    local function ownedFor(category: string): {{uid: string,egg: any}}
        local eggs={}
        for uid,egg in pairs(State.ReadOwnerEggs(player.UserId)) do
            if egg.AssetCategory==category and not hatchQueue.contains(uid) then table.insert(eggs,{uid=uid,egg=egg}) end
        end
        table.sort(eggs,function(a,b)
            local ar,br=State.IsReadyToHatch(a.uid),State.IsReadyToHatch(b.uid)
            if ar~=br then return ar end
            if (a.egg.Placement~=nil)~=(b.egg.Placement~=nil) then return a.egg.Placement~=nil end
            if a.egg.AssetScale~=b.egg.AssetScale then return a.egg.AssetScale<b.egg.AssetScale end
            return a.uid<b.uid
        end)
        return eggs
    end
    local function fieldsFor(category: string): {any}
        if FieldCycle.read().blocked then return {} end
        local eggs={};local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        for _,egg in pairs(State.ReadFieldEggs().Records) do
            if egg.AssetCategory==category and isCollectible(egg) and fieldRetryReady(egg) then table.insert(eggs,egg) end
        end
        table.sort(eggs,function(a,b)
            local aa,bb=areaById[a.AreaId],areaById[b.AreaId]
            if (aa and aa.rank or 99)~=(bb and bb.rank or 99) then return (aa and aa.rank or 99)<(bb and bb.rank or 99) end
            if root then return (a.BottomCFrame.Position-root.Position).Magnitude<(b.BottomCFrame.Position-root.Position).Magnitude end
            return a.Uid<b.Uid
        end)
        return eggs
    end
    local riftReadyAt,riftReadyRevision,riftReadyValue=0,-1,false
    local function riftWorkReady(): boolean
        if not api.active then return false end
        if api.committing or api.tradeRecovery then return true end
        local s=liveState
        if not s or not s.Unlocked or #s.Requirements~=3 then return false end
        if s.PendingReward then return true end
        if not acceptsBanner(s) then return false end
        if riftReadyRevision==eggRevision and os.clock()<riftReadyAt then return riftReadyValue end
        riftReadyAt=os.clock()+.15;riftReadyRevision=eggRevision;riftReadyValue=false
        local inputs=selectInputs(s.Requirements,Save.Get())
        if inputs[1] and inputs[2] and inputs[3] then riftReadyValue=true;return true end
        for i,category in ipairs(s.Requirements)do
            if not inputs[i] and not hatchQueue.pending(category) then
                local eggs=ownedFor(category)
                if eggs[1] then
                    if not eggs[1].egg.Placement or State.IsReadyToHatch(eggs[1].uid) then riftReadyValue=true;return true end
                elseif fieldsFor(category)[1] then riftReadyValue=true;return true end
            end
        end
        return false
    end
    featureReady=function(name: string): boolean
        local ok,ready=pcall(function()
            -- Finish leaving the underground room before scheduling any surface trip.
            if eventController and eventController.needsExit() then return name=="Event" end
            if name=="Event" then return eventController~=nil and eventController.hasOpportunity() end
            if name=="Area" then return priorityEgg()~=nil end
            if name=="Index" then return indexJob()~=nil end
            if name=="Rift" then return riftWorkReady() end
            return false
        end)
        return ok and ready==true
    end
    local function chooseNextFeature(): string?
        local name=priorities.choose(assert(featureReady),nil)
        local action="Train while waiting for available work"
        if name=="Area" then
            local egg=priorityEgg();action=egg and ("Auto Area / "..egg.AssetCategory) or "Auto Area"
        elseif name=="Index" then
            local job=indexJob();action=job and ("Auto Index / "..job.kind.." / "..job.category) or "Auto Index"
        elseif name=="Event" then action="DR Scramble / collect Samples from personal drones"
        elseif name=="Rift" then action="The Rift / continue the current recipe" end
        gui:SetAttribute("NextAction",action)
        return name
    end
    local function reserveForRift(): boolean
        return api.active and priorities.before("Area","Rift") and reserveAreaReset()
    end
    connect(Save.FieldSignal("Inventory"),function()riftReadyAt=0;eggRevision+=1 end)
    updateUI=function()
        if not alive then return end
        local cycle=FieldCycle.read()
        gui:SetAttribute("RiftFieldCycle",cycle.blocked and "Night / resetting" or "Day")
        gui:SetAttribute("RiftResetRemaining",math.ceil(cycle.remaining))
        cycleLabel.Text="CONTINUOUS  /  "..api.rounds.." event eggs confirmed  /  "..(cycle.blocked and "NIGHT / FIELD RESET - training wait" or "DAY - field open")
        gui:SetAttribute("RiftCompletedCycles",api.rounds)
        if not page.Visible or not panel.Visible then return end
        local s=liveState;if not s then return end
        local inputs,counts=selectInputs(s.Requirements,Save.Get())
        banner.Text=(s.BannerDisplayName or s.BannerId).."  /  "..(s.PityCount or 0).." / "..(s.PityThreshold or 50).." pity"
        local remaining=math.max(0,math.floor((s.SecondsUntilRotation or 0)-(os.clock()-lastFetch)))
        timer.Text=string.format("ROTATES IN  %02d:%02d:%02d",remaining//3600,(remaining%3600)//60,remaining%60)
        local chances,total={},0
        for _,v in ipairs(s.PetOdds or {}) do total+=v.Weight end
        for _,v in ipairs(s.PetOdds or {}) do table.insert(chances,v.AssetId.." "..compact(total>0 and v.Weight/total*100 or 0).."%") end
        odds.Text=table.concat(chances,"  /  ")
        local ready=0
        for i,row in ipairs(rows) do
            local id=s.Requirements[i];local cfg=id and Assets.Directory[id]
            local eggs=id and ownedFor(id) or {};local field=id and fieldsFor(id) or {}
            local _,area=Recipes.SpawnChanceOf(id or "")
            row.name.Text=cfg and cfg.DisplayName or id or "--";row.icon.Image=cfg and cfg.Icon or ""
            local rarity,rarityColor=petRarity(id)
            row.rarity.Text="Rarity: "..rarity
            row.rarity.TextColor3=rarityColor
            row.card:SetAttribute("PetRarity",rarity)
            row.detail.Text=(area or "Unknown area").."  /  "..#eggs.." owned eggs  /  "..#field.." field eggs"
            local requirementStatus: string="NEEDS COLLECTING"
            if inputs[i] then requirementStatus="READY  x"..counts[i]
            elseif id and hatchQueue.pending(id) then requirementStatus="HATCHING"
            elseif #eggs>0 then requirementStatus="NEEDS HATCHING" end
            row.status.Text=requirementStatus
            row.status.TextColor3=inputs[i] and C.mint or purple
            row.card:SetAttribute("Pet",id);row.card:SetAttribute("ReadyCount",counts[i] or 0)
            row.card:SetAttribute("FieldCount",#field);row.card:SetAttribute("OwnedEggCount",#eggs)
            if inputs[i] then ready+=1 end
        end
        gui:SetAttribute("RiftReadyCount",ready);gui:SetAttribute("RiftBanner",s.BannerId)
    end
    requestRiftRefresh=refreshScheduler(function()
        local ok,err=pcall(updateUI)
        if not ok then warn("RIFT_UI",err) end
    end,.1)
    connect(page:GetPropertyChangedSignal("Visible"),requestRiftRefresh)
    connect(panel:GetPropertyChangedSignal("Visible"),requestRiftRefresh)
    local function rootPart()
        return assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"),"Character unavailable")
    end
    type TreadmillBox={x0: number,x1: number,z0: number,z1: number}
    local treadmillCache={at=0,model=nil :: Instance?,bottom=nil :: BasePart?,cf=nil :: CFrame?,size=nil :: Vector3?,zones={} :: {TreadmillBox}}
    local function treadmillZones(force: boolean?): {TreadmillBox}
        local plot=Plot.ResolvePlot()
        if not plot then return {} end
        local bottom=plot.PlotFolder:FindFirstChild("TreadmillBottom")
        local model=Registry.Peek("TreadmillPlotRender",tostring(plot.Slot))
        if not bottom or not bottom:IsA("BasePart") or not model then
            treadmillCache.at=0
            return {}
        end
        local now=os.clock()
        if not force and now<treadmillCache.at and treadmillCache.model==model and treadmillCache.bottom==bottom
            and treadmillCache.cf==bottom.CFrame and treadmillCache.size==bottom.Size then return treadmillCache.zones end
        local box={x0=math.huge,x1=-math.huge,z0=math.huge,z1=-math.huge}
        local function include(cf,size)
            for _,x in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
                local p=cf:PointToWorldSpace(Vector3.new(size.X*x*.5,0,size.Z*z*.5))
                box.x0=math.min(box.x0,p.X);box.x1=math.max(box.x1,p.X)
                box.z0=math.min(box.z0,p.Z);box.z1=math.max(box.z1,p.Z)
            end end
        end
        include(bottom.CFrame,bottom.Size)
        include(model:GetBoundingBox())
        treadmillCache={at=now+.1,model=model,bottom=bottom,cf=bottom.CFrame,size=bottom.Size,zones={box}}
        return treadmillCache.zones
    end
    local function treadmillExitPoint(position,zones)
        local b=zones[1]
        if not b or position.X<b.x0-6 or position.X>b.x1+6 or position.Z<b.z0-6 or position.Z>b.z1+6 then return nil end
        local exits={Vector3.new(b.x0-12,position.Y,position.Z),Vector3.new(b.x1+12,position.Y,position.Z),
            Vector3.new(position.X,position.Y,b.z0-12),Vector3.new(position.X,position.Y,b.z1+12)}
        table.sort(exits,function(a,c)return (a-position).Magnitude<(c-position).Magnitude end)
        return exits[1]
    end
    local function prepareDeparture(token)
        check(token)
        if training.belt then training.owner=token end
        stopTraining(token);check(token)
        return treadmillExitPoint(rootPart().Position,treadmillZones(true))
    end
    local function walk(token: number,destination: Vector3,label: string): ()
        -- Plot/hatch/trade trips avoid re-entering the treadmill after dismounting.
        for _=1,3 do
            checkRiftPriority(token)
            local exitPoint=prepareDeparture(token)
            checkRiftPriority(token)
            local function interrupt()
                check(token)
                if training.belt then training.owner=token;return "treadmill entered" end
                if riftShouldYield() then return "area priority" end
                return nil
            end
            say("Travelling",label)
            local outcome=runner.travel(destination,label,interrupt,treadmillZones,exitPoint)
            check(token)
            if outcome=="area priority" then error(PRIORITY_INTERRUPTED,0) end
            if outcome~="treadmill entered" then return end
            say("Recovering","Accidentally entered the treadmill. Leaving it and continuing the same task.")
        end
        error("Treadmill repeatedly recaptured the character; stopped after 3 recovery attempts",0)
    end
    -- Check local egg/inventory changes while training; refresh the server recipe separately.
    local function waitingWorkReady(s)
        hatchQueue.refresh()
        if api.finishIndexIfComplete() then return true end
        if priorityEgg() or indexJob() then return true end
        if eventController and eventController.hasOpportunity() then return true end
        if not api.active or not s or not acceptsBanner(s) then return false end
        local inputs=selectInputs(s.Requirements,Save.Get())
        if inputs[1] and inputs[2] and inputs[3] then return true end
        for i,category in ipairs(s.Requirements) do
            if not inputs[i] and not hatchQueue.pending(category) then
                local eggs=ownedFor(category)
                if eggs[1] then
                    if not eggs[1].egg.Placement or State.IsReadyToHatch(eggs[1].uid) then return true end
                elseif fieldsFor(category)[1] then return true end
            end
        end
        return false
    end
    local function trainWhileWaiting(token,s,waiting)
        check(token)
        if waitingWorkReady(s) then return end
        local riftWasActive=api.active
        local startingBanner=wantedBanner
        local reservedReset=reserveForRift()
        local function workChanged()
            return api.active~=riftWasActive or wantedBanner~=startingBanner or waitingWorkReady(s)
                or reserveForRift()~=reservedReset
                or (s and liveState and signature(liveState)~=signature(s))
        end
        local plot=Plot.ResolvePlot()
        local bottom=plot and plot.PlotFolder:FindFirstChild("TreadmillBottom")
        local model=plot and Registry.Peek("TreadmillPlotRender",tostring(plot.Slot))
        if not bottom or not bottom:IsA("BasePart") or not model then
            say("Waiting","Treadmill unavailable; "..table.concat(waiting," / "))
            pause(token,1);return
        end
        training.owner=token
        local trainingCharacter=player.Character
        if not training.belt then
            training.entering=true
            say("To treadmill","Going to your treadmill while "..table.concat(waiting," / "))
            local pollAt=0;local ready=false;local seenRevision=-1
            local function interrupt()
                check(token)
                if training.belt then return "training" end
                if api.active~=riftWasActive or wantedBanner~=startingBanner or reserveForRift()~=reservedReset
                    or (s and liveState and signature(liveState)~=signature(s)) then return "work ready" end
                if seenRevision~=eggRevision or os.clock()>=pollAt then
                    seenRevision=eggRevision
                    pollAt=os.clock()+.25;ready=waitingWorkReady(s)
                end
                if ready then return "work ready" end
                return nil
            end
            local outcome=runner.travel(bottom.Position+Vector3.new(0,3,0),"Going to your plot treadmill",interrupt)
            check(token)
            if outcome=="work ready" then
                if not training.belt and not treadmillExitPoint(rootPart().Position,treadmillZones()) then training.entering=false end
                stopTraining(token);return
            end
            -- Standing on the belt starts the game's own static treadmill controller.
            local deadline=os.clock()+5
            while not training.belt do
                check(token)
                if workChanged() then stopTraining(token);return end
                if os.clock()>=deadline then
                    training.entering=false
                    say("Waiting","Treadmill entry did not confirm; retrying while watching for eggs.")
                    waitForEggChange(token,.5);return
                end
                waitForEggChange(token,.2)
            end
        end
        check(token)
        training.entering=false
        gui:SetAttribute("RiftTraining",true)
        local function trainingStatus()
            local cycle=FieldCycle.read()
            say("Training",(cycle.blocked and "Night/reset: training until the field reopens. " or "Running on your treadmill while ")..table.concat(waiting," / "))
            if indexWatch.enabled then
                local data=indexScan(false)
                indexMessage(data.selected==0 and "SELECT AREAS / training while waiting" or (data.total==0 and "SELECT SPECIES / training while waiting" or (data.missing==0 and "COMPLETE / selected targets discovered; training" or ("TRAINING / "..data.missing.." selected targets missing / waiting for spawn or hatch"))))
            end
            if areaWatch.enabled then
                watchMessage(cycle.blocked and "TRAINING  /  night/reset; waiting for morning and matching eggs"
                    or ("TRAINING  /  waiting for matching eggs in "..areaWatch.area))
            end
        end
        trainingStatus()
        local nextRefresh=os.clock()+10
        while true do
            check(token)
            trainingStatus()
            assert(player.Character==trainingCharacter,"Character changed during training; Auto Rift stopped")
            if not training.belt then
                training.entering=false
                gui:SetAttribute("RiftTraining",false)
                say("Waiting","Treadmill ended; checking available work before returning to training.")
                waitForEggChange(token,.25);return
            end
            if workChanged() then break end
            if s and api.active and os.clock()>=nextRefresh then
                local fresh=fetch();check(token);nextRefresh=os.clock()+10
                if signature(fresh)~=signature(s) or not fresh.Unlocked or fresh.PendingReward then break end
            end
            waitForEggChange(token,.25)
        end
        if reserveForRift() and not priorityEgg() then return end
        stopTraining(token);check(token)
    end
    local function placementPlan(preferred: {slot: any,position: Vector3}?): ({slot: any,position: Vector3},any)
        local plot=assert(Plot.ResolvePlot(),"Your plot is not loaded")
        local area=plot.PetArea
        -- Raycast onto free plot floor, respecting existing rendered eggs.
        local targets={area};Renderer.AppendRaycastTargets(targets,player.UserId)
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=targets
        local function freeFloor(position: Vector3): Vector3?
            local hit=workspace:Raycast(position+Vector3.new(0,70,0),Vector3.new(0,-100,0),params)
            if not hit or hit.Instance~=area then return nil end
            for _,egg in pairs(State.ReadOwnerEggs(player.UserId)) do
                if egg.Placement then
                    local other=(plot.CenterPoint.CFrame*egg.Placement.LocalCFrame).Position
                    if ((other-hit.Position)*Vector3.new(1,0,1)).Magnitude<9 then return nil end
                end
            end
            return hit.Position
        end
        if preferred and preferred.slot==plot.Slot then
            local position=freeFloor(preferred.position)
            if position then return {slot=plot.Slot,position=position},plot end
        end
        local destination=nil
        for x=-.35,.35,.175 do
            for z=-.32,.32,.16 do
                local p=area.CFrame:PointToWorldSpace(Vector3.new(area.Size.X*x,area.Size.Y*.5,area.Size.Z*z))
                destination=freeFloor(p)
                if destination then break end
            end
            if destination then break end
        end
        assert(destination,"No free egg placement space found on your plot")
        return {slot=plot.Slot,position=destination},plot
    end
    local function plant(token: number,uid: string,preferred: {slot: any,position: Vector3}?): ()
        for _=1,3 do
            checkRiftPriority(token)
            local egg=State.ReadOwnerEggs(player.UserId)[uid]
            assert(egg,"The collected egg is not in your inventory")
            if egg.Placement then return end
            local placement=placementPlan(preferred)
            local goal=placement.position+Vector3.new(0,3,0)
            if ((rootPart().Position-goal)*Vector3.new(1,0,1)).Magnitude>3 then
                walk(token,goal,"Moving directly to the hatching space")
            end
            checkRiftPriority(token)
            -- The player may have placed another egg while we were returning.
            local current,currentPlot=placementPlan(placement)
            if current.slot~=placement.slot or (current.position-placement.position).Magnitude>1 then
                preferred=current
                continue
            end
            egg=State.ReadOwnerEggs(player.UserId)[uid]
            assert(egg,"The collected egg is no longer in your inventory")
            if egg.Placement then return end
            say("Planting","Placing the collected egg in its hatching space")
            checkRiftPriority(token)
            local ok,reason=State.WearEggTool(uid);assert(ok,reason or "Cannot equip required egg")
            check(token)
            if riftShouldYield() then
                ok,reason=State.DoffEggTool(uid);assert(ok,reason or "Cannot put the Rift egg back in inventory")
                check(token)
                error(PRIORITY_INTERRUPTED,0)
            end
            ok,reason=State.PlantEgg(uid,currentPlot.CenterPoint.CFrame:ToObjectSpace(CFrame.new(current.position)))
            assert(ok,reason or "Egg placement refused")
            gameCall(Renderer.Refresh);pauseRift(token,1)
            return
        end
        error("Hatching space kept changing; stopped before placing the egg",0)
    end
    local function hatch(token,entry)
        checkRiftPriority(token)
        if hatchQueue.contains(entry.uid) then return false end
        if not State.IsReadyToHatch(entry.uid) then return false end
        local plot=assert(Plot.ResolvePlot(),"Your plot is not loaded")
        local p=(plot.CenterPoint.CFrame*entry.egg.Placement.LocalCFrame).Position
        walk(token,p+Vector3.new(5,3,0),"Returning to hatch "..entry.egg.AssetCategory)
        checkRiftPriority(token)
        if not State.IsReadyToHatch(entry.uid) then return false end
        say("Hatching","Starting "..entry.egg.AssetCategory.."; continuing other work while it hatches")
        checkRiftPriority(token)
        return hatchQueue.start(entry)
    end
    local function tradeSettled(receipt,fresh,save)
        if not receipt.claimConfirmed or fresh.PendingReward then return false end
        local count=(save.Rift.TradeInsByBanner or {})[receipt.banner] or 0
        if count<=receipt.beforeCount then return false end
        for _,uid in ipairs(receipt.ids) do if save.Inventory[uid] then return false end end
        return true
    end
    local function trade(token,s)
        checkRiftPriority(token)
        local machine=workspace:WaitForChild("__OBJECTS"):WaitForChild("Machines"):WaitForChild("RiftMachine")
        local prompt=machine:FindFirstChildWhichIsA("ProximityPrompt",true)
        assert(prompt and prompt.Parent:IsA("Attachment"),"Rift interaction point unavailable")
        local point=prompt.Parent.WorldPosition
        local root=rootPart();local delta=(root.Position-point)*Vector3.new(1,0,1)
        local goal=point+(delta.Magnitude>.01 and delta.Unit or Vector3.xAxis)*5
        walk(token,Vector3.new(goal.X,root.Position.Y,goal.Z),"Bringing the three pets to The Rift")
        check(token)
        local fresh=fetch();check(token)
        if signature(fresh)~=signature(s) or not acceptsBanner(fresh) then return false end
        if wantedBanner~="Any" and (fresh.SecondsUntilRotation or 0)<=2 then pauseRift(token,.5);return false end
        assert(fresh.Unlocked==true,"The Rift is locked")
        assert(not fresh.PendingReward,"Claim the existing Rift reward before starting a new trade")
        local selected=selectInputs(fresh.Requirements,Save.Get())
        local ids,decoded={},{}
        for i=1,3 do
            if not selected[i] then return false end
            ids[i]=selected[i].uid;decoded[i]=Items.Decode(selected[i].item)
        end
        assert((rootPart().Position-point).Magnitude<=math.max(prompt.MaxActivationDistance,10),"Not close enough to The Rift")
        local before=State.ReadOwnerEggs(player.UserId)
        local beforeCount=(Save.Get().Rift.TradeInsByBanner or {})[fresh.BannerId] or 0
        check(token)
        checkRiftPriority(token)
        say("Trading","Offering three pets for one "..(fresh.BannerDisplayName or fresh.BannerId).." egg")
        -- Send exactly once. An uncertain response stops; it must never repeat a sacrifice.
        api.tradeRecovery={banner=fresh.BannerId,beforeCount=beforeCount,ids=ids}
        configStore.request();configStore.flush()
        api.committing=true
        api.commitToken=token
        gui:SetAttribute("RiftCommitting",true)
        local called,accepted,reason=pcall(function()return Remotes.Rift.AskTradeIn:InvokeServer(ids)end)
        if called and accepted~=true then api.tradeRecovery=nil;configStore.request();configStore.flush() end
        assert(called,"Trade response uncertain. Check The Rift before starting again.")
        assert(accepted==true,reason or "The Rift refused this trade")
        local receipt={banner=fresh.BannerId,beforeCount=beforeCount,ids=ids,recipe=signature(fresh),claimConfirmed=false}
        -- The recipe changes at acceptance; publish it without waiting for the reveal.
        local stateOK,acceptedState=pcall(fetch)
        if stateOK and type(acceptedState.PendingReward)=="table" then receipt.rewardUid=acceptedState.PendingReward.Uid end
        local pending=Save.Get().Rift.PendingReward
        if not receipt.rewardUid and type(pending)=="table" then receipt.rewardUid=pending.Uid end
        local finished=false
        local function finishClaim()
            if finished then return end
            finished=true
            local ok,result=pcall(function()return Remotes.Rift.AskFinishReveal:InvokeServer()end)
            receipt.claimConfirmed=ok and result~=false
            recipeDirty=true
            print("RIFT_CLAIM_RESPONSE",ok,tostring(result),receipt.rewardUid)
            if not ok then warn("RIFT_CLAIM_PENDING",result) end
        end
        -- Complete a committed trade even if the user stops during the animation.
        local shown=pcall(gameCall,Sequence.Play,decoded,finishClaim)
        if not shown then finishClaim() end
        local untilTime=os.clock()+50
        local nextRead=0
        repeat
            local owned=State.ReadOwnerEggs(player.UserId)
            for uid,egg in pairs(owned) do
                if (receipt.rewardUid and uid==receipt.rewardUid)
                    or (not before[uid] and Rift.BannerContainsPet(fresh.BannerId,egg.AssetCategory)) then
                    if not finished then finishClaim() end
                    receipt.rewardUid=uid
                    receipt.claimConfirmed=true
                end
            end
            if os.clock()>=nextRead then
                local ok,current=pcall(fetch);nextRead=os.clock()+1
                if ok and tradeSettled(receipt,current,Save.Get()) then
                    -- A reward may already be hatched/moved by the player. The server's
                    -- cleared pending claim + consumed UIDs + incremented counter still confirm it.
                    print("RIFT_REWARD_CONFIRMED",receipt.rewardUid or "server claim",signature(current))
                    while Sequence.IsPlaying() do task.wait(.1) end
                    return receipt
                end
            end
            task.wait(.3)
        until os.clock()>untilTime
        if not finished then finishClaim() end
        error("Trade accepted; reward has not appeared yet. Check The Rift pending reward before restarting.",0)
    end
    local function chooseFieldEgg(field)
        local cycle=FieldCycle.read()
        if cycle.blocked then return nil,nil end
        for _,egg in ipairs(field) do
            local current=State.ReadFieldEgg(egg.Uid)
            local latestCycle=FieldCycle.read()
            if latestCycle.blocked or latestCycle.epoch~=cycle.epoch then return nil,nil end
            if current and isCollectible(current) then return current,cycle.epoch end
        end
        return nil,nil
    end
    local function nextRecipe(token,receipt)
        check(token)
        say("Refreshing","Event egg received. Waiting for the next recipe and updated inventory.")
        local deadline=os.clock()+20
        repeat
            check(token)
            local fresh=fetch();check(token)
            local save=Save.Get()
            local count=(save.Rift.TradeInsByBanner or {})[receipt.banner] or 0
            local consumed=true
            for _,uid in ipairs(receipt.ids) do if save.Inventory[uid] then consumed=false;break end end
            -- A randomly repeated recipe is valid. Never require different pet names.
            if count>receipt.beforeCount and consumed and not fresh.PendingReward
                and #fresh.Requirements==3 and signature(fresh)==save.Rift.RequirementsBannerId.."|"..table.concat(save.Rift.Requirements,"|") then
                api.tradeRecovery=nil;api.failures=0
                configStore.request();configStore.flush()
                api.committing=false
                api.commitToken=nil
                gui:SetAttribute("RiftCommitting",false)
                gui:SetAttribute("RiftLastRewardUid",receipt.rewardUid)
                print("RIFT_NEXT_RECIPE",receipt.recipe,"->",signature(fresh),"trade count",count)
                return fresh
            end
            pause(token,.5)
        until os.clock()>deadline
        error("Event egg received, but the new recipe or inventory has not synced. Stopped before another trade.",0)
    end
    local function runPriorityTrip(token)
        local target=priorityEgg()
        if not target then return false end
        areaWatch.busy=true
        gui:SetAttribute("AreaWatchBusy",true);gui:SetAttribute("AutomationOwner","Area")
        local ok,err=pcall(function()
            check(token)
            if api.active then say("Area priority","Finishing the selected Area egg first; The Rift will resume automatically.") end
            local exitPoint=prepareDeparture(token)
            check(token)
            -- Re-read after the server confirms dismount; the field or filter may have changed.
            target=priorityEgg()
            if not target then return end
            watchMessage("COLLECTING  /  "..target.AreaId.." / "..petRarity(target.AssetCategory).." / "..target.AssetCategory.." / $"..compact(fieldEggIncome(target)).."/s")
            local cycle=FieldCycle.read()
            runner.start(target.Uid,cycle.epoch,{avoidZones=treadmillZones,exitPoint=exitPoint,
                priorityCheck=function()return higherPriorityWork("Area")end})
            while runner.active do check(token);heartbeat:Wait() end
            check(token)
            if runner.phase=="Complete" then
                api.failures=0
                areaWatch.completed[target.Uid]=true
                watchMessage("COLLECTED  /  "..target.AssetCategory.." is in your inventory")
            elseif runner.phase=="ResetWait" or runner.phase=="Unavailable" or runner.phase=="RetryWait" or runner.phase=="Yielded" then
                if runner.phase=="RetryWait" then deferFieldEgg(target.Uid) end
                watchMessage("WAITING  /  target changed or field reset; checking the next spawn")
                waitForEggChange(token,.25)
            else
                error("Area trip stopped: "..tostring(gui:GetAttribute("RunnerMessage")),0)
            end
        end)
        areaWatch.busy=false;eggRevision+=1
        if alive then gui:SetAttribute("AreaWatchBusy",false);gui:SetAttribute("AutomationOwner",nil) end
        if token~=generation or not alive then error("CANCELLED",0) end
        if not ok then
            if runner.active then runner.stop("Auto Area stopped") end
            if target then deferFieldEgg(target.Uid) end
            watchMessage("RETRYING  /  "..tostring(err))
            -- Recover a held egg before choosing another job; keep the user's toggle.
            error(err,0)
        end
        if not areaWatch.enabled then watchMessage("OFF") end
        return true
    end
    local function runIndexWork(token)
        local job=indexJob()
        if not job then return false end
        indexWatch.busy=true;gui:SetAttribute("IndexBusy",true);gui:SetAttribute("AutomationOwner","Index")
        local target=nil
        local ok,err=pcall(function()
            checkRiftPriority(token)
            local exitPoint=prepareDeparture(token)
            checkRiftPriority(token)
            job=indexScan(true).job
            if not job or not indexWatch.enabled then return end
            if job.kind=="plant" then
                indexMessage("PLACING / "..job.category)
                plant(token,job.entry.uid)
            elseif job.kind=="hatch" then
                indexMessage("HATCHING / "..job.category)
                hatch(token,job.entry)
            else
                target=job.egg
                indexMessage("COLLECTING / "..target.AreaId.." / "..job.category)
                runner.start(target.Uid,FieldCycle.read().epoch,{
                    avoidZones=treadmillZones,exitPoint=exitPoint,
                    priorityCheck=riftShouldYield,
                })
                while runner.active do check(token);heartbeat:Wait()end
                check(token)
                if runner.phase=="Complete" then
                    api.failures=0
                    -- Delivery is not discovery. The next scan will either use
                    -- the owned egg or accept the server's actual Index update.
                    indexMessage("DELIVERED / "..job.category.." / checking Index")
                elseif runner.phase=="RetryWait" then deferFieldEgg(target.Uid)
                elseif runner.phase~="ResetWait" and runner.phase~="Yielded" and runner.phase~="Unavailable" then
                    error("Index trip stopped: "..tostring(gui:GetAttribute("RunnerMessage")),0)
                end
            end
        end)
        indexWatch.busy=false;indexRevision=-1;eggRevision+=1
        if alive then gui:SetAttribute("IndexBusy",false)end
        if not ok then
            if target and err~=PRIORITY_INTERRUPTED then deferFieldEgg(target.Uid)end
            error(err,0)
        end
        if not indexWatch.enabled then indexMessage("OFF")end
        return true
    end

    local recoverPendingWork
    local function workflow(token)
        recoverPendingWork(token)
        local nextState=nil
        while api.active or areaWatch.enabled or indexWatch.enabled do
            check(token)
            hatchQueue.refresh()
            if api.finishIndexIfComplete() then continue end
            if api.eventPaused then heartbeat:Wait();continue end
            local nextFeature=chooseNextFeature()
            if nextFeature=="Event" then heartbeat:Wait();continue end
            if nextFeature=="Area" and runPriorityTrip(token) then continue end
            if nextFeature=="Index" and runIndexWork(token) then continue end
            if areaWatch.enabled then watchMessage("WAITING  /  "..areaWatch.area.." / "..areaWatch.rarity..(api.active and " / The Rift is working" or " / watching new spawns")) end
            if not api.active then
                gui:SetAttribute("AutomationOwner",indexWatch.enabled and "Index" or "Area")
                trainWhileWaiting(token,nil,{indexWatch.enabled and "Auto Index waits for missing species or hatches" or "Auto Area waits for matching eggs"})
                continue
            end
            if reserveForRift() then
                gui:SetAttribute("AutomationOwner","Area")
                trainWhileWaiting(token,nil,{"Auto Area gets first pick after the field reset"})
                continue
            end
            gui:SetAttribute("AutomationOwner","Rift")
            local s=nextState or fetch();nextState=nil
            check(token);updateUI()
            if not acceptsBanner(s) and not s.PendingReward then
                trainWhileWaiting(token,s,{"waiting for "..Rift.GetBannerDisplayName(wantedBanner).." banner; the server controls rotation"})
                continue
            end
            if riftShouldYield() then continue end
            assert(s.Unlocked==true,"The Rift needs "..compact(s.UnlockSpeedPower).." Speed")
            assert(#s.Requirements==3,"The current Rift recipe is incomplete")
            assert(not s.PendingReward,"A Rift reward is already pending. Claim it before starting.")
            local inputs=selectInputs(s.Requirements,Save.Get())
            if inputs[1] and inputs[2] and inputs[3] then
                local receipt=trade(token,s)
                if receipt then
                    api.rounds+=1
                    nextState=nextRecipe(token,receipt)
                    updateUI()
                    say("Next recipe","Completed "..api.rounds.." event eggs. Checking the next three pets.")
                    pauseRift(token,.5)
                end
                continue
            end
            local action=false;local waiting={}
            for i,category in ipairs(s.Requirements) do
                if inputs[i] then continue end
                if hatchQueue.pending(category) then
                    table.insert(waiting,category.." hatching in background")
                    continue
                end
                local eggs=ownedFor(category)
                if eggs[1] then
                    local entry=eggs[1]
                    if not entry.egg.Placement then plant(token,entry.uid);action=true;break end
                    if State.IsReadyToHatch(entry.uid) then hatch(token,entry);action=true;break end
                    table.insert(waiting,category.." growing")
                else
                    local field=fieldsFor(category)
                    if field[1] then
                        local exitPoint=prepareDeparture(token)
                        check(token)
                        if riftShouldYield() then action=true;break end
                        -- The field may reset while we step off the treadmill.
                        field=fieldsFor(category)
                        if not field[1] then action=true;break end
                        local target,targetCycle=chooseFieldEgg(field)
                        if not target then action=true;pause(token,.2);break end
                        check(token)
                        if liveState and signature(liveState)~=signature(s) then action=true;break end
                        say("Collecting",category.." / "..target.AreaId.."; one egg, then return directly to the hatching space")
                        local placement=placementPlan()
                        runner.start(target.Uid,targetCycle,{
                            destination=placement.position+Vector3.new(0,3,0),
                            avoidZones=treadmillZones,
                            exitPoint=exitPoint,
                            priorityCheck=riftShouldYield,
                        })
                        while runner.active do check(token);heartbeat:Wait() end
                        check(token)
                        assert(runner.phase=="Complete" or runner.phase=="ResetWait" or runner.phase=="Yielded" or runner.phase=="Unavailable" or runner.phase=="RetryWait","Egg trip stopped: "..tostring(gui:GetAttribute("RunnerMessage")))
                        if runner.phase=="RetryWait" then deferFieldEgg(target.Uid) end
                        if runner.phase=="Complete" then
                            local collectedUid=assert(runner.collectedUid,"Collected egg UID did not confirm")
                            checkRiftPriority(token)
                            plant(token,collectedUid,placement)
                        end
                        action=true;break
                    end
                    table.insert(waiting,category.." waiting for spawn")
                end
            end
            if not action then trainWhileWaiting(token,s,waiting) end
        end
    end
    local function finishWorkflow(token,ok,err)
        if api.commitToken==token then
            api.committing=false;api.commitToken=nil
            if alive then gui:SetAttribute("RiftCommitting",false) end
        end
        if token~=generation or not alive then return end
        if ok then return end
        local reason=tostring(err)
        recordEvent("error",reason)
        api.failures=math.min((api.failures or 0)+1,5)
        api.retryAt=os.clock()+math.min(30,2^api.failures)
        recordStop("Recoverable error",reason)
        gui:SetAttribute("AutomationRecoveryReason",reason)
        gui:SetAttribute("AutomationRetryAt",api.retryAt)
        if runner.active then runner.stop("Pausing failed trip before retry") end
        local left,leaveError=pcall(stopTraining,token)
        if not left then gui:SetAttribute("AutomationRecoveryReason",reason.." / "..tostring(leaveError)) end
        if token~=generation or not alive then return end
        if api.active then say("Retrying",reason.." / Toggle stays ON; retrying after a short pause.") end
        if indexWatch.enabled then indexMessage("RETRYING / "..reason) end
        if areaWatch.enabled then watchMessage("RETRYING  /  "..reason.." / toggle stays ON") end
    end
    function api.interruptForRecovery(reason)
        generation+=1
        if runner.active then runner.stop(reason) end
        api.retryAt=os.clock()+2
        if api.active then say("Waiting",reason.." / Will resume when the character is ready.") end
        if indexWatch.enabled then indexMessage("WAITING / "..reason) end
        if areaWatch.enabled then watchMessage("WAITING  /  "..reason) end
    end
    recoverPendingWork=function(token)
        check(token)
        local safe=runner.carriedReturnPoint()
        if safe then
            local exitPoint=prepareDeparture(token)
            runner.travel(safe,"Returning the held egg before resuming automation",function()check(token);return nil end,treadmillZones,exitPoint)
            local deadline=os.clock()+6
            while runner.carriedReturnPoint() and os.clock()<deadline do pause(token,.1) end
            assert(not runner.carriedReturnPoint(),"Held egg inventory confirmation is still pending")
        end
        local receipt=api.tradeRecovery
        -- Collection features do not need a Rift request unless a sent trade is unfinished.
        if not api.active and not receipt then return end
        local s=fetch();check(token)
        if s.PendingReward then
            say("Claiming","Finishing the existing Rift reward before any new trade.")
            local ok,value=pcall(function()return Remotes.Rift.AskFinishReveal:InvokeServer()end)
            assert(ok and value~=false,"Pending Rift reward is not confirmed yet")
            s=fetch();check(token)
            assert(not s.PendingReward,"Waiting for the Rift claim to sync")
        end
        if receipt then
            local save=Save.Get()
            local count=(save.Rift.TradeInsByBanner or {})[receipt.banner] or 0
            local consumed=true
            for _,uid in ipairs(receipt.ids) do if save.Inventory[uid] then consumed=false;break end end
            assert(count>receipt.beforeCount and consumed and not s.PendingReward,"Previous trade outcome is uncertain; waiting for confirmation, not sending another trade")
            api.tradeRecovery=nil
            configStore.request();configStore.flush()
        end
    end
    local function automationReady()
        if player:GetAttribute("InBossArena") then return false end
        local character=player.Character
        local hum=character and character:FindFirstChildOfClass("Humanoid")
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not character or not character.Parent or not hum or hum.Health<=0 or not root then return false end
        local ok,ready=pcall(function()
            local save=Save.Get()
            local plot=Plot.ResolvePlot()
            local objects=workspace:FindFirstChild("__OBJECTS")
            local areas=objects and objects:FindFirstChild("Areas")
            return type(save)=="table" and type(save.Inventory)=="table" and type(save.Rift)=="table"
                and plot~=nil and plot.PetArea~=nil and plot.CenterPoint~=nil and plot.PlotFolder~=nil
                and areas~=nil and areas:FindFirstChild("SeparationLine")~=nil
        end)
        return ok and ready==true
    end
    ensureWorkflow=function()
        if os.clock()<api.retryAt or restoringConfig or api.eventPaused or (eventController and eventController.busy) or manualStarting or schedulerRunning or not alive or not (api.active or areaWatch.enabled or indexWatch.enabled)
            or runner.active or training.leaving or api.committing then return end
        if not automationReady() then
            gui:SetAttribute("AutomationWaitingForLoad",true)
            if api.active then say("Loading","Waiting for your character, inventory and plot before resuming saved settings.") end
            if indexWatch.enabled then indexMessage("LOADING / waiting for your character, inventory and plot") end
            if areaWatch.enabled then watchMessage("LOADING  /  waiting for your character, inventory and plot") end
            return
        end
        gui:SetAttribute("AutomationWaitingForLoad",false)
        schedulerRunning=true;generation+=1
        local token=generation
        if training.belt or training.owner then training.owner=token end
        task.spawn(function()
            repeat
                local ok,err=pcall(workflow,token)
                if token~=generation or not alive then finishWorkflow(token,ok,err);break end
                if not ok and err==PRIORITY_INTERRUPTED then continue end
                if not ok then finishWorkflow(token,ok,err) end
                break
            until false
            schedulerRunning=false
            if alive then gui:SetAttribute("AutomationOwner",nil) end
            if alive and (api.active or areaWatch.enabled or indexWatch.enabled) then task.defer(ensureWorkflow) end
        end)
    end
    function api.collectOnce(uid)
        if api.eventPaused or (eventController and eventController.busy) then return end
        if not alive or manualStarting or runner.active or api.active or api.committing or areaWatch.enabled or indexWatch.enabled then return end
        if not automationReady() then
            runStatus.Text="LOADING";runDetail.Text="Wait for your character and plot to load, then click COLLECT.";return
        end
        manualStarting=true;stopTrip.Visible=true
        generation+=1
        local token=generation
        task.spawn(function()
            local ok,err=pcall(function()
                local exitPoint=prepareDeparture(token)
                check(token)
                runner.start(uid,FieldCycle.read().epoch,{avoidZones=treadmillZones,exitPoint=exitPoint})
            end)
            manualStarting=false
            if not alive then return end
            stopTrip.Visible=runner.active
            if not ok and token==generation then
                runStatus.Text="STOPPED";runDetail.Text=tostring(err)
            end
            render(false)
        end)
    end
    -- Pause execution, not the user's desired toggles. Wait for old tasks to
    -- relinquish movement before the event controller can acquire it.
    function api.pauseForEvent(cancelled)
        api.eventPaused=true
        if api.active then say("Event priority","Paused for DR Scramble; this toggle stays enabled.") end
        if indexWatch.enabled then indexMessage("PAUSED / DR Scramble has priority") end
        if areaWatch.enabled then watchMessage("PAUSED  /  DR Scramble has priority") end
        while api.committing do
            if cancelled() then error("EVENT_CANCELLED",0) end
            heartbeat:Wait()
        end
        generation+=1
        if runner.active then runner.stop("Paused for DR Scramble") end
        while schedulerRunning or manualStarting do
            if cancelled() then error("EVENT_CANCELLED",0) end
            heartbeat:Wait()
        end
        if cancelled() then error("EVENT_CANCELLED",0) end
        -- An assigned belt may have no workflow owner; claim it only to dismount.
        if training.belt then training.owner=generation end
        stopTraining()
        return treadmillZones,treadmillExitPoint(rootPart().Position,treadmillZones(true))
    end
    function api.resumeAfterEvent()
        api.eventPaused=false
        if not alive then return end
        if api.active then say("Checking","DR Scramble finished; resuming the current recipe.") end
        if areaWatch.enabled then watchMessage("WAITING  /  checking your selected eggs") end
        task.defer(ensureWorkflow)
    end
    setWatchEnabled=function(on)
        if not alive then return end
        if not restoringConfig then rememberToggle("autoArea",on) end
        watchSwitch(on);eggRevision+=1
        if on then
            watchMessage("WAITING  /  watching "..areaWatch.area.." / "..areaWatch.rarity)
            ensureWorkflow()
        elseif areaWatch.busy then
            watchMessage("FINISHING  /  return the current egg, then Auto Area stays off")
        else
            watchMessage("OFF")
        end
    end
    function api.start()
        if api.eventPaused or (eventController and eventController.busy) then
            api.active=true;switchOn(true)
            say("Event priority","The Rift will resume after the drone round.")
            return
        end
        if manualStarting then say("Busy","A manual collection is starting. Finish it before enabling The Rift.");return end
        if api.active or api.committing or training.leaving then return end
        if runner.active and not schedulerRunning then say("Busy","Finish or stop the manual egg trip before starting The Rift");return end
        api.active=true;switchOn(true)
        say("Checking",areaWatch.busy and "Auto Area is collecting; The Rift will follow." or "Reading your recipe and available pets")
        ensureWorkflow()
    end
    connect(sw.Activated,function()
        if api.active then
            rememberToggle("rift",false)
            api.stop("Stopped by toggle","Toggle")
        else
            rememberToggle("rift",true)
            api.start()
        end
    end)
    connect(Input.InputBegan,function(input)
        if not (api.active or areaWatch.enabled or areaWatch.busy or indexWatch.enabled or indexWatch.busy) or Input:GetFocusedTextBox() then return end
        local k=input.KeyCode
        if k==Enum.KeyCode.W or k==Enum.KeyCode.A or k==Enum.KeyCode.S or k==Enum.KeyCode.D or k==Enum.KeyCode.Escape
            or k==Enum.KeyCode.Up or k==Enum.KeyCode.Down or k==Enum.KeyCode.Left or k==Enum.KeyCode.Right then
            indexWatch.enabled=false;gui:SetAttribute("IndexEnabled",false);indexMessage("OFF / stopped by keyboard")
            watchSwitch(false);watchMessage("OFF  /  stopped by keyboard")
            api.stop("Stopped by keyboard","Keyboard")
        end
    end)
    eventController=createScrambleController(eventPage)
    switchOn(false);say("Ready","Continuous recipes: train on your treadmill while required eggs spawn or grow.")
    connect(Save.FieldSignal("Rift"),function()recipeDirty=true end)
    task.spawn(function()
        local nextRender=0
            while alive do
            hatchQueue.refresh()
            if indexPage.Visible and panel.Visible then
                local ok,data=pcall(indexScan,false)
                if ok then paintIndex(data) else indexMessage("WAITING / Index data unavailable") end
            end
            ensureWorkflow()
            if not fetching and (recipeDirty or os.clock()-lastFetch>=5) then
                local ok,err=pcall(fetch)
                if not ok and alive then
                    if not api.active then say("Unavailable",tostring(err)) else warn("RIFT_STATE_REFRESH",err) end
                    task.wait(1)
                end
            end
            if alive and os.clock()>=nextRender then
                nextRender=os.clock()+1
                requestRiftRefresh()
            end
            task.wait(.25)
        end
    end)
end

initializeRift()

-- Attach persistence only after all settings have been restored and the UI is ready.
do
    for _,name in ipairs({"AreaWatchRules","AreaWatchEditingArea","SelectedArea","ActiveTab"}) do
        connect(gui:GetAttributeChangedSignal(name),configStore.request)
    end
    connect(panel:GetPropertyChangedSignal("Position"),configStore.request)
    connect(search:GetPropertyChangedSignal("Text"),configStore.request)
    configStore.start(function()
        return {
            rules=areaWatch.rules,editingArea=areaWatch.editing,
            selectedArea=selected,search=search.Text,tab=gui:GetAttribute("ActiveTab"),
            position={x=panel.Position.X.Offset,y=panel.Position.Y.Offset},
            autoArea=togglePreference.autoArea,rift=togglePreference.rift,autoEvent=togglePreference.autoEvent,autoIndex=togglePreference.autoIndex,indexAreas=indexWatch.areas,
            indexTargets=indexWatch.options.targets,indexStrategy=indexWatch.options.strategy,indexCompletion=indexWatch.options.completion,
            priorityOrder=table.clone(priorities.order),
            notifications=gui:GetAttribute("NotificationsEnabled")~=false,
            pendingRiftTrade=riftController and riftController.tradeRecovery or nil,
            riftBanner=gui:GetAttribute("RiftWantedBanner"),
        }
    end)
    -- Restore both switches before the shared scheduler can start either feature.
    if togglePreference.autoArea and setWatchEnabled then setWatchEnabled(true) end
    if togglePreference.autoIndex and riftController then riftController.setIndexEnabled(true) end
    if togglePreference.rift and riftController then riftController.start() end
    if togglePreference.autoEvent and eventController then eventController.setEnabled(true) end
    restoringConfig=false
    connect(player.OnTeleport,function()configStore.request();configStore.flush()end)
    connect(Players.PlayerRemoving,function(leaving)
        if leaving==player then configStore.request();configStore.flush() end
    end)
end
launchTicket.loading=false
launchTicket.readyAt=os.clock()
