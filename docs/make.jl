using TrimTrace
using Documenter
using DocumenterCodeBlocks
using DocumenterDocstringStyle

const _repo_url = "https://github.com/BjarkeHautop/TrimTrace.jl"

# The `record` and `check` examples use the demo package in test/fixtures.
const _fixture_dir = joinpath(dirname(@__DIR__), "test", "fixtures", "TrimFixture")

DocMeta.setdocmeta!(
    TrimTrace,
    :DocTestSetup,
    :(using TrimTrace; $_fixture_dir in LOAD_PATH || push!(LOAD_PATH, $_fixture_dir));
    recursive = true,
)

# Add titles of sections and overrides page titles
const titles =
    Dict("90-tested-packages.md" => "Tested Packages", "95-reference.md" => "Reference")

function recursively_list_pages(folder; path_prefix = "")
    pages_list = Any[]

    # A subfolder's own index.md (if any) becomes its overview page, listed
    # first within that subfolder. The root index.md is handled separately by
    # `list_pages`, so skip this for the top-level call (empty path_prefix).
    if path_prefix != "" && isfile(joinpath(folder, "index.md"))
        folder_title = get(titles, path_prefix, path_prefix)
        push!(pages_list, "$folder_title overview" => joinpath(path_prefix, "index.md"))
    end

    for file in readdir(folder)
        if file == "index.md"
            # We add index.md separately to make sure it is the first in the list
            continue
        end
        # this is the relative path according to our prefix, not @__DIR__, i.e., relative to `src`
        relpath = joinpath(path_prefix, file)
        # full path of the file
        fullpath = joinpath(folder, relpath)

        if isdir(fullpath)
            # If this is a folder, enter the recursion case
            subsection = recursively_list_pages(fullpath; path_prefix = relpath)

            # Ignore empty folders
            if length(subsection) > 0
                title = if haskey(titles, relpath)
                    titles[relpath]
                else
                    @error "Bad usage: '$relpath' does not have a title set. Fix in 'docs/make.jl'"
                    relpath
                end
                push!(pages_list, title => subsection)
            end

            continue
        end

        if splitext(file)[2] != ".md" # non .md files are ignored
            continue
        elseif haskey(titles, relpath) # case 'title => path'
            push!(pages_list, titles[relpath] => relpath)
        else # case 'title'
            push!(pages_list, relpath)
        end
    end

    return pages_list
end

function list_pages()
    root_dir = joinpath(@__DIR__, "src")
    pages_list = recursively_list_pages(root_dir)

    return ["index.md"; pages_list]
end

makedocs(;
    modules = [TrimTrace],
    authors = "Bjarke Hautop Kristensen <bjarke.hautop@gmail.com>",
    repo = "$_repo_url/blob/{commit}{path}#{line}",
    sitename = "TrimTrace.jl",
    format = Documenter.HTML(;
        canonical = "https://BjarkeHautop.github.io/TrimTrace.jl",
        repolink = _repo_url,
    ),
    pages = list_pages(),
    plugins = [
        CodeBlocks(line_numbers = false),
        SchemaConfig(
            order = [
                "Arguments",
                "Keywords",
                "Returns",
                "Attributes",
                "Throws",
                "Notes",
                "Examples",
                "See also",
                "References",
                "Extended help",
            ],
            theme = :rustdoc,
            strict = true,
            skip_unexported = true,
        ),
    ],
)

deploydocs(; repo = "github.com/BjarkeHautop/TrimTrace.jl")
