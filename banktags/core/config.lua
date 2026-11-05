-- Name Bank Tags' plugin identity, event prefix, saved-data keys, and text limits

local Config = {
    -- Plugin identity and event-name prefix
    PLUGIN_REF = "banktags",
    OWNER_LABEL = "Bank Tags",
    -- Globals where Bank Core and RuneQL leave their APIs when none is passed in
    CORE_API_KEY = "__bankcore_api",
    RUNEQL_API_KEY = "__runeql_api",
    -- The tag save, written as chunked share-code text
    TAGS_TEXT_MANIFEST_KEY = "banktags:tags:v4:manifest",
    TAGS_TEXT_CHUNK_PREFIX = "banktags:tags:v4:",
    -- Preferences shown on Bank Tags' Plugin Hub page
    SETTINGS_KEY = "banktags:settings:v1",
    -- The longest text a share-code field accepts
    LONG_INPUT_LIMIT = 9999,
}

return Config
