defmodule RepomaticApt.Build do
  @moduledoc """
  Build identification shown in the web UI: the application version from
  `mix.exs` and the short git revision the build was made from.

  Both are captured at compile time. The revision comes from the
  `REPOMATIC_GIT_REV` environment variable when set (the Docker build passes
  it as a build arg, since the image build context has no `.git`), otherwise
  from `git rev-parse` in the source tree, with a `-dirty` suffix when the
  working tree had uncommitted changes. It is `nil` when neither is available.
  """

  @version Mix.Project.config()[:version]

  @git_rev (case System.get_env("REPOMATIC_GIT_REV") do
              rev when is_binary(rev) and rev != "" ->
                rev

              _ ->
                with {rev, 0} <-
                       System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true),
                     {status, 0} <-
                       System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
                  String.trim(rev) <> if(String.trim(status) == "", do: "", else: "-dirty")
                else
                  _ -> nil
                end
            end)

  @display if(@git_rev, do: "v#{@version} (#{@git_rev})", else: "v#{@version}")

  @doc "Application version, e.g. `\"0.2.2\"`."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Short git revision of the build, or `nil` if unknown."
  @spec git_rev() :: String.t() | nil
  def git_rev, do: @git_rev

  @doc "Human-readable build string: `\"v0.2.2 (f5a729c)\"`, or just `\"v0.2.2\"` without a revision."
  @spec display() :: String.t()
  def display, do: @display
end
