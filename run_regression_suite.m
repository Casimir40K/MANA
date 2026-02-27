function summary = run_regression_suite(varargin)
%RUN_REGRESSION_SUITE End-to-end regression suite for MathLab.
%   SUMMARY = RUN_REGRESSION_SUITE() runs deterministic checks for
%   solver workflows and all built-in unit blocks.
%
%   SUMMARY = RUN_REGRESSION_SUITE('verbose', false) suppresses per-test logs.
%   SUMMARY = RUN_REGRESSION_SUITE('errorOnFailure', false) returns summary
%   without throwing, even when one or more tests fail.
%   Intended use before merging/upgrading MathLab:
%       summary = run_regression_suite();
%
%   The runner always executes all tests and aggregates failures.

    p = inputParser;
    p.addParameter('verbose', true, @(x)islogical(x) && isscalar(x));
    p.addParameter('errorOnFailure', true, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});
    verbose = p.Results.verbose;
    errorOnFailure = p.Results.errorOnFailure;

    tests = {
        @testSolveWaterRecycleFlowsheet
        @testRunFromConfigRoundTrip
        @testMassOnlyReactorVariants
        @testTopologyUnits
        @testSourceSinkDesignSpecAdjustCalculatorConstraint
        @testThermoShomateSpecies
        @testThermoIdealGasMixture
        @testCompressorSolve
        @testTurbineSolve
        @testHeaterCoolerSolve
        @testHeaterCoolerCompositionPassThrough
        @testHeatExchangerSolve
    };

    n = numel(tests);
    results = repmat(struct('name',"",'passed',false,'seconds',0,'message',""), n, 1);

    tSuite = tic;
    for i = 1:n
        f = tests{i};
        t0 = tic;
        try
            f();
            results(i).name = string(func2str(f));
            results(i).passed = true;
            results(i).seconds = toc(t0);
            results(i).message = "OK";
            if verbose
                fprintf('[PASS] %s (%.3fs)\n', results(i).name, results(i).seconds);
            end
        catch ME
            results(i).name = string(func2str(f));
            results(i).passed = false;
            results(i).seconds = toc(t0);
            results(i).message = string(getReport(ME, 'basic', 'hyperlinks', 'off'));
            if verbose
                fprintf('[FAIL] %s (%.3fs)\n', results(i).name, results(i).seconds);
                fprintf('%s\n', results(i).message);
            end
        end
    end

    summary = struct();
    summary.totalTests = n;
    summary.passedTests = sum([results.passed]);
    summary.failedTests = n - summary.passedTests;
    summary.totalSeconds = toc(tSuite);
    summary.results = results;
    summary.failedNames = strings(0, 1);
    summary.failedMessages = strings(0, 1);


    if summary.failedTests == 0
        if verbose
            fprintf('\nMathLab regression suite passed: %d/%d tests in %.3fs\n', ...
                summary.passedTests, summary.totalTests, summary.totalSeconds);
        end
    else
        failedIdx = find(~[results.passed]);
        summary.failedNames = string({results(failedIdx).name}).';
        summary.failedMessages = string({results(failedIdx).message}).';

        if verbose
            fprintf('\nMathLab regression suite found %d failure(s):\n', summary.failedTests);
            for j = 1:numel(failedIdx)
                r = results(failedIdx(j));
                fprintf('  - %s (%.3fs)\n', r.name, r.seconds);
            end
        end

        if errorOnFailure
            msg = sprintf('Regression suite completed with %d failure(s) out of %d test(s).', ...
                summary.failedTests, summary.totalTests);
            for j = 1:numel(failedIdx)
                r = results(failedIdx(j));
                msg = sprintf('%s\n\n- %s\n%s', msg, r.name, r.message);
            end
            error('MathLab:RegressionSuiteFailed', '%s', msg);
        end
    end
end

