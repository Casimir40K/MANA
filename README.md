# MathLab — MATLAB Steady-State Process Solver

A transparent, educational process simulator built in MATLAB. Simpler than Aspen/HYSYS by design — explicit physics, readable code, no black boxes.

## Quick Start

### Folder Structure

```
MathLab/
├── MathLabApp.m            ← the GUI (run this)
├── run_case_water.m        ← command-line demo
└── +proc/                  ← package folder (+ is required)
    ├── Stream.m
    ├── Flowsheet.m
    ├── ProcessSolver.m
    └── +units/
        ├── Link.m
        ├── Mixer.m
        ├── Reactor.m
        ├── StoichiometricReactor.m
        ├── ConversionReactor.m
        ├── YieldReactor.m
        ├── EquilibriumReactor.m
        ├── Separator.m
        └── Purge.m
```

The `+proc` prefix is mandatory MATLAB package syntax. Don't rename it.

### Run the GUI

```matlab
cd('path/to/MathLab')
app = MathLabApp;
```

### Run the Command-Line Demo

```matlab
cd('path/to/MathLab')
run_case_water
```

---

## App Tabs

### 1. Species

Editable table with columns **Name** and **MW (kg/kmol)**. Add, remove, or edit species directly in the table. Click **Apply Species** to lock them in — this resets all streams and units, since composition vectors depend on the species list.

You can start from the defaults (H2, O2, H2O) or define your own system from scratch.

### 2. Streams

Two tables stacked vertically:

**Top table (Values):** Edit n_dot, T, P, and mole fractions for each stream. Double-click a cell, type a value, press Enter.

