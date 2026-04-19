if engine.ActiveGamemode() ~= "terrortown" then return end

timer.Simple( 0, function()
    ---@diagnostic disable-next-line: undefined-global
    local PROPSPEC = PROPSPEC
    if PROPSPEC == nil then return end

    local original_fn = PROPSPEC.Key
    if original_fn == nil then return end

    local info = debug.getinfo( original_fn, "nSu" )
    if info == nil then return end

    if info.short_src ~= "gamemodes/terrortown/gamemode/propspec.lua" then
        for i = 1, info.nups, 1 do
            local name, value = debug.getupvalue( original_fn, i )
            if name == "original_fn" then
                original_fn = value
            end
        end
    end

    ---@param pl Player
    ---@param key integer
    function PROPSPEC.Key( pl, key )
        if original_fn( pl, key ) then
            ---@diagnostic disable-next-line: undefined-field
            local propspec = pl.propspec
            if propspec ~= nil then
                ---@type Entity
                local entity = propspec.ent
                local class_name = entity:GetClass()

                if class_name == "prop_door_rotating" then
                    entity:Use( pl, pl )
                end
            end

            return true
        end

        return false
    end

    local propspec_toggle = GetConVar( "ttt_spec_prop_control" )
    if propspec_toggle == nil then return end

    ---@param pl Player
    ---@param entity Entity
    function PROPSPEC.Target( pl, entity )
        if not propspec_toggle:GetBool() then return end
        if not ( pl ~= nil and pl:IsValid() and pl:IsSpec() ) then return end
        if not ( entity ~= nil and entity:IsValid() ) then return end

        if not entity:IsWeapon() then
            local class_name = entity:GetClass()
            if string.match( class_name, "^prop_physics*" ) == nil and
                string.match( class_name, "^func_physbox*" ) == nil and
                string.match( class_name, "^item_*" ) == nil and
                string.match( class_name, "^ttt_*" ) == nil and
                class_name ~= "prop_door_rotating" then return end
        end

        local entity_spectator = entity:GetNWEntity( "spec_owner", nil )
        if entity_spectator == nil and entity_spectator:IsValid() then return end

        local phys = entity:GetPhysicsObject()
        if not ( phys ~= nil and phys:IsValid() and phys:IsMoveable() ) then return end

        PROPSPEC.Start( pl, entity )
    end

end )

do

    local exploded = {}

    setmetatable( exploded, {
        __mode = "k"
    } )

    ---@param entity Entity
    local function explode( entity )
        if exploded[ entity ] then return end
        exploded[ entity ] = true

        local effectdata = EffectData()
        effectdata:SetOrigin( entity:GetPos() )
        util.Effect( "Explosion", effectdata )

        util.BlastDamage( entity, entity, entity:GetPos(), 256, 45 )
        entity:Remove()
    end

    ---@param entity Entity
    ---@param damage_info CTakeDamageInfo
    hook.Add( "EntityTakeDamage", "TTT++", function( entity, damage_info )
        ---@diagnostic disable-next-line: undefined-field
        if entity.Base ~= "base_ammo_ttt" then return end

        if damage_info:IsBulletDamage() then
            if math.random( 1, 10 ) == 4 then return end
            entity:Ignite( 10, 32 )
        elseif damage_info:IsDamageType( DMG_BURN ) and math.random( 1, 10 ) == 3 then
            explode( entity )
        elseif damage_info:IsDamageType( DMG_BLAST ) then
            if math.random( 1, 10 ) == 5 then return end
            explode( entity )
        end
    end, PRE_HOOK )

end
