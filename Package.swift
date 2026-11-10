// swift-tools-version:6.2
// SPDX-License-Identifier: GPL-3.0-or-later
// EMSKit: one Swift package for the EMSKit solver family (fdtdKit, femKit, momKit, sbrKit) and the `emskit` CLI.
// Created on branch fdtdkit (2026-11-05) with only fdtdKit's pieces; the sibling kits add their own targets.
import PackageDescription

let package = Package(
    name: "EMSKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "fdtdKit", targets: ["fdtdKit"]),
        .executable(name: "emskit", targets: ["emskit-cli"]),
    ],
    targets: [
        .target(name: "fdtdKit", exclude: ["Python"]),       // Foundation, CryptoKit, Synchronization only; no Metal, no Accelerate
        .executableTarget(name: "emskit-cli", dependencies: ["fdtdKit"]),
        .testTarget(name: "fdtdKitTests", dependencies: ["fdtdKit"], exclude: ["Fixtures"]),
    ]
)
