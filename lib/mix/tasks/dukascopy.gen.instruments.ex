defmodule Mix.Tasks.Dukascopy.Gen.Instruments do
  @moduledoc """
  Downloads Dukascopy instrument data and saves it to priv/instruments.json

  Fetches instrument data directly from Dukascopy API and saves it as JSON.

  Usage:

      mix dukascopy.gen.instruments

  """

  use Mix.Task

  @shortdoc "Downloads instruments data from Dukascopy API"

  @dukascopy_api_url "https://freeserv.dukascopy.com/2.0/index.php?path=common%2Finstruments&jsonp=_callbacks_._2n9mtpe0f"

  def run(_args) do
    Mix.Task.run("app.start")

    output_file = "priv/instruments.json"

    # Ensure priv directory exists
    File.mkdir_p!("priv")

    IO.puts("Fetching instrument data from Dukascopy API...")
    json_data = fetch_instruments()

    IO.puts("Saving to #{output_file}...")
    File.write!(output_file, Jason.encode!(json_data, pretty: true))

    IO.puts("✓ Downloaded #{output_file}")
  end

  defp fetch_instruments do
    headers = [
      {"User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
      {"Accept", "*/*"},
      {"Referer", "https://freeserv.dukascopy.com/"}
    ]

    case Req.get(@dukascopy_api_url, headers: headers) do
      {:ok, response} ->
        response.body
        |> strip_jsonp()
        |> Jason.decode!()

      {:error, reason} ->
        raise "Failed to fetch instruments from Dukascopy: #{inspect(reason)}"
    end
  end

  defp strip_jsonp(body) do
    # Remove JSONP wrapper: _callbacks_._1m9mtpe0f({...})
    body
    |> String.replace(~r/^[^(]+\(/, "")
    |> String.replace(~r/\)[^)]*$/, "")
  end
end
