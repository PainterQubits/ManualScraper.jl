module ManualScraper
using CHM
using DataStructures
import JSON
import Base: contains, delete!, show

export CHMSource
export Parser
export @ena_str
export @awg5k_str

export scrape

immutable Parser
    init::AbstractArray
    getset::Regex
    cmd::Regex
    rettype::Regex
    cmd1::AbstractArray
    cmd2::AbstractArray
    arg::Regex
    val::AbstractArray
end

immutable CHMSource{T}
    path::AbstractString
    dirs::AbstractArray
    filter::Regex
    parser::Parser
end
show(io::IO, x::CHMSource) = print(io, "CHM source at: $(x.path)")

# Modules describing how to parse each different .chm file.
include("ENA.jl")
include("AWG5K.jl")

"""
`@awg5k_str(path)`

String macro. Given a path to the Tektronix AWG5000 series' .chm file,
construct a `CHMSource` that contains information on how to parse the .chm file.

Usage: `src = awg5k"/path/to/file.chm"`

When entering a file path using this macro, do not escape spaces in the path.
"""
macro awg5k_str(path)
    CHMSource{AWG5K.SYM}(path, AWG5K.DIRS, AWG5K.FILTER, AWG5K.PARSER)
end

"""
`@ena_str(path)`

String macro. Given a path to the Keysight ENA's .chm file, construct a
`CHMSource` that contains information on how to parse the .chm file.

Usage: `src = ena"/path/to/file.chm"`

When entering a file path using this macro, do not escape spaces in the path.
"""
macro ena_str(path)
    CHMSource{ENA.SYM}(path, ENA.DIRS, ENA.FILTER, ENA.PARSER)
end

"""
`capture_names(r::Regex)`

Returns a ValueIterator of the capture group names for a given Regex.
Test to see if a name is there via: `"abc" in capture_names(r)`

Not really used in the code but I thought it was strange that it is not in Base.
"""
function capture_names(r::Regex)
    values(Base.PCRE.capture_names(r.regex))
end

"""
`scrape(inpath::AbstractString, outpath::AbstractString)`

Function used to scrape information out of the Yokogawa GS200 manual.
The manual should be exported to plain text using Adobe Acrobat as other
choices seem to give poor results.
Eventually this will be restructured to accommodate any plain text file.
"""
function scrape(inpath::AbstractString, outpath::AbstractString)
    f = open(inpath)
    str = readall(f)
    close(f)

    r = r"Function\s+([\w\d\s\(\)/,’'.]+)Syntax\s+(:[A-Za-z:\[\]/?]+)\s+((?:(?:[\[\]<>A-Za-z0-9\s]+\|)+[A-Za-z0-9\[\]]+)?(?:<character string>)?)"
    optional = r"\[:[A-Za-z]+\]"

    entries = eachmatch(r, str)

    docs     = UTF8String[]
    commands = ASCIIString[]
    types = ASCIIString[]
    values   = []

    # Initial parse pass.
    for e in entries
        # Get rid of extraneous newlines.
        push!(docs, replace(e[1], "\n", ""))
        # Strip optional parts of the commands and make everything uppercase.
        c = replace(e[2], optional, "")
        push!(types, cmdtostr(c))
        c = replace(c, r"[a-z]+", "")
        push!(commands, uppercase(c))
        opt = e[3]
        opt = replace(opt, "|", ",")
        opt = replace(opt, r"\s", "")
        opt = replace(opt, "<characterstring>", "s::ASCIIString")
        opt = replace(opt, "1,0,ON,OFF", "v::Bool")
        opt = replace(opt, "<voltage>,<current>", "v::Real")
        opt = replace(opt, "<voltage>", "v::Real")
        opt = replace(opt, "<current>", "v::Real")
        opt = replace(opt, "<time>", "v::Real")
        opt = replace(opt, "<integer>", "v::Integer")
        opt = replace(opt, r"[\[\]]", "")

        # opt = replace(opt, r"[a-z]+", "")
        push!(values, opt)
    end

    symbols  = Array{Dict}(length(values))

    v2 = copy(values)
    for (i,v) in enumerate(v2)
        a = parse(v)
        if isa(a, Symbol)
            # Just a single symbol... unexpected.
            error("Unexpected argument.")
        elseif isa(a, Expr)
            if a.head == :(::)
                # Just a single type
                symbols[i] = Dict()
            elseif a.head == :tuple
                if isa(a.args[1], Expr)
                    # Both values and symbols. Just keep the values.
                    values[i] = string(a.args[1])
                    symbols[i] = Dict()
                    # push!(values, "v::Symbol in symbols")
                    # s = map(string, a.args[2:end])
                    # push!(symbols, Dict(zip(map(upperfirst,s),map(x->replace(x,r"[a-z]+",""),s))))
                    # push!(commands, commands[i])
                    # push!(docs, docs[i])
                    # push!(types, types[i])
                else
                    # Only symbols
                    values[i] = "v::Symbol in symbols"
                    s = map(string, a.args[1:end])
                    symbols[i] = Dict(zip(map(upperfirst,s),map(x->replace(x,r"[a-z]+",""),s)))
                end
            end
        else
            # could be nothing
            symbols[i] = Dict()
        end
    end

    insdict = Dict("module"=>"GS200", "type"=>"InsGS200", "make"=>"Yokogawa",
        "model"=>"GS200", "writeterminator"=>"")
    template(zip(commands,values,symbols,types),
        ["cmd","values","symbols","type"], outpath, insdict=insdict, merge=true)
