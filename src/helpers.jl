# Return a date-time string to be used as directory name for a benchmark
# Format based on: https://serverfault.com/a/370766
function benchmark_dirname()
    return joinpath("out", gethostname(), Dates.format(now(), "yyyy-mm-dd--HH-MM-SS"))
end

function load_standard_packages(project="@mainpkgs")
    core_pkgs = ["BenchmarkTools", "Infiltrator", "Revise", "Cthulhu"]
    # current_project = Pkg.project().path
    # Pkg.activate(project; shared=true)
    # installed_deps = [dep.name for dep in values(Pkg.dependencies()) if dep.is_direct_dep]
    # pkgs = core_pkgs[[pkg ∉ installed_deps for pkg in core_pkgs]]
    # !isempty(pkgs) && Pkg.add(pkgs)
    # Pkg.activate(current_project)
    Pkg.REPLMode.pkgstr("stack $(project)")
    for pkg in core_pkgs
        Core.eval(Main, :(using $(Symbol(pkg))))
    end
    return
end

function repl_ast_transforms(repl)
    if Base.isinteractive() && (local REPL = get(Base.loaded_modules,
        Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL"),
        nothing);
    REPL !== nothing)

        # Exit Julia with :q, restart with :r
        pushfirst!(REPL.repl_ast_transforms,
            function (ast::Union{Expr, Nothing})
                function toplevel_quotenode(ast, s)
                    return (Meta.isexpr(ast, :toplevel, 2) &&
                            ast.args[2] === QuoteNode(s)) ||
                           (Meta.isexpr(ast, :toplevel) &&
                            any(x -> toplevel_quotenode(x, s), ast.args))
                end
                if toplevel_quotenode(ast, :q)
                    exit()
                elseif toplevel_quotenode(ast, :r)
                    argv = Base.julia_cmd().exec
                    opts = Base.JLOptions()
                    if opts.project != C_NULL
                        push!(argv, "--project=$(unsafe_string(opts.project))")
                    end
                    if opts.nthreads != 0
                        push!(argv, "--threads=$(opts.nthreads)")
                    end
                    restart_julia(argv)
                end
                return ast
            end)

        # Automatically load tooling on demand:
        local tooling_dict = Dict{Symbol, Vector{Symbol}}(
            # dev tools:
            :BenchmarkTools => Symbol.(["@btime", "@benchmark"]),
            :Cthulhu => Symbol.([
                "@descend",
                "@descend_code_typed",
                "@descend_code_warntype",
            ]),
            :Debugger => Symbol.(["@enter", "@run"]),
            :Profile => Symbol.(["@profile"]),
            :ProfileView => Symbol.(["@profview"]),
            # everything else:
            :Dictionaries => Symbol.(["Dictionary", "dictionary"]),
            :LinearAlgebra => Symbol.([
                "dot",
                "norm",
                "normalize",
                "Symmetric",
                "Diagonal",
                "eigen",
                "eigvals",
                "eigvecs",
            ]),
            :StaticArrays => Symbol.(["SVector", "@SVector"]),
            :Statistics => Symbol.(["mean", "median", "std", "cor", "cov", "quantile"]),
            # :ReTest => Symbol.([
            #     "retest",
            #     "@test",
            #     "@testset",
            #     "@test_broken",
            #     "@test_deprecated",
            #     "@test_logs",
            #     "@test_nowarn",
            #     "@test_skip",
            #     "@test_throws",
            #     "@test_warn",
            # ])
            :Accessors => Symbol.(["@optic", "@set", "@modify"])
            # :DataManipulation => Symbol.(["flatmap", "filtermap", "mapview", "group", "groupview", "groupmap", "findonly", "filteronly", "filterfirst", "uniqueonly"]),
            # :DataPipes => Symbol.(["@p"]),
            # :DictArrays => Symbol.(["DictArray"]),
            # :FlexiJoins => Symbol.(["innerjoin", "leftjoin", "rightjoin", "outerjoin"]),
            # :StatsBase => Symbol.(["geomean", "harmmean", "percentile"]),
            # :StructArrays => Symbol.(["StructArray"]),
        )
        pushfirst!(REPL.repl_ast_transforms,
            function (ast::Union{Expr, Nothing})
                contains_calls(ast, ms::Vector{Symbol}, res=Symbol[]) = res
                function contains_calls(ast::Expr, ms::Vector{Symbol}, res=Symbol[])
                    if Meta.isexpr(ast, [:macrocall, :call]) && first(ast.args) ∈ ms
                        push!(res, first(ast.args))
                    end
                    for x in ast.args
                        contains_calls(x, ms, res)
                    end
                    return res
                end

                for (mod, callables) in tooling_dict
                    isdefined(Main, mod) && continue
                    calls = contains_calls(ast, callables)
                    filter!(c -> !isdefined(Main, c), calls)
                    isempty(calls) && continue
                    @info "Loading $mod for $(join(calls, ", ")) ..."
                    try
                        if isnothing(Base.identify_package(String(mod)))
                            for f in REPL.install_packages_hooks
                                Base.invokelatest(f, [mod]) && break
                            end
                        end
                        Core.eval(Main, :(using $mod))
                    catch err
                        @info "Failed to automatically install and load $mod" exception=err
                    end
                end
                return ast
            end)
    end
end

function replinit(repl)
    @eval Main begin
        using Revise
        using Infiltrator
        # import TerminalUserInterfaces as TUI
        # push!(Revise.dont_watch_pkgs, :Startup)
        # import REPL
        # REPL.GlobalOptions.auto_indent = false
        # REPL.LineEdit.options(s::REPL.LineEdit.PromptState) = REPL.GlobalOptions
    end
end

function ohmyreplinit(repl)
    @eval Main begin
        using OhMyREPL
        @eval Main.colorscheme!("OneDark")
    end
end

function gitdir(currdir)
    while true
        dirname(currdir) == currdir && return nothing
        isdir(joinpath(currdir, ".git")) && return currdir
        currdir = dirname(currdir)
    end
end

@static if Sys.iswindows()
    function restart_julia(argv)
        @info "Current Julia session paused. Spawning new Julia session..."
        run(Cmd(argv))
        return exit()
    end
else
    function restart_julia(argv)
        # @ccall execv(argv[1]::Cstring, argv::Ref{Cstring})::Cint
        return ccall(:execv, Cint, (Cstring, Ref{Cstring}), argv[1], argv)
    end
end
