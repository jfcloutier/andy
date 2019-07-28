defmodule Andy.GM.Perception do
  @moduledoc "Perception behaviour to unify some of Prediction and PredictionError"

  @alias Andy.GM.{PredictionError, Prediction}

  @callback source(perception :: any) :: String.t
  @callback name(perception :: any) :: String.t
  @callback about(perception :: any) :: any
  @callback parameter_values(perception :: any) :: map

  def competing?(perception, other) do
    name(perception) == name(other)
    and about(perception) == about(other)
  end

  def source(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :source, [])
  end

  def name(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :name, [])
  end

  def about(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :about, [])
  end

  def parameter_values(perception) do
    module = Map.get(perception, :__struct__)
    apply(module, :parameter_values, [])
  end

  def prediction_error?(perception) do
    Map.get(perception, :__struct__) == PredictionError
  end

  def prediction?(perception) do
    Map.get(perception, :__struct__) == Prediction
  end

end