defmodule Andy.RESTCommunicator do
  @moduledoc "REST communicator used communicate via HTTP with other smart things"

  @behaviour Andy.Communicating

  alias Andy.PubSub
  require Logger
  use GenServer

  @name __MODULE__
  @timeout 20_000

  def start_link(_) do
    Logger.info("Starting #{@name}")
    GenServer.start_link(@name, [], name: @name)
  end

  @doc "Broadcast info to the community"
  def broadcast(_device, _info) do
    Logger.warn("Broadcast not implemented for #{@name}")
  end

  @doc "Send percept to a member of the parent community"
  def send_percept(_device, url, about, value) do
    GenServer.cast(@name, {:send_percept, url, about, value})
  end

  def send_hello(url) do
    GenServer.call(@name, {:hello, url}, @timeout)
  end

  def senses_awakened_by(_sense) do
    []
  end

  def port() do
    Andy.rest_source()
  end

  ####

  def remote_percept(percept) do
    # 		Logger.info("Received remote percept #{inspect(percept.about)}=#{inspect(percept.value)} from #{inspect(percept.source)}")
    PubSub.notify_perceived(percept)
  end

  ### CALLBACKS

  def init([]) do
    {:ok, []}
  end

  def handle_call({:hello, partial_url}, _from, state) do
    full_url = "http://#{partial_url}/api/marvin/hello"
    Logger.info("Saying hello to #{full_url}")

    case HTTPoison.get(full_url, headers(), options()) do
      {:error, reason} ->
        Logger.warn("Failed to reach #{full_url}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}

      {:ok, _} ->
        Logger.info("Hello answered")
        {:reply, :ok, state}
    end
  end

  def handle_cast({:send_percept, partial_url, about, value}, state) do
    full_url = "#{partial_url}/api/marvin/percept"

    body =
      %{
        percept: %{
          about: "#{inspect(about)}",
          value: %{
            is: "#{inspect(value)}",
            from: %{
              community_name: Andy.community_name(),
              member_name: Andy.member_name(),
              member_url: Andy.rest_source(),
              id_channel: Andy.id_channel()
            }
          }
        }
      }
      |> Poison.encode!()

    # 		Logger.info("Posting to #{full_url} with #{inspect body}")
    case HTTPoison.post(full_url, body, headers(), options()) do
      {:ok, _response} ->
        Logger.info("Sent percept :report #{inspect(value)} to #{full_url}")

      {:error, reason} ->
        Logger.warn(
          "FAILED to send percept #{inspect(about)} #{inspect(value)} to #{full_url} - #{
            inspect(reason)
          }"
        )
    end

    {:noreply, state}
  end

  defp headers() do
    [{"Content-Type", "application/json"}]
  end

  def options() do
    [connect_timeout: @timeout, recv_timeout: @timeout, timeout: @timeout]
  end
end
