defmodule DukascopyEx do
  @moduledoc """
  Elixir client for downloading historical market data from Dukascopy Bank SA.

  Supports 1600+ instruments including Forex, Stocks, Crypto, Commodities, Bonds, ETFs, and Indices.

  ## Usage

  The main function is `stream/3` which returns a lazy stream of market data:

      # Stream raw ticks
      DukascopyEx.stream("EUR/USD", :ticks, from: ~D[2024-01-01], to: ~D[2024-01-02])
      |> Enum.take(100)

      # Stream 5-minute bars
      DukascopyEx.stream("EUR/USD", "m5", from: ~D[2024-01-01], to: ~D[2024-01-31])
      |> Enum.to_list()

      # Stream hourly bars with options
      DukascopyEx.stream("EUR/USD", "h1",
        from: ~D[2024-01-01],
        to: ~D[2024-12-31],
        price_type: :mid,
        timezone: "America/New_York"
      )

  ## Supported Timeframes

    - `:ticks` - Raw tick data
    - `"t<N>"` - N ticks per bar (e.g., "t5")
    - `"s<N>"` - N-second bars (e.g., "s30")
    - `"m<N>"` - N-minute bars (e.g., "m1", "m5", "m15")
    - `"h<N>"` - N-hour bars (e.g., "h1", "h4")
    - `"D<N>"` - N-day bars (e.g., "D", "D3")
    - `"W<N>"` - N-week bars (e.g., "W")
    - `"M<N>"` - N-month bars (e.g., "M")

  """

  alias DukascopyEx.{Options, StreamBuilder}

  @type timeframe :: :ticks | String.t()

  @doc """
  Creates a lazy stream of ticks or bars for an instrument and time period.

  ## Parameters

    * `instrument` - Trading instrument (e.g., "EUR/USD", "AAPL.US/USD")
    * `timeframe` - Target timeframe: `:ticks` or a TheoryCraft timeframe string
    * `opts` - Options keyword list (see below)

  ## Required Options

    * `:from` and `:to` - Start and end of the date range (DateTime or Date)
    * OR `:date_range` - A `Date.Range` struct (e.g., `Date.range(~D[2024-01-01], ~D[2024-01-31])`)

  ## Optional Options

    * `:price_type` - `:bid` (default), `:ask`, or `:mid`
    * `:utc_offset` - Fixed UTC offset as Time (default: `~T[00:00:00]`)
    * `:timezone` - Timezone string with DST support (default: `"Etc/UTC"`)
    * `:volume_units` - `:millions` (default), `:thousands`, or `:units`
    * `:ignore_flats` - Ignore zero-volume data (default: `true`)
    * `:batch_size` - Number of parallel requests per batch (default: `10`)
    * `:pause_between_batches_ms` - Pause between batches in ms (default: `1000`)
    * `:use_cache` - Enable file caching (default: `false`)
    * `:cache_folder_path` - Cache folder path (default: `".dukascopy-cache"`)
    * `:retry_count` - Number of retries per request (default: `3`)
    * `:retry_on_empty` - Retry on empty response (default: `false`)
    * `:fail_after_retry_count` - Raise error after all retries exhausted (default: `true`)
    * `:pause_between_retries_ms` - Pause between retries in ms (default: `500`)
    * `:market_open` - Market open time for daily/weekly/monthly alignment (default: `~T[00:00:00]`)
    * `:weekly_open` - Day the week starts (default: `:monday`)

  ## Returns

  A `Stream` that yields `TheoryCraft.MarketSource.Tick` or `TheoryCraft.MarketSource.Bar` structs.

  ## Examples

      # Raw ticks for a single day
      DukascopyEx.stream("EUR/USD", :ticks, from: ~D[2024-11-15], to: ~D[2024-11-16])
      |> Enum.take(1000)

      # 5-minute bars with mid price
      DukascopyEx.stream("EUR/USD", "m5",
        from: ~D[2024-01-01],
        to: ~D[2024-01-31],
        price_type: :mid
      )
      |> Enum.to_list()

      # Daily bars with caching enabled
      DukascopyEx.stream("EUR/USD", "D",
        date_range: Date.range(~D[2020-01-01], ~D[2024-01-01]),
        use_cache: true
      )
      |> Enum.to_list()

      # Weekly bars with custom market open time
      DukascopyEx.stream("EUR/USD", "W",
        from: ~D[2024-01-01],
        to: ~D[2024-12-31],
        market_open: ~T[17:00:00],
        weekly_open: :sunday
      )
      |> Enum.to_list()

  """
  @spec stream(String.t(), timeframe(), Keyword.t()) :: Enumerable.t()
  def stream(instrument, timeframe, opts \\ []) do
    validated_opts = Options.validate!(instrument, timeframe, opts)
    StreamBuilder.build(instrument, timeframe, validated_opts)
  end
end
