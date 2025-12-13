defmodule DukascopyEx.DataFeedTest do
  use ExUnit.Case, async: true

  import DukascopyEx.TestAssertions

  alias DukascopyEx.DataFeed
  alias DukascopyEx.TestFixtures

  ## Validation tests

  describe "stream/1 validation" do
    test "returns error when instrument is missing" do
      assert {:error, :missing_instrument} =
               DataFeed.stream(from: ~D[2024-01-01], to: ~D[2024-01-02])
    end

    test "returns error when instrument is unknown" do
      assert {:error, {:unknown_instrument, "UNKNOWN"}} =
               DataFeed.stream(instrument: "UNKNOWN", from: ~D[2024-01-01], to: ~D[2024-01-02])
    end

    test "returns error when date range is missing" do
      assert {:error, :missing_date_range} =
               DataFeed.stream(instrument: "EUR/USD")
    end

    test "returns error when granularity is invalid" do
      assert {:error, {:invalid_granularity, :invalid}} =
               DataFeed.stream(
                 instrument: "EUR/USD",
                 from: ~D[2024-01-01],
                 to: ~D[2024-01-02],
                 granularity: :invalid
               )
    end

    test "returns error when price_type is invalid" do
      assert {:error, {:invalid_price_type, :invalid}} =
               DataFeed.stream(
                 instrument: "EUR/USD",
                 from: ~D[2024-01-01],
                 to: ~D[2024-01-02],
                 price_type: :invalid
               )
    end

    test "returns error when batch_size is zero or negative" do
      assert {:error, {:invalid_positive_integer, :batch_size, 0}} =
               DataFeed.stream(
                 instrument: "EUR/USD",
                 from: ~D[2024-01-01],
                 to: ~D[2024-01-02],
                 batch_size: 0
               )
    end
  end

  ## Error handling tests

  describe "stream/1 error handling" do
    @tag :capture_log
    test "raises on fetch error when halt_on_error is true (default)" do
      stub_opts = TestFixtures.stub_dukascopy_error(:data_feed_halt_error)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~U[2019-02-04 00:00:00Z],
          to: ~U[2019-02-04 01:00:00Z],
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)

      assert_raise RuntimeError, ~r/Fetch failed/, fn ->
        Enum.to_list(stream)
      end
    end

    @tag :capture_log
    test "continues with empty result when halt_on_error is false" do
      stub_opts = TestFixtures.stub_dukascopy_error(:data_feed_continue_error)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~U[2019-02-04 00:00:00Z],
          to: ~U[2019-02-04 01:00:00Z],
          halt_on_error: false,
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)

      assert Enum.to_list(stream) == []
    end
  end

  ## Tick streaming tests

  describe "stream/1 with ticks" do
    test "returns ticks with correct values and chronological order" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_ticks_exact)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~U[2019-02-04 00:00:00Z],
          to: ~U[2019-02-04 00:05:00Z],
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)
      ticks = Enum.take(stream, 100)

      assert length(ticks) == 100
      assert_chronological_order ticks

      # First tick from 00h_ticks.bi5
      [first | _] = ticks
      assert first.time == ~U[2019-02-04 00:00:00.994Z]
      assert first.ask == 1.14545
      assert first.bid == 1.14543
      assert_in_delta first.ask_volume, 1.0, 0.01
      assert_in_delta first.bid_volume, 2.06, 0.01
    end
  end

  ## Bar streaming tests

  describe "stream/1 with minute bars" do
    test "returns m1 bars with correct OHLCV values and 1-minute spacing" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_m1_exact)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~D[2019-02-04],
          to: ~D[2019-02-05],
          granularity: :minute,
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)
      bars = Enum.take(stream, 60)

      assert length(bars) == 60
      assert_uniform_spacing bars, :timer.minutes(1)

      # First m1 bar values
      [first | _] = bars
      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert first.open == 1.14543
      assert first.close == 1.14569
      assert first.low == 1.14542
      assert first.high == 1.14570
      assert_in_delta first.volume, 293.76, 0.01
    end
  end

  describe "stream/1 with hour bars" do
    test "returns h1 bars with correct OHLCV values and 1-hour spacing" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_h1_exact)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~D[2019-02-01],
          to: ~D[2019-02-28],
          granularity: :hour,
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)
      bars = Enum.take(stream, 24)

      assert length(bars) == 24
      assert_uniform_spacing bars, :timer.hours(1)

      # First h1 bar values
      [first | _] = bars
      assert first.time == ~U[2019-02-01 00:00:00Z]
      assert first.open == 1.14482
      assert first.close == 1.14481
      assert first.low == 1.14462
      assert first.high == 1.14499
      assert_in_delta first.volume, 6718.49, 0.01
    end
  end

  describe "stream/1 with day bars" do
    test "returns d1 bars with correct OHLCV values and 1-day spacing" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_daily_exact)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~D[2019-01-01],
          to: ~D[2019-01-31],
          granularity: :day,
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)
      bars = Enum.take(stream, 10)

      assert length(bars) == 10
      assert_uniform_spacing bars, :timer.hours(24)

      # First d1 bar values
      [first | _] = bars
      assert first.time == ~U[2019-01-01 00:00:00Z]
      assert first.open == 1.14598
      assert first.close == 1.14612
      assert first.low == 1.14566
      assert first.high == 1.14676
      assert_in_delta first.volume, 11_818.90, 0.01
    end
  end

  describe "stream/1 with :mid price_type" do
    test "returns bars with averaged OHLC and summed volume" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_mid)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~D[2019-02-04],
          to: ~D[2019-02-05],
          granularity: :minute,
          price_type: :mid,
          batch_size: 2,
          pause_between_batches_ms: 0
        )

      {:ok, stream} = DataFeed.stream(opts)
      [first | _] = Enum.take(stream, 1)

      # mid = (bid + ask) / 2 for OHLC, sum for volume
      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert_in_delta first.open, 1.14544, 0.000001
      assert_in_delta first.high, 1.14572, 0.000001
      assert_in_delta first.low, 1.145435, 0.000001
      assert_in_delta first.close, 1.145715, 0.000001
      assert_in_delta first.volume, 695.63, 0.01
    end
  end

  ## Bang function tests

  describe "stream!/1" do
    test "returns stream directly on success" do
      stub_opts = TestFixtures.stub_dukascopy(:data_feed_bang)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          from: ~U[2019-02-04 00:00:00Z],
          to: ~U[2019-02-04 00:05:00Z],
          batch_size: 1,
          pause_between_batches_ms: 0
        )

      stream = DataFeed.stream!(opts)
      [first | _] = Enum.take(stream, 10)

      assert first.ask == 1.14545
      assert first.bid == 1.14543
    end

    test "raises ArgumentError on validation error" do
      assert_raise ArgumentError, ~r/missing_instrument/, fn ->
        DataFeed.stream!(from: ~D[2024-01-01], to: ~D[2024-01-02])
      end
    end
  end

  ## Period generation tests

  describe "stream/1 period generation" do
    test "fetches exactly 1 file for a 1-day minute bar range" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:period_test_m1)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :minute,
          from: ~D[2019-01-04],
          to: ~D[2019-01-05]
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch exactly 1 file (Jan 4), not Jan 5
      # (to: Jan 5 00:00:00 means we don't need Jan 5's file)
      assert length(paths) == 1
      assert Enum.any?(paths, &String.contains?(&1, "2019/00/04"))
      refute Enum.any?(paths, &String.contains?(&1, "2019/00/05"))
    end

    test "fetches exactly 1 file for a 1-month hourly bar range" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:period_test_h1)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :hour,
          from: ~D[2019-01-01],
          to: ~D[2019-01-31]
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch exactly 1 file (January), not February
      assert length(paths) == 1
      assert Enum.any?(paths, &String.contains?(&1, "2019/00"))
      refute Enum.any?(paths, &String.contains?(&1, "2019/01"))
    end

    test "fetches exactly 1 file for a 1-year daily bar range" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:period_test_d1)

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :day,
          from: ~D[2019-01-01],
          to: ~D[2019-12-31]
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch exactly 1 file (2019), not 2020
      assert length(paths) == 1
      assert Enum.any?(paths, &String.contains?(&1, "2019"))
      refute Enum.any?(paths, &String.contains?(&1, "2020"))
    end
  end

  describe "stream/1 current period fallback" do
    test "fetches minute files for hourly data in current month" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:fallback_h1_current_month)

      # Use current month dates
      now = DateTime.utc_now()
      from = Date.new!(now.year, now.month, 1)
      to = Date.new!(now.year, now.month, min(now.day, 2))

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :hour,
          from: from,
          to: to
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch minute files (candles_min_1), not hourly files (candles_hour_1)
      # because current month's hourly file doesn't exist yet
      assert length(paths) > 0
      assert Enum.all?(paths, &String.contains?(&1, "candles_min_1"))
      refute Enum.any?(paths, &String.contains?(&1, "candles_hour_1"))
    end

    test "fetches hourly file for hourly data in past month" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:fallback_h1_past_month)

      # Use past month dates (November 2019)
      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :hour,
          from: ~D[2019-11-01],
          to: ~D[2019-11-30]
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch hourly file, not minute files
      assert length(paths) == 1
      assert Enum.all?(paths, &String.contains?(&1, "candles_hour_1"))
    end

    test "fetches hourly files for daily data in current year" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:fallback_d1_current_year)

      # Use current year dates (but past months to avoid double fallback)
      now = DateTime.utc_now()
      from = Date.new!(now.year, 1, 1)

      # Use past month to avoid double fallback (day→hour + hour→minute)
      to =
        if now.month > 1 do
          Date.new!(now.year, now.month - 1, 1)
        else
          # January: use December of previous year
          Date.new!(now.year - 1, 12, 1)
        end

      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :day,
          from: from,
          to: to
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch hourly files (candles_hour_1), not daily files (candles_day_1)
      # because current year's daily file doesn't exist yet
      assert length(paths) > 0
      assert Enum.all?(paths, &String.contains?(&1, "candles_hour_1"))
      refute Enum.any?(paths, &String.contains?(&1, "candles_day_1"))
    end

    test "fetches daily file for daily data in past year" do
      {stub_opts, tracker} = TestFixtures.stub_dukascopy_with_tracking(:fallback_d1_past_year)

      # Use past year dates (2019)
      opts =
        Keyword.merge(stub_opts,
          instrument: "EUR/USD",
          granularity: :day,
          from: ~D[2019-01-01],
          to: ~D[2019-06-30]
        )

      {:ok, stream} = DataFeed.stream(opts)
      Stream.run(stream)

      paths = TestFixtures.get_request_paths(tracker)

      # Should fetch daily file, not hourly files
      assert length(paths) == 1
      assert Enum.all?(paths, &String.contains?(&1, "candles_day_1"))
    end
  end
end
