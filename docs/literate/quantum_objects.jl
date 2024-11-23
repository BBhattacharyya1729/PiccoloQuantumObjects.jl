# ```@meta
# CollapsedDocStrings = true
# ```

using PiccoloQuantumObjects
using SparseArrays # for visualization
⊗ = kron;

#==========================================================================================
# Quantum objects

Most of the time, we work with quantum states and operators in the form of complex vectors
and matrices. We provide a number of convenient ways to construct these objects.
==========================================================================================#

#==========================================================================================
## Quantum states

We can construct quantum states from bitstrings or string representations. The string 
representations use atomic notation (ground state `g`, excited state `e`, etc.).
==========================================================================================#

ket_from_string("g", [2])
#

ket_from_string("(g+e)g", [2,2])
#

ket_from_bitstring("01")
#

#==========================================================================================
## Quantum operators

Frequently used operators are provided in [`PAULIS`](@ref) and [`GATES`](@ref).
```@docs
GATES
```
Quantum operators can also be constructed from strings.
==========================================================================================#

operator_from_string("X")
#

operator_from_string("XZ")

# Annihilation and creation operators are provided for oscillator systems.
a = annihilate(3)

#
a⁺ = create(3)

#
a'a

# ### Random operators

# The [`haar_random`](@ref) function draws random unitary operators according to the Haar
# measure.

haar_random(3)

# If we want to generate random operations that are close to the identity, we can use the 
# [`haar_random`](@ref) function.

haar_identity(2, 0.1)

#
haar_identity(2, 0.01)

#==========================================================================================

## Embedded operators
Sometimes we want to embed a quantum operator into a larger Hilbert space, $\mathcal{H}$,
which we decompose into subspace and leakage components:
```math
    \mathcal{H} = \mathcal{H}_{\text{subspace}} \oplus \mathcal{H}_{\text{leakage}},
```
In quantum computing, the computation is encoded in a `subspace`, while the remaining
`leakage` states should be avoided.

### The `embed` and `unembed` functions

The [`embed`](@ref) function allows to embed a quantum operator in a larger Hilbert space.
```@docs
embed
```

The [`unembed`](@ref) function allows to unembed a quantum operator from a larger Hilbert 
space.
```@docs
unembed
```
==========================================================================================#

# We can embed the two-level X gate into a multilevel system:

levels = 3
X = GATES[:X]
subspace_indices = 1:2
X_embedded = embed(X, subspace_indices, levels)

# Unembed to retrieve the original operator:
X_original = unembed(X_embedded, subspace_indices)

#=
### The `EmbeddedOperator` type
The [`EmbeddedOperator`](@ref) type stores information about an operator embedded in the subspace 
of a larger quantum system.
```@docs
EmbeddedOperator
```

We can construct an embedded operator in the same manner as the `embed` function:
```@docs
EmbeddedOperator(subspace_operator::Matrix{<:Number}, subspace::AbstractVector{Int}, subsystem_levels::AbstractVector{Int})
```
=#

# For an X gate on the first qubit of two qubit, 3-level system:
gate = GATES[:X] ⊗ GATES[:I]
subsystem_levels = [3, 3]
subspace_indices = get_subspace_indices([1:2, 1:2], subsystem_levels)
embedded_operator = EmbeddedOperator(gate, subspace_indices, subsystem_levels)

# Show the full operator.
embedded_operator.operator .|> real |> sparse

# We can get the original operator back.
unembed(embedded_operator) .|> real |> sparse

#=
## Subspace and leakage indices

### The `get_subspace_indices` function
The [`get_subspace_indices`](@ref) function is a convenient way to get the indices of a subspace in
a larger quantum system. 
```@docs
get_subspace_indices
```
Its dual function is [`get_leakage_indices`](@ref). 

=#

get_subspace_indices(1:2, 5) |> collect, get_leakage_indices(1:2, 5) |> collect

# Composite systems are supported. For example, we can get the indices of the qubit
# subspace of two 3-level systems.
get_subspace_indices([1:2, 1:2], [3, 3])

# Qubits are assumed if the indices are not provided.
get_subspace_indices([3, 3])

#
get_leakage_indices([3, 3])

#=
### Excitation number restrictions
Sometimes we want to cap the number of excitations we allow across a composite system. 
For example, if we want to restrict ourselves to the ground and single excitation states 
of two 3-level systems:
=#
get_enr_subspace_indices(1, [3, 3])

#=
### The `get_iso_vec_subspace_indices` function
For isomorphic operators, the [`get_iso_vec_subspace_indices`](@ref) function can be used 
to find the appropriate vector indices of the equivalent operator subspace.
```@docs
get_iso_vec_subspace_indices
```

Its dual function is [`get_iso_vec_leakage_indices`](@ref), which by default only returns
the leakage indices of the blocks:
```math
\mathcal{H}_{\text{subspace}} \otimes \mathcal{H}_{\text{subspace}},\quad
\mathcal{H}_{\text{subspace}} \otimes \mathcal{H}_{\text{leakage}},\quad
\mathcal{H}_{\text{leakage}} \otimes \mathcal{H}_{\text{subspace}}
```
allowing for leakage-suppressing code to disregard the uncoupled pure-leakage space.
=#

get_iso_vec_subspace_indices(1:2, 3)

#
ignore_pure_leakage = get_iso_vec_leakage_indices(1:2, 3)

#
setdiff(get_iso_vec_leakage_indices(1:2, 3, ignore_pure_leakage=false), ignore_pure_leakage)

