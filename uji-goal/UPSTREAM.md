# Upstream

Adapted from https://github.com/g4bwy/maki-goal at revision
`cf145bc70eb74d086f9339d8fcb147bb064fb5fb`.

The original Lua modules are retained unchanged in `upstream/` for attribution
and comparison. They are not loaded by the uji pack. Upstream describes the
project as a port of pi-goal and pi-goal-x and declares “Same as maki (MIT)” in
its README, but does not include a LICENSE file at this revision. This fork
does not invent a replacement copyright notice; confirm licensing with the
upstream author before redistributing.

The native adaptation intentionally replaces incomplete upstream continuation
and auditing behavior, and fixes completed-goal retention. The existing git
remote still points to upstream; no GitHub fork, branch, commit, or push was
created by this adaptation.
