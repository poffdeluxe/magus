defmodule Magus.AgentExecutor do
  @doc """
  The AgentExecutor is a GenServer for executing an agent and managing/storing its
  state. This includes agent state as well as state about the execution (current node, status, errors, etc)

  For each node in the agent graph, a new `Task` will be started to run the function for the current node.
  If the node function succeeds, the current agent state will be updated and the executor
  traverses the agent's graph to find the next node to execute.
  If the node function fails, it is retrieved 3 times with an expotential backoff.

  Once created, the AgentExecutor process can be subscribed to in order to get to state and log updates.
  """

  use GenServer
  use Retry

  alias LangChain.MessageDelta
  alias Magus.AgentExecutor
  alias Magus.AgentExecutor.Step
  alias Magus.GraphAgent
  alias Magus.AgentChain

  defstruct [
    :id,
    :agent,
    :cur_node,
    :cur_agent_state,
    :created_at,
    :pid,
    :error_message,
    steps: [],
    status: :notstarted
  ]

  @type t() :: %AgentExecutor{}

  @doc """
  Create a new AgentExecutor process responsible for running an agent.

  ## Options

  - `:agent` - The `Magus.GraphAgent` definition of the agent for the executor.
  - `:id` - A string to use for the id of the execution.
  """
  @spec new(agent: GraphAgent.t(), id: String.t()) :: {:ok, pid()} | {:error, any()}
  def new(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc """
  Returns the execution state of the given AgentExecutor process
  """
  @spec get_state(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) :: any()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Starts the agent execution for the given AgentExecutor process.
  """
  @spec run(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) :: :ok
  def run(pid) do
    GenServer.cast(pid, :start)

    :ok
  end

  @doc """
  Subscribe to new agents being started.
  """
  @spec subscribe_to_new_agents() :: :ok | {:error, {:already_registered, pid()}}
  def subscribe_to_new_agents() do
    Phoenix.PubSub.subscribe(Magus.PubSub, "agent_starting")
  end

  @doc """
  Subscribe to agent execution state changes.
  """
  @spec subscribe_to_state(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) ::
          :ok | {:error, {:already_registered, pid()}}
  def subscribe_to_state(pid) do
    %{id: id} = AgentExecutor.get_state(pid)
    Phoenix.PubSub.subscribe(Magus.PubSub, get_agent_state_topic(id))
  end

  @doc """
  Subscribe to logs coming from the agent execution. This includes info about steps and
  the streamed content from the LLM.
  """
  @spec subscribe_to_logs(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) ::
          :ok | {:error, {:already_registered, pid()}}
  def subscribe_to_logs(pid) do
    %{id: id} = AgentExecutor.get_state(pid)
    Phoenix.PubSub.subscribe(Magus.PubSub, get_agent_log_topic(id))
  end

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    # TODO: autogenerate id if one is not provided
    {:ok,
     %AgentExecutor{
       id: Keyword.fetch!(opts, :id),
       agent: Keyword.fetch!(opts, :agent),
       status: :notstarted,
       cur_node: nil,
       cur_agent_state: nil,
       steps: [],
       created_at: DateTime.now!("Etc/UTC"),
       pid: self(),
       error_message: nil
     }}
  end

  @impl true
  def handle_call(:get_state, _reply, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:start, %{agent: agent} = state) do
    cur_node = agent.entry_point_node

    state = %AgentExecutor{
      state
      | cur_node: cur_node,
        status: :running,
        cur_agent_state: agent.initial_state
    }

    Phoenix.PubSub.broadcast!(Magus.PubSub, "agent_starting", {:agent_starting, state.id})

    # TODO: Check if the end of the graph is reachable
    # Throw error if not

    GenServer.cast(self(), :step)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :step,
        %{agent: agent, cur_node: cur_node, cur_agent_state: cur_agent_state, steps: steps} =
          state
      ) do
    step = %Step{
      node: cur_node,
      status: :notstarted,
      input_state: cur_agent_state
    }

    cur_node_fn = agent.node_to_fn[cur_node]

    # Execute function for current node
    pid = self()
    notify_with_log(state.id, "\n--- BEGINNING STEP #{cur_node} ---\n")

    Task.start_link(fn ->
      log_handler = %{
        on_llm_new_delta: fn _model, %MessageDelta{} = data ->
          # We receive a piece of data
          AgentExecutor.notify_with_log(state.id, data.content)
        end
      }

      chain = AgentChain.new!(stream_handler: log_handler)

      # Retry up to 3 times if we get an error
      # TODO: Make this more configurable
      # and be more thoughtful about how we want to handle errors
      # thrown from nodes
      retry with: exponential_backoff() |> cap(1_000) |> Stream.take(3),
            rescue_only: [MatchError] do
        cur_node_fn.(chain, cur_agent_state)
      after
        new_state -> GenServer.cast(pid, {:step_done, new_state})
      else
        error -> GenServer.cast(pid, {:error, error})
      end
    end)

    # Update the state with the step and notify subscribers
    step = %Step{step | pid: pid, status: :running}
    steps = steps ++ [step]
    state = %AgentExecutor{state | steps: steps}
    notify_with_state(state.id, state)

    {:noreply, state}
  end

  def handle_cast(
        {:step_done, new_agent_state},
        %{agent: agent, cur_node: cur_node, steps: steps} = state
      ) do
    # Set the new agent state
    state = %AgentExecutor{state | cur_agent_state: new_agent_state}

    # Find next nodes to go to
    neighbors = agent.graph |> Graph.out_neighbors(cur_node)

    next_node =
      if length(neighbors) > 1 do
        # We need to call a conditional function to figure out what node to move to
        conditional_fn = agent.node_to_conditional_fn[cur_node]
        conditional_fn.(new_agent_state)
      else
        neighbors |> Enum.at(0)
      end

    if !Enum.member?(neighbors, next_node) do
      raise "Next node is not a possible edge -- check the agent definition"
    end

    # Gets the latest state (assuming that's what we're workin on)
    # and sets the output state
    last_step =
      steps
      |> List.last()
      |> Map.put(:status, :done)
      |> Map.put(:output_state, new_agent_state)

    steps = steps |> List.replace_at(-1, last_step)
    state = %AgentExecutor{state | steps: steps}
    notify_with_state(state.id, state)
    notify_with_log(state.id, "\n--- FINISHED STEP #{cur_node} ---\n")

    # If we're not done, continue to step through the graph
    status =
      if next_node != :end do
        GenServer.cast(self(), :step)
        :running
      else
        # Clean up the agent
        GraphAgent.cleanup(state.agent, state.cur_agent_state)

        # We're done
        :done
      end

    # TODO: have an update state func that automatically notifies subscribers
    state = %AgentExecutor{
      state
      | agent: agent,
        cur_node: next_node,
        steps: steps,
        status: status
    }

    notify_with_state(state.id, state)

    {:noreply, state}
  end

  def handle_cast({:error, msg}, state) do
    # Gets the latest state (assuming that's what we're workin on)
    last_step =
      state.steps
      |> List.last()
      |> Map.put(:status, :failed)

    msg_string = inspect(msg)

    steps = state.steps |> List.replace_at(-1, last_step)
    state = %{state | steps: steps, error_message: msg_string, status: :failed}

    # Clean up the agent
    GraphAgent.cleanup(state.agent, state.cur_agent_state)

    notify_with_state(state.id, state)
    notify_with_log(state.id, "#{msg_string}\n")
    notify_with_log(state.id, "\n--- STEP FAILED #{state.cur_node} ---\n")

    {:noreply, state}
  end

  defp notify_with_state(id, state) do
    Phoenix.PubSub.broadcast!(
      Magus.PubSub,
      get_agent_state_topic(id),
      {:agent_state, id, state}
    )
  end

  def notify_with_log(id, msg) do
    Phoenix.PubSub.broadcast!(Magus.PubSub, get_agent_log_topic(id), {:agent_log, id, msg})
  end

  def get_agent_state_topic(id) do
    "agent:#{id}"
  end

  def get_agent_log_topic(id) do
    "agent_log:#{id}"
  end
end
