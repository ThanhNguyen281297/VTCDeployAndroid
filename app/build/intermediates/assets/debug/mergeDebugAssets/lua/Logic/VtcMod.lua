-- TS Online VTC - Writable Custom Overlay Injection Layer (Robust Memory Hooking)
VtcMod = {};
local this = VtcMod;

this.initialized = false;

-- DRM Verification State Variables
-- Note: License is verified at PC deploy level (ram_stream_deploy.ps1).
-- RAM Stream architecture protects scripts from extraction.
-- In-game DRM is bypassed since PC-side DRM is the authoritative check.
this.isLicensed = true
this.deviceId = nil
this.key1 = nil
this.drmDialogShown = false

-- Online Trial Verification Variables
this.trialApiUrl = "" -- DÁN URL CỦA GOOGLE APPS SCRIPT VÀO ĐÂY
this.trialWww = nil
this.isTrialExpired = false
this.trialDaysLeft = 0

-- Generates pure Lua Key 1 (Ma May) from raw Device ID using double DJB2/SDBM hashing
function VtcMod.GetHardwareCode(deviceId)
  if not deviceId or deviceId == "" then deviceId = "default_device_id" end
  
  -- Hash A (DJB2)
  local hashA = 5381
  for i = 1, #deviceId do
    local c = string.byte(deviceId, i)
    hashA = ((hashA * 33) + c) % 4294967296
  end
  
  -- Hash B (SDBM)
  local hashB = 0
  for i = 1, #deviceId do
    local c = string.byte(deviceId, i)
    hashB = (c + (hashB * 65599)) % 4294967296
  end
  
  local hexA = string.format("%08X", hashA)
  local hexB = string.format("%08X", hashB)
  
  -- Combine into 16-hex characters: e.g. A081B77132C6F09A
  local combined = hexA:sub(1,4) .. hexB:sub(1,4) .. hexA:sub(5,8) .. hexB:sub(5,8)
  
  -- Format into: XXXX-XXXX-XXXX-XXXX
  return string.format("%s-%s-%s-%s", 
    combined:sub(1,4), 
    combined:sub(5,8), 
    combined:sub(9,12), 
    combined:sub(13,16))
end

-- Verifies the entered Key 2 offline against Key 1 using DJB2 with salt 'hoangmanhsu@12345'
function VtcMod.VerifyKey(key1, key2)
  if not key2 or key2 == "" then return false end
  
  local salt = "hoangmanhsu@12345"
  local cleanKey1 = string.gsub(string.upper(key1), "%s", "")
  
  local combined = cleanKey1 .. salt
  local hash = 5381
  for i = 1, #combined do
    local c = string.byte(combined, i)
    hash = ((hash * 33) + c) % 4294967296
  end
  
  local expectedKey = string.format("VTCMOD-%08X", hash)
  return string.upper(key2) == expectedKey
end

-- Kiểm tra thiết bị đã ROOT hoặc giả lập bật ROOT trong game Android
function VtcMod.IsDeviceRooted()
  local rootPaths = {
    "/system/app/Superuser.apk",
    "/system/etc/init.d/99SuperSUDaemon",
    "/system/bin/.ext/.su",
    "/system/usr/we-need-sys/su-backup",
    "/system/xbin/mu",
    "/system/xbin/su",
    "/system/bin/su",
    "/sbin/su",
    "/data/local/xbin/su",
    "/data/local/bin/su",
    "/system/sd/xbin/su",
    "/system/bin/failsafe/su",
    "/data/local/su"
  }
  for _, path in ipairs(rootPaths) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return true
    end
  end
  
  -- Kiểm tra gián tiếp qua os.execute
  local status = os.execute("which su")
  if status == 0 or status == true then
    return true
  end
  return false
end

-- Initializes license status on launch
function VtcMod.InitLicense()
  local success, err = pcall(function()
    if this.deviceId == nil then
      local rawId = "pc_simulation_device_id"
      if CS and CS.UnityEngine and CS.UnityEngine.SystemInfo then
        local sysInfo = CS.UnityEngine.SystemInfo
        local uid = tostring(sysInfo.deviceUniqueIdentifier or "")
        local cpu = tostring(sysInfo.processorType or "")
        local ram = tostring(sysInfo.systemMemorySize or "")
        local os = tostring(sysInfo.operatingSystem or "")
        local model = tostring(sysInfo.deviceModel or "")
        rawId = string.format("%s|%s|%s|%s|%s", uid, cpu, ram, os, model)
      end
      this.deviceId = rawId
      this.key1 = VtcMod.GetHardwareCode(this.deviceId)
      logError("--- [VtcMod] Device Hardware Code (Key 1): " .. tostring(this.key1) .. " ---")
    end
    
    local key2 = ""
    if CS and CS.UnityEngine and CS.UnityEngine.PlayerPrefs then
      key2 = CS.UnityEngine.PlayerPrefs.GetString("VTC_MOD_LICENSE_KEY", "")
      logError("--- [VtcMod] Read License Key (Key 2) from PlayerPrefs: '" .. tostring(key2) .. "' ---")
    else
      logError("--- [VtcMod] PlayerPrefs not available! ---")
    end
    
    -- Kiểm tra ROOT để cảnh báo hệ thống
    this.isDeviceRooted = VtcMod.IsDeviceRooted()
    if this.isDeviceRooted then
      logError("--- [VtcMod] WARNING: Device is ROOTED (SuperSU/Magisk detected)! Enforcing Anti-Extraction RAM Protection. ---")
    end
    
    if VtcMod.VerifyKey(this.key1, key2) then
      this.isLicensed = true
      logError("--- [VtcMod] License verified successfully! Status: PREMIUM ---")
    else
      this.isLicensed = false
      if VtcMod.trialApiUrl and VtcMod.trialApiUrl ~= "" then
        logError("--- [VtcMod] Offline License invalid! Initiating Online Trial Check... ---")
        local url = VtcMod.trialApiUrl .. "?action=check&deviceId=" .. tostring(this.deviceId)
        if CS and CS.UnityEngine and CS.UnityEngine.WWW then
          this.trialWww = CS.UnityEngine.WWW(url)
        end
      else
        logError("--- [VtcMod] License invalid! Status: LOCKED ---")
      end
    end
  end)
  if not success then
    logError("--- [VtcMod] InitLicense Error: " .. tostring(err) .. " ---")
  end
end

-- Renders the elegant cross-platform In-Game Activation Dialog using game's built-in UICheck
function VtcMod.ShowDrmDialog(key1)
  if not UICheck then return end
  
  local extraMsg = ""
  if this.isTrialExpired then
    extraMsg = "<color=#FF0000><b>THOI GIAN DUNG THU 5 NGAY DA HET!</b></color>\n"
  end
  
  local message = "<color=#FFFF00><b>KICH HOAT BAN QUYEN TS ONLINE VTC MOD VIP</b></color>\n\n" ..
                  extraMsg ..
                  "Ma may cua ban (Key 1):\n" ..
                  "<color=#00FF00><b>" .. key1 .. "</b></color>\n\n" ..
                  "Hay gui Ma May tren cho Admin de lay Ma Kich Hoat (Key 2).\n" ..
                  "Bam nut SAO CHEP ben duoi de copy Ma May de dang!"
  
  local choices = { "SAO CHEP MA MAY (KEY 1)", "NHAP MA KICH HOAT (KEY 2)" }
  
  UICheck.OnOpen(function(index)
    if index == 1 then
      -- Copy Key 1 to system clipboard!
      if CS and CS.UnityEngine and CS.UnityEngine.GUIUtility then
        CS.UnityEngine.GUIUtility.systemCopyBuffer = key1
        ShowCenterMessage("Da sao chep Ma May vao bo nho dem!")
      else
        ShowCenterMessage("Khong copy duoc vi thieu thong tin!")
      end
      -- Reopen dialog immediately so they don't get stuck
      CGTimer.DoFunctionDelay(0.5, function()
        VtcMod.ShowDrmDialog(key1)
      end)
    elseif index == 2 then
      -- Open mobile native keyboard to paste Key 2
      if CS and CS.UnityEngine and CS.UnityEngine.TouchScreenKeyboard then
        this.keyboard = CS.UnityEngine.TouchScreenKeyboard.Open("", CS.UnityEngine.TouchScreenKeyboardType.Default, false, false, false, false, "Nhap Ma Kich Hoat VIP (Key 2)")
      else
        ShowCenterMessage("Khong mo duoc ban phim tren phien ban nay!")
      end
    end
  end, message, choices, nil, nil, false, false, false)
end


-- Default Player Mod Variables
VtcMod.movementSpeed = 260
VtcMod.battleTimeScale = 20
VtcMod.autoTalkSkip = false
VtcMod.wallHack = false
VtcMod.autoHeal = false
VtcMod.alwaysAutoFight = false
VtcMod.showHiddenNpc = false
VtcMod.targetFPS = 30
VtcMod.powerSaving = false
VtcMod.autoPartyMode = "NONE"      -- "NONE", "LEADER", "MEMBER"
VtcMod._partyList = {
  "__PARTY_SLOT_1__", -- Leader
  "__PARTY_SLOT_2__", -- Adviser
  "__PARTY_SLOT_3__",
  "__PARTY_SLOT_4__",
  "__PARTY_SLOT_5__"
}
VtcMod._partyLeaderTarget = VtcMod._partyList[1]   -- Tên chủ party đích (dành cho MEMBER)
VtcMod._partyLeaderId = nil        -- ID chủ party đích (chỉ dùng runtime)
VtcMod._partyRejoinNextTime = 0    -- Cooldown chống spam request join
VtcMod.persistentSampleMode = false
VtcMod.autoDailyQuests = false
VtcMod.drawWith9000Xu = false
VtcMod.autoBuffOutBattle = false
VtcMod.autoPetBuffOutBattle = false
VtcMod.autoRemoteSniper = false
VtcMod.autoAnotherWorldSniper = false
VtcMod.autoStandaloneSniper = false
VtcMod.autoDiGioiSniper = false
VtcMod.userInitiatedEvent = false
VtcMod.quickBankEnabled = false
VtcMod._quickBankStep = 0
VtcMod._quickBankQueue = {}
VtcMod._quickBankQueueIdx = 0
VtcMod._quickBankNextTime = 0
VtcMod._quickBankTransferred = 0

-- Auto-Flee No Party: injected from C# Tool checkbox
VtcMod.autoFleeNoParty = ("__AUTO_FLEE_NO_PARTY__" == "true")

-- 40NPC Configurations (Đã tự động lấy từ logcat)
VtcMod.auto40NPC = false
VtcMod.cfg40NPC_MapID = 10991
VtcMod.cfg40NPC_TargetX = 990
VtcMod.cfg40NPC_TargetY = 310

-- Auto-Decompose Gift Bags
-- Nhóm A: Hộp Trang Bị — mở thẳng trang bị, KHÔNG sub-bag. Batch 3-5.
VtcMod.GROUP_A_IDS = {
  [46388]=true, [46389]=true, [46390]=true, [46391]=true,
}
-- Nhóm B: Túi Phó Bản — có thể rơi SUB-BAG (túi con). Batch 1-2.
VtcMod.GROUP_B_IDS = {
  [46387]=true, [46396]=true, [46397]=true, [46404]=true, [46407]=true,
  [33997]=true, [33998]=true, [33999]=true, [34000]=true, [35101]=true,
  [46921]=true, [46922]=true, [46923]=true, [46924]=true, [46926]=true,
  [46410]=true, [46413]=true,
  [46385]=true, [46386]=true, [46398]=true, [46399]=true,
  [46405]=true, [46406]=true, [46408]=true, [46409]=true,
  [46411]=true, [46412]=true, [46414]=true, [46415]=true,
}
-- Union A + B for general lookup
VtcMod.GIFT_BAG_IDS = {}
for k in pairs(VtcMod.GROUP_A_IDS) do VtcMod.GIFT_BAG_IDS[k] = true end
for k in pairs(VtcMod.GROUP_B_IDS) do VtcMod.GIFT_BAG_IDS[k] = true end

VtcMod._decomposeBlacklist = {}
VtcMod._decomposeActive = false
VtcMod._decomposeStep = 0        -- 0=IDLE, 1=SCAN_ONE, 2=OPEN_ONE, 3=DIFF, 4=DISMANTLE, 5=DONATE, 6=DROP
VtcMod._decomposeNextTime = 0
VtcMod._decomposeStep3Start = 0
VtcMod._decomposeSnapshot = {}     -- Bag state snapshot taken before opening 1 bag
VtcMod._decomposeNewItems = {}     -- Items produced by the current bag
VtcMod._decomposeActionIdx = 0     -- Index into _decomposeNewItems for per-tick processing
VtcMod._decomposeCurrentBag = nil  -- Single bag currently being processed {slot, id}
VtcMod._decomposeTotalOpened = 0
VtcMod._decomposeTotalDismantled = 0
VtcMod._decomposeTotalDonated = 0
VtcMod._decomposeTotalDropped = 0
VtcMod._decomposeStartTime = 0
VtcMod._decomposeIterations = 0
VtcMod._decomposeWorkerCount = 0   -- How many bags (workers) have been fully processed

-- Two-Phase Pipeline Config (Group A: fast 3-5, Group B: safe 1-2)
VtcMod._decomposeReservedSlots = 5        -- Keep 5 slots reserved for safety
VtcMod._decomposeMaxBatchSize = 10        -- Hard cap: max 10 bags per batch
VtcMod._decomposeRecursionDepth = 0       -- Current recursive depth level
VtcMod._decomposeMaxRecursionDepth = 8    -- Max recursive depth (B bags nest 3-4 deep)
VtcMod._decomposeBatchBags = {}           -- Current batch of bags being processed
VtcMod._decomposeBatchOpenIdx = 0         -- Index into batch for sequential open


-- Database Table Inspector Helper
function VtcMod.DumpToChat(data)
  if type(data) ~= "table" then
    if Chat and EChannel then
      Chat.AddMessage(EChannel.System, tostring(data))
    end
    return
  end
  local lines = {}
  for k, v in pairs(data) do
    if type(v) == "table" then
      table.insert(lines, string.format("%s: {table}", tostring(k)))
    else
      table.insert(lines, string.format("%s: %s", tostring(k), tostring(v)))
    end
  end
  if Chat and EChannel then
    Chat.AddMessage(EChannel.System, "Du lieu:\n" .. table.concat(lines, "\n"))
  end
end

function VtcMod.IsNpcRelatedToActiveQuest(npcEventId)
  if not npcEventId or npcEventId == 0 then return true end
  if not MarkManager or not MarkManager.missions or not markDatas then return true end
  
  -- Check if we actually have any active missions to avoid blocking if none exist
  local hasActiveMissions = false
  for k, v in pairs(MarkManager.missions) do
    if v then
      hasActiveMissions = true
      break
    end
  end
  if not hasActiveMissions then return true end
  
  -- Get the database npcId if available
  local npcRole = Role and Role.mapNpcs and Role.mapNpcs[npcEventId]
  local npcId = npcRole and npcRole.npcId
  
  local isRelated = false
  for missionId, v in pairs(MarkManager.missions) do
    if v and v.id and v.step then
      local mData = markDatas[v.id]
      if mData and mData.steps then
        local step = mData.steps[v.step]
        if step then
          -- 1. Check if the NPC is the end target of the current step
          -- step.endEventKind == 1 means Npc
          if step.endEventKind == 1 and (step.endEventId == npcEventId or (npcId and npcId ~= 0 and step.endEventId == npcId)) then
            isRelated = true
            break
          end
          
          -- 2. Check if the NPC is part of any active conditions in the step
          if step.conditions then
            for i = 1, 5 do
              local cond = step.conditions[i]
              if cond and cond.kind ~= 0 then
                local condDone = false
                if cond.kind == 1 then -- capture NPC
                  condDone = (Role and Role.GetFollowNpc and Role.GetFollowNpc(Role.playerId, cond.id) ~= nil)
                elseif cond.kind == 3 then -- collect item
                  condDone = (Item and Item.GetItemCount and Item.GetItemCount(cond.id) >= cond.count)
                end
                
                if not condDone then
                  -- Check if condition is associated with this NPC eventId or npcId
                  if cond.eventKind == 1 and (cond.eventId == npcEventId or (npcId and npcId ~= 0 and cond.eventId == npcId)) then
                    isRelated = true
                    break
                  end
                  if (cond.kind == 1 or cond.kind == 2) and cond.id == npcId then
                    isRelated = true
                    break
                  end
                end
              end
            end
          end
          
          if isRelated then break end
        end
      end
    end
  end
  
  return isRelated
end