end

"""
`scrape(src::CHMSource, outpath::AbstractString; merge::Bool=true,
    insdict=emptyinsdict(), breakpoints=[])`

Given a `CHMSource` object named `src` and an `outpath`, scrape information out
of the CHM source into organized arrays, and pass that on to [`template`]({ref})
to assemble a JSON file.

Keyword arguments:

- `merge::Bool=true`: Default to attempting to merge with a previous JSON file
rather than overwriting. See the documentation for [`template`]({ref}) for
further details.
- `insdict=emptyinsdict()`: Default to writing an empty instrument dictionary.
- `breakpoints=[]`: If this array has any command strings (as they appear in
the processed JSON file) then we will pause at that command so the source file
can be examined.

"""
function scrape(src::CHMSource, outpath::AbstractString; merge::Bool=true,
    insdict=emptyinsdict(), breakpoints=[])

    cmds = []
    infixes = []
    types = []
    getargs = []
    setargs = []
    syms = []
    rettypes = []
    docs = UTF8String[]
    writeonly = []
    allfiles = (cmds, infixes, types, getargs, setargs, syms, docs, writeonly)

    flag = true
    f=CHM.open(src.path)
    try
        for directory in src.dirs
            files = CHM.readdir(f, directory)
            deleteat!(files, find(x->(match(src.filter, x) == nothing), files))
            for file in files
                text = CHM.retrieve(f, file)

                # Initial pass of text replacement to correct inconsistencies.
                for x in src.parser.init
                    text = replace(text, x...)
                end

                # Parse for get / set capability if desired
                _get, _set = cangetset(src, text)
                if src.parser.getset != r"" && (length(_get) == 0 || length(_set) == 0)
                    flag && (flag = diagnose(text, "Could not determine read/write capability."))
                    continue
                end

                # Get commands and list of arguments
                _cmds, _types, _args, _infixes = commands(src, text)
                len = length(_cmds)
                if len == 0
                    flag && (flag = diagnose(text, "Could not parse command in file: $file"))
                    continue
                elseif len > 2
                    info("$len matches in file: $file")
                end
                flag2 = false
                for cmd in _cmds
                    if contains(cmd, ["{", "(", "["])
                        if contains(cmd, ["}", ")", "]"])
                            flag && (flag = diagnose(text, "Uncaught braces in $cmd"))
                            flag2 = true
                        else
                            flag && (flag = diagnose(text, "Suspect an incomplete command $cmd"))
                            flag2 = true
                        end
                    end
                end
                flag2 && continue

                for cmd in _cmds
                    if findfirst(breakpoints, cmd) != 0
                        flag && (flag = diagnose(text, "Hit a breakpoint."))
                        continue
                    end
                end

                # Parse arguments and find symbols
                argdict = Dict()
                if src.parser.arg != r""
                    for h in eachmatch(src.parser.arg, text)
                        argdict[h[1]] = h[2]
                    end
                end
                _syms = args!(src, _args, argdict)
                println(argdict)

                # Parse for return type of get methods
                _rettypes = rettype(src, text)
                len = length(_rettypes)
                if len == 0 && reduce(|, _get)
                    flag && (flag = diagnose(text, "Could not parse return types in file: $file"))
                    continue
                end

                # Assemble documentation
                _docs = doc(src, file, text)
                len = length(_docs)
                if len == 0
                    flag && (flag = diagnose(text, "Could not parse for documentation in file: $file"))
                    continue
                end

                # Do a final pass for consistency of array lengths, etc.
                _getargs, _setargs, _writeonly = finishfile!(src,
                    _set, _get, _cmds, _infixes, _types, _args, _syms, _rettypes, _docs)

                # all equal lengths?
                valid = reduce(==, extrema(map(length, (_cmds, _types, _getargs, _setargs, _docs))))
                if !valid
                    warn("Could not process file: $file")
                    warn("cmds: $(length(_cmds)) types: $(length(_types)) get: $(length(_getargs)) set: $(length(_setargs)) docs: $(length(_docs))")
                    println(_cmds, _types, _getargs, _setargs, _docs)
                    continue
                end

                # Keep everything we've learned from this file
                thisfile = (_cmds, _infixes, _types, _getargs, _setargs, _syms, _docs, _writeonly)
                for (x,y) in zip(allfiles, thisfile)
                    for z in y
                        push!(x,z)
                    end
                end
                for x in _cmds
                    info("Processed command: $x")
                end

            end
        end
    finally
        CHM.close(f)
    end

    # Save to JSON template file
    template(zip(cmds,infixes,types,setargs,getargs,docs,writeonly),
            ["cmd","infixes","type","setargs","getargs","doc","writeonly"], syms,
            outpath, insdict=insdict, merge=merge)
