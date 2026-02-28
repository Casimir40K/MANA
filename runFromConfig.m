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
    [resolvedDefs, aliasByOutlet] = proc.UnitFactory.resolveIdentityLinks(cfg.unitDefs);

    % --- Rebuild units ---
    units = {};
    for i = 1:numel(resolvedDefs)
        def = resolvedDefs{i};
        u = proc.UnitFactory.buildUnitFromDef(def, streams, units, cfg.speciesNames);
        if ~isempty(u)
            units{end+1} = u; %#ok
        else
            warning('Could not rebuild unit %d (%s).', i, def.type);
        end
    end

    % --- Build flowsheet ---
    fs = proc.Flowsheet(cfg.speciesNames);
    for i = 1:numel(streams), fs.addStream(streams{i}); end
    proc.UnitFactory.addStreamAliasesToFlowsheet(fs, streams, aliasByOutlet);
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
