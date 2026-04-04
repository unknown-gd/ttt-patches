local string_byte = string.byte
local bit_band = bit.band

hook.Add( "EntityTakeDamage", "NoMorePropDamage", function( pl, damage_info )
    if not ( pl ~= nil and pl:IsValid() and pl:IsPlayer() and pl:Alive() ) then return end
    if bit_band( damage_info:GetDamageType(), 1 ) == 0 then return end

    local attacker = damage_info:GetAttacker()
    if not ( attacker ~= nil and attacker:IsValid() ) then return end

    local b1, b2, b3, b4, b5 = string_byte( attacker:GetClass(), 1, 5 )
    if ( ( ( ( b5 * 0x100 + b4 ) * 0x100 + b3 ) * 0x100 + b2 ) * 0x100 + b1 ) ~= 0x5f706f7270 --[[ prop_ signature ]] then return end

    local phys = attacker:GetPhysicsObject()
    if not ( phys ~= nil and phys:IsValid() ) then return end
    if phys:GetMass() > 250 then return end

    damage_info:SetDamageForce( vector_origin )
    damage_info:SetDamage( 0 )

    return true
end )
