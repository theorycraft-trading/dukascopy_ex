defmodule DukascopyExTest do
  use ExUnit.Case, async: true

  import DukascopyEx.TestAssertions

  alias DukascopyEx.TestFixtures

  ## Validation tests

  describe "stream/3 validation" do
    test "raises on missing date range" do
      assert_raise ArgumentError, ~r/Missing date range/, fn ->
        DukascopyEx.stream("EUR/USD", :ticks, [])
      end
    end

    test "raises on unknown instrument" do
      assert_raise ArgumentError, ~r/Unknown instrument/, fn ->
        DukascopyEx.stream("UNKNOWN", :ticks, from: ~D[2024-01-01], to: ~D[2024-01-02])
      end
    end

    test "raises on invalid timeframe" do
      assert_raise ArgumentError, ~r/Invalid timeframe/, fn ->
        DukascopyEx.stream("EUR/USD", "invalid", from: ~D[2024-01-01], to: ~D[2024-01-02])
      end
    end

    test "raises on invalid price_type" do
      assert_raise ArgumentError, ~r/Invalid price_type/, fn ->
        DukascopyEx.stream("EUR/USD", :ticks,
          from: ~D[2024-01-01],
          to: ~D[2024-01-02],
          price_type: :invalid
        )
      end
    end
  end

  ## Tick streaming tests

  describe "stream/3 with :ticks" do
    test "streams first tick with exact values" do
      opts =
        TestFixtures.stub_dukascopy(:stream_ticks_exact)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 00:05:00Z])

      [first | _] = DukascopyEx.stream("EUR/USD", :ticks, opts) |> Enum.take(10)

      assert first.time == ~U[2019-02-04 00:00:00.994Z]
      assert first.ask == 1.14545
      assert first.bid == 1.14543
      assert first.ask_volume == 1.0
      assert_in_delta first.bid_volume, 2.06, 0.01
    end

    test "streams multiple ticks in chronological order" do
      opts =
        TestFixtures.stub_dukascopy(:stream_ticks_order)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 00:05:00Z])

      ticks = DukascopyEx.stream("EUR/USD", :ticks, opts) |> Enum.to_list()

      assert length(ticks) == 589
      assert_chronological_order ticks

      second = Enum.at(ticks, 1)
      assert second.time == ~U[2019-02-04 00:00:01.271Z]
      assert second.ask == 1.14546
      assert second.bid == 1.14544
    end

    test "filters by date range" do
      from = ~U[2019-02-04 00:00:00Z]
      to = ~U[2019-02-04 00:01:00Z]

      opts =
        TestFixtures.stub_dukascopy(:stream_ticks_range)
        |> Keyword.merge(from: from, to: to)

      ticks = DukascopyEx.stream("EUR/USD", :ticks, opts) |> Enum.to_list()

      assert length(ticks) > 0

      Enum.each(ticks, fn tick ->
        assert DateTime.compare(tick.time, from) != :lt
        assert DateTime.compare(tick.time, to) == :lt
      end)
    end

    test "converts volume_units to units" do
      base_opts =
        TestFixtures.stub_dukascopy(:stream_ticks_volume)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 00:01:00Z])

      [tick_millions | _] =
        DukascopyEx.stream("EUR/USD", :ticks, Keyword.put(base_opts, :volume_units, :millions))
        |> Enum.take(1)

      [tick_units | _] =
        DukascopyEx.stream("EUR/USD", :ticks, Keyword.put(base_opts, :volume_units, :units))
        |> Enum.take(1)

      assert_in_delta tick_units.bid_volume, tick_millions.bid_volume * 1_000_000, 1
    end
  end

  ## Bar streaming tests

  describe "stream/3 with m1 bars" do
    test "streams first m1 bar with exact values" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m1_exact)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      [first | _] = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.take(10)

      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert first.open == 1.14543
      assert first.close == 1.14569
      assert first.low == 1.14542
      assert first.high == 1.14570
      assert_in_delta first.volume, 293.76, 0.01
    end

    test "streams m1 bars 1 minute apart" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m1_spacing)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.to_list()

      assert length(bars) == 1440
      assert_uniform_spacing bars, :timer.minutes(1)
    end
  end

  describe "stream/3 with m5 bars (resampled from m1)" do
    test "streams m5 bars 5 minutes apart" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m5)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.to_list()

      assert length(bars) == 288
      assert_uniform_spacing bars, :timer.minutes(5)
    end

    test "m5 bars have valid OHLC values" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m5_ohlc)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.to_list()

      assert length(bars) == 288

      Enum.each(bars, fn bar ->
        assert bar.high >= bar.low
        assert bar.high >= bar.open
        assert bar.high >= bar.close
        assert bar.low <= bar.open
        assert bar.low <= bar.close
      end)
    end
  end

  describe "stream/3 with h1 bars" do
    test "streams first h1 bar with exact values" do
      opts =
        TestFixtures.stub_dukascopy(:stream_h1_exact)
        |> Keyword.merge(from: ~D[2019-02-01], to: ~D[2019-02-28])

      [first | _] = DukascopyEx.stream("EUR/USD", "h1", opts) |> Enum.take(24)

      assert first.time == ~U[2019-02-01 00:00:00Z]
      assert first.open == 1.14482
      assert first.close == 1.14481
      assert first.low == 1.14462
      assert first.high == 1.14499
    end

    test "streams h4 bars 4 hours apart" do
      opts =
        TestFixtures.stub_dukascopy(:stream_h4)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-06])

      bars = DukascopyEx.stream("EUR/USD", "h4", opts) |> Enum.to_list()

      assert length(bars) == 12
      assert_uniform_spacing bars, :timer.hours(4)
    end
  end

  describe "stream/3 with daily bars" do
    test "streams first daily bar with exact values" do
      opts =
        TestFixtures.stub_dukascopy(:stream_daily_exact)
        |> Keyword.merge(from: ~D[2019-01-01], to: ~D[2019-01-31])

      [first | _] = DukascopyEx.stream("EUR/USD", "D", opts) |> Enum.take(30)

      assert first.time == ~U[2019-01-01 00:00:00Z]
      assert first.open == 1.14598
      assert first.close == 1.14612
      assert first.low == 1.14566
      assert first.high == 1.14676
    end
  end

  ## Caching tests

  describe "stream/3 caching" do
    test "caches data to disk when use_cache is true" do
      cache_path = Path.join(System.tmp_dir!(), "dukascopy_test_cache_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(cache_path) end)

      opts =
        TestFixtures.stub_dukascopy(:stream_cache)
        |> Keyword.merge(
          from: ~U[2019-02-04 00:00:00Z],
          to: ~U[2019-02-04 01:00:00Z],
          use_cache: true,
          cache_folder_path: cache_path
        )

      ticks1 = DukascopyEx.stream("EUR/USD", :ticks, opts) |> Enum.to_list()

      assert File.exists?(cache_path)
      assert length(File.ls!(cache_path)) > 0

      ticks2 = DukascopyEx.stream("EUR/USD", :ticks, opts) |> Enum.to_list()

      assert length(ticks1) == length(ticks2)

      [first1 | _] = ticks1
      [first2 | _] = ticks2
      assert first1.time == first2.time
      assert first1.ask == first2.ask
    end
  end

  ## Aggregation tests

  describe "stream/3 tick to m1 aggregation" do
    test "first m1 bar has exact OHLCV values from ticks" do
      opts =
        TestFixtures.stub_dukascopy(:agg_tick_to_m1)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      [first | _] = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.take(5)

      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert first.open == 1.14543
      assert first.high == 1.14570
      assert first.low == 1.14542
      assert first.close == 1.14569
      assert_in_delta first.volume, 293.76, 0.1
    end

    test "multiple m1 bars have correct values" do
      opts =
        TestFixtures.stub_dukascopy(:agg_tick_to_m1_multi)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      bars = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.take(10)
      second = Enum.at(bars, 1)

      assert second.time == ~U[2019-02-04 00:01:00Z]
      assert second.open == 1.14569
      assert second.close == 1.14575
      assert_in_delta second.volume, 271.59, 0.1
    end
  end

  describe "stream/3 tick to m5 aggregation" do
    test "first m5 bar aggregates 5 minutes of ticks" do
      opts =
        TestFixtures.stub_dukascopy(:agg_tick_to_m5)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      [first | _] = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.take(3)

      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert first.open == 1.14543
      assert first.volume > 1000
    end

    test "m5 bars are 5 minutes apart" do
      opts =
        TestFixtures.stub_dukascopy(:agg_m5_spacing)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.to_list()

      assert length(bars) == 12
      assert_uniform_spacing bars, :timer.minutes(5)
    end
  end

  describe "stream/3 m1 to h1 aggregation" do
    test "h1 bar aggregates 60 m1 bars" do
      opts =
        TestFixtures.stub_dukascopy(:agg_m1_to_h1)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      [first | _] = DukascopyEx.stream("EUR/USD", "h1", opts) |> Enum.take(3)

      assert first.time == ~U[2019-02-04 00:00:00Z]
      assert first.open == 1.14543
      assert first.volume > 5000
    end

    test "h1 bars are 1 hour apart" do
      opts =
        TestFixtures.stub_dukascopy(:agg_h1_spacing_from_m1)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "h1", opts) |> Enum.take(24)

      assert length(bars) == 24
      assert_uniform_spacing bars, :timer.hours(1)
    end
  end

  ## OHLC integrity tests

  describe "OHLC integrity" do
    test "OHLC values are valid" do
      opts =
        TestFixtures.stub_dukascopy(:ohlc_integrity)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.take(10)

      Enum.each(bars, fn bar ->
        assert bar.high >= bar.open
        assert bar.high >= bar.close
        assert bar.high >= bar.low
        assert bar.low <= bar.open
        assert bar.low <= bar.close
      end)
    end
  end

  ## Bar flags tests

  describe "bar flags" do
    test "resampled bars have new_bar? set to true" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m5)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.to_list()

      assert length(bars) == 288
      assert Enum.all?(bars, & &1.new_bar?)
    end

    test "first bar after market_open has new_market? set to true" do
      opts =
        TestFixtures.stub_dukascopy(:stream_m5)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05], market_open: ~T[08:00:00])

      bars = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.to_list()

      new_market_bars = Enum.filter(bars, & &1.new_market?)

      # Should have exactly one new_market bar (at 08:00)
      assert length(new_market_bars) == 1
      [market_open_bar] = new_market_bars
      assert market_open_bar.time.hour == 8
      assert market_open_bar.time.minute == 0
    end
  end

  describe "stream/3 h4 aggregation" do
    test "h4 bars are 4 hours apart" do
      opts =
        TestFixtures.stub_dukascopy(:agg_h4)
        |> Keyword.merge(from: ~D[2019-02-04], to: ~D[2019-02-05])

      bars = DukascopyEx.stream("EUR/USD", "h4", opts) |> Enum.to_list()

      assert length(bars) == 6
      assert_uniform_spacing bars, :timer.hours(4)
    end
  end

  ## Volume aggregation tests

  describe "volume aggregation" do
    test "m5 volume is sum of m1 volumes" do
      opts =
        TestFixtures.stub_dukascopy(:volume_agg)
        |> Keyword.merge(from: ~U[2019-02-04 00:00:00Z], to: ~U[2019-02-04 01:00:00Z])

      m1_bars = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.take(5)
      [m5_first] = DukascopyEx.stream("EUR/USD", "m5", opts) |> Enum.take(1)

      m1_volume_sum = Enum.reduce(m1_bars, 0, fn b, acc -> acc + b.volume end)
      assert_in_delta m5_first.volume, m1_volume_sum, 1
    end
  end

  ## Ignore flats tests

  describe "ignore_flats option" do
    test "filters out zero-volume bars when true" do
      opts =
        TestFixtures.stub_dukascopy(:ignore_flats_test)
        |> Keyword.merge(from: ~D[2020-05-01], to: ~D[2020-05-02])

      all_bars =
        DukascopyEx.stream("EUR/USD", "m1", Keyword.put(opts, :ignore_flats, false))
        |> Enum.to_list()

      flat_count = Enum.count(all_bars, &(&1.volume == 0.0))
      assert flat_count > 0, "Fixture must contain flat bars"

      filtered_bars =
        DukascopyEx.stream("EUR/USD", "m1", Keyword.put(opts, :ignore_flats, true))
        |> Enum.to_list()

      assert Enum.all?(filtered_bars, &(&1.volume > 0))
      assert length(filtered_bars) == length(all_bars) - flat_count
    end

    test "keeps zero-volume bars when false" do
      opts =
        TestFixtures.stub_dukascopy(:ignore_flats_test)
        |> Keyword.merge(from: ~D[2020-05-01], to: ~D[2020-05-02], ignore_flats: false)

      bars = DukascopyEx.stream("EUR/USD", "m1", opts) |> Enum.to_list()

      flat_count = Enum.count(bars, &(&1.volume == 0.0))
      assert flat_count == 180
      assert length(bars) == 1440
    end
  end
end
