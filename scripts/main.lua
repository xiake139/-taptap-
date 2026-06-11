---------------------------------------------------
-- main.lua - 创世修仙 主入口
-- 文字修仙游戏，基于 UrhoX UI 系统
-- 支持服务端/客户端模式（共享云存储）
---------------------------------------------------

-- 服务端模式：仅处理数据代理，无 UI
if IsServerMode() then
    print("[Main] ===== 服务端模式启动 =====")
    local Server = require("network.Server")
    function Start()
        Server.Start()
    end
    return
end

-- 客户端模式
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

-- 全局变量
---@type Widget
local uiRoot_ = nil

-- 游戏状态枚举
local GameState = {
    LOGIN = "login",
    CREATE_CHAR = "create_char",
    GAME = "game",
    ADMIN_LOGIN = "admin_login",
    ADMIN = "admin",
}
local currentState_ = GameState.LOGIN

-- UI 模块（延迟加载）
local LoginUI = nil
local CreateCharUI = nil
local GameUI = nil
local AdminUI = nil

function Start()
    graphics.windowTitle = "创世修仙"
    print("[Main] 游戏启动...")

    -- 初始化 UI
    InitUI()

    -- 如果是联网模式，初始化 CloudProxy
    if IsNetworkMode() then
        print("[Main] 检测到联网模式，初始化 CloudProxy...")
        local CloudProxy = require("network.CloudProxy")
        CloudProxy.Init()
        -- 将 CloudProxy 设置到 DataManager
        DataManager.SetCloudProvider(CloudProxy)

        -- 后台匹配模式：订阅 ServerReady 事件（服务器连接就绪后触发）
        SubscribeToEvent("ServerReady", "HandleServerReady")
    end

    -- 加载系统数据（异步，完成后显示登录界面）
    DataManager.LoadSystemData(function()
        ShowLogin()
    end)

    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("Update", "HandleUpdate")
end

--- 后台匹配模式下服务器连接就绪回调
function HandleServerReady(eventType, eventData)
    print("[Main] ServerReady - 服务器连接已就绪")
end

local buffCheckTimer_ = 0
local statusRefreshTimer_ = 0
local leaderboardRefreshTimer_ = 0
local LEADERBOARD_REFRESH_INTERVAL = 30  -- 排行榜每30秒自动刷新
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local GameUI = require("UI.GameUI")
    -- 每 5 秒检查一次 buff 过期
    buffCheckTimer_ = buffCheckTimer_ + dt
    if buffCheckTimer_ >= 5.0 then
        buffCheckTimer_ = 0
        local BagUI = require("UI.BagUI")
        BagUI.CleanExpiredBuffs()
    end
    -- 状态面板打开时每秒更新倒计时文本（不重建面板）
    if GameUI.currentPanel == "status" then
        statusRefreshTimer_ = statusRefreshTimer_ + dt
        if statusRefreshTimer_ >= 1.0 then
            statusRefreshTimer_ = 0
            local StatusUI = require("UI.StatusUI")
            StatusUI.UpdateTimers()
        end
    else
        statusRefreshTimer_ = 0
    end
    -- 排行榜面板打开时自动定时刷新
    if GameUI.currentPanel == "leaderboard" then
        leaderboardRefreshTimer_ = leaderboardRefreshTimer_ + dt
        if leaderboardRefreshTimer_ >= LEADERBOARD_REFRESH_INTERVAL then
            leaderboardRefreshTimer_ = 0
            DataManager.SyncLeaderboardScores(function()
                local src = GameUI.currentLeaderboardSource or "等级"
                GameUI.ShowLeaderboardDetail(src)
            end)
        end
    else
        leaderboardRefreshTimer_ = 0
    end
end

function Stop()
    UI.Shutdown()
end

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })


end

--- 切换游戏状态
---@param state string
function SwitchState(state)
    currentState_ = state
    if state == GameState.LOGIN then
        ShowLogin()
    elseif state == GameState.CREATE_CHAR then
        ShowCreateChar()
    elseif state == GameState.GAME then
        ShowGame()
    elseif state == GameState.ADMIN_LOGIN then
        ShowAdminLogin()
    elseif state == GameState.ADMIN then
        ShowAdmin()
    end
end

--- 显示登录界面
function ShowLogin()
    if not LoginUI then
        LoginUI = require("UI.LoginUI")
    end
    local root = LoginUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示角色创建界面
function ShowCreateChar()
    if not CreateCharUI then
        CreateCharUI = require("UI.CreateCharUI")
    end
    local root = CreateCharUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示主游戏界面
function ShowGame()
    if not GameUI then
        GameUI = require("UI.GameUI")
    end
    local root = GameUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示管理员登录界面
function ShowAdminLogin()
    if not AdminUI then
        AdminUI = require("UI.AdminUI")
    end
    local root = AdminUI.CreateLogin()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示管理员后台（由 AdminUI 内部调用 ShowDashboard）
function ShowAdmin()
    if not AdminUI then
        AdminUI = require("UI.AdminUI")
    end
    AdminUI.ShowDashboard()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- ESC 键处理
        if currentState_ == GameState.GAME and GameUI and GameUI.HandleEscape then
            GameUI.HandleEscape()
        end
    end
end
