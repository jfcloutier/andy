defmodule Andy.Memory do
  @moduledoc "The memory of percepts"

  alias Andy.{ Percept, Intent, InternalCommunicator }
  import Andy.Utils
  require Logger

  @name __MODULE__
  @forget_pause 5000 # clear expired precepts every 10 secs
  @intent_ttl 30_000 # all intents are forgotten after 30 secs

  @behaviour Andy.CognitionAgentBehaviour

  ### API

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the memory server"
  def start_link() do
    Logger.info("Starting #{@name}")
    Agent.start_link(
      fn () ->
        pid = spawn_link(fn () -> forget()  end)
        Process.register(pid, :forgetting)
        register_internal()
        %{ percepts: %{ }, intents: %{ } }
      end,
      [name: @name]
    )
  end

  @doc "Remember a percept or intent"
  def store(something) do
    Agent.cast(
      @name,
      fn (state) -> store(something, state) end
    )
  end


  @doc "Return percepts memorized since window_width as %{percepts: [...], intents: [...]}"
  def since(window_width, senses: senses, intents: intent_names) do
    Agent.get(
      @name,
      fn (state) ->
        since(
          window_width,
          senses,
          intent_names,
          state
        )
      end
    )
  end

  @doc "Recall all percepts from any of given senses in a time window until now"
  def recall_percepts(senses, window_width) do
    Agent.get(
      @name,
      fn (state) ->
        recent_percepts(window_width, senses, state)
      end
    )
  end


  @doc "Recall the history of a named intent, within a time window until now"
  def recall_intents(name, window_width) do
    Agent.get(
      @name,
      fn (state) ->
        recent_intents(window_width, [name], state)
      end
    )
  end

  ### Cognitive Agent behaviour

  def register_internal() do
    InternalCommunicator.register(__MODULE__)
  end

  def handle_event({ :perceived, percept }, state) do
    if not percept.transient do
      store(percept)
    end
    state
  end

  # Intends are memorized only when realized by actuators
  # {:intended, intent} events are ignored
  def handle_event({ :realized, _actuator_name, intent }, state) do
    store(intent)
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # forget all expired percepts every second
  defp forget() do
    :timer.sleep(@forget_pause)
    Agent.update(@name, fn (state) -> forget_expired(state) end)
    forget()
  end

  defp store(%Percept{ } = percept, state) do
    key = Percept.sense(percept)
    percepts = Map.get(state.percepts, key, [])
    new_percepts = update_percepts(percept, percepts)
    %{ state | percepts: Map.put(state.percepts, key, new_percepts) }
  end

  defp store(%Intent{ } = intent, state) do
    intents = Map.get(state.intents, intent.about, [])
    new_intents = update_intents(intent, intents)
    %{ state | intents: Map.put(state.intents, intent.about, new_intents) }
  end

  defp since(window_width, senses, intent_names, state) do
    percepts = recent_percepts(window_width, senses, state)
    intents = recent_intents(window_width, intent_names, state)
    %{ percepts: percepts, intents: intents }
  end

  defp update_percepts(percept, []) do
    InternalCommunicator.notify_memorized(:new, percept)
    [percept]
  end

  defp update_percepts(percept, [previous | others]) do
    if not change_felt?(percept, previous) do
      extended_percept = %Percept{ previous | until: percept.since }
      InternalCommunicator.notify_memorized(:extended, extended_percept)
      [extended_percept | others]
    else
      InternalCommunicator.notify_memorized(:new, percept)
      [percept, previous | others]
    end
  end

  defp update_intents(intent, []) do
    InternalCommunicator.notify_memorized(:new, intent)
    [intent]
  end

  defp update_intents(intent, intents) do
    InternalCommunicator.notify_memorized(:new, intent)
    [intent | intents]
  end


  defp recent_percepts(window_width, senses, state) do
    msecs = now()
    Enum.reduce(
      senses,
      [],
      fn (sense, acc) ->
        percepts = Enum.take_while(
          Map.get(state.percepts, sense, []),
          fn (percept) ->
            window_width == nil or percept.until > (msecs - window_width)
          end
        )
        acc ++ percepts
      end
    )
  end

  defp recent_intents(window_width, names, state) do
    msecs = now()
    Enum.reduce(
      names,
      [],
      fn (name, acc) ->
        intents = Enum.take_while(
          Map.get(state.intents, name, []),
          fn (intent) ->
            window_width == nil or intent.since > (msecs - window_width)
          end
        )
        acc ++ intents
      end
    )
  end

  # Both percepts are assumed to be from the same sense, thus comparable
  defp change_felt?(percept, previous) do
    cond do
      percept.resolution == nil or previous.resolution == nil ->
        percept.value != previous.value
      not is_number(percept.value) or not is_number(previous.value) ->
        percept.value != previous.value
      true ->
        resolution = max(percept.resolution, previous.resolution)
        abs(percept.value - previous.value) >= resolution
    end
  end

  defp forget_expired(state) do
    forget_expired_percepts(state)
    |> forget_expired_intents()
  end

  defp forget_expired_percepts(state) do
    msecs = now()
    remembered = Enum.reduce(
      Map.keys(state.percepts),
      %{ },
      fn (sense, acc) ->
        unexpired = Enum.take_while(
          Map.get(state.percepts, sense),
          fn (percept) ->
            if percept.ttl == nil or (percept.until + percept.ttl) > msecs do
              true
            else
              # Logger.debug("Forgot #{inspect percept.about} = #{inspect percept.value} after #{div(msecs - percept.until, 1000)} secs")
              false
            end
          end
        )
        Map.put_new(acc, sense, unexpired)
      end
    )
    %{ state | percepts: remembered }
  end

  defp forget_expired_intents(state) do
    msecs = now()
    remembered = Enum.reduce(
      Map.keys(state.intents),
      %{ },
      fn (name, acc) ->
        case Map.get(state.intents, name, []) do
          [] -> Map.put_new(acc, name, [])
          intents ->
            expired = Enum.filter(intents, &((&1.since + @intent_ttl) < msecs))
            # Logger.debug("Forgot #{name} intents #{inspect expired}")
            Map.put(acc, name, intents -- expired)
        end
      end
    )
    %{ state | intents: remembered }
  end


end
