@{
    # Scripts not yet rewritten to the Phase 1 conventions (see todo.md).
    # Lint findings in these files are reported but do not fail the checks, and
    # the convention tests in Repository.Tests.ps1 skip them.
    #
    # Remove a file from this list in the same commit that rewrites it; from then
    # on it is held to the full rule set. The list must only ever shrink.
    Legacy = @(
    )
}
