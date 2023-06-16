# TODOs
# - what about julia patches - we use precompiled official julia?

project_name = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: project name")
repo_dir = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: repo directory")
out_dir = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: output directory")

include("utils.jl")

cd(out_dir)

using Pkg
Pkg.activate(".")

haskey(Pkg.project().dependencies, "StabilityCheck") || Pkg.develop(path=STS_PATH)
using StabilityCheck
# ENV["JULIA_DEBUG"] = StabilityCheck

Pkg.develop(path=repo_dir)
Pkg.build(project_name)
eval(Meta.parse("using $project_name"))
checkModule(eval(Meta.parse("$project_name")))
