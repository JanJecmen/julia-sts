using Test
using InteractiveUtils
using StabilityCheck

#
# Examples of type-(un)stable functions
#

abstract type MyAbsVec{T} end

struct MyVec{T <: Signed} <: MyAbsVec{T}
    data :: Vector{T}
end

# Ex. (mysum1) stable, hard: abstract parametric type
mysum1(a::AbstractArray) = begin
    r = zero(eltype(a))
    for x in a
        r += x
    end
    r
end

# Ex. (mysum2) stable, hard: cf. (mysum1) but use our types
# for simpler use case
mysum2(a::MyAbsVec) = begin
    r = zero(eltype(a))
    for x in a
        r += x
    end
    r
end

# Ex. (add1)
# |
# --- a) using `one`
add1i(x :: Integer) = x + one(x)
# |
# --- b) using `1` -- surpricingly stable (coercion)
add1iss(x :: Integer) = x + 1
# |
# --- c) with type inspection -- still stable! (constant folding)
add1typcase(x :: Number) =
    if typeof(x) <: Integer
        x + 1
    elseif typeof(x) <: Real
        x + 1.0
    else
        x + one(x)
    end
# |
# -- d) Number-input: lots of subtypes. Would be stable if skip Rational{Bool} and
#       abstract arguments to parametric types (e.g. Complex{Integer}).
#       Currently unstable.
add1n(x :: Number) = x + one(x)
# |
# -- e) generic parameter (use AbstractFloat i/a of Integer because of the Bool business)
add1r(x :: Complex{T} where T <: AbstractFloat) = x + one(x)

trivial_unstable(x::Int) = x > 0 ? 0 : "0"

plus2i(x :: Integer, y :: Integer) = x + y
plus2n(x :: Number, y :: Number) = x + y

sum_top(v, t) = begin
    res = 0 # zero(eltype(v))
    for x in v
        res += x < t ? x : t
    end
    res
end

# Note: generic methods
# We don't handle generic methods yet (#9)
# rational_plusi(a::Rational{T}, b::Rational{T}) where T <: Integer = a + b

# test call:
#is_stable_function(add1i)

#
# Tests
#

@testset "Simple stable                  " begin
    t1 = is_stable_method(@which add1i(1))
    @test isa(t1, Par)
    @test length(t1.skipexist) == 1 &&
            contains("$t1.skipexist", "SentinelArrays.ChainedVectorIndex")
    # SentinelArrays.ChainedVectorIndex comes from CSV, which we depend upon for
    # reporting. Would be nice to factor out reporting

    t2 = is_stable_method(@which add1i(1))
    @test isa(t2, Par)
    @test length(t2.skipexist) == 1 &&
            contains("$t2.skipexist", "SentinelArrays.ChainedVectorIndex")
    # this is same as above

    @test isa(is_stable_method(@which plus2i(1,1)) , Par)
    @test isa(is_stable_method(@which add1typcase(1)), Par)

    # cf. Note: generic methods
    #@test isa(is_stable_method(@which rational_plusi(1//1,1//1)) , Stb)

    @test isa(is_stable_method(@which add1r(1.0 + 1.0im)) , Stb)
end

@testset "Simple unstable                " begin
    @test isa(is_stable_method(@which add1n(1)),      Uns)
    @test isa(is_stable_method(@which plus2n(1,1)),   Uns)

    # cf. Note: generic methods
    # Alos, this used to fail when abstract instantiations are ON
    # (compare to the similar test in the "stable" examples)
    #@test isa(is_stable_method((@which rational_plusi(1//1,1//1)), SearchCfg(abstract_args=true)), Stb)

    @test isa(is_stable_method((@which add1r(1.0 + 1.0im)), SearchCfg(abstract_args=true)) , Stb)
end

@testset "Special (Any, Varargs, Generic)" begin
    f(x)=1
    @test is_stable_method(@which f(2)) == AnyParam(Any[Any])
    g(x...)=2
    @test is_stable_method(@which g(2)) == VarargParam(Any[Vararg{Any}])
    gen(x::T) where T = 1
    @test is_stable_method(@which gen(1)) == GenericMethod()
