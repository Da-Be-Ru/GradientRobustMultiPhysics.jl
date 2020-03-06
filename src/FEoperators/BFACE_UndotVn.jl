struct BFACE_UndotVn <: FiniteElements.AbstractFEOperator end

# matrix for L2 bestapproximation of normal component on boundary faces that writes into an ExtendableSparseMatrix
function assemble_operator!(A::ExtendableSparseMatrix,::Type{BFACE_UndotVn},FE::AbstractFiniteElement, Dbids::Vector{Int64}, factor::Float64 = 1.0)
    ensure_bfaces!(FE.grid);
    ensure_length4faces!(FE.grid);
    ensure_normal4faces!(FE.grid);
  
    # get quadrature formula
    T = eltype(FE.grid.coords4nodes);
    ET = FE.grid.elemtypes[1]
    ETF = Grid.get_face_elemtype(ET);
    quadorder = 2*FiniteElements.get_polynomial_order(FE);
    qf = QuadratureFormula{T,typeof(ETF)}(quadorder);
     
    # generate caller for FE basis functions
    ndofs4face::Int = FiniteElements.get_ndofs4elemtype(FE, ETF);
    ncomponents::Int = FiniteElements.get_ncomponents(FE);
    FEbasis = FiniteElements.FEbasis_caller_face(FE, qf, false);
    basisvals = zeros(Float64,ndofs4face,ncomponents)
    dofs = zeros(Int64,ndofs4face)

    @assert ncomponents == size(FE.grid.normal4faces,2)
    
    # quadrature loop
    temp = 0.0;
    face = 0;
    #@time begin      
    for r = 1 : length(Dbids),  bface = 1 : size(FE.grid.bfaces,1)
        if FE.grid.bregions[bface] == Dbids[r]

            face = FE.grid.bfaces[bface];
         
            # get dofs
            FiniteElements.get_dofs_on_face!(dofs,FE,face,ETF);
 
            # update FEbasis on face
            FiniteElements.updateFEbasis!(FEbasis, face)
             
            for i in eachindex(qf.w)
                # get FE basis at quadrature point
                FiniteElements.getFEbasis4qp!(basisvals, FEbasis, i)
            
                for dof_i = 1 : ndofs4face, dof_j = dof_i : ndofs4face
                    # fill upper right part and diagonal of matrix
                    @inbounds begin
                        temp = 0.0
                        for k = 1 : ncomponents
                            temp += basisvals[dof_i,k]*FE.grid.normal4faces[face,k]*basisvals[dof_j,k]*FE.grid.normal4faces[face,k];
                        end
                        temp *= factor * qf.w[i] * FE.grid.length4faces[face];
                        A[dofs[dof_i],dofs[dof_j]] += temp;
                        # fill lower left part of matrix
                        if dof_j > dof_i
                            A[dofs[dof_j],dofs[dof_i]] += temp;
                        end 
                    end
                end
            end
      end
    end    
    #end      
end