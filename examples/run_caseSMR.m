%% generate_smr_ccs_test_config.m
% Build a screening-level SMR + CCS test configuration from the provided
% PFD layout and project presentation assumptions.
%
% Design/spec assumptions encoded here:
%   - H2 product target: 100,000 Nm^3/h (~4,464 kmol/h at NTP)
%   - H2 purity target: >= 99 mol%%
%   - CO2 capture target: >= 90%% overall (implemented with staged fixed splits)
%   - CO2 export pressure: 110 bar(a)
%   - Feed basis: NG represented as methane-equivalent + inert trace
%   - Reformer pressure: 25 bar
%   - Steam-to-carbon ratio: S/C = 2.35
%   - SMR CH4 conversion: 80%%
%   - Two WGS stages with 75%% CO conversion each
%   - PSA/CO2 stages represented by fixed split factors with impurity slip
%
% Notes:
%   - This is intentionally a test config with semi-randomized initial guesses
%     on intermediate streams to support solver initialization studies.
%   - It is not a rigorously heat-integrated plant model.

clear; clc;

outFile = 'smr_ccs_pfd_test_config.mat';
fprintf('Generating test config: %s\n', outFile);

%% Species
% NOTE:
%   Use CH4 (not CH4eq) so thermo-dependent units in MathLabApp can
%   instantiate their mixture model when this config is loaded in the GUI.
cfg.speciesNames = {'CH4','CO','CO2','H2O','H2','N2'};
cfg.speciesMW    = [16.04, 28.01, 44.01, 18.015, 2.016, 28.014];

ix.CH4 = 1; ix.CO = 2; ix.CO2 = 3; ix.H2O = 4; ix.H2 = 5; ix.N2 = 6;
ns = numel(cfg.speciesNames);

%% Feed + utility basis from assumptions
% H2 target at NTP ~ 100000/22.414 = 4461.5 kmol/h; design near this scale.
nCH4eq_feed = 1900;              % kmol/h methane-equivalent basis
sToC = 2.35;                     % steam-to-carbon
nSteam = sToC * nCH4eq_feed;     % kmol/h boiler steam addition

% Ambient inlet, reformer pressure basis.
Tamb = 298.15;                   % K
Pin  = 10e5;                     % Pa
Preformer = 25e5;                % Pa

%% Stream definitions (semi-random initial guesses for unspecified internals)
% Columns:
% name, n_dot, T(K), P(Pa), y(1xns), known_n, known_T, known_P, known_y_all
streamDefs = {
    'S01_NG_feed',           nCH4eq_feed/0.97, Tamb,      Pin,      [0.97 0.00 0.00 0.00 0.00 0.03], true,  true,  true,  true;
    'S02_desulfurized',      1960,             302,       9.8e5,    [0.965 0.003 0.0005 0.001 0.0005 0.03], false, false, false, false;
    'S03_compressed_NG',     1960,             315,       Preformer, [0.965 0.003 0.0005 0.001 0.0005 0.03], false, false, false, false;
    'S04_steam_feed',        nSteam,           673.15,    Preformer, [0 0 0 1 0 0], true,  true,  true,  true;
    'S05_mixed_to_reformer', 6400,             760,       24.8e5,   [0.30 0.01 0.005 0.66 0.01 0.015], false, false, false, false;
    'S06_heated_reformer_in',6400,             1120,      24.6e5,   [0.30 0.01 0.005 0.66 0.01 0.015], false, false, false, false;
    'S07_reformer_out',      6400,             1140,      24.0e5,   [0.08 0.21 0.02 0.30 0.37 0.02], false, false, false, false;
    'S08_cooled_to_HTS',     6400,             690,       23.8e5,   [0.08 0.21 0.02 0.30 0.37 0.02], false, false, false, false;
    'S09_HTS_out',           6400,             670,       23.5e5,   [0.08 0.05 0.18 0.14 0.53 0.02], false, false, false, false;
    'S10_cooled_to_LTS',     6400,             520,       23.2e5,   [0.08 0.05 0.18 0.14 0.53 0.02], false, false, false, false;
    'S11_LTS_out',           6400,             500,       22.9e5,   [0.08 0.012 0.22 0.10 0.568 0.02], false, false, false, false;
    'S12_flash_in',          6400,             320,       22.6e5,   [0.08 0.012 0.22 0.10 0.568 0.02], false, false, false, false;
    'S13_flash_gas',         5600,             315,       22.4e5,   [0.09 0.013 0.25 0.01 0.617 0.02], false, false, false, false;
    'S14_flash_condensate',   800,             315,       22.4e5,   [0.005 0.002 0.02 0.97 0.002 0.001], false, false, false, false;
    'S15_psa_feed',          5600,             313,       21.8e5,   [0.09 0.013 0.25 0.01 0.617 0.02], false, false, false, false;
    'S16_H2_product',        4550,             308,       20.8e5,   [0.004 0.002 0.003 0.001 0.988 0.002], false, false, false, false;
    'S17_psa_offgas',        1050,             308,       20.8e5,   [0.46 0.06 0.40 0.03 0.03 0.02], false, false, false, false;
    'S18_CO2_rich_stage1',    840,             305,       20.5e5,   [0.03 0.01 0.93 0.02 0.005 0.005], false, false, false, false;
    'S19_tailgas_stage1',     210,             305,       20.5e5,   [0.58 0.15 0.08 0.05 0.11 0.03], false, false, false, false;
    'S20_CO2_export',         840,             318,       110e5,    [0.03 0.01 0.93 0.02 0.005 0.005], false, false, false, false;
};

