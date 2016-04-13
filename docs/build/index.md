
<a id='ManualScraper.jl-1'></a>

# ManualScraper.jl


A package for scraping instrument manuals to assemble standardized templates of commands and documentation.


<a id='Installation-1'></a>

## Installation


  * Install package [`CHM.jl`](https://github.com/ajkeller34/CHM.jl).
  * `Pkg.clone("https://github.com/ajkeller34/ManualScraper.jl.git")`


<a id='Usage-1'></a>

## Usage


This package is not entirely automated; to do so would require some intelligent parsing that would be far more complicated. Think of this package as a repository for the code that generates the template files read by the [PainterQB](https://github.com/ajkeller34/PainterQB.jl) package.


1. Get a plain-text or HTML file to parse that describes the instrument commands. This may be the hardest part as often times only a PDF file is provided. If the instrument has an on-board Windows computer, it will likely have a .CHM file from which HTML can be retrieved using `CHM.jl`. If the instrument only has a PDF file, I've achieved the best results in extracting text using Adobe Acrobat. There are open-source packages to do this but the results are often worse, at least with limited tweaking.


1. Construct regular expressions to peel the required information out of the plain-text, HTML, etc. You will want to extract the commands, argument types, and possibly documentation (although be careful with copyright if sharing). For constructing the regular expressions, it is probably easiest to use an interactive website that shows the results of the regex search as you construct the expression. Just search for "regular expression tester" and look for one that supports PCRE regex.


1. Collect the information from the regex search into arrays. See existing examples for how to do this.


1. Use the [`ManualScraper.template`](index.md#ManualScraper.template) function to turn the collected information into the desired template file. It is capable of merging information from old versions of template files.


<a id='API-1'></a>

## API


<a id='Macros-1'></a>

### Macros

<a id='ManualScraper.@awg5k_str' href='#ManualScraper.@awg5k_str'>#</a>
**`ManualScraper.@awg5k_str`** &mdash; *Macro*.

---


`@awg5k_str(path)`

String macro. Given a path to the Tektronix AWG5000 series' .chm file, construct a `CHMSource` that contains information on how to parse the .chm file.

Usage: `src = awg5k"/path/to/file.chm"`

When entering a file path using this macro, do not escape spaces in the path.

<a id='ManualScraper.@ena_str' href='#ManualScraper.@ena_str'>#</a>
**`ManualScraper.@ena_str`** &mdash; *Macro*.

---


`@ena_str(path)`

String macro. Given a path to the Keysight ENA's .chm file, construct a `CHMSource` that contains information on how to parse the .chm file.

Usage: `src = ena"/path/to/file.chm"`

When entering a file path using this macro, do not escape spaces in the path.


<a id='Internal-1'></a>

### Internal

<a id='ManualScraper.cmdtostr' href='#ManualScraper.cmdtostr'>#</a>
**`ManualScraper.cmdtostr`** &mdash; *Function*.

---


`cmdtostr(a::AbstractString)`

Returns a string based on a command, e.g. ":SOURCE:FUNCTION" becomes "SourceFunction".

<a id='ManualScraper.diagnose' href='#ManualScraper.diagnose'>#</a>
**`ManualScraper.diagnose`** &mdash; *Function*.

---


`diagnose(text)`

Sets up an interactive prompt for diagnosing issues with files that are not correctly parsed by the given regular expressions. This is called e.g. whenever a .chm file is scraped, not directly by the user.

<a id='ManualScraper.emptyinsdict' href='#ManualScraper.emptyinsdict'>#</a>
**`ManualScraper.emptyinsdict`** &mdash; *Function*.

---


`emptyinsdict()`

Returns a `Dict` intended to be used in an instrument JSON file for the "instrument" dictionary. It has the expected keys and corresponding empty string values.

<a id='ManualScraper.template' href='#ManualScraper.template'>#</a>
**`ManualScraper.template`** &mdash; *Function*.

---


`template(data, labels, ids, outpath::AbstractString;     insdict=emptyinsdict(),     merge::Bool=true)`

Writes a JSON file given `data` and `labels`. For example:

```
data = [(":OUTPUT", "v::Bool", ""), (":OTHERCMD", "v::Symbol", "")]
labels = ["cmd", "values", "type"]
template(data, labels, 1:2, "/my/path.json")
```

Optionally `insdict` can be provided for the `"instrument"` field of the resulting JSON file, or if not provided a template is included to be filled in later.

If `merge` is true, then the "type" and symbol fields of a JSON file at `outpath` are retained for a given `cmd`. The `cmd` field of a property dictionary is used to distinguish different instrument properties. The user is prompted to advise how to proceed if a new command is found that wasn't at `outpath`, and also if multiple entries are found with the same `cmd` field. It is recommended to work on a duplicate of the original file.

<a id='ManualScraper.upperfirst' href='#ManualScraper.upperfirst'>#</a>
**`ManualScraper.upperfirst`** &mdash; *Function*.

---


`upperfirst(a::AbstractString)`

Returns a string based on `a` with the first character only in uppercase.

