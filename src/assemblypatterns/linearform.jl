abstract type APT_LinearForm <: AssemblyPatternType end

"""
````
function LinearForm(
    T::Type{<:Real},
    AT::Type{<:AbstractAssemblyType},
    FE::Array{FESpace,1},
    operators::Array{DataType,1}, 
    action::AbstractAction; 
    regions::Array{Int,1} = [0])
````

Creates a LinearForm assembly pattern with the given FESpaces, operators and action etc.
"""
function LinearForm(T::Type{<:Real}, AT::Type{<:AbstractAssemblyType}, FES, operators, action; regions = [0])
    return AssemblyPattern{APT_LinearForm, T, AT}(FES,operators,action,regions,AssemblyManager{T}(length(operators)))
end


function assemble!(
    b::Union{AbstractArray{T,1},AbstractArray{T,2}},
    AP::AssemblyPattern{APT,T,AT};
    verbosity::Int = 0,
    skip_preps::Bool = false,
    factor = 1,
    offset = 0) where {APT <: APT_LinearForm, T <: Real, AT <: AbstractAssemblyType}

    # prepare assembly
    FE = AP.FES[1]
    if !skip_preps
        prepare_assembly!(AP; verbosity = verbosity - 1)
    end
    AM::AssemblyManager{T} = AP.AM
    xItemVolumes::Array{T,1} = FE.xgrid[GridComponentVolumes4AssemblyType(AT)]
    xItemRegions::Union{VectorOfConstants{Int32}, Array{Int32,1}} = FE.xgrid[GridComponentRegions4AssemblyType(AT)]
    nitems = length(xItemVolumes)

    # prepare action
    action = AP.action
    action_resultdim::Int = action.argsizes[1]
    action_input::Array{T,1} = zeros(T,action.argsizes[2]) # heap for action input
    action_result::Array{T,1} = zeros(T,action_resultdim) # heap for action output
    if typeof(b) <: AbstractArray{T,1}
        @assert action_resultdim == 1
        onedimensional = true
    else
        onedimensional = false
    end

    if verbosity > 0
        println("  Assembling ($APT,$AT,$T) into vector")
        println("   skip_preps = $skip_preps")
        println("    operators = $(AP.operators)")
        println("      regions = $(AP.regions)")
        println("       factor = $factor")
        println("       action = $(AP.action.name) (size = $(action.argsizes))")
        println("        qf[1] = $(qf[1].name) ")
        println("           EG = $EG")
    end

    # loop over items
    weights::Array{T,1} = get_qweights(AM)
    localb::Array{T,2} = zeros(T,get_maxndofs(AM)[1],action_resultdim)
    ndofitems::Int = get_maxdofitems(AM)[1]
    bdof::Int = 0
    ndofs4dofitem::Int = 0
    itemfactor::T = 0
    regions::Array{Int,1} = AP.regions
    allitems::Bool = (regions == [0])
    nregions::Int = length(regions)
    for item = 1 : nitems
    for r = 1 : nregions
    # check if item region is in regions
    if allitems || xItemRegions[item] == regions[r]

        # update assembly manager (also updates necessary basisevaler)
        update!(AP.AM, item)
        weights = get_qweights(AM)

        # loop over associated dofitems
        for di = 1: ndofitems
            if AM.dofitems[1][di] != 0

                # get information on dofitem
                ndofs4dofitem = get_ndofs(AM, 1, di)

                # get correct basis evaluator for dofitem (was already updated by AM)
                basisevaler = get_basisevaler(AM, 1, di)

                # update action on dofitem
                update!(action, basisevaler, AM.dofitems[1][di], item, regions[r])

                for i in eachindex(weights)
                    for dof_i = 1 : ndofs4dofitem
                        # apply action
                        eval!(action_input, basisevaler, dof_i, i)
                        apply_action!(action_result, action_input, action, i)
                        for j = 1 : action_resultdim
                            localb[dof_i,j] += action_result[j] * weights[i]
                        end
                    end 
                end  

                ## copy into global vector
                itemfactor = factor * xItemVolumes[item] * AM.coeff4dofitem[1][di]
                if onedimensional
                    for dof_i = 1 : ndofs4dofitem
                        bdof = get_dof(AM, 1, di, dof_i) + offset
                        b[bdof] += localb[dof_i,1] * itemfactor
                    end
                else
                    for dof_i = 1 : ndofs4dofitem, j = 1 : action_resultdim
                        bdof = get_dof(AM, 1, di, dof_i) + offset
                        b[bdof,j] += localb[dof_i,j] * itemfactor
                    end
                end
                fill!(localb, 0)
            end
        end
        break; # region for loop
    end # if in region    
    end # region for loop
    end # item for loop
    return nothing
end

function assemble!(
    b::FEVectorBlock{T},
    AP::AssemblyPattern{APT,T,AT};
    verbosity::Int = 0,
    skip_preps::Bool = false,
    factor = 1) where {APT <: APT_LinearForm, T <: Real, AT <: AbstractAssemblyType}

    @assert b.FES == AP.FES[1]

    assemble!(b.entries, AP; verbosity = verbosity, factor = factor, offset = b.offset, skip_preps = skip_preps)
end