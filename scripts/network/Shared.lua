---------------------------------------------------
-- Shared.lua - 客户端/服务端共享事件定义
---------------------------------------------------
local Shared = {}

-- 所有远程事件名称
Shared.EVENTS = {
    CLIENT_READY = "ClientReady",
    CLOUD_GET = "CloudGet",
    CLOUD_GET_RESULT = "CloudGetResult",
    CLOUD_SET = "CloudSet",
    CLOUD_SET_RESULT = "CloudSetResult",
    CLOUD_BATCH_GET = "CloudBatchGet",
    CLOUD_BATCH_GET_RESULT = "CloudBatchGetResult",
    CLOUD_BATCH_SET = "CloudBatchSet",
    CLOUD_BATCH_SET_RESULT = "CloudBatchSetResult",


}

--- 注册所有远程事件（客户端和服务端都必须调用）
function Shared.RegisterEvents()
    for _, eventName in pairs(Shared.EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 远程事件已注册")
end

return Shared
