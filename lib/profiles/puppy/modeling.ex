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
            believed: { :is, :safe },
            precision: :high,
            # try this first (of course it won't fulfil the prediction of believing that one is safe)
            fulfillments: [Fulfillment.new(actions: [say_once("I am scared!")])]
          ),
          Prediction.new(
            believed: { :is, :sated },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [say_once("I am hungry!")])]
          ),
          Prediction.new(
            believed: { :is, :free },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [say_once("Huh hoh!")])]
          )
        ],
        focus: :same, # does not matter since no sibling models
        hyper_prior: true
      ),
      # Hyper-prior sub-models

      # SAFE
      GenerativeModel.new(
        name: :safe,
        description: "The puppy is safe",
        predictions: [
          Prediction.new(
            believed: { :not, :bumped },
            precision: :high,
            fulfillments: [Fulfillment.new(actions: [backoff(), turn()])]
          ),
          Prediction.new(
            believed: { :not, :in_the_dark },
            precision: :high,
            fulfillments: [Fulfillment.new(model_name: :in_the_light)]
          ),
          Prediction.new(
            believed: { :is, :others_safe },
            precision: :high,
            # That won't help but heh...
            fulfillments: [Fulfillment.new(actions: [say_once("I am scared too!")])]
          )
        ],
        focus: :high,
        hyper_prior: false
      ),


      # Action models
      # In a well-light area
      GenerativeModel.new(
        name: :in_the_light,
        description: "The puppy is in a well-light area",
        predictions: [
          Prediction.new(
            perceived: { :sensor, :color, :ambient, { :gt, 50 }, :now },
            precision: :high,
            fulfillments: [Fulfillment.new(model_name: :getting_lighter)]
          )
        ],
        focus: :high,
        hyper_prior: false
      ),
      # It's getting lighter
      GenerativeModel.new(
        name: :getting_lighter,
        description: "The puppy is in a better-lit area",
        predictions: [
          Prediction.new(
            perceived: { :sensor, :color, :ambient, :ascending, { :past_secs, 5 } },
            precision: :low,
            # keep going forward if it works, else turn
            fulfillments: [Fulfillment.new(actions: [forward(), turn()])]
          )
        ],
        focus: :high,
        hyper_prior: false
      )


    ]
    # TODO
  end

  ### PRIVATE

  defp forward() do
    fn ->
      [
        Action.new(
          intent_name: :go_forward,
          intent_value: %{
            speed: :fast,
            time: 1
          },
          once: false
        )
      ]
    end
  end

  defp backoff() do
    fn -> [
            Action.new(
              intent_name: :go_backward,
              intent_value: %{
                speed: :fast,
                time: 1
              }
            )
          ]
    end
  end

  defp turn() do
    fn ->
      [
        Action.new(
          intent_name: choose_one([:turn_right, :turn_left]),
          value: choose_one(1..10) / 10,
          once: false
        )
      ]
    end
  end

  defp say_once(words) do
    fn ->
      [
        Action.new(
          intent_name: :say,
          intent_value: words,
          once: true
        )
      ]
    end
  end

end