# Ermine examples

These are examples of Ermine syntax and reports.

To make them available, depend on the artifact, and add to your `s:
SessionEnv`:

```scala
s.loadFile =
  SourceFile.inOrder(others...,
                     SourceFile classloader "com/clarifi/reporting/examples")
```