end

@testset "Fuel                           " begin
    g(x::Int)=2
    @test isa(is_stable_method((@which g(2)), SearchCfg(fuel=1)) , Stb)

    h(x::Integer)=3
    @test is_stable_method((@which h(2)), SearchCfg(fuel=1)) == OutOfFuel()

    # Instantiations fuel
    k(x::Complex{T} where T<:Integer)=3
    t3 = is_stable_method((@which k(1+1im)), SearchCfg(max_instantiations=1))
    @test t3 isa Par &&
        length(t3.skipexist) == 2 && # one for TooManyInst and
                                     # one for the dreaded SentinelArrays.ChainedVectorIndex <: Integer
        contains("$t3.skipexist", "TooManyInst")
end

# (Un)Stable Modules

module M
export a, b, c;
a()=1; b()=2
c=3; # not a function!
d()=if rand()>0.5; 1; else ""; end
end

@testset "is_stable_module               " begin
    @test is_stable_moduleb(M, SearchCfg(exported_names_only=true))
    @test ! is_stable_moduleb(M)
end

# Stats

module N
export a, b;
a()=1; b()=2
g(x...)=2
f(x)=1
d()=if rand()>0.5; 1; else ""; end
end

@testset "Collecting stats               " begin
    @test aggregateStats(is_stable_module(N)) == AgStats(5, 2, 0, 1, 1, 1, 0, 0, 0)
end

# Recursing into submodules

# should not be included in the result
module TestExternalModule
export ext
ext(x::Int64) = 2x
end

# only exports stable
module TestNestedModule
    export NestedA, stable, ext

    import ..TestExternalModule: ext, TestExternalModule

    # exported, only exports stable
    module NestedA
        export NestedA1, stableA

        # exported, only exports stable
        module NestedA1
            export stableA1
            stableA1() = 1
            unstableA1() = if rand()>0.5; 1; else ""; end
        end
        # not exported, exports everything
        module NestedA2
            export stableA2, unstableA2
            stableA2() = 1
            unstableA2() = if rand()>0.5; 1; else ""; end
        end
        # deeply nested
        module NestedA3
            module NestedA3a
                module NestedA3b
                    module NestedA3c
                        module NestedA3d
                            module NestedA3e
                                unstableA3abcde() = if rand()>0.5; 1; else ""; end
                            end
                        end
                    end
                end
            end
        end
        stableA() = 1
        unstableA() = if rand()>0.5; 1; else ""; end
    end

    # not exported, exports everything
    module NestedB
        export NestedB1, stableB, unstableB
        module NestedB1
            export stableB1, unstableB1
            stableB1() = 1
            unstableB1() = if rand()>0.5; 1; else ""; end
        end
        stableB() = 1
        unstableB() = if rand()>0.5; 1; else ""; end
    end
    stable() = 1
    unstable() = if rand()>0.5; 1; else ""; end
end

@testset "is_stable_module nesting       " begin
    @test is_stable_moduleb(TestNestedModule, SearchCfg(exported_names_only=true))
    @test aggregateStats(is_stable_module(TestNestedModule)) == AgStats(13, 6, 0, 7, 0, 0, 0, 0, 0)
    @test !any(mc -> mc.method.module === TestExternalModule, is_stable_module(TestNestedModule))
end

@testset "Types Database                 " begin
    f(x)=1
    # Normally, we don't process Any-arg methods
    # (there's no way to enumerate subtypes of Any),
    # see "Special (Any, Varargs, Generic)" testset above.
    # But we can load a types database and try only types
    # from there.
    typesdb_cfg = build_typesdb_scfg("merged-small.csv")
    @test Stb(2) == is_stable_method((@which f(1)), typesdb_cfg)
end

module ImportBase; import Base.push!; push!(::Int)=1; end
@testset "Method discovery completeness   " begin
    chks = is_stable_module(ImportBase)
    @test length(chks) == 1
    @test chks[1].check == Stb(1)
end
