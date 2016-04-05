module ManualScraper
using CHM
import JSON

export scrape_gs200
export scrape_ena

"""
Function used to scrape information out of the Yokogawa GS200 manual.
The manual should be exported to plain text using Adobe Acrobat as other
choices seem to give poor results.
"""
function scrape_gs200(inpath::AbstractString, outpath::AbstractString)
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


function scrape_ena(inpath::AbstractString, outpath::AbstractString, mergewith="")

    cmd_r = r"Syntax<\/a>[A-Za-z0-9<>\"=\\\/\s:]+(?:<\/p>)?<p>(:[:A-Za-z\(\)\-\{\}\[\]\|0-9<>\\?]+)\s*\{?(?:&lt;)?((?:numeric)?(?:string)?(?:[\[\]A-Z0-9\|]+)?)"s

    docs = UTF8String[]
    commands = ASCIIString[]
    types = ASCIIString[]
    values = []

    f=CHM.open(inpath)
    try
        prefix = "/Programming/Command_Reference/"
        cats = ["ABORT", "CALCULATE", "CONTROL", "DISPLAY", "FORMAT", "HCOPY",
                "IEEE", "INIT", "LXI", "MEMORY", "OUTPUT", "PROGRAM", "SENSE",
                "SERVICE", "SOURCE", "STATUS", "SYSTEM", "TRIGGER"]
        for directory in cats
            files = CHM.readdir(f, prefix*directory)
            for file in files
                text = CHM.retrieve(f, file)
                entries = eachmatch(cmd_r, text)
                # length(entries) > 1 && info("Multiple commands in file: $file")
                for e in entries
                    push!(commands, e[1])
                    push!(types, cmdtostr(e[1]))
                    opt = e[2]
                    push!(values, opt)
                end
                # escape parentheses
                file = replace(file, "(", "%28")
                file = lowercase(replace(file, ")", "%29"))
                url = "http://ena.support.keysight.com/e5071c/manuals/webhelp/eng/"
                file = "- [External documentation]($url$file)"
                push!(docs, file)
            end
        end
    finally
        CHM.close(f)
    end

    insdict = Dict("module"=>"E5071C", "type"=>"InsE5071C", "make"=>"Keysight",
        "model"=>"E5071C", "writeterminator"=>"")
    template(zip(commands,values,types,docs),
        ["cmd","values","type","docs"], outpath,
        insdict=insdict, merge=true)
end


"""
`template(data, labels, outpath::AbstractString;
    insdict=emptyinsdict(),
    merge::Bool=true)`

Writes a JSON file given `data` and `labels`. For example:

```
data = [(":OUTPUT", "v::Bool", ""), (":OTHERCMD", "v::Symbol", "")]
labels = ["cmd", "values", "type"]
template(data, labels, "/my/path.json")
```

Optionally `insdict` can be provided for the `"instrument"` field of the resulting
JSON file, or if not provided a template is included to be filled in later.


If `merge` is true, then the fields of any JSON file at `outpath` are retained
and only previously undefined fields are added to the file in the corresponding
locations. The `cmd` field of a property dictionary is used to distinguish
different instrument properties. It is recommended to work on a duplicate of
the original file.
"""
function template(data, labels, outpath::AbstractString;
    insdict=emptyinsdict(),
    merge::Bool=true)

    if merge == true
        local r
        try
            r = JSON.parsefile(outpath)
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
        for x in data
            d = Dict(zip(labels, x))
            # Any identical entries, looking at cmd field?
            where = find(y->(y["cmd"]==d["cmd"]), proparr)
            # If not, add it
            if length(where) == 0
                push!(proparr, d)
            else
                # If more than one, warn and drop all but the first
                if length(where) > 1
                    warn("Duplicate `cmd` key: $(d["cmd"])")
                    deleteat!(proparr, where[2:end])
                end
                idx = where[1]
                olddict = proparr[idx]
                for k in keys(olddict)
                    d[k] = olddict[k]
                end
                proparr[idx] = d
            end
        end
    else
        # Just start from scratch
        proparr = []
        for x in data
            push!(proparr, Dict(zip(labels, x)))
        end
    end

    temp = Dict("instrument"=>insdict, "properties"=>proparr)

    # Write the dictionary to JSON
    open(outpath, "w") do f
        JSON.print(f, temp, 4)
    end
end

"""
`emptyinsdict()`

Returns a `Dict` intended to be used in an instrument JSON file for the "instrument"
dictionary. It has the expected keys and corresponding empty string values.
"""
emptyinsdict() = Dict("module" => "",
                      "type"   => "",
                      "make"   => "",
                      "model"  => "",
                      "writeterminator" => "")

"""
`cmdtostr(a::AbstractString)`

Returns a string based on a command, e.g. ":SOURCE:FUNCTION" becomes "SourceFunction".
"""
function cmdtostr(a::AbstractString)
    s = mapreduce(upperfirst, *, "", split(a,":"))
    replace(s, r"[^A-Za-z]", "")    # only text
end

"""
`upperfirst(a::AbstractString)`

Returns a string based on `a` with the first character only in uppercase.
"""
function upperfirst(a::AbstractString)
    length(a) == 0 && return a
    a = lowercase(a)
    string(uppercase(a[1]))*a[2:end]
end

end # module
