
local serpent = require "serpent"
local sets = require "sets"
local item_values = {}



function item_values.calculate(recipe_graph, raw_values, allowed_recipes, other_planet_calculated_values, spoilable_items, params)
    params = params or {}

    if not params.max_iterations then
        -- The number of iterations to simulate for convergence
        params.max_iterations = 100
    end

    if not params.convergence_threshold then
        -- The threshold for convergence
        params.convergence_threshold = 0.001
    end

    if not params.energy_coefficient then
        -- The effect that recipe crafting time has on the values of the recipe's products
        params.energy_coefficient = 0.05
    end

    if not params.item_complexity_coefficient then
        -- Multiplier for every distinct (non-fluid) item in the ingredients of a recipe.
        params.complexity_coefficient = 0.25
    end

    if not params.fluid_complexity_coefficient then
        -- Multiplier for every distinct fluid in the ingredients of a recipe.
        -- NOTE: TODO: NOT YET IMPLEMENTED
        params.item_fluid_multiplier = 0.35
    end

    if not params.raw_multiplier then
        -- Multiplier applied regardless of any conditions.
        params.raw_multiplier = 0.25
    end

    if not params.spoilable_coefficient then
        -- Multiplier applied to any item that is spoilable.
        params.spoilable_coefficient = 0.75
    end

    if not params.interplanetary_coefficient then
        -- Multiplier applied to the values of items from other planets.
        params.interplanetary_coefficient = 5
    end

    if not params.planet_depth_coefficient then
        -- Multiplier for each planet outward from Nauvis (Nauvis = 0, Vulcanus = Fulgora = Gleba = 1, Aquilo = 2)
        -- NOTE: TODO: NOT YET IMPLEMENTED
        params.planet_depth_coefficient = 0.5
    end

    if not params.update_sensitivity then
        -- The time scale of the simulation
        -- (is that a good way to describe it? not sure because different values can lead to different equilibria)
        params.update_sensitivity = 0.01
    end

    if not params.update_sensitivity_decay then
        -- The rate at which the update sensitivity decays per iteration
        params.update_sensitivity_decay = 0.9999
    end

    if not params.depth_sensitivity then
        -- The effect that recipe depth has on the adjustments to the values of the recipe's products and ingredients
        -- Note: this does not necessarily mean that deeper recipes have greater influence on the values of their items
        params.depth_sensitivity = 2
    end

    if not params.magnitude_penalty then
        -- The penalty for divergence toward infinity
        params.magnitude_penalty = 0.001
    end

    if not params.backward_calculation_coefficient then
        -- The effect that a recipe's product values have on the values of the recipe's ingredients.
        params.backward_calculation_coefficient = 0.1
    end

    if not params.min_selection_weight then
        -- Weight for minimum selection vs averaging (1.0 = pure minimum, 0.0 = pure average)
        -- Higher values favor the cheapest production path, lower values smooth across all recipes
        params.min_selection_weight = 0.7
    end

    if not params.initial_values then
        -- The initial values of all items
        params.initial_values = {}
    end

    if not params.tracked_calculations then
        -- Items whose value calculations should be tracked in detail
        params.tracked_calculations = {}
    end

    -- For backward compatibility, if iron-plate tracking was requested before
    if not params.tracked_calculations then
        params.tracked_calculations = {}
    end

    -- Logging
    local log
    if params.logging then
        log = print
    else
        log = function(...) end
    end

    -- Pre-process the recipe graph to calculate item depths (by BFS) and recipe depths (calculated from item BFS)
    item_values.calculate_bfs_depths(recipe_graph, raw_values)
    item_values.calculate_recipe_bfs_depths(recipe_graph)

    -- Values table
    local values = {}

    -- Target values table (stores suggested values from each recipe, for minimum selection)
    local target_values = {}

    -- Update sensitivity, to be decayed after each iteration
    local update_sensitivity = params.update_sensitivity
    local cur_update_sensitivity = update_sensitivity -- gets scaled by total increment of item values so that convergence isn't overshot

    -- Initialize the values of all items to the raw values, or 10 for an item if it isn't raw
    for _, item_name in pairs(recipe_graph.all_items) do
        values[item_name] = raw_values[item_name] or params.initial_values[item_name] or 10
    end

    local function is_raw_or_interplanetary(item_name)
        return raw_values[item_name] ~= nil or other_planet_calculated_values[item_name] ~= nil
    end

    local function get_raw_or_interplanetary_value(item_name)
        return raw_values[item_name] or (other_planet_calculated_values[item_name] * params.interplanetary_coefficient)
    end

    -- Special logging function for tracked items
    local function log_item_calculation(item_name, message)
        if params.tracked_calculations[item_name] then
            print("[" .. item_name:upper() .. "] " .. message)
        end
    end

    -- Log initial values for tracked items
    for item_name, _ in pairs(params.tracked_calculations) do
        log_item_calculation(item_name, "Initial value: " .. (values[item_name] or "N/A"))
    end

    -- Pre-processing to ensure that products don't include ingredients
    for recipe_name, recipe in pairs(recipe_graph.recipes_by_name) do

        local s = "RECIPE " .. recipe_name .. " | ingredients: ["
        for i, ing in ipairs(recipe.ingredients) do
            if i > 1 then
                s = s .. " + "
            end
            s = s .. ing.name .. " x" .. ing.amount
            for p, prod in ipairs(recipe.products) do
                if ing.name == prod.name then
                    -- Subtract from "both sides" so that the math checks out
                    -- This helps to prevent divergence toward infinity
                    if ing.amount > prod.amount then
                        ing.amount = ing.amount - prod.amount
                        prod.amount = 0
                        table.remove(recipe.products, p)
                        log("removed ingredient " .. ing.name .. " from recipe " .. recipe_name)
                    elseif ing.amount < prod.amount then
                        prod.amount = prod.amount - ing.amount
                        ing.amount = 0
                        table.remove(recipe.ingredients, i)
                        log("removed product " .. prod.name .. " from recipe " .. recipe_name)
                    else
                        log("WARNING: recipe ingredients and products of " .. recipe_name .. " have the same amounts of " .. ing.name)
                        log(">> IT MAY NEED TO BE HANDLED SPECIALLY <<")
                    end
                end
            end
        end
        s = s .. "] | products: ["
        for p, prod in ipairs(recipe.products) do
            if p > 1 then
                s = s .. " + "
            end
            s = s .. prod.name .. " x" .. prod.amount
        end
        s = s .. "]"
        log(s)
    end

    -- Start simulation
    for n = 1, params.max_iterations do
        if n % 100 == 0 then
            -- log("Iteration " .. n)
            for item_name, _ in pairs(params.tracked_calculations) do
                log_item_calculation(item_name, "======= START OF ITERATION " .. n .. " =======")
                log_item_calculation(item_name, "Current value: " .. values[item_name])
            end
        end

        -- For each iteration, reset all target values
        local total_abs_increment = 0
        for _, item_name in pairs(recipe_graph.all_items) do
            target_values[item_name] = {}
        end

        -- Calculate the increments
        for recipe_name, recipe in pairs(recipe_graph.recipes_by_name) do
            -- Only search allowed recipes
            if allowed_recipes[recipe_name] then
                -- Check if this recipe involves any tracked items or spoilable ingredients
                local spoilable_count = 0
                local tracked_items_involved = {}
                for _, ing in pairs(recipe.ingredients) do
                    if params.tracked_calculations[ing.name] then
                        tracked_items_involved[ing.name] = true
                    end
                    if spoilable_items[ing.name] then
                        spoilable_count = spoilable_count + 1
                    end
                end
                for _, prod in pairs(recipe.products) do
                    if params.tracked_calculations[prod.name] then
                        tracked_items_involved[prod.name] = true
                    end
                end

                -- Log recipe details for each tracked item involved
                for item_name, _ in pairs(tracked_items_involved) do
                    log_item_calculation(item_name, "Processing recipe: " .. recipe_name)
                    log_item_calculation(item_name, "  Energy: " .. recipe.energy)
                    log_item_calculation(item_name, "  Ingredients:")
                    for _, ing in pairs(recipe.ingredients) do
                        log_item_calculation(item_name, "    - " .. ing.name .. " x" .. ing.amount .. " (value: " .. (other_planet_calculated_values[ing.name] or values[ing.name]) .. ")")
                    end
                    log_item_calculation(item_name, "  Products:")
                    for _, prod in pairs(recipe.products) do
                        log_item_calculation(item_name, "    - " .. prod.name .. " x" .. prod.amount .. " (value: " .. (other_planet_calculated_values[prod.name] or values[prod.name]) .. ")")
                    end
                end

                -- Store variables so they can be swapped once
                local ingredients = recipe.ingredients
                local products = recipe.products

                -- Calculate multiplier for products from ingredients.
                local energy_mult = 1 + params.energy_coefficient * recipe.energy
                local item_complexity_mult = 1 + params.item_complexity_coefficient * #ingredients
                local spoilable_mult = 1 + params.spoilable_coefficient * spoilable_count
                local mult = energy_mult * item_complexity_mult * spoilable_mult * (1 + params.raw_multiplier)

                for item_name, _ in pairs(tracked_items_involved) do
                    log_item_calculation(item_name, "  Multipliers:")
                    log_item_calculation(item_name, "    - Energy multiplier: " .. energy_mult)
                    log_item_calculation(item_name, "    - Complexity multiplier: " .. item_complexity_mult)
                    log_item_calculation(item_name, "    - Spoilable multiplier: " .. spoilable_mult)
                    log_item_calculation(item_name, "    - Final multiplier: " .. mult)
                end

                -- Process recipe, swapping ingredients and products to calculate values in both directions (e.g. nutrients get calculated, then biter eggs get inversely calculated from nutrients)
                for i = 1, 2 do
                    -- For repeatedly checking whether the ingredients and products are swapped
                    local swapped = i == 2

                    for item_name, _ in pairs(tracked_items_involved) do
                        log_item_calculation(item_name, "  Direction: " .. (swapped and "products->ingredients" or "ingredients->products"))
                    end

                    -- Sum the values of the ingredients (or products if swapped)
                    local ingredients_value = 0
                    for _, ing in pairs(ingredients) do
                        ingredients_value = ingredients_value + (other_planet_calculated_values[ing.name] or values[ing.name]) * ing.amount
                    end

                    for item_name, _ in pairs(tracked_items_involved) do
                        log_item_calculation(item_name, "  Total ingredients value: " .. ingredients_value)
                    end

                    -- Divide the ingredient value if the products and ingredients are swapped (to avoid divergence toward infinity)
                    if swapped then
                        ingredients_value = ingredients_value / mult
                        for item_name, _ in pairs(tracked_items_involved) do
                            log_item_calculation(item_name, "  Adjusted ingredients value (after division): " .. ingredients_value)
                        end
                    end

                    -- This is the total value for products (or ingredients if swapped), to be adjusted before calculating increments
                    local total_product_value = ingredients_value

                    -- If there are raw values, then we need to subtract the raw values from the total product value (pre-multiplication) because we can't change the raw values
                    local num_raw = 0
                    for _, prod in pairs(products) do
                        if is_raw_or_interplanetary(prod.name) then
                            num_raw = num_raw + 1

                            local dec = get_raw_or_interplanetary_value(prod.name) * prod.amount
                            if swapped then
                                -- Make sure that if products and ingredients are swapped, the decrement is divided just like the pre-adjusted product amount (to respect the relative ratios)
                                dec = dec / mult
                            end

                            total_product_value = total_product_value - dec

                            for item_name, _ in pairs(tracked_items_involved) do
                                log_item_calculation(item_name, "  Subtracted raw value for " .. prod.name .. ": " .. dec)
                                log_item_calculation(item_name, "  Adjusted product value: " .. total_product_value)
                            end
                        end
                    end

                    -- If the products (or ingredients if already swapped, etc.) are only raw items, then no calculations are needed.
                    -- Instead, let the products and ingredients swap so that the raw items in the products actually determine the values of the ingredients
                    if num_raw < #products then
                        -- Multiply product value if the products and ingredients are NOT swapped
                        if not swapped then
                            total_product_value = total_product_value * mult
                            for item_name, _ in pairs(tracked_items_involved) do
                                log_item_calculation(item_name, "  Adjusted product value (after multiplication): " .. total_product_value)
                            end
                        end

                        -- Calculate the new per-product scaled (multiplied by amount of each item) value, skipping values of raw items
                        local per_product_scaled_value = total_product_value / (#products - num_raw)

                        for item_name, _ in pairs(tracked_items_involved) do
                            log_item_calculation(item_name, "  Per product scaled value: " .. per_product_scaled_value)
                            log_item_calculation(item_name, "  Number of non-raw products: " .. (#products - num_raw))
                        end

                        -- Calculate target values based on the new per-product scaled value to each product, skipping raw values
                        for _, prod in pairs(products) do
                            if not is_raw_or_interplanetary(prod.name) then
                                -- The per-product value is scaled, so rescale it to get the correct value for the item.
                                local new_value = per_product_scaled_value / prod.amount

                                -- If swapped (doing backward calculation from products to ingredients), skip if coefficient is 0
                                if swapped and params.backward_calculation_coefficient == 0 then
                                    -- Skip backward calculations when coefficient is 0
                                else
                                    -- Store the target value suggested by this recipe
                                    -- Use a unique key for forward vs backward to allow both directions
                                    local key = recipe_name .. (swapped and "_bwd" or "_fwd")
                                    target_values[prod.name][key] = new_value

                                    if params.tracked_calculations[prod.name] then
                                        log_item_calculation(prod.name, "  Calculated for " .. prod.name .. ":")
                                        log_item_calculation(prod.name, "    - Target value: " .. new_value)
                                        log_item_calculation(prod.name, "    - Current value: " .. values[prod.name])
                                        log_item_calculation(prod.name, "    - Recipe: " .. key)
                                        log_item_calculation(prod.name, "    - Direction: " .. (swapped and "backward" or "forward"))
                                    end
                                end
                            end
                        end
                    end

                    -- Swap ingredients and products for the next iteration, making it so that item values can be calculated in both directions
                    ingredients, products = products, ingredients
                end
            end
        end

        -- Apply target values using minimum selection
        for tracked_item, _ in pairs(params.tracked_calculations) do
            if target_values[tracked_item] then
                log_item_calculation(tracked_item, "Target values for " .. tracked_item .. ":")
                for recipe_name, target in pairs(target_values[tracked_item]) do
                    log_item_calculation(tracked_item, "  From recipe " .. recipe_name .. ": " .. target)
                end
            end
        end

        for item_name, targets_for_item in pairs(target_values) do
            -- Count how many target values there are for this item
            local num_targets = 0
            for _ in pairs(targets_for_item) do
                num_targets = num_targets + 1
            end

            -- Hold raw values constant (this shouldn't be necessary, but it's a failsafe)
            if not is_raw_or_interplanetary(item_name) then
                -- If there are any target values, find the minimum (cheapest production path)
                if num_targets > 0 then
                    -- Find minimum and average target values across all recipes
                    local min_target = math.huge
                    local min_recipe = nil
                    local sum_target = 0

                    if params.tracked_calculations[item_name] then
                        log_item_calculation(item_name, "Finding target values:")
                    end

                    for recipe_name, target in pairs(targets_for_item) do
                        if params.tracked_calculations[item_name] then
                            log_item_calculation(item_name, "  Recipe " .. recipe_name .. ": " .. target)
                        end

                        sum_target = sum_target + target
                        if target < min_target then
                            min_target = target
                            min_recipe = recipe_name
                        end
                    end

                    local avg_target = sum_target / num_targets

                    -- Blend minimum and average based on min_selection_weight
                    -- weight=1.0 means pure minimum, weight=0.0 means pure average
                    local blended_target = params.min_selection_weight * min_target + (1 - params.min_selection_weight) * avg_target

                    if params.tracked_calculations[item_name] then
                        log_item_calculation(item_name, "  Minimum target: " .. min_target .. " (from " .. (min_recipe or "unknown") .. ")")
                        log_item_calculation(item_name, "  Average target: " .. avg_target)
                        log_item_calculation(item_name, "  Blended target (weight=" .. params.min_selection_weight .. "): " .. blended_target)
                    end

                    -- Calculate increment from blended target value
                    local raw_increment = blended_target - values[item_name]

                    -- Apply sqrt dampening to prevent large jumps (preserving sign)
                    local increment
                    if raw_increment > 0 then
                        increment = math.sqrt(raw_increment)
                    elseif raw_increment < 0 then
                        increment = -math.sqrt(-raw_increment)
                    else
                        increment = 0
                    end

                    -- Retrieve the graph depth of the item
                    local depth = recipe_graph.item_bfs_depths[item_name] or 0

                    -- Scale the increment for deeper items (negative depth_sensitivity means deeper = smaller adjustments)
                    local depth_scaled = increment * ((1 + depth) ^ params.depth_sensitivity)

                    -- Scale down the increment so that the dynamical system can actually converge to an equilibrium
                    local final_increment = depth_scaled * cur_update_sensitivity

                    if params.tracked_calculations[item_name] then
                        log_item_calculation(item_name, "  Current value: " .. values[item_name])
                        log_item_calculation(item_name, "  Raw increment: " .. raw_increment)
                        log_item_calculation(item_name, "  Sqrt-dampened increment: " .. increment)
                        log_item_calculation(item_name, "  Item depth: " .. depth)
                        log_item_calculation(item_name, "  Depth scaling factor: " .. ((1 + depth) ^ params.depth_sensitivity))
                        log_item_calculation(item_name, "  After depth scaling: " .. depth_scaled)
                        log_item_calculation(item_name, "  Current update sensitivity: " .. cur_update_sensitivity)
                        log_item_calculation(item_name, "  Final increment: " .. final_increment)
                    end

                    -- Apply the final calculated increment
                    -- Scale down the FINAL result to penalize divergence toward infinity
                    local prev_value = values[item_name]
                    local new_value = (prev_value + final_increment) * (1 - params.magnitude_penalty)
                    if new_value > prev_value * 1.1 then
                        new_value = prev_value * 1.1
                    elseif new_value < prev_value * 0.9 then
                        new_value = prev_value * 0.9
                    end
                    values[item_name] = math.max(0.001, new_value)

                    if params.tracked_calculations[item_name] then
                        log_item_calculation(item_name, "  Previous value: " .. prev_value)
                        log_item_calculation(item_name, "  New value before clamping: " .. (prev_value + final_increment) * (1 - params.magnitude_penalty))
                        log_item_calculation(item_name, "  Final new value (after clamping): " .. values[item_name])
                        log_item_calculation(item_name, "  Change: " .. (values[item_name] - prev_value))
                    end

                    -- Track the overall change
                    total_abs_increment = total_abs_increment + math.abs(values[item_name] - prev_value)
                end
            end
        end

        if values["iron-bacteria"] ~= 10 then
            -- this is GLEBA
            -- terrible idea to be hardcoding, but it's so much easier than implementing a whole other part of this algorithm just to handle TWO items
            values["iron-ore"] = values["iron-bacteria"]
            values["copper-ore"] = values["copper-bacteria"]
        end

        if n % 100 == 0 then
            log("(Iteration " .. n .. ") Total absolute increment: " .. total_abs_increment .. " | Update sensitivity: " .. update_sensitivity)

            -- End of iteration logging for tracked items
            for item_name, _ in pairs(params.tracked_calculations) do
                log_item_calculation(item_name, "======= END OF ITERATION " .. n .. " =======")
                log_item_calculation(item_name, "Final value: " .. values[item_name])
            end
        elseif n % 10000 == 0 then
            print(serpent.block(values))
        end

        -- Check if the dynamical system has converged to an acceptable equilibrium
        if total_abs_increment < params.convergence_threshold then
            log("Converged after " .. n .. " iterations (total_abs_increment = " .. total_abs_increment .. ")")
            break
        end

        -- Decay update sensitivity
        update_sensitivity = update_sensitivity * params.update_sensitivity_decay
        -- Ensure total_abs_increment is at least 1 to avoid negative log values
        cur_update_sensitivity = update_sensitivity * math.log(math.max(1, total_abs_increment)) * 0.0625
    end

    return values
end

function item_values.get_recipe_graph(recipe_tree)
    local recipe_graph = {made_from = {}, used_in = {}, recipes_by_name = {}, item_edges = {}, all_items = {}}
    local added_edges = {}
    for recipe_name, recipe in pairs(recipe_tree) do
        recipe_graph.recipes_by_name[recipe_name] = recipe
        for _, ing in pairs(recipe.ingredients) do
            local t = recipe_graph.used_in[ing.name]
            if not t then
                t = {}
                recipe_graph.used_in[ing.name] = t
            end
            table.insert(t, recipe.name)
            if not recipe_graph.all_items[ing.name] then
                recipe_graph.all_items[ing.name] = true
            end
        end
        for _, prod in pairs(recipe.products) do
            local t = recipe_graph.made_from[prod.name]
            if not t then
                t = {}
                recipe_graph.made_from[prod.name] = t
            end
            table.insert(t, recipe.name)
            if not recipe_graph.all_items[prod.name] then
                recipe_graph.all_items[prod.name] = true
            end
            for _, ing in pairs(recipe.ingredients) do
                local edge_key = ing.name .. "->" .. prod.name
                if not added_edges[edge_key] then
                    added_edges[edge_key] = true
                    table.insert(recipe_graph.item_edges, {ing.name, prod.name})
                end
            end
        end
    end
    recipe_graph.all_items = sets.to_array(recipe_graph.all_items)
    return recipe_graph
end

function item_values.calculate_bfs_depths(recipe_graph, raw_items)
    -- Initialize BFS depths for all items
    local bfs_depths = {}
    for _, item in pairs(recipe_graph.all_items) do
        bfs_depths[item] = nil -- nil means not visited yet
    end

    -- Set all raw items to depth 0
    local queue = {}

    -- First add items that are explicitly marked as raw
    if raw_items then
        for item_name, _ in pairs(raw_items) do
            if bfs_depths[item_name] == nil then  -- Avoid duplicates
                bfs_depths[item_name] = 0
                table.insert(queue, item_name)
            end
        end
    end

    -- Then add items that don't have any recipes producing them
    for _, item in pairs(recipe_graph.all_items) do
        if not recipe_graph.made_from[item] and bfs_depths[item] == nil then
            bfs_depths[item] = 0
            table.insert(queue, item)
        end
    end

    -- BFS to compute minimum depth for each item
    local current_item
    local index = 1
    while index <= #queue do
        current_item = queue[index]
        local current_depth = bfs_depths[current_item]

        -- Process all items that can be crafted using the current item
        if recipe_graph.used_in[current_item] then
            for _, recipe_name in ipairs(recipe_graph.used_in[current_item]) do
                local recipe = recipe_graph.recipes_by_name[recipe_name]

                -- Check all products from this recipe
                for _, product in ipairs(recipe.products) do
                    -- If we haven't visited this product yet
                    if bfs_depths[product.name] == nil then
                        bfs_depths[product.name] = current_depth + 1
                        table.insert(queue, product.name)
                    end
                end
            end
        end

        index = index + 1
    end

    -- Store the result in recipe_graph
    recipe_graph.item_bfs_depths = bfs_depths

    return bfs_depths -- Return for convenience
end

function item_values.calculate_recipe_bfs_depths(recipe_graph)
    -- -- Recipe depth is the maximum depth of its ingredients
    -- recipe_graph.recipe_bfs_depths = {}
    -- for recipe_name, recipe in pairs(recipe_graph.recipes_by_name) do
    --     local max_depth = -math.huge
    --     for _, ing in pairs(recipe.ingredients) do
    --         local depth = recipe_graph.item_bfs_depths[ing.name] or 0
    --         max_depth = math.max(max_depth, depth)
    --     end
    --     recipe_graph.recipe_bfs_depths[recipe_name] = max_depth
    -- end
    -- return recipe_graph.recipe_bfs_depths

    -- Recipe depth is the sum of depths of its ingredients
    recipe_graph.recipe_bfs_depths = {}
    for recipe_name, recipe in pairs(recipe_graph.recipes_by_name) do
        local total_depth = 0
        for _, ing in pairs(recipe.ingredients) do
            local depth = recipe_graph.item_bfs_depths[ing.name] or 0
            total_depth = total_depth + depth
        end
        recipe_graph.recipe_bfs_depths[recipe_name] = total_depth
    end
    return recipe_graph.recipe_bfs_depths
end



return item_values
