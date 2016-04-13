module ENA
using ManualScraper: Parser

const SYM = :ena

# Directories to pull from inside ENA's help file.
const DIRS = map(x->"/Programming/Command_Reference/"*x,
    ["ABORT", "CALCULATE", "CONTROL", "DISPLAY", "FORMAT", "HCOPY", #"IEEE",
    "INIT", "LXI", "MEMORY", "OUTPUT", "PROGRAM", "SENSE",
    "SERVICE", "SOURCE", "STATUS", "SYSTEM", "TRIGGER"])

# Files to pull from inside ENA's help file.
const FILTER = r".htm$"

# This is necessary due to inconsistencies in the HTML files.
const INIT = [

    # Remove control chars and extended chars except CR and LF.
    (r"[^\x20-\x7e\x0a\x0d]", ""),

    # Remove certain tags that randomly interrupt command syntax
    ("<br />", ""),
    ("<br>", ""),
    ("</a>",""),
    (r"<a[\sA-Za-z0-9_=\"]+>",""),
    (r"<span[\sA-Za-z0-9_\-#;,:=\"]+>", ""),
    (r"<font[\sA-Za-z0-9_\-#;,:=\"]+>", ""),
    ("</font>",""),
    ("</span>",""),

    # Remove class attributes
    (r" style=\"[A-Za-z0-9\-\s;:]+\"", ""),
    (r" class=\"[a-z0-9]+\"", ""),

    # Contract extra white space
    (" - ", "-"),
    ("&#160;", ""),
    (r"\s+\|", "|"),
    (r"\|\s+", "|"),

    # Fix some syntactical typos. There are a lot, thanks Keysight
    (r"COLLect\s+:ITERation", "COLLect:ITERation"),
    ("CALCulate{[1]-160}:TRACe(Tr):", "CALCulate{[1]-160}:TRACe{[1]-16}:"),
    (":CALCulate{[1]-160]", ":CALCulate{[1]-160}"),
    (" [:", "[:"),
    (" :",":"),
    (" ?", "?"),
    ("Aux1", "AUX1"),
    ("E/span&gt;", "..."),
    (r": ([A-Z]+)", s":\1"),
    (r"([A-Z]).VOLTage.", s"\1:VOLTage"),
    ("STORe.STSource", "STORe:STSource"),
    ("DC.RANGe", "DC:RANGe"),
    ("[:STATe]{", " {"),
    ("SENSe([1]-160)", "SENSe{[1]-160}"),
    ("SENSe[1-160]", "SENSe{[1]-160}"),
    ("PORT([1]-4)", "PORT{[1]-4}"),
    ("SOLT4 1,2,3,4</p>","SOLT4 &lt;numeric 1&gt;,&lt;numeric 2&gt;,&lt;numeric 3&gt;,&lt;numeric 4&gt;</p>"),
    ("RECeiver([1]-4)", "RECeiver{[1]-4}"),
    (":[EXTernal]", "[:EXTernal]"),
    ("CALCulate[1-160]", "CALCulate{[1]-160}"),
    (r"STARt\|\s+STOP", "STARt|STOP"),
    (r"R<\/p>\s+<p>1\|R2\|R3", "R1|R2|R3"),
    (r"(EXTernal.SLOPe<\/h1>[\s]+<h2>Object type<\/h2>[\s]+<p>Property)(</p>)", s"\1 (Read-Write)\2"),
    (r"(REPort\.DATA[<>\/A-Za-z0-9\s=\"\-:';.&#]+<p>Property)(<\/p>)", s"\1 (Read-Only)\2"),
    (r"(&lt;string 1&gt;)(&lt;\^END&gt;)", s"\1&lt;newline&gt;\2"),
    (r"&lt;1/0&gt;(&lt;\^END&gt;)", s"{1|0}&lt;newline&gt;\1"),
    ("{1/0}","{1|0}"),
    (r"&lt;string \(&quot;n, m, l\.\.\.&quot;\)&gt;\s*", "&lt;string&gt;</p>\r\n<p>"),
    (r"(&lt;string&gt;)\s+(:CALCulate\{\[1\]\-160\})", s"\1</p>\r\n<p>\2"),
    # ("&lt;numeric&gt;", "{numeric}"),
    # ("&lt;value&gt;", "{value}"),

    # Make parsing more convenient in a few special cases
    ("Data Array", "DataArray"),
    (r";([A-Za-z]+)\s+([0-9])&", s";\1\2&"),
    ("&quot;Sx1y1, Sx2y2, ... , Sxnxn&quot;", "&lt;string&gt;"),
    ("&lt;+ or -&gt;&lt;value of ", "&lt;"),
    (r"SCPI commands:<\/p>[<>a-zA-Z0-9.;\"\{\}\-?:=\s\/]+<ul>", "SCPI commands:</p><ul>"), # in :FORMAT:DATA
    (r"(CATalog\?<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Read-Only)\2"),
    (r"(:NAME<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Read-Write)\2"),
    (r"(STATe<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Read-Write)\2"),
    (r"(TRANsfer<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Read-Write)\2"),
    (r"(LOAD:PROGram<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Write-Only)\2"),
    (r"(STORe:PROGram<\/h1>\s+<p>)No equivalent COM Commands(<\/p>)", s"\1Property (Write-Only)\2"),

    # (r"{numeric 1},,{numeric NOP.2.\(number\s+of specified traces\)}", "{array}"),
    # ("&lt;numeric1&gt;,,&lt;numeric N&gt;&lt;^END&gt;", "{array}&lt;newline&gt;&lt;^END&gt;"),
    # ("{numeric 1},,{numeric NOP?2}", "{array}"),
    # ("&lt;numeric1&gt;,,&lt;numeric NOP?2&gt;", "{array}&lt;newline&gt;"),
    # ("&lt;numeric1&gt;,,&lt;numeric N*2&gt;", "{array}&lt;newline&gt;"),
    # (r"\{numeric 1\},\s*\.\.\.\s*,\{numeric 1\+\(N\*5\)\}","{array}"),
    # ("{numeric 1},,{numeric 1+(Nx4)}","{array}"),
    # ("{numeric 1},,{numeric 1+Nx3}","{array}"),
    # ("{numeric 1},{numeric 2},...,{numeric N}","{array}"),
    # ("{numeric 1}, ...,{numeric NOP*2}", "{array}"),
    # ("{numeric 1},...,{numeric NOP}","{array}"),
    # ("{value 1},...,{value NOP}","{array}"),
    # ("R1|R1|R2|R3}", ""),

]

