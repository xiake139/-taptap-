---------------------------------------------------
-- EquipUI.lua - 装备系统面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local BigNum = require("Utils.BigNum")

local EquipUI = {}

local parentRef_ = nil

--- 中文部位→英文key映射（兼容玩家数据结构）
local SLOT_CN_TO_KEY = {
    ["武器"] = "weapon", ["头盔"] = "helmet", ["铠甲"] = "armor", ["护腕"] = "bracer",
    ["腰带"] = "belt", ["战靴"] = "boots", ["披风"] = "cloak", ["项链"] = "necklace",
    ["戒指"] = "ring", ["法宝"] = "artifact", ["坐骑"] = "mount", ["灵翼"] = "wings",
    ["护盾"] = "shield", ["防具"] = "armor", ["饰品"] = "accessory",
}
--- 英文key→中文显示名
local SLOT_KEY_TO_LABEL = {
    weapon = "武器", helmet = "头盔", armor = "铠甲", bracer = "护腕",
    belt = "腰带", boots = "战靴", cloak = "披风", necklace = "项链",
    ring = "戒指", artifact = "法宝", mount = "坐骑", wings = "灵翼",
    shield = "护盾", accessory = "饰品",
}

--- 渲染装备面板
---@param parent Widget
function EquipUI.Render(parent)
    parentRef_ = parent
    EquipUI.Refresh()
end

--- 刷新装备显示
function EquipUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 使用 ScrollView 确保内容可滚动
    local scrollContent = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        flexDirection = "column",
    }
    parentRef_:AddChild(scrollContent)

    scrollContent:AddChild(UI.Label {
        text = "— 装备栏 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    -- 装备槽（13个部位）
    local slots = {
        { key = "weapon", label = "武器" },
        { key = "helmet", label = "头盔" },
        { key = "armor", label = "铠甲" },
        { key = "bracer", label = "护腕" },
        { key = "belt", label = "腰带" },
        { key = "boots", label = "战靴" },
        { key = "cloak", label = "披风" },
        { key = "necklace", label = "项链" },
        { key = "ring", label = "戒指" },
        { key = "artifact", label = "法宝" },
        { key = "mount", label = "坐骑" },
        { key = "wings", label = "灵翼" },
        { key = "shield", label = "护盾" },
    }

    for _, slot in ipairs(slots) do
        local equipName = player.equip[slot.key] or ""
        local eData = nil
        local statsText = ""

        if equipName ~= "" then
            eData = DataManager.GetEquipData(equipName)
            if eData then
                local parts = {}
                if BigNum.gt(eData.atk or "0", "0") then table.insert(parts, "攻+" .. BigNum.toShort(eData.atk)) end
                if BigNum.gt(eData.def or "0", "0") then table.insert(parts, "防+" .. BigNum.toShort(eData.def)) end
                if BigNum.gt(eData.hp or "0", "0") then table.insert(parts, "血+" .. BigNum.toShort(eData.hp)) end
                statsText = table.concat(parts, " ")
            end
        end

        local qualityColor = EquipUI.GetQualityColor(eData and eData.quality or "white")

        scrollContent:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 8,
            backgroundColor = { 25, 20, 45, 200 },
            borderRadius = 6,
            marginBottom = 6,
            gap = 8,
            children = {
                UI.Label { text = "[" .. slot.label .. "]", fontSize = 14, fontColor = { 140, 140, 160, 255 }, width = 50 },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label {
                            text = equipName ~= "" and equipName or "（未装备）",
                            fontSize = 14,
                            fontColor = equipName ~= "" and qualityColor or { 100, 100, 120, 255 },
                        },
                        statsText ~= "" and UI.Label {
                            text = statsText,
                            fontSize = 11,
                            fontColor = { 150, 200, 150, 255 },
                        } or UI.Panel { height = 0 },
                    },
                },
                equipName ~= "" and UI.Button {
                    text = "卸下",
                    variant = "secondary",
                    height = 28,
                    onClick = function() EquipUI.Unequip(slot.key) end,
                } or UI.Panel { width = 0 },
            },
        })
    end

    -- 分隔
    scrollContent:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 }, marginTop = 8, marginBottom = 8 })

    -- 可装备物品列表
    scrollContent:AddChild(UI.Label {
        text = "背包中可装备的物品",
        fontSize = 14,
        fontColor = { 150, 150, 180, 255 },
        textAlign = "center",
        marginBottom = 6,
    })

    local hasEquippable = false
    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetEquipData(item.name)
        if itemData and itemData.slot then
            hasEquippable = true
            local qualityColor = EquipUI.GetQualityColor(itemData.quality or "white")
            local parts = {}
            if BigNum.gt(itemData.atk or "0", "0") then table.insert(parts, "攻+" .. BigNum.toShort(itemData.atk)) end
            if BigNum.gt(itemData.def or "0", "0") then table.insert(parts, "防+" .. BigNum.toShort(itemData.def)) end
            if BigNum.gt(itemData.hp or "0", "0") then table.insert(parts, "血+" .. BigNum.toShort(itemData.hp)) end

            -- 部位显示（中文）
            local slotKey = SLOT_CN_TO_KEY[itemData.slot] or itemData.slot
            local slotLabel = SLOT_KEY_TO_LABEL[slotKey] or itemData.slot or "未知"

            scrollContent:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                padding = 6,
                backgroundColor = { 20, 15, 35, 200 },
                borderRadius = 4,
                marginBottom = 3,
                gap = 6,
                children = {
                    UI.Label { text = "[" .. slotLabel .. "]", fontSize = 12, fontColor = { 120, 120, 150, 255 }, width = 46 },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        children = {
                            UI.Label { text = item.name .. " x" .. item.count, fontSize = 13, fontColor = qualityColor },
                            UI.Label { text = table.concat(parts, " "), fontSize = 11, fontColor = { 150, 200, 150, 255 } },
                        },
                    },
                    UI.Button {
                        text = "装备",
                        variant = "primary",
                        height = 26,
                        onClick = function() EquipUI.EquipFromBag(i) end,
                    },
                },
            })
        end
    end

    if not hasEquippable then
        scrollContent:AddChild(UI.Label {
            text = "无可装备物品",
            fontSize = 12,
            fontColor = { 100, 100, 120, 255 },
            textAlign = "center",
        })
    end
