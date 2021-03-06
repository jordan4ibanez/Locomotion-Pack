
--[[goals:
Literally copied from forum post

Tunneler
A node/entity which digs 3x3 into the ground or wall which places power rail or ladders depending on the direction. 
Powered by coal or fuel items and gets items (rails, coal, torches) placed in it and uses them to power itself and place rails 
or ladders where it's going.

Locomotion Pack
Modified default carts which does a few things extra. 
You can place chests, furnaces, a tunnel boar(hence tunneler mod), and tnt in it. 

A crowbar to link carts to each other. Furnace in carts allows you to open up a gui in the cart and put in fuel and adjust speed. 
With the cart linking the furnace cart would pull anything behind it or push anything in front of it...some how. 
Chest carts work like chests. Tunneler carts do what is above. 

A hopper cart which collects items around it, can be linked behind chest carts to put items in chests. 
These could have a setting to force load the mapblocks around it to have automated world trains placed 
by admins that can't be destroyed by players to take them to shops, houses, or other things.

You could create an automated bore-ing train like this:
Bore-Hopper-Chest-Furnace-Optional Default Cart to ride in

Torch Cart
adds in cart which lights up area
]]--


carts = {}
carts.modpath = minetest.get_modpath("carts")
carts.railparams = {}

-- Maximal speed of the cart in m/s (min = -1)
carts.speed_max = 7
-- Set to -1 to disable punching the cart from inside (min = -1)
carts.punch_speed_max = 5

dofile(carts.modpath.."/functions.lua")
dofile(carts.modpath.."/rails.lua")
dofile(carts.modpath.."/crowbar.lua")

-- Support for non-default games
if not default.player_attached then
	default.player_attached = {}
end

-- Add support to couple carts together
carts.couple = {}

local cart_entity = {
	physical = true, -- otherwise going uphill breaks
	collide_with_objects = true, -- collides with players and other carts
	collisionbox = {-0.5, 1.0, -0.5, 0.5, 1.5, 0.5},
	visual = "mesh",
	mesh = "carts_cart.b3d",
	visual_size = {x=1, y=1},
	textures = {"carts_cart.png"},

	cart = true,
	driver = nil,
	punched = false, -- used to re-send velocity and position
	velocity = {x=0, y=0, z=0}, -- only used on punch
	old_dir = {x=1, y=0, z=0}, -- random value to start the cart on punch
	old_pos = nil,
	old_switch = 0,
	railtype = nil,
	attached_item = nil,
	
	--cart attachment vars "Cart coupling"
	--only allow two attachment because 
	couple1 = nil,
	couple2 = nil,
	
	--vars for allowing player's to turn carts into furnace,chest, and borer carts
}