function VtcMod.Init()
  if this.initialized then return end
  this.initialized = true;
  
  -- Anti-Extraction Device-Bound DRM
  local embeddedToken = "__VTC_DEVICE_TOKEN__"
  pcall(function()
    if embeddedToken == "__VTC_DEVICE" .. "_TOKEN__" then
      logError("--- [VtcMod] FATAL: Raw undeployed file detected. ---")
      return
    end
    
    local f = io.open("/sys/class/net/wlan0/address", "r")
    if f then
      local mac = f:read("*a"):gsub("%s+", "")
      f:close()
      
      -- DJB2 Hash using old keygen salt to match the system
      local salt = "hoangmanhsu@12345"
      local combined = mac .. salt
      local hash = 5381
      for i = 1, #combined do
        local c = string.byte(combined, i)
        hash = ((hash * 33) + c) % 4294967296
      end
      local expectedToken = string.format("DEVLOCK-%08X", hash)
      
      if embeddedToken ~= expectedToken then
        logError("--- [VtcMod] DEVICE MISMATCH! Extracted file detected. Locking Mod. ---")
        this.isLicensed = false
        if VtcMod.ShowDrmDialog then
            -- Fallback to showing old keygen dialog using the MAC address as Key 1
            VtcMod.ShowDrmDialog(mac)
        end
        return
      end
      logError("--- [VtcMod] Device token verified OK! ---")
    else
      logError("--- [VtcMod] Cannot read MAC address for DRM verify. Locking Mod. ---")
      this.isLicensed = false
    end
  end)
  
  if not this.isLicensed then return end -- Abort initialization if locked
  
  logError("--- [VtcMod] Initializing Robust Mod Layer... ---");
  
  -- Clear and reload UISetting/UIDebug/UIMiniMap to force our patched versions
  pcall(function()
    package.loaded["UI/UISetting"] = nil
    package.loaded["UI/UIDebug"] = nil
    package.loaded["UI/UITeleport"] = nil
    require "UI/UISetting"
    require "UI/UIDebug"
    require "UI/UITeleport"
    require "UI/UIMiniMap"
    logError("--- [VtcMod] Successfully reloaded UISetting and UIMiniMap! ---")
  end)
  
  -- 1. Force target FPS
  pcall(function()
    local fps = VtcMod.targetFPS or 30
    if UnityEngine and UnityEngine.Application then
      UnityEngine.Application.targetFrameRate = fps
      logError("--- [VtcMod] Set targetFrameRate via UnityEngine.Application to: " .. fps .. " ---")
    end
  end)
  pcall(function()
    local fps = VtcMod.targetFPS or 30
    if Application then
      Application.targetFrameRate = fps
      logError("--- [VtcMod] Set targetFrameRate via Application to: " .. fps .. " ---")
    end
  end)
  
  -- 2. Hook Debug Mode dynamically
  pcall(function()
    if Define and not Define.isHooked then
      Define.IsDebugMode = function()
        return false
      end
      Define.isHooked = true
      logError("--- [VtcMod] Hooked Define.IsDebugMode to false (Disabled Item IDs)! ---")
    end
  end)
  
  -- 3. Hook MachineBox Always BDY ON
  pcall(function()
    if MachineBox and VtcMod.alwaysAutoFight and not MachineBox.isSetAutoFightHooked then
      local original_SetAutoFight = MachineBox.SetAutoFight
      MachineBox.SetAutoFight = function(active, sendMessage)
        return original_SetAutoFight(true, sendMessage)
      end
      MachineBox.isSetAutoFightHooked = true
      MachineBox.autoFight = true
      logError("--- [VtcMod] Hooked MachineBox.SetAutoFight! ---")
    end
  end)
  
  -- 4. Set Default Role Class Speed & Scene Speed
  pcall(function()
    if Role then
      Role.baseSpeed = VtcMod.movementSpeed or 260
      logError("--- [VtcMod] Hooked Role.baseSpeed! ---")
    end
    if SceneManager and SceneManager.sceneState then
      SceneManager.sceneState.moveSpeed = VtcMod.movementSpeed or 260
      logError("--- [VtcMod] Set SceneManager.sceneState.moveSpeed! ---")
    end
  end)

  -- 5. Hook FindWay.Start dynamically for Wall Hack (Noclip)
  pcall(function()
    if FindWay and FindWay.Start and not FindWay.isStartHooked then
      local original_FindWay_Start = FindWay.Start
      FindWay.Start = function(startPosition, targetPosition, isMoveStraight, isMoveCurrentView, isMoveLine, roleController)
        if VtcMod.wallHack then
          isMoveStraight = true
        end
        return original_FindWay_Start(startPosition, targetPosition, isMoveStraight, isMoveCurrentView, isMoveLine, roleController)
      end
      FindWay.isStartHooked = true
      logError("--- [VtcMod] Dynamically hooked FindWay.Start for WallHack! ---")
    end
  end)

  -- 6. Hook UICheck.OnOpen dynamically for Auto-Dialogue Skip
  pcall(function()
    if UICheck and UICheck.OnOpen and not UICheck.isOnOpenHooked then
      local original_UICheck_OnOpen = UICheck.OnOpen
      UICheck.OnOpen = function(callbackFunction, message, showChooses, showRole, showIcon, showYes, showCancel, showClose)
        local ret = original_UICheck_OnOpen(callbackFunction, message, showChooses, showRole, showIcon, showYes, showCancel, showClose)
        
        local shouldAutoSkip = false
        if VtcMod.autoTalkSkip or VtcMod.autoSkipEventToBattle then
          shouldAutoSkip = true
        elseif not VtcMod.userInitiatedEvent and (VtcMod.autoStandaloneSniper or VtcMod.autoDiGioiSniper) then
          shouldAutoSkip = true
        end
        
        if shouldAutoSkip then
          CGTimer.DoFunctionDelay(0, function()
            if UI and UICheck and UI.IsVisible(UICheck) then
              if type(showChooses) == "table" then
                local numChooses = 0
                for _ in pairs(showChooses) do numChooses = numChooses + 1 end
                
                if numChooses == 1 or VtcMod.autoSkipEventToBattle then
                  -- Nếu chỉ có 1 lựa chọn hoặc đang auto skip event, click chọn luôn (mặc định chọn 1)
                  UI.Close(UICheck, 1)
                else
                  -- Nếu có nhiều lựa chọn (câu hỏi), ngừng auto skip để người dùng tự chọn
                  logError("--- [VtcMod] Detected Choices. Paused AutoTalk for manual selection. ---")
                end
              elseif showYes and VtcMod.autoSkipEventToBattle then
                UI.Close(UICheck, 1)
              elseif not showYes then
                -- Thoại thông thường, bấm Next
                UICheck.OnClick_Next()
              end
            end
          end)
        end
        return ret
      end
      UICheck.isOnOpenHooked = true
      logError("--- [VtcMod] Dynamically hooked UICheck.OnOpen for AutoTalkSkip! ---")
    end
  end)
  
  -- 8. Hook RoleController:UpdateViewVisible dynamically for Hidden NPC visibility & clickability
  pcall(function()
    if RoleController and RoleController.UpdateViewVisible and not RoleController.isUpdateViewVisibleHooked then
      local original_UpdateViewVisible = RoleController.UpdateViewVisible
      RoleController.UpdateViewVisible = function(self)
        if VtcMod.showHiddenNpc and self.kind == EHuman.MapNpc then
          local visibleEnum = ERoleVisible or { Visible = 1, Hide = 2, TimeHide = 4 }
          if self.visible == visibleEnum.Hide or self.visible == visibleEnum.TimeHide then
            self.originalVisibleState = self.visible -- Lưu lại trạng thái ẩn nguyên thủy
            self.visible = visibleEnum.Visible
          end
        end
        original_UpdateViewVisible(self)
        if VtcMod.showHiddenNpc and self.kind == EHuman.MapNpc then
          if self.gameObject ~= nil then
            if self.bodyObject ~= nil then self.bodyObject:SetActive(true) end
            if self.hudVisibleObject ~= nil then self.hudVisibleObject:SetActive(true) end
            if self.image_MiniMap ~= nil and self.image_MiniMap.gameObject ~= nil then self.image_MiniMap.gameObject:SetActive(true) end
          end
        end
      end
      RoleController.isUpdateViewVisibleHooked = true
      logError("--- [VtcMod] Hooked RoleController:UpdateViewVisible for Hidden NPC! ---")
    end
  end)

  -- 9. Hook EventManager to track user-initiated events for AutoTalkSkip
  pcall(function()
    if EventManager and not EventManager.isVtcModHooked then
      if EventManager.TriggerEvent then
        local original_TriggerEvent = EventManager.TriggerEvent
        EventManager.TriggerEvent = function(triggerKind, triggerID, triggerObj, isStopMove)
          VtcMod.userInitiatedEvent = true
          
          -- Stationary Shadow Teleport (Pimbot style) before triggering to avoid "Too far" error
          pcall(function()
            if triggerKind == 1 or triggerKind == 2 then
              local tObj = triggerObj
              if not tObj and triggerID and Role and Role.mapNpcs then
                tObj = Role.mapNpcs[triggerID]
              end
              if tObj and tObj.position then
                -- Calculate precise anticipatory interception position (vị trí đón đầu) + Thêm Offset an toàn chống lỗi kẹt vật lý
                local interceptX = tObj.position.x + 20
                local interceptY = tObj.position.y + 20
                if tObj.moveController and tObj.moveController.targetPosition and tObj.moveController.targetPosition.x ~= 0 then
                  local targetX = tObj.moveController.targetPosition.x
                  local targetY = tObj.moveController.targetPosition.y
                  local dx = targetX - interceptX
                  local dy = targetY - interceptY
                  local distSqr = dx * dx + dy * dy
                  if distSqr > 1 then
                    local dist = math.sqrt(distSqr)
                    -- Dynamic look-ahead based on baseSpeed (supports 500~2000 speed bounds)
                    local speed = tObj.speed or (Role and Role.baseSpeed) or 160
                    local lookAheadDist = speed * 0.4 -- predict 400ms ahead
                    if lookAheadDist > dist then lookAheadDist = dist end
                    local ratio = lookAheadDist / dist
                    interceptX = interceptX + dx * ratio
                    interceptY = interceptY + dy * ratio
                  end
                end
                
                -- Stop local movement logic from overriding our teleport packet
                if MachineBox then MachineBox.autoMove = false end
                if Role and Role.player then Role.player:StopMove() end
                -- if CGTimer and MoveController and MoveController.SendRolePosition then CGTimer.RemoveListener(MoveController.SendRolePosition) end
                
                -- Send network movement to the exact intercept point (Stationary Shadow)
                if MoveController and MoveController.SendMove then
                  MoveController.SendMove(math.floor(interceptX), math.floor(interceptY))
                end
              end
            end
          end)
          
          return original_TriggerEvent(triggerKind, triggerID, triggerObj, isStopMove)
        end
      end
      if EventManager.ClearEventState then
        local original_ClearEventState = EventManager.ClearEventState
        EventManager.ClearEventState = function()
          VtcMod.userInitiatedEvent = false
          -- Chỉ clear autoSkipEventToBattle nếu KHÔNG đang trong dungeon/boss steps
          -- Step 12.5 (Boss battle) và Step 17 (Team Dungeon) cần giữ flag suốt chuỗi event
          if VtcMod._dailyStep ~= 12.5 and VtcMod._dailyStep ~= 17 then
            VtcMod.autoSkipEventToBattle = false
          end
          return original_ClearEventState()
        end
      end
      EventManager.isVtcModHooked = true
      logError("--- [VtcMod] Hooked EventManager for AutoTalk tracking! ---")
    end
  end)

  -- 10. Hook EventManager.OnNpcEvent to block non-quest NPCs when AutoTalkSkip is active
  pcall(function()
    if EventManager and EventManager.OnNpcEvent and not EventManager.isOnNpcEventHooked then
      local original_OnNpcEvent = EventManager.OnNpcEvent
      EventManager.OnNpcEvent = function(triggerKind, npcEventData)
        if VtcMod.autoTalkSkip and triggerKind == 2 then -- 2 is BumpNpc
          if npcEventData and npcEventData.id then
            if not VtcMod.IsNpcRelatedToActiveQuest(npcEventData.id) then
              logError("--- [VtcMod] Blocked BumpNpc for non-quest NPC: " .. tostring(npcEventData.id) .. " ---")
              return false
            end
          end
        end
        return original_OnNpcEvent(triggerKind, npcEventData)
      end
      EventManager.isOnNpcEventHooked = true
      logError("--- [VtcMod] Hooked EventManager.OnNpcEvent for AutoTalk skip non-quest NPC! ---")
    end
  end)



  


  -- 12. Hook Network.Send has been moved to Update loop to support late loading of Network module.

  -- 13. Hook FightField.SetConSkill to log manually selected skills
  pcall(function()
    if FightField and FightField.SetConSkill and not FightField.isVtcModSkillLoggerHooked then
      local original_SetConSkill = FightField.SetConSkill
      FightField.SetConSkill = function(skillId)
        logError("--- [VtcMod] MANUAL SKILL USED IN BATTLE: ID " .. tostring(skillId) .. " ---")
        return original_SetConSkill(skillId)
      end
      FightField.isVtcModSkillLoggerHooked = true
    end
  end)

  -- 14. Hook RoleController.CheckInteractive to force display of PK option for hidden MapNpc
  pcall(function()
    if RoleController and RoleController.CheckInteractive and not RoleController.isCheckInteractiveHooked then
      local original_CheckInteractive = RoleController.CheckInteractive
      RoleController.CheckInteractive = function(self, kind)
        local active, color = original_CheckInteractive(self, kind)
        if VtcMod.showHiddenNpc and kind == EInteractive.PK and self.kind == EHuman.MapNpc then
          active = true
          color = Color.White
        end
        return active, color
      end
      RoleController.isCheckInteractiveHooked = true
      logError("--- [VtcMod] Hooked RoleController.CheckInteractive for hidden NPC PK option! ---")
    end
  end)

  -- 15. Hook SceneManager.CheckLimit to bypass NoPKNPC map constraint for hidden MapNpc
  pcall(function()
    if SceneManager and SceneManager.CheckLimit and not SceneManager.isVtcModCheckLimitHookedV2 then
      local original_CheckLimit = SceneManager.CheckLimit
      SceneManager.original_CheckLimit = original_CheckLimit
      SceneManager.CheckLimit = function(id, limitKind)
        if VtcMod.showHiddenNpc and limitKind == ESceneLimit.NoPKNPC then
          return false
        end
        return original_CheckLimit(id, limitKind)
      end
      SceneManager.isVtcModCheckLimitHookedV2 = true
      logError("--- [VtcMod] Hooked SceneManager.CheckLimit to bypass NoPKNPC limit! ---")
    end
  end)

  -- 16. Hook NpcData.CheckLimit to bypass PK limits on hidden MapNpc
  pcall(function()
    if NpcData and NpcData.CheckLimit and not NpcData.isVtcModNpcCheckLimitHookedV2 then
      local original_NpcData_CheckLimit = NpcData.CheckLimit
      NpcData.original_CheckLimit = original_NpcData_CheckLimit
      NpcData.CheckLimit = function(self, limitKind)
        if VtcMod.showHiddenNpc and limitKind == ENpcLimit.PK then
          return false
        end
        return original_NpcData_CheckLimit(self, limitKind)
      end
      NpcData.isVtcModNpcCheckLimitHookedV2 = true
      logError("--- [VtcMod] Hooked NpcData.CheckLimit to bypass NPC PK limit! ---")
    end
  end)

  -- 17. Hook RoleController.OnInteractive to redirect Trig to PK for hidden NPCs
  pcall(function()
    if RoleController and RoleController.OnInteractive and not RoleController.isVtcModOnInteractiveHookedV4 then
      local original_OnInteractive = RoleController.OnInteractive
      RoleController.OnInteractive = function(self, kind)
        pcall(function()
          local nameStr = self.data and self.data.name or "Unknown"
          if self.npcId and npcDatas and npcDatas[self.npcId] and npcDatas[self.npcId].name then
            nameStr = npcDatas[self.npcId].name
          end
          logError(string.format("--- [VtcMod] Clicked NPC: Name: %s, ID: %d, Index: %d, Kind: %d ---", nameStr, self.npcId or 0, self.index or 0, kind or 0))
        end)
        
        -- Smart PK Logic
        if VtcMod.showHiddenNpc and self.kind == EHuman.MapNpc and kind == EInteractive.PK then
          local serverRejectsPK = false
          if SceneManager and SceneManager.original_CheckLimit and SceneManager.original_CheckLimit(SceneManager.sceneId, ESceneLimit.NoPKNPC) then
            serverRejectsPK = true
          end
          if NpcData and NpcData.original_CheckLimit and npcDatas and npcDatas[self.npcId] and NpcData.original_CheckLimit(npcDatas[self.npcId], ENpcLimit.PK) then
            serverRejectsPK = true
          end

          if serverRejectsPK then
            logError("--- [VtcMod Smart PK] Server blocked PK! Auto-falling back to Trig (Talk) to trigger Event Battle ---")
            kind = EInteractive.Trig
            VtcMod.autoSkipEventToBattle = true
          else
            logError("--- [VtcMod Smart PK] Server allows PK! Sending direct PK packet ---")
          end
        end
        
        return original_OnInteractive(self, kind)
      end
      RoleController.isVtcModOnInteractiveHookedV4 = true
      logError("--- [VtcMod] Hooked RoleController.OnInteractive for Smart PK! ---")
    end
  end)

  logError("--- [VtcMod] Robust Mod Layer Initialized successfully! ---");
end

function VtcMod.ClaimDailyAwards()
  pcall(function()
    if missionAwardDatas then
      local claimed = 0
      for _, value in ipairs(missionAwardDatas) do
        if value:IsComplete() and not value:HaveGetFlag() then
          MissionAward.SendCompleteMission(value.Id)
          claimed = claimed + 1
        end
      end
      if claimed > 0 then
        ShowCenterMessage("Đã nhận phần thưởng từ " .. claimed .. " nhiệm vụ ngày!")
      else
        ShowCenterMessage("Không có phần thưởng nhiệm vụ ngày nào để nhận.")
      end
    end
  end)
end

-- ====================================================================================
-- BACKGROUND AUTO-CLAIM STATE MACHINE
-- ====================================================================================
VtcMod._autoClaimStep = 0
VtcMod._autoClaimNextTime = 0
VtcMod._autoClaimInterval = 18000 -- 5 hours (5 * 3600 seconds)
VtcMod._lastPlayerId = nil
VtcMod._cachedLoginAward = nil

function VtcMod.GetParsedLoginAward()
  if VtcMod._cachedLoginAward then return VtcMod._cachedLoginAward end
  if not loginAwardDatas then return nil end
  local award = {}
  local groupTracker = {}
  for k, v in pairs(loginAwardDatas) do
    if v and v.group then
      if not award[v.group] then
        award[v.group] = { Date = {} }
        groupTracker[v.group] = 0
      end
      groupTracker[v.group] = groupTracker[v.group] + 1
      local idx = groupTracker[v.group]
      award[v.group].Date[idx] = v
      award[v.group].Date[idx].sort = idx
    end
  end
  VtcMod._cachedLoginAward = award
  return award
end

function VtcMod.ExecuteAutoClaimSteps()
  local step = VtcMod._autoClaimStep

  -- Guard: player check
  if not Role or not Role.player then
    VtcMod._autoClaimStep = 0
    return
  end

  -- Safe fallback for enums to avoid nil reference errors
  local loginSingDayIdx = (ERoleCount and ERoleCount.LoginSingDay) or 107
  local continueLoginIdx = (ERoleCount and ERoleCount.ContinueLogin) or 108
  local continueLoginAwardIdx = (ERoleCount and ERoleCount.ContinueLoginAward) or 109
  local onlineTimeIdx = (ERoleCount and ERoleCount.OnlineTime) or 10
  local bitFlagLogin = (EBitFlag and EBitFlag.Login) or 1
  local bitFlagBack = (EBitFlag and EBitFlag.Back) or 1517

  if step == 1 then
    logError("--- [AutoClaim Step 1] Claiming Attendance (Diem danh) ---")
    pcall(function()
      local loginAward = VtcMod.GetParsedLoginAward()
      if loginAward and BitFlag and RoleCount then
        -- 1. Daily Login (EAward.Login = 1)
        local activeDay = RoleCount.Get(loginSingDayIdx) + 1
        if loginAward[1] and loginAward[1].Date and loginAward[1].Date[activeDay] then
          if not BitFlag.Get(bitFlagLogin) then
            local buf = ByteBuffer.New()
            buf:WriteByte(1) -- EAward.Login
            buf:WriteInt32(loginAward[1].Date[activeDay].day)
            buf:WriteByte(1)
            Network.Send(87, 2, buf)
            logError("--- [AutoClaim] Da gui nhan qua Diem Danh (Login) ngay " .. activeDay .. " ---")
          end
        end

        -- 2. Cumulative Login (EAward.AccLogin = 2)
        if loginAward[2] and loginAward[2].Date then
          local continueLogin = RoleCount.Get(continueLoginIdx)
          local continueLoginAward = RoleCount.Get(continueLoginAwardIdx)
          for i = 1, #loginAward[2].Date do
            local v = loginAward[2].Date[i]
            if v and v.day and continueLogin >= v.day and continueLoginAward < i then
              local buf = ByteBuffer.New()
              buf:WriteByte(2) -- EAward.AccLogin
              buf:WriteInt32(v.day)
              buf:WriteByte(1)
              Network.Send(87, 2, buf)
              logError("--- [AutoClaim] Da gui nhan qua Luy Ke Login ngay " .. v.day .. " ---")
            end
          end
        end

        -- 3. Online Gift (EAward.Online = 3)
        if loginAward[3] and loginAward[3].Date then
          local onlineTime = 0
          if UILoginAward and UILoginAward.GetOnlineTime then
            onlineTime = UILoginAward.GetOnlineTime()
          else
            onlineTime = math.floor(RoleCount.Get(onlineTimeIdx) / 60)
          end
          for k, v in pairs(loginAward[3].Date) do
            if v and v.day and not BitFlag.Get(v.flag) and onlineTime >= v.day then
              local buf = ByteBuffer.New()
              buf:WriteByte(3) -- EAward.Online
              buf:WriteInt32(v.day)
              buf:WriteByte(1)
              Network.Send(87, 2, buf)
              logError("--- [AutoClaim] Da gui nhan qua Online (moc " .. v.day .. " phut) ---")
            end
          end
        end

        -- 4. Open Server Gift (EAward.OpenServer = 4)
        if loginAward[4] and loginAward[4].Date then
          local loginDay = 1
          if Role and Role.GetLoginDay then
            loginDay = Role.GetLoginDay()
          end
          for k, v in pairs(loginAward[4].Date) do
            if v and v.day and v.day <= loginDay and not BitFlag.Get(v.flag) then
              local buf = ByteBuffer.New()
              buf:WriteByte(4) -- EAward.OpenServer
              buf:WriteInt32(v.day)
              buf:WriteByte(1)
              Network.Send(87, 2, buf)
              logError("--- [AutoClaim] Da gui nhan qua Khai mo may chu (OpenServer) ngay " .. v.day .. " ---")
            end
          end
        end

        -- 5. Consumption Rebate (EAward.Back = 8)
        if not BitFlag.Get(bitFlagBack) then
          local buf = ByteBuffer.New()
          buf:WriteByte(8) -- EAward.Back
          buf:WriteInt32(0)
          buf:WriteByte(1)
          Network.Send(87, 2, buf)
          logError("--- [AutoClaim] Da gui nhan qua Tieu Phi Hoan Tra ---")
        end
      end
    end)
    VtcMod._autoClaimNextTime = CGTimer.time + 3.0
    VtcMod._autoClaimStep = 2

  elseif step == 2 then
    logError("--- [AutoClaim Step 2] Claiming Mail (Nhan Thu) ---")
    pcall(function()
      if Social and Social.mails and Network and Network.Send then
        local list = {}
        for k, v in pairs(Social.mails) do
          if v and v.time and CGTimer and CGTimer.serverTime and DateTime.Compare(v.time, CGTimer.serverTime) > 0 then
            local hasAttachment = false
            if v.contents and table.maxn(v.contents) > 0 then
              hasAttachment = true
            end
            local state = v.state or 0
            if hasAttachment and state < 2 then
              table.insert(list, k)
            end
          end
        end

        local count = #list
        if count > 0 then
          local buf = ByteBuffer.New()
          buf:WriteUInt32(count)
          for _, v in ipairs(list) do
            buf:WriteUInt32(v)
          end
          Network.Send(83, 1, buf)
          logError("--- [AutoClaim] Da gui nhan vat pham trong hom thu cho " .. count .. " thu ---")
        end
      end
    end)
    VtcMod._autoClaimNextTime = CGTimer.time + 3.0
    VtcMod._autoClaimStep = 3

  elseif step == 3 then
    logError("--- [AutoClaim Step 3] Claiming Free Events & Liveness ---")
    pcall(function()
      if missionAwardDatas then
        local claimedAny = false
        for _, value in ipairs(missionAwardDatas) do
          if value and value.IsComplete and value.HaveGetFlag then
            local ok1, isComplete = pcall(function() return value:IsComplete() end)
            local ok2, hasGot = pcall(function() return value:HaveGetFlag() end)
            if ok1 and isComplete and ok2 and not hasGot then
              if MissionAward and MissionAward.SendCompleteMission then
                MissionAward.SendCompleteMission(value.Id)
                claimedAny = true
              end
            end
          end
        end
        if claimedAny then
          logError("--- [AutoClaim] Claimed MissionAwards ---")
        end
      end
    end)
    VtcMod._autoClaimNextTime = CGTimer.time + 3.0
    VtcMod._autoClaimStep = 4

  elseif step == 4 then
    logError("--- [AutoClaim Step 4] Claiming Active Event Rewards (Free only) ---")
    pcall(function()
      -- Guard bag full
      if Item and Item.CheckBagIsFull and Item.CheckBagIsFull() then
        logError("--- [AutoClaim] Ruong do day, bo qua nhan qua Event ---")
        return
      end

      local loginAward = VtcMod.GetParsedLoginAward()
      if loginAward and BitFlag and RoleCount then
        -- Exclusive list of free event award kinds that do not require item exchange (Change = 9 is excluded!)
        local eventKinds = { 13, 14, 15, 20, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36 }
        for _, kind in ipairs(eventKinds) do
          if loginAward[kind] and loginAward[kind].Date then
            for idx, v in ipairs(loginAward[kind].Date) do
              if v and v.flag and v.day then
                -- Get roleCount index and value dynamically or via fallbacks
                local roleCount = 0
                if kind == 13 then roleCount = RoleCount.Get(128)
                elseif kind == 14 then roleCount = RoleCount.Get(129)
                elseif kind == 15 then roleCount = RoleCount.Get(130)
                elseif kind == 20 then roleCount = RoleCount.Get(133)
                elseif kind == 23 then roleCount = RoleCount.Get(146)
                elseif kind == 24 then
                  roleCount = (UILoginAward and UILoginAward.GetStagePassCount and UILoginAward.GetStagePassCount()) or 0
                elseif kind == 25 then roleCount = RoleCount.Get(189)
                elseif kind == 26 then roleCount = RoleCount.Get(651)
                elseif kind == 27 then roleCount = RoleCount.Get(653)
                elseif kind == 28 then roleCount = RoleCount.Get(665)
                elseif kind == 29 then roleCount = RoleCount.Get(667)
                elseif kind >= 30 and kind <= 35 then
                  if v.roleCount then roleCount = RoleCount.Get(v.roleCount) end
                elseif kind == 36 then
                  local serverIndex = v.roleCount
                  if serverIndex and UILoginAward and UILoginAward.GetAllServerRoleCount then
                    roleCount = UILoginAward.GetAllServerRoleCount(serverIndex)
                  end
                end

                if not BitFlag.Get(v.flag) and roleCount >= v.day then
                  local buf = ByteBuffer.New()
                  buf:WriteByte(kind)
                  buf:WriteInt32(v.day)
                  buf:WriteByte(1)
                  Network.Send(87, 2, buf)
                  logError(string.format("--- [AutoClaim] Da gui nhan qua Event (Kind: %d, Day: %d) ---", kind, v.day))
                end
              end
            end
          end
        end
      end
    end)
    VtcMod._autoClaimNextTime = CGTimer.time + 3.0
    VtcMod._autoClaimStep = 5

  elseif step == 5 then
    logError("--- [AutoClaim Step 5] Claiming Dispatch Rewards (Van Tieu) ---")
    pcall(function()
      if Dispatch and Dispatch.MaxSilderCount and Dispatch.GetProcessValue and Dispatch.SendCompelete then
        local claimedAny = false
        for i = 1, Dispatch.MaxSilderCount do
          if Dispatch.GetProcessValue(i) >= 1 then
            Dispatch.SendCompelete(i)
            claimedAny = true
            logError("--- [AutoClaim] Da nhan thuong Van Tieu hoan thanh o khe so " .. i .. " ---")
          end
        end
        if claimedAny and Network and Network.Send then
          Network.Send(86, 1) -- Request refresh dispatch data from server
        end
      end
    end)

    logError("--- [AutoClaim] ====== COMPLETED BACKGROUND AUTO-CLAIM ====== ---")
    VtcMod._autoClaimNextTime = CGTimer.time + VtcMod._autoClaimInterval
    VtcMod._autoClaimStep = 0
  end
end

-- ====================================================================================
-- DAILY QUESTS STATE MACHINE
-- ====================================================================================
VtcMod._dailyStep = 0
VtcMod._dailyNextTime = 0
VtcMod._dailyDungeonCount = 0
VtcMod._lastSkipResult = -1

function VtcMod.StartDailyQuests()
  if VtcMod._dailyStep > 0 then
    ShowCenterMessage("Đang chạy nhiệm vụ ngày, vui lòng đợi!")
    logError("--- [Daily] BLOCKED: Already running at step " .. VtcMod._dailyStep .. " ---")
    return
  end
  if not Role or not Role.player then
    logError("--- [Daily] BLOCKED: Role/player is nil ---")
    ShowCenterMessage("Chưa vào game, không thể chạy!")
    return
  end
  logError("--- [Daily] ====== STARTING DAILY QUESTS (9 Steps) ====== ---")
  if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] 🚀 BẮT ĐẦU chạy 4 nhiệm vụ ngày tự động...") end
  ShowCenterMessage("🚀 Bắt đầu tự động Nhiệm vụ Ngày!")
  VtcMod._dailyStep = 1
  VtcMod._dailyNextTime = CGTimer.time + 1.0
  VtcMod._dailyDungeonCount = 0
  VtcMod._dailyDungeonBoughtCount = 0
end

