defmodule Andy.Puppy.Modeling do
  @moduledoc "The generative models for a puppy profile"

  alias Andy.{ GenerativeModel, Prediction, Action, Memory }
  import Andy.Utils, only: [choose_one: 1, as_percept_about: 1]

  def generative_models() do
    [
      # Hyper-prior

      #THRIVING

      generative_model(
        name: :thriving,
        description: "The puppy is safe, has eaten recently, and can move about",
        predictions: [
          # safe, sated and free are sinling models
          prediction(
            name: :puppy_is_safe,
            believed: { :is, :safe },
            precision: :high,
            # try this first (of course it won't fulfil the prediction of believing that one is safe)
            fulfillments: [
              { :actions, [say_once("I am scared!"), turn_led(:red, :on)] }
            ],
            when_fulfilled: [say_once("I am ok now"), turn_led(:red, :off)]
          ),
          prediction(
            name: :puppy_is_sated,
            believed: { :is, :sated },
            precision: :medium,
            fulfillments: [
              { :actions, [say_once("I am hungry!"), turn_led(:orange, :on)] }
            ],
            when_fulfilled: [turn_led(:orange, :off)]
          ),
          prediction(
            name: :puppy_is_free,
            believed: { :is, :free },
            precision: :low,
            fulfillments: [
              { :actions, [say_once("Freedom!"), turn_led(:all, :off)] }
            ],
            when_fulfilled: [turn_led(:green, :on)]
          )
        ],
        # Let activated sub-models dictate priority
        priority: :high,
        hyper_prior?: true
      ),

      # SAFE

      generative_model(
        name: :safe,
        description: "The puppy is safe",
        predictions: [
          prediction(
            name: :puppy_not_bumped_in_the_dark,
            believed: { :not, :bumped_in_the_dark },
            precision: :high,
            fulfillments: [
              { :actions, [say_once("What was that?"), backoff(), turn(), turn(), backoff()] },
              { :actions, [backoff(), turn()] }
            ]
          ),
          prediction(
            name: :puppy_not_about_to_collide,
            believed: { :not, :about_to_collide },
            precision: :high,
            fulfillments: [
              { :actions, [say_once("Uh oh!"), turn()] }
            ]
          ),
          prediction(
            name: :puppy_is_in_the_light,
            believed: { :is, :in_the_light },
            precision: :high,
            fulfill_when: [:puppy_not_bumped_in_the_dark],
            fulfillments: [
              { :actions, [say_once("It's too dark")] }
            ]
          )
        ],
        # Whereas the priorities for :free and :sated would be :medium
        priority: :high
      ),

      # Action models
      # In a well-light area
      generative_model(
        name: :in_the_light,
        description: "The puppy is in a well-light area",
        predictions: [
          prediction(
            name: :puppy_in_well_lit_area,
            perceived: [{ { :sensor, :any, :color, :ambient }, { :gt, 50 }, { :past_secs, 2 } }],
            precision: :high,
            fulfillments: [
              { :model, :getting_lighter }
            ]
          )
        ],
        priority: :high
      ),
      # It's getting lighter
      generative_model(
        name: :getting_lighter,
        description: "The puppy is in a better-lit area",
        predictions: [
          prediction(
            name: :puppy_in_better_lit_area,
            perceived: [{ { :sensor, :any, :color, :ambient }, :ascending, { :past_secs, 5 } }],
            precision: :low,
            fulfillments: [
              { :actions, [forward(), turn()] },
              { :actions, [turn(), backoff()] }
            ]
          )
        ],
        priority: :high
      ),
      # Recently got bumped while in the dark
      generative_model(
        name: :bumped_in_the_dark,
        description: "The puppy bumped into something in the dark",
        predictions: [
          prediction(
            name: :puppy_touched_in_low_light,
            perceived: [
              { { :sensor, :any, :touch, :touch }, { :eq, :touched }, :now },
              { { :sensor, :any, :color, :ambient }, { :lt, 10 }, :now }
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
        description: "The puppy is about to collide",
        predictions: [
          prediction(
            name: :puppy_close_to_obstacle,
            perceived: [
              { { :sensor, :any, :ultrasonic, :distance }, { :lt, 10 }, :now },
              { { :sensor, :any, :ultrasonic, :distance }, :descending, { :past_secs, 5 } }
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
        description: "The puppy ate enough recently",
        predictions: [
          prediction(
            name: :puppy_recently_ate,
            actuated: [{ :eating, { :sum, :quantity, 10 }, { :past_secs, 30 } }],
            precision: :medium,
            fulfillments: [
              { :model, :feeding }
            ]
          )
        ],
        priority: :medium
      ),

      generative_model(
        name: :feeding,
        description: "The puppy is feeding",
        predictions: [
          prediction(
            name: :puppy_on_food,
            perceived: [{ { :sensor, :any, :color, :color }, { :eq, :blue }, :now }],
            precision: :high,
            fulfillments: [
              { :model, :getting_closer_to_food }
            ]
          ),
          prediction(
            name: :puppy_eating,
            precision: :high,
            fulfill_when: [:puppy_on_food],
            fulfillments: [
              { :actions, [say_once("nom de nom de nom"), eat()] }
            ]
          )
        ],
        priority: :high
      ),

      generative_model(
        name: :getting_closer_to_food,
        description: "The puppy is getting closer to food",
        predictions: [
          prediction(
            name: :puppy_smells_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_distance, 1 } }, { :lt, 30 }, { :past_secs, 5 } }],
            precision: :high,
            fulfillments: [
              { :actions, [forward(), turn()] },
              { :actions, [turn()] }
            ]
          ),
          prediction(
            name: :puppy_faces_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 5 }, :now }],
            precision: :high,
            fulfill_when: [:puppy_smells_food],
            fulfillments: [
              { :actions, [turn_toward({ :sensor, :any, :infrared, { :beacon_heading, 1 } })] }
            ]
          ),
          prediction(
            name: :puppy_approaches_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_distance, 1 } }, :descending, { :past_secs, 2 } }],
            precision: :high,
            fulfill_when: [:puppy_faces_food],
            fulfillments: [
              { :actions, [approach({ :sensor, :any, :infrared, { :beacon_distance, 1 } })] }
            ]
          )
        ],
        priority: :high
      ),

      # FREE
      generative_model(
        name: :free,
        description: "The puppy is free to move about",
        predictions: [
          prediction(
            name: :puppy_unobstructed,
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [
              { :actions, [say_once("Huh hoh!"), backoff(), turn()] }
            ]
          ),
          prediction(
            name: :puppy_has_clear_path,
            believed: { :not, :approaching_obstacle },
            precision: :medium,
            fulfill_when: [:puppy_unobstructed],
            fulfillments: [
              { :actions, [avoid({ :sensor, :any, :ultrasonic, :distance })] }
            ]
          ),
          prediction(
            name: :puppy_is_moving,
            actuated: [{ :go_forward, { :times, 10 }, { :past_secs, 30 } }],
            precision: :medium,
            fulfill_when: [:puppy_has_clear_path],
            fulfillments: [
              { :actions, [move()] }
            ]
          ),
        ],
        priority: :low
      ),
      # Recently got bumped
      generative_model(
        name: :bumped,
        description: "The puppy bumped into something",
        predictions: [
          prediction(
            name: :puppy_recently_touched,
            perceived: [{ { :sensor, :any, :touch, :touch }, { :eq, :touched }, :now }],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: []
          )
        ],
        priority: :high
      ),

      # Approaching an obstacle
      generative_model(
        name: :approaching_obstacle,
        description: "The puppy is approaching an obstacle",
        predictions: [
          prediction(
            name: :puppy_approaching_obstacle,
            perceived: [
              { { :sensor, :any, :ultrasonic, :distance }, { :lt, 50 }, :now },
              { { :sensor, :any, :ultrasonic, :distance }, :descending, { :past_secs, 10 } }
            ],
            precision: :high,
            # We never want to fulfill this prediction
            fulfillments: []
          )
        ],
        priority: :high
      ),

    ]
    # TODO
  end

  ### PRIVATE

  defp forward() do
    fn ->
      Action.new(
        intent_name: :go_forward,
        intent_value: %{
          speed: :fast,
          time: 1
        }
      )
    end
  end

  defp backoff() do
    fn ->
      Action.new(
        intent_name: :go_backward,
        intent_value: %{
          speed: :fast,
          time: 1
        }
      )
    end
  end

  defp move() do
    fn ->
      random = choose_one(1..4)
      cond do
        random in 1..2 ->
          Action.new(
            intent_name: :go_forward,
            intent_value: %{
              speed: :fast,
              time: 1
            }
          )
        random == 3 ->
          Action.new(
            intent_name: choose_one([:turn_right, :turn_left]),
            intent_value: choose_one(1..3)
          )
        true ->
          Action.new(
            intent_name: :go_backward,
            intent_value: %{
              speed: :fast,
              time: 1
            }
          )
      end
    end
  end

  defp turn() do
    fn ->
      Action.new(
        intent_name: choose_one([:turn_right, :turn_left]),
        intent_value: choose_one(1..10) / 10
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
          3
        abs(heading) > 10 ->
          2
        true ->
          1
      end
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
        distance == 0 ->
          0
        distance > 50 ->
          :fast
        distance > 20 ->
          :medium
        true ->
          :slow
      end
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
      how_much = cond do
        distance < 5 ->
          3
        distance < 15 ->
          2
        true ->
          1
      end
      Action.new(
        intent_name: choose_one([:turn_right, :turn_left]),
        intent_value: how_much
      )
    end
  end

  defp say_once(words) do
    fn ->
      Action.new(
        intent_name: :say,
        intent_value: words,
        once?: true
      )
    end
  end

  defp eat() do
    fn ->
      Action.new(
        intent_name: :eat
      )
    end
  end

  defp turn_led(color, on_or_off) do
    intent_name = case color do
      :green -> :green_lights
      :orange -> :orange_lights
      :red -> :red_lights
      :all -> :all_lights
    end
    fn ->
      Action.new(
        intent_name: intent_name,
        intent_value: on_or_off
      )
    end
  end

  ### Utils

  defp generative_model(keywords) do
    GenerativeModel.new(keywords)
  end

  defp prediction(keywords) do
    Prediction.new(keywords)
  end

end