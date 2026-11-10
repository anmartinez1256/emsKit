// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd`: fdtdKit's front end over the emsKit tools; prints one JSON document (Docs/fdtdKit/PLAN.md)
import fdtdKit
enum FdtdCommand { static func main(_ args: [String]) -> Int32 { FdtdCLI.main(args) } }
