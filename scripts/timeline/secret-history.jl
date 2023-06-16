project_name = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: project name")
repo_dir = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: repo directory")
out_dir = length(ARGS) > 0 ? popfirst!(ARGS) : error("Requires argument: output directory")

include("utils.jl")

using TOML

PROCESS = joinpath(STS_PATH, "scripts/timeline/secret-process.jl")

manifest = TOML.parsefile(joinpath(repo_dir, "Manifest.toml"))
julia_version = VersionNumber(get(manifest, "julia_version", ""))
julia = get_julia_bin(julia_version, "/tmp/_julias_")

@info_extra "Using julia binary `$julia'..."

# NOTE: `timeout -k $KILL_SEC $TIMEOUT_SEC`
exec(`$julia $PROCESS $project_name $repo_dir $out_dir`)
