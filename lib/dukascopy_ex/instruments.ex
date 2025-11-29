defmodule DukascopyEx.Instruments do
  @moduledoc """
  List of available trading instruments on Dukascopy.

  This module loads instrument data from `priv/instruments.json` at compile time.
  Run `mix dukascopy.gen.instruments` to download the latest instrument data.
  """

  @external_resource "priv/instruments.json"

  # NOTE: Elixir 1.18 use the new JSON module
  @instruments_data @external_resource |> File.read!() |> Jason.decode!()

  @groups Map.fetch!(@instruments_data, "groups")
  @instruments Map.fetch!(@instruments_data, "instruments")

  get_parent = fn info, target, get_parent ->
    cond do
      Map.fetch!(info, "id") == target ->
        true

      Map.get(info, "parent") != nil ->
        parent_info = Map.fetch!(@groups, info["parent"])
        get_parent.(parent_info, target, get_parent)

      true ->
        false
    end
  end

  get_group_instruments = fn group_id ->
    instruments =
      for {_group_id, group_info} <- @groups,
          get_parent.(group_info, group_id, get_parent),
          instrument <- Map.get(group_info, "instruments", []),
          # NOTE: Some instruments may be missing in the instruments map.
          # This happens when instruments are delisted (e.g., stocks merged/acquired like
          # BBT.US/USD, CELG.US/USD, RHT.US/USD) or retired from trading (e.g., EUR/RUB, USD/RUB).
          # The Dukascopy API keeps these instruments in groups for historical reference,
          # but they're no longer available in the active instruments list.
          instrument_info = Map.get(@instruments, instrument),
          not is_nil(instrument_info) do
        Map.fetch!(instrument_info, "name")
      end

    instruments |> Enum.uniq() |> Enum.sort()
  end

  @all_instruments @instruments
                   |> Enum.map(fn {_k, v} -> Map.fetch!(v, "name") end)
                   |> Enum.sort()
  @fx_instruments get_group_instruments.("FX")
  @fx_major_instruments get_group_instruments.("FX_MAJORS")
  @fx_crosses_instruments get_group_instruments.("FX_CROSSES")
  @stocks_instruments get_group_instruments.("STCK_CFD")
  @metals_instruments get_group_instruments.("FX_METALS")
  @commodities_instruments get_group_instruments.("CMD")
  @agriculturals_instruments get_group_instruments.("CMD_AGRICULTURAL")

  ## Public API

  @doc """
  Returns the list of all available instruments.

  ## Examples

      iex> instruments = Instruments.all()
      iex> "EUR/USD" in instruments
      true
      iex> "AAPL.US/USD" in instruments
      true

  """
  @spec all() :: [String.t()]
  def all(), do: @all_instruments

  @doc """
  Returns the list of all Forex instruments.

  ## Examples

      iex> forex = Instruments.forex()
      iex> "EUR/USD" in forex
      true
      iex> "GBP/JPY" in forex
      true

  """
  @spec forex() :: [String.t()]
  def forex(), do: @fx_instruments

  @doc """
  Returns the list of all Forex Major instruments.

  ## Examples

      iex> Instruments.forex_majors()
      ["AUD/USD", "EUR/USD", "GBP/USD", "NZD/USD", "USD/CAD", "USD/CHF", "USD/JPY"]

  """
  @spec forex_majors() :: [String.t()]
  def forex_majors(), do: @fx_major_instruments

  @doc """
  Returns the list of all Forex Crosses instruments.

  ## Examples

      iex> crosses = Instruments.forex_crosses()
      iex> "EUR/GBP" in crosses
      true
      iex> "EUR/JPY" in crosses
      true

  """
  @spec forex_crosses() :: [String.t()]
  def forex_crosses(), do: @fx_crosses_instruments

  @doc """
  Returns the list of all Stocks instruments.

  ## Examples

      iex> stocks = Instruments.stocks()
      iex> "AAPL.US/USD" in stocks
      true
      iex> "TSLA.US/USD" in stocks
      true

  """
  @spec stocks() :: [String.t()]
  def stocks(), do: @stocks_instruments

  @doc """
  Returns the list of all Metals instruments.

  ## Examples

      iex> metals = Instruments.metals()
      iex> "XAU/USD" in metals
      true
      iex> "XAG/USD" in metals
      true

  """
  @spec metals() :: [String.t()]
  def metals(), do: @metals_instruments

  @doc """
  Returns the list of all Commodities instruments.

  ## Examples

      iex> commodities = Instruments.commodities()
      iex> "BRENT.CMD/USD" in commodities
      true
      iex> "COPPER.CMD/USD" in commodities
      true

  """
  @spec commodities() :: [String.t()]
  def commodities(), do: @commodities_instruments

  @doc """
  Returns the list of all Agricultural instruments.

  ## Examples

      iex> agriculturals = Instruments.agriculturals()
      iex> "COCOA.CMD/USD" in agriculturals
      true
      iex> "COFFEE.CMD/USX" in agriculturals
      true

  """
  @spec agriculturals() :: [String.t()]
  def agriculturals(), do: @agriculturals_instruments

  ## Historical filename lookup

  @doc """
  Returns the historical filename for a given instrument name.

  The historical filename is used for constructing Dukascopy API URLs.
  It removes dots and slashes from the instrument name.

  ## Examples

      iex> Instruments.get_historical_filename("EUR/USD")
      "EURUSD"
      iex> Instruments.get_historical_filename("AAPL.US/USD")
      "AAPLUSUSD"
      iex> Instruments.get_historical_filename("0005.HK/HKD")
      "0005HKHKD"
      iex> Instruments.get_historical_filename("UNKNOWN")
      nil

  """
  @spec get_historical_filename(String.t()) :: String.t() | nil
  for {_instrument_id, %{"name" => name, "historical_filename" => filename}} <- @instruments do
    def get_historical_filename(unquote(name)) do
      unquote(filename)
    end
  end

  def get_historical_filename(_instrument_name), do: nil

  @doc """
  Same as `get_historical_filename/1` but raises if instrument is not found.

  ## Examples

      iex> Instruments.get_historical_filename!("EUR/USD")
      "EURUSD"

      iex> Instruments.get_historical_filename!("UNKNOWN")
      ** (ArgumentError) unknown instrument: UNKNOWN

  """
  @spec get_historical_filename!(String.t()) :: String.t()
  def get_historical_filename!(instrument_name) do
    get_historical_filename(instrument_name) ||
      raise ArgumentError, "unknown instrument: #{instrument_name}"
  end

  ## Pip value lookup

  @doc """
  Returns the pip value for a given instrument name.

  The pip value is used to convert integer prices from Dukascopy's binary format
  to decimal prices. Formula: point_value = 10 / pip_value.

  ## Examples

      iex> Instruments.get_pip_value("EUR/USD")
      0.0001
      iex> Instruments.get_pip_value("USD/JPY")
      0.01
      iex> Instruments.get_pip_value("XAU/USD")
      0.01
      iex> Instruments.get_pip_value("BTC/USD")
      1
      iex> Instruments.get_pip_value("UNKNOWN")
      nil

  """
  @spec get_pip_value(String.t()) :: float() | integer() | nil
  for {_instrument_id, %{"name" => name, "pipValue" => pip_value}} <- @instruments do
    def get_pip_value(unquote(name)) do
      unquote(pip_value)
    end
  end

  def get_pip_value(_instrument_name), do: nil

  @doc """
  Same as `get_pip_value/1` but raises if instrument is not found.

  ## Examples

      iex> Instruments.get_pip_value!("EUR/USD")
      0.0001
      
      iex> Instruments.get_pip_value!("UNKNOWN")
      ** (ArgumentError) unknown instrument: UNKNOWN

  """
  @spec get_pip_value!(String.t()) :: float() | integer()
  def get_pip_value!(instrument_name) do
    get_pip_value(instrument_name) ||
      raise ArgumentError, "unknown instrument: #{instrument_name}"
  end

  ## Point value lookup

  # Some instruments have special point_value overrides (from dukascopy-node)
  @point_value_overrides %{
    "BAT/USD" => 100_000,
    "UNI/USD" => 1_000,
    "LNK/USD" => 1_000
  }

  @doc """
  Returns the point value for a given instrument.

  The point value is used to convert integer prices from Dukascopy's binary format
  to decimal prices.

  ## Options

    * `:point_value` - Override the point value (bypasses all lookups)

  ## Examples

      iex> Instruments.get_point_value("EUR/USD")
      {:ok, 100000.0}
      iex> Instruments.get_point_value("USD/JPY")
      {:ok, 1000.0}
      iex> Instruments.get_point_value("EUR/USD", point_value: 50000)
      {:ok, 50000}
      iex> Instruments.get_point_value("UNKNOWN")
      {:error, {:unknown_instrument, "UNKNOWN"}}

  """
  @spec get_point_value(String.t(), Keyword.t()) :: {:ok, number()} | {:error, term()}
  def get_point_value(instrument, opts \\ []) do
    with :error <- Keyword.fetch(opts, :point_value),
         :error <- Map.fetch(@point_value_overrides, instrument) do
      case get_pip_value(instrument) do
        nil -> {:error, {:unknown_instrument, instrument}}
        pip_value -> {:ok, 10 / pip_value}
      end
    end
  end
end
