// Command Line Tools' `swift test` does not run Swift Testing suites, so the
// tests are built as an executable that calls Swift Testing's entry point.
// Run with: swift run ClaudeSwitchCoreTests [--filter <name>]
import Testing

await Testing.__swiftPMEntryPoint() as Never
