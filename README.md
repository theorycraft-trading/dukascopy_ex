# DukascopyEx

[DukascopyEx](https://github.com/theorycraft-trading/dukascopy_ex) is a [TheoryCraft](https://github.com/theorycraft-trading/theory_craft) extension for downloading and streaming historical market data from Dukascopy Bank SA.

Access free historical tick and bar data for 1600+ instruments including Forex, Stocks, Crypto, Commodities, Bonds, ETFs, and Indices.

## ⚠️ Development Status

**This library is under active development and the API is subject to frequent changes.**

Breaking changes may occur between releases as we refine the interface and add new features.

## Installation

Add `dukascopy_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dukascopy_ex, github: "theorycraft-trading/dukascopy_ex"}
  ]
end
```

## Quick Start

### Fetch Tick Data

```elixir
alias DukascopyEx.TickData

# Fetch tick data for EUR/USD on 2024-11-15 at 10:00 UTC
{:ok, ticks} = TickData.fetch("EUR/USD", ~D[2024-11-15], 10)

# Returns TheoryCraft.MarketSource.Tick structs
%TheoryCraft.MarketSource.Tick{
  time: ~U[2024-11-15 10:00:00.123Z],
  ask: 1.05623,
  bid: 1.05621,
  ask_volume: 1.5,
  bid_volume: 2.0
} = hd(ticks)
```

### Stream with TheoryCraft

```elixir
alias TheoryCraft.MarketSource

# Build a pipeline with Dukascopy data
market =
  %MarketSource{}
  # TODO: Add DukascopyEx.DataFeed module here
  |> MarketSource.resample("m5", name: "EURUSD_m5")
  |> MarketSource.resample("h1", name: "EURUSD_h1")

# Stream events through the pipeline
for event <- MarketSource.stream(market) do
  IO.inspect(event)
end
```

### Browse Instruments

```elixir
alias DukascopyEx.Instruments

# Get all 1600+ instruments
Instruments.all()
# => ["EUR/USD", "GBP/USD", "AAPL.US/USD", "BTC/USD", ...]

# Filter by category
Instruments.forex_majors()  # => ["AUD/USD", "EUR/USD", "GBP/USD", ...]
Instruments.forex_crosses() # => ["AUD/CAD", "EUR/GBP", ...]
Instruments.metals()        # => ["XAU/USD", "XAG/USD", ...]
Instruments.stocks()        # => ["AAPL.US/USD", "TSLA.US/USD", ...]
Instruments.commodities()   # => ["BRENT.CMD/USD", "COPPER.CMD/USD", ...]
Instruments.agriculturals() # => ["COCOA.CMD/USD", "COFFEE.CMD/USX", ...]
```

## Features

### Current

- **Tick Data Download**: Fetch historical tick data with bid/ask prices and volumes
- **1600+ Instruments**: Forex, Stocks, Crypto, Commodities, Bonds, ETFs, Indices
- **TheoryCraft Integration**: Native `Tick` struct compatible with TheoryCraft pipelines
- **Instrument Metadata**: Pip values and categorization

### Planned

- **Bar Data**: Download pre-aggregated OHLC bars (m1, m5, m15, m30, h1, h4, d1)
- **Datafeed**: Stream real-time and historical data through GenStage producers
- **Local Storage**: Download and cache data locally for offline backtesting
- **CLI**: Command-line interface for data management
- **Date Range Downloads**: Batch download across date ranges with progress tracking
- **Multiple Output Formats**: CSV, JSON exports

## Instruments

| Category | Count | Examples |
|----------|-------|----------|
| Forex Majors | 7 | EUR/USD, GBP/USD, USD/JPY |
| Forex Crosses | 290+ | EUR/GBP, AUD/NZD, GBP/JPY |
| Metals | 50+ | XAU/USD, XAG/USD, XPT/USD |
| Stocks | 1000+ | AAPL.US/USD, TSLA.US/USD |
| Commodities | 10+ | BRENT.CMD/USD, COPPER.CMD/USD |
| Agriculturals | 6 | COCOA.CMD/USD, COFFEE.CMD/USX |

## Development

```bash
# Run tests (excludes network tests by default)
mix test

# Run tests including network tests
mix test --include network

# Run CI checks (credo + tests)
mix ci

# Update instrument metadata from Dukascopy API
mix dukascopy.gen.instruments
```

## License

Copyright (C) 2025 TheoryCraft Trading

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
