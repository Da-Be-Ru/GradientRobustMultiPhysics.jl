#= 

# 207 : Stokes Transient 2D
([source code](SOURCE_URL))

This example computes a velocity ``\mathbf{u}`` and pressure ``\mathbf{p}`` of the incompressible Navier--Stokes problem
```math
\begin{aligned}
\mathbf{u}_t - \mu \Delta \mathbf{u} + \nabla p & = \mathbf{f}\\
\mathrm{div}(u) & = 0
\end{aligned}
```
with (possibly time-dependent) exterior force ``\mathbf{f}`` and some viscosity parameter ``\mu``.

In this example we solve an analytical toy problem with prescribed solution
```math
\begin{aligned}
\mathbf{u}(\mathbf{x},t) & = (1+t)(\cos(x_2), \sin(x_1))^T\\
p(\mathbf{x}) &= \sin(x_1+x_2) - 2\sin(1) + \sin(2)
\end{aligned}
```
with time-dependent right-hand side and inhomogeneous Dirichlet boundary data. The example showcases the
benefits of pressure-robustness in time-dependent linear Stokes problem in presence of complicated pressures and small viscosities.
The problem is solved on series of finer and finer unstructured simplex meshes and compares the error of the discrete Stokes solution,
an interpolation into the same space and the best-approximations into the same space. While a pressure-robust variant shows optimally
converging errors close to the best-approximations, a non pressure-robust discretisations show suboptimal (or no) convergence!
Compare e.g. Bernardi--Raugel and Bernardi--Raugel pressure-robust by (un)commenting the responsible lines in this example.
=#


module Example207_StokesTransient2D

using GradientRobustMultiPhysics
using ExtendableGrids

## problem data
function exact_pressure!(result,x)
    result[1] = sin(x[1]+x[2]) - 2*sin(1)+sin(2)
end
function exact_velocity!(result,x,t)
    result[1] = (1+t)*cos(x[2]);
    result[2] = (1+t)*sin(x[1]);
end
function exact_velocity_gradient!(result,x,t)
    result[1] = 0.0
    result[2] = -(1+t)*sin(x[2]);
    result[3] = (1+t)*cos(x[1]);
    result[4] = 0.0;
end
function exact_rhs!(viscosity)
    function closure(result,x,t)
        result[1] = viscosity*(1+t)*cos(x[2]) + cos(x[1]+x[2]) + cos(x[2])
        result[2] = viscosity*(1+t)*sin(x[1]) + cos(x[1]+x[2]) + sin(x[1])
    end
end

