defmodule ExMachina do
  @moduledoc """
  Defines functions for generating data

  In depth examples are in the [README](README.html)
  """

  defmodule UndefinedFactoryError do
    @moduledoc """
    Error raised when trying to build or create a factory that is undefined.
    """

    defexception [:message]

    def exception(factory_name) do
      message =
        """
        No factory defined for #{inspect factory_name}.

        Please check for typos or define your factory:

            def #{inspect factory_name}_factory do
              ...
            end
        """
      %UndefinedFactoryError{message: message}
    end
  end

  use Application

  @doc false
  def start(_type, _args), do: ExMachina.Sequence.start_link

  defmacro __using__(_opts) do
    quote do
      @before_compile unquote(__MODULE__)

      import ExMachina, only: [sequence: 1, sequence: 2]

      def build(factory_name, attrs \\ %{}) do
        ExMachina.build(__MODULE__, factory_name, attrs)
      end

      def build_pair(factory_name, attrs \\ %{}) do
        ExMachina.build_pair(__MODULE__, factory_name, attrs)
      end

      def build_list(number_of_factories, factory_name, attrs \\ %{}) do
        ExMachina.build_list(__MODULE__, number_of_factories, factory_name, attrs)
      end

      def defer(weight \\ 0, func) do
        ExMachina.defer(weight, func)
      end
    end
  end

  @doc """
  Shortcut for creating unique string values. Similar to sequence/2

  For more customization of the generated string, see ExMachina.sequence/2

  ## Examples

      def user_factory do
        %User{
          # Will generate "username0" then "username1", etc.
          username: sequence("username")
        }
      end

      def article_factory do
        %Article{
          title: sequence("Article Title")
        }
      end
  """
  def sequence(name), do: ExMachina.Sequence.next(name)

  @doc """
  Create sequences for generating unique values

  ## Examples

      def user_factory do
        %{
          # Will generate "me-0@example.com" then "me-1@example.com", etc.
          email: sequence(:email, &"me-\#{&1}@foo.com")
        }
      end
  """
  def sequence(name, formatter), do: ExMachina.Sequence.next(name, formatter)

  @doc """
  Builds a factory with the passed in factory_name and attrs

  ## Example

      def user_factory do
        %{name: "John Doe", admin: false}
      end

      # Returns %{name: "John Doe", admin: true}
      build(:user, admin: true)
  """
  def build(module, factory_name, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    function_name = Atom.to_string(factory_name) <> "_factory" |> String.to_atom
    if Code.ensure_loaded?(module) && function_exported?(module, function_name, 0) do
      apply(module, function_name, []) |> do_merge(attrs) |> resolve
    else
      raise UndefinedFactoryError, factory_name
    end
  end

  def defer(weight \\ 0, func)

  def defer(weight, func) when is_number(weight) and is_function(func, 1) do
    %ExMachina.DeferredAttribute{weight: weight, func: func}
  end

  def defer(weight, func) when is_function(func, 1) do
    raise ArgumentError, "The first argument must be a number.  You gave: #{inspect(weight)}"
  end

  def defer(weight, func) when is_number(weight) do
    raise ArgumentError, "The second argument must be a function with arity 1.  You gave: #{inspect(func)}"
  end

  defp do_merge(%{__struct__: _} = record, attrs) do
    struct!(record, attrs)
  end
  defp do_merge(record, attrs) do
    Map.merge(record, attrs)
  end

  # Entry point to resolve the record map/struct.
  #
  # Traverses the record and applys functions, then undefers and computes
  # deferred attributes according to weight.
  defp resolve(record), do: resolve(record, nil) |> undefer

  defp resolve(%ExMachina.DeferredAttribute{} = attr, _scope), do: attr
  defp resolve(%{__struct__: _} = record, scope) do
    attrs = Map.from_struct(record) |> resolve(scope)
    struct!(record, attrs)
  end
  defp resolve(record, scope) when is_map(record) do
    for {key, value} <- record, into: %{}, do: {key, resolve(value, scope || record)}
  end
  defp resolve(function, scope) when is_function(function) do
    function.(scope)
  end
  defp resolve(list, scope) when is_list(list) do
    Enum.map(list, &resolve(&1, scope))
  end
  defp resolve(value, _scope), do: value

  defp undefer(record, weight \\ 0) do
    case do_undefer(record, weight) do
      {record, nil} -> record
      {record, next_weight} -> undefer(record, next_weight)
    end
  end

  def do_undefer(record, weight) do
    map = case record do
      %{__struct__: _} -> Map.from_struct(record)
      %{} -> record
    end

    map
    |> Enum.reduce({record, nil}, fn({key, value}, {acc_record, acc_weight}) ->
      case value do
        %ExMachina.DeferredAttribute{} ->
          # Deferred attribute and it is time to apply
          if value.weight <= weight do
            new_value = value.func.(acc_record)
            {Map.put(acc_record, key, new_value), acc_weight}
          # Deferred attribute, but will apply later
          else
            next_weight = cond do
              is_nil(acc_weight) -> value.weight         # 1. Next weight is at least this deferred weight
              value.weight < acc_weight -> value.weight  # 2. Found a lower weight we should run next
              true -> acc_weight                         # 3. No lower weight found
            end
            {acc_record, next_weight}
          end
        # Not a deferred attribute
        _ -> {acc_record, acc_weight}
      end
    end)
  end

  @doc """
  Builds and returns 2 records with the passed in factory_name and attrs

  ## Example

      # Returns a list of 2 users
      build_pair(:user)
  """
  def build_pair(module, factory_name, attrs \\ %{}) do
    ExMachina.build_list(module, 2, factory_name, attrs)
  end

  @doc """
  Builds and returns X records with the passed in factory_name and attrs

  ## Example

      # Returns a list of 3 users
      build_list(3, :user)
  """
  def build_list(module, number_of_factories, factory_name, attrs \\ %{}) do
    Enum.map(1..number_of_factories, fn(_) ->
      ExMachina.build(module, factory_name, attrs)
    end)
  end

  defmacro __before_compile__(_env) do
    # We are using line -1 because we don't want warnings coming from
    # save_record/1 when someone defines there own save_record/1 function.
    quote line: -1 do
      @doc """
      Raises a helpful error if no factory is defined.
      """
      def factory(factory_name) do
        raise UndefinedFactoryError, factory_name
      end
    end
  end
end
