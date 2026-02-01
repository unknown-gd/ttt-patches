if engine.ActiveGamemode() ~= "terrortown" then return end

local screen_width, screen_height = ScrW(), ScrH()
local vmin = math.floor( math.min( screen_width, screen_height ) / 100 )

hook.Add( "OnScreenSizeChanged", "TTT--", function( _, _, width, height )
    screen_width, screen_height = width, height
    vmin = math.floor( math.min( screen_width, screen_height ) / 100 )
end )

local text_1 = "Hold %s to block outgoing damage."
local text_2 = "Outgoing damage blocked!"

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_detectives_damage = CreateConVar( "ttt_feedback_detectives_damage", "0", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Allow outgoing damage from detectives.", 0, 1 )

hook.Add( "HUDPaint", "TTT--", function()
    local pl = LocalPlayer()

    ---@diagnostic disable-next-line: undefined-field
    if not ( pl ~= nil and pl:IsValid() and pl:IsActiveTraitor() or ( feedback_detectives_damage:GetBool() and pl:IsActiveDetective() ) ) then return end

    surface.SetFont( "DermaLarge" )

    local key_name, key_code, is_pressed = input.LookupBinding( "use" )
    if key_name == nil then
        is_pressed = false
        key_name = " "
        key_code = 0
    else
        key_code = input.GetKeyCode( key_name )
        is_pressed = input.IsKeyDown( key_code )
    end

    key_name = "[" .. string.upper( key_name ) .. "]"

    local use_text_width, use_text_height = surface.GetTextSize( key_name )

    local text = is_pressed and text_2 or string.format( text_1, key_name )
    local text_width, text_height = surface.GetTextSize( text )

    local height = vmin + text_height + vmin
    local width = height + vmin + text_width + vmin

    local x = ( screen_width - width ) * 0.5
    local y = screen_height - height - vmin

    surface.SetDrawColor( 0, 0, 0, 150 )
    surface.DrawRect( x, y, width, height )

    if is_pressed then
        surface.SetDrawColor( 0, 255, 0, 150 )
    else
        surface.SetDrawColor( 255, 0, 0, 150 )
    end

    surface.DrawRect( x, y, height, height )

    surface.SetTextPos(
        x + ( height - use_text_width ) * 0.5,
        y + ( height - use_text_height ) * 0.5
    )

    surface.SetTextColor( 0, 0, 0, 255 )
    surface.DrawText( key_name )

    surface.SetTextPos(
        x + height + vmin,
        y + ( height - text_height ) * 0.5
    )

    surface.SetTextColor( 255, 255, 255, 255 )
    surface.DrawText( text )
end )
