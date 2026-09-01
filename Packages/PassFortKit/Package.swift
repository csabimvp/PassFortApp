// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PassFortKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PassFortVault", targets: ["PassFortVault"]),
        .executable(name: "passfort-cli", targets: ["passfort-cli"]),
    ],
    targets: [
        // -- C++ -- keys and byte-marshaling only. NO interop flag on this target. --
        .target(
            name: "PFCrypto",
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("internal"),
                .headerSearchPath("vendor/botan"),
            ]
        ),

        // -- The ONLY module compiled with C++ interop (architecture §4). --
        .target(
            name: "PassFortCrypto",
            dependencies: ["PFCrypto"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                // C++ interop mode is recorded in the binary .swiftmodule and is viral:
                // without this, PassFortVault / passfort-cli would also need the flag
                // just to `import PassFortCrypto`, destroying the §4 "layering violation
                // = compile error" guarantee. Library evolution publishes a textual
                // .swiftinterface that clients compile against without inheriting the
                // interop mode, and turns "no pf.* in public API" into a compile error.
                .unsafeFlags(["-enable-library-evolution"]),
            ]
        ),

        // -- Swift storage/model/sync. MUST NOT import PFCrypto -- no interop flag,
        //    so a layering violation is a compile error, not a review catch. --
        .target(
            name: "PassFortVault",
            dependencies: ["PassFortCrypto"]
            // GRDB added at M2 (architecture §8)
        ),

        .executableTarget(
            name: "passfort-cli",
            dependencies: ["PassFortVault", "PassFortCrypto"]
        ),

        // The one sanctioned interop exception besides PassFortCrypto: the boundary
        // fuzz suite (architecture §13) needs to call pf_* directly.
        .testTarget(
            name: "PFCryptoBoundaryTests",
            dependencies: ["PassFortCrypto", "PFCrypto"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)