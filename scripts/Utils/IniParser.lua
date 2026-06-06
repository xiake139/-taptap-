---------------------------------------------------
-- IniParser.lua - INI 配置文件解析器/写入器
-- 支持 [section] key=value 格式
-- 支持注释（; 和 # 开头）
---------------------------------------------------
local IniParser = {}

--- 解析 INI 格式字符串，返回 table
---@param content string INI 格式内容
---@return table sections { section_name = { key = value, ... }, ... }
function IniParser.Parse(content)
    local sections = {}
    local currentSection = "default"
    sections[currentSection] = {}

    for line in content:gmatch("([^\r\n]*)\r?\n?") do
        -- 去除首尾空白
        line = line:match("^%s*(.-)%s*$")

        if line == "" or line:sub(1, 1) == ";" or line:sub(1, 1) == "#" then
            -- 空行或注释，跳过
        elseif line:match("^%[(.+)%]$") then
            -- Section 头
            currentSection = line:match("^%[(.+)%]$")
            if not sections[currentSection] then
                sections[currentSection] = {}
            end
        else
            -- key=value
            local key, value = line:match("^([^=]+)=(.*)$")
            if key and value then
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                -- 尝试转换数值
                local numValue = tonumber(value)
                if numValue then
                    sections[currentSection][key] = numValue
                elseif value == "true" then
                    sections[currentSection][key] = true
                elseif value == "false" then
                    sections[currentSection][key] = false
                else
                    sections[currentSection][key] = value
                end
            end
        end
    end

    return sections
end

--- 将 table 序列化为 INI 格式字符串
---@param sections table { section_name = { key = value, ... }, ... }
---@return string INI 格式内容
function IniParser.Serialize(sections)
    local lines = {}

    for section, kvs in pairs(sections) do
        table.insert(lines, "[" .. section .. "]")
        for key, value in pairs(kvs) do
            table.insert(lines, key .. "=" .. tostring(value))
        end
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

--- 从文件加载 INI 配置
---@param filePath string 文件路径（相对于资源目录或沙箱目录）
---@return table|nil sections 解析结果，文件不存在返回 nil
function IniParser.LoadFile(filePath)
    -- 先尝试用资源系统读取（assets/目录）
    local resourceFile = cache:GetFile(filePath)
    if resourceFile then
        local content = resourceFile:ReadString()
        resourceFile:Close()
        if content and content ~= "" then
            return IniParser.Parse(content)
        end
    end

    -- 再尝试用沙箱文件系统读取（玩家存档）
    if fileSystem:FileExists(filePath) then
        local file = File(filePath, FILE_READ)
        if file:IsOpen() then
            local content = file:ReadString()
            file:Close()
            if content and content ~= "" then
                return IniParser.Parse(content)
            end
        end
    end

    return nil
end

--- 保存 INI 配置到沙箱文件
---@param filePath string 文件路径（相对于沙箱目录）
---@param sections table { section_name = { key = value, ... }, ... }
---@return boolean success 是否成功
function IniParser.SaveFile(filePath, sections)
    local content = IniParser.Serialize(sections)
    local file = File(filePath, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(content)
        file:Close()
        return true
    end
    return false
end

--- 获取指定 section 中的值，支持默认值
---@param sections table 解析后的 INI 数据
---@param section string section 名
---@param key string 键名
---@param default any 默认值
---@return any value
function IniParser.Get(sections, section, key, default)
    if sections and sections[section] and sections[section][key] ~= nil then
        return sections[section][key]
    end
    return default
end

--- 解析列表值（用逗号分隔的字符串 → table）
---@param value string "item1,item2,item3"
---@return table list {"item1", "item2", "item3"}
function IniParser.ParseList(value)
    if not value or value == "" then
        return {}
    end
    local list = {}
    for item in value:gmatch("([^,]+)") do
        item = item:match("^%s*(.-)%s*$")
        if item ~= "" then
            table.insert(list, item)
        end
    end
    return list
end

return IniParser