function testSolveWaterRecycleFlowsheet()
    species = {'H2','O2','H2O'};
    fs = proc.Flowsheet(species);

    S1 = proc.Stream("S1", species);
    S2 = proc.Stream("S2", species);
    S3 = proc.Stream("S3", species);
    S4 = proc.Stream("S4", species);
    S5 = proc.Stream("S5", species);
    S6 = proc.Stream("S6", species);
    S7 = proc.Stream("S7", species);
    Sp = proc.Stream("Sp", species);

    for s = {S1,S2,S3,S4,S5,S6,S7,Sp}
        fs.addStream(s{1});
    end

    S1.setKnown('n_dot', 10);
    S1.setKnown('T', 300);
    S1.setKnown('P', 1e5);
    S1.setKnown('y', [2/3 1/3 0]);

    S2.setGuess(12, [0.75 0.20 0.05]);
    S3.setGuess(12, [0.75 0.20 0.05]);
    S4.setGuess(12, [0.60 0.10 0.30]);
    S5.setGuess(3,  [1e-6 1e-6 0.999998]);
    S6.setGuess(2,  [0.80 0.20 1e-6]);
    S7.setGuess(2,  [0.80 0.20 1e-6]);
    Sp.setGuess(0.2,[0.80 0.20 1e-6]);

    M1  = proc.units.Mixer({S1, S7}, S2);
    L23 = proc.units.Link(S2, S3);

    rxn.reactants = [1 2];
    rxn.products  = [3];
    rxn.stoich    = [-2 -1 2];
    rxn.name      = "Water formation";
    R1 = proc.units.Reactor(S3, S4, rxn, 0.7);

    epsSplit = 1e-6;
    phiSep = [epsSplit, epsSplit, 1-epsSplit];
    Sep1 = proc.units.Separator(S4, S5, S6, phiSep);

    P1 = proc.units.Purge(S6, S7, Sp, 0.95);

    for u = {M1, L23, R1, Sep1, P1}
        fs.addUnit(u{1});
    end

    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'Water recycle case is not square: unknowns=%d equations=%d', nU, nE);

    solver = fs.solve('maxIter', 250, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(~isempty(solver.residualHistory), 'No residual history captured for water recycle solve.');
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'Water recycle did not converge to tolerance: ||r||=%.3e tol=%.3e', ...
        solver.residualHistory(end), solver.tolAbs);
end

function testRunFromConfigRoundTrip()
    cfgPath = [tempname() '.mat'];
    outDir = tempname();

    cfg = buildWaterConfigStruct();
    save(cfgPath, '-struct', 'cfg');

    [T, solver] = runFromConfig(cfgPath, 'plot', false, 'verbose', false, 'outputDir', outDir);

    assert(istable(T), 'runFromConfig did not return a table.');
    assert(height(T) == numel(cfg.streams), 'runFromConfig table row count mismatch.');
    assert(~isempty(solver.residualHistory), 'runFromConfig solver has empty residual history.');
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'runFromConfig did not converge to tolerance: ||r||=%.3e tol=%.3e', ...
        solver.residualHistory(end), solver.tolAbs);

    if isfolder(outDir)
        rmdir(outDir, 's');
    end
    if isfile(cfgPath)
        delete(cfgPath);
    end
end

function testMassOnlyReactorVariants()
    species = {'A','B','C'};

    S1_in = proc.Stream('S1_in', species);
    S1_in.n_dot = 10; S1_in.y = [0.8 0.2 0.0];
    S1_out = proc.Stream('S1_out', species);
    S1_out.n_dot = 10; S1_out.y = [0.6 0.4 0.0];
    nu1 = [-1; 1; 0];
    uStoich = proc.units.StoichiometricReactor(S1_in, S1_out, nu1, ...
        'extent', 2.0, 'extentMode', 'fixed', 'referenceSpecies', 1);
    assertNearZero(uStoich.equations(), 1e-10, 'StoichiometricReactor fixed extent failed');

    S2_in = proc.Stream('S2_in', species);
    S2_in.n_dot = 12; S2_in.y = [0.5 0.5 0.0];
    S2_out = proc.Stream('S2_out', species);
    S2_out.n_dot = 12; S2_out.y = [0.3 0.7 0.0];
    nu2 = [-1; 1; 0];
    uConv = proc.units.ConversionReactor(S2_in, S2_out, nu2, 1, 0.4, 'conversionMode', 'fixed');
    assertNearZero(uConv.equations(), 1e-10, 'ConversionReactor fixed conversion failed');

    S3_in = proc.Stream('S3_in', species);
    S3_in.n_dot = 10; S3_in.y = [0.8 0.2 0.0];
    S3_out = proc.Stream('S3_out', species);
    S3_out.n_dot = 10; S3_out.y = [0.4 0.2 0.4];
    uYield = proc.units.YieldReactor(S3_in, S3_out, 1, 0.5, 3, 1.0, 'conversionMode', 'fixed');
    assertNearZero(uYield.equations(), 1e-10, 'YieldReactor fixed conversion failed');

    S4_in = proc.Stream('S4_in', species);
    S4_in.n_dot = 10; S4_in.y = [0.5 0.5 0.0];
    S4_out = proc.Stream('S4_out', species);
    % For A <-> B with nu=[-1 +1 0], Keq=4 => yB/yA = 4
    S4_out.n_dot = 10; S4_out.y = [0.2 0.8 0.0];
    uEq = proc.units.EquilibriumReactor(S4_in, S4_out, [-1;1;0], 4.0, 'referenceSpecies', 1);
    assertNearZero(uEq.equations(), 1e-10, 'EquilibriumReactor equilibrium check failed');
