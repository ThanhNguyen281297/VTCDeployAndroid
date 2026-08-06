local UnityTime = UnityEngine.Time;
pcall(function()
  require "Logic/VtcMod"
end)

CGTimer = {};
local this = CGTimer;

this.serverTimeSpan = nil;
this.serverTime = nil;
this.serverStartTime = nil;
this.roleCreateTime = nil;
this.onlineTime = nil;  --每日在線時間(跨日歸零從新計算)

this.time = 0;
this.deltaTime = 0;
this.timeScaleEndTime = nil;

local listeners = {};
local delayFunctions = {};
local countDownFunctions = {};

function CGTimer.Initialize()
  this.deltaTime = 0;
  this.time = UnityTime.realtimeSinceStartup;  
end

function CGTimer.Update()
  if VtcMod then
    if not VtcMod.initialized then
      VtcMod.Init()
    end
    VtcMod.Update()
  end

  if this.serverTimeSpan ~= nil then
    this.serverTime = System.DateTime.Now:Add(this.serverTimeSpan);
  end
  
  this.deltaTime = UnityTime.realtimeSinceStartup - this.time;
  this.time = UnityTime.realtimeSinceStartup;
  
  if this.timeScaleEndTime ~= nil and this.timeScaleEndTime < this.time then
    this.timeScaleEndTime = nil;
    
    UnityTime.timeScale = 1;
  end
  
  for k, v in pairs(listeners) do
    if this.time >= v.time then
      v.time = this.time + v.interval;
      k();
    end
  end
  
  for k, v in pairs(delayFunctions) do
    if this.time >= v[1] then
      local func = v[2];
      table.remove(delayFunctions, k);

      func();
    end
  end

  for k, v in pairs(countDownFunctions) do
    if this.time >= v.time then
      local func = k;
      countDownFunctions[k] = nil;

      func();
    end
  end
end

function CGTimer.SetServerTime(d)
  this.serverTime = System.DateTime.FromOADate(d);
  this.serverTimeSpan = this.serverTime - System.DateTime.Now;
end

function CGTimer.SetOnlineTime(d)
  this.onlineTime = System.DateTime.FromOADate(d);
end

function CGTimer.SetServerStartTime(d)
  this.serverStartTime = System.DateTime.FromOADate(d);
end

function CGTimer.SetRoleCreateTime(d)
  this.roleCreateTime = System.DateTime.FromOADate(d);
end

function CGTimer.AddListener(listener, trigInterval, immediately)
  if listener == nil then return end
  
  if listeners[listener] == nil then
    listeners[listener] = {};
  end
  
  if immediately == nil or immediately then
    listeners[listener].time = 0;
  else
    listeners[listener].time = this.time + trigInterval;
  end
  
  listeners[listener].interval = trigInterval;
end

function CGTimer.RemoveListener(listener)
  if listener == nil then return end

  listeners[listener] = nil;
end

function CGTimer.ContainsListener(listener)
  if listener == nil then return end

  return listeners[listener] ~= nil;
end

function CGTimer.DoFunctionDelay(delayTime, doFunction)
  table.insert(delayFunctions, { this.time + delayTime, doFunction });
end

function CGTimer.RemoveFunctionDelay(doFunction)
  for k, v in pairs(delayFunctions) do
    if doFunction == v[2] then
      table.remove(delayFunctions, k);
      break;
    end
  end
end

function CGTimer.DoCountdown(functionName, delayTime)
  if countDownFunctions[functionName] == nil then
    countDownFunctions[functionName] = {};
  end

  if countDownFunctions[functionName].time == nil then
    countDownFunctions[functionName].time = this.time + delayTime;
  else
    countDownFunctions[functionName].time = this.time + delayTime;
  end
end

function CGTimer.GetDoCountdownTime(functionName)
  for k, v in pairs(countDownFunctions) do
    if k == functionName then
      return math.ceil(countDownFunctions[k].time - this.time);
    end
  end

  return 0;
end

function CGTimer.SetTimeScale(timeScale, duration)
  this.timeScaleEndTime = this.time + duration;
  
  UnityTime.timeScale = timeScale;
end