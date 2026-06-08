---------------------------------------------------
-- QuestUI.lua - 任务系统面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local QuestUI = {}

--- 渲染任务面板
---@param parent Widget
function QuestUI.Render(parent)
    parent:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    parent:AddChild(UI.Label {
        text = "— 任务列表 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    -- 进行中的任务
    if #player.quests.active > 0 then
        parent:AddChild(UI.Label {
            text = "[ 进行中 ]",
            fontSize = 14,
            fontColor = { 100, 200, 255, 255 },
            marginBottom = 4,
        })

        for _, quest in ipairs(player.quests.active) do
            local qData = DataManager.GetQuest(quest.id)
            if qData then
                local targetCount = qData.target_count or "1"
                local progress = quest.progress or "0"
                local progressText = tostring(progress) .. "/" .. tostring(targetCount)

                local typeLabel = qData.type == "main" and "[主线]" or "[支线]"
                local typeColor = qData.type == "main" and { 255, 200, 50, 255 } or { 150, 200, 255, 255 }

                parent:AddChild(UI.Panel {
                    width = "100%",
                    flexDirection = "column",
                    padding = 8,
                    backgroundColor = { 25, 20, 45, 200 },
                    borderRadius = 6,
                    marginBottom = 6,
                    gap = 4,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label { text = typeLabel, fontSize = 12, fontColor = typeColor },
                                UI.Label { text = qData.name or quest.id, fontSize = 14, fontColor = { 220, 220, 240, 255 } },
                            },
                        },
                        UI.Label { text = qData.desc or "", fontSize = 12, fontColor = { 160, 160, 180, 255 }, whiteSpace = "normal" },
                        UI.Panel {
                            flexDirection = "row",
                            justifyContent = "space-between",
                            width = "100%",
                            children = {
                                UI.Label { text = "目标：" .. (qData.target_name or "?") .. " " .. progressText, fontSize = 12, fontColor = { 150, 200, 150, 255 } },
                                UI.Label { text = "奖励：经验" .. (qData.reward_exp or 0) .. " 金" .. (qData.reward_gold or 0), fontSize = 11, fontColor = { 255, 215, 0, 255 } },
                            },
                        },
                    },
                })
            end
        end
    else
        parent:AddChild(UI.Label {
            text = "暂无进行中的任务",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 10,
        })
    end

    -- 已完成的任务
    if #player.quests.completed > 0 then
        parent:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 }, marginTop = 10, marginBottom = 10 })

        parent:AddChild(UI.Label {
            text = "[ 已完成 ] (" .. #player.quests.completed .. ")",
            fontSize = 14,
            fontColor = { 100, 160, 100, 255 },
            marginBottom = 4,
        })

        -- 只显示最近5个
        local startIdx = math.max(1, #player.quests.completed - 4)
        for i = #player.quests.completed, startIdx, -1 do
            local qid = player.quests.completed[i]
            local qData = DataManager.GetQuest(qid)
            local qName = qData and qData.name or qid

            parent:AddChild(UI.Label {
                text = "  ✓ " .. qName,
                fontSize = 12,
                fontColor = { 100, 150, 100, 255 },
            })
        end
    end
end

return QuestUI