function VtcMod.CancelDailyQuests()
  if VtcMod._dailyStep > 0 then
    logError("--- [Daily] ====== CANCELLED BY USER at step " .. VtcMod._dailyStep .. " ====== ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] ❌ Đã hủy nhiệm vụ ngày.") end
    VtcMod._dailyStep = 0
    ShowCenterMessage("❌ Đã hủy tự động Nhiệm vụ Ngày!")
  end
end

function VtcMod.GetDoroPurchaseParams(doroItemId, cost, currencyType)
  if goodsSaleData and goodsSaleData[EStoreKind.Doro] then
    -- Debug dump: liệt kê tất cả items Doro để verify
    logError("--- [Daily] DORO DUMP START (looking for Id=" .. tostring(doroItemId) .. " cost=" .. tostring(cost) .. " currency=" .. tostring(currencyType) .. ") ---")
    for mainPageIndex, mainPageData in pairs(goodsSaleData[EStoreKind.Doro]) do
      for showKind, showKindData in pairs(mainPageData) do
        for pageItemIndex, sellData in pairs(showKindData) do
          logError("--- [Daily] DORO item: page=" .. mainPageIndex .. " show=" .. showKind .. " idx=" .. pageItemIndex .. " Id=" .. tostring(sellData.Id) .. " price=" .. tostring(sellData.saleCredit) .. " currency=" .. tostring(sellData.currencyKind) .. " ---")
          if sellData.Id == doroItemId and sellData.saleCredit == cost then
            -- Match tìm thấy - kiểm tra currency linh hoạt
            if sellData.currencyKind == currencyType or sellData.currencyKind == 3 then
              logError("--- [Daily] DORO MATCH FOUND! ---")
              return {
                storeKind = EStoreKind.Doro,
                mainPageIndex = mainPageIndex,
                showKind = showKind,
                pageItemIndex = pageItemIndex,
                Id = sellData.Id,
                saleCredit = sellData.saleCredit
              }
            end
          end
        end
      end
    end
    logError("--- [Daily] DORO DUMP END - NO MATCH ---")
  else
    logError("--- [Daily] goodsSaleData or EStoreKind.Doro is nil ---")
    if goodsSaleData then
      logError("--- [Daily] goodsSaleData exists, keys: ---")
      for k,_ in pairs(goodsSaleData) do logError("--- [Daily]   storeKind=" .. tostring(k)) end
    end
  end
  return nil
end

function VtcMod.FindAvailableSoloDungeon()
  if Dungeon and dungeonDatas and Role and Role.player then
    local lv = Role.player:GetAttribute(EAttribute.Lv)
    local bestId = 0
    local canSkip = false
    local hasFreeAttempt = false
    
    for k, v in pairs(dungeonDatas) do
      -- kind=2 is solo dungeon
      if v.kind == 2 and v.minLv <= lv and v.maxLv >= lv then
        bestId = v.id
        
        local usedCount = 0
        if MarkManager and MarkManager.missions and MarkManager.missions[v.dayilyFlag] ~= nil then 
          usedCount = MarkManager.missions[v.dayilyFlag].step
        end
        
        hasFreeAttempt = (v.dayilyCount - usedCount > 0)
        if MarkManager and MarkManager.GetMissionFlag then
          canSkip = MarkManager.GetMissionFlag(v.skipFlag)
        end
        -- Found the suitable solo dungeon for our level, break now
        break
      end
    end
    
    return bestId, canSkip, hasFreeAttempt
  end
  return 0, false, false
end

function VtcMod.FindAvailableTeamDungeon()
  if Dungeon and dungeonDatas and Role and Role.player then
    for k, v in pairs(dungeonDatas) do
      -- kind=1 is team dungeon, tìm phó bản đội cấp 20
      if v.kind == 1 and v.minLv <= 20 and v.maxLv >= 20 then
        local usedCount = 0
        if MarkManager and MarkManager.missions and MarkManager.missions[v.dayilyFlag] ~= nil then 
          usedCount = MarkManager.missions[v.dayilyFlag].step
        end
        local hasFreeAttempt = (v.dayilyCount - usedCount > 0)
        logError("--- [Daily] FindAvailableTeamDungeon: id=" .. tostring(v.id) .. " kind=" .. tostring(v.kind) .. " minLv=" .. tostring(v.minLv) .. " maxLv=" .. tostring(v.maxLv) .. " used=" .. tostring(usedCount) .. "/" .. tostring(v.dayilyCount) .. " hasFree=" .. tostring(hasFreeAttempt) .. " ---")
        return v.id, hasFreeAttempt
      end
    end
  end
  return 0, false
end