end

function testTopologyUnits()
    species = {'A','B'};

    S_feed = proc.Stream('S_feed', species);
    S_feed.n_dot = 100; S_feed.y = [0.7 0.3];

    S_procIn = proc.Stream('S_procIn', species);   S_procIn.n_dot = 75; S_procIn.y = [0.7 0.3];
    S_bypass = proc.Stream('S_bypass', species);   S_bypass.n_dot = 25; S_bypass.y = [0.7 0.3];
    S_procOut = proc.Stream('S_procOut', species); S_procOut.n_dot = 60; S_procOut.y = [0.6 0.4];
    S_mixOut = proc.Stream('S_mixOut', species);   S_mixOut.n_dot = 85; S_mixOut.y = [0.6294117647 0.3705882353];

    S_split1 = proc.Stream('S_split1', species);   S_split1.n_dot = 51; S_split1.y = [0.6294117647 0.3705882353];
    S_split2 = proc.Stream('S_split2', species);   S_split2.n_dot = 34; S_split2.y = [0.6294117647 0.3705882353];

    S_hdrIn1 = proc.Stream('S_hdrIn1', species);   S_hdrIn1.n_dot = 51; S_hdrIn1.y = [0.6294117647 0.3705882353];
    S_hdrIn2 = proc.Stream('S_hdrIn2', species);   S_hdrIn2.n_dot = 34; S_hdrIn2.y = [0.6294117647 0.3705882353];
    S_hdrOut1 = proc.Stream('S_hdrOut1', species); S_hdrOut1.n_dot = 34; S_hdrOut1.y = [0.6294117647 0.3705882353];
    S_hdrOut2 = proc.Stream('S_hdrOut2', species); S_hdrOut2.n_dot = 51; S_hdrOut2.y = [0.6294117647 0.3705882353];

    S_recycleSrc = proc.Stream('S_recycleSrc', species); S_recycleSrc.n_dot = 20; S_recycleSrc.y = [0.5 0.5];
    S_tear = proc.Stream('S_tear', species);             S_tear.n_dot = 20;       S_tear.y = [0.5 0.5];

    uBypass = proc.units.Bypass(S_feed, S_procIn, S_bypass, S_procOut, S_mixOut, 0.25);
    uSplit = proc.units.Splitter(S_mixOut, {S_split1, S_split2}, 'fractions', [0.6 0.4]);
    uMan = proc.units.Manifold({S_hdrIn1, S_hdrIn2}, {S_hdrOut1, S_hdrOut2}, [2 1]);
    uRec = proc.units.Recycle(S_recycleSrc, S_tear);

    assertNearZero(uBypass.equations(), 1e-10, 'Bypass equations failed');
    assertNearZero(uSplit.equations(), 1e-10, 'Splitter equations failed');
    assertNearZero(uMan.equations(), 1e-10, 'Manifold equations failed');
    assertNearZero(uRec.equations(), 1e-10, 'Recycle equations failed');

    assert(abs(S_feed.n_dot - (S_procIn.n_dot + S_bypass.n_dot)) < 1e-10, 'Bypass split flow mismatch');
    assert(abs(S_mixOut.n_dot - (S_bypass.n_dot + S_procOut.n_dot)) < 1e-10, 'Bypass mix flow mismatch');
    assert(abs(S_mixOut.n_dot - (S_split1.n_dot + S_split2.n_dot)) < 1e-10, 'Splitter total-flow mismatch');
