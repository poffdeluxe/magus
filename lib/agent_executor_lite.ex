defmodule Magus.AgentExecutorLite do
  alias Magus.GraphAgent

  @spec run(%GraphAgent{}) :: any()
  def run(%GraphAgent{} = agent) do
    do_step(agent, agent.initial_state, agent.entry_point_node)
  end

  defp do_step(agent, cur_state, :end) do
    # Return our final output state value or the whole state if an output state is not specified
    final_output_property = agent |> Map.get(:final_output_property)

    case final_output_property do
      nil -> cur_state
      _ -> Map.get(cur_state, final_output_property)
    end
  end

  defp do_step(%GraphAgent{} = agent, cur_state, cur_node) do
    cur_node_fn = agent.node_to_fn[cur_node]

    chain = Magus.AgentChain.new!()
    next_state = cur_node_fn.(chain, cur_state)

    # Find next edge to go to
    neighbors = agent.graph |> Graph.out_neighbors(cur_node)

    next_node =
      if length(neighbors) > 1 do
        # We need to call a conditional function to figure out what node to move to
        conditional_fn = agent.node_to_conditional_fn[cur_node]
        conditional_fn.(next_state)
      else
        neighbors |> Enum.at(0)
      end

    do_step(agent, next_state, next_node)
  end
end
