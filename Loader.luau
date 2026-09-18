if game.PlaceId ~= 107778070777162 then return end

-- EGG ATLAS 11.30.1 | Public/private GitHub loader.
-- Run this loader locally. Upload Main.luau and UI.luau to the selected repository.
-- Keep the token in the local TokenFile; never put it in a repository or a URL.
local GITHUB={
    Private=false,
    Owner="SitXz120",
    Repo="Steel",
    Ref="main",
    Folder="", -- Empty when Main.luau and UI.luau are at the repository root.
    TokenFile="EggAtlas-GitHub.token",
}
local VERSION="11.30.1"
local token: string?=nil

local function redact(value: any): string
    local message=tostring(value)
    if not token then return message end
    local parts={};local from=1
    while true do
        local a,b=message:find(token,from,true)
        if not a then table.insert(parts,message:sub(from));break end
        table.insert(parts,message:sub(from,a-1));table.insert(parts,"[REDACTED]");from=b+1
    end
    return table.concat(parts)
end

local function fail(stage: string,detail: any)
    error("EGG ATLAS / "..stage..": "..redact(detail),0)
end
if GITHUB.Owner=="YOUR_NAME" or GITHUB.Repo=="YOUR_REPO" then
    fail("setup","Set GITHUB.Owner and GITHUB.Repo in Loader.luau first.")
end
if not GITHUB.Owner:match("^[%w%-]+$") or not GITHUB.Repo:match("^[%w%._%-]+$")
    or GITHUB.Repo=="." or GITHUB.Repo==".." then
    fail("setup","Owner and Repo must be GitHub names, not URLs or paths.")
end
if GITHUB.Ref=="" or GITHUB.Ref:find("[%c]") then fail("setup","Ref must be a branch, tag or commit SHA.")end
local folder=GITHUB.Folder:gsub("^/+",""):gsub("/+$","")
for part in folder:gmatch("[^/]+")do
    if part=="." or part==".." or part:find("[%c\\]")then fail("setup","Folder must be a repository folder path.")end
end
local function encode(value: string): string
    return (value:gsub("[^%w%-%._~]",function(char)return string.format("%%%02X",string.byte(char))end))
end
local function encodedPath(name: string): string
    local path=folder~="" and (folder.."/"..name) or name
    local parts={}
    for part in path:gmatch("[^/]+")do table.insert(parts,encode(part))end
    return table.concat(parts,"/")
end
local requestFn=type(request)=="function" and request or http_request
if GITHUB.Private then
    if type(requestFn)~="function" then fail("setup","Private mode needs request or http_request support.")end
    if type(readfile)~="function" then fail("token file","Private mode needs readfile support.")end
    local ok,value=pcall(readfile,GITHUB.TokenFile)
    if not ok or type(value)~="string" then fail("token file","Create the local file "..GITHUB.TokenFile.." containing your GitHub token.")end
    value=value:gsub("^\239\187\191",""):match("^%s*(.-)%s*$") or ""
    if value=="" then fail("token file","The local token file is empty.")end
    if not value:match("^[%w_]+$") then fail("token file","The file must contain only the token, without quotes, spaces or a Bearer prefix.")end
    token=value
end
local function download(name: string): string
    local path=encodedPath(name)
    if not GITHUB.Private then
        local url="https://raw.githubusercontent.com/"..GITHUB.Owner.."/"..GITHUB.Repo.."/"..encode(GITHUB.Ref).."/"..path
        local ok,value=pcall(function()return game:HttpGet(url)end)
        if not ok then fail("download "..name,"Could not download the public file. Check repository, ref, folder and network.")end
        if type(value)~="string" or value=="" then fail("download "..name,"The response was empty or was not text.")end
        return value
    end
    local url="https://api.github.com/repos/"..GITHUB.Owner.."/"..GITHUB.Repo.."/contents/"..path.."?ref="..encode(GITHUB.Ref)
    local ok,response=pcall(requestFn,{
        Url=url,Method="GET",Headers={
            Authorization="Bearer "..assert(token),Accept="application/vnd.github.raw+json",
            ["X-GitHub-Api-Version"]="2026-03-10",["User-Agent"]="EggAtlas",
        },
    })
    -- Transport errors/bodies can contain request headers; report fixed messages only.
    if not ok or type(response)~="table" then fail("download "..name,"GitHub request failed. Check the network and request support.")end
    local status=tonumber(response.StatusCode)
    if status~=200 then
        local reasons={
            [401]="GitHub rejected the token. Check whether it expired or was revoked.",
            [403]="GitHub denied access or applied a rate limit. Check Contents: Read-only and repository/organization access.",
            [404]="File not found or not accessible. Check Owner, Repo, Ref, Folder and the token's selected repository.",
            [429]="GitHub rate limit reached. Wait before retrying.",
        }
        fail("download "..name,reasons[status or 0] or ("GitHub returned HTTP "..tostring(status or "unknown")..". No code was started."))
    end
    if type(response.Body)~="string" or response.Body=="" then fail("download "..name,"GitHub returned an empty or invalid file.")end
    if token and response.Body:find(token,1,true) then fail("download "..name,"Response contained authentication data; refusing to cache or execute it.")end
    return response.Body
