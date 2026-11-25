# Architecture decision records

| Record | Status | Decision |
|---|---|---|
| [0001](0001-nix-tooling.md) | Accepted | Project-local Nix tooling |
| [0002](0002-mister-prototyping.md) | Accepted | MiSTer as the initial FPGA platform |
| [0003](0003-display-resolution.md) | Accepted | Enhanced and legacy rendering resolutions |
| [0004](0004-software-first-validation.md) | Accepted | Software acceptance now; physical MiSTer verification deferred |
| [0005](0005-prototype-cpu-and-peripherals.md) | Superseded | Initial R65C02/four-sprite prototype; carried forward and extended by 0006 |
| [0006](0006-maze-game-and-sprite-budget.md) | Accepted | Rail maze game and eight-sprite budget, retaining the CPU/system design |
| [0007](0007-enhanced-graphics-effects.md) | Superseded | Initial graphics proposal; standalone target and budgets selected in 0008 |
| [0008](0008-standalone-development-target.md) | Superseded | Earlier ECP5-12F/x16 development target and graphics workload estimates; retained as historical reference |
| [0009](0009-tang-prototype.md) | Accepted | Tang Nano 20K legacy prototype, internal Lynx CPU and new board adapters; enhanced graphics require a fresh budget |

Use the next four-digit number and a descriptive filename. Each record contains
Date, Status, Context, Decision, Consequences, and References. Valid statuses are
Proposed, Accepted, and Superseded. Record actual user-approved requirements or
explicit implementation choices; keep unselected hardware in research notes.

When a decision changes, add a new accepted record, mark the old one Superseded,
and link the two. Do not rewrite the old decision as though it never existed.
