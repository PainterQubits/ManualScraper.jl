
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


1. Construct a regular expression to peel the required information out of the plain-text or HTML. You will want to extract the commands, argument types, and possibly documentation (although be careful with copyright if sharing). For constructing the regular expressions, it is probably easiest to use an interactive website that shows the results of the regex search as you construct the expression. Just search for "regular expression tester" and look for one that supports PCRE regex.


1. Collect the information from the regex search into arrays. See existing examples for how to do this.


1. Use the [`ManualScraper.template`](index.md#ManualScraper.template) function to turn the collected information into the desired template file. It is capable of merging information from old versions of template files.


<a id='API-1'></a>

## API

<a id='ManualScraper.template' href='#ManualScraper.template'>#</a>
**`ManualScraper.template`** &mdash; *Function*.

---


`template(data, labels, outpath::AbstractString;     insdict=emptyinsdict(),     merge::Bool=true)`

Writes a JSON file given `data` and `labels`. For example:

```
data = [(":OUTPUT", "v::Bool", ""), (":OTHERCMD", "v::Symbol", "")]
labels = ["cmd", "values", "type"]
template(data, labels, "/my/path.json")
```

Optionally `insdict` can be provided for the `"instrument"` field of the resulting JSON file, or if not provided a template is included to be filled in later.

If `merge` is true, then the fields of any JSON file at `outpath` are retained and only previously undefined fields are added to the file in the corresponding locations. The `cmd` field of a property dictionary is used to distinguish different instrument properties. It is recommended to work on a duplicate of the original file.

<a id='ManualScraper.cmdtostr' href='#ManualScraper.cmdtostr'>#</a>
**`ManualScraper.cmdtostr`** &mdash; *Function*.

---


`cmdtostr(a::AbstractString)`

Returns a string based on a command, e.g. ":SOURCE:FUNCTION" becomes "SourceFunction".

<a id='ManualScraper.emptyinsdict' href='#ManualScraper.emptyinsdict'>#</a>
**`ManualScraper.emptyinsdict`** &mdash; *Function*.

---


`emptyinsdict()`

Returns a `Dict` intended to be used in an instrument JSON file for the "instrument" dictionary. It has the expected keys and corresponding empty string values.

