
local serpent = require "serpent" -- By Paul Kulchenko (2012-18), convenience tool for printing and serializing Lua tables.
local raw_values = require "raw_values" -- Base values for uncraftable items.
local spoilable_items = require "spoilable_items" -- Can be generated from the runtime data `prototypes.item`.
local item_values = require "item_values" -- The heart of the solver.
local recipe_tree = require "recipe_tree" -- This is a slightly modified structure of the runtime data `prototypes.recipe`, printed with serpent.block().
local allowed_recipes = require "allowed_recipes" -- Tediously select which recipes are allowed to be used in calculating item values.
local calculated_values = require "calculated_values" -- Saved calculations from previous solver outputs.  This helps to determine interplanetary values, e.g. lithium on Aquilo references the value of holmium plates on Fulgora.
local sets = require "sets"



-- DEFINE THE PLANET FOR WHICH ITEM VALUES ARE SOLVED
local PLANET_NAME = arg[1] or "nauvis"



-- print(serpent.block(recipe_tree))
spoilable_items = sets.new(spoilable_items)

-- Pre-process allowed_recipes to generate recycling recipes if applicable
local graph = item_values.get_recipe_graph(recipe_tree)
for _, recipe_name in pairs(allowed_recipes[PLANET_NAME]) do
    if recipe_name:sub(-10) == "-recycling" and recipe_name ~= "scrap-recycling" then
        local item_name = recipe_name:sub(1, -11)
        local recipe = recipe_tree[item_name]
        if recipe then
            if recipe.ingredients and recipe.products then
                local count_in_products = 1
                for _, product in pairs(recipe.products) do
                    if product.name == item_name then
                        count_in_products = product.amount
                    end
                end
                local ingredients = recipe.ingredients
                local rec_recipe = {
                    name = recipe_name,
                    energy = 0.2 * count_in_products, -- easier to multiply here than to divide each ingredient by count_in_products
                    ingredients = {
                        {name = item_name, amount = count_in_products},
                    },
                    products = ingredients,
                }
                print("adding recycling recipe: " .. serpent.line(rec_recipe))
                recipe_tree[recipe_name] = rec_recipe
            else
                print("recipe has no ingredients or products for " .. item_name)
            end
        else
            print("recipe is nil for " .. item_name)
        end
    end
end

-- Pre-process interplanetary values by checking for the minimum value for each item across all other planets
local interplanetary_values = {}
for surface_name, surface_values in pairs(calculated_values) do
    for item_name, value in pairs(surface_values) do
        interplanetary_values[item_name] = math.min(interplanetary_values[item_name] or math.huge, value)
    end
end

-- print(interplanetary_values["biter-egg"])
-- io.read()

-- Remove items from interplanetary values if they are produceable from recipes in allowed_recipes for the given planet
for _, recipe_name in pairs(allowed_recipes[PLANET_NAME]) do
    print(recipe_name)
    local recipe = recipe_tree[recipe_name]
    if not recipe then print(recipe_name) end
    -- for _, ing in pairs(recipe.ingredients) do
    --     interplanetary_values[ing.name] = nil
    -- end
    for _, prod in pairs(recipe.products) do
        interplanetary_values[prod.name] = nil
    end
end

-- And in Gleba's weird case, remove iron and copper ore
if PLANET_NAME == "gleba" then
    interplanetary_values["iron-ore"] = nil
    interplanetary_values["copper-ore"] = nil
end

-- Regenerate with new recycling recipes
graph = item_values.get_recipe_graph(recipe_tree)

-- print(serpent.block(graph.recipes_by_name))

local t = {}
for recipe_name, _ in pairs(graph.recipes_by_name) do
    table.insert(t, recipe_name)
end
-- print(serpent.block(t))

-- print(serpent.block(graph.made_from))

-- item_values.calculate(graph, raw_values)

-- local values, convergence = item_values.calculate_fixed_point_values(graph, raw_values)

-- print(serpent.block(values))
-- print(convergence)


local values

if PLANET_NAME == "nauvis" then
    values = item_values.calculate(graph, raw_values.nauvis, sets.new(allowed_recipes.nauvis), {}, spoilable_items, {
        logging = true,
        max_iterations = 100000,
        convergence_threshold = 1,
        energy_coefficient = 0.01,
        item_complexity_coefficient = 0.08,
        fluid_complexity_coefficient = 0.10,
        raw_multiplier = 0.04,
        planet_depth_coefficient = 0.5,
        update_sensitivity = 50,
        update_sensitivity_decay = 0.9994,
        depth_sensitivity = -2,
        magnitude_penalty = 0,
        backward_calculation_coefficient = 0,
        initial_values = {},
    })
