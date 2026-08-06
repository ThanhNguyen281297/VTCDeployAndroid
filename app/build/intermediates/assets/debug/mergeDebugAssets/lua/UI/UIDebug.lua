-- TS Online VTC - Custom Premium Vietnamese Mod Control Panel
require "Logic/VtcMod"
if VtcMod and not VtcMod.initialized then VtcMod.Init() end

UIDebug = UIDebug or {};
local this = UIDebug;

this.name = "UIDebug";
this.uiController = nil;
this.RecordMode = false;
this.customLogin = false;
this.testSkillList = {};

local image_Mask;
local text_Info;
local scrollContent_Function;
local scrollItems_Function = {};
local dropdown_Function;
local dropdown_Skill;
local inputField_Args = {};
local inputField_RoleId;
local modFeatures = {};

-- Settings injected by Patcher
VtcMod.autoBuyDungeonCount = tonumber("__AUTO_BUY_DUNGEON__") or 0
UIDebug.language = "__LANGUAGE__"
if UIDebug.language ~= "EN" and UIDebug.language ~= "VN" then UIDebug.language = "VN" end

function UIDebug.ForceVerticalLayout()
  pcall(function()
    local panelWidth = 1370 -- wide enough for 6 columns

    -- Get ScrollContent RectTransform
    local rectTrans = scrollContent_Function.gameObject:GetComponent("RectTransform")
    if rectTrans then
      rectTrans.sizeDelta = Vector2.New(panelWidth, rectTrans.sizeDelta.y)
    end
    
    -- Find and configure ScrollRect to scroll vertically and horizontally
    local scrollRect = scrollContent_Function.gameObject:GetComponent("ScrollRect")
    if not scrollRect and scrollContent_Function.transform then
      scrollRect = scrollContent_Function.transform:GetComponent("ScrollRect")
      if not scrollRect then
        scrollRect = scrollContent_Function.transform:GetComponentInParent("ScrollRect")
      end
    end
    if scrollRect then
      scrollRect.horizontal = true
      scrollRect.vertical = true
      
      -- Also shrink the ScrollRect viewport and container widths
      local srRectTrans = scrollRect.gameObject:GetComponent("RectTransform")
      if srRectTrans then
        srRectTrans.sizeDelta = Vector2.New(panelWidth, srRectTrans.sizeDelta.y)
      end
      
      -- If there is a viewport under ScrollRect, shrink it too
      local viewportTrans = scrollRect.transform:Find("Viewport")
      if viewportTrans then
        local vpRectTrans = viewportTrans:GetComponent("RectTransform")
        if vpRectTrans then
          vpRectTrans.sizeDelta = Vector2.New(panelWidth, vpRectTrans.sizeDelta.y)
        end
      end
    end

    -- Configure GridLayoutGroup
    local gridLayout = scrollContent_Function.gameObject:GetComponent("GridLayoutGroup")
    if not gridLayout and scrollContent_Function.transform then
      gridLayout = scrollContent_Function.transform:GetComponent("GridLayoutGroup")
      if not gridLayout then
        local contentTrans = scrollContent_Function.transform:Find("Content")
        if contentTrans then
          gridLayout = contentTrans:GetComponent("GridLayoutGroup")
        end
      end
    end
    if gridLayout then
      gridLayout.constraint = 1 -- FixedColumnCount
      gridLayout.constraintCount = 6
      gridLayout.cellSize = Vector2.New(220, gridLayout.cellSize.y)
      gridLayout:SetLayoutDirty()
    end
  end)
end

function UIDebug.Initialize(go)
  local uiController = go:GetComponent("UIController");
  this.uiController = uiController;
  this.uiController.onOpen = this.OnOpen;
  
  image_Mask = uiController:FindImage("Image_Mask");
  text_Info = uiController:FindText("Text_Info");
  
  scrollContent_Function = uiController:FindScrollContent("ScrollContent_Function");
  scrollContent_Function.onInitialize = this.OnInitialize_ScrollContent_Function;
  scrollContent_Function.onItemChange = this.OnItemChange_ScrollContent_Function;
  
  -- Force vertical layout before component initialization to affect internal cache
  this.ForceVerticalLayout();
  scrollContent_Function:Initialize(1);
  -- Force vertical layout after component initialization
  this.ForceVerticalLayout();

  dropdown_Function = uiController:FindDropdown("Dropdown_Function");
  this.dropdown_Function = dropdown_Function;
  dropdown_Skill = uiController:FindDropdown("Dropdown_Skill");

  for i = 1, 15 do
    inputField_Args[i] = uiController:FindInputField(string.format("InputField_Args (%d)", i));
  end
  inputField_RoleId = uiController:FindInputField("InputField_RoleId");

  -- Hide all legacy elements immediately during initialization to avoid cluttering/flashing
  pcall(function()
    if dropdown_Function and dropdown_Function.gameObject then dropdown_Function.gameObject:SetActive(true) end
    if dropdown_Skill and dropdown_Skill.gameObject then dropdown_Skill.gameObject:SetActive(false) end
    if inputField_RoleId and inputField_RoleId.gameObject then inputField_RoleId.gameObject:SetActive(false) end
    for i = 1, 15 do
      if inputField_Args[i] and inputField_Args[i].gameObject then inputField_Args[i].gameObject:SetActive(false) end
    end
    local imgSend = uiController:FindGameObject("Image_Send")
    if imgSend then 
      imgSend:SetActive(false)
      local rt = imgSend:GetComponent("RectTransform")
      if rt and Vector3 then rt.localScale = Vector3.New(0,0,0) end
    end
    local imgReset = uiController:FindGameObject("Image_Reset")
    if imgReset then 
      imgReset:SetActive(true)
      local rt = imgReset:GetComponent("RectTransform")
      if rt and Vector3 then rt.localScale = Vector3.New(1,1,1) end
    end
    local evReset = uiController:FindEvent("Image_Reset")
    if evReset then
      evReset:SetListener(EventTriggerType.PointerClick, this.OnClick_Reset)
    end
  end)

  local tempEvent = uiController:FindEvent("Image_Switch");
  if tempEvent then
    tempEvent:SetListener(EventTriggerType.PointerClick, this.OnClick_Switch);
  end
end

