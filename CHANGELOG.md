# Changelog

`PUBLISH.md`, `NEXT_WORK_PROMPT.md` and `CLAUDE.md`, which some entries below name, are the author's publishing
steps, the work plan of 2026-11-04 and the assistants' working notes; they are not part of the published repository.
The repository is published as one commit, without the history in which it was made; the hashes of this repository's
own commits that the entries cite (for example 00e8f7d, 60fd4a3 and 64d19f8) name commits of that history. Hashes such
as 1620939 and 087ce9e name commits of the openEMS fork, not of this repository: entries dated before 2026-11-07, like
the records in `results/` made before then, give the hashes that the fork's commits had before they were rewritten for
publication that day (with the same trees), and the table in the entry of 2026-11-07 on the fork's rewrite maps them
to the published ones.

## 2026-11-10: published

On the author's word this repository was pushed to github.com/anmartinez1256/emsKit as one commit made from the files
of `main`, without the history in which they were made and without the three files named at the top of this file.
Before the push the main session (Claude Fable 5.2, Claude Code) made that commit once in a scratch copy: no personal
address in any file, the author's public identity on the commit, and from the copy alone `swift build` complete
without warnings and the unit suite passing. New for the publication: `CITATION.cff` (how to cite the repository) and
`.zenodo.json` (the description that Zenodo shows when it archives a release; the DOI follows with the first
release). `ROADMAP.md` lists the publication under Done, and section 13 of `Docs/fdtdKit/PLAN.md` gives the date.

## 2026-11-10: the second review's fixes (branch `fdtdkit`)

On 2026-11-09 a read-only workflow of the main session (Claude Fable 5.2, Claude Code) reviewed all 31 source files
of the command line as of f9b7cc3: four reviewers (the libraries, the outputs, the children and signals, the
commands), a refuting verifier for each, and one critic. The reviewers raised 23 findings; the verifiers confirmed 21
of them, 16 distinct, called 1 plausible and refuted 1, and the critic added 5 more. On 2026-11-10 three fixers of a
second workflow (the libraries, the outputs, the rest) changed the code in a scratch clone, each fix with a unit test
that fails without it. No fork code, patch file, measured value or tool of `bench/` and `scripts/` changed.

- e2e never looked at the libraries its run loaded (`Commands/E2ECommand.swift`, `Verdicts.swift`): dyld takes the
  installed copy of a snapshot file it cannot use, without a message, so `e2e --lib SNAP` could report times for SNAP
  that the installed library had produced. The verdict now gets the launcher report's libraries and gives
  `library_not_loaded` (exit 4), as run does. Tests: LoadedLibraryTests `e2eVerdictChecksTheLoadedLibraries`,
  `e2eReportsALibraryFromAnotherFolder`.
- run and validate compared the loaded images' folder with LIB's as text (`Verdicts.swift`, `Discovery.swift`): dyld
  reports real paths, so a `--lib` or SNAPS reached through a link ended in a false `library_not_loaded`. One rule,
  `FdtdDiscovery.lies` (the image or its real path in the folder as given or in its real path), now serves the probe
  and the three verdicts, and validate, e2e and run refuse before the run when the probe took a file from another
  folder (`Commands/CommandSupport.swift`, `scriptLibrary`). Tests: `anImageLiesInTheFolderAsGivenOrByRealPath`,
  `requireLoadedNamesTheFileFromElsewhere`, `aSnapshotTheProbeDidNotLoadIsRefusedBeforeTheRun`,
  `runVerdictChecksTheLoadedLibraries`, `validateVerdictChecksTheLoadedLibraries`,
  `runReportsALibraryFromAnotherFolder`; FakeSystem's probe reports real paths now.
- check's `--extra` configs were only parsed (`Commands/CheckCommand.swift`, `Commands/BenchCommand.swift`
  `requireSupport`): a missing folder, an engine or a knob that the extra's library lacks surfaced late or not at
  all. Each extra's library is now resolved (exit 2), its engine and knobs are required as for a bench CFG (exit 3),
  and the library joins the envelope's list and the concurrency scan. Tests: `checkExtrasAreMatchedAgainstTheirLibrary`,
  `checkExtrasAddTheirLibrariesToTheUsedList`; `aKnobOrEngineTheLibraryLacksIsRefused` covers the knob and engine
  guards of bench, validate, run and e2e, which had no test.
- A SNAP or `--stock` folder that a CFG cannot carry was reported as a bad `--extra` (`Commands/CheckCommand.swift`
  `requireCarried`, `BenchConfig.swift` `carries`): it is refused under its own field (`config_invalid`, exit 2).
  Test: `aSnapThatAConfigCannotCarryIsReportedUnderItsField`.
- `--output` naming a folder, `.` or an empty value with `--overwrite` renamed that folder away (`FdtdKit.swift`
  `begin`, `Options.swift`): both are usage errors now (exit 64), in a dry run too, and finish() never renames a
  folder. Test: OutputTests `outputThatIsAFolderOrEmptyIsRefused`.
- finish() cleaned the run folder before it knew whether `--output` could be written (`FdtdKit.swift`): the backup
  and the write come first, and the file is written once, already saying `keptRuns` false; a failed write is an
  error that deletes nothing. A file that appeared at `--output` during the run is left alone without `--overwrite`
  (`tool_failed`, exit 4, the envelope on stdout). Tests: `outputHoldsTheEnvelopeAfterTheCleanup`,
  `aFailedOutputWriteDeletesNothing`, `anOutputThatAppearedDuringTheRunIsLeftAlone`.
- A usage error (64) is now reported before a bad `--tag` (2) on the same line (`Options.swift`: `requireTag` runs
  after each command's usage rules; for bench's `--knob` rules since the third review, below). The envelope of a
  line that did not parse still goes to stdout, whatever `--output` says, and a stderr line says that the file is
  not written (`FdtdKit.swift`). An intermediate version of this day wrote it to FILE and read `--overwrite`,
  `--dry-run` and the discovery options back from the unparsed line (`commonAfterError`); that was withdrawn after
  the guard attack, below. Tests: `aUsageErrorWritesNoFile`, `aUsageErrorOutranksABadTag`.
- Signals (`Context.swift`, `FdtdKit.swift`): a SIGHUP that was ignored when the CLI started (nohup) is no stop
  request any more (INT and TERM always are), and the handling is restored only after finish(), so a signal during
  the cleanup or the envelope write no longer ends the CLI without an envelope. Tests:
  `onlyAnInheritedIgnoredHangupStaysIgnored`, `signalsAreHandledUntilTheEnvelopeIsOut`.
- A captured child that exits while a process it started still holds the pipes left that process running
  (`Spawn.swift`): after the short wait, what is left of the child's group gets SIGKILL. Test:
  `captureEndsWhatTheChildLeftInItsGroup`.
- e2e's `--out-dir` (`Commands/E2ECommand.swift`): `--overwrite` renamed the old folder before the run folder existed
  and before the quiet wait, so a failure or Ctrl-C there left it gone with no run; it is renamed as the last step
  before the run. An `--out-dir` that is or holds the run folder is a usage error (64): core.run empties its folder
  first, and with it the launcher, tool.log and the report. Tests: `e2eRenamesTheOldOutDirOnlyBeforeTheRun`,
  `e2eRefusesAnOutDirThatHoldsTheRunFolder`.
- The critic's finding on the protected folders (`Commands/CommandSupport.swift`, `protectedRoots`): the list kept
  one path per folder, so with a prefix reached through a link the name `~/opt/openEMS` was dropped and a folder
  above the link could be renamed away. Every path of a folder is listed now. NoInstallTests
  `aFolderAboveTheNameOfAProtectedFolderHoldsIt` passed before only because the fake probe reported the link's name;
  with real paths from the fake probe it fails without the fix.
- bench accepted a summary line with no parsed rows (`Commands/BenchCommand.swift`, `Verdicts.swift`; the plausible
  finding, a missing guard that needs a changed bench.py): a summary line now needs one readable row per config
  (`tool_output_unparsed`, exit 4), RUN/runs is looked at whenever there is a summary, and under `--exact` a
  `NOTHING REQUIRED TO MATCH` without a compared row gives `nothing_verified`. Tests: GuardTests
  `benchSummaryNeedsARowPerConfig`, `exactWithoutAComparedRowVerifiesNothing`.
