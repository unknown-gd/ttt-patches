if engine.ActiveGamemode() ~= "terrortown" then return end
util.AddNetworkString( "ttt--" )

local RecipientFilter = RecipientFilter
local CurTime = CurTime

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

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_time = CreateConVar( "ttt_feedback_time", "300", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Time in seconds when damage can be given from victim.", 5, 60 * 60 )

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_detectives_damage = CreateConVar( "ttt_feedback_detective_damage", "1", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Allow outgoing damage from detective.", 0, 1 )

---@param pl Player
---@param attacker Player
---@param cur_time number
local function updateTime( pl, attacker, cur_time )
	damage_history[ pl ][ attacker ] = cur_time
    if pl:IsBot() then return end

    net.Start( "ttt--" )
    net.WriteUInt( 0, 2 )
    net.WriteUInt( attacker:EntIndex(), 8 )
    net.WriteDouble( cur_time + feedback_time:GetFloat() )
	net.Send( pl )
end

---@param attacker Player
---@param victim Player
---@param cur_time number
---@return boolean is_damage_allowed
local function isAllowedToGiveDamage( attacker, victim, cur_time )
    if attacker:IsActiveDetective() and feedback_detectives_damage:GetBool() then
        return true
    end

    if attacker:IsTraitor() then
        return not attacker:KeyDown( IN_USE )
    end

    ---@type integer
    local alive_traitors = 0

    ---@type integer
    local alive_innocents = 0

    for _, pl in player.Iterator() do
        ---@cast pl Player

        if pl:IsTerror() and pl:Alive() then
            if pl:IsTraitor() then
                alive_traitors = alive_traitors + 1
            else
                alive_innocents = alive_innocents + 1
            end
        end
    end

    if alive_innocents <= alive_traitors then return true end

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
---@return boolean is_damage_allowed
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
            if pl ~= attacker and pl:IsTerror() and pl:Alive() and isScreenVisible( pl, observed_position ) then
                updateTime( pl, attacker, cur_time )
            end
        end

        return
    end

    return true

    ---@diagnostic disable-next-line: redundant-parameter, undefined-global
end, PRE_HOOK_RETURN )

---@param pl Player
local function clearDamageHistory( pl )
    net.Start( "ttt--" )
    net.WriteUInt( 1, 2 )
    net.WriteUInt( pl:EntIndex(), 8 )
    net.SendOmit( pl )

    damage_history[ pl ] = nil
end

---@param detective Player
---@param killer Player
---@param entity Entity
hook.Add( "TTTFoundDNA", "TTT--", function( detective, killer, entity )
    -- if not ( entity ~= nil and entity:IsValid() and entity:IsRagdoll() ) then return end
    if not ( killer:IsValid() and killer:Alive() and killer:IsTerror() ) then return end

    local detective_position = detective:WorldSpaceCenter()
    local cur_time = CurTime()

    for _, pl in player.Iterator() do
        if pl ~= killer and pl:IsTerror() and pl:Alive() and pl:IsLineOfSightClear( detective_position ) and pl:EyePos():Distance( detective_position ) < 512 then
            updateTime( pl, killer, cur_time )
        end
    end
end )

hook.Add( "PlayerSpawn", "TTT--", clearDamageHistory )
hook.Add( "PostPlayerDeath", "TTT--", clearDamageHistory )

timer.Simple( 0, function()

    hook.Add( "TTTKarmaLow", "TTT--", function( pl )
        return false
    end )

    local ttt_karma_low_amount = GetConVar( "ttt_karma_low_amount" )

    local function hasLowKarma( pl )
        return pl:GetBaseKarma() <= ttt_karma_low_amount:GetInt()
    end

    hook.Add( "TTTKarmaGivePenalty", "TTT--", function( attacker, _, victim )
        if victim ~= nil and victim:IsValid() and hasLowKarma( victim ) then
            return false
        end
    end )

    hook.Add( "TTTBeginRound", "TTT--", function()
        net.Start( "ttt--" )
        net.WriteUInt( 2, 2 )
        net.Broadcast()

        for key in pairs( damage_history ) do
            damage_history[ key ] = nil
        end

        local round_end_time = GetGlobalFloat( "ttt_round_end", CurTime() )

        for _, low_karma_pl in player.Iterator() do
            if hasLowKarma( low_karma_pl ) then
                for _, pl in player.Iterator() do
                    if pl ~= low_karma_pl and pl:IsTerror() and pl:Alive() then
                        updateTime( pl, low_karma_pl, round_end_time )
                    end
                end
            end
        end
    end )

end )
