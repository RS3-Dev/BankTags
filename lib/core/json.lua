-- Encode and decode the JSON subset used by tag and saved-query persistence

local Json = {}

-- Escape characters that would break a JSON string
local function escape(value)
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, "\"", "\\\"")
    value = string.gsub(value, "\b", "\\b")
    value = string.gsub(value, "\f", "\\f")
    value = string.gsub(value, "\n", "\\n")
    value = string.gsub(value, "\r", "\\r")
    value = string.gsub(value, "\t", "\\t")
    return value
end

-- Recognize consecutive numeric keys so tables encode as arrays or objects correctly
local function isArray(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    for index = 1, count do if value[index] == nil then return false end end
    return true
end

-- Encode supported Lua values as JSON with sorted object keys
function Json.encode(value)
    local kind = type(value)
    if value == nil then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then return tostring(value) end
    if kind == "string" then return "\"" .. escape(value) .. "\"" end
    if kind ~= "table" then return "null" end
    local parts = {}
    if isArray(value) then
        for index = 1, #value do parts[#parts + 1] = Json.encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = Json.encode(key) .. ":" .. Json.encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Report malformed JSON with the byte position that failed
local function decodeError(index, message)
    error("invalid JSON at byte " .. tostring(index) .. ": " .. message)
end

-- Read one JSON value and reject extra content after it
function Json.decode(source)
    if type(source) ~= "string" then error("JSON source must be a string") end
    local index = 1
    local length = #source

    -- Advance past whitespace between JSON values and punctuation
    local function skipSpace()
        while index <= length and string.match(string.sub(source, index, index), "%s") do
            index = index + 1
        end
    end

    local parseValue
    -- Read a quoted string and decode its supported escape sequences
    local function parseString()
        index = index + 1
        local parts = {}
        while index <= length do
            local character = string.sub(source, index, index)
            if character == "\"" then
                index = index + 1
                return table.concat(parts)
            end
            if character == "\\" then
                local escaped = string.sub(source, index + 1, index + 1)
                local substitutions = {
                    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'
                }
                if substitutions[escaped] ~= nil then
                    parts[#parts + 1] = substitutions[escaped]
                    index = index + 2
                elseif escaped == "u" then
                    local code = tonumber(string.sub(source, index + 2, index + 5), 16)
                    if code == nil then decodeError(index, "bad unicode escape") end
                    if code < 128 then
                        parts[#parts + 1] = string.char(code)
                    else
                        parts[#parts + 1] = "?"
                    end
                    index = index + 6
                else
                    decodeError(index, "bad string escape")
                end
            else
                parts[#parts + 1] = character
                index = index + 1
            end
        end
        decodeError(index, "unterminated string")
    end

    -- Read comma-separated values until the closing array bracket
    local function parseArray()
        index = index + 1
        local result = {}
        skipSpace()
        if string.sub(source, index, index) == "]" then index = index + 1 return result end
        while true do
            result[#result + 1] = parseValue()
            skipSpace()
            local character = string.sub(source, index, index)
            if character == "]" then index = index + 1 return result end
            if character ~= "," then decodeError(index, "expected ',' or ']'") end
            index = index + 1
        end
    end

    -- Read quoted keys and values until the closing object brace
    local function parseObject()
        index = index + 1
        local result = {}
        skipSpace()
        if string.sub(source, index, index) == "}" then index = index + 1 return result end
        while true do
            skipSpace()
            if string.sub(source, index, index) ~= "\"" then
                decodeError(index, "expected object key")
            end
            local key = parseString()
            skipSpace()
            if string.sub(source, index, index) ~= ":" then decodeError(index, "expected ':'") end
            index = index + 1
            result[key] = parseValue()
            skipSpace()
            local character = string.sub(source, index, index)
            if character == "}" then index = index + 1 return result end
            if character ~= "," then decodeError(index, "expected ',' or '}'") end
            index = index + 1
        end
    end

    -- Choose the appropriate parser for the next JSON value
    function parseValue()
        skipSpace()
        local character = string.sub(source, index, index)
        if character == "\"" then return parseString() end
        if character == "{" then return parseObject() end
        if character == "[" then return parseArray() end
        local tail = string.sub(source, index)
        if string.sub(tail, 1, 4) == "true" then index = index + 4 return true end
        if string.sub(tail, 1, 5) == "false" then index = index + 5 return false end
        if string.sub(tail, 1, 4) == "null" then index = index + 4 return nil end
        local numberText = string.match(tail, "^-?%d+%.?%d*[eE]?[+-]?%d*")
        if numberText ~= nil and numberText ~= "" then
            index = index + #numberText
            return tonumber(numberText)
        end
        decodeError(index, "unexpected value")
    end

    local result = parseValue()
    skipSpace()
    if index <= length then decodeError(index, "trailing content") end
    return result
end

return Json