# Determine if the commands are for read/write, read, or write
const GETSET_REGEX = r"((?:property)|(?:method)) \((?:(read|write|only)?[\-\s\/]*(read|write|only)?)\s?\)"i

# How to parse the ENA's HTML files for commands and args.
# l1. Preceding line must end with >\r\n
# l2. Start with <p>: then follow with any # of chars that may be found in a SCPI command
# l3. (variable whitespace)
# l4. One of two things follows:
#   1) Some text between &lt; and &rt; or
#   2) Some text in curly braces
# l5. optionally have a comma and/or whitespace, then repeat to l4
# l6. optionally have whitespace, terminate with a </p> tag and optional whitespace.
# const CMD_REGEX = r"(?<=>\r\n)(?:<p>(:[:A-Za-z\(\)\-\{\}\[\]\|?0-9\\\n\r]+)\s*(?:(?:(&lt;[A-Z\(\)\s,a-z0-9]+&gt;)|\{([A-Za-z0-9\-\|]+)\}),*\s*)*\s*<\/p>\s*)"
const CMD_REGEX = r"(?<=>\r\n)(?:<p>(:[:A-Za-z\(\)\-\{\}\[\]\|?0-9\\\n\r]+)\s*((?:(?:(?:&lt;[A-Z\(\)\s,a-z0-9]+&gt;)|\{(?:[A-Za-z0-9\-\|]+)\}),*\s*)+)*\s*<\/p>\s*)"

