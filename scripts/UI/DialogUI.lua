---------------------------------------------------
-- DialogUI.lua - NPC对话系统
-- 点击NPC可触发支线任务
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local BigNum = require("Utils.BigNum")
local NumFormat = require("Utils.NumFormat")

local DialogUI = {}

--- 显示NPC对话
---@param npcName string
---@param parent Widget
function DialogUI.Show(npcName, parent)
    if not parent then return end
    parent:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    local npcData = DataManager.GetNPC(npcName)
    if not npcData then
        parent:AddChild(UI.Label { text = "找不到此NPC", fontSize = 14, fontColor = { 255, 100, 100, 255 } })
        return
    end

    local dialog = npcData.dialog or "......"

    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        backgroundColor = { 25, 25, 50, 220 },
        borderRadius = 8,
        children = {
            -- NPC 名
            UI.Label {
                text = "【" .. npcName .. "】",
                fontSize = 16,
                fontColor = { 100, 220, 100, 255 },
                textAlign = "center",
            },

            -- 对话内容
            UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = { 15, 12, 30, 200 },
                borderRadius = 6,
                children = {
                    UI.Label {
                        text = dialog,
                        fontSize = 14,
                        fontColor = { 220, 220, 240, 255 },
                        whiteSpace = "normal",
                        lineHeight = 1.5,
                    },
                },
            },
        },
    })

    -- 根据NPC类型显示选项
    local npcType = npcData.type or "normal"

    if npcType == "merchant" or npcType == "商人" then
        -- 商人：显示NPC专属商店
        local shopId = npcData.shop_id or ""
        parent:AddChild(UI.Button {
            text = "查看商品",
            variant = "primary",
            width = "100%",
            marginTop = 8,
            onClick = function()
                DialogUI.ShowNpcShop(parent, npcName, shopId)
            end,
        })
    end

    if npcType == "quest" or npcType == "任务" or npcType == "teacher" or npcType == "师傅" then
        -- 有支线任务的NPC
        local questId = npcData.quest_id
        if questId and questId ~= "" then
            DialogUI.ShowQuestOption(parent, questId, npcName)
        end
    end

    -- 对话类任务完成检查（主线中的"对话"目标）
    DialogUI.CheckTalkQuest(npcName)

    -- 关闭按钮
    parent:AddChild(UI.Button {
        text = "离开",
        variant = "secondary",
        width = "100%",
        marginTop = 8,
        onClick = function()
            local GameUI = require("UI.GameUI")
            GameUI.RefreshMap()
        end,
    })
end

--- 显示任务选项
---@param parent Widget
---@param questId string
---@param npcName string
function DialogUI.ShowQuestOption(parent, questId, npcName)
    local player = DataManager.playerData
    if not player then return end

    local qData = DataManager.GetQuest(questId)
    if not qData then return end

    -- 检查是否已完成
    for _, cid in ipairs(player.quests.completed) do
        if cid == questId then
            parent:AddChild(UI.Label {
                text = "（此任务已完成）",
                fontSize = 12,
                fontColor = { 100, 160, 100, 255 },
                textAlign = "center",
                marginTop = 4,
            })
            return
        end
    end

    -- 检查是否已接取
    for _, q in ipairs(player.quests.active) do
        if q.id == questId then
            parent:AddChild(UI.Label {
                text = "（任务进行中...）",
                fontSize = 12,
                fontColor = { 200, 200, 100, 255 },
                textAlign = "center",
                marginTop = 4,
            })
            return
        end
    end

    -- 可接取支线任务
    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 8,
        marginTop = 8,
        backgroundColor = { 40, 35, 60, 200 },
        borderRadius = 6,
        gap = 4,
        children = {
            UI.Label {
                text = "[支线任务] " .. (qData.name or questId),
                fontSize = 14,
                fontColor = { 150, 200, 255, 255 },
            },
            UI.Label {
                text = qData.desc or "",
                fontSize = 12,
                fontColor = { 160, 160, 180, 255 },
                whiteSpace = "normal",
            },
            UI.Label {
                text = "奖励：经验" .. (qData.reward_exp or 0) .. " 金币" .. (qData.reward_gold or 0),
                fontSize = 11,
                fontColor = { 255, 215, 0, 255 },
            },
            UI.Button {
                text = "接受任务",
                variant = "success",
                width = "100%",
                marginTop = 4,
                onClick = function()
                    DialogUI.AcceptQuest(questId)
                    DialogUI.Show(npcName, parent) -- 刷新对话
                end,
            },
        },
    })
end

--- 接受支线任务
---@param questId string
function DialogUI.AcceptQuest(questId)
    local player = DataManager.playerData
    if not player then return end

    table.insert(player.quests.active, { id = questId, progress = "0" })

    local qData = DataManager.GetQuest(questId)
    local GameUI = require("UI.GameUI")
    GameUI.AddLog("接受任务：" .. (qData and qData.name or questId))

    DataManager.SaveToCloud(player)