% --- FIX: preallocate cfg.streams with consistent fields ---
sdTemplate = struct( ...
    'name',        '', ...
    'n_dot',       NaN, ...
    'T',           NaN, ...
    'P',           NaN, ...
    'y',           zeros(1, ns), ...
    'known_n_dot', false, ...
    'known_T',     false, ...
    'known_P',     false, ...
    'known_y',     false(1, ns) ...
);

cfg.streams = repmat(sdTemplate, size(streamDefs,1), 1);

for i = 1:size(streamDefs, 1)
    sd = sdTemplate;  % ensures identical fields every iteration

    sd.name        = streamDefs{i,1};
    sd.n_dot       = streamDefs{i,2};
    sd.T           = streamDefs{i,3};
    sd.P           = streamDefs{i,4};

    y = streamDefs{i,5};
    y = y ./ sum(y);
    sd.y           = y;

    sd.known_n_dot = streamDefs{i,6};
    sd.known_T     = streamDefs{i,7};
    sd.known_P     = streamDefs{i,8};

    if streamDefs{i,9}
        sd.known_y = true(1, ns);
    else
        sd.known_y = false(1, ns);
    end

    cfg.streams(i) = sd;
end

%% Unit definitions (mirrors high-level PFD sequence)
unitDefs = {};

% U1 Turbine/depressurization representation: inlet conditioning
u = struct();
u.type = 'Turbine';
u.inlet = 'S01_NG_feed';
u.outlet = 'S02_desulfurized';
u.Pout = 9.8e5;   % slight pressure drop placeholder
u.eta = 0.85;
unitDefs{end+1} = u;

% U2 NG compression to reformer pressure
u = struct();
u.type = 'Compressor';
u.inlet = 'S02_desulfurized';
u.outlet = 'S03_compressed_NG';
u.Pout = Preformer;
u.eta = 0.78;
unitDefs{end+1} = u;

% U3 Mix NG + steam
u = struct();
u.type = 'Mixer';
u.inlets = {'S03_compressed_NG','S04_steam_feed'};
u.outlet = 'S05_mixed_to_reformer';
unitDefs{end+1} = u;

% U4 Preheat to reformer inlet temperature
u = struct();
u.type = 'Heater';
u.inlet = 'S05_mixed_to_reformer';
u.outlet = 'S06_heated_reformer_in';
u.Tout = 1120;
unitDefs{end+1} = u;

% U5 SMR reactor: CH4 + H2O -> CO + 3H2 (X=0.80)
rxn1.reactants = [ix.CH4 ix.H2O];
rxn1.products  = [ix.CO ix.H2];
rxn1.stoich    = [-1 1 0 -1 3 0];
rxn1.name      = "SMR";

u = struct();
u.type = 'Reactor';
u.inlet = 'S06_heated_reformer_in';
u.outlet = 'S07_reformer_out';
u.conversion = 0.80;
u.reactions = rxn1;
unitDefs{end+1} = u;

