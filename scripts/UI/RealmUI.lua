---------------------------------------------------
-- RealmUI.lua - 境界修炼面板
-- 大境界 + 小层级系统，独立于等级
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local RealmUI = {}

-- UI 引用
local parentRef_ = nil
local tipLabel_ = nil

--- 显示提示信息
---@param msg string
---@param color? table
local function ShowTip(msg, color)
    color = color or { 255, 220, 100, 255 }
    if tipLabel_ then
        tipLabel_:SetText(msg)
        tipLabel_:SetFontColor(color)
    end
end

--- 获取玩家背包中指定物品数量
---@param itemName string
---@return number
local function GetBagItemCount(itemName)
    local player = DataManager.playerData
    if not player then return 0 end
    for _, bagItem in ipairs(player.bag) do
        if bagItem.name == itemName then
            return tonumber(bagItem.count) or 0
        end
    end
    return 0
end

--- 从背包消耗指定数量物品
---@param itemName string
---@param amount number
---@return boolean success
local function ConsumeBagItem(itemName, amount)
    local player = DataManager.playerData
    if not player then return false end
    for i, bagItem in ipairs(player.bag) do
        if bagItem.name == itemName then
            local current = tonumber(bagItem.count) or 0
            if current < amount then return false end
            current = current - amount
            if current <= 0 then
                table.remove(player.bag, i)
            else
                bagItem.count = tostring(current)
            end
            return true
        end
    end
    return false
end

--- 提升境界（小层级升级）
local function DoUpgrade()
    local player = DataManager.playerData
    if not player then return end

    local realm = DataManager.GetCurrentRealm()
    if not realm then return end

    local layer = tonumber(player.status.realm_layer) or 1
    if layer >= realm.layers then
        ShowTip("已达本境界最高层，请突破进入下一境界！", { 200, 100, 100, 255 })
        return
    end

    -- 检查经验
    local curExp = tonumber(player.status.realm_exp) or 0
    local needExp = tonumber(realm.layer_exp) or 100
    if curExp < needExp then
        ShowTip("修炼经验不足！需要 " .. NumFormat.Short(tostring(needExp)) .. "，当前 " .. NumFormat.Short(tostring(curExp)), { 200, 100, 100, 255 })
        return
    end

    -- 检查材料
    local material = realm.upgrade_material
    local needCount = realm.upgrade_count
    if material and material ~= "" and needCount > 0 then
        local haveCount = GetBagItemCount(material)
        if haveCount < needCount then
            ShowTip(material .. "不足！需要 " .. needCount .. "，当前 " .. haveCount, { 200, 100, 100, 255 })
            return
        end
        -- 消耗材料
        if not ConsumeBagItem(material, needCount) then
            ShowTip("消耗材料失败！", { 200, 100, 100, 255 })
            return
        end
    end

    -- 扣除经验
    player.status.realm_exp = tostring(curExp - needExp)
    -- 层数 +1
    player.status.realm_layer = tostring(layer + 1)

    -- 保存
    DataManager.SaveToCloud(player)

    -- 日志
    local GameUI = require("UI.GameUI")
    GameUI.AddLog("境界提升！当前：【" .. DataManager.GetRealmFullName() .. "】")
    ShowTip("提升成功！晋升为【" .. DataManager.GetRealmFullName() .. "】", { 100, 255, 100, 255 })

    -- 刷新面板
    RealmUI.Refresh()
end

