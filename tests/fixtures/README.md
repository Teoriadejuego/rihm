# Classification oracle

`classification-oracle.csv` enumerates all 64 binary decision patterns. Expected
axis levels come from the four allowed decision triples for each axis. Expected
categories come from an explicitly enumerated 4×4 category table, independent of
the predicates in `R/classify.R`; the fixture was not produced by that function.
All other patterns are inconsistent and their category indicators are missing.
Individual axis levels remain available when only the other axis is inconsistent.

These are deterministic test inputs, never observed respondents or public results.
