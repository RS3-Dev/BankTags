-- Exercise the real import window with lightweight client controls.
local suite = { tests = {} }
function suite.setup()
    local function control(options)
        options = options or {}
        local value = { content = options.text or "", options = options }
        value.root = value
        function value:SetPos(x, y) self.x, self.y = x, y end
        function value:SetSize(width, height) self.width, self.height = width, height end
        function value:SetText(text, notify)
            self.content = text
            if notify and options.onChange then options.onChange(self, nil, text) end
        end
        function value:GetText() return self.content end
        function value:SetDisabled(disabled) self.disabled = disabled end
        function value:SetObject(object) self.object = object end
        function value:SetEntries(entries, selected) self.selected = selected end
        function value:GetSelectedID() return self.selected end
        function value:Subscribe() end
        function value:Destroy() self.destroyed = true end
        function value:SetContentHeight(height) self.contentHeight = height end
        return value
    end
    id = { Font = { CINZEL_13PT_BOLD = 1, MUSEO_SANS_11PT_REGULAR = 2 } }
    ui = { AlignMode = { CENTRE = 1 }, Hook = { ONCLICK = 1 } }
    ui.Layer = { new = function() return control() end }
    prettyui = {}
    for _, name in ipairs({"Text", "TextField", "ComboBox"}) do
        prettyui[name] = { new = function(_, options) return control(options) end }
    end
    prettyui.ItemSlot = { new = function(_, _, options) return control(options) end }
    prettyui.SimpleButton = { new = function(_, _, callback, options)
        local button = control(options); button.click = callback; return button
    end }
    prettyui.Window = { new = function(_, options)
        local window = control(options); window.content = {}; return window
    end }
    prettyui.Tabs = { new = function(_, entries)
        assert(entries[1].scrollable)
        local tabs = control()
        local pages = { control(), control() }
        for _, page in ipairs(pages) do page.content = {} end
        function tabs:GetPage(index) return pages[index] end
        return tabs
    end }
    Config = require("resources/core/config")
    Data = require("resources/tags/tag_data")
    local ImportShare = require("resources/windows/import_share")
    window = ImportShare.new({}, {
        onClose = function() end,
        onGetFolders = function() return {} end,
        onGetTagExports = function() return {} end,
        onImport = function(code, overrides)
            savedCode, savedOverrides = code, overrides
            return true, { tags = 1 }
        end,
    })
end

suite.tests.full_fields_add_parts_and_preserve_later_text = function()
    local full = string.rep("x", Config.LONG_INPUT_LIMIT)
    window.importFields[1]:SetText(full, true)
    assert(#window.importFields == 2)
    assert(window.importNameField.y == 165)
    window.importFields[2]:SetText(full, true)
    assert(#window.importFields == 3)
    window.importFields[3]:SetText("tail", true)
    window.importFields[1]:SetText("short", true)
    assert(#window.importFields == 3)
    assert(window:GetImportText() == "short" .. full .. "tail")
    window.importFields[3]:SetText("", true)
    window.importFields[2]:SetText("", true)
    assert(#window.importFields == 1 and window.importNameField.y == 127)
    assert(window.importButton.disabled)
end

suite.tests.long_valid_code_is_previewed_and_imported_in_order = function()
    local rows = {}
    for index = 1, 600 do rows[index] = { kind = "label", text = string.rep("a", 60) } end
    local code = Data.Encode({
        order = { "gear" }, folders = {}, tags = { gear = { rows = rows, unsorted = {} } },
    })
    assert(#code > Config.LONG_INPUT_LIMIT * 3)
    local index = 1
    for start = 1, #code, Config.LONG_INPUT_LIMIT do
        window.importFields[index]:SetText(code:sub(start, start + Config.LONG_INPUT_LIMIT - 1), true)
        index = index + 1
    end
    assert(window.importState == "ready" and window.importText == code)
    window.importNameField:SetText("renamed", false)
    window.importButton.click()
    assert(savedCode == code and savedOverrides.name == "renamed")
    assert(window.importPage.contentHeight > 424)
    local fields = window.importFields
    window:Destroy()
    for _, field in ipairs(fields) do assert(field.destroyed) end
end

suite.tests.exact_limit_and_new_folder_layout = function()
    window.importFields[1]:SetText(string.rep(" ", Config.LONG_INPUT_LIMIT - 1), true)
    assert(#window.importFields == 1)
    window.importFields[1]:SetText(string.rep(" ", Config.LONG_INPUT_LIMIT), true)
    assert(#window.importFields == 2)
    window.importSingleTag = "gear"
    window.importFolder.selected = "new"
    window:UpdateImportFolderControls()
    assert(window.importButton.y == 236 + 38 + 42)
    assert(not window.importFolderName.hidden)
end
suite.tests.share_splits_at_limit_and_keeps_tags_and_parts_in_order = function()
    for _, length in ipairs({9998, 9999, 10000, 19998, 19999, 30001}) do
        local code = string.rep("a", length - 1) .. "z"
        window:RebuildShareRows({{ tag = "gear", value = code }, { tag = "food", value = "next" }})
        local count = math.ceil(length / Config.LONG_INPUT_LIMIT)
        assert(#window.shareRows == count + 1)
        local parts = {}
        for index = 1, count do
            local row = window.shareRows[index]
            parts[index] = row.field:GetText()
            assert(#parts[index] <= Config.LONG_INPUT_LIMIT)
            assert(row.root.y == 82 + (index - 1) * 34)
            assert(row.tag == "gear")
            local expected = count == 1 and "gear" or "gear (" .. index .. "/" .. count .. ")"
            assert(row.label.content == expected)
        end
        assert(table.concat(parts) == code)
        assert(window.shareRows[count + 1].field:GetText() == "next")
        local old = window.shareRows
        window:RebuildShareRows({})
        for _, row in ipairs(old) do assert(row.root.destroyed and row.field.destroyed) end
    end
end

suite.tests.share_errors_remain_visible = function()
    window:RebuildShareRows({{ tag = "broken", reason = "Unavailable" }})
    assert(#window.shareRows == 1)
    assert(window.shareRows[1].field:GetText() == "Unavailable")
    assert(window.shareRows[1].label.options.colour == 0xE57373FF)
end
return suite