## everything is wrapped in a main function
function main(; verbosity = 0, Plotter = nothing, nlevels = 4, timestep = 1e-3, T = 1e-2, viscosity = 1e-6, graddiv = 0)

    ## set log level
    set_verbosity(verbosity)

    ## initial grid
    xgrid = grid_unitsquare(Triangle2D);

    ## choose one of these (inf-sup stable) finite element type pairs
    reconstruct = false # do not change
    broken_p = false # is pressure space broken ?
    #FETypes = [H1P2{2,2}, H1P1{1}] # Taylor--Hood
    #FETypes = [H1P2B{2,2}, H1P1{1}]; broken_p = true # P2-bubble
    #FETypes = [H1CR{2}, H1P0{1}]; broken_p = true # Crouzeix--Raviart
    #FETypes = [H1CR{2}, H1P0{1}]; broken_p = true; reconstruct = true # Crouzeix-Raviart gradient-robust
    #FETypes = [H1MINI{2,2}, H1P1{1}] # MINI element on triangles only
    #FETypes = [H1MINI{2,2}, H1CR{1}] # MINI element on triangles/quads
    #FETypes = [H1BR{2}, H1P0{1}]; broken_p = true # Bernardi--Raugel
    FETypes = [H1BR{2}, H1P0{1}]; broken_p = true; reconstruct = true # Bernardi--Raugel gradient-robust
  
    #####################################################################################

    ## set testfunction operator for certain testfunctions
    ## (pressure-robustness chooses a reconstruction that can exploit the L2-orthogonality onto gradients)
    testfunction_operator = reconstruct ? ReconstructionIdentity{HDIVBDM1{2}} : Identity

    ## negotiate data functions to the package
    ## note that dependencies "XT" marks the function to be x- and t-dependent
    ## that causes the solver to automatically reassemble associated operators in each time step
    u = DataFunction(exact_velocity!, [2,2]; name = "u", dependencies = "XT", quadorder = 5)
    p = DataFunction(exact_pressure!, [1,2]; name = "p", dependencies = "X", quadorder = 5)
    ∇u = DataFunction(exact_velocity_gradient!, [4,2]; name = "∇u", dependencies = "XT", quadorder = 4)
    user_function_rhs = DataFunction(exact_rhs!(viscosity), [2,2]; name = "f", dependencies = "XT", quadorder = 5)

    ## load Stokes problem prototype and assign data
    Problem = IncompressibleNavierStokesProblem(2; viscosity = viscosity, nonlinear = false)
    add_boundarydata!(Problem, 1, [1,2,3,4], BestapproxDirichletBoundary; data = u)
    add_rhsdata!(Problem, 1, RhsOperator(testfunction_operator, [1], user_function_rhs))

    ## add grad-div stabilisation
    if graddiv > 0
        add_operator!(Problem, [1,1], BilinearForm("graddiv-stabilisation (div x div)", Divergence, Divergence; factor = graddiv))
    end

    ## define bestapproximation problems
    BAP_L2_p = L2BestapproximationProblem(p; bestapprox_boundary_regions = [])
    BAP_L2_u = L2BestapproximationProblem(u; bestapprox_boundary_regions = [1,2,3,4])
    BAP_H1_u = H1BestapproximationProblem(∇u, u; bestapprox_boundary_regions = [1,2,3,4])

    ## define ItemIntegrators for L2/H1 error computation and arrays to store them
    L2VelocityError = L2ErrorIntegrator(Float64, u, Identity; time = T)
    L2PressureError = L2ErrorIntegrator(Float64, p, Identity)
    H1VelocityError = L2ErrorIntegrator(Float64, ∇u, Gradient; time = T) 
    Results = zeros(Float64, nlevels, 6)
    NDofs = zeros(Int, nlevels)
    
    ## loop over levels
    for level = 1 : nlevels

        ## refine grid
        xgrid = uniform_refine(xgrid)

        ## generate FESpaces
        FES = [FESpace{FETypes[1]}(xgrid), FESpace{FETypes[2]}(xgrid; broken = broken_p)]

        ## generate solution fector
        Solution = FEVector(["u_h", "p_h"],FES)

        ## set initial solution ( = bestapproximation at time 0)
        BA_L2_u = FEVector("L2-Bestapproximation velocity",FES[1])
        solve!(BA_L2_u, BAP_L2_u; time = 0)
        Solution[1][:] = BA_L2_u[1][:]

        ## generate time-dependent solver and chance rhs data
        TCS = TimeControlSolver(Problem, Solution, CrankNicolson; timedependent_equations = [1], skip_update = [-1], dt_operator = [testfunction_operator])
        advance_until_time!(TCS, timestep, T)

        ## solve bestapproximation problems at final time for comparison
        BA_L2_p = FEVector("L2-Bestapproximation pressure",FES[2])
        BA_H1_u = FEVector("H1-Bestapproximation velocity",FES[1])
        solve!(BA_L2_u, BAP_L2_u; time = T)
        solve!(BA_L2_p, BAP_L2_p)
        solve!(BA_H1_u, BAP_H1_u; time = T)

        ## compute L2 and H1 errors and save data
        NDofs[level] = length(Solution.entries)
        Results[level,1] = sqrt(evaluate(L2VelocityError,Solution[1]))
        Results[level,2] = sqrt(evaluate(L2VelocityError,BA_L2_u[1]))
        Results[level,3] = sqrt(evaluate(L2PressureError,Solution[2]))
        Results[level,4] = sqrt(evaluate(L2PressureError,BA_L2_p[1]))
        Results[level,5] = sqrt(evaluate(H1VelocityError,Solution[1]))
        Results[level,6] = sqrt(evaluate(H1VelocityError,BA_H1_u[1]))
    end    

    ## print convergence history
    print_convergencehistory(NDofs, Results[:,1:2]; X_to_h = X -> X.^(-1/2), ylabels = ["||u-u_h||", "||u-Πu||"])
    print_convergencehistory(NDofs, Results[:,3:4]; X_to_h = X -> X.^(-1/2), ylabels = ["||p-p_h||", "||p-πp||"])
    print_convergencehistory(NDofs, Results[:,5:6]; X_to_h = X -> X.^(-1/2), ylabels = ["||∇(u-u_h)||", "||∇(u-Su)||"])
end

end