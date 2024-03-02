module PkgStack

import Pkg
import Markdown: @md_str

function stack(envs)
    if isempty(envs)
        printstyled(" The current stack:\n"; bold=true)
        println.("  " .* LOAD_PATH)
    else
        for env in envs
            env ∉ LOAD_PATH && push!(LOAD_PATH, env)
        end
    end
end

@static if VERSION ≥ v"1.11-"
    const STACK_SPEC = Pkg.REPLMode.CommandSpec(; name="stack",
        api=stack,
        help=md"""
        stack envs...
    Stack another environment.
    """,
        description="Stack another environment",
        should_splat=false,
        arg_count=0 => Inf)
else
    const STACK_SPEC = Pkg.REPLMode.CommandSpec(; name="stack",
        api=stack,
        help=md"""
        stack envs...
    Stack another environment.
    """,
        description="Stack another environment",
        completions=Pkg.REPLMode.complete_activate,
        should_splat=false,
        arg_count=0 => Inf)
end

function unstack(envs)
    if isempty(envs)
        printstyled(" The current stack:\n"; bold=true)
        println.("  " .* LOAD_PATH)
    else
        deleteat!(LOAD_PATH, sort(filter(!isnothing, indexin(envs, LOAD_PATH))))
    end
end

const UNSTACK_SPEC = Pkg.REPLMode.CommandSpec(; name="unstack",
    api=unstack,
    help=md"""
      unstack envs...
  Unstack a previously stacked environment.
  """,
    description="Unstack an environment",
    completions=(_, partial, _, _) -> filter(p -> startswith(p, partial), LOAD_PATH),
    should_splat=false,
    arg_count=0 => Inf)

# Taken from https://github.com/JuliaLang/Pkg.jl/pull/3266
function autocompat(ctx=Pkg.Types.Context(); io=nothing)
    io = something(io, ctx.io)
    updated_deps = String[]
    for dep_list in (ctx.env.project.deps, ctx.env.project.weakdeps,
            ctx.env.project.extras), (dep, uuid) in dep_list
        compat_str = Pkg.Operations.get_compat_str(ctx.env.project, dep)
        isnothing(compat_str) || continue
        if uuid in ctx.env.manifest
            v = ctx.env.manifest[uuid].version
            v === nothing && (v = "<0.0.1, 1")
        else
            try
                pkg_versions = Pkg.Versions.VersionSpec([
                    Pkg.Operations.get_all_registered_versions(ctx, uuid)...
                ])
                if isempty(pkg_versions)
                    @warn "No versions of $(dep) are registered. Possibly a Standard Library package."
                    v = "<0.0.1, 1"
                else
                    latest_version = Pkg.Operations.get_latest_compatible_version(ctx,
                        uuid, pkg_versions)
                    v = latest_version
                end
            catch err
                @error "Encountered Error $(err) while processing $(dep). Skipping."
                continue
            end
        end
        Pkg.Operations.set_compat(ctx.env.project, dep, string(v)) ||
            Pkg.Types.pkgerror("invalid compat version specifier \"$(string(v))\"")
        push!(updated_deps, dep)
    end
    if isempty(updated_deps)
        Pkg.printpkgstyle(io, :Info, "no misssing compat entries found. No changes made.";
            color=Base.info_color())
    elseif length(updated_deps) == 1
        Pkg.printpkgstyle(io, :Info,
            "new entry set for $(only(updated_deps)) based on its current version";
            color=Base.info_color())
    else
        Pkg.printpkgstyle(io, :Info,
            "new entries set for $(join(updated_deps, ", ", " and ")) based on their current versions";
            color=Base.info_color())
    end
    Pkg.Types.write_env(ctx.env)
    return Pkg.Operations.print_compat(ctx; io)
end

const AUTOCOMPAT_SPEC = Pkg.REPLMode.CommandSpec(; name="autocompat",
    api=autocompat,
    help=md"""
      autocompat
  Set the compat entries for all packages in the current environment.
  """,
    description="Auto Compat Entries",
    arg_count=0 => 0)

function environments()
    envs = String[]
    for depot in Base.DEPOT_PATH
        envdir = joinpath(depot, "environments")
        isdir(envdir) || continue
        for env in readdir(envdir)
            if !isnothing(match(r"^__", env))
            elseif !isnothing(match(r"^v\d+\.\d+$", env))
            else
                push!(envs, '@' * env)
            end
        end
    end
    envs = Base.DEFAULT_LOAD_PATH ∪ LOAD_PATH ∪ envs
    for env in envs
        if env in LOAD_PATH
            print("  ", env)
        else
            printstyled("  ", env; color=:light_black)
            if env in Base.DEFAULT_LOAD_PATH
                printstyled(" (unloaded)"; color=:light_red)
            end
        end
        if env == "@"
            printstyled(" [current environment]"; color=:light_black)
        elseif env == "@v#.#"
            printstyled(" [global environment]"; color=:light_black)
        elseif env == "@stdlib"
            printstyled(" [standard library]"; color=:light_black)
        elseif env in LOAD_PATH
            printstyled(" (loaded)"; color=:green)
        end
        print('\n')
    end
end

const ENVS_SPEC = Pkg.REPLMode.CommandSpec(; name="environments",
    short_name="envs",
    api=environments,
    help=md"""
      environments|envs
  List all known named environments.
  """,
    description="List all known named environments",
    arg_count=0 => 0)

const SPECS = Dict("stack" => STACK_SPEC,
    "unstack" => UNSTACK_SPEC,
    "environments" => ENVS_SPEC,
    "envs" => ENVS_SPEC,
    "autocompat" => AUTOCOMPAT_SPEC)

function __init__()
    # add the commands to the repl
    activate = Pkg.REPLMode.SPECS["package"]["activate"]
    activate_modified = Pkg.REPLMode.CommandSpec(activate.canonical_name,
        "a", # Modified entry, short name
        activate.api,
        activate.should_splat,
        activate.argument_spec,
        activate.option_specs,
        activate.completions,
        activate.description,
        activate.help)
    SPECS["activate"] = activate_modified
    SPECS["a"] = activate_modified
    Pkg.REPLMode.SPECS["package"] = merge(Pkg.REPLMode.SPECS["package"], SPECS)
    # update the help with the new commands
    return copy!(Pkg.REPLMode.help.content, Pkg.REPLMode.gen_help().content)
end

end
