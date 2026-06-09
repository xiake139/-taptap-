---------------------------------------------------
-- BagUI.lua - 背包系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local BigNum = require("Utils.BigNum")

local BagUI = {}

local GameUI = nil  -- 延迟加载
local EquipUI = nil -- 延迟加载

--- 宝箱名称缓存（从云端加载后缓存，避免每次渲染都异步查询）
local chestNamesCache_ = nil  -- nil=未加载, table=已加载的宝箱名称集合

--- 中文部位→英文key映射
local SLOT_CN_TO_KEY = {
    ["武器"] = "weapon", ["头盔"] = "helmet", ["铠甲"] = "armor", ["护腕"] = "bracer",
    ["腰带"] = "belt", ["战靴"] = "boots", ["披风"] = "cloak", ["项链"] = "necklace",
    ["戒指"] = "ring", ["法宝"] = "artifact", ["坐骑"] = "mount", ["灵翼"] = "wings",
    ["护盾"] = "shield", ["防具"] = "armor", ["饰品"] = "accessory",
}

local parentRef_ = nil

--- 加载宝箱名称缓存
---@param callback fun()|nil 加载完成回调
function BagUI.LoadChestNames(callback)
    local IniParser = require("Utils.IniParser")
    local cloud = DataManager.GetCloudProvider()
    if not cloud then
        chestNamesCache_ = {}
        if callback then callback() end
        return
    end

    local CHESTS_KEY = "系统配置/chests.ini"
    cloud:Get(CHESTS_KEY, {
        ok = function(values)
            local raw = values[CHESTS_KEY]
            chestNamesCache_ = {}
            if raw and raw ~= "" then
                local sections = IniParser.Parse(raw)
                for name, _ in pairs(sections) do
                    chestNamesCache_[name] = true
                end
            end
            print("[BagUI] 宝箱缓存已加载，共 " .. tostring(BagUI.GetChestCount()) .. " 种宝箱")
            if callback then callback() end
        end,
        error = function()
            chestNamesCache_ = {}
            if callback then callback() end
        end,
    })
end

--- 获取宝箱缓存数量
function BagUI.GetChestCount()
    if not chestNamesCache_ then return 0 end
    local n = 0
    for _ in pairs(chestNamesCache_) do n = n + 1 end
    return n
end

--- 判断物品名是否是宝箱（通过缓存匹配）
---@param itemName string
---@return boolean
function BagUI.IsChest(itemName)
    if chestNamesCache_ and chestNamesCache_[itemName] then
        return true
    end
    return false
end

--- 渲染背包面板
---@param parent Widget
function BagUI.Render(parent)
    parentRef_ = parent
    -- 首次打开背包时加载宝箱缓存，加载完后刷新
    if chestNamesCache_ == nil then
        BagUI.LoadChestNames(function()
            BagUI.Refresh()
        end)
        -- 先显示一次（无宝箱按钮），等缓存加载后再刷新
        BagUI.Refresh()
    else
        BagUI.Refresh()
    end
end

