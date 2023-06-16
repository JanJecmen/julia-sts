using Dates
using Downloads
using Pkg

# Relies on this script being in $STS-PATH/scripts/timeline
STS_PATH = dirname(dirname(@__DIR__))

# Like @info but also print timestamp & flush immediately
macro info_extra(msg, rest...)
    result = quote
        Base.@info "[$(Dates.now(Dates.UTC))] " * string($(msg)) $(rest...)
        Base.flush(stdout)
        Base.flush(stderr)
    end
    esc(result)
end

ensure_dir(dir::AbstractString) = ispath(dir) || mkpath(dir)

dump(file::AbstractString, what::AbstractString) = begin
    @info_extra "Writing to `$file'"
    ensure_dir(dirname(file))
    open(file, "w") do f
        write(f, what)
    end
end

csv_quote(str::AbstractString) = "\"$(replace(str, '"' => "\"\"", '\n' => " "))\""
repo_to_filename(url::AbstractString) = "$(replace(url, ':' => "_", '/' => "_", '.' => "_"))"

read_strip(file::AbstractString) = strip(read(file, String))
read_lines(file::AbstractString) = split(read_strip(file), "\n")

pkg_info(pkg::AbstractString) = begin
    # NOT PRETTY but normally should Just Work™
    general = Pkg.Registry.reachable_registries()[1]
    uuid = findfirst(p -> p.name == pkg, general.pkgs)
    Pkg.Registry.registry_info(general[uuid])
end

pretty_duration(t) = begin
    if isnan(t) || isinf(t)
        return "??"
    end
    u = "s"
    units = ["m", "h", "d", "w"]
    facs = [60, 60, 24, 7]
    while !isempty(facs) && t > first(facs)
        u = popfirst!(units)
        t /= popfirst!(facs)
    end
    "$(round(t, digits = 2)) $u"
end

# Run cmd (runs in a new process) and capture stdout and stderr.
# On errors, reformats the exception and rethrows. Otherwise returns the concatenation of stdout and stderr
exec(cmd::Cmd) = begin
    out = IOBuffer()
    err = IOBuffer()
    try
        run(pipeline(cmd, stdout=out, stderr=err))
    catch e
        rethrow(ErrorException("Error executing $cmd: $e\nstdout:\n$(String(take!(out)))\nstderr:\n$(String(take!(err)))\n"))
    end
    strip(String(take!(out)) * String(take!(err)))
end

# Download the specified version of precompiled Julia to the specified location.
# Return the path to the given julia binary.
# If the version already exists there, reuse it.
get_julia_bin(ver::VersionNumber, dir::AbstractString) = begin
    bin = joinpath(dir, "julia-$(ver.major).$(ver.minor).$(ver.patch)/bin/julia")
    if !isfile(bin)
        url = "https://julialang-s3.julialang.org/bin/linux/x64/$(ver.major).$(ver.minor)/julia-$(ver.major).$(ver.minor).$(ver.patch)-linux-x86_64.tar.gz"
        cmd = `tar xzf - -C $(mkpath(dir))`
        Downloads.download(url, cmd)
    end
    bin
end