end

"""
`cangetset(src::CHMSource, text)`

Parse text for get and set capability of commands in the file.
Called by [`scrape`]({ref}). This is not sufficiently general yet.
"""
function cangetset(src::CHMSource, text)
    p = src.parser

    if p.getset == r""
        return [],[]
    end

    entries = eachmatch(p.getset, text)

    getarray = Bool[]
    setarray = Bool[]
    for e in entries
        get = false
        set = false
        for i in 1:3
            ans = (e[i] == nothing ? "" : e[i])
            get |= (lowercase(ans) == "read" ? true : false)
            set |= (lowercase(ans) == "write" ? true : false)
        end
        push!(getarray, get)
        push!(setarray, set)
    end

    getarray, setarray
end

"""
`commands(src::CHMSource, text)`

Parse text for commands. Called by [`scrape`]({ref}).
"""
function commands(src::CHMSource, text)
    p = src.parser
    # entries = eachmatch(p.cmd, text)

    cmds = ASCIIString[]
    types = ASCIIString[]
    args = []
    syms = []
    infixes = []
    argdict = Dict()

    while (e = match(p.cmd, text)) != nothing
        rawcmd = e[1]

        # We obliterate matches in the text as we go.
        text = replace(text, ASCIIString(e.match), "")

        # First pass of command regex replacement
        for x in p.cmd1
            rawcmd = replace(rawcmd, x...)
        end

        # Make types from first pass results
        push!(types, cmdtostr(rawcmd))

        # Second pass of command regex replacement
        for x in p.cmd2
            rawcmd = replace(rawcmd, x...)
        end

        # Save command we discovered
        push!(cmds, rawcmd)

        # Get infixes from that command (look for lowercase strings)
        _infixes = []
        inf = eachmatch(r"[a-z]+", rawcmd)
        for g in inf
            push!(_infixes, g.match*"::Integer=1") # assume Integers, default 1
        end
        push!(infixes, _infixes)

        # Retain arguments
        vals = e.captures[2:end]
        deleteat!(vals, find(x->x==nothing, vals))
        push!(args, vals)
    end

    cmds, types, args, infixes
end

