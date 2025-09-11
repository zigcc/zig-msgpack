# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a MessagePack implementation library for Zig, providing serialization and deserialization capabilities with full MessagePack specification support including timestamp extensions.

## Development Commands

### Build and Test
```bash
# Run all unit tests
zig build test

# Run tests with detailed output
zig build test --summary all

# Generate documentation
zig build docs
```

### Zig Version Compatibility
- **Currently supports**: Zig 0.14.0 and 0.15.x
- **Partial support**: Zig 0.16 (nightly) - may have compatibility issues
- **Legacy support**: Zig 0.11-0.13 (use library version 0.0.6 for Zig 0.13 and older)
- Code uses version detection (`builtin.zig_version.minor`) to handle API differences:
  - Endianness enum changes (`.Big`/`.Little` vs `.big`/`.little`)
  - ArrayList API changes in Zig 0.15+ (allocator parameter required for methods)
  - Build system API differences between versions

## Architecture

### Core Structure

The library consists of three main files:
- `src/msgpack.zig`: Core implementation with Pack/Unpack functionality and Payload type system
- `src/test.zig`: Comprehensive test suite
- `build.zig`: Build configuration with version compatibility handling

### Key Components

**Payload Union Type**: Central data representation supporting all MessagePack types:
- Basic types: nil, bool, int, uint, float
- Container types: array, map
- Binary types: str, bin, ext
- Special type: timestamp (extension type -1)

**Pack Generic Function**: Template-based packer/unpacker that works with any Read/Write context:
- Handles endianness conversion (MessagePack uses big-endian)
- Supports streaming serialization/deserialization
- Memory efficient with configurable allocators

**Type Wrappers**: Special wrapper types for structured data:
- `Str`, `Bin`, `EXT`, `Timestamp` - provide type safety and convenience methods
- `wrapStr()`, `wrapBin()`, `wrapEXT()` - helper functions for creating wrapped types

### MessagePack Format Implementation

The library implements the complete MessagePack specification:
- Fixed-size formats for small integers and strings
- Variable-size formats with size prefixes
- Extension type system with timestamp support (type -1)
- Proper handling of signed/unsigned integer boundaries

### Memory Management

- All dynamic allocations go through provided Allocator
- Payload types that allocate memory must be freed with `payload.free(allocator)`
- Container types (array, map) manage their child elements' memory

## Testing Approach

Tests use Zig's built-in testing framework. The test suite in `src/test.zig` covers:
- All MessagePack type encodings/decodings
- Edge cases and boundary conditions
- Timestamp format variations (32-bit, 64-bit, 96-bit)
- Round-trip serialization verification

## CI/CD

GitHub Actions workflow tests against multiple Zig versions (0.14.0, 0.15.1, nightly) to ensure compatibility.