function VtcMod.ExecuteDailyStep()
  local step = VtcMod._dailyStep

  -- Guard: kiểm tra player tồn tại
  if not Role or not Role.player then
    logError("--- [Daily Step " .. step .. "] ERROR: Role.player is nil, aborting ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] LỖI: Mất kết nối nhân vật, đã dừng.") end
    VtcMod._dailyStep = 0
    return
  end

  -- Guard: đợi hết trận đấu (Ngoại trừ Step 12.5 và 17 vì các step này có logic track battle riêng)
  if Role.player.war ~= EWar.None and step ~= 12.5 and step ~= 17 then
    logError("--- [Daily Step " .. step .. "] WAITING: Player is in battle ---")
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    return
  end

  -- ========================================
  -- TASK 1: Tự động hoàn thành 2 phó bản đơn
  -- ========================================
  if step == 1 then
    logError("--- [Daily Step 1] Requesting dungeon list (Network.Send 47,1) ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 1: Đang tải danh sách phó bản...") end
    Network.Send(47, 1)
    
    VtcMod._dailySoloDungeonWait = 0
    VtcMod._dailyNextTime = CGTimer.time + 3.0
    VtcMod._dailyStep = 2

  elseif step == 2 then
    -- Refresh useableDungeons sau khi nhận 047-001 response
    if Dungeon and Dungeon.InitAvailableDungeonDatas then
      pcall(Dungeon.InitAvailableDungeonDatas)
    end
    if not Dungeon or not Dungeon.useableDungeons then
      logError("--- [Daily Step 2] SKIP: Dungeon module not loaded ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 2: ⚠ Module Dungeon chưa sẵn sàng.") end
      VtcMod._dailyStep = 5
    else
      local dungeonId, canSkip, hasFreeAttempt = VtcMod.FindAvailableSoloDungeon()
      logError("--- [Daily Step 2] FindAvailableSoloDungeon returned: id=" .. tostring(dungeonId) .. ", hasFree=" .. tostring(hasFreeAttempt) .. " ---")
      
      if dungeonId ~= 0 then
        VtcMod._dailyDungeonId = dungeonId
        
        if hasFreeAttempt then
          -- Reset isSending guard để tránh bị chặn ngầm
          if Dungeon then Dungeon.isSending = false end
          local ok, enterErr = pcall(Dungeon.SendCreateDungeon, dungeonId, false, 2)
          if ok then
            logError("--- [Daily Step 2] SUCCESS: Entered dungeon ID " .. dungeonId .. " (Free) ---")
            if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 2: Tham gia phó bản đơn " .. dungeonId .. " (Lượt miễn phí). Đang chờ hoàn thành...") end
            VtcMod._dailyNextTime = CGTimer.time + 5.0
            VtcMod._dailyStep = 3
          else
            logError("--- [Daily Step 2] ERROR: SendCreateDungeon failed - " .. tostring(enterErr) .. " ---")
            VtcMod._dailyStep = 5
          end
        else
          -- No free attempts. Check if we can buy.
          local allowBuy = VtcMod.autoBuyDungeonCount or 0
          local bought = VtcMod._dailyDungeonBoughtCount or 0
          if bought < allowBuy then
            logError("--- [Daily Step 2] Buying additional dungeon run " .. (bought + 1) .. "/" .. allowBuy .. " for ID " .. dungeonId .. " ---")
            if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Đang mua thêm lượt phó bản đơn (" .. (bought + 1) .. "/" .. allowBuy .. ")...") end
            
            pcall(function()
              local buf = ByteBuffer.New()
              buf:WriteByte(2)
              buf:WriteUInt16(13)
              buf:WriteUInt16(dungeonId)
              Network.Send(84, 2, buf)
            end)
            
            VtcMod._dailyDungeonBoughtCount = bought + 1
            
            -- Wait a few seconds for server to process the buy, then force enter
            VtcMod._dailyDungeonIdToEnter = dungeonId
            VtcMod._dailyNextTime = CGTimer.time + 3.0
            VtcMod._dailyStep = 2.5
          else
            logError("--- [Daily Step 2] SKIP: No free attempts and buy limit reached ---")
            if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 2: Đã hết lượt đi phó bản đơn.") end
            VtcMod._dailyStep = 5
          end
        end
      else
        logError("--- [Daily Step 2] SKIP: No solo dungeon suitable for level ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 2: Không tìm thấy phó bản đơn phù hợp.") end
        VtcMod._dailyStep = 5
      end
    end

  elseif step == 2.5 then
    -- Try to enter directly after purchase
    if VtcMod._dailyDungeonIdToEnter then
      if Dungeon then Dungeon.isSending = false end
      local ok, enterErr = pcall(Dungeon.SendCreateDungeon, VtcMod._dailyDungeonIdToEnter, false, 2)
      if ok then
        logError("--- [Daily Step 2.5] SUCCESS: Entered dungeon ID " .. VtcMod._dailyDungeonIdToEnter .. " (Purchased) ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 2.5: Tham gia phó bản đơn (Lượt mua thêm). Đang chờ hoàn thành...") end
        VtcMod._dailyNextTime = CGTimer.time + 5.0
        VtcMod._dailyStep = 3
      else
        logError("--- [Daily Step 2.5] ERROR: SendCreateDungeon failed - " .. tostring(enterErr) .. " ---")
        VtcMod._dailyStep = 5
      end
    else
      VtcMod._dailyStep = 5
    end

  elseif step == 3 then
    -- Nếu UIResult (Xác định phần thưởng) hiện lên, tự động bấm Xác định
    if UI and UIResult and UI.IsVisible(UIResult) then
      logError("--- [Daily Step 3] UIResult is visible! Auto clicking Confirm (Xác định) ---")
      pcall(function()
        if UIResult.OnClickfun1 then
          UIResult.OnClickfun1(nil)
        end
      end)
    end

    -- Bước chờ hoàn thành phó bản
    if Dungeon and Dungeon.nowDungeonId == 0 and Role.player.war == EWar.None then
      logError("--- [Daily Step 3] Finished Dungeon! Moving back to loop. ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Đã hoàn thành một lượt phó bản!") end
      VtcMod._dailyNextTime = CGTimer.time + 3.0
      VtcMod._dailyStep = 1 -- Loop back to Step 1 to check if we can run again
    else
      -- Vẫn đang ở trong phó bản hoặc đang đánh nhau, tiếp tục chờ
      VtcMod._dailySoloDungeonWait = (VtcMod._dailySoloDungeonWait or 0) + 1
      if VtcMod._dailySoloDungeonWait > 40 then -- ~120s timeout
        logError("--- [Daily Step 3] TIMEOUT waiting for Solo Dungeon, skipping ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \226\154\160 Hết thời gian chờ phó bản đơn, bỏ qua.") end
        VtcMod._dailySoloDungeonWait = 0
        VtcMod._dailyStep = 5
      else
        VtcMod._dailyNextTime = CGTimer.time + 3.0
      end
    end

  -- ========================================
  -- TASK 2: Rút tướng và rút thẻ 9000 xu đồng
  -- ========================================
  elseif step == 5 then
    -- Step 5: Rút thẻ 9000 xu đồng (Doro ID 45659)
    logError("--- [Daily Step 5/9] Drawing card 9000 xu (Doro ID 45659) ---")
    local p = VtcMod.GetDoroPurchaseParams(45659, 9000, 3)
    if p then
      local buf = ByteBuffer.New()
      buf:WriteByte(p.storeKind)
      buf:WriteByte(p.mainPageIndex)
      buf:WriteByte(p.showKind)
      buf:WriteByte(p.pageItemIndex)
      buf:WriteUInt16(p.Id)
      buf:WriteUInt16(p.saleCredit)
      buf:WriteUInt16(1)
      buf:WriteByte(0)
      Network.Send(66, 1, buf)
      logError("--- [Daily Step 5/9] SUCCESS: Card draw packet sent ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 5/9: ✅ Đã rút thẻ 9000 xu đồng.") end
    else
      logError("--- [Daily Step 5/9] SKIP: Card draw params not found (ID 45659, 9000 xu) ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 5/9: ⚠ Không tìm thấy gói rút thẻ 9000 xu.") end
    end
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    VtcMod._dailyStep = 6

  elseif step == 6 then
    -- Step 6: Rút võ tướng 9000 xu đồng (Doro ID 45660)
    logError("--- [Daily Step 6/9] Drawing warrior 9000 xu (Doro ID 45660) ---")
    local p = VtcMod.GetDoroPurchaseParams(45660, 9000, 3)
    if p then
      local buf = ByteBuffer.New()
      buf:WriteByte(p.storeKind)
      buf:WriteByte(p.mainPageIndex)
      buf:WriteByte(p.showKind)
      buf:WriteByte(p.pageItemIndex)
      buf:WriteUInt16(p.Id)
      buf:WriteUInt16(p.saleCredit)
      buf:WriteUInt16(1)
      buf:WriteByte(0)
      Network.Send(66, 1, buf)
      logError("--- [Daily Step 6/9] SUCCESS: Warrior draw packet sent ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 6/9: ✅ Đã rút võ tướng 9000 xu đồng.") end
    else
      logError("--- [Daily Step 6/9] SKIP: Warrior draw params not found (ID 45660, 9000 xu) ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 6/9: ⚠ Không tìm thấy gói rút tướng 9000 xu.") end
    end
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    VtcMod._dailyStep = 7

  -- ========================================
  -- TASK 3: Tặng quà cho toàn bộ bạn bè
  -- ========================================
  elseif step == 7 then
    -- Step 7: Tặng quà + nhận quà tất cả bạn bè
    logError("--- [Daily Step 7/9] Gifting all friends ---")
    if Social and Social.friends then
      -- Debug: đếm bạn bè
      local friendCount = 0
      for _ in pairs(Social.friends) do friendCount = friendCount + 1 end
      logError("--- [Daily Step 7/9] Social.friends count: " .. friendCount .. " ---")

      -- Gọi SendAllGift (tặng quà)
      if Social.SendAllGift then
        pcall(Social.SendAllGift)
        logError("--- [Daily Step 7/9] SendAllGift() called ---")
      end

      -- Gọi ReceiveAllGift (nhận quà từ bạn)
      if Social.ReceiveAllGift then
        pcall(Social.ReceiveAllGift)
        logError("--- [Daily Step 7/9] ReceiveAllGift() called ---")
      end

      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 7/9: ✅ Đã tặng/nhận quà bạn bè (" .. friendCount .. " bạn).") end
    else
      logError("--- [Daily Step 7/9] SKIP: Social module or friends list not available ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 7/9: ⚠ Module Social chưa sẵn sàng.") end
    end
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    VtcMod._dailyStep = 8

  -- ========================================
  -- TASK 4: Vận tiêu võ tướng từ khách sạn
  -- ========================================
  elseif step == 8 then
    -- Step 8: Request dữ liệu khách sạn thông qua Dispatch.SendQueryData (protocol 86,1)
    -- Server sẽ phản hồi protocol 31/6 (populate Inn.npcs) + 86/1 (dispatch data)
    logError("--- [Daily Step 8/9] Requesting Inn warrior data via Dispatch.SendQueryData (86,1) ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 8/9: Đang tải dữ liệu khách sạn...") end
    local queryOk = false
    pcall(function()
      if Dispatch and Dispatch.SendQueryData then
        Dispatch.SendQueryData()
        queryOk = true
        logError("--- [Daily Step 8/9] Called Dispatch.SendQueryData() ---")
      end
    end)
    if not queryOk then
      -- Fallback: gửi packet trực tiếp như game gốc (dùng local buffer tránh race condition)
      logError("--- [Daily Step 8/9] Fallback: Direct Network.Send(86, 1) ---")
      pcall(function()
        local buf = ByteBuffer.New()
        Network.Send(86, 1, buf)
      end)
    end
    VtcMod._dailyNextTime = CGTimer.time + 4.0  -- Tăng delay lên 4s cho server populate Inn.npcs
    VtcMod._dailyStep = 9

  elseif step == 9 then
    -- Check for completed dispatch and claim reward first
    local claimed = false
    if Dispatch and Dispatch.IsHaveProcessData then
      for i = 1, Dispatch.MaxSilderCount or 4 do
        if Dispatch.IsHaveProcessData(i) then
          local pv = Dispatch.GetProcessValue(i)
          if pv >= 1 then
            logError("--- [Daily Step 9/9] Found completed dispatch at slot " .. i .. ". Claiming... ---")
            pcall(function() Dispatch.SendCompelete(i) end)
            if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 9/9: ✅ Đã nhận thưởng vận tiêu cũ ở ô " .. i) end
            claimed = true
          end
        end
      end
    end
    
    if claimed then
      -- Re-request data and wait for refresh
      logError("--- [Daily Step 9/9] Claimed rewards, re-requesting data and waiting... ---")
      pcall(function()
        if Dispatch and Dispatch.SendQueryData then
          Dispatch.SendQueryData()
        else
          local buf = ByteBuffer.New()
          Network.Send(86, 1, buf)
        end
      end)
      VtcMod._dailyNextTime = CGTimer.time + 3.0
      return -- Stay at step 9
    end

    -- Step 9: Phái võ tướng level cao nhất đi vận tiêu
    logError("--- [Daily Step 9/9] Dispatching best warrior for transport ---")
    local dispatchStatus = 1 -- ENpcInnStatus.Dispatch = 1 (fallback nếu enum chưa load)
    pcall(function() dispatchStatus = ENpcInnStatus.Dispatch end)
    logError("--- [Daily Step 9/9] ENpcInnStatus.Dispatch = " .. tostring(dispatchStatus) .. " ---")

    -- Debug: check Inn module
    logError("--- [Daily Step 9/9] Inn exists: " .. tostring(Inn ~= nil) .. " ---")
    if Inn then
      logError("--- [Daily Step 9/9] Inn.npcs exists: " .. tostring(Inn.npcs ~= nil) .. " ---")
      logError("--- [Daily Step 9/9] Inn.Lv = " .. tostring(Inn.Lv) .. " ---")
    end

    if Inn and Inn.npcs then
      local bestNpcIndex = nil
      local bestLevel = -1
      local npcCount = 0
      for k, n in pairs(Inn.npcs) do
        npcCount = npcCount + 1
        logError("--- [Daily Step 9/9] NPC innIndex=" .. tostring(k) .. " status=" .. tostring(n.status) .. " level=" .. tostring(n.level) .. " name=" .. tostring(n.name) .. " ---")
        -- Chỉ chọn võ tướng KHÔNG đang phái (status ~= Dispatch)
        if n and n.status ~= dispatchStatus then
          if n.level > bestLevel then
            bestLevel = n.level
            bestNpcIndex = k
          end
        end
      end
      logError("--- [Daily Step 9/9] Inn has " .. npcCount .. " NPCs total ---")

      if bestNpcIndex then
        local buf = ByteBuffer.New()
        buf:WriteByte(bestNpcIndex)
        Network.Send(86, 2, buf)
        logError("--- [Daily Step 9/9] SUCCESS: Dispatched warrior innIndex=" .. bestNpcIndex .. " Lv." .. bestLevel .. " ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 9/9: ✅ Đã phái võ tướng Lv." .. bestLevel .. " đi vận tiêu.") end
      else
        logError("--- [Daily Step 9/9] SKIP: No available warrior (all dispatched or inn empty) ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 9/9: ⚠ Không có võ tướng rảnh trong khách sạn.") end
      end
    else
      logError("--- [Daily Step 9/9] SKIP: Inn.npcs is nil ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 9/9: ⚠ Không tải được dữ liệu khách sạn.") end
    end
    VtcMod._dailyNextTime = CGTimer.time + 3.0
    VtcMod._dailyStep = 10

  elseif step == 10 then
    -- Step 10: Tự động Hợp vật phẩm rác
    logError("--- [Daily Step 10/10] Auto Synthesis ---")
    local combined = false
    pcall(function()
      local myBag = nil
      if Item and type(Item.GetBag) == "function" then
        myBag = Item.GetBag(1)
      elseif Item then
        myBag = Item.bag
      end
      if myBag then
        local validItems = {}
        for k, v in pairs(myBag) do
          if v and v.Id and itemDatas and itemDatas[v.Id] then
            local fitType = itemDatas[v.Id].fitType or 0
            local quality = itemDatas[v.Id].quality or 0
            local kind = itemDatas[v.Id].kind or 0
            local restrict = itemDatas[v.Id].restrict or 0
            
            -- Bỏ qua trang bị (vũ khí, quần áo...)
            local isEquip = Item.IsTypeOfEquips(fitType)
            -- Các loại rác, HP, SP, gỗ, quặng, giấy, v.v. (kind từ 16-36 hoặc 40-46)
            local isTrash = (kind >= 16 and kind <= 36) or (kind >= 40 and kind <= 46)
            -- Kiểm tra xem vật phẩm có bị cấm hợp thành không (restrict & 8 == 0)
            local canCompound = false
            if bit and bit.band then
              canCompound = (bit.band(restrict, 8) == 0)
            else
              -- Fallback nếu không có thư viện bit (thường TS VTC có)
              canCompound = true 
            end

            -- Filter: White Quality (0) AND isTrash AND NOT isEquip AND canCompound
            if quality == 0 and isTrash and not isEquip and canCompound then
              local price = itemDatas[v.Id].price or 999999
              local level = itemDatas[v.Id].level or 999
              table.insert(validItems, {
                bagIndex = k, 
                price = price,
                level = level,
                quant = v.quant,
                id = v.Id
              })
            end
          end
        end
        
        -- Sort by price ascending, then level ascending
        table.sort(validItems, function(a, b)
          if a.price ~= b.price then return a.price < b.price end
          if a.level ~= b.level then return a.level < b.level end
          return a.id < b.id
        end)

        local bagIndexes = {}
        for _, item in ipairs(validItems) do
          -- Select different slot indices to avoid transaction block / same slot compounding
          table.insert(bagIndexes, item.bagIndex)
          if #bagIndexes >= 2 then break end
        end
        if #bagIndexes >= 2 then
          local buf = ByteBuffer.New()
          buf:WriteByte(bagIndexes[1])
          buf:WriteInt32(1)
          buf:WriteByte(bagIndexes[2])
          buf:WriteInt32(1)
          buf:WriteByte(0)
          buf:WriteInt32(0)
          buf:WriteByte(1) -- kind 1 (general compound)
          Network.Send(23, 14, buf)
          combined = true
          logError("--- [Daily Step 10/10] Sent Synthesis packet for bag indexes: " .. bagIndexes[1] .. " and " .. bagIndexes[2] .. " ---")
          if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 10/10: ✅ Đã Hợp thành công 2 vật phẩm rác.") end
        end
      end
    end)
    if not combined then
      logError("--- [Daily Step 10/10] SKIP: Not enough equipment items to combine ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] Bước 10/10: ⚠ Không có đủ đồ rác (Trang bị Trắng) để Hợp.") end
    end

    -- Chuyển sang Task 6: Boss Thế Giới
    VtcMod._dailyNextTime = CGTimer.time + 1.0
    VtcMod._dailyStep = 11

  -- ========================================
  -- TASK 6: Boss Thế Giới (Steps 11-13)
  -- ========================================
  elseif step == 11 then
    -- Step 11: Navigate tới khu vực Boss trên Trác Quận (SceneId 12001)
    -- Tọa độ (1830, 1170) là vị trí Boss NPC cluster (xác nhận qua logcat 24/07/2026)
    logError("--- [Daily Step 11] Navigating to World Boss area (SceneId 12001, pos 1830,1170) ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\140\141 Bước 11: Đang di chuyển tới Boss Thế Giới...") end
    
    -- Kiểm tra nếu đã ở map 12001 thì bỏ qua navigation, đi thẳng đến local move
    if SceneManager and SceneManager.sceneId == 12001 then
      logError("--- [Daily Step 11] Already at SceneId 12001, moving to Boss area ---")
      VtcMod._dailyNextTime = CGTimer.time + 1.0
      VtcMod._dailyStep = 11.7
    else
      pcall(function()
        -- Sử dụng Wrap teleport tới cổng Trác Quận (310, 1530) trước
        MarkManager.StartNavigation(0, 12001, 1, Vector2.New(310, 1530), 0)
      end)
      VtcMod._dailyNavTimeout = 0
      VtcMod._dailyNextTime = CGTimer.time + 3.0
      VtcMod._dailyStep = 11.5
    end

  elseif step == 11.5 then
    -- Chờ đến map 12001
    if SceneManager and SceneManager.sceneId == 12001 then
      logError("--- [Daily Step 11.5] Arrived at SceneId 12001! Moving to Boss area... ---")
      VtcMod._dailyNextTime = CGTimer.time + 1.0
      VtcMod._dailyStep = 11.7
    else
      -- Vẫn đang di chuyển, chờ tiếp
      logError("--- [Daily Step 11.5] Still navigating, current sceneId=" .. tostring(SceneManager and SceneManager.sceneId or "nil") .. " ---")
      VtcMod._dailyNextTime = CGTimer.time + 3.0
      -- Timeout safety: nếu chờ quá lâu (~60s), skip task
      VtcMod._dailyNavTimeout = (VtcMod._dailyNavTimeout or 0) + 1
      if VtcMod._dailyNavTimeout > 20 then
        logError("--- [Daily Step 11.5] TIMEOUT: Could not reach map 12001, skipping WorldBoss ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\140\141 Bước 11: ⚠ Không thể di chuyển tới Boss Thế Giới, bỏ qua.") end
        VtcMod._dailyNavTimeout = 0
        VtcMod._dailyStep = 14 -- Skip tới phó bản đội
      end
    end

  elseif step == 11.7 then
    -- Step 11.7 (NEW): Đảm bảo nhân vật đã di chuyển sát Boss NPC
    local pX = Role.player.position and Role.player.position.x or 0
    local pY = Role.player.position and Role.player.position.y or 0
    local distSq = (pX - 1830)^2 + (pY - 1170)^2
    
    if distSq < 90000 then -- Khoảng cách < 300 (tức là đã đến khu vực Boss)
      logError("--- [Daily Step 11.7] Arrived at Boss area! Moving to Step 12 ---")
      VtcMod._dailyNextTime = CGTimer.time + 1.0
      VtcMod._dailyStep = 12
    else
      -- Chưa đến nơi, tiếp tục StartNavigation (tốt hơn SendMove cho khoảng cách xa)
      pcall(function()
        MarkManager.StartNavigation(0, 12001, 1, Vector2.New(1830, 1170), 0)
      end)
      logError("--- [Daily Step 11.7] Walking to Boss area (dist: " .. math.floor(math.sqrt(distSq)) .. ") ---")
      
      VtcMod._dailyNavTimeout = (VtcMod._dailyNavTimeout or 0) + 1
      if VtcMod._dailyNavTimeout > 30 then -- Chờ tối đa ~90s
        logError("--- [Daily Step 11.7] TIMEOUT moving to Boss, forcing Step 12 ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] ⚠ Đi bộ quá lâu, ép buộc tương tác Boss.") end
        VtcMod._dailyNavTimeout = 0
        VtcMod._dailyStep = 12
      else
        VtcMod._dailyNextTime = CGTimer.time + 3.0
      end
    end

  elseif step == 12 then
    -- Step 12: Request WorldBoss data + Di chuyển đến sát NPC + Click NPC Boss
    logError("--- [Daily Step 12] Requesting WorldBoss data (065-001) and finding Boss NPC ---")
    VtcMod._dailyNavTimeout = 0
    VtcMod._dailyBossEntered = false
    VtcMod._dailyBossWaitCount = 0
    
    -- Gửi 065-001 để xin data boss
    pcall(function() Network.Send(65, 1) end)
    
    -- Tìm NPC Boss trên map: iterate qua Role.mapNpcs tìm MapNpc có eventNpcData
    -- Ưu tiên NPC gần khu vực Boss (1750-1850, 1100-1200)
    local bossFound = false
    pcall(function()
      local bestNpc = nil
      local bestDistSq = math.huge
      local bossAreaX, bossAreaY = 1830, 1170
      
      if Role and Role.mapNpcs then
        for idx, npc in pairs(Role.mapNpcs) do
          if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData then
            local npcName = ""
            if npc.npcId and npcDatas and npcDatas[npc.npcId] and npcDatas[npc.npcId].name then
              npcName = npcDatas[npc.npcId].name
            end
            local npcX = npc.position and math.floor(npc.position.x) or 0
            local npcY = npc.position and math.floor(npc.position.y) or 0
            logError("--- [Daily Step 12] MapNpc index=" .. tostring(idx) .. " npcId=" .. tostring(npc.npcId) .. " name=" .. tostring(npcName) .. " pos=(" .. npcX .. "," .. npcY .. ") ---")
            
            -- Tính khoảng cách đến khu vực Boss
            local dx = npcX - bossAreaX
            local dy = npcY - bossAreaY
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then
              bestDistSq = distSq
              bestNpc = npc
            end
          end
        end
      end
      
      -- Fallback: quét Role.roles nếu Role.mapNpcs trống
      if not bestNpc and Role and Role.roles then
        for idx, role in pairs(Role.roles) do
          if role and role.kind == EHuman.MapNpc and role.data and role.data.eventNpcData then
            local npcX = role.position and math.floor(role.position.x) or 0
            local npcY = role.position and math.floor(role.position.y) or 0
            local dx = npcX - bossAreaX
            local dy = npcY - bossAreaY
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then
              bestDistSq = distSq
              bestNpc = role
            end
          end
        end
      end
      
      if bestNpc then
        -- Di chuyển đến sát NPC trước khi Trig
        if bestNpc.position and MoveController and MoveController.SendMove then
          local targetX = math.floor(bestNpc.position.x)
          local targetY = math.floor(bestNpc.position.y)
          logError("--- [Daily Step 12] Moving to Boss NPC at (" .. targetX .. "," .. targetY .. ") ---")
          MoveController.SendMove(targetX, targetY)
        end
        
        -- Delay nhỏ rồi Trig NPC (dùng DoFunctionDelay để đợi di chuyển xong)
        local npcRef = bestNpc
        CGTimer.DoFunctionDelay(1.5, function()
          pcall(function()
            logError("--- [Daily Step 12] Triggering Boss NPC interaction ---")
            npcRef:OnInteractive(EInteractive.Trig)
          end)
        end)
        
        bossFound = true
        VtcMod.autoSkipEventToBattle = true -- Auto skip dialog -> vào trận
        logError("--- [Daily Step 12] Found Boss NPC! autoSkipEventToBattle=true ---")
      end
    end)
    
    if not bossFound then
      logError("--- [Daily Step 12] Boss NPC not found, will retry in Step 12.5 ---")
    end
    
    VtcMod._dailyNextTime = CGTimer.time + 4.0
    VtcMod._dailyStep = 12.5

  elseif step == 12.5 then
    -- Chờ vào trận Boss và kết thúc
    -- Auto click UIResult nếu hiện (phần thưởng)
    pcall(function()
      if UI and UIResult and UI.IsVisible(UIResult) then
        logError("--- [Daily Step 12.5] UIResult visible! Auto-clicking confirm ---")
        if UIResult.OnClickfun1 then UIResult.OnClickfun1(nil) end
      end
    end)
    
    -- Thêm logic dự phòng ÉP CHỌN LỰA CHỌN 1 "Ta muốn khiêu chiến"
    pcall(function()
      if UI and UICheck and UI.IsVisible(UICheck) then
        logError("--- [Daily Step 12.5] UICheck visible! Forcing Option 1 (Ta muốn khiêu chiến) ---")
        UI.Close(UICheck, 1)
      end
    end)
    
    if Role.player.war ~= EWar.None then
      -- Đang trong trận, chờ tiếp
      logError("--- [Daily Step 12.5] In WorldBoss battle, waiting... ---")
      VtcMod._dailyBossEntered = true
      VtcMod._dailyNextTime = CGTimer.time + 3.0
    else
      -- Đã ra khỏi trận
      if VtcMod._dailyBossEntered then
        logError("--- [Daily Step 12.5] WorldBoss battle completed! ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\140\141 Bước 12: ✅ Đã hoàn thành đánh Boss Thế Giới!") end
        VtcMod._dailyBossEntered = false
        VtcMod.autoSkipEventToBattle = false
        VtcMod._dailyNextTime = CGTimer.time + 3.0
        VtcMod._dailyStep = 13
      else
        -- Chưa vào trận, có thể đang load dialog hoặc NPC chưa tìm thấy
        VtcMod._dailyBossWaitCount = (VtcMod._dailyBossWaitCount or 0) + 1
        
        -- Retry: cứ mỗi 3 lần poll (~9s), thử scan lại NPC và click
        if VtcMod._dailyBossWaitCount % 3 == 0 then
          logError("--- [Daily Step 12.5] Retry #" .. VtcMod._dailyBossWaitCount .. ": Re-scanning Boss NPC ---")
          pcall(function()
            local bossAreaX, bossAreaY = 1830, 1170
            local bestNpc = nil
            local bestDistSq = math.huge
            local npcSource = Role.mapNpcs or Role.roles
            if npcSource then
              for _, npc in pairs(npcSource) do
                if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData and npc.position then
                  local dx = npc.position.x - bossAreaX
                  local dy = npc.position.y - bossAreaY
                  local distSq = dx * dx + dy * dy
                  if distSq < bestDistSq then
                    bestDistSq = distSq
                    bestNpc = npc
                  end
                end
              end
            end
            if bestNpc then
              if MoveController and MoveController.SendMove then
                MoveController.SendMove(math.floor(bestNpc.position.x), math.floor(bestNpc.position.y))
              end
              CGTimer.DoFunctionDelay(1.0, function()
                pcall(function()
                  bestNpc:OnInteractive(EInteractive.Trig)
                  VtcMod.autoSkipEventToBattle = true
                end)
              end)
            end
          end)
        end
        
        if VtcMod._dailyBossWaitCount > 20 then -- ~60s timeout
          logError("--- [Daily Step 12.5] TIMEOUT waiting for boss battle, skipping ---")
          if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\140\141 Bước 12: ⚠ Hết thời gian chờ Boss, bỏ qua.") end
          VtcMod._dailyBossWaitCount = 0
          VtcMod.autoSkipEventToBattle = false
          VtcMod._dailyStep = 14
        else
          VtcMod._dailyNextTime = CGTimer.time + 3.0
        end
      end
    end

  elseif step == 13 then
    -- Step 13: Claim reward Boss (124-004) nếu có
    logError("--- [Daily Step 13] Claiming WorldBoss reward (124-004) ---")
    pcall(function()
      Network.Send(124, 4)
    end)
    
    -- Auto click UIResult nếu còn hiện
    pcall(function()
      if UI and UIResult and UI.IsVisible(UIResult) then
        if UIResult.OnClickfun1 then UIResult.OnClickfun1(nil) end
      end
    end)
    
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\140\141 Bước 13: ✅ Đã nhận phần thưởng Boss Thế Giới.") end
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    VtcMod._dailyStep = 14

  -- ========================================
  -- TASK 7: Phó Bản Đội cấp 20 (Steps 14-17)
  -- ========================================
  elseif step == 14 then
    -- Step 14: Request danh sách phó bản
    logError("--- [Daily Step 14] Requesting dungeon list for Team Dungeon (047-001) ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 14: Đang tải danh sách phó bản đội...") end
    Network.Send(47, 1)
    
    VtcMod._dailyTeamDungeonWait = 0
    VtcMod._dailyNextTime = CGTimer.time + 2.0
    VtcMod._dailyStep = 15

  elseif step == 15 then
    -- Step 15: Tìm phó bản đội cấp 20 và tạo phòng
    logError("--- [Daily Step 15] Finding Team Dungeon Lv20 and creating room ---")
    -- Refresh useableDungeons
    if Dungeon and Dungeon.InitAvailableDungeonDatas then
      pcall(Dungeon.InitAvailableDungeonDatas)
    end
    
    if not Dungeon or not Dungeon.useableDungeons then
      logError("--- [Daily Step 15] SKIP: Dungeon module not loaded ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 15: ⚠ Module Dungeon chưa sẵn sàng.") end
      VtcMod._dailyStep = 18
    else
      local teamDungeonId, hasFreeAttempt = VtcMod.FindAvailableTeamDungeon()
      logError("--- [Daily Step 15] FindAvailableTeamDungeon returned: id=" .. tostring(teamDungeonId) .. ", hasFree=" .. tostring(hasFreeAttempt) .. " ---")
      
      if teamDungeonId ~= 0 and hasFreeAttempt then
        -- Reset isSending guard
        if Dungeon then Dungeon.isSending = false end
        -- CreateDungeon với kind=1 (team) → tạo phòng
        local ok, enterErr = pcall(Dungeon.SendCreateDungeon, teamDungeonId, false, 1)
        if ok then
          logError("--- [Daily Step 15] SUCCESS: Created Team Dungeon room ID " .. teamDungeonId .. " ---")
          if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 15: ✅ Đã tạo phòng phó bản đội cấp 20.") end
          VtcMod._dailyTeamDungeonId = teamDungeonId
          VtcMod._dailyNextTime = CGTimer.time + 2.0
          VtcMod._dailyStep = 16
        else
          logError("--- [Daily Step 15] ERROR: SendCreateDungeon failed - " .. tostring(enterErr) .. " ---")
          if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 15: ❌ Lỗi tạo phòng phó bản đội.") end
          VtcMod._dailyStep = 18
        end
      else
        logError("--- [Daily Step 15] SKIP: No team dungeon Lv20 available (id=" .. tostring(teamDungeonId) .. " hasFree=" .. tostring(hasFreeAttempt) .. ") ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 15: ⚠ Hết lượt phó bản đội cấp 20.") end
        VtcMod._dailyStep = 18
      end
    end

  elseif step == 16 then
    -- Step 16: Bắt đầu phó bản đội (solo mode) - SendStartDungeon
    logError("--- [Daily Step 16] Starting Team Dungeon (solo mode) via 047-012 ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 16: Bắt đầu phó bản đội (solo)...") end
    
    -- Bật auto skip dialog cho toàn bộ chuỗi event trong phó bản đội
    VtcMod.autoSkipEventToBattle = true
    VtcMod._dailyTeamDungeonWait = 0
    VtcMod._dailyTeamNpcClickCount = 0
    VtcMod._dailyTeamLastNpcClickTime = 0
    
    pcall(function()
      -- Ưu tiên gọi hàm game nếu có
      if Dungeon and Dungeon.SendStartDungeon then
        logError("--- [Daily Step 16] Using Dungeon.SendStartDungeon() ---")
        Dungeon.SendStartDungeon()
      else
        -- Fallback: gửi packet trực tiếp (zero-payload)
        logError("--- [Daily Step 16] Fallback: Direct Network.Send(47, 12) ---")
        Network.Send(47, 12)
      end
    end)
    
    VtcMod._dailyNextTime = CGTimer.time + 5.0
    VtcMod._dailyStep = 17

  elseif step == 17 then
    -- Step 17: Phó bản đội — auto skip dialog + scan NPC + click + wait battles
    -- Logcat xác nhận: dungeon SceneId=62002, 4 trận, mỗi trận có dialog chain (Event 0/1)
    -- Server tự gửi event chain qua 020-001 → chỉ cần skip UICheck dialog
    
    -- 1. Auto click UIResult nếu hiện (phần thưởng phó bản)
    pcall(function()
      if UI and UIResult and UI.IsVisible(UIResult) then
        logError("--- [Daily Step 17] UIResult visible! Auto-clicking confirm ---")
        if UIResult.OnClickfun1 then UIResult.OnClickfun1(nil) end
      end
    end)
    
    -- 2. Auto skip UICheck dialog bên trong phó bản (bổ sung cho UICheck hook)
    pcall(function()
      if UI and UICheck and UI.IsVisible(UICheck) then
        logError("--- [Daily Step 17] UICheck visible inside dungeon! Auto-closing ---")
        -- Thử click Next trước (dialog thường)
        if UICheck.OnClick_Next then
          UICheck.OnClick_Next()
        else
          -- Fallback: Close với result=1
          UI.Close(UICheck, 1)
        end
      end
    end)
    
    -- 3. Kiểm tra phó bản đã hoàn thành chưa
    if Dungeon and Dungeon.nowDungeonId == 0 and Role.player.war == EWar.None then
      logError("--- [Daily Step 17] Team Dungeon completed! ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 17: ✅ Đã hoàn thành phó bản đội cấp 20!") end
      VtcMod.autoSkipEventToBattle = false
      VtcMod._dailyNextTime = CGTimer.time + 3.0
      VtcMod._dailyStep = 18
    else
      -- Vẫn đang trong phó bản
      VtcMod._dailyTeamDungeonWait = (VtcMod._dailyTeamDungeonWait or 0) + 1
      
      -- 4. Nếu không đang trong trận → scan NPC và click
      if Role.player.war == EWar.None then
        if VtcMod._dailyTeamWasInBattle then
            VtcMod._dailyTeamWasInBattle = false
            -- Đánh xong trận -> Tự động sang waypoint tiếp theo ngay lập tức!
            VtcMod._dailyTeamDungeonWave = (VtcMod._dailyTeamDungeonWave or 1) + 1
            VtcMod._dailyTeamWpWait = 0
            logError("--- [Daily Step 17] Battle ended. Fast-advancing to Waypoint " .. VtcMod._dailyTeamDungeonWave .. " ---")
        end

        -- Kiểm tra UICheck có đang hiện (đang trong event chain) → không scan NPC
        local dialogActive = false
        pcall(function()
          if UI and UICheck and UI.IsVisible(UICheck) then
            dialogActive = true
          end
        end)
        
        if not dialogActive then
          -- Cooldown: chỉ điều hướng nếu đã qua ít nhất 3s kể từ lần click trước
          local lastClickTime = VtcMod._dailyTeamLastNpcClickTime or 0
          local canClick = (CGTimer.time - lastClickTime) >= 3.0
          
          if canClick then
            VtcMod._dailyTeamLastNpcClickTime = CGTimer.time
            pcall(function()
              local pX = Role.player.position and Role.player.position.x or 0
              local pY = Role.player.position and Role.player.position.y or 0
              local targetPos = nil

              if SceneManager and SceneManager.sceneId == 62002 then
                VtcMod._dailyTeamDungeonWave = VtcMod._dailyTeamDungeonWave or 1
                local waypoints = {
                    {x = 50, y = 800},
                    {x = 470, y = 700},
                    {x = 730, y = 560},
                    {x = 590, y = 340}
                }
                
                local wp = waypoints[VtcMod._dailyTeamDungeonWave]
                if wp then
                    local dx = pX - wp.x
                    local dy = pY - wp.y
                    local distSq = dx * dx + dy * dy
                    
                    if distSq < 900 then -- < 30 units (đã đến nơi)
                        VtcMod._dailyTeamWpWait = (VtcMod._dailyTeamWpWait or 0) + 1
                        -- Đợi 3 poll (~9 giây) tại vị trí, nếu không có dialog/battle nào thì tự next
                        if VtcMod._dailyTeamWpWait > 3 then
                            VtcMod._dailyTeamWpWait = 0
                            VtcMod._dailyTeamDungeonWave = VtcMod._dailyTeamDungeonWave + 1
                            logError("--- [Daily Step 17] Waypoint idle timeout, advancing to wave " .. VtcMod._dailyTeamDungeonWave .. "... ---")
                        end
                    else
                        VtcMod._dailyTeamWpWait = 0
                        targetPos = Vector2.New(wp.x, wp.y)
                    end
                end
              end

              -- 2. Nếu có Waypoint, điều hướng đi tới
              if targetPos then
                logError("--- [Daily Step 17] Auto navigating to dungeon wave " .. VtcMod._dailyTeamDungeonWave .. " at (" .. targetPos.x .. "," .. targetPos.y .. ") ---")
                MarkManager.StartNavigation(0, SceneManager.sceneId, 1, targetPos, 0)
              else
                -- 3. Fallback: Quét NPC ẩn (logic cũ) nếu không có waypoint hoặc đã đến điểm cuối
                if Role and Role.mapNpcs then
                  local bestNpc = nil
                  local bestDistSq = math.huge
                  
                  for _, npc in pairs(Role.mapNpcs) do
                    if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData
                       and npc.data.eventNpcData.id and npc.data.eventNpcData.id ~= 0
                       and npc.war == EWar.None and npc.position then
                      local dx = npc.position.x - pX
                      local dy = npc.position.y - pY
                      local distSq = dx * dx + dy * dy
                      if distSq < bestDistSq then
                        bestDistSq = distSq
                        bestNpc = npc
                      end
                    end
                  end
                  
                  if bestNpc then
                    local targetX = math.floor(bestNpc.position.x)
                    local targetY = math.floor(bestNpc.position.y)
                    VtcMod._dailyTeamNpcClickCount = (VtcMod._dailyTeamNpcClickCount or 0) + 1
                    
                    logError("--- [Daily Step 17] Found dungeon NPC at (" .. targetX .. "," .. targetY .. "), moving + clicking (attempt #" .. VtcMod._dailyTeamNpcClickCount .. ") ---")
                    
                    if MoveController and MoveController.SendMove then
                      MoveController.SendMove(targetX, targetY)
                    end
                    
                    local npcRef = bestNpc
                    CGTimer.DoFunctionDelay(1.5, function()
                      pcall(function()
                        if npcRef and npcRef.OnInteractive then
                          npcRef:OnInteractive(EInteractive.Trig)
                          logError("--- [Daily Step 17] Triggered dungeon NPC interaction ---")
                        end
                      end)
                    end)
                  end
                end
              end
            end)
          end -- end canClick
        else
          logError("--- [Daily Step 17] Dialog active (UICheck visible), waiting for event chain ---")
        end
      else
        VtcMod._dailyTeamWasInBattle = true
        logError("--- [Daily Step 17] In battle, waiting... ---")
      end
      
      logError("--- [Daily Step 17] Still in Team Dungeon (dungeonId=" .. tostring(Dungeon and Dungeon.nowDungeonId or "nil") .. ", wait=" .. VtcMod._dailyTeamDungeonWait .. "), polling... ---")
      
      -- Timeout 300s (~100 polls × 3s) thay vì 120s, vì dungeon có 4 trận mất ~4.5 phút
      if VtcMod._dailyTeamDungeonWait > 100 then
        logError("--- [Daily Step 17] TIMEOUT waiting for Team Dungeon (300s), skipping ---")
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\143\176 Bước 17: \226\154\160 Hết thời gian chờ phó bản đội, bỏ qua.") end
        VtcMod._dailyTeamDungeonWait = 0
        VtcMod.autoSkipEventToBattle = false
        VtcMod._dailyStep = 18
      else
        VtcMod._dailyNextTime = CGTimer.time + 3.0
      end
    end

  -- ========================================
  -- TASK 8: Nhận phần thưởng Nhiệm Vụ Ngày
  -- ========================================
  elseif step == 18 then
    logError("--- [Daily Step 18] Claiming all daily quest rewards ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \240\159\142\129 Bước 18: Đang nhận phần thưởng Nhiệm Vụ Ngày...") end
    
    -- Claim individual missions (091-003)
    pcall(VtcMod.ClaimDailyAwards)
    
    -- Claim Active Points Chests 1 to 5 (091-002)
    pcall(function()
      for i = 1, 5 do
        local buf = ByteBuffer.New()
        buf:WriteByte(i)
        Network.Send(91, 2, buf)
      end
    end)
    
    VtcMod._dailyNextTime = CGTimer.time + 3.0
    VtcMod._dailyStep = 19

  -- ========================================
  -- HOÀN THÀNH TẤT CẢ — Tự nhả button
  -- ========================================
  elseif step == 19 then
    logError("--- [Daily] ====== ALL STEPS COMPLETED SUCCESSFULLY ====== ---")
    if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] \226\156\133 HOÀN THÀNH TẤT CẢ CÁC NHIỆM VỤ NGÀY!") end
    ShowCenterMessage("\226\156\133 Hoàn thành tất cả nhiệm vụ ngày!")
    VtcMod._dailyStep = 0 -- Auto-release: button tự nhả về TẮT
    -- Refresh UI để button hiển thị trạng thái TẮT
    pcall(function()
      if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() end
      if UIDebug and UIDebug.UpdateStatusText then UIDebug.UpdateStatusText() end
    end)
  end