% U6 Cool to HTS
u = struct();
u.type = 'Cooler';
u.inlet = 'S07_reformer_out';
u.outlet = 'S08_cooled_to_HTS';
u.Tout = 690;
unitDefs{end+1} = u;

% U7 HTS: CO + H2O -> CO2 + H2 (X=0.75)
rxn2.reactants = [ix.CO ix.H2O];
rxn2.products  = [ix.CO2 ix.H2];
rxn2.stoich    = [0 -1 1 -1 1 0];
rxn2.name      = "WGS-HTS";

u = struct();
u.type = 'Reactor';
u.inlet = 'S08_cooled_to_HTS';
u.outlet = 'S09_HTS_out';
u.conversion = 0.75;
u.reactions = rxn2;
unitDefs{end+1} = u;

% U8 Cool to LTS
u = struct();
u.type = 'Cooler';
u.inlet = 'S09_HTS_out';
u.outlet = 'S10_cooled_to_LTS';
u.Tout = 520;
unitDefs{end+1} = u;

% U9 LTS: same reaction and conversion
rxn3 = rxn2;
rxn3.name = "WGS-LTS";

u = struct();
u.type = 'Reactor';
u.inlet = 'S10_cooled_to_LTS';
u.outlet = 'S11_LTS_out';
u.conversion = 0.75;
u.reactions = rxn3;
unitDefs{end+1} = u;

% U10 Flash feed cooler
u = struct();
u.type = 'Cooler';
u.inlet = 'S11_LTS_out';
u.outlet = 'S12_flash_in';
u.Tout = 320;
unitDefs{end+1} = u;

% U11 Flash separator: route most H2O to condensate (outletB)
phiFlashToGas = [0.995 0.995 0.995 0.05 0.995 0.995];

u = struct();
u.type = 'Separator';
u.inlet = 'S12_flash_in';
u.outletA = 'S13_flash_gas';
u.outletB = 'S14_flash_condensate';
u.phi = phiFlashToGas;
unitDefs{end+1} = u;

% U12 PSA feed trim (pressure matching)
u = struct();
u.type = 'Turbine';
u.inlet = 'S13_flash_gas';
u.outlet = 'S15_psa_feed';
u.PR = 1.03;  % mild letdown before PSA train
u.eta = 0.80;
unitDefs{end+1} = u;

% U13 H2 PSA: high H2 recovery, impurity slip ~=1%
% phi is fraction to outletA (H2 product stream)
phiPSA_H2 = [0.01 0.01 0.01 0.01 0.92 0.01];

u = struct();
u.type = 'Separator';
u.inlet = 'S15_psa_feed';
u.outletA = 'S16_H2_product';
u.outletB = 'S17_psa_offgas';
u.phi = phiPSA_H2;
unitDefs{end+1} = u;

% U14 CO2 capture stage: 79% effective CO2 removal with impurity slip
phiCO2Stage1 = [0.01 0.01 0.79 0.01 0.01 0.01];

u = struct();
u.type = 'Separator';
u.inlet = 'S17_psa_offgas';
u.outletA = 'S18_CO2_rich_stage1';
u.outletB = 'S19_tailgas_stage1';
u.phi = phiCO2Stage1;
unitDefs{end+1} = u;

% U15 CO2 export compression to 110 bar(a)
u = struct();
u.type = 'Compressor';
u.inlet = 'S18_CO2_rich_stage1';
u.outlet = 'S20_CO2_export';
u.Pout = 110e5;
u.eta = 0.75;
unitDefs{end+1} = u;

cfg.unitDefs = unitDefs;

%% Solver settings
cfg.maxIter = 250;
cfg.tolAbs  = 1e-8;


% Basic guardrails for config integrity
for i = 1:numel(cfg.streams)
    if abs(sum(cfg.streams(i).y) - 1.0) > 1e-10
        error('Stream %s has mole fractions that do not sum to one.', cfg.streams(i).name);
    end
end

save(outFile, '-struct', 'cfg');

fprintf('Saved: %s\n', outFile);
fprintf('Run with: [T, solver] = runFromConfig(''%s'', ''plot'', false);\n', outFile);
