defmodule ExMachina.EctoStrategy do
  @moduledoc false

  use ExMachina.Strategy, function_name: :insert

  def handle_insert(%{__meta__: %{state: :loaded}} = record, _) do
    raise "You called `insert` on a record that has already been inserted.
     Make sure that you have not accidentally called insert twice.

     The record you attempted to insert:

     #{inspect record, limit: :infinity}"
  end

  def handle_insert(%{__meta__: %{__struct__: Ecto.Schema.Metadata}} = record, %{repo: repo}) do
    record
    |> cast
    |> repo.insert!
  end

  def handle_insert(record, %{repo: _repo}) do
    raise ArgumentError, "#{inspect record} is not an Ecto model. Use `build` instead"
  end

  def handle_insert(_record, _opts) do
    raise "expected :repo to be given to ExMachina.EctoStrategy"
  end

  defp cast(record) do
    record
    |> cast_all_fields
    |> cast_all_assocs
  end

  defp cast_all_fields(struct) do
    struct
    |> ExMachina.Ecto.drop_ecto_fields
    |> Map.keys
    |> cast_all_fields(struct)
  end

  defp cast_all_fields(fields, struct) do
    Enum.reduce(fields, struct, fn(field, struct) ->
      casted_value = cast_field(field, struct)
      Map.put(struct, field, casted_value)
    end)
  end

  defp cast_field(field, %{__struct__: schema} = struct) do
    field_type = schema.__schema__(:type, field)
    virtual_field? = !field_type
    embed_type = schema.__schema__(:embed, field)
    embedded_field? = !!embed_type

    value = Map.get(struct, field)

    if virtual_field? || embedded_field? do
      value
    else
      cast_value(field_type, value, struct)
    end
  end

  defp cast_value(field_type, value, struct) do
    case Ecto.Type.cast(field_type, value) do
      {:ok, value} ->
        value
      _ ->
        raise "Failed to cast `#{inspect value}` of type #{inspect field_type} in #{inspect struct}."
    end
  end

  defp cast_all_assocs(%{__struct__: schema} = struct) do
    assocs = get_schema_assocs(schema)

    Enum.reduce(assocs, struct, fn(assoc, struct) ->
      casted_value = Map.get(struct, assoc)
                   |> cast_assoc(assoc, struct)

      Map.put(struct, assoc, casted_value)
    end)
  end

  defp cast_assoc(original_value, assoc, struct) when is_list(original_value) do
    Enum.map(original_value, &(cast_assoc(&1, assoc, struct)))
  end

  defp cast_assoc(original_value, assoc, %{__struct__: schema}) do
    case original_value do
      %{__meta__: %{__struct__: Ecto.Schema.Metadata, state: :built}} ->
        cast(original_value)

      %{__struct__: Ecto.Association.NotLoaded} ->
        original_value

      %{__struct__: _} ->
        cast(original_value)

      %{} ->
        assoc_reflection = schema.__schema__(:association, assoc) || schema.__schema__(:embed, assoc)
        assoc_type = assoc_reflection.related
        assoc_type |> struct |> Map.merge(original_value) |> cast

      nil -> nil
    end
  end

  defp get_schema_assocs(schema) do
    schema.__schema__(:associations) ++ schema.__schema__(:embeds)
  end
end