end

-- ==============================================================================
-- 40 NPC STATE MACHINE
-- ==============================================================================
function VtcMod.Execute40NPCStep()
  if not VtcMod.auto40NPC or not Role or not Role.player then return end
  
  -- [AUDIT FIX] Tự động đóng bảng Kết Quả Trận Đánh (UIResult) bất cứ lúc nào nó hiện lên
  -- Ngăn chặn UI hấp thụ click (block raycast) khiến việc click NPC tiếp theo bị hỏng.
  pcall(function()
    if UI and UIResult and UI.IsVisible(UIResult) then
      if UIResult.OnClickfun1 then UIResult.OnClickfun1(nil) end
    end
  end)
  
  -- Fast Battle Loop Pattern
  if Role.player.war ~= EWar.None then 
    -- Đang trong trận đánh, đánh dấu cờ và chờ
    VtcMod._40NpcWasInBattle = true
    VtcMod._40NpcLastActionTime = CGTimer.time + 1.0
    return
  else
    -- Nếu vừa thoát trận, lập tức quay lại Step 2 để tìm NPC ngay lập tức
    if VtcMod._40NpcWasInBattle then
       logError("--- [40NPC] Battle Ended! Fast looping back to Anchor... ---")
       VtcMod._40NpcWasInBattle = false
       VtcMod._40NpcStep = 2
       VtcMod._40NpcLastActionTime = CGTimer.time + 0.5
       return
    end
  end
  
  local step = VtcMod._40NpcStep or 1
  
  if step == 1 then
    -- [AUDIT FIX] Đảm bảo cờ chiến đấu được reset sạch sẽ khi user vừa bật nút
    VtcMod._40NpcWasInBattle = false
    
    -- Bước 1: Kiểm tra Map và Điều hướng
    if SceneManager.sceneId ~= VtcMod.cfg40NPC_MapID then
      logError("--- [40NPC] Step 1: Navigating to Map " .. tostring(VtcMod.cfg40NPC_MapID) .. " ---")
      if MarkManager and MarkManager.StartNavigation then
         local tgX = VtcMod._40NpcAnchorX or VtcMod.cfg40NPC_TargetX
         local tgY = VtcMod._40NpcAnchorY or VtcMod.cfg40NPC_TargetY
         MarkManager.StartNavigation(0, VtcMod.cfg40NPC_MapID, 1, Vector2.New(tgX, tgY), 0)
      end
      VtcMod._40NpcLastActionTime = CGTimer.time + 3.0
    else
      VtcMod._40NpcStep = 2
      VtcMod._40NpcLastActionTime = CGTimer.time + 0.5
    end
    
  elseif step == 2 then
    -- Bước 2: Di chuyển đến Anchor (Neo)
    logError("--- [40NPC] Step 2: Moving to Anchor ---")
    local tgX = VtcMod._40NpcAnchorX or VtcMod.cfg40NPC_TargetX
    local tgY = VtcMod._40NpcAnchorY or VtcMod.cfg40NPC_TargetY
    
    local distSq = 999999
    if Role.player and Role.player.position then
       local dx = Role.player.position.x - tgX
       local dy = Role.player.position.y - tgY
       distSq = dx * dx + dy * dy
    end
    
    if distSq > 900 then -- Khoảng cách > 30 pixels
       if MarkManager and MarkManager.StartNavigation then
         MarkManager.StartNavigation(0, VtcMod.cfg40NPC_MapID, 1, Vector2.New(tgX, tgY), 0)
       end
       VtcMod._40NpcLastActionTime = CGTimer.time + 2.0
    else
       -- Đã tới nơi, chuyển sang tìm NPC
       VtcMod._40NpcStep = 3
       VtcMod._40NpcLastActionTime = CGTimer.time + 0.5
    end
    
  elseif step == 3 then
    -- Bước 3: Tìm NPC gần Điểm Neo nhất (Bỏ qua NPC rác)
    logError("--- [40NPC] Step 3: Finding Target NPC near Anchor ---")
    local closestNpc = nil
    local minDistSq = 999999
    local tgX = VtcMod._40NpcAnchorX or VtcMod.cfg40NPC_TargetX
    local tgY = VtcMod._40NpcAnchorY or VtcMod.cfg40NPC_TargetY
    
    local npcSource = Role.mapNpcs or Role.roles
    if npcSource then
      for k, npc in pairs(npcSource) do
        -- LƯU Ý: KHÔNG check npc.gameObject vì nhiều Event NPC là tàng hình (invisible)
        if npc and (npc.kind == EHuman.MapNpc or npc.kind == 1) and npc.position then
          local dx = npc.position.x - tgX
          local dy = npc.position.y - tgY
          local distSq = dx * dx + dy * dy
          if distSq < 22500 and distSq < minDistSq then -- 150^2 = 22500
             minDistSq = distSq
             closestNpc = npc
          end
        end
      end
    end
    
    if closestNpc then
       logError("--- [40NPC] Found NPC! Triggering OnInteractive ---")
       if MoveController and MoveController.SendMove then
          MoveController.SendMove(closestNpc.position.x, closestNpc.position.y)
       end
       
       -- [AUDIT FIX] Bọc pcall vào closure của Delay Timer để ngăn chặn Memory/Object Destroyed Leak
       CGTimer.DoFunctionDelay(1.0, function()
          pcall(function()
            -- Trích xuất ID sự kiện. C# Lua Wrapper có thể dùng các tên thuộc tính khác nhau
            local trigId = closestNpc.id or closestNpc.npcid or closestNpc.Id or (closestNpc.data and closestNpc.data.id) or (closestNpc.data and closestNpc.data.npcid)
            
            if EventManager and EventManager.TriggerEvent then
               if trigId then
                  logError("--- [40NPC] Safely Triggering Dynamic Event ID: " .. tostring(trigId) .. " ---")
                  EventManager.TriggerEvent(1, trigId, nil, true)
               else
                  -- Nếu không thể đọc được ID từ object, bắn trực tiếp ID 3 và 5 (nhặt từ logcat của User)
                  logError("--- [40NPC] Dynamic ID is NIL! Forcing Fallback Event IDs: 3 and 5 ---")
                  EventManager.TriggerEvent(1, 3, nil, true)
                  EventManager.TriggerEvent(1, 5, nil, true)
               end
            end
            
            -- [BỎ HOÀN TOÀN OnInteractive VÌ C# SẼ CRASH DO NPC TÀNG HÌNH KHÔNG CÓ GAMEOBJECT]
          end)
       end)
       
       VtcMod._40NpcWaitDialogTimeout = CGTimer.time + 4.0 
       VtcMod._40NpcStep = 4
       VtcMod._40NpcLastActionTime = CGTimer.time + 1.5
    else
       logError("--- [40NPC] NPC not found, retrying... ---")
       
       -- Fallback: Trực tiếp kích hoạt Event ID 3 và 5 (Dựa vào logcat user)
       -- Chỉ gửi ĐÚNG 2 lệnh duy nhất để tránh kích hoạt hệ thống chống Spam gây Disconnect.
       pcall(function()
          if EventManager and EventManager.TriggerEvent then
             logError("--- [40NPC] Force triggering Fallback Event Kind=1 No=3 and 5 ---")
             EventManager.TriggerEvent(1, 3, nil, true)
             EventManager.TriggerEvent(1, 5, nil, true)
          end
       end)
       
       VtcMod._40NpcWaitDialogTimeout = CGTimer.time + 4.0 
       VtcMod._40NpcStep = 4
       VtcMod._40NpcLastActionTime = CGTimer.time + 1.5
    end
    
  elseif step == 4 then
    -- Bước 4: Skip Dialog (Cực kỳ an toàn và toàn diện)
    logError("--- [40NPC] Step 4: Skipping Dialog ---")
    
    local hasDialog = false
    
    -- Xử lý hộp thoại (UICheck)
    if UI and UICheck and UI.IsVisible(UICheck) then
       hasDialog = true
       logError("--- [40NPC] UICheck is visible, forcing Option 1 (Boss TG Style) ---")
       pcall(function()
         UI.Close(UICheck, 1) -- Ép chọn lựa chọn 1
       end)
       VtcMod._40NpcWaitDialogTimeout = CGTimer.time + 3.0 -- Refresh timeout khi dang click
    end
    
    -- Xử lý hội thoại tự động (EventNpc)
    if EventManager and EventManager.IsRunning and EventManager.IsRunning() then
       hasDialog = true
       if EventManager.autoSkipEventToBattle ~= nil then
          EventManager.autoSkipEventToBattle = true
       end
       VtcMod._40NpcWaitDialogTimeout = CGTimer.time + 3.0
    end
    
    if not hasDialog and CGTimer.time > (VtcMod._40NpcWaitDialogTimeout or 0) then
       -- Không thấy dialog và cũng chưa vào trận quá lâu -> Có thể click hụt hoặc kẹt event, spam lại NPC
       logError("--- [40NPC] Dialog timeout, no battle started. Retrying from Step 3... ---")
       VtcMod._40NpcStep = 3
       VtcMod._40NpcLastActionTime = CGTimer.time + 0.5
    else
       -- Đợi load vào trận (sẽ được bắt bởi wasInBattle) hoặc đợi qua hội thoại
       VtcMod._40NpcLastActionTime = CGTimer.time + 0.3
    end
  end
end

function VtcMod.Update()
  -- Hook Network.Send continuously in Update loop to prevent it from being overwritten by game loading sequence
  pcall(function()
    if Network and Network.Send and not Network.isVtcModLoggerHookedV3 then
      local original_Send = Network.Send
      Network.Send = function(kind, code, buffer)
        pcall(function()
          if VtcMod.debugPackets and (kind == 11 or kind == 84 or kind == 37 or kind == 1 or kind == 38 or kind == 83 or kind == 87 or kind == 23) then
             local len = buffer and buffer.length or 0
             logError(string.format("--- [VtcMod Packet] SEND Kind: %d, Code: %d, Len: %d ---", kind, code, len))
          end
        end)
        return original_Send(kind, code, buffer)
      end
      Network.isVtcModLoggerHookedV3 = true
      logError("--- [VtcMod] Network.Send hooked successfully in Update loop! ---")
    end
  end)

  -- =============================================
  -- AUTO RECONNECT (Xử lý Soft Disconnect / Rớt mạng)
  -- =============================================
  pcall(function()
    -- 1. Xử lý bảng thông báo đứt kết nối (UICenterMessage)
    if UI and UICenterMessage and UI.IsVisible(UICenterMessage) then
      if UICenterMessage.text_Message and UICenterMessage.text_Message.text then
        local msg = UICenterMessage.text_Message.text
        -- Bắt các từ khóa rớt mạng
        if string.find(msg, "kết nối") or string.find(msg, "Mất") or string.find(msg, "disconnect") then
          logError("--- [Auto Reconnect] Phat hien bang thong bao mat ket noi, tu dong dong! ---")
          -- BUG 7 FIX: Reset battle state on disconnect to prevent stuck _inBattle=true
          VtcMod._inBattle = false
          UI.Close(UICenterMessage)
          if Game and Game.Logout then Game.Logout() end
          if UILogin then UI.Open(UILogin) end
        end
      end
    end

    -- 2. Xử lý màn hình UILogin
    if UI and UILogin and UI.IsVisible(UILogin) then
      VtcMod._reconnectWait = (VtcMod._reconnectWait or 0) + 1
      if VtcMod._reconnectWait >= 180 then -- Khoảng 5-6 giây (30 ticks/s)
        VtcMod._reconnectWait = 0
        logError("--- [Auto Reconnect] Dang tien hanh tu dong Dang Nhap lai! ---")
        if UILogin.OnClick_Login then
          UILogin.OnClick_Login()
        elseif CGSDK and CGSDK.showLoginForm then
          CGSDK.showLoginForm()
        end
      end
    else
      VtcMod._reconnectWait = 0
    end
  end)

  -- DRM enforcement removed: handled by PC-side ram_stream_deploy.ps1

  -- Proactive RAM Protection on Rooted Devices (Collect Garbage to prevent RAM Dump memory scraping)
  if this.isDeviceRooted then
    this.gcCounter = (this.gcCounter or 0) + 1
    if this.gcCounter >= 300 then
      this.gcCounter = 0
      collectgarbage("collect")
    end
  end



  -- Daily Quests state machine execution
  if VtcMod._dailyStep > 0 and CGTimer.time >= VtcMod._dailyNextTime then
    local success, err = pcall(VtcMod.ExecuteDailyStep)
    if not success then
      logError("--- [Daily] PCALL ERROR: " .. tostring(err) .. " ---")
      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Daily] ERROR: " .. tostring(err)) end
      VtcMod._dailyStep = 0
    end
  end

  -- 40NPC Auto Farm State Machine
  if VtcMod._40NpcStep and VtcMod._40NpcStep > 0 then
    if CGTimer.time >= (VtcMod._40NpcLastActionTime or 0) then
       local success, err = pcall(VtcMod.Execute40NPCStep)
       if not success then
         logError("--- [40NPC] PCALL ERROR: " .. tostring(err) .. " ---")
         VtcMod._40NpcStep = 0
       end
    end
  end

  -- Background Auto-Claim state machine execution
  if Role and Role.playerId and Role.playerId ~= VtcMod._lastPlayerId then
    VtcMod._lastPlayerId = Role.playerId
    VtcMod._autoClaimNextTime = 0
    VtcMod._autoClaimStep = 0
    VtcMod._cachedLoginAward = nil -- Reset cache khi player thay đổi để tránh claim sai data
    logError("--- [AutoClaim] Character changed/logged in, resetting auto-claim to run immediately ---")
  end

  if CGTimer.time >= (VtcMod._autoClaimNextTime or 0) then
    if (VtcMod._autoClaimNextTime or 0) == 0 then
       VtcMod._autoClaimNextTime = CGTimer.time + 5 -- Chay lan dau ngay lap tuc sau 5 giay vao game
    elseif VtcMod._autoClaimStep == 0 then
       if not (FightField and FightField.isInBattle) and Role and Role.player and Role.player.war == EWar.None then
          VtcMod._autoClaimStep = 1
       else
          VtcMod._autoClaimNextTime = CGTimer.time + 30
       end
    end
  end

  if VtcMod._autoClaimStep > 0 and CGTimer.time >= VtcMod._autoClaimNextTime then
    local success, err = pcall(VtcMod.ExecuteAutoClaimSteps)
    if not success then
      logError("--- [AutoClaim] PCALL ERROR: " .. tostring(err) .. " ---")
      VtcMod._autoClaimStep = 0
      VtcMod._autoClaimNextTime = CGTimer.time + (VtcMod._autoClaimInterval or 300)
    end
  end

  -- Dump server IDs for verification
  if Network and Network.servers and not this.dumpedServers then
    local count = 0
    for _ in pairs(Network.servers) do count = count + 1 end
    if count > 0 then
      this.dumpedServers = true
      logError("--- [VtcMod] DUMPING SERVERS ---")
      for k, v in ipairs(Network.servers) do
        logError(string.format("--- [VtcMod] SERVER INDEX: %d | ID: %s | NAME: %s | HOST: %s | PORT: %s ---", k, tostring(v.id), tostring(v.name), tostring(v.host), tostring(v.port)))
      end
    end
  end

  -- QUICK BANK: Dynamic Hook
  pcall(function()
    if UIBank and UIBank.OnOpen and not UIBank.isQuickBankHooked then
      local original_UIBank_OnOpen = UIBank.OnOpen
      UIBank.OnOpen = function(...)
        local ret = original_UIBank_OnOpen(...)
        if VtcMod.quickBankEnabled then
          VtcMod._quickBankStep = 1
          VtcMod._quickBankNextTime = CGTimer.time + 1.5
          VtcMod._quickBankTransferred = 0
          logError("--- [QuickBank] UIBank opened! Scheduling scan in 1.5s ---")
        end
        return ret
      end
      UIBank.isQuickBankHooked = true
      logError("--- [VtcMod] Dynamically hooked UIBank.OnOpen for QuickBank! ---")
    end
  end)

  -- QUICK BANK: State Machine
  pcall(function()
    if VtcMod.quickBankEnabled and VtcMod._quickBankStep > 0 and CGTimer.time >= VtcMod._quickBankNextTime then
      if not (UI and UIBank and UI.IsVisible(UIBank)) then
        VtcMod._quickBankStep = 0
        VtcMod._quickBankQueue = {}
        VtcMod._quickBankQueueIdx = 0
        logError("--- [QuickBank] UIBank closed, aborting. ---")
      else
        local step = VtcMod._quickBankStep
        if step == 1 then
          local bagItems = nil
          local bankItems = nil
          if Item and Item.GetBag then
            bagItems = Item.GetBag(EThings and EThings.Bag or 1)
            bankItems = Item.GetBag(EThings and EThings.Bank or 4)
          end
          
          local bankItemIds = {}
          if bankItems then
            for _, v in pairs(bankItems) do
              if v and v.Id then bankItemIds[v.Id] = true end
            end
          end
          
          local queue = {}
          if bagItems then
            for bagIdx, v in pairs(bagItems) do
              if v and v.Id and bankItemIds[v.Id] then
                table.insert(queue, {bagIndex = bagIdx, itemId = v.Id, quant = v.quant or 1})
              end
            end
          end
          
          VtcMod._quickBankQueue = queue
          VtcMod._quickBankQueueIdx = 1
          
          if #queue > 0 then
            VtcMod._quickBankStep = 2
            VtcMod._quickBankNextTime = CGTimer.time + 0.3
            if Chat and EChannel then
              Chat.AddMessage(EChannel.System, string.format("[QuickBank] Tìm thấy %d item trùng lặp. Đang chuyển...", #queue))
            end
          else
            VtcMod._quickBankStep = 0
            ShowCenterMessage("Không có item trùng lặp giữa Túi và Rương!")
          end
        elseif step == 2 then
          local idx = VtcMod._quickBankQueueIdx
          local queue = VtcMod._quickBankQueue
          
          if idx > #queue then
            VtcMod._quickBankStep = 0
            ShowCenterMessage(string.format("✅ Đã chuyển %d item vào Rương!", VtcMod._quickBankTransferred))
            VtcMod._quickBankQueue = {}
            VtcMod._quickBankQueueIdx = 0
          else
            local item = queue[idx]
            local buf = ByteBuffer.New()
            buf:WriteByte(item.bagIndex)
            buf:WriteInt32(item.quant)
            -- 30 = mainKind (Bank), 2 = Save
            Network.Send(30, 2, buf)
            
            VtcMod._quickBankTransferred = VtcMod._quickBankTransferred + 1
            VtcMod._quickBankQueueIdx = idx + 1
            VtcMod._quickBankNextTime = CGTimer.time + 0.5
          end
        end
      end
    end
  end)

  -- =============================================
  -- AUTO FLEE NO PARTY
  -- When in battle with no party, force all units to escape
  -- =============================================
  pcall(function()
    if VtcMod.autoFleeNoParty and FightField and FightField.isInBattle then
      -- Chỉ auto-flee khi đang ở chế độ Party (LEADER hoặc MEMBER).
      -- Nếu autoPartyMode == "NONE" → người chơi solo, KHÔNG bỏ chạy.
      if VtcMod.autoPartyMode ~= "NONE" and Team and Role and Role.playerId and Team.IsAlone(Role.playerId) then
        if FightField.conIdx ~= -1 and FightField.fightHum[FightField.conIdx] then
          local nowRole = FightField.fightHum[FightField.conIdx]
          local playerIdx = FightField.GetPlayerIdx()
          local isMyUnit = false
          if playerIdx >= 0 and FightField.fightHum[playerIdx] then
            local myParty = FightField.fightHum[playerIdx].party_Kind
            if nowRole.party_Kind == myParty then isMyUnit = true end
          end
          if isMyUnit then
            nowRole.useSkID = 18001  -- ExitFight (Bỏ Chạy)
            local targetIdx = -1
            pcall(function() targetIdx = FightField.GetAutoTarget() end)
            if targetIdx and targetIdx ~= -1 and FightField.fightHum[targetIdx] then
              FightField.fightHum[targetIdx]:DoClick()
            else
              nowRole:DoClick()
            end
            logError("--- [VtcMod] AUTO FLEE: No party, forcing escape for unit " .. tostring(FightField.conIdx) .. " ---")
          end
        end
      end
    end
  end)

  -- =============================================
  -- AUTO-DECOMPOSE GIFT BAGS: Throttled Multi-Worker Pipeline State Machine
  -- Architecture: Batch Open N bags → Diff ALL → Process ALL → Repeat
  --   Step 1 → SCAN_BATCH: Calculate slot budget, find N bags, snapshot
  --   Step 2 → OPEN_BATCH: Open bags one-by-one within batch (sequential send)
  --   Step 3 → DIFF_BATCH: Wait for server, compare snapshot for ALL opened bags
  --   Step 4 → DISMANTLE: Process dismantlable items one-by-one
  --   Step 5 → DONATE: Batch donate new-slot items to guild
  --   Step 6 → DROP: Drop remaining items one-by-one
  --   → Loop back to Step 1 (picks up sub-bags with adaptive batch size)
  -- =============================================
  pcall(function()
    if VtcMod._decomposeActive and VtcMod._decomposeStep > 0 and CGTimer.time >= VtcMod._decomposeNextTime then
      -- Safety: abort if in battle
      if FightField and FightField.isInBattle then
        VtcMod._decomposeActive = false
        VtcMod._decomposeStep = 0
        VtcMod._decomposeBatchBags = {}
        VtcMod._decomposeNewItems = {}
        VtcMod._decomposeSnapshot = {}
        logError("--- [AutoDecompose] Aborted: entered battle ---")
        pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
        return
      end

      -- Safety: timeout after 300 seconds (increased for multi-worker batch processing)
      if CGTimer.time - VtcMod._decomposeStartTime > 300 then
        VtcMod._decomposeActive = false
        VtcMod._decomposeStep = 0
        VtcMod._decomposeBatchBags = {}
        VtcMod._decomposeNewItems = {}
        VtcMod._decomposeSnapshot = {}
        logError("--- [AutoDecompose] TIMEOUT: auto-cancelled after 300s ---")
        ShowCenterMessage("[Phân Giải] ⚠️ Đã tự hủy sau 300 giây!")
        pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
        return
      end

      -- Safety: max iterations (prevent infinite loop)
      VtcMod._decomposeIterations = VtcMod._decomposeIterations + 1
      if VtcMod._decomposeIterations > 1000 then
        VtcMod._decomposeActive = false
        VtcMod._decomposeStep = 0
        VtcMod._decomposeBatchBags = {}
        VtcMod._decomposeNewItems = {}
        VtcMod._decomposeSnapshot = {}
        logError("--- [AutoDecompose] MAX ITERATIONS: auto-cancelled ---")
        ShowCenterMessage("[Phân Giải] ⚠️ Đã tự hủy do quá nhiều vòng lặp!")
        pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
        return
      end

      local step = VtcMod._decomposeStep

      if step == 1 then
        -- ═══════════════════════════════════════════
        -- STEP 1: SCAN — Two-Phase scan, slot budget, snapshot
        -- Phase 1: Group A (batch 3-5, no sub-bags)
        -- Phase 2: Group B + sub-bags (batch 1-2, recursive safe)
        -- ═══════════════════════════════════════════

        -- Check recursion depth limit
        if VtcMod._decomposeRecursionDepth > VtcMod._decomposeMaxRecursionDepth then
          VtcMod._decomposeActive = false
          VtcMod._decomposeStep = 0
          VtcMod._decomposeBatchBags = {}
          VtcMod._decomposeNewItems = {}
          VtcMod._decomposeSnapshot = {}
          logError("--- [AutoDecompose] ABORTED: Recursion depth limit reached (" .. VtcMod._decomposeRecursionDepth .. "/" .. VtcMod._decomposeMaxRecursionDepth .. ") ---")
          ShowCenterMessage("[Phân Giải] ⚠️ Đạt giới hạn tầng đệ quy! Dừng để tránh tràn.")
          pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
          return
        end

        local freeSlots = VtcMod.CountFreeSlots()
        local reservedSlots = VtcMod._decomposeReservedSlots or 5
        local slotBudget = freeSlots - reservedSlots

        logError("--- [AutoDecompose] Step 1 SCAN: freeSlots=" .. freeSlots .. " reserved=" .. reservedSlots .. " slotBudget=" .. slotBudget .. " groupA=5 groupB=2 depth=" .. VtcMod._decomposeRecursionDepth .. " ---")

        if slotBudget < 2 then
          -- Not enough free slots to safely open any bags
          VtcMod._decomposeActive = false
          VtcMod._decomposeStep = 0
          VtcMod._decomposeBatchBags = {}
          VtcMod._decomposeNewItems = {}
          VtcMod._decomposeSnapshot = {}
          logError("--- [AutoDecompose] ABORTED: Slot budget too low (" .. slotBudget .. ", need >= 2, freeSlots=" .. freeSlots .. ") ---")
          ShowCenterMessage("[Phân Giải] ⚠️ Túi đồ gần đầy! Cần thêm " .. (reservedSlots + 2 - freeSlots) .. " ô trống.")
          pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
          return
        end

        -- ═══════════════════════════════════════════
        -- TWO-PHASE SCAN: Group A (fast 3-5) → Group B (safe 1-2)
        -- ═══════════════════════════════════════════
        local bags = nil

        -- Phase 1: Group A (Hộp Trang Bị — no sub-bags, fast batch 3-5)
        local groupALimit = math.min(slotBudget, 5, VtcMod._decomposeMaxBatchSize)
        groupALimit = math.max(1, groupALimit)
        bags = VtcMod.FindGiftBagsByIds(VtcMod.GROUP_A_IDS, groupALimit)

        if not bags or #bags == 0 then
          -- Phase 2: Remaining (Group B + sub-bags, safe batch 1-2)
          local groupBLimit = math.min(slotBudget, 2)
          groupBLimit = math.max(1, groupBLimit)
          bags = VtcMod.FindGiftBagsInBag(groupBLimit)
        end

        if bags and #bags > 0 then
          VtcMod._decomposeBatchBags = bags
          VtcMod._decomposeBatchOpenIdx = 1
          VtcMod._decomposeWorkerCount = VtcMod._decomposeWorkerCount + 1

          local bagNames = {}
          for _, b in ipairs(bags) do
            local name = (itemDatas and itemDatas[b.id]) and itemDatas[b.id]:GetName(true) or tostring(b.id)
            local group = VtcMod.GROUP_A_IDS[b.id] and "A" or "B"
            table.insert(bagNames, "[" .. name .. "(" .. group .. ")]")
          end
          logError("--- [AutoDecompose] Batch #" .. VtcMod._decomposeWorkerCount .. ": Opening " .. #bags .. " bags: " .. table.concat(bagNames, ", ") .. " (budget=" .. slotBudget .. ") ---")
          if Chat and EChannel then
            Chat.AddMessage(EChannel.System, "[Phân Giải] Batch #" .. VtcMod._decomposeWorkerCount .. ": Mở " .. #bags .. " túi (" .. freeSlots .. " ô trống, budget=" .. slotBudget .. ")")
          end

          -- Take snapshot BEFORE opening any bag in this batch
          VtcMod._decomposeSnapshot = VtcMod.TakeDecomposeSnapshot()

          VtcMod._decomposeStep = 2
          VtcMod._decomposeNextTime = CGTimer.time + 0.1
        else
          -- No more gift bags found in inventory → ALL DONE
          VtcMod._decomposeActive = false
          VtcMod._decomposeStep = 0
          VtcMod._decomposeBatchBags = {}
          VtcMod._decomposeNewItems = {}
          VtcMod._decomposeSnapshot = {}
          local summary = string.format("[Phân Giải] ✅ Hoàn tất! Batches: %d | Mở: %d | Phân giải: %d | Đóng góp: %d | Vứt: %d | Depth: %d",
            VtcMod._decomposeWorkerCount, VtcMod._decomposeTotalOpened,
            VtcMod._decomposeTotalDismantled, VtcMod._decomposeTotalDonated,
            VtcMod._decomposeTotalDropped, VtcMod._decomposeRecursionDepth)
          logError("--- [AutoDecompose] " .. summary .. " ---")
          if Chat and EChannel then Chat.AddMessage(EChannel.System, summary) end
          ShowCenterMessage(summary)
          pcall(function() if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() pcall(function() scrollContent_Function:Reset(#modFeatures) end) end end)
        end

      elseif step == 2 then
        -- ═══════════════════════════════════════════
        -- STEP 2: OPEN_BATCH — Open bags one-by-one within batch
        -- Sequential send with 0.15s spacing to avoid server flood
        -- ═══════════════════════════════════════════
        local idx = VtcMod._decomposeBatchOpenIdx
        local bags = VtcMod._decomposeBatchBags

        if idx <= #bags then
          local b = bags[idx]
          local buf = ByteBuffer.New()
          buf:WriteByte(b.slot)
          buf:WriteInt32(1)   -- quantity = 1
          buf:WriteByte(0)    -- followIndex = 0 (main character)
          buf:WriteByte(0)    -- useType = 0
          Network.Send(23, 15, buf)
          VtcMod._decomposeTotalOpened = VtcMod._decomposeTotalOpened + 1
          logError("--- [AutoDecompose] Step 2 OPEN_BATCH: Sent UseItem for slot " .. b.slot .. " (" .. idx .. "/" .. #bags .. ") ---")

          VtcMod._decomposeBatchOpenIdx = idx + 1
          VtcMod._decomposeNextTime = CGTimer.time + 0.15  -- 150ms between opens (optimized)
        else
          -- All bags in batch have been opened → move to DIFF
          logError("--- [AutoDecompose] Step 2 OPEN_BATCH: All " .. #bags .. " bags opened. Waiting for server diff... ---")
          VtcMod._decomposeStep = 3
          VtcMod._decomposeStep3Start = CGTimer.time
          VtcMod._decomposeNextTime = CGTimer.time + 0.8  -- Wait 0.8s for server (optimized, retry has 5s budget)
        end

      elseif step == 3 then
        -- ═══════════════════════════════════════════
        -- STEP 3: DIFF_BATCH — Compare snapshot, detect ALL new items + sub-bags
        -- ═══════════════════════════════════════════
        VtcMod._decomposeNewItems = VtcMod.DiffDecomposeSnapshot(VtcMod._decomposeSnapshot)
        
        if #VtcMod._decomposeNewItems > 0 then
          local subBagCount = 0
          logError("--- [AutoDecompose] Step 3 DIFF_BATCH: Found " .. #VtcMod._decomposeNewItems .. " new items from Batch #" .. VtcMod._decomposeWorkerCount .. " ---")
          for _, item in ipairs(VtcMod._decomposeNewItems) do
            local name = (itemDatas and itemDatas[item.Id]) and itemDatas[item.Id]:GetName(true) or tostring(item.Id)
            logError("--- [AutoDecompose]   New: " .. name .. " x" .. item.quant .. " (slot " .. item.bagIndex .. ", isNewSlot=" .. tostring(item.isNewSlot) .. ") ---")
            -- Sub-bag filter: mark as processed so they're NOT dismantled/donated/dropped
            -- They will be picked up as new workers on the next Step 1 scan (recursive unboxing)
            if VtcMod.GIFT_BAG_IDS[item.Id] then
              item._processed = true
              subBagCount = subBagCount + 1
              logError("--- [AutoDecompose]   ↳ Sub-Bag detected: [" .. name .. "] → Will be processed in next batch (depth+1) ---")
            end
          end

          -- Track recursion: if sub-bags were found, increment depth for next cycle
          if subBagCount > 0 then
            VtcMod._decomposeRecursionDepth = VtcMod._decomposeRecursionDepth + 1
            logError("--- [AutoDecompose] Sub-bags found: " .. subBagCount .. ". Recursion depth now: " .. VtcMod._decomposeRecursionDepth .. "/" .. VtcMod._decomposeMaxRecursionDepth .. " ---")
          end

          VtcMod._decomposeActionIdx = 1
          VtcMod._decomposeStep = 4
          VtcMod._decomposeNextTime = CGTimer.time + 0.1
        else
          -- No new items detected. Check if ANY bag in batch was consumed.
          local anyBagConsumed = false
          local bags = VtcMod._decomposeBatchBags
          if bags then
            local currentBag = Item.GetBag(EThings.Bag)
            if currentBag then
              for _, b in ipairs(bags) do
                local currentItem = currentBag[b.slot]
                local oldItem = VtcMod._decomposeSnapshot[b.slot]
                if not currentItem or (oldItem and (currentItem.Id ~= b.id or (currentItem.quant or 0) < (oldItem.quant or 0))) then
                  anyBagConsumed = true
                  break
                end
              end
            end
          end

          if anyBagConsumed then
            -- Server consumed bag(s) but yielded nothing visible (e.g. gold only) → move on
            logError("--- [AutoDecompose] Batch consumed (gold-only?). Batch #" .. VtcMod._decomposeWorkerCount .. " done. Next... ---")
            VtcMod._decomposeBatchBags = {}    -- Cleanup: release batch reference
            VtcMod._decomposeBatchOpenIdx = 0
            VtcMod._decomposeNewItems = {}
            VtcMod._decomposeStep = 1
            VtcMod._decomposeNextTime = CGTimer.time + 0.2
          else
            -- Server hasn't processed bag(s) yet. Network lag or unopenable.
            if CGTimer.time - (VtcMod._decomposeStep3Start or CGTimer.time) < 5.0 then
              -- Keep waiting (retry diff every 0.3s, up to 5 seconds total)
              VtcMod._decomposeNextTime = CGTimer.time + 0.3
            else
              -- Timeout 5s reached. Blacklist ALL bags in batch.
              if bags then
                for _, b in ipairs(bags) do
                  VtcMod._decomposeBlacklist[b.slot] = true
                  logError("--- [AutoDecompose] Timeout 5s. Blacklisted slot " .. b.slot .. " ---")
                end
              end
              logError("--- [AutoDecompose] Batch #" .. VtcMod._decomposeWorkerCount .. " blacklisted. ---")
              VtcMod._decomposeBatchBags = {}    -- Cleanup: release batch reference
              VtcMod._decomposeBatchOpenIdx = 0
              VtcMod._decomposeNewItems = {}
              VtcMod._decomposeStep = 1
              VtcMod._decomposeNextTime = CGTimer.time + 0.2
            end
          end
        end

      elseif step == 4 then
        -- ═══════════════════════════════════════════
        -- STEP 4: DISMANTLE — Process items with furnaceCount > 0, one per tick
        -- ═══════════════════════════════════════════
        local idx = VtcMod._decomposeActionIdx
        local items = VtcMod._decomposeNewItems

        while idx <= #items do
          local item = items[idx]
          if not item._processed then
            local iData = itemDatas and itemDatas[item.Id]
            if iData and iData.furnaceCount and iData.furnaceCount > 0 then
              -- Dismantle this item (packet 89,3 supports quantity)
              local buf = ByteBuffer.New()
              buf:WriteByte(1)
              buf:WriteByte(item.bagIndex)
              buf:WriteInt32(item.quant)
              Network.Send(89, 3, buf)
              VtcMod._decomposeTotalDismantled = VtcMod._decomposeTotalDismantled + 1
              local name = iData:GetName(true) or tostring(item.Id)
              logError("--- [AutoDecompose] Step 4 DISMANTLE: " .. name .. " x" .. item.quant .. " (slot " .. item.bagIndex .. ") ---")
              item._processed = true
              VtcMod._decomposeActionIdx = idx + 1
              VtcMod._decomposeNextTime = CGTimer.time + 0.2
              return  -- Process one per tick
            end
          end
          idx = idx + 1
        end

        -- All items checked for dismantle, move to donate
        VtcMod._decomposeActionIdx = 1
        VtcMod._decomposeStep = 5
        VtcMod._decomposeNextTime = CGTimer.time + 0.2

      elseif step == 5 then
        -- ═══════════════════════════════════════════
        -- STEP 5: DONATE — Batch donate new-slot items to guild
        -- ═══════════════════════════════════════════
        local hasGuild = Organization and Organization.Id and Organization.Id > 0
        if hasGuild then
          local donateBuf = ByteBuffer.New()
          donateBuf:WriteInt32(0)  -- 0 gold
          local donateCount = 0

          for _, item in ipairs(VtcMod._decomposeNewItems) do
            if not item._processed then
              if item.isNewSlot then
                -- Safe to donate: entire slot is new (won't lose old items)
                donateBuf:WriteByte(item.bagIndex)
                donateCount = donateCount + 1
                item._processed = true
                logError("--- [AutoDecompose] Step 5 DONATE: slot " .. item.bagIndex .. " (ID " .. item.Id .. ") ---")
              end
            end
          end

          if donateCount > 0 then
            Network.Send(39, 15, donateBuf)
            VtcMod._decomposeTotalDonated = VtcMod._decomposeTotalDonated + donateCount
            logError("--- [AutoDecompose] Step 5 DONATE: Donated " .. donateCount .. " items to guild ---")
            if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Phân Giải] Batch #" .. VtcMod._decomposeWorkerCount .. ": Đóng góp " .. donateCount .. " món.") end
          end
        end

        VtcMod._decomposeActionIdx = 1
        VtcMod._decomposeStep = 6
        VtcMod._decomposeNextTime = CGTimer.time + 0.2

      elseif step == 6 then
        -- ═══════════════════════════════════════════
        -- STEP 6: DROP — Fallback for remaining unprocessed items (stacked or no guild)
        -- ═══════════════════════════════════════════
        local idx = VtcMod._decomposeActionIdx
        local items = VtcMod._decomposeNewItems

        while idx <= #items do
          local item = items[idx]
          if not item._processed then
            -- Drop with specific quantity (safe for stacked items)
            local buf = ByteBuffer.New()
            buf:WriteByte(item.bagIndex)
            buf:WriteInt32(item.quant)
            Network.Send(23, 3, buf)
            VtcMod._decomposeTotalDropped = VtcMod._decomposeTotalDropped + 1
            local name = (itemDatas and itemDatas[item.Id]) and itemDatas[item.Id]:GetName(true) or tostring(item.Id)
            logError("--- [AutoDecompose] Step 6 DROP: " .. name .. " x" .. item.quant .. " (slot " .. item.bagIndex .. ") ---")
            item._processed = true
            VtcMod._decomposeActionIdx = idx + 1
            VtcMod._decomposeNextTime = CGTimer.time + 0.2
            return  -- Process one per tick
          else
            idx = idx + 1
          end
        end

        -- ═══════════════════════════════════════════
        -- Batch complete! Loop to Step 1 for next bags / sub-bags.
        -- ═══════════════════════════════════════════
        local postFreeSlots = VtcMod.CountFreeSlots()
        logError("--- [AutoDecompose] Batch #" .. VtcMod._decomposeWorkerCount .. " COMPLETE. postFreeSlots=" .. postFreeSlots .. ". Next batch... ---")

        VtcMod._decomposeCurrentBag = nil
        VtcMod._decomposeBatchBags = {}
        VtcMod._decomposeBatchOpenIdx = 0
        VtcMod._decomposeNewItems = {}  -- Release memory from processed items
        VtcMod._decomposeStep = 1
        VtcMod._decomposeNextTime = CGTimer.time + 0.3  -- Brief pause before next batch
      end
    end
  end)

  -- 0. Forced Reload of UI Packages (Ensures Vietnamese LUA is loaded from disk when UI system is fully initialized)
  if Network and Network.loginFinished and not this.uiDebugReloaded then
    this.uiDebugReloaded = true
    pcall(function()
      if UIDebug and not UIDebug.uiController then
        package.loaded["UI/UIDebug"] = nil
        package.loaded["UI/UISetting"] = nil
        require "UI/UIDebug"
        require "UI/UISetting"
        logError("--- [VtcMod] FORCED RELOAD OF UIDEBUG AND UISETTING ON UPDATE (uiController was nil)! ---")
      end
    end)
  end

  -- =============================================
  -- BATTLE END DETECTION (Pimbot-inspired: event-driven buff)
  -- Chỉ buff sau khi ra trận, không poll liên tục
  -- =============================================
  pcall(function()
    if FightField then
      if FightField.isInBattle then
        VtcMod._inBattle = true
      elseif VtcMod._inBattle then
        VtcMod._inBattle = false
        VtcMod._needMainBuff = true
        VtcMod._needPetBuff = true
        VtcMod._loggedPetSkills = false
        VtcMod._buffDeadline = CGTimer.time + 15
        logError("--- [VtcMod] BATTLE END DETECTED. Setting _needMainBuff=true, Deadline=" .. tostring(VtcMod._buffDeadline))
        if VtcMod.autoBuffOutBattle or VtcMod.autoPetBuffOutBattle then
          ShowCenterMessage("BATTLE END - Kích hoạt Auto Buff")
        end
      end
    end
  end)

  -- =============================================
  -- BOT AUTO DAILY QUESTS (Robust)
  -- Tự rà quests đang delay/chưa hoàn thành, xử lý lần lượt
  -- =============================================
  pcall(function()
    if VtcMod.autoDailyQuests and not FightField.isInBattle and CGTimer.time > (VtcMod.nextDailyQuestTime or 0) then
      VtcMod.nextDailyQuestTime = CGTimer.time + 3
      -- Safety: kiểm tra đủ điều kiện trước khi thao tác
      if not Role or not Role.player then
        logError("--- [VtcMod Scanner Skip] Role or Role.player is nil ---")
        return
      end
      if Role.CanControl and not Role.CanControl() then
        logError("--- [VtcMod Scanner Skip] Role.CanControl() is false ---")
        return
      end
      if SceneManager and SceneManager.isChangingScene then
        logError("--- [VtcMod Scanner Skip] SceneManager.isChangingScene is true ---")
        return
      end
      if not MarkManager then
        logError("--- [VtcMod Scanner Skip] MarkManager is nil ---")
        return
      end
      if MarkManager.navigationMissionId ~= 0 then
        -- Anti-deadlock: Clear if stuck for 10 seconds to prevent blocking other daily quests
        if not VtcMod._navTimeout then VtcMod._navTimeout = CGTimer.time + 10 end
        if CGTimer.time > VtcMod._navTimeout then
          logError("--- [VtcMod] Clearing stuck navigationMissionId: " .. tostring(MarkManager.navigationMissionId))
          MarkManager.navigationMissionId = 0
          VtcMod._navTimeout = nil
        end
        logError("--- [VtcMod Scanner Skip] MarkManager.navigationMissionId is " .. tostring(MarkManager.navigationMissionId) .. " ---")
        return
      else
        VtcMod._navTimeout = nil
      end
      if MachineBox and MachineBox.autoMove then
        logError("--- [VtcMod Scanner Skip] MachineBox.autoMove is true, turning it OFF ---")
        MachineBox.autoMove = false
      end
      -- Disable isMoving block to avoid stuck conditions due to lag or small movements
      if Role.player.isMoving then
        logError("--- [VtcMod Scanner Skip] Role.player.isMoving is true (Warning, bypassed) ---")
      end
      if EventManager and EventManager.IsRunning and EventManager.IsRunning() then
        logError("--- [VtcMod Scanner Skip] EventManager.IsRunning() is true ---")
        return
      end
      if UI and UICheck and UI.IsVisible(UICheck) then
        logError("--- [VtcMod Scanner Skip] UI.IsVisible(UICheck) is true ---")
        return
      end

      local function shouldExcludeQuest(name, kind)
        if not name then return false end
        local lowerName = string.lower(name)
        
        -- 1. Loại trừ Phó bản đội
        if kind == 5 or 
           string.find(lowerName, "đội") or 
           string.find(lowerName, "doi") or 
           string.find(lowerName, "nhóm") or 
           string.find(lowerName, "nhom") or 
           string.find(lowerName, "multiplayer") or 
           string.find(lowerName, "多人") then
          return true
        end
        
        -- 2. Loại trừ World Boss
        if string.find(lowerName, "boss thế giới") or 
           string.find(lowerName, "boss the gioi") or 
           string.find(lowerName, "thế giới") or 
           string.find(lowerName, "the gioi") or 
           string.find(lowerName, "world boss") or 
           string.find(lowerName, "世界boss") or 
           string.find(lowerName, "boss") then
          return true
        end
        
        -- 3. Loại trừ Chiến đấu 50 lần
        if string.find(lowerName, "chiến đấu") or 
           string.find(lowerName, "chien dau") then
          return true
        end
        
        -- 4. Loại trừ Rút thẻ & Rút tướng nếu tùy chọn drawWith9000Xu đang TẮT
        if not VtcMod.drawWith9000Xu then
          if string.find(lowerName, "rút thẻ") or 
             string.find(lowerName, "rut the") or 
             string.find(lowerName, "rút võ tướng") or 
             string.find(lowerName, "rut vo tuong") or 
             string.find(lowerName, "rút tướng") or 
             string.find(lowerName, "rut tuong") or 
             string.find(lowerName, "gacha") or 
             string.find(lowerName, "lottery") then
            return true
          end
        end
        
        return false
      end

      local foundDaily = false
      -- 1. Tìm và chạy quest daily chưa hoàn thành (kind == 7)
      if MarkManager.missions and markDatas then
        for k, v in pairs(MarkManager.missions) do
          if type(v) == "table" and v.id and v.id ~= 0 then
            local mData = markDatas[v.id]
            if mData and mData.kind == 7 then
              if not shouldExcludeQuest(mData.name, mData.kind) then
                local ok, mission = pcall(function() return MarkManager.GetMission(v.id) end)
                if ok and mission and not mission:IsComplete() then
                  MarkManager.Navigation(v.id)
                  ShowCenterMessage("Bot Auto: Đang chạy NV Ngày [" .. (mData.name or tostring(v.id)) .. "]")
                  foundDaily = true
                  break
                end
              end
            end
          end
        end
      end
      -- 2. Tự động nhận thưởng Nhiệm vụ ngày (Liveness/Monopoly) độc lập
      if missionAwardDatas then
        local claimedAny = false
        for _, value in ipairs(missionAwardDatas) do
          if value and value.activityId == 98 and value.IsComplete and value.HaveGetFlag then
            local ok1, isComplete = pcall(function() return value:IsComplete() end)
            local ok2, hasGot = pcall(function() return value:HaveGetFlag() end)
            if ok1 and isComplete and ok2 and not hasGot then
              MissionAward.SendCompleteMission(value.Id)
              claimedAny = true
            end
          end
        end
        if claimedAny then
          ShowCenterMessage("Bot Auto: Đã nhận thưởng NV Ngày!")
        end
      end
    end
  end)

  -- =============================================
  -- HOOK HandleAutoDig: Unified Smart Heal Override
  -- Fixes: (1) GetElementSkill Lv=0 bug (2) Wrong target for heal (3) Racing condition
  -- Logic: heal nếu team HP/SP < 75%, else PHÒNG THỦ. Không đánh, không skill tấn công.
  -- =============================================
  if FightField and FightField.HandleAutoDig and not VtcMod._hookedHandleAutoDig then
    VtcMod._origHandleAutoDig = FightField.HandleAutoDig

    -- Danh sách skill ID theo loại heal
    local HEAL_HP_SKILLS = {10002, 10004, 10005, 10012, 11010, 14002, 14005, 14008, 14009, 14010, 14011}
    local HEAL_SP_SKILLS = {10009, 11009, 14013, 14014}
    local HEAL_BOTH_SKILLS = {12022, 14022}
    local HEAL_HP_THRESHOLD = tonumber("__CATBINH_HP_TRIGGER__") or 0.75
    local HEAL_SP_THRESHOLD = tonumber("__CATBINH_SP_TRIGGER__") or 0.75

    -- Helper: kiểm tra skillId có thuộc danh sách không
    local function isInList(skillId, list)
      for _, v in ipairs(list) do
        if v == skillId then return true end
      end
      return false
    end

    -- Tìm heal skill ĐÃ HỌC (Lv > 0) từ RoleController
    -- roleObj: Role.player hoặc Role.GetFollowNpc(...)
    local function findLearnedHealSkill(roleObj)
      if not roleObj or not roleObj.GetElementSkill then return nil, nil, nil end

      local ok, skills = pcall(roleObj.GetElementSkill, roleObj, 0)
      if not ok or not skills then return nil, nil, nil end

      local hpSkill, spSkill, bothSkill = nil, nil, nil
      for _, s in pairs(skills) do
        local sId = s and s.Id
        local sLv = s and s.Lv
        if sId and sLv and sLv > 0 and skillDatas[sId] then
          if isInList(sId, HEAL_HP_SKILLS) then hpSkill = sId end
          if isInList(sId, HEAL_SP_SKILLS) then spSkill = sId end
          if isInList(sId, HEAL_BOTH_SKILLS) then bothSkill = sId end
        end
      end
      return hpSkill, spSkill, bothSkill
    end

    -- Quét team xem có ai cần heal không (HP/SP < 75%)
    local function scanTeamNeedHeal(nowRole)
      local myParty = nowRole.party_Kind
      local needHp, needSp = false, false

      for i = 0, MaxFightHum do
        local fh = FightField.fightHum[i]
        if fh and fh.party_Kind == myParty and fh.roleController then
          local curHp = fh.roleController:GetAttribute(EAttribute.Hp) or 0
          local maxHp = fh.roleController:GetAttribute(EAttribute.MaxHp) or 0
          local curSp = fh.roleController:GetAttribute(EAttribute.Sp) or 0
          local maxSp = fh.roleController:GetAttribute(EAttribute.MaxSp) or 0
          if curHp > 0 then -- Phải còn sống
            if maxHp > 0 and curHp < maxHp * HEAL_HP_THRESHOLD then needHp = true end
            if maxSp > 0 and curSp < maxSp * HEAL_SP_THRESHOLD then needSp = true end
          end
        end
      end
      return needHp, needSp
    end

    -- Tìm đồng đội cùng party cần heal nhất (HP/SP thấp nhất)
    local function findBestAlly(nowRole, skillId)
      local myParty = nowRole.party_Kind
      local bestIdx = -1
      local lowestRatio = 1.0

      local isHp = isInList(skillId, HEAL_HP_SKILLS)
      local isSp = isInList(skillId, HEAL_SP_SKILLS)
      local isBoth = isInList(skillId, HEAL_BOTH_SKILLS)

      for i = 0, MaxFightHum do
        local fh = FightField.fightHum[i]
        if fh and fh.party_Kind == myParty and fh.roleController then
          local curHp = fh.roleController:GetAttribute(EAttribute.Hp) or 0
          local maxHp = fh.roleController:GetAttribute(EAttribute.MaxHp) or 0
          local curSp = fh.roleController:GetAttribute(EAttribute.Sp) or 0
          local maxSp = fh.roleController:GetAttribute(EAttribute.MaxSp) or 0

          if curHp > 0 then -- Phải còn sống
            local ratio = 1.0
            if isHp and maxHp > 0 then ratio = curHp / maxHp
            elseif isSp and maxSp > 0 then ratio = curSp / maxSp
            elseif isBoth and maxHp > 0 then ratio = math.min(curHp / maxHp, (maxSp > 0 and curSp / maxSp) or 1.0)
            end

            if ratio < lowestRatio then
              lowestRatio = ratio
              bestIdx = i
            end
          end
        end
      end

      if bestIdx == -1 then bestIdx = FightField.conIdx end
      return bestIdx
    end

    -- Chọn heal skill tốt nhất dựa trên nhu cầu team
    local function chooseBestHealSkill(needHp, needSp, hpSkill, spSkill, bothSkill)
      if needHp and needSp and bothSkill then return bothSkill end
      if needHp and hpSkill then return hpSkill end
      if needSp and spSkill then return spSkill end
      -- Fallback: ưu tiên HP nếu có
      if hpSkill then return hpSkill end
      if spSkill then return spSkill end
      if bothSkill then return bothSkill end
      return nil
    end

    -- Lấy RoleController gốc (ngoài battle) để check GetSkillLv
    local function getOriRole(nowRole)
      if Contains(nowRole.kind, EHuman.Player, EHuman.Players, EHuman.Divide) then
        return Role.player
      elseif nowRole.kind == EHuman.FollowNpc then
        return Role.GetFollowNpc(Role.playerId, nowRole.npcId)
      end
      return nil
    end

    -- Kiểm tra nhân vật có phải của mình không
    local function isMyCharacter(nowRole)
      local playerIdx = FightField.GetPlayerIdx()
      if FightField.conIdx == playerIdx then return true end
      if nowRole.masterID == Role.playerId and Contains(nowRole.kind, EHuman.FollowNpc, EHuman.Divide, EHuman.Player, EHuman.Players) then
        return true
      end
      return false
    end

    -- Kiểm tra nhân vật này có được bật SmartHeal không
    local function isSmartHealEnabled(nowRole)
      local playerIdx = FightField.GetPlayerIdx()
      if FightField.conIdx == playerIdx or Contains(nowRole.kind, EHuman.Player, EHuman.Players, EHuman.Divide) then
        return (VtcMod.autoBuffOutBattle == true) or (VtcMod.autoTrainBuffOutBattle == true)
      elseif nowRole.kind == EHuman.FollowNpc and nowRole.masterID == Role.playerId then
        return VtcMod.autoPetBuffOutBattle == true
      end
      return false
    end

    -- Thực hiện phòng thủ cho nhân vật
    local function doDefend(nowRole)
      nowRole.useSkID = 17001
      nowRole:DoClick()
    end

    -- ★★★ MAIN OVERRIDE ★★★
    FightField.HandleAutoDig = function()
      -- Guard checks giữ nguyên y hệt game gốc
      if Role.player.war == EWar.None then return end
      if Role.player.war == EWar.Guest then return end
      if MachineBox.autoFight and SceneManager.CheckLimit(SceneManager.sceneId, ESceneLimit.NoMachinebox) then
        MachineBox.SetAutoFight(false)
        ShowCenterMessage(string.Get(20340))
        return
      end

      local needSmartHeal = (VtcMod.autoBuffOutBattle == true) or (VtcMod.autoTrainBuffOutBattle == true) or (VtcMod.autoPetBuffOutBattle == true)

      -- Nếu autoFight OFF VÀ SmartHeal OFF → return (game gốc behavior)
      if not MachineBox.autoFight and not needSmartHeal then return end

      local idx = -1
      local count = 0

      while FightField.conIdx ~= -1 do
        count = count + 1
        if count > MaxFightHum then break end

        local nowRole = FightField.fightHum[FightField.conIdx]
        if nowRole == nil then break end

        local handled = false

        -- Wrap toàn bộ logic SmartHeal trong pcall để crash 1 turn không crash game
        local okTurn, errTurn = pcall(function()
          local isMine = isMyCharacter(nowRole)

          if isMine and needSmartHeal then
            local smartHealOn = isSmartHealEnabled(nowRole)

            if smartHealOn then
              -- ★ NEW MULTI-AGENT MAIN AUTO BUFF ★
              local isMainRole = (FightField.conIdx == FightField.GetPlayerIdx()) or Contains(nowRole.kind, EHuman.Player, EHuman.Players, EHuman.Divide)
              if isMainRole and (VtcMod.autoBuffOutBattle or VtcMod.autoTrainBuffOutBattle) then
                  local MainAutoBuffAI = require("Logic.MainAutoBuffAI")
                  
                  -- Reset Turn Queue if new turn (>3.0s since last action choice)
                  if CGTimer.time - (VtcMod.LastTurnTick or 0) > 3.0 then
                      MainAutoBuffAI.ResetTurnQueue()
                  end
                  VtcMod.LastTurnTick = CGTimer.time
                  
                  local fId = FightField.fightId or 1
                  
                  -- Nếu là Train Buff, khóa các Tier Hồi sinh, Giải trạng thái, Buff khiên
                  local extraIgnoreTiers = nil
                  if VtcMod.autoTrainBuffOutBattle and not VtcMod.autoBuffOutBattle then
                      extraIgnoreTiers = { [5]=true, [6]=true }
                  end
                  
                  local action = MainAutoBuffAI.GetAction(nowRole, FightField.fightHum, fId, extraIgnoreTiers)
                  
                  if action and action.actionType ~= "Defend" then
                      nowRole.useSkID = action.skillId
                      if action.targetObj then
                          logError("[VTCMOD] NEW_AI: " .. tostring(nowRole.kind) .. " useSkID=" .. tostring(action.skillId) .. " → targetId=" .. tostring(action.targetId))
                          action.targetObj:DoClick()
                          handled = true
                          return
                      else
                          -- ★ FIX v5.7: targetObj nil → reset useSkID để tránh buff vào quái khi fallback
                          logError("[VTCMOD] NEW_AI: WARNING targetObj nil for skillId=" .. tostring(action.skillId) .. ", resetting useSkID")
                          nowRole.useSkID = 17001  -- Reset về Defend
                      end
                  end
                  
                  if VtcMod.autoTrainBuffOutBattle and not VtcMod.autoBuffOutBattle then
                      -- Fallback TrainBuff: Đánh thường (SK_HandFight = 10000)
                      local targetIdx = FightField.GetAutoTarget()
                      if targetIdx ~= -1 and FightField.fightHum[targetIdx] then
                          logError("[VTCMOD] NEW_AI: ATTACK (Train Fallback) → targetId=" .. tostring(targetIdx))
                          nowRole.useSkID = 10000
                          FightField.fightHum[targetIdx]:DoClick()
                      else
                          logError("[VTCMOD] NEW_AI: No target for Attack, Fallback to DEFEND")
                          doDefend(nowRole)
                      end
                  else
                      -- Fallback EventBuff: Phòng ngự
                      logError("[VTCMOD] NEW_AI: DEFEND")
                      doDefend(nowRole)
                  end
                  
                  handled = true
                  return
              end
              -- ★ END NEW MULTI-AGENT MAIN AUTO BUFF ★

              -- ★ SMART HEAL TURN: heal nếu cần, else phòng thủ
              local needHp, needSp = scanTeamNeedHeal(nowRole)

              if needHp or needSp then
                -- Tìm heal skill ĐÃ HỌC
                local oriRole = getOriRole(nowRole)
                local hpSkill, spSkill, bothSkill = findLearnedHealSkill(oriRole)
                local healSkill = chooseBestHealSkill(needHp, needSp, hpSkill, spSkill, bothSkill)

                if healSkill and skillDatas[healSkill] then
                  -- Validate SP
                  local curSp = nowRole.roleController:GetAttribute(EAttribute.Sp) or 0
                  local reqSp = skillDatas[healSkill].requireSp or 0

                  if curSp >= reqSp then
                    -- ★ BYPASS CaseSkill — gán useSkID trực tiếp
                    nowRole.useSkID = healSkill
                    local allyIdx = findBestAlly(nowRole, healSkill)

                    if allyIdx ~= -1 and FightField.fightHum[allyIdx] then
                      logError("[VTCMOD] SMART_HEAL: " .. tostring(nowRole.kind) .. " npcId=" .. tostring(nowRole.npcId) .. " useSkID=" .. tostring(healSkill) .. " → ally[" .. tostring(allyIdx) .. "]")
                      FightField.fightHum[allyIdx]:DoClick()
                      handled = true
                    else
                      -- Ally không hợp lệ → phòng thủ
                      logError("[VTCMOD] SMART_HEAL: ally invalid, DEFEND")
                      doDefend(nowRole)
                      handled = true
                    end
                  else
                    -- SP không đủ → phòng thủ
                    logError("[VTCMOD] SMART_HEAL: SP insufficient (" .. tostring(curSp) .. "<" .. tostring(reqSp) .. "), DEFEND")
                    doDefend(nowRole)
                    handled = true
                  end
                else
                  -- Không tìm thấy heal skill đã học → phòng thủ
                  if not VtcMod._loggedNoHealSkill then
                    logError("[VTCMOD] SMART_HEAL: No learned heal skill found for " .. tostring(nowRole.kind) .. " npcId=" .. tostring(nowRole.npcId) .. ", DEFEND")
                    VtcMod._loggedNoHealSkill = true
                  end
                  doDefend(nowRole)
                  handled = true
                end
              else
                -- Team đủ HP/SP → phòng thủ (KHÔNG đánh, KHÔNG skill)
                doDefend(nowRole)
                handled = true
              end

            else
              -- Nhân vật này KHÔNG được bật SmartHeal
              if MachineBox.autoFight then
                -- autoFight ON → dùng logic game gốc (Att/Skill/Def)
                -- KHÔNG xử lý ở đây, để fallthrough xuống block autoFight bên dưới
              else
                -- autoFight OFF + nhân vật không bật SmartHeal
                -- → phòng thủ (để không đứng im kẹt trận)
                doDefend(nowRole)
                handled = true
              end
            end

          elseif isMine and not needSmartHeal then
            -- Không bật SmartHeal + autoFight ON → để game gốc xử lý
            -- fallthrough
          end
        end)

        if not okTurn then
          logError("[VTCMOD] SMART_HEAL ERROR: " .. tostring(errTurn))
        end

        -- Nếu SmartHeal đã xử lý → skip logic game gốc cho nhân vật này
        if not handled and MachineBox.autoFight then
          -- ★ LOGIC GAME GỐC — giữ nguyên 100% từ FightField.HandleAutoDig gốc
          local fightMode = MachineBox.GetFightMode(FightField.fightHum[FightField.conIdx].npcId)

          if fightMode == EMachineBoxFight.Att then
            idx = FightField.GetAutoTarget()
            if idx ~= -1 then
              if FightField.CheckEscape() or FightField.CheckMineralMobEscape() then
                nowRole.useSkID = 18001
                FightField.fightHum[idx]:DoClick()
              else
                local exitThreshold = MachineBox.GetExitThreshold(FightField.fightHum[FightField.conIdx].npcId)
                if exitThreshold > 0 and FightField.GetPartyMaxLv() - nowRole.roleController:GetAttribute(EAttribute.Lv) >= exitThreshold then
                  nowRole.useSkID = 18001
                  FightField.fightHum[idx]:DoClick()
                else
                  nowRole.useSkID = 10000
                  FightField.fightHum[idx]:DoClick()
                end
              end
            end
          elseif fightMode == EMachineBoxFight.Skill then
            idx = FightField.GetAutoTarget()
            if idx ~= -1 then
              if FightField.CheckEscape() or FightField.CheckMineralMobEscape() then
                nowRole.useSkID = 18001
                FightField.fightHum[idx]:DoClick()
              else
                local exitThreshold = MachineBox.GetExitThreshold(FightField.fightHum[FightField.conIdx].npcId)
                if exitThreshold > 0 and FightField.GetPartyMaxLv() - nowRole.roleController:GetAttribute(EAttribute.Lv) >= exitThreshold then
                  nowRole.useSkID = 18001
                  FightField.fightHum[idx]:DoClick()
                else
                  if FightField.GetPartyMemberCount(EFightParty.Left) > MachineBox.GetAOEThreshold(FightField.fightHum[FightField.conIdx].npcId) then
                    FightField.CaseSkill(nowRole, MachineBox.GetSkill(FightField.fightHum[FightField.conIdx].npcId, EMachineBoxSkill.AOE))
                  else
                    FightField.CaseSkill(nowRole, MachineBox.GetSkill(FightField.fightHum[FightField.conIdx].npcId, EMachineBoxSkill.Single))
                  end
                  FightField.fightHum[idx]:DoClick()
                end
              end
            end
          elseif fightMode == EMachineBoxFight.Def then
            if FightField.CheckEscape() or FightField.CheckMineralMobEscape() then
              nowRole.useSkID = 18001
              nowRole:DoClick()
            else
              if FightField.conIdx ~= -1 then
                local exitThreshold = MachineBox.GetExitThreshold(FightField.fightHum[FightField.conIdx].npcId)
                if exitThreshold > 0 and FightField.GetPartyMaxLv() - nowRole.roleController:GetAttribute(EAttribute.Lv) >= exitThreshold then
                  nowRole.useSkID = 18001
                  nowRole:DoClick()
                else
                  nowRole.useSkID = 17001
                  nowRole:DoClick()
                end
              end
            end
          end
        elseif not handled and not MachineBox.autoFight then
          -- autoFight OFF, SmartHeal ON nhưng nhân vật này không phải của mình
          -- → không xử lý (chỉ xử lý nhân vật của mình)
        end
      end -- end while
    end -- end HandleAutoDig override

    VtcMod._hookedHandleAutoDig = true
    logError("[VTCMOD] HOOKED FightField.HandleAutoDig successfully (Unified Smart Heal v2)")
  end

  -- 0.35. Dynamic Agro / Trace Radius đã bị gỡ bỏ để đảm bảo nhân vật CHẠY ĐẾN SÁT mục tiêu mới tiến hành đánh/nói chuyện, tránh lỗi Server từ chối vì đứng quá xa.

  -- =============================================
  -- TRUY KÍCH TẠI CHỖ (Pimbot-style: Camp in Place)
  -- Đứng yên tại vị trí anchor, chờ quái đi vào bán kính → tấn công
  -- Sau trận → tự quay về anchor
  -- =============================================
  pcall(function()
    if not VtcMod.autoStandaloneSniper then return end
    if not Role or not Role.player or not Role.player.position then return end
    if FightField and FightField.isInBattle then
      -- Đang trong trận: đánh dấu cần về anchor sau trận
      VtcMod._campReturnAfterBattle = true
      VtcMod._campWaitId = nil
      return
    end
    if SceneManager and SceneManager.isChangingScene then return end
    if CGTimer.time < (VtcMod._campNextScan or 0) then return end
    VtcMod._campNextScan = CGTimer.time + 0.3

    local pX = Role.player.position.x
    local pY = Role.player.position.y
    local campX = VtcMod._campX or math.floor(pX)
    local campY = VtcMod._campY or math.floor(pY)

    -- Nếu chưa lưu anchor → lưu
    if not VtcMod._campX then
      VtcMod._campX = math.floor(pX)
      VtcMod._campY = math.floor(pY)
      campX = VtcMod._campX
      campY = VtcMod._campY
    end

    -- Sau trận → quay về anchor
    if VtcMod._campReturnAfterBattle then
      VtcMod._campReturnAfterBattle = false
      if MoveController and MoveController.SendMove then
        MoveController.SendMove(campX, campY)
      end
      VtcMod._campNextScan = CGTimer.time + 1.5
      return
    end

    -- Đang chờ quái vào trận → theo dõi
    if VtcMod._campWaitId then
      if CGTimer.time > (VtcMod._campWaitTimeout or 0) then
        -- Timeout → bỏ target, quay về anchor
        VtcMod._campWaitId = nil
        if MoveController and MoveController.SendMove then
          MoveController.SendMove(campX, campY)
        end
        VtcMod._campNextScan = CGTimer.time + 0.5
        return
      end
      -- Retry gửi packet Click/Bump cho quái
      if Role.mapNpcs then
        local found = false
        for _, npc in pairs(Role.mapNpcs) do
          if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData
             and npc.data.eventNpcData.id == VtcMod._campWaitId and npc.war == EWar.None then
            found = true
            -- Di chuyển sát quái (nhẹ nhàng, không burst)
            if npc.position and MoveController and MoveController.SendMove then
              MoveController.SendMove(math.floor(npc.position.x), math.floor(npc.position.y))
            end
            -- Gửi lại Click/Bump
            if Network and Network.Send then
              -- BUG 2 FIX: Use ByteBuffer.New() instead of GetSendBuffer() to prevent race condition
              local buf1 = ByteBuffer.New()
              buf1:WriteUInt16(VtcMod._campWaitId)
              Network.Send(20, 2, buf1)
              local buf2 = ByteBuffer.New()
              buf2:WriteUInt16(VtcMod._campWaitId)
              Network.Send(20, 1, buf2)
            end
            break
          end
        end
        if not found then
          -- Quái đã biến mất hoặc vào trận với người khác
          VtcMod._campWaitId = nil
          if MoveController and MoveController.SendMove then
            MoveController.SendMove(campX, campY)
          end
        end
      end
      return
    end

    -- Chặn client di chuyển tự động
    if MachineBox then MachineBox.autoMove = false end

    -- Quét tìm quái gần nhất trong bán kính
    if not Role.mapNpcs then return end
    local radius = VtcMod._campRadius or 500
    local radiusSq = radius * radius
    local bestNpc = nil
    local bestDistSq = math.huge

    for _, npc in pairs(Role.mapNpcs) do
      if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData
         and npc.data.eventNpcData.id and npc.data.eventNpcData.id ~= 0 then
        if npc.war == EWar.None and npc.position then
          -- Loại trừ NPC ẩn
          local isHidden = (npc.visible == ERoleVisible.Hide or npc.visible == ERoleVisible.TimeHide
                            or npc.originalVisibleState ~= nil)
          if not isHidden then
            -- Tính khoảng cách từ ANCHOR (không phải từ player)
            local dx = npc.position.x - campX
            local dy = npc.position.y - campY
            local distSq = dx * dx + dy * dy
            if distSq <= radiusSq and distSq < bestDistSq then
              bestDistSq = distSq
              bestNpc = npc
            end
          end
        end
      end
    end

    if bestNpc then
      local eventId = bestNpc.data.eventNpcData.id
      -- Di chuyển đến quái (nhẹ nhàng, chỉ SendMove bình thường)
      if bestNpc.position and MoveController and MoveController.SendMove then
        MoveController.SendMove(math.floor(bestNpc.position.x), math.floor(bestNpc.position.y))
      end
      -- Gửi packet Click/Bump
      if Network and Network.Send then
        -- BUG 2 FIX: Use ByteBuffer.New() instead of GetSendBuffer() to prevent race condition
        local buf1 = ByteBuffer.New()
        buf1:WriteUInt16(eventId)
        Network.Send(20, 2, buf1)
        local buf2 = ByteBuffer.New()
        buf2:WriteUInt16(eventId)
        Network.Send(20, 1, buf2)
      end
      -- Đặt trạng thái chờ vào trận
      VtcMod._campWaitId = eventId
      VtcMod._campWaitTimeout = CGTimer.time + 3.0
      VtcMod._campNextScan = CGTimer.time + 0.3
    else
      -- Không có quái → đảm bảo đứng yên tại anchor
      local dxP = pX - campX
      local dyP = pY - campY
      local pDistSq = dxP * dxP + dyP * dyP
      if pDistSq > 100 then -- > 10 pixels lệch → kéo về
        if MoveController and MoveController.SendMove then
          MoveController.SendMove(campX, campY)
        end
      end
    end
  end)

  -- =============================================
  -- DỊ GIỚI TRUY KÍCH TẠI CHỖ (Camp in Place, chỉ nhắm NPC ẩn)
  -- Cùng chiến thuật camp-in-place, nhưng lọc NPC ẩn (visible == Hide/TimeHide)
  -- =============================================
  pcall(function()
    if not VtcMod.autoDiGioiSniper then return end
    if not Role or not Role.player or not Role.player.position then return end
    if FightField and FightField.isInBattle then
      VtcMod._dgReturnAfterBattle = true
      VtcMod._dgWaitId = nil
      return
    end
    if SceneManager and SceneManager.isChangingScene then return end
    if CGTimer.time < (VtcMod._dgNextScan or 0) then return end
    VtcMod._dgNextScan = CGTimer.time + 0.3

    local pX = Role.player.position.x
    local pY = Role.player.position.y
    local campX = VtcMod._dgCampX or math.floor(pX)
    local campY = VtcMod._dgCampY or math.floor(pY)

    if not VtcMod._dgCampX then
      VtcMod._dgCampX = math.floor(pX)
      VtcMod._dgCampY = math.floor(pY)
      campX = VtcMod._dgCampX
      campY = VtcMod._dgCampY
    end

    -- Sau trận → quay về anchor
    if VtcMod._dgReturnAfterBattle then
      VtcMod._dgReturnAfterBattle = false
      if MoveController and MoveController.SendMove then
        MoveController.SendMove(campX, campY)
      end
      VtcMod._dgNextScan = CGTimer.time + 1.5
      return
    end

    -- Đang chờ quái ẩn vào trận
    if VtcMod._dgWaitId then
      if CGTimer.time > (VtcMod._dgWaitTimeout or 0) then
        VtcMod._dgWaitId = nil
        if MoveController and MoveController.SendMove then
          MoveController.SendMove(campX, campY)
        end
        VtcMod._dgNextScan = CGTimer.time + 0.5
        return
      end
      if Role.mapNpcs then
        local found = false
        for _, npc in pairs(Role.mapNpcs) do
          if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData
             and npc.data.eventNpcData.id == VtcMod._dgWaitId and npc.war == EWar.None then
            found = true
            if npc.position and MoveController and MoveController.SendMove then
               MoveController.SendMove(math.floor(npc.position.x), math.floor(npc.position.y))
            end
            if Network and Network.Send then
              -- BUG 2 FIX: Use ByteBuffer.New() instead of GetSendBuffer() to prevent race condition
              local buf1 = ByteBuffer.New()
              buf1:WriteUInt16(VtcMod._dgWaitId)
              Network.Send(20, 2, buf1)
              local buf2 = ByteBuffer.New()
              buf2:WriteUInt16(VtcMod._dgWaitId)
              Network.Send(20, 1, buf2)
            end
            break
          end
        end
        if not found then
          VtcMod._dgWaitId = nil
          if MoveController and MoveController.SendMove then
            MoveController.SendMove(campX, campY)
          end
        end
      end
      return
    end

    -- Chặn client di chuyển tự động (KHÔNG xóa SendRolePosition listener để tránh phá sync vĩnh viễn)
    if MachineBox then MachineBox.autoMove = false end
    if Role and Role.player then Role.player:StopMove() end

    -- Quét tìm quái trong phạm vi cấu hình
    if not Role.mapNpcs then return end
    local radius = VtcMod._dgRadius or 1200
    local maxRadiusSq = radius * radius
    local bestNpc = nil
    local bestDistSq = math.huge

    for _, npc in pairs(Role.mapNpcs) do
      if npc and npc.kind == EHuman.MapNpc and npc.data and npc.data.eventNpcData and npc.data.eventNpcData.id ~= 0 then
        if npc.war == EWar.None and npc.position then
          local isOriginallyHidden = false
          if ERoleVisible then
            isOriginallyHidden = (npc.visible == ERoleVisible.Hide or npc.visible == ERoleVisible.TimeHide or npc.originalVisibleState ~= nil)
          else
            isOriginallyHidden = (npc.visible == 2 or npc.visible == 4 or npc.originalVisibleState ~= nil)
          end
          
          local isVisible = not isOriginallyHidden
          
          -- Bê nguyên xi bộ lọc "khắc nghiệt" của bản cũ: Chỉ đánh quái hiển thị thực sự,
          -- Bỏ qua các bóng ma decorative (trang trí) hoặc trigger sự kiện ảo!
          if isVisible then
            local dx = npc.position.x - campX
            local dy = npc.position.y - campY
            local distSq = dx * dx + dy * dy
            
            if distSq <= maxRadiusSq and distSq < bestDistSq then
              bestDistSq = distSq
              bestNpc = npc
            end
          end
        end
      end
    end


    if bestNpc then
      local eventId = bestNpc.data.eventNpcData.id
      if bestNpc.position and MoveController and MoveController.SendMove then
        -- Di chuyển trực tiếp đến mục tiêu (1 packet thay vì burst loop tránh flood server)
        MoveController.SendMove(math.floor(bestNpc.position.x), math.floor(bestNpc.position.y))
      end
      
      if Network and Network.Send then
        -- BUG 2 FIX: Use ByteBuffer.New() instead of GetSendBuffer() to prevent race condition
        local buf1 = ByteBuffer.New()
        buf1:WriteUInt16(eventId)
        Network.Send(20, 2, buf1)
        local buf2 = ByteBuffer.New()
        buf2:WriteUInt16(eventId)
        Network.Send(20, 1, buf2)
      end
      VtcMod._dgWaitId = eventId
      VtcMod._dgWaitTimeout = CGTimer.time + 3.0
      VtcMod._dgNextScan = CGTimer.time + 0.3
    else
      -- Không có quái ẩn → giữ vị trí anchor
      local dxP = campX - pX
      local dyP = campY - pY
      local pDistSq = dxP * dxP + dyP * dyP
      if pDistSq > 100 then
        if MoveController and MoveController.SendMove then
          MoveController.SendMove(campX, campY)
        end
      else
        -- Đứng tại Anchor: Thực hiện Wiggle (Lắc qua lại 50px) để Server kích hoạt Ám Lôi (Random Encounter)
        -- Dùng timer riêng để giảm tần suất wiggle (2 giây/lần thay vì 0.3 giây)
        if CGTimer.time >= (VtcMod._dgWiggleNextTime or 0) then
          VtcMod._dgWiggleNextTime = CGTimer.time + 2.0
          if MoveController and MoveController.SendMove then
            VtcMod._dgFakeMoveToggle = not VtcMod._dgFakeMoveToggle
            local offset = VtcMod._dgFakeMoveToggle and 50 or 0
            MoveController.SendMove(campX + offset, campY + offset)
          end
        end
      end
    end
  end)

  -- 0.1. Power Saving Mode Enforcement
  pcall(function()
    if VtcMod.persistentSampleMode and MachineBox and MachineBox.client and MachineBox.client.general then
      local sampleModeIndex = 12
      if EMachineBoxSwitch and EMachineBoxSwitch.SampleMode then
        sampleModeIndex = EMachineBoxSwitch.SampleMode
      end
      if not MachineBox.client.general[sampleModeIndex] then
        MachineBox.client.general[sampleModeIndex] = true
        logError("--- [VtcMod] Persistently Enforced Extreme Battle Simplicity (SampleMode) ---")
      end
    end
  end)

  -- 0.2. Power Saving Mode Enforcement
  pcall(function()
    if VtcMod.powerSaving then
      -- Wake up on any click/touch
      local clickDetected = false
      if Input and Input.GetMouseButtonDown and Input.GetMouseButtonDown(0) then
        clickDetected = true
      elseif UnityEngine and UnityEngine.Input and UnityEngine.Input.GetMouseButtonDown and UnityEngine.Input.GetMouseButtonDown(0) then
        clickDetected = true
      end
      
      if clickDetected then
        VtcMod.powerSaving = false
        VtcMod._powerSavingApplied = false
        if UIDebug and UIDebug.UpdateFeaturesList then
          UIDebug.UpdateFeaturesList()
          UIDebug.UpdateStatusText()
          if UIDebug.uiController then
            local scroll = UIDebug.uiController:FindScrollContent("ScrollContent_Function")
            if scroll then scroll:Reset(#UIDebug.modFeatures) end
          end
        end
        ShowCenterMessage("Da TAT Che Do Tiet Kiem Pin - Khoi Phuc Man Hinh!")
        pcall(function()
          if UnityEngine and UnityEngine.Application then
            UnityEngine.Application.targetFrameRate = VtcMod.targetFPS or 30
          end
          if Scene and Scene.sceneCamera then
            Scene.sceneCamera.enabled = true
          end
          if UnityEngine and UnityEngine.AudioListener then
            UnityEngine.AudioListener.pause = false
          end
        end)
      elseif not VtcMod._powerSavingApplied then
        VtcMod._powerSavingApplied = true
        -- Enforce 1 FPS, Disable Scene Camera, Disable Audio
        if UnityEngine and UnityEngine.Application and UnityEngine.Application.targetFrameRate ~= 1 then
          UnityEngine.Application.targetFrameRate = 1
        end
        if Scene and Scene.sceneCamera and Scene.sceneCamera.enabled then
          Scene.sceneCamera.enabled = false
          logError("--- [VtcMod] Disabled SceneCamera for Power Saving ---")
        end
        if UnityEngine and UnityEngine.AudioListener and not UnityEngine.AudioListener.pause then
          UnityEngine.AudioListener.pause = true
        end
      end
    else
      if VtcMod._powerSavingApplied then
        VtcMod._powerSavingApplied = false
        -- Restore Scene Camera if it was disabled
        if Scene and Scene.sceneCamera and not Scene.sceneCamera.enabled then
          Scene.sceneCamera.enabled = true
          logError("--- [VtcMod] Restored SceneCamera ---")
        end
        if UnityEngine and UnityEngine.AudioListener and UnityEngine.AudioListener.pause then
          UnityEngine.AudioListener.pause = false
        end
      end
    end
  end)

  -- 0.3. Universal Auto Party 2-Way (LEADER/MEMBER)
  pcall(function()
    if VtcMod.autoPartyMode ~= "NONE" and CGTimer and CGTimer.time then
      if CGTimer.time >= VtcMod._partyRejoinNextTime then
        VtcMod._partyRejoinNextTime = CGTimer.time + 2.0

        -- A. XỬ LÝ NHẬN THƯ MỜI / YÊU CẦU (PASSIVE ACCEPT)
        if Invitation and Invitation.invitations and Invitation.invitations[EInvitation.Team] then
          for roleId, inv in pairs(Invitation.invitations[EInvitation.Team]) do
            local shouldAccept = false

            -- LEADER Mode: Tự động Accept nếu người gửi có trong _partyList (Bỏ qua state check rườm rà)
            if VtcMod.autoPartyMode == "LEADER" then
              for _, memName in ipairs(VtcMod._partyList) do
                if memName and memName ~= "" and inv.name == memName then 
                  shouldAccept = true; 
                  break 
                end
              end
            end

            -- MEMBER Mode: Tự động Accept nếu người gửi đúng là Chủ Party Target
            if VtcMod.autoPartyMode == "MEMBER" then
              if inv.name == VtcMod._partyLeaderTarget then
                shouldAccept = true
                VtcMod._partyLeaderId = roleId
              end
            end

            if shouldAccept then
              logError("--- [Auto Party] ACCEPT: " .. tostring(inv.name) .. " ---")
              pcall(function() Invitation.Reply(EInvitation.Team, roleId, true) end)
              if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Auto Party] Đã tự động nhận: " .. tostring(inv.name)) end
            end
          end
        end

        -- B. XỬ LÝ GỬI THƯ MỜI / YÊU CẦU (ACTIVE REQUEST)
        if Role and Role.players then
          -- LEADER Mode: Quét map tìm member trong list chưa có team -> gửi Invite
          if VtcMod.autoPartyMode == "LEADER" then
            local currentMembers = Team.GetMember(Role.playerId, false) or {}
            local isFull = true
            for i = 2, 5 do
                local slotName = VtcMod._partyList[i]
                if slotName and slotName ~= "" then
                    local foundInTeam = false
                    for _, mem in pairs(currentMembers) do
                        if mem.name == slotName then
                            foundInTeam = true
                            break
                        end
                    end
                    if not foundInTeam then isFull = false end
                end
            end

            for pid, player in pairs(Role.players) do
              if pid and not isFull then
                local isAlone = false
                pcall(function() isAlone = Team.IsAlone(pid) end)
                if isAlone then
                  for i = 2, 5 do
                    if player.name == VtcMod._partyList[i] and VtcMod._partyList[i] ~= "" then
                      pcall(function() Social.Invite(pid) end)
                    end
                  end
                end
              end
              
              -- Set Quân Sư cho Slot 2
              local adviserName = VtcMod._partyList[2]
              if adviserName and adviserName ~= "" and player.name == adviserName then
                local isMyMember = false
                pcall(function() isMyMember = (Team.GetLeader(pid) == Role.player) end)
                if isMyMember then
                  local isAdv = false
                  pcall(function() isAdv = Team.IsAdviser(pid) end)
                  if not isAdv then
                    pcall(function()
                      -- BUG 3 FIX: Always use ByteBuffer.New() to prevent race condition
                      local buf = ByteBuffer.New()
                      buf:WriteInt64(pid)
                      Network.Send(13, 5, buf)
                    end)
                  end
                end
              end
            end
          end

          -- MEMBER Mode: Quét map tìm chủ party -> gửi Request Join
          if VtcMod.autoPartyMode == "MEMBER" then
            local myLeader = Team.GetLeader(Role.playerId)
            local targetLeader = VtcMod._partyLeaderTarget
            if targetLeader and targetLeader ~= "" then
                if Team.IsAlone(Role.playerId) then
                  for pid, player in pairs(Role.players) do
                    if player.name == targetLeader then
                      pcall(function()
                        local buf = ByteBuffer.New()
                        buf:WriteInt64(pid)
                        Network.Send(13, 1, buf)
                      end)
                      VtcMod._partyLeaderId = pid
                      if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Auto Party] Xin vào nhóm: " .. tostring(player.name)) end
                      VtcMod._partyRejoinNextTime = CGTimer.time + 3.0
                      break
                    end
                  end
                elseif myLeader and myLeader.name ~= targetLeader then
                  pcall(function() Team.Leave() end)
                  VtcMod._partyRejoinNextTime = CGTimer.time + 1.0
                end
            end
          end
        end

      end
    end
  end)

  -- 1. Continuous Speed Hack Reinforcer & Battle Speed Hack (Throttled)
  this._speedCheckTimer = (this._speedCheckTimer or 0) + 1
  if this._speedCheckTimer >= 30 then
    this._speedCheckTimer = 0
    pcall(function()
      Role.baseSpeed = VtcMod.movementSpeed or 160
      if Role.player then
        Role.player.baseSpeed = VtcMod.movementSpeed or 160
        if Role.player.speed ~= Role.player.baseSpeed then
          Role.player.speed = Role.player.baseSpeed
        end
      end
    end)
    if SceneManager and SceneManager.sceneState then
      SceneManager.sceneState.moveSpeed = VtcMod.movementSpeed or 260
    end
    if FightField and FightField.isInBattle then
      FightField.timeScale = VtcMod.battleTimeScale or 2
      VtcMod.autoSkipEventToBattle = false
    end

    -- 1.1. Continuous FPS Lock
    pcall(function()
      if not VtcMod.powerSaving then
        local fps = VtcMod.targetFPS or 30
        if UnityEngine and UnityEngine.Application and UnityEngine.Application.targetFrameRate ~= fps then
          UnityEngine.Application.targetFrameRate = fps
        end
      end
    end)
  end



  -- 2.3. Speed Hack Debug Logger
  -- this.debugTimer = (this.debugTimer or 0) + 1
  -- if this.debugTimer >= 60 then
  --   this.debugTimer = 0
  --   if Role and Role.player then
  --     logError(string.format("--- [VtcMod] DEBUG SPEED: baseSpeed=%s, playerSpeed=%s, sceneSpeed=%s ---", 
  --       tostring(Role.baseSpeed), tostring(Role.player.speed), 
  --       tostring(SceneManager and SceneManager.sceneState and SceneManager.sceneState.moveSpeed)))
  --   else
  --     logError("--- [VtcMod] DEBUG SPEED: Role.player is nil ---")
  --   end
  -- end
end

-- Teleport instantly to map coordinates using Shadow Move technique
function VtcMod.TeleportToMapPos(x, y)
  if not Role or not Role.player or not MoveController then return end
  
  -- Disable auto pathing to prevent interference
  if MachineBox then MachineBox.autoMove = false end
  Role.player:StopMove()
  
  -- Snap local coordinate visually and logically
  Role.player.position = Vector2.New(x, y)
  Role.player:SetPosition(Role.player.position)
  
  -- Transmit the final target position immediately to the server
  if MoveController.SendMove then
    MoveController.SendMove(x, y)
    ShowCenterMessage("Đã dịch chuyển tới: " .. math.floor(x) .. ", " .. math.floor(y))
  end
end

-- =============================================
-- AUTO-DECOMPOSE GIFT BAGS: Helper Functions
-- =============================================

-- Snapshot current bag state (slot -> {Id, quant})
function VtcMod.TakeDecomposeSnapshot()
  local snapshot = {}
  pcall(function()
    local bag = Item.GetBag(EThings.Bag)
    if bag then
      for k, v in pairs(bag) do
        if v and v.Id and v.Id > 0 then
          snapshot[k] = { Id = v.Id, quant = v.quant or 1 }
        end
      end
    end
  end)
  return snapshot
end

-- Compare current bag vs snapshot, return list of NEW items only
function VtcMod.DiffDecomposeSnapshot(oldSnapshot)
  local newItems = {}
  pcall(function()
    local bag = Item.GetBag(EThings.Bag)
    if bag then
      for k, v in pairs(bag) do
        if v and v.Id and v.Id > 0 then
          local old = oldSnapshot[k]
          if not old then
            -- Completely new slot
            table.insert(newItems, { bagIndex = k, Id = v.Id, quant = v.quant or 1, isNewSlot = true })
          elseif old.Id ~= v.Id then
            -- Slot changed item (old was consumed, new appeared)
            table.insert(newItems, { bagIndex = k, Id = v.Id, quant = v.quant or 1, isNewSlot = true })
          elseif (v.quant or 0) > (old.quant or 0) then
            -- Same item, quantity increased (stacking) - only the delta is new
            table.insert(newItems, { bagIndex = k, Id = v.Id, quant = (v.quant or 0) - (old.quant or 0), isNewSlot = false })
          end
        end
      end
    end
  end)
  return newItems
end

-- Find up to 'limit' gift bags in inventory (ANY group), return table of {slot, id}
function VtcMod.FindGiftBagsInBag(limit)
  limit = limit or 2
  local actions = {}
  local bag = Item.GetBag(EThings.Bag)
  if not bag then return actions end
  local totalFound = 0
  for k, v in pairs(bag) do
    if v and v.Id and v.Id > 0 and VtcMod.GIFT_BAG_IDS[v.Id] and not VtcMod._decomposeBlacklist[k] then
      table.insert(actions, { slot = k, id = v.Id })
      totalFound = totalFound + 1
      if totalFound >= limit then break end
    end
  end
  return actions
end

-- Find up to 'limit' bags from a SPECIFIC ID table (e.g. GROUP_A_IDS only)
function VtcMod.FindGiftBagsByIds(idTable, limit)
  limit = limit or 2
  local actions = {}
  local bag = Item.GetBag(EThings.Bag)
  if not bag then return actions end
  local totalFound = 0
  for k, v in pairs(bag) do
    if v and v.Id and v.Id > 0 and idTable[v.Id] and not VtcMod._decomposeBlacklist[k] then
      table.insert(actions, { slot = k, id = v.Id })
      totalFound = totalFound + 1
      if totalFound >= limit then break end
    end
  end
  return actions
end

-- Count free (empty) slots in player bag (smart fallback: 120 if API fails)
function VtcMod.CountFreeSlots()
  local freeSlots = 0
  pcall(function()
    local bag = Item.GetBag(EThings.Bag)
    if not bag then return end
    -- Method 1: Try game API
    local maxSlots = 0
    if Item and Item.GetBagMaxCount then
      maxSlots = Item.GetBagMaxCount(EThings.Bag) or 0
    end
    -- Count used slots + find highest slot key for smart fallback
    local usedSlots = 0
    local maxKey = -1
    for k, v in pairs(bag) do
      if v and v.Id and v.Id > 0 then
        usedSlots = usedSlots + 1
      end
      if type(k) == "number" and k > maxKey then maxKey = k end
    end
    -- Smart fallback: if API failed or returned wrong value, derive from data
    if maxSlots <= 0 or maxSlots < usedSlots then
      maxSlots = math.max((maxKey >= 0) and (maxKey + 1) or 0, 120)
    end
    freeSlots = math.max(0, maxSlots - usedSlots)
  end)
  return freeSlots
end

-- Start the auto-decompose process (Throttled Multi-Worker Pipeline)
function VtcMod.StartAutoDecompose()
  if VtcMod._decomposeActive then
    ShowCenterMessage("Đang xử lý phân giải, vui lòng chờ...")
    return
  end
  if FightField and FightField.isInBattle then
    ShowCenterMessage("Không thể phân giải trong trận đấu!")
    return
  end
  VtcMod._decomposeActive = true
  VtcMod._decomposeStep = 1
  VtcMod._decomposeNextTime = 0
  VtcMod._decomposeCurrentBag = nil
  VtcMod._decomposeNewItems = {}
  VtcMod._decomposeSnapshot = {}
  VtcMod._decomposeTotalOpened = 0
  VtcMod._decomposeTotalDismantled = 0
  VtcMod._decomposeTotalDonated = 0
  VtcMod._decomposeTotalDropped = 0
  VtcMod._decomposeStartTime = CGTimer.time
  VtcMod._decomposeIterations = 0
  VtcMod._decomposeWorkerCount = 0
  VtcMod._decomposeBlacklist = {}
  VtcMod._decomposeActionIdx = 0
  VtcMod._decomposeStep3Start = 0
  -- Two-Phase Pipeline resets (Group A: fast 3-5, Group B: safe 1-2)
  VtcMod._decomposeRecursionDepth = 0
  VtcMod._decomposeBatchBags = {}
  VtcMod._decomposeBatchOpenIdx = 0
  logError("--- [AutoDecompose] Started (Two-Phase Pipeline, A:3-5, B:1-2, reserved=5, maxDepth=8) ---")
  if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Phân Giải] Bắt đầu quét túi đồ (A:3-5, B:1-2, giữ 5 ô dự phòng)...") end
end



