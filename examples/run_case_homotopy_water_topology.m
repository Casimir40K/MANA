%% run_case_homotopy_water_topology.m
% Demonstrates continuation/homotopy solve mode on topology:
% Mixer -> Link -> Heater -> Reactor -> Cooler -> Separator -> Purge.
%
% The homotopy solve proceeds in stages:
%   A) Set reactor conversion near 0
%   B) Ramp conversion to target
%   C) Ramp separator/purge sharpness to target values

clear; clc;

species = {'H2','O2','H2O'};
fs = proc.Flowsheet(species);

thermoLib = thermo.ThermoLibrary();
mix = thermo.IdealGasMixture(species, thermoLib);

%% Streams
S_feed   = proc.Stream('S_feed', species);
S_mixOut = proc.Stream('S_mixOut', species);
S_link   = proc.Stream('S_link', species);
S_hot    = proc.Stream('S_hot', species);
S_rxOut  = proc.Stream('S_rxOut', species);
S_cool   = proc.Stream('S_cool', species);
S_prod   = proc.Stream('S_prod', species);
S_gas    = proc.Stream('S_gas', species);
S_recy   = proc.Stream('S_recy', species);
S_purge  = proc.Stream('S_purge', species);

for s = {S_feed,S_mixOut,S_link,S_hot,S_rxOut,S_cool,S_prod,S_gas,S_recy,S_purge}
    fs.addStream(s{1});
end

%% Known feed
S_feed.setKnown('n_dot', 10);
S_feed.setKnown('T', 300);
S_feed.setKnown('P', 1e5);
S_feed.setKnown('y', [2/3 1/3 0]);

%% Initial guesses (nonlinear recycle-friendly)
S_mixOut.setGuess(14, [0.70 0.20 0.10], 330, 1e5);
S_link.setGuess(14,   [0.70 0.20 0.10], 330, 1e5);
S_hot.setGuess(14,    [0.70 0.20 0.10], 540, 1e5);
S_rxOut.setGuess(14,  [0.50 0.10 0.40], 540, 1e5);
S_cool.setGuess(14,   [0.50 0.10 0.40], 350, 1e5);
S_prod.setGuess(2,    [1e-6 1e-6 0.999998], 350, 1e5);
S_gas.setGuess(12,    [0.80 0.20 1e-6], 350, 1e5);
S_recy.setGuess(11,   [0.80 0.20 1e-6], 350, 1e5);
S_purge.setGuess(1,   [0.80 0.20 1e-6], 350, 1e5);

%% Units: Mixer -> Link -> Heater -> Reactor -> Cooler -> Separator -> Purge
uMix = proc.units.Mixer({S_feed, S_recy}, S_mixOut);
uLnk = proc.units.Link(S_mixOut, S_link);
uHtr = proc.units.Heater(S_link, S_hot, mix, 'Tout', 550);

rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "Water formation";
uRct = proc.units.Reactor(S_hot, S_rxOut, rxn, 0.85);

uClr = proc.units.Cooler(S_rxOut, S_cool, mix, 'Tout', 350);

% Target sharp separator and high recycle fraction from purge
phiSepTarget = [1e-4 1e-4 1-2e-4];
uSep = proc.units.Separator(S_cool, S_prod, S_gas, phiSepTarget);
uPrg = proc.units.Purge(S_gas, S_recy, S_purge, 0.95);

for u = {uMix,uLnk,uHtr,uRct,uClr,uSep,uPrg}
    fs.addUnit(u{1});
end

fprintf('Solving with homotopy continuation...\n');
solver = fs.solve( ...
    'mode', 'homotopy', ...
    'maxIter', 200, ...
    'tolAbs', 1e-9, ...
    'printToConsole', true, ...
    'homotopyConversionStart', 1e-3, ...
    'homotopyConversionSteps', 5, ...
    'homotopySharpnessStart', 0.5, ...
    'homotopySharpnessSteps', 4);

fprintf('\nConverged: %d\n', solver.converged);
fprintf('Final residual: %.3e\n', solver.finalResidual);

disp(fs.streamTable());
