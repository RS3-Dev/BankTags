-- Encode and decode the JSON subset tag saves and share codes use

local Json = {}

-- Keep empty JSON values without shifting array items
Json.null = {}

local ESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}
local MAX_DEPTH = 128

-- Escape quotes, slashes, and control characters
local function escape(value)
    -- Encode each character that cannot appear directly in JSON
    return (string.gsub(value, '[%z\1-\31\\"]', function(character)
        if character == '"' or character == '\\' then return '\\' .. character end
        return string.format('\\u%04x', string.byte(character))
    end))
end

-- Check whether a table encodes as a JSON array
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
    if value == nil or value == Json.null then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("JSON numbers must be finite")
        end
        return tostring(value)
    end
    if kind == "string" then return "\"" .. escape(value) .. "\"" end
    if kind ~= "table" then return "null" end
    local parts = {}
    if isArray(value) then
        for index = 1, #value do parts[#parts + 1] = Json.encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then error("JSON object keys must be strings") end
        keys[#keys + 1] = key
    end
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
    local index, depth = 1, 0
    local length = #source

    -- Advance past whitespace between JSON values and punctuation
    local function skipSpace()
        index = string.match(source, "[ \t\r\n]*()", index)
    end

    local parseValue
    -- Read four digits from a Unicode escape
    local function unicodeCode()
        local digits = string.sub(source, index + 2, index + 5)
        if #digits ~= 4 or string.find(digits, "[^%da-fA-F]") then
            decodeError(index, "bad unicode escape")
        end
        index = index + 6
        return tonumber(digits, 16)
    end

    -- Read a quoted string and its escapes
    local function parseString()
        index = index + 1
        local parts = {}
        while index <= length do
            local special = string.find(source, '[%z\1-\31\\"]', index)
            if special == nil then decodeError(index, "unterminated string") end
            if special > index then parts[#parts + 1] = string.sub(source, index, special - 1) end
            index = special
            local character = string.sub(source, special, special)
            if character == "\"" then
                index = index + 1
                return table.concat(parts)
            end
            if character == "\\" then
                local escaped = string.sub(source, index + 1, index + 1)
                if ESCAPES[escaped] ~= nil then
                    parts[#parts + 1] = ESCAPES[escaped]
                    index = index + 2
                elseif escaped == "u" then
                    local code = unicodeCode()
                    if code >= 0xD800 and code <= 0xDBFF then
                        if string.sub(source, index, index + 1) ~= "\\u" then
                            decodeError(index, "missing unicode pair")
                        end
                        local low = unicodeCode()
                        if low < 0xDC00 or low > 0xDFFF then decodeError(index, "bad unicode pair") end
                        code = 0x10000 + (code - 0xD800) * 0x400 + low - 0xDC00
                    elseif code >= 0xDC00 and code <= 0xDFFF then
                        decodeError(index, "unexpected unicode pair")
                    end
                    parts[#parts + 1] = utf8.char(code)
                else
                    decodeError(index, "bad string escape")
                end
            else
                decodeError(index, "unescaped control character")
            end
        end
        decodeError(index, "unterminated string")
    end

    -- Read a number with complete decimal and exponent parts
    local function parseNumber()
        local first = index
        if string.sub(source, index, index) == "-" then index = index + 1 end
        if string.sub(source, index, index) == "0" then
            index = index + 1
        else
            index = string.match(source, "^[1-9]%d*()", index)
            if index == nil then decodeError(first, "bad number") end
        end
        if string.sub(source, index, index) == "." then
            index = string.match(source, "^%.%d+()", index)
            if index == nil then decodeError(first, "bad decimal") end
        end
        if string.match(string.sub(source, index, index), "[eE]") then
            index = string.match(source, "^[eE][+-]?%d+()", index)
            if index == nil then decodeError(first, "bad exponent") end
        end
        local value = tonumber(string.sub(source, first, index - 1))
        if value == nil or value == math.huge or value == -math.huge then decodeError(first, "bad number") end
        return value
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
        if character == "{" or character == "[" then
            depth = depth + 1
            if depth > MAX_DEPTH then decodeError(index, "too many nested values") end
            local value = character == "{" and parseObject() or parseArray()
            depth = depth - 1
            return value
        end
        if string.sub(source, index, index + 3) == "true" then index = index + 4 return true end
        if string.sub(source, index, index + 4) == "false" then index = index + 5 return false end
        if string.sub(source, index, index + 3) == "null" then index = index + 4 return Json.null end
        if character == "-" or string.match(character, "%d") then return parseNumber() end
        decodeError(index, "unexpected value")
    end

    local result = parseValue()
    skipSpace()
    if index <= length then decodeError(index, "trailing content") end
    return result
end

return Json
