
hook.Add( "EntityTakeDamage", "NoMorePropDamage", function( pl, damage_info )
    if not ( pl ~= nil and pl:IsValid() and pl:IsPlayer() and pl:Alive() ) then return end
    if bit.band( damage_info:GetDamageType(), 1 ) == 0 then return end

    local attacker = damage_info:GetAttacker()
    if not ( attacker ~= nil and attacker:IsValid() ) then return end

    local phys = attacker:GetPhysicsObject()
    if not ( phys ~= nil and phys:IsValid() ) then return end
    if phys:GetMass() > 250 then return end

    return true
end )
