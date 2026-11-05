-- Save large strings in chunks, switching over only once a save is complete

local ChunkedStringStore = {}

local CHUNK_SIZE = 12000

-- Read a saved string and report failures
local function readString(key)
    if PersistentDB == nil or PersistentDB.GetString == nil then
        return nil, "PersistentDB is unavailable."
    end
    local ok, value = pcall(function() return PersistentDB:GetString(key) end)
    if not ok then return nil, tostring(value) end
    if value ~= nil and type(value) ~= "string" then return nil, "The saved value is not text." end
    return value, nil
end

-- Read the current save's name and chunk count
local function manifest(options)
    local value, reason = readString(options.manifestKey)
    if value == nil then return nil, nil, reason end
    local generation, count = string.match(value, "^([ab]):(%d+)$")
    count = math.tointeger(tonumber(count))
    if generation == nil or count == nil or count < 1 then
        return nil, nil, "The saved chunk list is invalid."
    end
    return generation, count, nil
end

-- Write text and check any reported failure
local function writeVerified(key, value)
    -- Catch storage failures reported by the client
    local ok, result = pcall(function()
        return PersistentDB:SetString(key, value)
    end)
    if not ok then return false, tostring(result) end
    if result == false and readString(key) ~= value then
        return false, "write rejected"
    end
    return true, nil
end

-- Join saved chunks and report missing pieces
function ChunkedStringStore.Read(options)
    local generation, count, reason = manifest(options)
    if generation == nil then return nil, reason end

    local chunks = {}
    for index = 1, count do
        local chunk, problem = readString(
            options.chunkPrefix .. generation .. ":" .. tostring(index)
        )
        if chunk == nil then return nil, problem or ("Saved chunk " .. index .. " is missing.") end
        chunks[index] = chunk
    end
    return table.concat(chunks)
end

-- Finish the spare save before making it current
function ChunkedStringStore.Write(options, value)
    local activeGeneration, _, problem = manifest(options)
    if problem ~= nil then return false, { stage = "manifest", reason = problem } end
    local generation = activeGeneration == "a" and "b" or "a"
    local chunkCount = math.max(1, math.ceil(#value / CHUNK_SIZE))

    for index = 1, chunkCount do
        local first = (index - 1) * CHUNK_SIZE + 1
        local chunk = string.sub(value, first, first + CHUNK_SIZE - 1)
        local saved, reason = writeVerified(
            options.chunkPrefix .. generation .. ":" .. tostring(index),
            chunk
        )
        if not saved then
            return false, { stage = "chunk", index = index, reason = reason }
        end
    end

    local saved, reason = writeVerified(
        options.manifestKey,
        generation .. ":" .. tostring(chunkCount)
    )
    if not saved then
        return false, { stage = "manifest", reason = reason }
    end
    return true, nil
end

return ChunkedStringStore
