# Hello world!

This is a very basic plugin that can be used as template for your own 
plugin development. It should be complete enough to fulfill the requirements 
of the Checkmk exchange.

Besides this it can be used to create some noise for testing purposes.

## Contents

A Python script for the agent side that outputs "hello_world" and a
random number between 0.0 and 100.0, the CheckMK side sends WARN and 
CRIT when thresholds of 80.0 or 90.0 are reached (so expect a 
notification roughly every 5 minutes.

```
<<<hello_world>>>
hello_world 90.24242012379389
```

The package includes:

- Checkmk side agent based check
- Configuration for editable thresholds
- Definition of a graph
- Definition of perf-o-meter

