module StabilityCheck

#
# Exhaustive enumeration of types for static type stability checking
#

export @stable, @stable!, @stable!_nop,
    is_stable_method, is_stable_function, is_stable_module, is_stable_moduleb,
    check_all_stable,
    convert,
    typesDB,

    # Stats
    AgStats,
    aggregateStats,
    # CSV-aware tools
    checkModule, prepCsv,

    # Types
    MethStCheck,
    SkippedUnionAlls, UnboundedUnionAlls, SkipMandatory, TooManyInst,
    Stb, Par, Uns, AnyParam, VarargParam, TcFail, OutOfFuel, GenericMethod,
    SearchCfg, build_typesdb_scfg, default_scfg

# Debug print:
# ENV["JULIA_DEBUG"] = StabilityCheck  # turn on
# ENV["JULIA_DEBUG"] = Nothing         # turn off

include("equality.jl")

using InteractiveUtils
using MacroTools
using CSV
using Setfield

include("typesDB.jl")
include("types.jl")
include("report.jl")
include("utils.jl")
include("enumeration.jl")
include("annotations.jl")


#
#       Main interface utilities
#

#
# is_stable_module : Module, SearchCfg -> IO StCheckResults
#
# Check all(*) function definitions in the module for stability.
# Relies on `is_stable_function`.
# (*) "all" can mean all or exported; cf. `SearchCfg`'s  `exported_names_only`.
#
is_stable_module(mod::Module, scfg :: SearchCfg = default_scfg) :: StCheckResults =
    is_stable_module_aux(mod, mod, Set{Module}(), scfg)

# bool-returning version of the above
is_stable_moduleb(mod::Module, scfg :: SearchCfg = default_scfg) :: Bool =
    convert(Bool, is_stable_module(mod, scfg))

# Auxiliary recursive implementation of `is_stable_module`. It gets two extra arguments:
# - root is the toplevel module that we process; we only recurse into modules that are enclosed in root
# - seen is a cache of modules we already processed; this prevents processing modules multiple times
is_stable_module_aux(mod::Module, root::Module, seen::Set{Module}, scfg::SearchCfg) :: StCheckResults = begin
    @debug "is_stable_module($mod)"
    push!(seen, mod)
    res = []
    ns = names(mod; all=!scfg.exported_names_only, imported=true)
    @debug "number of members in $mod: $(length(ns))"
    for sym in ns
        @debug "is_stable_module($mod): check symbol $sym"
        try
            evsym = getproperty(mod, sym)

            # recurse into submodules
            if evsym isa Module && !(evsym in seen) && is_module_nested(evsym, root)
                @debug "is_stable_module($mod): found module $sym"
                append!(res, is_stable_module_aux(evsym, root, seen, scfg))
                continue
            end

            # not interested in non-functional symbols
            isa(evsym, Function) || continue

            # not interested in special functions
            special_syms = [ :include, :eval ]
            (sym in special_syms) && continue

            append!(res,
                    map(m -> MethStCheck(m, is_stable_method(m, scfg)),
                        our_methods_of_function(evsym, mod)))
        catch e
            if e isa UndefVarError
                @warn "Module $mod exports symbol $sym but it's undefined"
                # showerror(stdout, e)
                # not our problem, so proceed as usual
            elseif e isa CantSplitMethod
                @warn "Can't process method with no canonical instance:\n$m"
                # cf. comment in `split_method`
            else
                throw(e)
            end
        end
    end
    return res
end

#
# is_stable_method : Method, SearchCfg -> StCheck
#
# Main interface utility: check if method is stable by enumerating
# all possible instantiations of its signature.
#
# If signature has Any at any place and (! scfg.types_db.use_types_db), i.e. we don't want
# to sample types, yeild AnyParam immediately.
# If signature has Vararg at any place, yeild VarargParam immediately.
#
is_stable_method(m::Method, scfg :: SearchCfg = default_scfg) :: StCheck = begin
    @debug "is_stable_method: $m"

    if scfg.typesDBcfg.use_types_db
        scfg.typesDBcfg.types_db === Nothing &&
            (scfg.typesDBcfg.types_db = typesDB())
    end

    # Slpit method into signature and the corresponding function object
    sm = split_method(m)
    sm isa GenericMethod && return sm
    (func, sig_types) = sm

    # Corner cases where we give up
    Any ∈ sig_types && ! scfg.typesDBcfg.use_types_db && return AnyParam(sig_types)
    any(t -> is_vararg(t), sig_types) && return VarargParam(sig_types)

    # Loop over all instantiations of the signature
    unst = Vector{Any}([])
    steps = 0
    skipexists = Set{SkippedUnionAlls}([])
    for ts in Channel(ch -> all_subtypes(sig_types, scfg, ch))
        @debug "[ is_stable_method ] loop" steps "$ts"

        # case over special cases
        if ts == "done"
            break
        end
        if ts isa OutOfFuel
            return ts
        end
        if ts isa SkippedUnionAlls
            push!(skipexists, ts)
            continue
        end

        # the actual stability check
        try
            if ! is_stable_call(func, ts)
                push!(unst, ts)
            end
        catch e
            return TcFail(ts, e)
        end

        # increment the counter, check fuel
        steps += 1
        if steps > scfg.fuel
            return OutOfFuel()
        end
    end

    return if isempty(unst)
        if isempty(skipexists)
            Stb(steps)
        else
            Par(steps, skipexists)
        end
    else
        Uns(steps, unst)
    end
end


end # module