end

--- 卸下装备
---@param slot string
function EquipUI.Unequip(slot)
    local player = DataManager.playerData
    if not player then return end

    local equipName = player.equip[slot]
    if not equipName or equipName == "" then return end

    -- 放回背包
    local found = false
    for _, item in ipairs(player.bag) do
        if item.name == equipName then
            item.count = BigNum.add(item.count or "0", "1")
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = equipName, count = "1" })
    end

    player.equip[slot] = ""
    print("[EquipUI] 卸下了 " .. equipName)
    DataManager.SaveToCloud(player)
    EquipUI.Refresh()
end

--- 从背包装备
---@param bagIndex number
function EquipUI.EquipFromBag(bagIndex)
    print("[EquipUI] EquipFromBag 被调用, bagIndex=" .. tostring(bagIndex))
    local player = DataManager.playerData
    if not player then print("[EquipUI] player为nil"); return end

    local item = player.bag[bagIndex]
    if not item then print("[EquipUI] bag[" .. tostring(bagIndex) .. "]为nil, bag长度=" .. #player.bag); return end

    print("[EquipUI] 尝试装备: " .. tostring(item.name))
    local itemData = DataManager.GetEquipData(item.name)
    if not itemData then print("[EquipUI] GetEquipData返回nil, name=" .. tostring(item.name)); return end
    if not itemData.slot then print("[EquipUI] itemData.slot为nil, name=" .. tostring(item.name)); return end

    print("[EquipUI] 物品部位: " .. tostring(itemData.slot))

    -- 检查等级需求
    local levelReq = itemData.level_req or "0"
    local playerLevel = player.status.level or "1"
    print("[EquipUI] 等级检查: 玩家=" .. playerLevel .. " 需求=" .. levelReq)
    if BigNum.lt(playerLevel, levelReq) then
        print("[EquipUI] 等级不足，需要等级 " .. levelReq)
        return
    end

    -- 将中文部位名转换为英文key（兼容旧数据）
    local slot = SLOT_CN_TO_KEY[itemData.slot] or itemData.slot

    -- 卸下旧装备
    local oldEquip = player.equip[slot]
    if oldEquip and oldEquip ~= "" then
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

    -- 装备
    player.equip[slot] = item.name
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, bagIndex)
    end

    print("[EquipUI] 装备了 " .. item.name .. " → " .. slot)
    DataManager.SaveToCloud(player)
    EquipUI.Refresh()
end

--- 获取品质颜色
---@param quality string
---@return table color {r,g,b,a}
function EquipUI.GetQualityColor(quality)
    local colors = {
        -- 英文兼容（旧数据）
        white = { 200, 200, 200, 255 },
        green = { 100, 220, 100, 255 },
        blue = { 100, 150, 255, 255 },
        purple = { 200, 100, 255, 255 },
        gold = { 255, 200, 50, 255 },
        orange = { 255, 165, 0, 255 },
        red = { 255, 80, 80, 255 },
        -- 中文品质（新数据）
        ["白色"] = { 200, 200, 200, 255 },
        ["绿色"] = { 100, 220, 100, 255 },
        ["橙色"] = { 255, 165, 0, 255 },
        ["红色"] = { 255, 80, 80, 255 },
        ["彩色"] = { 255, 100, 200, 255 },
        ["地级"] = { 180, 130, 255, 255 },
        ["天级"] = { 100, 200, 255, 255 },
        ["帝级"] = { 255, 215, 0, 255 },
        ["仙级"] = { 200, 255, 100, 255 },
        ["神级"] = { 255, 100, 100, 255 },
        ["创世级"] = { 255, 50, 200, 255 },
        -- 旧中文兼容
        ["蓝色"] = { 100, 150, 255, 255 },
        ["紫色"] = { 200, 100, 255, 255 },
        ["金色"] = { 255, 200, 50, 255 },
    }
    return colors[quality] or colors["白色"]
end

return EquipUI
