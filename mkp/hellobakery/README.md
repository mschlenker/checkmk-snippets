# Hello bakery!

This example extends the "Hello world!" example with bakery configuration
to showcase how plugins can access the bakery API for easier distribution
of agent checks and their configuration. 

Enterprise Edition only!

## Contents

A Python script for the agent side that outputs "hello_world" and a
random number between 0.0 and 100.0, the CheckMK side sends WARN and 
CRIT when thresholds of 80.0 or 90.0 are reached (so expect a 
notification roughly every 5 minutes.

Additionally the user name read from the JSON config is printed out.

```
<<<hello_bakery>>>
hello_bakery 90.24242012379389
user johndoe
```

The package includes:

- Checkmk side agent based check
- Configuration for editable thresholds
- Definition of a graph
- Definition of perf-o-meter
- Registry for the bakery API
- Bakery example with postinstall and configuration
- Configuration of package contents via setup GUI
