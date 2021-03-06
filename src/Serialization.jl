""" Serialization of raw and semantic flow graphs.
"""
module Serialization
export read_raw_graphml, read_raw_graph_json,
  read_semantic_graphml, read_semantic_graph_json

using Nullables

using Catlab, Catlab.WiringDiagrams
import Catlab.WiringDiagrams: convert_from_graph_data, convert_to_graph_data
using ..Doctrine
using ..RawFlowGraphs

# Raw flow graphs
#################

read_raw_graphml(xml) = read_graphml(RawNode, RawPort, Nothing, xml)
read_raw_graph_json(json) = read_json_graph(RawNode, RawPort, Nothing, json)

function convert_from_graph_data(::Type{RawNode}, data::AbstractDict)
  annotation = to_nullable(String, pop!(data, "annotation", nothing))
  annotation_index = to_nullable(Int, pop!(data, "annotation_index", nothing))
  annotation_kind_str = to_nullable(String, pop!(data, "annotation_kind", nothing))
  annotation_kind = isnull(annotation_kind_str) ? FunctionAnnotation :
    convert(RawNodeAnnotationKind, get(annotation_kind_str))
  RawNode(data, annotation, annotation_index, annotation_kind)
end

function convert_from_graph_data(::Type{RawPort}, data::AbstractDict)
  annotation = to_nullable(String, pop!(data, "annotation", nothing))
  annotation_index = to_nullable(Int, pop!(data, "annotation_index", nothing))
  value = to_nullable(Any, pop!(data, "value", nothing))
  RawPort(data, annotation, annotation_index, value)
end

to_nullable(T::Type, x) = isnothing(x) ? Nullable{T}() : Nullable{T}(x)

# Semantic flow graphs
######################

read_semantic_graphml(xml) = read_graphml(
  Union{Monocl.Hom,Nothing}, Union{Monocl.Ob,Nothing}, Nothing, xml)
read_semantic_graph_json(json) = read_json_graph(
  Union{Monocl.Hom,Nothing}, Union{Monocl.Ob,Nothing}, Nothing, json)

function convert_from_graph_data(::Type{Monocl.Ob}, data::AbstractDict)
  parse_json_sexpr(Monocl, data["ob"]; symbols=false)
end
function convert_from_graph_data(::Type{Monocl.Hom}, data::AbstractDict)
  parse_json_sexpr(Monocl, data["hom"]; symbols=false)
end
function convert_from_graph_data(::Type{Union{Monocl.Ob,Nothing}}, data::AbstractDict)
  isempty(data) ? nothing : convert_from_graph_data(Monocl.Ob, data)
end
function convert_from_graph_data(::Type{Union{Monocl.Hom,Nothing}}, data::AbstractDict)
  isempty(data) ? nothing : convert_from_graph_data(Monocl.Hom, data)
end

function convert_to_graph_data(expr::Monocl.Ob)
  Dict("ob" => to_json_sexpr(expr))
end
function convert_to_graph_data(expr::Monocl.Hom)
  Dict("hom" => to_json_sexpr(expr))
end

function convert_from_graph_data(::Type{MonoclElem}, data::AbstractDict)
  ob = haskey(data, "ob") ?
    parse_json_sexpr(Monocl, data["ob"]; symbols=false) : nothing
  value = get(data, "value", Nullable())
  MonoclElem(ob, value)
end

function convert_to_graph_data(elem::MonoclElem)
  data = Dict{String,Any}()
  if (elem.ob != nothing) data["ob"] = to_json_sexpr(elem.ob) end
  if (!isnull(elem.value)) data["value"] = get(elem.value) end
  return data
end

end