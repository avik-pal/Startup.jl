"""
    @subprocess ex
    @subprocess ex wait=false

Execute `ex` in a subprocess that mimics the current process configuration.
Returns the constructed `Process`.
See [`Base.julia_cmd`](@ref) for the subprocess configuration forwarding that is used.

```julia-repl
julia> println("hello from $(Base.getpid())")
hello from 35640

julia> @subprocess println("hello from $(Base.getpid())")
hello from 43056
Process(`/home/user/julia/julia -Cnative -J/home/user/julia/usr/lib/julia/sys.dylib -g1 -e 'println("hello from $(Base.getpid())")'`, ProcessExited(0))
```
"""
macro subprocess(ex, wait=true)
    quote
        local ex_str = $(esc(sprint(Base.show_unquoted, ex)))
        run(`$(Base.julia_cmd()) -e "$(ex_str)"`; wait=$(wait))
    end
end

# Silent @show version (omit the right-hand side)
# https://github.com/mroavi/dotfiles/blob/2d1f6d05515153b3616f5384faf85e2d406a6e26/julia/.julia/config/startup.jl#L147
macro sshow(exs...)
    blk = Expr(:block)
    for ex in exs
        push!(blk.args, :(println(repr(begin
            local value = $(esc(ex))
        end))))
    end
    isempty(exs) || push!(blk.args, :value)
    return blk
end

macro autoinfiltrate(cond=true)
    pkgid = Base.PkgId(Base.UUID("5903a43b-9cc3-4c30-8d17-598619ec4e9b"), "Infiltrator")
    if !haskey(Base.loaded_modules, pkgid)
        try
            Base.eval(Main, :(using Infiltrator))
        catch err
            @error "Cannot load Infiltrator.jl. Make sure it is included in your environment stack."
        end
    end
    i = get(Base.loaded_modules, pkgid, nothing)
    lnn = LineNumberNode(__source__.line, __source__.file)

    if i === nothing
        return Expr(:macrocall, Symbol("@warn"), lnn, "Could not load Infiltrator.")
    end

    return Expr(:macrocall, Expr(:., i, QuoteNode(Symbol("@infiltrate"))), lnn, esc(cond))
end
