function carts:get_sign(z)
	if z == 0 then
		return 0
	else
		return z / math.abs(z)
	end
end

function carts:manage_attachment(player, obj)
	if not player then
		return
	end
	local status = obj ~= nil
	local player_name = player:get_player_name()
	if default.player_attached[player_name] == status then
		return
	end
	default.player_attached[player_name] = status

	if status then
		player:set_attach(obj, "", {x=0, y=6, z=0}, {x=0, y=0, z=0})
		player:set_eye_offset({x=0, y=-4, z=0},{x=0, y=-4, z=0})
	else
		player:set_detach()
		player:set_eye_offset({x=0, y=0, z=0},{x=0, y=0, z=0})
	end
end

function carts:velocity_to_dir(v)
	if math.abs(v.x) > math.abs(v.z) then
		return {x=carts:get_sign(v.x), y=carts:get_sign(v.y), z=0}
	else
		return {x=0, y=carts:get_sign(v.y), z=carts:get_sign(v.z)}
	end
end

function carts:is_rail(pos, railtype)
	local node = minetest.get_node(pos).name
	if node == "ignore" then
		local vm = minetest.get_voxel_manip()
		local emin, emax = vm:read_from_map(pos, pos)
		local area = VoxelArea:new{
			MinEdge = emin,
			MaxEdge = emax,
		}
		local data = vm:get_data()
		local vi = area:indexp(pos)
		node = minetest.get_name_from_content_id(data[vi])
	end
	if minetest.get_item_group(node, "rail") == 0 then
		return false
	end
	if not railtype then
		return true
	end
	return minetest.get_item_group(node, "connect_to_raillike") == railtype
end

function carts:check_front_up_down(pos, dir_, check_up, railtype)
	local dir = vector.new(dir_)
	local cur

	-- Front
	dir.y = 0
	cur = vector.add(pos, dir)
	if carts:is_rail(cur, railtype) then
		return dir
	end
	-- Up
	if check_up then
		dir.y = 1
		cur = vector.add(pos, dir)
		if carts:is_rail(cur, railtype) then
			return dir
		end
	end
	-- Down
	dir.y = -1
	cur = vector.add(pos, dir)
	if carts:is_rail(cur, railtype) then
		return dir
	end
	return nil
end

function carts:get_rail_direction(pos_, dir, ctrl, old_switch, railtype)
	local pos = vector.round(pos_)
	local cur
	local left_check, right_check = true, true

	-- Check left and right
	local left = {x=0, y=0, z=0}
	local right = {x=0, y=0, z=0}
	if dir.z ~= 0 and dir.x == 0 then
		left.x = -dir.z
		right.x = dir.z
	elseif dir.x ~= 0 and dir.z == 0 then
		left.z = dir.x
		right.z = -dir.x
	end

	if ctrl then
		if old_switch == 1 then
			left_check = false
		elseif old_switch == 2 then
			right_check = false
		end
		if ctrl.left and left_check then
			cur = carts:check_front_up_down(pos, left, false, railtype)
			if cur then
				return cur, 1
			end
			left_check = false
		end
		if ctrl.right and right_check then
			cur = carts:check_front_up_down(pos, right, false, railtype)
			if cur then
				return cur, 2
			end
			right_check = true
		end
	end

	-- Normal
	cur = carts:check_front_up_down(pos, dir, true, railtype)
	if cur then
		return cur
	end

	-- Left, if not already checked
	if left_check then
		cur = carts:check_front_up_down(pos, left, false, railtype)
		if cur then
			return cur
		end
	end

	-- Right, if not already checked
	if right_check then
		cur = carts:check_front_up_down(pos, right, false, railtype)
		if cur then
			return cur
		end
	end

	-- Backwards
	if not old_switch then
		cur = carts:check_front_up_down(pos, {
				x = -dir.x,
				y = dir.y,
				z = -dir.z
			}, true, railtype)
		if cur then
			return cur
		end
	end

	return {x=0, y=0, z=0}
end

function carts:pathfinder(pos_, expected_pos, old_dir, ctrl, pf_switch, railtype)
	local pos = vector.round(pos_)
	local pf_pos = vector.round(expected_pos)
	local pf_dir = vector.new(old_dir)

	for i = 1, 3 do
		if vector.equals(pf_pos, pos) then
			-- Success! Cart moved on correctly
			return true
		end

		pf_dir, pf_switch = carts:get_rail_direction(pf_pos, pf_dir, ctrl, pf_switch, railtype)
		if vector.equals(pf_dir, {x=0, y=0, z=0}) then
			-- No way forwards
			return false
		end

		pf_pos = vector.add(pf_pos, pf_dir)
	end
	-- Cart not found
	return false
end

function carts:register_rail(name, def, railparams)
	local def_default = {
		drawtype = "raillike",
		paramtype = "light",
		sunlight_propagates = true,
		is_ground_content = true,
		walkable = false,
		selection_box = {
			type = "fixed",
			fixed = {-1/2, -1/2, -1/2, 1/2, -1/2+1/16, 1/2},
		},
		sounds = default.node_sound_metal_defaults()
	}
	for k, v in pairs(def_default) do
		def[k] = v
	end
	if not def.inventory_image then
		def.wield_image = def.tiles[1]
		def.inventory_image = def.tiles[1]
	end

	if railparams then
		carts.railparams[name] = table.copy(railparams)
	end

	minetest.register_node(name, def)
end

