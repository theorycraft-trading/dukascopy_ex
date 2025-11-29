defmodule DukascopyEx.TickDataTest do
  use ExUnit.Case, async: true

  alias DukascopyEx.TickData
  alias TheoryCraft.MarketSource.Tick

  ## Tests

  doctest DukascopyEx.TickData

  describe "fetch/4" do
    test "returns error for unknown instrument" do
      assert {:error, {:unknown_instrument, "UNKNOWN"}} =
               TickData.fetch("UNKNOWN", ~D[2024-11-15], 10)
    end

    @tag :network
    test "fetches tick data for EUR/USD" do
      date = ~D[2024-11-15]
      hour = 10

      assert {:ok, ticks} = TickData.fetch("EUR/USD", date, hour)
      assert length(ticks) > 0

      assert %Tick{time: time, ask: ask, bid: bid} = hd(ticks)
      assert %DateTime{year: 2024, month: 11, day: 15, hour: 10} = time
      assert is_float(ask)
      assert is_float(bid)
    end

    @tag :network
    test "fetches tick data for stocks" do
      date = ~D[2024-11-15]
      hour = 14

      assert {:ok, ticks} = TickData.fetch("AAPL.US/USD", date, hour)
      assert length(ticks) > 0

      assert %Tick{time: time} = hd(ticks)
      assert %DateTime{year: 2024, month: 11, day: 15, hour: 14} = time
    end
  end

  describe "fetch!/4" do
    test "raises on unknown instrument" do
      assert_raise RuntimeError, ~r/unknown_instrument/, fn ->
        TickData.fetch!("UNKNOWN", ~D[2024-11-15], 10)
      end
    end
  end
end
