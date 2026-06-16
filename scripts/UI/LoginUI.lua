---------------------------------------------------
-- LoginUI.lua - 登录/注册界面
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")

local LoginUI = {}

local usernameField_ = nil
local passwordField_ = nil
local msgLabel_ = nil

--- 创建登录界面
---@return Widget
function LoginUI.Create()
    usernameField_ = UI.TextField {
        placeholder = "请输入账号",
        maxLength = 20,
        width = 250,
        height = 40,
    }

    passwordField_ = UI.TextField {
        placeholder = "请输入密码",
        maxLength = 20,
        width = 250,
        height = 40,
    }

    msgLabel_ = UI.Label {
        id = "loginMsg",
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
            -- 标题
            UI.Label {
                text = "创 世 修 仙",
                fontSize = 36,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 8,
            },
            UI.Label {
                text = "踏入修仙界，逆天改命",
                fontSize = 14,
                fontColor = { 150, 150, 180, 255 },
                textAlign = "center",
                marginBottom = 40,
            },

            -- 登录面板
            UI.Panel {
                width = 320,
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 30, 25, 50, 220 },
                borderRadius = 12,
                padding = 24,
                gap = 12,
                children = {
                    UI.Label {
                        text = "账号登录",
                        fontSize = 18,
                        fontColor = { 220, 200, 150, 255 },
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    usernameField_,
                    passwordField_,
                    msgLabel_,
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "登 录",
                                variant = "primary",
                                width = 100,
                                onClick = function() LoginUI.DoLogin() end,
                            },
                            UI.Button {
                                text = "注 册",
                                variant = "secondary",
                                width = 100,
                                onClick = function() LoginUI.DoRegister() end,
                            },
                        },
                    },
                },
            },

            -- 底部提示
            UI.Label {
                text = "首次游玩请先注册账号",
                fontSize = 12,
                fontColor = { 100, 100, 130, 255 },
                textAlign = "center",
                marginTop = 20,
            },

            -- 管理员入口
            UI.Button {
                text = "管理员登录",
                variant = "text",
                fontSize = 11,
                fontColor = { 80, 80, 110, 255 },
                marginTop = 12,
                onClick = function() SwitchState("admin_login") end,
            },
        },
    }

    return root
end

--- 执行登录
function LoginUI.DoLogin()
    local username = usernameField_:GetValue()
    local password = passwordField_:GetValue()

    if not username or username == "" then
        msgLabel_:SetText("请输入账号")
        return
    end
    if not password or password == "" then
        msgLabel_:SetText("请输入密码")
        return
    end

    print("[LoginUI] 尝试登录: " .. username)
    msgLabel_:SetText("正在登录...")

    -- 从集中式账号配置验证
    DataManager.VerifyLogin(username, password, function(success, charName, errorMsg)
        if not success then
            DataManager.currentAccount = nil
            msgLabel_:SetText(errorMsg or "登录失败")
            return
        end

        -- 验证通过，加载游戏数据
        DataManager.currentAccount = username
        DataManager.currentPassword = password
        DataManager.LoadFromCloud(function(playerData)
            if not playerData then
                -- 账号存在但无游戏数据，可能是旧账号，创建默认数据
                playerData = DataManager.CreateNewPlayer(username, charName or username)
                DataManager.SaveToCloud(playerData)
            end
            DataManager.playerData = playerData
            -- 恢复玩家数值显示模式偏好
            NumFormat.SetMode(playerData.status.num_format_mode or "unit")
            -- 确保 account 字段正确
            playerData.account.username = username
            playerData.account.password = password
            playerData.account.char_name = charName or playerData.status.name or username

            -- 懒迁移：检查部署版本，自动传送到目标地图
            local deployCfg = (DataManager.gameConfig or {})["deploy"]
            local needSave = false
            if deployCfg and deployCfg.version and deployCfg.version > 0 then
                local playerVer = tonumber(playerData.status.last_deploy_version) or 0
                if playerVer < deployCfg.version then
                    local targetMap = deployCfg.target_map or ""
                    if targetMap ~= "" and DataManager.maps[targetMap] then
                        playerData.status.current_map = targetMap
                        print("[LoginUI] 部署迁移: v" .. playerVer .. " -> v" .. deployCfg.version .. " 传送至【" .. targetMap .. "】")
                    end
                    playerData.status.last_deploy_version = tostring(deployCfg.version)
                    needSave = true
                end
            end

            -- 容错：如果玩家当前地图在系统数据中不存在，自动回退到有效地图
            local curMap = playerData.status.current_map or ""
            if curMap == "" or not DataManager.maps[curMap] then
                local fallbackMap = nil
                -- 优先选 deploy 目标地图
                if deployCfg and deployCfg.target_map and deployCfg.target_map ~= "" and DataManager.maps[deployCfg.target_map] then
                    fallbackMap = deployCfg.target_map
                end
                -- 其次选新手村
                if not fallbackMap and DataManager.maps["新手村"] then
                    fallbackMap = "新手村"
                end
                -- 最后取第一个可用地图
                if not fallbackMap then
                    for name, _ in pairs(DataManager.maps) do
                        fallbackMap = name
                        break
                    end
                end
                if fallbackMap then
                    print("[LoginUI] 当前地图【" .. curMap .. "】不存在，自动回退到【" .. fallbackMap .. "】")
                    playerData.status.current_map = fallbackMap
                    needSave = true
                end
            end

            if needSave then
                DataManager.SaveToCloud(playerData)
            end

            print("[LoginUI] 登录成功!")
            msgLabel_:SetText("")
            SwitchState("game")
        end, username)
    end)
end

--- 执行注册
function LoginUI.DoRegister()
    local username = usernameField_:GetValue()
    local password = passwordField_:GetValue()

    if not username or username == "" then
        msgLabel_:SetText("请输入账号")
        return
    end
    if not password or password == "" then
        msgLabel_:SetText("请输入密码")
        return
    end
    if #username < 2 then
        msgLabel_:SetText("账号至少2个字符")
        return
    end
    if #password < 3 then
        msgLabel_:SetText("密码至少3个字符")
        return
    end

    print("[LoginUI] 注册新账号: " .. username)
    msgLabel_:SetText("正在检查...")

    -- 从集中式账号配置检查是否已存在
    DataManager.CheckAccountExists(username, function(exists)
        if exists then
            msgLabel_:SetText("账号「" .. username .. "」已存在，请直接登录")
        else
            -- 可以注册，进入角色创建
            DataManager.currentAccount = username
            DataManager.currentPassword = password
            msgLabel_:SetText("")
            SwitchState("create_char")
        end
    end)
end

return LoginUI
