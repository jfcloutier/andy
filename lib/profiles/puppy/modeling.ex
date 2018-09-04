defmodule Andy.Puppy.Modeling do
  @moduledoc "The generative models for a puppy profile"

  alias Andy.{ GenerativeModel, Prediction, Action, Memory }
  import Andy.Utils, only: [choose_one: 1, as_percept_about: 1]
  require Logger

  @low_light 1
  @us_near 15 # 15 cm

  def generative_models() do
    [
      # Hyper-prior

      #THRIVING

      generative_model(
        name: :thriving,
        hypothesis: "The puppy is safe, has eaten recently, and can move about",
        predictions: [
          # safe, sated and free are sibling models
          prediction(
            name: :puppy_is_safe,
            believed: { :is, :safe },
            precision: :high,
            # try this first (of course it won't fulfil the prediction of believing that one is safe)
            fulfillments: [
              { :actions, [say_once("I am scared")] }
            ],
            when_fulfilled: [say("I am ok now")]
          ),
          prediction(
            name: :puppy_is_sated,
            believed: { :is, :sated },
            precision: :medium,
            fulfillments: [
              { :actions, [say_once("I am hungry")] }
            ],
            when_fulfilled: [say("I am full")]
          ),
          prediction(
            name: :puppy_is_free,
            believed: { :is, :free },
            precision: :low,
            fulfillments: [
              { :actions, [say_once("I'm stuck")] }
            ],
            when_fulfilled: [say("I'm free")]
          )
        ],
        # Let activated sub-models dictate priority
        priority: :high,
        hyper_prior?: true
      ),

      # SAFE

      generative_model(
        name: :safe,
        hypothesis: "The puppy is safe",
        predictions: [
          prediction(
            name: :puppy_not_bumping,
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [
              { :actions, [backoff(:fast), backoff(:fast), turn()] },
              { :actions, [backoff(:fast), turn()] },
              { :actions, [turn(), backoff(:fast)] },
              { :actions, [backoff(:fast), turn(), backoff(:fast), turn()] },
            ]
          ),
          prediction(
            name: :puppy_not_about_to_collide,
            believed: { :not, :about_to_collide },
            precision: :high,
            fulfillments: [
              { :actions, [turn()] },
              { :actions, [backoff(:fast)] },
              { :actions, [backoff(:fast), turn()] }
            ]
          ),
          prediction(
            name: :puppy_is_in_the_light,
            believed: { :is, :in_the_light },
            precision: :high,
            fulfill_when: [:puppy_not_bumping],
            fulfillments: [
              { :actions, [say_once("It's too dark")] }
            ]
          )
        ],
        priority: :high
      ),

      # In a well-light area

      generative_model(
        name: :in_the_light,
        hypothesis: "The puppy is in a well-light area",
        predictions: [
          prediction(
            name: :puppy_in_high_ambient_light,
            perceived: [{ { :sensor, :color, :ambient }, { :gt, @low_light }, { :past_secs, 3 } }],
            precision: :medium,
            fulfillments: [
              { :model, :getting_lighter }
            ]
          )
        ],
        priority: :medium
      ),

      # It's getting lighter

      generative_model(
        name: :getting_lighter,
        hypothesis: "The puppy is in a better-lit area",
        predictions: [
          prediction(
            name: :puppy_in_increasingly_lit_area,
            perceived: [{ { :sensor, :color, :ambient }, :ascending, { :past_secs, 5 } }],
            precision: :medium,
            fulfillments: [
              { :actions, [turn(), forward()] }
            ],
            when_fulfilled: [forward()]
          )
        ],
        priority: :medium
      ),

      # Recently got bumped while in the dark
      generative_model(
        name: :bumped_in_the_dark,
        hypothesis: "The puppy bumped into something in the dark",
        predictions: [
          prediction(
            name: :puppy_touched_in_low_light,
            perceived: [
              { { :sensor, :touch, :touch }, { :eq, :pressed }, :now },
              { { :sensor, :color, :ambient }, { :lt, @low_light }, :now }
            ],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: []
          )
        ],
        priority: :high
      ),
      # About to collide
      generative_model(
        name: :about_to_collide,
        hypothesis: "The puppy is about to collide",
        predictions: [
          prediction(
            name: :puppy_close_to_obstacle,
            perceived: [
              { { :sensor, :ultrasonic, :distance }, { :lt, @us_near }, { :past_secs, 2 } },
              { { :sensor, :ultrasonic, :distance }, :descending, { :past_secs, 5 } }
            ],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: []
          )
        ],
        priority: :high
      ),

      # SATED

      generative_model(
        name: :sated,
        hypothesis: "The puppy ate enough recently",
        predictions: [
          prediction(
            name: :puppy_recently_ate,
            #            perceived: [{ { :sensor, :timer, :time_elapsed }, { :gt, :count, 30 }, :now }],
            actuated: [{ :eating, { :sum, :quantity, 200 }, { :past_secs, 30 } }],
            precision: :medium,
            fulfillments: [
              { :model, :feeding }
            ],
            true_by_default?: false,
            time_sensitive?: true
          )
        ],
        priority: :medium
      ),

      generative_model(
        name: :feeding,
        hypothesis: "The puppy is feeding",
        predictions: [
          prediction(
            name: :puppy_on_food,
            perceived: [{ { :sensor, :color, :color }, { :eq, :blue }, { :past_secs, 3 } }],
            precision: :high,
            fulfillments: [
              { :model, :getting_closer_to_food }
            ],
            when_fulfilled: [eat({ :sensor, :color, :ambient }), say("nom de nom de nom")]
          )
        ],
        priority: :medium
      ),

      generative_model(
        name: :getting_closer_to_food,
        hypothesis: "The puppy detects food",
        predictions: [
          prediction(
            name: :puppy_smells_food,
            perceived: [
              { { :sensor, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 25 }, { :past_secs, 2 } }
            ],
            precision: :medium, # because not entirely reliable
            fulfillments: [
              { :actions, [forward()] },
              { :actions, [turn()] },
              { :actions, [backoff()] }
            ],
            when_fulfilled: [say("I smell food")]
          ),
          prediction(
            name: :puppy_faces_food,
            perceived: [{ { :sensor, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 5 }, :now }],
            precision: :medium,
            fulfill_when: [:puppy_smells_food],
            fulfillments: [
              { :actions, [turn_toward({ :sensor, :infrared, { :beacon_heading, 1 } })] }
            ]
          ),
          prediction(
            name: :puppy_approaches_food,
            perceived: [{ { :sensor, :infrared, { :beacon_distance, 1 } }, :descending, { :past_secs, 2 } }],
            precision: :medium,
            fulfill_when: [:puppy_faces_food],
            fulfillments: [
              { :actions, [approach({ :sensor, :infrared, { :beacon_distance, 1 } })] }
            ]
          )
        ],
        priority: :high
      ),

      # FREE
      generative_model(
        name: :free,
        hypothesis: "The puppy is free to move about",
        predictions: [
          prediction(
            name: :puppy_unobstructed,
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [
              { :actions, [backoff(), turn()] },
              { :actions, [backoff(), turn(), turn()] },
              { :actions, [backoff()] }
            ]
          ),
          prediction(
            name: :puppy_has_clear_path,
            believed: { :not, :approaching_obstacle },
            precision: :medium,
            fulfill_when: [:puppy_unobstructed],
            fulfillments: [
              { :actions, [avoid({ :sensor, :ultrasonic, :distance })] }
            ]
          ),
          prediction(
            name: :puppy_is_moving,
            actuated: [{ :go_forward, { :times, 10 }, { :past_secs, 10 } }],
            precision: :medium,
            fulfill_when: [:puppy_has_clear_path],
            fulfillments: [
              { :actions, [move()] }
            ],
            time_sensitive?: true
          ),
        ],
        priority: :low
      ),
      # Recently got bumped
      generative_model(
        name: :bumped,
        hypothesis: "The puppy bumped into something",
        predictions: [
          prediction(
            name: :puppy_recently_touched,
            perceived: [{ { :sensor, :touch, :touch }, { :eq, :pressed }, :now }],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: [],
            when_fulfilled: [say("Ouch!")]
          )
        ],
        priority: :high
      ),

      # Approaching an obstacle
      generative_model(
        name: :approaching_obstacle,
        hypothesis: "The puppy is approaching an obstacle",
        predictions: [
          prediction(
            name: :puppy_approaching_obstacle,
            perceived: [
              { { :sensor, :ultrasonic, :distance }, { :lt, 30 }, :now },
              { { :sensor, :ultrasonic, :distance }, :descending, { :past_secs, 5 } }
            ],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: [],
            when_fulfilled: [say("Uh oh!")]
          )
        ],
        priority: :high
      ),

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

  defp move(speed \\ :normal) do
    fn ->
      Logger.info("Action move at #{speed} speed")
      random = choose_one(1..4)
      cond do
        random in 1..2 ->
          Action.new(
            intent_name: :go_forward,
            intent_value: %{
              speed: speed,
              time: 1
            }
          )
        random == 3 ->
          Action.new(
            intent_name: choose_one([:turn_right, :turn_left]),
            intent_value: choose_one(1..3)
            # 1 to 3 secs
          )
        true ->
          Action.new(
            intent_name: :go_backward,
            intent_value: %{
              speed: speed,
              time: 1
            }
          )
      end
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
      direction = if heading < 0, do: :turn_right, else: :turn_left
      how_much = cond do
        heading == 0 ->
          0
        abs(heading) > 20 ->
          1
        abs(heading) > 10 ->
          0.25
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

  defp avoid(distance_percept_specs) do
    fn ->
      distance = Memory.recall_value_of_latest_percept(as_percept_about(distance_percept_specs)) || 0
      Logger.info("Action avoid from distance #{distance}")
      seconds = cond do
        distance < 5 ->
          3
        distance < 10 ->
          2
        distance < 20 ->
          1
        distance < 30 ->
          0.5
        true ->
          0
      end
      Action.new(
        intent_name: choose_one([:turn_right, :turn_left]),
        intent_value: seconds
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

  ### Utils

  defp generative_model(keywords) do
    GenerativeModel.new(keywords)
  end

  defp prediction(keywords) do
    Prediction.new(keywords)
  end

end