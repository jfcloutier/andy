defmodule Andy.Puppy.Profiling do
  @moduledoc "The conjectures for a puppy profile"

  alias Andy.{ Conjecture, Prediction, Action, Memory }
  import Andy.Utils, only: [choose_one: 1, as_percept_about: 1]
  require Logger

  @low_light 1
  @us_near 20 # cm

  def conjectures() do
    [
      # THRIVING

      conjecture(
        name: :thriving,
        hypothesis: "The puppy is safe, has eaten recently, and can move about",
        predictions: [
          prediction(
            name: :puppy_is_safe,
            believed: { :is, :safe },
            precision: :high,
            fulfill_by: { :doing, [say_once("I am scared")] },
            when_fulfilled: [say_without_repeating("I am ok now")]
          ),
          prediction(
            name: :puppy_is_sated,
            believed: { :is, :sated },
            precision: :medium,
            fulfill_by: { :doing, [say_once("I am hungry")] },
            when_fulfilled: [say_without_repeating("I am full"), backoff()]
          ),
          prediction(
            name: :puppy_is_free,
            believed: { :is, :free },
            precision: :low,
            when_fulfilled: [say_without_repeating("I'm free")]
          )
        ],
        priority: :high,
        hyper_prior?: true
      ),

      # SAFE

      conjecture(
        name: :safe,
        hypothesis: "The puppy is safe",
        predictions: [
          prediction(
            name: :puppy_not_bumping,
            believed: { :not, :bumped },
            precision: :high,
            fulfill_by:
              {
              :doing,
              %{
                pick: 2,
                from: [backoff(), turn(), forward()],
                allow_duplicates: true
              }
            }
          ),
          prediction(
            name: :puppy_not_about_to_bump,
            believed: { :not, :about_to_bump },
            precision: :high,
            fulfill_by:
              { :doing,
              %{
                pick: 2,
                from: [backoff(), turn(), forward()],
                allow_duplicates: true
              } }
          ),
          prediction(
            name: :puppy_is_in_the_light,
            believed: { :is, :in_the_light },
            precision: :high,
            fulfill_when: [:puppy_not_bumping, :puppy_not_about_to_bump],
            fulfill_by: { :doing, [say_once("It's too dark")] }
          )
        ],
        priority: :high
      ),

      # Just bumped into something

      conjecture(
        name: :bumped,
        hypothesis: "The puppy bumped into something",
        predictions: [
          prediction(
            name: :puppy_bumped,
            perceived: [{ { :sensor, :touch, :touch }, { :eq, :pressed }, :now }],
            precision: :high,
            when_fulfilled: [say("Ouch!")]
          )
        ],
        priority: :high
      ),

      # In a well-light area

      conjecture(
        name: :in_the_light,
        hypothesis: "The puppy is in a well-light area",
        predictions: [
          prediction(
            name: :puppy_in_high_ambient_light,
            perceived: [{ { :sensor, :color, :ambient }, { :gt, @low_light }, { :past_secs, 3 } }],
            precision: :medium,
            fulfill_by: { :believing_in, :getting_lighter }
          )
        ],
        priority: :medium
      ),

      # It's getting lighter

      conjecture(
        name: :getting_lighter,
        hypothesis: "The puppy is in a better-lit area",
        predictions: [
          prediction(
            name: :puppy_in_better_lit_area,
            perceived: [{ { :sensor, :color, :ambient }, :ascending, { :past_secs, 5 } }],
            precision: :medium,
            fulfill_by: { :doing,
              %{
                pick: 2,
                from: [backoff(), turn(), forward()],
                allow_duplicates: true
              } },
            when_fulfilled: [forward()]
          )
        ],
        priority: :medium
      ),

      # About to bump
      conjecture(
        name: :about_to_bump,
        hypothesis: "The puppy is about to bump",
        predictions: [
          prediction(
            name: :puppy_about_to_bump,
            perceived: [
              { { :sensor, :ultrasonic, :distance }, { :lt, @us_near }, { :past_secs, 2 } },
              { { :sensor, :ultrasonic, :distance }, :descending, { :past_secs, 5 } }
            ],
            precision: :medium
          )
        ],
        priority: :high
      ),

      # SATED

      conjecture(
        name: :sated,
        hypothesis: "The puppy ate enough recently",
        predictions: [
          prediction(
            name: :puppy_recently_ate,
            actuated: [{ :eat, { :times, 2 }, { :past_secs, 30 } }],
            precision: :medium,
            fulfill_by: { :believing_in, :feeding },
            true_by_default?: false,
            time_sensitive?: true
          )
        ],
        priority: :medium
      ),

      conjecture(
        name: :feeding,
        hypothesis: "The puppy is feeding",
        predictions: [
          prediction(
            name: :puppy_on_food,
            perceived: [{ { :sensor, :color, :color }, { :eq, :blue }, { :past_secs, 3 } }],
            precision: :high,
            fulfill_by: { :believing_in, :getting_closer_to_food },
            when_fulfilled: [eat({ :sensor, :color, :ambient }), say("nom de nom de nom")]
          )
        ],
        priority: :medium
      ),

      conjecture(
        name: :getting_closer_to_food,
        hypothesis: "The puppy detects food",
        predictions: [
          prediction(
            name: :puppy_smells_food,
            perceived: [
              { { :sensor, :infrared, { :beacon_distance, 1 } }, { :lt, 90 }, :now },
              { { :sensor, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 20 }, { :past_secs, 2 } }
            ],
            precision: :medium, # because not entirely reliable (sometimes fails to see beacon heading when right in front)
            fulfill_by: {
              :doing,
              %{
                pick: 2,
                from: [backoff(), turn(), forward()],
                allow_duplicates: true
              }
            },
            when_fulfilled: [say_without_repeating("I smell food")]
          ),
          prediction(
            name: :puppy_faces_food,
            perceived: [
              { { :sensor, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 5 }, :now }
            ],
            precision: :medium,
            fulfill_when: [:puppy_smells_food],
            fulfill_by: { :doing, [turn_toward({ :sensor, :infrared, { :beacon_heading, 1 } })] }
          ),
          prediction(
            name: :puppy_approaches_food,
            perceived: [{ { :sensor, :infrared, { :beacon_distance, 1 } }, :descending, { :past_secs, 2 } }],
            precision: :medium,
            fulfill_when: [:puppy_faces_food],
            fulfill_by: { :doing, [approach({ :sensor, :infrared, { :beacon_distance, 1 } })] }
          )
        ],
        priority: :high
      ),

      # FREE
      conjecture(
        name: :free,
        hypothesis: "The puppy is moving about",
        predictions: [
          prediction(
            name: :puppy_is_moving,
            actuated: [{ :go_forward, { :times, 10 }, { :past_secs, 10 } }],
            precision: :medium,
            fulfill_when: [:puppy_has_clear_path],
            fulfill_by:
              { :doing,
              %{
                pick: 2,
                from: [turn(), forward()],
                allow_duplicates: true
              } },
            time_sensitive?: true
          ),
        ],
        priority: :low
      )
    ]

  end

  ### PRIVATE

  defp forward(speed \\ :normal) do
    fn ->
      Logger.info("Action forward")
      Action.new(
        intent_name: :go_forward,
        intent_value: %{
          speed: speed,
          time: 2
        }
      )
    end
  end

  defp backoff(speed \\ :normal) do
    fn ->
      Logger.info("Action backoff")
      Action.new(
        intent_name: :go_backward,
        intent_value: %{
          speed: speed,
          time: 3
        }
      )
    end
  end

  defp turn() do
    fn ->
      Logger.info("Action turn")
      Action.new(
        intent_name: choose_one([:turn_right, :turn_left]),
        intent_value: 1
        # turn for 1 sec
      )
    end
  end

  defp turn_toward(heading_percept_specs) do
    fn ->
      heading = Memory.recall_value_of_latest_percept(heading_percept_specs) || 0
      direction = if heading < 0, do: :turn_left, else: :turn_right
      how_much = cond do
        heading == 0 ->
          0
        abs(heading) == 25 -> # don't really know where it is, so don't bother
          0
        abs(heading) > 20 ->
          0.5
        abs(heading) > 15 ->
          0.2
        true ->
          0.1
      end
      Logger.info("Action turn_toward heading #{heading}, direction #{direction} for #{how_much} secs")
      Action.new(
        intent_name: direction,
        intent_value: how_much
      )
    end
  end

  defp approach(distance_percept_specs) do
    fn ->
      distance = Memory.recall_value_of_latest_percept(as_percept_about(distance_percept_specs)) || 0
      speed = cond do
        # On top of it
        distance == 0 ->
          :zero
        # Don't know how far the beacon is. There might be no beacon at all.
        distance == 100 ->
          :zero
        # A meter or more
        distance > 50 ->
          :very_fast
        distance > 30 ->
          :fast
        distance > 20 ->
          :normal
        distance > 10 ->
          :slow
        true ->
          :very_slow
      end
      Logger.info("Action approach from distance #{distance} at speed #{speed} for 1 second")
      Action.new(
        intent_name: :go_forward,
        intent_value: %{
          speed: speed,
          time: 1
        }
      )
    end
  end

  defp say_once(words) do
    fn ->
      Logger.info("Action say_once #{words}")
      Action.new(
        intent_name: :say,
        intent_value: words,
        once?: true
      )
    end
  end

  defp say_without_repeating(words) do
    fn ->
      Logger.info("Action say_once #{words}")
      Action.new(
        intent_name: :say,
        intent_value: words,
        once?: true,
        allow_repeating?: false
      )
    end
  end


  defp say(words) do
    fn ->
      Logger.info("Action say #{words}")
      Action.new(
        intent_name: :say,
        intent_value: words,
        once?: false
      )
    end
  end

  defp eat(ambient_percept_specs) do
    fn ->
      ambient_level = Memory.recall_value_of_latest_percept(as_percept_about(ambient_percept_specs)) || 0
      Logger.info("Action eat in ambient light #{ambient_level}")
      Action.new(
        intent_name: :eat,
        intent_value: ambient_level
      )
    end
  end

  #  defp turn_led_once(on_or_off) do
  #    fn ->
  #      Action.new(
  #        intent_name: :blue_lights,
  #        intent_value: on_or_off,
  #        once?: true
  #      )
  #    end
  #  end
  #
  #
  #  defp turn_led(on_or_off) do
  #    fn ->
  #      Action.new(
  #        intent_name: :blue_lights,
  #        intent_value: on_or_off
  #      )
  #    end
  #  end

  #  defp avoid(distance_percept_specs) do
  #    fn ->
  #      distance = Memory.recall_value_of_latest_percept(as_percept_about(distance_percept_specs)) || 0
  #      Logger.info("Action avoid from distance #{distance}")
  #      seconds = cond do
  #        distance < 5 ->
  #          3
  #        distance < 10 ->
  #          2
  #        distance < 20 ->
  #          1
  #        distance < 30 ->
  #          0.5
  #        true ->
  #          0
  #      end
  #      Action.new(
  #        intent_name: choose_one([:turn_right, :turn_left]),
  #        intent_value: seconds
  #      )
  #    end
  #  end

  ### Utils

  defp conjecture(keywords) do
    Conjecture.new(keywords)
  end

  defp prediction(keywords) do
    Prediction.new(keywords)
  end

end