-- Name the event prefix, saved-data keys, and text limits Bank Utilities' own features use.
-- The bank core keeps its own prefix and keys in lib/core/config.lua

local StorageKeys = {
    -- Prefix for Bank Utilities' event subscriptions and hook names
    PLUGIN_REF = "bankutils",
    -- The tag save, written as chunked share-code text
    TAGS_TEXT_MANIFEST_KEY = "bankutils:tags:v3:manifest",
    TAGS_TEXT_CHUNK_PREFIX = "bankutils:tags:v3:",
    -- The plugin-panel preferences
    SETTINGS_KEY = "bankutils:settings:v1",
    -- Saved RuneQL queries and their chunked text
    RUNESQL_KEY = "bankutils:runesql:v1",
    RUNESQL_TEXT_MANIFEST_KEY = "bankutils:runesql:text:v1:manifest",
    RUNESQL_TEXT_CHUNK_PREFIX = "bankutils:runesql:text:v1:",
    -- The launcher order and hidden set the single-plugin build saved; offered to the bank
    -- core once, read only, so a core without saved choices starts from them
    LEGACY_HEADER_LAUNCHERS_KEY = "bankutils:header_launchers:v1",
    -- The longest text a search, query, or share-code field accepts
    LONG_INPUT_LIMIT = 9999,
}

return StorageKeys
