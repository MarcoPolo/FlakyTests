### A Pluto.jl notebook ###
# v0.19.12

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ e87dbb91-2721-477e-8f1a-6d2327b03ee8
begin
	import GitHub
	using PlutoUI
	using HTTP
	using Downloads
	DEFAULT_API=GitHub.DEFAULT_API
end

# ╔═╡ f2d9e292-52e8-46ee-832e-acad12b2380b
begin
	using Distributed
	using Chain
end

# ╔═╡ 3575ac50-cd4f-494d-ab1b-c1b0fdfa230c
using DataFrames

# ╔═╡ 9ab4ced1-e416-44a9-af44-3b92e3f75631
using VegaLite

# ╔═╡ 6e589fe5-32bf-4a62-b9fb-e3e43e461fb8
repo = "libp2p/go-libp2p"

# ╔═╡ 8142cf70-df0a-40b4-979c-2fd5ecc254f2
md"Workflow to check:"

# ╔═╡ e49b7891-3cf7-426b-a8b9-893377daaa38
md"""
## Notes:

- This analysis works by seeing which test failed on the first try, but passed when reran with no code changes.
- "Missing Test Name" is likely a test timeout
"""

# ╔═╡ c2320b04-276d-43e3-b166-d7b151f179ff
defaultWorkflowName = "Go Test"

# ╔═╡ 29c69892-54bc-4882-a1ea-3b978dfed033
md"### Top 10 Flaky tests, sorted by recency, then count"

# ╔═╡ 96d99d5b-b52a-47fe-aebd-96ca712d0f36
function find_test_name_or_nothing(log)
	let m = match(r"(Test[^\s]*)", log)
		if m == nothing "Missing Test Name" else m[1] end
	end
end

# ╔═╡ 38a79f14-1905-4ff7-8dcb-00c0d0cffae1
md"### All Flaky tests, sorted by recency, then count
(expand the array, to see them all)
"

# ╔═╡ f9537631-7cda-4e38-8e47-105ad8aa2f31
md"## Implementation"

# ╔═╡ d3323ee3-9466-4ccb-b8a6-2c4f2e2a752e
gh_auth = GitHub.authenticate(ENV["GITHUB_ACCESS_TOKEN"])

# ╔═╡ 105c8219-439f-4ab2-9b3d-a1a183c69144
workflows = GitHub.gh_get_paged_json(GitHub.DEFAULT_API, "/repos/$repo/actions/workflows", auth = gh_auth)


# ╔═╡ 8b9dd7dd-52ea-4a9c-8b18-08204d6e5f1a
workflowNames = map(x -> x => x["name"], workflows[1]["workflows"])

# ╔═╡ 4e75e173-7da7-4aed-8b9d-98eb975ea87c
defaultWorkflow = first(filter(x -> x["name"] == defaultWorkflowName,workflows[1]["workflows"]))

# ╔═╡ 8799c8e7-a708-4a8a-ba77-5065662e8ec4
@bind selectedWorkflow Select(workflowNames, default=defaultWorkflow)

# ╔═╡ f4ed5a0d-a4ed-491d-bc2e-b857b23160a7
runs = GitHub.gh_get_paged_json(GitHub.DEFAULT_API, "/repos/$repo/actions/workflows/$(selectedWorkflow["id"])/runs", auth = gh_auth, page_limit = 5)

# ╔═╡ 64c3a7a7-b810-4331-b303-8b86e031c2ec
wf_runs = collect(Iterators.flatten(map(x -> x["workflow_runs"], runs[1])))

# ╔═╡ 65e07a73-3f05-4842-a33f-e1674697afe3
successful_runs = filter(collect(wf_runs)) do run 
	run["conclusion"] == "success"
end

# ╔═╡ 89e58a37-d075-475e-b66a-3bfec1b6dae2
successful_runs_after_retry = filter(successful_runs) do run 
	run["run_attempt"] > 1
end

# ╔═╡ aa767183-6ffc-4345-90f6-fd9d0100fc44
score = round(1000*(length(successful_runs) - length(successful_runs_after_retry))/length(successful_runs))/10

