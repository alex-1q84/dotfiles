local drawing = require "hs.drawing"
local uielement = require "hs.uielement"
local watcher = uielement.watcher
local fnutils = require "hs.fnutils"
local timer = require "hs.timer"
local application = require "hs.application"
local appwatcher = application.watcher
local appfinder = require "hs.appfinder"



local tabs = {}

tabs.DRAW_TABS = true
tabs.leftPad = 10
tabs.topPad = 2
tabs.tabPad = 2
tabs.tabWidth = 80
tabs.tabHeight = 17
tabs.tabRound = 4
tabs.textLeftPad = 2
tabs.textTopPad = 2
tabs.textSize = 10
tabs.fillColor = {red = 1.0, green = 1.0, blue = 1.0, alpha = 0.5}
tabs.selectedColor = {red = .9, green = .9, blue = .9, alpha = 0.5}
tabs.strokeColor = {red = 0.0, green = 0.0, blue = 0.0, alpha = 0.7}
tabs.textColor = {red = 0.0, green = 0.0, blue = 0.0, alpha = 0.6}
tabs.maxTitle = 11

local function realWindow(win)
  -- AXScrollArea is weird role of special finder desktop window
  return (win:isStandard() and win:role() ~= "AXScrollArea")
end

function tabs.tabWindows(app)
  local tabWins = fnutils.filter(app:allWindows(),realWindow)
  table.sort(tabWins, function(a,b) return a:title() < b:title() end)
  return tabWins
end

local drawTable = {}
local function trashTabs(pid)
  local tab = drawTable[pid]
  if not tab then return end
  for i,obj in ipairs(tab) do
    obj:delete()
  end
end
local function drawTabs(app)
  local pid = app:pid()
  trashTabs(pid)
  drawTable[pid] = {}
  local proto = app:focusedWindow()
  if not proto or not app:isFrontmost() then return end
  local geom = app:focusedWindow():frame()

  local tabWins = tabs.tabWindows(app)
  local pt = {x = geom.x+geom.w-tabs.leftPad, y = geom.y+tabs.topPad}
  local objs = drawTable[pid]
  -- iterate in reverse order because we draw right to left
  local numTabs = #tabWins
  for i=0,(numTabs-1) do
    local win = tabWins[numTabs-i]
    pt.x = pt.x - tabs.tabWidth - tabs.tabPad
    local r = drawing.rectangle({x=pt.x,y=pt.y,w=tabs.tabWidth,h=tabs.tabHeight})
    r:setFill(true)
    if win == proto then
      r:setFillColor(tabs.selectedColor)
    else
      r:setFillColor(tabs.fillColor)
    end
    r:setStrokeColor(tabs.strokeColor)
    r:setRoundedRectRadii(tabs.tabRound,tabs.tabRound)
    r:bringToFront()
    r:show()
    table.insert(objs,r)
    local tabText = win:title():sub(1,tabs.maxTitle)
    local t = drawing.text({x=pt.x+tabs.textLeftPad,y=pt.y+tabs.textTopPad,
                            w=tabs.tabWidth,h=tabs.tabHeight},tabText)
    t:setTextSize(tabs.textSize)
    t:setTextColor(tabs.textColor)
    t:show()
    table.insert(objs,t)
  end
end

local function reshuffle(app)
  -- print("Resizing " .. app:title())
  local proto = app:focusedWindow()
  if not proto then return end
  local geom = app:focusedWindow():frame()
  for i,win in ipairs(app:allWindows()) do
    if win:isStandard() then
      win:setFrame(geom)
    end
  end
  drawTabs(app)
end

local function manageWindow(win, app)
  if not win:isStandard() then return end
  -- only trigger on focused window movements otherwise the reshuffling triggers itself
  local newWatch = win:newWatcher(function(el,ev,wat,ud) if el == app:focusedWindow() then reshuffle(app) end end)
  newWatch:start({watcher.windowMoved, watcher.windowResized, watcher.elementDestroyed})
  local redrawWatch = win:newWatcher(function (el,ev,wat,ud) drawTabs(app) end)
  redrawWatch:start({watcher.elementDestroyed, watcher.titleChanged})

  -- resize this window to match possible others
  local notThis = fnutils.filter(app:allWindows(), function(x) return (x ~= win and realWindow(x)) end)
  local protoWindow = notThis[1]
  if protoWindow then
    print("Prototyping to '" .. protoWindow:title() .. "'")
    win:setFrame(protoWindow:frame())
  end
end

local function watchApp(app)
  -- print("Enabling tabs for " .. app:title())
  for i,win in ipairs(app:allWindows()) do
    manageWindow(win,app)
  end
  local winWatch = app:newWatcher(function(el,ev,wat,appl) manageWindow(el,appl) end,app)
  winWatch:start({watcher.windowCreated})
  local redrawWatch = app:newWatcher(function (el,ev,wat,ud) drawTabs(app) end)
  redrawWatch:start({watcher.applicationActivated, watcher.applicationDeactivated,
                     watcher.applicationHidden, watcher.focusedWindowChanged})

  reshuffle(app)
end

local appWatcherStarted = false
local appWatches = {}
function tabs.enableForApp(appName)
  appWatches[appName] = true

  -- might already be running
  local runningApp = appfinder.appFromName(appName)
  if runningApp then
    watchApp(runningApp)
  end

  -- set up a watcher to catch any watched app launching or terminating
  if appWatcherStarted then return end
  appWatcherStarted = true
  local watch = appwatcher.new(function(name,event,app)
      -- print("Event from " .. name)
      if event == appwatcher.launched and appWatches[name] then
        watchApp(app)
      elseif event == appwatcher.terminated then
        trashTabs(app:pid())
      end
  end)
  watch:start()
end

function tabs.focusTab(app,num)
  if not app or not appWatches[app:title()] then return end
  local tabs = tabs.tabWindows(app)
  local bounded = num
  print(hs.inspect(tabs))
  if num > #tabs then
    bounded = #tabs
  end
  tabs[bounded]:focus()
end

return tabs