--- 刷新背包显示
function BagUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    parentRef_:AddChild(UI.Label {
        text = "— 背包 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    if #player.bag == 0 then
        parentRef_:AddChild(UI.Label {
            text = "背包空空如也...",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return
    end

    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetItem(item.name)
        -- 如果items表找到但无slot，尝试从equipment表补充装备数据
        local equipData = DataManager.GetEquipData(item.name)
        if equipData and equipData.slot then
            itemData = equipData
        end
        local desc = itemData and (itemData.desc or "") or ""
        local sellPrice = itemData and (itemData.price_sell or "0") or "0"

        local itemType = itemData and itemData.type or "材料"
        local isConsumable = itemData and itemType ~= "材料" and not itemData.slot
        local isEquip = itemData and itemData.slot
        -- 宝箱判断：type含"宝箱"，或物品名匹配宝箱配置缓存
        local isChest = (itemType:find("宝箱")) or BagUI.IsChest(item.name)

        local btnChildren = {}

        -- 装备类物品显示详情按钮
        if isEquip then
            table.insert(btnChildren, UI.Button {
                text = "详情",
                variant = "secondary",
                height = 26,
                onClick = function()
                    if not EquipUI then EquipUI = require("UI.EquipUI") end
                    EquipUI.ShowDetail(item.name)
                end,
            })
        end

        if isChest then
            table.insert(btnChildren, UI.Button {
                text = "打开",
                variant = "success",
                height = 26,
                onClick = function() BagUI.OpenChest(i, item.name) end,
            })
        elseif isConsumable then
            table.insert(btnChildren, UI.Button {
                text = "使用",
                variant = "success",
                height = 26,
                onClick = function() BagUI.UseItem(i) end,
            })
        end

        if isEquip then
            table.insert(btnChildren, UI.Button {
                text = "装备",
                variant = "primary",
                height = 26,
                onClick = function() BagUI.EquipItem(i) end,
            })
        end

        if BigNum.gt(sellPrice, "0") then
            table.insert(btnChildren, UI.Button {
                text = "卖" .. BigNum.toShort(sellPrice),
                variant = "danger",
                height = 26,
                onClick = function() BagUI.SellItem(i) end,
            })
        end

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 6,
            gap = 6,
            backgroundColor = { 25, 20, 45, 200 },
            borderRadius = 4,
            marginBottom = 4,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label { text = item.name .. " x" .. item.count, fontSize = 14, fontColor = { 220, 220, 240, 255 } },
                        UI.Label { text = desc, fontSize = 11, fontColor = { 140, 140, 160, 255 }, whiteSpace = "normal" },
                    },
                },
                UI.Panel { flexDirection = "row", gap = 4, children = btnChildren },
            },
        })
    end
end

--- 添加 buff 到玩家
---@param player table
---@param buffType string "攻击"|"防御"|"生命上限"|"经验倍率"|"货币倍率"
---@param value number
---@param durationMin number 持续分钟数
local function AddBuff(player, buffType, value, durationMin)
    if not player.buffs then player.buffs = {} end

    local now = os.time()
    local durationSec = durationMin * 60

    -- 经验倍率/货币倍率：相同倍率叠加时间，不同倍率各自独立
    if buffType == "经验倍率" or buffType == "货币倍率" then
        -- 查找相同类型且相同数值的已有 buff
        for _, b in ipairs(player.buffs) do
            if b.type == buffType and tonumber(b.value) == value then
                -- 相同倍率：叠加时间
                b.expires = math.max(b.expires, now) + durationSec
                print("[Buff] " .. buffType .. " x" .. value .. " 叠加时间至 " .. os.date("%H:%M:%S", b.expires))
                return
            end
        end
        -- 不同倍率：新增独立buff
        table.insert(player.buffs, {
            type = buffType,
            value = value,
            expires = now + durationSec,
        })
        print("[Buff] " .. buffType .. " x" .. value .. " 新增，到期 " .. os.date("%H:%M:%S", now + durationSec))
    else
        -- 攻击/防御/生命上限：直接新增独立buff
        table.insert(player.buffs, {
            type = buffType,
            value = value,
            expires = now + durationSec,
        })
        print("[Buff] " .. buffType .. " +" .. value .. " 新增，到期 " .. os.date("%H:%M:%S", now + durationSec))
    end
end

--- 获取当前有效的 buff 加成
---@param player table
---@param buffType string
---@return number|string 倍率类返回总乘数(number)，属性类返回总加值(string)
function BagUI.GetBuffValue(player, buffType)
    if not player.buffs then return (buffType == "经验倍率" or buffType == "货币倍率") and 1 or 0 end

    local now = os.time()
    if buffType == "经验倍率" or buffType == "货币倍率" then
        -- 倍率类：所有有效buff的value相乘
        local total = 1
        for _, b in ipairs(player.buffs) do
            if b.type == buffType and b.expires > now then
                total = total * tonumber(b.value)
            end
        end
        return total
    else
        -- 属性类：所有有效buff的value相加（大数）
        local total = "0"
        for _, b in ipairs(player.buffs) do
            if b.type == buffType and b.expires > now then
                total = BigNum.add(total, tostring(b.value))
            end
        end
        return total
    end
