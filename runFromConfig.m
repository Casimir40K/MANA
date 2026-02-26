function [T, solver] = runFromConfig(configFile, varargin)
%RUNFROMCONFIG  Solve a MathLab flowsheet from a saved .mat config file.
%
%   [T, solver] = runFromConfig('myconfig.mat');
%   [T, solver] = runFromConfig('myconfig.mat', 'maxIter', 500);
%   [T, solver] = runFromConfig('myconfig.mat', 'outputDir', 'results');
%
%   Loads species, streams, units from a .mat saved by MathLabApp.
%   Solves the flowsheet. Returns stream table + full solver object.
%   Saves solver output (residual history, log, stream table) to disk.
%
%   Options:
%     'maxIter'   - override max iterations
%     'tolAbs'    - override tolerance
%     'outputDir' - output folder (default: 'output')
%     'verbose'   - console printing (default: true)
%     'plot'      - show convergence plot (default: true)

    p = inputParser;
    p.addParameter('maxIter', [], @isnumeric);
    p.addParameter('tolAbs', [], @isnumeric);
    p.addParameter('outputDir', 'output', @ischar);
    p.addParameter('verbose', true, @islogical);
    p.addParameter('plot', true, @islogical);
    p.parse(varargin{:});
    opts = p.Results;

    % --- Load ---
    if ~isfile(configFile)
        error('Config file not found: %s', configFile);
    end
    cfg = load(configFile);

    fprintf('=== MathLab: runFromConfig ===\n');
    fprintf('File:    %s\n', configFile);
    fprintf('Species: {%s}\n', strjoin(cfg.speciesNames, ', '));
    fprintf('Streams: %d   Units: %d\n', numel(cfg.streams), numel(cfg.unitDefs));

    % --- Rebuild streams ---
    streams = {};
    for i = 1:numel(cfg.streams)
        sd = cfg.streams(i);
        s = proc.Stream(string(sd.name), cfg.speciesNames);
        s.n_dot = sd.n_dot; s.T = sd.T; s.P = sd.P; s.y = sd.y;
        s.known.n_dot = sd.known_n_dot;
        s.known.T     = sd.known_T;
        s.known.P     = sd.known_P;
        s.known.y     = sd.known_y;
        streams{end+1} = s; %#ok
    end

    % --- Resolve identity links as stream aliases ---
    [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(cfg.unitDefs);

    % --- Rebuild units ---
    units = {};
    for i = 1:numel(resolvedDefs)
        def = resolvedDefs{i};
        u = buildUnitFromDef(def, streams, cfg.speciesNames, units);
        if ~isempty(u)
            units{end+1} = u; %#ok
        else
            warning('Could not rebuild unit %d (%s).', i, def.type);
        end
    end

    % --- Build flowsheet ---
    fs = proc.Flowsheet(cfg.speciesNames);
    for i = 1:numel(streams), fs.addStream(streams{i}); end
    addStreamAliasesToFlowsheet(fs, aliasByOutlet, streams);
    for i = 1:numel(units),   fs.addUnit(units{i}); end

    % --- Settings ---
    maxIter = cfg.maxIter;
    tolAbs  = cfg.tolAbs;
    if ~isempty(opts.maxIter), maxIter = opts.maxIter; end
    if ~isempty(opts.tolAbs),  tolAbs  = opts.tolAbs; end

    [nU, nE] = fs.checkDOF('quiet', true);
    fprintf('DOF:     %d unknowns, %d equations', nU, nE);
    if nU == nE, fprintf(' (square)\n');
    else,        fprintf(' (mismatch = %+d)\n', nE - nU); end
    fprintf('MaxIter: %d   Tolerance: %.2e\n\n', maxIter, tolAbs);

    % --- Solve ---
    autoScale = true;
    if isfield(cfg, 'autoScale'), autoScale = cfg.autoScale; end
    solver = fs.solve('maxIter', maxIter, 'tolAbs', tolAbs, ...
        'autoScale', autoScale, ...
        'printToConsole', opts.verbose, 'consoleStride', 1);

    % --- Results ---
    T = fs.streamTable();
    fprintf('\n=== Stream Table ===\n');
    disp(T);

    % --- Save output ---
    if ~isfolder(opts.outputDir), mkdir(opts.outputDir); end

    [~, cfgName] = fileparts(configFile);
    ts = datestr(now, 'yyyymmdd_HHMMSS');

    outFile = fullfile(opts.outputDir, sprintf('%s_result_%s.mat', cfgName, ts));
    result = struct();
    result.streamTable     = T;
    result.residualHistory = solver.residualHistory;
    result.stepHistory     = solver.stepHistory;
    result.alphaHistory    = solver.alphaHistory;
    result.logLines        = solver.logLines;
    result.configFile      = configFile;
    result.timestamp       = ts;
    save(outFile, '-struct', 'result');
    fprintf('Results saved to: %s\n', outFile);

    % --- Convergence plot ---
    if opts.plot && ~isempty(solver.residualHistory)
        fig = figure('Name','MathLab Convergence','NumberTitle','off');
        rh = solver.residualHistory;
        semilogy(0:numel(rh)-1, rh, '-o', 'LineWidth',1.5, 'MarkerSize',4, ...
            'Color',[0.15 0.5 0.75]);
        hold on;
        yline(tolAbs, '--r', 'Tolerance', 'LineWidth', 1);
        hold off;
        xlabel('Iteration'); ylabel('||r||');
        title(sprintf('Convergence: %s', cfgName), 'Interpreter','none');
        grid on;

        figFile = fullfile(opts.outputDir, sprintf('%s_convergence_%s.png', cfgName, ts));
        saveas(fig, figFile);
        fprintf('Plot saved to: %s\n', figFile);
    end

    fprintf('\nDone.\n');
end

% =========================================================================
function u = buildUnitFromDef(def, streams, speciesNames, existingUnits)
    if nargin < 4, existingUnits = {}; end
    u = [];
    switch def.type
        case 'Link'
            if isIdentityLinkDef(def)
                return;
            end
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.Link(sIn, sOut);
            end
        case 'Mixer'
            inS = {};
            for k = 1:numel(def.inlets)
                s = findS(def.inlets{k}, streams);
                if isempty(s), return; end
                inS{end+1} = s; %#ok
            end
            sOut = findS(def.outlet, streams);
            if ~isempty(sOut), u = proc.units.Mixer(inS, sOut); end
        case 'Reactor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.Reactor(sIn, sOut, def.reactions, def.conversion);
            end
        case 'StoichiometricReactor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.StoichiometricReactor(sIn, sOut, def.nu, ...
                    'extent', def.extent, 'extentMode', def.extentMode, ...
                    'referenceSpecies', def.referenceSpecies);
            end
        case 'ConversionReactor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.ConversionReactor(sIn, sOut, def.nu, def.keySpecies, ...
                    def.conversion, 'conversionMode', def.conversionMode);
            end
        case 'YieldReactor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.YieldReactor(sIn, sOut, def.basisSpecies, def.conversion, ...
                    def.productSpecies, def.productYields, 'conversionMode', def.conversionMode);
            end
        case 'EquilibriumReactor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                u = proc.units.EquilibriumReactor(sIn, sOut, def.nu, def.Keq, ...
                    'referenceSpecies', def.referenceSpecies);
            end
        case 'Separator'
            sIn = findS(def.inlet, streams);
            sA = findS(def.outletA, streams);
            sB = findS(def.outletB, streams);
            if ~isempty(sIn) && ~isempty(sA) && ~isempty(sB)
                u = proc.units.Separator(sIn, sA, sB, def.phi);
            end
        case 'Purge'
            sIn = findS(def.inlet, streams);
            sRec = findS(def.recycle, streams);
            sPur = findS(def.purge, streams);
            if ~isempty(sIn) && ~isempty(sRec) && ~isempty(sPur)
                u = proc.units.Purge(sIn, sRec, sPur, def.beta);
            end
        case 'Splitter'
            sIn = findS(def.inlet, streams);
            outS = {};
            for k = 1:numel(def.outlets)
                s = findS(def.outlets{k}, streams);
                if isempty(s), return; end
                outS{end+1} = s; %#ok
            end
            if ~isempty(sIn)
                if isfield(def, 'splitFractions')
                    u = proc.units.Splitter(sIn, outS, 'fractions', def.splitFractions);
                else
                    u = proc.units.Splitter(sIn, outS, 'flows', def.specifiedOutletFlows);
                end
            end
        case 'Recycle'
            sSrc = findS(def.source, streams);
            sTear = findS(def.tear, streams);
            if ~isempty(sSrc) && ~isempty(sTear)
                u = proc.units.Recycle(sSrc, sTear);
            end
        case 'Bypass'
            sIn = findS(def.inlet, streams);
            sProcIn = findS(def.processInlet, streams);
            sByp = findS(def.bypassStream, streams);
            sRet = findS(def.processReturn, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sProcIn) && ~isempty(sByp) && ~isempty(sRet) && ~isempty(sOut)
                u = proc.units.Bypass(sIn, sProcIn, sByp, sRet, sOut, def.bypassFraction);
            end
        case 'Manifold'
            inS = {};
            for k = 1:numel(def.inlets)
                s = findS(def.inlets{k}, streams);
                if isempty(s), return; end
                inS{end+1} = s; %#ok
            end
            outS = {};
            for k = 1:numel(def.outlets)
                s = findS(def.outlets{k}, streams);
                if isempty(s), return; end
                outS{end+1} = s; %#ok
            end
            u = proc.units.Manifold(inS, outS, def.route);
        case 'Source'
            sOut = findS(def.outlet, streams);
            if ~isempty(sOut)
                opts = struct();
                if isfield(def,'totalFlow'), opts.totalFlow = def.totalFlow; end
                if isfield(def,'composition'), opts.composition = def.composition; end
                if isfield(def,'componentFlows'), opts.componentFlows = def.componentFlows; end
                u = proc.units.Source(sOut, opts);
            end
        case 'Sink'
            sIn = findS(def.inlet, streams);
            if ~isempty(sIn), u = proc.units.Sink(sIn); end
        case 'DesignSpec'
            s = findS(def.stream, streams);
            if ~isempty(s)
                u = proc.units.DesignSpec(s, def.metric, def.target, def.componentIndex);
            end
        case 'Adjust'
            if isfield(def,'designSpecIndex') && isfield(def,'ownerIndex') && ...
                    def.designSpecIndex <= numel(existingUnits) && def.ownerIndex <= numel(existingUnits)
                ds = existingUnits{def.designSpecIndex};
                owner = existingUnits{def.ownerIndex};
                u = proc.units.Adjust(ds, owner, def.field, def.index, def.minValue, def.maxValue);
            end
        case 'Calculator'
            lhs = findS(def.lhsStream, streams);
            a = findS(def.aStream, streams);
            b = findS(def.bStream, streams);
            if ~isempty(lhs) && ~isempty(a) && ~isempty(b)
                u = proc.units.Calculator(lhs, def.lhsField, a, def.aField, def.operator, b, def.bField);
            end
        case 'Constraint'
            s = findS(def.stream, streams);
            if ~isempty(s)
                u = proc.units.Constraint(s, def.field, def.value, def.index);
            end
        case 'Compressor'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                mix = buildThermoMix(speciesNames);
                args = {};
                if isfield(def,'Pout'), args = [args, {'Pout', def.Pout}]; end
                if isfield(def,'PR'), args = [args, {'PR', def.PR}]; end
                if isfield(def,'eta'), args = [args, {'eta', def.eta}]; end
                u = proc.units.Compressor(sIn, sOut, mix, args{:});
            end
        case 'Turbine'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                mix = buildThermoMix(speciesNames);
                args = {};
                if isfield(def,'Pout'), args = [args, {'Pout', def.Pout}]; end
                if isfield(def,'PR'), args = [args, {'PR', def.PR}]; end
                if isfield(def,'eta'), args = [args, {'eta', def.eta}]; end
                u = proc.units.Turbine(sIn, sOut, mix, args{:});
            end
        case 'Heater'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                mix = buildThermoMix(speciesNames);
                args = {};
                if isfield(def,'Tout'), args = [args, {'Tout', def.Tout}]; end
                if isfield(def,'duty'), args = [args, {'duty', def.duty}]; end
                u = proc.units.Heater(sIn, sOut, mix, args{:});
            end
        case 'Cooler'
            sIn = findS(def.inlet, streams);
            sOut = findS(def.outlet, streams);
            if ~isempty(sIn) && ~isempty(sOut)
                mix = buildThermoMix(speciesNames);
                args = {};
                if isfield(def,'Tout'), args = [args, {'Tout', def.Tout}]; end
                if isfield(def,'duty'), args = [args, {'duty', def.duty}]; end
                u = proc.units.Cooler(sIn, sOut, mix, args{:});
            end
        case 'HeatExchanger'
            hIn = findS(def.hotInlet, streams);
            hOut = findS(def.hotOutlet, streams);
            cIn = findS(def.coldInlet, streams);
            cOut = findS(def.coldOutlet, streams);
            if ~isempty(hIn) && ~isempty(hOut) && ~isempty(cIn) && ~isempty(cOut)
                mix = buildThermoMix(speciesNames);
                args = {};
                if isfield(def,'Th_out'), args = [args, {'Th_out', def.Th_out}]; end
                if isfield(def,'Tc_out'), args = [args, {'Tc_out', def.Tc_out}]; end
                if isfield(def,'duty'), args = [args, {'duty', def.duty}]; end
                u = proc.units.HeatExchanger(hIn, hOut, cIn, cOut, mix, args{:});
            end
    end
