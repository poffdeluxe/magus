# Magus

[![Module Version](https://img.shields.io/hexpm/v/magus.svg)](https://hex.pm/packages/magus)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/magus/)
[![License](https://img.shields.io/hexpm/l/magus.svg)](https://github.com/poffdeluxe/magus/blob/main/LICENSE)

Magus is a proof-of-concept libray for implementing and running graph-based agents in Elixir.

Magus provides a simple interface in `Magus.GraphAgent` for defining agents and their flows.
These agent definitions can then be run using either the `Magus.AgentExecutor` (which creates a 
GenServer for storing state as the agent runs asynchronously) and `Magus.AgentExecutorLite` (which
steps through th agent graph synchronously in the same process)

## Examples
Livebooks with a few examples can be found in the `notebooks/` directory. You will need to set a `OPENAI_KEY` secret in your Livebook.
