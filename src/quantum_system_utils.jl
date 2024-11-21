module QuantumSystemUtils

export is_reachable

using ..EmbeddedOperators
using ..QuantumObjectUtils
using ..QuantumSystems
using ..Gates

using LinearAlgebra
using SparseArrays
using TestItemRunner


commutator(A::AbstractMatrix{<:Number}, B::AbstractMatrix{<:Number}) = A * B - B * A

is_hermitian(H::AbstractMatrix{<:Number}; atol=eps(Float32)) = all(isapprox.(H - H', 0.0, atol=atol))

is_linearly_dependent(basis::Vector{<:AbstractMatrix{<:Number}}; kwargs...) = 
    is_linearly_dependent(stack(vec.(basis)); kwargs...)

function is_linearly_dependent(M::AbstractMatrix; eps=eps(Float32), verbose=true)
    if size(M, 2) > size(M, 1)
        if verbose
            println("Linearly dependent because columns > rows, $(size(M, 2)) > $(size(M, 1)).")
        end
        return true
    end
    # QR decomposition has a zero R on diagonal if linearly dependent
    val = minimum(abs.(diag(qr(M).R)))
    return isapprox(val, 0.0, atol=eps)
end

function linearly_independent_indices(
    basis::Vector{<:AbstractMatrix{<:Number}};
    order=1:length(basis),
    kwargs...
)
    @assert issetequal(order, 1:length(basis)) "Order must enumerate entire basis."
    bᵢ = Int[]
    for i ∈ order
        if !is_linearly_dependent([basis[bᵢ]..., basis[i]]; kwargs...)
            push!(bᵢ, i)
        end
    end
    return bᵢ
end

function linearly_independent_subset(basis::Vector{<:AbstractMatrix}; kwargs...)
    bᵢ = linearly_independent_indices(basis; kwargs...)
    return deepcopy(basis[bᵢ])
end

function linearly_independent_subset!(basis::Vector{<:AbstractMatrix}; kwargs...)
    bᵢ = linearly_independent_indices(basis; kwargs...)
    deleteat!(basis, setdiff(1:length(basis), bᵢ))
    return nothing
end

traceless(M::AbstractMatrix) = M - tr(M) * I / size(M, 1)

"""
    operator_algebra(generators; kwargs...)

Compute the Lie algebra basis for the given `generators`.

# Arguments
- `generators::Vector{<:AbstractMatrix}`: generators of the Lie algebra

# Keyword Arguments
- `return_layers::Bool=false`: return the Lie tree layers
- `normalize::Bool=false`: normalize the basis
- `verbose::Bool=false`: print information
- `remove_trace::Bool=true`: remove trace from generators

"""
function operator_algebra(
    generators::Vector{<:AbstractMatrix{T}};
    return_layers=false,
    normalize=false,
    verbose=false,
    remove_trace=true
) where T <: Number
    # Initialize basis (traceless, normalized)
    basis = normalize ? [g / norm(g) for g ∈ generators] : deepcopy(generators)
    if remove_trace
        @. basis = traceless(basis)
    end

    # Initialize layers
    current_layer = deepcopy(basis)
    if return_layers
        all_layers = Vector{Matrix{T}}[deepcopy(basis)]
    end

    subspace_termination = false

    ℓ = 1
    if verbose
        print("operator algebra depth = [")
        print("$(ℓ)")
    end
    if is_linearly_dependent(basis)
        println("Linearly dependent generators.")
    else
        # Note: Use left normalized commutators
        # Note: Jacobi identity is not checked
        need_basis = true
        algebra_dim = size(first(generators), 1)^2 - 1
        while need_basis
            layer = Matrix{T}[]
            # Repeat commutators until no new operators are found
            for op ∈ current_layer
                for gen ∈ generators
                    if !need_basis
                        continue
                    end

                    test = commutator(gen, op)
                    if all(test .≈ 0)
                        continue
                    # Current basis is assumed to be linearly independent
                    elseif is_linearly_dependent([basis..., test], verbose=verbose)
                        continue
                    else
                        test .= is_hermitian(test) ? test : im * test
                        test .= normalize ? test / norm(test) : test
                        push!(basis, test)
                        push!(layer, test)
                        need_basis = length(basis) < algebra_dim ? true : false
                    end
                end
            end

            if isempty(layer)
                if verbose
                    println("Subspace termination.")
                end
                subspace_termination = true
                break
            else
                current_layer = layer
                ℓ += 1
                if verbose
                    print(" $(ℓ)")
                end
            end

            if return_layers
                append!(all_layers, [current_layer])
            end
        end
    end

    if verbose && !subspace_termination
        println("]")
    end

    if return_layers
        return basis, all_layers
    else
        return basis
    end
end

function fit_gen_to_basis(
    gen::AbstractMatrix{<:Number},
    basis::AbstractVector{<:AbstractMatrix{<:Number}}
)
    A = stack(vec.(basis))
    b = vec(gen)
    return A \ b
end

function is_in_span(
    gen::AbstractMatrix{<:Number},
    basis::AbstractVector{<:AbstractMatrix{<:Number}};
    subspace::AbstractVector{Int}=1:size(gen, 1),
    atol=eps(Float32),
    return_effective_gen=false,
)
    g_basis = [deepcopy(b[subspace, subspace]) for b ∈ basis]
    linearly_independent_subset!(g_basis)
    # Traceless basis needs traceless fit
    x = fit_gen_to_basis(gen, g_basis)
    g_eff = sum(x .* g_basis)
    ε = norm(g_eff - gen, 2)
    if return_effective_gen
        return ε < atol, g_eff
    else
        return ε < atol
    end
end

# ----------------------------------------------------------------------------- #
#                            Reachability                                       #
# ----------------------------------------------------------------------------- #

"""
    is_reachable(gate, hamiltonians; kwargs...)

Check if the gate is reachable from the given generators.

# Arguments
- `gate::AbstractMatrix`: target gate
- `hamiltonians::AbstractVector{<:AbstractMatrix}`: generators of the Lie algebra

# Keyword Arguments
- `subspace::AbstractVector{<:Int}=1:size(gate, 1)`: subspace indices
- `compute_basis::Bool=true`: compute the basis or use the Hamiltonians directly
- `remove_trace::Bool=true`: remove trace from generators
- `verbose::Bool=true`: print information about the operator algebra
- `atol::Float32=eps(Float32)`: absolute tolerance

See also [`QuantumSystemUtils.operator_algebra`](@ref).
"""
function is_reachable(
    gate::AbstractMatrix{<:Number},
    hamiltonians::AbstractVector{<:AbstractMatrix{<:Number}};
    subspace::AbstractVector{Int}=1:size(gate, 1),
    compute_basis=true,
    remove_trace=true,
    verbose=true,
    atol=eps(Float32)
)
    @assert size(gate, 1) == length(subspace) "Gate must be given in the subspace."
    generator = im * log(gate)

    if remove_trace
        generator = traceless(generator)
    end

    if compute_basis
        basis = operator_algebra(hamiltonians, remove_trace=remove_trace, verbose=verbose)
    else
        basis = hamiltonians
    end

    return is_in_span(
        generator,
        basis,
        subspace=subspace,
        atol=atol
    )
end

"""
    is_reachable(gate, system; kwargs...)

Check if the gate is reachable from the given system.

# Arguments
- `gate::AbstractMatrix`: target gate
- `system::QuantumSystem`: quantum system

# Keyword Arguments
- `use_drift::Bool=true`: include drift Hamiltonian in the generators
- `kwargs...`: keyword arguments for `is_reachable`

# Example

```jldoctest
julia> sys = QuantumSystem(PAULIS[:Z], [PAULIS[:X]])
julia> is_reachable(GATES[:Y], sys)
true

julia> sys = QuantumSystem([PAULIS[:X]])
julia> is_reachable(GATES[:Y], sys)
false
```

"""
function is_reachable(
    gate::AbstractMatrix{<:Number},
    system::QuantumSystem;
    use_drift::Bool=true,
    kwargs...
)
    H_drift = sparse(system.H(zeros(system.n_drives)))
    hamiltonians = [
        sparse(system.H(I[1:system.n_drives, i])) - H_drift
            for i = 1:system.n_drives
    ]
    if use_drift && !isapprox(H_drift, zeros(eltype(H_drift), size(H_drift)))
        push!(hamiltonians, H_drift)
    end
    return is_reachable(gate, hamiltonians; kwargs...)
end

is_reachable(gate::EmbeddedOperator, args...; kwargs...) =
    is_reachable(unembed(gate), args...; subspace=gate.subspace, kwargs...)

# ****************************************************************************** #

@testitem "Lie algebra basis" begin
    # Check 1 qubit with complete basis
    gen = operator_from_string.(["X", "Y"])
    basis = operator_algebra(gen, return_layers=false, verbose=false)
    @test length(basis) == size(first(gen), 1)^2-1

    # Check 1 qubit with complete basis and layers
    basis, layers = operator_algebra(gen, return_layers=true, verbose=false)
    @test length(basis) == size(first(gen), 1)^2-1

    # Check 1 qubit with subspace
    gen = operator_from_string.(["X"])
    basis = operator_algebra(gen, verbose=false)
    @test length(basis) == 1

    # Check 2 qubit with complete basis
    gen = operator_from_string.(["XX", "YY", "XI", "YI", "IY", "IX"])
    basis = operator_algebra(gen, verbose=false)
    @test length(basis) == size(first(gen), 1)^2-1

    # Check 2 qubit with linearly dependent basis
    gen = operator_from_string.(["XX", "YY", "XI", "XI", "IY", "IX"])
    basis = operator_algebra(gen, verbose=false)
    @test length(basis) == length(gen)

    # Check 2 qubit with pair of 1-qubit subspaces
    gen = operator_from_string.(["XI", "YI", "IY", "IX"])
    basis = operator_algebra(gen, verbose=false)
    @test length(basis) == 2 * (2^2 - 1)
end

@testitem "Lie Algebra reachability single qubit" begin
    # Check 1 qubit with complete basis
    gen = [PAULIS[:X], PAULIS[:Y]]
    target = PAULIS[:Z]
    @test is_reachable(target, gen, compute_basis=true, verbose=false)

    # System
    sys = QuantumSystem([PAULIS[:X], PAULIS[:Y], PAULIS[:Z]])
    target = PAULIS[:Z]
    @test is_reachable(target, sys, verbose=false)

    # System with drift
    sys = QuantumSystem(PAULIS[:Z], [PAULIS[:X]])
    target = PAULIS[:Z]
    @test is_reachable(target, sys, verbose=false)
end

@testitem "Lie Algebra reachability two qubits" begin
    using LinearAlgebra
    ⊗ = kron

    # Check 2 qubit with complete basis
    XI = PAULIS[:X] ⊗ PAULIS[:I]
    IX = PAULIS[:I] ⊗ PAULIS[:X]
    YI = PAULIS[:Y] ⊗ PAULIS[:I]
    IY = PAULIS[:I] ⊗ PAULIS[:Y]
    XX = PAULIS[:X] ⊗ PAULIS[:X]
    YY = PAULIS[:Y] ⊗ PAULIS[:Y]
    ZI = PAULIS[:Z] ⊗ PAULIS[:I]
    IZ = PAULIS[:I] ⊗ PAULIS[:Z]
    ZZ = PAULIS[:Z] ⊗ PAULIS[:Z]

    complete_gen = [XX+YY, XI, YI, IX, IY]
    incomplete_gen = [XI, ZZ]
    r = [0, 1, 2, 3, 4]
    r /= norm(r)
    R2 = exp(-im * sum([θ * H for (H, θ) in zip(complete_gen, r)]))
    CZ = [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1]
    CX = [1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]

    # Pass
    @test is_reachable(R2, complete_gen, verbose=false)
    @test is_reachable(CZ, complete_gen, verbose=false)
    @test is_reachable(CX, complete_gen, verbose=false)
    @test is_reachable(XI, complete_gen, verbose=false)

    # Mostly fail
    @test !is_reachable(R2, incomplete_gen, verbose=false)
    @test !is_reachable(CZ, incomplete_gen, verbose=false)
    @test !is_reachable(CX, incomplete_gen, verbose=false)
    @test is_reachable(XI, incomplete_gen, verbose=false)

    # QuantumSystems
    complete_gen_sys = QuantumSystem(complete_gen)
    incomplete_gen_sys = QuantumSystem(incomplete_gen)
    # Pass
    @test is_reachable(R2, complete_gen_sys, verbose=false)
    @test is_reachable(CZ, complete_gen_sys, verbose=false)
    @test is_reachable(CX, complete_gen_sys, verbose=true)
    @test is_reachable(XI, complete_gen_sys, verbose=false)

    # Mostly fail
    @test !is_reachable(R2, incomplete_gen_sys, verbose=false)
    @test !is_reachable(CZ, incomplete_gen_sys, verbose=false)
    @test !is_reachable(CX, incomplete_gen_sys, verbose=false)
    @test is_reachable(XI, incomplete_gen_sys, verbose=false)
end

@testitem "Lie Algebra embedded subspace reachability" begin
    # Check 1 qubit with complete basis
    gen = [PAULIS[:X], PAULIS[:Y]]
    target = EmbeddedOperator(PAULIS[:Z], 1:2, 4)
    @test is_reachable(target, gen, verbose=false)

    # System
    sys = QuantumSystem([GATES[:X], GATES[:Y]])
    @test is_reachable(target, sys, verbose=false)
end

end
