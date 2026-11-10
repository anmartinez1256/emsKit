// SPDX-License-Identifier: GPL-3.0-or-later

// emskit: one CLI for the EMSKit solvers. Subcommands: fdtd (fdtdKit). fem, mom and sbr are added by their kits.
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let sub = args.first else {
    FileHandle.standardError.write(Data("usage: emskit <fem|fdtd|mom|sbr> ...\n".utf8)); exit(64)
}
switch sub {
case "fdtd": exit(FdtdCommand.main(Array(args.dropFirst())))
default:
    FileHandle.standardError.write(Data("emskit: unknown or not yet available subcommand '\(sub)'\n".utf8)); exit(64)
}
