# SPDX-License-Identifier: GPL-3.0-or-later
# Cut on 2026-11-06 from openEMS/python/openEMS/openEMS.pyx (v0.37.0), lines 585-614 (_SetLibraryArguments).
# Copyright (C) 2015,20016 Thorsten Liebig (Thorsten.Liebig@gmx.de)
# openEMS is free software under the GNU General Public License, version 3 or (at your option) any later version, and
# comes WITHOUT ANY WARRANTY; this file is distributed under the same terms (see LICENSE at the repository's root).
    def _SetLibraryArguments(self, arguments):
        allOptions = []
        integerOptions = ["verbose", "numthreads"]

        for key, val in arguments.items():
            key = key.replace("_", "-")
            key = key.replace("setup-only", "no-simulation")

            # Using 1/0 instead of True/False is tolerated, but only
            # if the option is not an integer (which is ambiguous)
            if key.lower() not in integerOptions:
                if val == 1:
                    val = True
                elif val == 0:
                    val = False

            if val is True:
                # "True" boolean options are implicit
                opt = "%s" % key
            elif val is False:
                # "False" boolean options are ignored
                opt = ""
            elif (val is not True) and (val is not False):
                # integer and string options are explicit
                opt = "%s=%s" % (key, val)

            allOptions.append(opt.encode("UTF-8"))

        cdef vector[string] allOptionsBuffer = allOptions
        self.thisptr.SetLibraryArguments(allOptionsBuffer)
