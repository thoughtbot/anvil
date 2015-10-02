defmodule ExMachina do
  @moduledoc """
  Defines functions for generating data

  In depth examples are in the [README](README.html)
  """

  defmodule UndefinedFactory do
    @moduledoc """
    Error raised when trying to build or create a factory that is undefined.
    """

    defexception [:message]

    def exception(factory_name) do
      message = "No factory defined for #{inspect factory_name}"
      %UndefinedFactory{message: message}
    end
  end

  defmodule UndefinedSave do
    @moduledoc """
    Error raised when trying to call create and save_record/1 is
    not defined.
    """

    defexception [:message]

    def exception do
      %UndefinedSave{
        message: "Define save_record/1. See docs for ExMachina.save_record/1."
      }
    end
  end

  use Application

  def start(_type, _args), do: ExMachina.Sequence.start_link

  defmacro __using__(_opts) do
    quote do
      @before_compile unquote(__MODULE__)

      import ExMachina, only: [sequence: 2, factory: 2]
    end
  end

  defmacro factory(factory_name, do: block) do
    quote do
      def factory(unquote(factory_name), var!(attrs)) do
        !var!(attrs) # Removes unused variable warning if attrs wasn't used
        unquote(block)
      end
    end
  end

  @doc """
  Create sequences for generating unique values

  ## Examples

      factory :user do
        %{
          # Will generate "me-0@example.com" then "me-1@example.com", etc.
          email: sequence(:email, &"me-\#{&1}@foo.com")
        }
      end
  """
  def sequence(name, formatter), do: ExMachina.Sequence.next(name, formatter)

  defmacro __before_compile__(_env) do
    # We are using line -1 because we don't want warnings coming from
    # save_record/1 when someone defines there own save_recod/1 function.
    quote line: -1 do
      @doc """
      Raises a helpful error if no factory is defined.
      """
      def factory(factory_name, _) do
        raise UndefinedFactory, factory_name
      end

      @doc """
      Builds a factory with the passed in factory_name and attrs

      ## Example

          factory :user do
            %{name: "John Doe", admin: false}
          end

          # Returns %{name: "John Doe", admin: true}
          build(:user, admin: true)
      """
      def build(factory_name, attrs \\ %{}) do
        attrs = Enum.into(attrs, %{})
        __MODULE__.factory(factory_name, attrs) |> Map.merge(attrs)
      end

      @doc """
      Builds and returns 2 records with the passed in factory_name and attrs

      ## Example

          # Returns a list of 2 users
          build_pair(:user)
      """
      def build_pair(factory_name, attrs \\ %{}) do
        build_list(2, factory_name, attrs)
      end

      @doc """
      Builds and returns X records with the passed in factory_name and attrs

      ## Example

          # Returns a list of 3 users
          build_list(3, :user)
      """
      def build_list(number_of_factories, factory_name, attrs \\ %{}) do
        Enum.map(1..number_of_factories, fn(_) ->
          build(factory_name, attrs)
        end)
      end

      @doc """
      Builds and saves a factory with the passed in factory_name

      If using ExMachina.Ecto it will use the Ecto Repo passed in to save the
      record automatically.

      If you are not using ExMachina.Ecto, you need to define a `save_record/1`
      function in your module. See `save_record` docs for more information.

      ## Example

          factory :user do
            %{name: "John Doe", admin: false}
          end

          # Saves and returns %{name: "John Doe", admin: true}
          create(:user, admin: true)
      """
      def create(built_record) when is_map(built_record) do
        built_record |> save_record
      end

      def create(factory_name, attrs \\ %{}) do
        build(factory_name, attrs) |> save_record
      end

      @doc """
      Creates and returns 2 records with the passed in factory_name and attrs

      ## Example

          # Returns a list of 2 saved users
          create_pair(:user)
      """
      def create_pair(factory_name, attrs \\ %{}) do
        create_list(2, factory_name, attrs)
      end

      @doc """
      Creates and returns X records with the passed in factory_name and attrs

      ## Example

          # Returns a list of 3 saved users
          create_list(3, :user)
      """
      def create_list(number_of_factories, factory_name, attrs \\ %{}) do
        Enum.map(1..number_of_factories, fn(_) ->
          create(factory_name, attrs)
        end)
      end

      @doc """
      Saves a record when `create` is called. Uses Ecto if using ExMachina.Ecto

      If using ExMachina.Ecto (`use ExMachina.Ecto, repo: MyApp.Repo`) this
      function will call `insert!` on the passed in repo.

      If you are not using ExMachina.Ecto, you must define a custom
      save_record/1 for saving the record.

      ## Examples

          defmodule MyApp.Factory do
            use ExMachina.Ecto, repo: MyApp.Repo

            factory :user do
              %User{name: "John"}
            end
          end

          # Will build and save the record to the MyApp.Repo
          MyApp.Factory.create(:user)

          defmodule MyApp.JsonFactories do
            # Note, we are not using ExMachina.Ecto
            use ExMachina

            factory :user do
              %User{name: "John"}
            end

            def save_record(record) do
              # Poison is a library for working with JSON
              Poison.encode!(record)
            end
          end

          # Will build and then return a JSON encoded version of the map
          MyApp.JsonFactories.create(:user)
      """
      def save_record(record) do
        raise UndefinedSave
      end
    end
  end
end
