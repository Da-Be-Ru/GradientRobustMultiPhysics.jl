
"""
$(TYPEDEF)

Continuous piecewise second-order polynomials

allowed ElementGeometries:
- Edge1D (quadratic polynomials)
- Triangle2D (quadratic polynomials)
- Quadrilateral2D (Q2 space)
- Tetrahedron3D (quadratic polynomials)
"""
abstract type H1P2{ncomponents,edim} <: AbstractH1FiniteElement where {ncomponents<:Int,edim<:Int} end

get_ncomponents(FEType::Type{<:H1P2}) = FEType.parameters[1]
get_edim(FEType::Type{<:H1P2}) = FEType.parameters[2]

get_ndofs_on_face(FEType::Type{<:H1P2}, EG::Type{<:Union{AbstractElementGeometry1D, Triangle2D, Tetrahedron3D}}) = Int((FEType.parameters[2])*(FEType.parameters[2]+1)/2*FEType.parameters[1])
get_ndofs_on_cell(FEType::Type{<:H1P2}, EG::Type{<:Union{AbstractElementGeometry1D, Triangle2D, Tetrahedron3D}}) = Int((FEType.parameters[2]+1)*(FEType.parameters[2]+2)/2*FEType.parameters[1])
get_ndofs_on_cell(FEType::Type{<:H1P2}, EG::Type{<:Quadrilateral2D}) = 8*FEType.parameters[1]


get_polynomialorder(::Type{<:H1P2}, ::Type{<:Edge1D}) = 2;
get_polynomialorder(::Type{<:H1P2}, ::Type{<:Triangle2D}) = 2;
get_polynomialorder(::Type{<:H1P2}, ::Type{<:Quadrilateral2D}) = 3;
get_polynomialorder(::Type{<:H1P2}, ::Type{<:Tetrahedron3D}) = 2;


get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry1D}) = "N1I1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry2D}) = "N1F1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry3D}) = "N1E1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{FaceDofs}, EG::Type{<:AbstractElementGeometry0D}) = "N1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{FaceDofs}, EG::Type{<:AbstractElementGeometry1D}) = "N1I1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{FaceDofs}, EG::Type{<:AbstractElementGeometry2D}) = "N1E1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{BFaceDofs}, EG::Type{<:AbstractElementGeometry0D}) = "N1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{BFaceDofs}, EG::Type{<:AbstractElementGeometry1D}) = "N1I1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{BFaceDofs}, EG::Type{<:AbstractElementGeometry2D}) = "N1E1"
get_dofmap_pattern(FEType::Type{<:H1P2}, ::Type{EdgeDofs}, EG::Type{<:AbstractElementGeometry1D}) = "N1I1"


function init!(FES::FESpace{FEType}) where {FEType <: H1P2}
    ncomponents = get_ncomponents(FEType)
    edim = get_edim(FEType)
    name = "P2"
    for n = 1 : ncomponents-1
        name = name * "xP2"
    end
    FES.name = name * " (H1, edim=$edim)"   

    # total number of dofs
    ndofs = 0
    nnodes = num_sources(FES.xgrid[Coordinates]) 
    ndofs4component = 0
    if edim == 1
        ncells = num_sources(FES.xgrid[CellNodes])
        ndofs4component = nnodes + ncells
    elseif edim == 2
        nfaces = num_sources(FES.xgrid[FaceNodes])
        ndofs4component = nnodes + nfaces
    elseif edim == 3
        nedges = num_sources(FES.xgrid[EdgeNodes])
        ndofs4component = nnodes + nedges
    end    
    FES.ndofs = ndofs4component * ncomponents

end

function interpolate!(Target::AbstractArray{<:Real,1}, FE::FESpace{FEType}, ::Type{AT_NODES}, exact_function!; items = [], bonus_quadorder::Int = 0, time = 0) where {FEType <: H1P2}
    edim = get_edim(FEType)
    nnodes = size(FE.xgrid[Coordinates],2)
    if edim == 1
        nedges = num_sources(FE.xgrid[CellNodes])
    elseif edim == 2
        nedges = num_sources(FE.xgrid[FaceNodes])
    elseif edim == 3
        nedges = num_sources(FE.xgrid[EdgeNodes])
    end

    point_evaluation!(Target, FE, AT_NODES, exact_function!; items = items, component_offset = nnodes + nedges, time = time)

end