end

--- 清理过期 buff（应在 Update 中定期调用）
function BagUI.CleanExpiredBuffs()
    local player = DataManager.playerData
    if not player or not player.buffs then return end

    local now = os.time()
    local changed = false
    local GameUI = require("UI.GameUI")

    for i = #player.buffs, 1, -1 do
        local b = player.buffs[i]
        if b.expires <= now then
            local msg = ""
            if b.type == "经验倍率" or b.type == "货币倍率" then
                msg = b.type .. " x" .. b.value .. " 已到期"
            else
                msg = b.type .. " +" .. b.value .. " 已到期"
            end
            if GameUI.AddLog then GameUI.AddLog(msg) end
            print("[Buff] " .. msg)
            table.remove(player.buffs, i)
            changed = true
        end
    end

    if changed then
        DataManager.SaveToCloud(player)
    end
end

function BagUI.UseItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    if not itemData then return end

    local itemType = itemData.type or "材料"

    -- 宝箱类：异步加载配置后开箱
    if itemType:find("宝箱") or BagUI.IsChest(item.name) then
        BagUI.OpenChest(index, item.name)
        return
    end

    local val = itemData.value or "0"  -- 保留字符串，大数安全
    local valNum = tonumber(val) or 0  -- 用于倍率等小数场景
    local duration = tonumber(itemData.duration) or 0  -- 分钟，0=永久
    local effectMsg = ""

    -- 恢复类：立即生效，无时间限制
    if itemType:find("恢复血量") then
        local maxHp = BigNum.new(player.status.max_hp or "100")
        player.status.hp = BigNum.min(BigNum.add(player.status.hp or "0", val), maxHp)
        effectMsg = "恢复 " .. BigNum.toShort(val) .. " 生命"
    end
    if itemType:find("恢复灵力") then
        local maxMp = BigNum.new(player.status.max_mp or "50")
        player.status.mp = BigNum.min(BigNum.add(player.status.mp or "0", val), maxMp)
        effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "恢复 " .. BigNum.toShort(val) .. " 灵力"
    end

    -- 攻击/防御/生命上限：有 duration 则限时buff，否则永久
    if itemType:find("攻击") then
        if duration > 0 then
            AddBuff(player, "攻击", val, duration)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "攻击+" .. BigNum.toShort(val) .. "(" .. duration .. "分钟)"
        else
            player.status.atk = BigNum.add(player.status.atk or "0", val)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "攻击永久+" .. BigNum.toShort(val)
        end
    end
    if itemType:find("防御") then
        if duration > 0 then
            AddBuff(player, "防御", val, duration)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "防御+" .. BigNum.toShort(val) .. "(" .. duration .. "分钟)"
        else
            player.status.def = BigNum.add(player.status.def or "0", val)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "防御永久+" .. BigNum.toShort(val)
        end
    end
    if itemType:find("生命上限") then
        if duration > 0 then
            AddBuff(player, "生命上限", val, duration)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "生命上限+" .. BigNum.toShort(val) .. "(" .. duration .. "分钟)"
        else
            player.status.max_hp = BigNum.add(player.status.max_hp or "100", val)
            player.status.hp = BigNum.add(player.status.hp or "0", val)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "生命上限永久+" .. BigNum.toShort(val)
        end
    end

    -- 经验倍率/货币倍率：必须有 duration（倍率用数字）
    if itemType:find("经验倍率") then
        if duration > 0 then
            AddBuff(player, "经验倍率", valNum, duration)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "经验x" .. valNum .. "(" .. duration .. "分钟)"
        else
            -- 无持续时间默认给 30 分钟
            AddBuff(player, "经验倍率", valNum, 30)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "经验x" .. valNum .. "(30分钟)"
        end
    end
    if itemType:find("货币倍率") then
        if duration > 0 then
            AddBuff(player, "货币倍率", valNum, duration)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "金币x" .. valNum .. "(" .. duration .. "分钟)"
        else
            AddBuff(player, "货币倍率", valNum, 30)
            effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "金币x" .. valNum .. "(30分钟)"
        end
    end

    -- 境界经验类：增加修炼经验
    if itemType:find("境界经验") then
        player.status.realm_exp = BigNum.add(player.status.realm_exp or "0", val)
        effectMsg = effectMsg .. (effectMsg ~= "" and "，" or "") .. "获得修炼经验 +" .. BigNum.toShort(val)
    end

    if effectMsg == "" then
        effectMsg = "使用成功"
    end
    print("[BagUI] 使用 " .. item.name .. "：" .. effectMsg)

    -- 减少数量
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, index)
    end

    DataManager.SaveToCloud(player)
    BagUI.Refresh()

    -- 通知 GameUI 日志
    local GameUI = require("UI.GameUI")
    if GameUI.AddLog then
        GameUI.AddLog("使用 " .. item.name .. "：" .. effectMsg)
    end
