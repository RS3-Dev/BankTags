-- Publish large saves without replacing the previous generation until writing succeeds

local ChunkedStringStore = {}

local CHUNK_SIZE = 12000

-- Read a stored string, allowing missing keys or rejected host reads
local function readString(key)
    if PersistentDB == nil or PersistentDB.GetString == nil then return nil end
    local ok, value = pcall(function() return PersistentDB:GetString(key) end)
    return ok and type(value) == "string" and value or nil
end

-- Read the published generation and chunk count from the save marker
local function manifest(options)
    local value = readString(options.manifestKey)
    if value == nil then return nil, nil end
    local generation, count = string.match(value, "^([ab]):(%d+)$")
    count = math.tointeger(tonumber(count))
    if generation == nil or count == nil or count < 1 then return nil, nil end
    return generation, count
end

-- Write a string and confirm it when the host reports a possible rejection
local function writeVerified(key, value)
    local ok, result = pcall(function()
        return PersistentDB:SetString(key, value)
    end)
    if not ok then return false, tostring(result) end
    if result == false and readString(key) ~= value then
        return false, "write rejected"
    end
    return true, nil
end

-- Join every chunk from the published save, rejecting incomplete generations
function ChunkedStringStore.Read(options)
    local generation, count = manifest(options)
    if generation == nil then return nil end

    local chunks = {}
    for index = 1, count do
        local chunk = readString(
            options.chunkPrefix .. generation .. ":" .. tostring(index)
        )
        if chunk == nil then return nil end
        chunks[index] = chunk
    end
    return table.concat(chunks)
end

-- Write the inactive generation first and publish its marker only after all chunks succeed
function ChunkedStringStore.Write(options, value)
    local activeGeneration = manifest(options)
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