function interpolate!(Target::AbstractArray{<:Real,1}, FE::FESpace{FEType}, ::Type{ON_EDGES}, exact_function!; items = [], bonus_quadorder::Int = 0, time = 0) where {FEType <: H1P2}
    edim = get_edim(FEType)
    if edim == 3
        # delegate edge nodes to node interpolation
        subitems = slice(FE.xgrid[EdgeNodes], items)
        interpolate!(Target, FE, AT_NODES, exact_function!; items = subitems, time = time)

        # perform edge mean interpolation
        ensure_edge_moments!(Target, FE, ON_EDGES, exact_function!; items = items, time = time)
    end
end

function interpolate!(Target::AbstractArray{<:Real,1}, FE::FESpace{FEType}, ::Type{ON_FACES}, exact_function!; items = [], bonus_quadorder::Int = 0, time = 0) where {FEType <: H1P2}
    edim = get_edim(FEType)
    if edim == 2
        # delegate face nodes to node interpolation
        subitems = slice(FE.xgrid[FaceNodes], items)
        interpolate!(Target, FE, AT_NODES, exact_function!; items = subitems, time = time)

        # perform face mean interpolation
        ensure_edge_moments!(Target, FE, ON_FACES, exact_function!; items = items, time = time)
    elseif edim == 3
        # delegate face edges to edge interpolation
        subitems = slice(FE.xgrid[FaceEdges], items)
        interpolate!(Target, FE, ON_EDGES, exact_function!; items = subitems, time = time)
    elseif edim == 1
        # delegate face nodes to node interpolation
        subitems = slice(FE.xgrid[FaceNodes], items)
        interpolate!(Target, FE, AT_NODES, exact_function!; items = subitems, time = time)
    end
end


function interpolate!(Target::AbstractArray{<:Real,1}, FE::FESpace{FEType}, ::Type{ON_CELLS}, exact_function!; items = [], bonus_quadorder::Int = 0, time = 0) where {FEType <: H1P2}
    edim = get_edim(FEType)
    ncells = num_sources(FE.xgrid[CellNodes])
    if edim == 2
        # delegate cell faces to face interpolation
        subitems = slice(FE.xgrid[CellFaces], items)
        interpolate!(Target, FE, ON_FACES, exact_function!; items = subitems, time = time)
    elseif edim == 3
        # delegate cell edges to edge interpolation
        subitems = slice(FE.xgrid[CellEdges], items)
        interpolate!(Target, FE, ON_EDGES, exact_function!; items = subitems, time = time)
    elseif edim == 1
        # delegate cell nodes to node interpolation
        subitems = slice(FE.xgrid[CellNodes], items)
        interpolate!(Target, FE, AT_NODES, exact_function!; items = subitems, time = time)

        # preserve cell integral
        ensure_edge_moments!(Target, FE, ON_CELLS, exact_function!; items = items, time = time)
    end
end

function nodevalues!(Target::AbstractArray{<:Real,2}, Source::AbstractArray{<:Real,1}, FE::FESpace{<:H1P2})
    nnodes = num_sources(FE.xgrid[Coordinates])
    FEType = eltype(FE)
    ncomponents::Int = get_ncomponents(FEType)
    edim = get_edim(FEType)
    if edim == 1
        ncells = num_sources(FE.xgrid[CellNodes])
        offset4component = 0:(nnodes+ncells):ncomponents*(nnodes+ncells)
    elseif edim == 2
        nfaces = num_sources(FE.xgrid[FaceNodes])
        offset4component = 0:(nnodes+nfaces):ncomponents*(nnodes+nfaces)
    elseif edim == 3
        nedges = num_sources(FE.xgrid[EdgeNodes])
        offset4component = 0:(nnodes+nedges):ncomponents*(nnodes+nedges)
    end
    for node = 1 : nnodes
        for c = 1 : ncomponents
            Target[c,node] = Source[offset4component[c]+node]
        end    
    end    
end


function get_basis_on_cell(::Type{<:H1P2}, ::Type{<:Vertex0D})
    ncomponents = get_ncomponents(FEType)
    function closure(refbasis,xref)
        for k = 1 : ncomponents
            refbasis[k,k] = 1
        end
    end
end

