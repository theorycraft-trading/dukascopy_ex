defmodule DukascopyEx.Helpers.PeriodGenerator do
  @moduledoc false

  #
  # Generates fetch periods for Dukascopy data downloads.
  #
  # Dukascopy organizes data files by time periods:
  #
  #   - Ticks: hourly files (`XXh_ticks.bi5`)
  #   - Minutes: daily files (`BID_candles_min_1.bi5`)
  #   - Hours: monthly files (`BID_candles_hour_1.bi5`)
  #   - Days: yearly files (`BID_candles_day_1.bi5`)
  #
  # For current (incomplete) periods, aggregated files don't exist yet.
  # This module handles fallback to finer granularities automatically.
  #

  alias DukascopyEx.Helpers.TimeRange

  @typedoc "Fetch granularity for bar data"
  @type granularity :: :minute | :hour | :day

  @typedoc "Period tuple returned by generators"
  @type tick_period :: {Date.t(), 0..23}
  @type bar_period :: {granularity(), Date.t()}

  ## Public API

  @doc """
  Generates periods for tick data (one per hour).

  Returns a stream of `{date, hour}` tuples for each hour in the range.

  ## Parameters

    * `from` - Start datetime (inclusive)
    * `to` - End datetime (exclusive)

  ## Examples

      iex> periods = PeriodGenerator.tick_periods(~U[2024-01-01 10:30:00Z], ~U[2024-01-01 14:00:00Z])
      iex> Enum.to_list(periods)
      [{~D[2024-01-01], 10}, {~D[2024-01-01], 11}, {~D[2024-01-01], 12}, {~D[2024-01-01], 13}]

      iex> periods = PeriodGenerator.tick_periods(~U[2024-01-01 22:00:00Z], ~U[2024-01-02 02:00:00Z])
      iex> Enum.to_list(periods)
      [{~D[2024-01-01], 22}, {~D[2024-01-01], 23}, {~D[2024-01-02], 0}, {~D[2024-01-02], 1}]

  """
  @spec tick_periods(DateTime.t(), DateTime.t()) :: Enumerable.t()
  def tick_periods(from, to) do
    from = truncate_to_hour(from)

    Stream.unfold(from, fn current ->
      if DateTime.compare(current, to) == :lt do
        {{DateTime.to_date(current), current.hour}, DateTime.add(current, 1, :hour)}
      end
    end)
  end

  @doc """
  Generates periods for bar data with current period fallback.

  Returns a stream of `{fetch_granularity, date}` tuples. The fetch_granularity
  may differ from the requested granularity due to current period fallback.

  ## Parameters

    * `granularity` - Requested data granularity (`:minute`, `:hour`, or `:day`)
    * `from` - Start datetime (inclusive)
    * `to` - End datetime (exclusive)

  ## Examples

      # Hourly data: one monthly file per month
      iex> periods = PeriodGenerator.bar_periods(:hour, ~U[2019-01-01 00:00:00Z], ~U[2019-04-01 00:00:00Z])
      iex> Enum.to_list(periods)
      [{:hour, ~D[2019-01-01]}, {:hour, ~D[2019-02-01]}, {:hour, ~D[2019-03-01]}]

      # Daily data: one yearly file per year
      iex> periods = PeriodGenerator.bar_periods(:day, ~U[2017-01-01 00:00:00Z], ~U[2020-01-01 00:00:00Z])
      iex> Enum.to_list(periods)
      [{:day, ~D[2017-01-01]}, {:day, ~D[2018-01-01]}, {:day, ~D[2019-01-01]}]

      # Minute data: one daily file per day
      iex> periods = PeriodGenerator.bar_periods(:minute, ~U[2019-01-15 00:00:00Z], ~U[2019-01-19 00:00:00Z])
      iex> Enum.to_list(periods)
      [{:minute, ~D[2019-01-15]}, {:minute, ~D[2019-01-16]}, {:minute, ~D[2019-01-17]}, {:minute, ~D[2019-01-18]}]

  ## Current period fallback

  When fetching data that spans into the current period (year/month/day),
  aggregated files don't exist yet. The generator automatically falls back
  to finer granularities. For example, if today is 2025-03-15:

      # Requesting :day from 2023 to now
      PeriodGenerator.bar_periods(:day, ~U[2023-01-01 00:00:00Z], ~U[2025-03-15 00:00:00Z])
      # Returns:
      # [
      #   {:day, ~D[2023-01-01]},   # 2023 yearly file exists
      #   {:day, ~D[2024-01-01]},   # 2024 yearly file exists
      #   {:hour, ~D[2025-01-01]},  # 2025 falls back to monthly (current year)
      #   {:hour, ~D[2025-02-01]},
      #   {:minute, ~D[2025-03-01]},  # March falls back to daily (current month)
      #   ...
      # ]

  """
  @spec bar_periods(granularity(), DateTime.t(), DateTime.t()) :: Enumerable.t()
  def bar_periods(granularity, from, to) do
    granularity
    |> TimeRange.closest_available_range(from)
    |> periods_for_range(granularity, from, to)
  end

  ## Private functions - Range-specific period generation

  defp periods_for_range(:year, requested_granularity, from, to) do
    start = %DateTime{from | month: 1, day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    unfold_with_fallback(
      start,
      to,
      :year,
      :day,
      requested_granularity,
      &DateTime.shift(&1, year: 1)
    )
  end

  defp periods_for_range(:month, requested_granularity, from, to) do
    start = %DateTime{from | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    unfold_with_fallback(
      start,
      to,
      :month,
      :hour,
      requested_granularity,
      &DateTime.shift(&1, month: 1)
    )
  end

  defp periods_for_range(:day, _requested_granularity, from, to) do
    start = %DateTime{from | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    Stream.unfold(start, fn current ->
      if DateTime.compare(current, to) == :lt do
        {{:minute, DateTime.to_date(current)}, DateTime.add(current, 1, :day)}
      end
    end)
  end

  ## Private functions - Unfold with fallback

  defp unfold_with_fallback(
         start,
         to,
         range_type,
         fetch_granularity,
         requested_granularity,
         next_fn
       ) do
    {start, false}
    |> Stream.unfold(fn
      {_, true} ->
        nil

      {current, _} ->
        unfold_step(current, to, range_type, fetch_granularity, requested_granularity, next_fn)
    end)
    |> expand_fallbacks()
  end

  defp unfold_step(current, to, range_type, fetch_granularity, requested_granularity, next_fn) do
    if DateTime.compare(current, to) == :lt do
      do_unfold_step(current, to, range_type, fetch_granularity, requested_granularity, next_fn)
    end
  end

  defp do_unfold_step(current, to, range_type, fetch_granularity, requested_granularity, next_fn) do
    next = next_fn.(current)
    is_last = DateTime.compare(next, to) != :lt

    if is_last and TimeRange.current_range?(range_type, current) do
      lower_range = TimeRange.lower_range(range_type)
      fallback = periods_for_range(lower_range, requested_granularity, current, to)
      {{:fallback, fallback}, {next, true}}
    else
      {{fetch_granularity, DateTime.to_date(current)}, {next, false}}
    end
  end

  # Expand {:fallback, stream} tuples into their underlying periods
  defp expand_fallbacks(stream) do
    Stream.flat_map(stream, fn
      {:fallback, inner_stream} -> inner_stream
      period -> [period]
    end)
  end

  ## Private functions - Helpers

  defp truncate_to_hour(%DateTime{} = dt) do
    %DateTime{dt | minute: 0, second: 0, microsecond: {0, 0}}
  end
end
