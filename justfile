set shell := ["cmd", "/c"]

# Default recipe
default:
    @just --list

# Build and run mute (mode: debug, release-safe, release-fast, release-small)
mute mode="debug":
    cls && just clean && zig build {{ if mode == "debug" { "" } else if mode == "release-safe" { "-Doptimize=ReleaseSafe" } else if mode == "release-fast" { "-Doptimize=ReleaseFast" } else if mode == "release-small" { "-Doptimize=ReleaseSmall" } else { "" } }} && zig-out\bin\mute.exe

# Build and run deafen (mode: debug, release-safe, release-fast, release-small)
deafen mode="debug":
    cls && just clean && zig build {{ if mode == "debug" { "" } else if mode == "release-safe" { "-Doptimize=ReleaseSafe" } else if mode == "release-fast" { "-Doptimize=ReleaseFast" } else if mode == "release-small" { "-Doptimize=ReleaseSmall" } else { "" } }} && zig-out\bin\deafen.exe

# Build both without running
build mode="debug":
    cls && just clean && zig build {{ if mode == "debug" { "" } else if mode == "release-safe" { "-Doptimize=ReleaseSafe" } else if mode == "release-fast" { "-Doptimize=ReleaseFast" } else if mode == "release-small" { "-Doptimize=ReleaseSmall" } else { "" } }}

# Clean build artifacts
clean:
    cls
    if exist zig-out rd /s /q zig-out
    if exist .zig-cache rd /s /q .zig-cache

# Build in release mode (ReleaseSafe)
release:
    cls && just clean && zig build -Doptimize=ReleaseSafe
