defmodule Andy.Puppy.Modeling do
  @moduledoc "The generative models for a puppy profile"

  alias Andy.{ GenerativeModel, Prediction, Fulfillment, Action, Memory }
  import Andy.Utils, only: [choose_one: 1, as_percept_about: 1]

  def generative_models() do
    [
      # Hyper-prior

      #THRIVING

      GenerativeModel.new(
        name: :thriving,
        description: "The puppy is alive and well",
        predictions: [
          # safe, sated and free are sinling models
          Prediction.new(
            name: :puppy_is_safe,
            believed: { :is, :safe },
            precision: :high,
            # try this first (of course it won't fulfil the prediction of believing that one is safe)
            fulfillments: [Fulfillment.new(actions: [say_once("I am scared!")])]
          ),
          Prediction.new(
            name: :puppy_is_sated,
            believed: { :is, :sated },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [say_once("I am hungry!")])]
          ),
          Prediction.new(
            name: :puppy_is_free,
            believed: { :is, :free },
            precision: :high,
            fulfillments: []
          )
        ],
        # Let activated sub-models dictate priority
        priority: nil,
        hyper_prior?: true
      ),

      # SAFE

      GenerativeModel.new(
        name: :safe,
        description: "The puppy is safe",
        predictions: [
          Prediction.new(
            name: :puppy_not_bumped_in_the_dark,
            believed: { :not, :bumped_in_the_dark },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [say_once("What was that?"), backoff(), turn(), turn(), backoff()])]
          ),
          Prediction.new(
            name: :puppy_is_in_the_light,
            believed: { :is, :in_the_light },
            precision: :high,
            fulfill_when: [:puppy_not_bumped_in_the_dark],
            fulfillments: [Fulfillment.new(actions: [say_once("It's too dark")])]
          )
          #  ,
          #          Prediction.new(
          #            name: :other_puppies_safe,
          #            believed: { :is, :others_safe },
          #            precision: :high,
          #            # That won't help but heh...
          #            fulfillments: [Fulfillment.new(actions: [say_once("What's going on?")])]
          #          )
        ],
        # Whereas the priorities for :free and :stated would be :medium
        priority: :high
      ),

      # Action models
      # In a well-light area
      GenerativeModel.new(
        name: :in_the_light,
        description: "The puppy is in a well-light area",
        predictions: [
          Prediction.new(
            name: :puppy_in_well_lit_area,
            perceived: [{ { :sensor, :any, :color, :ambient }, { :gt, 50 }, { :past_secs, 2 } }],
            precision: :high,
            fulfillments: [Fulfillment.new(model_name: :getting_lighter)]
          )
        ],
        priority: :high
      ),
      # It's getting lighter
      GenerativeModel.new(
        name: :getting_lighter,
        description: "The puppy is in a better-lit area",
        predictions: [
          Prediction.new(
            name: :puppy_in_better_lit_area,
            perceived: [{ { :sensor, :any, :color, :ambient }, :ascending, { :past_secs, 5 } }],
            precision: :low,
            # keep going forward if it works, else turn
            fulfillments: [Fulfillment.new(actions: [forward(), turn()])]
          )
        ],
        priority: :high
      ),
      # Recently got bumped while in the dark
      GenerativeModel.new(
        name: :bumped_in_the_dark,
        description: "The puppy bumped into something in the dark",
        predictions: [
          Prediction.new(
            name: :puppy_touched_in_dark,
            perceived: [
              { { :sensor, :any, :touch, :touch }, { :eq, :touched }, :now },
              { { :sensor, :any, :color, :ambient }, { :lt, 10 }, :now }
            ],
            precision: :medium,
            # We never want to fulfill this prediction
            fulfillments: []
          )
        ],
        priority: :high
      ),

      # SATED

      GenerativeModel.new(
        name: :sated,
        description: "The puppy ate enough recently",
        predictions: [
          Prediction.new(
            name: :puppy_recently_ate,
            actuated: [{ :eating, { :sum, :quantity, 10 }, { :past_secs, 30 } }],
            precision: :medium,
            fulfillments: [Fulfillment.new(model_name: :feeding)]
          )
        ],
        priority: :high
      ),

      GenerativeModel.new(
        name: :feeding,
        description: "The puppy is feeding",
        predictions: [
          Prediction.new(
            name: :puppy_on_food,
            perceived: [{ { :sensor, :any, :color, :color }, { :eq, :blue }, :now }],
            precision: :high,
            fulfillments: [Fulfillment.new(model_name: :getting_closer_to_food)]
          ),
          Prediction.new(
            name: :puppy_eating,
            precision: :high,
            fulfill_when: [:puppy_on_food],
            fulfillments: [Fulfillment.new(actions: [say_once("nom de nom de nom"), eat()])]
          )
        ],
        priority: :high
      ),

      GenerativeModel.new(
        name: :getting_closer_to_food,
        description: "The puppy is getting closer to food",
        predictions: [
          Prediction.new(
            name: :puppy_smells_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_distance, 1 } }, { :lt, 30 }, { :past_secs, 5 } }],
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [forward(), turn()])]
          ),
          Prediction.new(
            name: :puppy_faces_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_heading, 1 } }, { :abs_lt, 5 }, :now }],
            precision: :high,
            fulfill_when: [:puppy_smells_food],
            fulfillments: [
              Fulfillment.new(actions: [turn_toward({ :sensor, :any, :infrared, { :beacon_heading, 1 } })])
            ]
          ),
          Prediction.new(
            name: :puppy_approaches_food,
            perceived: [{ { :sensor, :any, :infrared, { :beacon_distance, 1 } }, :descending, { :past_secs, 2 } }],
            precision: :high,
            fulfill_when: [:puppy_faces_food],
            fulfillments: [Fulfillment.new(actions: [approach({ :sensor, :any, :infrared, { :beacon_distance, 1 } })])]
          )
        ],
        priority: :high
      ),

      # FREE
      GenerativeModel.new(
        name: :free,
        description: "The puppy is free to move about",
        predictions: [
          Prediction.new(
            name: :puppy_unobstructed,
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [say_once("Huh hoh!"), backoff(), turn()])]
          ),
          Prediction.new(
            name: :puppy_has_clear_path,
            believed: { :not, :approaching_obstacle },
            precision: :medium,
            when_fulfilled: [:puppy_unobstructed],
            fulfillments: [Fulfillment.new(actions: [avoid({ :sensor, :any, :ultrasonic, :distance })])]
          ),
          Prediction.new(
            name: :puppy_is_moving,
            actuated: [{ :go_forward, { :times, 10 }, { :past_secs, 30 } }],
            precision: :medium,
            when_fulfilled: [:puppy_has_clear_path],
            fulfillments: [Fulfillment.new(actions: [move()])]
          ),
        ],
        priority: :high
      ),
      # Recently got bumped
      GenerativeModel.new(
        name: :bumped,
        description: "The puppy bumped into something",
        predictions: [
          Prediction.new(
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
      GenerativeModel.new(
        name: :approaching_obstacle,
        description: "The puppy is approaching an obstacle",
        predictions: [
          Prediction.new(
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

end