function carts:get_rail_groups(additional_groups)
	-- Get the default rail groups and add more when a table is given
	local groups = {dig_immediate = 2, attached_node = 1, rail = 1, connect_to_raillike = 1}
	if type(additional_groups) == "table" then
		for k, v in pairs(additional_groups) do
			groups[k] = v
		end
	end
	return groups
end

function carts:couple_cart(cart,player)
	local name = player:get_player_name()
	if carts.couple[name] == nil then
		carts.couple[name] = cart:get_luaentity()
		print("Click other cart to connect")
	else --assume entity still exists in the world - make sure to update coupled cart on deletion
		if carts.couple[name] == cart:get_luaentity() then
			print("You can't couple a cart to itself!")
		else
			if  carts.couple[name].object:get_luaentity() then
				carts.couple[name].couple1 =  cart:get_luaentity()
				cart:get_luaentity().couple2 = carts.couple[name].object:get_luaentity()
				carts.couple[name] = nil
				print("Coupled!")
			else
				print("Cart doesn't exist!")
				carts.couple[name] = nil
			end
		end
	end
end

function carts:start_magnet(self,object)
	--magnetise towards the other one
	--print(dump(object:get_luaentity()))
	local pos = self.object:getpos()
	if object:get_luaentity().cart and object:get_luaentity() == self.couple1 then
		local pos2 = object:getpos()
						
		local cart_dir = carts:get_rail_direction(pos, {x=(pos2.x-pos.x),y=pos.y,z=(pos2.z-pos.z)}, nil, nil, self.railtype)
		
		if vector.equals(cart_dir, {x=0, y=0, z=0}) then
			return
		end
		local dist = vector.distance(pos, pos2)
		
		local vel = dist
		vel = vel
		local punch_interval = 1
		time_from_last_punch = math.min(time_from_last_punch or punch_interval, punch_interval)
		local f = vel * (time_from_last_punch / punch_interval)
		--print(f)
		self.velocity = vector.multiply(cart_dir, f)
		self.old_dir = cart_dir
		self.punched = true
		print("started magnet")
	end
end

function carts:cart_repulsion_start(self,object)
	--set the carts velocity using player's around
	local pos  = self.object:getpos()
	local pos2 = object:getpos()
						
	local cart_dir = carts:get_rail_direction(pos, {x=(pos.x-pos2.x),y=pos.y,z=(pos.z-pos2.z)}, nil, nil, self.railtype)
	
	if vector.equals(cart_dir, {x=0, y=0, z=0}) then
		return
	end
	local dist = vector.distance(pos, pos2)
	
	local vel = 1.5-dist
	vel = vel * 3
	local punch_interval = 1
	time_from_last_punch = math.min(time_from_last_punch or punch_interval, punch_interval)
	local f = vel * (time_from_last_punch / punch_interval)
	--print(f)
	self.velocity = vector.multiply(cart_dir, f)
	self.old_dir = cart_dir
	self.punched = true
	return(time_from_last_punch)
end


function carts:cart_physical_interactions(self,dir)
	local speed_mod
	local pos = self.object:getpos()
	if self.couple1 or self.couple2 then
		for _,object in ipairs(minetest.env:get_objects_inside_radius(pos, 6)) do
			--magnetise towards other carts
			if object:get_luaentity() == self.couple1 or object:get_luaentity() == self.couple2 then
				print("magnetizing")
				local pos2 = object:getpos()
				local modify = {}
				modify.x = (pos2.x - pos.x) * (dir.x*2)
				modify.z = (pos2.z - pos.z) * (dir.z*2)
				if vector.distance(pos, pos2) > 1 then
					if modify.x ~= 0 then
						speed_mod = modify.x
					elseif modify.z ~= 0 then
						speed_mod = modify.z
					end
				else
					speed_mod = -3
				end		
			end
			--[[
			if not object:is_player() then
				if object:get_luaentity().cart and object == self.couple1 then
					--couplers's position
					local pos2 = object:getpos()
					local modify = {}
					modify.x = (pos2.x - pos.x) * (dir.x*2)
					modify.z = (pos2.z - pos.z) * (dir.z*2)
					if vector.distance(pos, pos2) > 1 then
						if modify.x ~= 0 then
							speed_mod = modify.x
						elseif modify.z ~= 0 then
							speed_mod = modify.z
						end
					else
						speed_mod = -3
					end
				end
			end
			]]--
		end
	else --repel carts from other carts and players
		for _,object in ipairs(minetest.env:get_objects_inside_radius(pos, 2)) do

			if object:is_player() and object:get_player_name() ~= self.driver then
				--player's position
				local pos2 = object:getpos()
				local modify = {}
				modify.x = (pos.x - pos2.x) * (dir.x*2)
				modify.z = (pos.z - pos2.z) * (dir.z*2)
				if modify.x ~= 0 then
					speed_mod = modify.x
				elseif modify.z ~= 0 then
					speed_mod = modify.z
				end
			elseif not object:is_player() and self.object ~= object and object:get_luaentity().cart == true then
				--cart's position
				local pos2 = object:getpos()
				local modify = {}
				modify.x = (pos.x - pos2.x) * (dir.x*2)
				modify.z = (pos.z - pos2.z) * (dir.z*2)
				if modify.x ~= 0 then
					speed_mod = modify.x
				elseif modify.z ~= 0 then
					speed_mod = modify.z
				end
			end
		end
	end
	return(speed_mod)
end
