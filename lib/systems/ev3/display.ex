defmodule Andy.Ev3.Display do
	# Modified from code by Frank Hunleth
	
  use GenServer
  alias ExNcurses, as: N
	alias Andy.Ev3.Brick
	require Logger

	@refresh_interval 2000 # Every 2 seconds
	@name __MODULE__

  def start_link() do
    GenServer.start_link(@name, [], [name: @name])
  end

  def init(_) do
    N.n_begin()
    N.clear()
    N.refresh()
    :timer.send_interval(@refresh_interval, :refresh)
    {:ok, "Hello world!"}
  end

  def terminate(_reason, _state) do
    N.endwin()
  end

	def show_banner(banner) do
		GenServer.cast(@name, {:banner, banner})
	end

	def handle_cast({:banner, banner}, _state) do
		Logger.info("Banner: #{banner}")
		{:noreply, banner}
	end

  def handle_info(:refresh, state) do
    N.clear()
    N.mvprintw(2, 1, "#{inspect state}")
    N.mvprintw(4, 1, "IP: #{Brick.ipaddr()}")
    N.mvprintw(6, 1, "Node: #{node()}")
		N.mvprintw(8, 1, "Peers: #{inspect Node.list()}")
    N.mvprintw(10, 1, "Battery: #{battery_voltage()}V")
    N.mvprintw(12, 1, "Memory: #{meminfo()}")
    N.refresh()
    {:noreply, state}
  end

  defp battery_voltage() do
    case File.read("/sys/class/power_supply/legoev3-battery/voltage_now") do
      {:ok, microvolts_str} ->
        {microvolts, _} = Integer.parse(microvolts_str)
        Float.round(microvolts / 1000000, 1)
      _ ->
        0
    end
  end

  def meminfo() do
    {free_info, 0} = System.cmd("free", [])
    mem_line = free_info
      |> String.split("\n")  # split into lines
      |> Enum.at(1)          # the "Mem:" line is the second one
      |> String.split(" ")   # split out the fields
      |> Enum.filter(&(&1 != ""))
    {total, _} = Enum.at(mem_line, 1) |> Integer.parse
    {free, _}  = Enum.at(mem_line, 3) |> Integer.parse
    "#{free} KB free / #{total} KB"
  end
end
