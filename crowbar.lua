-- A crowbar to connect carts and quickly remove rails
minetest.register_tool("carts:crowbar", {
	description = "Crowbar",
	inventory_image = "carts_crowbar.png^[transformR270",
	tool_capabilities = {
		full_punch_interval = 0.9,
		max_drop_level=3,
		groupcaps={
			rail = {times={[1]=0.1, [2]=0.1, [3]=0.1}, uses=20, maxlevel=3},
		},
		damage_groups = {fleshy=5},
	},
	sound = {breaks = "default_tool_breaks"},
})