"""
`args!(src::CHMSource, args)`

`args`: array of arrays, one array entry for each command with multiple arguments.

Called by [`scrape`]({ref}).
"""
function args!(src::CHMSource, args, argdict)
    p = src.parser
    syms = []
    sregex = r"\|"

    # Initial pass of argument replacement
    for i in 1:length(args)
        args[i] = convert(Array{ASCIIString,1}, args[i])
        arr = args[i]
        for j in 1:length(arr)
            for (k,v) in argdict
                arr[j] = replace(arr[j], k, v)
            end
        end
    end
    if p.val != r""
        for i in 1:length(args)
            for x in p.val
                args[i] = map(val->replace(val, x...), args[i])
            end
        end
    end

    for i in 1:length(args)
        s = OrderedDict()

        # Separate entries which are still connected by commas
        args[i] = mapreduce(x->split(x,","), vcat, UTF8String[], args[i])

        arr = args[i]
        for j in 1:length(arr)
            # Make argument names unique
            arr[j] = replace(arr[j], "v::", "v$j::")

            # Replace symbols with appropriate arguments
            if ismatch(sregex, arr[j])
                vs = split(arr[j], "|")
                ks = map(upperfirst, vs)
                vs = map(x->replace(x,r"[a-z]",""), vs)
                arr[j] = "v$j::Symbol in s$j"
                s["s$j"] = OrderedDict(zip(ks,vs))
            end
        end

        push!(syms, s)
    end
    syms
end

function doc(src::CHMSource{ENA.SYM}, file, text)
    d = replace(file, "(", "%28")
    d = lowercase(replace(d, ")", "%29"))
    url = "http://ena.support.keysight.com/e5071c/manuals/webhelp/eng"
    ["- [External documentation]($url$d)"]
end

function doc(src::CHMSource{AWG5K.SYM}, file, text)
    [""]
end


function rettype(src::CHMSource, text)
    p = src.parser
    if p.rettype == r""
        return [nothing]
    end

    entries = eachmatch(p.rettype, text)

    rettypes = []
    for e in entries
        t = e.captures[1:end]
        deleteat!(t, find(x->x==nothing, t))
        push!(rettypes, e)
    end
    rettypes
end

function finishfile!(src::CHMSource{ENA.SYM},
        _set, _get, _cmds, _infixes, _types, _args, _syms, _rettypes, _docs)

    getargs = []
    setargs = []
    writeonly = Bool[]
    set = _set[1]
    get = _get[1]
    !set && !get && warn("Neither read nor write in `finishfile!`.")

    # println(_cmds)
    # println(_types)
    # println(_args)
    # println(_syms)
    # println(_docs)
    # chomp(readline())

    if !set && get# read only
        for i in _args
            push!(getargs, i)
            push!(setargs, [])
            push!(writeonly, false)
        end
    elseif !get && set# write only
        for i in _args
            push!(setargs, i)
            push!(getargs, [])
            push!(writeonly, true)
        end
    else
        # only retain the write commands
        getinds = find(x->x[end]=='?', _cmds)
        setinds = find(x->x[end]!='?', _cmds)
        deleteat!(_cmds, getinds)
        deleteat!(_types, getinds)
        deleteat!(_syms, getinds)
        deleteat!(_infixes, getinds)

        for i in setinds
            length(setargs) < length(_cmds)   && push!(setargs, _args[i])
            length(writeonly) < length(_cmds) && push!(writeonly, false)
        end

        for i in getinds
            length(getargs) < length(_cmds) && push!(getargs, _args[i])
        end
    end

    # Documentation goes on all the commands
    d = _docs[1]
    while length(_docs) < length(_cmds)
        push!(_docs, d)
    end

    getargs, setargs, writeonly

end