end

--- 显示操作提示
---@param msg string
function BagUI.ShowTip(msg)
    print("[BagUI] " .. msg)
    if not parentRef_ then return end
    local tip = parentRef_:FindById("bagTip")
    if tip then
        tip:SetText("> " .. msg)
    else
        parentRef_:AddChild(UI.Label {
            id = "bagTip",
            text = "> " .. msg,
            fontSize = 12,
            fontColor = { 255, 200, 100, 255 },
            textAlign = "center",
            marginBottom = 4,
        })
    end
end

--- 装备物品
---@param index number
function BagUI.EquipItem(index)
    local player = DataManager.playerData
    if not player then BagUI.ShowTip("数据异常"); return end

    local item = player.bag[index]
    if not item then BagUI.ShowTip("物品不存在"); return end

    local itemData = DataManager.GetEquipData(item.name)
    if not itemData then BagUI.ShowTip("找不到装备数据: " .. tostring(item.name)); return end
    if not itemData.slot then BagUI.ShowTip("该物品无法装备"); return end

    -- 检查等级需求
    local levelReq = itemData.level_req or "0"
    local playerLevel = player.status.level or "1"
    if BigNum.lt(playerLevel, levelReq) then
        BagUI.ShowTip("等级不足! 需要等级" .. levelReq .. ", 当前" .. playerLevel)
        return
    end

    -- 将中文部位名转换为英文key
    local slot = SLOT_CN_TO_KEY[itemData.slot] or itemData.slot

    -- 卸下旧装备
    local oldEquip = player.equip[slot]
    if oldEquip and oldEquip ~= "" then
        -- 放回背包
        local found = false
        for _, bagItem in ipairs(player.bag) do
            if bagItem.name == oldEquip then
                bagItem.count = BigNum.add(bagItem.count or "0", "1")
                found = true
                break
            end
        end
        if not found then
            table.insert(player.bag, { name = oldEquip, count = "1" })
        end
    end

    -- 装备新物品
    local equipedName = item.name
    player.equip[slot] = equipedName
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, index)
    end

    print("[BagUI] 装备了 " .. equipedName)
    DataManager.SaveToCloud(player)
    BagUI.Refresh()
    BagUI.ShowTip("已装备: " .. equipedName)
end

--- 出售物品
---@param index number
function BagUI.SellItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    local sellPrice = itemData and (itemData.price_sell or "0") or "0"

    if not BigNum.gt(sellPrice, "0") then return end

    player.status.gold = BigNum.add(player.status.gold or "0", sellPrice)
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, index)
    end

    print("[BagUI] 卖出 " .. item.name .. "，获得 " .. sellPrice .. " 金币")
    DataManager.SaveToCloud(player)
    BagUI.Refresh()
