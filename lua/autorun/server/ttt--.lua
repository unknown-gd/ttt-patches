if engine.ActiveGamemode() ~= "terrortown" then return end
util.AddNetworkString( "ttt--" )

local RecipientFilter = RecipientFilter
local CurTime = CurTime

local timer = timer

---@type table<Player, table<Player, number>>
local damage_history = {}

do

    local attacks_metatable = {
        ---@param attacker Player
        __index = function( self, attacker )
            return 0
        end,
        __mode = "k"
    }

    setmetatable( damage_history, {
        ---@param victim Player
        __index = function( self, victim )
            ---@type table<Player, number>
            local attacks = {}
            setmetatable( attacks, attacks_metatable )
            self[ victim ] = attacks
            return attacks
        end,
        __mode = "k"
    } )

end

---@class Player
---@field IsSpec fun( self: Player ): boolean
---@field IsTerror fun( self: Player ): boolean
---@field IsTraitor fun( self: Player ): boolean
---@field IsDetective fun( self: Player ): boolean
---@field IsActiveDetective fun( self: Player ): boolean
---@field IsActiveTraitor fun( self: Player ): boolean

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_time = CreateConVar( "ttt_feedback_time", "300", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Time in seconds when damage can be given from victim.", 5, 60 * 60 )

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_detectives_damage = CreateConVar( "ttt_feedback_detective_damage", "1", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Allow outgoing damage from detective.", 0, 1 )

---@param victim Player
---@param attackers Player
---@param cur_time number
local function updateTimes( victim, attackers, cur_time )
    if not ( victim:Alive() and victim:IsTerror() ) then return end

    local markers = {}
    local marker_count = 0

    for i = #attackers, 1, -1 do
        local attacker = attackers[ i ]
        if attacker:IsTerror() and attacker:Alive() and attacker ~= victim then
            marker_count = marker_count + 1
            markers[ marker_count ] = attacker
            damage_history[ victim ][ attacker ] = cur_time
        end
    end

    if victim:IsBot() then return end

    net.Start( "ttt--" )
    net.WriteUInt( 3, 8 )
    net.WriteDouble( cur_time + feedback_time:GetFloat() )

    for i = 1, marker_count, 1 do
        net.WriteUInt( markers[ i ]:EntIndex(), 8 )
    end

	net.Send( victim )
end

---@param victim Player
---@param attacker Player
---@param cur_time number
local function updateTime( victim, attacker, cur_time )
    if not ( victim:Alive() and victim:IsTerror() ) then return end
    if not ( attacker:IsTerror() and attacker:Alive() ) or attacker == victim then return end

    damage_history[ victim ][ attacker ] = cur_time

    if victim:IsBot() then return end

    net.Start( "ttt--" )
    net.WriteUInt( 0, 8 )
    net.WriteUInt( attacker:EntIndex(), 8 )
    net.WriteDouble( cur_time + feedback_time:GetFloat() )
	net.Send( victim )
end

---@param attacker Player
---@param victim Player
---@param cur_time number
---@return boolean is_damage_allowed
local function isAllowedToGiveDamage( attacker, victim, cur_time )
    if attacker:IsActiveDetective() and feedback_detectives_damage:GetBool() then
        return true
    elseif attacker:IsTraitor() then
        return not attacker:KeyDown( IN_USE )
    end

    local last_damage_time = damage_history[ attacker ][ victim ]
    return last_damage_time ~= 0 and ( cur_time - last_damage_time ) < feedback_time:GetFloat()
end

---@param pl Player
---@param observed_position Vector
---@return boolean
local function isScreenVisible( pl, observed_position )
    if not pl:IsLineOfSightClear( observed_position ) then
        return false
    end

    local view_position = pl:EyePos()
    local view_angles = pl:EyeAngles()

    local observed_direction = view_position - observed_position
    observed_direction:Normalize()

    return math.abs( math.deg( math.acos( view_angles:Forward():Dot( observed_direction ) ) ) ) > pl:GetFOV()
end

local bit_band = bit.band

---@param victim Player
---@param damage_info CTakeDamageInfo
---@return boolean | nil is_damage_allowed
hook.Add( "EntityTakeDamage", "TTT--", function( victim, damage_info )
    if not ( victim ~= nil and victim:IsValid() and victim:IsPlayer() and victim:IsTerror() and victim:Alive() ) then return end

    local damage_type = damage_info:GetDamageType()
    if damage_type ~= 0 and
        bit_band( damage_type, DMG_CLUB ) == 0 and
        bit_band( damage_type, DMG_DIRECT ) == 0 and
        -- bit_band( damage_type, DMG_CRUSH ) == 0 and
        bit_band( damage_type, DMG_BULLET ) == 0 and
        bit_band( damage_type, DMG_SLASH ) == 0 and
        bit_band( damage_type, DMG_AIRBOAT ) == 0 and
        bit_band( damage_type, DMG_NEVERGIB ) == 0 then
        return
    end

    local attacker = damage_info:GetAttacker()
    if attacker == nil or not attacker:IsValid() then return end

    if not attacker:IsPlayer() then
        local owner = attacker:GetOwner()
        if owner == nil or not owner:IsValid() or not owner:IsPlayer() then return end
        attacker = owner
        return
    end

    ---@cast attacker Player

    if not ( attacker:Alive() and attacker:IsTerror() ) or attacker == victim then return end

    local cur_time = CurTime()

    if isAllowedToGiveDamage( attacker, victim, cur_time ) then
        local observed_position = attacker:WorldSpaceCenter()

        if victim:IsLineOfSightClear( observed_position ) then
            updateTime( victim, attacker, cur_time )
        end

        if attacker:IsDetective() then return end

        local rf = RecipientFilter()
        rf:AddPVS( observed_position )

        local viewers = rf:GetPlayers()

        for i = 1, #viewers, 1 do
            local pl = viewers[ i ]
            if pl ~= attacker and pl:IsTerror() and isScreenVisible( pl, observed_position ) then
                updateTime( pl, attacker, cur_time )
            end
        end

        return
    end

    return true

    ---@diagnostic disable-next-line: redundant-parameter, undefined-global
end, PRE_HOOK_RETURN )

---@param detective Player
---@param killer Player
---@param entity Entity
hook.Add( "TTTFoundDNA", "TTT--", function( detective, killer, entity )
    -- if not ( entity ~= nil and entity:IsValid() and entity:IsRagdoll() ) then return end
    if not ( killer:IsValid() and killer:Alive() and killer:IsTerror() ) then return end

    local detective_position = detective:WorldSpaceCenter()
    local cur_time = CurTime()

    for _, pl in player.Iterator() do
        if pl ~= killer and pl:IsTerror() and pl:IsLineOfSightClear( detective_position ) and pl:EyePos():Distance( detective_position ) < 512 then
            updateTime( pl, killer, cur_time )
        end
    end
end )

do

    ---@param pl Player
    local function clearDamageHistory( pl )
        net.Start( "ttt--" )
        net.WriteUInt( 1, 8 )
        net.WriteUInt( pl:EntIndex(), 8 )
        net.SendOmit( pl )

        damage_history[ pl ] = nil
    end

    hook.Add( "PostPlayerDeath", "TTT--", clearDamageHistory )
    hook.Add( "PlayerSpawn", "TTT--", clearDamageHistory )

end

local function player_death()
    ---@diagnostic disable-next-line: undefined-global
    if GetRoundState() ~= ROUND_ACTIVE then return end

    ---@type integer
    local alive_traitors = 0

    ---@type integer
    local alive_innocents = 0

    ---@type Player[]
    local alive_players = {}

    ---@type integer
    local alive_count = 0

    for _, pl in player.Iterator() do
        ---@cast pl Player

        if pl:IsTerror() and pl:Alive() then
            if pl:IsTraitor() then
                alive_traitors = alive_traitors + 1
            else
                alive_innocents = alive_innocents + 1
            end

            alive_count = alive_count + 1
            alive_players[ alive_count ] = pl
        end
    end

    if alive_innocents > alive_traitors or alive_count < 2 then return end

    local round_end_time = GetGlobalFloat( "ttt_round_end", CurTime() )

    for i = 1, alive_count, 1 do
        updateTimes( alive_players[ i ], alive_players, round_end_time )
    end

    PrintMessage( HUD_PRINTCENTER, "Most of the players are dead, damage restrictions are disabled!" )
    PrintMessage( HUD_PRINTCONSOLE, "[TTT--] Damage restrictions disabled." )
end

timer.Simple( 0, function()

    hook.Add( "TTTKarmaLow", "TTT--", function( pl )
        return false
    end )

    local ttt_karma_low_amount = GetConVar( "ttt_karma_low_amount" )

    local function hasLowKarma( pl )
        return ttt_karma_low_amount ~= nil and pl:GetBaseKarma() <= ttt_karma_low_amount:GetInt()
    end

    hook.Add( "TTTKarmaGivePenalty", "TTT--", function( attacker, _, victim )
        if victim ~= nil and victim:IsValid() and hasLowKarma( victim ) then
            return false
        end
    end )

    hook.Add( "TTTBeginRound", "TTT--", function()
        net.Start( "ttt--" )
        net.WriteUInt( 2, 8 )
        net.Broadcast()

        for key in pairs( damage_history ) do
            damage_history[ key ] = nil
        end

        local round_end_time = GetGlobalFloat( "ttt_round_end", CurTime() )

        for _, low_karma_pl in player.Iterator() do
            if hasLowKarma( low_karma_pl ) then
                for _, pl in player.Iterator() do
                    if pl ~= low_karma_pl and pl:IsTerror() then
                        updateTime( pl, low_karma_pl, round_end_time )
                    end
                end
            end
        end

        timer.Simple( 0.25, player_death )
    end )

end )

hook.Add( "PostPlayerDeath", "TTT--", function()
    timer.Create( "TTT--::Player Death", 0.5, 1, player_death )
end )

do

    local listeners = {}

    setmetatable( listeners, {
        __mode = "k",
        __index = function( self, pl )
            local speakers = {}
            self[ pl ] = speakers
            return speakers
        end
    } )

    local mono_mode = {}

    setmetatable( mono_mode, {
        __mode = "k",
        __index = function( self, pl )
            local speakers = {}
            self[ pl ] = speakers
            return speakers
        end
    } )

    timer.Create( "TTT--::Voice Chat", 0.25, 0, function()
        local rf = RecipientFilter()

        for _, listener in player.Iterator() do
            if not listener:IsBot() then
                local listener_position = listener:EyePos()

                local speakers = {}

                if listener:Alive() and listener:IsTerror() then
                    rf:RemoveAllPlayers()
                    rf:AddPAS( listener_position )

                    local players = rf:GetPlayers()

                    for i = #players, 1, -1 do
                        local speaker = players[ i ]
                        if speaker ~= listener and not speaker:IsBot() and speaker:Alive() and speaker:IsTerror() and speaker:EyePos():Distance( listener_position ) < ( speaker:IsLineOfSightClear( listener_position ) and 2048 or 256 ) then
                            speakers[ speaker ] = true
                        end
                    end
                else

                    local mono = {}

                    for _, speaker in player.Iterator() do
                        if speaker ~= listener and not speaker:IsBot() then
                            if speaker:Alive() and speaker:IsTerror() then
                                speakers[ speaker ] = speaker:EyePos():Distance( listener_position ) < ( speaker:IsLineOfSightClear( listener_position ) and 2048 or 256 )
                            else
                                speakers[ speaker ] = true
                                mono[ speaker ] = true
                            end
                        end
                    end

                    mono_mode[ listener ] = mono

                end

                listeners[ listener ] = speakers
            end
        end
    end )

    -- Mute players when we are about to run map cleanup, because it might cause
    -- net buffer overflows on clients.
    local mute_all = false

    function MuteForRestart( state )
        mute_all = state
    end

    hook.Add( "PlayerCanHearPlayersVoice", "TTT--", function( arguments, listener, speaker )
        -- Enforced silence
        if mute_all then
            return false, false
        end

        local should_hear = arguments[ 1 ]
        if should_hear ~= nil then
            return should_hear
        end

	    ---@diagnostic disable-next-line: undefined-global
	    if GetRoundState() ~= ROUND_ACTIVE then return true, false end

        -- Specific mute
        ---@diagnostic disable-next-line: undefined-global
        if listener:IsSpec() and listener.mute_team == speaker:Team() or listener.mute_team == MUTE_ALL then
            return false, false
        end

        -- Specs should not hear each other locationally
        if speaker:IsSpec() and listener:IsSpec() then
            return true, false
        end

        if speaker:IsActiveTraitor() and not speaker.traitor_gvoice then
            if listener:IsActiveTraitor() then
                return true, false
            else
                return false, false
            end
        end

        if listeners[ listener ][ speaker ] then
            return true, not mono_mode[ listener ][ speaker ]
        end

        return false, false
    end, POST_HOOK_RETURN )

end
