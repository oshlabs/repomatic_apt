ExUnit.start()

# Generate a test signing key (2048 bits for speed)
signing_key =
  RepomaticApt.Gpg.Key.generate(
    bits: 2048,
    uid: "Test <test@example.com>",
    creation_time: 1_700_000_000
  )

Application.put_env(:repomatic_apt, :signing_key, signing_key)
