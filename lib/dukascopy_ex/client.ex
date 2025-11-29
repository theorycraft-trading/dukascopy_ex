defmodule DukascopyEx.Client do
  @moduledoc false

  # HTTP client for Dukascopy API using Req.
  # Handles retry, caching, and LZMA decompression via Req steps.

  @base_url "https://datafeed.dukascopy.com/datafeed"
  @default_cache_folder_path ".dukascopy-cache"

  @client_options [
    :retry_count,
    :pause_between_retries_ms,
    :retry_on_empty,
    :use_cache,
    :cache_folder_path,
    :fail_after_retry_count
  ]

  ## Public API

  @doc false
  @spec base_url() :: String.t()
  def base_url(), do: @base_url

  @doc false
  @spec fetch(String.t(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def fetch(path, opts \\ []) do
    opts
    |> build_request()
    |> Req.get(url: path)
    |> handle_response(opts)
  end

  ## Private functions

  defp build_request(opts) do
    client_opts = Keyword.take(opts, @client_options)
    retry_delay = Keyword.get(client_opts, :pause_between_retries_ms, 500)

    Req.new(
      base_url: @base_url,
      retry: &should_retry/2,
      max_retries: Keyword.get(client_opts, :retry_count, 3),
      retry_delay: fn _attempt -> retry_delay end,
      decode_body: false,
      compressed: false
    )
    |> Req.Request.register_options(@client_options)
    |> Req.Request.merge_options(client_opts)
    |> maybe_add_cache_steps(client_opts)
    |> Req.Request.append_response_steps(decompress_lzma: &decompress_lzma/1)
  end

  defp should_retry(request, response_or_error) do
    retry_on_empty = request.options[:retry_on_empty] || false

    case response_or_error do
      %Req.Response{status: 200, body: <<>>} when retry_on_empty -> true
      %Req.Response{status: 200} -> false
      %Req.Response{status: 404} -> false
      %Req.Response{} -> true
      %{__exception__: true} -> true
      _ -> false
    end
  end

  defp decompress_lzma({request, %Req.Response{status: 200, body: body} = response})
       when byte_size(body) > 0 do
    case LZMA.lzma_decompress(body) do
      {:ok, decompressed} -> {request, %Req.Response{response | body: decompressed}}
      {:error, _} = err -> {request, err}
    end
  end

  defp decompress_lzma({request, response}), do: {request, response}

  defp maybe_add_cache_steps(req, opts) do
    if Keyword.get(opts, :use_cache, false) do
      req
      |> Req.Request.prepend_request_steps(cache_read: &cache_read/1)
      |> Req.Request.append_response_steps(cache_write: &cache_write/1)
    else
      req
    end
  end

  defp cache_read(request) do
    cache_path = request.options[:cache_folder_path] || @default_cache_folder_path
    cache_file = cache_file_path(request.url, cache_path)

    case File.read(cache_file) do
      {:ok, data} -> {request, Req.Response.new(status: 200, body: data)}
      {:error, :enoent} -> request
    end
  end

  defp cache_write({request, %Req.Response{status: 200, body: body} = response})
       when byte_size(body) > 0 do
    cache_path = request.options[:cache_folder_path] || @default_cache_folder_path
    cache_file = cache_file_path(request.url, cache_path)

    :ok = File.mkdir_p!(cache_path)
    :ok = File.write!(cache_file, body)

    {request, response}
  end

  defp cache_write({request, response}), do: {request, response}

  defp cache_file_path(url, cache_path) do
    cache_key =
      url
      |> URI.to_string()
      |> String.trim_leading(@base_url <> "/")
      |> String.replace("/", "-")

    Path.join(cache_path, cache_key)
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}, _opts), do: {:ok, body}
  defp handle_response({:ok, %Req.Response{status: 404}}, _opts), do: {:ok, <<>>}

  defp handle_response({:ok, %Req.Response{status: status}}, _opts),
    do: {:error, {:http_error, status}}

  defp handle_response({:error, exception}, opts) do
    if Keyword.get(opts, :fail_after_retry_count, true) do
      {:error, {:retry_exhausted, exception}}
    else
      {:ok, <<>>}
    end
  end
end
