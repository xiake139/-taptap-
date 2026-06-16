---------------------------------------------------
-- Server.lua - 服务端数据代理
-- 接收客户端远程事件，用 serverCloud 读写共享数据
---------------------------------------------------
local Shared = require("network.Shared")
local EVENTS = Shared.EVENTS
local Server = {}

-- 共享 UID（所有数据存在此 uid 下，所有客户端共享）
-- serverCloud 要求 uid 必须是正整数（≥1），0 无效！
local SHARED_UID = 1

-- WebSocket 安全分片阈值
local MAX_CHUNK = 60000

-- 分片接收缓冲区 { [reqId] = { chunks={}, received=N, total=N, key=string } }
local chunkBuffers_ = {}

--- 将任意 key（含中文/特殊字符）编码为 serverCloud 兼容的 ASCII key
--- serverCloud 只接受 [A-Za-z0-9._-] 字符的 key
---@param raw string 原始 key，如 "系统配置/maps.ini"
---@return string 编码后的 key，如 "E7B3BBE7BB9FE9858DE7BDAE_maps.ini"
local function encodeKey(raw)
    -- 将非 ASCII 安全字符逐字节转为十六进制
    return (raw:gsub("[^%w._-]", function(c)
        return string.format("%02X", string.byte(c))
    end))
end

-- 连接 → userId 映射（用于日志）
local connectionUserIds_ = {}