function finishfile!(src::CHMSource{AWG5K.SYM},
        _set, _get, _cmds, _infixes, _types, _args, _syms, _rettypes, _docs)

    getargs = []
    setargs = []
    writeonly = Bool[]

    println(_cmds)
    println(_types)
    println(_args)
    println(_syms)
    println(_docs)
    chomp(readline())

    if length(_cmds) == 1
        if _cmds[1][end]=='?'
            (get = true; set = false)
        else
            (get = false; set = true)
        end
    else
        get = true; set = true;
    end

    if !set && get# read only
        for i in _args
            push!(getargs, i)
            push!(setargs, [])
            push!(writeonly, false)
        end
    elseif !get && set# write only
        for i in _args
            push!(setargs, i)
            push!(getargs, [])
            push!(writeonly, true)
        end
    else
        getinds = find(x->x[end]=='?', _cmds)
        setinds = find(x->x[end]!='?', _cmds)
        deleteat!(_cmds, getinds)
        deleteat!(_types, getinds)
        deleteat!(_syms, getinds)
        deleteat!(_infixes, getinds)

        for i in setinds
            length(setargs) < length(_cmds)   && push!(setargs, _args[i])
            length(writeonly) < length(_cmds) && push!(writeonly, false)
        end

        for i in getinds
            length(getargs) < length(_cmds) && push!(getargs, _args[i])
        end
    end

    d = _docs[1]
    while length(_docs) < length(_cmds)
        push!(_docs, d)
    end
    while length(_docs) > length(_cmds)
        d = pop!(_docs)
        warn("Dropping documentation: $d")
    end

    for x in _cmds
        info("Processed command: $x")
    end

    getargs, setargs, writeonly
end

"""
`delete!(inpath::AbstractString, itr)`

Delete entries from the property dictionary at key values given by `itr`.
"""
function delete!(path::AbstractString, itr)
    # splitext(inpath)[2] == ".json" || error("Not a JSON file.")
    r = JSON.parsefile(path, dicttype=OrderedDict)
    d = r["properties"]
    for i in itr
        if haskey(d, i)
            delete(d, i)
        end
    end
    r["properties"] = d
    open(path, "w") do f
        JSON.print(f, r, 4)
    end
end

"""
`allproperties(path::AbstractString, key::AbstractString)`

Return all values for a given `key` from instrument property dictionaries in a
JSON file at `path`.
"""
function allproperties(path::AbstractString, key::AbstractString)
    r = JSON.parsefile(path, dicttype=OrderedDict)
    d = r["properties"]
    cmds = ASCIIString[]
    for (k,v) in d
        push!(cmds, v[key])
    end
    cmds
end

