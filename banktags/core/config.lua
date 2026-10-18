-- Name Bank Tags' plugin identity, event prefix, saved-data keys, and text limits

local Config = {
    -- The owner ID Bank Core knows this plugin by, and the prefix for its event names
    PLUGIN_REF = "banktags",
    OWNER_LABEL = "Bank Tags",
    -- Where Bank Core and RuneQL publish their APIs for plugins whose injected copy is missing
    CORE_API_KEY = "__bankcore_api",
    RUNEQL_API_KEY = "__runeql_api",
    -- The tag save, written as chunked share-code text
    TAGS_TEXT_MANIFEST_KEY = "banktags:tags:v3:manifest",
    TAGS_TEXT_CHUNK_PREFIX = "banktags:tags:v3:",
    -- The plugin-panel preferences
    SETTINGS_KEY = "banktags:settings:v1",
    -- The longest text a share-code field accepts
    LONG_INPUT_LIMIT = 9999,
}

return Config
