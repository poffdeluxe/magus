defmodule Magus.AgentExecutor.Step do
  defstruct [
    :node,
    status: :notstarted,
    input_state: nil,
    output_state: nil,
    pid: nil
  ]
end
