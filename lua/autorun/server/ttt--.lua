if engine.ActiveGamemode() ~= "terrortown" then return end

local addon_name = "TTT--"

local RecipientFilter = RecipientFilter
local CurTime = CurTime

---@type table<Player, table<Player, number>>
local damage_history = {}

do

    local attacks_metatable = {
        ---@param attacker Player
        __index = function( self, attacker )
            -- return CurTime()
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

--- Time in seconds when damage can be given from victim
---@type integer
local attack_frame = 60 * 5

---@type boolean
local allow_damage_from_detectives = false

---@param attacker Player
---@param victim Player
---@param cur_time number
---@return boolean is_damage_allowed
local function isAllowedToGiveDamage( attacker, victim, cur_time )
    if ( attacker:IsTraitor() or ( allow_damage_from_detectives and attacker:IsActiveDetective() ) ) then
        return not attacker:KeyDown( IN_USE )
    end

    return ( cur_time - damage_history[ attacker ][ victim ] ) < attack_frame
end

local view_limit = 1024 ^ 2

---@param pl Player
---@param observed_position Vector
---@return boolean
local function isScreenVisible( pl, observed_position )
    local view_position, view_angles = pl:GetPos(), pl:EyeAngles()

    if view_position:DistToSqr( observed_position ) > view_limit then
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
hook.Add( "EntityTakeDamage", addon_name, function( victim, damage_info )
    if not ( victim ~= nil and victim:IsValid() and victim:IsPlayer() and victim:IsTerror() and victim:Alive() ) then return end

    ---@type integer
    local alive_innocents = 0

    for _, pl in player.Iterator() do
        ---@cast pl Player
        if pl:IsTerror() and pl:Alive() and not pl:IsTraitor() then
            alive_innocents = alive_innocents + 1
        end
    end

    if alive_innocents == 1 then return end

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

        local rf = RecipientFilter()
        rf:AddPVS( observed_position )

        local viewers = rf:GetPlayers()

        for i = 1, #viewers, 1 do
            local pl = viewers[ i ]
            print( pl, pl ~= attacker, not pl:IsSpec(), isScreenVisible( pl, observed_position ) )
            if pl ~= attacker and not pl:IsSpec() and isScreenVisible( pl, observed_position ) then
                pl:Say( attacker:Nick() .. " attacked " .. victim:Nick() .. "!" )
                damage_history[ pl ][ attacker ] = cur_time
            end
        end

        return
    end

    return true

    ---@diagnostic disable-next-line: redundant-parameter, undefined-global
end, PRE_HOOK_RETURN )

hook.Add( "PlayerSpawn", addon_name, function( pl )
    damage_history[ pl ] = nil
end )
