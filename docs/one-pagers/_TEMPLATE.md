# <model_name>

One-pager for a single table. Written before the model is considered done, not
after. If you cannot fill in the grain line in one sentence, the model is not
ready.

## Purpose
What question this table exists to answer. One or two sentences. If the answer is
"lots of things", split the table.

## Grain
One row per ____ per ____ .
Primary key: ____
Enforced by: ____

## Input sourcing
| Upstream | What it contributes | Refresh |
|---|---|---|
|  |  |  |

## Dimensionality
Which attributes are available to slice by, and which are deliberately absent.
Note anything nullable that will silently drop rows from a filtered cut.

## Known limitations
Things a consumer of this table would get wrong if nobody told them. Nulls with
meaning, heuristics, incomplete joins, coverage gaps by era or set.

## Retention and refresh
How far back the data goes, how often it rebuilds, whether it is incremental, and
what a full refresh costs.

## Tests
What is asserted about this table and what each test protects against.

## Owner and last reviewed
____ / ____
