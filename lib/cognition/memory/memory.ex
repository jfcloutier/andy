defmodule Andy.Memory do
  @moduledoc "The memory of percepts"

  alias Andy.{ Percept, Intent, Belief, PubSub }
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
    {:ok, pid} = Agent.start_link(
      fn () ->
        forgetting_pid = spawn_link(fn () -> forget()  end)
        Process.register(forgetting_pid, :forgetting)
        %{ percepts: %{ }, intents: %{ }, beliefs: %{ } }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  @doc "Remember a percept or intent"
  def store(something) do
    Agent.cast(
      @name,
      fn (state) -> store(something, state) end
    )
  end

  @doc "Recall all matching, unexpired percepts in a time window until now, latest to oldest"
  def recall_percepts_since(about, { :past_secs, secs }) do
    Agent.get(
      @name,
      fn (state) ->
        percepts_since(
          about,
          secs,
          state
        )
      end
    )
  end

  @doc "Recall latest unexpired, matching percept, if any"
  def recall_percepts_since(about, :now) do
    case recall_percepts_since(about, { :past_secs, 1 }) do
      [percept | _] ->
        [percept]
      [] ->
        []
    end
  end


  @doc "Recall the history of a named intent, within a time window until now"
  def recall_intents_since(name, { :past_secs, secs }) do
    Agent.get(
      @name,
      fn (state) ->
        intents_since(name, secs, state)
      end
    )
  end

  ### Cognitive Agent behaviour

   def handle_event({ :perceived, percept }, state) do
    if not percept.transient do
      store(percept, state)
    end
    state
  end

  # Intends are memorized only when realized by actuators
  # {:intended, intent} events are ignored
  def handle_event({ :realized, _actuator_name, intent }, state) do
    store(intent, state)
  end

  def handle_event({ :believed, belief }, state) do
    store(belief, state)
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

  defp store(%Percept{ about: about } = percept, state) do
    key = about.sense
    percepts = Map.get(state.percepts, key, [])
    new_percepts = update_percepts(percept, percepts)
    PubSub.notify_percept_memorized(percept)
    %{ state | percepts: Map.put(state.percepts, key, new_percepts) }
  end

  defp store(%Intent{ } = intent, state) do
    intents = Map.get(state.intents, intent.about, [])
    new_intents = update_intents(intent, intents)
    PubSub.notify_intent_memorized(intent)
    %{ state | intents: Map.put(state.intents, intent.about, new_intents) }
  end

  defp store(%Belief{ } = belief, %{ beliefs: beliefs } = state) do
    PubSub.notify_belief_memorized(belief)
    %{ state | beliefs: Map.put(beliefs, belief.model_name, belief) }
  end

  defp update_percepts(percept, []) do
    [percept]
  end

  defp update_percepts(percept, [previous | others]) do
    if not change_felt?(percept, previous) do
      extended_percept = %Percept{ previous | until: percept.since }
      [extended_percept | others]
    else
      [percept, previous | others]
    end
  end

  defp update_intents(intent, []) do
    [intent]
  end

  defp update_intents(intent, intents) do
    [intent | intents]
  end


  defp percepts_since(about, secs, state) do
    msecs = now()
    Enum.take_while(
      Map.get(state.percepts, about.sense, []),
      fn (percept) ->
        secs == nil or percept.until > (msecs - (secs * 1000))
      end
    )
    |> Enum.filter(&(Percept.about_match?(&1.about, about)))
  end

  defp intents_since(name, secs, state) do
    msecs = now()
    Enum.take_while(
      Map.get(state.intents, name, []),
      fn (intent) ->
        secs == nil or intent.since > (msecs - (secs * 1000))
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
