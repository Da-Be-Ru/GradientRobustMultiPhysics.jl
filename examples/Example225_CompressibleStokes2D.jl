#= 

# 225 : Compressible Stokes 2D
([source code](SOURCE_URL))

This example solves the compressible Stokes equations where one seeks a (vector-valued) velocity ``\mathbf{u}``, a density ``\varrho`` and a pressure ``p`` such that
```math
\begin{aligned}
- \mu \Delta \mathbf{u} + \λ \nabla(\mathrm{div}(\mathbf{u})) + \nabla p & = \mathbf{f} + \varrho \mathbf{g}\\
\mathrm{div}(\varrho \mathbf{u}) & = 0\\
        p & = eos(\varrho)\\
        \int_\Omega \varrho \, dx & = M\\
        \varrho & \geq 0.
\end{aligned}
```
Here eos ``eos`` is some equation of state function that describes the dependence of the pressure on the density
(and further physical quantities like temperature in a more general setting).
Moreover, ``\mu`` and ``\λ`` are Lame parameters and ``\mathbf{f}`` and ``\mathbf{g}`` are given right-hand side data.

In this example we solve a analytical toy problem with the prescribed solution
```math
\begin{aligned}
\mathbf{u}(\mathbf{x}) & =0\\
\varrho(\mathbf{x}) & = 1 - (x_2 - 0.5)/c\\
p &= eos(\varrho) := c \varrho^\γ
\end{aligned}
```
such that ``\mathbf{f} = 0`` and ``\mathbf{g}`` nonzero to match the prescribed solution.
This example is designed to study the well-balanced property of a discretisation. Note that a gradient-robust discretisation (set reconstruct = true below)
has a much smaller L2 velocity error (i.e. approximatse the well-balanced state much better). For larger c the problem gets more incompressible which reduces
the error further as then the right-hand side is a perfect gradient also when evaluated with the (now closer to a constant) discrete density.
See reference below for more details.

