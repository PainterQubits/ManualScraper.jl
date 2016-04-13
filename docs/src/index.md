# ManualScraper.jl

A package for scraping instrument manuals to assemble standardized templates
of commands and documentation.

## Installation

+ Install package [`CHM.jl`](https://github.com/ajkeller34/CHM.jl).
+ `Pkg.clone("https://github.com/ajkeller34/ManualScraper.jl.git")`

## Usage

This package is not entirely automated; to do so would require some intelligent
parsing that would be far more complicated. Think of this package as a repository
for the code that generates the template files read by the
[PainterQB](https://github.com/ajkeller34/PainterQB.jl)
package.

1. Get a plain-text or HTML file to parse that describes the instrument commands.
This may be the hardest part as often times only a PDF file is provided. If the
instrument has an on-board Windows computer, it will likely have a .CHM file
from which HTML can be retrieved using `CHM.jl`.
If the instrument only has a PDF file, I've achieved the best results in
extracting text using Adobe Acrobat. There are open-source packages to do this
but the results are often worse, at least with limited tweaking.

2. Construct regular expressions to peel the required information out of the
plain-text, HTML, etc. You will want to extract the commands, argument types, and
possibly documentation (although be careful with copyright if sharing). For
constructing the regular expressions, it is probably easiest to use an
interactive website that shows the results of the regex search as you construct the
expression. Just search for "regular expression tester" and look for one that
supports PCRE regex.

3. Collect the information from the regex search into arrays. See existing examples
for how to do this.

4. Use the [`ManualScraper.template`]({ref}) function to turn the collected
information into the desired template file. It is capable of merging information
from old versions of template files.

## API

### Macros

    {docs}
    @awg5k_str
    @ena_str
    scrape

### Internal

    {docs}
    ManualScraper.cmdtostr
    ManualScraper.diagnose
    ManualScraper.emptyinsdict
    ManualScraper.template
    ManualScraper.upperfirst
