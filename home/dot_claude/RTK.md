# RTK output filtering

The configured Claude hook rewrites supported shell commands through RTK to
reduce output. `rtk proxy <command>` runs without filtering when diagnosis
requires the original output. `rtk gain` reports RTK's own recorded savings;
that metric does not measure the complete agent context or guarantee lossless
output. Check the hook and `rtk --version` when filtering behaves unexpectedly.
