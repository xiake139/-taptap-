---------------------------------------------------
-- CloudProxy.lua - 客户端云存储代理
-- 提供与 clientCloud 完全相同的 API 接口
-- 内部通过远程事件与服务端通信，实现数据共享
---------------------------------------------------
local Shared = require("network.Shared")
local EVENTS = Shared.EVENTS

local CloudProxy = {}

-- 请求 ID 计数器（确保唯一）
local reqIdCounter_ = 0

-- 待处理回调 { [reqId] = {ok=fn, error=fn} }
local pendingCallbacks_ = {}

-- 是否已初始化
local initialized_ = false

--- 生成唯一请求 ID
local function nextReqId()
    reqIdCounter_ = reqIdCounter_ + 1
    return "r" .. reqIdCounter_ .. "_" .. tostring(os.time())
end

-- 连接就绪标志
local serverReady_ = false

-- 等待队列（连接就绪前的请求暂存在这里）
local pendingQueue_ = {}

--- 初始化 CloudProxy（客户端启动时调用）
function CloudProxy.Init()
    if initialized_ then return end
    initialized_ = true

    -- 注册远程事件
    Shared.RegisterEvents()

    -- 订阅服务端响应事件
    SubscribeToEvent(EVENTS.CLOUD_GET_RESULT, "HandleCloudGetResult")
    SubscribeToEvent(EVENTS.CLOUD_SET_RESULT, "HandleCloudSetResult")
    SubscribeToEvent(EVENTS.CLOUD_BATCH_GET_RESULT, "HandleCloudBatchGetResult")
    SubscribeToEvent(EVENTS.CLOUD_BATCH_SET_RESULT, "HandleCloudBatchSetResult")

    -- 订阅连接成功事件（普通模式）
    SubscribeToEvent("ServerConnected", "HandleServerConnected")
    -- 订阅 ServerReady 事件（后台匹配模式：background_match=true 时仅此事件触发）
    SubscribeToEvent("ServerReady", "HandleCloudProxyServerReady")

    -- 如果连接已经建立，立即发送
    local serverConn = network:GetServerConnection()
    if serverConn then
        serverReady_ = true
        serverConn:SendRemoteEvent(EVENTS.CLIENT_READY, true)
        print("[CloudProxy] 连接已存在，立即发送 ClientReady")
        -- 连接已存在时也要 flush（可能 LoadSystemData 已经排队）
        CloudProxy.FlushPendingQueue()
    else
        print("[CloudProxy] 等待服务器连接...")
    end

    print("[CloudProxy] 初始化完成")
end

--- 服务器连接成功后发送 ClientReady（普通模式触发）
function HandleServerConnected(eventType, eventData)
    if serverReady_ then return end  -- 避免重复处理
    serverReady_ = true
    local serverConn = network:GetServerConnection()
    if serverConn then
        serverConn:SendRemoteEvent(EVENTS.CLIENT_READY, true)
        print("[CloudProxy] ServerConnected - 已发送 ClientReady")
    end
    -- 处理等待队列中的请求
    CloudProxy.FlushPendingQueue()
end

--- 后台匹配模式下服务器就绪（background_match=true 时触发）
function HandleCloudProxyServerReady(eventType, eventData)
    if serverReady_ then return end  -- 避免与 ServerConnected 重复
    serverReady_ = true
    local serverConn = network:GetServerConnection()
    if serverConn then
        serverConn:SendRemoteEvent(EVENTS.CLIENT_READY, true)
        print("[CloudProxy] ServerReady(后台匹配) - 已发送 ClientReady")
    else
        print("[CloudProxy] ServerReady 触发但连接为空，等待重试...")
    end
    -- 处理等待队列中的请求
    CloudProxy.FlushPendingQueue()
end

--- 获取服务端连接
---@return Connection|nil
local function getServerConn()
    return network:GetServerConnection()
end