function Server.Start()
    print("[Server] 服务端启动...")

    -- 注册远程事件
    Shared.RegisterEvents()

    -- 订阅客户端事件
    SubscribeToEvent(EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(EVENTS.CLOUD_GET, "HandleCloudGet")
    SubscribeToEvent(EVENTS.CLOUD_SET, "HandleCloudSet")
    SubscribeToEvent(EVENTS.CLOUD_BATCH_GET, "HandleCloudBatchGet")
    SubscribeToEvent(EVENTS.CLOUD_BATCH_SET, "HandleCloudBatchSet")

    print("[Server] 事件已订阅，等待客户端连接...")
end

--- 客户端连接就绪
function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local userId = connection.identity["user_id"]:GetInt64()
    local connKey = tostring(connection)
    connectionUserIds_[connKey] = userId
    print("[Server] 客户端就绪, userId=" .. tostring(userId))
end

--- 处理单 key 读取请求
function HandleCloudGet(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local reqId = eventData["ReqId"]:GetString()
    local key = eventData["Key"]:GetString()

    local encodedKey = encodeKey(key)
    print("[Server] CloudGet key=" .. key .. " encoded=" .. encodedKey .. " reqId=" .. reqId)

    serverCloud:Get(SHARED_UID, encodedKey, {
        ok = function(scores, iscores, sscores)
            local value = ""
            if scores and scores[encodedKey] ~= nil then
                -- scores[encodedKey] 是存入时的 table {v = "..."}, 提取 .v
                local stored = scores[encodedKey]
                if type(stored) == "table" and stored.v ~= nil then
                    value = tostring(stored.v)
                elseif type(stored) == "string" then
                    value = stored
                else
                    value = tostring(stored)
                end
            end

            -- 分片发送大 value
            local dataLen = #value
            if dataLen <= MAX_CHUNK then
                local resp = VariantMap()
                resp["ReqId"] = Variant(reqId)
                resp["Key"] = Variant(key)
                resp["Value"] = Variant(value)
                resp["Success"] = Variant(true)
                resp["ChunkIndex"] = Variant(1)
                resp["ChunkTotal"] = Variant(1)
                connection:SendRemoteEvent(EVENTS.CLOUD_GET_RESULT, true, resp)
            else
                local chunkTotal = math.ceil(dataLen / MAX_CHUNK)
                for ci = 1, chunkTotal do
                    local startPos = (ci - 1) * MAX_CHUNK + 1
                    local endPos = math.min(ci * MAX_CHUNK, dataLen)
                    local chunk = value:sub(startPos, endPos)
                    local resp = VariantMap()
                    resp["ReqId"] = Variant(reqId)
                    resp["Key"] = Variant(key)
                    resp["Value"] = Variant(chunk)
                    resp["Success"] = Variant(true)
                    resp["ChunkIndex"] = Variant(ci)
                    resp["ChunkTotal"] = Variant(chunkTotal)
                    connection:SendRemoteEvent(EVENTS.CLOUD_GET_RESULT, true, resp)
                end
            end
        end,
        error = function(code, reason)
            print("[Server] CloudGet 失败: " .. tostring(reason))
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Key"] = Variant(key)
            resp["Value"] = Variant("")
            resp["Success"] = Variant(false)
            resp["Error"] = Variant(tostring(reason))
            connection:SendRemoteEvent(EVENTS.CLOUD_GET_RESULT, true, resp)
        end,
    })
end

--- 处理单 key 写入请求（支持分片接收）
function HandleCloudSet(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local reqId = eventData["ReqId"]:GetString()
    local key = eventData["Key"]:GetString()
    local chunkData = eventData["Value"]:GetString()
    local chunkIndex = eventData["ChunkIndex"]:GetInt()
    local chunkTotal = eventData["ChunkTotal"]:GetInt()

    -- 分片重组
    local value
    if chunkTotal <= 1 then
        value = chunkData
    else
        if not chunkBuffers_[reqId] then
            chunkBuffers_[reqId] = { chunks = {}, received = 0, total = chunkTotal, key = key }
        end
        local buf = chunkBuffers_[reqId]
        buf.chunks[chunkIndex] = chunkData
        buf.received = buf.received + 1
        if buf.received < buf.total then
            return -- 等待更多分片
        end
        -- 所有分片到齐，拼接
        local parts = {}
        for i = 1, buf.total do
            parts[i] = buf.chunks[i] or ""
        end
        value = table.concat(parts)
        chunkBuffers_[reqId] = nil
    end

    local encodedKey = encodeKey(key)
    local valueLen = #value
    print("[Server] CloudSet key=" .. key .. " encoded=" .. encodedKey .. " reqId=" .. reqId .. " len=" .. valueLen)

    -- 值大小保护：超过 512KB 拒绝写入，避免后端崩溃
    local MAX_VALUE_SIZE = 512 * 1024  -- 512KB
    if valueLen > MAX_VALUE_SIZE then
        print("[Server] CloudSet 拒绝: 值过大 (" .. valueLen .. " > " .. MAX_VALUE_SIZE .. ") key=" .. key)
        local resp = VariantMap()
        resp["ReqId"] = Variant(reqId)
        resp["Success"] = Variant(false)
        resp["Error"] = Variant("值过大(" .. valueLen .. "字节)，超过512KB上限，请减少数据量")
        connection:SendRemoteEvent(EVENTS.CLOUD_SET_RESULT, true, resp)
        return
    end

    -- serverCloud:Set 的 value 必须是 table，用 {v=string} 包装
    serverCloud:Set(SHARED_UID, encodedKey, {v = value}, {
        ok = function()
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Success"] = Variant(true)
            connection:SendRemoteEvent(EVENTS.CLOUD_SET_RESULT, true, resp)


        end,
        error = function(code, reason)
            print("[Server] CloudSet 失败: " .. tostring(reason))
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Success"] = Variant(false)
            resp["Error"] = Variant(tostring(reason))
            connection:SendRemoteEvent(EVENTS.CLOUD_SET_RESULT, true, resp)
        end,
    })
end

--- 处理批量读取请求
--- 客户端发送 Keys 为逗号分隔的 key 列表
function HandleCloudBatchGet(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local reqId = eventData["ReqId"]:GetString()
    local keysStr = eventData["Keys"]:GetString()

    -- 解析逗号分隔的 key 列表
    local keys = {}
    for k in keysStr:gmatch("[^,]+") do
        table.insert(keys, k)
    end

    print("[Server] CloudBatchGet reqId=" .. reqId .. " keys=" .. #keys)

    if #keys == 0 then
        local resp = VariantMap()
        resp["ReqId"] = Variant(reqId)
        resp["Success"] = Variant(true)
        resp["Data"] = Variant("")
        connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_GET_RESULT, true, resp)
        return
    end

    -- 建立原始key与编码key的映射
    local encodedKeys = {}
    local encodedToRaw = {}
    for _, key in ipairs(keys) do
        local ek = encodeKey(key)
        table.insert(encodedKeys, ek)
        encodedToRaw[ek] = key
    end

    local batch = serverCloud:BatchGet(SHARED_UID)
    for _, ek in ipairs(encodedKeys) do
        batch:Key(ek)
    end
    batch:Fetch({
        ok = function(scores, iscores, sscores)
            -- 将结果序列化为简单格式: key\1value\2key\1value\2...
            -- 使用 \1 分隔 key 和 value，\2 分隔各对
            -- 注意：返回给客户端的 key 是原始中文 key
            local parts = {}
            for _, ek in ipairs(encodedKeys) do
                local val = ""
                if scores and scores[ek] ~= nil then
                    local stored = scores[ek]
                    if type(stored) == "table" and stored.v ~= nil then
                        val = tostring(stored.v)
                    elseif type(stored) == "string" then
                        val = stored
                    else
                        val = tostring(stored)
                    end
                end
                local rawKey = encodedToRaw[ek] or ek
                table.insert(parts, rawKey .. "\1" .. val)
            end
            local encoded = table.concat(parts, "\2")

            -- 分片发送：WebSocket 上限 65535，安全阈值 60000
            local MAX_CHUNK = 60000
            local dataLen = #encoded
            if dataLen <= MAX_CHUNK then
                -- 单条发送（无需分片）
                local resp = VariantMap()
                resp["ReqId"] = Variant(reqId)
                resp["Success"] = Variant(true)
                resp["Data"] = Variant(encoded)
                resp["ChunkIndex"] = Variant(1)
                resp["ChunkTotal"] = Variant(1)
                connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_GET_RESULT, true, resp)
            else
                -- 分片发送
                local chunkTotal = math.ceil(dataLen / MAX_CHUNK)
                for ci = 1, chunkTotal do
                    local startPos = (ci - 1) * MAX_CHUNK + 1
                    local endPos = math.min(ci * MAX_CHUNK, dataLen)
                    local chunk = encoded:sub(startPos, endPos)
                    local resp = VariantMap()
                    resp["ReqId"] = Variant(reqId)
                    resp["Success"] = Variant(true)
                    resp["Data"] = Variant(chunk)
                    resp["ChunkIndex"] = Variant(ci)
                    resp["ChunkTotal"] = Variant(chunkTotal)
                    connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_GET_RESULT, true, resp)
                end
            end
        end,
        error = function(code, reason)
            print("[Server] CloudBatchGet 失败: " .. tostring(reason))
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Success"] = Variant(false)
            resp["Error"] = Variant(tostring(reason))
            resp["Data"] = Variant("")
            connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_GET_RESULT, true, resp)
        end,
    })
end

--- 处理批量写入请求（支持分片接收）
--- 客户端发送 Data 为序列化格式: key\1value\2key\1value\2...
function HandleCloudBatchSet(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local reqId = eventData["ReqId"]:GetString()
    local chunkData = eventData["Data"]:GetString()
    local chunkIndex = eventData["ChunkIndex"]:GetInt()
    local chunkTotal = eventData["ChunkTotal"]:GetInt()

    -- 分片重组
    local dataStr
    if chunkTotal <= 1 then
        dataStr = chunkData
    else
        if not chunkBuffers_[reqId] then
            chunkBuffers_[reqId] = { chunks = {}, received = 0, total = chunkTotal }
        end
        local buf = chunkBuffers_[reqId]
        buf.chunks[chunkIndex] = chunkData
        buf.received = buf.received + 1
        if buf.received < buf.total then
            return -- 等待更多分片
        end
        local parts = {}
        for i = 1, buf.total do
            parts[i] = buf.chunks[i] or ""
        end
        dataStr = table.concat(parts)
        chunkBuffers_[reqId] = nil
    end

    -- 解析数据
    local pairs_list = {}
    for part in dataStr:gmatch("[^\2]+") do
        local sep = part:find("\1")
        if sep then
            local key = part:sub(1, sep - 1)
            local val = part:sub(sep + 1)
            table.insert(pairs_list, { key = key, value = val })
        end
    end

    print("[Server] CloudBatchSet reqId=" .. reqId .. " pairs=" .. #pairs_list)

    if #pairs_list == 0 then
        local resp = VariantMap()
        resp["ReqId"] = Variant(reqId)
        resp["Success"] = Variant(true)
        connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_SET_RESULT, true, resp)
        return
    end

    local batch = serverCloud:BatchSet(SHARED_UID)
    for _, p in ipairs(pairs_list) do
        -- serverCloud BatchSet:Set 的 value 必须是 table，key 需编码
        batch:Set(encodeKey(p.key), {v = p.value})
    end
    batch:Save("客户端批量写入", {
        ok = function()
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Success"] = Variant(true)
            connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_SET_RESULT, true, resp)
        end,
        error = function(code, reason)
            print("[Server] CloudBatchSet 失败: " .. tostring(reason))
            local resp = VariantMap()
            resp["ReqId"] = Variant(reqId)
            resp["Success"] = Variant(false)
            resp["Error"] = Variant(tostring(reason))
            connection:SendRemoteEvent(EVENTS.CLOUD_BATCH_SET_RESULT, true, resp)
        end,
    })
end

return Server
