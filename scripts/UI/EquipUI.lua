---------------------------------------------------
-- EquipUI.lua - 装备系统面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local BigNum = require("Utils.BigNum")

local EquipUI = {}

local parentRef_ = nil
local GameUI = nil -- 延迟加载避免循环引用

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
        local eData = equipName ~= "" and DataManager.GetEquipData(equipName) or nil
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
                UI.Label {
                    text = equipName ~= "" and equipName or "（未装备）",
                    fontSize = 14,
                    fontColor = equipName ~= "" and qualityColor or { 100, 100, 120, 255 },
                    flexGrow = 1,
                    flexShrink = 1,
                },
                equipName ~= "" and UI.Button {
                    text = "详情",
                    variant = "secondary",
                    height = 28,
                    onClick = function() EquipUI.ShowDetail(equipName) end,
                } or UI.Panel { width = 0 },
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
                    UI.Label {
                        text = item.name .. " x" .. item.count,
                        fontSize = 13,
                        fontColor = qualityColor,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Button {
                        text = "详情",
                        variant = "secondary",
                        height = 26,
                        onClick = function() EquipUI.ShowDetail(item.name) end,
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

--- 显示装备操作提示（短暂显示在面板顶部）
---@param msg string
function EquipUI.ShowTip(msg)
    print("[EquipUI] " .. msg)
    if not parentRef_ then return end
    -- 查找或创建提示标签
    local tip = parentRef_:FindById("equipTip")
    if tip then
        tip:SetText("> " .. msg)
    else
        parentRef_:AddChild(UI.Label {
            id = "equipTip",
            text = "> " .. msg,
            fontSize = 12,
            fontColor = { 255, 200, 100, 255 },
            textAlign = "center",
            marginBottom = 4,
        })
    end
end

--- 从背包装备
---@param bagIndex number
function EquipUI.EquipFromBag(bagIndex)
    print("[EquipUI] EquipFromBag 被调用, bagIndex=" .. tostring(bagIndex))
    local player = DataManager.playerData
    if not player then EquipUI.ShowTip("数据异常"); return end

    local item = player.bag[bagIndex]
    if not item then EquipUI.ShowTip("物品不存在(索引:" .. tostring(bagIndex) .. ")"); return end

    print("[EquipUI] 尝试装备: " .. tostring(item.name))
    local itemData = DataManager.GetEquipData(item.name)
    if not itemData then EquipUI.ShowTip("找不到装备数据: " .. tostring(item.name)); return end
    if not itemData.slot then EquipUI.ShowTip("该物品无法装备(无部位): " .. tostring(item.name)); return end

    print("[EquipUI] 物品部位: " .. tostring(itemData.slot))

    -- 检查等级需求
    local levelReq = itemData.level_req or "0"
    local playerLevel = player.status.level or "1"
    print("[EquipUI] 等级检查: 玩家=" .. playerLevel .. " 需求=" .. levelReq)
    if BigNum.lt(playerLevel, levelReq) then
        EquipUI.ShowTip("等级不足! 需要等级" .. levelReq .. ", 当前" .. playerLevel)
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

    local equipedName = item.name
    print("[EquipUI] 装备了 " .. equipedName .. " → " .. slot)
    DataManager.SaveToCloud(player)
    EquipUI.Refresh()
    EquipUI.ShowTip("已装备: " .. equipedName)
end

--- 显示装备详情弹窗
---@param equipName string
function EquipUI.ShowDetail(equipName)
    if not equipName or equipName == "" then return end
    local eData = DataManager.GetEquipData(equipName)
    if not eData then return end

    local qualityColor = EquipUI.GetQualityColor(eData.quality or "white")
    local slotKey = SLOT_CN_TO_KEY[eData.slot] or eData.slot or ""
    local slotLabel = SLOT_KEY_TO_LABEL[slotKey] or eData.slot or "未知"

    -- 属性列表
    local statRows = {}
    if BigNum.gt(eData.atk or "0", "0") then table.insert(statRows, { label = "攻击力", value = "+" .. BigNum.toShort(eData.atk), color = { 255, 120, 120, 255 } }) end
    if BigNum.gt(eData.def or "0", "0") then table.insert(statRows, { label = "防御力", value = "+" .. BigNum.toShort(eData.def), color = { 120, 180, 255, 255 } }) end
    if BigNum.gt(eData.hp or "0", "0") then table.insert(statRows, { label = "生命值", value = "+" .. BigNum.toShort(eData.hp), color = { 120, 255, 120, 255 } }) end

    -- 等级需求
    local levelReq = eData.level_req or "0"
    local playerLevel = DataManager.playerData and DataManager.playerData.status.level or "1"
    local levelMet = BigNum.gte(playerLevel, levelReq)

    local statChildren = {}
    for _, row in ipairs(statRows) do
        table.insert(statChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%", marginBottom = 6,
            children = {
                UI.Label { text = row.label, fontSize = 14, fontColor = { 180, 180, 200, 255 }, width = 80, flexShrink = 0 },
                UI.Label { text = row.value, fontSize = 14, fontColor = row.color, flexShrink = 1, textAlign = "right" },
            },
        })
    end

    -- 等级需求行
    if tonumber(levelReq) and tonumber(levelReq) > 0 then
        table.insert(statChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 6,
            children = {
                UI.Label { text = "需要等级", fontSize = 13, fontColor = { 150, 150, 170, 255 }, width = 80, flexShrink = 0 },
                UI.Label { text = levelReq, fontSize = 13, fontColor = levelMet and { 150, 255, 150, 255 } or { 255, 80, 80, 255 }, textAlign = "right" },
            },
        })
    end

    -- 先创建引用变量
    ---@type Widget
    local dialog = nil

    dialog = UI.Panel {
        id = "equipDetailOverlay",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        onClick = function()
            -- 点击遮罩层也可关闭
            if dialog then dialog:Remove() end
        end,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 320,
                padding = 20,
                backgroundColor = { 30, 25, 50, 245 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = qualityColor,
                flexDirection = "column",
                alignItems = "center",
                gap = 10,
                -- 阻止点击穿透到遮罩层
                onClick = function() end,
                children = {
                    -- 名称
                    UI.Label { text = equipName, fontSize = 18, fontColor = qualityColor, textAlign = "center" },
                    -- 品质 + 部位
                    UI.Panel {
                        flexDirection = "row", gap = 16, marginBottom = 4,
                        children = {
                            UI.Label { text = "品质: " .. (eData.quality or "未知"), fontSize = 13, fontColor = qualityColor },
                            UI.Label { text = "部位: " .. slotLabel, fontSize = 13, fontColor = { 180, 180, 200, 255 } },
                        },
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 200 } },
                    -- 属性
                    UI.Panel {
                        width = "100%", flexDirection = "column", paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                        children = statChildren,
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关  闭",
                        variant = "secondary",
                        width = 100,
                        height = 34,
                        marginTop = 8,
                        onClick = function()
                            if dialog then dialog:Remove() end
                        end,
                    },
                },
            },
        },
    }

    -- 添加到游戏根面板（覆盖所有内容）
    if not GameUI then GameUI = require("UI.GameUI") end
    local root = GameUI.rootPanel
    if not root then root = parentRef_ end  -- fallback
    if root then
        local old = root:FindById("equipDetailOverlay")
        if old then old:Remove() end
        root:AddChild(dialog)
    end
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
