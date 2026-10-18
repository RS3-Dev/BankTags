-- Static host IDs, the bank core's event prefix and storage keys, and sidebar dimensions.
-- Bank Utilities carries a copy of this module; its own prefix and keys are in
-- lib/features/storage_keys.lua

local Config = {
    -- Prefix for the bank core's event subscriptions and hook names
    CORE_REF = "bankcore",
    -- The player's bank-header launcher order and hidden set
    HEADER_LAUNCHERS_KEY = "bankcore:header_launchers:v1",
    -- The bank core's own preferences, such as debug logging
    PREFERENCES_KEY = "bankcore:settings:v1",
    BANK_INTERFACE_ID = 517,
    BANK_INVENTORY_ID = 95,
    BACKPACK_INVENTORY_ID = 93,
    UI_CATEGORY_ID = 155,
    WIDE_BANK_PROTOTYPE = true,
    -- The sidebar's content column and the gutter after it
    TAG_RAIL_WIDTH = 244,
    -- The vertical tab rail and the gap between it and the content column
    SIDEBAR_TAB_WIDTH = 32,
    SIDEBAR_TAB_GAP = 8,
}
-- How far the sidebar widens the bank: tab rail, gap, content column, and gutter
Config.SIDEBAR_WIDTH = Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP + Config.TAG_RAIL_WIDTH

return Config
