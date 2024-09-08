# Magus
Magus is a proof-of-concept libray for implementing and running graph-based agents in Elixir.

Magus provides a simple interface in `Magus.GraphAgent` for defining agents and their flows.
These agent definitions can then be run using either the `Magus.AgentExecutor` (which creates a 
GenServer for storing state as the agent runs asynchronously) and `Magus.AgentExecutorLite` (which
steps through th agent graph synchronously in the same process)

## Examples
Livebooks with a few examples can be found in the `notebooks/` directory