end

--- 检查对话类任务
---@param npcName string
function DialogUI.CheckTalkQuest(npcName)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and qData.target_type == "talk" and qData.target_name == npcName then
            quest.progress = BigNum.add(tostring(quest.progress or "0"), "1")
            local targetCount = qData.target_count or "1"

            local GameUI = require("UI.GameUI")
            GameUI.AddLog("任务进度：" .. (qData.name or quest.id) .. " (" .. quest.progress .. "/" .. targetCount .. ")")

            if BigNum.gte(quest.progress, targetCount) then
                GameUI.CompleteQuest(quest)
            end
            break
        end
    end
end

--- NPC专属商店界面
---@param parent Widget
---@param npcName string
---@param shopId string
function DialogUI.ShowNpcShop(parent, npcName, shopId)
    if not parent then return end
    parent:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    local shopData = DataManager.GetShop(shopId)
    if not shopData or #(shopData.items or {}) == 0 then
        parent:AddChild(UI.Label {
            text = "【" .. npcName .. "】的商店暂无商品",
            fontSize = 14, fontColor = { 200, 200, 100, 255 }, textAlign = "center", marginTop = 12,
        })
        parent:AddChild(UI.Button {
            text = "← 返回对话",
            variant = "outline", width = "100%", marginTop = 8,
            onClick = function() DialogUI.Show(npcName, parent) end,
        })
        return
    end

    local shopName = shopData.name or npcName .. "的商店"
    local currency = "金币"

    -- 标题 + 返回
    parent:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", width = "100%", marginBottom = 4,
        children = {
            UI.Button {
                text = "← 返回",
                variant = "outline", height = 26, fontSize = 11,
                onClick = function() DialogUI.Show(npcName, parent) end,
            },
            UI.Label {
                text = "  " .. shopName,
                fontSize = 15, fontColor = { 100, 220, 100, 255 }, flexGrow = 1,
            },
        },
    })

    -- 玩家金币
    local goldValue = DataManager.GetPlayerCurrency(player, currency)
    parent:AddChild(UI.Label {
        text = currency .. "：" .. NumFormat.Short(goldValue),
        fontSize = 14, fontColor = { 255, 215, 0, 255 }, textAlign = "center", marginBottom = 6,
    })

    -- 商品列表
    for _, shopItem in ipairs(shopData.items) do
        local itemName = shopItem.name or ""
        local price = shopItem.price or "0"
        local desc = shopItem.desc or ""
        if itemName == "" then goto continue_npc_item end

        parent:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", width = "100%",
            padding = 6, gap = 6,
            backgroundColor = { 25, 30, 20, 200 }, borderRadius = 4, marginBottom = 3,
            children = {
                UI.Panel {
                    flexGrow = 1, flexShrink = 1, flexDirection = "column",
                    children = {
                        UI.Label { text = itemName, fontSize = 14, fontColor = { 220, 240, 220, 255 } },
                        desc ~= "" and UI.Label { text = desc, fontSize = 11, fontColor = { 140, 160, 140, 255 }, whiteSpace = "normal" } or nil,
                    },
                },
                UI.Label { text = NumFormat.Short(price) .. currency, fontSize = 13, fontColor = { 255, 215, 0, 255 } },
                UI.Button {
                    text = "购买",
                    variant = "success", height = 28,
                    onClick = function()
                        DialogUI.BuyNpcItem(parent, npcName, shopId, itemName, price, currency)
                    end,
                },
            },
        })
        ::continue_npc_item::
    end
end

--- NPC商店购买物品
---@param parent Widget
---@param npcName string
---@param shopId string
---@param itemName string
---@param price string
---@param currency string
function DialogUI.BuyNpcItem(parent, npcName, shopId, itemName, price, currency)
    local player = DataManager.playerData
    if not player then return end

    local have = BigNum.new(DataManager.GetPlayerCurrency(player, currency))
    local cost = BigNum.new(tostring(price))
    if BigNum.lt(have, cost) then
        local GameUI = require("UI.GameUI")
        GameUI.AddLog(currency .. "不足，无法购买 " .. itemName)
        return
    end

    -- 扣除货币
    local newVal = BigNum.sub(have, cost)
    DataManager.SetPlayerCurrency(player, currency, newVal)

    -- 添加到背包
    local found = false
    for _, item in ipairs(player.bag) do
        if item.name == itemName then
            item.count = BigNum.add(item.count or "0", "1")
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = itemName, count = "1" })
    end

    local GameUI = require("UI.GameUI")
    GameUI.AddLog("从【" .. npcName .. "】购买了 " .. itemName)

    DataManager.SaveToCloud(player)
    -- 刷新商店界面
    DialogUI.ShowNpcShop(parent, npcName, shopId)
end

return DialogUI
