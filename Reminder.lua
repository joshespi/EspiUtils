local _, EspiUtils = ...

function EspiUtils.CreateReminder(titleText, iconPath)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(300, 54)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.07, 0.065, 0.05, 0.96)
    frame:SetBackdropBorderColor(0.53, 0.38, 0.19)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    title:SetText(titleText)

    local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)
    return frame, detail
end

function EspiUtils.Print(message)
    print("|cffefbd68Espi Utils|r " .. message)
end
