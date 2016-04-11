module ManualScraper
using CHM
using DataStructures
import JSON
import Base: contains, delete!, show

export CHMSource
export Parser
export @ena_str

export scrape

immutable Parser
    init::AbstractArray
    getset::Regex
    cmd::Regex
    rettype::Regex
    cmd1::AbstractArray
    cmd2::AbstractArray
    val::AbstractArray
end

immutable CHMSource{T}
    path::AbstractString
    dirs::AbstractArray
    filter::Regex
    parser::Parser
end
show(io::IO, x::CHMSource) = print(io, "CHM source at: $(x.path)")

include("ENA.jl")

macro ena_str(path)
    CHMSource{ENA.SYM}(path, ENA.DIRS, ENA.FILTER, ENA.PARSER)
end

"""
`capture_names(r::Regex)`

Returns a ValueIterator of the capture group names for a given Regex.
Test to see if a name is there via: `"abc" in capture_names(r)`
"""
function capture_names(r::Regex)
    values(Base.PCRE.capture_names(r.regex))
end

"""
Function used to scrape information out of the Yokogawa GS200 manual.
The manual should be exported to plain text using Adobe Acrobat as other
choices seem to give poor results.
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


function scrape(src::CHMSource, outpath::AbstractString; merge::Bool=true,
    insdict=emptyinsdict())

    cmds = []
    types = []
    setargs = []
    getargs = []
    rettypes = []
    docs = UTF8String[]
    ids = Int64[]

    flag = true
    f=CHM.open(src.path)
    id=1
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

                # Parse for get / set capability.
                _get, _set = cangetset(src, text)
                if length(_get) == 0 || length(_set) == 0
                    flag && (flag = diagnose(text, "Could not determine read/write capability."))
                    continue
                end
                println(_get, _set)

                _cmds, _types, _args = commands(src, text)
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
                            warn("Uncaught braces in $cmd")
                        else
                            flag && (flag = diagnose(text, "Suspect an incomplete command $cmd"))
                            flag2 = true
                        end
                    end
                end
                flag2 && continue
                println(_cmds,_types,_args)

                _rettypes = rettype(src, text)
                len = length(_rettypes)
                if len == 0 && reduce(|, _get)
                    flag && (flag = diagnose(text, "Could not parse return types in file: $file"))
                    continue
                end
                println(_rettypes)

                _docs = doc(src, file, text)
                len = length(_docs)
                if len == 0
                    flag && (flag = diagnose(text, "Could not parse for documentation in file: $file"))
                    continue
                end

                _getargs, _setargs, _ids =
                    finishfile!(src, _set, _get, _cmds, _types, _args, _rettypes, _docs, id)
                for (x,y) in [(cmds, _cmds), (types, _types), (getargs, _getargs),
                    (setargs, _setargs), (rettypes, _rettypes), (docs, _docs), (ids, _ids)]
                    for z in y
                        push!(x,z)
                    end
                end
            end
        end
    finally
        CHM.close(f)
    end

    # length(commands) == length(types) == length(docs) ||
        # error("It looks like not all the fields may be in sync!")

    # template(zip(commands,setargs,getargs,types,docs),
    #         ["cmd","setargs","getargs","type","docs"],
    #         ids, outpath, insdict=insdict, merge=merge)
end

function cangetset(src::CHMSource, text)
    p = src.parser
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

function commands(src::CHMSource, text)
    p = src.parser
    entries = eachmatch(p.cmd, text)

    cmds = ASCIIString[]
    types = ASCIIString[]
    args = []

    for e in entries
        rawcmd = e[1]
        for x in p.cmd1
            rawcmd = replace(rawcmd, x...)
        end
        push!(types, cmdtostr(rawcmd))

        for x in p.cmd2
            rawcmd = replace(rawcmd, x...)
        end
        push!(cmds, rawcmd)

        vals = e.captures[2:end]
        deleteat!(vals, find(x->x==nothing, vals))
        for x in p.val
            vals = map(val->replace(val, x...), vals)
        end
        push!(args, vals)
    end
    cmds, types, args
end

function doc(src::CHMSource{ENA.SYM}, file, text)
    d = replace(file, "(", "%28")
    d = lowercase(replace(d, ")", "%29"))
    url = "http://ena.support.keysight.com/e5071c/manuals/webhelp/eng/"
    ["- [External documentation]($url$d)"]
end

function rettype(src::CHMSource, text)
    p = src.parser
    entries = eachmatch(p.rettype, text)

    rettypes = []
    for e in entries
        t = e.captures[1:end]
        deleteat!(t, find(x->x==nothing, t))
        push!(rettypes, e)
    end
    rettypes
end

rettype(src::CHMSource{ENA.SYM}, text) = [nothing]

function finishfile!(src::CHMSource{ENA.SYM}, _set, _get, _cmds, _types, _args, _rettypes, _docs, id)

    getargs = []
    setargs = []
    set = _set[1]
    get = _get[1]
    !set && !get && warn("Neither read nor write in `finishfile!`.")

    if !set && get# read only
        for i in _args
            push!(getargs, i)
            push!(setargs, nothing)
        end
    elseif !get && set# write only
        for i in _args
            push!(setargs, i)
            push!(getargs, nothing)
        end
    else
        getinds = find(x->x[end]=='?', _cmds)
        setinds = find(x->x[end]!='?', _cmds)
        for i in setinds
            push!(setargs, _args[i])
            push!(getargs, _args[i+1])
        end
        deleteat!(_cmds, getinds)
        deleteat!(_types, getinds)
    end

    # Documentation goes on all the commands
    d = _docs[1]
    while length(_docs) < length(_cmds)
        push!(_docs, d)
    end

    ids = collect((1:length(_cmds))+(id-1))

    println(_cmds)
    println(_types)
    println(getargs)
    println(setargs)
    println(_docs)
    chomp(readline())

    getargs, setargs, ids

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

If `merge` is true, then the fields of any JSON file at `outpath` are retained
and only previously undefined fields are added to the file in the corresponding
locations. The `cmd` field of a property dictionary is used to distinguish
different instrument properties. It is recommended to work on a duplicate of
the original file.
"""
function template(data, labels, ids, outpath::AbstractString;
    insdict=emptyinsdict(),
    merge::Bool=true)

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
            propdict = r["properties"]
        else
            propdict = OrderedDict()
        end

        # Now process the new properties and merge with the old
        for (i,x) in enumerate(data)
            d = OrderedDict(zip(labels, x))
            if !haskey(propdict, ids[i])
                propdict[ids[i]] = d
            else
                olddict = propdict[ids[i]]
                for k in keys(olddict)
                    d[k] = olddict[k]
                end
                propdict[ids[i]] = d
            end
        end
    else
        # Just start from scratch
        propdict = OrderedDict()
        for (i,x) in enumerate(data)
            propdict[ids[i]] = OrderedDict(zip(labels, x))
        end
    end

    temp = OrderedDict("instrument"=>insdict, "properties"=>propdict)

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
    replace(s, r"[^A-Za-z]", "")    # only text
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
