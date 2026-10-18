-- Describe the built-in import source: a pasted share code or backup

local CodeImportSource = {
    -- Provider keys are "owner/provider", so this key can never collide with one
    key = "builtin:code",
    revision = 0,
    builtin = true,
    label = "Share code",
    input = "text",
    prompt = "Import code",
    placeholder = "Paste a shared tag code...",
}

-- Use the pasted text itself as the tag data to preview and import
function CodeImportSource.Read(text)
    return text
end

return CodeImportSource
