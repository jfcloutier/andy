defmodule Andy.Utils do

  @moduledoc "Utility functions"

  alias Andy.PubSub
  require Logger

  @ttl 10_000
  @brickpi_port_pattern ~r/spi0.1:(.+)/

  def listen_to_events(pid, module) do
    spawn(
      fn ->
        Process.sleep(1000)
        Agent.cast(
          pid,
          fn (state) ->
            PubSub.register(module)
            state
          end
        )
      end
    )
  end

  def timeout() do
    10000
  end

  def tick_interval() do
    Application.fetch_env!(:andy, :tick_interval)
  end

  def max_percept_age() do
    Application.fetch_env!(:andy, :max_percept_age)
  end

  def max_motive_age() do
    Application.fetch_env!(:andy, :max_motive_age)
  end

  def max_intent_age() do
    Application.fetch_env!(:andy, :max_intent_age)
  end

  def strong_intent_factor() do
    Application.fetch_env!(:andy, :strong_intent_factor)
  end

  def max_beacon_channels() do
    Application.fetch_env!(:andy, :max_beacon_channels)
  end

  def very_fast_rps() do
    Application.fetch_env!(:andy, :very_fast_rps)
  end

  def fast_rps() do
    Application.fetch_env!(:andy, :fast_rps)
  end

  def normal_rps() do
    Application.fetch_env!(:andy, :normal_rps)
  end

  def slow_rps() do
    Application.fetch_env!(:andy, :slow_rps)
  end

  def very_slow_rps() do
    Application.fetch_env!(:andy, :very_slow_rps)
  end

  def default_ttl(kind) do
    Application.get_env(:andy, :ttl, [])
    |> Keyword.get(kind, @ttl)
  end

  @doc "The time now in msecs"
  def now() do
    div(:os.system_time(), 1_000_000)
  end

  @doc "Supported time units"
  def units() do
    [:msecs, :secs, :mins, :hours]
  end

  @doc "Convert a duration to msecs"
  def convert_to_msecs(nil), do: nil
  def convert_to_msecs({ count, unit }) do
    case unit do
      :msecs -> count
      :secs -> count * 1000
      :mins -> count * 1000 * 60
      :hours -> count * 1000 * 60 * 60
    end
  end

  def system_dispatch(fn_name, args) do
    apply(Andy.system(), fn_name, args)
  end

  def platform_dispatch(fn_name) do
    platform_dispatch(fn_name, [])
  end

  def platform_dispatch(fn_name, args) do
    apply(Andy.platform(), fn_name, args)
  end

  def profile_dispatch(fn_name) do
    profile_dispatch(fn_name, [])
  end

  def profile_dispatch(fn_name, args) do
    apply(Andy.profile(), fn_name, args)
  end

  def get_voice() do
    platform_dispatch(:voice)
  end

  def pg2_group() do
    get_andy_env("ANDY_COMMUNITY") || "lego"
  end

  def get_andy_env(variable) do
    get_andy_env(variable, nil)
  end

  def get_andy_env(variable, default_value) do
    Map.get(extract_plain_env_arguments(), variable) || System.get_env(variable) || default_value
  end

  def time_secs() do
    System.os_time()
    |> div(1_000_000_000)
  end

  def choose_one(choices) do
    [choice] = Enum.take_random(choices, 1)
    choice
  end

  def as_percept_about(percept_specs) when is_map(percept_specs) do
    percept_specs
  end

  def as_percept_about({ class, type, sense } = _percept_specs) do
    %{
      class: class,
      port: :any,
      type: type,
      sense: sense
    }
  end

  def as_percept_about({ class, port, type, sense } = _percept_specs) do
    %{
      class: class,
      port: port,
      type: type,
      sense: sense
    }
  end

  def translate_port(port_name) do
    case Andy.system() do
      "brickpi" ->
        case Regex.run(@brickpi_port_pattern, port_name) do
          nil ->
            port_name
          [_, name] ->
            case name do
              "MA" -> "outA"
              "MB" -> "outB"
              "MC" -> "outC"
              "MD" -> "outD"
              "S1" -> "in1"
              "S2" -> "in2"
              "S3" -> "in3"
              "S4" -> "in4"
            end
        end
      _other ->
        port_name
    end
  end

  ### PRIVATE

  defp extract_plain_env_arguments() do
    :init.get_plain_arguments()
    |> Enum.map(&("#{&1}"))
    |> Enum.filter(&(Regex.match?(~r/\w+=\w+/, &1)))
    |> Enum.reduce(
         %{ },
         fn (arg, acc) ->
           case Regex.named_captures(~r/(?<var>\w+)=(?<val>\w+)/, arg) do
             %{ "var" => var, "val" => val } ->
               Map.put(acc, var, val)
             nil ->
               acc
           end
         end
       )
  end

end