elseif PLANET_NAME == "vulcanus" then
    values = item_values.calculate(graph, raw_values.vulcanus, sets.new(allowed_recipes.vulcanus), {}, spoilable_items, {
        logging = true,
        max_iterations = 100000,
        convergence_threshold = 1,
        energy_coefficient = 0.025,
        item_complexity_coefficient = 0.18,
        fluid_complexity_coefficient = 0.2,
        raw_multiplier = 0.075,
        planet_depth_coefficient = 0.5,
        update_sensitivity = 50,
        update_sensitivity_decay = 0.9994,
        depth_sensitivity = -2,
        magnitude_penalty = 0,
        backward_calculation_coefficient = 0,
        initial_values = {},
    })
elseif PLANET_NAME == "fulgora" then
    values = item_values.calculate(graph, raw_values.fulgora, sets.new(allowed_recipes.fulgora), {}, spoilable_items, {
        logging = true,
        max_iterations = 100000,
        convergence_threshold = 1,
        energy_coefficient = 0.025,
        item_complexity_coefficient = 0.18,
        fluid_complexity_coefficient = 0.2,
        raw_multiplier = 0.075,
        planet_depth_coefficient = 0.5,
        update_sensitivity = 50,
        update_sensitivity_decay = 0.9994,
        depth_sensitivity = -2,
        magnitude_penalty = 0,
        backward_calculation_coefficient = 0,
        initial_values = {},
    })
elseif PLANET_NAME == "gleba" then
    values = item_values.calculate(graph, raw_values.gleba, sets.new(allowed_recipes.gleba), interplanetary_values, spoilable_items, {
        logging = true,
        max_iterations = 100000,
        convergence_threshold = 0.1,
        energy_coefficient = 0.025,
        item_complexity_coefficient = 0.2,
        fluid_complexity_coefficient = 0.2,
        raw_multiplier = 0.075,

        spoilable_coefficient = 0.75,
        interplanetary_coefficient = 5,

        planet_depth_coefficient = 0.5,
        update_sensitivity = 75,
        update_sensitivity_decay = 0.9998,
        depth_sensitivity = -2,
        magnitude_penalty = 0,
        backward_calculation_coefficient = 0,
        initial_values = {},
        tracked_calculations = sets.new {
            -- "efficiency-module-3",
            -- "productivity-module-3",
            -- "bioflux",
            -- "iron-plate",
        },
    })
elseif PLANET_NAME == "aquilo" then
    values = item_values.calculate(graph, raw_values.aquilo, sets.new(allowed_recipes.aquilo), {}, spoilable_items, {
        logging = true,
        max_iterations = 100000,
        convergence_threshold = 0.01,
        energy_coefficient = 0.10,
        item_complexity_coefficient = 0.35,
        fluid_complexity_coefficient = 0.45,
        raw_multiplier = 0.25,

        spoilable_coefficient = 0.95,
        interplanetary_coefficient = 10,

        planet_depth_coefficient = 0.5,
        update_sensitivity = 50,
        update_sensitivity_decay = 0.9994,
        depth_sensitivity = -2,
        magnitude_penalty = 0,
        backward_calculation_coefficient = 0,
        initial_values = {},
    })
end

print(serpent.block(values))

local changed_values = {}
for item_name, value in pairs(values) do
    if value ~= raw_values[item_name] and value ~= 10 then -- TODO: properly check for changed values JUST IN CASE SOMEHOW a value is calculated as exactly 10
        changed_values[item_name] = value
    end
end

print("values changed:")
print(serpent.block(changed_values))

local view_item_values = {}
if PLANET_NAME == "nauvis" then
    view_item_values = {
        "iron-ore",
        "iron-plate",
        "steel-plate",
        "barrel",
        "sulfuric-acid",
        "sulfuric-acid-barrel",
        "crude-oil",
        "petroleum-gas",
        "plastic-bar",
    }
elseif PLANET_NAME == "vulcanus" then
    view_item_values = {
        "lava",
        "molten-iron",
        "iron-plate",
        "iron-gear-wheel",
        "tungsten-plate",
        "metallurgic-science-pack",
    }
elseif PLANET_NAME == "fulgora" then
    view_item_values = {
        "scrap",
        "holmium-ore",
        "holmium-solution",
        "holmium-plate",
        "tesla-turret",
        "electromagnetic-science-pack",
    }
elseif PLANET_NAME == "gleba" then
    view_item_values = {
        "nutrients",
        "yumako-mash",
        "bioflux",
        "carbon-fiber",
        "agricultural-science-pack",
        "efficiency-module-3",
        "productivity-module-3",
        "overgrowth-yumako-soil",
        "overgrowth-jellynut-soil",
        "spidertron",
    }
elseif PLANET_NAME == "aquilo" then
    view_item_values = {
        "ammonia",
        "ice",
        "water",
    }
end

for _, item_name in pairs(view_item_values) do
    print(item_name .. ": " .. values[item_name])
end

local sorted_items = {}
for item_name, value in pairs(values) do
    table.insert(sorted_items, {name = item_name, value = value})
end

table.sort(sorted_items, function(a, b) return a.value > b.value end)

print("\nTop 10 items by value:")
for i = 1, math.min(10, #sorted_items) do
    local item = sorted_items[i]
    print(string.format("%s: %.2f", item.name, item.value))
end

-- TODO: Automatically save calculated item values.
