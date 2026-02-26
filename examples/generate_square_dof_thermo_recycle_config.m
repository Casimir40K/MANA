%% generate_square_dof_thermo_recycle_config.m
% Creates a GUI-loadable .mat config (same style as generate_test_config.m)
% for the square-DOF thermo recycle topology.
%
% Output:
%   square_dof_thermo_recycle_config.mat
%
% Usage:
%   app = MathLabApp('square_dof_thermo_recycle_config.mat');
%   [T, solver] = runFromConfig('square_dof_thermo_recycle_config.mat');

clear; clc;

outFile = 'square_dof_thermo_recycle_config.mat';
fprintf('Generating test config: %s\n', outFile);

% === Species ===
cfg.speciesNames = {'H2', 'O2', 'H2O'};
cfg.speciesMW    = [2.016, 32.00, 18.015];
cfg.projectTitle = 'Square DOF Thermo Recycle';

% === Streams ===
% Guesses are chosen to be recycle-consistent (Mixer/Reactor/Separator/Purge)
% so early line-search iterations start near material-balance feasibility.
streamDefs = {
% name  n_dot       T       P      y                                  kn_n  kn_T  kn_P  kn_y
  'S1', 10.0,       300.0,  1e5, [0.80 0.20 0.00],                    true, true, true, true;
  'S2', 17.25,      300.0,  1e5, [0.821 0.175 0.004],                 false,false,false,false;
  'S3', 17.25,      300.0,  1e5, [0.821 0.175 0.004],                 false,false,false,false;
  'S4', 15.14,      500.0,  1e5, [0.657 0.060 0.283],                 false,false,false,false;
  'S5', 4.368,      278.15, 1e5, [0.165 0.027 0.808],                 false,false,false,false;
  'S6', 7.632,      278.15, 1e5, [0.849 0.142 0.009],                 false,false,false,false;
  'S7', 7.250,      278.15, 1e5, [0.849 0.142 0.009],                 false,false,false,false;
  'Sp', 0.382,      278.15, 1e5, [0.849 0.142 0.009],                 false,false,false,false;
  'Sh', 17.25,      500.0,  1e5, [0.821 0.175 0.004],                 false,false,false,false;
  'Sc', 15.14,      278.15, 1e5, [0.657 0.060 0.283],                 false,false,false,false;
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
def1.type = 'Mixer';
def1.inlets = {'S1', 'S7'};
def1.outlet = 'S2';

def2.type = 'Link';
def2.inlet = 'S2';
def2.outlet = 'S3';
% IMPORTANT: mark as non-identity so MathLabApp keeps Link equations in DOF.
def2.mode = 'material';
def2.isIdentity = false;

def3.type = 'Heater';
def3.inlet = 'S3';
def3.outlet = 'Sh';
def3.Tout = 500.0;

def4.type = 'Reactor';
def4.inlet = 'Sh';
def4.outlet = 'S4';
def4.conversion = 0.70;
rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "reaction";
def4.reactions = rxn;

def5.type = 'Cooler';
def5.inlet = 'S4';
def5.outlet = 'Sc';
def5.Tout = 278.15;

def6.type = 'Separator';
def6.inlet = 'Sc';
def6.outletA = 'S5';
def6.outletB = 'S6';
def6.phi = [0.1 0.1 0.98];

def7.type = 'Purge';
def7.inlet = 'S6';
def7.recycle = 'S7';
def7.purge = 'Sp';
def7.beta = 0.95;

cfg.unitDefs = {def1, def2, def3, def4, def5, def6, def7};

% === Solver settings ===
cfg.maxIter = 200;
cfg.tolAbs  = 1e-9;

save(outFile, '-struct', 'cfg');
fprintf('Saved: %s\n', outFile);
fprintf('To load in GUI: app = MathLabApp(''%s'');\n', outFile);
fprintf('To solve headlessly: [T, solver] = runFromConfig(''%s'');\n', outFile);