- `info --rfsim DIR` with a DIR that is no toolkit reported the installed library as unknown and blamed the Python
  probe (`Commands/InfoCommand.swift`; the critic's): the probe's child environment stopped on the option. info now
  reports that option once, before the probe, and shows the installed library. Test:
  `infoShowsTheInstalledLibraryBesideABadRfsim`.
- `tools_modified` never fired in a tools tree kept below the top level of another repository (`Discovery.swift`; the
  critic's): porcelain paths start at the top level. With a non-empty `git rev-parse --show-prefix` the status is
  asked for the tree's folder and the prefix is taken off the paths; `repo.head` is then the commit of the repository
  that holds the tree, which the plan now says (section 5.3). Test: `toolsModifiedReadsPathsBelowTheTopLevel`;
  FakeSystem answers `--show-prefix`.
- Rules that a mutation could switch off with the suite still passing (the critic's two findings on tests), now with
  tests in `Tests/fdtdKitTests/GuardTests.swift`. FailingVerdictTests: the verdicts of ab, validate, debye-check,
  diamond-check, e2e and run on failing inputs, each directly (six tests) and through its command on a fake tool
  (`debyeCheckExitsOneOnFail`, `diamondCheckExitsOneOnFail`, `validateExitsOneOnAFailedCheck`,
  `runExitsOneWhenTheScriptRaisesOrExits`, `abExitsOneOnADifferingRun`, `e2eExitsFourWithoutAResult`). GuardTests:
  the sampler counts (`aSamplerThatSawNothingGivesNoValidLoad`, `loadWithoutAValidSampleIsLoadUnavailable`,
  `aCallSpeedNeedsASamplerThatSawTheMac`, `validateCaseTimesNeedASamplerThatSawTheMac`), validate's unchanged JSON
  (`validateDoesNotTakeAnOldJSONForThisRuns`), `aLauncherWithoutAReportIsAnError`,
  `aChildThatCannotStartIsSpawnFailed`, `theZshPreProbeMustLoadTheLibrary` and `keepRunsKeepsTheRunData`. No source
  line changed for these.
- Left as they are. An installed library whose three files lie in separate real folders (a folder of links) is still
  refused as `library_incomplete`: dyld reports real paths, so the fallback folder cannot be reached; the message now
  says that the three files must lie in the one real folder of libopenEMS (`Libraries.swift`, `Discovery.swift`
  comment). The refuted finding (validate, e2e and run take the last of two `--knob` values for one name) kept
  its behaviour and got a warning (the open items, below). In a nested tools tree whose folder name needs quoting in
  git's output, the prefix is not taken off the quoted form's escapes, so `tools_modified` stays silent there
  (closed for names outside ASCII by the review of the fixes, below).
- The review of the fixes. Three more read-only agents then checked the change (one for regressions, one that ran
  the suite on mutants of each fix, one that ran the built binary on scratch folders): 18 findings, one of them
  raised by two reviewers. A final fixer checked each and acted on all but two:
  - A file that appeared at `--output` made a failed or passing run exit 5 with status `refused`, although the
    tools had run: it is `tool_failed` (exit 4) now, like a folder that appeared there. Tests:
    `anOutputThatAppearedDuringTheRunIsLeftAlone`, `anAppearedOutputNeverTurnsAFailedRunIntoARefusal`.
  - The second `--output` write after the cleanup could fail and leave a file that said ok and `keptRuns` true
    beside deleted data: the file is written once, before the cleanup, with `keptRuns` already false, and again
    only when the cleanup fails. Tests: `outputIsWrittenOnceBeforeTheCleanup`, `aFailedCleanupCorrectsTheOutput`,
    `aFailedBackupNeverWritesOverTheOldOutput` (FakeSystem can now fail a rename, a removal and the nth write).
  - Every inherited SIG_IGN was honoured, so a CLI started as `cmd &` by a script (SIGINT ignored there) could no
    longer be stopped with `kill -INT`: only SIGHUP's is. Test: `onlyAnInheritedIgnoredHangupStaysIgnored`.
  - With the handling kept until the envelope is out, a write that blocked could not be interrupted: a second
    signal during finish() ends the CLI with the signal's default action (`FdtdFinishGuard`, `giveUp`). Test:
    `aSecondSignalDuringFinishGivesUp`.
  - A usage error with `--output` probed for the protected folders with no signal handling. The intermediate
    version installed it first; in the final one (the guard attack, below) a line that did not parse writes no
    file, so it probes nothing and needs no signal handling. Test: SignalTests `usageErrorsInstallNoHandler`.
  - e2e renamed the old `--out-dir` after the quiet wait without a second look at the protected folders, and a job
    that could not be resolved failed after the rename: both come before it now. Tests:
    `e2eChecksTheOutDirAgainBeforeTheRename`, `e2eRenamesTheOldOutDirOnlyBeforeTheRun` (a stop during the wait),
    `e2eRefusesAnOutDirThatHoldsTheRunFolder` (the run folder itself, a second name of RUNS, a sibling whose name
    starts like RUNS'). The job resolved first and the second look at the run folder had no test until the third
    review, below.
  - validate, e2e and run refused a library folder whose three names are links to files in another folder, which
    dyld loads: `FdtdDiscovery.lies` also takes the file that one of the three names leads to (bench, ab and check
    refuse such a folder since the third review, below, as bench.py does after its first run). Test:
    `anImageBehindALinkedNameLiesInTheFolder`.
  - `tools_modified` stayed silent below a folder whose name has a letter outside ASCII: the status is asked with
    `-c core.quotePath=false`. Test: `toolsModifiedReadsPathsBelowTheTopLevel` (FakeSystem's git quotes as git does).
  - Rules without a test: bench's summary after a stop and with more rows than configs
    (`benchSummaryNeedsARowPerConfig`), info's probe order with a valid `--rfsim`
    (`infoShowsTheInstalledLibraryBesideABadRfsim`), check's probe with an extra's snapshot folder
    (`checkProbesWithAnExtrasSnapshotFolder`), and that the concurrency scan lists a library named twice once
    (`checkExtrasAddTheirLibrariesToTheUsedList`).
  - Not changed: check's own removal of doubles from its used list has no test, because nothing can see it: the
    scan's file list and the backend's folder map each drop doubles themselves, so the mutant without it behaves
    the same.
  - Not changed: a probe's child that closed its pipes and stays in the probe's process group is not ended. What a
    child leaves behind with its pipes closed reads as a daemon left on purpose (git can start one), and ending it
    would do more harm than leaving it; the plan's section 9 already speaks of pipes still held.
- The open items, closed the same day by one more fixer (Claude Fable 5.2, in the same scratch clone): the lists
  "Left as they are" of this entry and of the entry of 2026-11-09 were gone through, and each item that could be
  closed with a small change was, with a unit test that fails without it.
  - The rfsim probe read the toolkit's values without defaults, so a toolkit that lacks one ended in exit 4
    (`Discovery.swift`, `FdtdSnippets.rfsim`): each of the five values is read with a default, the `launch` module is
    optional, and a value that is missing or no finite number is null. Test: LauncherTests
    `theRfsimProbeTakesAToolkitWithoutItsValues` (a real python3 on three toolkits).
  - The protected-folder check kept, for the rest of the command, a list made while a stop cut the installed
    library's probe short, so an `--output` inside a prefix that only the probe names was written after Ctrl-C
    (`Commands/CommandSupport.swift`, `protectedFolders`, `refuseProtected`). Such a list is not kept, and a check
    made on it lets nothing through: a known folder is refused as ever, any other location ends the command as
    `interrupted` (130) with nothing written, and the envelope goes to stdout. A probe that answered before the
    stop, or a Python that cannot be found, gives the list as without the stop. Tests: OpenItemTests
    `aStopDuringTheInstalledProbeLetsNoOutputThrough`, `aStopDuringTheInstalledProbeStillRefusesAKnownFolder`,
    `aCutShortAnswerIsNotKeptForTheRestOfTheCommand` (FakeSystem can now deliver a signal during a capture).
  - The rule "take the index entry for a folder that the index holds" stood in three places with three conditions
    (`Libraries.swift`, `Commands/CommandSupport.swift`, `Commands/CheckCommand.swift`): one helper,
    `FdtdSnapshotIndex.entry(at:)` (the folder's path, byte for byte), and one function above it,
    `FdtdLibraries.record`, now serve the commands' LIB resolution, check's stock scan and its stock match. info
    uses them too (`Commands/InfoCommand.swift`), so a snapshot named with `--lib` is no longer read twice, and a
    LIB that names a SNAPS folder by its path is no longer read again, in any command. Tests:
    `aRecordFromTheIndexEqualsTheOneFromTheFiles`, `aLibInTheIndexIsReadOnce`.
  - info installed no stop handling although it runs probes and scans (`FdtdKit.swift`,
    `Commands/InfoCommand.swift`; its comment said that it starts no child): it handles INT, TERM and HUP like every
    command, and after a stop request it ends as `interrupted` (130) once the step the signal arrived in is over,
    with no warning for the child that the stop ended. Tests: `infoStopsOnASignal`, SignalTests
    `usageErrorsInstallNoHandler` (the earlier `infoAndUsageErrorsInstallNoHandler`).
  - The probe and the launcher took the binding's version from the package metadata by name, which can belong to
    another installed copy (`Discovery.swift`, `Python/fdtdkit_run.py`, `LauncherSource.swift`): the version counts
    only when one of that distribution's files lies in the folder of the imported package, else it is left out
    (null). Test: LauncherTests `theBindingsVersionNeedsMetadataOfTheImportedCopy`.
  - The probe's `legacyEmptyOption` was null where the launcher's is true (`Discovery.swift`): the probe now follows
    the launcher's rule, true unless an `openEMS.pyx` beside `openEMS.openEMS` can be read and lacks `opt = ""`,
    and imports `openEMS.openEMS` itself as the launcher does; it is null only when that import fails, and the
    launcher then reports no binding. Test: `theProbeAndTheLauncherAgreeOnTheLegacyBinding`.
  - Two `--knob` values for one name in validate, e2e and run: the last one still wins, as designed, and the
    warning `knob_ignored` now names the knob and its values (`Knobs.swift`, `repeated`). The same value twice gives
    no warning. Test: `aKnobGivenWithTwoValuesWarns`.
  - Still left as they are: the installed library whose three `.0.dylib` names resolve to separate real folders
    (`library_incomplete`, with the clearer message; accepting it would end the one-folder model of a library
    record), a probe's child that closed its pipes and stays in the group (deliberate, above), check's removal of
    doubles (nothing can see it), and the escapes of a quoted ASCII folder name in a nested tools tree.
- The third review. Three more read-only agents (Claude Fable 5.2) then reviewed the whole uncommitted change
  (the change itself, the safety rules, the verdicts), with a refuting verifier. Ten findings reached one more
  fixer, each confirmed by the verifier (nine distinct: the first was raised by two reviewers); the fixer checked
  each again, found all ten real and fixed them, and left none:
  - A `--rfsim` that names no toolkit stopped the base environment and with it the probe that finds the installed
    prefix, so an `--output` inside a prefix that only the probe names was written, or with `--overwrite` renamed,
    on that line (`Commands/CommandSupport.swift`, `protectedFolders`): the probe
    then runs with the base environment without `RFSIM_PATH`. Test: OpenItemTests
    `aBadRfsimLeavesTheInstalledPrefixProtected`.
  - A usage rule found after the options are parsed lost to a bad `--tag` (exit 2 for 64): bench checks its tag
    after its `--knob` rules (`Commands/BenchCommand.swift`), and validate's parser reads `--knob` as NAME=VALUE
    before the tag (`Options.swift`). Test: `aUsageErrorOutranksABadTag` (four more lines).
  - e2e with `--overwrite` renamed away an `--out-dir` that is or holds the working directory, the tools tree, the
    toolkit, the `--lib` folder or the Python's folder, and an empty value meant the working directory
    (`Commands/E2ECommand.swift`, `refuseHolding`; `Options.swift`): both are usage errors (64), at plan time and
    again before the rename. Test: `e2eRefusesAnOutDirThatTheRunNeeds`.
  - An `--out-dir` that was filled during the quiet wait was emptied by the run with no refusal and no backup: it
    is looked at again after the wait (`prepareOutDir`), exit 5 without `--overwrite`, a backup with it. Test:
    `e2eLooksAtTheOutDirAgainAfterTheWait`.
  - Two e2e rules named as tested above could be taken out with the suite still passing (the job resolved before
    the rename, the second look at the folders the run needs): tests `e2eResolvesTheJobBeforeTheRename` and
    `e2eRefusesAnOutDirThatBecameAHolderDuringTheWait`.
  - validate gave `library_not_loaded` for a good run when the home folder's text occurs inside the library's
    path (the suite writes `~` for it anywhere, so `/Users/name2/x` reads `~2/x`): a name is also tried with every
    `~` read as the home folder (`Verdicts.swift`). Test: `validateVerdictChecksTheLoadedLibraries` (two cases).
  - bench, ab and check took a LIB folder whose names are links to files in another folder, which bench.py
    refuses after its first simulation: refused at plan time (`library_incomplete`, exit 2; `Libraries.swift`,
    `requireOwnFiles`). Test: `benchAbAndCheckRefuseAFolderOfLinksElsewhere`.
  - Documents: the plan's section 6.2 on a knob given twice now names `--knob` and the CFG list apart; the counts
    and dates of the README, the roadmap, the plan and the paper agree, and the PDF was built again.
- The fourth review. Two more read-only reviewers (Claude Fable 5.2), each with a refuting verifier, then went
  through the guards (what is checked before anything is written, renamed or started) and through the verdict
  paths (from tool output to status and exit code). They raised six findings; the verifiers confirmed all six, one
  of them medium and five low, and one more fixer fixed all six:
  - A mistyped `--repo` or `--python` switched off the protection of an installed prefix that only the Python
    probe names (medium; the same pattern as the bad `--rfsim` of the third review), and on a usage error's line a
    discovery option given twice was dropped, so `--output` was checked against other folders than the line's
    (low; such a line writes no file any more, the guard attack, below). The first is fixed by one rule instead of
    one case per option (`Commands/CommandSupport.swift`,
    `protectedFolders`; the plan's section 10.2): the protected folders are the union of what discovery finds with
    the line's `--repo`, `--python`, `--rfsim` and `--snaps` and what it finds with all of them ignored (the walk
    from the working directory and the executable, PATH's python, the environment and the defaults). The second
    Python probe runs whenever the line names something with one of these options, respects a stop, changes
    nothing the command uses or records, and is skipped when it would be the same child as the first (the options
    name what the defaults find). The rule is for lines that parse. (An intermediate version applied it to a line
    that did not parse too, and left `--output` unwritten when such a line gave one of the four twice or without
    a value; withdrawn with the guard attack, below.) The special probe for
    a bad `--rfsim` is gone; its test passes on the rule. Tests: the new suite DiscoveryOptionTests (seven tests
    then: each option naming nothing, on info, load and bench, with `--output` and with `--overwrite`, inside the
    prefix and inside a snapshot folder; a second Python with its own prefix; a stop during the second probe; no
    second probe when the options name the defaults; and two on unparsed lines that went with the withdrawal).
  - e2e's test for an `--out-dir` that holds a folder the run needs missed a folder named through a link inside
    the `--out-dir` (low): it now uses the protected folders' own test, `FdtdProtectedPaths.holds` (`RunFolder.swift`,
    `Commands/E2ECommand.swift`), which compares the path a folder is named by as well as its real path. Test:
    OutputTests `e2eRefusesAnOutDirThatHoldsANeededFolderByItsName`.
  - ab accepted a `--record` that is a folder or empty and failed only after all rounds, and an empty `--results`
    or `--runs` was read as the working directory (low): the tokenizer refuses an empty value of every option that
    takes a path (`--repo`, `--python`, `--snaps`, `--rfsim`, `--runs`, `--output`, `--hosts`, `--results`,
    `--record`, `--out-dir`, `--build`; exit 64, `Options.swift`), and `--record` goes through the checks of
    `--output` (`FdtdSession.requireFile`: a folder is 64, a missing parent folder 2; `Commands/ABCommand.swift`).
    Tests: the new suite PathOptionTests (four tests).
  - check let a model block pass without the rows its count leaves out, a tolerant `--extra` or the reference of a
    lite block, so their engines were never confirmed (low; needs a changed bench.py): a block's summary needs one
    readable row per config, as bench's does (`tool_output_unparsed`, exit 4; `Commands/CheckCommand.swift`). Test:
    VerdictTests `checkNeedsARowPerConfig`.
  - validate, e2e and run gave the engine's `knob_ignored` for an `OPENEMS_DIAMOND_TILE` value that a later
    `--knob` had replaced (low): the engine's warnings are made for the value that reaches the child
    (`Commands/CommandSupport.swift`, `environmentKnobs`). Test: OpenItemTests `aKnobGivenWithTwoValuesWarns` (two
    more cases).
  - The re-check. Two more read-only reviewers (Claude Fable 5.2) then looked at the tree with these fixes and
    reported four findings; a last fixer reproduced all four and fixed all four. (1, medium) The first half of the
    one rule was all or nothing: a correct `--python` or `--repo` of a second installation lost its prefix as soon
    as another discovery option on the line named nothing (for a bad `--rfsim`, protection that the third
    review's special probe had given). The line's options now count one by one, with the default in place of
    each one that names nothing (`installedDirAside`). (2, low) On a line that did not parse, a discovery option
    written as `--name=VALUE`, with one dash, or as a near miss of its name was not counted as unclear, so
    `--output` could still be written into the folder it names; the intermediate fix counted any such token
    (`commonAfterError`), and the guard attack, below, replaced it: such a line writes no file. (3, low) The second
    probe was skipped only for an equal path and a wholly equal environment, so the everyday line with `--rfsim DIR`
    and a `--repo` through a link started the same Python import twice; two probes are now the same child by what
    can change the answer: the Python as named, the tools tree as a folder and the environment without `RFSIM_PATH`
    (`FdtdInstalledProbe`). (4, low)
    One line of the plan's section 10.2 was 153 characters long; the bullet is wrapped and written again for the
    changes above. Tests: two more in DiscoveryOptionTests
    (`aCorrectOptionBesideOneThatNamesNothingKeepsItsPrefix`, `aCorrectRepoBesideAPythonThatNamesNothing`) and
    three extended (the other spellings, the probe counts); each fails on the tree before these fixes.
  - The guard attack. Two more read-only agents (Claude Fable 5.2) then attacked the guards of that tree with the
    built program, on scratch folders with a scratch home and fake Pythons: about 3,650 attack lines. On the lines
    that parse they found 0 changes under a protected folder. They reported three distinct low findings: (1) on a line
    that did not parse, a discovery option spelt beyond the hint's reach (`--SNAPS`, `--snapshots`, `--snaps-dir`,
    `--py`, `--python-path`, or given after `--`) was not unclear, so `--output` was written, and with `--overwrite`
    renamed and replaced, inside the folder it names; (2) check read `-snaps DIR` as two more SNAP names, so that line
    parsed and did the same; (3) no test held the rule that two probes are told apart by the Python as named. This was
    the third round in a row to find a spelling that the reading of unparsed lines did not cover, so one more fixer
    took the reading out instead of widening it. Rule 1: a line that did not parse (a usage error, 64, or the bad
    `--tag` that the parser finds for check and validate, 2) writes no file, renames nothing, probes nothing and
    installs no signal handling; the envelope goes to stdout, and when the line holds `--output` a stderr line says
    that it is not written because the line was not understood (`FdtdKit.swift`; `Options.swift` loses
    `commonAfterError` and the list of unclear options, 49 lines less in `Sources/`: 86 removed, 37 added). Rule 2: a
    positional that starts with `-` is a usage error on every command (the tokenizer, `Options.swift`), with the
    option meant or the path form (`./-x`) as the hint; check, debye-check and diamond-check answered such a LIB with
    `library_not_found` (2) before. The union rule for lines that parse is as it was. Tests: the new suite
    UnparsedLineTests (five tests: each of the ten commands with an unknown option and `--output FILE`, with and
    without `--overwrite`, FILE new, existing and inside a protected folder, leaves every path and its bytes
    unchanged, starts no child, exits 64 and prints the envelope on stdout; every spelling above; tokens after `--`;
    the parser's bad tag; the same lines parsed), GrammarTests `aPositionalStartingWithADashIsAUsageError` and
    `theDashPositionalsHintAndWhatStaysAllowed`, DiscoveryOptionTests `aPythonThatIsALinkToPathsPythonIsAnotherPython`
    (finding 3: two probes, both prefixes protected) and `theDiscoveryOptionsOfAParsedLine`, OutputTests
    `aUsageErrorWritesNoFile`. Six tests that pinned the withdrawn reading are gone (three each in OutputTests and
    DiscoveryOptionTests), and four others lost the lines that used it.
  - The check of those fixes. One more read-only agent ran the built program against the final tree and reported
    four low findings, none in the code's rules; a last fixer changed documents and one comment only. (1) On check,
    whose SNAP list is open, a line with two slips still parses: `--stock -snaps DIR` (the token with one dash is
    the option's value, DIR a second SNAP), or `snaps DIR` without any dash. It names no `--snaps`, so DIR is not
    protected and an `--output` inside it is written. The form without a dash cannot be closed by a spelling rule,
    so neither was, and the next item closes it by another rule. The other commands refuse these slips (64). (2) The
    README said that every usage error writes no file; a usage rule found after parsing (bench's `--knob` rules)
    does write `--output`, as section 4.1 says, and the sentence is narrowed. (3) The plan's log line on the
    withdrawn reading is marked as withdrawn. (4) A stale comment in OpenItemTests. Test counts unchanged.
  - The residual closed. One more fixer closed finding (1) with one rule that reads no spelling: every LIB that
    the line names by its path (check's SNAPs, `--stock`, `--lib`, `--ref`, the LIB of each `--config`, `--extra`
    and ab CFG) and that is a folder is a protected folder for that command, whether it holds a complete library
    or not (`Options.swift`: `FdtdCommandOptions.librarySpecs`; `FdtdKit.swift`: `begin()` takes the list before
    it checks `--output`; `CommandSupport.swift`: `protectedFolders()`). It needs no probe and holds in a dry run.
    The two lines of (1) are refused now (`protected_path`, exit 2), with and without `--overwrite`, when DIR is
    written with a `/` (a bare name was closed by the last review, below); an output beside a library folder is
    accepted as before. One behaviour changed: e2e's `--out-dir` that is or holds a
    `--lib` folder given by its path answers `protected_path` (2) where it answered usage (64). Tests: four more
    in DiscoveryOptionTests (`aFolderThatASlipMakesALibraryIsProtected`, `everyLibraryNamedByItsPathIsProtected`,
    `theOtherTargetsOfALineWithALibraryFolder`, `aLibraryPathThatIsNoFolderProtectsNothing`), which fail with the
    rule taken out, and OutputTests `e2eRefusesAnOutDirThatTheRunNeeds` edited for the changed answer.
  - The last review. Two read-only reviewers (Claude Fable 5.2), each with a refuting verifier, went over the rule
    for the library folders and the whole committed change 6344992: 4 findings, 3 confirmed, all low, 1 refuted.
    (1) The two-slip line of check with DIR as a bare relative name (`--stock -snaps mysnaps --output
    mysnaps/e.json`) still wrote the envelope inside DIR, because a LIB without `/` is a snapshot name. Closed in
    the code: a LIB of the line without `/` (other than `installed`, the empty word, `.`, `..` and a name that
    starts with `-`, none of which is read as a snapshot name) also protects the folder of that name in the working
    directory when there is one (`CommandSupport.swift`: `protectedFolders()`; `Libraries.swift`:
    `isSnapshotName`); no probe more. One behaviour changed: an `--output`, `--runs`, `--results`, `--record` or
    `--out-dir` inside a folder of the working directory that has the name of a snapshot of the line (`check cg29
    --output cg29/e.json` where `./cg29` exists) answers `protected_path` (2). (2) `info -h` and `bench -help` got
    the hint of a path `./-h`; the hint is `--help` now, and `help` is among the names a single-dash word is
    compared with (`Options.swift`). (3) Helpers left without a caller in Sources: `protectedRoots()` and
    `FdtdSnapshotIndex.entry(_ name:)` are removed (their tests call `protectedFolders().roots` and read the
    entries), and `discoveryGiven` keeps its names with the note that only the tests read them; no behaviour
    changed. Refuted: a path with `#` inside a CFG is no LIB by the grammar (the text before the first `#` up to
    its last `@`); the plan's section 10.2 says so now and one test line pins the last `@`. Tests: three more
    (DiscoveryOptionTests `aBareFolderThatASlipMakesALibraryIsProtected` and
    `aSnapshotNameProtectsOnlyAFolderOfThatNameInTheWorkingDirectory`, GrammarTests
    `aSingleDashHelpRequestIsToldTheSpelling`), each failing with its fix taken out.
  - Documents: the plan's sections 4.1 (the path options, a line that did not parse), 4.2 (ab's record, check's guard,
    e2e's `--out-dir`), 6.2 and 10.2 (the one rule), its rows and counts in section 12 and its log in section 16;
    the counts of the README, the roadmap and the paper, and the PDF built again.
- Tests: 258 tests in 28 suites (244 unit tests in 27 suites and the 14 smoke runs), 100 more than at f9b7cc3: 58 in
  the new suites LoadedLibraryTests (14), OutputTests (19), FailingVerdictTests (12) and GuardTests (13), the
  ten of the open items, seven in the new suite OpenItemTests and three in LauncherTests, the six of the third
  review (four in OutputTests, one each in LoadedLibraryTests and OpenItemTests), the thirteen of the fourth
  (seven in the new suite DiscoveryOptionTests, four in the new suite PathOptionTests, one each in OutputTests and
  VerdictTests), the two of its re-check (DiscoveryOptionTests), and four net with the guard attack (ten new,
  five of them in the new suite UnparsedLineTests, for six removed), the four of the library folders of the
  line (DiscoveryOptionTests), and the three of the last review (two in DiscoveryOptionTests, one in
  GrammarTests). Each fix and
  each newly tested rule was taken out once (21 mutants for the fixes of bench, info and `tools_modified` and for
  the rules that had no test, 13 for the library fixes, the output fixer's own run, 30 for the final
  fixer's changes and the rules the second set of reviewers found untested, 17 for the open items, 14 for the
  third review's fixes and 16 for the fourth's), and each time a test failed, except for the one mutant just
  named and the two e2e rules that the third review found untested, which have their tests now.
- Documents: `README.md` (the command line's status), `ROADMAP.md` (the command line's row),
  `Docs/fdtdKit/PLAN.md` (sections 4.1, 4.2, 5.1, 5.3, 7.3, 9 and 10.2, section 12's rows and counts, the entry of
  section 16). The paper (dated 2026-11-10): the command line's paragraph and the Disclosure of the closing section.
  With the open items: the plan's sections 4.2 (info's exit), 4.3, 5.1 ("Read once"), 5.3 (items 2 and 4), 6.2, 9
  and 10.2 ("After a stop"), a row for OpenItemTests in section 12 and the counts here, in the README, the roadmap,
  the plan and the paper's sentence on the tests (`paper/sec_closing.tex`). With the third review: the plan's
  sections 4.1, 4.2 (e2e's `--out-dir`), 5.1 ("A folder of links"), 6.2, 10.2, 12 and 16, the same counts again,
  and the PDF built from the final source. With the fourth review: the plan's sections 4.1, 4.2, 6.2, 10.2, 12
  and 16, the counts once more, and the PDF; with its re-check, sections 4.1, 10.2, 12 and 16, the counts and the
  PDF again; with the guard attack, sections 4.1, 10.2, 12 and 16 and the counts once more; with the library
  folders of the line, the same sections and counts; with
  the last review, the plan's sections 4.1, 10.2, 12 and 16, the README's guarantee and the counts (README,
  roadmap, plan, `paper/sec_closing.tex`).
- Checks: `swift build` complete without warnings and `swift test --filter fdtdKitTests` 216 tests in 24 suites
  passed (202 run, the 14 smoke runs skipped), also after the documents were written. The fixers had no leave to start
  simulations; the main session then ran, on the final tree and on a Mac loaded by other programs (about eight
  cores busy, among them another session's openEMS simulation on the installed library, so only the verdicts count):
  the unit suite again (216 in 24 passed), the 14 smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--no-parallel`; passed, 108 s,
  01:46-01:48 CST), `check cg29 --tag fabfix --lite` (01:48-01:58: `ALL IDENTICAL (6 models)`, 18 of 18 exact rows,
  warnings `simulation_running` and `loaded_mac`; tables kept outside `results/`), `diamond-check cg29` (72 of 72
  identical) and `e2e gcpw --lib cg29`: refused at first with `simulation_running` (exit 5), the guard's answer to
  the other session's run, then with `--allow-concurrent` status ok, 34,300 timesteps by the probe end. After the
  open items were closed, later the same day: `swift build` complete without warnings and the unit suite again, 226
  tests in 25 suites passed (212 run, the 14 smoke runs skipped). That fixer had no leave to start simulations, so
  the smoke and acceptance runs above are those of the tree before its change. After the third review's fixes:
  `swift build` from an empty build folder complete without warnings, and the unit suite 232 tests in 25 suites
  passed (218 run, the 14 smoke runs skipped); again no simulation was started. After the fourth review's fixes:
  `swift build` from an empty build folder complete without warnings, and the unit suite 245 tests in 27 suites
  passed (231 run, the 14 smoke runs skipped); no simulation was started for these either. After the re-check's
  fixes: `swift build` complete without warnings, and the unit suite 247 tests in 27 suites passed (233 run, the 14
  smoke runs skipped); no simulation was started. After the guard attack's fixes: `swift build` complete without
  warnings, and the unit suite 251 tests in 28 suites passed (237 run, the 14 smoke runs skipped); no simulation
  was started. After the rule for the library folders of the line: `swift build` complete without warnings, and
  the unit suite 255 tests in 28 suites passed (241 run, the 14 smoke runs skipped); no simulation was started.
  After the last review's fixes: `swift build` complete without warnings, and the unit suite 258 tests in 28
  suites passed (244 run, the 14 smoke runs skipped); no simulation was started.
  The main session ran the smoke and acceptance runs again after the third round (03:07-03:21 CST), after the
  fourth (04:45-04:57) and on the final tree (05:40-05:53), each time with six to nine cores busy in other programs,
  so only the verdicts count, and each time with the same results: the 14 smoke runs passed, `check cg29 --lite`
  gave `ALL IDENTICAL (6 models)` with 18 of 18 exact rows, `diamond-check cg29` passed every comparison, and
  `e2e gcpw --lib cg29 --allow-concurrent` ended ok at 34,300 timesteps. After the last review's fixes the main session ran them once more
  (07:29-07:39 CST, the Mac again loaded), with the same results and the unit suite at 258 tests in 28 suites.
  The PDF was rebuilt with `pdflatex` from the final source (53 pages, no LaTeX warning, no overfull box).

## 2026-11-09: the code review's fixes (branch `fdtdkit`)

On 2026-11-08 (17:33 to 17:49 CST) the author ran Claude Code's cloud code review (`/code-review ultra`; the model of
its reviewers is not shown) on a scratch copy of the command line as of 2618180, cut to the review's limit of 8,000
changed lines: 18 of the package's 31 source files, 7,867 of their 11,634 lines (the files that start programs, choose
the libraries, write or delete files and decide pass or fail; the tests and the files that only parse options, plan
or print were left out). It reported one bug and five minor issues. On 2026-11-09 (01:03 to 01:22 CST) a separate
Claude Opus 5.5 session, opened by the author in the review's copy, wrote a fix for each of the six and four tests.
The main session (Claude Opus 5.5, Claude Code) applied that change to 7534d81, where it applied cleanly, and three
Claude Opus 5.5 agents in a read-only workflow of the main session checked it (08:38 to 09:09): one took the first
three fixes, one the other three, and one ran the suite with parts of each fix taken out (12 mutants) and the old and
new probe on fake bindings. They found that each fix does what it set out to do, except that the reuse of the snapshot
index in `check` had dropped a fallback, and raised 20 findings, 17 of them distinct. The main session acted on nine
of them, with five tests more, and lists the other eight below. No fork code, patch file, measured value or tool of
`bench/` and `scripts/` changed.

- The python probe (`Discovery.swift`; the review's bug): `import openEMS` and the lookups of the binding's version
  (`importlib.metadata.version('openEMS')`) and of its `openEMS.pyx` sat in one try block, so a binding that imports
  but has no package metadata, such as a build tree on `PYTHONPATH`, was taken for one that failed to import, and every
  command that probes Python stopped with `python_no_openems` (exit 3). The two lookups now come after the import, in
  try blocks of their own; without metadata the version is left out. On this Mac the old probe gave the error only
  with the user site-packages hidden as well, since the installed binding's metadata is found there (the checkers'
  runs). The main session added the test that runs the probe itself: LauncherTests
  `theProbeTakesABindingWithoutMetadata` runs it with a real `python3 -S` against the fake binding (no import error,
  no version, the pyx read), and the comment that called the snippets verbatim copies of the specification says that
  the probe differs from it since this day.
- Ctrl-C at the concurrency check (`Commands/CommandSupport.swift`, `concurrencyGate`): the stop controller kills each
  child as it starts, and an lsof scan without an exit status reads as `concurrency_unknown`, whose exit 5 outranks
  the interruption's 130, so a Ctrl-C there made bench, ab and e2e report a refusal. The gate now ends the command as
  `interrupted` when a stop came before it or during the scans. Three corrections of the main session, from the
  checkers' findings: the first check of a stop is now the gate's first line (it came after the installed library's
  probe, which a stop had made fail and which then started once more); a process that a scan found before the stop
  still counts (bench, ab and e2e refuse with 5, the other commands warn), where the review session's fix had let the
  interruption hide it; and the jobs recorded as planned after a stop are marked interrupted, as a job that a stop
  keeps from starting is elsewhere. Tests: ConcurrencyTests `aStopDuringTheScansIsAnInterruptionNotARefusal` (the
  review session's, now also on `check` and on the record of the planned jobs), `aStopBeforeTheGateStartsNoChild`
  and `aProcessFoundBeforeAStopStillCounts`; FakeSystem can now send a signal during scan B alone or after a given
  capture, and kill every child that starts after a stop.
- load's planned run folder (`Commands/CommandSupport.swift`, `plannedRunFolder`): a refused load recorded its
  launcher in `RUNS/emskit-fdtd/<stamp>-load-<pid>`, not in the hidden scratch folder `.<stamp>-load-<pid>` that a real
  load writes to and the protected-folder check looks at; it now records the scratch folder (NoInstallTests
  `aRefusedLoadPlansInTheScratchFolder`). The review also named load's dry run, but load takes no `--dry-run` (exit
  64), so the main session removed the branch that the fix had edited and that could never run, and `validate` takes
  its planned folder from the same function instead of building it by hand.
- check.sh's library argument (`Commands/CheckCommand.swift`, `Distribution.swift`): `check` predicted the rows'
  labels and run subfolders with one rule (a snapshot's name, else the folder) and the backend built check.sh's
  arguments with another that gave the same strings; both now call `FdtdLocalBackend.checkArgument`. No behaviour
  changed.
- Snapshot files read twice (`Commands/CommandSupport.swift`, `Commands/CheckCommand.swift`, `Libraries.swift`): a
  snapshot named as a LIB, `check`'s stock reference and the stock scan read and hashed files that the snapshot index
  had streamed already; all three now take the index entry (the stock scan with the registry names of both files,
  `FdtdSnapshotEntry.registryNames`), and `check` reads each snapshot file once and none whole again (LibraryScanTests
  `checkReadsEverySnapshotFileOnce`, StockTests `aRegistryNameInEitherFileFailsTheStockScan`). Two corrections of the
  main session: `check` found SNAPS/stock only through the index, so a stock folder that the folder's listing leaves
  out (another letter case on a case-insensitive disk, a SNAPS that can be searched but not listed) was no longer the
  stock the reference is matched against, and the check came out partial; it now falls back to the folder, as before
  (StockTests `aStockFolderTheListingLeavesOutIsStillTheReference`). And a snapshot name typed in another Unicode form
  than the listed one found the entry too (Swift compares strings canonically) and was recorded with the listing's
  bytes; the entry is now taken only for the same bytes (LibraryScanTests
  `aNameInAnotherUnicodeFormKeepsTheBytesTyped`).
- ab's sampler check (`Commands/CommandSupport.swift`, `Commands/ABCommand.swift`): built by hand for a run and by the
  backend for a planned or refused envelope; both now use the backend's rule. No behaviour changed.
- Left as they are, the checkers' other eight findings, seven on code that the fixes left as it was and one on how
  three of the changed places share a rule: the rfsim probe
  reads the toolkit's values without defaults, so a toolkit that lacks one ends with exit 4 (`tool_output_unparsed`),
  although the rest of the code treats each value as optional; the protected-folder check keeps, for the rest of the
  command, an answer of the installed library's probe that a stop cut short, so an `--output` inside a non-default
  installed prefix is then not refused; `info` reads a snapshot named with `--lib` twice, and a LIB that names a SNAPS
  folder by its path is read again; the rule "take the index entry for a folder that the index holds" is written in
  three places with three conditions; `info` installs no stop handler, although it runs probes and scans (its comment
  says it starts no child); the probe and the launcher take the binding's version from the package metadata by name,
  which can belong to another installed copy; and the probe's `legacyEmptyOption` is null where the launcher's is
  true (an `openEMS.pyx` that cannot be read, a package that does not import `openEMS.openEMS`). All of these were
  closed on 2026-11-10 (the entry above, "The open items").
- Tests: 158 tests in 20 suites (144 unit tests in 19 suites and the 14 smoke runs), nine more than at 7534d81: the
  four of the review session and five of the main session. In a copy, each change of the main session was taken out
  once (seven mutants), and each time a new test failed.
- Documents: `README.md` (the command line's status, the paragraph on AI assistance), `ROADMAP.md` (the command
  line's row), `Docs/fdtdKit/PLAN.md` (the status line, the stop rule of section 10.1, section 12's rows and counts,
  the entry of section 16) and the paper (dated 2026-11-09; the command line's paragraph and the Disclosure of the
  closing section).
- Checks, on a Mac loaded by other programs (another session's Fortran program and Swift tests), so only the verdicts
  count. On the review session's change alone, earlier the same morning (08:36 to 08:48): the unit suite 153 tests in
  20 suites passed, the 14 smoke runs passed (78 s), and the three acceptance runs below passed. On the final change,
  09:24 to 09:33, with the other processes at 3.0 to 5.4 cores and 0 to 8 % of the GPU: `swift test --filter
  fdtdKitTests` 158 tests in 20 suites passed (144 run, the 14 smoke runs skipped); the seven mutants were each caught,
  and the copy without them passed; the 14 smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--no-parallel`) passed in 61 s; on
  cg29, `check cg29 --tag rvfix2 --lite` gave ALL IDENTICAL on the six models (18 of 18 exact rows, the reference
  matched to stock by sha256; 09:27:37 to 09:32:17, during which this session's build below ran for 10 s),
  `diamond-check cg29` 72 of 72 comparisons identical, and `e2e gcpw --lib cg29` stopped by the probe end criterion
  after 34,300 steps, as before (`FDTD.Run` 8.6 s); their tables went to a scratch folder, not to `results/`. Two
  `pdflatex` passes gave 52 pages with no warning and no overfull or underfull box. After three lines were wrapped and
  one comment reworded (09:35), `swift build` from an empty build folder completed without warnings (6.5 s, Swift
  6.4.2), the 14 smoke runs passed again (59 s, the other processes at about 2.3 cores and 5 % of the GPU), and the
  unit suite passed again (158 tests in 20 suites), also after this entry and the plan's were written.

## 2026-11-08: the pre-push audit's fixes and the author's decisions (branch `fdtdkit`)

On 2026-11-07, before this repository's first push, Claude Opus 5.5 agents in a read-only workflow of the main session
audited the copy that the push would publish (`git archive` of `main` at 41f43b1, without `PUBLISH.md`,
`NEXT_WORK_PROMPT.md` and `CLAUDE.md`). Six auditors (privacy and the records, references, build and tests, the paper,
the patches, the licence) raised 35 findings. A skeptic confirmed 32 of them (four that call for a fix and 28 notes)
and refuted 3; none blocks the push. A critic then planned the fixes, listed the checks still missing and eight
decisions for the author; four of them were put to the author as questions, which the author answered on 2026-11-08
(around 06:45 CST). This change, on top of 41f43b1, applies the four answers (the first four items below) and acts on
the four fixes and on 23 of the notes; five notes stay as they are. No fork code, patch file, measured value or file
of `Sources/` changed, and nothing was created on GitHub or pushed. It was made by Claude Opus 5.5 agents in a
workflow of the main session (Claude Opus 5.5, Claude Code): three editors (the front documents with the records and
the test fixture; `Docs/fdtdKit/PLAN.md` with `ROADMAP.md`; the paper) and an agent that went over the whole change,
brought the author's publishing steps up to date, wrote this entry and ran the checks. Two read-only checkers then
went over the change, one of them over a copy of its export, which it also built, tested and made into the one-commit
repository in a scratch folder; one more agent applied their nine findings.

- The licence: the push no longer waits for an agreement of the kits that share the Swift package. The package stays
  under GPL-3.0-or-later, as decided on 2026-11-06, and femKit, momKit and sbrKit, which have no code in this
  repository, choose their licence when they are merged and published (code under Apache-2.0 can join a
  GPL-3.0-or-later program, not the reverse). `README.md` ("Status and licence"), `ROADMAP.md` (Phase 0) and sections
  13 and 15 of `Docs/fdtdKit/PLAN.md` say so; the push is still to come, and the Phase 0 row moves to Done on that
  day.
- The records: `results/` is published as measured, with the processes that loaded the Mac in its `busy` columns and
  its paths in the home folder, except three mentions of the main session's ID in comment lines
  (`rfsim_e2e_gpu_2026-11-04.txt`, `rfsim_e2e_cg29_2026-11-05.txt` and `cpu_items_cg29_2026-11-05.txt`), which no test
  reads. Those words were removed, and no other byte of `results/` changed.
- The name: the repository stays emsKit and the documents fdtdKit; no file changed for it.
- The GPL wording: `README.md`, the paper's licence paragraph and its CC BY notice called the harness, the scripts,
  `paper/code_notes.md`, `swift_engine/` and the result files "GPLv3", that is version 3 only; all three now say
  GPL-3.0-or-later, like the patches, the Swift package and upstream, and so does section 15 of the plan. The README's
  row of the CSXCAD patch says LGPL-3.0-or-later, as `patches/README.md` does.
- The command line in `README.md`: the `check` example has `--allow-partial`, and a paragraph after the examples says
  that `check` runs all six models, and `e2e` runs at all, only with the author's rfsim toolkit, which is not public
  (without it both stop with `rfsim_not_found`, exit 2; with `--allow-partial` `check` runs the other four models,
  with status partial). The smoke runs are written for the author's Mac, and run 2 checks the identities of the
  author's own library files, so it fails on any other build; the README says so, and it names what the Command Line
  Tools alone give: three linker warnings on each build, and test builds that can fail with "plugin for module
  'TestingMacros' not found". The code is unchanged: the hint of `rfsim_not_found` names only `--rfsim`, and smoke run
  2 has no hash guard.
- `Docs/fdtdKit/PLAN.md`: the code comments cite the command line's specification, a working note that is not
  published, by its own section numbers ("spec N"), so a new paragraph after the plan's opening maps the
  specification's sections 2 to 16, the only ones the code cites, to the plan's. Section 3's line numbers refer to the
  repository as published (they were read at 00e8f7d, and the cited lines are unchanged); F23 cites `BUILD.md` section
  7; the item "Where" and rule S10 are in the past tense, without the paths of the author's worktrees, and dbc1baa is
  marked as a commit of the unpublished history; section 14's rule against `update_openEMS.sh` and `build_python.sh`
  now applies only to the author's own checkout of the superproject, where they and a private setup script (no longer
  named) build an older tree, while a fresh checkout uses them, as `BUILD.md` sections 5 and 6 do; and section 5.1
  says that smoke run 2 checks the stock and cg29 rows without the hash guard of LibraryScanTests.
- `BUILD.md` section 4: no upstream branch holds the base 7bb294f any more, and GitHub serves it by its hash. If that
  fetch fails, a new fallback fetches the fork's branch `speed-m5-gpu`, whose first commit on the base, patch 0001,
  has the base as its parent (tried in a throwaway clone: tree 90f8c01 with 27 commits).
- Hashes and working files: `README.md` ("Status and licence") says that the fork hashes in records made before
  2026-11-07 are those from before that day's rewrite, which the table of the entry of 2026-11-07 maps, and its
  `results/` row says that the files that the records place in the scratchpad were the assistant session's working
  files, which are not published.
- Notices: the tests' stub `openEMS.pyx` (in `Tests/fdtdKitTests/Fixtures/fake_openEMS/`, 30 lines cut from upstream's
  v0.37.0 binding) begins with an SPDX line, where and when it was cut, upstream's copyright line and a licence
  notice; `paper/LICENSE-CC-BY-4.0.txt` names `figures/tab_*.tex` among the paper's text and the Swift package among
  the code under the GPL; `swift_engine/fdtd.swift` credits openEMS's Engine_sse, whose operation order its kernels
  follow.
- Wording: `patches/README.md` names the new heading of the list of corrections in the message of 0006 and the change
  of 0017 to the compressed operator's index; `scripts/README.md` gives the diamond options of
  `swift_engine/fdtd.swift`.
- The paper: Table 4's text column is ragged right (its four underfull boxes are gone), and the title keeps "Apple M5"
  together. The reference for RDMA over Thunderbolt 5 in macOS 26.2 cites Apple's release notes of macOS Tahoe 26.2
  and its technical note TN3205 instead of a news summary. The Disclosure says, as the README now does, that the
  trailer of 0001 also names Claude Opus 5.5, which wrote that patch's code, and both record the audit and this
  change. `\date` gives 2026-11-08; "draft" and the sentence that the author has not yet read every line of the fork
  stay. Two `pdflatex` passes: 52 pages, no LaTeX warning, no overfull or underfull box.
- File modes: `bench/bench.py`, `bench/runner.py` and `bench/validation/run_validation.py`, which start with a
  shebang, are executable now; their content is unchanged.
- The author's publishing steps (not published) record the four decisions and give the tarball command for arXiv
  without the hidden AppleDouble members and xattr headers that macOS's tar adds, the result of a test compile of that
  tarball, the limit of the arXiv form on the abstract (1,920 characters, about half of the paper's) with its comments
  field, the checks of gh's login and of two e-mail settings of the GitHub account before the push, and the result of
  a trial of the steps up to the one commit in a scratch folder.
- Left as they are, the five notes: the name of the author's private project in the messages of fork commits 0003 and
  0006 and in two result file names; the local folder name that 0002 adds in a code comment and 0006 removes; the
  GitHub login in four lines of this file; the SHA-256 of the author's first name in `TextRuleTests.swift`; and the
  interface details of the private toolkit, which let readers rerun the board models with `RFSIM_PATH`. Each is public
  already (through the pushed forks or the author line) or there on purpose, and the patches must stay equal to the
  published commits. Also left: the other paths of the author's folder layout (in dated entries of this file, in a
  script's defaults and, in section 14 of the plan, the name of a backup folder), which hold no personal data, and the
  26 JSON files without a final newline (records and test fixtures).
- Checks, 07:17-07:28, with the other processes at 0.6 cores and 6 % of the GPU before `tables.py`, and at 9.4 to 9.8
  cores (Swift test processes and four pw.x processes of other programs) and 4 to 5 % of the GPU around the build and
  the tests: `paper/figures/tables.py` wrote its three outputs with the bytes they had (`git status` and
  `git diff --stat` the same before and after it, the README's speed table equal to that of 41f43b1); the arXiv
  tarball, made with the new command (20 members, none hidden and none with an xattr header), compiled on its own in
  an empty folder with two `pdflatex` passes to the same 52 pages, with no warning and no overfull or underfull box,
  and its text equal to that of `paper/emskit.pdf`; `pdftotext` of the PDF has cg29 on 154 lines, emskit only in the
  passages that the publishing steps allow, and no hyphenated fdtdKit; `swift build` from an empty build folder
  complete without warnings (15.0 s, Swift 6.4.2); the unit suite (`swift test --filter fdtdKitTests`) 149 tests in 20
  suites passed (135 run, the 14 smoke tests skipped), among them TextRuleTests, GrammarTests, KnobTests and
  LauncherTests, which read the plan, the README, `BUILD.md` and the fixture, and again at 07:31, after this entry and
  the plan's were written (the other processes then at 2.7 to 3.8 cores and 5 % of the GPU). The smoke runs were not
  run. After the checkers' findings were applied, at 08:24 with the other processes at 8.8 to 9.9 cores (other
  programs' Swift tests and solvers) and 5 % of the GPU: `swift build` from an empty build folder complete without
  warnings (12.2 s), and the unit suite again (149 tests in 20 suites passed).
- Left for the author: reading the paper and the patches (then "draft" and that sentence go), the DOI and when to get
  it, the author's own review of the command line, the push of this repository and the arXiv submission.

## 2026-11-07: a fresh build of the published patches passes the full check (branch `fdtdkit`)

The publishing steps ask for a build of the published branch from a fresh clone, and its full check, before this
repository's first push. The author chose to have that run while the push waits for the licence (the entry below).
The main session (Claude Opus 5.5, Claude Code) ran it on 2026-11-07, on a Mac loaded by other programs, so only the
verdicts count; the record is `results/fresh_build_pub29_2026-11-07.txt`. Claude Opus 5.5 agents in a read-only
workflow of that session then checked the record against the raw logs, and the changed files; the 22 findings that
their verifiers confirmed (of 23) were fixed before the commit.

- Build: a fresh clone of upstream's superproject at v0.37.0, the CSXCAD patch and the 27 openEMS patches applied with
  `git am` (trees 902b9d6 and 90f8c01, those of the published heads), and `update_openEMS.sh --disable-GUI --python`
  into an empty prefix (`BUILD.md` sections 1, 4 and 5). Its dependency check said that it did not pass, because
  Homebrew's Python formulas were missing; the build completed all the same, with the Python modules in the script's
  own virtual environment, which pip filled (`BUILD.md` section 5 now says so).
- Checks of that build, as snapshot pub29: `bench/check.sh pub29 pub29` with `RFSIM_PATH` set, every run identical to
  stock on the six models (`results/*_pub29.txt`); `debye_check.sh` PASS, with snapshot cg29 as the second reference;
  `diamond_check.sh` 72 of 72; the six models on `metal-diamond` identical to the multithreaded engine with
  `OPENEMS_FTZ=1` (`results/*_pub29gpu.txt`); the validation suite 15 of 15 with the multithreaded engine at 4 threads
  and with the fastest engine (`results/validation_pub29_*`); the cylindrical multigrid, 34 datasets equal to stock's.
  The validation suite needs scipy (`bench/validation/README.md`), which the build's virtual environment does not
  have: it was added with pip after its first two starts stopped at the import. In the validation files the path of
  the build's scratch folder is replaced by `$PUBCHECK`. Not repeated: the three extra `check.sh` configurations of
  cg29, its box checks and its run-mode matrix (`results/cpu_items_cg29_2026-11-05.txt`, section 3).
- `paper/figures/parse_results.py` ran again, as the publishing steps ask: `results/summary.json` holds every model
  table in `results/` itself up to pub29 (not those in `others_2026-11-04/`), the entries written on 2026-11-03
  unchanged. The script now leaves `metal-diamond` rows out of the CPU speed, as it did `gpu` rows, so the entries of
  the `*_cg2Ngpu.txt` (cg20 to cg29) and `*_pub29gpu.txt` tables give the multithreaded row. Its docstring, the
  README's `results/` row and the paper's list of artefacts now say that the tables after cg18 are correctness checks,
  not speed results. The figures were not made again (they read the entries of cg14 and older).
- Documents: `BUILD.md` (the opening paragraph, the note on commit hashes, section 5's note on the dependency check,
  section 9), `README.md` (the checks paragraph, the `bench/validation/` and `results/` rows, the chronology),
  `bench/validation/README.md` (its list of runs), the note at the top of this file (the records in `results/` made
  before 2026-11-07 give the earlier hashes), the paper's method section, its list of artefacts (the new tables and
  validation runs, the version string of this build) and its Disclosure, `ROADMAP.md` (Phase 0 now names only the
  licence; a row under Done), section 13 and the log of section 16 of `Docs/fdtdKit/PLAN.md`, and `patches/README.md`
  (which entry maps the hashes).
- Checks: 09:28-09:29, with the other processes at 0.4 to 0.5 cores and 0 to 1 % of the GPU: the paper rebuilt with
  two `pdflatex` passes, 52 pages (the new sentences of the method section and the Disclosure), with no undefined
  reference and no overfull box (its four underfull boxes, in the GPU section's snapshot table, as before);
  `swift build` from an empty build folder complete without warnings (5.4 s); the unit suite 149 tests in 20 suites
  passed, and again after the log entry of the plan was written. After the corrections from the check, at 10:01 with
  the other processes at 0.6 to 0.7 cores and 5 to 6 % of the GPU, the paper again (52 pages, the same four underfull
  boxes) and the unit suite again (149 tests in 20 suites passed).

## 2026-11-07: the fork's commits rewritten for publication and pushed (branch `fdtdkit`)

The author asked on 2026-11-07 for section 1 of the publishing steps to be run on the two fork branches, with the old
branches kept as local backups, with patch 0001 naming both models, and with the hashes treated as below, and then for
the two branches to be pushed. The branches are `speed-m5-gpu` of the openEMS fork (27 commits on 7bb294f) and
`speed-m5` of the CSXCAD fork (one commit on v0.7.0). This repository is not pushed yet: it waits until a fresh build
has passed the full check and the kits that share the Swift package agree on its licence. The work was done by the
main session (Claude Opus 5.5, Claude Code), and Claude Opus 5.5 agents in two read-only workflows of that session
checked it: before the push the first rewrite and a first version of the changed files of this repository, after the
push the pushed branches and the final files. The main session compared the second pass (below) commit by commit.

- Every commit now has the author's name with the GitHub no-reply address of the account anmartinez1256 as author and
  committer. Its `Co-Authored-By:` trailer became `Generated-by: <the same model> (Anthropic)`, followed by a
  `Signed-off-by:` line with the same identity as the last line, the form that upstream's `AI_POLICY.md` asks for.
  Patch 0001 names both models, `Generated-by: Claude Opus 5.5, Claude Fable 5.1 (Anthropic)`: Claude Opus 5.5 wrote
  its code and Claude Fable 5.1 committed it (the paper's Disclosure). Of the other commits, 22 name Claude Opus 5.5,
  and four openEMS commits and the CSXCAD commit name Claude Fable 5.1. The trees of all 28 commits and their author
  dates and subjects are unchanged, so the heads keep trees 90f8c01 and 902b9d6, the code that was checked; so are the
  message bodies, apart from that of 0006 (next item).
- The rewrite ran in fresh clones; each rewritten commit was compared with its old one (tree, author date, identity,
  and the message that the rule gives) before the two branches were moved to the new commits. The old commits stay on
  the author's Mac on backup branches, which are not published. The first check found that the message of 0006, which
  lists corrections to 0001-0005, named those commits by their old hashes and said "(not reworded, so the hashes
  stay)". A second pass, before the push, gave it their new hashes (9651fff, 4acfb64, 487e684, a5195df, 99e20fd) and
  "(not reworded)"; only that message changed, so 0001-0005 kept their hashes and 0006-0027 got new ones once more.
  The table below gives the final hashes.
- The two branches were pushed at 08:01 CST to public forks of upstream's repositories under the account
  anmartinez1256, made at 07:54 with upstream's default branch only: `speed-m5-gpu` (head 78fe656) to
  github.com/anmartinez1256/openEMS and `speed-m5` (bc854b7) to github.com/anmartinez1256/CSXCAD. GitHub shows the
  heads with the public identity and the two trailers as the last lines; the backup branches were not pushed. The push
  also keeps the base commit 7bb294f available, which no upstream branch contains any more.
- The patches were made again from the final commits. In each file the first line (`From <hash> ...`, now the
  published commit) and the trailers changed, and in 0006 also the hashes of 0001-0005 wherever its message names them
  (its list of corrections, whose heading now ends "(not reworded)", and three references to the build of 0005 in its
  notes on the checks); the `From:` lines had the public identity since 2026-11-06, and the two cumulative diffs are
  the same byte for byte. `git am` of 0001-0027 on 7bb294f gives tree 90f8c01 with 27 commits that carry the public
  identity and the new trailers; the CSXCAD patch on v0.7.0 gives 902b9d6.
- The hashes that point a reader to the fork's code are now those of the published commits: `BUILD.md` (the tested
  trees, the sources with the head's `git describe --tags`, v0.37.0-45-g78fe656, the result of `git am`, the code
  behind the cg29 version string, and a new note on the hashes), `patches/README.md`, the paper's GPU section (the
  commits of cg19-cg28 in its text and table, and the `git diff --stat` it cites) and section 3 of
  `Docs/fdtdKit/PLAN.md`. Records keep the hashes they were made with: `results/`, `scripts/gpu_crossover/header.txt`
  (from which the crossover record is made), the entries of this file dated before 2026-11-07 and those of section 16
  of the plan, and the version strings that built libraries print (`v0.37.0-NN-g<hash>`, the commit at which a build
  folder was configured). The table below maps the old hashes to the new ones.
- `README.md` ("Status and licence") and the paper's Disclosure say that the fork's commits name the model in a
  `Generated-by:` trailer above a `Signed-off-by:` line and record this day's work; the paper's date is 2026-11-07,
  its list of the repository's contents and the note at the top of this file say which hashes are which, and the
  paragraph on the corrections of 0001-0005 in the paper's engine section and the item "Commit messages" of `BUILD.md`
  section 8 say that their message bodies are kept as written (their trailers changed). `ROADMAP.md` (Phase 0 and
  Done) and sections 13 and 16 of the plan record the rewrite and the push.
- Checks, 08:32-08:35, with the other processes at 8.3 to 8.5 cores (another program's eight processes) and 6 to 46 %
  of the GPU between the steps: the paper rebuilt with two `pdflatex` passes, 51 pages as before, with no undefined
  reference and no overfull box (its four underfull boxes, in the text column of the GPU section's snapshot table,
  were there before); `swift build` from an empty build folder complete without warnings; the unit suite 149 tests in
  20 suites passed; the 14 smoke runs passed in 72 s. After the corrections from the second check, at 09:09 with the
  other processes at 1.4 cores and 10 % of the GPU, the paper again (51 pages, the same four underfull boxes) and the
  unit suite again (149 tests in 20 suites passed).

| before | published | commit |
|---|---|---|
| 0893f50 | 9651fff | openEMS 0001: Speed up the multithreaded engine on Apple M5 (bit-identical to stock) |
| d610d9f | 4acfb64 | openEMS 0002: Speed up operator setup and nf2ff, add engine export hooks (snapshot cg9) |
| 976ed0d | 487e684 | openEMS 0003: Cut engine memory traffic on real boards (snapshots cg10-cg15) |
| b2c4ddd | a5195df | openEMS 0004: Probe end criterion: stop once every probe has settled (OPENEMS_PROBE_END_DB) |
| 489b805 | 99e20fd | openEMS 0005: Review fixes: Debye hooks, probe end arming, setup cache key, portability (snapshot cg17) |
| 087ce9e | cb168f7 | openEMS 0006: Review fixes: probe end delays and mode match, =0 switches, FTZ restore, size guard |
| 315acee | 6b23756 | openEMS 0007: Metal diamond engine: --engine=metal-diamond with excitation and Mur (snapshot cg19) |
| cd80d8c | 7ac3438 | openEMS 0008: Metal diamond engine: lumped RLC elements on the GPU (snapshot cg20) |
| 75417db | 2c79751 | openEMS 0009: Metal diamond engine: UPML on the GPU, extension data in three buffers (snapshot cg21) |
| 57511e8 | 5ea5ffd | openEMS 0010: Metal diamond engine: Drude/Lorentz materials and conducting sheets on the GPU (snapshot cg22) |
| 452f905 | 0242c5f | openEMS 0011: Metal diamond engine: Debye materials on the GPU (snapshot cg23) |
| 3a8ca20 | 8dd56e5 | openEMS 0012: Metal diamond engine: multithreaded operator setup, GPU timing diagnostics (snapshot cg24) |
| ab12bbe | 3db2791 | openEMS 0013: Metal diamond engine: runs for the excitation and the dispersive materials (snapshot cg25) |
| 74479c0 | ca7c334 | openEMS 0014: Metal diamond engine: the grid as compile-time constants (snapshot cg26) |
| 4127e1e | 282707b | openEMS 0015: Metal diamond engine: split coefficient tables for graded meshes (snapshot cg27) |
| 85dc48c | 68c1c82 | openEMS 0016: Metal diamond engine: pick the tiling at run time (snapshot cg28) |
| 09c170c | e1b83c6 | openEMS 0017: Compressed operator: one operator index per z-vector |
| 8587ebc | e57d3fc | openEMS 0018: Dispersive line hooks: the orders of a position back to back, four positions at a time |
| 29981cd | 67e6f6e | openEMS 0019: UPML: the scalar SSE path four y-rows at a time |
| 3e5d678 | 0ff3802 | openEMS 0020: UPML operator: compute the coefficients on the setup threads (upstream PR #244) |
| 12aeaff | 3c75b0b | openEMS 0021: Steady-state detection: line hooks for the fused sweep |
| 2cebd7c | 8d792c5 | openEMS 0022: Debye material: line hooks for the fused sweep |
| bfd1298 | 11f1624 | openEMS 0023: Compressed engine: geometry coefficient tables when the packed ones exceed 4 MB |
| 9e64203 | ae21bd1 | openEMS 0024: Multithreaded engine: OPENEMS_FUSED_STAT, the time split of the fused sweep per thread |
| 050271c | 8f9d55e | openEMS 0025: Multithreaded engine: neighbour flags instead of the two barriers of the fused sweep |
| c86f402 | 51cc401 | openEMS 0026: Steady-state detection: TS_LOCAL, so that it runs with the neighbour flags |
| 1620939 | 78fe656 | openEMS 0027: Neighbour flags: no spin above the performance-core count (snapshot cg29) |
| 34f3d85 | bc854b7 | CSXCAD 0001: Speed up material lookups during openEMS operator setup |

## 2026-11-06: the author's publishing decisions (branch `fdtdkit`)

The author's answers of 2026-11-06 (around 17:25 CST) to seven questions on publishing: `patches/rfsim/` is left
out; the command line's Swift package is under GPL-3.0-or-later; `main` goes public as one fresh commit, without the
history in which it was made; that commit and the patch files carry the author's name with the GitHub no-reply address
of the account anmartinez1256; the repository and the two fork branches are linked under that account; the paper's
author line gives the affiliation, University of Texas at Austin; and the work of 2026-11-03 that the project log does
not record is credited to an AI assistant session whose model is not recorded. This change applies them, on top of
64d19f8 (the documentation update, to which `main` was fast-forwarded that day, so `fdtdkit` is merged into `main`).
No fork code, result or measured value changed (the patch files changed in one header line only), and nothing was
created on GitHub or pushed. It was made the same evening by the main session (Claude Opus 5.5, Claude Code) and
Claude Opus 5.5 agents in a workflow of that session, on the author's decisions: after the mechanical part (the
deletion, the patch headers, the SPDX lines), three editors (the front documents, the author's steps with
`Docs/fdtdKit/PLAN.md`, the paper), a read-only checker for each, one agent that applied the checkers' findings, and a
last agent that went over the whole tree, ran `tables.py`, rebuilt the PDF, ran the tests and wrote this entry.
- `patches/rfsim/` (0001-0003, the changes to the author's private toolkit) was left out of the published repository
  at the author's decision; `results/` and the entries below keep the record.
- The Swift package of the command line (`Package.swift`, `Sources/`, `Tests/`) is under GPL-3.0-or-later:
  `// SPDX-License-Identifier: GPL-3.0-or-later` in all 45 Swift files of the package (`Package.swift` on line 2,
  after the tools-version line; every other file on line 1, then a blank line), and `# SPDX-License-Identifier:
  GPL-3.0-or-later` as line 1 of the launcher `Sources/fdtdKit/Python/fdtdkit_run.py` and of its embedded copy in
  `Sources/fdtdKit/LauncherSource.swift`, which stay equal byte for byte. The 25 test fixtures (text, JSON and the stub
  openEMS package) have no such line. The launcher that the command line writes into each run folder has one line
  more, so the sha256 that the envelope records for it changes; the command line behaves as before. `LICENSE` holds
  the licence text, and the licence paragraphs of `README.md` and the paper and section 15 of `Docs/fdtdKit/PLAN.md`
  give it. femKit's plan proposes Apache-2.0 for its packages, so the kits that share the package are to agree on its
  licence before the first push.
- The `From:` line (line 2) of the 28 patch files (`patches/openems/0001-0027`, `patches/csxcad/0001`) now carries the
  author's name with the GitHub no-reply address of the account anmartinez1256; nothing else in them changed. `git am`
  of 0001-0027 on 7bb294f gives tree 90f8c01, the tree of the fork's head 1620939, as before, and the CSXCAD patch on
  v0.7.0 gives 902b9d6, the tree of 34f3d85; the commits that `git am` makes carry the new identity. The first line of
  each patch (`From <hash> ...`) still names the fork's commit, and the fork's own commits keep the author's git
  identity and their `Co-Authored-By:` trailers until the fork branches are rewritten (below).
- The paper: `\author` gives the author's name with the affiliation, University of Texas at Austin, on its own line
  (the placeholder footnote is gone), and `pdfauthor` the same name. `\repourl`, set once in `paper/emskit.tex`, gives
  https://github.com/anmartinez1256/emsKit, which the abstract and the repository list of "Reproducibility and
  artefacts" use; the to-do note there now asks the author only for a DOI. `README.md` ("What is in the box") and
  `BUILD.md` (section 1) link the two fork branches, https://github.com/anmartinez1256/openEMS/tree/speed-m5-gpu (the
  27 commits of `patches/openems/` on 7bb294f) and https://github.com/anmartinez1256/CSXCAD/tree/speed-m5 (the commit
  of `patches/csxcad/` on v0.7.0). The links name where the repository and the branches are to be; nothing was
  created or pushed.
- The work of 2026-11-03 that the project log does not record: the first versions of the paper's positioning section
  and of `ROADMAP.md`, the abstract's sentence on clusters, the README paragraph "Scaling out" and `bench/validation/`
  with its two Linux runs were added by an AI assistant session whose model is not recorded (the author's answer), and
  the two runs of snapshot cg17 on the Mac (`results/validation_cg17*`) came later that day from a Claude Opus 5.5
  session in the Claude desktop app, also outside the project log. `README.md` ("Status and licence") and the paper's
  Disclosure say so, without the two to-do notes that asked the author. The Disclosure now also limits the toolkit
  changes it credits to Claude Fable 5.1 to those up to 2026-11-02, and it records this change.
- The files left out. `PUBLISH.md`, `NEXT_WORK_PROMPT.md` and `CLAUDE.md` are not published (the note at the top of
  this file), so the present-tense text no longer points a reader to them: `README.md` (the places where the old name
  emsKit appears; the work plan of 2026-11-04, now "a working note that is not part of the published repository"; the
  licence of the Swift package), the paper's Disclosure and licence paragraph, `ROADMAP.md` (the publication items of
  Phase 0, and the `accept` bundle of Phase 5, which now names the full check itself, as run for cg29 in section 3 of
  `results/cpu_items_cg29_2026-11-05.txt`), `Docs/fdtdKit/PLAN.md` (section 11 states the family's rule on
  distribution itself; sections 13, 14, 15, 17 and 18), the comment on line 3 of `.gitignore`, and the comment on
  `--distribute` in `Sources/fdtdKit/Options.swift`, which now names section 11 of the plan. `README.md` ("Status and
  licence") also says that the repository is published as one commit and that the hashes of its own commits in the
  records name commits of that history; section 16 of the plan says the same of its entries and has an entry for
  this change.
- The toolkit. `README.md`, `BUILD.md` (sections 4 and 7), `patches/README.md`, `scripts/README.md`, the comments of
  `scripts/sma_mesh/batch.sh`, `scripts/zpad/zpad_full.py` and `scripts/probe_end/pend_run.py`, and the paper (the
  abstract, `sec_method.tex`, `sec_modelling.tex`, `sec_results.tex`, `sec_positioning.tex`, `sec_closing.tex`, the
  docstrings of `fig_mesh.py` and `fig_runtime.py`, a caption string of `tables.py`) now say that the changes made in
  this project to the toolkit are not published, since the toolkit itself is private, and name what the runs used
  instead of a patch file: the toolkit's defaults until 2026-11-04 (a 0.02 mm floor and a hold of 1), the 1.071 M-cell
  mesh of its former 0.02 mm floor, and in `scripts/README.md` its commits ed3ac3e and 2948d58 (2026-11-01: the
  automatic thread count and the z padding; the probe end option) and 2b0fd8c and 4a7e20e (2026-11-04: the mesh floor
  with the fixes of 2026-11-02 and 2026-11-03; the defaults since then). No measured value changed. `tables.py` then
  rewrote the README's speed table, whose caption is the only change; `tab_current.tex` and `tab_e2e_cg29.tex` came
  out unchanged.
- Checks, 18:45 to 19:01, with the other processes at 0.6 to 1.6 cores and 5 to 6 % of the GPU between the steps:
  the PDF rebuilt with two `pdflatex` passes, 51 pages as before, with no undefined reference and no overfull or
  underfull box that the text of 64d19f8 does not have; `swift build` from an empty build folder without warnings
  (Swift 6.4.2); `swift test --filter fdtdKitTests`: 149 tests in 20 suites passed (135 run, the 14 smoke tests
  skipped), also after the last edit of `Docs/fdtdKit/PLAN.md`; the 14 smoke runs passed in 45 s (another program used
  up to 56 % of the GPU during one of them). No file holds the author's personal e-mail address.
- Left for the author: the paper's date line, the word "draft" and the sentence that the author has not yet read
  every line of the fork, until the paper and the patches are read; the DOI (its to-do note in
  `paper/sec_closing.tex`); the `busy` columns and the home-folder paths in `results/`; the name on the public pages
  (the repository emsKit, the documents fdtdKit); the other kits' agreement on the licence of the shared package
  before the first push; the rewrite of the fork branches' identity and trailers, with the patches made again from
  them and a choice for the fork hashes that `results/` cites; a build and full check of the published branch; and the
  push.

## 2026-11-06: cg29 installed on the author's Mac; documentation pass (branch `fdtdkit`)

Snapshot cg29 replaced cg18 as the build installed on the author's Mac, and the documents now say so. The pass also
closed the 18 stale or inconsistent statements that a read-only audit had found in the documents at commit 2618180,
and it records the check of the name fdtdKit. No fork code, patch, tool, result or source file of the command line
changed; two tests learned the new install (below). The install and the pass were made by the main session (Claude
Opus 5.5, Claude Code) and Claude Opus 5.5 agents. The pass ran as a workflow of the main session: three editors
(`README.md` with `BUILD.md`, `ROADMAP.md` and `patches/README.md`; `PUBLISH.md` with `Docs/fdtdKit/PLAN.md`; the
paper), a read-only checker for each, one agent that applied the checkers' findings, and a last editor that went over
the whole tree again and wrote this entry; the main session then read the changes and updated the two tests.
- The install. At 10:00 snapshot cg29 (patches 0001-0027, version string v0.37.0-44-g074a687) went over the author's
  openEMS prefix (`~/opt/openEMS`), which had held cg18 (patches 0001-0006) since 2026-11-04 02:20; the cg18 prefix
  was backed up beside it first. Two files changed: `lib/libopenEMS.0.37.0.dylib`, now snap/cg29's library with the
  prefix's install name and rpath, re-signed (cg29's build UUID, 40BC8CFF-6082-3FAD-BE46-832EAF165E8C, in other
  bytes), and `include/openEMS/openems.h`. The prefix's `libCSXCAD` and `libnf2ff` already had cg29's bytes.
  `cmake --install` was not used: none of the author's build folders both matches cg29 and installs into the prefix
  (`Docs/fdtdKit/PLAN.md`, section 14). The Python modules stayed upstream's v0.37.0 binding in the user
  site-packages: no file under `python/` changed between cg18 and cg29, and `openems.h` only appends
  `EngineType_Metal_Diamond` to an enum; without a rebuild of the modules only SAR is affected (`BUILD.md` section 6).
  `bin/openEMS` is still the one installed with cg18; no XML run of it on cg29's library is recorded.
- The checks from the install, 10:04-10:15, with the command line's release build (`emskit fdtd` 0.1.0, tree
  2618180). Other programs kept 4.6 to 8.5 cores busy, so the speeds these runs printed are not quoted; only the
  verdicts count. `debye-check installed --ref cg29`: PASS (basic against sse-compressed, sse-compressed against
  multithreaded, and the installed library against snap/cg29, all identical). `check installed --tag inst29 --lite`:
  ALL IDENTICAL, 18 of 18 rows exact on the six models against stock v0.37.0. `diamond-check installed`: 72 of 72
  comparisons identical in 9 boxes. `validate --lib installed`: 15 of 15 with the fastest engine and 15 of 15 with
  the multithreaded engine at 4 threads. `e2e gcpw --lib installed`: finished, stopped by the probe end criterion at
  step 34300, as before. The six `results/*_inst29.txt` tables were copied out of the tree and are not in the
  repository; `Docs/fdtdKit/PLAN.md`, section 16, logs the runs.
- For the toolkit: its runs (the CPU engine with the automatic thread count and the probe end criterion) now run on
  cg29 with no change on the toolkit's side. The Metal diamond engine is in the installed library but opt-in, and the
  toolkit does not select it. How much faster cg29's CPU engine is than cg18's was measured in paired rounds on
  2026-11-05: 1.13 to 1.42 times cg18's rate with the automatic thread count over the six models, the SMA launch on
  its 0.871 M-cell mesh (`results/cpu_items_cg29_2026-11-05.txt`, section 4).
- Tests: `Tests/fdtdKitTests/LibraryTests.swift` (the installed row of `Docs/fdtdKit/PLAN.md` section 5.1) and smoke
  run 2 (`SmokeTests.swift`) knew only cg18's installed file (sha256 819179a2...), so they skipped their install
  checks once cg29 was in place. Both now list the two installs, cg18's file and cg29's (sha256 0d81372e..., UUID
  40BC8CFF, sameBuild cg29), and check the one that is installed; the number of tests is unchanged. At 11:34-11:36,
  on a loaded Mac, 149 tests in 20 suites passed (135 run, the 14 smoke tests skipped) and then the 14 smoke runs
  passed (95 s); with cg29's row naming cg18 instead, the library test fails, as it should.
- The name. `gh search repos fdtdkit` and `gh search repos emskit` returned no repository, PyPI has no package
  `fdtdkit` (https://pypi.org/pypi/fdtdkit/json gives 404), and two web searches found no project named fdtdKit; the
  nearest names are FDTDX (ymahlau/fdtdx) and fdtd (flaport/fdtd). `PUBLISH.md` section 0 had said that this check
  was not made; it now records it. Keeping the name stays the author's decision.
- `README.md`: the status paragraph (cg18 was the installed build from 2026-11-04 to 2026-11-06 and cg29 is since,
  with the checks run from the install); "What is in the box" (the patch row with both installs; the Swift package
  written on 2026-11-05 and 2026-11-06; `ROADMAP.md` with version 2 of the command line planned and 0.1.0 done); the
  command line's status line (the 135 unit tests in 19 suites and the 14 smoke runs, 149 tests in 20 suites in all,
  where it had counted the smoke runs twice); the opening line of "What changed in the engine" (the installed cg29
  has all eighteen items); "Status and licence" (the fork in daily use as cg29; the toolkit runs it unchanged on the CPU
  engine, and the Metal diamond engine is in the installed build but opt-in); and the authorship paragraph (the size
  sweep and its check, the rename, the command line, the install and this pass).
- `BUILD.md`: the introduction and its list of what the fork is built on (the two installs, and how cg29 was put in
  place), section 4 (which build was installed when), section 5 (the installed library reports cg29's version
  string; the libraries now in the cg19 and cg20 snapshot folders report v0.37.0-25-g315acee and v0.37.0-26-gcd80d8c,
  not the strings their tables print), section 7 (the installed build has the Metal diamond engine since 2026-11-06;
  the toolkit does not select it) and section 9 (the checks from the install).
- `ROADMAP.md`: Phase 5's command-line row is now version 2 (`install` and `rollback`, the `accept` bundle,
  `snapshot`, the cylinder multigrid check, multi-Mac runs; `Docs/fdtdKit/PLAN.md`, sections 14 and 18), and "Done"
  has a row for `emskit fdtd` 0.1.0. `patches/README.md`: the openEMS row gives both installs.
- `PUBLISH.md`: section 0 (the models of the `fdtdkit` commits, of the install and of this pass; the name check; the
  kit branches as they stood on 2026-11-06, with momKit's work branch `m6a-wip` and the agent worktree removed that
  day; the author's decision to merge `fdtdkit` into `main` once the code review of it has started; the
  licence item points to the paper's licence paragraph), section 1 (fork hashes also in `Docs/fdtdKit/PLAN.md`,
  `scripts/gpu_crossover/header.txt` and `results/gpu_crossover_cg29_2026-11-05.txt`; the version strings of the
  tables against those of the libraries now in the cg19 and cg20 snapshot folders; the strings in the plan and the
  tests stay), section 2 (what this changelog records, up to 2026-11-06; the checks from the install under "Full
  check"; `ROADMAP.md`; "Figures after the rename" done in 4829e22, and the PDF's name check now also allows the
  lines that name `emskit fdtd`) and section 3 (the branches that `git push --all` would add; this repository's own
  commit hashes, with a `git grep` that lists them and a `paste` map for Way 1).
- `Docs/fdtdKit/PLAN.md`: section 1 (the protected folders in the scope; the size as built at 2618180, 11,071 lines
  of Swift in 29 files, 545 lines of Python and 4,927 lines of tests with 1,518 lines of fixtures, against the
  estimate of 2026-11-05); section 2 (both phases committed together as 60fd4a3; the launcher's row, 545 lines);
  section 3 (F7 and F20: the version strings of the cg19 and cg20 snapshot libraries, and the installed libopenEMS
  is cg29's build since 2026-11-06, in other bytes; the note on what was not established: `bin/openEMS` is still
  cg18's); sections 4.1 and 4.2 (the protected-folder rule in the rows of `--runs`, `--output` and `--overwrite` and
  under the commands table); 5.1 (the installed rows before and after 2026-11-06, and the tests that skip since
  then); 12 (the five suites the table lacked: LauncherSourceTests, EchoFilterTests, VerdictTests, GpuFallbackTests
  and NoInstallTests; 19 unit suites with 135 tests, and 20 suites with 149 tests with SmokeTests; smoke run 2); 13
  (the kit branches and the merge decision); 14 (how cg29 was installed without `cmake --install`); 16 (an entry for
  the install and its checks); and 18 (items 17 and 18 done).
- The paper: the date line (work of 2026-10-28 to 2026-11-06, draft of 2026-11-06); the abstract (cg18 was the
  installed build until cg29 replaced it; the command line among what is published); `sec_intro.tex`,
  `sec_method.tex` and `sec_results.tex` (cg18 installed from 2026-11-04 to 2026-11-06 and cg29 since, in the text
  and two captions; in `sec_method.tex` a paragraph on the install of cg29 and the checks from it, without their
  speeds; in `sec_results.tex` the toolkit's runs on cg29); `sec_engine.tex` and `sec_positioning.tex` (after an
  install over another build the Python modules must be rebuilt for SAR; FDTD runs and nf2ff are not affected, so
  existing scripts gain the speed-up without a rebuild); `sec_closing.tex` (the repository list with the two
  installs, the GPU-against-CPU results file and scripts and an item for the command line; six figure scripts read
  `results/`; the licence of the Swift package is not decided; the Disclosure over ten days, 2026-10-28 to
  2026-11-06, with the size sweep and its check, the rename, the command line, the install and this pass; the sweep
  and the checks of 2026-11-06 under "Where the numbers come from"). The PDF was rebuilt (51 pages).
- Three dated entries below stay as written but are imprecise. The two 2026-11-06 entries count the 14 smoke tests
  among their "unit tests": their 149 and 142 tests in 20 suites are 135 and 128 unit tests in 19 suites plus the 14
  smoke tests of the suite `SmokeTests`, which run only with `EMSKIT_FDTD_SMOKE=1`. The 2026-11-05 entry on the name
  says "Not redrawn yet", but its own commit, 4829e22, redrew the four figures and rebuilt the PDF.
- Left for the author, unchanged: the owner items of `PUBLISH.md` section 0 (the public identity and the paper's
  author line, the repository URLs, who wrote the additions of 2026-11-03, the paper's final date and its draft
  wording, `patches/rfsim/`, the licence of the Swift package, how `main` goes public, keeping the name).

## 2026-11-06: fdtdKit command line, the open items after commit 60fd4a3 (branch `fdtdkit`)

The small items the build agents had left open, on top of commit 60fd4a3; no fork code, patch, tool or result changed.
Claude Opus 5.5 (Claude Code), at the author's request ("commit and continue"), in a workflow of the main session
(07:15 to 09:15; Claude Opus 5.5 agents): one agent closed the items, two read-only reviewers checked the change, one
agent fixed what they found (12 of their 13 findings, in the code and the plan; the 13th was this README's test count),
and one agent ran the builds, the tests and the acceptance runs on the final tree. The Mac was heavily loaded (another
session's DFT jobs, `pw.x`, and from about 08:50 another session's GPU work: the other processes at up to 9.6 cores and
72 % of the GPU), so the speeds the runs printed say nothing about the engines.
- e2e's summary prints run-time parts under 0.1 s in ms (`build 8.1 ms` where it printed `build 0.0 s`); the envelope
  keeps the exact seconds.
- A library or snapshot name that starts with `-` is refused at plan time (exit 2; bench.py's argparse would read it as
  an option), with a hint that names the same folder by its path.
- The account's home folder, which the protected folders also use, is looked up with a buffer that grows when the
  password database needs more than the first one.
- `ab` plans both of its sampler checks (`bench/usage.py`, before and after the run) in a dry run and in a refused run,
  as a run does them.
- `rfsim_not_found` says what was looked at and why it was not accepted.
- `info` reads and hashes each snapshot library once instead of twice (87 reads instead of 171; the second pass cost
  about 0.3 s): 0.5 to 0.8 s of wall time with the other processes at 2.5 to 4.5 cores.
- `Docs/fdtdKit/PLAN.md`: info's warnings, the knob counts and the library matches as `info` prints them now, what a
  stop can and cannot interrupt in a script-mode command (not a C call outside `FDTD.Run`), how the answer of `lsof` and
  an interrupted run with a passed verdict are read, the load sampler's undercount of the command line's own GPU use for
  short child runs, and the log entries for 60fd4a3 and for this round.
- Tests: 149 unit tests in 20 suites (7 new, each failing without its fix in mutation runs) and the 14 smoke runs pass.
  Acceptance on the final tree, 09:02 to 09:10: `check cg29 --tag cliaccept --lite` gave `ALL IDENTICAL (6 models)`,
  `diamond-check cg29` 72 of 72 identical, and `e2e gcpw --lib cg29` finished at 34300 steps; the six
  `results/*_cliaccept.txt` tables were deleted afterwards. README's status line now gives the 149 tests.

## 2026-11-06: fdtdKit command line 0.1.0 built, tested and acceptance-run (branch `fdtdkit`)

The command line of the 2026-11-05 entry below, now compiled, tested on the Mac and run through both phases' acceptance
runs, with one rule added (the protected folders); no fork code, patch, tool or result changed. Claude Opus 5.5 (Claude
Code), at the author's request, in two workflows of the main session (00:04 to 03:44 and 03:49 to 05:53; Claude Opus
5.5 agents): the ten commands written and compiled one after another, the unit and smoke tests, the smoke runs, the
acceptance runs beside three read-only reviewers, a skeptic who checked their findings, and the fixes; then the
protected-folder check, two more read-only reviewers and their fixes. The Mac was shared with other sessions: during
the runs the other processes (most of the time another session's DFT jobs, `pw.x`) used 0.3 to 4.9 cores, so the
speeds the runs printed say nothing about the engines; the verdicts (bit identity, a finished run) hold under load.
- Builds: `swift build` and `swift build -c release` with Swift 6.4.2 on macOS 27.0.1 (the package asks for Swift
  tools 6.2 and macOS 26), from an empty build folder without warnings.
- Tests: 142 unit tests in 20 suites (`swift test --filter fdtdKitTests`), among them golden plans for the nine command
  cases, the launcher spawned with the framework Python 3.14.6 against a fake openEMS binding (option injection, the
  three stop paths, process groups, the child's exact environment), the check verdict, and the safety items (no
  install, the protected folders, no echo of a speed without a load, tolerant rows never counted as proof). 14 smoke
  runs against the real tools (`EMSKIT_FDTD_SMOKE=1`, `--filter fdtdKitTests.SmokeTests --no-parallel`), each speed
  with the other processes' load.
- Acceptance (`Docs/fdtdKit/PLAN.md`, section 16, with each run's load), four times, the last at 05:43 to 05:48 with
  the final release build: `emskit fdtd check cg29 --tag cliaccept --lite` gave `ALL IDENTICAL (6 models)` with 18 of
  18 counted rows exact and every engine confirmed by its Create line, against snap/stock identified as stock v0.37.0
  by sha256 (v1a); `diamond-check cg29` gave PASS, 72 of 72 comparisons identical in 9 boxes, and `e2e gcpw --lib
  cg29` finished with the toolkit's probe end at 34300 steps (v1b). The six `results/*_cliaccept.txt` tables were
  deleted after each run.
- Review: three reviewers (process safety, parsing and verdicts, conformance with the plan) reported 9 findings; the
  skeptic confirmed 8 (two duplicates) and rejected one. Fixed, each with a test that fails without the fix: a `--tag`
  that starts with `-` is refused (`tag_invalid`; bench.py's argparse read it as an option); check's FAIL line counts
  as `check_failed` only when every model it names printed a MISMATCH block, otherwise `tool_output_unparsed`; a copied
  backup of a table behind a symbolic link holds the bytes, not a second link; two signals merged into one event count
  as two; `gpu_fallback` is also reported by bench, ab, check and validate, and also for the Metal kernel's compilation
  and pipeline failures. The rejected finding (an output the user names inside the install, which the plan allowed:
  `info --output` on the installed library with `--overwrite` would have renamed the library) was taken up anyway, by
  the main session's decision (next item).
- Protected folders: every location a command would write, create or rename (`--output`, `--record`, `--out-dir`,
  `--results`, `--runs`, the `--tag` tables, the planned backups, the run folder, `run`'s `OPENEMS_EXPORT_*` folders;
  defaults included) is checked before anything is created, renamed or spawned, in a dry run too, against the
  installed prefix (the one the Python probe finds, and `~/opt/openEMS`) and the snapshot folder (`--snaps`,
  `$OPENEMS_BENCH_SNAPS`, `~/opt/openEMS-dev/snap`), by file identity, so links, `..` and letter case do not hide
  them. A location inside one, one renamed as a whole while it holds one, and a file a tool rewrites in place that is
  a hard link of a file in one are refused with the new issue `protected_path` (exit 2; no option overrides it;
  `PLAN.md` section 10.2). With the check undone, 5 of its first 6 tests failed, and 8 of their 20 refused command
  lines changed `~/opt` on the tests' fake Mac. Two read-only reviewers of the check reported 8 findings, all of which
  held (one in the documentation only); the fixes protect the default prefix and snapshot folder also when the Python
  probe fails or `$HOME` points elsewhere, refuse hard links, take check's results folder beside the real
  `bench/check.sh`, look at `--output` once more before it is written, and make e2e's plan the same with and without
  `--output`. In 14 mutation runs, each undoing one fix or a part of one, the test written for it failed.
- In the tests, the rule that the public text names no person compares SHA-256 hashes, so the rule names no one
  itself.
- `README.md` (the status of the command line, the smoke runs, the protected folders among its guarantees, exit code
  2), the command line's row in `ROADMAP.md` and the status line of `Docs/fdtdKit/PLAN.md` now say it is built and
  tested.

## 2026-11-05: GPU against CPU by grid size (snapshot cg29; branch `fdtdkit`)

A measurement with its results file, scripts, a figure and text in the paper; no fork code, patch or tool changed. The
author asked at how many cells the GPU engine becomes faster than the CPU engine, and why it is slower below that.
Claude Opus 5.5 (Claude Code) ran the sweep in the main session, 10:24 to 16:42, on a Mac shared with other sessions
(the other processes at 0.5 to 1.3 cores and 1 to 5 % of the GPU in the median of a point).
- `results/gpu_crossover_cg29_2026-11-05.txt`: three bench models (the patch antenna, the notch filter, the GCPW line)
  at 25 points (10, 6 and 9 mesh scales) from 0.10 to 7.9 M cells, each point in 4 paired, interleaved rounds of the multithreaded engine at
  8 and 4 threads and of `metal-diamond` with and without `OPENEMS_DIAMOND_TIMING=1`. The GPU is ahead in every round
  from 1.7 M cells on the notch filter, 2.4 M on the GCPW line and 2.9 M on the patch antenna, by 1.25 to 1.52x from
  3.1 M cells on; the medians cross for the last time at about 0.66, 1.45 and 1.91 M cells. Below that the engines are within 0.89 to
  1.23x of each other and the side depends on the model and the session (the patch tutorial: 1.107x in the sweep, 0.91
  to 0.97x in a later session at 10 500 and 36 500 steps). Why the GPU's lead narrows on small grids, or turns into a loss: it
  waits while the CPU records the probes and evaluates the dumps between short calls and while each call's command
  buffers start and finish (busy 73 to 82 % of the loop on the patch tutorial,
  whose nf2ff dumps end a call every 31 steps, and 97 to 99 % on the other two models), its own rate is lower (1959 MC/s
  over busy time on the notch tutorial against 3239 on notch x3), and the CPU engine is at its fastest at 0.6 to 1.9 M
  cells (2570 to 3003 MC/s, above its DRAM rate). Refined to 3.2 and 5.1 M cells, the GCPW line runs on the GPU
  between patch x5 and notch x3 (2933 and 3028 against 2908 and 3220 MC/s), so its lower rate at 0.24 M cells comes
  mostly from its size. Every CPU run gave the CPU reference's
  probes bit for bit; the GPU's were within 1.7e-6 relative (no FTZ in either), apart from ports whose CPU values were
  still subnormal at one point, which the GPU flushes to zero.
- `scripts/gpu_crossover/` (`sweep.sh`, `tiles.py`, `cells.py`, `analyze.py`, `mkresult.py`), `paper/figures/fig_crossover.py`
  (Figure fig:crossover), the paragraph "Where the GPU overtakes the CPU" in `paper/sec_gpu.tex` with a sentence in
  "Where the GPU waits" and three of its limits, and the crossover in the abstract, the introduction, the results and
  the closing section, where the explanation of the tutorials' ratios had rested on the cg24 timing alone; `README.md`
  (a paragraph after the speed table, two rows of "What is in the box") and `scripts/README.md`.
- After commit 4829e22, a read-only check of these lines (five checkers and a skeptic, Claude Opus 5.5 agents)
  recomputed the 25 rows from the raw output (all equal) and confirmed 24 wording faults, now fixed: among them, the GPU
  is not "the slower engine on small grids" (it leads on the GCPW line there), 11 points rest on 2 or 3 of the 4
  rounds (a round still loaded after three repeats is left out), the GCPW line's scale coarsens its mesh above 1, the
  refined GCPW line runs between patch x5 and notch x3 (not as fast as both), and the GPU's idle time on the patch
  tutorial includes the start and finish of each call's command buffers. Two script faults are fixed as well:
  `analyze.py` now lists every tiling the tuner chose in the timed runs (two rows had mixed picks), and `tiles.py`
  takes `sweep.sh`'s point format; `header.txt` is now in the repository, and `mkresult.py` reads it from there.

## 2026-11-05: fdtdKit command line 0.1.0 (`emskit fdtd`) and the name fdtdKit (branch `fdtdkit`)

On branch `fdtdkit` (worktree `~/Developer/EMSKit-fdtd`, from `main` at 00e8f7d): documents, the labels of five
figure and table scripts, and the files of a command line that is not built yet; no fork code, patch, tool or result
changed. Claude Opus 5.5 (Claude Code), at the author's request, in a workflow of the main session: Claude Opus 5.5
agents wrote a read-only fact sheet, three designs, a critic's review and a spec (revision 2) of the command line and
a read-only inventory of every occurrence of the old name, then the code and the documents from them. Nothing was
compiled, run or tested in this step, because a GPU-against-CPU benchmark was running on the Mac at the same time.
- The name. This FDTD project (the openEMS fork, the harness and the toolkit knobs) is called fdtdKit in the documents
  and the paper; up to this entry it was called emsKit. The author chose to rename the documents and the paper only:
  the repository and its folder keep the name emsKit, and EMSKit is the name of the family of four kits (fdtdKit,
  femKit, momKit, sbrKit). Renamed line by line from the inventory: `README.md` (the title, the first paragraph, which
  now also introduces EMSKit and the old name, and the rows of "What is in the box"), `BUILD.md` (the title, "the 27
  fdtdKit patches", the example prefix `$HOME/opt/fdtdKit` and the moved-aside install `$PREFIX.fdtdKit`),
  `PUBLISH.md` (the title, section 2's title, the Way 2 commit message), `ROADMAP.md` (the title),
  `patches/README.md`, `scripts/README.md`, the paper's title and PDF title, `paper/sec_positioning.tex` (the section
  title "Positioning: fdtdKit and other electromagnetic solvers" and the paragraph "Where fdtdKit stands"),
  `paper/sec_results.tex` (captions, and the group header "fdtdKit (cg18)" of Table tab:e2e), `paper/sec_engine.tex`
  (the caption of the allocation-placement figure), `paper/sec_modelling.tex`, `paper/code_notes.md`, the title line of
  `paper/LICENSE-CC-BY-4.0.txt`, the labels and docstrings of `fig_bandwidth.py`, `fig_cache.py`, `fig_runtime.py`
  and `fig_speed.py` (`fig_bandwidth.py` keeps the word "CPU" in its labels, which colours the bars) and the README
  header and note in `paper/figures/tables.py`. New sentences that define the name: `paper/sec_intro.tex`, where the
  fork is introduced, and `paper/sec_closing.tex`, "Reproducibility and artefacts" (EMSKit, its other kits not
  covered, the repository's name).
- Kept as they are: `results/` (records: dated notes, run labels such as the `emskit` label of
  `scripts/others/run_others.sh` with its eleven `*_emskit*.txt` tables, other processes' names in the busy columns),
  the patches (the fork's commit messages and source lines such as "Copyright (C) 2026 the emsKit author": changing
  them would change tree 90f8c01 and the hashes that the documents cite), the rfsim diff, the dated entries of this
  file (they quote the paper's old wording, such as "Where emsKit stands", now "Where fdtdKit stands"),
  `NEXT_WORK_PROMPT.md`, `CLAUDE.md`, the repository's name and paths (`$EMSKIT`, `~/Developer/emsKit`, the
  repository URL, `gh repo create emsKit`), line 7 of `paper/LICENSE-CC-BY-4.0.txt` ("the emsKit repository"), and
  the names in `bench/`, `scripts/` and `swift_engine/` (temporary folders such as `/tmp/emskit_validation`, GPL
  modification notices, docstrings), which the scripts' READMEs quote and the command line wraps unchanged. The
  paper's files keep their names, `paper/emskit.tex` and `paper/emskit.pdf` (an owner item in `PUBLISH.md`, section
  0).
- Not redrawn yet: the four figure scripts and LaTeX were not run, so `fig_bandwidth`, `fig_cache`, `fig_runtime` and
  `fig_speed` (PDF and PNG) and `paper/emskit.pdf` still print emsKit (`PUBLISH.md`, section 2, "Figures after the
  rename"). The README's generated speed table was changed by hand in the same four words as `tables.py` (its header
  "fdtdKit CPU, MC/s (threads)" and "fdtdKit GPU, MC/s", "fdtdKit's multithreaded engine", "stock and fdtdKit CPU"),
  checked against the script's string literals without running it, so the next run of `tables.py` changes nothing
  there; `tab_current.tex` and `tab_e2e_cg29.tex` contain no name.
- `PUBLISH.md` also: the four kit branches and their worktrees (sections 0 and 3; section 3 had said that each kit
  adds a Swift package of its own, while they share one, EMSKit, with one `emskit` command), how `fdtdkit` and the
  other kit branches meet Way 1's rewrite of `main` (merged before it or rebased onto it afterwards, the author's
  choice), the licence of the Swift code (open), and the steps that redraw the figures.
- The command line, version 0.1.0, not built or tested yet. `emskit fdtd` is fdtdKit's subcommand of the family's
  `emskit` tool: ten commands (`info`, `load`, `bench`, `ab`, `check`, `validate`, `debye-check`, `diamond-check`,
  `e2e`, `run`) that run the repository's tools unchanged (`bench/bench.py`, `bench/abtest.py`, `bench/check.sh`, the
  validation suite, `scripts/checks/debye_check.sh` and `diamond_check.sh`, `scripts/e2e/run_one.py`, or any openEMS
  script) and print one JSON document per call. It builds every child's environment explicitly (inherited
  `OPENEMS_*`, `DYLD_*`, most `PYTHON*` and `Malloc*` variables are removed and listed), names libraries by sha256 and
  Mach-O build UUID, takes its verdicts from the tools' printed lines, prints every speed and run time with the other
  processes' CPU and GPU use during it and withholds a figure without a valid reading, refuses to overwrite, refuses
  timed runs while another simulation has an openEMS library open, stops runs through openEMS's abort flag, and
  installs nothing; `check` counts as the CPU acceptance only against the stock v0.37.0 build of all three libraries.
  Its files: `Package.swift` (the EMSKit package with fdtdKit's targets only), `Sources/fdtdKit` (with the Python
  launcher `Python/fdtdkit_run.py`), `Sources/emskit-cli`, `Tests/fdtdKitTests` and `Docs/fdtdKit/PLAN.md` (the plan:
  the phases v1a and v1b with their acceptance runs, the facts it rests on, the open questions, the log); in
  `README.md` the section "Command line" and two rows of "What is in the box"; `ROADMAP.md`'s Phase 5 item points to
  the plan. The build of each phase adds its acceptance runs, with their load and run times, to the plan's log.

## 2026-11-05: documentation pass (snapshot cg29 and the Metal diamond engine in the documents)

Documents, two new results files, a table script and one option of the harness; three results notes corrected, one of
them also completed; no fork code and no patch changed. Claude Opus 5.5 (Claude Code), at the author's request (step 5
of `NEXT_WORK_PROMPT.md`), in workflows of the main session: Claude Opus 5.5 agents first wrote read-only fact sheets
(every statement with its file and line), then edited the documents in a first wave, a sweep and a second wave against
those sheets, `results/` and one sheet of names and settled facts, which the main session wrote and in which it
settled the conflicts the agents reported. The measurements ran in the main session: the speed table from 03:51, the
end-to-end runs from 06:13, the last three rows of section 4 of `results/cpu_items_cg29_2026-11-05.txt` from 07:05 and
its section 5 from 07:19 (the cg29 entry below).
- Rules of the pass: cg29 (patches 0001-0027) is the current fork, and cg18 (0001-0006), the build installed on the
  author's Mac, is no longer called "the final build"; measured history keeps its snapshot (the 3.2-6.9x factors stay
  cg14's); the toolkit's defaults since 2026-11-04 (0.05 mm, hold 0.5) are told apart from those of the published
  `patches/rfsim/` (0.02 mm, hold 1), and an SMA figure names its mesh (1.071 M or 0.871 M cells); a "not tried" or
  "not measured" that the work of 2026-11-04/05 answered now gives the measurement; another engine's differences from
  stock are float rounding and subnormal flushing; the credits read luikore (openEMS pull request #228: the diamond
  tile schedule; no code of it is used), Noriaki Takashima (nori-proto, pull request #244), Roel Budé
  (unsettledroell404, pull request #245) and MrHighVoltage (Discussion #492).
- New `results/speed_cg29_2026-11-05.txt`, the speed table of the documents: stock v0.37.0 at 4, 2 and 8 threads,
  cg29's CPU engine at 4 and 8 threads and with the automatic count, and the Metal diamond engine in turn in every
  round, one paired interleaved run of 4 rounds per model (`bench/abtest.py`; the table is assembled from its raw
  output, which follows it in the file), the SMA launch on the 1.071 M-cell mesh (`RFSIM_MIN_CELL=0.02`). Every CPU
  run is identical to stock at 4 threads; the GPU's port probes differ from stock's by at most 9.4e-7 relative
  (identical with `OPENEMS_FTZ=1` on the CPU, `results/*_cg29gpu.txt`). Its numbers are in the cg29 entry below.
- New `results/rfsim_e2e_cg29_2026-11-05.txt`: the two boards end to end through the toolkit
  (`scripts/e2e/run_one.py` with `E2E_ENGINE`), cg29's CPU engine with the automatic thread count against the Metal
  diamond engine, in interleaved rounds (3 with the toolkit's defaults since 2026-11-04, 2 with the probe end off).
  `FDTD.Run` wall time, CPU to GPU: GCPW line 5.6 to 4.1 s (1.37x, the median of the per-round ratios) and in the full
  run 13.1 to 11.2 s (1.17x); SMA launch (0.871 M cells) 28.9 to 23.6 s (1.22x) and 68.1 to 58.5 s (1.17x). Both
  engines stop at the same step in every round; the GPU's results differ from the CPU's by at most 7.3e-3 dB in S11
  (where |S11| > -40 dB), 2.0e-4 dB in S21 and 5.4e-3 ohm in Z0 at the reference frequency, as the GPU flushes
  subnormal numbers. The other processes used a median of 1.0-1.6 cores per row, and 5 of the 20 runs kept stayed
  above the load limit through three redos (at most 4.4 cores); the rounds in which both runs were clean give
  1.08-1.27x. With that load the file's CPU times are no comparison with cg18's runs of 2026-11-03, made on a quiet
  Mac (cg18 against cg29: the paired ratios in the cg29 entry). The scripts that drove these runs and wrote the
  file's tables are not published (the file names them).
- Both files waited for a quiet Mac: each round (`bench/abtest.py --quiet 150 --redo 3`) or, end to end, each run
  (`bench.wait_quiet`) starts once the other processes use at most 150 % CPU and 10 % GPU, or after 15 minutes of
  waiting, and a round or run during which they rose above that is run again, three times at most; the discarded
  attempts stay in the files as `redo` lines, and `bench/usage.py` logs the others' CPU and GPU use during every run.
  New in `bench/abtest.py`: `--run-redo N` (with `--quiet`, in place of `--redo`), in which every run waits for the
  quiet Mac itself and only a loaded run is repeated, so one loaded run does not cost the whole round; the SMA launch
  of the speed table, left with fewer than three clean rounds, was run again this way.
- New `paper/figures/tables.py` writes the tables of cg29 from those two files, so that no number is typed twice:
  `paper/figures/tab_current.tex` (stock, cg29's CPU engine and the Metal diamond engine on the six models),
  `paper/figures/tab_e2e_cg29.tex` (the end-to-end runs, beside the runs of 2026-11-03 with the same settings and
  steps) and the speed table of `README.md` between its two marker lines. Every value is one of the files' medians or
  median paired ratios as the file rounds it; only the labels, the README's model descriptions and the earlier runs'
  times (from `results/rfsim_e2e_2026-11-03.txt`) are written in the script. It reads text files only and writes
  nothing if a CPU run of the speed file is not identical to stock or the two engines of an end-to-end run stop at
  different steps.
  The three blocks are not edited by hand (`PUBLISH.md`, section 2).
- Results notes corrected. `results/cpu_items_cg29_2026-11-05.txt`, section 2: the 2026-10-28 kernel `kb_tb.cpp` ran
  the stock arithmetic with its invariants hoisted and the 12 coefficient tables, also as a fused sweep on one
  independent sub-grid per thread (the note had called it the stock loops with more bytes per cell and given a cache
  explanation as fact; why the fork's loops gain less from two time steps per sweep was not examined); section 3:
  `bench/check.sh` runs its stock reference at its own thread count per model (8 for patch x5 and notch x3, 2 for the
  patch tutorial, 4 for the notch tutorial and the two boards), not at 4 threads for all, and the speeds of its
  tables are the faster of two unpaired runs (the note said single runs); section 1: the operator index per z-vector
  (09c170c) ran 5 rounds with the other processes on 0.3-1.4 cores (the range of the configurations' medians in the
  raw table; the note said 0.4-1.4, the commit message 0.4-1.7), and a line under the table now says how its load
  ranges are taken. `results/diamond_engine_cg24_cg27_2026-11-04.txt`, section 8: in the cg23 sweep the default
  tiling ran 8-9 % below the best setting on the two boards; the note's 11-13 % is the paired gain of the best
  tilings found, 1.11x on the GCPW line and 1.13x on the SMA launch (the cg24-cg27 entry below is corrected the
  same way).
  `results/diamond_engine_cg28_tuner_2026-11-04.txt`: in the cg23 sweep (the faster of two runs per setting, not
  paired) four models ran best with one of the tuner's four tilings and the SMA launch and the patch tutorial with a
  K=2 tiling (0.3 % and 1.2 % faster), and K=2 with 6:4 tiles, the SMA's best in cg24's paired runs (x1.132), is not
  among the four and was not timed after cg24 (the note said every model ran best with one of the four). The kb_tb
  and tuner corrections are marked "Corrected 2026-11-05" in their files, and the cg28 and cg29 entries below were
  corrected the same way. Earlier that day, before the results of 2026-11-04/05 were committed,
  `results/fused_sweep_k1_2026-11-04.txt` got the note that its "upstream gpu" is the Metal engine of the fork's base
  (7bb294f), not the engine that master merged.
- Master's GPU engine on the notch tutorial with PEC in place of Mur (0.270 M cells), in `ROADMAP.md`,
  `paper/sec_positioning.tex` and `paper/sec_beyond.tex`: 2374 MC/s against 2053 for cg18 at 4 threads is the faster
  of two runs (1.82 s; the other ran 1452 MC/s, about 3 s), with the other processes at 43 % of a core in the second
  before it (`results/others_2026-11-04/notch_s1_n16000_master-nomur.txt`). It is above the ~2000 MC/s DRAM bound of
  an unfused 74 B/cell sweep; whether master's kernels fuse or the small model stays in the GPU's caches was not
  examined, and the bound claim stays with the base's unfused engine. The first wording in `ROADMAP.md` had two runs
  of under 2 s and the others on 0.4-0.9 cores.
- `BUILD.md`: the trees (0001-0006 give f67bc0f, that of cg18; the 27 patches or the cumulative diff give 90f8c01,
  that of cg29) and the three groups of patches (section 4: `0*.patch`, or `000[1-6]-*.patch` for cg18);
  `ENABLE_METAL` and the version strings that the libraries print (section 5); section 7: the defaults and knobs of
  cg29 and of the Metal diamond engine, a paragraph on that engine (opt-in, not in the installed cg18, what runs on
  the GPU, identity with the FTZ CPU engine) and the toolkit's defaults since 4a7e20e beside those of
  `patches/rfsim/`; section 8: the cg29 run-mode matrix, the engine's mesh limits, the `TS_LOCAL` extensions; section
  9: `check.sh`'s options and tolerant configurations, `scripts/checks/diamond_check.sh` and the checks of cg29.
- `patches/README.md`: 0001-0027 in three groups (0001-0006 cg18, installed; 0007-0016 the Metal diamond engine,
  cg19-cg28, opt-in on macOS with `ENABLE_METAL`; 0017-0027 the CPU items of cg29), the cumulative diff (66 files,
  +6178/-256; both routes give tree 90f8c01) and the SMA mesh of the speed table of 2026-11-05 (1.071 M cells).
- `bench/validation/README.md` and the docstring of `case_dispersive_slab.py`: what the fork's engine names run on
  stock and on a build without Metal, the slab tolerance (`metal-diamond` held to 0 unless `OPENEMS_FTZ` is set) and
  the runs of the suite on the author's Mac (stock, cg18, cg29, and the Metal diamond engine on cg23 and cg27; 15 of
  15 each).
- `scripts/README.md`: `checks/diamond_check.sh` (nine boxes against the FTZ CPU engine, 72 comparisons),
  `checks/diamond_box.py` and `checks/diamond_compare.py`; `E2E_ENGINE` of `e2e/run_one.py`; the variables of
  `others/run_others.sh`.
- `PUBLISH.md`: the models and dates through 2026-11-05 and the toolkit's defaults against `patches/rfsim/0003`, an
  owner decision (section 0); the rewrite of the 27 commits and the fork hashes to replace (section 1); the full check
  of cg29, the generated tables and the open notes (section 2); the state of emsKit's own repository and two untried
  ways to publish it (section 3); the tarball with the generated tables (section 4); the upstream hold of Discussion
  #495 (section 5).
- `ROADMAP.md`: both bit-identity references in the acceptance rule; Phase 0 with patches 0001-0027 and the hold on
  speed pull requests; the validation cases still missing; a Phase 4 of the Metal engine's open items (the second
  review's CPU estimates it held are measured); a command-line front end (Phase 5, unnamed); a "Done" table for the
  work of 2026-11-04/05 with the speed and end-to-end figures of cg29; "Not planned" with the GPU measurements (the
  base's engine, master's merged engine, the K=1 sweep) and the corrected kb_tb wording.
- The paper (`paper/`): new `sec_gpu.tex`, "A diamond-blocked Metal engine" (design, what runs on the GPU per
  snapshot, bit identity with the FTZ CPU engine, the speed of cg28 and of K=1, limits; luikore's schedule
  credited); `sec_engine.tex`, a subsection on the cg29 CPU items with their A/B ratios and credits, and the older
  text dated "up to cg28" or "since cg29"; `sec_closing.tex`, the second review's table with the outcomes measured on
  2026-11-05 beside its estimates, the dropped CPU and GPU items under "What did not work", the K=1 result in the
  discussion, the reproducibility list and the Disclosure (2026-10-28 to 2026-11-05, the models per period);
  `sec_beyond.tex`, the ceiling subsection limited to the engines measured up to cg14, with master's engine and the
  Swift prototype's diamond mode added and its "not tried" sentences replaced; `sec_positioning.tex`, the
  measurements of master and pull request #228 on the M5 and the snapshot of every factor; `sec_method.tex` and
  `sec_modelling.tex`, both SMA meshes, the load logging, the GPU's identity rule and the toolkit's defaults since
  4a7e20e beside the published patches'; `code_notes.md`, a note that it covers the patches up to 0006 (the later
  ones: their commit messages, this file and the paper's sections). The phrase "the final build" was replaced by
  "cg18" throughout the text.
- Second wave, by its briefs: `README.md` (the generated speed table, the end-to-end paragraphs, the patches and
  status text for 0001-0027), `paper/emskit.tex` (the abstract with cg29 and the Metal engine, `\date`, `sec_gpu.tex`
  input after `sec_beyond.tex`), `paper/sec_intro.tex`, `paper/sec_results.tex` (the two generated tables), the check
  markers resolved where their measurements exist, this entry, `ROADMAP.md` and `PUBLISH.md`; the PDF is rebuilt at
  the end of the pass.
- Measured at the end of the pass, 07:19-09:17: section 5 of `results/cpu_items_cg29_2026-11-05.txt`, upstream's
  benchmark cases on cg18, cg28 and cg29 in paired interleaved rounds that waited for a quiet Mac (the other
  processes on a median of 0.4-1.4 cores per row), every run identical across the three builds (180 runs). cg29 against cg18: 1.11-1.36x on the ideal box, 1.74-2.18x on the
  pml and inhomogeneous cases and 4.25-7.40x on the dispersive case (cg18 runs them all on the unfused plan); the
  ideal case of 8 M cells at 8 threads and with the automatic count ran under load (3 of 4 rounds) and is marked so.

## 2026-11-05: CPU engine: the second review's items and the other forks' ideas (snapshot cg29)

Code by Claude Opus 5.5 (Claude Code), at the author's request. Eleven commits on `speed-m5-gpu` after cg28
(09c170c to 1620939), one per topic, each bit-identical to stock v0.37.0. Measurements:
`results/cpu_items_cg29_2026-11-05.txt` (every A/B with the other processes' load, the dropped items with their numbers);
the full check of the snapshot in `results/*_cg29.txt` and `results/validation_cg29_*`; the preliminary check of an
earlier build of the same topics is kept as `*_cg29pre.*`.
- Operator index per z-vector instead of per cell (`OPENEMS_OP_INDEX_PER_CELL=1` keeps the old array): about 3 B per
  cell less memory, and on meshes of up to 42 z lines 3 B per cell less to stream; patch x5 x1.12 at 4 threads and
  x1.10 at 8, notch x3 x1.04 / x1.05.
- Conducting sheets: the ADE orders of a position back to back, four positions per f4vector (`OPENEMS_ADE_MERGED=0`
  off; second review item 2): GCPW line x1.041 at 4 threads, x1.031 at 8. A uniqueness guard (every position once)
  follows the strict-order check of upstream PR #245 by Roel Budé.
- UPML boxes that are not full-z slabs: the scalar SSE path four y-rows at a time (`OPENEMS_PML_YVEC=0` off; item 1):
  SMA launch x1.18 at 1 thread, x1.13 at 4 and 8.
- UPML operator coefficients on the setup threads, from upstream PR #244 by Noriaki Takashima (its UPML part and
  `RunJobsInThreads`, with the operator's setup thread count): the SMA's UPML build 0.086 -> 0.022 s.
- The steady-state detection (every sinusoidal source) and Debye materials have line hooks, so upstream's benchmark
  cases (`benchmark/cases.py`) run on the fused sweep: pml x1.36 at 4 threads, inhomogeneous x1.29 / x1.34 (4 / 8),
  dispersive x6.5 / x10.0 (the unfused plan ran the Debye hooks on one thread).
- Geometry coefficient tables (item 9 in another form): when the packed tables would exceed 4 MiB, an operator's vi
  and iv terms (2 x 48 B) and two 16-bit indices into tables of the distinct vv and ii triplets, 100 B per operator
  (plus 48 B per distinct triplet) instead of 192 (`OPENEMS_COEF=packed|geom` chooses): SMA launch x1.067 at 8
  threads, x1.033 with the automatic count. The split layout of the diamond engine lost on the CPU (x0.93-x1.02) and
  was dropped.
- `OPENEMS_FUSED_STAT=1` prints the time split of the fused sweep per thread (sweep, waits, the line before the slab).
- Neighbour flags instead of the two barriers per timestep of the fused sweep (item 5; `OPENEMS_FLAGS=0` keeps the
  barriers): a thread waits for its two neighbours only, so threads run up to their distance in timesteps apart; the
  extensions declare `TS_LOCAL` and read their own thread's timestep. Lumped RLC takes its three time slots from the
  timestep (the idea MrHighVoltage proposed in upstream Discussion #492). x1.015-x1.055 at 4 threads, x1.07-x1.29 at
  8. The steady-state detection keeps three periods of records and runs on the flags too.
- Flag waits do not spin when the threads outnumber the performance cores (`OPENEMS_FLAGS_SPIN_US` sets the spin for
  any count): x1.05-x1.12 at 8 threads and with the automatic count on the GCPW line and the notch tutorial, 4 threads
  unchanged.
- Measured and dropped (numbers in the results file): the thread-count cache (item 3), the per-thread QoS P/E split, a
  longer barrier spin and faster slab balancing (item 4), Mur z-face vectors (item 6), per-line hook masks (item 7),
  the split coefficient tables (item 9's first form), a 50 ms tuning window, CPU temporal blocking of 2-4 timesteps
  per sweep (at most +6 % even as a standalone upper bound without halos or hooks, against +10-14 % for the 2026-10-28
  kernel, the stock arithmetic with the 12 coefficient tables). Not built: spin barriers at the start and stop of each
  processing interval (item 10: two wake-ups per 50-300 ms call on the boards, under 0.1 %). Already in the fork:
  MrHighVoltage's thread tuner on real timesteps (since cg8) and PR #231 (the hook plan of step 2, the UPML row paths
  of cg11-cg14). Skipped: item 8 (the Mur dispatch of the base's Metal engine; the diamond engine replaces it).
- Identity of cg29: `bench/check.sh` on the six models (stock at check.sh's thread count per model, 2 to 8, against
  cg29 at 1, 4, 8 and 10 threads, the automatic count, the geometry and the packed tables forced, the barriers
  instead of the flags) all identical;
  `scripts/checks/debye_check.sh` PASS; `bench/validation/` 15 of 15 with the multithreaded engine at 4 threads and
  with the fastest engine; the cylindrical multigrid 34 datasets equal to stock; the box checks of sheets, UPML, Mur
  and the steady-state detection identical; a matrix of 45 small models in up to 11 run modes identical (461
  comparisons) except one model whose energy end criterion stops at step 255 instead of the step limit, because the
  base branch checks the criterion every Nyquist period in its first minute (upstream eb1c5ee; its 64 probe lines
  equal stock's first 64); `scripts/checks/diamond_check.sh` 72 of 72 and the six models on `metal-diamond` identical
  to the multithreaded engine with `OPENEMS_FTZ=1`.
- Speed against cg18 (patches 0001-0006, the build installed on the author's Mac), median ratios of paired interleaved
  rounds in one session, each model on its default mesh (the SMA launch on 0.871 M cells), other processes on 0.3-0.6
  cores: x1.03-x1.23 at 4 threads, x1.13-x1.44 at 8 threads and x1.13-x1.42 with the automatic count over the six
  models (5 rounds; notch x3 at the automatic count was measured afterwards in quiet rounds, 4 of its 5 rounds kept,
  the fifth loaded). The SMA launch on the 1.071 M-cell mesh, also measured afterwards (4 rounds, others on 0.6-0.7
  cores): x1.37 at 8 threads and x1.38 with the automatic count (`results/cpu_items_cg29_2026-11-05.txt`, section 4).
  The absolute rates of that session differ from the cg18 tables of 2026-11-03, so the paired ratio is the comparison.
- Against stock v0.37.0, with the Metal diamond engine: one paired interleaved run of 4 rounds per model, each round
  started once the other processes used at most 1.5 cores and 10 % of the GPU (each run in the SMA launch's re-run
  with `--run-redo 3`; a median of 0.5-0.8 cores per model during the runs), the SMA launch on the 1.071 M-cell mesh
  (`results/speed_cg29_2026-11-05.txt`, from which `paper/figures/tables.py` writes the paper's table and the
  README's). cg29's CPU engine at its best setting, 8 threads on all six models, 1808-2177 MC/s, 1.95x (patch x5) to
  6.89x (patch tutorial) stock at its best of 2, 4 and 8 threads; the Metal diamond engine 1729-3193 MC/s, 2.87x
  (patch x5) to 7.40x (GCPW line). GPU against the CPU engine's best: 1.47x on patch x5, 1.46x on notch x3, 1.17x on
  the GCPW line, 1.00x on the SMA launch, 0.97x on the notch tutorial and 0.93x on the patch tutorial (medians of the
  per-round ratios).
- `patches/openems/` holds the fork as 27 `git am` patches (0001-0027) and a regenerated cumulative diff; both give
  the tree of the branch head (90f8c01) on 7bb294f. 0001-0006 differ from the earlier files only in their subject
  numbering.
- `bench/abtest.py --quiet PCT` waits before each round until the other processes use at most PCT % CPU and 10 % GPU;
  with `--redo N` a round in which a run saw them above that is run again (N times at most) and the discarded runs
  are kept in the output as `# redo` lines.

## 2026-11-04: a fused, unblocked Metal sweep measured (K=1 of the diamond engine, snapshot cg27)

Measurement only; no code change. Claude Opus 5.5 (Claude Code), at the author's request (step 2 of the 2026-11-04
plan: the open question of `paper/sec_beyond.tex`). `results/fused_sweep_k1_2026-11-04.txt`.
- At K=1 (`OPENEMS_DIAMOND_K=1`) each threadgroup updates the voltages and then the currents of its tile in one pass,
  so each field value is read and written once per time step: the 49 B per cell of the CPU's fused sweep.
- Paired interleaved A/B on the two large models (other processes on 2.5-4 cores): at each model's best tile (notch
  x3 32:16, patch x5 16:8) 1,730-1,840 MC/s, 1.25-1.30x the unfused Metal engine of the fork's base (`--engine=gpu`)
  and 67-75 % of the 2,470-2,590 MC/s bound of the paper (85-90 GB/s at 49 B per cell). Against the default K=4 (8:8
  tiles): 0.57-0.65x with 8:8 and 16:8 tiles (notch x3 also with 32:16), 0.54x for patch x5 with 32:16. K=2 (4:4
  tiles) runs 2,120-2,410 and K=4 2,820-2,990 MC/s: temporal blocking, not the fused sweep alone, passes the bound.
  Every run identical to the multithreaded engine with `OPENEMS_FTZ=1`.

## 2026-11-04: Metal diamond engine: tiling chosen at run time (snapshot cg28)

Code by Claude Opus 5.5 (Claude Code), at the author's request. In `FDTD/metal/engine_metal_diamond.mm`; the CPU engines
are not touched. Measurements: `results/diamond_engine_cg28_tuner_2026-11-04.txt`, the six models against the CPU engine
in `results/*_cg28gpu.txt`.
- The engine builds four tilings (K time steps per block, mountains and valleys M, V cells wide): K=4 8,8 (the old
  default), K=4 12,8, K=3 8,6 and K=3 6,6; in the sweep of cg23 (faster of two runs per setting, not paired) four models ran best with one of them and
  the SMA launch and the patch tutorial with K=2 (0.3 % and 1.2 % faster), and K=2 tile 6:4, the SMA's best in cg24's
  paired runs, is not among them (corrected 2026-11-05: this bullet first said every model ran best with one of the
  four). While tuning, the command buffers take the tilings in turn (half batches, at most two in flight); after 4 timed
  buffers each, the fastest by GPU time per step runs the rest of the simulation and the other tilings' buffers are
  released. Only full batches and whole IterateTS calls are timed and take a turn. The tuning takes 532-623 steps on
  the six benchmark models. `OPENEMS_DIAMOND_TUNE=n` sets the timed buffers per tiling, `0` keeps K=4 8,8;
  `OPENEMS_DIAMOND_K`/`_TILE` fix one tiling as before; verbose > 0 or `OPENEMS_DIAMOND_TIMING=1` print the choice.
- Chosen: SMA launch K=3 8,6, GCPW line and notch x3 K=4 12,8, patch tutorial K=3 6,6, notch tutorial and patch x5
  K=4 8,8 (in each case the best of the four as a fixed tiling in paired runs, and the same choice in every repeat).
- Speed, paired interleaved A/B against cg27 on a quiet Mac (other processes on 0.5-1.3 cores, GPU 2-4 %): SMA launch
  1671 -> 1828 MC/s (x1.094), GCPW line 1896 -> 2113 (x1.114), notch x3 3039 -> 3226 (x1.061), patch tutorial
  1640 -> 1764 (x1.064); the notch tutorial (x0.996) and patch x5 (x0.995) keep the default tiling and pay the tuning
  steps of these short benchmark runs. `OPENEMS_DIAMOND_TUNE=0` equals cg27 (x0.998-x1.003).
- Fixed before the commit: the first version gave the short last command buffer of each IterateTS call a turn without
  timing it, so with some call lengths one tiling was never timed and the tuning did not end.
- Identity: `scripts/checks/diamond_check.sh` 72 of 72 (the 54 of cg27 plus a tuned run that ends its tuning within the
  run and one that changes the tiling every command buffer); all six benchmark models bit-identical to the
  multithreaded engine with `OPENEMS_FTZ=1` (port probes, S11/S21); every A/B run identical.

## 2026-11-04: Metal diamond engine: faster setup, runs, compile-time grid, split coefficients (snapshots cg24-cg27)

Code by Claude Opus 5.5 (Claude Code), at the author's request. All in `FDTD/metal/engine_metal_diamond.mm` (cg24 also
`FDTD/engine_metal_diamond.h` and the `--engine` help text in `openems.cpp`); the CPU engines are not touched.
Measurements: `results/diamond_engine_cg24_cg27_2026-11-04.txt` (paired interleaved A/B on a shared Mac, with the other
processes' CPU and GPU use).
- cg24: the engine's operator derives from `Operator_Multithread`, so material averaging, the PEC search, the time step
  and the coefficients are computed on all cores, as for the multithreaded engine (the same operator). Operator setup
  notch x3 5.55 -> 2.74 s, patch x5 6.48 -> 1.69 s, SMA launch 1.25 -> 0.57 s, GCPW line 0.31 -> 0.13 s.
  `OPENEMS_DIAMOND_TIMING=1` prints the IterateTS calls, command buffers and GPU time; `=2` splits the GPU time by phase.
- cg25: the excitation entries and the dispersive elements (conducting sheets, Drude/Lorentz, Debye) as runs: all entries
  of one field value, or all elements at one cell, in the CPU's order, applied by one thread, so the excitation runs in
  parallel instead of on one thread per tile (the SMA launch has 3851 entries), the two orders of a conducting sheet share
  one pass, steps without work skip the stage and its barrier, and the per-tile offsets are read once per dispatch.
- cg26: the grid dimensions as compile-time constants in the kernel (it is compiled per model already), so the index
  arithmetic divides by constants; the Mur and UPML records are passed by value.
- cg27: split coefficient tables for graded meshes. The SMA launch's graded mesh has an operator for every 3.4 f4vectors
  (64410 operators, 12.4 MB of packed coefficients). luikore's engine (PR #228) deduplicates whole coefficient records
  with a 16-bit index and keeps dense reads above min(65536, positions/4) records, which this mesh exceeds, and its notes
  claim no speed-up for PCB models that hit that fallback. The split layout deduplicates the single coefficient
  f4vectors instead: one table of the distinct ones (SMA: 88485, 1.4 MB) and 2 x 16 B of indices per operator, for one
  more dependent load per cell. It is chosen when the packed coefficients of a 16 x 16 column block exceed 32 KB on
  average (SMA launch, GCPW line, patch tutorial); `OPENEMS_DIAMOND_COEF=packed|split` forces one.
- Speed, paired interleaved A/B against cg24 with other processes on 4-5 cores (MC/s cg24 -> cg27): SMA launch
  1184 -> 1482 (x1.27 [1.22-1.28]), GCPW line 1361 -> 1773 (x1.30 [1.29-1.37]); notch x3 x1.01, patch x5 x0.99 and the
  notch tutorial x0.98 are within the noise, the patch tutorial is CPU-bound at that load. Per snapshot (SMA, GCPW):
  cg25 x1.15, x1.24; cg26 x1.03, x1.02 (and the notch tutorial x1.06, which cg25 had cost 4 %); cg27 x1.04, x1.04. The
  quiet-Mac CPU best of cg18: SMA 1361 (on the 1.071 M-cell mesh of 2026-11-03; these runs have 0.871 M), GCPW 1760.
  All 180 runs of that session identical.
- End to end through the toolkit (`scripts/e2e/run_one.py`, other processes on 3.6-4.7 cores), GPU cg23 -> cg27: GCPW
  12 ns 15.9 -> 13.7 s full, 6.0 -> 5.6 s with probe end; SMA launch 10 ns 79.5 -> 65.5 s full, 34.2 -> 27.6 s with probe
  end; the port data equal the cg23 runs. Validation suite on `metal-diamond` (cg27): 15 of 15
  (`results/validation_cg27_metal.md`).
- Dropped: the UPML update fused into the cell update (no gain: SMA x1.02 [0.93-1.11], notch tutorial x0.95, notch x3
  x0.99); a diagnostic barrier knob that showed the notch tutorial's 3 % loss at cg25 to be code generation (cg26 gets
  it back).
- Identity: `scripts/checks/diamond_check.sh` 54 of 54 on cg25, cg26 and cg27 (cg27 also with the split tables forced);
  all six benchmark models bit-identical to the multithreaded engine with `OPENEMS_FTZ=1` on each snapshot
  (port probes, S11/S21).
- Tile and K sweep: no single setting is best for all six models; K=4 tile 8:8 stays the default (best or within 8 % on
  the four tutorial models, 8-9 % below the best setting on the two boards in the cg23 sweep; in paired runs the best
  tiling found ran 1.11x of the default on the GCPW line, tile 12:8 on cg23, and 1.13x on the SMA launch, K=2 tile 6:4
  on cg24; `OPENEMS_DIAMOND_K`, `OPENEMS_DIAMOND_TILE`).

## 2026-11-04: dispersive materials on the Metal diamond engine (snapshots cg22, cg23)

Code by Claude Opus 5.5 (Claude Code), at the author's request.
- `FDTD/metal/engine_metal_diamond.mm`, cg22: `Engine_Ext_LorentzMaterial` on the GPU (Drude/Lorentz materials and the
  conducting sheets, which are an order-2 Lorentz extension with voltage ADEs); cg23: `Engine_Ext_DebyeMaterial`. Only
  these two classes themselves (typeid), not subclasses. Pre stages that only read the field (Mur, Lorentz, Debye) run
  together before the UPML Pre stage, the Debye Post stage with the Mur Post stage after the UPML Post stage, the
  `field -= ADE` Apply steps in the extension-order Apply list (E step) and before the current excitation (H step).
  The arithmetic follows clang's contraction of the CPU code.
- All six benchmark models now run on the GPU, bit-identical to the multithreaded engine with `OPENEMS_FTZ=1` (port
  probes and S-parameters; `results/*_cg22gpu.txt`, `results/diamond_engine_cg22_cg23_2026-11-04.txt`). The GCPW line
  (conducting sheets): 1465 MC/s vs 761 for the FTZ CPU at the same load (quiet cg18 CPU best 1760).
- `scripts/checks/diamond_check.sh`: conducting sheets on a Mur box, a two-pole Debye block on a Mur box, and one case
  with PML, Mur, lumped RLC, two Drude/Lorentz blocks (eps and mue ADEs, with and without the Lorentz pole), the sheets
  and the Debye block (`--sheet`, `--debye`, `--drude` in `diamond_box.py`); 54 of 54 comparisons identical.
  `bench/check.sh cg22`: CPU paths identical to stock on all six models; `debye_check.sh` passes on cg23.
- Validation suite on `metal-diamond` (cg23): 15 of 15 (`results/validation_cg23_metal.md`); `bench/validation`
  accepts `VALIDATION_ENGINE=metal-diamond`.
- End to end through the toolkit (`scripts/e2e/run_one.py`, new `E2E_ENGINE=metal-diamond`; `results/rfsim_e2e_gpu_2026-11-04.txt`,
  one core taken by another job): GCPW 12 ns 18.2 -> 15.9 s full, 7.4 -> 6.0 s with the toolkit's probe end; SMA launch
  10 ns 100.1 -> 79.5 s full, 43.7 -> 34.2 s with probe end (1.15-1.28x over the CPU engine of the same build, same
  stop steps).

## 2026-11-04: UPML on the Metal diamond engine (snapshot cg21)

Code by Claude Opus 5.5 (Claude Code), at the author's request.
- `FDTD/metal/engine_metal_diamond.mm`: the UPML extension on the GPU, per tile: Pre before the update (after the Mur
  Pre stage, as the CPU calls the Pre hooks in reverse extension order), Post after it (before the Mur Post stage), for
  the voltages and the currents, over the box cells in the tile's ranges; one table of the distinct coefficient sets of
  all boxes with an index per component and cell; the arithmetic follows clang's contraction of the CPU expressions.
  Overlapping boxes (Create_UPML makes none) fall back to the CPU loops.
- The extension data moved into three Metal buffers (read-only words, read-only floats, state) with an offset table:
  the kernel had used 29 of Metal's 31 buffer slots.
- Threads per tile now follow the tile size (the power of two at or below 3/5 of a mountain's f4vectors per half-step,
  256-1024) instead of the pipeline maximum, which had cost 44 % on the notch tutorial and 21 % on the SMA launch
  (`results/diamond_sweep_cg21_2026-11-04.txt`). `OPENEMS_DIAMOND_TILE` also reads `M:V`: bench.py splits its `#`
  settings on commas, so `M,V` had been silently ignored there.
- The notch tutorial, notch x3 and the SMA launch now run on the GPU (five of the six models; the GCPW line needs the
  conducting sheets): port probes and S-parameters bit-identical to the multithreaded engine with `OPENEMS_FTZ=1`
  (`results/*_cg21gpu.txt`, `results/diamond_engine_cg21_2026-11-04.txt`). Loaded Mac: notch x3 2966 MC/s, patch x5
  2865, SMA 1304, notch tutorial 1804, patch tutorial 1531 (quiet cg18 CPU best 2046, 1716, 1361, 1961, 1880; cg18's
  SMA figure is on the 1.071 M-cell mesh of 2026-11-03, these runs on 0.871 M).
- The base's `--engine=gpu` (the Metal engine of 7bb294f, not master's) is also bit-identical to the FTZ CPU on all
  five models.
- `bench/check.sh cg21`: CPU paths identical to stock on all six models. `bench/bench.py` counts `metal-diamond` as a
  tolerant engine, like `gpu` (it is compared with stock without FTZ there).
- `scripts/checks/diamond_check.sh`: two PML cases (PML_8 on six faces; PML mixed with Mur faces that cross the PML
  boxes, with lumped elements; `--bc pml|pmlmix` in `diamond_box.py`); 36 of 36 comparisons identical.

## 2026-11-04: lumped RLC on the Metal diamond engine (snapshot cg20)

Code by Claude Opus 5.5 (Claude Code), at the author's request.
- `FDTD/metal/engine_metal_diamond.mm`: the lumped RLC extension on the GPU, per tile in the engine's Apply order
  with the Mur faces (both have priority 0); one state record per element (Il, Vd[n-1], Vd[n-2], J[n-1], J[n-2]) in
  place of the CPU's rotating arrays; the arithmetic follows clang's contraction of the CPU expressions; all reads
  before all writes, one thread in element order when two elements share a cell; per-tile element lists.
- The patch tutorial and patch x5 (Mur, lumped port, nf2ff dumps) now run on the GPU: port probes, S11 and the nf2ff
  dumps bit-identical to the multithreaded engine with `OPENEMS_FTZ=1` (`results/patch_*_cg20gpu.txt`,
  `results/diamond_engine_cg20_2026-11-04.txt`). The notch models and the SMA launch still need UPML, the GCPW line
  conducting sheets.
- `scripts/checks/diamond_check.sh`: a fourth case with a parallel RLC, a series RLC and a series LC element (`--rlc`
  in `diamond_box.py`); 24 of 24 comparisons identical.
- Found on the way: dumps are computed on the creating thread, which `OPENEMS_FTZ` also flushes, so dump comparisons
  need `OPENEMS_FTZ=1` in both runs.

## 2026-11-04: diamond-blocked Metal engine (snapshot cg19)

Code by Claude Opus 5.5 (Claude Code), at the author's request. The tile schedule follows luikore's Metal engine
(openEMS pull request #228, `macos/doc/metal-engine.rst`, GPL); no code of it is used. Credited in the code comments.

### Standalone prototype (`swift_engine/fdtd.swift --diamond K`)
- A diamond-blocked kernel: x and y split into mountains (shrinking by one cell per half-step) and valleys (growing
  into what the mountains left), four dispatches per block (MM, MV, VM, VV), one threadgroup per tile over K
  timesteps in place, z complete, a threadgroup barrier between half-steps.
- Bit-identical to the CPU engines on 41^3 x 600, 121^3 x 600 and 201^3 x 400 timesteps for K = 1, 2, 4, 8 (the CPU
  with `OPENEMS_FTZ=1`); `results/diamond_swift_2026-11-04.txt`.

### openEMS fork: `--engine=metal-diamond` (ENABLE_METAL, macOS)
- `FDTD/engine_metal_diamond.h`, `FDTD/metal/engine_metal_diamond.mm`: `Engine_Metal_Diamond` (derived from
  `Engine_SSE_Compressed`) and `Operator_Metal_Diamond`. The fields are the engine's f4vector arrays, held in shared
  Metal buffers in N-I-J-K order (`ArrayENG::InitView`, new), so probes, dumps and every extension read the same
  memory. The kernel is compiled at the first timestep with Metal fast math off, without the parts a model does not
  use.
- On the GPU: the update equations, the excitation (voltage and current entries, delays, signal period) and the Mur
  ABC (Pre, update, Post, Apply per tile in the CPU engine's extension order; the two cells at each domain edge always
  lie in one edge valley; a face excited on its plane starts late as on the CPU). Each tile reads a list of the
  excitation entries its ranges can reach, in entry order (scanning all 1035 entries of the test box in every tile
  cost a third of the speed).
- Any other extension (PML, lumped RLC, conducting sheets, dispersive materials, ...) makes the engine run the
  generic CPU loops of `Engine_SSE_Compressed` on the same memory, with a message naming the extension.
- Knobs: `OPENEMS_DIAMOND_K` (default 4), `OPENEMS_DIAMOND_TILE=M,V` (default 2K,2K), `OPENEMS_DIAMOND_TG`,
  `OPENEMS_DIAMOND_BATCH` (default 64), `OPENEMS_DIAMOND_TIMING=1` (setup time and GPU cell rate at the end).
- Bit-identical to the multithreaded engine with `OPENEMS_FTZ=1`: `scripts/checks/diamond_check.sh` (new, with
  `diamond_box.py`, `diamond_compare.py`), 18 of 18 comparisons: PEC, Mur on six faces, and MUR/PEC/PMC with a
  delayed E, a soft H and an excitation on a Mur plane, for K = 1, 2, 3, 4, 8 and an odd tile, threadgroup and batch.
- `bench/bench.py` accepts the engine `metal-diamond`.

## 2026-11-04: other GPU engines measured on the M5

Measurements only; no fork, patch or paper change. Claude Opus 5.5 (Claude Code), at the author's request:
- Built upstream master (5fecbb5, its Metal GPU engine) and luikore's Metal fork (openEMS pull request #228, 55ce11b)
  into their own prefixes (`~/opt/openEMS-master`, `~/opt/openEMS-luikore`, each with its own Python), and ran the six
  benchmark models on them next to stock and cg18: `scripts/others/` (new: `run_others.sh`, `bench_ext.py`,
  `xcompare.py`; three lines in `scripts/README.md`), tables and summary in `results/others_2026-11-04/` (README.md).
- luikore's diamond path refuses all six models (Mur; the GCPW line also its conducting sheets). With every Mur face
  replaced by PEC it runs patch x5 and notch x3 at 2.0 and 1.9 times cg18, the notch tutorial at 1.5, the SMA launch
  at 1.05 and the patch tutorial at 0.4. Master's GPU engine runs the six models as they are at 0.42 to 1.06 times
  cg18 (patch x5 and the SMA launch about level, the GCPW line 0.82). GPU results differ from stock by 1.7e-7 to
  1.3e-6 (probes, relative); cg18 stays identical to stock throughout.
- The SMA launch now builds 0.871 M cells (toolkit commit 4a7e20e, mesh floor 0.05 mm), so its numbers in that folder
  do not compare with the 1.071 M-cell `*_cg18.txt` tables.

## 2026-11-04: concurrent work in the paper

Text only; no code, patch or result file changed. Claude Opus 5.5 (Claude Code), at the author's request, from the
public GitHub pages it cites (none of that work was built or run here when this was written; later the same day the
same session built and ran master and PR #228, see "other GPU engines measured on the M5"):
- `paper/sec_positioning.tex`: a new paragraph "Concurrent work on openEMS speed" (luikore's Metal engine with diamond
  blocking, openEMS#228; upstream's GPU engine in master, c3a956b; the CPU pull requests #230, #231, #244, #245; the
  fork of Discussion #492; the SYCL backend #243; the maintainer's plan in Discussion #495, with speed pull requests on
  hold), and what of emsKit we have not found elsewhere.
- "Where emsKit stands" is narrowed from "the fastest configuration of openEMS reported on Apple silicon" to the
  fastest reported on the CPU of Apple silicon that keeps stock's results bit for bit; it now says that luikore's
  diamond Metal engine reports several times emsKit's cell rate on larger Apple chips (simpler model, no bit identity,
  no conducting sheets).
- "Deeper wavefront or diamond blocking was not tried" now says "here" and points to luikore's engine (abstract,
  introduction, `sec_beyond.tex`, `sec_closing.tex`); the third lesson of "Discussion and future work" is limited to
  GPU sweeps that are neither fused nor blocked over time steps.
- The cluster outlook mentions the two-GPU slab split tried in a fork and the maintainer's reply (not a priority).
- The upstreaming paragraph mentions the hold on speed pull requests and the overlap with #231, #244 and #245.
- Nine references added; the Disclosure records this change; `\date` says draft of 2026-11-04.
- `README.md` "Status and licence" and `ROADMAP.md` ("Not planned") point to the same work.

## 2026-11-04: the toolkit's defaults set (toolkit commit 4a7e20e); cg18 installed

No file of this repository changed. Claude Opus 5.5 (Claude Code), at the author's request:
- In the author's toolkit, commit 2b0fd8c (01:58) committed the SMA launch's mesh floor and the review fixes of
  2026-11-02/03, uncommitted until then; its changed lines are those of `patches/rfsim/0003-sma-mesh-floor.diff`.
- Commit 4a7e20e (02:19) then set the defaults that the 2026-11-03 section of `results/sma_mesh_sweep_2026-11-01.txt`
  suggested: a 0.05 mm mesh floor for the SMA launch (`launch.MIN_CELL`), which then builds 0.871 M cells instead of
  1.071 M, and a probe-end hold of 0.5 excitation lengths for every `core.run` (`core.PROBE_END_HOLD`);
  `RFSIM_MIN_CELL=0.02` and `RFSIM_PROBE_END_HOLD=1` give the old ones. `patches/rfsim/` was not regenerated: 0003
  still sets 0.02 mm and a hold of 1 (whether it takes 4a7e20e is an owner decision, `PUBLISH.md` section 0).
- From then on the bench's SMA launch (`bench/models.py` calls the toolkit's builder) has 0.871 M cells too; the
  tables of `results/` that run the 1.071 M-cell mesh of the earlier tables (`RFSIM_MIN_CELL=0.02`) say so.
- At 02:20 snapshot cg18 (patches 0001-0006) was installed on the author's Mac; nothing later is installed.

## 2026-11-03: final review

A final review of the fork, the toolkit patches, the harness, the paper and these documents by Claude Opus 5.5 (30
reviewers; every finding checked by two verifiers, the nits by one), its fixes, a re-measurement of the end-to-end runs
and the SMA mesh sweep on cg18, and the full check and further checks and measurements of that build. What
changed:

### openEMS fork: patch 0006 (commit 087ce9e, snapshot cg18)
- Probe end criterion: the excitation counts as running until its signal length plus the largest excitation delay
  (the voltage and current entries of every grid, the TFSF propagation delay too), so a port excited late no longer
  lets the run stop before its pulse. Mode-match (waveguide) probes count with their amplitude only; their purity
  value kept the criterion from firing. A probe that is still exactly zero holds the run, as before, and a one-time
  notice names it once the others have settled. An invalid `OPENEMS_PROBE_END_DB` or `OPENEMS_PROBE_END_HOLD` prints
  a warning (`BUILD.md`, section 7). Without delays, TFSF or mode-match probes the stop step is unchanged.
- Switches: `OPENEMS_FTZ`, `OPENEMS_NO_STAGGER`, `OPENEMS_NO_PACKED_COEFF`, `OPENEMS_NO_PML_TABLE`,
  `OPENEMS_NF2FF_LEGACY` and `OPENEMS_SETUP_TIMING` act only when set to a value other than empty or `0` (before, `=0`
  turned them on). For every `OPENEMS_*` variable that openEMS reads, an empty value now counts as unset.
- `OPENEMS_FTZ` (arm64): the thread that creates an SSE-family engine gets its FPCR.FZ bit back when the engine is
  destroyed there, so the Python thread keeps its subnormals after a run.
- Packed coefficient tables are always built (the size test of 0005 is removed); only a failed allocation skips them,
  and the multithreaded engine then says that its sweep is not fused.
- Automatic thread count: every candidate, the starting count included, is clamped to the threads that get x-lines.
  The cylindrical multigrid prints its fused-sweep line once per level engine (the lines raced on `cout`).
- A mesh too large for the 32-bit array sizes is refused at setup with error code 2 and a message (`BUILD.md`,
  section 8).
- nf2ff: `<vecLib/cblas.h>` instead of the Accelerate umbrella header, which GCC cannot parse (the older CBLAS
  interface is kept on purpose: the newer one changes the far field in the last bits); the blocks of directions also
  bound the P buffer.
- Raw export (`OPENEMS_EXPORT_*`): every failed write is reported, an empty value exports nothing, and a warning counts
  the current excitation entries, which are not exported.
- Portability and comments: the spin barrier emits its yield hint only on ARM targets that have it; comments
  corrected. The message lists the corrections to the messages of 0001-0005; `BUILD.md` (section 8) adds two for 0003.
- Verified when committed, at most 2 engine threads: without switches bit-identical to the 0005 build on the patch
  tutorial and the GCPW line (port files, HDF5 dumps; the GPU engine too), the Debye box on three engines, each switch,
  the probe-end cases with delays, mode-match ports and TFSF, the size guard, the cylindrical multigrid.
- Documented, not changed (from the base): a time-domain HDF5 dump keeps its file open until the run ends, as upstream
  master does, so a killed run leaves no readable time step in it, and its metadata cache grows while the run lasts;
  the base's background writer queues up to 64 field copies, where upstream master keeps one pending task per dump
  (`BUILD.md`, section 8).

### rfsim (patches/rfsim/0003-sma-mesh-floor.diff, regenerated from the toolkit)
They include the fixes that the corrections of the 2026-11-02 entry call "fixed on 2026-11-03". No mesh line of a
default or swept model moved.
- `core.run()`: `stopped_early` is true only when the probe end criterion was on and the run ended before `max_time`;
  false when the criterion was off, the library is stock, or the run reached `max_time` (a warning names every run
  that reached it with the criterion on); `None` when it cannot be told (no `max_time`, no port, an unreadable probe
  file). `m.info["threads"]` is `"auto"` for 0.
- Probe-end arguments: `probe_end_hold=None` is the default hold; a positive `probe_end_db` or a hold that is not
  positive raises `ValueError`. An invalid `RFSIM_PROBE_END_DB` or `RFSIM_PROBE_END_HOLD`, `RFSIM_PROBE_END_HOLD=0`
  included, gives a warning and the default (-60 dB, hold 1); only an empty or zero `RFSIM_PROBE_END_DB` turns the
  criterion off. openEMS itself takes `OPENEMS_PROBE_END_HOLD=0` as no hold; the toolkit refuses a hold of 0 on
  purpose, because it can stop a run on the precursor (`BUILD.md`, section 7).
- `core.features()` asks the loader which libopenEMS the process loaded (macOS: the dyld image list; Linux:
  `/proc/self/maps`) and records it as `lib`.
- `core.merge_lines()` thins a run of lines finer than the floor (its end lines stay, the others are spaced at the floor
  or more) instead of merging it into one line.
- `edge_launch` records its boundary conditions through `Model.set_bc()`, so `pad_z` keeps its Mur cell.
- `sma_launch` refuses a scale at which the edge-rule lines of the two gap edges meet or cross (3 and above with the
  default gap), and its error message for a floor that is too coarse suggests a smaller scale where a smaller floor
  would undo the coarse mesh.
- `core.run()` and `extract.run()` make `sim_dir` absolute (openEMS changes into it and stays there).
- Docstrings, comments and the toolkit's README: one excitation length of the toolkit's pulse is 2.865 ns at `f_max`
  2 GHz (hold 1 = 2.865 ns); the probe-end rules say which fork patch brings them (0005, 0006); a 0.06 mm floor takes
  the prepreg from 4 to 2 cells; the sweep numbers are those of 2026-11-03.

### End-to-end runs and the SMA mesh floor, re-measured
- `results/rfsim_e2e_2026-11-03.txt`: 14 toolkit runs, one each on a quiet Mac, on cg18 and on
  stock v0.37.0, with the published toolkit patches; times are `FDTD.Run` wall times. SMA launch (1.071 M cells,
  182 622 steps of 54.76 fs): stock 562.7 s, full run 168.5 s (3.3x), -60 dB / hold 1 97.6 s (5.8x), 0.05 mm floor and
  hold 0.5 37.4 s (15.0x). GCPW line (0.242 M cells, 94 217 steps): stock 76.5 s, full run 13.7 s (5.6x), -60 dB /
  hold 1 8.6 s (8.9x). The stock port files are byte-identical to the fork's full runs on both boards, and the port
  files of every probe-end run on the default mesh are a byte-identical prefix of its full run's.
- These replace the earlier headline numbers: for the SMA launch 462 s (computed from stock's 4-thread speed and the
  original mesh's 188 697 steps), 29 s (the first floor version's 0.777 M-cell mesh, 46 444 steps) and 16x; for the
  GCPW line 76 s (computed) and 8.9 s (project log, snapshot cg16).
- Mesh floor (2026-11-03 section of `results/sma_mesh_sweep_2026-11-01.txt`): the reference is now the full run on the
  published default mesh, not `s_ref`. 0.05 mm at -60 dB / hold 1: 1.90x fewer cell-steps and 1.97x less run time, S11
  within 0.116 dB at -22.8 dB, Z0 +0.104 ohm; with a hold of 0.5: 2.54x / 2.61x, Z0 +0.121 ohm. 0.03 mm, first run on
  the corrected merge: 1.007 M cells, S11 within 0.029 dB. The recommendation (0.05 mm, hold 0.5) stands; the
  toolkit's defaults stay 0.02 mm and a hold of 1.

### Harness, scripts and repository
- `bench.py` refuses a snapshot folder that is missing or lacks one of the three libraries, and checks after each run
  that all three were loaded from it (`bench/libinfo.py`). `bench.py` and `check.sh` exit non-zero on a difference or
  a missing file. A comparison without a relative figure (an all-zero reference probe, an S-parameter below -40 dB) is
  compared exactly and named. Every repeat is compared with the reference config's first run. The tables go to the
  top-level `results/` (`--out` changes it). `step1.sh` measures the stock snapshot (`STOCK=`); `check.sh` has `LITE=1`
  (the reduced set of the cg17 check) and ends with PARTIAL when `RFSIM_PATH` is unset.
- New scripts: `scripts/e2e/` (the end-to-end re-measurement), `scripts/memory/`, `scripts/timestep/`,
  `scripts/cache_valley/place.c` and `placement.sh`, `scripts/kernel/gcc_vs_clang.sh`; `scripts/README.md` lists every
  script.
- New files: `patches/README.md`; `patches/csxcad/COPYING.LESSER` (a copy of CSXCAD's `COPYING`);
  `results/rfsim_e2e_2026-11-03.txt`; `results/notch_s1_n3000_ftzgpu.txt` (with `OPENEMS_FTZ=1` the multithreaded and
  sse-compressed engines give the upstream GPU engine's probes bit for bit on the notch tutorial);
  `results/validation_negative-control_patches-0001-0004_mt2.*` (the validation suite's Debye slab fails on a build of
  patches 0001-0004, which has the Debye bug).
- Licences: the CSXCAD patch is under the LGPL v3 like CSXCAD, the openEMS patches under the GPL like the files they
  change; emsKit's own files (harness, scripts, `paper/code_notes.md`, `swift_engine/`, the result files, the rfsim
  patches) are GPLv3; the paper text and figures are CC BY 4.0.
- `.gitignore`: the paper's preview PDF and arXiv tarball, `bench/results/`, the `s_ref` reference run, the raw
  `*.f32` / `*.u32` exports.

### Paper and documentation
- The paper's end-to-end, probe-end and mesh-floor tables and figures, its abstract and the README use the
  re-measured runs. The title says "towards the memory ceiling" (paper, README, the CC BY notice, `PUBLISH.md`).
- Paper, besides those runs: the abstract gives the engine's cell-rate range apart from the setup and far-field times;
  the precomputed dump gather is upstream's, used by the fork's SSE engines; the notch run with `PML_8` requested on
  all six faces had PML on the four x and y faces (`results/notch_s1_n8000_pml6.txt`); the Mac mini figures follow the
  cited specification page; the reproducibility section lists `paper/code_notes.md`; the Disclosure covers 2026-10-28
  to 2026-11-03 and says who re-measured the runs.
- README: the instruction counts of the rewritten loop are those of cg18's library (94 to 41 per iteration of the
  voltage update, 95 to 42 for the currents; the earlier 94 to 44 was snapshot AB's); the dump gather is upstream's,
  used by the fork's SSE engines; the energy end criterion's schedule is upstream eb1c5ee's; links to
  `patches/README.md` and `paper/code_notes.md`. The README and this file no longer call the reviews of 2026-11-02
  independent (the message of 0006 corrects that of 0005).
- BUILD.md: the time-domain HDF5 dumps inherited from the base (section 8); the empty-value rule, the warnings, the
  stop-time limitation of the probe end criterion and the toolkit's own rules (section 7); the two corrections to
  0003's message (section 8); GCC and the C++ standard with VTK 9.7 (section 8); the `git am` check with 0006
  (section 4).
- Added on 2026-11-03 in work that the project's log does not record (who wrote them is for the owner to state): the
  paper's positioning section (`paper/sec_positioning.tex`) and the abstract's sentence on clusters, the README's
  "Scaling out" paragraph, `ROADMAP.md`, the validation suite `bench/validation/` and its first results
  (`results/validation_stock-v0.37.0_linux-sandbox.*`, `results/validation_negative-control_debye-hooks-disabled.*`),
  and later that day two runs of snapshot cg17 on the Mac, 15 of 15 each (`results/validation_cg17.*` with the
  defaults, `results/validation_cg17_mt8.*` with the multithreaded engine at 8 threads).

### Checks and measurements on cg18
- Full check, `bench/check.sh cg18 cg18` on a quiet Mac (`results/*_cg18.txt`; 1, 4, 8 and 10 threads and the
  automatic choice, two runs each): every run bit-identical to stock v0.37.0 on all six models. Best speeds against
  cg14's: patch x5 1715.5 MC/s (-2.7 %), notch x3 2045.8 (-2.5 %), patch tutorial 1880.4 (-1.6 %), notch tutorial
  1960.8 (+1.6 %), GCPW line 1760.2 (+8.2 %), SMA launch 1361.4 (-1.7 %). The paper's speed tables and figures stay
  those of cg14.
- Correctness (`results/correctness_cg18_2026-11-03.txt`): the Debye box bit-identical on the basic, sse-compressed and
  multithreaded (4 threads) engines, and on sse-compressed against cg17; the cylindrical multigrid example (1.37 M
  cells, 1500 steps, an FD and a TD dump) identical to stock in all 34 HDF5 datasets; the patch tutorial's far field
  identical to cg17's, with `OPENEMS_NF2FF_LEGACY=1` identical to stock's, and on the separable path within 6.8e-7
  relative of stock's (CalcNF2FF of the 3-D pattern: 1.21 s on stock, 0.30 s on cg18).
- Validation suite on the Mac: cg18 15 of 15 with the multithreaded engine at 4 threads and with the default
  engine and thread count (`results/validation_cg18_mt4.*`, `results/validation_cg18_fastest.*`), stock v0.37.0 15 of
  15 (`results/validation_stock-v0.37.0_macos.*`).
- The fork's base against stock (`results/*_base.txt`; the libopenEMS of 7bb294f with the stock libCSXCAD and
  libnf2ff, beside stock and cg18, on four models): on the patch tutorial the base runs 1.13-1.18x faster
  than stock at 1-4 threads, all of it on the dump side (342.2 MC/s each with the dumps off, 2 threads). Best against
  best that is 1.13x, so about 1.13x of that model's 6.9x comes from upstream's background dump writer, and the
  patches' own factor there is about 6.0x. On the notch tutorial, the GCPW line and patch x5 the base is within noise
  of stock (0.98-1.03x). Probes and S-parameters identical in every row.
- The valley, re-measured on cg18 and on stock (`results/cache_valley_placement_2026-11-03.txt`,
  `results/cache_valley_stock_2026-11-03.txt`), is now called the allocation-placement valley (before: the
  cache-aliasing valley). It covers field arrays of 2-4 MiB each, about 0.175-0.35 M cells (the 2026-11-01 sweep, in
  steps of 10 lines, gave a coarser range). macOS 27.0.1's allocator puts two such arrays 4 MiB + 16 KiB apart; arrays
  exactly 4 MiB or 8 MiB + 16 KiB apart run fast, although all these distances are multiples of 16 KiB. Without
  the stagger cg18 runs 239.9-240.9 MC/s in the valley against 864.9-882.4 at its edges (3.6-3.7x), with
  it 867.7-899.7 at every size tested. In the standalone kernel, moving the current array by 512 B to 64 KiB (16 and
  32 KiB included) removes the slowdown, so the project log's record of 2026-10-29 (16 and 32 KB offsets did not
  help, read as L1 set aliasing) was not reproduced at the shape tested; the mechanism is not identified. Stock
  v0.37.0 has the valley too: 213.4-215.3 MC/s against 461.2-474.6 at the nearest sizes (2.1-2.2x).
- GCC and the loop counts (`results/kernel_gcc_vs_clang_2026-11-03.txt`,
  `results/kernel_loop_instructions_2026-11-03.txt`): in the standalone kernel at one thread, GCC 16.2 with the same
  flags runs the stock loop 1.16-1.39x faster than Apple clang 21 and the rewritten loop at about the same speed, so
  the rewrite gains 1.26-1.47x there over a GCC-built stock loop against 1.74-1.80x over a clang-built one. The stock
  loop gives the same bits under both compilers; the GCC-built rewrite does not match it bit for bit. Counted in the
  disassembly: 94 / 95 instructions per iteration of the voltage / current loop in the stock library, 41 / 42 in
  cg18's. Apple clang gives every store through the f4vector union the alias type of char, so the stock loop
  reloads strides and table pointers after the stores (44 loads, 21 of them vector loads); GCC's stock loop does not
  (80-82 instructions, 29 loads). A GCC build of openEMS itself was not made.
- Memory and time step, now in `results/` and run on cg18 (`results/memory_per_cell_2026-11-03.txt`,
  `results/timestep_bound_gcpw_2026-11-03.txt`): 28.1 B per mesh node in the time loop (28.2 with a dump box) and a
  setup peak of 99.7 B per node (123.7 with a dump box), within 0.1 B of the cg17 run of that morning that the paper's
  numbers first came from; the exact leapfrog limit of the GCPW line's bulk update (without the Mur, lumped-port and
  conducting-sheet updates) is 1.2604 times openEMS's time step, from an operator export byte-identical to that
  morning's cg17 export.
- New scripts and files: `scripts/kernel/loop_insns.py` with `scripts/kernel/pc_sampler.cpp` (the loop counts); in
  `results/` the six `*_cg18.txt`, the four `*_base.txt`, the two valley files above,
  `kernel_gcc_vs_clang_2026-11-03.txt`, `kernel_loop_instructions_2026-11-03.txt`, `correctness_cg18_2026-11-03.txt`,
  `validation_cg18_mt4.*`, `validation_cg18_fastest.*`, `validation_stock-v0.37.0_macos.*`,
  `memory_per_cell_2026-11-03.txt` and `timestep_bound_gcpw_2026-11-03.txt`; `summary.json` regenerated (it now also
  collects the base, cg18 and ftzgpu tables; no earlier value changed).
- Paper: the valley subsection and its figure (now with a stock v0.37.0 curve) follow the placement test, and every
  mention uses the new name; the inner-loop subsection gives the measured loop counts and the GCC kernel comparison,
  which the scope paragraph, the bit-identity subsection, the positioning section and the list of what did not work
  also cite; the abstract, the introduction and the results, dumps and positioning sections give the base's share of
  the patch tutorial's factor; the method and results sections and the review-fixes subsection report
  cg18's full check, correctness checks and validation runs (the speed tables and figures stay those of cg14); the
  far-field subsection adds cg18's nf2ff times; the memory and time-step figures cite their files in
  `results/`; the reproducibility section lists the new files and scripts, and the Disclosure names the runs of
  2026-11-03. Corrected: the upstream GPU engine's three patch-tutorial runs in `results/` span 923-1115 MC/s; the
  paper gave 1055-1622 MC/s for the two tutorials, from one run each (both notch-tutorial runs give 1622).
- Documents: the README gives the base's share of the patch tutorial's factor, cg18's check, the validation
  runs on the fork and the GCC kernel result, its valley item follows the placement test, its nf2ff item says complex
  matrix products (one per plane and block of directions), and stock's thread counts in the end-to-end runs are named
  as those the toolkit uses for a stock library. `BUILD.md`: section 8 names the base's dump writer as a speed change
  (its heading now says "besides the fork's speed-ups") and gives the GCC kernel comparison; the introduction and
  section 9 name cg18's checks. `PUBLISH.md` says what is left of the full check; `scripts/README.md`
  corrects the `place.c` row to the placement file, and `place.c`'s own header comment follows it.
- Models corrected from the session transcript: the first day (2026-10-28, until the evening) ran on Claude Opus 5.5,
  which wrote the benchmark harness and the engine work of patch 0001 (snapshots A to cg8); Claude Fable 5.1 took
  over that evening, committed 0001 (its trailer names Fable 5.1) and made 0002-0005; Opus 5.5 came back for the
  final review. The paper's Disclosure, the README and `PUBLISH.md` had said Fable 5.1 from 2026-10-28; the
  2026-11-02 entry below is corrected the same way.

## 2026-11-02: pre-publication review

Four read-only reviews by fresh instances of Claude Fable 5.1, one of the two models that wrote the code (fork
correctness, further optimisation, the rfsim changes, and the paper's numbers against the result files), run before
anything was published. What they found and what changed:

### openEMS fork: patch 0005 (commit 489b805, snapshot cg17)
- **Wrong result fixed:** Debye materials lost their dispersion in the multithreaded engine. `Engine_Ext_DebyeMaterial`
  inherited `Engine_Ext_Dispersive`'s hook declaration, so the hook plan never called its Pre/Post voltage hooks; the
  single-threaded engines were right. No Debye material was in the test set. Fixed, plus a structural guard
  (`OPENEMS_HOOKS_DECLARED_BY`) that makes any extension without its own declaration fall back to every hook.
  Test: `scripts/checks/debye_check.sh` (37 % of the peak field before, bit-identical after).
- Probe end criterion: the hold starts only once every probe has seen a signal (a probe ahead of the wavefront no longer
  counts as settled); a non-Gaussian excitation with the knob set prints a notice.
  - *Corrected 2026-11-03:* this holds back only a probe whose values are all still exactly zero. The numerical
    precursor of the pulse makes a far probe non-zero shortly before the pulse arrives, so the hold must still be longer
    than the longest one-way delay in the model (`BUILD.md`, section 7).
- `Operator::GetMaterial()` lookup cache keyed by a setup generation (no stale property pointer across setups).
- `Engine_Ext_Excitation` declares the current hook only when it has current excitations (one barrier less per step).
- Auto thread tuner never queues more threads than x-lines.
  - *Corrected 2026-11-03:* only the candidates above the starting count were clamped; the starting count itself and the
    one two below it were not (patch 0006 clamps every candidate).
- nf2ff: the separable path only with a CBLAS (Apple Accelerate); other builds keep the threaded legacy loop.
- Packed coefficient tables skipped with a message when they would exceed twice the field memory or fail to allocate.
  - *Corrected 2026-11-03:* the size test could fire only through the z padding of the f4vectors, and when it fired it
    also turned off the IJKN loops and the fused sweep without saying so. Patch 0006 removes it: only a failed
    allocation skips the tables, and the multithreaded engine then says that its sweep is not fused.
- Cleanups (include order, unused includes, the NX-1 current-hook invariant documented).
- Verified: six bench models bit-identical to stock at 4, 8 and auto threads (`results/*_cg17.txt`), cylindrical
  multigrid example 18 HDF5 datasets identical, GCPW probe-end stop step unchanged (45570) with a bit-identical prefix.
- Documented, not changed: the staggered allocator is an ABI change for out-of-tree code; `OPENEMS_FTZ` also sets
  FPCR.FZ on the creating thread; GCC's default fp-contraction on x86 with FMA may differ from stock in the last bit.
  - *Corrected 2026-11-03:* the ABI note was incomplete. The base's GPU-engine commit (bf30fa4) also changed the layout
    of ArrayLib's `ArrayBase`, so Python modules built against one build break `openEMS.sar_calculation` on the other
    (an abort, or a wrong SAR without an error). Both modules must be rebuilt after every install over another build, in
    either direction (`BUILD.md`, section 6).
  - *Corrected 2026-11-03:* `OPENEMS_FTZ` has no effect on the basic engine. On x86 the engines set MXCSR FZ and DAZ
    whatever the variable says and never restore them, as stock v0.37.0 does (upstream fixed this later, 367a63f). Since
    patch 0006 the creating thread gets its arm64 state back when the engine is destroyed.
  - *Corrected 2026-11-03:* the GCC note holds on every aarch64 build as well (FMA is part of the base instruction set
    there), not only on x86 with FMA; the IJKN loops and the UPML f4vector rows are the affected code (`BUILD.md`,
    section 8).

### rfsim (patches/rfsim/0003-sma-mesh-floor.diff, uncommitted in the owner's toolkit)
- **Two bugs fixed in the SMA launch mesh floor:** `min_cell` did not scale with the model's `scale` (a 0.6 convergence
  mesh was merged with the unscaled floor), and the line merge depended on the scan direction, so a mirror-symmetric
  structure got an asymmetric y mesh at floors above 0.02 mm. New `core.merge_lines()`: scan-order independent,
  priority classes (protected strip/gap lines and layer planes never move; geometry lines merge at their mean; grid lines
  give way), `ValueError` when the floor would merge two protected lines or is not below every fixed cell of the stack-up
  (0.0526 mm and above are refused; the old sweep's 0.06 row lost prepreg cells). The default 0.02 mm mesh is unchanged
  line for line; 0.04 and 0.05 mm meshes gained lines (0.953 M and 0.871 M cells instead of 0.930 M and 0.777 M).
  Re-measured on the corrected mesh against `s_ref` (steps exact, machine loaded, so times are estimates from the
  cell-step count): 0.04 mm 72.9 k steps, S11 within 0.08 dB, Z0 +0.13 ohm (1.6x fewer cell-steps than the default);
  0.05 mm 67.3 k steps, 0.12 dB, +0.11 ohm (1.9x); 0.05 mm with hold 0.5: 50.3 k steps (2.5x). The recommendation
  0.05 mm + hold 0.5 stands; the toolkit's defaults stay 0.02 mm and hold 1.
  - *Re-measured 2026-11-03* (cg18, quiet Mac, against the full run on the published default mesh instead of
    `s_ref`; same meshes and step counts; 2026-11-03 section of `results/sma_mesh_sweep_2026-11-01.txt`): 0.04 mm S11
    within 0.078 dB, Z0 +0.123 ohm, 1.60x fewer cell-steps and 1.68x less run time than the default; 0.05 mm S11 within
    0.116 dB, Z0 +0.104 ohm, 1.90x and 1.97x; 0.05 mm with hold 0.5: S11 within 0.116 dB, Z0 +0.121 ohm, 2.54x and
    2.61x. See the 2026-11-03 entry.
  - *Corrected 2026-11-03:* "unchanged line for line" compares with the first version of the floor (2026-11-01). Against
    the toolkit's mesh before this patch (the mesh of `s_ref`), 14 lines of the default mesh move: 9 by at most 0.01 mm
    in the merge and 5 graded y lines by up to 0.104 mm. The time step goes from 53.0 to 54.8 fs (the full 10 ns run
    from 188 697 steps to 182 622, the latter in `results/rfsim_e2e_2026-11-03.txt`), the -60 dB / hold 1 stop from
    107 289 steps (project log) to 103 831, and 0.0337 dB of that row's 0.038 dB in S11 comes from the mesh change
    (`results/sma_mesh_sweep_2026-11-01.txt`).
  - *Corrected 2026-11-03:* the headline end-to-end numbers of the SMA launch (abstract, README, the end-to-end table
    and figure) were not moved to the corrected mesh and still came from the first version's 0.05 mm run; see the
    2026-11-03 entry.
- `core.pad_z()` never splits the z-max boundary cells (PML keeps its thickness, the Mur cell its size) and never
  shrinks the time step; builders record their boundary conditions through `Model.set_bc()`.
  - *Corrected 2026-11-03:* not all of them: `edge_launch` still called `SetBoundaryCond` directly, so `pad_z` split its
    Mur cell (fixed on 2026-11-03).
- `core.run()`: `core.features()` detects a stock openEMS (no auto thread count, no probe end criterion) by scanning the
  openEMS library file it finds (see the correction below) and falls back to the old 4 / 8 thread rule with a warning;
  the probe-end request is warned about on a stock library; `hold=None` no longer raises; `m.info` records `t_end_ns`,
  `stopped_early` and `threads`, and a probe-end run that reached `max_time` is warned about. `RFSIM_MIN_CELL=0` now
  means the default.
  - *Corrected 2026-11-03:* `hold=None` still raised (a `ValueError`) while the criterion was on,
    `RFSIM_PROBE_END_HOLD=0` made every run raise, and a positive `probe_end_db` was passed on and ignored by openEMS
    without a message. `stopped_early` was true for most runs that reached `max_time` (the last probe sample lies up to
    one probe interval before it), which also kept the `max_time` warning from showing. Under the automatic thread count
    `threads` recorded 0. `core.features()` did not ask the loader which library it had loaded: it guessed the file from
    `DYLD_LIBRARY_PATH` / `LD_LIBRARY_PATH` and `otool` / `ldd` output, so with `LD_LIBRARY_PATH` set on macOS, or a
    library path with a space in it, it could take the fork for stock or the other way round. All fixed on 2026-11-03.
- The two committed rfsim patches were regenerated restricted to `_sim/` (the earlier files carried hunks of the
  owner's private daily notes).

### Paper and documentation
- Nine wrong numbers or claims corrected (macOS version; operator table size; notch x3 2108 to 2099 and SMA 1409 to 1385,
  the results-backed cg14 values; two cg13/cg14 step figures; the single-thread valley figure; the automatic thread
  count's accuracy; a figure caption's reference run; the bandwidth sentence, which now separates cell rate from GB/s),
  twelve smaller fixes (see the paper's Disclosure and the git history of this repository once published), numbers that
  come from the project log instead of `results/` marked as such.
  - *Corrected 2026-11-03:* the new valley figure (230 to 790 MC/s) came from an earlier sweep in the project log and
    was not marked; the published sweep, `results/cache_valley_2026-11-01.txt`, has 247 to 249 MC/s without the stagger
    against 881 to 894 with it, at 0.20 to 0.34 M cells.
  - *Corrected 2026-11-03:* the pointer for the twelve smaller fixes leads nowhere: the Disclosure refers back to this
    file, and the repository starts with one commit, so no list of them is published.
  - *Corrected 2026-11-03:* the marking was incomplete: many numbers that come only from the project log stayed unmarked
    (the probe-end and end-to-end tables, setup and nf2ff times, the 201^3 box, the standalone kernels, the z-padding
    and side-by-side runs, among others).
- The AI assistant is no longer listed as an author (arXiv policy); the contribution is stated in the Disclosure.
- `parse_results.py` keyed per (model, scale, steps, tag): the GCPW cg12 entry of `summary.json` was taken from a loaded
  run (1241 instead of 1621 MC/s).
- A second-review table of further optimisation candidates with estimates in the future-work section.
- BUILD.md: exact base commit checkout, `EMSKIT` path variable, verified `setup.py` variables, harness knobs, macOS-only
  statement, review notes. PUBLISH.md: real commands for the trailer rewrite and the author line, arXiv notes.
  - *Corrected 2026-11-03:* the checkout fetched upstream's `gpu-engine` branch by name, which upstream had already
    deleted, so it failed; `BUILD.md` now fetches the base commit by its hash. The steps also lacked the dependencies
    (fparser, TinyXML, CGAL, VTK), saving a stock reference before installing, and rebuilding the Python modules.
- Hygiene: personal paths replaced by `RFSIM_PATH` and relative paths, `scripts/README.md`, `.gitignore` for run
  outputs, `paper/LICENSE-CC-BY-4.0.txt`, patch numbering.
  - *Corrected 2026-11-03:* the `.gitignore` missed the preview PDF and the arXiv tarball in `paper/`, the `s_ref`
    reference run that `scripts/README.md` asks for, and the check tables that `bench.py` wrote to `bench/results/`. The
    CC BY notice put the CSXCAD patch under the GPL; CSXCAD and its patch are under the LGPL v3
    (`patches/csxcad/COPYING.LESSER`).

## 2026-11-01: first publication folder
Patches 0001 to 0004 (snapshot cg16), the bench harness, results, scripts, the Swift/Metal kernel and the paper draft.
