defmodule RepomaticApt.Store.Backend do
  @moduledoc """
  Behaviour for pluggable storage backends.

  All paths are relative — the backend's state holds any root prefix
  (filesystem path, bucket name, etc.).

  Implementations must ensure `put/3` is atomic where the underlying
  storage supports it (e.g. temp-file + rename on local filesystems).
  """

  @type state :: term()
  @type path :: String.t()

  @callback put(state(), path(), iodata()) :: :ok | {:error, term()}
  @callback get(state(), path()) :: {:ok, binary()} | {:error, term()}
  @callback delete(state(), path()) :: :ok | {:error, term()}
  @callback exists?(state(), path()) :: boolean()
  @callback list(state(), path()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Return the absolute filesystem path for the given relative path.

  Only local backends implement this — it enables zero-copy `Plug.Conn.send_file`.
  Remote backends should not implement this callback.
  """
  @callback file_path(state(), path()) :: String.t() | nil

  @optional_callbacks [file_path: 2]
end