--- 突破境界（大境界突破）
local function DoBreakthrough()
    local player = DataManager.playerData
    if not player then return end

    local realm = DataManager.GetCurrentRealm()
    if not realm then return end

    -- 必须在最高层才能突破
    local layer = tonumber(player.status.realm_layer) or 1
    if layer < realm.layers then
        ShowTip("需要达到" .. realm.name .. "最高层才能突破！", { 200, 100, 100, 255 })
        return
    end

    -- 检查是否有下一境界
    local nextRealm = DataManager.GetNextRealm()
    if not nextRealm then
        ShowTip("已达最高境界，无法继续突破！", { 200, 100, 100, 255 })
        return
    end

    -- 检查突破材料
    local material = realm.breakthrough_material
    local needCount = realm.breakthrough_count
    if not material or material == "" then
        ShowTip("配置错误：当前境界无突破材料", { 200, 100, 100, 255 })
        return
    end

    local haveCount = GetBagItemCount(material)
    if haveCount < needCount then
        ShowTip(material .. "不足！需要 " .. needCount .. "，当前 " .. haveCount, { 200, 100, 100, 255 })
        return
    end

    -- 消耗材料
    if not ConsumeBagItem(material, needCount) then
        ShowTip("消耗材料失败！", { 200, 100, 100, 255 })
        return
    end

    -- 进入下一大境界第一层
    local newStage = (tonumber(player.status.realm) or 1) + 1
    player.status.realm = tostring(newStage)
    player.status.realm_layer = "1"
    player.status.realm_exp = "0"

    -- 保存
    DataManager.SaveToCloud(player)

    -- 日志
    local GameUI = require("UI.GameUI")
    GameUI.AddLog("境界突破成功！当前境界：【" .. DataManager.GetRealmFullName() .. "】")
    ShowTip("突破成功！晋升为【" .. DataManager.GetRealmFullName() .. "】", { 100, 255, 100, 255 })

    -- 刷新面板
    RealmUI.Refresh()
end

--- 构建一行信息
---@param label string
---@param value string
---@param valueColor? table
local function InfoRow(label, value, valueColor)
    valueColor = valueColor or { 220, 220, 240, 255 }
    return UI.Panel {
        flexDirection = "row", width = "100%", justifyContent = "space-between",
        paddingTop = 3, paddingBottom = 3,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = { 160, 160, 180, 255 } },
            UI.Label { text = value, fontSize = 13, fontColor = valueColor },
        },
    }
end

--- 刷新面板（重新渲染）
function RealmUI.Refresh()
    if parentRef_ then
        parentRef_:ClearChildren()
        RealmUI.Render(parentRef_)
    end
end

