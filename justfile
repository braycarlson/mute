set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

bin := home_directory() / ".local/bin"
data := env("XDG_DATA_HOME", home_directory() / ".local/share")
python := if os_family() == "windows" { "python" } else { "python3" }
release := justfile_directory() / "zig-out/release"
units := env("XDG_CONFIG_HOME", home_directory() / ".config") / "systemd/user"

[doc('Regenerate the glyph atlases and src/ui/atlas.zig')]
atlas:
    {{ python }} tools/atlas.py

[doc('Compile every artifact without running it')]
check:
    zig build check

[doc('Compile every artifact for Linux from any host')]
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu

[doc('Compile every artifact for Windows from any host')]
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Format build.zig and every source file')]
fmt:
    zig fmt build.zig src

[doc('Regenerate the tray pixmaps and the desktop entry images from the icons')]
icons:
    magick 'assets/mute.ico[5]' -background none -alpha on -resize 32x32 -depth 8 rgba:assets/mute.rgba
    magick 'assets/unmute.ico[5]' -background none -alpha on -resize 32x32 -depth 8 rgba:assets/unmute.rgba
    magick 'assets/deafen.ico[5]' -background none -alpha on -resize 32x32 -depth 8 rgba:assets/deafen.rgba
    magick 'assets/undeafen.ico[5]' -background none -alpha on -resize 32x32 -depth 8 rgba:assets/undeafen.rgba
    magick 'assets/unmute.ico[8]' -strip assets/unmute.png
    magick 'assets/undeafen.ico[8]' -strip assets/undeafen.png

[doc('Build a release, install mute, deafen, their user services, and their desktop entries, and restart them on the new build')]
[linux]
install:
    zig build --release=safe --prefix '{{ release }}'
    install -D -m 755 '{{ release }}/bin/mute' '{{ bin }}/mute.new'
    mv -f '{{ bin }}/mute.new' '{{ bin }}/mute'
    install -D -m 755 '{{ release }}/bin/deafen' '{{ bin }}/deafen.new'
    mv -f '{{ bin }}/deafen.new' '{{ bin }}/deafen'
    install -D -m 644 -t '{{ units }}' contrib/mute.service contrib/deafen.service
    install -D -m 644 -t '{{ data }}/applications' contrib/mute.desktop contrib/deafen.desktop
    install -D -m 644 assets/unmute.png '{{ data }}/icons/hicolor/256x256/apps/mute.png'
    install -D -m 644 assets/undeafen.png '{{ data }}/icons/hicolor/256x256/apps/deafen.png'
    touch '{{ data }}/icons/hicolor'
    systemctl --user daemon-reload
    systemctl --user enable mute.service deafen.service
    systemctl --user restart mute.service deafen.service
    sleep 2
    systemctl --user is-active mute.service deafen.service

[doc('Lint build.zig, every source file, and the tools with tigerstyle-lsp')]
lint:
    tigerstyle-lsp check build.zig src tools --format concise

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Build and run the application')]
run:
    zig build run

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Run the end to end tests against the fake libraries: just test-fake [filter]')]
test-fake filter="":
    zig build test:fake {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the unit tests and the tidy check: just test-unit [filter]')]
test-unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}
