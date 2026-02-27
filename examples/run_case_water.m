%% run_case_water.m — Water Formation Demo (command-line, no GUI)
%
%  This script demonstrates the MathLab solver on a simple recycle loop:
%    Feed(H2/O2) -> Mixer -> Link -> Heater -> Reactor(2H2+O2->2H2O)
%      -> Separator -> Purge, with 95% recycle back to the mixer.
%
%  Run from the MathLab/ folder (the one containing +proc/ and this file).

clear; clc;

species = {'H2','O2','H2O'};
fs = proc.Flowsheet(species);

% ---- Thermodynamic mixture (needed for Heater) ----
thermoLib = proc.thermo.ThermoLibrary();
mix = proc.thermo.IdealGasMixture(species, thermoLib);

% ---- Streams ----
S1 = proc.Stream("S1", species);  % fresh feed
S2 = proc.Stream("S2", species);  % mixer outlet
S3 = proc.Stream("S3", species);  % link outlet / heater inlet
Sh = proc.Stream("Sh", species);  % heater outlet / reactor inlet
S4 = proc.Stream("S4", species);  % reactor outlet
S5 = proc.Stream("S5", species);  % separator -> water product
S6 = proc.Stream("S6", species);  % separator -> gas recycle
S7 = proc.Stream("S7", species);  % purge -> recycle to mixer
Sp = proc.Stream("Sp", species);  % purge stream out

for s = {S1,S2,S3,Sh,S4,S5,S6,S7,Sp}
    fs.addStream(s{1});
end

% ---- Known feed ----
S1.setKnown('n_dot', 10);
S1.setKnown('T', 300);
S1.setKnown('P', 1e5);
S1.setKnown('y', [2/3 1/3 0]);

% ---- Initial guesses (NOT known) ----
S2.setGuess(12, [0.75 0.20 0.05]);
S3.setGuess(12, [0.75 0.20 0.05]);
Sh.setGuess(12, [0.75 0.20 0.05], 500);
S4.setGuess(12, [0.60 0.10 0.30]);
S5.setGuess(3,  [1e-6 1e-6 0.999998]);
S6.setGuess(2,  [0.80 0.20 1e-6]);
S7.setGuess(2,  [0.80 0.20 1e-6]);
Sp.setGuess(0.2,[0.80 0.20 1e-6]);

% ---- Units ----
M1  = proc.units.Mixer({S1, S7}, S2);
L23 = proc.units.Link(S2, S3);
H1  = proc.units.Heater(S3, Sh, mix, 'Tout', 500);  % preheat to 500 K

rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "Water formation";
R1 = proc.units.Reactor(Sh, S4, rxn, 0.7);

epsSplit = 1e-6;
phiSep = [epsSplit, epsSplit, 1-epsSplit];
Sep1 = proc.units.Separator(S4, S5, S6, phiSep);

P1 = proc.units.Purge(S6, S7, Sp, 0.95);

for u = {M1, L23, H1, R1, Sep1, P1}
    fs.addUnit(u{1});
end

% ---- DOF check ----
[nU, nE] = fs.checkDOF();
fprintf('DOF: unknowns=%d, equations=%d\n\n', nU, nE);

% ---- Solve ----
solver = fs.solve('maxIter', 200, 'tolAbs', 1e-9, 'verbose', true);

% ---- Results ----
fprintf('\n=== Stream Table ===\n');
T = fs.streamTable();
disp(T);
