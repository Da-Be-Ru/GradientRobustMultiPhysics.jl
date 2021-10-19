#= 

# 222 : Navier-Stokes Lid-driven cavity + Anderson Acceleration
([source code](SOURCE_URL))

This example solves the lid-driven cavity problem where one seeks
a velocity ``\mathbf{u}`` and pressure ``\mathbf{p}`` of the incompressible Navier--Stokes problem
```math
\begin{aligned}
- \mu \Delta \mathbf{u} + (\mathbf{u} \cdot \nabla) \mathbf{u} + \nabla p & = 0\\
\mathrm{div}(u) & = 0
\end{aligned}
```
where ``\mathbf{u} = (1,0)`` along the top boundary of a square domain.

For small viscosities (where a Newton and a classical Picard iteration do not converge anymore),
Anderson acceleration might help which can be tested with this script.
Here, we use [Anderson acceleration](@ref) until the residual is small enough for the Newton to take over.

=#

module Example222_NavierStokesAnderson2D

using GradientRobustMultiPhysics
using ExtendableGrids
using GridVisualize
using Printf

## everything is wrapped in a main function
function main(; verbosity = 0, Plotter = nothing, μ = 5e-4, anderson_iterations = 10, target_residual = 1e-12, maxiterations = 50, switch_to_newton_tolerance = 1e-4)

    ## set log level
    set_verbosity(verbosity)

    ## grid
    xgrid = uniform_refine(grid_unitsquare(Triangle2D), 5);

    ## finite element type
    FETypes = [H1P2{2,2}, H1P1{1}] # Taylor--Hood

    ## load Navier-Stokes problem prototype and assign data
    Problem = IncompressibleNavierStokesProblem(2; viscosity = μ, nonlinear = true, auto_newton = false, store = false)
    add_boundarydata!(Problem, 1, [1,2,4], HomogeneousDirichletBoundary)
    add_boundarydata!(Problem, 1, [3], BestapproxDirichletBoundary; data = DataFunction([1,0]))
    @show Problem

    ## generate FESpaces
    FES = [FESpace{FETypes[1]}(xgrid), FESpace{FETypes[2]}(xgrid)]
    Solution = FEVector{Float64}(["u_h", "p_h"],FES)

    ## solve with anderson iterations until 1e-4
    solve!(Solution, Problem; anderson_iterations = anderson_iterations, anderson_metric = "l2", anderson_unknowns = [1], maxiterations = maxiterations, target_residual = switch_to_newton_tolerance)

    ## solve rest with Newton
    Problem = IncompressibleNavierStokesProblem(2; viscosity = μ, nonlinear = true, auto_newton = true, store = true)
    add_boundarydata!(Problem, 1, [1,2,4], HomogeneousDirichletBoundary)
    add_boundarydata!(Problem, 1, [3], BestapproxDirichletBoundary; data = DataFunction([1,0]))
    @show Problem
    solve!(Solution, Problem; anderson_iterations = anderson_iterations, maxiterations = maxiterations, target_residual = target_residual)

    ## plot
    p=GridVisualizer(;Plotter=Plotter,layout=(1,1),clear=true,resolution=(600,600))
    nodevals = zeros(Float64,2,num_nodes(xgrid))
    nodevalues!(nodevals, Solution[1], Identity)
    scalarplot!(p[1,1],xgrid,view(sum(nodevals.^2, dims = 1),1,:),levels=1)
    vectorplot!(p[1,1],xgrid,nodevals;Plotter=Plotter, spacing = 0.1, clear = false, title = "u (quiver)")
end

end