end

function testSourceSinkDesignSpecAdjustCalculatorConstraint()
    species = {'A','B','C'};

    s = proc.Stream('S_source', species);
    s.n_dot = 10;
    s.y = [0.2 0.3 0.5];
    s.T = 350;
    s.P = 2e5;

    srcOpts = struct();
    srcOpts.totalFlow = 10;
    srcOpts.componentFlows = [2 3 5];
    srcOpts.composition = [0.2 0.3 0.5];
    srcOpts.specifyT = true;
    srcOpts.specifyP = true;
    srcOpts.T = 350;
    srcOpts.P = 2e5;
    uSource = proc.units.Source(s, srcOpts);
    assertNearZero(uSource.equations(), 1e-10, 'Source equations failed');

    uSink = proc.units.Sink(s);
    assertNearZero(uSink.equations(), 1e-10, 'Sink equations failed');

    ds = proc.units.DesignSpec(s, 'comp_flow', 3, 2);
    assertNearZero(ds.equations(), 1e-10, 'DesignSpec equation failed');

    dsAdj = proc.units.DesignSpec(s, 'total_flow', 12);
    adj = proc.units.Adjust(dsAdj, s, 'n_dot', NaN, 1, 20);
    adj.setVariableValue(12);
    assert(abs(adj.getVariableValue() - 12) < 1e-12, 'Adjust set/get variable failed');
    assertNearZero(adj.equations(), 1e-10, 'Adjust equation failed after variable update');

    sA = proc.Stream('S_A', species); sA.n_dot = 10; sA.y = [0.4 0.3 0.3];
    sB = proc.Stream('S_B', species); sB.n_dot = 4;  sB.y = [0.2 0.5 0.3];
    sC = proc.Stream('S_C', species); sC.n_dot = 14; sC.y = [0.3 0.36 0.34];

    calc = proc.units.Calculator(sC, 'n_dot', sA, 'n_dot', '+', sB, 'n_dot');
    assertNearZero(calc.equations(), 1e-10, 'Calculator equation failed');

    con = proc.units.Constraint(s, 'P', 2e5);
    assertNearZero(con.equations(), 1e-10, 'Constraint equation failed');
end

function cfg = buildWaterConfigStruct()
    cfg.speciesNames = {'H2', 'O2', 'H2O'};
    cfg.speciesMW = [2.016, 32.00, 18.015];

    streamDefs = {
        'S1',  10,   300, 1e5, [0.80 0.20 0.00],  true,  true,  true,  true;
        'S2',  12,   300, 1e5, [0.75 0.20 0.05],  false, false, false, false;
        'S3',  12,   300, 1e5, [0.75 0.20 0.05],  false, false, false, false;
        'S4',  12,   300, 1e5, [0.60 0.10 0.30],  false, false, false, false;
        'S5',  3,    300, 1e5, [1e-6 1e-6 0.999998], false, false, false, false;
        'S6',  2,    300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
        'S7',  2,    300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
        'Sp',  0.2,  300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
    };

    for i = 1:size(streamDefs, 1)
        sd.name = streamDefs{i, 1};
        sd.n_dot = streamDefs{i, 2};
        sd.T = streamDefs{i, 3};
        sd.P = streamDefs{i, 4};
        sd.y = streamDefs{i, 5};
        sd.known_n_dot = streamDefs{i, 6};
        sd.known_T = streamDefs{i, 7};
        sd.known_P = streamDefs{i, 8};
        sd.known_y = streamDefs{i, 9};
        if sd.known_y
            sd.known_y = true(1, numel(cfg.speciesNames));
        else
            sd.known_y = false(1, numel(cfg.speciesNames));
        end
        cfg.streams(i) = sd; %#ok<AGROW>
    end

    def1.type = 'Mixer';
    def1.inlets = {'S1', 'S7'};
    def1.outlet = 'S2';

    def2.type = 'Link';
    def2.inlet = 'S2';
    def2.outlet = 'S3';

    def3.type = 'Reactor';
    def3.inlet = 'S3';
    def3.outlet = 'S4';
    def3.conversion = 0.7;
    rxn.reactants = [1 2];
    rxn.products = [3];
    rxn.stoich = [-2 -1 2];
    rxn.name = "Water formation";
    def3.reactions = rxn;

    def4.type = 'Separator';
    def4.inlet = 'S4';
    def4.outletA = 'S5';
    def4.outletB = 'S6';
    e = 1e-6;
    def4.phi = [e, e, 1-e];

    def5.type = 'Purge';
    def5.inlet = 'S6';
    def5.recycle = 'S7';
    def5.purge = 'Sp';
    def5.beta = 0.95;

    cfg.unitDefs = {def1, def2, def3, def4, def5};
    cfg.maxIter = 250;
    cfg.tolAbs = 1e-9;
