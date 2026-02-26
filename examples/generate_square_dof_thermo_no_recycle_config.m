%% generate_square_dof_thermo_no_recycle_config.m
% Creates a GUI-loadable .mat config (same style as generate_test_config.m)
% for a square-DOF thermo-enabled baseline with no recycle loop.
%
% Output:
%   square_dof_thermo_no_recycle_config.mat
%
% Usage:
%   app = MathLabApp('square_dof_thermo_no_recycle_config.mat');
%   [T, solver] = runFromConfig('square_dof_thermo_no_recycle_config.mat');

clear; clc;

outFile = 'square_dof_thermo_no_recycle_config.mat';
fprintf('Generating test config: %s\n', outFile);

% === Species ===
cfg.speciesNames = {'H2', 'O2', 'H2O'};
cfg.speciesMW    = [2.016, 32.00, 18.015];
cfg.projectTitle = 'Square DOF Thermo Baseline (No Recycle)';

% === Streams ===
streamDefs = {
% name  n_dot  T      P      y                       kn_n  kn_T  kn_P  kn_y
  'S1', 10.0,  300.0, 1e5, [0.80 0.20 0.00],        true, true, true, true;
  'S2', 10.0,  300.0, 1e5, [0.80 0.20 1e-12],       false,false,false,false;
  'Sh', 9.5,   480.0, 1e5, [0.78 0.19 0.03],        false,false,false,false;
  'S4', 9.0,   520.0, 1e5, [0.70 0.10 0.20],        false,false,false,false;
  'Sc', 9.0,   320.0, 1e5, [0.65 0.08 0.27],        false,false,false,false;
};

for i = 1:size(streamDefs,1)
    sd.name        = streamDefs{i,1};
    sd.n_dot       = streamDefs{i,2};
    sd.T           = streamDefs{i,3};
    sd.P           = streamDefs{i,4};
    sd.y           = streamDefs{i,5};
    sd.known_n_dot = streamDefs{i,6};
    sd.known_T     = streamDefs{i,7};
    sd.known_P     = streamDefs{i,8};
    if streamDefs{i,9}
        sd.known_y = true(1, numel(cfg.speciesNames));
    else
        sd.known_y = false(1, numel(cfg.speciesNames));
    end
    cfg.streams(i) = sd; %#ok<SAGROW>
end

% === Unit definitions ===
def1.type = 'Link';
def1.inlet = 'S1';
def1.outlet = 'S2';
% IMPORTANT: mark as non-identity so MathLabApp keeps Link equations in DOF.
def1.mode = 'material';
def1.isIdentity = false;

def2.type = 'Heater';
def2.inlet = 'S2';
def2.outlet = 'Sh';
def2.Tout = 500.0;

def3.type = 'Reactor';
def3.inlet = 'Sh';
def3.outlet = 'S4';
def3.conversion = 0.30;
rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "H2 oxidation";
def3.reactions = rxn;

def4.type = 'Cooler';
def4.inlet = 'S4';
def4.outlet = 'Sc';
def4.Tout = 320.0;

cfg.unitDefs = {def1, def2, def3, def4};

% === Solver settings ===
cfg.maxIter = 200;
cfg.tolAbs  = 1e-9;

save(outFile, '-struct', 'cfg');
fprintf('Saved: %s\n', outFile);
fprintf('To load in GUI: app = MathLabApp(''%s'');\n', outFile);
fprintf('To solve headlessly: [T, solver] = runFromConfig(''%s'');\n', outFile);
