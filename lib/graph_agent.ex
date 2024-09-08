defmodule Magus.GraphAgent do
  alias Magus.GraphAgent

  defstruct [
    :name,
    :entry_point_node,
    initial_state: %{},
    graph: Graph.new(),
    final_output_property: nil,
    node_to_fn: %{},
    node_to_conditional_fn: %{},
    cleanup_fn: nil
  ]

  @type t() :: %GraphAgent{}
  @type node_name() :: atom()

  @spec add_node(t(), node_name(), fun()) :: t()
  def add_node(agent, node, node_fn) do
    g = agent.graph |> Graph.add_vertex(node)
    node_to_fn = agent.node_to_fn |> Map.put(node, node_fn)

    %{agent | graph: g, node_to_fn: node_to_fn}
  end

  @spec add_edge(t(), node_name(), node_name()) :: t()
  def add_edge(agent, node_a, node_b) do
    g = agent.graph |> Graph.add_edge(node_a, node_b)

    %{agent | graph: g}
  end

  @spec add_conditional_edges(t(), node_name(), list(node_name()), fun()) :: t()
  def add_conditional_edges(agent, node_a, possible_nodes, conditional_fn) do
    edges = Enum.map(possible_nodes, fn end_node -> {node_a, end_node} end)
    g = agent.graph |> Graph.add_edges(edges)

    %{
      agent
      | graph: g,
        node_to_conditional_fn: Map.put(agent.node_to_conditional_fn, node_a, conditional_fn)
    }
  end

  @spec set_entry_point(t(), node_name()) :: t()
  def set_entry_point(agent, node) do
    %{agent | entry_point_node: node}
  end

  @spec get_final_output(t()) :: any()
  def get_final_output(%GraphAgent{final_output_property: nil}) do
    # No final output property specified
    ""
  end

  @spec get_final_output(t(), any()) :: any()
  def get_final_output(agent, cur_state) do
    Map.fetch!(cur_state, agent.final_output_property)
  end

  @spec cleanup(t(), any()) :: t()
  def cleanup(agent, cur_state)

  def cleanup(%GraphAgent{cleanup_fn: nil} = agent, _cur_state) do
    agent
  end

  def cleanup(%GraphAgent{cleanup_fn: cleanup_fn} = agent, cur_state) do
    cleanup_fn.(cur_state)
    agent
  end
end
