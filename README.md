# Chet

Chet is a macOS disk usage treemap and cleanup app. It scans a directory, draws a squarified treemap of what is using space, and can move reclaimable caches, logs, and build output to the Trash.

## Requirements

- macOS 14 or later
- Swift 6 command-line tools (Xcode, or the Swift toolchain that provides `swift build`)

## Build

```sh
swift build
```

## Run

```sh
swift run
```

`./run.sh` does the same thing. On launch Chet scans your home directory, or reloads the last scan from its cache.

## App bundle

```sh
./scripts/build-app.sh release
```

That produces `dist/Chet.app`. Install it with `./scripts/install-app.sh`, which copies the bundle to `/Applications/Chet.app`.

## License

Chet is licensed under the MIT License. See [LICENSE](LICENSE). Copyright (c) 2026 shawnaydelotte.