const CMD_PASS1 = [
    # Strip junk: stray HTML tag snippets
    (r"<[A-Za-z0-9]+>?", s""),
    (r"[<>]+",           s""),

    # Strip newline and form feeds
    (r"[\r\n]+", ""),

    # Strip optional segments of command
    (r"\[:[:A-Za-z\|]+\]", s"")
]

const CMD_PASS2 = [
    # Strip lowercase parts
    (r"[a-z]+",                    ""),

    # Replace infixes. Could be automated...
    (r"(ADAP)\{[\[\]0-9\-\|]+\}",  s"\1pt"),
    (r"(ARR)\{[\[\]0-9\-\|]+\}",   s"\1vnum"),
    (r"(BPOR)\{[\[\]0-9\-\|]+\}",  s"\1bp"),
    (r"(:C)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(CALC)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(CHAN)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(CKIT)\{[\[\]0-9\-\|]+\}",  s"\1ckit"),
    (r"(COL)\{[\[\]0-9\-\|]+\}",   s"\1dnum"),
    (r"(DOUB)\{[\[\]0-9\-\|]+\}",  s"\1vnum"),
    (r"(FREQ)\{[\[\]0-9\-\|]+\}",  s"\1freq"),
    (r"(:G)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(GRAT)\{[\[\]0-9\-\|]+\}",  s"\1gnum"),
    (r"(INCL)\{[\[\]0-9\-\|]+\}",  s"\1incl"),
    (r"(INIT)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(:L)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(LIM)\{[\[\]0-9\-\|]+\}",   s"\1lnum"),
    (r"(LONG)\{[\[\]0-9\-\|]+\}",  s"\1vnum"),
    (r"(LOSS)\{[\[\]0-9\-\|]+\}",  s"\1loss"),
    (r"(MARK)\{[\[\]0-9\-\|]+\}",  s"\1m"),
    (r"(MULT)\{[\[\]0-9\-\|]+\}",  s"\1mult"),
    (r"(NETW)\{[\[\]0-9\-\|]+\}",  s"\1netw"),
    (r"(OUTP)\{[\[\]0-9\-\|]+\}",  s"\1num"),
    (r"(PAR)\{[\[\]0-9\-\|]+\}",   s"\1par"),
    (r"(PLOS)\{[\[\]0-9\-\|]+\}",  s"\1pt"),
    (r"(PORT)\{[\[\]0-9\-\|]+\}",  s"\1pt"),
    (r"(:R)\{[\[\]0-9\-\|]+\}",    s"\1el"),
    (r"(REC)\{[\[\]0-9\-\|]+\}",   s"\1pt"),
    (r"(SENS)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(STAN)\{[\[\]0-9\-\|]+\}",  s"\1std"),
    (r"(STR)\{[\[\]0-9\-\|]+\}",   s"\1vnum"),
    (r"(SOUR)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(TYPE)\{[\[\]0-9\-\|]+\}",  s"\1tr"),
    (r"(TRAC)\{[\[\]0-9\-\|]+\}",  s"\1tr"),
    (r"(WIND)\{[\[\]0-9\-\|]+\}",  s"\1ch"),
    (r"(VOLT)\{[\[\]0-9\-\|]+\}",  s"\1auxpt")
]

const ARG_REGEX = r""

const ARG_PASS = [
    (r"[\{\}\s]+", ""),
    ("ON|OFF|1|0", "v::Bool"),
    (r"&lt;numeric[0-9]?\(?[A-Za-z]*\)?&gt;", "v::Real"),
    (r"&lt;value[0-9]?\(?[A-Za-z]*\)?&gt;", "v::Real"),
    (r"&lt;string[0-9]?&gt;", "v::AbstractString"),
]

const RETTYPE_REGEX = r""
# const RETTYPE_REGEX = r"[Qq]uery [Rr]esponse<\/h[0-9]>\s+<p>(?:\{([A-Za-z0-9,_\-\?\|…\.\(\)\/\s]+)\},*\s*)*&lt;newline"

const PARSER = Parser(INIT, GETSET_REGEX, CMD_REGEX, RETTYPE_REGEX,
    CMD_PASS1, CMD_PASS2, ARG_REGEX, ARG_PASS)

end