# ╔═╡ ef87a21a-693b-4096-8f05-212eba946276
Markdown.parse("
# $repo flakiness score: $score

For the `$(selectedWorkflow["name"])` workflow
")

# ╔═╡ 3f4e98f7-6856-474a-8094-bb4ba49eb578
begin
	r=HTTP.request(:GET, "https://img.shields.io/badge/ci--flakiness--score-$score-blue")
	write("./current-score.svg", r.body)
	"Wrote badge for $score"
end

# ╔═╡ 29e69e6c-a9fd-4e94-84ce-52d2dbb5451e
successful_runs_after_retry[2]

# ╔═╡ 7bc99df9-d9e7-4303-b36e-84faef7cc325
@GitHub.api_default function get_run_log_url(api::GitHub.GitHubAPI, run_id, run_attempt; options...)
	apiUrl = "/repos/$(GitHub.name(repo))/actions/runs/$run_id/attempts/$run_attempt"
GitHub.gh_get_json(api, apiUrl; options...)["logs_url"]
end

# ╔═╡ c658bd71-84b2-422c-bf64-5c35b0b9a09e
function maybe_download_log(run_id, run_attempt)
	path = "./run-logs/$run_id-$run_attempt.zip"
	if isfile(path)
		return path
	end
	log_url = get_run_log_url(run_id, run_attempt, auth = gh_auth)
	Downloads.download(log_url, path, headers = GitHub.authenticate_headers!(Dict{String,String}(), gh_auth))

	return path
end

# ╔═╡ d69e309e-7e21-40c4-bca9-d19fab26541b
all_logs = Iterators.map(
	Iterators.flatten(map(x -> map(run_attempt -> (x, x["id"], run_attempt),[1:x["run_attempt"]-1;]), successful_runs_after_retry))
) do (run, id, attempt)
	try
		(run, maybe_download_log(id, attempt))
	catch e
		nothing
	end
end

# ╔═╡ 04b17c05-af01-4a2c-a4ec-c44945466f41
function parse_os(s)
	match(r"\s([a-z]+)",s)[1]
end

# ╔═╡ 92b717b5-ef2d-4580-b98b-224786e06d92
md"### Deps"

# ╔═╡ 1f17eef4-2ef2-4bc3-a4ca-0709205afbb1
import ZipFile

# ╔═╡ b593638c-0347-4c81-9552-c42a43867dad
function filter_zipped_logs(line_filter, zip_file_path)
	logs = ZipFile.Reader(zip_file_path)
	
	filtered = collect(Iterators.flatten(map(logs.files) do f
		(Iterators.filter(line_filter, eachline(f)) |> 
		lines -> Iterators.map(x -> (f.name, x), lines))
	end))
	
	close(logs)

	return filtered
end

# ╔═╡ d76b3c2e-bf48-40f2-885b-3658d95fc986
flaky_tests = @chain Iterators.filter(!isnothing, all_logs) begin
  Iterators.map(_) do runAndPath
	  matches = @chain runAndPath[2] begin
		  filter_zipped_logs(l -> contains(l, "--- FAIL:"), _)
		  collect
	  end
	  return (runAndPath[1], matches)
  end |> collect
end

# ╔═╡ 4bfea66a-28f7-4c5a-adcc-fc04ff5cddd3
flaky_tests_transformed = map(flaky_tests) do t 
	map(x -> (x[1],x[2],t[1]), t[2]) 
end |> Iterators.flatten |> collect

# ╔═╡ be8d0bac-9e22-4b99-bcb9-304e28da169d
flaky_tests_table = @chain DataFrame(flaky_tests_transformed) begin
	transform(:3 => ByRow(x -> x["html_url"]) => :html_url)
	transform(:3 => ByRow(x -> x["id"]) => :id)
	rename(:3 => :run)
	transform(:2 => ByRow(find_test_name_or_nothing) => :Test)
	rename(:1 => :Filename)
	rename(:2 => :FailLine)
	groupby([:Test, :id])
	combine( :Filename => parse_os ∘ first => :OS, :html_url => first => :html_url, :run => first => :run)
	transform(:run => ByRow(x -> x["run_started_at"]) => :run_date)
	sort(:run_date, rev = true)
	groupby([:Test])
	# sort(:run_date, rev = true)
	combine(:run_date => first => :run_date, :id => length => :count, :id => first => :id, :html_url => first => :html_url)

	# select([:Test, :id, :run_date, :html_url, :OS])
	# sort(:run_date, rev = true)
end

# ╔═╡ 5fd73cbc-31d5-4c9b-a7a5-b1d7746ffbd7
# A bit of a hack to render all the flaky tests. Since the default table viewer only renders 10 entries. The workaround is to render only 10 entries at a time, and return a vector of these tables.
map([0:Int(round(nrow(flaky_tests_table) / 20, RoundUp));]) do x
	let start_idx = 1+x*10,
	end_idx = min(start_idx+10, nrow(flaky_tests_table))
		flaky_tests_table[start_idx:end_idx, :]
	end
end

# ╔═╡ 8d2036e8-fadb-4da4-95ed-35c22fec8b16
flaky_tests_df = @chain map(flaky_tests_transformed) do l
	find_test_name_or_nothing(l[2])
end begin
	DataFrame(Test=_, OS=map(x->parse_os(x[1]),flaky_tests_transformed), run=map(x -> x[3], flaky_tests_transformed))
	transform(:run => ByRow(x -> x["id"]) => :id)
	select(Not(:run))


	# Dedupe the same failure in the same run+os
	groupby([:id, :OS, :Test])
	combine(:Test => first => :Test)
	# Count failures by test + os
	groupby([:Test, :OS])
	combine(:Test=> length => :Count)
	sort(:Count, rev=true)
end

# ╔═╡ 26df8f0a-5a1e-4c33-af11-e1c983df4484
flaky_tests_df |> @vlplot(:bar, y=:Test, x=:Count, color=:OS)

# ╔═╡ 429bb5e5-6c12-4ebc-adb9-5f6e2b65dfac
flaky_tests

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Chain = "8be319e6-bccf-4806-a6f7-6fae938471bc"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Distributed = "8ba89e20-285c-5b6f-9357-94700520ee1b"
Downloads = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
GitHub = "bc5e4493-9b4d-5f90-b8aa-2b2bcaad7a26"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"
ZipFile = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"

[compat]
Chain = "~0.5.0"
DataFrames = "~1.3.6"
GitHub = "~5.7.3"
HTTP = "~1.4.0"
PlutoUI = "~0.7.43"
VegaLite = "~2.6.0"
ZipFile = "~0.10.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.2"
manifest_format = "2.0"
project_hash = "094bfd5031a6cbbc197e993454827b0979635f45"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitFlags]]
git-tree-sha1 = "84259bb6172806304b9101094a7cc4bc6f56dbc6"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.5"

