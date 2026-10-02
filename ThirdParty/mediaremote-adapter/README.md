# MediaRemoteAdapter (third party)

`MediaRemoteAdapter.framework` and `mediaremote-adapter.pl` are the work of Jonas van den Berg and contributors,
redistributed unmodified under the BSD 3-Clause License (see `LICENSE`).

They let iSland read what is playing (any app that registers with the system's Now Playing: Music, Spotify, a
browser tab...). macOS 15.4 restricted the private MediaRemote framework to Apple-signed processes; the trick is to
load the framework from `/usr/bin/perl`, which is allowed. iSland starts the script as a child process and reads the
JSON lines it prints.

The binary was taken from the boring.notch repository's `mediaremote-adapter` folder. The framework is a universal
binary (arm64 and x86_64). Package scripts copy it into `iSland.app/Contents/Frameworks` and re-sign it.
