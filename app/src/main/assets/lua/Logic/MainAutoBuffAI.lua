-- =========================================================================
-- MainAutoBuffAI.lua  v5.8
-- Architecture: Multi-Agent Pipeline (State -> Priority -> Skill -> Target -> Execute)
-- Element: Agnostic (Hỗ trợ tất cả 5 Hệ: Thủy, Địa, Hỏa, Phong, Tâm)
-- Status: Đọc từ fightHum.status_Kind[] (KHÔNG dùng roleController attributes)
-- =========================================================================

local MainAutoBuffAI = {}

-- -------------------------------------------------------------------------
-- CONSTANTS & HELPERS FOR BATTLE STATUS EFFECTS
-- -------------------------------------------------------------------------
local STATUS_KIND = {
    Seal = 1,
    Vary = 2,
    Faint = 3,
    Spec = 4,
    Strong = 5
}

-- Helper to safely read fight status kinds from fightHum object in battle
local function getFightStatusKind(ally, statusKindId)
    if not ally then return 0 end
    if ally.status_Kind then
        return ally.status_Kind[statusKindId] or 0
    elseif ally.GetStatusKind then
        local ok, val = pcall(ally.GetStatusKind, ally, statusKindId)
        if ok then return val or 0 end
    end
    return 0
end

-- -------------------------------------------------------------------------
-- CẤU HÌNH (CONFIG)
-- -------------------------------------------------------------------------
MainAutoBuffAI.Config = {
    HP_CRITICAL_THRESHOLD = 0.40,
    SAFE_THRESHOLD = 0.75,
    SP_HEAL_THRESHOLD = 0.75,
    REVIVE_SORT = "hpMax_desc",
    SHIELD_SORT_ORDER = {"MAIN", "VT"},
    ALLOW_LOCKING_SHIELD = false, -- Tắt Kim Chung Tráo mặc định
    DISPEL_SPECIAL_CASE = { BangPhong = 11015 }
}

-- -------------------------------------------------------------------------
-- GLOBAL STATE TRACKERS (Dùng chung cho chống Conflict)
-- -------------------------------------------------------------------------
VtcMod = VtcMod or {}
VtcMod.ActionQueueTargets = VtcMod.ActionQueueTargets or {}
VtcMod.CurrentBattleId = VtcMod.CurrentBattleId or -1
VtcMod.TurnCount = VtcMod.TurnCount or 0
VtcMod.LastTurnTick = VtcMod.LastTurnTick or 0

-- -------------------------------------------------------------------------
-- DANH MỤC SKILL (Đã sắp xếp PowerRank giảm dần)
-- v5.7: Mở rộng cross-element — AI quét toàn bộ skill đã học bất kể Hệ
-- -------------------------------------------------------------------------
local SKILLS = {
    -- HP Heal: AoE trước, Single sau. CS ưu tiên hơn Base.
    HP_AOE      = { 11030, 11026, 11010 },
    HP_SINGLE   = { 11007, 11004, 10002, 10005, 14002, 14005, 14008, 14009, 14010, 14011 },
    HP_SP_COMBO = { 11030, 12022, 14022 },  -- Skill hồi CẢ HP lẫn SP

    -- SP Heal
    SP_AOE      = { 11030, 11029, 11009 },
    SP_SINGLE   = { 11006, 10009, 14013, 14014 },

    -- Revive
    REVIVE = { 11013 },

    -- Dispel: Chung + Chuyên biệt từng loại debuff
    DISPEL_NORMAL    = { 11031, 11025, 11024, 11012, 10012 },  -- Thêm 10012 (Địa)
    DISPEL_BANGPHONG = { 11015 },                               -- Dung Băng (Giải Băng Phong)
    DISPEL_SLEEP     = { 14007 },                               -- Giải Hôn Thụy (Tâm)
    DISPEL_POISON    = { 14014 },                               -- Giải Độc (Tâm)
    DISPEL_CHAOS     = { 14022 },                               -- Giải Hỗn Loạn (Tâm)

    -- Shield
    SHIELD = { 10010, 11002, 10015, 10026, 10031 } -- 10031 cuối cùng
}

local CS_SKILLS_IDS = { [11026]=true, [11029]=true, [11030]=true, [11024]=true, [11025]=true, [11031]=true }
local AOE_SKILLS = { [11030]=true, [11026]=true, [11010]=true, [11029]=true, [11009]=true, [11031]=true, [12022]=true }

