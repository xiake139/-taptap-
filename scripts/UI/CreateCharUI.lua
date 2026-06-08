---------------------------------------------------
-- CreateCharUI.lua - 角色创建界面
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local CreateCharUI = {}

local nameField_ = nil
local msgLabel_ = nil

--- 创建角色创建界面
---@return Widget
function CreateCharUI.Create()
    nameField_ = UI.TextField {
        placeholder = "为你的角色取一个名字",
        maxLength = 12,
        width = 250,
        height = 40,
    }

    msgLabel_ = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 255, 100, 100, 255 },
        textAlign = "center",
        height = 20,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 15, 10, 30, 255 },
        children = {
            UI.Label {
                text = "创建角色",
                fontSize = 28,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 30,
            },

            UI.Panel {
                width = 360,
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 30, 25, 50, 220 },
                borderRadius = 12,
                padding = 24,
                gap = 16,
                children = {
                    UI.Label {
                        text = "你即将踏入修仙界",
                        fontSize = 15,
                        fontColor = { 180, 180, 200, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "起始境界：练气期一层",
                        fontSize = 14,
                        fontColor = { 130, 200, 130, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "起始属性：生命100 攻击5 防御3",
                        fontSize = 13,
                        fontColor = { 150, 150, 180, 255 },
                        textAlign = "center",
                    },

                    -- 分隔
                    UI.Panel { width = "80%", height = 1, backgroundColor = { 60, 50, 80, 255 } },

                    UI.Label {
                        text = "角色名称",
                        fontSize = 14,
                        fontColor = { 200, 200, 220, 255 },
                    },
                    nameField_,
                    msgLabel_,

                    UI.Button {
                        text = "开始修仙之旅",
                        variant = "primary",
                        width = 180,
                        marginTop = 8,
                        onClick = function() CreateCharUI.DoCreate() end,
                    },

                    UI.Button {
                        text = "返回",
                        variant = "secondary",
                        width = 100,
                        onClick = function() SwitchState("login") end,
                    },
                },
            },
        },
    }

    return root
end

--- 执行角色创建
function CreateCharUI.DoCreate()
    local charName = nameField_:GetValue()

    if not charName or charName == "" then
        msgLabel_:SetText("请输入角色名称")
        return
    end
    if #charName < 2 then
        msgLabel_:SetText("角色名至少2个字符")
        return
    end

    print("[CreateCharUI] 创建角色: " .. charName)

    -- 创建新玩家数据
    local playerData = DataManager.CreateNewPlayer(DataManager.currentAccount, charName)
    DataManager.playerData = playerData

    -- 自动接取主线第一个任务
    local startQuest = DataManager.gameConfig["game"] and DataManager.gameConfig["game"]["start_quest"] or "main_001"
    table.insert(playerData.quests.active, { id = startQuest, progress = 0 })
    print("[CreateCharUI] 触发主线任务: " .. startQuest)

    -- 注册账号到集中式配置
    DataManager.RegisterAccount(DataManager.currentAccount, DataManager.currentPassword or "", charName)

    -- 保存游戏数据到云端
    DataManager.SaveToCloud(playerData, function(success)
        if success then
            print("[CreateCharUI] 初始存档已保存到云端")
        end
    end)

    -- 进入游戏
    SwitchState("game")
end

return CreateCharUI