end

function assertNearZero(values, tol, msg)
    maxAbs = max(abs(values(:)));
    assert(maxAbs < tol, '%s (max|res|=%.3e, tol=%.3e)', msg, maxAbs, tol);
end

% =========================================================================
% THERMODYNAMICS TESTS
% =========================================================================

function testThermoShomateSpecies()
    lib = proc.thermo.ThermoLibrary();

    % --- N2 at 500 K: cp should be ~29.1 J/(mol*K) = 29.1 kJ/(kmol*K) ---
    n2 = lib.get('N2');
    cp500 = n2.cp_molar(500);
    assert(abs(cp500 - 29.13) < 0.5, ...
        'N2 cp(500K) expected ~29.1, got %.2f', cp500);

    % --- N2 sensible enthalpy at 298.15 K should be ~0 ---
    h298 = n2.h_sensible(298.15);
    assert(abs(h298) < 0.1, 'N2 h_sensible(298.15) should be ~0, got %.4f', h298);

    % --- N2 sensible enthalpy at 1000 K: ~21.46 kJ/mol = 21460 kJ/kmol ---
    h1000 = n2.h_sensible(1000);
    assert(abs(h1000 - 21460) < 300, ...
        'N2 h_sensible(1000K) expected ~21460, got %.1f', h1000);

    % --- Ar cp should be ~20.786 (monatomic, 5/2 R) ---
    ar = lib.get('Ar');
    cpAr = ar.cp_molar(500);
    assert(abs(cpAr - 20.786) < 0.1, ...
        'Ar cp(500K) expected ~20.786, got %.3f', cpAr);

    % --- H2O(g) formation enthalpy ---
    h2o = lib.get('H2O');
    assert(abs(h2o.Hf298_kJkmol - (-241826)) < 100, ...
        'H2O Hf298 expected ~-241826, got %.1f', h2o.Hf298_kJkmol);

    % --- CO2 at 1000 K: cp ~54.3 J/(mol*K) ---
    co2 = lib.get('CO2');
    cpCO2 = co2.cp_molar(1000);
    assert(abs(cpCO2 - 54.3) < 1.0, ...
        'CO2 cp(1000K) expected ~54.3, got %.2f', cpCO2);
end

function testThermoIdealGasMixture()
    lib = proc.thermo.ThermoLibrary();
    species = {'N2', 'O2'};
    mix = proc.thermo.IdealGasMixture(species, lib);

    z = [0.79, 0.21];  % air-like

    % cp of air at 300 K: ~29.1 kJ/(kmol*K)
    cpAir = mix.cp_mix(300, z);
    assert(cpAir > 28 && cpAir < 31, ...
        'Air cp(300K) expected ~29, got %.2f', cpAir);

    % Sensible enthalpy at Tref should be ~0
    h298 = mix.h_mix_sensible(298.15, z);
    assert(abs(h298) < 0.5, 'Air h(298.15) should be ~0, got %.4f', h298);

    % gamma of air at 300 K: ~1.4
    gam = mix.gamma_mix(300, z);
    assert(abs(gam - 1.4) < 0.02, ...
        'Air gamma(300K) expected ~1.4, got %.3f', gam);

    % MW of air: ~28.85
    mw = mix.MW_mix(z);
    assert(abs(mw - 28.85) < 0.2, ...
        'Air MW expected ~28.85, got %.2f', mw);

    % Entropy increases with temperature at constant P
    s300 = mix.s_mix(300, 1e5, z);
    s500 = mix.s_mix(500, 1e5, z);
    assert(s500 > s300, 'Entropy should increase with T');

    % Entropy decreases with pressure at constant T
    s1bar = mix.s_mix(300, 1e5, z);
    s10bar = mix.s_mix(300, 1e6, z);
    assert(s1bar > s10bar, 'Entropy should decrease with P');

    % Inverse solver: T from h
    h_target = mix.h_mix_sensible(800, z);
    T_solved = mix.solveT_from_h(h_target, z, 500);
    assert(abs(T_solved - 800) < 0.1, ...
        'solveT_from_h: expected 800, got %.2f', T_solved);

    % Inverse solver: T from s (isentropic)
    s_target = mix.s_mix(500, 1e5, z);
    T_isen = mix.solveT_isentropic(s_target, 2e5, z, 500);
    % At 2x pressure, isentropic T should be > 500
    assert(T_isen > 500, 'Isentropic compression should raise T');
    % Check the entropy actually matches
    s_check = mix.s_mix(T_isen, 2e5, z);
    assert(abs(s_check - s_target) < 1e-6, ...
        'solveT_isentropic entropy mismatch: %.6e', abs(s_check - s_target));
