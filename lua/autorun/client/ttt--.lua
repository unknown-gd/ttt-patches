if engine.ActiveGamemode() ~= "terrortown" then return end

local screen_width, screen_height = ScrW(), ScrH()
local vmin = math.floor( math.min( screen_width, screen_height ) / 100 )

hook.Add( "OnScreenSizeChanged", "TTT--", function( _, _, width, height )
    screen_width, screen_height = width, height
    vmin = math.floor( math.min( screen_width, screen_height ) / 100 )
end )

local text_1 = "Hold %s to block outgoing damage."
local text_2 = "Outgoing damage blocked!"

---@class ttt__.Mark
---@field index integer
---@field end_time number
---@field entity Entity | nil
---@field visible boolean
---@field fade number

---@class Player
---@field IsActiveTraitor fun( self: Player ): boolean

---@type ttt__.Mark[]
local marked_players = { [ 0 ] = 0 }

hook.Add( "ScalePlayerDamage", "TTT--", function( pl, _, damage_info )
    local attacker = damage_info:GetAttacker()

    ---@diagnostic disable-next-line: undefined-field
    if not ( attacker == LocalPlayer() ) then return end

    ---@cast attacker Player

    if attacker:IsActiveTraitor() then
        if attacker:KeyDown( IN_USE ) then
            return true
        end

        return
    end

    for i = marked_players[ 0 ], 1, -1 do
        local mark = marked_players[ i ]
        if mark ~= nil and mark.entity == attacker then
            return
        end
    end

    return true
end )

local handlers = {
    [ 0 ] = function()
        local attacker_index = net.ReadUInt( 8 )
        local end_time = net.ReadDouble()

        local player_count = marked_players[ 0 ]

        for i = 1, player_count, 1 do
            local mark = marked_players[ i ]
            if mark.index == attacker_index then
                mark.end_time = end_time
                return
            end
        end

        player_count = player_count + 1
        marked_players[ 0 ] = player_count

        marked_players[ player_count ] = {
            index = attacker_index,
            end_time = end_time,
            visible = false,
            fade = 1
        }
    end,
    [ 1 ] = function()
        local attacker_index = net.ReadUInt( 8 )
        local player_count = marked_players[ 0 ]

        for i = player_count, 1, -1 do
            local mark = marked_players[ i ]
            if mark.index == attacker_index then
                marked_players[ 0 ] = player_count - 1
                table.remove( marked_players, i )
                break
            end
        end
    end,
    [ 2 ] = function()
        marked_players = { [ 0 ] = 0 }
    end
}

do

    local CurTime = CurTime
    local Entity = Entity

    hook.Add( "Think", "TTT--", function()
        local player_count = marked_players[ 0 ]
        local view_position = MainEyePos()
        local cur_time = CurTime()

        for i = player_count, 1, -1 do
            local mark = marked_players[ i ]
            if cur_time < mark.end_time then
                local entity = Entity( mark.index )
                if entity ~= nil and entity:IsValid() then
                    if not ( entity:IsPlayer() and entity:Alive() ) then
                        player_count = player_count - 1
                        table.remove( marked_players, i )
                    else
                        mark.entity = entity
                        mark.fade = math.Clamp( 1 - ( mark.end_time - cur_time ) / 10, 0, 1 )
                        mark.visible = entity:IsLineOfSightClear( view_position )
                    end
                end
            else
                player_count = player_count - 1
                table.remove( marked_players, i )
            end
        end

        marked_players[ 0 ] = player_count
    end )

end

net.Receive( "ttt--", function()
    local fn = handlers[ net.ReadUInt( 2 ) ]
    if fn == nil then return end
    fn()
end )

do

    local attention_icon = Material( "icon16/exclamation.png", "ignorez" )
    local color = Color( 255, 255, 255, 255 )

    hook.Add( "PostDrawTranslucentRenderables", "TTT--", function( bDrawingDepth, bDrawingSkybox, isDraw3DSkybox )
        local clock = os.clock()

        for i = marked_players[ 0 ], 1, -1 do
            local mark = marked_players[ i ]

            local entity = mark.entity
            if entity ~= nil and mark.visible then
                local origin = entity:EyePos()
                origin[ 3 ] = origin[ 3 ] + 16

                local fade = mark.fade
                if fade == 1 then
                    color.a = 255
                else
                    color.a = 255 - 250 * math.abs( math.sin( clock * 4 ) ) * fade
                end

                render.SetMaterial( attention_icon )
                render.DrawSprite( origin, 12, 12, color )
            end
        end
    end )

end

hook.Add( "HUDPaint", "TTT--", function()
    local pl = LocalPlayer()

    ---@diagnostic disable-next-line: undefined-field
    if not ( pl ~= nil and pl:IsValid() and pl:IsActiveTraitor() ) then return end

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