[[deps.Chain]]
git-tree-sha1 = "8c4920235f6c561e401dfe569beb8b924adad003"
uuid = "8be319e6-bccf-4806-a6f7-6fae938471bc"
version = "0.5.0"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "5856d3031cdb1f3b2b6340dfdc66b6d9a149a374"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.2.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "0.5.2+0"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "fb21ddd70a051d882a1686a5a550990bbe371a95"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.4.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "1106fa7e1256b402a86a8e7b15c00c85036fef49"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.11.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "db2a9cb664fcea7836da4b414c3278d71dd602d2"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.3.6"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "94f5101b96d2d968ace56f7f2db19d0a5f592e28"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.15.0"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GitHub]]
deps = ["Base64", "Dates", "HTTP", "JSON", "MbedTLS", "Sockets", "SodiumSeal", "URIs"]
git-tree-sha1 = "f1d3170f588c7610b568c9a97971915100dd51e8"
uuid = "bc5e4493-9b4d-5f90-b8aa-2b2bcaad7a26"
version = "5.7.3"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "4abede886fcba15cd5fd041fef776b230d004cee"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.4.0"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JSONSchema]]
deps = ["HTTP", "JSON", "URIs"]
git-tree-sha1 = "8d928db71efdc942f10e751564e6bbea1e600dfe"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "1.0.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "6872f9594ff273da6d13c7c1a1545d5a8c7d0c1c"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.6"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.NodeJS]]
deps = ["Pkg"]
git-tree-sha1 = "905224bbdd4b555c69bb964514cfa387616f0d3a"
uuid = "2bd173c7-0d6d-553b-b6af-13a54713934c"
version = "1.3.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "02be9f845cb58c2d6029a6d5f67f4e0af3237814"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.1.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e60321e3f2616584ff98f0a4f18d98ae6f89bbb3"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.17+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "3d5bf43e3e8b412656404ed9466f1dcbf7c50269"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "2777a5c2c91b3145f5aa75b61bb4c2eb38797136"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.43"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "dfb54c4e414caa595a1f2ed759b160f5a3ddcba5"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SodiumSeal]]
deps = ["Base64", "Libdl", "libsodium_jll"]
git-tree-sha1 = "80cef67d2953e33935b41c6ab0a178b9987b1c99"
uuid = "2133526b-2bfb-4018-ac12-889fb3908a75"
version = "0.1.1"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "78fecfe140d7abb480b53a44f3f85b6aa373c293"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.2"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "2d7164f7b8a066bcfa6224e67736ce0eb54aef5b"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.9.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "8a75929dcd3c38611db2f8d08546decb514fcadf"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.9"