-- -------------------------------------------------------------------------
-- BẢNG PHÂN LOẠI TRẠNG THÁI (STATUS CLASSIFICATION)
-- Engine TS Online lưu trạng thái qua 5 Attribute slots:
--   EAttribute.Seal  (221) → Giá trị 1~50   → LUÔN LÀ DEBUFF
--   EAttribute.Strong (225) → Giá trị 51~100 → LUÔN LÀ BUFF
--   EAttribute.Vary  (222) → Giá trị 101~170 → CÓ THỂ BUFF HOẶC DEBUFF
--   EAttribute.Faint (223) → Giá trị 171~240 → LUÔN LÀ DEBUFF
--   EAttribute.Spec  (224) → Giá trị 241~255 → LUÔN LÀ BUFF
-- Mỗi slot chỉ chứa ĐÚNG 1 status ID. Giá trị 0 = Trống.
-- -------------------------------------------------------------------------

-- Tất cả EStatus ID trong Vary slot (101-170) mà là BUFF CÓ LỢI
-- Nếu đồng đội đang mang 1 trong các status này → KHÔNG giải trừ, KHÔNG buff đè
local BENEFICIAL_VARY_IDS = {
    [101]=true,  -- Boundary (Kết Giới)
    [102]=true,  -- Avoid (Thiểm Né)
    [103]=true,  -- Mirror (Kính)
    [104]=true,  -- IceWall (Băng Tường)
    [105]=true,  -- Limpid (Ẩn Thân)
    [106]=true,  -- Vitality (Nguyên Khí)
    [107]=true,  -- Enlarge (Phóng To)
    [108]=true,  -- SameHeart (Đồng Tâm)
    [109]=true,  -- Inspire (Cổ Vũ)
    [110]=true,  -- SoulMirror (Linh Kính)
    [111]=true,  -- FireAmulet (Đan Dương Hộ Thể)
    [112]=true,  -- TransferAttack (Đẩu Chuyển Tinh Di)
    [113]=true,  -- Invisible (Vô Hình Vô Tướng)
    [114]=true,  -- WarStep (Ngưng Khí Hộ Thuẫn)
    [115]=true,  -- GoldShield (Kim Chung Tráo)
    [116]=true,  -- DolphieGraud (Cá Heo Hộ Thể)
    [117]=true,  -- ImmunityShield (Ma Vương Lĩnh Vực)
    [118]=true,  -- DragonTransfer (Ba Long Phong Chướng)
    [119]=true,  -- IceCrystals (Băng Tinh Thủ Hộ)
    [170]=true,  -- God (Phúc Thần Phụ Thân)
}

-- Subset: Các Shield cụ thể mà bot có thể chủ động buff bằng skill
local SHIELD_STATUS_IDS = {
    [101]=true,  -- Boundary (Kết Giới) → Skill 10010
    [103]=true,  -- Mirror (Kính) → Skill 10015
    [104]=true,  -- IceWall (Băng Tường) → Skill 11002
    [110]=true,  -- SoulMirror (Linh Kính) → Skill 10026
    [115]=true,  -- GoldShield (Kim Chung Tráo) → Skill 10031
}

-- Edge Case: EW_Counter (8) nằm trong Seal slot (1~50) nhưng là BUFF có lợi (Kim Chung Phản Chế).
-- Nếu không loại trừ, AI sẽ cố giải trừ nhầm → phá buff đồng đội.
local BENEFICIAL_SEAL_IDS = {
    [8]=true,  -- EW_Counter (Kim Chung Phản Chế - Phản đòn)
}

-- v5.7: Debuff gây sát thương liên tục (Damage over Time).
-- Khi phát hiện DoT, AI ƯU TIÊN giải debuff TRƯỚC khi heal HP (tránh vòng lặp heal vô tận).
local DOT_DEBUFFS = {
    [171]=true,  -- Poison (Trúng Độc)
    [176]=true,  -- Stool1 (Trúng Độc Phân)
    [179]=true,  -- ThunderFire (Phần Thiêu)
    [180]=true,  -- HealthDrawer (Thức Quỷ Hấp Hồn)
    [183]=true,  -- SoulCurse (Thực Hồn Trớ Chú)
}

