-- Egg Atlas UI. Loading this file returns factories without creating a window.
-- All runtime data and actions are supplied explicitly by Main.luau.
local UI={ApiVersion=1,Version="11.31.0"}
local C = {
    bg = Color3.fromRGB(17, 16, 25), side = Color3.fromRGB(26, 24, 38),
    card = Color3.fromRGB(39, 35, 53), edge = Color3.fromRGB(86, 76, 112),
    text = Color3.fromRGB(245, 241, 252), muted = Color3.fromRGB(184, 176, 201),
    mint = Color3.fromRGB(195, 165, 255), selected = Color3.fromRGB(67, 48, 97),
}
local function make(class: string, props: {[string]: any}, holder: Instance?): any
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = holder
    return obj
end
local function round(obj, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, obj)
end
local function border(obj, color)
    make("UIStroke", {Color = color or C.edge, Thickness = 1, Transparency = 0.4}, obj)
end
local function text(holder: Instance, value: string, x: number, y: number, w: number, h: number, size: number?, color: Color3?, bold: boolean?): TextLabel
    return make("TextLabel", {
        Text = value, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, TextColor3 = color or C.text,
        TextSize = size or 13, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
end
local function button(holder: Instance, value: string, x: number, y: number, w: number, h: number): TextButton
    local b = make("TextButton", {
        Text = value, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.card, BorderSizePixel = 0, TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
    }, holder)
    round(b, 8)
    return b
end
local function section(holder: Instance, name: string, x: number, y: number, w: number, h: number, title: string): Frame
    local card=make("Frame",{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=C.card,BorderSizePixel=0},holder) :: Frame
    round(card,12);border(card)
    if title~="" then text(card,title,16,12,w-32,18,10,C.muted,true) end
    return card
end
local function scrolling(holder: Instance, x: number, y: number, w: number, h: number): ScrollingFrame
    local s = make("ScrollingFrame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.mint, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, holder)
    make("UIListLayout", {Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder}, s)
    make("UIPadding", {PaddingBottom = UDim.new(0, 4), PaddingTop = UDim.new(0, 2)}, s)
    return s
end

function UI.CreateAreaBrowser(ctx)
    local panel=ctx.panel
    local areaById=ctx.areaById
    local areaList=ctx.areaList
    local configStore=ctx.configStore
    local compact=ctx.compact
    local connect=ctx.connect
local sidebar = make("Frame", {
    Position = UDim2.fromOffset(14, 80), Size = UDim2.fromOffset(210, 624),
    BackgroundColor3 = C.side, BorderSizePixel = 0,
}, panel)
round(sidebar, 12);border(sidebar)
text(sidebar, "AREA DIRECTORY", 14, 13, 180, 20, 12, C.text, true)
text(sidebar, "Need = recommended Speed", 14, 35, 184, 18, 10, C.muted)
local areaScroll = scrolling(sidebar, 8, 63, 194, 547)
local areaButtons={}
local function areaButton(id, title, subtitle, rank, color)
    local b = make("TextButton", {
        Name = "Area_" .. id, Text = "", Size = UDim2.fromOffset(186, 49),
        BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = rank,
    }, areaScroll)
    round(b, 8)
    text(b, rank == 0 and "*" or string.format("%02d", rank), 9, 12, 25, 24, 12, color, true)
    text(b, title, 39, 5, 126, 21, 11, C.text, true)
    local sub = text(b, subtitle, 39, 26, 139, 16, 10, C.muted)
    b:SetAttribute("AreaId", id)
    b:SetAttribute("GuardSpeed", areaById[id] and areaById[id].speed)
    areaButtons[id] = {button = b, sub = sub}
    connect(b.Activated, function()
        ctx.onSelect(id)
    end)
end
areaButton("All", "All areas", "Field eggs + held by rivals", 0, C.mint)
for _, a in ipairs(areaList) do
    areaButton(a.id, a.name, "Need " .. compact(a.requiredPower), a.rank, a.color)
end
local heading = text(panel, "All areas", 245, 83, 450, 30, 22, C.text, true)
local subheading = text(panel, "Collectible spawns, grouped by guard difficulty", 246, 117, 638, 20, 11, C.muted)
local function metric(x, title)
    local box = make("Frame", {
        Position = UDim2.fromOffset(x, 151), Size = UDim2.fromOffset(208, 62),
        BackgroundColor3 = C.card, BorderSizePixel = 0,
    }, panel)
    round(box, 10)
    text(box, title, 13, 8, 184, 15, 9, C.muted, true)
    return text(box, "--", 13, 26, 184, 27, 22, C.mint, true)
end
local countMetric = metric(245, "COLLECTIBLE EGGS")
local rateMetric = metric(465, "BEST EGG  /  $ PER SEC")
local speedMetric = metric(685, "YOUR WALK SPEED  /  STUDS PER SEC")
local search = make("TextBox", {
    Name = "Search", Text = type(configStore.data.search)=="string" and configStore.data.search or "", PlaceholderText = "Search pet, rarity, area, spawn or mutation...",
    Position = UDim2.fromOffset(245, 228), Size = UDim2.fromOffset(648, 34),
    ClearTextOnFocus = false, BackgroundColor3 = C.side, BorderSizePixel = 0,
    TextColor3 = C.text, PlaceholderColor3 = C.muted, Font = Enum.Font.Gotham,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
}, panel) :: TextBox
round(search, 8)
make("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, search)
text(panel, "HATCHED PET", 263, 273, 350, 19, 9, C.muted, true)
text(panel, "WEIGHT", 659, 273, 88, 19, 9, C.muted, true)
text(panel, "INCOME / SEC", 765, 273, 125, 19, 9, C.muted, true)
local eggScroll = scrolling(panel, 245, 301, 648, 251)
eggScroll.Name = "EggList"
text(panel, "Income includes mutations; excludes personal and server boosts.", 246, 675, 647, 17, 10, C.muted)
text(panel, "LEFT ALT: hide/show  |  WASD: stop  |  Egg recovery ON", 246, 696, 450, 16, 10, C.muted)
local runPanel = make("Frame", {
    Name = "RunnerPanel", Position = UDim2.fromOffset(245,559),
    Size = UDim2.fromOffset(648,104), BackgroundColor3 = C.side, BorderSizePixel = 0,
},panel)
round(runPanel,12)
border(runPanel)
local targetLabel = text(runPanel,"Click COLLECT on the pet you want",14,8,610,22,13,C.text,true)
text(runPanel,"One click starts one collection trip and a safe return.",14,33,510,18,10,C.muted)
local runStatus = text(runPanel,"READY",14,57,518,18,11,C.mint,true)
local runDetail = text(runPanel,"Choose a pet to start. No collection toggle required.",14,79,610,17,10,C.muted)
local stopTrip=button(runPanel,"STOP TRIP",526,38,105,32)
stopTrip.Name="StopTrip";stopTrip.Visible=false

    return {sidebar=sidebar,areaButtons=areaButtons,heading=heading,subheading=subheading,countMetric=countMetric,rateMetric=rateMetric,speedMetric=speedMetric,search=search,eggScroll=eggScroll,runPanel=runPanel,targetLabel=targetLabel,runStatus=runStatus,runDetail=runDetail,stopTrip=stopTrip}
end

function UI.CreateAreaFilters(ctx)
    local panel=ctx.panel
    local gui=ctx.gui
    local areaList=ctx.areaList
    local areaById=ctx.areaById
    local areaWatch=ctx.areaWatch
    local configStore=ctx.configStore
    local watchRarities=ctx.watchRarities
    local connect=ctx.connect
    local TweenService=ctx.TweenService
local watchPanel=make("Frame",{Name="AreaWatchPanel",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel)
round(watchPanel,12);border(watchPanel)
text(watchPanel,"AUTO AREA",22,16,580,33,25,C.text,true)
text(watchPanel,"Choose an area, set its rarities, then enable Auto Collect. Highest income wins.",23,55,840,22,12,C.muted)
text(watchPanel,"AUTO COLLECT",658,29,126,18,10,C.mint,true)
local watchActivity=make("Frame",{Name="Activity",Position=UDim2.fromOffset(22,496),Size=UDim2.fromOffset(848,104),BackgroundColor3=C.card,BorderSizePixel=0},watchPanel)
round(watchActivity,12);border(watchActivity)
text(watchActivity,"CURRENT ACTIVITY",16,12,810,18,10,C.mint,true)
local watchStatus=text(watchActivity,"OFF — select your filters, then enable Auto Collect.",16,37,810,50,12,C.text)
watchStatus.TextWrapped=true;watchStatus.TextYAlignment=Enum.TextYAlignment.Top
local function watchMessage(message)
    watchStatus.Text=message
    gui:SetAttribute("AreaWatchMessage",message)
end
local function filterChecklist(label,x,values,selected,onSelect)
    local wildcard=values[1].id
    local card=make("Frame",{Name=label.."Filter",Position=UDim2.fromOffset(x,96),Size=UDim2.fromOffset(416,384),BackgroundColor3=C.card,BorderSizePixel=0},watchPanel)
    round(card,12)
    local title=text(card,"RARITIES",16,12,252,22,12,C.text,true)
    title.Name="EditingTitle"
    local selectAll=button(card,"All",276,10,52,26);selectAll.Name="SelectAll"
    local clear=button(card,"Clear",336,10,64,26);clear.Name="ClearSelection"
    selectAll.BackgroundColor3=C.selected
    local summaryLabel=text(card,"",16,40,384,18,10,C.muted)
    summaryLabel.Name="Watch"..label
    local filter=make("TextBox",{Name="FilterSearch",Position=UDim2.fromOffset(16,70),Size=UDim2.fromOffset(384,32),
        Text="",PlaceholderText=label=="Area" and "Search areas..." or "Search rarities...",ClearTextOnFocus=false,
        BackgroundColor3=C.side,BorderSizePixel=0,TextColor3=C.text,PlaceholderColor3=C.muted,
        TextSize=12,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},card) :: TextBox
    round(filter,8);make("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},filter)
    local list=scrolling(card,12,114,392,254)
    list.Name=label.."Options"
    local options={}
    local function refresh()
        local names,ids={},{}
        if selected[wildcard] then table.insert(names,values[1].label);table.insert(ids,wildcard) end
        local count=0
        for index=2,#values do
            local value=values[index]
            local on=selected[wildcard]==true or selected[value.id]==true
            local row=options[index]
            row.button.BackgroundColor3=on and C.selected or C.side
            row.box.BackgroundColor3=on and C.mint or C.edge
            row.tick.Text=on and "✓" or ""
            row.button:SetAttribute("Selected",on)
            if on then count+=1 end
            if selected[value.id] and not selected[wildcard] then table.insert(names,value.label);table.insert(ids,value.id) end
        end
        local summary=#names==0 and "None" or table.concat(names,", ")
        summaryLabel.Text=count.." of "..(#values-1).." selected  ·  "..summary
        summaryLabel:SetAttribute("SelectionCount",count)
        onSelect(summary,ids)
    end
    for index=2,#values do
        local value=values[index]
        local option=make("TextButton",{Text="",Size=UDim2.new(1,-8,0,38),LayoutOrder=index,
            BackgroundColor3=C.side,BorderSizePixel=0,AutoButtonColor=false},list)
        round(option,8);option:SetAttribute("Value",value.id)
        local box=make("Frame",{Position=UDim2.fromOffset(12,10),Size=UDim2.fromOffset(18,18),BackgroundColor3=C.edge,BorderSizePixel=0},option)
        round(box,5)
        local tick=text(box,"",0,0,18,18,13,C.bg,true);tick.TextXAlignment=Enum.TextXAlignment.Center
        text(option,value.label,42,8,328,22,12,C.text)
        options[index]={button=option,box=box,tick=tick}
        connect(option.Activated,function()
            -- With All selected, unchecking one item keeps the other items selected.
            if selected[wildcard] then
                table.clear(selected)
                for i=2,#values do selected[values[i].id]=true end
            end
            if selected[value.id] then selected[value.id]=nil else selected[value.id]=true end
            refresh();ctx.changed()
        end)
    end
    local empty=text(card,"No matching options.",24,128,368,22,12,C.muted)
    empty.Name="EmptySearch";empty.Visible=false
    connect(filter:GetPropertyChangedSignal("Text"),function()
        local query=filter.Text:lower()
        local shown=0
        for index,row in pairs(options) do
            local matches=values[index].label:lower():find(query,1,true)~=nil
            row.button.Visible=matches
            if matches then shown+=1 end
        end
        empty.Visible=shown==0;list.CanvasPosition=Vector2.zero
    end)
    connect(selectAll.Activated,function()
        table.clear(selected);selected[wildcard]=true;refresh();ctx.changed()
    end)
    connect(clear.Activated,function()
        table.clear(selected);refresh();ctx.changed()
    end)
    refresh()
    return {setSelection=function(selection,areaName)
        selected=selection;title.Text="RARITIES · "..areaName;refresh()
    end}
end
do
    local card=make("Frame",{Name="AreaRules",Position=UDim2.fromOffset(22,96),Size=UDim2.fromOffset(416,384),BackgroundColor3=C.card,BorderSizePixel=0},watchPanel)
    round(card,12)
    text(card,"AREA RULES",16,12,220,22,13,C.text,true)
    local allOn=button(card,"All on",264,10,64,26);allOn.Name="EnableAll"
    local allOff=button(card,"All off",336,10,64,26);allOff.Name="DisableAll"
    local summary=text(card,"Click a row to edit its rarities",16,40,384,18,10,C.muted)
    local searchAreas=make("TextBox",{Name="FilterSearch",Position=UDim2.fromOffset(16,70),Size=UDim2.fromOffset(384,32),
        Text="",PlaceholderText="Search areas...",ClearTextOnFocus=false,BackgroundColor3=C.side,BorderSizePixel=0,
        TextColor3=C.text,PlaceholderColor3=C.muted,TextSize=12,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},card) :: TextBox
    round(searchAreas,8);make("UIPadding",{PaddingLeft=UDim.new(0,12)},searchAreas)
    local list=scrolling(card,12,114,392,254);list.Name="AreaOptions"
    local rows={}
    local rarityEditor
    for _,area in ipairs(areaList) do
        local rule={enabled=true,rarities={Any=true}}
        local saved=type(configStore.data.rules)=="table" and configStore.data.rules[area.id]
        if type(saved)=="table" then
            if type(saved.enabled)=="boolean" then rule.enabled=saved.enabled end
            if type(saved.rarities)=="table" then
                rule.rarities={}
                for _,value in ipairs(watchRarities) do
                    if saved.rarities[value.id]==true then rule.rarities[value.id]=true end
                end
            end
        end
        areaWatch.rules[area.id]=rule
    end
    areaWatch.editing=areaById[configStore.data.editingArea] and configStore.data.editingArea
        or (areaList[1] and areaList[1].id)
    local function publishRules()
        local encoded={};local enabled=0
        for _,area in ipairs(areaList) do
            local rule=areaWatch.rules[area.id]
            local names,ids={},{}
            if rule.rarities.Any then names={"All rarities"};ids={"Any"}
            else
                for i=2,#watchRarities do
                    local value=watchRarities[i]
                    if rule.rarities[value.id] then table.insert(names,value.label);table.insert(ids,value.id) end
                end
            end
            if rule.enabled then enabled+=1 end
            table.insert(encoded,{AreaId=area.id,Enabled=rule.enabled,Rarities=ids})
            local row=rows[area.id]
            if row then
                row.button.BackgroundColor3=areaWatch.editing==area.id and C.selected or C.side
                row.button:SetAttribute("Editing",areaWatch.editing==area.id)
                row.detail.Text=(rule.enabled and "" or "OFF · ")..(#names==0 and "No rarities selected" or table.concat(names,", "))
                row.toggle:SetAttribute("On",rule.enabled)
                row.toggle.BackgroundColor3=rule.enabled and Color3.fromRGB(52,199,89) or C.edge
                row.knob.Position=UDim2.fromOffset(rule.enabled and 27 or 3,3)
            end
        end
        areaWatch.area=enabled.." areas enabled"
        summary.Text=enabled.." / "..#areaList.." enabled · click a row to edit"
        gui:SetAttribute("AreaWatchRules",game:GetService("HttpService"):JSONEncode(encoded))
        gui:SetAttribute("AreaWatchEditingArea",areaWatch.editing)
    end
    local function editArea(id)
        areaWatch.editing=id
        local area=areaById[id]
        rarityEditor.setSelection(areaWatch.rules[id].rarities,area and area.name or id)
    end
    for _,area in ipairs(areaList) do
        local option=make("TextButton",{Name="Rule_"..area.id,Text="",Size=UDim2.new(1,-8,0,60),LayoutOrder=area.rank,
            BackgroundColor3=C.side,BorderSizePixel=0,AutoButtonColor=false},list)
        round(option,8);option:SetAttribute("AreaId",area.id)
        text(option,area.name,12,7,288,22,12,C.text,true)
        local detail=text(option,"",12,32,290,18,10,C.muted)
        local toggle=make("TextButton",{Name="AreaEnabled",Text="",Position=UDim2.fromOffset(316,16),Size=UDim2.fromOffset(52,28),
            BackgroundColor3=C.edge,BorderSizePixel=0,AutoButtonColor=false},option);round(toggle,14)
        local knob=make("Frame",{Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(22,22),BackgroundColor3=C.text,BorderSizePixel=0},toggle);round(knob,11)
        rows[area.id]={button=option,detail=detail,toggle=toggle,knob=knob}
        connect(option.Activated,function()editArea(area.id)end)
        connect(toggle.Activated,function()
            local rule=areaWatch.rules[area.id];rule.enabled=not rule.enabled
            publishRules();ctx.changed()
        end)
    end
    local empty=text(card,"No matching areas.",24,128,368,22,12,C.muted);empty.Visible=false
    connect(searchAreas:GetPropertyChangedSignal("Text"),function()
        local query=searchAreas.Text:lower();local shown=0
        for id,row in pairs(rows) do
            row.button.Visible=areaById[id].name:lower():find(query,1,true)~=nil
            if row.button.Visible then shown+=1 end
        end
        empty.Visible=shown==0;list.CanvasPosition=Vector2.zero
    end)
    connect(allOn.Activated,function()
        for _,rule in pairs(areaWatch.rules) do rule.enabled=true end
        publishRules();ctx.changed()
    end)
    connect(allOff.Activated,function()
        for _,rule in pairs(areaWatch.rules) do rule.enabled=false end
        publishRules();ctx.changed()
    end)
    rarityEditor=filterChecklist("Rarity",454,watchRarities,areaWatch.editing and areaWatch.rules[areaWatch.editing].rarities or {},function(_summary,_ids)publishRules()end)
    if areaWatch.editing then editArea(areaWatch.editing) end
end
local watchToggle=make("TextButton",{Name="AreaWatchToggle",Text="",Position=UDim2.fromOffset(804,22),Size=UDim2.fromOffset(64,36),BackgroundColor3=Color3.fromRGB(67,76,91),BorderSizePixel=0,AutoButtonColor=false},watchPanel)
round(watchToggle,18)
local watchKnob=make("Frame",{Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(30,30),BackgroundColor3=Color3.fromRGB(250,252,255),BorderSizePixel=0},watchToggle)
round(watchKnob,15)
local function watchSwitch(on)
    areaWatch.enabled=on
    watchToggle:SetAttribute("On",on);gui:SetAttribute("AreaWatchEnabled",on)
    TweenService:Create(watchToggle,TweenInfo.new(.18),{BackgroundColor3=on and Color3.fromRGB(52,199,89) or Color3.fromRGB(67,76,91)}):Play()
    TweenService:Create(watchKnob,TweenInfo.new(.18),{Position=UDim2.fromOffset(on and 31 or 3,3)}):Play()
end
connect(watchToggle.Activated,function()ctx.setEnabled(not areaWatch.enabled) end)
watchSwitch(false)





    return {panel=watchPanel,message=watchMessage,switch=watchSwitch}
end

function UI.RenderAreas(ctx,resetScroll)
    local gui=ctx.gui
    local areaView=ctx.areaView
    local snapshotGroups=ctx.snapshotGroups
    local selected=ctx.selected
    local selectedTarget=ctx.selectedTarget
    local runner=ctx.runner
    local manualStarting=ctx.manualStarting
    local areaWatch=ctx.areaWatch
    local indexWatch=ctx.indexWatch
    local riftController=ctx.riftController
    local snapshotRevision=ctx.snapshotRevision
    local areaList=ctx.areaList
    local areaById=ctx.areaById
    local compact=ctx.compact
    local selectEgg=ctx.selectEgg
    local areaButtons=areaView.areaButtons
    local heading=areaView.heading
    local subheading=areaView.subheading
    local countMetric=areaView.countMetric
    local rateMetric=areaView.rateMetric
    local speedMetric=areaView.speedMetric
    local search=areaView.search
    local eggScroll=areaView.eggScroll
    if not ctx.isAlive() or not ctx.isVisible() then return end
    local savedScroll = resetScroll and Vector2.zero or eggScroll.CanvasPosition
    local query, shown, best, order, total = search.Text:lower(), 0, nil, 0, 0
    local yourPower=ctx.yourPower
    for _, a in ipairs(areaList) do total += #(snapshotGroups[a.id] or {}) end
    for id, ui in pairs(areaButtons) do
        ui.button.BackgroundColor3 = selected == id and C.selected or C.card
        if id == "All" then ui.sub.Text = total .. " eggs / " .. #areaList .. " areas"
        else
            local a=areaById[id]
            ui.sub.Text = "Need " .. compact(a.requiredPower) .. "  /  " .. #(snapshotGroups[id] or {}) .. " eggs"
            ui.sub.TextColor3=a.requiredPower and yourPower>=a.requiredPower and C.mint or C.muted
        end
    end
    local chosen = areaById[selected]
    heading.Text = chosen and chosen.name or "All areas"
    if chosen then
        local enough=chosen.requiredPower and yourPower>=chosen.requiredPower
        subheading.Text="Need "..compact(chosen.requiredPower).." Speed  /  "..compact(chosen.requiredWalk)
            .." studs/s  /  You: "..compact(yourPower).."  /  "..(enough and "Above recommendation" or "Below recommendation")
        subheading.TextColor3=enough and C.mint or Color3.fromRGB(244,166,132)
    else
        subheading.Text="Your Speed: "..compact(yourPower).."  /  Area recommendations from the game's signs"
        subheading.TextColor3=C.muted
    end
    speedMetric.Text=compact(ctx.walkSpeed)
    local viewParts={tostring(snapshotRevision),selected,query,
        selectedTarget and selectedTarget.uid or "",tostring(runner.active),tostring(manualStarting),
        tostring(areaWatch.enabled),tostring(indexWatch.enabled),
        tostring(riftController and (riftController.active or riftController.committing))}
    for _,area in ipairs(areaList)do table.insert(viewParts,tostring(area.requiredPower~=nil and yourPower>=area.requiredPower))end
    local viewKey=table.concat(viewParts,"\30")
    if viewKey==areaView.lastViewKey then
        if resetScroll then eggScroll.CanvasPosition=Vector2.zero end
        return
    end
    areaView.lastViewKey=viewKey
    for _,child in ipairs(eggScroll:GetChildren())do if child:IsA("Frame")then child:Destroy()end end
    for _, a in ipairs(areaList) do
        if selected == "All" or selected == a.id then
            local matching = {}
            for _, row in ipairs(snapshotGroups[a.id] or {}) do
                if query == "" or row.query:find(query, 1, true) then table.insert(matching, row) end
            end
            if #matching > 0 or (query == "" and selected == a.id) then
                order += 1
                local group = make("Frame", {
                    Name = "Group_" .. a.id, Size = UDim2.fromOffset(638, 48),
                    BackgroundTransparency = 1, LayoutOrder = order,
                }, eggScroll)
                group:SetAttribute("GuardSpeed", a.speed)
                group:SetAttribute("RequiredSpeedPower",a.requiredPower)
                group:SetAttribute("RequiredWalkSpeed",a.requiredWalk)
                text(group, string.format("%02d  %s", a.rank, a.name), 8, 2, 382, 26, 12, a.color, true)
                local enough=a.requiredPower and yourPower>=a.requiredPower
                text(group,"Need "..compact(a.requiredPower).." Speed / "..compact(a.requiredWalk).." studs/s",365,2,269,26,10,enough and C.mint or Color3.fromRGB(244,166,132),true)
                text(group,"Guard "..compact(a.speed).."  /  "..#matching.." eggs  /  "..(enough and "Above recommended Speed" or "Below recommended Speed"),8,28,621,17,10,C.muted)
            end
            for _, row in ipairs(matching) do
                order += 1
                shown += 1
                if row.rate and (not best or row.rate > best) then best = row.rate end
                local card = make("Frame", {
                    Name = "Egg_" .. row.uid, Size = UDim2.fromOffset(638, 110),
                    BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = order,
                }, eggScroll)
                card:SetAttribute("AreaId", row.area)
                card:SetAttribute("CarrierUserId",row.carrierId)
                card:SetAttribute("Income", row.rate)
                card:SetAttribute("PetRarity", row.rarity)
                round(card, 10)
                if selectedTarget and selectedTarget.uid==row.uid then border(card,C.mint) end
                local iconBox = make("Frame", {
                    Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(46, 46),
                    BackgroundColor3 = C.side, BorderSizePixel = 0,
                }, card)
                round(iconBox, 9)
                if row.icon ~= "" then
                    make("ImageLabel", {Image = row.icon, BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(40, 40),
                        ScaleType = Enum.ScaleType.Fit}, iconBox)
                else text(iconBox, "PET", 7, 10, 36, 25, 10, a.color, true) end
                text(card, row.pet, 69, 10, 329, 23, 14, C.text, true)
                local rarityLabel = text(card, "Rarity: " .. row.rarity, 69, 35, 329, 17, 11, row.rarityColor, true)
                rarityLabel.Name = "PetRarity"
                text(card, (row.carrierId and ("HELD BY "..row.carrierName.."  /  ") or (row.state=="Dropped" and "DROPPED  /  " or "")) .. row.nest .. "  /  " .. row.mutation, 69, 54, 329, 19, 10, C.muted)
                text(card, compact(row.weight) .. " kg", 414, 20, 100, 26, 12, C.text, true)
                text(card, "$" .. compact(row.rate), 520, 19, 113, 28, 16, C.mint, true)
                local picked=selectedTarget and selectedTarget.uid==row.uid and (runner.active or manualStarting)
                local busy=runner.active or manualStarting
                local automated=areaWatch.enabled or indexWatch.enabled or (riftController and (riftController.active or riftController.committing))
                text(card,picked and "COLLECTING THIS PET" or (automated and "Pause automation for manual collection" or (row.carrierId and "Chase carrier, recover egg, return safely" or "Click to collect and return safely")),69,83,365,18,10,picked and C.mint or C.muted,picked)
                local pick=button(card,picked and "COLLECTING" or (busy and "IN PROGRESS" or (automated and "AUTO ACTIVE" or (row.carrierId and "CHASE  >" or "COLLECT  >"))),454,80,173,24)
                pick.Name="CollectEgg"
                pick:SetAttribute("EggUid",row.uid)
                pick.BackgroundColor3=(busy or automated) and C.edge or C.selected
                pick.Active=not busy and not automated
                pick.AutoButtonColor=not busy and not automated
                pick.Activated:Connect(function() selectEgg(row) end)
            end
        end
    end
    if shown == 0 then
        local empty = make("Frame", {Size = UDim2.fromOffset(638, 91), BackgroundTransparency = 1, LayoutOrder = order + 1}, eggScroll)
        text(empty, query ~= "" and "No eggs match your search." or "No collectible eggs in this area right now.", 18, 20, 600, 28, 15, C.text, true)
        text(empty, "Updates as eggs spawn, disappear or reset.", 18, 51, 600, 20, 11, C.muted)
    end
    countMetric.Text = tostring(shown)
    rateMetric.Text = best and "$" .. compact(best) or "--"
    gui:SetAttribute("RecordCount", total)
    gui:SetAttribute("VisibleEggCount", shown)
    gui:SetAttribute("SelectedArea", selected)
    eggScroll.CanvasPosition = resetScroll and Vector2.zero or savedScroll

end

function UI.CreateEventWidgets(page)
    text(page,"DR SCRAMBLE'S",22,16,630,33,25,C.mint,true)
    text(page,"Personal drones  /  Samples  /  Return to your enabled features between rounds",23,56,820,23,12,C.muted)
    local sw=make("TextButton",{Name="EventAutoToggle",Text="",Position=UDim2.fromOffset(804,22),Size=UDim2.fromOffset(64,36),BackgroundColor3=Color3.fromRGB(67,76,91),BorderSizePixel=0,AutoButtonColor=false},page)
    round(sw,18)
    local dot=make("Frame",{Name="Knob",Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(30,30),BackgroundColor3=C.text,BorderSizePixel=0},sw);round(dot,15)
    local activity=section(page,"EventActivity",24,96,844,156,"CURRENT ACTIVITY")
    local stateText=text(activity,"OFF",16,39,812,32,22,C.mint,true)
    local detail=text(activity,"Enable to wait for the next drone outbreak.",16,82,812,60,13,C.text)
    detail.TextWrapped=true;detail.TextTruncate=Enum.TextTruncate.None;detail.TextYAlignment=Enum.TextYAlignment.Top
    local progress=section(page,"EventProgress",24,268,844,108,"YOUR EVENT PROGRESS")
    local samples=text(progress,"-- SAMPLES",16,36,280,28,20,C.mint,true)
    local parts=text(progress,"-- / 5 parts",324,40,200,24,14,C.text,true)
    local targets=text(progress,"-- personal drones",568,40,256,24,13,C.text)
    local timeText=text(progress,"Reading the server schedule...",16,76,800,18,11,C.muted)
    local flow=section(page,"EventFlow",24,392,844,184,"HOW IT WORKS")
    local explanation=text(flow,"Wait for the server's event window while other features continue.\nDeliver a held egg first, then follow your own drones. The game handles bat attacks.\nCollect dropped rewards and return safely when the round ends.\nSamples stay in your wallet; spending and the Vault quest remain manual.",16,40,812,124,13,C.text)
    explanation.TextWrapped=true;explanation.TextTruncate=Enum.TextTruncate.None;explanation.TextYAlignment=Enum.TextYAlignment.Top
    text(page,"Priority can be changed in Overview. WASD / Esc releases control. LEFT ALT hides the UI.",24,594,844,20,10,C.muted)
    return {sw=sw,dot=dot,stateText=stateText,detail=detail,samples=samples,parts=parts,targets=targets,timeText=timeText}
end

function UI.CreateRiftWidgets(page,banners)
    local purple=Color3.fromRGB(185,151,255)
    text(page,"THE RIFT",22,16,570,33,25,purple,true)
    text(page,"One egg per trip  >  Train while eggs spawn / grow  >  Hatch  >  Trade 3 pets",23,54,790,22,12,C.muted)
    local bannerButtons={}
    local options={{Id="Any",DisplayName="Any active banner"}}
    for _,entry in ipairs(banners) do table.insert(options,entry) end
    for i,entry in ipairs(options) do
        local choice=button(page,entry.DisplayName,22+(i-1)*213,84,207,30)
        choice.Name="RiftBanner_"..entry.Id;bannerButtons[entry.Id]=choice
    end
    text(page,"Only trade the chosen banner when its server rotation is active.",24,118,844,16,10,C.muted)
    local recipeSection=section(page,"RiftRecipe",22,141,848,60,"ACTIVE SERVER RECIPE")
    local activitySection=section(page,"RiftActivity",22,466,848,98,"CURRENT ACTIVITY")
    local banner=text(recipeSection,"Reading current recipe...",16,30,558,24,18,C.text,true)
    local timer=text(recipeSection,"--",590,30,242,24,12,purple,true)
    local odds=text(page,"",23,207,844,18,10,C.muted)
    local rows: {{card: Frame,icon: ImageLabel,name: TextLabel,rarity: TextLabel,detail: TextLabel,status: TextLabel}}={}
    for i=1,3 do
        local card=make("Frame",{Name="Requirement"..i,Position=UDim2.fromOffset(22,231+(i-1)*77),Size=UDim2.fromOffset(848,71),BackgroundColor3=C.card,BorderSizePixel=0},page)
        round(card,10)
        local icon=make("ImageLabel",{Position=UDim2.fromOffset(12,11),Size=UDim2.fromOffset(55,55),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},card)
        local rarityLabel=text(card,"Rarity: --",80,34,430,16,10,C.muted,true)
        rarityLabel.Name="PetRarity"
        rows[i]={card=card,icon=icon,name=text(card,"--",80,7,430,25,16,C.text,true),rarity=rarityLabel,detail=text(card,"",80,53,750,18,11,C.muted),status=text(card,"--",595,14,237,26,14,purple,true)}
    end
    local status=text(activitySection,"READY",16,30,816,25,16,purple,true)
    local detail=text(activitySection,"Enable to keep collecting, hatching and trading each new recipe.",16,58,816,34,12,C.text)
    detail.TextWrapped=true;detail.TextTruncate=Enum.TextTruncate.None;detail.TextYAlignment=Enum.TextYAlignment.Top
    local sw=make("TextButton",{Name="RiftAutoToggle",Text="",Position=UDim2.fromOffset(804,22),Size=UDim2.fromOffset(64,36),BackgroundColor3=Color3.fromRGB(67,76,91),BorderSizePixel=0,AutoButtonColor=false},page)
    round(sw,18)
    local dot=make("Frame",{Name="Knob",Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(30,30),BackgroundColor3=Color3.fromRGB(250,252,255),BorderSizePixel=0},sw);round(dot,15)
    local cycleLabel=text(page,"CONTINUOUS  /  0 event eggs confirmed  /  Lowest-income eligible pets first",24,574,844,18,10,C.muted)
    text(page,"WASD / Esc stops this run. Toggle choices are saved. Accepted trades finish claiming.",24,597,844,18,10,C.muted)

    return {bannerButtons=bannerButtons,banner=banner,timer=timer,odds=odds,rows=rows,status=status,detail=detail,sw=sw,dot=dot,cycleLabel=cycleLabel}
end

function UI.CreateStatsWidgets(ctx,page)
    text(page,"STATS EGGS",22,16,570,33,25,C.mint,true)
    text(page,"Click an egg to locate it / click again to clear ESP / highest income first",23,54,842,22,12,C.muted)
    local function metricBox(x,title)
        local box=make("Frame",{Position=UDim2.fromOffset(x,92),Size=UDim2.fromOffset(272,70),BackgroundColor3=C.card,BorderSizePixel=0},page)
        round(box,10)
        text(box,title,13,10,248,16,10,C.muted,true)
        return text(box,"--",13,31,248,27,21,C.mint,true)
    end
    local count=metricBox(22,"PLACED EGGS / READY")
    local total=metricBox(310,"COMBINED INCOME AFTER HATCH")
    local best=metricBox(598,"BEST EGG / INCOME PER SECOND")
    text(page,"PET / RARITY / MUTATIONS",35,181,388,20,10,C.muted,true)
    text(page,"WEIGHT",435,181,93,20,10,C.muted,true)
    text(page,"AFTER HATCH / SEC",550,181,166,20,10,C.muted,true)
    text(page,"HATCH STATUS",733,181,133,20,10,C.muted,true)
    local list=scrolling(page,22,211,848,350)
    list.Name="StatsEggList"
    local empty=text(page,"No placed eggs. Place an egg in your plot to see it here.",38,245,810,48,14,C.muted)
    empty.Name="EmptyState"
    local note=text(page,"Projected pet income, including mutations; excludes personal and server boosts.",23,572,844,20,11,C.muted)
    text(page,"Eggs do not earn while growing. Finished hatches leave this list automatically.",23,597,844,18,10,C.muted)
    local espGui=make("ScreenGui",{Name="EggAtlasSelectedEggESP",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=110,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},ctx.parent)
    local anchor=make("Attachment",{Name="EggAtlasSelectedEggAnchor"},workspace.Terrain) :: Attachment
    local highlight=make("Highlight",{Name="SelectedEgg",Enabled=false,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,FillColor=C.mint,OutlineColor=Color3.new(1,1,1),FillTransparency=.7,OutlineTransparency=0},espGui) :: Highlight
    local billboard=make("BillboardGui",{Name="EggLocation",Adornee=anchor,AlwaysOnTop=true,Enabled=false,Size=UDim2.fromOffset(260,70),StudsOffsetWorldSpace=Vector3.new(0,5,0)},espGui) :: BillboardGui
    local billboardText=text(billboard,"",0,0,260,70,14,C.mint,true) :: TextLabel
    billboardText.TextXAlignment=Enum.TextXAlignment.Center
    billboardText.TextWrapped=true;billboardText.TextTruncate=Enum.TextTruncate.None
    billboardText.TextStrokeTransparency=.25
    local edge=make("Frame",{Name="OffscreenPointer",Visible=false,Size=UDim2.fromOffset(150,62),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.bg,BackgroundTransparency=.1,BorderSizePixel=0},espGui) :: Frame
    round(edge,10)
    local arrow=text(edge,">",58,0,34,30,28,C.mint,true)
    arrow.TextXAlignment=Enum.TextXAlignment.Center
    local edgeText=text(edge,"",5,32,140,24,11,C.text,true)
    edgeText.TextXAlignment=Enum.TextXAlignment.Center
    local stop=button(espGui,"",0,0,310,34) :: TextButton
    stop.Name="StopEggESP";stop.AnchorPoint=Vector2.new(.5,1);stop.Position=UDim2.new(.5,0,1,-24);stop.Visible=false

    return {count=count,total=total,best=best,list=list,empty=empty,note=note,espGui=espGui,anchor=anchor,highlight=highlight,billboard=billboard,billboardText=billboardText,edge=edge,arrow=arrow,edgeText=edgeText,stop=stop}
end

function UI.RenderStats(ctx,rows)
    local view=ctx.view
    local page=ctx.page
    local cards=ctx.cards
    local selectedUid=ctx.selectedUid
    local selectEgg=ctx.selectEgg
    local compact=ctx.compact
    local duration=ctx.duration
    local count=view.count
    local total=view.total
    local best=view.best
    local list=view.list
    local empty=view.empty
    local note=view.note
        local seen={}
        local sum,ready,unknown=0,0,0
        for i,row in ipairs(rows) do
            seen[row.uid]=true
            if row.rate~=nil then sum+=row.rate else unknown+=1 end
            if row.ready then ready+=1 end
            local ui=cards[row.uid]
            if not ui then
                local card=make("TextButton",{Name="Egg_"..row.uid,Text="",AutoButtonColor=false,Size=UDim2.fromOffset(840,104),BackgroundColor3=C.card,BorderSizePixel=0},list)
                round(card,10)
                local icon=make("ImageLabel",{Position=UDim2.fromOffset(10,13),Size=UDim2.fromOffset(52,52),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},card)
                ui={card=card,icon=icon,name=text(card,"",76,8,325,22,14,C.text,true),
                    rarity=text(card,"",76,33,325,17,10,C.muted,true),
                    mutation=text(card,"",76,55,325,40,12,Color3.fromRGB(205,178,255),true),
                    weight=text(card,"",413,29,105,25,13,C.text),
                    income=text(card,"",528,25,176,29,18,C.mint,true),
                    status=text(card,"",711,17,125,20,10,C.mint,true),
                    time=text(card,"",711,43,125,20,11,C.muted)}
                ui.mutation.Name="Mutation"
                ui.mutation.TextWrapped=true;ui.mutation.TextTruncate=Enum.TextTruncate.None
                ui.mutation.TextYAlignment=Enum.TextYAlignment.Top
                ui.name.Name="PetName"
                cards[row.uid]=ui
                -- Destroying the card also disconnects its own Activated handler.
                card.Activated:Connect(function()selectEgg(row.uid,ui.name.Text)end)
            end
            ui.card.LayoutOrder=i
            ui.card:SetAttribute("EggUid",row.uid);ui.card:SetAttribute("Income",row.rate)
            ui.card:SetAttribute("RemainingSeconds",row.remaining)
            ui.icon.Image=row.icon;ui.name.Text=row.pet
            ui.rarity.Text=row.rarity.."  /  #"..row.uid:sub(1,8);ui.rarity.TextColor3=row.color
            ui.mutation.Text="Mutation: "..row.mutation
            local height=game:GetService("TextService"):GetTextSize(ui.mutation.Text,12,Enum.Font.GothamBold,Vector2.new(325,1000)).Y
            ui.mutation.Size=UDim2.fromOffset(325,math.max(32,height+4))
            ui.card.Size=UDim2.fromOffset(840,math.max(104,63+height))
            ui.card.BackgroundColor3=selectedUid==row.uid and C.selected or C.card
            ui.weight.Text=row.weight and (compact(row.weight).." kg") or "N/A"
            ui.income.Text=row.rate~=nil and ("$"..compact(row.rate).."/s") or "N/A"
            ui.status.Text=row.status
            ui.status.TextColor3=row.ready and C.mint or C.muted
            ui.time.Text=row.status=="HATCHING" and "Finishing..." or (row.ready and "Ready now" or duration(row.remaining))
        end
        for uid,ui in pairs(cards) do if not seen[uid] then ui.card:Destroy();cards[uid]=nil end end
        empty.Visible=#rows==0
        count.Text=tostring(#rows).." / "..tostring(ready).." ready"
        total.Text=(unknown>0 and "Known: " or "").."$"..compact(sum).."/s"
        best.Text=rows[1] and rows[1].rate~=nil and ("$"..compact(rows[1].rate).."/s") or "--"
        note.Text=unknown>0 and (tostring(unknown).." egg income unavailable; total includes known values only.")
            or "Projected pet income, including mutations; excludes personal and server boosts."
        page:SetAttribute("EggCount",#rows);page:SetAttribute("KnownIncome",sum)
    
end

function UI.CreatePriorityControls(ctx,section)
    local names={Event="DR SCRAMBLE",Area="AUTO AREA",Index="AUTO INDEX",Rift="THE RIFT"}
    local labels={}
    local function paint()
        for i,label in ipairs(labels)do label.Text=i.."  "..names[ctx.order[i]]end
    end
    for i=1,4 do
        local x=16+(i-1)*205
        labels[i]=text(section,"",x,40,119,28,11,C.text,true)
        local left=button(section,"<",x+121,39,31,29)
        local right=button(section,">",x+158,39,31,29)
        left.Name="PriorityLeft"..i;right.Name="PriorityRight"..i
        left.Visible=i>1;right.Visible=i<4
        ctx.connect(left.Activated,function()ctx.shift(i,-1);paint()end)
        ctx.connect(right.Activated,function()ctx.shift(i,1);paint()end)
    end
    paint()
end

-- Index/Overview presentation dependencies are supplied explicitly by the main script.
type IndexViewOptions = {targets: {[string]: {[string]: boolean}},strategy: string,completion: string}
type IndexViewContext = {
    indexWatch: {enabled: boolean,areas: {[string]: boolean},message: string,options: IndexViewOptions},
    areaList: {{id: string,name: string,rank: number,config: any}},
    gui: ScreenGui,TweenService: TweenService,
    connect: (RBXScriptSignal,(...any) -> ()) -> RBXScriptConnection,
    petRarity: (string) -> (string,Color3),
}
type OverviewViewContext = {
    configStore: {data: {[string]: any},request: () -> ()},gui: ScreenGui,panel: Frame,
    connect: (RBXScriptSignal,(...any) -> ()) -> RBXScriptConnection,
    isAlive: () -> boolean,
}

type IndexViewJob = {kind: string,category: string,entry: {uid: string,egg: any}?,egg: any?}
type IndexViewAreaProgress = {id: string,name: string,total: number,found: number,targetTotal: number,targetFound: number,selected: boolean,
    missing: {{category: string,name: string,icon: string,state: string,selected: boolean}}}
type IndexViewPlan = {areas: {IndexViewAreaProgress},wanted: {[string]: boolean},total: number,found: number,
    missing: number,selected: number,collectionTotal: number,collectionFound: number,job: IndexViewJob?}

function UI.CreateIndexPage(ctx: IndexViewContext,page: Frame,controller: {changed: () -> (),setEnabled: (boolean) -> ()})
    local indexWatch,areaList=ctx.indexWatch,ctx.areaList
    local gui,connect=ctx.gui,ctx.connect
    local TweenService,petRarity=ctx.TweenService,ctx.petRarity
    text(page,"AUTO INDEX",22,16,600,32,25,C.mint,true)
    text(page,"Choose areas, then tap missing species to include or skip. Existing eggs are used first.",23,55,840,20,11,C.muted)
    local toggle=button(page,"",804,22,64,36);round(toggle,18)
    local knob=make("Frame",{Size=UDim2.fromOffset(30,30),Position=UDim2.fromOffset(3,3),BackgroundColor3=C.text,BorderSizePixel=0},toggle);round(knob,15)
    local summary=section(page,"IndexProgress",22,92,848,110,"YOUR COLLECTION GOAL")
    local areaSection=section(page,"IndexAreas",22,214,270,318,"AREAS")
    local missingSection=section(page,"IndexMissing",310,214,560,318,"MISSING SPECIES / TAP TO SELECT")
    local activity=section(page,"IndexActivity",22,546,848,42,"")
    local progress=text(summary,"Reading Index...",16,31,816,22,14,C.text,true)
    local strategy=button(summary,"",16,65,392,30)
    local completion=button(summary,"",424,65,408,30)
    local all=button(areaSection,"Select all areas",12,41,116,28)
    local none=button(areaSection,"Clear areas",140,41,116,28)
    local areas=scrolling(areaSection,12,82,246,220)
    local targetAll=button(missingSection,"All species",12,41,246,28)
    local targetNone=button(missingSection,"Clear species",272,41,276,28)
    local missing=scrolling(missingSection,12,82,536,220)
    local status=text(activity,"OFF",16,9,816,24,13,C.mint,true)
    text(page,"Completion uses the game's Index. Other enabled features continue when Index finishes.",23,599,844,16,10,C.muted)
    local buttons={}
    local cardConnections={}
    local lastKey: string?=nil
    local function clearCards()
        for _,connection in ipairs(cardConnections) do connection:Disconnect() end
        table.clear(cardConnections)
        for _,child in ipairs(missing:GetChildren())do if child:IsA("GuiObject")then child:Destroy()end end
    end
    connect(page.Destroying,clearCards)
    local function paint()
        toggle.BackgroundColor3=indexWatch.enabled and C.mint or Color3.fromRGB(67,76,91)
        TweenService:Create(knob,TweenInfo.new(.18),{Position=UDim2.fromOffset(indexWatch.enabled and 31 or 3,3)}):Play()
    end
    for _,area in ipairs(areaList) do
        local row=make("TextButton",{Name=area.id,Text="",Size=UDim2.fromOffset(236,55),BackgroundColor3=C.side,BorderSizePixel=0,LayoutOrder=area.rank},areas)
        round(row,8)
        local mark=text(row,"",10,15,30,22,12,C.mint,true)
        text(row,area.name,42,7,183,21,12,C.text,true)
        local count=text(row,"",42,30,182,18,10,C.muted)
        buttons[area.id]={row=row,mark=mark,count=count}
        connect(row.Activated,function()
            indexWatch.areas[area.id]=not indexWatch.areas[area.id]
            controller.changed()
        end)
    end
    local function selectTargets(value: boolean)
        for _,area in ipairs(areaList) do
            if indexWatch.areas[area.id] then
                local choices: {[string]: boolean}={}
                if not value then
                    for _,drop in ipairs(area.config.DropTable or {}) do choices[drop[1]]=false end
                end
                indexWatch.options.targets[area.id]=choices
            end
        end
        controller.changed()
    end
    connect(all.Activated,function()for _,a in ipairs(areaList)do indexWatch.areas[a.id]=true end;controller.changed()end)
    connect(none.Activated,function()table.clear(indexWatch.areas);controller.changed()end)
    connect(targetAll.Activated,function()selectTargets(true)end)
    connect(targetNone.Activated,function()selectTargets(false)end)
    connect(strategy.Activated,function()
        local current=indexWatch.options.strategy
        indexWatch.options.strategy=current=="income" and "nearest" or (current=="nearest" and "rarity" or "income")
        controller.changed()
    end)
    connect(completion.Activated,function()
        indexWatch.options.completion=indexWatch.options.completion=="train" and "stop" or "train"
        controller.changed()
    end)
    connect(toggle.Activated,function()controller.setEnabled(not indexWatch.enabled)end)
    connect(gui:GetAttributeChangedSignal("IndexEnabled"),paint)
    paint()
    return function(data: IndexViewPlan?)
        status.Text=indexWatch.message
        local mode=indexWatch.options.strategy
        strategy.Text="Collect: "..(mode=="nearest" and "Nearest first" or (mode=="rarity" and "Rarest first" or "Highest income first"))
        completion.Text="When complete: "..(indexWatch.options.completion=="stop" and "Turn off Index only" or "Keep training")
        if not data then progress.Text="Waiting for Index data...";return end
        progress.Text="Selected targets: "..data.found.." / "..data.total.."   |   "..data.missing.." missing   |   Whole areas: "..data.collectionFound.." / "..data.collectionTotal
        local parts={}
        for _,row in ipairs(data.areas) do
            local b=buttons[row.id]
            b.row.BackgroundColor3=row.selected and C.selected or C.side
            b.mark.Text=row.selected and "ON" or "OFF"
            b.count.Text=row.found.." / "..row.total.." discovered"
            if row.selected then
                table.insert(parts,row.id)
                for _,pet in ipairs(row.missing)do table.insert(parts,pet.category..":"..pet.state..":"..tostring(pet.selected))end
            end
        end
        local key=table.concat(parts,"|")
        if key==lastKey then return end
        lastKey=key
        clearCards()
        local count=0
        for _,row in ipairs(data.areas)do if row.selected then
            for _,pet in ipairs(row.missing)do
                count+=1
                local card=make("TextButton",{Text="",AutoButtonColor=false,Size=UDim2.fromOffset(525,65),BackgroundColor3=pet.selected and C.selected or C.side,BorderSizePixel=0,LayoutOrder=count},missing)
                round(card,8)
                make("ImageLabel",{Position=UDim2.fromOffset(8,8),Size=UDim2.fromOffset(48,48),Image=pet.icon,BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},card)
                text(card,pet.name,68,7,292,21,13,C.text,true)
                local rarity,color=petRarity(pet.category)
                text(card,row.name.." / "..rarity,68,33,292,18,10,color)
                text(card,pet.selected and "INCLUDED" or "SKIPPED",367,7,150,20,10,pet.selected and C.mint or C.muted,true)
                text(card,pet.selected and pet.state or "Tap to include",367,33,150,18,9,C.muted)
                table.insert(cardConnections,card.Activated:Connect(function()
                    local choices=indexWatch.options.targets[row.id] or {}
                    choices[pet.category]=not pet.selected
                    indexWatch.options.targets[row.id]=choices
                    controller.changed()
                end))
            end
        end end
        if count==0 then
            text(missing,data.selected==0 and "Choose one or more areas." or "Selected areas are fully discovered.",10,10,512,40,14,C.muted)
        end
    end
end


-- Session-only counters: no inventory identities or player information are retained.
type OverviewEvent = {kind: string, message: string, at: number, repeated: number}
type OverviewSnapshot = {trips: number, drops: number, replans: number, waitSeconds: number, revision: number, events: {OverviewEvent}}
type OverviewLedger = {
    record: (string, string) -> (),
    waiting: (boolean) -> (),
    read: () -> OverviewSnapshot,
}
local function createOverviewLedger(clock: () -> number): OverviewLedger
    local started=clock()
    local events: {OverviewEvent}={}
    local trips,drops,replans,waitSeconds,revision=0,0,0,0,0
    local waitingSince: number?=nil
    local api: OverviewLedger={} :: any
    function api.record(kind: string,message: string): ()
        if kind=="trip" then trips+=1 elseif kind=="drop" then drops+=1 elseif kind=="replan" then replans+=1 end
        local now=math.max(0,clock()-started)
        local recent=events[1]
        if recent and recent.kind==kind and recent.message==message and now-recent.at<3 then
            recent.repeated+=1;recent.at=now
        else
            table.insert(events,1,{kind=kind,message=message,at=now,repeated=1})
            if #events>20 then table.remove(events) end
        end
        revision+=1
    end
    function api.waiting(on: boolean): ()
        local now=clock()
        if on and waitingSince==nil then waitingSince=now
        elseif not on and waitingSince~=nil then waitSeconds+=math.max(0,now-waitingSince);waitingSince=nil end
    end
    function api.read(): OverviewSnapshot
        return {trips=trips,drops=drops,replans=replans,
            waitSeconds=waitSeconds+(waitingSince and math.max(0,clock()-waitingSince) or 0),
            revision=revision,events=events}
    end
    return api
end

type OverviewAPI = {record: (string,string) -> ()}
function UI.CreateOverviewPage(ctx: OverviewViewContext,page: Frame): OverviewAPI
    local configStore,gui=ctx.configStore,ctx.gui
    local connect,panel=ctx.connect,ctx.panel
    local ledger=createOverviewLedger(os.clock)
    local notifications=configStore.data.notifications~=false
    gui:SetAttribute("NotificationsEnabled",notifications)
    text(page,"OVERVIEW",22,16,550,33,25,C.text,true)
    text(page,"See what is running, what comes next and why it is waiting.",23,55,820,20,12,C.muted)
    text(page,"NOTIFY",694,29,88,18,10,C.muted,true)
    local notifySwitch=make("TextButton",{Name="NotificationsToggle",Text="",Position=UDim2.fromOffset(804,22),Size=UDim2.fromOffset(64,36),BorderSizePixel=0,AutoButtonColor=false},page) :: TextButton
    round(notifySwitch,18)
    local notifyDot=make("Frame",{Name="Knob",Size=UDim2.fromOffset(30,30),BackgroundColor3=C.text,BorderSizePixel=0},notifySwitch) :: Frame
    round(notifyDot,15)
    local function paintSwitch(): ()
        notifySwitch.BackgroundColor3=notifications and C.selected or Color3.fromRGB(67,62,79)
        notifyDot.Position=UDim2.fromOffset(notifications and 31 or 3,3)
    end
    paintSwitch()
    local activity=section(page,"OverviewActivity",22,90,848,144,"")
    local nowTitle=text(activity,"NOW",16,15,94,18,10,C.mint,true)
    local current=text(activity,"Ready",118,12,714,28,17,C.text,true)
    text(activity,"NEXT",16,54,94,18,10,C.muted,true)
    local nextLabel=text(activity,"Enable a feature to begin.",118,52,714,27,12,C.text)
    text(activity,"DETAIL",16,94,94,18,10,C.muted,true)
    local reason=text(activity,"Your settings are saved automatically.",118,88,714,43,11,C.muted)
    reason.TextWrapped=true;reason.TextTruncate=Enum.TextTruncate.None;reason.TextYAlignment=Enum.TextYAlignment.Top
    local counters: {TextLabel}={}
    for i,caption in ipairs({"EGGS DELIVERED","EGGS DROPPED","ROUTES RETRIED","TIME WAITING"}) do
        local card=section(page,"OverviewCounter"..i,22+(i-1)*217,246,197,70,caption)
        counters[i]=text(card,"0",16,32,165,30,23,C.text,true)
    end
    local history=section(page,"OverviewHistory",22,330,848,164,"RECENT ACTIVITY")
    text(history,"This session  /  Latest 20 events",568,13,264,18,10,C.muted)
    local historyList=scrolling(history,16,39,816,112)
    local historyRows: {TextLabel}={}
    for i=1,20 do
        local row=text(historyList,"",0,0,798,26,11,C.muted)
        row.LayoutOrder=i;row.Visible=false
        table.insert(historyRows,row)
    end
    section(page,"OverviewPriority",22,510,848,90,"FEATURE PRIORITY  /  LEFT RUNS FIRST")
    text(page,"Notifications only show important results and errors. Counters reset when this script restarts.",23,604,847,16,9,C.muted)

    -- A single bounded queue keeps notifications from covering the game screen.
    local toast=make("Frame",{Name="OverviewNotification",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-18,1,-20),Size=UDim2.new(1,-36,0,88),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false,ZIndex=30},gui) :: Frame
    make("UISizeConstraint",{MaxSize=Vector2.new(350,88)},toast)
    round(toast,12);border(toast,C.mint)
    local toastTitle=text(toast,"EGG ATLAS",16,11,310,20,11,C.mint,true);toastTitle.ZIndex=31
    local toastMessage=text(toast,"",16,36,310,42,12,C.text);toastMessage.ZIndex=31
    toastTitle.Size=UDim2.new(1,-32,0,20);toastMessage.Size=UDim2.new(1,-32,0,42)
    toastMessage.TextWrapped=true;toastMessage.TextTruncate=Enum.TextTruncate.None;toastMessage.TextYAlignment=Enum.TextYAlignment.Top
    local queue: {{kind: string,message: string}}={}
    local toastActive=false
    local lastNotification,lastNotificationAt="",-math.huge
    local function showNext(): ()
        if not ctx.isAlive() or not notifications or toastActive then return end
        local item=table.remove(queue,1)
        if not item then return end
        toastActive=true;toast.Visible=true
        toastTitle.Text=item.kind=="error" and "NEEDS ATTENTION" or "EGG ATLAS"
        toastMessage.Text=item.message
        task.delay(5,function()
            if not ctx.isAlive() then return end
            toast.Visible=false;toastActive=false;showNext()
        end)
    end
    connect(notifySwitch.Activated,function()
        notifications=not notifications
        gui:SetAttribute("NotificationsEnabled",notifications)
        configStore.request();paintSwitch()
        if not notifications then table.clear(queue);toast.Visible=false end
    end)
    local dirty,lastHistory=true,-1
    local api: OverviewAPI={} :: any
    function api.record(kind: string,message: string): ()
        if not ctx.isAlive() then return end
        ledger.record(kind,message);dirty=true
        if not notifications or (kind~="event" and kind~="collection" and kind~="error") then return end
        local key=kind..":"..message
        if key==lastNotification and os.clock()-lastNotificationAt<20 then return end
        lastNotification=key;lastNotificationAt=os.clock()
        if #queue>=3 then table.remove(queue,1) end
        table.insert(queue,{kind=kind,message=message});showNext()
    end
    local currentText,nextText,detailText="Ready","Enable a feature to begin.","Your settings are saved automatically."
    local function attribute(name: string): string
        local value=gui:GetAttribute(name)
        return type(value)=="string" and value or ""
    end
    local function syncStatus(): ()
        local owner=attribute("AutomationOwner")
        local anyEnabled=gui:GetAttribute("AreaWatchEnabled") or gui:GetAttribute("RiftActive") or gui:GetAttribute("IndexEnabled") or gui:GetAttribute("EventEnabled")
        local eventBusy=gui:GetAttribute("EventBusy")==true
        local runnerBusy=gui:GetAttribute("RunnerActive")==true
        local anyBusy=eventBusy or runnerBusy or gui:GetAttribute("AreaWatchBusy")==true or gui:GetAttribute("IndexBusy")==true or gui:GetAttribute("RiftCommitting")==true
        local running=anyEnabled or anyBusy
        local function messagePhase(message: string,fallback: string): string
            local prefix=string.upper(message:match("^%s*([%a]+)") or "")
            local phases={CHECKING="Checking",COLLECTING="Collecting",COLLECTED="Complete",PLACING="Planting",HATCHING="Hatching",TRAINING="Training",WAITING="Waiting",LOADING="Loading",RETRYING="Retrying",COMPLETE="Complete",FINISHING="Finishing",OFF="Off",SELECT="Waiting"}
            return phases[prefix] or fallback
        end
        if eventBusy then owner="Event" end
        local phase,message="",""
        if not running then owner=""
        elseif owner=="Event" then phase=attribute("EventPhase");message=attribute("EventMessage")
        elseif runnerBusy then
            phase=attribute("RunnerPhase");message=attribute("RunnerMessage")
            if owner=="" then owner="Collection" end
        elseif owner=="Index" then message=attribute("IndexMessage");phase=messagePhase(message,"Checking")
        elseif owner=="Area" then message=attribute("AreaWatchMessage");phase=messagePhase(message,"Checking")
        elseif owner=="Rift" or gui:GetAttribute("RiftActive") then owner="Rift";phase=attribute("RiftPhase");message=attribute("RiftMessage")
        elseif gui:GetAttribute("IndexEnabled") then owner="Index";message=attribute("IndexMessage");phase=messagePhase(message,"Waiting")
        elseif gui:GetAttribute("AreaWatchEnabled") then owner="Area";message=attribute("AreaWatchMessage");phase=messagePhase(message,"Waiting")
        elseif gui:GetAttribute("EventEnabled") then owner="Event";phase="Waiting";message="Waiting for personal drones or the next event round." end
        if running and gui:GetAttribute("RiftTraining")==true and not eventBusy and not runnerBusy then phase="Training" end
        if running and gui:GetAttribute("AutomationWaitingForLoad")==true and not anyBusy then
            phase="Loading";message="Waiting for your character, inventory and plot."
        end
        local names={Area="Auto Area",Index="Auto Index",Event="DR Scramble",Rift="The Rift",Collection="Collection"}
        currentText=owner~="" and ((names[owner] or owner)..(phase~="" and "  /  "..phase or "")) or "Ready"
        local waitReason=running and attribute("WaitReason") or ""
        nextText=running and attribute("NextAction") or ""
        if eventBusy then
            nextText=(phase=="Leaving" or phase=="Returning safely" or phase=="Exit blocked")
                and "Return to the safe zone, then resume your enabled features."
                or "Finish this encounter, leave the arena, then resume your enabled features."
        elseif not anyEnabled and anyBusy then nextText="Finish the current task safely, then stop."
        elseif phase=="Training" and not anyBusy then nextText="Resume the first available task in your priority order."
        elseif owner=="Event" and phase=="Waiting" then nextText="Collect Samples when the next drone round opens."
        elseif phase=="Loading" and not anyBusy then nextText="Resume saved features when your character and plot are ready."
        elseif nextText=="" then nextText=anyEnabled and "Check the next available task in your priority order." or "Enable a feature to begin." end
        detailText=waitReason~="" and waitReason or message
        if detailText=="" then detailText="Your settings are saved automatically." end
        local waiting=running and (waitReason~="" or phase=="Waiting" or phase=="Training" or phase=="ResetWait" or phase=="Respawning" or phase=="Loading" or phase=="Retrying")
        ledger.waiting(waiting==true)
        nowTitle.Text=waiting and "WAITING" or "NOW"
        dirty=true
    end
    for _,name in ipairs({"AutomationOwner","RunnerActive","RunnerPhase","RunnerMessage","RiftPhase","RiftMessage","IndexMessage","AreaWatchMessage","EventPhase","EventMessage","EventBusy","AreaWatchBusy","IndexBusy","RiftCommitting","RiftTraining","AutomationWaitingForLoad","AreaWatchEnabled","RiftActive","IndexEnabled","EventEnabled","NextAction","WaitReason"}) do
        connect(gui:GetAttributeChangedSignal(name),syncStatus)
    end
    local function duration(seconds: number): string
        local value=math.floor(seconds)
        return value>=3600 and string.format("%dh %02dm",math.floor(value/3600),math.floor(value/60)%60)
            or string.format("%dm %02ds",math.floor(value/60),value%60)
    end
    local function paint(): ()
        if not page.Visible or not panel.Visible then return end
        local snapshot=ledger.read()
        if dirty then current.Text=currentText;nextLabel.Text=nextText;reason.Text=detailText;dirty=false end
        counters[1].Text=tostring(snapshot.trips);counters[2].Text=tostring(snapshot.drops);counters[3].Text=tostring(snapshot.replans)
        counters[4].Text=duration(snapshot.waitSeconds)
        if snapshot.revision==lastHistory then return end
        lastHistory=snapshot.revision
        for i,row in ipairs(historyRows) do
            local event=snapshot.events[i]
            row.Visible=event~=nil
            if event then
                row.Text=duration(event.at).."  /  "..event.message..(event.repeated>1 and "  ("..event.repeated..")" or "")
                row.TextColor3=event.kind=="error" and Color3.fromRGB(244,132,154) or C.muted
            end
        end
        if #snapshot.events==0 then historyRows[1].Visible=true;historyRows[1].Text="Your next completed task will appear here." end
    end
    connect(page:GetPropertyChangedSignal("Visible"),paint)
    connect(panel:GetPropertyChangedSignal("Visible"),paint)
    syncStatus()
    task.spawn(function()
        while ctx.isAlive() do paint();task.wait(.5) end
    end)
    return api
end



function UI.CreateWindow(parent: Instance,version: string)
local gui = make("ScreenGui", {
    Name = "EggAtlasUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 80,
}, parent)
gui:SetAttribute("Version", version)
local panel = make("Frame", {
    Name = "Window", Size = UDim2.fromOffset(1120, 736), BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui) :: Frame
round(panel, 16)
border(panel)
local uiScale = make("UIScale", {}, panel)
    return {gui=gui,panel=panel,uiScale=uiScale}
end

function UI.MountWindow(ctx: any,window: any)
local gui,panel,uiScale=window.gui,window.panel,window.uiScale
local configStore,connect,Input=ctx.configStore,ctx.connect,ctx.Input
local dragging=false
local viewport=ctx.getViewport
local firstLayout = true
do
    local position=configStore.data.position
    local function finite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    if type(position)=="table" and finite(position.x) and finite(position.y) then
        panel.Position=UDim2.fromOffset(position.x,position.y)
        firstLayout=false
    end
end
local function fit()
    local v = viewport()
    uiScale.Scale = math.min(1, math.max(0.1, math.min((v.X - 24) / 1120, (v.Y - 24) / 736)))
    local w, h = 1120 * uiScale.Scale, 736 * uiScale.Scale
    local p = panel.Position
    local x = firstLayout and (v.X - w) / 2 or p.X.Offset
    local y = firstLayout and (v.Y - h) / 2 or p.Y.Offset
    panel.Position = UDim2.fromOffset(math.clamp(x, 8, math.max(8, v.X - w - 8)),
        math.clamp(y, 8, math.max(8, v.Y - h - 8)))
    firstLayout = false
end
fit()
local header = make("Frame", {
    Name = "DragHandle", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(1040, 72),
    BackgroundTransparency = 1, Active = true,
}, panel)
text(header, "EGG ATLAS", 24, 14, 260, 28, 23, C.text, true)
text(header, "COLLECTION  /  EVENTS  /  PROGRESS", 25, 45, 360, 18, 10, C.muted, true)
local live = text(header, "LIVE", 934, 25, 106, 22, 10, C.mint, true)
do
    local label=text(header,configStore.status,910,48,130,16,9,C.muted,true)
    label.Name="ConfigStatus"
    connect(gui:GetAttributeChangedSignal("ConfigStatus"),function()
        label.Text=gui:GetAttribute("ConfigStatus") or "CONFIG"
        label.TextColor3=label.Text:find("ERROR",1,true) and Color3.fromRGB(244,132,154) or C.muted
    end)
end
local close = button(panel, "X", 1064, 23, 34, 32)
local featureNav=make("Frame",{Name="FeatureNav",Position=UDim2.fromOffset(14,80),Size=UDim2.fromOffset(178,624),BackgroundColor3=C.side,BorderSizePixel=0},panel)
round(featureNav,12);border(featureNav)
text(featureNav,"WORKSPACE",16,10,146,18,11,C.text,true)
text(featureNav,"COLLECTION",16,32,146,16,9,C.muted,true)
text(featureNav,"EVENTS",16,306,146,16,9,C.muted,true)
text(featureNav,"PROGRESS",16,456,146,16,9,C.muted,true)
make("Frame",{Name="FooterDivider",Position=UDim2.fromOffset(16,546),Size=UDim2.fromOffset(146,1),BackgroundColor3=C.edge,BorderSizePixel=0},featureNav)
text(featureNav,"v"..tostring(gui:GetAttribute("Version")),16,554,146,16,10,C.muted)
text(featureNav,"LEFT ALT  /  HIDE UI",16,575,148,18,10,C.mint,true)
text(featureNav,"Drag the header to move",16,598,148,16,9,C.muted)
local function setVisible(visible)
    panel.Visible = visible
    dragging = false
end
connect(close.Activated, function() gui:Destroy() end)
connect(gui.Destroying, function()
    dragging=false
    ctx.onDestroy()
end)
local dragStart, startPosition, touch
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPosition = true, input.Position, panel.Position
        touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
    end
end)
connect(Input.InputChanged, function(input)
    if not dragging then return end
    if (touch and input ~= touch) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
    local delta, v = input.Position - dragStart, viewport()
    panel.Position = UDim2.fromOffset(
        math.clamp(startPosition.X.Offset + delta.X, 8, math.max(8, v.X - 1120 * uiScale.Scale - 8)),
        math.clamp(startPosition.Y.Offset + delta.Y, 8, math.max(8, v.Y - 736 * uiScale.Scale - 8)))
end)
connect(Input.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch then dragging = false; touch = nil end
end)
connect(Input.WindowFocusReleased, function() dragging = false; touch = nil end)
connect(Input.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.LeftAlt then setVisible(not panel.Visible) end
end)
    return {fit=fit,header=header,close=close,featureNav=featureNav,live=live}
end

function UI.CreatePages(ctx: any)
    local gui,panel,header,close=ctx.gui,ctx.panel,ctx.header,ctx.close
    local watchPanel,featureNav,connect=ctx.watchPanel,ctx.featureNav,ctx.connect
    local purple=Color3.fromRGB(185,151,255)
    local areaPage=make("Frame",{Name="AreaPage",Position=UDim2.fromOffset(196,0),Size=UDim2.fromOffset(920,720),BackgroundTransparency=1},panel)
    for _,v in ipairs(panel:GetChildren()) do
        if v:IsA("GuiObject") and v~=areaPage and v~=header and v~=close and v~=watchPanel and v~=featureNav then v.Parent=areaPage end
    end
    local page=make("Frame",{Name="RiftPage",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel)
    round(page,12)
    local function featureTab(name,title,description,y)
        local b=button(featureNav,"",10,y,158,54);b.Name=name
        text(b,title,14,8,130,21,13,C.text,true).Name="Title"
        text(b,description,14,31,130,16,9,C.muted).Name="Description"
        local marker=make("Frame",{Name="SelectionMarker",Position=UDim2.fromOffset(0,9),Size=UDim2.fromOffset(3,36),BackgroundColor3=C.mint,BorderSizePixel=0,Visible=false},b)
        round(marker,2)
        return b
    end
    local overviewPage=make("Frame",{Name="OverviewPage",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel) :: Frame
    round(overviewPage,12)
    local overviewTab=featureTab("OverviewTab","OVERVIEW","Activity and priorities",54)
    local areaTab=featureTab("AreasTab","AREAS","One-click collection",116)
    local autoTab=featureTab("AutoAreaTab","AUTO AREA","Area and rarity filters",178)
    local riftTab=featureTab("RiftTab","THE RIFT","Collect, hatch, combine",328)
    local eventPage=make("Frame",{Name="EventPage",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel)
    round(eventPage,12)
    local eventTab=featureTab("EventTab","DR SCRAMBLE","Drones and Samples",390)
    local statsPage=make("Frame",{Name="StatsEggsPage",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel) :: Frame
    round(statsPage,12)
    local statsTab=featureTab("StatsEggsTab","STATS EGGS","Hatching and income",478)
    local indexPage=make("Frame",{Name="IndexPage",Position=UDim2.fromOffset(210,80),Size=UDim2.fromOffset(892,624),BackgroundColor3=C.side,BorderSizePixel=0,Visible=false},panel) :: Frame
    round(indexPage,12)
    local indexTab=featureTab("IndexTab","AUTO INDEX","Complete collections",240)
    local function showEnabledTabs()
        indexTab.Title.TextColor3=gui:GetAttribute("IndexEnabled") and C.mint or C.text
        eventTab.Title.Text=gui:GetAttribute("EventEnabled") and "DR SCRAMBLE  •" or "DR SCRAMBLE"
        eventTab.Title.TextColor3=gui:GetAttribute("EventEnabled") and purple or C.text
        autoTab.Title.Text=gui:GetAttribute("AreaWatchEnabled") and "AUTO AREA  •" or "AUTO AREA"
        riftTab.Title.Text=gui:GetAttribute("RiftActive") and "THE RIFT  •" or "THE RIFT"
        autoTab.Title.TextColor3=gui:GetAttribute("AreaWatchEnabled") and C.mint or C.text
        riftTab.Title.TextColor3=gui:GetAttribute("RiftActive") and purple or C.text
    end
    connect(gui:GetAttributeChangedSignal("AreaWatchEnabled"),showEnabledTabs)
    connect(gui:GetAttributeChangedSignal("RiftActive"),showEnabledTabs)
    connect(gui:GetAttributeChangedSignal("EventEnabled"),showEnabledTabs)
    connect(gui:GetAttributeChangedSignal("IndexEnabled"),showEnabledTabs)
    showEnabledTabs()
    local function tab(name)
        areaPage.Visible=name=="Areas";watchPanel.Visible=name=="AutoArea";page.Visible=name=="Rift"
        eventPage.Visible=name=="Event"
        statsPage.Visible=name=="StatsEggs"
        indexPage.Visible=name=="Index"
        overviewPage.Visible=name=="Overview"
        overviewTab.BackgroundColor3=name=="Overview" and C.selected or C.card
        overviewTab.SelectionMarker.Visible=name=="Overview"
        indexTab.BackgroundColor3=name=="Index" and C.selected or C.card
        indexTab.SelectionMarker.Visible=name=="Index"
        statsTab.BackgroundColor3=name=="StatsEggs" and C.selected or C.card
        statsTab.SelectionMarker.Visible=name=="StatsEggs"
        eventTab.BackgroundColor3=name=="Event" and C.selected or C.card
        eventTab.SelectionMarker.Visible=name=="Event"
        areaTab.BackgroundColor3=name=="Areas" and C.selected or C.card
        autoTab.BackgroundColor3=name=="AutoArea" and C.selected or C.card
        riftTab.BackgroundColor3=name=="Rift" and C.selected or C.card
        areaTab.SelectionMarker.Visible=name=="Areas"
        autoTab.SelectionMarker.Visible=name=="AutoArea"
        riftTab.SelectionMarker.Visible=name=="Rift"
        gui:SetAttribute("ActiveTab",name)
    end
    connect(overviewTab.Activated,function()tab("Overview")end)
    connect(areaTab.Activated,function()tab("Areas")end)
    connect(autoTab.Activated,function()tab("AutoArea")end)
    connect(riftTab.Activated,function()tab("Rift")end)
    connect(eventTab.Activated,function()tab("Event")end)
    connect(statsTab.Activated,function()tab("StatsEggs")end)
    connect(indexTab.Activated,function()tab("Index")end)
    local savedTab=ctx.savedTab
    if ctx.savedTab=="Boss" then ctx.savedTab="Event" end
    local validTabs={Overview=true,Areas=true,AutoArea=true,Rift=true,Event=true,StatsEggs=true,Index=true}
    tab(validTabs[savedTab] and savedTab or "Overview")
    return {
        areaPage=areaPage,page=page,overviewPage=overviewPage,eventPage=eventPage,
        statsPage=statsPage,indexPage=indexPage,select=tab,
        tabs={Overview=overviewTab,Areas=areaTab,AutoArea=autoTab,Rift=riftTab,Event=eventTab,StatsEggs=statsTab,Index=indexTab},
    }
end

UI.Theme=C
UI.Make=make
UI.Text=text
UI.Button=button
UI.Round=round
UI.Border=border
UI.Section=section
UI.Scrolling=scrolling
return UI