end

function testCompressorSolve()
    lib = proc.thermo.ThermoLibrary();
    species = {'N2', 'O2'};
    mix = proc.thermo.IdealGasMixture(species, lib);

    fs = proc.Flowsheet(species);

    % Inlet: fully specified
    S1 = proc.Stream('S1', species);
    S1.setKnown('n_dot', 1.0);
    S1.setKnown('T', 300);
    S1.setKnown('P', 1e5);
    S1.setKnown('y', [0.79, 0.21]);

    % Outlet: only guesses, everything unknown (solver finds n_dot, y, T, P)
    S2 = proc.Stream('S2', species);
    S2.setGuess(1.0, [0.79 0.21], 450, 3e5);

    fs.addStream(S1);
    fs.addStream(S2);

    comp = proc.units.Compressor(S1, S2, mix, 'Pout', 3e5, 'eta', 0.85);
    fs.addUnit(comp);

    % DOF: S1 has 0 unknowns. S2 has n_dot(1) + y(ns-1=1) + T(1) + P(1) = 4.
    % Compressor gives ns+2 = 4 equations. Square!
    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'Compressor DOF not square: %d unknowns, %d eqs', nU, nE);

    solver = fs.solve('maxIter', 100, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'Compressor did not converge: ||r||=%.3e', solver.residualHistory(end));

    % Check outlet pressure
    assert(abs(S2.P - 3e5) < 1, 'Outlet P should be 3e5, got %.1f', S2.P);

    % Outlet T should be > inlet T (compression heats gas)
    assert(S2.T > S1.T, 'Compressor outlet T should be > inlet T');

    % Composition should be preserved (pass-through)
    assert(abs(S2.y(1) - 0.79) < 1e-3, 'Compressor should preserve y(1)');
    assert(abs(S2.y(2) - 0.21) < 1e-3, 'Compressor should preserve y(2)');

    % Rough check: for ideal gas with k~1.4, T2s/T1 = (P2/P1)^((k-1)/k)
    k = mix.gamma_mix(300, [0.79 0.21]);
    T2s_approx = 300 * (3)^((k-1)/k);
    T2_approx = 300 + (T2s_approx - 300) / 0.85;
    assert(abs(S2.T - T2_approx) < 5, ...
        'Compressor T2 expected ~%.1f, got %.1f', T2_approx, S2.T);

    % Power check
    W = comp.getPower();
    assert(W > 0, 'Compressor power should be positive (consumed)');
end

function testTurbineSolve()
    lib = proc.thermo.ThermoLibrary();
    species = {'N2', 'O2'};
    mix = proc.thermo.IdealGasMixture(species, lib);

    fs = proc.Flowsheet(species);

    S1 = proc.Stream('S1', species);
    S1.setKnown('n_dot', 1.0);
    S1.setKnown('T', 800);
    S1.setKnown('P', 5e5);
    S1.setKnown('y', [0.79, 0.21]);

    S2 = proc.Stream('S2', species);
    S2.setGuess(1.0, [0.79 0.21], 600, 1e5);

    fs.addStream(S1);
    fs.addStream(S2);

    turb = proc.units.Turbine(S1, S2, mix, 'Pout', 1e5, 'eta', 0.90);
    fs.addUnit(turb);

    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'Turbine DOF not square: %d unknowns, %d eqs', nU, nE);

    solver = fs.solve('maxIter', 100, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'Turbine did not converge: ||r||=%.3e', solver.residualHistory(end));

    assert(abs(S2.P - 1e5) < 1, 'Turbine outlet P should be 1e5');
    assert(S2.T < S1.T, 'Turbine outlet T should be < inlet T');

    W = turb.getPower();
    assert(W > 0, 'Turbine power should be positive (produced)');
