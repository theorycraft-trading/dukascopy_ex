defmodule DukascopyEx.BarData do
  @moduledoc """
  Downloads and parses Dukascopy bar (OHLCV) data.

  Supports multiple timeframes:

    - `:minute` - 1 minute bars (one file per day)
    - `:hour` - 1 hour bars (one file per month)
    - `:day` - 1 day bars (one file per year)

  """

  alias DukascopyEx.{Client, Instruments}
  alias TheoryCraft.MarketSource.Bar

  @type timeframe :: :minute | :hour | :day
  @type price_type :: :bid | :ask

  @doc """
  Downloads and unpacks bar data for a specific instrument and period.

  ## Parameters

    * `instrument` - Trading instrument (e.g., "EUR/USD")
    * `timeframe` - Bar timeframe: `:minute`, `:hour`, or `:day`
    * `date` - Date for `:minute` (day), `:hour` (any day in month), or `:day` (any day in year)
    * `opts` - Options keyword list:
      * `:price_type` - `:bid` (default) or `:ask`
      * `:point_value` - Point value divisor for price conversion (default: auto-detected)

  ## Returns

    * `{:ok, [Bar.t()]}` - List of bars
    * `{:error, reason}` - Error tuple

  ## Examples

      # Fetch minute bars for a specific day
      {:ok, bars} = BarData.fetch("EUR/USD", :minute, ~D[2024-11-15])

      # Fetch hourly bars for a specific month
      {:ok, bars} = BarData.fetch("EUR/USD", :hour, ~D[2024-11-01])

      # Fetch daily bars for a specific year
      {:ok, bars} = BarData.fetch("EUR/USD", :day, ~D[2024-01-01])

      # Use ask prices instead of bid
      {:ok, bars} = BarData.fetch("EUR/USD", :minute, ~D[2024-11-15], price_type: :ask)

  """
  @spec fetch(String.t(), timeframe(), Date.t(), Keyword.t()) ::
          {:ok, [Bar.t()]} | {:error, term()}
  def fetch(instrument, timeframe, %Date{} = date, opts \\ [])
      when timeframe in [:minute, :hour, :day] do
    price_type = Keyword.get(opts, :price_type, :bid)

    with {:ok, point_value} <- Instruments.get_point_value(instrument, opts),
         {:ok, url} <- build_url(instrument, timeframe, date, price_type),
         {:ok, binary} <- Client.fetch(url, opts) do
      parse_bars(binary, timeframe, date, point_value)
    end
  end

  @doc """
  Same as `fetch/4` but raises on error.
  """
  @spec fetch!(String.t(), timeframe(), Date.t(), Keyword.t()) :: [Bar.t()]
  def fetch!(instrument, timeframe, date, opts \\ []) do
    case fetch(instrument, timeframe, date, opts) do
      {:ok, bars} -> bars
      {:error, reason} -> raise "Failed to fetch bar data: #{inspect(reason)}"
    end
  end

  # Private functions

  defp build_url(instrument, timeframe, date, price_type) do
    case Instruments.get_historical_filename(instrument) do
      nil ->
        {:error, {:unknown_instrument, instrument}}

      filename ->
        %Date{month: month, year: year} = date
        price_str = price_type |> Atom.to_string() |> String.upcase()

        url =
          case timeframe do
            :minute ->
              %Date{day: day} = date

              "#{Client.base_url()}/#{filename}/#{year}/" <>
                "#{format_month(month)}/#{format_day(day)}/" <>
                "#{price_str}_candles_min_1.bi5"

            :hour ->
              "#{Client.base_url()}/#{filename}/#{year}/" <>
                "#{format_month(month)}/#{price_str}_candles_hour_1.bi5"

            :day ->
              "#{Client.base_url()}/#{filename}/#{year}/#{price_str}_candles_day_1.bi5"
          end

        {:ok, url}
    end
  end

  defp format_month(month), do: String.pad_leading("#{month - 1}", 2, "0")
  defp format_day(day), do: String.pad_leading("#{day}", 2, "0")

  defp parse_bars(binary, timeframe, date, point_value, acc \\ [])
  defp parse_bars(<<>>, _timeframe, _date, _point_value, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_bars(
         <<time_delta::32-big-signed, open::32-big-signed, high::32-big-signed,
           low::32-big-signed, close::32-big-signed, volume::32-big-float, rest::binary>>,
         timeframe,
         date,
         point_value,
         acc
       ) do
    time = calculate_bar_time(timeframe, date, time_delta)

    bar = %Bar{
      time: time,
      open: open / point_value,
      high: high / point_value,
      low: low / point_value,
      close: close / point_value,
      volume: volume
    }

    parse_bars(rest, timeframe, date, point_value, [bar | acc])
  end

  defp parse_bars(_binary, _timeframe, _date, _point_value, _acc) do
    {:error, :invalid_bar_format}
  end

  defp calculate_bar_time(:minute, date, time_delta) do
    # time_delta is seconds from midnight
    midnight = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    DateTime.add(midnight, time_delta, :second)
  end

  defp calculate_bar_time(:hour, date, time_delta) do
    # time_delta is SECONDS from start of month
    first_of_month = %Date{date | day: 1}
    month_start = DateTime.new!(first_of_month, ~T[00:00:00], "Etc/UTC")
    DateTime.add(month_start, time_delta, :second)
  end

  defp calculate_bar_time(:day, date, time_delta) do
    # time_delta is SECONDS from start of year
    first_of_year = %Date{date | month: 1, day: 1}
    year_start = DateTime.new!(first_of_year, ~T[00:00:00], "Etc/UTC")
    DateTime.add(year_start, time_delta, :second)
  end
end