!!! reference

    "A gradient-robust well-balanced scheme for the compressible isothermal Stokes problem",\
    M. Akbas, T. Gallouet, A. Gassmann, A. Linke and C. Merdon,\
    Computer Methods in Applied Mechanics and Engineering 367 (2020),\
    [>Journal-Link<](https://doi.org/10.1016/j.cma.2020.113069)
    [>Preprint-Link<](https://arxiv.org/abs/1911.01295)

=#


module Example225_CompressibleStokes2D

using GradientRobustMultiPhysics
using ExtendableGrids
using Printf


## the equation of state
function equation_of_state!(c,γ)
    function closure(pressure,density)
        for j = 1 : length(density)
            pressure[j] = c*density[j]^γ
        end
    end
end

## the exact density (used for initial value of density if configured so)
function ϱ_exact!(M,c)
    function closure(result,x::Array{<:Real,1})
        result[1] = M*(1.0 - (x[2] - 0.5)/c)
    end
end

## gravity right-hand side (just gravity but with opposite sign!)
function gravity!(γ,c)
    function closure(result,x::Array{<:Real,1})
        result[1] = 1.0 - (x[2] - 0.5)/c # = density
        result[2] = - result[1]^(γ-2) * γ
        result[1] = 0.0
    end
end   

## everything is wrapped in a main function
function main(; verbosity = 0, Plotter = nothing, reconstruct::Bool = true, c = 10, γ = 1.4, M = 1, μ = 1e-3, λ = -1e-3/3)

    ## set log level
    set_verbosity(verbosity)

    ## load mesh and refine
    xgrid = simplexgrid("assets/2d_grid_mountainrange.sg")

    ## solve without and with reconstruction and plot
    Solution = setup_and_solve(xgrid; reconstruct = false, c = c, M = M, λ = λ, μ = μ, γ = γ)
    Solution2 = setup_and_solve(xgrid; reconstruct = true, c = c, M = M, λ = λ, μ = μ, γ = γ)

    ## plot everything
    GradientRobustMultiPhysics.plot(xgrid, [Solution[1],Solution[2],Solution2[1],Solution2[2]], [Identity, Identity, Identity, Identity]; add_grid_plot = true, Plotter = Plotter)

    ## compare L2 error for velocity and density
    u = DataFunction([0,0]; name = "u")
    ϱ = DataFunction(ϱ_exact!(M,c), [1,2]; name = "ϱ", dependencies = "X", quadorder = 1)
    L2VelocityErrorEvaluator = L2ErrorIntegrator(Float64, u, Identity)
    L2DensityErrorEvaluator = L2ErrorIntegrator(Float64, ϱ, Identity)
    L2error = sqrt(evaluate(L2VelocityErrorEvaluator,Solution[1]))
    L2error2 = sqrt(evaluate(L2VelocityErrorEvaluator,Solution2[1]))
    L2error3 = sqrt(evaluate(L2DensityErrorEvaluator,Solution[2]))
    L2error4 = sqrt(evaluate(L2DensityErrorEvaluator,Solution2[2]))
    @printf("\n        reconstruct     false    |    true\n")
    @printf("================================================\n")
    @printf("L2error(Velocity) | %.5e  | %.5e \n",L2error,L2error2)
    @printf("L2error(Density)  | %.5e  | %.5e \n",L2error3,L2error4)
    
end

function setup_and_solve(xgrid; 
    c = 1, γ = 1, M = 1, μ = 1, λ = 0, 
    reconstruct = true,
    initial_density_bestapprox = true, 
    timestep = 2 * μ / c,
    maxTimeSteps = 1000,
    stationarity_threshold = 1e-12/μ)

    ## set finite element type [velocity, density,  pressure]
    FETypes = [H1BR{2}, H1P0{1}, H1P0{1}] # Bernardi--Raugel

    ## generate empty PDEDescription for three unknowns (u, ϱ. p)
    Problem = PDEDescription("compressible Stokes problem")
    add_unknown!(Problem; unknown_name = "v", equation_name = "momentum equation")
    add_unknown!(Problem; unknown_name = "ϱ", equation_name = "continuity equation")
    add_unknown!(Problem; unknown_name = "p", equation_name = "equation of state")
    add_boundarydata!(Problem, 1,  [1,2,3,4], HomogeneousDirichletBoundary)

    ## momentum equation
    VeloIdentity = reconstruct ? ReconstructionIdentity{HDIVBDM1{2}} : Identity
    VeloDivergence = reconstruct ? ReconstructionDivergence{HDIVBDM1{2}} : Divergence
    add_operator!(Problem, [1,1], LaplaceOperator(2*μ; store = true))
    if λ != 0
        add_operator!(Problem, [1,1], AbstractBilinearForm([VeloDivergence,VeloDivergence]; name = "λ (div(u),div(v))", factor = λ, store = true))
    end
    add_operator!(Problem, [1,3], AbstractBilinearForm([Divergence,Identity]; name = "(div(v),p)", factor = -1, store = true))

    function gravity_action()
        g = DataFunction(gravity!(γ,c), [2,2]; name = "g", dependencies = "X", quadorder = 1)
        temp = zeros(Float64,2)
        function closure(result,input,x, t)
            eval!(temp, g, x, t)
            result[1] = - temp[1] * input[1] - temp[2] * input[2]
        end
        gravity_action = Action(Float64, closure, [1,2]; name = "gravity action", dependencies = "XT", quadorder = g.quadorder)
    end    
    add_operator!(Problem, [1,2], AbstractBilinearForm([VeloIdentity,Identity],gravity_action(); name = "ϱ(g ⋅ v)", store = true))

    ## continuity equation (by FV upwind on triangles)
    add_operator!(Problem, [2,2], FVConvectionDiffusionOperator(1))

    ## equation of state (by best-approximation, P0 mass matrix is diagonal)
    eos_action = Action(Float64, equation_of_state!(c,γ),[1,1]; dependencies = "", quadorder = 0)
    add_operator!(Problem, [3,2], AbstractBilinearForm([Identity,Identity],eos_action; name = "(p,eos(ϱ))", apply_action_to = [2]))
    add_operator!(Problem, [3,3], AbstractBilinearForm([Identity,Identity]; name = "(p,q)", factor = -1, store = true))

    ## generate FESpaces and solution vector
    FES = [FESpace{FETypes[1]}(xgrid), FESpace{FETypes[2]}(xgrid), FESpace{FETypes[3]}(xgrid)]
    Solution = FEVector{Float64}(["v_h (reconst=$reconstruct)", "ϱ_h (reconst=$reconstruct)", "p_h (reconst=$reconstruct)"],FES)

    ## initial values for density (bestapproximation or constant)
    ϱ = DataFunction(ϱ_exact!(M,c), [1,2]; name = "ϱ", dependencies = "X", quadorder = 1)
    if initial_density_bestapprox 
        L2DensityBestapproximationProblem = L2BestapproximationProblem(ϱ; bestapprox_boundary_regions = [])
        InitialDensity = FEVector{Float64}("ϱ_best",FES[2])
        solve!(InitialDensity, L2DensityBestapproximationProblem)
        Solution[2][:] = InitialDensity[1][:]
    else
        for j = 1 : FESpacePD.ndofs
            Solution[2][j] = M
        end
    end

    ## initial values for pressure obtained from equation of state
    equation_of_state!(c,γ)(Solution[3],Solution[2])
    Minit = M * sum(Solution[2][:] .* xgrid[CellVolumes])

    ## generate time-dependent solver
    ## three equations [1] for velocity, [2] for density, [3] for pressure
    ## solved iteratively [1] => [2] => [3] => [1] ...
    ## [2] is time-dependent (pseudo time stepping)
    TCS = TimeControlSolver(Problem, Solution, BackwardEuler;
                                        subiterations = [[1],[2],[3]],
                                        skip_update = [-1,1,-1],
                                        timedependent_equations = [2],
                                        maxiterations = 1,
                                        show_solver_config = true,
                                        check_nonlinear_residual = false)
    advance_until_stationarity!(TCS, timestep; maxTimeSteps = maxTimeSteps, stationarity_threshold = stationarity_threshold)

    ## compute error in mass constraint
    Md = sum(Solution[2][:] .* xgrid[CellVolumes])
    @printf("  mass_error = %.4e - %.4e = %.4e \n",Minit, Md, abs(Minit-Md))

    return Solution
end

end