"""
`template(data, labels, ids, outpath::AbstractString;
    insdict=emptyinsdict(),
    merge::Bool=true)`

Writes a JSON file given `data` and `labels`. For example:

```
data = [(":OUTPUT", "v::Bool", ""), (":OTHERCMD", "v::Symbol", "")]
labels = ["cmd", "values", "type"]
template(data, labels, 1:2, "/my/path.json")
```

Optionally `insdict` can be provided for the `"instrument"` field of the resulting
JSON file, or if not provided a template is included to be filled in later.

If `merge` is true, then the "type" and symbol fields of a JSON file at `outpath`
are retained for a given `cmd`. The `cmd` field of a property dictionary is used
to distinguish different instrument properties. The user is prompted to advise
how to proceed if a new command is found that wasn't at `outpath`, and also
if multiple entries are found with the same `cmd` field. It is recommended to
work on a duplicate of the original file.
"""
function template(data, labels, syms, outpath::AbstractString;
    insdict=emptyinsdict(),
    merge::Bool=true)

    keepall = false
    if merge == true
        local r
        try
            r = JSON.parsefile(outpath, dicttype=OrderedDict)
        catch e
            warn("No file found at `outpath` to merge with. Writing a new template.")
            return template(data, labels, outpath, insdict=insdict, merge=false)
        end

        # Keep all of the old instrument key/value pairs.
        if haskey(r, "instrument")
            oldid = r["instrument"]
            for k in keys(oldid)
                insdict[k] = oldid[k]
            end
        end

        # As a starting point go with the old properties array.
        if haskey(r, "properties")
            proparr = r["properties"]
        else
            proparr = []
        end

        # Now process the new properties and merge with the old
        for (i,x) in enumerate(data)
            d = OrderedDict(zip(labels, x))
            for (k,v) in syms[i]
                d[k] = v
            end

            ind = find(y->y["cmd"]==d["cmd"], proparr)
            if length(ind) == 0
                if keepall
                    push!(proparr, d)
                else
                    # Ask if we should add this command.
                    warn("""Command not found in old file: $(d["cmd"])""")
                    println("How do you want to proceed? [a=abort, i=ignore, k=keepall, anything else to keep it]")
                    response = chomp(readline())
                    if response == "a" || response == "abort"
                        error("Aborted!")
                    end
                    if response == "i" || response == "ignore"
                    elseif response == "k" || response == "keepall"
                        keepall = true
                        push!(proparr, d)
                    else
                        push!(proparr, d)
                    end
                end
            else
                if length(ind) > 1
                    warn("""Multiple entries with same command: $(d["cmd"])""")
                    println("How do you want to proceed? [a=abort, anything else to expunge all but first entry]")
                    response = chomp(readline())
                    if response == "a" || response == "abort"
                        error("Aborted!")
                    end
                    deleteat!(proparr, ind[2:end])
                end

                olddict = proparr[ind[1]]

                # Retain old types
                if haskey(olddict, "type")
                    d["type"] = olddict["type"]
                end

                # Retain old symbols
                k1 = collect(keys(olddict))
                symdicts = find(x->ismatch(r"s[0-9]+", x), k1)
                for i in symdicts
                    d[k1[i]] = olddict[k1[i]]
                end

                # Everything else, we take from the current parse pass
                proparr[ind[1]] = d
            end
        end
    else
        # Just start from scratch
        proparr = []
        for (i,x) in enumerate(data)
            d = OrderedDict(zip(labels, x))
            for (k,v) in syms[i]
                d[k] = v
            end
            push!(proparr, d)
        end

        # Now look for duplicate cmds
        for (i,d) in enumerate(proparr)
            ind = find(y->y["cmd"]==d["cmd"], proparr)
            if length(ind) > 1
                warn("""Multiple entries with same command: $(d["cmd"]). Expunging all but first.""")
                deleteat!(proparr, ind[2:end])
            end
        end

    end

    temp = OrderedDict("instrument"=>insdict, "properties"=>proparr)

    # Write the dictionary to JSON
    open(outpath, "w") do f
        JSON.print(f, temp, 4)
    end
end

# # # ### Utility functions ### # # #

"""
`cmdtostr(a::AbstractString)`

Returns a string based on a command, e.g. ":SOURCE:FUNCTION" becomes "SourceFunction".
"""
function cmdtostr(a::AbstractString)
    s = mapreduce(upperfirst, *, "", split(a,":"))
    s = replace(s, r"(\[|\{)[A-Za-z0-9\|\-\[\]]+(\}|\])", "")    # only text
    replace(s, "?", "")
end

"""
`diagnose(text)`

Sets up an interactive prompt for diagnosing issues with files that are not
correctly parsed by the given regular expressions. This is called e.g. whenever
a .chm file is scraped, not directly by the user.
"""
function diagnose(text, message)
    println(text)
    warn(message)
    println("Above are the pre-processed file contents.")
    println("\nHow do you want to proceed? [i=ignoreall, a=abort, anything else to continue]")
    response = chomp(readline())
    if response == "a" || response == "abort"
        error("Aborted!")
    elseif response == "i" || replace(response," ","") == "ignoreall"
        return false
    else
        return true
    end
end

"""
`emptyinsdict()`

Returns a `Dict` intended to be used in an instrument JSON file for the "instrument"
dictionary. It has the expected keys and corresponding empty string values.
"""
emptyinsdict() = OrderedDict("module" => "",
                             "type"   => "",
                             "make"   => "",
                             "model"  => "",
                             "writeterminator" => "")

"""
`upperfirst(a::AbstractString)`

Returns a string based on `a` with the first character only in uppercase.
"""
function upperfirst(a::AbstractString)
    length(a) == 0 && return a
    a = lowercase(a)
    string(uppercase(a[1]))*a[2:end]
end

"""
`contains(haystack::AbstractString, needles::AbstractArray)`

Implementation of `contains` for multiple needles...
"""
function contains(string::AbstractString, strings::AbstractArray)
    mapreduce(x->contains(string,x), |, false, strings)
end

end # module
