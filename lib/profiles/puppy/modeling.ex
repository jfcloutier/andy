defmodule Andy.Puppy.Modeling do
  @moduledoc "The generative models for a puppy profile"

  alias Andy.{ GenerativeModel, Prediction, Fulfillment, Action }
  import Andy.Utils, only: [choose_one: 1]

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
          #          Prediction.new(
          #            name: :puppy_is_free,
          #            believed: { :is, :free },
          #            precision: :high,
          #            fulfillments: [Fulfillment.new(actions: [say_once("Huh hoh!")])]
          #          )
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
            name: :puppy_not_bumped,
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [backoff(), turn()])]
          ),
          Prediction.new(
            name: :puppy_is_in_the_light,
            believed: { :is, :in_the_light },
            precision: :high,
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
      # Recently got bumped
      GenerativeModel.new(
        name: :bumped,
        description: "The puppy bumped into something",
        predictions: [
          Prediction.new(
            name: :puppy_recently_touched,
            perceived: [{ { :sensor, :any, :touch, :touch }, { :eq, :touched }, { :past_secs, 1 } }],
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
            actualized: [{ :eating, { :sum, :quantity, 10 }, { :past_secs, 30 } }],
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
        # TBD
         ],
        priority: :high
      )


      # FREE
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
    fn -> Action.new(
            intent_name: :go_backward,
            intent_value: %{
              speed: :fast,
              time: 1
            }
          )
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