function cart_entity:on_rightclick(clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local player_name = clicker:get_player_name()
	local item = clicker:get_wielded_item():to_table().name

	if item == "carts:crowbar" then
		carts:couple_cart(self.object,clicker)
	elseif item == "default:furnace" then
		-- Collect dropped items
		local obj = minetest.add_item(self.object:getpos(), item)
		--print(dump(obj:get_luaentity().itemstring))
		obj:set_attach(self.object, "", {x=0, y=5, z=0}, {x=0, y=0, z=0})
		self.attached_item= obj
		obj:set_properties({visual_size = {x=0.5,y=0.5}})
	else
		if self.driver and player_name == self.driver then
			self.driver = nil
			carts:manage_attachment(clicker, nil)
		elseif not self.driver then
			self.driver = player_name
			carts:manage_attachment(clicker, self.object)
		end
	end
end

function cart_entity:on_activate(staticdata, dtime_s)
	self.object:set_armor_groups({immortal=1})
	if string.sub(staticdata, 1, string.len("return")) ~= "return" then
		return
	end
	local data = minetest.deserialize(staticdata)
	if not data or type(data) ~= "table" then
		return
	end
	self.railtype = data.railtype
	if data.old_dir then
		self.old_dir = data.old_dir
	end
	if data.old_vel then
		self.old_vel = data.old_vel
	end
end

function cart_entity:get_staticdata()
	return minetest.serialize({
		railtype = self.railtype,
		old_dir = self.old_dir,
		old_vel = self.old_vel
	})
end

function cart_entity:on_punch(puncher, time_from_last_punch, tool_capabilities, direction)
	local pos = self.object:getpos()
	if not self.railtype then
		local node = minetest.get_node(pos).name
		self.railtype = minetest.get_item_group(node, "connect_to_raillike")
	end

	if not puncher or not puncher:is_player() then
		local cart_dir = carts:get_rail_direction(pos, self.old_dir, nil, nil, self.railtype)
		if vector.equals(cart_dir, {x=0, y=0, z=0}) then
			return
		end
		self.velocity = vector.multiply(cart_dir, 3)
		self.punched = true
		return
	end

	if puncher:get_player_control().sneak then
		if self.sound_handle then
			minetest.sound_stop(self.sound_handle)
		end
		-- Pick up cart: Drop all attachments
		if self.driver then
			if self.old_pos then
				self.object:setpos(self.old_pos)
			end
			local player = minetest.get_player_by_name(self.driver)
			carts:manage_attachment(player, nil)
		end

		if self.attached_item then
			self.attached_item:set_detach()
		end


		local leftover = puncher:get_inventory():add_item("main", "carts:cart")
		if not leftover:is_empty() then
			minetest.add_item(self.object:getpos(), leftover)
		end
		self.object:remove()
		return
	end

	local vel = self.object:getvelocity()
	if puncher:get_player_name() == self.driver then
		if math.abs(vel.x + vel.z) > carts.punch_speed_max then
			return
		end
	end
	print(dump(puncher:get_look_dir()))
	local punch_dir = carts:velocity_to_dir(puncher:get_look_dir())
	punch_dir.y = 0
	local cart_dir = carts:get_rail_direction(pos, punch_dir, nil, nil, self.railtype)
	if vector.equals(cart_dir, {x=0, y=0, z=0}) then
		return
	end

	local punch_interval = 1
	if tool_capabilities and tool_capabilities.full_punch_interval then
		punch_interval = tool_capabilities.full_punch_interval
	end
	time_from_last_punch = math.min(time_from_last_punch or punch_interval, punch_interval)
	local f = 2 * (time_from_last_punch / punch_interval)

	self.velocity = vector.multiply(cart_dir, f)
	self.old_dir = cart_dir
	self.punched = true
end

local function rail_on_step_event(handler, obj, dtime)
	if handler then
		handler(obj, dtime)
	end
end

-- sound refresh interval = 1.0sec
local function rail_sound(self, dtime)
	if not self.sound_ttl then
		self.sound_ttl = 1.0
		return
	elseif self.sound_ttl > 0 then
		self.sound_ttl = self.sound_ttl - dtime
		return
	end
	self.sound_ttl = 1.0
	if self.sound_handle then
		local handle = self.sound_handle
		self.sound_handle = nil
		minetest.after(0.2, minetest.sound_stop, handle)
	end
	local vel = self.object:getvelocity()
	local speed = vector.length(vel)
	if speed > 0 then
		self.sound_handle = minetest.sound_play(
			"carts_cart_moving", {
			object = self.object,
			gain = (speed / carts.speed_max) / 2,
			loop = true,
		})
	end
end

local function rail_on_step(self, dtime)
	local pos = self.object:getpos()
	local node = minetest.get_node(pos)
	local railparams = carts.railparams[node.name] or {}

	local vel = self.object:getvelocity()
	
	--allow players to push carts around with their presence
	
	if not self.old_vel or self.old_vel.x == 0 and self.old_vel.y == 0 and self.old_vel.z == 0 then
		--furnace cart
		print("trying")
		if self.attached_item and self.attached_item:get_luaentity().itemstring == "default:furnace" then
			--local cart_dir = carts:get_rail_direction(pos, self.old_dir, nil, nil, self.railtype)
			local punch_interval = 1
			time_from_last_punch = math.min(time_from_last_punch or punch_interval, punch_interval)
			local f = 3 * (time_from_last_punch / punch_interval)
			self.velocity = vector.multiply(self.old_dir, f)
			self.old_dir = cart_dir
			self.punched = true
			print("started furnace cart")
		end
		--normal repulsion
		for _,object in ipairs(minetest.env:get_objects_inside_radius(pos, 2)) do
			--if there is an ent coupled to it, check for it
			if object:is_player() and object:get_player_name() ~= self.driver then
				carts:cart_repulsion_start(self,object)
			elseif not object:is_player() and self.object ~= object and object:get_luaentity().cart == true then
				carts:cart_repulsion_start(self,object)
			end
		end
		--cart coupling
		for _,object in ipairs(minetest.env:get_objects_inside_radius(pos, 6)) do
			if self.couple1 ~= nil or self.couple2 ~= nil then
				if not object:is_player() then
					carts:start_magnet(self,object)
				end
			end
		end
	end
	
	local update = {}
	if self.punched then
		vel = vector.add(vel, self.velocity)
		self.object:setvelocity(vel)
		self.old_dir.y = 0
	elseif vector.equals(vel, {x=0, y=0, z=0}) then
		return
	end

	-- stop cart if velocity vector flips
	if self.old_vel and (((self.old_vel.x * vel.x) < 0) or
			((self.old_vel.z * vel.z) < 0)) and
			(self.old_vel.y == 0) then
		self.old_dir = {x = 0, y = 0, z = 0}
		self.old_vel = {x = 0, y = 0, z = 0}
		self.velocity = {x = 0, y = 0, z = 0}
		self.old_pos = pos
		self.object:setvelocity(vector.new())
		self.object:setacceleration(vector.new())
		rail_on_step_event(railparams.on_step, self, dtime)
		return
	end
	self.old_vel = vector.new(vel)

	if self.old_pos and not self.punched then
		local flo_pos = vector.round(pos)
		local flo_old = vector.round(self.old_pos)
		if vector.equals(flo_pos, flo_old) then
			-- Do not check one node multiple times
			rail_on_step_event(railparams.on_step, self, dtime)
			return
		end
	end

	local ctrl, player

	-- Get player controls
	if self.driver then
		player = minetest.get_player_by_name(self.driver)
		if player then
			ctrl = player:get_player_control()
		end
	end
	
	if self.old_pos then
		-- Detection for "skipping" nodes
		local expected_pos = vector.add(self.old_pos, self.old_dir)
		local found_path = carts:pathfinder(
			pos, expected_pos, self.old_dir, ctrl, self.old_switch, self.railtype
		)

		if not found_path then
			-- No rail found: reset back to the expected position
			pos = vector.new(self.old_pos)
			update.pos = true
		end
	end

	local cart_dir = carts:velocity_to_dir(vel)

	-- dir:         New moving direction of the cart
	-- switch_keys: Currently pressed L/R key, used to ignore the key on the next rail node
	local dir, switch_keys = carts:get_rail_direction(
		pos, cart_dir, ctrl, self.old_switch, self.railtype
	)

	local new_acc = {x=0, y=0, z=0}
	
	if vector.equals(dir, {x=0, y=0, z=0}) then
		vel = {x=0, y=0, z=0}
		pos = vector.round(pos)
		update.pos = true
		update.vel = true
	else
		-- If the direction changed
		if dir.x ~= 0 and self.old_dir.z ~= 0 then
			vel.x = dir.x * math.abs(vel.z)
			vel.z = 0
			pos.z = math.floor(pos.z + 0.5)
			update.pos = true
		end
		if dir.z ~= 0 and self.old_dir.x ~= 0 then
			vel.z = dir.z * math.abs(vel.x)
			vel.x = 0
			pos.x = math.floor(pos.x + 0.5)
			update.pos = true
		end
		-- Up, down?
		if dir.y ~= self.old_dir.y then
			vel.y = dir.y * math.abs(vel.x + vel.z)
			pos = vector.round(pos)
			update.pos = true
		end

		-- Slow down or speed up..
		local acc = dir.y * -4.0

		-- no need to check for railparams == nil since we always make it exist.
		
		--allow players to move carts by pushing them
		local speed_mod = carts:cart_physical_interactions(self,dir)

		if self.attached_item and self.attached_item:get_luaentity().itemstring == "default:furnace" then
			speed_mod = carts.speed_max
			minetest.add_particle({
				pos = {x=pos.x, y=pos.y + 1, z=pos.z},
				velocity = {x=0, y=0, z=0},
				acceleration = {x=0, y=3, z=0},
				expirationtime = 1,
				size = math.random(1,3),
				collisiondetection = false,
				vertical = false,
				texture = "carts_smoke.png",
			})
		end
		
		if not speed_mod then
			speed_mod = railparams.acceleration
		end
		if speed_mod and speed_mod ~= 0 then
			-- Try to make it similar to the original carts mod
			acc = acc + speed_mod
		else
			-- Handbrake
			if ctrl and ctrl.down then
				acc = acc - 1.6
			else
				acc = acc - 0.4
			end
		end

		new_acc = vector.multiply(dir, acc)
	end

	-- Limits
	local max_vel = carts.speed_max
	for _,v in ipairs({"x","y","z"}) do
		if math.abs(vel[v]) > max_vel then
			vel[v] = carts:get_sign(vel[v]) * max_vel
			new_acc[v] = 0
			update.vel = true
		end
	end

	self.object:setacceleration(new_acc)
	self.old_pos = vector.new(pos)
	if not vector.equals(dir, {x=0, y=0, z=0}) then
		self.old_dir = vector.new(dir)
	end
	self.old_switch = switch_keys

	if self.punched then
		self.punched = false
		update.vel = true
	end


	if not (update.vel or update.pos) then
		rail_on_step_event(railparams.on_step, self, dtime)
		return
	end

	local yaw = 0
	if self.old_dir.x < 0 then
		yaw = 0.5
	elseif self.old_dir.x > 0 then
		yaw = 1.5
	elseif self.old_dir.z < 0 then
		yaw = 1
	end
	self.object:setyaw(yaw * math.pi)

	local anim = {x=0, y=0}
	if dir.y == -1 then
		anim = {x=1, y=1}
	elseif dir.y == 1 then
		anim = {x=2, y=2}
	end
	self.object:set_animation(anim, 1, 0)

	self.object:setvelocity(vel)
	if update.pos then
		self.object:setpos(pos)
	end

	-- call event handler
	rail_on_step_event(railparams.on_step, self, dtime)
end

function cart_entity:on_step(dtime)
	rail_on_step(self, dtime)
	rail_sound(self, dtime)
end

minetest.register_entity("carts:cart", cart_entity)

minetest.register_craftitem("carts:cart", {
	description = "Cart (Sneak+Click to pick up)",
	inventory_image = minetest.inventorycube("carts_cart_top.png", "carts_cart_side.png", "carts_cart_side.png"),
	wield_image = "carts_cart_side.png",
	on_place = function(itemstack, placer, pointed_thing)
		if not pointed_thing.type == "node" then
			return
		end
		if carts:is_rail(pointed_thing.under) then
			minetest.add_entity(pointed_thing.under, "carts:cart")
		elseif carts:is_rail(pointed_thing.above) then
			minetest.add_entity(pointed_thing.above, "carts:cart")
		else
			return
		end

		minetest.sound_play({name = "default_place_node_metal", gain = 0.5},
			{pos = pointed_thing.above})

		if not minetest.setting_getbool("creative_mode") then
			itemstack:take_item()
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = "carts:cart",
	recipe = {
		{"default:steel_ingot", "", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	},
})
