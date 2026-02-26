classdef Flowsheet < handle
    properties
        species   % cellstr species list (global order)
        streams   % cell array of proc.Stream objects
        units     % cell array of unit objects (proc.units.*) with equations()
        streamDisplayNames % user-visible stream names for reporting (incl. aliases)
        streamDisplayRefs  % stream object handles aligned with streamDisplayNames
        hasSolveAttempted logical = false
        lastSolveConverged logical = false
    end

    methods
        function obj = Flowsheet(species)
            obj.species = species;
            obj.streams = {};
            obj.units   = {};
            obj.streamDisplayNames = {};
            obj.streamDisplayRefs  = {};
        end

        function addStream(obj, s, displayName)
            obj.streams{end+1} = s;
            if nargin < 3 || isempty(displayName)
                displayName = char(string(s.name));
            end
            obj.streamDisplayNames{end+1} = char(string(displayName));
            obj.streamDisplayRefs{end+1}  = s;
        end

        function addAlias(obj, aliasName, s)
            obj.streamDisplayNames{end+1} = char(string(aliasName));
            obj.streamDisplayRefs{end+1}  = s;
        end

        function addUnit(obj, u)
            obj.units{end+1} = u;
        end

        function [nUnknown, nEq] = checkDOF(obj, varargin)
            % checkDOF() prints by default
            % checkDOF('quiet',true) suppresses printing

            p = inputParser;
            p.addParameter('quiet', false, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            quiet = p.Results.quiet;

            nUnknown = obj.countUnknowns();
            nEq      = obj.countEquations();

            if ~quiet
                fprintf('DOF check:\n');
                fprintf('  Unknowns:  %d\n', nUnknown);
                fprintf('  Equations: %d\n', nEq);

                if nEq < nUnknown
                    fprintf('  Status: UNDER-CONSTRAINED (need %d more equations/specs)\n', nUnknown - nEq);
                elseif nEq > nUnknown
                    fprintf('  Status: OVER-CONSTRAINED (have %d extra equations)\n', nEq - nUnknown);
                else
                    fprintf('  Status: Square (unknowns == equations)\n');
                end
            end
        end

        function solver = solve(obj, varargin)
            % Usage:
            %   solver = fs.solve();
            %   solver = fs.solve('maxIter',80,'tolAbs',1e-9,'printToConsole',true,'consoleStride',10);
            %   solver = fs.solve(...,'allowNonConverged',true);

            obj.validate();  % throws if not runnable

            p = inputParser;
            p.KeepUnmatched = true;
            p.addParameter('mode', 'direct', @(x)(isstring(x)||ischar(x))&&isscalar(string(x)));
            p.addParameter('allowNonConverged', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('homotopyConversionStart', 1e-3, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
            p.addParameter('homotopyConversionSteps', 4, @(x)isnumeric(x)&&isscalar(x)&&x>=1&&mod(x,1)==0);
            p.addParameter('homotopySharpnessStart', 0.5, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
            p.addParameter('homotopySharpnessSteps', 3, @(x)isnumeric(x)&&isscalar(x)&&x>=1&&mod(x,1)==0);
            p.addParameter('homotopyLog', true, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            mode = lower(string(p.Results.mode));
            allowNonConverged = p.Results.allowNonConverged;
            homotopyConversionStart = p.Results.homotopyConversionStart;
            homotopyConversionSteps = p.Results.homotopyConversionSteps;
            homotopySharpnessStart = p.Results.homotopySharpnessStart;
            homotopySharpnessSteps = p.Results.homotopySharpnessSteps;
            homotopyLog = p.Results.homotopyLog;

            % Optional overrides: apply any name/value pair that matches a solver property
            unmatched = p.Unmatched;
            % Print DOF summary (keep this behavior for now)
            obj.checkDOF();

            if mode == "direct"
                solver = obj.runSingleSolve(unmatched);
            elseif mode == "homotopy"
                homotopyOpts = struct();
                homotopyOpts.conversionStart = homotopyConversionStart;
                homotopyOpts.conversionSteps = homotopyConversionSteps;
                homotopyOpts.sharpnessStart = homotopySharpnessStart;
                homotopyOpts.sharpnessSteps = homotopySharpnessSteps;
                homotopyOpts.logProgress = homotopyLog;
                solver = obj.solveWithHomotopy(unmatched, homotopyOpts);
            else
                error('Unsupported solve mode "%s". Use "direct" or "homotopy".', mode);
            end

            obj.hasSolveAttempted = true;
            obj.lastSolveConverged = solver.converged;

            if ~solver.converged && ~allowNonConverged
                error('Flowsheet:NonConvergedSolve', ...
                    ['Solve exited with a non-converged iterate; balances not satisfied. ' ...
                     'exitFlag=%s, finalResidual=%.6e, finalWeightedResidual=%.6e. ' ...
                     'Set allowNonConverged=true to inspect intermediate iterate only.'], ...
                    char(solver.exitFlag), solver.finalResidual, solver.finalWeightedResidual);
            end
        end

        function T = streamTable(obj, varargin)
            if obj.hasSolveAttempted && ~obj.lastSolveConverged
                error('Flowsheet:NonConvergedResults', ...
                    'Cannot present streamTable as final results: non-converged iterate; balances not satisfied.');
            end

            % Table including: name, n_dot, T, P, y_i, and species molar flows n_i = n_dot*y_i
            %
            % Options:
            %   'includeAliases' (default false): include one row for every
            %       display name (aliases included).
            %   'showAliasColumn' (default false): when aliases are suppressed,
            %       append an aliases column that lists additional names.
            p = inputParser;
            p.addParameter('includeAliases', false, @(x)islogical(x)&&isscalar(x));
            p.addParameter('showAliasColumn', false, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});

            includeAliases = p.Results.includeAliases;
            showAliasColumn = p.Results.showAliasColumn;

            [displayNames, displayRefs, aliasNames] = obj.selectStreamDisplayRows(includeAliases);

            N  = numel(displayRefs);
            ns = numel(obj.species);

            names = strings(N,1);
            n_dot = nan(N,1);
            TT    = nan(N,1);
            PP    = nan(N,1);
            Y     = nan(N,ns);
            Ni    = nan(N,ns);

            for i = 1:N
                s = displayRefs{i};
                names(i) = string(displayNames{i});
                n_dot(i) = s.n_dot;
                TT(i)    = s.T;
                PP(i)    = s.P;
                Y(i,:)   = s.y(:).';
                Ni(i,:)  = s.n_dot .* s.y(:).';
            end

            T = table(names, n_dot, TT, PP);

            % y columns
            for j = 1:ns
                T.(sprintf('y_%s', obj.species{j})) = Y(:,j);
            end

            % species molar flow columns
            for j = 1:ns
                T.(sprintf('n_%s', obj.species{j})) = Ni(:,j);
            end

            if showAliasColumn && ~includeAliases
                aliases = strings(N,1);
                for i = 1:N
                    aliases(i) = string(strjoin(aliasNames{i}, ', '));
                end
                T.aliases = aliases;
            end
        end
    end

    methods (Access = private)
        function solver = runSingleSolve(obj, solverOverrides)
            solver = proc.ProcessSolver(obj.streams, obj.units);
            fields = fieldnames(solverOverrides);
            for i = 1:numel(fields)
                name = fields{i};
                val  = solverOverrides.(name);
                if isprop(solver, name)
                    solver.(name) = val;
                else
                    error('ProcessSolver has no property "%s"', name);
                end
            end
            solver.solve();
        end

        function solver = solveWithHomotopy(obj, solverOverrides, opts)
            [reactors, conversionTarget] = obj.collectUnitsWithProperty('conversion');
            [separators, separatorTarget] = obj.collectUnitsWithProperty('phi');
            [purges, purgeTarget] = obj.collectUnitsWithProperty('beta');

            convStart = min(max(opts.conversionStart, 0), 1);
            sharpStart = min(max(opts.sharpnessStart, 0), 1);

            % Stage A: flatten conversion to make reaction source terms mild.
            for i = 1:numel(reactors)
                reactors{i}.conversion = convStart;
            end
            obj.logHomotopy(opts.logProgress, 'Stage A: conversion fixed near zero (X=%.4f).', convStart);
            solver = obj.runSingleSolve(solverOverrides);
            obj.assertStageConverged('A', solver, opts.logProgress);

            % Stage B: ramp reactor conversion from Stage A value to target values.
            if ~isempty(reactors)
                lambdas = linspace(0, 1, opts.conversionSteps);
                for k = 1:numel(lambdas)
                    lam = lambdas(k);
                    for i = 1:numel(reactors)
                        reactors{i}.conversion = convStart + lam * (conversionTarget{i} - convStart);
                    end
                    obj.logHomotopy(opts.logProgress, ...
                        'Stage B.%d/%d: conversion ramp lambda=%.3f.', k, numel(lambdas), lam);
                    solver = obj.runSingleSolve(solverOverrides);
                    obj.assertStageConverged(sprintf('B.%d', k), solver, opts.logProgress);
                end
            else
                obj.logHomotopy(opts.logProgress, 'Stage B: no reactor conversion controls found; skipping.');
            end

            % Stage C: ramp split sharpness for separator and purge units.
            hasSharpness = ~isempty(separators) || ~isempty(purges);
            if hasSharpness
                lambdas = linspace(0, 1, opts.sharpnessSteps);
                for k = 1:numel(lambdas)
                    lam = lambdas(k);
                    for i = 1:numel(separators)
                        tgt = separatorTarget{i};
                        separators{i}.phi = sharpStart + lam .* (tgt - sharpStart);
                    end
                    for i = 1:numel(purges)
                        tgt = purgeTarget{i};
                        purges{i}.beta = sharpStart + lam .* (tgt - sharpStart);
                    end
                    obj.logHomotopy(opts.logProgress, ...
                        'Stage C.%d/%d: separator/purge sharpness ramp lambda=%.3f.', k, numel(lambdas), lam);
                    solver = obj.runSingleSolve(solverOverrides);
                    obj.assertStageConverged(sprintf('C.%d', k), solver, opts.logProgress);
                end
            else
                obj.logHomotopy(opts.logProgress, 'Stage C: no separator/purge sharpness controls found; skipping.');
            end
        end

        function [unitsWithProp, targets] = collectUnitsWithProperty(obj, propName)
            unitsWithProp = {};
            targets = {};
            for ui = 1:numel(obj.units)
                u = obj.units{ui};
                if isprop(u, propName)
                    unitsWithProp{end+1} = u; %#ok<AGROW>
                    targets{end+1} = u.(propName); %#ok<AGROW>
                end
            end
        end

        function assertStageConverged(obj, stageName, solver, doLog)
            if solver.converged
                obj.logHomotopy(doLog, ...
                    'Stage %s converged (||r||=%.3e, ||W*r||=%.3e, exit=%s).', ...
                    stageName, solver.finalResidual, solver.finalWeightedResidual, char(solver.exitFlag));
            else
                error('Flowsheet:HomotopyStageFailed', ...
                    ['Homotopy stage %s did not converge. ' ...
                     'exitFlag=%s, finalResidual=%.6e, finalWeightedResidual=%.6e.'], ...
                    stageName, char(solver.exitFlag), solver.finalResidual, solver.finalWeightedResidual);
            end
        end

        function logHomotopy(~, enabled, msg, varargin)
            if ~enabled
                return;
            end
            fprintf('[homotopy] %s\n', sprintf(msg, varargin{:}));
        end

        function [names, refs, aliasNames] = selectStreamDisplayRows(obj, includeAliases)
            names = {};
            refs = {};
            aliasNames = {};

            if includeAliases
                names = obj.streamDisplayNames;
                refs = obj.streamDisplayRefs;
                aliasNames = repmat({{}}, numel(names), 1);
                return;
            end

            for i = 1:numel(obj.streamDisplayRefs)
                s = obj.streamDisplayRefs{i};
                thisName = char(string(obj.streamDisplayNames{i}));
                matchIdx = 0;
                for j = 1:numel(refs)
                    if isequal(refs{j}, s)
                        matchIdx = j;
                        break;
                    end
                end

                if matchIdx == 0
                    names{end+1} = thisName; %#ok<AGROW>
                    refs{end+1} = s; %#ok<AGROW>
                    aliasNames{end+1} = {}; %#ok<AGROW>
                else
                    aliasNames{matchIdx}{end+1} = thisName;
                end
            end
            aliasNames = reshape(aliasNames, [], 1);
        end

        function n = countUnknowns(obj)
            ns = numel(obj.species);
            n = 0;

            for si = 1:numel(obj.streams)
                s = obj.streams{si};

                % n_dot
                if isUnknownField(s, 'n_dot')
                    n = n + 1;
                end

                % T
                if isUnknownField(s, 'T')
                    n = n + 1;
                end

                % P
                if isUnknownField(s, 'P')
                    n = n + 1;
                end

                % y
                if hasKnownY(s)
                    nUnknownY = sum(~s.known.y(:));
                    if nUnknownY > 0
                        % Gauge fixing for softmax logits: when composition
                        % has free dimensions, one unknown component can be
                        % anchored so composition contributes (nUnknownY-1)
                        % independent unknowns.
                        n = n + max(nUnknownY - 1, 0);
                    end
                else
                    % If known.y flags are unavailable/invalid, composition is
                    % fully free and contributes (ns-1) independent unknowns.
                    n = n + max(ns - 1, 0);
                end
            end


            % Unit-level manipulated unknowns (e.g., Adjust blocks)
            for ui = 1:numel(obj.units)
                unit = obj.units{ui};
                if ismethod(unit, 'unknownSpecs')
                    specs = unit.unknownSpecs();
                    if ~isempty(specs)
                        n = n + numel(specs);
                    end
                end
            end

            function tf = isUnknownField(st, fieldName)
                if isprop(st,'known') && isstruct(st.known) && isfield(st.known, fieldName)
                    tf = ~st.known.(fieldName);
                else
                    % default: treat as unknown (UI/app will manage known flags)
                    tf = true;
                end
            end

            function tf = hasKnownY(st)
                tf = isprop(st,'known') && isstruct(st.known) && isfield(st.known,'y') && numel(st.known.y)==ns;
            end
        end

        function nEq = countEquations(obj)
            % Count total number of scalar equations returned by unit.equations()
            nEq = 0;
            for u = 1:numel(obj.units)
                ru = obj.units{u}.equations();
                nEq = nEq + numel(ru);
            end
        end

        function validate(obj)
            % Throws an error with a readable message if the model is not runnable.

            if isempty(obj.streams)
                error('Flowsheet has no streams.');
            end
            if isempty(obj.units)
                error('Flowsheet has no units.');
            end

            ns = numel(obj.species);

            % Stream checks
            for i = 1:numel(obj.streams)
                s = obj.streams{i};

                if ~isprop(s,'name')
                    error('Stream #%d has no name property.', i);
                end

                % Check y vector
                if isempty(s.y) || numel(s.y) ~= ns
                    error('Stream "%s": y must be length %d.', string(s.name), ns);
                end
                if any(~isfinite(s.y))
                    error('Stream "%s": y contains NaN/Inf.', string(s.name));
                end
                if any(s.y < 0)
                    error('Stream "%s": y contains negative entries.', string(s.name));
                end
                sy = sum(s.y);
                if abs(sy - 1) > 1e-6
                    error('Stream "%s": y must sum to 1 (currently %.6g).', string(s.name), sy);
                end

                % Scalars (we require finite initial guesses even if unknown)
                if ~isfinite(s.n_dot) || s.n_dot <= 0
                    error('Stream "%s": n_dot must be finite and > 0 (currently %.6g).', string(s.name), s.n_dot);
                end
                if ~isfinite(s.T) || s.T <= 0
                    error('Stream "%s": T must be finite and > 0 (currently %.6g).', string(s.name), s.T);
                end
                if ~isfinite(s.P) || s.P <= 0
                    error('Stream "%s": P must be finite and > 0 (currently %.6g).', string(s.name), s.P);
                end

                % known flags sanity (required for app workflow)
                if ~isprop(s,'known') || ~isstruct(s.known)
                    error('Stream "%s": missing known struct. Ensure Stream constructor initializes known.*', string(s.name));
                end

                req = {'n_dot','T','P','y'};
                for f = req
                    if ~isfield(s.known, f{1})
                        error('Stream "%s": known.%s missing. Ensure Stream constructor initializes it.', string(s.name), f{1});
                    end
                end

                if ~islogical(s.known.n_dot) || ~isscalar(s.known.n_dot)
                    error('Stream "%s": known.n_dot must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.T) || ~isscalar(s.known.T)
                    error('Stream "%s": known.T must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.P) || ~isscalar(s.known.P)
                    error('Stream "%s": known.P must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.y) || numel(s.known.y) ~= ns
                    error('Stream "%s": known.y must be logical(1,%d).', string(s.name), ns);
                end
            end

            % Unit checks (lightweight)
            for u = 1:numel(obj.units)
                unit = obj.units{u};

                if ~ismethod(unit, 'equations')
                    error('Unit #%d (%s) has no equations() method.', u, class(unit));
                end

                ru = unit.equations();
                if any(~isfinite(ru(:)))
                    error('Unit #%d (%s): equations() returned NaN/Inf. Check connectivity/initial guesses.', u, class(unit));
                end
            end

            % DOF check (quiet inside validate)
            [nU, nE] = obj.checkDOF('quiet', true);
            if nU ~= nE
                warning('Flowsheet DOF not square: unknowns=%d, eqs=%d. Solver may still run (LM), but check specs.', nU, nE);
            end
        end
    end
end
