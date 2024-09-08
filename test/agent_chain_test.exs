defmodule Magus.AgentChainTest do
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias Magus.AgentChain

  import LangChain.Utils.ApiOverride

  use ExUnit.Case

  test "if json is requested, it should parse and validate proper llm responses", %{} do
    json_schema = %{
      "type" => "object",
      "properties" => %{
        "title" => %{
          "type" => "string",
          "description" => "Title"
        },
        "characters" => %{
          "type" => "array",
          "description" => "List of characters in the story",
          "items" => %{
            "type" => "string"
          }
        }
      },
      "required" => [
        "characters"
      ]
    }

    raw_json = "{\"title\": \"Formula 1\", \"characters\": [\"Lewis\", \"Max\"]}"

    fake_messages = [
      Message.new!(%{role: :assistant, content: raw_json, status: :complete})
    ]
    set_api_override({:ok, fake_messages})

    wrapped_chain =
      %{
        llm: ChatOpenAI.new!(%{temperature: 1, stream: false})
      }
      |> LLMChain.new!()

    chain = %AgentChain{
      wrapped_chain: wrapped_chain
    } |> AgentChain.ask_for_json_response(json_schema)

    {:ok, content, _response} = chain |> AgentChain.run()

    assert content["title"] == "Formula 1"
    assert content["characters"] == ["Lewis", "Max"]
  end

  test "if json is requested, it should error on json llm repsonses that don't conform to spec", %{} do
    json_schema = %{
      "type" => "object",
      "properties" => %{
        "title" => %{
          "type" => "string",
          "description" => "Title"
        },
        "characters" => %{
          "type" => "array",
          "description" => "List of characters in the story",
          "items" => %{
            "type" => "string"
          }
        }
      },
      "required" => [
        "characters"
      ]
    }

    # `racers` should be `characters` to be valid
    raw_json = "{\"title\": \"Formula 1\", \"racers\": [\"Lewis\", \"Max\"]}"

    fake_messages = [
      Message.new!(%{role: :assistant, content: raw_json, status: :complete})
    ]
    set_api_override({:ok, fake_messages})

    wrapped_chain =
      %{
        llm: ChatOpenAI.new!(%{})
      }
      |> LLMChain.new!()

    chain = %AgentChain{
      wrapped_chain: wrapped_chain
    } |> AgentChain.ask_for_json_response(json_schema)

    {:error, validation_errors} = chain |> AgentChain.run()
    assert validation_errors == [{"Required property characters was not present.", "#"}]
  end

  test "if json is requested, it should error on llm repsonses that aren't json", %{} do
    json_schema = %{
      "type" => "object",
      "properties" => %{
        "title" => %{
          "type" => "string",
          "description" => "Title"
        },
        "characters" => %{
          "type" => "array",
          "description" => "List of characters in the story",
          "items" => %{
            "type" => "string"
          }
        }
      },
      "required" => [
        "characters"
      ]
    }

    raw_content = "Lewis, Max"

    fake_messages = [
      Message.new!(%{role: :assistant, content: raw_content, status: :complete})
    ]
    set_api_override({:ok, fake_messages})

    wrapped_chain =
      %{
        llm: ChatOpenAI.new!(%{})
      }
      |> LLMChain.new!()

    chain = %AgentChain{
      wrapped_chain: wrapped_chain
    } |> AgentChain.ask_for_json_response(json_schema)

    {:error, error} = chain |> AgentChain.run()
    assert error == %Jason.DecodeError{position: 0, token: nil, data: "Lewis, Max"}
  end
end
