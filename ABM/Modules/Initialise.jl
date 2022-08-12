"""
Module contains all of the functions required to setup the model at the start
of a run
"""
module Setup
    using Agents
    using Random
    using StatsBase

    #% Define agents
    #? Maybe a dict of species key value pairs could be useful
    @agent Tree GridAgent{2} begin 
        species_ID::Int
        growth_form::Int
        height::Float64
        dbh::Float64
        age::Float64
    end

    #% Define world
    function forest_model(;
        forest_area = 16,
        cell_grain = 4,
        edge_strength = 0.0,
        site_df = site_df,
        demography_df = demography_df,
        seed = 999,)
        
        #? Could we define space as many dimensional and just add the properties like height
        #? and species present to this
        ## Define globals
        dims = trunc(Int, (sqrt(forest_area * 1e4)) / cell_grain)

        space = GridSpaceSingle((dims, dims); periodic = false);
        rng = MersenneTwister(seed)

        seedling_survival = demography_df.seedling_survival
        sapling_survival = demography_df.sapling_survival
        seedling_transition = demography_df.seedling_transition
        seedling_mortality = 1 .- (seedling_survival .+ seedling_transition)
        sapling_mortality = 1 .- sapling_survival

        edge_b0 = 0
        edge_b1 = 1

        ## Define patch properties
        properties = (
            seedlings = ifelse.(demography_df.growth_form .== 1, 10, 6),
            saplings = ifelse.(demography_df.growth_form .== 1, 2, 1),
            edge_weight = zeros(Float64, prod((dims, dims)))
        )

        model = ABM(Tree, space; 
            properties,
            rng,
            scheduler = Schedulers.Randomly())

        ## Populate the world with adult tree agents
        grid = collect(positions(model))
        num_positions = prod((dims, dims))

        #TODO Will need the below for calculating edges
        #minimum(grid) #Get tuple of minimum x,y coordinates
        #maximum(grid) #Get tuple of maximum x,y coordinates
        #grid[2] .- minimum(grid) #Get distance (x,y) to edge from current cell OR minimum(grid[2] .- minimum(grid)) for one value


        #Make for loop that samples a proportion of space and allocates each species
        for p in 1:num_positions
            # Todo get correct heights etc for each tree
            #? Could we use dictionary keys to get name value pairs and make it clearer what we are doing
            # Column 1 is species column 2 is initial abundance
            specID = wsample(site_df[ : , 1], site_df[ : , 2])

            grow_form = demography_df.growth_form[specID]

            ## Get height dbh and age
            agent_demos = assign_demographic(specID, 
                                             site_df, 
                                             demography_df)

            adult_tree = Tree(
                p,
                grid[p],
                specID,
                grow_form,
                agent_demos[1],
                agent_demos[2],
                agent_demos[3],
            )
            add_agent_single!(adult_tree, model)

            ## Update patch level properties
            e_dist = minimum(grid[p] .- minimum(positions(model)))
            weight = edge_b1 * exp(-edge_strength * e_dist) + edge_b0
        
            model.edge_weight[p...] = weight
        end
        
        return model
    end

    #// Define patches


    #% Helper functions
    include("Helper_functions.jl")
    include("Demographic_assignments.jl")

    function assign_demographic(
        species::Integer,
        site_df = site_df,
        demography_df = demography_df
    )
        ## Define species charatecteristics
        growth_form = demography_df.growth_form[species]

        max_height_frac = site_df.max_init_hgt[species]
        max_height_frac = max_height_frac < 0 || max_height_frac > 1 ? 0.95 : max_height_frac
        max_height = demography_df.max_hgt[species]

        max_dbh = demography_df.max_dbh[species]
        start_dbh = site_df.start_dbh[species]
        start_dbh_sd = site_df.start_dbh_sd[species]

        b2_jabowa = (2 * (max_height - 1.37)) / max_dbh #*Based on equation from Botkin 2001
        b3_jabowa = ((max_height - 1.37) / (max_dbh)^2) #*Based on equation from Botkin 2001
        g_jabowa = demography_df.g_jabowa[species]

        ## Define behaviour for trees (growth form 1)
        if growth_form == 1
            # Define initial DBH
            dbh = min(rand(distribution_functions.generate_LogNormal(start_dbh,
                                                                     start_dbh_sd), 1)[1], 
                (max_height_frac * max_dbh))
            dbh = max(0.01, dbh)

            # Define initial height
            height = 1.37 + (b2_jabowa * dbh) - (b3_jabowa * dbh * dbh)

            # Define initial age
            age = demog_metrics.age_by_dbh(
                height, 
                dbh,
                max_dbh,
                Float64(max_height),
                g_jabowa,
                b2_jabowa,
                b3_jabowa
            )


        #* Define behaviour for tree ferns (growth form 2)
        elseif growth_form == 2
            #? Is this actually the correct calculation
            height = min(rand(distribution_functions.generate_LogNormal(start_dbh,
                                                                        start_dbh_sd), 1)[1], 
                    (max_height_frac * max_height))
            height = height < 0 ? 1.5 : height

            ## TODO This hard coding seems odd
            dbh = 0.1

            age = demog_metrics.age_by_height(
                height
            )

        #* If growth form is not of known type send an error message
        else
            error("The growth form $growth_form is undefined, please check species demography data")
        end

        return(height, dbh, age)
    end
end