-- =========================================================================
-- AGENT 1: STATE SCANNER
-- =========================================================================
function MainAutoBuffAI.StateScanner(caster, allies, fightId)
    local team = {}
    local aliveTeam = {}
    local totalCurrentHp, totalMaxHp = 0, 0
    local totalCurrentSp, totalMaxSp = 0, 0
    local myParty = caster.party_Kind or 1

    for i, ally in pairs(allies) do
        if ally and ally.party_Kind == myParty then
            local isMain = (ally.kind == 1 or ally.kind == 2 or ally.isMain == true)

            local activeDebuffs = {}
            local hasShield = false
            local hasBeneficialBuff = false
            local isBangPhong = false
            local hasTrance = false
            local hasPoison = false
            local hasChaos = false
            local hasDot = false

            -- ★ ĐỌC HP/SP TỪ ENGINE ATTRIBUTES ★
            local hpCur, hpM, spCur, spM = 0, 1, 0, 1
            if ally.roleController then
                hpCur = ally.roleController:GetAttribute(EAttribute.Hp) or 0
                hpM = ally.roleController:GetAttribute(EAttribute.MaxHp) or 1
                spCur = ally.roleController:GetAttribute(EAttribute.Sp) or 0
                spM = ally.roleController:GetAttribute(EAttribute.MaxSp) or 1
            end

            -- ★ ĐỌC BUFF/DEBUFF TỪ status_Kind (Lua-side battle table) ★
            -- Engine KHÔNG sync status vào roleController.attributes trong trận.
            -- Phải đọc trực tiếp từ fightHum[i].status_Kind[EFightStatusKind].
            local sealVal = getFightStatusKind(ally, STATUS_KIND.Seal)
            if sealVal > 0 then
                if BENEFICIAL_SEAL_IDS[sealVal] then
                    hasBeneficialBuff = true
                else
                    table.insert(activeDebuffs, sealVal)
                    if sealVal == 1 or (EStatus and sealVal == EStatus.IceBound) then
                        isBangPhong = true
                    end
                    if sealVal == 6 then
                        hasTrance = true
                    end
                end
            end

            local faintVal = getFightStatusKind(ally, STATUS_KIND.Faint)
            if faintVal > 0 then
                table.insert(activeDebuffs, faintVal)
                if faintVal == 171 then hasPoison = true end
                if faintVal == 173 then hasChaos = true end
                if DOT_DEBUFFS[faintVal] then hasDot = true end
            end

            local varyVal = getFightStatusKind(ally, STATUS_KIND.Vary)
            if varyVal > 0 then
                if BENEFICIAL_VARY_IDS[varyVal] then
                    hasBeneficialBuff = true
                    if SHIELD_STATUS_IDS[varyVal] then
                        hasShield = true
                    end
                else
                    table.insert(activeDebuffs, varyVal)
                end
            end

            local strongVal = getFightStatusKind(ally, STATUS_KIND.Strong)
            local specVal = getFightStatusKind(ally, STATUS_KIND.Spec)

            if VtcMod and VtcMod.debugAI then
                logError("[VTCMOD] DUMP_ATTR ID" .. tostring(i) .. ": Seal="..sealVal.." Vary="..varyVal.." Faint="..faintVal.." Strong="..strongVal.." Spec="..specVal)
            end

            local unit = {
                unitId = i,
                rawObject = ally,
                type = isMain and "MAIN" or "VT",
                isAlive = hpCur > 0,
                hpCurrent = hpCur,
                hpMax = hpM,
                spCurrent = spCur,
                spMax = spM,
                hasReincarnated = (ally.turn and ally.turn > 0) or false,
                activeDebuffs = activeDebuffs,
                isBangPhong = isBangPhong,
                hasTrance = hasTrance,
                hasPoison = hasPoison,
                hasChaos = hasChaos,
                hasDot = hasDot,
                hasShield = hasShield,
                hasBeneficialBuff = hasBeneficialBuff
            }
            table.insert(team, unit)
            if unit.isAlive then
                table.insert(aliveTeam, unit)
                totalCurrentHp = totalCurrentHp + unit.hpCurrent
                totalMaxHp = totalMaxHp + unit.hpMax
                totalCurrentSp = totalCurrentSp + unit.spCurrent
                totalMaxSp = totalMaxSp + unit.spMax
            end
        end
    end

    local teamHpPercent = totalMaxHp > 0 and (totalCurrentHp / totalMaxHp) or 1.0
    local teamSpPercent = totalMaxSp > 0 and (totalCurrentSp / totalMaxSp) or 1.0

    local spCurrent = 0
    if caster.roleController then
        spCurrent = caster.roleController:GetAttribute(EAttribute.Sp) or 0
    end

    local isReincarnated = false
    if caster.roleController then
        local turn = caster.roleController:GetAttribute(EAttribute.Turn) or 0
        if turn > 0 then isReincarnated = true end
    end

    local function getOriRole(nowRole)
        if Contains(nowRole.kind, EHuman.Player, EHuman.Players, EHuman.Divide) then
            return Role.player
        elseif nowRole.kind == EHuman.FollowNpc then
            return Role.GetFollowNpc(Role.playerId, nowRole.npcId)
        end
        return nil
    end

    local oriRole = getOriRole(caster)
    
    local element = 6
    if caster.roleController then
        element = caster.roleController:GetAttribute(EAttribute.Element) or 6
    end

    local skillsAvailable = {}

    -- Quét skill thực tế từ source code
    -- v5.7 perf: Cache GetElementSkill(0) MỘT LẦN, dùng chung cho tất cả category
    local cachedSkills = nil
    if oriRole and oriRole.GetElementSkill then
        local ok, skills = pcall(oriRole.GetElementSkill, oriRole, 0)
        if ok and skills then cachedSkills = skills end
    end

    local function CheckSkillAndAdd(skillList, categoryName)
        if not cachedSkills then return end

        for _, skillId in ipairs(skillList) do
            if skillId == 10031 and not MainAutoBuffAI.Config.ALLOW_LOCKING_SHIELD then
                -- Bỏ qua Kim Chung Tráo nếu config tắt
            else
                local learned = false
                for _, s in pairs(cachedSkills) do
                    if s and s.Id == skillId and s.Lv and s.Lv > 0 then
                        learned = true
                        break
                    end
                end

                if learned then
                    table.insert(skillsAvailable, {
                        skillId = skillId,
                        category = categoryName,
                        isCS = (CS_SKILLS_IDS[skillId] == true)
                    })
                end
            end
        end
    end

    -- Quét toàn bộ các kỹ năng hỗ trợ có thể có, bất kể Hệ nào (vì game cho phép học chéo Hệ)
    CheckSkillAndAdd(SKILLS.HP_AOE, "HP_AOE")
    CheckSkillAndAdd(SKILLS.HP_SINGLE, "HP_SINGLE")
    CheckSkillAndAdd(SKILLS.HP_SP_COMBO, "HP_SP_COMBO")
    CheckSkillAndAdd(SKILLS.SP_AOE, "SP_AOE")
    CheckSkillAndAdd(SKILLS.SP_SINGLE, "SP_SINGLE")
    CheckSkillAndAdd(SKILLS.REVIVE, "REVIVE")
    CheckSkillAndAdd(SKILLS.DISPEL_NORMAL, "DISPEL_NORMAL")
    CheckSkillAndAdd(SKILLS.DISPEL_BANGPHONG, "DISPEL_BANGPHONG")
    CheckSkillAndAdd(SKILLS.DISPEL_SLEEP, "DISPEL_SLEEP")
    CheckSkillAndAdd(SKILLS.DISPEL_POISON, "DISPEL_POISON")
    CheckSkillAndAdd(SKILLS.DISPEL_CHAOS, "DISPEL_CHAOS")
    CheckSkillAndAdd(SKILLS.SHIELD, "SHIELD")

    local casterState = {
        unitId = caster.id or caster.index,
        element = element,
        spCurrent = spCurrent,
        hasReincarnated = isReincarnated,
        skillsAvailable = skillsAvailable
    }

    -- DEBUG: IN RA LOG NHỮNG SKILL MÀ AI NHÌN THẤY
    if VtcMod and VtcMod.debugAI then
        local skillLogStr = ""
        for _, s in ipairs(skillsAvailable) do
            skillLogStr = skillLogStr .. tostring(s.skillId) .. ","
        end
        logError("[VTCMOD] NEW_AI_DEBUG: Caster=" .. tostring(caster.kind) .. " Element=" .. tostring(element) .. " SP=" .. tostring(spCurrent) .. " CS=" .. tostring(isReincarnated) .. " Skills=[" .. skillLogStr .. "]")

        local teamLog = ""
        for _, u in ipairs(aliveTeam) do
            teamLog = teamLog .. "ID" .. u.unitId .. ":H" .. u.hpCurrent .. "/" .. u.hpMax .. "-S" .. u.spCurrent .. "/" .. u.spMax .. "(SH=" .. tostring(u.hasShield) .. ",DB=" .. tostring(#u.activeDebuffs) .. ",BF=" .. tostring(u.hasBeneficialBuff) .. ") | "
        end
        logError("[VTCMOD] NEW_AI_TEAM: " .. teamLog)
    end


    local teamState = {
        team = team,
        aliveTeam = aliveTeam,
        teamHpPercent = teamHpPercent,
        teamSpPercent = teamSpPercent
    }

    -- Cập nhật Turn Management
    if fightId ~= VtcMod.CurrentBattleId then
        VtcMod.CurrentBattleId = fightId
        VtcMod.TurnCount = 1
        table.Clear(VtcMod.ActionQueueTargets)
    else
        -- Logic đếm Turn giả lập: Nếu khoảng cách từ lần lấy AI trước > 5s, có thể coi là qua Turn mới.
        -- Hoặc engine phải tự gọi MainAutoBuffAI.ResetTurn() ở mỗi đầu hiệp.
        -- Mặc định ở đây ta giả sử người dùng gọi đúng cách hoặc ta track bằng tick.
    end

    return teamState, casterState
end

-- =========================================================================
-- AGENT 2: PRIORITY EVALUATOR
-- =========================================================================
function MainAutoBuffAI.PriorityEvaluator(teamState, ignoreTiers)
    ignoreTiers = ignoreTiers or {}
    local cfg = MainAutoBuffAI.Config
    
    -- Xử lý Turn 1
    if VtcMod.TurnCount == 1 and not ignoreTiers[6] then
        -- Ưu tiên rải khiên toàn đội
        local needsShield = false
        for _, u in ipairs(teamState.aliveTeam) do
            if not u.hasShield then needsShield = true break end
        end
        if needsShield then return 6 end -- Ép Tier 6
    end

    -- v5.7: DoT-Aware Priority — Nếu đồng đội đang bị debuff gây sát thương liên tục
    -- (Poison, ThunderFire, SoulCurse...), ƯU TIÊN giải debuff TRƯỚC khi heal HP.
    -- Tránh vòng lặp vô tận: HP↓ → Heal → DoT hút HP↓ → Heal → ...
    if not ignoreTiers[5] then
        local hasDotDebuff = false
        for _, u in ipairs(teamState.aliveTeam) do
            if u.hasDot then hasDotDebuff = true break end
        end
        if hasDotDebuff then return 5 end  -- Ưu tiên giải DoT trước khi heal
    end

    -- Cứu nguy cá nhân hoặc toàn đội
    local needsIndividualHp = false
    for _, u in ipairs(teamState.aliveTeam) do
        if u.hpMax > 0 and (u.hpCurrent / u.hpMax) < cfg.SAFE_THRESHOLD then
            needsIndividualHp = true
            break
        end
    end

    if (teamState.teamHpPercent < cfg.HP_CRITICAL_THRESHOLD or needsIndividualHp) and not ignoreTiers[1] then
        return 1 -- Tier 1: HP Team or Individual
    end

    local deadMains, deadVTs = false, false
    for _, u in ipairs(teamState.team) do
        if not u.isAlive then
            if u.type == "MAIN" then deadMains = true
            else deadVTs = true end
        end
    end

    if deadMains and not ignoreTiers[2] then return 2 end -- Tier 2: Revive Main
    if deadVTs and not ignoreTiers[3] then return 3 end -- Tier 3: Revive VT

    local needsIndividualSp = false
    for _, u in ipairs(teamState.aliveTeam) do
        if u.spMax > 0 and (u.spCurrent / u.spMax) < cfg.SP_HEAL_THRESHOLD then
            needsIndividualSp = true
            break
        end
    end

    if (teamState.teamSpPercent < cfg.SP_HEAL_THRESHOLD or needsIndividualSp) and not ignoreTiers[4] then
        return 4 -- Tier 4: SP Team or Individual
    end

    if teamState.teamHpPercent >= cfg.SAFE_THRESHOLD and teamState.teamSpPercent >= cfg.SAFE_THRESHOLD then
        if not ignoreTiers[5] then
            local hasDebuff = false
            for _, u in ipairs(teamState.aliveTeam) do
                if #u.activeDebuffs > 0 then hasDebuff = true break end
            end
            if hasDebuff then return 5 end -- Tier 5: Dispel
        end

        if not ignoreTiers[6] then
            local needsShield = false
            for _, u in ipairs(teamState.aliveTeam) do
                if not u.hasShield then needsShield = true break end
            end
            if needsShield then return 6 end -- Tier 6: Shield
        end
    end

    return 0 -- Defend / Idle
end

-- =========================================================================
-- AGENT 3: SKILL SELECTOR
-- =========================================================================
function MainAutoBuffAI.SkillSelector(activeTier, casterState, targetUnit)
    local avail = casterState.skillsAvailable
    
    local function FindSkill(categories)
        local function IsValidSkill(s)
            local reqSp = 0
            if skillDatas and skillDatas[s.skillId] then
                reqSp = skillDatas[s.skillId].requireSp or 0
            end
            return casterState.spCurrent >= reqSp
        end

        -- Vòng 1: Ưu tiên tuyệt đối các skill Sau Chuyển Sinh (isCS == true) nếu Caster đã chuyển sinh
        if casterState.hasReincarnated then
            for _, cat in ipairs(categories) do
                for _, s in ipairs(avail) do
                    if s.category == cat and s.isCS and IsValidSkill(s) then
                        return s.skillId
                    end
                end
            end
        end

        -- Vòng 2: Fallback (Hoặc Caster chưa CS, hoặc đã CS nhưng không có skill CS/thiếu SP nên không quét thấy)
        for _, cat in ipairs(categories) do
            for _, s in ipairs(avail) do
                if s.category == cat and not s.isCS and IsValidSkill(s) then
                    return s.skillId
                end
            end
        end
        return nil
    end

    if activeTier == 1 then return FindSkill({"HP_AOE", "HP_SP_COMBO", "HP_SINGLE"}) end
    if activeTier == 2 or activeTier == 3 then return FindSkill({"REVIVE"}) end
    if activeTier == 4 then return FindSkill({"SP_AOE", "HP_SP_COMBO", "SP_SINGLE"}) end
    if activeTier == 5 then
        -- v5.7: Chọn skill giải chuyên biệt theo loại debuff cụ thể trước
        if targetUnit then
            -- 1. Băng Phong (IceBound=1) → Dung Băng chuyên dụng
            if targetUnit.isBangPhong then
                local bpSkill = FindSkill({"DISPEL_BANGPHONG"})
                if bpSkill then return bpSkill end
            end
            -- 2. Hôn Thụy (Trance=6) → Giải Hôn Thụy chuyên dụng (hệ Tâm)
            if targetUnit.hasTrance then
                local trSkill = FindSkill({"DISPEL_SLEEP"})
                if trSkill then return trSkill end
            end
            -- 3. Trúng Độc (Poison=171) → Giải Độc chuyên dụng (hệ Tâm)
            if targetUnit.hasPoison then
                local poSkill = FindSkill({"DISPEL_POISON"})
                if poSkill then return poSkill end
            end
            -- 4. Hỗn Loạn (Chaos=173) → Giải Hỗn Loạn chuyên dụng (hệ Tâm)
            if targetUnit.hasChaos then
                local chSkill = FindSkill({"DISPEL_CHAOS"})
                if chSkill then return chSkill end
            end
        end
        -- Fallback: Giải trạng thái chung (quét tất cả category giải debuff)
        return FindSkill({"DISPEL_NORMAL", "DISPEL_BANGPHONG", "DISPEL_SLEEP", "DISPEL_POISON", "DISPEL_CHAOS"})
    end
    if activeTier == 6 then return FindSkill({"SHIELD"}) end

    return nil
end

-- =========================================================================
-- AGENT 4: TARGET RESOLVER
-- =========================================================================
function MainAutoBuffAI.TargetResolver(activeTier, teamState)
    local targetQueue = {}

    local function IsQueued(unitId)
        return VtcMod.ActionQueueTargets[unitId] == true
    end

    if activeTier == 1 then
        for _, u in ipairs(teamState.aliveTeam) do
            if not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) return (a.hpCurrent/a.hpMax) < (b.hpCurrent/b.hpMax) end)

    elseif activeTier == 2 then
        for _, u in ipairs(teamState.team) do
            if not u.isAlive and u.type == "MAIN" and not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) return a.hpMax > b.hpMax end)

    elseif activeTier == 3 then
        for _, u in ipairs(teamState.team) do
            if not u.isAlive and u.type == "VT" and not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) return a.hpMax > b.hpMax end)

    elseif activeTier == 4 then
        for _, u in ipairs(teamState.aliveTeam) do
            if not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) return (a.spCurrent/a.spMax) < (b.spCurrent/b.spMax) end)

    elseif activeTier == 5 then
        for _, u in ipairs(teamState.aliveTeam) do
            if #u.activeDebuffs > 0 and not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) return #a.activeDebuffs > #b.activeDebuffs end)

    elseif activeTier == 6 then
        for _, u in ipairs(teamState.aliveTeam) do
            if not u.hasShield and not IsQueued(u.unitId) then table.insert(targetQueue, u) end
        end
        table.sort(targetQueue, function(a, b) 
            if a.type == "MAIN" and b.type ~= "MAIN" then return true end
            if a.type ~= "MAIN" and b.type == "MAIN" then return false end
            return a.hpMax > b.hpMax 
        end)
    end

    return targetQueue