end
local function compile(source: string,name: string)
    local ok,chunk,err=pcall(loadstring,source,name)
    if not ok then fail("compile "..name,chunk)end
    if not chunk then fail("compile "..name,err)end
    return chunk
end

-- Complete both downloads and syntax checks before creating or replacing any UI.
local uiSource=download("UI.luau")
local mainSource=download("Main.luau")
local loadUI=compile(uiSource,"UI.luau")
local runMain=compile(mainSource,"Main.luau")
local uiOK,UI=pcall(loadUI)
if not uiOK then fail("initialize UI module",UI)end
if type(UI)~="table" or UI.ApiVersion~=1 or UI.Version~=VERSION then
    fail("UI compatibility","UI.luau and Main.luau must both be version "..VERSION.." (UI API 1).")
end

-- Server Hop reads this local bootstrap. It contains both downloaded files so a
-- hop can resume the same release without another HTTP request.
local bootstrap=string.format([=[
if game.PlaceId ~= 107778070777162 then return end

-- EGG ATLAS cached GitHub release. Both module sources are stored locally.
local uiSource=%q
local mainSource=%q
local version=%q
local loadUI=loadstring(uiSource,"EggAtlasCachedUI")
assert(loadUI,"EGG ATLAS / cached UI: compilation failed. Run the local Loader again.")
local runMain=loadstring(mainSource,"EggAtlasCachedMain")
assert(runMain,"EGG ATLAS / cached Main: compilation failed. Run the local Loader again.")
local uiOK,UI=pcall(loadUI)
assert(uiOK,"EGG ATLAS / cached UI: initialization failed. Run the local Loader again.")
assert(type(UI)=="table" and UI.ApiVersion==1 and UI.Version==version,"Cached UI module is incompatible")
local environment=type(getgenv)=="function" and getgenv() or _G
local previousTicket=environment.EggAtlasLaunch
local ok=pcall(runMain,UI)
if not ok then
    local ticket=environment.EggAtlasLaunch
    if ticket and ticket~=previousTicket and ticket.job==game.JobId and ticket.version==version and ticket.loading then
        environment.EggAtlasLaunch=nil
    end
    error("EGG ATLAS / cached Main: startup failed. Run the local Loader again.",0)
end
]=],uiSource,mainSource,VERSION)

if not game:IsLoaded() then game.Loaded:Wait() end
local players=game:GetService("Players")
while not players.LocalPlayer do players:GetPropertyChangedSignal("LocalPlayer"):Wait()end
local path="EggAtlas-Core-"..game.PlaceId.."-"..players.LocalPlayer.UserId..".luau"
if type(writefile)=="function" then
    local saved,err=pcall(writefile,path,bootstrap)
    if not saved then warn("EGG ATLAS / resume cache could not be saved:",redact(err))end
end
local environment=type(getgenv)=="function" and getgenv() or _G
local previousTicket=environment.EggAtlasLaunch
local ok,err=pcall(runMain,UI)
if not ok then
    local ticket=environment.EggAtlasLaunch
    if ticket and ticket~=previousTicket and ticket.job==game.JobId and ticket.version==VERSION and ticket.loading then
        environment.EggAtlasLaunch=nil
    end
    fail("start Main.luau",err)
end
