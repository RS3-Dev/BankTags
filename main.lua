-- Start Bank Tags and connect it to Bank Core when present

-- Keep the debug preference loaded even if the last session failed to stop
local DebugLog = require("resources/core/debug_log")
local debugLog = DebugLog.Write

local SESSION_KEY = "__banktags_session"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then
    local ok, message = pcall(function() previous:Shutdown() end)
    if not ok then debugLog("Bank Tags could not fully stop the previous reload: ", message) end
end
-- Reloads share the Lua state, so drop the old references first
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
-- Remove the old import-provider export
_G.__banktags_api = nil
previous = nil
pcall(function() collectgarbage("collect") end)

-- Reload runtime modules while preserving the debug preference
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        "resources/app",
        "resources/core/chunked_string_store",
        "resources/core/config",
        "resources/core/json",
        "resources/core/object_config",
        "resources/core/settings",
        "resources/core/text",
        "resources/sidebar/select_mode",
        "resources/sidebar/tag_list",
        "resources/sidebar/tag_list_drag",
        "resources/sidebar/tag_list_parts",
        "resources/sidebar/tag_menus",
        "resources/sidebar/tag_tab",
        "resources/tags/catalog",
        "resources/tags/item_identity",
        "resources/tags/native_items",
        "resources/tags/tag_data",
        "resources/tags/tag_layouts",
        "resources/tags/tag_page",
        "resources/tags/tag_rules",
        "resources/tags/tag_store",
        "resources/tags/tag_store_folders",
        "resources/tags/tag_store_labels",
        "resources/tags/tag_store_layouts",
        "resources/ui/bank_controls",
        "resources/ui/bank_grid",
        "resources/ui/geometry",
        "resources/ui/menu_entries",
        "resources/ui/native_ui",
        "resources/ui/sidebar_rows",
        "resources/ui/text_prompt",
        "resources/ui/theme",
        "resources/windows/confirm_window",
        "resources/windows/import_share",
        "resources/windows/import_share_draft",
        "resources/windows/layout_editor_clipboard",
        "resources/windows/layout_editor_drag",
        "resources/windows/layout_editor_group",
        "resources/windows/layout_editor_history",
        "resources/windows/layout_editor_keys",
        "resources/windows/layout_editor_marquee",
        "resources/windows/layout_editor_names",
        "resources/windows/layout_editor_parts",
        "resources/windows/layout_editor_rows",
        "resources/windows/layout_editor_search",
        "resources/windows/layout_editor_tabs",
        "resources/windows/layout_editor_view",
        "resources/windows/layout_editor_unsorted",
        "resources/windows/layout_editor_window",
        "resources/windows/settings_section",
        "resources/windows/sprite_picker",
        "resources/windows/tag_settings_editor",
        "resources/windows/tutorial",
        "resources/windows/tutorial_view",
        "resources/windows/windows",
    }) do
        package.loaded[moduleName] = nil
    end
end

local App = require("resources/app")
local Catalog = require("resources/tags/catalog")
local app = App.new()
_G[SESSION_KEY] = app
app:Start()

-- Handle dependency updates when the host sends them
function PluginDependencyUpdate(event)
    if event.pluginIdentifier == "runeql" then Catalog.SetRuneQLEnabled(event.enabled) end
    if event.pluginIdentifier ~= "bankcore" then return end
    if event.enabled then app:Connect() else app:Disconnect() end
end

-- Stop the session and release its references on unload
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, SESSION_KEY) == app then _G[SESSION_KEY] = nil end
end
