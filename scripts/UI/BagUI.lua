---------------------------------------------------
-- BagUI.lua - 背包系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local BigNum = require("Utils.BigNum")

local BagUI = {}

--- 中文部位→英文key映射
local SLOT_CN_TO_KEY = {
    ["武器"] = "weapon", ["头盔"] = "helmet", ["铠甲"] = "armor", ["护腕"] = "bracer",
    ["腰带"] = "belt", ["战靴"] = "boots", ["披风"] = "cloak", ["项链"] = "necklace",
    ["戒指"] = "ring", ["法宝"] = "artifact", ["坐骑"] = "mount", ["灵翼"] = "wings",
    ["护盾"] = "shield", ["防具"] = "armor", ["饰品"] = "accessory",
}

local parentRef_ = nil

--- 渲染背包面板
---@param parent Widget
function BagUI.Render(parent)
    parentRef_ = parent
    BagUI.Refresh()
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
        local desc = itemData and (itemData.desc or "") or ""
        local sellPrice = itemData and (itemData.price_sell or "0") or "0"

        local itemType = itemData and itemData.type or "材料"
        local isConsumable = itemData and itemType ~= "材料" and not itemData.slot
        local isEquip = itemData and itemData.slot

        local btnChildren = {}

        if isConsumable then
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

--- 装备物品
---@param index number
function BagUI.EquipItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    if not itemData or not itemData.slot then return end

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
    player.equip[slot] = item.name
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, index)
    end

    print("[BagUI] 装备了 " .. item.name)
    DataManager.SaveToCloud(player)
    BagUI.Refresh()
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

return BagUI