end

--- 开启宝箱（异步加载宝箱配置后处理）
---@param index number 背包中物品索引
---@param chestName string 宝箱物品名称
function BagUI.OpenChest(index, chestName)
    local player = DataManager.playerData
    if not player then return end

    BagUI.ShowTip("正在开启宝箱...")

    local IniParser = require("Utils.IniParser")
    local cloud = DataManager.GetCloudProvider()
    if not cloud then
        BagUI.ShowTip("云存储不可用，无法开启宝箱")
        return
    end

    local CHESTS_KEY = "系统配置/chests.ini"
    cloud:Get(CHESTS_KEY, {
        ok = function(values)
            local raw = values[CHESTS_KEY]
            if not raw or raw == "" then
                BagUI.ShowTip("未找到宝箱配置")
                return
            end

            local sections = IniParser.Parse(raw)
            -- 查找匹配的宝箱配置
            local chestConfig = nil
            for name, data in pairs(sections) do
                if name == chestName then
                    chestConfig = data
                    break
                end
            end

            if not chestConfig then
                BagUI.ShowTip("未配置此宝箱: " .. chestName)
                return
            end

            local chestType = chestConfig["类型"] or "固定"
            local itemsStr = chestConfig["物品"] or ""

            if itemsStr == "" then
                BagUI.ShowTip("宝箱为空")
                return
            end

            -- 解析物品列表：物品:数量,物品2:数量,...
            local itemList = {}
            for entry in itemsStr:gmatch("[^,]+") do
                entry = entry:match("^%s*(.-)%s*$") -- trim
                local name, count = entry:match("^(.+):(%d+)$")
                if name and count then
                    table.insert(itemList, { name = name, count = count })
                end
            end

            if #itemList == 0 then
                BagUI.ShowTip("宝箱配置格式错误")
                return
            end

            -- 确认背包中物品仍然存在
            local item = player.bag[index]
            if not item or item.name ~= chestName then
                BagUI.ShowTip("物品已变化，请重新操作")
                BagUI.Refresh()
                return
            end

            -- 扣除宝箱物品
            item.count = BigNum.sub(item.count or "1", "1")
            if BigNum.lte(item.count, "0") then
                table.remove(player.bag, index)
            end

            -- 发放奖励
            local rewards = {}
            if chestType == "随机" then
                -- 随机选择一个物品
                local pick = itemList[math.random(1, #itemList)]
                table.insert(rewards, pick)
            else
                -- 固定：发放全部物品
                for _, v in ipairs(itemList) do
                    table.insert(rewards, v)
                end
            end

            -- 将奖励添加到背包
            for _, reward in ipairs(rewards) do
                local found = false
                for _, bagItem in ipairs(player.bag) do
                    if bagItem.name == reward.name then
                        bagItem.count = BigNum.add(bagItem.count or "0", reward.count)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(player.bag, { name = reward.name, count = reward.count })
                end
            end

            -- 构造奖励展示信息
            local rewardMsg = ""
            for _, r in ipairs(rewards) do
                if rewardMsg ~= "" then rewardMsg = rewardMsg .. "，" end
                rewardMsg = rewardMsg .. r.name .. " x" .. r.count
            end

            print("[BagUI] 开启宝箱 " .. chestName .. "(" .. chestType .. ")，获得: " .. rewardMsg)
            DataManager.SaveToCloud(player)
            BagUI.Refresh()
            BagUI.ShowTip("开启 " .. chestName .. " 获得: " .. rewardMsg)

            -- 通知 GameUI 日志
            local GameUI = require("UI.GameUI")
            if GameUI.AddLog then
                GameUI.AddLog("开启 " .. chestName .. " 获得: " .. rewardMsg)
            end
        end,
        error = function(code, reason)
            BagUI.ShowTip("加载宝箱配置失败: " .. tostring(reason))
        end,
    })
end

return BagUI
