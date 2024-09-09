defmodule Magus.AgentChain do
  @doc """
  Define a chain for agents.

  This is an extention of the LangChain.Chains.LLMChain chain that provides
  a few helpers for the agent use case.

  A `stream_handler` can be passed in when the AgentChain is created and then
  used automatically when the chain is run. This is useful for the AgentExecutor
  to listen to tokens as they're returned by the LLM.

  The AgentChain can also be configured with a JSON schema that is used when
  requesting content from the LLM and then used to validate that the LLM response
  conforms to the schema.
  """
  alias LangChain.PromptTemplate
  alias Magus.AgentChain

  alias LangChain.Message
  alias LangChain.MessageDelta
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatGoogleAI

  defstruct [
    :wrapped_chain,
    :stream_handler,
    :json_response_schema
  ]

  @default_openai_model "gpt-3.5-turbo"
  @default_gemini_model "gemini-1.5-flash"

  @json_format_template PromptTemplate.from_template!(
                          ~S|"The output should be formatted as a JSON instance that conforms to the JSON schema below.

As an example, for the schema {"properties": {"foo": {"title": "Foo", "description": "a list of strings", "type": "array", "items": {"type": "string"}}}, "required": ["foo"]}
the object {"foo": ["bar", "baz"]} is a well-formatted instance of the schema. The object {"properties": {"foo": ["bar", "baz"]}} is not well-formatted.

Do not wrap the JSON with any Markdown.

Here is the output schema:
```
<%= @schema %>
```|
                        )
  @type t() :: %AgentChain{}

  @doc """
  Start a new AgentChain configuration.

  ## Options

  - `:verbose` - Runs the LLM in verbose mode if set to true. Defaults to `false`.
  - `:stream_handler` - Handler that is called as the LLM returns messages.

  """
  @spec new!(opts :: keyword()) :: t()
  def new!(opts \\ []) do
    default = [verbose: false, stream_handler: nil]
    opts = Keyword.merge(default, opts)

    stream_handler = opts[:stream_handler]

    callback =
      if stream_handler != nil, do: stream_handler, else: get_default_stream_handler()

    # TODO: pull this default llm from a config
    wrapped_chain =
      %{
        llm: get_default_llm(),
        verbose: opts[:verbose]
      }
      |> LLMChain.new!()
      |> LLMChain.add_llm_callback(callback)

    %AgentChain{wrapped_chain: wrapped_chain, stream_handler: stream_handler}
  end

  @doc """
  Adds a JSON schema to the chain as the response format from the LLM.

  A message is added to the chain that tells the LLM to return the response
  content in JSON format. In the OpenAI case, the request will be made
  in [JSON Mode](https://platform.openai.com/docs/guides/text-generation/json-mode)
  """
  @spec ask_for_json_response(t(), map()) :: t()
  def ask_for_json_response(chain, schema) do
    # TODO: this is ugly and doesn't generalize well. Re-work this when we re-think LLM configuration
    inner_llm =
      case chain.wrapped_chain.llm do
        %ChatOpenAI{} -> %ChatOpenAI{chain.wrapped_chain.llm | json_response: true}
        _ -> chain.wrapped_chain.llm
      end

    wrapped_chain = %{chain.wrapped_chain | llm: inner_llm}

    # Add a message to the chain that requests the schema
    schema_json = Jason.encode!(schema)

    wrapped_chain =
      wrapped_chain
      |> LLMChain.add_message(
        PromptTemplate.to_message!(@json_format_template, %{
          schema: schema_json
        })
      )

    %AgentChain{chain | wrapped_chain: wrapped_chain, json_response_schema: schema}
  end

  @spec add_message(t(), LangChain.Message.t()) :: t()
  def add_message(chain, message) do
    wrapped_chain = chain.wrapped_chain |> LLMChain.add_message(message)

    %AgentChain{chain | wrapped_chain: wrapped_chain}
  end

  @spec add_messages(t(), [LangChain.Message.t()]) :: t()
  def add_messages(chain, messages) do
    wrapped_chain = chain.wrapped_chain |> LLMChain.add_messages(messages)

    %AgentChain{chain | wrapped_chain: wrapped_chain}
  end

  @spec add_tool(t(), LangChain.Function.t()) :: t()
  def add_tool(chain, tool) do
    wrapped_chain = chain.wrapped_chain |> LLMChain.add_tools([tool])

    %AgentChain{chain | wrapped_chain: wrapped_chain}
  end

  @doc """
  Run the AgentChain.

  If a `stream_handler` was specified when the AgentChain was created,
  it will be called as the LLM returns tokens.

  If a JSON response was requested with `ask_for_json_response`, the response
  will be validated against the schema and decoded to a struct.
  """
  @spec run(t()) :: {:error, binary() | list()} | {:ok, any(), LangChain.Message.t()}
  def run(%AgentChain{wrapped_chain: llm_chain} = chain) do
    with {:ok, _updated_llm, response} <-
           LLMChain.run(llm_chain),
         content <- process_raw_content(response.content),
         {:ok, content} <- parse_content_to_schema(content, chain.json_response_schema) do
      {:ok, content, response}
    end
  end

  defp process_raw_content(content) when is_list(content) do
    content
    |> Enum.map(fn part -> part.content end)
    |> Enum.join(" ")
  end

  defp process_raw_content(content) do
    content
  end

  defp parse_content_to_schema(content, nil) do
    {:ok, content}
  end

  defp parse_content_to_schema(content, schema) do
    # Strip Gemini's markdown
    content =
      content |> String.replace_leading("```json", "") |> String.replace_trailing("```", "")

    with {:ok, parsed_content} <- Jason.decode(content),
         :ok <- ExJsonSchema.Validator.validate(schema, parsed_content) do
      {:ok, parsed_content}
    end
  end

  defp get_default_llm() do
    model_provider = Application.fetch_env!(:magus, :model_provider)

    case model_provider do
      "gemini_ai" -> get_default_gemini_llm()
      "openai" -> get_default_openai_llm()
    end
  end

  def get_default_gemini_llm() do
    gemini_key = Application.fetch_env!(:magus, :gemini_key)
    gemini_model = Application.get_env(:magus, :gemini_model) || @default_gemini_model

    ChatGoogleAI.new!(%{
      endpoint: "https://generativelanguage.googleapis.com",
      model: gemini_model,
      api_key: gemini_key,
      stream: true
    })
  end

  defp get_default_openai_llm() do
    openai_key = Application.fetch_env!(:magus, :openai_key)
    openai_model = Application.get_env(:magus, :openai_model) || @default_openai_model

    ChatOpenAI.new!(%{model: openai_model, api_key: openai_key, stream: true})
  end

  defp get_default_stream_handler() do
    %{
      on_llm_new_delta: fn _model, %MessageDelta{} = _data ->
        :ok
      end,
      on_message_processed: fn _chain, %Message{} = _data ->
        :ok
      end
    }
  end
end