**Bottom table (Known Flags):** Checkboxes. Checked = you are specifying this value (it's a process input). Unchecked = the solver will calculate it. Your feed stream(s) should have everything checked. Internal streams need only reasonable initial guesses.

Add/remove streams at the bottom. Stream names auto-increment.

### 3. Units & Flowsheet

**Left panel:** Add unit operations from the dropdown. Each opens a configuration dialog where you pick streams by name and set parameters. You can reconfigure or remove units at any time.

**Right panel:** A process flow diagram that updates whenever you add/change/remove units. Blue squares = unit operations, orange circles = streams, arrows = flow direction with stream names as labels.

### 4. Solve

Set max iterations and tolerance, then click **Solve**. The tab shows:

- **DOF indicator:** Green if square (unknowns = equations), amber if under-constrained, red if over-constrained.
- **Convergence plot:** Log-scale residual norm vs iteration, with tolerance line shown. This is your main diagnostic — a healthy solve shows a smooth drop to below the tolerance line.
- **Solver log:** Full text output from the solver.

### 5. Results

Complete stream table with all solved values: names, n_dot, T, P, and mole fractions.

You can also run a **local stability diagnostic** from this tab:
- **Update Stability** computes a local Jacobian-based pole proxy (`dx/dt = -r(x)`), then overlays pole locations (imaginary vs real parts) on the results axes.
- Stability is summarized using `max(Re(pole))`: negative implies locally stable; positive implies locally unstable.
- Optional **stability sweep** lets you vary a key unit parameter (`conversion`, `beta`, or `phi`) and plot `max(Re(pole))` vs that parameter to see how stability margin shifts.

### 6. Sensitivity

Sweep any unit parameter or stream property across a range and see how an output changes:

1. Pick what to sweep (reactor conversion, purge beta, separator phi, stream n_dot/T/P)
2. Pick the target unit or stream
3. Set min, max, and number of points
4. Pick which output stream and field to monitor
5. Click **Run Sensitivity**

The app re-solves the entire flowsheet for each point and plots the result. Points that fail to converge show as gaps.

---


## Available Unit Operations

- Material/path units: `Link`, `Mixer`, `Splitter`, `Separator`, `Purge`, `Recycle`, `Bypass`, `Manifold`, `Reactor`
- Specification / solver-control blocks: `Source`, `Sink`, `DesignSpec`, `Adjust`, `Calculator`, `Constraint`

### Hidden Solver Debug Logging

Solver debug output is **off by default**. You can enable it only from code or environment variables:

```matlab
solver = proc.ProcessSolver(streams, units);
solver.debugLevel = 2;   % 0=off, 1=iter summary, 2=+top residuals at exit, 3=+periodic top residuals
solver.debugTopN = 10;
solver.debugEvery = 0;   % 0 = only at exit
solver.solve();
```

Or set an environment variable before launching MATLAB:

```bash
export MATHLAB_DEBUG=2
```

`MATHLAB_DEBUG` raises the active debug level without changing call sites, and can be combined with solver settings.

---

## Key Concepts

### Known vs Unknown
Every stream variable is either **known** (fixed input) or **unknown** (solved). Feed streams should be fully known. The solver uses Levenberg-Marquardt with finite-difference Jacobians, log-transformed flow rates, and softmax-transformed compositions.

### DOF (Degrees of Freedom)
Aim for unknowns = equations. Under-constrained means you need more specifications. The solver may still work when slightly non-square (LM is least-squares), but square is ideal.

### Reactions
Defined by species indices, stoichiometric coefficients, and a single-pass conversion:
- **Reactant indices**: consumed species (1-indexed)
- **Product indices**: produced species
- **Stoich vector**: negative for reactants, positive for products, length = number of species
- **Conversion**: fraction of limiting reactant consumed (0 to 1)

Example: `2H₂ + O₂ → 2H₂O` with species `{H2, O2, H2O}`:
reactants = `[1 2]`, products = `[3]`, stoich = `[-2 -1 2]`

Mass-only reactor variants are also available:
- `StoichiometricReactor` (extent-based: `n_out = n_in + nu*xi`)
- `ConversionReactor` (limiting-reactant conversion -> extent)
- `YieldReactor` (basis-reactant conversion + product yields)
- `EquilibriumReactor` (single-reaction ideal mass-action equilibrium)

---

## Adding Custom Unit Operations

Create `+proc/+units/YourUnit.m`:

```matlab
classdef YourUnit < handle
    properties
        inlet; outlet;
        % your parameters
    end
    methods
        function obj = YourUnit(inlet, outlet, ...)
            obj.inlet = inlet; obj.outlet = outlet;
        end
        function eqs = equations(obj)
            eqs = [];
            % Residuals — each should be zero when satisfied
            eqs(end+1) = obj.outlet.n_dot - obj.inlet.n_dot;
        end
        function str = describe(obj)
            str = sprintf('YourUnit: %s -> %s', string(obj.inlet.name), string(obj.outlet.name));
        end
        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end
```

For the GUI to support your custom unit, add a dialog method in MathLabApp.m and add it to the dropdown. For command-line use, just instantiate it directly and add to the flowsheet.

---


## Equation Independence Policy (`+proc/+units/*.m`)

MathLab unit equations now follow a repository-wide independence policy:

- Prefer **component molar flow balances** (`n_dot * y_i`) as the primary conserved equations for material units.
- Avoid enforcing all three at once for the same material relation: component balances, total-flow balance, and composition normalization.
- Composition normalization belongs to variable parameterization (the solver softmax map), not usually to unit residuals.
- Keep `T`/`P` equations only when they represent intentional unit physics; avoid adding duplicate pass-through constraints that are just wiring artifacts.

### Examples

- **Independent set (preferred)** for a mixer with `ns` species:
  - `ns` component balances on outlet `n_dot * y_i`
  - optional thermal/mechanical model equations (`T`, `P`) if physically intended

- **Redundant set (avoid)** for the same mixer:
  - `ns` component balances
  - plus total-flow balance
  - plus explicit `sum(y)=1` normalization residual

Because stream compositions are packed with a softmax transform in `ProcessSolver`, `sum(y)=1` is already guaranteed by construction.

## Troubleshooting

| Problem | Likely Cause / Fix |
|---------|-------------------|
| y must sum to 1 | Mole fraction guesses don't add up — normalize them |
| Initial residual NaN/Inf | A stream has zero or negative n_dot/T/P |
| Doesn't converge | Poor initial guesses — try values closer to expected solution |
| DOF not square | Need more known specs, or a missing/extra unit |
| Line search failed | The problem may be too stiff — try smaller conversion or check connections |
| Stream not found in dialog | Create the stream first on the Streams tab |

### Why results can look “weird” after adding thermal/thermo units

When a mass-only model behaves well but adding `Heater`/`Cooler`/energy-aware units causes tiny or unrealistic flows, check these first:

1. **Under-constrained model (most common).**
   Thermal units add additional unknowns (`T`, sometimes `P`) that must be closed by specs (`Tout`, `duty`, `Pout`, `dP`, etc.) and/or known flags in stream tables. If DOF is not square, the solver can still return a least-squares fit that is mathematically acceptable but physically odd.

2. **T/P values entered but not marked as known.**
   In the Streams tab, a numeric value is only an initial guess unless its checkbox is enabled in the Known Flags table.

3. **Conflicting or missing unit thermal specs.**
   Each heater/cooler must have exactly one thermal spec (`Tout` or `duty`) and at most one pressure mode (`dP`, `Pout`, or `PR`). Bad combinations can force inconsistent balances.

4. **Reaction specification inconsistent with feed composition.**
   If a reactant needed by stoichiometry is absent or nearly zero, conversion-style reactor equations can drive a near-degenerate solution and create surprising recycle behavior.

5. **Aggressive separator/purge settings creating near-singular recycle loops.**
   Very sharp split factors (phi near 0 or 1) plus strong recycle/purge can collapse some component flows to machine-level tiny values, especially when coupled with thermal constraints.

6. **Thermo property validity range mismatch.**
   If temperatures move outside correlation validity (or near limits), enthalpy differences can become unreliable and destabilize duty-based solves.

7. **Poor initial guesses for recycle temperatures.**
   Recycle loops with energy balances are more sensitive than mass-only loops; initialize recycle `T` closer to expected converged values.


## Regression Test Suite

Run the full non-GUI regression suite before pushing to `development`:

```matlab
cd('path/to/MathLab')
summary = run_regression_suite();
```

The suite lives at `run_regression_suite.m` and covers:
- end-to-end recycle-flowsheet solve + convergence checks
- config round-trip solve via `runFromConfig`
- mass-only reactor variants (`Stoichiometric`, `Conversion`, `Yield`, `Equilibrium`)
- topology blocks (`Bypass`, `Splitter`, `Manifold`, `Recycle`)
- spec/control blocks (`Source`, `Sink`, `DesignSpec`, `Adjust`, `Calculator`, `Constraint`)
