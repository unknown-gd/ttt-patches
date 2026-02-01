if engine.ActiveGamemode() ~= "terrortown" then return end

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
---@field IsActiveDetective fun( self: Player ): boolean

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_time = CreateConVar( "ttt_feedback_time", "300", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Time in seconds when damage can be given from victim.", 0, 60 * 60 )

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_detectives_damage = CreateConVar( "ttt_feedback_detectives_damage", "0", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Allow outgoing damage from detectives.", 0, 1 )

---@type ConVar
---@diagnostic disable-next-line: param-type-mismatch
local feedback_distance = CreateConVar( "ttt_feedback_distance", "1024", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Distance limit in square meters.", 0, 2 ^ 32 - 1 )

---@param attacker Player
---@param victim Player
---@param cur_time number
---@return boolean is_damage_allowed
local function isAllowedToGiveDamage( attacker, victim, cur_time )
    if attacker:IsTraitor() or ( feedback_detectives_damage:GetBool() and attacker:IsActiveDetective() ) then
        return not attacker:KeyDown( IN_USE )
    end

    local last_damage_time = damage_history[ attacker ][ victim ]
    return last_damage_time ~= 0 and ( cur_time - last_damage_time ) < feedback_time:GetFloat()
end

---@param pl Player
---@param observed_position Vector
---@param view_position Vector
---@return boolean
local function isScreenVisible( pl, observed_position, view_position )
    local view_angles = pl:EyeAngles()

    if view_position:Distance( observed_position ) > feedback_distance:GetFloat() then
        return false
    end

    if not pl:IsLineOfSightClear( observed_position ) then
        return false
    end

    local observed_direction = view_position - observed_position
    observed_direction:Normalize()

    return math.abs( math.deg( math.acos( view_angles:Forward():Dot( observed_direction ) ) ) ) > pl:GetFOV()
end

local bit_band = bit.band

---@param victim Player
---@param damage_info CTakeDamageInfo
---@return boolean is_damage_allowed
hook.Add( "EntityTakeDamage", "TTT--", function( victim, damage_info )
    ---@diagnostic disable-next-line: undefined-global
    if GetRoundState() ~= ROUND_ACTIVE then return end

    if not ( victim ~= nil and victim:IsValid() and victim:IsPlayer() and victim:IsTerror() and victim:Alive() ) or victim:IsSpec() then return end

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

    if alive_innocents <= alive_traitors then return end

    local damage_type = damage_info:GetDamageType()
    if damage_type ~= 0 and
        bit_band( damage_type, DMG_CLUB ) == 0 and
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

        if victim:IsLineOfSightClear( observed_position ) and victim:EyePos():Distance( observed_position ) < feedback_distance:GetFloat() then
            damage_history[ victim ][ attacker ] = cur_time
        end

        local rf = RecipientFilter()
        rf:AddPVS( observed_position )

        local viewers = rf:GetPlayers()

        for i = 1, #viewers, 1 do
            local pl = viewers[ i ]
            if pl ~= attacker and not pl:IsSpec() and isScreenVisible( pl, observed_position, pl:EyePos() ) then
                damage_history[ pl ][ attacker ] = cur_time
            end
        end

        return
    end

    return true

    ---@diagnostic disable-next-line: redundant-parameter, undefined-global
end, PRE_HOOK_RETURN )

local function clearDamageHistory( pl )
    damage_history[ pl ] = nil
end

hook.Add( "PlayerSpawn", "TTT--", clearDamageHistory )
hook.Add( "PostPlayerDeath", "TTT--", clearDamageHistory )

hook.Add( "TTTBeginRound", "TTT--", function()
    for key in pairs( damage_history ) do
        damage_history[ key ] = nil
    end
end )