function get_basis_on_cell(FEType::Type{<:H1P2}, ::Type{<:Edge1D})
    ncomponents = get_ncomponents(FEType)
    function closure(refbasis, xref)
        temp = 1 - xref[1]
        for k = 1 : ncomponents
            refbasis[3*k-2,k] = 2*temp*(temp - 1//2)            # node 1
            refbasis[3*k-1,k] = 2*xref[1]*(xref[1] - 1//2)      # node 2
            refbasis[3*k,k] = 4*temp*xref[1]                    # face 1
        end
    end
end

function get_basis_on_cell(FEType::Type{<:H1P2}, ::Type{<:Triangle2D})
    ncomponents = get_ncomponents(FEType)
    function closure(refbasis, xref)
        temp = 1 - xref[1] - xref[2]
        for k = 1 : ncomponents
            refbasis[6*k-5,k] = 2*temp*(temp - 1//2)            # node 1
            refbasis[6*k-4,k] = 2*xref[1]*(xref[1] - 1//2)      # node 2
            refbasis[6*k-3,k] = 2*xref[2]*(xref[2] - 1//2)      # node 3
            refbasis[6*k-2,k] = 4*temp*xref[1]                  # face 1
            refbasis[6*k-1,k] = 4*xref[1]*xref[2]               # face 2
            refbasis[6*k,k] = 4*xref[2]*temp                    # face 3
        end
    end
end


function get_basis_on_cell(FEType::Type{<:H1P2}, ::Type{<:Tetrahedron3D})
    ncomponents = get_ncomponents(FEType)
    function closure(refbasis, xref)
        temp = 1 - xref[1] - xref[2] - xref[3]
        for k = 1 : ncomponents
            refbasis[10*k-9,k] = 2*temp*(temp - 1//2)            # node 1
            refbasis[10*k-8,k] = 2*xref[1]*(xref[1] - 1//2)      # node 2
            refbasis[10*k-7,k] = 2*xref[2]*(xref[2] - 1//2)      # node 3
            refbasis[10*k-6,k] = 2*xref[3]*(xref[3] - 1//2)      # node 4
            refbasis[10*k-5,k] = 4*temp*xref[1]                  # edge 1
            refbasis[10*k-4,k] = 4*temp*xref[2]                  # edge 2
            refbasis[10*k-3,k] = 4*temp*xref[3]                  # edge 3
            refbasis[10*k-2,k] = 4*xref[1]*xref[2]               # edge 4
            refbasis[10*k-1,k] = 4*xref[1]*xref[3]               # edge 5
            refbasis[10*k  ,k] = 4*xref[2]*xref[3]               # edge 6
        end
    end
end


function get_basis_on_cell(FEType::Type{<:H1P2}, ::Type{<:Quadrilateral2D})
    ncomponents = get_ncomponents(FEType)
    function closure(refbasis, xref)
        refbasis[1,1] = 1 - xref[1]
        refbasis[2,1] = 1 - xref[2]
        refbasis[3,1] = 2*xref[1]*xref[2]*(xref[1]+xref[2]-3//2);
        refbasis[4,1] = -2*xref[2]*refbasis[1,1]*(xref[1]-xref[2]+1//2);
        refbasis[5,1] = 4*xref[1]*refbasis[1,1]*refbasis[2,1]
        refbasis[6,1] = 4*xref[2]*xref[1]*refbasis[2,1]
        refbasis[7,1] = 4*xref[1]*xref[2]*refbasis[1,1]
        refbasis[8,1] = 4*xref[2]*refbasis[1,1]*refbasis[2,1]
        refbasis[1,1] = -2*refbasis[1,1]*refbasis[2,1]*(xref[1]+xref[2]-1//2);
        refbasis[2,1] = -2*xref[1]*refbasis[2,1]*(xref[2]-xref[1]+1//2);
        for k = 2 : ncomponents
            refbasis[8*k-7,k] = refbasis[1,1] # node 1
            refbasis[8*k-6,k] = refbasis[2,1] # node 2
            refbasis[8*k-5,k] = refbasis[3,1] # node 3
            refbasis[8*k-4,k] = refbasis[4,1] # node 4
            refbasis[8*k-3,k] = refbasis[5,1] # face 1
            refbasis[8*k-2,k] = refbasis[6,1] # face 2
            refbasis[8*k-1,k] = refbasis[7,1] # face 3
            refbasis[8*k,k] = refbasis[8,1]  # face 4
        end
    end
end


function get_basis_on_face(FE::Type{<:H1P2}, EG::Type{<:AbstractElementGeometry})
    return get_basis_on_cell(FE, EG)
end
