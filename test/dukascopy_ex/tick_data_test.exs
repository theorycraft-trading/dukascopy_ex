defmodule DukascopyEx.TickDataTest do
  use ExUnit.Case, async: true

  alias DukascopyEx.TickData
  alias TheoryCraft.MarketSource.Tick

  doctest DukascopyEx.TickData

  describe "fetch/4" do
    test "returns error for unknown instrument" do
      assert {:error, {:unknown_instrument, "UNKNOWN"}} =
               TickData.fetch("UNKNOWN", ~D[2024-11-15], 10)
    end

    @tag :network
    test "fetches tick data for EUR/USD" do
      assert {:ok, ticks} = TickData.fetch("EUR/USD", ~D[2024-11-15], 10)

      assert length(ticks) > 0
      assert %Tick{time: time, ask: ask, bid: bid} = hd(ticks)
      assert %DateTime{} = time
      assert is_float(ask)
      assert is_float(bid)
    end

    @tag :network
    test "fetches tick data for stocks" do
      {:ok, ticks} = TickData.fetch("AAPL.US/USD", ~D[2024-11-15], 14)

      assert length(ticks) > 0
      assert %Tick{} = hd(ticks)
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
