defmodule RepomaticApt.Test.DebHelper do
  @moduledoc false

  def build_deb(fields) when is_list(fields) do
    control = Enum.map_join(fields, "\n", fn {k, v} -> "#{k}: #{v}" end) <> "\n"
    control_tar_gz = make_control_tar_gz(control)
    make_ar([{"debian-binary", "2.0\n"}, {"control.tar.gz", control_tar_gz}, {"data.tar.gz", ""}])
  end

  def build_deb(name, version, arch) do
    build_deb([
      {"Package", name},
      {"Version", version},
      {"Architecture", arch},
      {"Maintainer", "Test <test@example.com>"},
      {"Description", "Test package #{name}"}
    ])
  end

  defp make_control_tar_gz(control_content) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_deb_helper_#{:erlang.unique_integer([:positive])}.tar"
      )

    :ok = :erl_tar.create(~c"#{tmp}", [{~c"./control", control_content}])
    tar_data = File.read!(tmp)
    File.rm!(tmp)
    :zlib.gzip(tar_data)
  end

  defp make_ar(members) do
    body =
      Enum.reduce(members, <<>>, fn {name, data}, acc ->
        padded_name = String.pad_trailing(name <> "/", 16)
        size_str = String.pad_trailing(Integer.to_string(byte_size(data)), 10)
        filler = String.pad_trailing("", 32)
        header = padded_name <> filler <> size_str <> "`\n"
        padding = if rem(byte_size(data), 2) == 1, do: "\n", else: ""
        acc <> header <> data <> padding
      end)

    "!<arch>\n" <> body
  end
end
