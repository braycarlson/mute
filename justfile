set windows-shell := ["cmd.exe", "/c"]

# Default recipe
default:
    @just --list

# Run the whole continuous integration pipeline
ci:
    zig build ci --summary all

# Compile every artifact without running it
check:
    zig build check --summary all

# Compile every artifact for Linux from any host
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu --summary all

# Compile every artifact for Windows from any host
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu --summary all

# Build the applications and install artifacts
build:
    zig build

# Build and run the capture application
run:
    zig build run

# Run every test suite
test:
    zig build test:unit test:mock --summary all

# Run the colocated unit tests and the tidy law, optionally filtered: just unit tidy
unit filter="":
    zig build test:unit --summary all -- {{filter}}

# Drive the application against the mock backends, optionally filtered
mock filter="":
    zig build test:mock --summary all -- {{filter}}

# Run the tidy check on its own
tidy:
    zig build test:unit -- tidy

# Check that every source file is formatted
fmt:
    zig build test:fmt

# Format every source file in place
format:
    zig fmt build.zig src

# Regenerate the tray pixmaps from the icon sources
#
# Frame 5 of each .ico is the 1024x1024 PNG, which downsamples cleanly to the
# 32x32 the tray wants. The committed .rgba files are raw 8 bit RGBA, which is
# the widest raw format ImageMagick 6 writes. src/icon.zig moves the alpha
# channel to the front at comptime, because that is the ARGB order umbra ships
# to both backends.
[unix]
icons:
    convert asset/mute.ico[5] -background none -alpha on -resize 32x32 -depth 8 rgba:asset/mute.rgba
    convert asset/unmute.ico[5] -background none -alpha on -resize 32x32 -depth 8 rgba:asset/unmute.rgba
    convert asset/deafen.ico[5] -background none -alpha on -resize 32x32 -depth 8 rgba:asset/deafen.rgba
    convert asset/undeafen.ico[5] -background none -alpha on -resize 32x32 -depth 8 rgba:asset/undeafen.rgba

# Regenerate the glyph atlases and the metrics table
#
# Renders DejaVu Sans at the two sizes the overlay uses into raw 8 bit coverage
# masks under asset/, and regenerates src/ui/atlas.zig beside them. Needs python3
# with Pillow and the fonts-dejavu-core package, or DEJAVU_FONTS pointing at the
# directory holding it.
[unix]
atlas:
    python3 tool/atlas.py

# Regenerate the glyph atlases and the metrics table
[windows]
atlas:
    python tool/atlas.py

# Build with release safety checks
release:
    zig build -Doptimize=ReleaseSafe

# Build the smallest release binary
release-small:
    zig build -Doptimize=ReleaseSmall

# Clean build artifacts
[unix]
clean:
    rm -rf zig-out .zig-cache

# Clean build artifacts
[windows]
clean:
    if exist zig-out rmdir /s /q zig-out
    if exist .zig-cache rmdir /s /q .zig-cache