function UIDebug.OnOpen()
  logError("--- [VtcModUI] UIDebug.OnOpen() - Displaying Premium Mod Menu Layer! ---");
  
  if image_Mask == nil or this.uiController == nil then
    logError("--- [VtcModUI] image_Mask or uiController is nil, deferring OnOpen! ---");
    return true;
  end

  -- Debug: Always show it for now!
  pcall(function()
    ShowCenterMessage("VtcMod UIDebug V2 Loaded!");
    image_Mask.gameObject:SetActive(true);
    this.firstOpenDone = true;
  end)
  
  -- Hide legacy GM Debug elements to clean up the screen
  pcall(function()
    if dropdown_Function and dropdown_Function.gameObject then
      dropdown_Function.gameObject:SetActive(true)
    end
    if dropdown_Skill and dropdown_Skill.gameObject then
      dropdown_Skill.gameObject:SetActive(false)
    end
    if inputField_RoleId and inputField_RoleId.gameObject then
      inputField_RoleId.gameObject:SetActive(false)
    end
    for i = 1, 15 do
      if inputField_Args[i] and inputField_Args[i].gameObject then
        inputField_Args[i].gameObject:SetActive(false)
      end
    end
    
    local imgSend = this.uiController:FindGameObject("Image_Send")
    if imgSend then 
      imgSend:SetActive(false)
      local rt = imgSend:GetComponent("RectTransform")
      if rt and Vector3 then rt.localScale = Vector3.New(0,0,0) end
    end
    local imgReset = this.uiController:FindGameObject("Image_Reset")
    if imgReset then 
      imgReset:SetActive(true)
      local rt = imgReset:GetComponent("RectTransform")
      if rt and Vector3 then rt.localScale = Vector3.New(1,1,1) end
    end
    
    -- Crucial: Ensure the Eye Switch Button is active and visible!
    local imgSwitch = this.uiController:FindGameObject("Image_Switch")
    if imgSwitch then imgSwitch:SetActive(true) end
  end)

  this.UpdateFeaturesList();
  this.UpdateStatusText();
  
  pcall(function()
    scrollContent_Function:Reset(#modFeatures);
    -- this.ForceVerticalLayout(); -- Removed to prevent redundant rebuilds
  end)
  
  return true;
end

function UIDebug.OnClick_Reset(sender)
  logError("--- [VtcModUI] Reset Button Clicked! ---")
  
  -- Reset all values to default
  VtcMod.movementSpeed = 260
  if Role and Role.player then Role.player.baseSpeed = 260 end
  
  VtcMod.battleTimeScale = 2
  if FightField then FightField.timeScale = 2 end
  
  VtcMod.targetFPS = 30
  if UnityEngine and UnityEngine.Application then UnityEngine.Application.targetFrameRate = 30 end
  
  VtcMod.powerSaving = false
  VtcMod.autoBuffOutBattle = false
  VtcMod.autoPetBuffOutBattle = false
  VtcMod.autoDailyQuests = false
  VtcMod.persistentSampleMode = false
  VtcMod.autoRemoteSniper = false
  VtcMod.autoAnotherWorldSniper = false
  VtcMod.autoTalkSkip = false
  VtcMod.wallHack = false
  VtcMod.autoBuyDungeonCount = tonumber("__AUTO_BUY_DUNGEON__") or 0

  VtcMod.showHiddenNpc = false
  
  if Chat and EChannel then Chat.AddMessage(EChannel.System, "[System] Đã khôi phục toàn bộ tính năng về mặc định!") end
  ShowCenterMessage("Đã reset toàn bộ tính năng!")
  
  this.UpdateFeaturesList()
  this.UpdateStatusText()
  pcall(function()
    scrollContent_Function:Reset(#modFeatures)
    -- this.ForceVerticalLayout()
  end)
end

function UIDebug.OnClick_Switch(sender)
  logError("--- [VtcModUI] Eye Button Clicked! ---")
  if image_Mask == nil or this.uiController == nil then
    logError("--- [VtcModUI] image_Mask or uiController is nil! ---")
    return
  end
  
  local active = not image_Mask.gameObject.activeSelf
  logError("--- [VtcModUI] Setting Panel Active: " .. tostring(active))
  image_Mask.gameObject:SetActive(active)
  
  if active then
    this.UpdateFeaturesList()
    this.UpdateStatusText()
    pcall(function()
      scrollContent_Function:Reset(#modFeatures)
      -- this.ForceVerticalLayout()
    end)
  end
end

function UIDebug.UpdateStatusText()
  if not text_Info then return end
  
  if VtcMod.powerSaving then
    local lines = {}
    if UIDebug.language == "EN" then
      table.insert(lines, "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
      table.insert(lines, "  🔋 POWER SAVING ACTIVE 🔋")
      table.insert(lines, "  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      table.insert(lines, "  - Framerate locked to 1 FPS.")
      table.insert(lines, "  - Map & character rendering completely disabled.")
      table.insert(lines, "  - Audio (AudioListener) completely disabled.")
      table.insert(lines, "  - Game is running silently in background.")
      table.insert(lines, "  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      table.insert(lines, "  👉 CLICK ANYWHERE ON SCREEN TO RESTORE!")
    else
      table.insert(lines, "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
      table.insert(lines, "  🔋 TIẾT KIỆM PIN ĐANG HOẠT ĐỘNG 🔋")
      table.insert(lines, "  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      table.insert(lines, "  - Đã khóa giới hạn khung hình xuống 1 FPS.")
      table.insert(lines, "  - Đã tắt hoàn toàn Camera render bản đồ & nhân vật.")
      table.insert(lines, "  - Đã ngắt hoàn toàn Âm Thanh (AudioListener).")
      table.insert(lines, "  - Game vẫn đang chạy tự động chiến đấu ngầm.")
      table.insert(lines, "  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      table.insert(lines, "  👉 NHẤP VÀO BẤT KỲ ĐÂU TRÊN MÀN HÌNH ĐỂ KHÔI PHỤC!")
    end
    text_Info.text = table.concat(lines, "\n")
    return
  end
  
  local mapName = UIDebug.language == "EN" and "Unknown" or "Không xác định"
  pcall(function()
    if SceneManager and SceneManager.sceneId then
      if sceneDatas and sceneDatas[SceneManager.sceneId] then
        mapName = sceneDatas[SceneManager.sceneId].name or (UIDebug.language == "EN" and "Unknown" or "Không xác định")
      end
    end
  end)
  
  local lines = {}
  table.insert(lines, "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
  table.insert(lines, "  🌟 VTC MOD PANEL - VIP 🌟")
  table.insert(lines, "  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
  if UIDebug.language == "EN" then
      table.insert(lines, string.format("  📍 Current Map: %s", mapName))
      table.insert(lines, string.format("  🏃 Move Speed: %s", VtcMod.movementSpeed == 500 and "FAST" or (VtcMod.movementSpeed == 2000 and "EXTREME" or "NORMAL")))
      table.insert(lines, string.format("  ⚡ Battle Speed: x%s", VtcMod.battleTimeScale == 2 and "NORMAL" or (VtcMod.battleTimeScale == 20 and "FAST x20" or "EXTREME x50")))
      table.insert(lines, string.format("  💬 Auto-Talk: %s", VtcMod.autoTalkSkip and "ON" or "OFF"))
      table.insert(lines, string.format("  🧱 Wallhack: %s", VtcMod.wallHack and "ON" or "OFF"))

      table.insert(lines, string.format("  ⚡ Stealth Battle: %s", VtcMod.persistentSampleMode and "ON" or "OFF"))
      table.insert(lines, string.format("  🤖 Daily Quests: %s", VtcMod._dailyStep > 0 and ("RUNNING " .. VtcMod._dailyStep .. "/9") or "OFF"))
  else
      table.insert(lines, string.format("  📍 Bản đồ hiện tại: %s", mapName))
      table.insert(lines, string.format("  🏃 Tốc độ chạy: %s", VtcMod.movementSpeed == 500 and "NHANH" or (VtcMod.movementSpeed == 2000 and "CỰC NHANH" or "THƯỜNG")))
      table.insert(lines, string.format("  ⚡ Tốc độ trận đấu: x%s", VtcMod.battleTimeScale == 2 and "THƯỜNG" or (VtcMod.battleTimeScale == 20 and "NHANH x20" or "CỰC NHANH x50")))
      table.insert(lines, string.format("  💬 Auto-Talk: %s", VtcMod.autoTalkSkip and "BẬT" or "TẮT"))
      table.insert(lines, string.format("  🧱 Đi xuyên tường: %s", VtcMod.wallHack and "BẬT" or "TẮT"))

      table.insert(lines, string.format("  ⚡ Đấu Ngầm: %s", VtcMod.persistentSampleMode and "BẬT" or "TẮT"))
      table.insert(lines, string.format("  🤖 Bot Nhiệm Vụ Ngày: %s", VtcMod._dailyStep > 0 and ("ĐANG CHẠY " .. VtcMod._dailyStep .. "/9") or "TẮT"))
  end
  table.insert(lines, "  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
  text_Info.text = table.concat(lines, "\n")
end

function UIDebug.UpdateFeaturesList()
  -- Reuse existing table instead of creating new one (reduces GC pressure on Android emulator)
  for k in pairs(modFeatures) do modFeatures[k] = nil end
  
  local cols = {}
  for i=1, 5 do cols[i] = {} end

  -- COL 1: 🔋 TỐI ƯU PIN (Col1_ToiUuPin)
  table.insert(cols[1], { name = UIDebug.language == "EN" and "<b><color=#FFD700>🔋 POWER OPT</color></b>" or "<b><color=#FFD700>🔋 TỐI ƯU PIN</color></b>", callback = nil })
  table.insert(cols[1], {
    name = string.format(UIDebug.language == "EN" and "❄️ Lock FPS: %d FPS" or "❄️ Khóa FPS: %d FPS", VtcMod.targetFPS or 30),
    isActive = function() return VtcMod.targetFPS and VtcMod.targetFPS ~= 30 end,
    callback = function()
      local cur = VtcMod.targetFPS or 30
      local nextFPS = 30
      if cur == 30 then nextFPS = 40
      elseif cur == 40 then nextFPS = 50
      elseif cur == 50 then nextFPS = 60
      elseif cur == 60 then nextFPS = 10
      elseif cur == 10 then nextFPS = 20
      elseif cur == 20 then nextFPS = 30
      end
      VtcMod.targetFPS = nextFPS
      pcall(function()
        if UnityEngine and UnityEngine.Application then
          UnityEngine.Application.targetFrameRate = nextFPS
        end
        if Application then
        end
      end)
      ShowCenterMessage(UIDebug.language == "EN" and ("FPS locked to: " .. nextFPS) or ("Tốc độ FPS khóa chuyển sang: " .. nextFPS .. " FPS"))
    end
  })
  table.insert(cols[1], {
    name = string.format(UIDebug.language == "EN" and "🔋 Power Saving: %s" or "🔋 Tiết Kiệm Pin: %s", VtcMod.powerSaving and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.powerSaving end,
    callback = function()
      VtcMod.powerSaving = not VtcMod.powerSaving
      if VtcMod.powerSaving then
        ShowCenterMessage(UIDebug.language == "EN" and "Power Saving ON (1 FPS, CPU reduced)! Click anywhere to disable." or "Đã BẬT Chế Độ Tiết Kiệm Pin (1 FPS, Giảm CPU)! Nhấp bất kỳ đâu để tắt.")
        pcall(function()
          if UnityEngine and UnityEngine.Application then
            UnityEngine.Application.targetFrameRate = 1
          end
        end)
        pcall(function()
          if Scene and Scene.sceneCamera then
            Scene.sceneCamera.enabled = false
          end
          if UnityEngine and UnityEngine.AudioListener then
            UnityEngine.AudioListener.pause = true
          end
        end)
        -- Ghi nhớ tên chủ party hiện tại (nếu đang ở trong party)
        pcall(function()
          if Team and Role and Role.playerId and not Team.IsAlone(Role.playerId) then
            local leader = Team.GetLeader(Role.playerId)
            if leader and leader.name and leader.index then
              VtcMod._savedPartyLeaderName = leader.name
              VtcMod._savedPartyLeaderId = leader.index
              logError("--- [PowerSave] Da ghi nho chu party: " .. tostring(leader.name) .. " (ID=" .. tostring(leader.index) .. ") ---")
              if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Tiết Kiệm Pin] Đã ghi nhớ chủ party: " .. tostring(leader.name)) end
            end
          else
            logError("--- [PowerSave] Player dang khong o trong party nao. Khong ghi nho chu party. ---")
            if VtcMod._savedPartyLeaderName then
              logError("--- [PowerSave] Van giu ten chu party cu: " .. tostring(VtcMod._savedPartyLeaderName) .. " ---")
              if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Tiết Kiệm Pin] Giữ tên chủ party cũ: " .. tostring(VtcMod._savedPartyLeaderName)) end
            end
          end
        end)
      else
        ShowCenterMessage(UIDebug.language == "EN" and "Power Saving OFF - Display restored!" or "Đã TẮT Chế Độ Tiết Kiệm Pin - Khôi Phục Màn Hình!")
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
        if Chat and EChannel then Chat.AddMessage(EChannel.System, "[Tiết Kiệm Pin] TẮT.") end
      end
    end
  })

  table.insert(cols[1], {
    name = string.format(UIDebug.language == "EN" and "👑 Party Leader: %s" or "👑 Chủ Party: %s", VtcMod.autoPartyMode == "LEADER" and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoPartyMode == "LEADER" end,
    callback = function()
      if VtcMod.autoPartyMode == "LEADER" then
        VtcMod.autoPartyMode = "NONE"
        ShowCenterMessage(UIDebug.language == "EN" and "Party Leader mode OFF." or "Đã TẮT chế độ Chủ Party.")
      else
        VtcMod.autoPartyMode = "LEADER"
        ShowCenterMessage(UIDebug.language == "EN" and "Party Leader ON! Auto-inviting members from Settings." or "Đã BẬT Chủ Party! Sẽ tự động mời các thành viên từ Settings.")
      end
      -- Removed redundant UpdateFeaturesList/Reset calls (handled by OnClick_Function)

    end
  })
  table.insert(cols[1], {
    name = string.format(UIDebug.language == "EN" and "🤝 Party Member: %s" or "🤝 Thành Viên: %s", VtcMod.autoPartyMode == "MEMBER" and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoPartyMode == "MEMBER" end,
    callback = function()
      if VtcMod.autoPartyMode == "MEMBER" then
        VtcMod.autoPartyMode = "NONE"
        ShowCenterMessage(UIDebug.language == "EN" and "Party Member mode OFF." or "Đã TẮT chế độ Thành Viên.")
      else
        VtcMod.autoPartyMode = "MEMBER"
        ShowCenterMessage(UIDebug.language == "EN" and ("Party Member ON! Following leader: " .. tostring(VtcMod._partyLeaderTarget)) or ("Đã BẬT Thành Viên! Sẽ bám theo chủ party: " .. tostring(VtcMod._partyLeaderTarget)))
      end
      -- Removed redundant UpdateFeaturesList/Reset calls (handled by OnClick_Function)

    end
  })

  -- COL 2: 🤖 AUTO AI (Col2_AutoAI)
  table.insert(cols[2], { name = UIDebug.language == "EN" and "<b><color=#FFD700>🤖 AUTO AI</color></b>" or "<b><color=#FFD700>🤖 AUTO AI</color></b>", callback = nil })
  table.insert(cols[2], {
    name = string.format(UIDebug.language == "EN" and "🏥 Event Buff: %s" or "🏥 Event Buff (Full): %s", VtcMod.autoBuffOutBattle and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoBuffOutBattle end,
    callback = function()
      logError("--- [Col2_Debug] User clicked 1_MainEventBuff ---")
      VtcMod.autoBuffOutBattle = not VtcMod.autoBuffOutBattle
      if VtcMod.autoBuffOutBattle then
        VtcMod.autoTrainBuffOutBattle = false -- Mutually exclusive
        if CGTimer then VtcMod._buffDeadline = CGTimer.time + 15 else VtcMod._buffDeadline = 0 end
        VtcMod._needMainBuff = true
        ShowCenterMessage(UIDebug.language == "EN" and "Main Event Buff ON (Full 6 Tiers + Cross-Element + Smart Dispel)!" or "Đã BẬT Main Event Buff v5.7.1 (Full 6 Tiers + Cross-Element + Smart Dispel)!")
      else
        VtcMod._needMainBuff = false
        ShowCenterMessage(UIDebug.language == "EN" and "Main Event Buff OFF!" or "Đã TẮT Main Event Buff!")
        
        -- Reset lại Turn Queue khi tắt AI để dọn dẹp bộ nhớ chống xung đột
        if VtcMod.ActionQueueTargets then
            table.Clear(VtcMod.ActionQueueTargets)
        end
      end
    end
  })
  table.insert(cols[2], {
    name = string.format(UIDebug.language == "EN" and "⚔️ Train Buff (HP/SP/Revive): %s" or "⚔️ Train Buff (HP/SP/HS): %s", VtcMod.autoTrainBuffOutBattle and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoTrainBuffOutBattle end,
    callback = function()
      logError("--- [Col2_Debug] User clicked 2_MainTrainBuff ---")
      VtcMod.autoTrainBuffOutBattle = not VtcMod.autoTrainBuffOutBattle
      if VtcMod.autoTrainBuffOutBattle then
        VtcMod.autoBuffOutBattle = false -- Mutually exclusive
        if CGTimer then VtcMod._buffDeadline = CGTimer.time + 15 else VtcMod._buffDeadline = 0 end
        VtcMod._needMainBuff = true
        ShowCenterMessage(UIDebug.language == "EN" and "Train Buff ON (HP, SP, Revive)!" or "Đã BẬT Train Buff (HP, SP, Cứu Người)!")
      else
        VtcMod._needMainBuff = false
        ShowCenterMessage(UIDebug.language == "EN" and "Train Buff OFF!" or "Đã TẮT Train Buff!")
        
        -- Reset lại Turn Queue khi tắt Train AI để dọn dẹp bộ nhớ chống xung đột
        if VtcMod.ActionQueueTargets then
            table.Clear(VtcMod.ActionQueueTargets)
        end
      end
    end
  })
  table.insert(cols[2], {
    name = string.format(UIDebug.language == "EN" and "🐾 Pet Auto Buff: %s" or "🐾 Pet Auto Buff: %s", VtcMod.autoPetBuffOutBattle and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoPetBuffOutBattle end,
    callback = function()
      logError("--- [Col2_Debug] User clicked 2_CatBinhAutoBuff ---")
      VtcMod.autoPetBuffOutBattle = not VtcMod.autoPetBuffOutBattle
      if VtcMod.autoPetBuffOutBattle then
        logError("--- [Col2_Debug] 2_CatBinhAutoBuff: turning ON ---")
        if CGTimer then VtcMod._buffDeadline = CGTimer.time + 15 else VtcMod._buffDeadline = 0 end
        VtcMod._needPetBuff = true
        ShowCenterMessage(UIDebug.language == "EN" and "Pet Auto Buff ON!" or "Đã BẬT Pet Auto Buff trong trận!")
      else
        logError("--- [Col2_Debug] 2_CatBinhAutoBuff: turning OFF ---")
        VtcMod._needPetBuff = false
        ShowCenterMessage(UIDebug.language == "EN" and "Pet Auto Buff OFF!" or "Đã TẮT Pet Auto Buff!")
      end
    end
  })
  table.insert(cols[2], {
    name = string.format(UIDebug.language == "EN" and "🤖 Daily Quests: %s" or "🤖 Nhiệm Vụ Ngày: %s", VtcMod._dailyStep > 0 and (UIDebug.language == "EN" and ("🟢 RUNNING " .. VtcMod._dailyStep .. "/9") or ("🟢 ĐANG CHẠY " .. VtcMod._dailyStep .. "/9")) or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod._dailyStep > 0 end,
    callback = function()
      logError("--- [Col2_Debug] User clicked DailyQuests button ---")
      if VtcMod._dailyStep > 0 then
        VtcMod.CancelDailyQuests()
      else
        VtcMod.StartDailyQuests()
      end
      -- Removed redundant UpdateFeaturesList/Reset calls (handled by OnClick_Function)

    end
  })

  table.insert(cols[2], {
    name = string.format(UIDebug.language == "EN" and "🎰 Auto MaxRoll: %s" or "🎰 Auto MaxRoll: %s", UISlotMachine ~= nil and UISlotMachine.isMaxRolling and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return UISlotMachine ~= nil and UISlotMachine.isMaxRolling end,
    callback = function()
      if UISlotMachine == nil then
        ShowCenterMessage(UIDebug.language == "EN" and "You must open the Slot Machine first!" or "Bạn phải mở giao diện Xổ Quà trước!")
        return
      end
      
      if UISlotMachine.isMaxRolling == nil then
          UISlotMachine.isMaxRolling = false
      end
      
      UISlotMachine.isMaxRolling = not UISlotMachine.isMaxRolling
      
      if UISlotMachine.isMaxRolling then
          -- Cấy Timer độc lập (Loop mỗi 0.5s)
          CGTimer.AddListener(UISlotMachine.ExecuteMaxRollLogic, 0.5, false)
          ShowCenterMessage(UIDebug.language == "EN" and "Auto MaxRoll ON!" or "Đã BẬT Auto MaxRoll (Xổ Quà)!")
      else
          -- Gỡ Timer khi tắt để giải phóng CPU
          CGTimer.RemoveListener(UISlotMachine.ExecuteMaxRollLogic)
          if UISlotMachine.OnClick_Stop then pcall(UISlotMachine.OnClick_Stop) end
          ShowCenterMessage(UIDebug.language == "EN" and "Auto MaxRoll OFF!" or "Đã TẮT Auto MaxRoll (Xổ Quà)!")
      end
      
      -- Removed redundant UpdateFeaturesList/Reset calls
    end
  })

  -- COL 3: ⚔️ CHẾ ĐỘ FARM (Col3_CheDoFarm)
  table.insert(cols[3], { name = UIDebug.language == "EN" and "<b><color=#FFD700>⚔️ FARM MODE</color></b>" or "<b><color=#FFD700>⚔️ CHẾ ĐỘ FARM</color></b>", callback = nil })
  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "🏃 Move Speed: %s" or "🏃 Tốc Độ Chạy: %s", VtcMod.movementSpeed == 500 and (UIDebug.language == "EN" and "⚡ FAST" or "⚡ NHANH") or (VtcMod.movementSpeed == 2000 and (UIDebug.language == "EN" and "🔥 EXTREME" or "🔥 CỰC NHANH") or (UIDebug.language == "EN" and "🟢 NORMAL" or "🟢 THƯỜNG"))),
    isActive = function() return VtcMod.movementSpeed > 160 end,
    callback = function()
      if VtcMod.movementSpeed == 160 then
        VtcMod.movementSpeed = 500
      elseif VtcMod.movementSpeed == 500 then
        VtcMod.movementSpeed = 2000
      else
        VtcMod.movementSpeed = 160
      end
      if Role and Role.player then
        Role.player.baseSpeed = VtcMod.movementSpeed
      end
      ShowCenterMessage(UIDebug.language == "EN" and ("Move speed changed to: " .. VtcMod.movementSpeed) or ("Tốc độ chạy chuyển sang: " .. VtcMod.movementSpeed))
      -- Removed redundant UpdateFeaturesList/Reset calls (handled by OnClick_Function)

    end
  })
  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "⚡ Stealth Battle: %s" or "⚡ Đấu Ngầm: %s", VtcMod.persistentSampleMode and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.persistentSampleMode end,
    callback = function()
      VtcMod.persistentSampleMode = not VtcMod.persistentSampleMode
      if not VtcMod.persistentSampleMode and MachineBox and MachineBox.client and MachineBox.client.general then
        local sampleModeIndex = 12
        if EMachineBoxSwitch and EMachineBoxSwitch.SampleMode then
          sampleModeIndex = EMachineBoxSwitch.SampleMode
        end
        MachineBox.client.general[sampleModeIndex] = false
      end
      ShowCenterMessage(VtcMod.persistentSampleMode and (UIDebug.language == "EN" and "Stealth Battle ON!" or "Đã BẬT Cực Hạn Trận Đấu (SampleMode)!") or (UIDebug.language == "EN" and "Stealth Battle OFF!" or "Đã TẮT Cực Hạn Trận Đấu (SampleMode)!"))
    end
  })
  local speedDesc = UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT"
  if VtcMod.battleTimeScale == 50 then speedDesc = UIDebug.language == "EN" and "⚡ MAX x50" or "⚡ HẠN x50"
  elseif VtcMod.battleTimeScale == 20 then speedDesc = UIDebug.language == "EN" and "🟡 FAST x20" or "🟡 SIÊU x20"
  end
  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "⚡ Battle Speed: %s" or "⚡ Tốc Độ Trận: %s", speedDesc),
    isActive = function() return VtcMod.battleTimeScale > 2 end,
    callback = function()
      if VtcMod.battleTimeScale == 50 then
        VtcMod.battleTimeScale = 2 -- normal
      elseif VtcMod.battleTimeScale == 20 then
        VtcMod.battleTimeScale = 50
      else
        VtcMod.battleTimeScale = 20
      end
      if FightField then
        FightField.timeScale = VtcMod.battleTimeScale
      end
      ShowCenterMessage(UIDebug.language == "EN" and ("Battle speed changed to: x" .. VtcMod.battleTimeScale) or ("Tốc độ trận đấu chuyển sang: x" .. VtcMod.battleTimeScale))
    end
  })
  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "🎯 Standalone Sniper: %s" or "🎯 Truy Kích Tại Chỗ: %s", VtcMod.autoStandaloneSniper and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoStandaloneSniper end,
    callback = function()
      VtcMod.autoStandaloneSniper = not VtcMod.autoStandaloneSniper
      if VtcMod.autoStandaloneSniper then
        VtcMod.autoRemoteSniper = false
        VtcMod.autoAnotherWorldSniper = false
        VtcMod.autoDiGioiSniper = false
        VtcMod._dgCampX = nil
        VtcMod._dgCampY = nil
        VtcMod._dgWaitId = nil
        VtcMod._dgReturnAfterBattle = false
        
        if Role and Role.player and Role.player.position then
          VtcMod._campX = math.floor(Role.player.position.x)
          VtcMod._campY = math.floor(Role.player.position.y)
        end
        VtcMod._campWaitId = nil
        VtcMod._campWaitTimeout = 0
        VtcMod._campNextScan = 0
        VtcMod._campRadius = 500
        VtcMod._campReturnAfterBattle = false
        ShowCenterMessage(UIDebug.language == "EN" and "Standalone Sniper ON!" or "Đã BẬT Truy Kích Tại Chỗ!")
      else
        VtcMod._campX = nil
        VtcMod._campY = nil
        VtcMod._campWaitId = nil
        VtcMod._campWaitTimeout = 0
        VtcMod._campNextScan = 0
        VtcMod._campReturnAfterBattle = false
        pcall(function()
          if Role and Role.player then Role.player:StopMove() end
          if MachineBox then MachineBox.autoMove = true end
        end)
        ShowCenterMessage(UIDebug.language == "EN" and "Sniper OFF!" or "Đã TẮT Truy Kích!")
      end
    end
  })
  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "🌌 Underworld Sniper: %s" or "🌌 Dị Giới Truy Kích: %s", VtcMod.autoDiGioiSniper and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoDiGioiSniper end,
    callback = function()
      VtcMod.autoDiGioiSniper = not VtcMod.autoDiGioiSniper
      if VtcMod.autoDiGioiSniper then
        VtcMod.autoRemoteSniper = false
        VtcMod.autoAnotherWorldSniper = false
        VtcMod.autoStandaloneSniper = false
        VtcMod._campX = nil
        VtcMod._campY = nil
        VtcMod._dgWaitId = nil
        VtcMod._dgReturnAfterBattle = false
        
        if Role and Role.player and Role.player.position then
          VtcMod._dgCampX = math.floor(Role.player.position.x)
          VtcMod._dgCampY = math.floor(Role.player.position.y)
        end
        VtcMod._dgWaitId = nil
        VtcMod._dgWaitTimeout = 0
        VtcMod._dgNextScan = 0
        VtcMod._dgRadius = 500
        VtcMod._dgReturnAfterBattle = false
        ShowCenterMessage(UIDebug.language == "EN" and "Underworld Sniper ON!" or "Đã BẬT Dị Giới Truy Kích!")
      else
        VtcMod._dgCampX = nil
        VtcMod._dgCampY = nil
        VtcMod._dgWaitId = nil
        VtcMod._dgWaitTimeout = 0
        VtcMod._dgNextScan = 0
        VtcMod._dgReturnAfterBattle = false
        pcall(function()
          if Role and Role.player then Role.player:StopMove() end
          if MachineBox then MachineBox.autoMove = true end
        end)
        ShowCenterMessage(UIDebug.language == "EN" and "Underworld Sniper OFF!" or "Đã TẮT Dị Giới Truy Kích!")
      end
    end
  })

  table.insert(cols[3], {
    name = string.format(UIDebug.language == "EN" and "👺 Auto 40NPC: %s" or "👺 Auto 40NPC: %s", VtcMod.auto40NPC and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.auto40NPC end,
    callback = function()
      VtcMod.auto40NPC = not VtcMod.auto40NPC
      if VtcMod.auto40NPC then
        -- Tắt các chế độ farm xung đột khác
        VtcMod.autoDiGioiSniper = false
        VtcMod.autoRemoteSniper = false
        VtcMod.autoAnotherWorldSniper = false
        VtcMod.autoStandaloneSniper = false
        VtcMod._campX = nil
        VtcMod._campY = nil
        VtcMod._dgCampX = nil
        VtcMod._dgCampY = nil

        -- Sử dụng tọa độ cố định làm Anchor (Điểm Neo) thay vì vị trí hiện tại
        VtcMod._40NpcAnchorX = 990
        VtcMod._40NpcAnchorY = 310

        VtcMod._40NpcStep = 1
        VtcMod._40NpcWaitTimeout = 0
        VtcMod._40NpcLastActionTime = 0
        
        ShowCenterMessage(UIDebug.language == "EN" and "Auto 40NPC ON (Anchored)!" or "Đã BẬT Auto 40NPC (Neo vị trí)!")
        if Chat and EChannel then
          Chat.AddMessage(EChannel.System, "[40NPC] BẬT. Neo tại tọa độ: " .. tostring(VtcMod._40NpcAnchorX) .. ", " .. tostring(VtcMod._40NpcAnchorY))
        end
      else
        VtcMod._40NpcStep = 0
        VtcMod._40NpcWaitTimeout = 0
        VtcMod._40NpcLastActionTime = 0
        VtcMod._40NpcAnchorX = nil
        VtcMod._40NpcAnchorY = nil

        pcall(function()
          if Role and Role.player then Role.player:StopMove() end
          if MachineBox then MachineBox.autoMove = true end
        end)
        ShowCenterMessage(UIDebug.language == "EN" and "Auto 40NPC OFF!" or "Đã TẮT Auto 40NPC!")
        if Chat and EChannel then
          Chat.AddMessage(EChannel.System, "[40NPC] TẮT.")
        end
      end
      -- if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() end
      -- if UIDebug and UIDebug.UpdateStatusText then UIDebug.UpdateStatusText() end
    end
  })

  -- COL 4: 🛠️ TIỆN ÍCH (Col5_TienIch)
  table.insert(cols[4], { name = UIDebug.language == "EN" and "<b><color=#FFD700>🛠️ UTILITIES</color></b>" or "<b><color=#FFD700>🛠️ TIỆN ÍCH</color></b>", callback = nil })
  table.insert(cols[4], {
    name = UIDebug.language == "EN" and "🎒 Personal Bank" or "🎒 Rương Tiền Trang",
    callback = function()
      pcall(function()
        if not UI then return end
        if UIBank then
          if UI.IsVisible and UI.IsVisible(UIBank) then
            UI.Close(UIBank)
            ShowCenterMessage(UIDebug.language == "EN" and "Personal Bank closed." or "Đã đóng Rương Tiền Trang.")
          else
            UI.Open(UIBank, 2)
            ShowCenterMessage(UIDebug.language == "EN" and "Personal Bank opened remotely!" or "Đã mở Tiền Trang cá nhân từ xa!")
          end
        else
          ShowCenterMessage(UIDebug.language == "EN" and "UIBank not found!" or "Không tìm thấy UIBank!")
        end
      end)
    end
  })
  table.insert(cols[4], {
    name = string.format(
      UIDebug.language == "EN" and "📦 Quick Bank: %s" or "📦 QuickTiềnTrang: %s",
      VtcMod.quickBankEnabled 
        and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT")
        or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")
    ),
    isActive = function() return VtcMod.quickBankEnabled end,
    callback = function()
      VtcMod.quickBankEnabled = not VtcMod.quickBankEnabled
      if VtcMod.quickBankEnabled then
        ShowCenterMessage(
          UIDebug.language == "EN" 
            and "Quick Bank ON! Open bank to auto-transfer duplicate items." 
            or "Đã BẬT QuickTiềnTrang! Mở Tiền Trang để tự động chuyển đồ trùng."
        )
      else
        VtcMod._quickBankStep = 0
        VtcMod._quickBankQueue = {}
        VtcMod._quickBankQueueIdx = 0
        ShowCenterMessage(
          UIDebug.language == "EN" and "Quick Bank OFF!" or "Đã TẮT QuickTiềnTrang!"
        )
      end
      -- if UIDebug and UIDebug.UpdateFeaturesList then UIDebug.UpdateFeaturesList() end
    end
  })
  table.insert(cols[4], {
    name = UIDebug.language == "EN" and "🏨 Inn (Pet Storage)" or "🏨 Võ Tướng Khách Sạn",
    callback = function()
      pcall(function()
        if UINpcInn then
          UI.Open(UINpcInn)
          ShowCenterMessage(UIDebug.language == "EN" and "Inn opened remotely!" or "Đã mở Khách sạn cất/lấy tướng từ xa!")
        end
      end)
    end
  })

  table.insert(cols[4], {
    name = string.format(UIDebug.language == "EN" and "💬 Auto-Talk: %s" or "💬 Auto-Talk: %s", VtcMod.autoTalkSkip and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.autoTalkSkip end,
    callback = function()
      VtcMod.autoTalkSkip = not VtcMod.autoTalkSkip
      ShowCenterMessage(VtcMod.autoTalkSkip and (UIDebug.language == "EN" and "Auto-Talk ON!" or "Đã BẬT tự động bỏ qua hội thoại!") or (UIDebug.language == "EN" and "Auto-Talk OFF!" or "Đã TẮT tự động bỏ qua hội thoại!"))
    end
  })
  table.insert(cols[4], {
    name = UIDebug.language == "EN" and "🚀 Warp/Teleport" or "🚀 Warp Di Chuyển",
    callback = function()
      ShowCountInput(UIDebug.language == "EN" and "Enter Map ID (1-65000)" or "Nhập Map ID (1-65000)", 1, 65000, function(text)
        local mapId = tonumber(text)
        if mapId and mapId > 0 then
          if Role.player.war ~= EWar.None then
            ShowCenterMessage(UIDebug.language == "EN" and "Cannot teleport while in combat." or string.Get(80099))
            return
          end
          if Team.IsMember(Role.playerId) and not Team.IsLeader(Role.playerId) then
            ShowCenterMessage(UIDebug.language == "EN" and "Only Party Leader can teleport." or string.Get(20519))
            return
          end
          if not Role.CanControl() then return end
          
          -- Tìm toạ độ và areaId chuẩn từ sceneFightDatas (Dữ liệu bãi train)
          local areaId = 1
          local position = Vector2.New(400, 400)
          if sceneFightDatas ~= nil then
            for k, v in pairs(sceneFightDatas) do
              if v.sceneId == mapId then
                areaId = v.areaId
                position = Vector2.New(v.x, v.y)
                break
              end
            end
          end

          -- Sử dụng StartNavigation để bắt đầu tự chạy bộ xuyên map
          MarkManager.StartNavigation(0, mapId, areaId, position, 0)
          ShowCenterMessage(UIDebug.language == "EN" and ("Auto-navigating to Map: " .. mapId) or ("Đang tự tìm đường đi đến Map: " .. mapId))
        end
      end)
    end
  })
  table.insert(cols[4], {
    name = VtcMod._decomposeActive 
      and (UIDebug.language == "EN" and "📦 Decomposing... ⏳ (Click to Cancel)" or "📦 Đang phân giải... ⏳ (Bấm để hủy)")
      or (UIDebug.language == "EN" and "📦 Auto Decompose Bags" or "📦 Phân Giải Túi Đồ"),
    isActive = function() return VtcMod._decomposeActive end,
    callback = function()
      if VtcMod._decomposeActive then
        VtcMod._decomposeActive = false
        VtcMod._decomposeStep = 0
        VtcMod._decomposeBatchBags = {}
        VtcMod._decomposeNewItems = {}
        VtcMod._decomposeSnapshot = {}
        ShowCenterMessage(UIDebug.language == "EN" and "Auto-Decompose CANCELLED!" or "Đã HỦY phân giải!")
      else
        VtcMod.StartAutoDecompose()
      end
      -- Removed redundant UpdateFeaturesList/Reset calls (handled by OnClick_Function)
    end
  })



  -- COL 5: 👁️ HIỂN THỊ (Col6_HienThi)
  table.insert(cols[5], { name = UIDebug.language == "EN" and "<b><color=#FFD700>👁️ DISPLAY</color></b>" or "<b><color=#FFD700>👁️ HIỂN THỊ</color></b>", callback = nil })
  table.insert(cols[5], {
    name = string.format(UIDebug.language == "EN" and "🧱 Wallhack: %s" or "🧱 Xuyên Tường: %s", VtcMod.wallHack and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.wallHack end,
    callback = function()
      VtcMod.wallHack = not VtcMod.wallHack
      ShowCenterMessage(VtcMod.wallHack and (UIDebug.language == "EN" and "Wallhack ON!" or "Đã BẬT Noclip đi xuyên tường!") or (UIDebug.language == "EN" and "Wallhack OFF!" or "Đã TẮT Noclip xuyên tường!"))
    end
  })
  table.insert(cols[5], {
    name = string.format(UIDebug.language == "EN" and "👻 Hidden NPCs: %s" or "👻 NPC Ẩn: %s", VtcMod.showHiddenNpc and (UIDebug.language == "EN" and "🟢 ON" or "🟢 BẬT") or (UIDebug.language == "EN" and "🔴 OFF" or "🔴 TẮT")),
    isActive = function() return VtcMod.showHiddenNpc end,
    callback = function()
      VtcMod.showHiddenNpc = not VtcMod.showHiddenNpc
      ShowCenterMessage(VtcMod.showHiddenNpc and (UIDebug.language == "EN" and "Hidden NPCs ON!" or "Đã BẬT hiển thị NPC Ẩn!") or (UIDebug.language == "EN" and "Hidden NPCs OFF!" or "Đã TẮT hiển thị NPC Ẩn!"))
      if Role and Role.mapNpcs then
        for _, npc in pairs(Role.mapNpcs) do
          if npc.UpdateViewVisible then npc:UpdateViewVisible() end
        end
      end
    end
  })
  table.insert(cols[5], {
    name = UIDebug.language == "EN" and "🗺️ Toggle Minimap" or "🗺️ Bật/Tắt Minimap",
    isActive = function() return UI.showMiniMap end,
    callback = function()
      pcall(function()
        if UIMiniMap and UIMiniMap.UpdateMiniMap then
          UIMiniMap.UpdateMiniMap(not UI.showMiniMap)
        end
      end)
    end
  })
--[[
  table.insert(cols[5], {
    name = "🔍 Dump Trạng Thái Trận",
    callback = function()
      pcall(function()
        if not FightField or not FightField.isInBattle then
          ShowCenterMessage("Ban phai o trong tran dau de dump!")
          return
        end
        dofile("/data/local/tmp/vtc_debug/debug_status_dump.lua")
      end)
    end
  })
]]--

  -- Calculate max rows dynamically
  local maxRows = 0
  for col = 1, 5 do
    if #cols[col] > maxRows then
      maxRows = #cols[col]
    end
  end

  -- Combine into 1D array row by row (dynamic maxRows, 5 columns)
  for row = 1, maxRows do
    for col = 1, 5 do
      if cols[col][row] then
        table.insert(modFeatures, cols[col][row])
      else
        table.insert(modFeatures, { name = "", callback = nil, isEmpty = true })
      end
    end
  end
end

function UIDebug.OnInitialize_ScrollContent_Function(scrollItems)
  for i = 0, scrollItems.Length - 1 do
    scrollItems_Function[i] = {};
    scrollItems_Function[i].text_Name = scrollItems[i]:Find("Text_Name"):GetComponent("Text");
    scrollItems_Function[i].event_BG = scrollItems[i]:Find("Image_BG"):GetComponent("UIEvent");
    scrollItems_Function[i].event_BG:SetListener(EventTriggerType.PointerClick, function(sender)
      if this.OnClick_Function then
        this.OnClick_Function(sender)
      end
    end);
  end
end

function UIDebug.OnItemChange_ScrollContent_Function(dataIndex, itemIndex)
  if modFeatures[dataIndex + 1] == nil then return false end
  
  local item = modFeatures[dataIndex + 1]
  local isHeader = (item.callback == nil)
  local isEmpty = (item.isEmpty == true)
  
  -- Determine active state
  local active = false
  if not isHeader and not isEmpty and item.isActive then
    local ok, res = pcall(item.isActive)
    if ok and res then
      active = true
    end
  end
  
  -- Rich text formatting for active state (Bold) for maximum visibility
  local displayName = item.name
  if active then
    displayName = "<b>" .. displayName .. "</b>"
  end
  scrollItems_Function[itemIndex].text_Name.text = displayName;
  scrollItems_Function[itemIndex].event_BG.parameter = dataIndex + 1;
  
  local bgImage = scrollItems_Function[itemIndex].event_BG:GetComponent("Image")
  if bgImage then
    bgImage.enabled = not isHeader and not isEmpty
    bgImage.raycastTarget = not isHeader and not isEmpty
  end
  
  pcall(function()
    local textComp = scrollItems_Function[itemIndex].text_Name
    textComp.raycastTarget = not isHeader and not isEmpty
    textComp.enabled = not isEmpty
    
    -- Increase font sizes and configure overflow for superior readability
    textComp.horizontalOverflow = 1 -- Overflow
    textComp.verticalOverflow = 1 -- Overflow
    
    if isHeader then
      textComp.fontSize = 17
      LuaHelper.SetColor(textComp, Color.Yellow)
    elseif isEmpty then
      textComp.fontSize = 15
    else
      if active then
        textComp.fontSize = 16
        LuaHelper.SetColor(textComp, Color.White) -- High contrast white text on green
        if bgImage then
          -- Bright premium emerald green for active buttons
          LuaHelper.SetColor(bgImage, LuaHelper.GetColor(39, 174, 96, 255))
        end
      else
        textComp.fontSize = 15
        -- Light silver text for inactive buttons
        LuaHelper.SetColor(textComp, LuaHelper.GetColor(210, 210, 210, 255))
        if bgImage then
          LuaHelper.SetColor(bgImage, Color.White) -- default white tint (original texture)
        end
      end
    end
  end)
  
  pcall(function()
    scrollItems_Function[itemIndex].event_BG.enabled = not isHeader and not isEmpty
  end)
  
  return true;
end

function UIDebug.OnClick_Function(sender)
  local index = sender.parameter
  if modFeatures[index] and modFeatures[index].callback then
    modFeatures[index].callback()
    this.UpdateFeaturesList()
    this.UpdateStatusText()
    pcall(function()
      scrollContent_Function:Reset(#modFeatures)
      -- this.ForceVerticalLayout()
    end)
  end
end

-- Fallback/No-op method to prevent FightField.lua calls from crashing the game client
function UIDebug.UpdateUI()
  pcall(function()
    this.UpdateFeaturesList()
    this.UpdateStatusText()
    if scrollContent_Function then
      scrollContent_Function:Reset(#modFeatures)
      -- this.ForceVerticalLayout()
    end
  end)
end
