module AWG5K
using ManualScraper: Parser

const SYM = :awg5k

# Directories to pull from inside ENA's help file.
const DIRS = ["/"]

# Files to pull from inside ENA's help file.
const FILTER = r"(?<=\/)[0-9a-z\-\.]+.htm$"

# This is necessary due to inconsistencies in the HTML files.
const INIT = [

    # Remove control chars and extended chars except CR and LF.
    (r"[^\x20-\x7e\x0a\x0d]", ""),

    # Remove attributes from tags
    (r"<([A-Za-z0-9]+) [^>]+>", s"<\1>"),

    # Remove extraneous tags
    ("<font>", ""),
    ("</font>", ""),
    ("<h4>", ""),
    ("</h4>", ""),
    ("<blockquote>", ""),
    ("</blockquote>", ""),

    # Contract whitespace and detritus
    (r":\s+", ":"),
    (r"\s+:", ":"),
    (r"\s+\|", "|"),
    (r"\|\s+", "|"),
    (r"=\s+","="),
    (r"\s+=","="),
    (" [1|2|3|4]", ""),
    (r"<p>SLISt:SUBSequence:TSTamp\?<\/p>\s+<\/Syntax>", "</Syntax>"),

    # convenience
    ("[,&lt;StartIndex&gt;[,&lt;Size&gt;]]", ""),
    ("[,", ",["),
    ("msus", "string"),
    ("subseq_name", "string"),
]

# Determine if the commands are for read/write, read, or write
const GETSET_REGEX = r""    # cannot be determined in idiomatic way

# How to parse the AWG's HTML files for commands and args.
# l1. Preceding line must end with <Syntax>
# l2. Start with whitespace and <p>: then follow with anything but whitespace
# l3. optionally some arguments
# l4. end with </p>
# We will consume the lines as they are read to get multiple commands out
const CMD_REGEX = r"(?<=<Syntax>)(?:\s+<p>([^\s]+)(?: ([^<]+))?<\/p>)"

const CMD_PASS1 = [
    # Strip optional segments of command
    (r"\[SOURce\[([1n])\]\]", s":SOURce[\1]"),
    (r"\[:[:A-Za-z\|]+\]", s"")
]

const CMD_PASS2 = [

    # Save infixes
    (r"\[[a-z0-9\-\|]+\]", "[*]"),
    # but strip lowercase parts
    (r"[a-z]+", ""),

    # Replace infixes. Could be automated...
    (r"(MARK)\[\*\]", s"\1m"),
    (r"(SOUR)\[\*\]", s"\1ch"),
    (r"(DC)\[\*\]",   s"\1dc"),
    (r"(OUTP)\[\*\]", s"\1outp"),
    (r"(DOUT)\[\*\]", s"\1dout"),
    ("[:WIND[*]]",    ":WINDwind"),
    (r"(ELEM)\[\*\]", s"\1el"),
    (r"(WAV)\[\*\]",  s"\1wv"),

]

const ARG_REGEX = r"(?:&lt;)?([A-Za-z0-9_\s]+)(?:&gt;)?::=(?:&lt;|\{)([A-Za-z0-9_\|]+)(?:&gt;|\})"

const ARG_PASS = [
    (r"[\{\}]", ""),
    (r"&[lg]t;", ""),
    ("NR1", "v::Integer"),
    ("NRf", "v::Integer"),
    ("NR2", "v::Real"),
    ("NR3", "v::Real"),
    (r"\[?[Ss]tring\]?", "v::AbstractString"),
    (r"[Bb]oolean", "v::Bool"),
    (r"[Ll]ength", "v::Integer"),
]

const RETTYPE_REGEX = r""

const PARSER = Parser(INIT, GETSET_REGEX, CMD_REGEX, RETTYPE_REGEX,
    CMD_PASS1, CMD_PASS2, ARG_REGEX, ARG_PASS)

end
