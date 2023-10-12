module Startup

using Pkg, PrecompileTools, Dates, PkgTemplates, ArgParse, MacroTools
using Revise, OhMyREPL

include("macros.jl")
include("pkg.jl")
include("helpers.jl")

function __init__()
    atreplinit() do repl
        replinit(repl)
        ohmyreplinit(repl)
        repl_ast_transforms(repl)
        return
    end
end

@setup_workload begin
    function _activate()
        cd(dirname(dirname(pathof(Startup))))
        Pkg.activate("."; io=Base.devnull)
        return __init__()
    end
    @compile_workload begin
        using Pkg: Pkg as Pkg
        using Revise
        using OhMyREPL: JLFzf
        using OhMyREPL.JLFzf: fzf_jll
        using OhMyREPL.BracketInserter.Pkg.API.Operations.Registry: FileWatching
        using Infiltrator
        using BenchmarkTools
        push!(Revise.dont_watch_pkgs, :Startup)
    end
end

export @autoinfiltrate, @subprocess

end