end

function testHeaterCoolerSolve()
    lib = proc.thermo.ThermoLibrary();
    species = {'N2', 'O2'};
    mix = proc.thermo.IdealGasMixture(species, lib);

    % --- Heater with specified Tout ---
    fs = proc.Flowsheet(species);

    S1 = proc.Stream('S1', species);
    S1.setKnown('n_dot', 2.0);
    S1.setKnown('T', 300);
    S1.setKnown('P', 1e5);
    S1.setKnown('y', [0.79, 0.21]);

    S2 = proc.Stream('S2', species);
    S2.setGuess(2.0, [0.79 0.21], 500, 1e5);

    fs.addStream(S1); fs.addStream(S2);
    heater = proc.units.Heater(S1, S2, mix, 'Tout', 500);
    fs.addUnit(heater);

    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'Heater DOF not square: %d unknowns, %d eqs', nU, nE);

    solver = fs.solve('maxIter', 60, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'Heater did not converge: ||r||=%.3e', solver.residualHistory(end));
    assert(abs(S2.T - 500) < 0.01, 'Heater Tout should be 500');
    assert(abs(S2.P - 1e5) < 1, 'Heater should preserve P');

    Q_heater = heater.getDuty();
    assert(Q_heater > 0, 'Heater duty should be positive');

    % --- Cooler with specified duty (negative Q) ---
    fs2 = proc.Flowsheet(species);

    S3 = proc.Stream('S3', species);
    S3.setKnown('n_dot', 2.0);
    S3.setKnown('T', 500);
    S3.setKnown('P', 1e5);
    S3.setKnown('y', [0.79, 0.21]);

    S4 = proc.Stream('S4', species);
    S4.setGuess(2.0, [0.79 0.21], 400, 1e5);

    fs2.addStream(S3); fs2.addStream(S4);
    cooler = proc.units.Cooler(S3, S4, mix, 'duty', -Q_heater);
    fs2.addUnit(cooler);

    solver2 = fs2.solve('maxIter', 60, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solver2.residualHistory(end) < solver2.tolAbs, ...
        'Cooler did not converge: ||r||=%.3e', solver2.residualHistory(end));

    % Cooler with same magnitude duty should bring T back to ~300 K
    assert(abs(S4.T - 300) < 1.0, ...
        'Cooler with reversed heater duty should give T~300, got %.1f', S4.T);
end


function testHeaterCoolerCompositionPassThrough()
    lib = thermo.ThermoLibrary();
    species = {'N2', 'O2', 'Ar'};
    mix = thermo.IdealGasMixture(species, lib);

    y_ref = [0.65, 0.25, 0.10];

    % Heater pass-through with multi-species composition
    fsH = proc.Flowsheet(species);
    Sh_in = proc.Stream('Sh_in', species);
    Sh_in.setKnown('n_dot', 1.5);
    Sh_in.setKnown('T', 320);
    Sh_in.setKnown('P', 1.2e5);
    Sh_in.setKnown('y', y_ref);

    Sh_out = proc.Stream('Sh_out', species);
    Sh_out.setGuess(1.5, [0.45 0.35 0.20], 450, 1.2e5);

    fsH.addStream(Sh_in); fsH.addStream(Sh_out);
    heater = proc.units.Heater(Sh_in, Sh_out, mix, 'Tout', 450);
    fsH.addUnit(heater);

    solverH = fsH.solve('maxIter', 80, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solverH.residualHistory(end) < solverH.tolAbs, ...
        'Heater composition pass-through case did not converge: ||r||=%.3e', solverH.residualHistory(end));

    assert(max(abs(Sh_out.y - y_ref)) < 1e-10, ...
        'Heater should preserve each species composition.');
    assert(abs(Sh_out.n_dot - Sh_in.n_dot) < 1e-10, ...
        'Heater should preserve molar flow.');

    % Cooler pass-through with multi-species composition and duty spec
    fsC = proc.Flowsheet(species);
    Sc_in = proc.Stream('Sc_in', species);
    Sc_in.setKnown('n_dot', 1.5);
    Sc_in.setKnown('T', 450);
    Sc_in.setKnown('P', 1.2e5);
    Sc_in.setKnown('y', y_ref);

    Sc_out = proc.Stream('Sc_out', species);
    Sc_out.setGuess(1.5, [0.30 0.30 0.40], 360, 1.2e5);

    fsC.addStream(Sc_in); fsC.addStream(Sc_out);
    Q_heater = heater.getDuty();
    cooler = proc.units.Cooler(Sc_in, Sc_out, mix, 'duty', -Q_heater);
    fsC.addUnit(cooler);

    solverC = fsC.solve('maxIter', 80, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solverC.residualHistory(end) < solverC.tolAbs, ...
        'Cooler composition pass-through case did not converge: ||r||=%.3e', solverC.residualHistory(end));

    assert(max(abs(Sc_out.y - y_ref)) < 1e-10, ...
        'Cooler should preserve each species composition.');
    assert(abs(Sc_out.n_dot - Sc_in.n_dot) < 1e-10, ...
        'Cooler should preserve molar flow.');