end

-- =========================================================================
-- AGENT 5: EXECUTION & FALLBACK
-- =========================================================================
function MainAutoBuffAI.ExecutionAndFallback(activeTier, teamState, casterState)
    local targetQueue = MainAutoBuffAI.TargetResolver(activeTier, teamState)
    
    for _, target in ipairs(targetQueue) do
        local skillId = MainAutoBuffAI.SkillSelector(activeTier, casterState, target)
        if skillId then
            -- Fallback mechanic simulated: 
            -- Lock the target(s) to prevent other bots in this client from targeting them this turn.
            if AOE_SKILLS[skillId] then
                -- Nếu là skill AoE, khóa toàn bộ team sống để bot khác không buff đè
                for _, u in ipairs(teamState.aliveTeam) do
                    VtcMod.ActionQueueTargets[u.unitId] = true
                end
            else
                -- Skill đơn thể, chỉ khóa target hiện tại
                VtcMod.ActionQueueTargets[target.unitId] = true
            end

            return {
                actionType = "Skill",
                skillId = skillId,
                targetId = target.unitId,
                targetObj = target.rawObject
            }
        end
    end

    return nil -- Báo hiệu "Tier rỗng" (Hết target hoặc hết skill)
end

-- =========================================================================
-- MAIN ENTRY POINT
-- =========================================================================
function MainAutoBuffAI.GetAction(caster, allies, fightId, extraIgnoreTiers)
    local teamState, casterState = MainAutoBuffAI.StateScanner(caster, allies, fightId)

    local ignoreTiers = {}
    if extraIgnoreTiers then
        for k, v in pairs(extraIgnoreTiers) do
            ignoreTiers[k] = v
        end
    end
    
    local currentTier = MainAutoBuffAI.PriorityEvaluator(teamState, ignoreTiers)

    while currentTier > 0 do
        local action = MainAutoBuffAI.ExecutionAndFallback(currentTier, teamState, casterState)
        if action then
            return action
        end
        
        -- Nếu rỗng (hết mục tiêu hợp lệ hoặc hết skill), bỏ qua Tier hiện tại và quét lại Priority
        ignoreTiers[currentTier] = true
        currentTier = MainAutoBuffAI.PriorityEvaluator(teamState, ignoreTiers)
    end

    return { actionType = "Defend", skillId = 0, targetId = caster.id or caster.index, targetObj = caster }
end

-- =========================================================================
-- PUBLIC UTILS
-- =========================================================================
function MainAutoBuffAI.ResetTurnQueue()
    if VtcMod and VtcMod.ActionQueueTargets then
        table.Clear(VtcMod.ActionQueueTargets)
    end
    if VtcMod then
        VtcMod.TurnCount = (VtcMod.TurnCount or 0) + 1
    end
end

return MainAutoBuffAI
