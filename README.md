# Factorio Item Value Solver

A Lua-based solver for calculating relative item values in Factorio: Space Age. This tool computes economically balanced values for items across different planets by analyzing recipe chains, crafting complexity, and resource availability.

## Overview

The solver uses an iterative dynamical system to determine equilibrium values for items based on:
- Recipe ingredient and product relationships
- Crafting energy and time costs
- Recipe complexity (number of distinct ingredients)
- Item spoilability
- Interplanetary resource availability
- Planet-specific constraints

## Features

- **Multi-planet support**: Calculate values for Nauvis, Vulcanus, Fulgora, Gleba, and Aquilo
- **Bidirectional value propagation**: Values flow both from ingredients to products and vice versa
- **Configurable parameters**: Fine-tune coefficients for energy, complexity, spoilability, and more
- **Recycling recipe generation**: Automatically generates and includes recycling recipes
- **Convergence detection**: Iteratively refines values until reaching equilibrium

## Requirements

- Lua 5.1 or later
- `serpent.lua` library (included for table serialization)

## Usage

Run the solver from the command line with a planet name:

```bash
lua solver.lua nauvis
lua solver.lua vulcanus
lua solver.lua fulgora
lua solver.lua gleba
lua solver.lua aquilo
```

If no planet is specified, Nauvis is used by default.

## Project Structure

- `solver.lua` - Main entry point and configuration
- `item_values.lua` - Core calculations
- `recipe_tree.lua` - Recipe data structure, slightly modified from the Factorio engine's runtime data `prototypes.recipe`
- `raw_values.lua` - Base values for uncraftable items per planet
- `allowed_recipes.lua` - Planet-specific recipe whitelists
- `calculated_values.lua` - Cached calculations to be used for interplanetary items
- `spoilable_items.lua` - Set of items that spoil
- `serpent.lua` - Lua table serialization library by Paul Kulchenko
- `sets.lua` - Set operations utility module

## Algorithm

The solver uses a **dynamical systems approach** to find equilibrium item values through numerical simulation. Rather than solving a complex system of equations directly, it simulates economic value flowing through Factorio's recipe network until the system naturally stabilizes.

### How It Works

Values propagate bidirectionally through recipes: ingredients influence product values (normal crafting economics), and products influence ingredient values (resource demand from advanced recipes). Each iteration applies small adjustments to item values based on:

- Recipe ingredient costs and energy requirements
- Crafting complexity (number of distinct ingredients)
- Item spoilability and interplanetary transport costs
- Recipe depth in the production chain

The system iterates with gradually decreasing step sizes (controlled by `update_sensitivity_decay`) until the total change across all items falls below the convergence threshold, at which point values have reached economic equilibrium.

### Implementation Steps

1. **Initialization**: All items start with raw values or a default value of 10
2. **Recipe Processing**: For each allowed recipe:
   - Calculate total ingredient value
   - Apply multipliers (energy, complexity, spoilability)
   - Distribute value across products
   - Calculate increments for each item
3. **Bidirectional Calculation**: Process recipes in both directions (ingredients→products and products→ingredients)
4. **Increment Aggregation**: Average multiple increments per item with depth-based weighting
5. **Convergence Check**: Repeat until total absolute change falls below threshold

## Output

The solver outputs:
- Complete item value table
- Sample values for key items per planet
- Top 10 most valuable items

## Customization

To adapt the solver for your needs:

1. **Update recipe data**: Modify `recipe_tree.lua` with your existing Factorio data, modded data allowed
2. **Adjust raw values**: Edit `raw_values.lua` to change or add base values of uncraftable items
3. **Configure recipes**: Update `allowed_recipes.lua` to set the specific recipes used by the algorithm
4. **Tune parameters**: Modify coefficients in `solver.lua` to achieve desired value balance

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 sOvr9000

## Acknowledgments

- Uses the [serpent](https://github.com/pkulchenko/serpent) library by Paul Kulchenko for Lua table serialization
