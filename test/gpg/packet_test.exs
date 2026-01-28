defmodule RepomaticApt.Gpg.PacketTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Gpg.Packet

  describe "encode_mpi/1" do
    test "encodes zero" do
      assert Packet.encode_mpi(<<>>) == <<0::16>>
    end

    test "encodes single byte" do
      # 0xFF = 255, 8 bits
      assert Packet.encode_mpi(<<0xFF>>) == <<0, 8, 0xFF>>
    end

    test "encodes multi-byte value" do
      # 0x01, 0x00 = 256, 9 bits
      assert Packet.encode_mpi(<<1, 0>>) == <<0, 9, 1, 0>>
    end

    test "strips leading zeros" do
      assert Packet.encode_mpi(<<0, 0, 0xFF>>) == <<0, 8, 0xFF>>
    end

    test "leading bit count is correct for partial byte" do
      # 0x7F = 0111_1111 = 7 significant bits
      assert Packet.encode_mpi(<<0x7F>>) == <<0, 7, 0x7F>>
    end
  end

  describe "encode_old_packet/2" do
    test "encodes short packet (1-byte length)" do
      body = "hello"
      packet = Packet.encode_old_packet(6, body)
      # Tag 6, length type 0: tag_byte = 0x80 | (6 << 2) | 0 = 0x98
      assert <<0x98, 5, "hello">> = packet
    end

    test "encodes packet with 2-byte length" do
      body = :binary.copy(<<0>>, 300)
      packet = Packet.encode_old_packet(2, body)
      # Tag 2, length type 1: tag_byte = 0x80 | (2 << 2) | 1 = 0x89
      assert <<0x89, 1, 44, _body::binary-size(300)>> = packet
    end

    test "tag 13 (User ID)" do
      body = "Test User"
      packet = Packet.encode_old_packet(13, body)
      # Tag 13, length type 0: 0x80 | (13 << 2) | 0 = 0xB4
      assert <<0xB4, 9, "Test User">> = packet
    end
  end

  describe "encode_subpacket/2" do
    test "short subpacket" do
      sp = Packet.encode_subpacket(2, <<0, 0, 0, 1>>)
      # length = 5 (1 type + 4 data), type = 2
      assert <<5, 2, 0, 0, 0, 1>> = sp
    end
  end
end