--- 渲染境界面板
---@param parent Widget
function RealmUI.Render(parent)
    parentRef_ = parent
    local player = DataManager.playerData
    if not player then return end

    -- 确保老存档有字段
    if not player.status.realm or player.status.realm == "" then
        player.status.realm = "1"
    end
    if not player.status.realm_layer or player.status.realm_layer == "" then
        player.status.realm_layer = "1"
    end
    if not player.status.realm_exp or player.status.realm_exp == "" then
        player.status.realm_exp = "0"
    end

    local currentStage = tonumber(player.status.realm) or 1
    local currentLayer = tonumber(player.status.realm_layer) or 1
    local currentExp = player.status.realm_exp or "0"
    local realm = DataManager.GetCurrentRealm()
    local nextRealm = DataManager.GetNextRealm()
    local isAtMaxLayer = DataManager.IsAtMaxLayer()

    if not realm then return end

    -- 当前加成
    local curAtk, curDef, curHp = DataManager.GetRealmBonus()
    -- 下一级加成（+1层或下一大境界第一层）
    local nextAtk, nextDef, nextHp
    if not isAtMaxLayer then
        -- 下一小层：当前加成 + 本境界一层加成
        nextAtk = BigNum.add(curAtk, realm.atk_bonus or "0")
        nextDef = BigNum.add(curDef, realm.def_bonus or "0")
        nextHp = BigNum.add(curHp, realm.hp_bonus or "0")
    elseif nextRealm then
        -- 突破后：当前加成 + 下一境界第一层加成
        nextAtk = BigNum.add(curAtk, nextRealm.atk_bonus or "0")
        nextDef = BigNum.add(curDef, nextRealm.def_bonus or "0")
        nextHp = BigNum.add(curHp, nextRealm.hp_bonus or "0")
    else
        nextAtk = curAtk
        nextDef = curDef
        nextHp = curHp
    end

    -- 需要的经验
    local needExp = realm.layer_exp or "100"

    -- 提示标签
    tipLabel_ = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 255, 220, 100, 255 },
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    -- 构建内容
    local children = {}

    -- 标题
    table.insert(children, UI.Label {
        text = "【境界面板】",
        fontSize = 16,
        fontColor = { 255, 215, 0, 255 },
        textAlign = "center",
        width = "100%",
        marginBottom = 8,
    })
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } })

    -- 当前境界
    table.insert(children, InfoRow("当前境界", DataManager.GetRealmFullName(), { 255, 215, 0, 255 }))
    -- 当前经验
    table.insert(children, InfoRow("当前经验", NumFormat.Short(currentExp), { 180, 230, 255, 255 }))
    -- 下级所需经验（小层级时显示）
    if not isAtMaxLayer then
        table.insert(children, InfoRow("下级所需经验", NumFormat.Short(needExp), { 255, 200, 100, 255 }))
    end

    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 40, 35, 60, 255 }, marginTop = 4, marginBottom = 4 })

    -- 当前增加属性
    table.insert(children, InfoRow("当前增加攻击", "+" .. NumFormat.Short(curAtk), { 255, 150, 150, 255 }))
    table.insert(children, InfoRow("当前增加防御", "+" .. NumFormat.Short(curDef), { 150, 150, 255, 255 }))
    table.insert(children, InfoRow("当前增加生命", "+" .. NumFormat.Short(curHp), { 150, 255, 150, 255 }))

    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 40, 35, 60, 255 }, marginTop = 4, marginBottom = 4 })

    -- 下级增加属性
    if not isAtMaxLayer or nextRealm then
        table.insert(children, InfoRow("下级增加攻击", "+" .. NumFormat.Short(nextAtk), { 255, 180, 180, 255 }))
        table.insert(children, InfoRow("下级增加防御", "+" .. NumFormat.Short(nextDef), { 180, 180, 255, 255 }))
        table.insert(children, InfoRow("下级增加生命", "+" .. NumFormat.Short(nextHp), { 180, 255, 180, 255 }))
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 40, 35, 60, 255 }, marginTop = 4, marginBottom = 4 })
    end

    -- 小境界：显示提升材料
    if not isAtMaxLayer then
        local mat = realm.upgrade_material or ""
        local cnt = realm.upgrade_count or 0
        local have = GetBagItemCount(mat)
        local matColor = have >= cnt and { 100, 255, 100, 255 } or { 255, 100, 100, 255 }
        table.insert(children, InfoRow("下级所需材料", mat .. " × " .. cnt .. "（持有：" .. have .. "）", matColor))
    end

    -- 大境界（最高层）：显示突破材料
    if isAtMaxLayer and nextRealm then
        local mat = realm.breakthrough_material or ""
        local cnt = realm.breakthrough_count or 0
        local have = GetBagItemCount(mat)
        local matColor = have >= cnt and { 100, 255, 100, 255 } or { 255, 100, 100, 255 }
        table.insert(children, InfoRow("突破材料", mat .. " × " .. cnt .. "（持有：" .. have .. "）", matColor))
    end

    table.insert(children, UI.Panel { width = "100%", height = 6 })

    -- 按钮区域
    if not isAtMaxLayer then
        -- 小境界：显示"提升境界"按钮
        local canUpgrade = (tonumber(currentExp) or 0) >= (tonumber(needExp) or 100)
        local mat = realm.upgrade_material or ""
        local cnt = realm.upgrade_count or 0
        if mat ~= "" and cnt > 0 then
            canUpgrade = canUpgrade and (GetBagItemCount(mat) >= cnt)
        end
        table.insert(children, UI.Button {
            text = canUpgrade and "提升境界" or "条件不足",
            variant = canUpgrade and "primary" or "secondary",
            width = "100%",
            disabled = not canUpgrade,
            onClick = function()
                DoUpgrade()
            end,
        })
    elseif nextRealm then
        -- 大境界最高层：显示"突破境界"按钮
        local mat = realm.breakthrough_material or ""
        local cnt = realm.breakthrough_count or 0
        local canBreak = true
        if mat ~= "" and cnt > 0 then
            canBreak = GetBagItemCount(mat) >= cnt
        end
        table.insert(children, UI.Button {
            text = canBreak and "突破境界" or "材料不足",
            variant = canBreak and "primary" or "secondary",
            width = "100%",
            disabled = not canBreak,
            onClick = function()
                DoBreakthrough()
            end,
        })
    else
        -- 已达最高境界最高层
        table.insert(children, UI.Label {
            text = "已达最高境界圆满！",
            fontSize = 15,
            fontColor = { 255, 215, 0, 255 },
            textAlign = "center",
            width = "100%",
        })
    end

    -- 提示
    table.insert(children, tipLabel_)

    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 2,
        children = children,
    })
end

return RealmUI