[[deps.Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[deps.URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

[[deps.URIs]]
git-tree-sha1 = "e59ecc5a41b000fa94423a578d29290c7266fc10"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Vega]]
deps = ["DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "JSONSchema", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "Setfield", "TableTraits", "TableTraitsUtils", "URIParser"]
git-tree-sha1 = "c6bd0c396ce433dce24c4a64d5a5ab6dc8e40382"
uuid = "239c3e63-733f-47ad-beb7-a12fde22c578"
version = "2.3.1"

[[deps.VegaLite]]
deps = ["Base64", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "TableTraits", "TableTraitsUtils", "URIParser", "Vega"]
git-tree-sha1 = "3e23f28af36da21bfb4acef08b144f92ad205660"
uuid = "112f6efa-9a02-5b7d-90c0-432ed331239a"
version = "2.6.0"

[[deps.ZipFile]]
deps = ["Libdl", "Printf", "Zlib_jll"]
git-tree-sha1 = "ef4f23ffde3ee95114b461dc667ea4e6906874b2"
uuid = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
version = "0.10.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[deps.libsodium_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "848ab3d00fe39d6fbc2a8641048f8f272af1c51e"
uuid = "a9144af2-ca23-56d9-984f-0d03f7b5ccf8"
version = "1.0.20+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─ef87a21a-693b-4096-8f05-212eba946276
# ╟─6e589fe5-32bf-4a62-b9fb-e3e43e461fb8
# ╟─8142cf70-df0a-40b4-979c-2fd5ecc254f2
# ╟─8799c8e7-a708-4a8a-ba77-5065662e8ec4
# ╟─e49b7891-3cf7-426b-a8b9-893377daaa38
# ╟─c2320b04-276d-43e3-b166-d7b151f179ff
# ╟─26df8f0a-5a1e-4c33-af11-e1c983df4484
# ╟─29c69892-54bc-4882-a1ea-3b978dfed033
# ╟─be8d0bac-9e22-4b99-bcb9-304e28da169d
# ╠═96d99d5b-b52a-47fe-aebd-96ca712d0f36
# ╟─38a79f14-1905-4ff7-8dcb-00c0d0cffae1
# ╟─5fd73cbc-31d5-4c9b-a7a5-b1d7746ffbd7
# ╟─f9537631-7cda-4e38-8e47-105ad8aa2f31
# ╟─105c8219-439f-4ab2-9b3d-a1a183c69144
# ╟─8b9dd7dd-52ea-4a9c-8b18-08204d6e5f1a
# ╟─4e75e173-7da7-4aed-8b9d-98eb975ea87c
# ╠═3f4e98f7-6856-474a-8094-bb4ba49eb578
# ╟─f4ed5a0d-a4ed-491d-bc2e-b857b23160a7
# ╠═64c3a7a7-b810-4331-b303-8b86e031c2ec
# ╠═65e07a73-3f05-4842-a33f-e1674697afe3
# ╠═89e58a37-d075-475e-b66a-3bfec1b6dae2
# ╠═aa767183-6ffc-4345-90f6-fd9d0100fc44
# ╟─d3323ee3-9466-4ccb-b8a6-2c4f2e2a752e
# ╠═29e69e6c-a9fd-4e94-84ce-52d2dbb5451e
# ╠═c658bd71-84b2-422c-bf64-5c35b0b9a09e
# ╠═b593638c-0347-4c81-9552-c42a43867dad
# ╠═d69e309e-7e21-40c4-bca9-d19fab26541b
# ╠═d76b3c2e-bf48-40f2-885b-3658d95fc986
# ╟─7bc99df9-d9e7-4303-b36e-84faef7cc325
# ╠═8d2036e8-fadb-4da4-95ed-35c22fec8b16
# ╠═04b17c05-af01-4a2c-a4ec-c44945466f41
# ╠═4bfea66a-28f7-4c5a-adcc-fc04ff5cddd3
# ╠═429bb5e5-6c12-4ebc-adb9-5f6e2b65dfac
# ╟─92b717b5-ef2d-4580-b98b-224786e06d92
# ╟─e87dbb91-2721-477e-8f1a-6d2327b03ee8
# ╠═1f17eef4-2ef2-4bc3-a4ca-0709205afbb1
# ╠═f2d9e292-52e8-46ee-832e-acad12b2380b
# ╠═3575ac50-cd4f-494d-ab1b-c1b0fdfa230c
# ╠═9ab4ced1-e416-44a9-af44-3b92e3f75631
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
