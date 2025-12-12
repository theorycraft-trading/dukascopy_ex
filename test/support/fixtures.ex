defmodule DukascopyEx.TestFixtures do
  @moduledoc false

  @fixtures_path "test/fixtures"

  ## Public API

  def fixtures_path(), do: @fixtures_path

  def fixture_path(path), do: Path.join(@fixtures_path, path)

  def read_fixture(path), do: File.read(fixture_path(path))
  def read_fixture!(path), do: File.read!(fixture_path(path))

  @doc """
  Creates a Req.Test stub that serves fixtures based on the request path.

  The stub maps `/datafeed/INSTRUMENT/...` paths to fixture files.
  Returns 404 for paths that don't have a corresponding fixture.
  """
  def stub_dukascopy(name \\ __MODULE__) do
    Req.Test.stub(name, fn conn ->
      fixture_file = path_to_fixture(conn.request_path)

      case read_fixture(fixture_file) do
        {:ok, data} -> Plug.Conn.send_resp(conn, 200, data)
        {:error, :enoent} -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    [plug: {Req.Test, name}, retry_log_level: false, retry_delay: 0]
  end

  @doc """
  Creates a Req.Test stub that always returns an error status code.
  """
  def stub_dukascopy_error(name \\ __MODULE__, status \\ 500) do
    Req.Test.stub(name, fn conn ->
      Plug.Conn.send_resp(conn, status, "Internal Server Error")
    end)

    [plug: {Req.Test, name}, retry_log_level: false, retry_delay: 0, max_retries: 0]
  end

  @doc """
  Creates a Req.Test stub that counts requests and stores paths.
  Returns `{opts, tracker_pid}`. Call `get_request_paths(tracker_pid)` after consuming the stream.
  """
  def stub_dukascopy_with_tracking(name \\ __MODULE__) do
    {:ok, tracker} = Agent.start_link(fn -> [] end)

    Req.Test.stub(name, fn conn ->
      Agent.update(tracker, fn paths -> [conn.request_path | paths] end)

      fixture_file = path_to_fixture(conn.request_path)

      case read_fixture(fixture_file) do
        {:ok, data} -> Plug.Conn.send_resp(conn, 200, data)
        {:error, :enoent} -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    opts = [plug: {Req.Test, name}, retry_log_level: false, retry_delay: 0]
    {opts, tracker}
  end

  @doc """
  Returns the list of request paths made since `stub_dukascopy_with_tracking/1` was called.
  """
  def get_request_paths(tracker) do
    Agent.get(tracker, fn paths -> Enum.reverse(paths) end)
  end

  ## Private functions

  defp path_to_fixture("/datafeed/" <> rest), do: rest
  defp path_to_fixture(path), do: path
end
