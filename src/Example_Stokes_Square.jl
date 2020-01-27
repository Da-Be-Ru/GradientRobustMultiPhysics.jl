using Triangulate
using Grid
using Quadrature
using ExtendableSparse
using LinearAlgebra
using SparseArrays
using FiniteElements
using FESolveCommon
using FESolveStokes
using FESolvePoisson
using ForwardDiff
ENV["MPLBACKEND"]="tkagg"
using PyPlot


function triangulate_unitsquare(maxarea)
    triin=Triangulate.TriangulateIO()
    triin.pointlist=Matrix{Cdouble}([0 0; 1 0; 1 1; 0 1]');
    triin.segmentlist=Matrix{Cint}([1 2 ; 2 3 ; 3 4 ; 4 1 ]')
    triin.segmentmarkerlist=Vector{Int32}([1, 2, 3, 4])
    (triout, vorout)=triangulate("pQa" * string(maxarea), triin)
    return Grid.Mesh{Float64}(Array{Float64,2}(triout.pointlist'),Array{Int64,2}(triout.trianglelist'),Grid.ElemType2DTriangle());
end


function main()

#fem = "CR"
#fem = "MINI"
#fem = "TH"
#fem = "P2P0"
#fem = "BR"
fem = "BR+" # with reconstruction


#use_problem = "P7vortex"; u_order = 7; error_order = 6; p_order = 3; f_order = 5;
#use_problem = "constant"; u_order = 0; error_order = 0; p_order = 0; f_order = 0;
#use_problem = "linear"; u_order = 1; error_order = 2; p_order = 0; f_order = 0;
#use_problem = "quadratic"; u_order = 2; error_order = 2; p_order = 1; f_order = 0;
use_problem = "cubic"; u_order = 3; error_order = 4; p_order = 2; f_order = 1;
maxlevel = 3
nu = 1e-1

show_plots = true
show_convergence_history = true


# define problem data
function theta(problem) # stream function
    function closure(x)
        if problem == "linear"
            return - x[2]^2 * 1//2;
        elseif problem == "P7vortex"
            return x[1]^2 * (x[1] - 1)^2 * x[2]^2 * (x[2] - 1)^2
        elseif problem == "quadratic"
            return x[1]^3+x[2]^3;
        elseif problem == "cubic"
            return x[1]^4+x[2]^4;  
        elseif problem == "constant"
            return x[1] + x[2];    
        end
    end    
end    


function exact_pressure(problem) # exact pressure
    function closure(x)
        if problem == "P7vortex"
            return x[1]^3 + x[2]^3 - 1//2 
        elseif problem == "quadratic"
            return x[1] - 1//2;    
        elseif problem == "cubic"
            return x[1]^2 + x[2]^2 - 2//3;    
        else
            return 0;    
        end
    end    
end


function volume_data!(problem, poisson = false) # volume data (generated by FowardDiff)
    hessian = [0.0 0.0;0.0 0.0]
    p(x) = exact_pressure(problem)(x)
    u(x) = exact_solution(problem)(x)
    pgrad = DiffResults.GradientResult([0.0,0.0]);
    hessian = DiffResults.HessianResult([0.0,0.0]);
    velo_rotated(a) = ForwardDiff.gradient(theta(problem),a);
    velo1 = x -> -velo_rotated(x)[2]
    velo2 = x -> velo_rotated(x)[1]
    return function closure(result, x)  
        # compute gradient of pressure
        ForwardDiff.gradient!(pgrad,p,x);
        if (poisson)
            result[1] = 0
            result[2] = 0
        else
            result[1] = DiffResults.gradient(pgrad)[1]
            result[2] = DiffResults.gradient(pgrad)[2]
        end    
        # add Laplacian of velocity
        ForwardDiff.hessian!(hessian,velo1,x)
        result[1] -= nu * (DiffResults.hessian(hessian)[1] + DiffResults.hessian(hessian)[4])
        ForwardDiff.hessian!(hessian,velo2,x)
        result[2] -= nu * (DiffResults.hessian(hessian)[1] + DiffResults.hessian(hessian)[4])
    end    
end


function exact_velocity!(problem) # velocity (= curl(theta), generated by FowardDiff)
    thetagrad = DiffResults.GradientResult([0.0,0.0]);
    return function closure(result, x)
        ForwardDiff.gradient!(thetagrad,theta(problem),x);
        result[1] = -DiffResults.gradient(thetagrad)[2]
        result[2] = DiffResults.gradient(thetagrad)[1]
    end    
    
end

function wrap_pressure(result,x)
    result[1] = exact_pressure(use_problem)(x)
end    

L2error_velocity = zeros(Float64,maxlevel)
L2error_divergence = zeros(Float64,maxlevel)
L2error_pressure = zeros(Float64,maxlevel)
L2error_velocityBA = zeros(Float64,maxlevel)
L2error_velocityRT = zeros(Float64,maxlevel)
L2error_velocityVL = zeros(Float64,maxlevel)
L2error_pressureBA = zeros(Float64,maxlevel)
ndofs = zeros(Int,maxlevel)

for level = 1 : maxlevel

println("Solving Stokes problem on refinement level...", level);
println("Generating grid by triangle...");
maxarea = 4.0^(-level)
grid = triangulate_unitsquare(maxarea)
Grid.show(grid)

# load finite element
use_reconstruction = false
if fem == "TH"
    # Taylor--Hood
    FE_velocity = FiniteElements.getP2FiniteElement(grid,2);
    FE_pressure = FiniteElements.getP1FiniteElement(grid,1);
elseif fem == "MINI"
    # MINI
    FE_velocity = FiniteElements.getMINIFiniteElement(grid,2);
    FE_pressure = FiniteElements.getP1FiniteElement(grid,1);
elseif fem == "CR"
    # Crouzeix--Raviart
    FE_velocity = FiniteElements.getCRFiniteElement(grid,2);
    FE_pressure = FiniteElements.getP0FiniteElement(grid,1);
elseif fem == "BR"
    # Bernardi--Raugel
    FE_velocity = FiniteElements.getBRFiniteElement(grid,2);
    FE_pressure = FiniteElements.getP0FiniteElement(grid,1);
elseif fem == "BR+"
    # Bernardi--Raugel with RT0 reconstruction
    FE_velocity = FiniteElements.getBRFiniteElement(grid,2);
    FE_pressure = FiniteElements.getP0FiniteElement(grid,1);
    use_reconstruction = true
elseif fem == "P2P0"
    # CP2P0
    FE_velocity = FiniteElements.getP2FiniteElement(grid,2);
    FE_pressure = FiniteElements.getP0FiniteElement(grid,1);
end    
FiniteElements.show(FE_velocity)
FiniteElements.show(FE_pressure)
#FiniteElements.show_dofmap(FE_velocity)
#FiniteElements.show_dofmap(FE_pressure)
ndofs_velocity = FiniteElements.get_ndofs(FE_velocity);
ndofs_pressure = FiniteElements.get_ndofs(FE_pressure);
ndofs[level] = ndofs_velocity + ndofs_pressure;

# solve Stokes problem
val4dofs = zeros(Base.eltype(grid.coords4nodes),ndofs[level]);
residual = solveStokesProblem!(val4dofs,nu,volume_data!(use_problem),exact_velocity!(use_problem),grid,FE_velocity,FE_pressure,FiniteElements.get_polynomial_order(FE_velocity)+f_order, use_reconstruction);
    
    # check divergence
    B = ExtendableSparseMatrix{Float64,Int64}(ndofs_velocity,ndofs_velocity)
    FESolveStokes.assemble_divdiv_Matrix!(B,FE_velocity);
    divergence = sqrt(abs(dot(val4dofs[1:ndofs_velocity],B*val4dofs[1:ndofs_velocity])));
    println("divergence = ",divergence);
    L2error_divergence[level] = divergence;

# compute pressure best approximation
val4dofs_pressureBA = FiniteElements.createFEVector(FE_pressure);
residual = computeBestApproximation!(val4dofs_pressureBA,"L2",wrap_pressure,Nothing,FE_pressure,p_order + FiniteElements.get_polynomial_order(FE_pressure))

# compute velocity best approximation
val4dofs_velocityBA = FiniteElements.createFEVector(FE_velocity);
residual = computeBestApproximation!(val4dofs_velocityBA,"L2",exact_velocity!(use_problem),exact_velocity!(use_problem),FE_velocity,u_order+FiniteElements.get_polynomial_order(FE_velocity))

# compute velocity solution of vector Laplacian (Poisson)
val4dofs_velocityVL = FiniteElements.createFEVector(FE_velocity);
residual = FESolvePoisson.solvePoissonProblem!(val4dofs_velocityVL,nu,volume_data!(use_problem, true),exact_velocity!(use_problem),FE_velocity,u_order+FiniteElements.get_polynomial_order(FE_velocity))

# compute errors
integral4cells = zeros(size(grid.nodes4cells,1),1);
integrate!(integral4cells,eval_L2_interpolation_error!(wrap_pressure, val4dofs[ndofs_velocity+1:end], FE_pressure), grid, error_order, 1);
L2error_pressure[level] = sqrt(abs(sum(integral4cells)));
#println("L2_pressure_error_STOKES = " * string(L2error_pressure[level]));
integrate!(integral4cells,eval_L2_interpolation_error!(wrap_pressure, val4dofs_pressureBA, FE_pressure), grid, error_order, 1);
L2error_pressureBA[level] = sqrt(abs(sum(integral4cells)));
#println("L2_pressure_error_BA = " * string(L2error_pressureBA[level]));
integral4cells = zeros(size(grid.nodes4cells,1),2);
integrate!(integral4cells,eval_L2_interpolation_error!(exact_velocity!(use_problem), val4dofs[1:ndofs_velocity], FE_velocity), grid, error_order, 2);
L2error_velocity[level] = sqrt(abs(sum(integral4cells[:])));
#println("L2_velocity_error_STOKES = " * string(L2error_velocity[level]));
integrate!(integral4cells,eval_L2_interpolation_error!(exact_velocity!(use_problem), val4dofs_velocityBA, FE_velocity), grid, error_order, 2);
L2error_velocityBA[level] = sqrt(abs(sum(integral4cells[:])));
#println("L2_velocity_error_BA = " * string(L2error_velocityBA[level]));
integrate!(integral4cells,eval_L2_interpolation_error!(exact_velocity!(use_problem), val4dofs_velocityVL, FE_velocity), grid, error_order, 2);
L2error_velocityVL[level] = sqrt(abs(sum(integral4cells[:])));
#println("L2_velocity_error_VL = " * string(L2error_velocityVL[level]));


# compute error of RT0 best-approximation
FE_RT0 = FiniteElements.getRT0FiniteElement(grid);
FiniteElements.show(FE_RT0)
val4dofs_RT0 = FiniteElements.createFEVector(FE_RT0);
computeBestApproximation!(val4dofs_RT0,"L2",exact_velocity!(use_problem),exact_velocity!(use_problem),FE_RT0,p_order + FiniteElements.get_polynomial_order(FE_RT0))
integrate!(integral4cells,eval_L2_interpolation_error!(exact_velocity!(use_problem), val4dofs_RT0, FE_RT0), grid, error_order, 2);
L2error_velocityRT[level] = sqrt(abs(sum(integral4cells[:])));
println("L2_velocity_error_RT0 = " * string(L2error_velocityRT[level]));    

#plot
if (show_plots) && (level == maxlevel) && ndofs[level] < 7500
    pygui(true)
    
    # evaluate velocity and pressure at grid points
    velo = FESolveCommon.eval_at_nodes(val4dofs,FE_velocity);
    veloRT = FESolveCommon.eval_at_nodes(val4dofs_RT0,FE_RT0);
    pressure = FESolveCommon.eval_at_nodes(val4dofs,FE_pressure,FiniteElements.get_ndofs(FE_velocity));

    PyPlot.figure(1)
    PyPlot.plot_trisurf(view(grid.coords4nodes,:,1),view(grid.coords4nodes,:,2),view(velo,:,1),cmap=get_cmap("ocean"))
    PyPlot.title("Stokes Problem Solution - velocity component 1")
    PyPlot.figure(2)
    PyPlot.plot_trisurf(view(grid.coords4nodes,:,1),view(grid.coords4nodes,:,2),view(velo,:,2),cmap=get_cmap("ocean"))
    PyPlot.title("Stokes Problem Solution - velocity component 2")

    PyPlot.figure(4)
    PyPlot.plot_trisurf(view(grid.coords4nodes,:,1),view(grid.coords4nodes,:,2),view(veloRT,:,1),cmap=get_cmap("ocean"))
    PyPlot.title("RT0 Solution - velocity component 1")
    PyPlot.figure(5)
    PyPlot.plot_trisurf(view(grid.coords4nodes,:,1),view(grid.coords4nodes,:,2),view(veloRT,:,2),cmap=get_cmap("ocean"))
    PyPlot.title("RT0 Solution - velocity component 2")

    PyPlot.figure(3)
    PyPlot.plot_trisurf(view(grid.coords4nodes,:,1),view(grid.coords4nodes,:,2),pressure[:],cmap=get_cmap("ocean"))
    PyPlot.title("Stokes Problem Solution - pressure")
    show()
end
end # loop over levels

println("\n L2 pressure error");
show(L2error_pressure)
println("\n L2 pressure BA error");
show(L2error_pressureBA)
println("\n L2 velocity error");
show(L2error_velocity)
println("\n L2 velocity divergence error");
show(L2error_divergence)
println("\n L2 velocity BA error");
show(L2error_velocityBA)
println("\n L2 velocity VL error");
show(L2error_velocityVL)
println("\n L2 velocity RT error");
show(L2error_velocityRT)

if (show_convergence_history)
    PyPlot.figure()
    PyPlot.loglog(ndofs,L2error_velocity,"-o")
    PyPlot.loglog(ndofs,L2error_divergence,"-o")
    PyPlot.loglog(ndofs,L2error_pressure,"-o")
    PyPlot.loglog(ndofs,L2error_velocityBA,"-o")
    PyPlot.loglog(ndofs,L2error_velocityVL,"-o")
    PyPlot.loglog(ndofs,L2error_velocityRT,"-o")
    PyPlot.loglog(ndofs,L2error_pressureBA,"-o")
    PyPlot.loglog(ndofs,ndofs.^(-1/2),"--",color = "gray")
    PyPlot.loglog(ndofs,ndofs.^(-1),"--",color = "gray")
    PyPlot.loglog(ndofs,ndofs.^(-3/2),"--",color = "gray")
    PyPlot.legend(("L2 error velocity","L2 error divergence","L2 error pressure","L2 error velocity BA","L2 error velocity Poisson","L2 error velocity RT","L2 error pressure BA","O(h)","O(h^2)","O(h^3)"))
    PyPlot.title("Convergence history (fem=" * fem * " problem=" * use_problem * ")")
    ax = PyPlot.gca()
    ax.grid(true)
end    

    
end


main()
