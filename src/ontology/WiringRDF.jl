# Copyright 2018 IBM Corp.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module WiringRDF
export wiring_diagram_to_rdf

using Serd
using Catlab, Catlab.Diagram.Wiring

using ..OntologyRDF: rdf_list

const R = RDF.Resource

# Data types
############

struct RDFState
  graph::Union{RDF.Node,Nothing}
  box_value_to_rdf::Function
  port_value_to_rdf::Function
end

# RDF
#####

""" Translate wiring diagram to RDF, possibly as a named graph.
"""
function wiring_diagram_to_rdf(diagram::WiringDiagram;
    graph::Union{RDF.Node,Nothing} = nothing,
    box_value_to_rdf::Function = default_value_to_rdf,
    port_value_to_rdf::Function = default_value_to_rdf
  )
  state = RDFState(graph, box_value_to_rdf, port_value_to_rdf)
  wiring_diagram_to_rdf(state, diagram)
end

function wiring_diagram_to_rdf(state::RDFState, diagram::WiringDiagram)
  stmts = RDF.Statement[]
  graph = state.graph
  if graph != nothing
    append!(stmts, [
      RDF.Triple(graph, R("rdf","type"), R("cat","WiringDiagram")),
      RDF.Quad(graph, R("cat","inputs"), box_rdf_node(input_id(diagram)), graph),
      RDF.Quad(graph, R("cat","outputs"), box_rdf_node(output_id(diagram)), graph),
    ])
  end
  
  # Add ports of outer box.
  append!(stmts, ports_to_rdf(
    state, input_id(diagram), OutputPort, input_ports(diagram)))
  append!(stmts, ports_to_rdf(
    state, output_id(diagram), InputPort, output_ports(diagram)))
  
  # Add boxes.
  for v in box_ids(diagram)
    append!(stmts, box_to_rdf(state, v, box(diagram, v)))
  end
  
  # Add wires.
  for (i, wire) in enumerate(wires(diagram))
    append!(stmts, wire_to_rdf(state, i, wire))
  end
  
  return stmts
end

function box_to_rdf(state::RDFState, v::Int, box::Box)
  # Add RDF node for box.
  node = box_rdf_node(v)
  graph = state.graph
  stmts = RDF.Statement[
    RDF.Edge(node, R("rdf","type"), R("cat","Box"), graph)
  ]
  append!(stmts, state.box_value_to_rdf(box.value, node, graph))
  
  # Add RDF for ports of box.
  append!(stmts, ports_to_rdf(state, v, InputPort, input_ports(box)))
  append!(stmts, ports_to_rdf(state, v, OutputPort, output_ports(box)))
  
  return stmts
end

function box_to_rdf(state::RDFState, v::Int, diagram::WiringDiagram)
  error("RDF representation of nested wiring diagrams not yet implemented")
end

function ports_to_rdf(state::RDFState, v::Int, kind::PortKind, port_values::Vector)
  # Add RDF for ports.
  stmts = RDF.Statement[]
  for (i, port_value) in enumerate(port_values)
    append!(stmts, port_to_rdf(state, Port(v,kind,i), port_value))
  end
  
  # Add RDF list of ports.
  graph = state.graph
  node = box_rdf_node(v)
  port_nodes = [ port_rdf_node(Port(v,kind,i)) for i in eachindex(port_values) ]
  prop = kind == InputPort ? "dom" : "codom"
  list_node, list_stmts = rdf_list(port_nodes, "box$v-$prop"; graph=graph)
  push!(stmts, RDF.Edge(node, R("cat",prop), list_node, graph))
  append!(stmts, list_stmts)
  stmts
end

function port_to_rdf(state::RDFState, port::Port, port_value::Any)
  # Add RDF node for port.
  graph = state.graph
  port_node = port_rdf_node(port)
  stmts = RDF.Statement[
    RDF.Edge(port_node, R("rdf","type"), R("cat","Port"), graph),
  ]
  append!(stmts, state.port_value_to_rdf(port_value, port_node, graph))
  
  # Add RDF edges for port.
  #
  # Although "cat:in" and "cat:out" are both RDF sub-properties of "cat:wire",
  # we include "cat:wire" explicitly because it is difficult (impossible?)
  # to enable reasoning on all named graphs in Apache Jena.
  #
  # Reference: https://stackoverflow.com/q/35428064
  node = box_rdf_node(port.box)
  if port.kind == InputPort
    append!(stmts, [
      RDF.Edge(node, R("cat","port"), port_node, graph),
      RDF.Edge(node, R("cat","input-port"), port_node, graph),
      RDF.Edge(node, R("cat","input-port-$(port.port)"), port_node, graph),
      RDF.Edge(port_node, R("cat","wire"), node, graph),
      RDF.Edge(port_node, R("cat","in"), node, graph),
      RDF.Edge(port_node, R("cat","in-$(port.port)"), node, graph),
    ])
  elseif port.kind == OutputPort
    append!(stmts, [
      RDF.Edge(node, R("cat","port"), port_node, graph),
      RDF.Edge(node, R("cat","output-port"), port_node, graph),
      RDF.Edge(node, R("cat","output-port-$(port.port)"), port_node, graph),
      RDF.Edge(node, R("cat","wire"), port_node, graph),
      RDF.Edge(node, R("cat","out"), port_node, graph),
      RDF.Edge(node, R("cat","out-$(port.port)"), port_node, graph),
    ])
  end
  stmts
end

function wire_to_rdf(state::RDFState, n::Int, wire::Wire)
  graph = state.graph
  src, tgt = wire.source, wire.target
  src_node, tgt_node = port_rdf_node(src), port_rdf_node(tgt)
  RDF.Statement[
    RDF.Edge(src_node, R("cat","wire"), tgt_node, graph),
  ]
end

function box_rdf_node(v::Int)::RDF.Node
  RDF.Blank(string("box", v))
end

function port_rdf_node(port::Port)::RDF.Node
  RDF.Blank(string("box", port.box, "-",
                   port.kind == InputPort ? "in" : "out", port.port))
end

function default_value_to_rdf(value, node, graph)
  if value == nothing
    RDF.Statement[]
  else
    [ RDF.Edge(node, R("cat","value"), RDF.Literal(string(value)), graph) ]
  end
end

end