end

function testHeatExchangerSolve()
    lib = proc.thermo.ThermoLibrary();
    species = {'N2', 'O2'};
    mix = proc.thermo.IdealGasMixture(species, lib);

    fs = proc.Flowsheet(species);

    % Hot side: 800 K -> cool down
    Sh_in = proc.Stream('Sh_in', species);
    Sh_in.setKnown('n_dot', 1.0);
    Sh_in.setKnown('T', 800);
    Sh_in.setKnown('P', 1e5);
    Sh_in.setKnown('y', [0.79, 0.21]);

    Sh_out = proc.Stream('Sh_out', species);
    Sh_out.setGuess(1.0, [0.79 0.21], 500, 1e5);

    % Cold side: 300 K -> heat up
    Sc_in = proc.Stream('Sc_in', species);
    Sc_in.setKnown('n_dot', 1.5);
    Sc_in.setKnown('T', 300);
    Sc_in.setKnown('P', 2e5);
    Sc_in.setKnown('y', [0.79, 0.21]);

    Sc_out = proc.Stream('Sc_out', species);
    Sc_out.setGuess(1.5, [0.79 0.21], 500, 2e5);

    fs.addStream(Sh_in); fs.addStream(Sh_out);
    fs.addStream(Sc_in); fs.addStream(Sc_out);

    % DOF: Sh_in, Sc_in fully known (0+0 unknowns).
    % Sh_out: n_dot(1) + y(1) + T(1) + P(1) = 4.
    % Sc_out: n_dot(1) + y(1) + T(1) + P(1) = 4.
    % Total unknowns = 8. HX gives 2*ns+4 = 2*2+4 = 8 equations. Square!
    hx = proc.units.HeatExchanger(Sh_in, Sh_out, Sc_in, Sc_out, mix, ...
        'Th_out', 500);
    fs.addUnit(hx);

    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'HX DOF not square: %d unknowns, %d eqs', nU, nE);

    solver = fs.solve('maxIter', 100, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'HX did not converge: ||r||=%.3e', solver.residualHistory(end));

    assert(abs(Sh_out.T - 500) < 0.1, 'HX hot outlet should be 500 K');
    assert(abs(Sh_out.P - 1e5) < 1, 'HX hot side P should be preserved');
    assert(abs(Sc_out.P - 2e5) < 1, 'HX cold side P should be preserved');
    assert(Sc_out.T > 300, 'HX cold outlet should be heated');

    % Energy balance check: Q_hot = Q_cold
    z = [0.79, 0.21];
    h_h_in  = mix.h_mix_sensible(Sh_in.T,  z);
    h_h_out = mix.h_mix_sensible(Sh_out.T, z);
    h_c_in  = mix.h_mix_sensible(Sc_in.T,  z);
    h_c_out = mix.h_mix_sensible(Sc_out.T, z);
    Q_hot  = Sh_in.n_dot  * (h_h_in - h_h_out);
    Q_cold = Sc_in.n_dot * (h_c_out - h_c_in);
    assert(abs(Q_hot - Q_cold) < 1e-4, ...
        'HX energy balance violated: Q_hot=%.4f, Q_cold=%.4f', Q_hot, Q_cold);
end