end

function mix = buildThermoMix(speciesNames)
    %BUILDTHERMOMIX Create IdealGasMixture from species names.
    lib = proc.thermo.ThermoLibrary();
    mix = proc.thermo.IdealGasMixture(speciesNames, lib);
end

function [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(unitDefs)
    aliasByOutlet = containers.Map('KeyType','char','ValueType','char');
    resolvedDefs = cell(size(unitDefs));
    for i = 1:numel(unitDefs)
        def = unitDefs{i};
        if ~isstruct(def)
            resolvedDefs{i} = def;
            continue;
        end
        def = rewriteDefStreams(def, aliasByOutlet);
        if strcmp(def.type, 'Link') && isIdentityLinkDef(def)
            inletRoot = resolveAliasName(def.inlet, aliasByOutlet);
            aliasByOutlet(char(def.outlet)) = inletRoot;
            continue;
        end
        resolvedDefs{i} = def;
    end
    resolvedDefs = resolvedDefs(~cellfun(@isempty, resolvedDefs));
end

function def = rewriteDefStreams(def, aliasByOutlet)
    if isfield(def, 'inlet')
        def.inlet = resolveAliasName(def.inlet, aliasByOutlet);
    end
    if isfield(def, 'source')
        def.source = resolveAliasName(def.source, aliasByOutlet);
    end
    if isfield(def, 'stream')
        def.stream = resolveAliasName(def.stream, aliasByOutlet);
    end
    if isfield(def, 'tear')
        def.tear = resolveAliasName(def.tear, aliasByOutlet);
    end
    if isfield(def, 'processInlet')
        def.processInlet = resolveAliasName(def.processInlet, aliasByOutlet);
    end
    if isfield(def, 'bypassStream')
        def.bypassStream = resolveAliasName(def.bypassStream, aliasByOutlet);
    end
    if isfield(def, 'processReturn')
        def.processReturn = resolveAliasName(def.processReturn, aliasByOutlet);
    end
    if isfield(def, 'lhsStream')
        def.lhsStream = resolveAliasName(def.lhsStream, aliasByOutlet);
    end
    if isfield(def, 'aStream')
        def.aStream = resolveAliasName(def.aStream, aliasByOutlet);
    end
    if isfield(def, 'bStream')
        def.bStream = resolveAliasName(def.bStream, aliasByOutlet);
    end
    if isfield(def, 'recycle')
        def.recycle = resolveAliasName(def.recycle, aliasByOutlet);
    end
    if isfield(def, 'purge')
        def.purge = resolveAliasName(def.purge, aliasByOutlet);
    end
    if isfield(def, 'outlet')
        if ~strcmp(def.type, 'Link') || ~isIdentityLinkDef(def)
            def.outlet = resolveAliasName(def.outlet, aliasByOutlet);
        end
    end
    if isfield(def, 'outletA')
        def.outletA = resolveAliasName(def.outletA, aliasByOutlet);
    end
    if isfield(def, 'outletB')
        def.outletB = resolveAliasName(def.outletB, aliasByOutlet);
    end
    if isfield(def, 'hotInlet')
        def.hotInlet = resolveAliasName(def.hotInlet, aliasByOutlet);
    end
    if isfield(def, 'hotOutlet')
        def.hotOutlet = resolveAliasName(def.hotOutlet, aliasByOutlet);
    end
    if isfield(def, 'coldInlet')
        def.coldInlet = resolveAliasName(def.coldInlet, aliasByOutlet);
    end
    if isfield(def, 'coldOutlet')
        def.coldOutlet = resolveAliasName(def.coldOutlet, aliasByOutlet);
    end
    if isfield(def, 'inlets')
        for k = 1:numel(def.inlets)
            def.inlets{k} = resolveAliasName(def.inlets{k}, aliasByOutlet);
        end
    end
    if isfield(def, 'outlets')
        for k = 1:numel(def.outlets)
            def.outlets{k} = resolveAliasName(def.outlets{k}, aliasByOutlet);
        end
    end
end

function addStreamAliasesToFlowsheet(fs, aliasByOutlet, streams)
    if isempty(aliasByOutlet)
        return;
    end
    keys = aliasByOutlet.keys;
    for i = 1:numel(keys)
        aliasName = keys{i};
        targetName = aliasByOutlet(aliasName);
        s = findS(targetName, streams);
        if ~isempty(s)
            fs.addAlias(aliasName, s);
        end
    end
end

function tf = isIdentityLinkDef(def)
    tf = strcmp(def.type, 'Link') && isfield(def, 'mode') && strcmp(def.mode, 'identity');
    if isfield(def, 'isIdentity')
        tf = logical(def.isIdentity);
    end
end

function outName = resolveAliasName(name, aliasByOutlet)
    outName = char(string(name));
    visited = containers.Map('KeyType','char','ValueType','logical');
    while isKey(aliasByOutlet, outName)
        if isKey(visited, outName)
            break;
        end
        visited(outName) = true;
        outName = aliasByOutlet(outName);
    end
end

function s = findS(name, streams)
    s = [];
    for i = 1:numel(streams)
        if strcmp(char(string(streams{i}.name)), char(name))
            s = streams{i}; return;
        end
    end
end
