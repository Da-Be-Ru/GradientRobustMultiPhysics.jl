
using FEXGrid
using ExtendableGrids
using ExtendableSparse
using FiniteElements
using FEAssembly
using PDETools
using QuadratureRules
#using VTKView
ENV["MPLBACKEND"]="qt5agg"
using PyPlot
using BenchmarkTools
using Printf


include("testgrids.jl")

# problem data and expected exact solution
diffusion = 1.0
function exact_solution!(result,x)
    result[1] = x[1]*x[2]*(x[1]-1)*(x[2]-1) + x[1]
end    
function bnd_data_right!(result,x)
    result[1] = 1.0
end    
function bnd_data_rest!(result,x)
    result[1] = x[1]
end    
function exact_solution_gradient!(result,x)
    result[1] = x[2]*(2*x[1]-1)*(x[2]-1) + 1.0
    result[2] = x[1]*(2*x[2]-1)*(x[1]-1)
end    
function exact_solution_rhs!(result,x)
    # diffusion part
    result[1] = -diffusion*(2*x[2]*(x[2]-1) + 2*x[1]*(x[1]-1))
    # convection part
    result[1] += x[2]*(2*x[1]-1)*(x[2]-1) + 1.0
end    
function convection!(result,x)
    result[1] = 1.0
    result[2] = 0.0
end


function main()

    #####################################################################################
    #####################################################################################

    # meshing parameters
    xgrid = testgrid_mixedEG(); # initial grid
    #xgrid = split_grid_into(xgrid,Triangle2D) # if you want just triangles
    nlevels = 7 # number of refinement levels

    # problem parameters
    diffusion = 1

    # fem/solver parameters
    #FEType = FiniteElements.H1P1{1} # P1-Courant
    #FEType = FiniteElements.H1P2{1} # P2
    FEType = FiniteElements.H1CR{1} # Crouzeix-Raviart
    verbosity = 1 # deepness of messaging (the larger, the more)

    #####################################################################################    
    #####################################################################################

    # PDE description
    MyLHS = Array{Array{AbstractPDEOperator,1},2}(undef,1,1)
    MyLHS[1,1] = [LaplaceOperator(MultiplyScalarAction(diffusion,2)),
                  ConvectionOperator(convection!,2,1)]
    MyRHS = Array{Array{AbstractPDEOperator,1},1}(undef,1)
    MyRHS[1] = [RhsOperator(Identity, [exact_solution_rhs!], 2, 1; bonus_quadorder = 3)]
    MyBoundary = BoundaryOperator(2,1)
    append!(MyBoundary, 1, BestapproxDirichletBoundary; data = bnd_data_rest!, bonus_quadorder = 2)
    append!(MyBoundary, 2, InterpolateDirichletBoundary; data = bnd_data_right!)
    append!(MyBoundary, 3, BestapproxDirichletBoundary; data = bnd_data_rest!, bonus_quadorder = 2)
    append!(MyBoundary, 4, HomogeneousDirichletBoundary)
    ConvectionDiffusionProblem = PDEDescription("ConvectionDiffusionProblem",MyLHS,MyRHS,[MyBoundary])

    # define ItemIntegrators for L2/H1 error computation
    L2ErrorEvaluator = L2ErrorIntegrator(exact_solution!, Identity, 2, 1; bonus_quadorder = 4)
    H1ErrorEvaluator = L2ErrorIntegrator(exact_solution_gradient!, Gradient, 2, 2; bonus_quadorder = 3)
    L2error = []
    H1error = []
    L2errorInterpolation = []
    H1errorInterpolation = []
    NDofs = []

    # loop over levels
    for level = 1 : nlevels

        # uniform mesh refinement
        if (level > 1) 
            xgrid = uniform_refine(xgrid)
        end

        # generate FESpace
        FESpace = FiniteElements.FESpace{FEType}(xgrid)
        if verbosity > 2
            FiniteElements.show(FESpace)
        end    

        # solve PDE
        Solution = FEVector{Float64}("Problem solution",FESpace)
        solve!(Solution, ConvectionDiffusionProblem; verbosity = verbosity)
        push!(NDofs,length(Solution.entries))

        # interpolate
        Interpolation = FEVector{Float64}("Interpolation",FESpace)
        interpolate!(Interpolation[1], exact_solution!; verbosity = verbosity - 1)

        # compute L2 and H1 error
        append!(L2error,sqrt(evaluate(L2ErrorEvaluator,Solution[1])))
        append!(L2errorInterpolation,sqrt(evaluate(L2ErrorEvaluator,Interpolation[1])))
        append!(H1error,sqrt(evaluate(H1ErrorEvaluator,Solution[1])))
        append!(H1errorInterpolation,sqrt(evaluate(H1ErrorEvaluator,Interpolation[1])))
        
        # plot final solution
        if (level == nlevels)
            println("\n         |   L2ERROR   |   L2ERROR")
            println("   NDOF  |   SOLUTION  |   INTERPOL");
            for j=1:nlevels
                @printf("  %6d |",NDofs[j]);
                @printf(" %.5e |",L2error[j])
                @printf(" %.5e\n",L2errorInterpolation[j])
            end
            println("\n         |   H1ERROR   |   H1ERROR")
            println("   NDOF  |   SOLUTION  |   INTERPOL");
            for j=1:nlevels
                @printf("  %6d |",NDofs[j]);
                @printf(" %.5e |",H1error[j])
                @printf(" %.5e\n",H1errorInterpolation[j])
            end

            # split grid into triangles for plotter
            xgrid = split_grid_into(xgrid,Triangle2D)

            # plot triangulation
            PyPlot.figure(1)
            ExtendableGrids.plot(xgrid, Plotter = PyPlot)

            # plot solution
            PyPlot.figure(2)
            nnodes = size(xgrid[Coordinates],2)
            nodevals = zeros(Float64,2,nnodes)
            nodevalues!(nodevals,Solution[1],FESpace)
            ExtendableGrids.plot(xgrid, nodevals[1,:]; Plotter = PyPlot)
        end    
    end    


end


main()