--- 处理等待队列（连接就绪后调用）
function CloudProxy.FlushPendingQueue()
    if #pendingQueue_ == 0 then return end
    print("[CloudProxy] 处理等待队列，共 " .. #pendingQueue_ .. " 个请求")
    local queue = pendingQueue_
    pendingQueue_ = {}
    for _, req in ipairs(queue) do
        if req.type == "get" then
            CloudProxy:Get(req.key, req.events)
        elseif req.type == "set" then
            CloudProxy:Set(req.key, req.value, req.events)
        elseif req.type == "batchget" then
            local b = CloudProxy:BatchGet()
            for _, k in ipairs(req.keys) do b:Key(k) end
            b:Fetch(req.events)
        elseif req.type == "batchset" then
            local b = CloudProxy:BatchSet()
            for _, p in ipairs(req.pairs) do b:Set(p.key, p.value) end
            b:Save(req.desc, req.events)
        end
    end
end

-- =============== 对外 API（与 clientCloud 接口一致） ===============

--- 单 key 读取
---@param key string
---@param events table {ok=function(values, iscores), error=function(code, reason)}
function CloudProxy:Get(key, events)
    local serverConn = getServerConn()
    if not serverConn then
        -- 连接未就绪，放入队列等待
        if not serverReady_ then
            table.insert(pendingQueue_, { type = "get", key = key, events = events })
            print("[CloudProxy] Get 排队等待连接: " .. key)
            return
        end
        print("[CloudProxy] 无服务器连接")
        if events and events.error then
            events.error(-1, "无服务器连接")
        end
        return
    end

    local reqId = nextReqId()
    pendingCallbacks_[reqId] = {
        type = "get",
        key = key,
        ok = events and events.ok,
        error = events and events.error,
    }

    local data = VariantMap()
    data["ReqId"] = Variant(reqId)
    data["Key"] = Variant(key)
    serverConn:SendRemoteEvent(EVENTS.CLOUD_GET, true, data)
end

--- WebSocket 安全分片阈值
local MAX_CHUNK = 60000

--- 单 key 写入（支持分片：大 value 自动拆分多条消息）
---@param key string
---@param value string
---@param events table {ok=function(), error=function(code, reason)}
function CloudProxy:Set(key, value, events)
    local serverConn = getServerConn()
    if not serverConn then
        -- 连接未就绪，放入队列等待
        if not serverReady_ then
            table.insert(pendingQueue_, { type = "set", key = key, value = value, events = events })
            print("[CloudProxy] Set 排队等待连接: " .. key)
            return
        end
        print("[CloudProxy] 无服务器连接")
        if events and events.error then
            events.error(-1, "无服务器连接")
        end
        return
    end

    local reqId = nextReqId()
    pendingCallbacks_[reqId] = {
        type = "set",
        ok = events and events.ok,
        error = events and events.error,
    }

    local valStr = tostring(value)
    local dataLen = #valStr

    if dataLen <= MAX_CHUNK then
        -- 单条发送
        local data = VariantMap()
        data["ReqId"] = Variant(reqId)
        data["Key"] = Variant(key)
        data["Value"] = Variant(valStr)
        data["ChunkIndex"] = Variant(1)
        data["ChunkTotal"] = Variant(1)
        serverConn:SendRemoteEvent(EVENTS.CLOUD_SET, true, data)
    else
        -- 分片发送
        local chunkTotal = math.ceil(dataLen / MAX_CHUNK)
        for ci = 1, chunkTotal do
            local startPos = (ci - 1) * MAX_CHUNK + 1
            local endPos = math.min(ci * MAX_CHUNK, dataLen)
            local chunk = valStr:sub(startPos, endPos)
            local data = VariantMap()
            data["ReqId"] = Variant(reqId)
            data["Key"] = Variant(key)
            data["Value"] = Variant(chunk)
            data["ChunkIndex"] = Variant(ci)
            data["ChunkTotal"] = Variant(chunkTotal)
            serverConn:SendRemoteEvent(EVENTS.CLOUD_SET, true, data)
        end
    end
end

-- =============== BatchGet 构建器 ===============

local BatchGetBuilder = {}
BatchGetBuilder.__index = BatchGetBuilder

function BatchGetBuilder:Key(key)
    table.insert(self.keys_, key)
    return self
end

function BatchGetBuilder:Fetch(events)
    local serverConn = getServerConn()
    if not serverConn then
        -- 连接未就绪，放入队列等待
        if not serverReady_ then
            table.insert(pendingQueue_, { type = "batchget", keys = self.keys_, events = events })
            print("[CloudProxy] BatchGet 排队等待连接")
            return
        end
        print("[CloudProxy] BatchGet 无服务器连接")
        if events and events.error then
            events.error(-1, "无服务器连接")
        end
        return
    end

    local reqId = nextReqId()
    pendingCallbacks_[reqId] = {
        type = "batchget",
        keys = self.keys_,
        ok = events and events.ok,
        error = events and events.error,
    }

    local keysStr = table.concat(self.keys_, ",")
    local data = VariantMap()
    data["ReqId"] = Variant(reqId)
    data["Keys"] = Variant(keysStr)
    serverConn:SendRemoteEvent(EVENTS.CLOUD_BATCH_GET, true, data)
end

--- 创建 BatchGet 构建器（兼容 clientCloud:BatchGet() 接口）
function CloudProxy:BatchGet()
    local builder = setmetatable({ keys_ = {} }, BatchGetBuilder)
    return builder
end

-- =============== BatchSet 构建器 ===============

local BatchSetBuilder = {}
BatchSetBuilder.__index = BatchSetBuilder

function BatchSetBuilder:Set(key, value)
    table.insert(self.pairs_, { key = key, value = tostring(value) })
    return self
end

function BatchSetBuilder:Save(desc, events)
    local serverConn = getServerConn()
    if not serverConn then
        -- 连接未就绪，放入队列等待
        if not serverReady_ then
            table.insert(pendingQueue_, { type = "batchset", pairs = self.pairs_, desc = desc or "", events = events })
            print("[CloudProxy] BatchSet 排队等待连接")
            return
        end
        print("[CloudProxy] BatchSet 无服务器连接")
        if events and events.error then
            events.error(-1, "无服务器连接")
        end
        return
    end

    local reqId = nextReqId()
    pendingCallbacks_[reqId] = {
        type = "batchset",
        ok = events and events.ok,
        error = events and events.error,
    }

    -- 编码: key\1value\2key\1value\2...
    local parts = {}
    for _, p in ipairs(self.pairs_) do
        table.insert(parts, p.key .. "\1" .. p.value)
    end
    local encoded = table.concat(parts, "\2")

    local dataLen = #encoded
    if dataLen <= MAX_CHUNK then
        -- 单条发送
        local data = VariantMap()
        data["ReqId"] = Variant(reqId)
        data["Data"] = Variant(encoded)
        data["ChunkIndex"] = Variant(1)
        data["ChunkTotal"] = Variant(1)
        serverConn:SendRemoteEvent(EVENTS.CLOUD_BATCH_SET, true, data)
    else
        -- 分片发送
        local chunkTotal = math.ceil(dataLen / MAX_CHUNK)
        for ci = 1, chunkTotal do
            local startPos = (ci - 1) * MAX_CHUNK + 1
            local endPos = math.min(ci * MAX_CHUNK, dataLen)
            local chunk = encoded:sub(startPos, endPos)
            local data = VariantMap()
            data["ReqId"] = Variant(reqId)
            data["Data"] = Variant(chunk)
            data["ChunkIndex"] = Variant(ci)
            data["ChunkTotal"] = Variant(chunkTotal)
            serverConn:SendRemoteEvent(EVENTS.CLOUD_BATCH_SET, true, data)
        end
    end
end

--- 创建 BatchSet 构建器（兼容 clientCloud:BatchSet() 接口）
function CloudProxy:BatchSet()
    local builder = setmetatable({ pairs_ = {} }, BatchSetBuilder)
    return builder
end

-- =============== 响应处理（全局函数，由事件系统调用） ===============

-- 分片缓冲区（Get 和 BatchGet 共用）: reqId -> { chunks={}, received=0, total=N }
local chunkBuffers_ = {}

function HandleCloudGetResult(eventType, eventData)
    local reqId = eventData["ReqId"]:GetString()
    local cb = pendingCallbacks_[reqId]
    if not cb then return end

    local success = eventData["Success"]:GetBool()
    if not success then
        pendingCallbacks_[reqId] = nil
        chunkBuffers_[reqId] = nil
        local errMsg = eventData["Error"]:GetString()
        if cb.error then cb.error(-1, errMsg) end
        return
    end

    local key = eventData["Key"]:GetString()
    local chunkData = eventData["Value"]:GetString()
    local chunkIndex = eventData["ChunkIndex"]:GetInt()
    local chunkTotal = eventData["ChunkTotal"]:GetInt()

    -- 无分片或旧协议
    if chunkTotal <= 1 then
        pendingCallbacks_[reqId] = nil
        chunkBuffers_[reqId] = nil
        local values = { [key] = chunkData }
        if cb.ok then cb.ok(values, {}) end
        return
    end

    -- 分片累积
    if not chunkBuffers_[reqId] then
        chunkBuffers_[reqId] = { chunks = {}, received = 0, total = chunkTotal, key = key }
    end
    local buf = chunkBuffers_[reqId]
    buf.chunks[chunkIndex] = chunkData
    buf.received = buf.received + 1

    if buf.received >= buf.total then
        pendingCallbacks_[reqId] = nil
        local parts = {}
        for i = 1, buf.total do
            parts[i] = buf.chunks[i] or ""
        end
        chunkBuffers_[reqId] = nil
        local value = table.concat(parts)
        local values = { [buf.key] = value }
        if cb.ok then cb.ok(values, {}) end
    end
end

function HandleCloudSetResult(eventType, eventData)
    local reqId = eventData["ReqId"]:GetString()
    local cb = pendingCallbacks_[reqId]
    if not cb then return end
    pendingCallbacks_[reqId] = nil

    local success = eventData["Success"]:GetBool()
    if success then
        if cb.ok then cb.ok() end
    else
        local errMsg = eventData["Error"]:GetString()
        if cb.error then cb.error(-1, errMsg) end
    end
end

function HandleCloudBatchGetResult(eventType, eventData)
    local reqId = eventData["ReqId"]:GetString()
    local cb = pendingCallbacks_[reqId]
    if not cb then return end

    local success = eventData["Success"]:GetBool()
    if not success then
        pendingCallbacks_[reqId] = nil
        chunkBuffers_[reqId] = nil
        local errMsg = eventData["Error"]:GetString()
        if cb.error then cb.error(-1, errMsg) end
        return
    end

    local chunkIndex = eventData["ChunkIndex"]:GetInt()
    local chunkTotal = eventData["ChunkTotal"]:GetInt()
    local data = eventData["Data"]:GetString()

    -- 无分片或旧协议（没有 ChunkTotal 字段时默认 0）
    if chunkTotal <= 1 then
        pendingCallbacks_[reqId] = nil
        chunkBuffers_[reqId] = nil
        local encoded = data
        local values = {}
        if encoded ~= "" then
            for part in encoded:gmatch("[^\2]+") do
                local sep = part:find("\1")
                if sep then
                    local key = part:sub(1, sep - 1)
                    local val = part:sub(sep + 1)
                    values[key] = val
                end
            end
        end
        if cb.ok then cb.ok(values, {}) end
        return
    end

    -- 分片累积
    if not chunkBuffers_[reqId] then
        chunkBuffers_[reqId] = { chunks = {}, received = 0, total = chunkTotal }
    end
    local buf = chunkBuffers_[reqId]
    buf.chunks[chunkIndex] = data
    buf.received = buf.received + 1

    -- 所有分片到齐，拼接并处理
    if buf.received >= buf.total then
        pendingCallbacks_[reqId] = nil
        local parts = {}
        for i = 1, buf.total do
            parts[i] = buf.chunks[i] or ""
        end
        chunkBuffers_[reqId] = nil

        local encoded = table.concat(parts)
        local values = {}
        if encoded ~= "" then
            for part in encoded:gmatch("[^\2]+") do
                local sep = part:find("\1")
                if sep then
                    local key = part:sub(1, sep - 1)
                    local val = part:sub(sep + 1)
                    values[key] = val
                end
            end
        end
        if cb.ok then cb.ok(values, {}) end
    end
end

function HandleCloudBatchSetResult(eventType, eventData)
    local reqId = eventData["ReqId"]:GetString()
    local cb = pendingCallbacks_[reqId]
    if not cb then return end
    pendingCallbacks_[reqId] = nil

    local success = eventData["Success"]:GetBool()
    if success then
        if cb.ok then cb.ok() end
    else
        local errMsg = eventData["Error"]:GetString()
        if cb.error then cb.error(-1, errMsg) end
    end
end

return CloudProxy
