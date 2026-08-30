# ADR-0002: Opaque handles and `noexcept` free functions at the Swift↔C++ seam

**Status:** Accepted — amended by [ADR-0004](0004-swift-owns-storage.md)
**Date:** 2026-08-24

> **Amendment (ADR-0004):** the boundary *style* below is unchanged and now applies more strongly. What changed is its *scope* and the module names: the facade carries only key-handling and record seal/open (~12 functions), not a repository, and the targets are `PFCrypto` (C++) → `PassFortCrypto` (Swift wrapper) rather than `PassFortCore` → `PassFortKit`.

## Context

Swift 6.3's direct C++ interoperability is the feature this project is built to exercise. It is genuinely good, and it has sharp edges that are cheap to design around and expensive to debug. A spike against this machine's toolchain (Swift 6.3.3, clang 21, macOS 26.6) established the following, by compiling it:

- `std.string(swiftString)` — **failed to compile** (`no exact matches in call to initializer`), even with `import CxxStdlib`.
- `Array(cxxVector)` over a `std::vector<uint8_t>` returned inside a struct — **failed** (`does not conform to 'Sequence'`), including when given a named typealias, which is the usual fix for template instantiations.
- A C++ member function returning `const uint8_t*` — **not imported at all**; Swift reports `value of type 'pf.Bytes' has no member 'data'`, because the pointer's lifetime is unprovable.
- Manual element-by-element marshaling worked, but at per-element bridging cost.
- **An opaque forward-declared class plus `noexcept` free functions taking the handle worked cleanly**, marshaling via `Data(bytes:count:)`.

Separately, and non-negotiably: **C++ exceptions do not propagate into Swift — they terminate the process.** Botan throws on essentially every error path, including the one we hit most often in normal operation (a wrong master password raises an integrity failure).

## Decision

The public surface of `PassFortCore` is a **narrow, C-shaped facade written in C++**:

- every boundary function is `noexcept` and wraps its body in `try { ... } catch (...) { return Status::Internal; }`;
- errors are returned as `enum class Status : int32_t`, translated to Swift `Error`s by `PassFortKit`;
- heap-owned data is exposed as an **opaque forward-declared class** (`class Bytes;` in the header, defined in the `.cpp`);
- anything returning a pointer is a **free function** taking the handle, not a member;
- byte transfer is `(const uint8_t*, size_t)` → `Data(bytes:count:)`, never STL bridging;
- only POD types cross: fixed-width integers, raw pointers, and structs of those. No `std::string`, `std::vector`, `std::optional`, smart pointers, templates, or inheritance;
- `pf_bytes_free` zeroizes before freeing;
- `import PassFortCore` appears in exactly one Swift module, `PassFortKit`. The app target is compiled *without* the interop flag, so a layering violation is a build error.

`PassFortKit.Vault` is an `actor`: Argon2id at 512 MiB blocks for ~1 s and must never touch `@MainActor`, and the actor is what lets the C++ core stay single-threaded and lock-free by design.

## Consequences

- The boundary is boring, stable, and fuzzable — it survives toolchain upgrades because it barely uses interop's advanced features.
- Idiomatic modern C++ is still used freely *behind* the facade. Only the outermost layer is constrained.
- Byte transfer is one `memcpy` per call rather than per-element bridging: faster than the "nice" version we couldn't compile anyway.
- Cost: hand-written marshaling for every boundary function, and manual handle lifetime discipline in Swift (`defer { pf_bytes_free(h) }`). Both are mechanical, and both belong in `PassFortKit` where they're written once.
- Losing the exception type at the boundary means mapping Botan failures onto `Status` values by hand. Do it deliberately — in particular, a wrong password and a corrupt record must both surface as `AuthFailed`, so the API is not a decryption oracle.
- If a future Swift release fixes the STL bridging gaps, we can adopt them incrementally without redesigning anything.

## Alternatives considered

- **`extern "C"` ABI** — maximum stability, but throws away the interop feature the project exists to learn, and forces `void*` everywhere. Our facade is deliberately C-*shaped* while staying C++, which keeps namespaces, `enum class`, and type safety.
- **Objective-C++ (`.mm`) bridge** — the pre-Swift-5.9 answer. Adds a third language and an ARC boundary for nothing.
- **Rich interop: expose C++ types directly to Swift with `SWIFT_SHARED_REFERENCE` / `CxxSequence`** — the "showcase" approach, and where the compile failures above came from. Revisit for read-only value types once the core is stable; not for the load-bearing seam.
- **Rewriting the core in Swift** — would work, and would delete the reason for the project.
