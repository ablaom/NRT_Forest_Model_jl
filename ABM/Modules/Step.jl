"""
Module contains the step (aka go function) for the model
"""

module go
    using Agents
    using Random
    using StatsBase
    using DataFrames
    using Distributions

    include("Disturbance_functions.jl")
    include("Demographic_functions.jl")
    include("Helper_functions.jl")
    
    #TODO ORDERS MAY BE ODD WITH AGENT AND MODEL STEPS SPLITTING GO FUNCTION
    #%This is the step function for the individual trees (no globals changed) 
    #* RUN ONCE PER AGENT PER CALL (I.E. Multiple times per tick if multiple agents)
    """
    TODO some proper function documentation
    """
    function agent_step!(
        agent,
        model
    )
        spec_num = agent.species_ID
        
        demog_funcs.grow(agent, model)

        if agent.age ≥ model.repro_ages[spec_num] && agent.height ≥ model.repro_heights[spec_num]
            sp = Int64(model.seed_prod[agent.species_ID])
            if sp > zero(1) #*zero(1) gives a 0 value which is more type stable than 0
                ldd_disp_frac = model.ldd_dispersal_fracs[agent.species_ID]
                r_hgt = model.regen_heights[agent.species_ID]
                nhbs = model.nhb_set[agent.patch_here_ID]

                demog_funcs.nhb_dispersal(agent, 
                                        model,
                                        sp,
                                        ldd_disp_frac,
                                        r_hgt,
                                        agent.dbh,
                                        model.cell_grain,
                                        model.shell_layers,
                                        agent.pos, 
                                        nhbs,
                                        model.pcor,
                                        model.nhb_shade_height,
                                        model.seedlings,
                                        agent.species_ID
                                        )

            end

            demog_funcs.ldd_within(agent, model)
        end

        if model.herbivory == true
            demog_funcs.herbivore_effect(agent, model)
        end

        demog_funcs.thin_regenbank(agent, model)

        #* Run for tree ferns only
        if agent.growth_form == 2
            demog_funcs.macro_litter_fall(agent, model)
        end

        demog_funcs.death(agent, model)

    end

    #%This is the step function for global level changes e.g. ticks
    #* RUN ONCE PER MODEL PER CALL (I.E. ONCE PER TICK)
    """
    TODO some proper function documentation
    """
    function model_step!(model)
        grid = collect(positions(model))

        if model.disturbance_freq > 0
            disturbance_functions.lsp_disturbance(model)
        end

        if model.external_rain == true
            demog_funcs.external_ldd(model, 
                                     model.ext_dispersal_scenario,
                                     grid)
        end

        for i in 1:length(positions(model))
            if model.expand[i] == true
                demog_funcs.expand_gap(i, 
                                       model,
                                       grid)
            end

            model.nhb_shade_height[i] = set_get_functions.get_nhb_shade_height(i, 
                                                                               model,
                                                                               grid,
                                                                               range(0, 32, step = 4),
                                                                               model.shell_layers)

            model.nhb_light[i] = set_get_functions.get_light_env(i, model)
        end

        for e in empty_positions(model) #TODO more variables in capture_gap
            cell_ID = [findfirst(isequal([e]), model.pcor)] 
            demog_funcs.capture_gap(cell_ID, model)
        end

        if model.restoration_planting == true && mod(model.tick, model.planting_frequency) == 0
            for i in 1:length(positions(model))
                model.saplings[i] .+= model.saplings_to_plant
            end
        end

        for i in 1:length(positions(model))
            demog_funcs.regenerate_patch_bank(i, model)
            model.seedling_density[i] = sum(model.seedlings[i])
            model.sapling_density[i] = sum(model.saplings[i])
        end

        model.max_density = maximum(model.sapling_density)

        set_get_functions.update_abundances(model)

        model.tick += 1
    end
end