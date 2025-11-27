defmodule DukascopyEx.TickData do
  @moduledoc """
  Downloads and unpacks Dukascopy tick data from .bi5 files.
  """

  alias DukascopyEx.Instruments
  alias TheoryCraft.MarketSource.Tick

  @base_url "https://datafeed.dukascopy.com/datafeed"

  # Determines the point value for an instrument.
  # Formula from Dukascopy: point_value = 10 / pip_value
  # Some instruments have special overrides (from dukascopy-node)
  @point_value_overrides %{
    "BAT/USD" => 100_000,
    "UNI/USD" => 1_000,
    "LNK/USD" => 1_000
  }

  @doc """
  Downloads and unpacks tick data for a specific instrument, date and hour.

  ## Parameters

    * `instrument` - Trading instrument (e.g., "EUR/USD")
    * `date` - Date as a `Date` struct
    * `hour` - Hour (0-23)
    * `opts` - Options keyword list:
      * `:point_value` - Point value divisor for price conversion (default: auto-detected based on instrument)

  ## Returns

    * `{:ok, [Tick.t()]}` - List of ticks
    * `{:error, reason}` - Error tuple

  ## Examples

      iex> {:ok, ticks} = TickData.fetch("EUR/USD", ~D[2024-11-15], 10)
      iex> length(ticks) > 0
      true

      iex> TickData.fetch("UNKNOWN", ~D[2024-11-15], 10)
      {:error, {:unknown_instrument, "UNKNOWN"}}

  """
  @spec fetch(String.t(), Date.t(), integer(), keyword()) :: {:ok, [Tick.t()]} | {:error, term()}
  def fetch(instrument, %Date{} = date, hour, opts \\ []) when hour >= 0 and hour <= 23 do
    with {:ok, point_value} <- get_point_value(instrument, opts),
         {:ok, url} <- build_url(instrument, date, hour),
         {:ok, response} <- Req.get(url),
         {:ok, decompressed} <- LZMA.lzma_decompress(response.body) do
      parse_ticks(decompressed, date, hour, point_value)
    end
  end

  @doc """
  Same as `fetch/4` but raises on error.
  """
  @spec fetch!(String.t(), Date.t(), integer(), keyword()) :: [Tick.t()]
  def fetch!(instrument, date, hour, opts \\ []) do
    case fetch(instrument, date, hour, opts) do
      {:ok, ticks} -> ticks
      {:error, reason} -> raise "Failed to fetch tick data: #{inspect(reason)}"
    end
  end

  # Private functions

  defp get_point_value(instrument, opts) do
    with :error <- Keyword.fetch(opts, :point_value),
         :error <- Map.fetch(@point_value_overrides, instrument) do
      case Instruments.get_pip_value(instrument) do
        nil -> {:error, {:unknown_instrument, instrument}}
        pip_value -> {:ok, 10 / pip_value}
      end
    end
  end

  defp build_url(instrument, date, hour) do
    %Date{day: day, month: month, year: year} = date

    case Instruments.get_historical_filename(instrument) do
      nil ->
        {:error, {:unknown_instrument, instrument}}

      filename ->
        # Dukascopy months are 0-indexed (0 = January, 11 = December)
        month_str = String.pad_leading("#{month - 1}", 2, "0")
        day_str = String.pad_leading("#{day}", 2, "0")
        hour_str = String.pad_leading("#{hour}", 2, "0")

        {:ok, "#{@base_url}/#{filename}/#{year}/#{month_str}/#{day_str}/#{hour_str}h_ticks.bi5"}
    end
  end

  defp parse_ticks(binary, date, hour, point_value, acc \\ [])
  defp parse_ticks(<<>>, _date, _hour, _point_value, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_ticks(
         <<time_delta::32-big-unsigned, ask::32-big-signed, bid::32-big-signed,
           ask_volume::32-big-float, bid_volume::32-big-float, rest::binary>>,
         date,
         hour,
         point_value,
         acc
       ) do
    # Calculate the DateTime (Dukascopy data is in UTC)
    hour_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    hour_start_ms = DateTime.to_unix(hour_start, :millisecond)
    time = DateTime.from_unix!(hour_start_ms + hour * 3_600_000 + time_delta, :millisecond)

    tick = %Tick{
      time: time,
      ask: ask / point_value,
      bid: bid / point_value,
      ask_volume: ask_volume,
      bid_volume: bid_volume
    }

    parse_ticks(rest, date, hour, point_value, [tick | acc])
  end

  defp parse_ticks(_binary, _date, _hour, _point_value, _acc) do
    {:error, :invalid_tick_format}
  end
end
