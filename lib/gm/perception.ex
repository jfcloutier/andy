defmodule Andy.GM.Perception do
  @moduledoc "Perception behaviour to unify some of Prediction and PredictionError"

  alias Andy.GM.{PredictionError, Prediction, Perception}

  @callback source(perception :: any) :: String.t()
  @callback conjecture_name(perception :: any) :: String.t()
  @callback about(perception :: any) :: any
  @callback carry_overs(perception :: any) :: non_neg_integer
  @callback prediction_conjecture_name(perception :: any) :: String.t()
  @callback values(perception :: any) :: map

  def same_subject?(perception, other) do
    conjecture_name(perception) == conjecture_name(other) and
      about(perception) == about(other)
  end

  def source(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :source, [])
  end

  def conjecture_name(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :conjecture_name, [])
  end

  def about(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :about, [])
  end

  def carry_overs(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :carry_overs, [])
  end

  def prediction_conjecture_name(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :prediction_conjecture_name, [])
  end

  def values(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :values, [])
  end

  def prediction_error?(perception) do
    Map.get(perception, :__struct__) == PredictionError
  end

  def prediction?(perception) do
    Map.get(perception, :__struct__) == Prediction
  end

  def increment_carry_over(perception) do
    Map.put(perception, :carry_overs, Perception.carry_overs(perception) + 1)
  end
end
