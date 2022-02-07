# include("AModule.jl")
# to demo how @stable macro works

using StabilityCheck

@stable h(x::Int)=1+x

@stable f() = g()

@stable g() = if rand()>0.5; 1; else "" end

check_all_stable()
