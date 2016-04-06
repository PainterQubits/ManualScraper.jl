module ManualScraper
using CHM
import JSON
import Base: contains, delete!, show

export CHMSource
export Parser
export @ena_str

export scrape_gs200
export scrape_ena

# Directories to pull from inside ENA's help file.
const ENA_DIRS = map(x->"/Programming/Command_Reference/"*x,
    ["ABORT", "CALCULATE", "CONTROL", "DISPLAY", "FORMAT", "HCOPY", #"IEEE",
    "INIT", "LXI", "MEMORY", "OUTPUT", "PROGRAM", "SENSE",
    "SERVICE", "SOURCE", "STATUS", "SYSTEM", "TRIGGER"])

# Files to pull from inside ENA's help file.
const ENA_FILTER = r".htm$"

# This is necessary due to inconsistencies in a few of the HTML files.
const ENA_INIT = [
    ("<br />", ""),
    ("<br>", ""),
    (" - ", ""),
    ("<span class=\"Times\">", ""),
    ("</span",""),
    ("[:STATe]{", " {"),
    ("SENSe([1]-160)", "SENSe{[1]-160}"),
    ("SENSe[1-160]", "SENSe{[1]-160}"),
    ("PORT([1]-4)", "PORT{[1]-4}")
]

# Logic: Start with Syntax, then have any typical HTML characters until a colon,
# which must be preceeded by a right angle bracket (>); following the colon, there
# must not be an HTML tag. Then a SCPI command follows...
const ENA_REGEX = r"Syntax[A-Za-z0-9<>\"=\\\/\s:_&#;]+(?<=>)(?P<cmd>:(?!<\/?\w+((\s+\w+(\s*=\s*(?:\".*?\"|'.*?'|[\^'\">\s]+))?)+\s*|\s*)\/?>)[:A-Za-z\(\)\-\{\}\[\]\|0-9\\?\n\r]+)\s*\{?(?:&lt;)?(?P<val>(?:numeric)?(?:string)?(?:[\[\]A-Z0-9\|]+)?)"s

const ENA_CMD_PASS1 = [
    # Strip junk: stray HTML tag snippets
    (r"<[A-Za-z0-9]+>?", s""),
    (r"[<>]+",           s""),

    # Strip newline and form feeds
    (r"[\r\n]+", ""),

    # Strip optional segments of command
    (r"\[:[:A-Za-z]+\]", s"")
]

const ENA_CMD_PASS2 = [
    # Strip lowercase parts
    (r"[a-z]+",                    ""),
    (r"(BPOR)\{[\[\]0-9\-\|]+\}",  s"\1bp"),
    (r"(:C)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(CALC)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(CHAN)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(FREQ)\{[\[\]0-9\-\|]+\}",  s"\1freq"),
    (r"(:G)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(INCL)\{[\[\]0-9\-\|]+\}",  s"\1incl"),
    (r"(:L)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(LOSS)\{[\[\]0-9\-\|]+\}",  s"\1loss"),
    (r"(MARK)\{[\[\]0-9\-\|]+\}",  s"\1m"),
    (r"(MULT)\{[\[\]0-9\-\|]+\}",  s"\1mult"),
    (r"(NETW)\{[\[\]0-9\-\|]+\}",  s"\1netw"),
    (r"(PAR)\{[\[\]0-9\-\|]+\}",   s"\1par"),
    (r"(PORT)\{[\[\]0-9\-\|]+\}",  s"\1port"),
    (r"(:R)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(SENS)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(SOUR)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(TRAC)\{[\[\]0-9\-\|]+\}",  s"\1tr"),
    (r"(WIND)\{[\[\]0-9\-\|]+\}",  s"\1ch")
]

const ENA_VAL_PASS1 = [
    ("ON|OFF|1|0", "v::Bool")
]

const ENA_VAL_PASS2 = []

immutable CHMSource
    path::AbstractString
    dirs::AbstractArray
    filter::Regex
end
show(io::IO, x::CHMSource) = print(io, "CHM source at: $(x.path)")

immutable Parser
    init::AbstractArray
    regex::Regex
    cmd1::AbstractArray
    cmd2::AbstractArray
    val1::AbstractArray
    val2::AbstractArray
end

const ENA_PARSER =
    Parser(ENA_INIT, ENA_REGEX, ENA_CMD_PASS1, ENA_CMD_PASS2,
        ENA_VAL_PASS1, ENA_VAL_PASS2)

macro ena_str(path)
    CHMSource(path, ENA_DIRS, ENA_FILTER)
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


function scrape_ena(src::CHMSource, p::Parser, outpath::AbstractString; merge::Bool=true,
    insdict=emptyinsdict())

    docs = UTF8String[]
    commands = ASCIIString[]
    types = ASCIIString[]
    values = []
    ids = Int64[]

    flag = true
    f=CHM.open(src.path)
    id=0
    try
        for directory in src.dirs
            files = CHM.readdir(f, directory)
            deleteat!(files, find(x->(match(src.filter, x) == nothing), files))
            for file in files
                id += 1
                text = CHM.retrieve(f, file)
                for x in p.init
                    text = replace(text, x...)
                end
                entries = eachmatch(p.regex, text)

                # length(entries) > 1 && info("Multiple commands in file: $file")
                i = 0
                for e in entries
                    rawcmd = e[:cmd]

                    for x in p.cmd1
                        rawcmd = replace(rawcmd, x...)
                    end
                    push!(types, cmdtostr(rawcmd))
                    for x in p.cmd2
                        rawcmd = replace(rawcmd, x...)
                    end
                    push!(commands, rawcmd)

                    if contains(rawcmd, ["{", "(", "["])
                        if contains(rawcmd, ["}", ")", "]"])
                            warn("Uncaught braces in $rawcmd")
                        else
                            warn("Suspect an incomplete command $rawcmd")
                            flag = diagnose(text)
                        end
                    else
                        info("Processed $rawcmd")
                    end

                    val = e[:val]
                    for x in p.val1
                        val = replace(val, x...)
                    end
                    for x in p.val2
                        val = replace(val, x...)
                    end
                    push!(values, val)

                    i+=1
                end

                i == 0 && warn("Could not parse command in file: $file")
                if flag && i == 0
                    flag = diagnose(text)
                end
                i == 0 && continue
                i > 1 && warn("Multiple matches in file: $file")

                # escape parentheses
                file = replace(file, "(", "%28")
                file = lowercase(replace(file, ")", "%29"))
                url = "http://ena.support.keysight.com/e5071c/manuals/webhelp/eng/"
                file = "- [External documentation]($url$file)"
                push!(docs, file)
                push!(ids, id)
            end
        end
    finally
        CHM.close(f)
    end

    length(commands) == length(values) == length(types) == length(docs) ||
        error("It looks like not all the fields may be in sync!")

    template(zip(commands,values,types,docs,ids),
        ["cmd","values","type","docs","id"], outpath,
        insdict=insdict, merge=merge)
end

"""
`delete!(inpath::AbstractString, itr)`

Delete entries from the property dictionary at key values given by `itr`.
"""
function delete!(path::AbstractString, itr)
    # splitext(inpath)[2] == ".json" || error("Not a JSON file.")
    r = JSON.parsefile(path)
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
function diagnose(text)
    println("Here are the pre-processed file contents:")
    println(text)
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
emptyinsdict() = Dict("module" => "",
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
