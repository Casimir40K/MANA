classdef SolverDiagnostics
    %SOLVERDIAGNOSTICS  Static helpers for solver diagnostics, debug output,
    %   equation labeling, weighting, preflight checks, and failure reports.

    methods (Static)

        function [eqNames, types] = buildEquationLabels(units, eqCounts)
            %BUILDEQUATIONLABELS  Build equation labels with type classification.
            %   Returns eqNames (string column) and types (double column:
            %   0=default, 1=flow, 2=temperature, 3=pressure).
            %   eqCounts is an optional cached vector of per-unit equation counts.
            eqNames = strings(0,1);
            types = zeros(0,1);
            for u = 1:numel(units)
                unit = units{u};
                if nargin >= 2 && ~isempty(eqCounts) && u <= numel(eqCounts)
                    nEq = eqCounts(u);
                else
                    nEq = numel(unit.equations());
                end

                labels = strings(nEq,1);
                if ismethod(unit, 'equationLabels')
                    try
                        labels = string(unit.equationLabels());
                    catch
                        labels = strings(nEq,1);
                    end
                end
                if numel(labels) ~= nEq
                    labels = strings(nEq,1);
                end

                unitName = class(unit);
                if ismethod(unit, 'describe')
                    try
                        unitName = string(unit.describe());
                    catch
                        unitName = string(class(unit));
                    end
                end

                localTypes = zeros(nEq, 1);
                for i = 1:nEq
                    if strlength(labels(i)) == 0
                        labels(i) = sprintf('%s: eq %d', char(unitName), i);
                    end
                    lbl = lower(char(labels(i)));
                    if contains(lbl, 'pressure') || contains(lbl, ' p') || contains(lbl, 'dp')
                        localTypes(i) = 3;
                    elseif contains(lbl, 'temp') || contains(lbl, 'enthalpy') || contains(lbl, 'energy')
                        localTypes(i) = 2;
                    elseif contains(lbl, 'flow') || contains(lbl, 'mass') || contains(lbl, 'mole') || contains(lbl, 'n_dot')
                        localTypes(i) = 1;
                    end
                end
                eqNames = [eqNames; labels(:)]; %#ok<AGROW>
                types = [types; localTypes(:)]; %#ok<AGROW>
            end
        end

        function w = buildEquationWeights(eqNames, nEq, r0, eqTypes, opts)
            %BUILDEQUATIONWEIGHTS  Build per-equation weight vector.
            %   opts fields: equationWeights, autoScale, autoScaleMinMagnitude,
            %   autoScaleMaxWeightFactor, defaultResidualScale, flowResidualScale,
            %   temperatureResidualScale, pressureResidualScale
            if ~isempty(opts.equationWeights)
                ew = opts.equationWeights(:);
                if isscalar(ew)
                    w = repmat(ew, nEq, 1);
                elseif numel(ew) == nEq
                    w = ew;
                else
                    error('equationWeights must be scalar or length %d.', nEq);
                end
            elseif opts.autoScale && ~isempty(r0)
                mag = abs(r0(1:min(nEq, numel(r0))));
                w = 1 ./ max(mag, opts.autoScaleMinMagnitude);
                if numel(w) < nEq
                    w(end+1:nEq) = 1;
                end
                wMin = min(w);
                wMax = wMin * max(1, opts.autoScaleMaxWeightFactor);
                w = min(w, wMax);
            else
                w = ones(nEq,1) / max(opts.defaultResidualScale, eps);
                if ~isempty(eqTypes) && numel(eqTypes) == nEq
                    wFlow = 1 / max(opts.flowResidualScale, eps);
                    wTemp = 1 / max(opts.temperatureResidualScale, eps);
                    wPres = 1 / max(opts.pressureResidualScale, eps);
                    w(eqTypes == 1) = wFlow;
                    w(eqTypes == 2) = wTemp;
                    w(eqTypes == 3) = wPres;
                else
                    for i = 1:nEq
                        lbl = lower(char(eqNames(min(i, numel(eqNames)))));
                        if contains(lbl, 'pressure') || contains(lbl, ' p') || contains(lbl, 'dp')
                            w(i) = 1 / max(opts.pressureResidualScale, eps);
                        elseif contains(lbl, 'temp') || contains(lbl, 'enthalpy') || contains(lbl, 'energy')
                            w(i) = 1 / max(opts.temperatureResidualScale, eps);
                        elseif contains(lbl, 'flow') || contains(lbl, 'mass') || contains(lbl, 'mole') || contains(lbl, 'n_dot')
                            w(i) = 1 / max(opts.flowResidualScale, eps);
                        end
                    end
                end
            end
            w(~isfinite(w) | w <= 0) = 1;
        end

        function dbg = resolveDebugOptions(solverObj)
            %RESOLVEDEBUGOPTIONS  Convert solver debug fields to a struct.
            dbg = struct( ...
                'level', max(0, floor(solverObj.debugLevel)), ...
                'topN', max(1, floor(solverObj.debugTopN)), ...
                'every', max(0, floor(solverObj.debugEvery)), ...
                'out', solverObj.debugOut, ...
                'eqNames', logical(solverObj.debugEqNames));

            if solverObj.debug && dbg.level < 1
                dbg.level = 1;
            end

            if isstruct(solverObj.solverSettings) && isfield(solverObj.solverSettings, 'debugStruct')
                ds = solverObj.solverSettings.debugStruct;
                if isstruct(ds)
                    if isfield(ds, 'level'),   dbg.level = max(dbg.level, floor(ds.level)); end
                    if isfield(ds, 'topN'),    dbg.topN = max(1, floor(ds.topN)); end
                    if isfield(ds, 'every'),   dbg.every = max(0, floor(ds.every)); end
                    if isfield(ds, 'out'),     dbg.out = ds.out; end
                    if isfield(ds, 'eqNames'), dbg.eqNames = logical(ds.eqNames); end
                end
            end

            envLevel = str2double(getenv('MATHLAB_DEBUG'));
            if isfinite(envLevel) && envLevel > 0
                dbg.level = max(dbg.level, floor(envLevel));
            end
        end

        function nDisabled = configureNormalizationConstraints(units, removeFlag)
            %CONFIGURENORMALIZATIONCONSTRAINTS  Toggle normalization constraints.
            nDisabled = 0;
            for u = 1:numel(units)
                unit = units{u};
                if isprop(unit, 'includeNormalizationConstraints')
                    unit.includeNormalizationConstraints = ~removeFlag;
                    if removeFlag
                        nDisabled = nDisabled + 1;
                    end
                end
            end
        end

        function debugPrintIter(dbg, iter, rn2, r, dx, alpha, bt)
            rnInf = norm(r, inf);
            dxn = norm(dx, 2);
            [maxVal, maxIdx] = max(abs(r));
            if isempty(maxIdx), maxIdx = 0; maxVal = NaN; maxSigned = NaN;
            else, maxSigned = r(maxIdx);
            end

            fprintf(dbg.out, 'Iter %3d: ||r||2=%.3e  ||r||inf=%.3e  ||dx||=%.3e  alpha=%.3e  bt=%d  maxEq=%d (|r|=%.3e, r=%+.3e)\n', ...
                iter, rn2, rnInf, dxn, alpha, bt, maxIdx, maxVal, maxSigned);
        end

        function debugPrintTopResiduals(dbg, r, eqNames, context)
            if isempty(r)
                return
            end

            n = min(numel(r), dbg.topN);
            [~, order] = sort(abs(r), 'descend');
            topIdx = order(1:n);

            fprintf(dbg.out, 'Top %d residual components (%s):\n', n, context);
            for i = 1:n
                idx = topIdx(i);
                label = sprintf('eq %4d', idx);
                if dbg.eqNames && idx <= numel(eqNames) && strlength(eqNames(idx)) > 0
                    label = char(eqNames(idx));
                end
                fprintf(dbg.out, '  [%3d] %-40s : %+.3e\n', idx, label, r(idx));
            end
        end

        function debugPrintMixerCompositionConsistency(r, dbg, units, context)
            if dbg.level < 3
                return
            end
            [mixer, dominantEq, dominantVal] = proc.solver.SolverDiagnostics.findDominantMixer(r, units);
            if isempty(mixer)
                return
            end

            fprintf(dbg.out, 'Composition normalization + component-flow consistency (%s):\n', context);
            fprintf(dbg.out, '  Dominant mixer: %s (eq %d, r=%+.3e)\n', string(mixer.describe()), dominantEq, dominantVal);

            streamsToReport = [mixer.inlets(:); {mixer.outlet}];
            for i = 1:numel(streamsToReport)
                s = streamsToReport{i};
                y = s.y(:);
                sumY = sum(y);
                minY = min(y);
                maxY = max(y);
                compFlowSum = sum(s.n_dot .* y);
                diffFlow = compFlowSum - s.n_dot;
                fprintf(dbg.out, '  %s: sum(y)=%.15f (sum(y)-1=%+.3e) min=%.6e max=%.6e\n', ...
                    string(s.name), sumY, sumY - 1, minY, maxY);
                fprintf(dbg.out, '      n_dot=%.6e, sum(n_dot*y)=%.6e, diff=%+.3e\n', ...
                    s.n_dot, compFlowSum, diffFlow);
            end
        end

        function issues = detectKnownSpecConflicts(streams, units)
            %DETECTKNOWNSPECCONFLICTS  Detect contradictory fixed stream specs.
            issues = strings(0,1);
            for u = 1:numel(units)
                unit = units{u};
                uName = string(class(unit));
                if ismethod(unit, 'describe')
                    try uName = string(unit.describe()); catch, end
                end

                if isprop(unit, 'inlet') && isprop(unit, 'outlet')
                    sIn = unit.inlet;
                    sOut = unit.outlet;
                    if proc.solver.SolverDiagnostics.isKnownFlagTrue(sIn, 'T') && ...
                       proc.solver.SolverDiagnostics.isKnownFlagTrue(sOut, 'T')
                        if abs(sOut.T - sIn.T) > 1e-9
                            issues(end+1,1) = sprintf('%s has both inlet/outlet T marked Known but T_out-T_in=%+.3e K.', uName, sOut.T - sIn.T); %#ok<AGROW>
                        end
                    end
                    if proc.solver.SolverDiagnostics.isKnownFlagTrue(sIn, 'P') && ...
                       proc.solver.SolverDiagnostics.isKnownFlagTrue(sOut, 'P')
                        if abs(sOut.P - sIn.P) > 1e-6
                            issues(end+1,1) = sprintf('%s has both inlet/outlet P marked Known but P_out-P_in=%+.3e Pa.', uName, sOut.P - sIn.P); %#ok<AGROW>
                        end
                    end
                end

                if isprop(unit, 'Tout') && isfinite(unit.Tout) && isprop(unit, 'outlet')
                    sOut = unit.outlet;
                    if proc.solver.SolverDiagnostics.isKnownFlagTrue(sOut, 'T') && abs(sOut.T - unit.Tout) > 1e-9
                        issues(end+1,1) = sprintf('%s Tout=%.6g K conflicts with Known outlet T=%.6g K on stream %s.', ...
                            uName, unit.Tout, sOut.T, string(sOut.name)); %#ok<AGROW>
                    end
                end

                if isprop(unit, 'Pout') && isfinite(unit.Pout) && isprop(unit, 'outlet')
                    sOut = unit.outlet;
                    if proc.solver.SolverDiagnostics.isKnownFlagTrue(sOut, 'P') && abs(sOut.P - unit.Pout) > 1e-6
                        issues(end+1,1) = sprintf('%s Pout=%.6g Pa conflicts with Known outlet P=%.6g Pa on stream %s.', ...
                            uName, unit.Pout, sOut.P, string(sOut.name)); %#ok<AGROW>
                    end
                end
            end
        end

        function tf = isKnownFlagTrue(s, field)
            tf = false;
            if ~(isprop(s,'known') && isstruct(s.known) && isfield(s.known, field))
                return
            end
            v = s.known.(field);
            tf = islogical(v) && isscalar(v) && v;
        end

        function checkInitialJacobianConnectivity(x, r0, fdJacobianFcn, map, streams, nDotMin, ...
                jacobianDeadColumnTol, failOnJacobianDeadColumns, logFcn)
            %CHECKINITIALJACOBIAN  Detect disconnected unknowns (dead columns).
            if isempty(x)
                return
            end
            J0 = fdJacobianFcn(x, r0);
            colNormInf = max(abs(J0), [], 1);
            dead = find(colNormInf <= jacobianDeadColumnTol | ~isfinite(colNormInf));
            if isempty(dead)
                return
            end

            keep = true(size(dead));
            for i = 1:numel(dead)
                k = dead(i);
                m = map(k);
                if strcmp(m.var, 'a') && proc.solver.SolverDiagnostics.isNearZeroFlowStream( ...
                        m.streamIndex, streams, nDotMin)
                    keep(i) = false;
                    logFcn(['Jacobian dead-column candidate ignored: x(%d) %s ' ...
                        '(near-zero stream flow n_dot=%.3e).'], ...
                        k, proc.solver.SolverDiagnostics.describeUnknown(m), streams{m.streamIndex}.n_dot);
                end
            end

            dead = dead(keep);
            if isempty(dead), return; end

            msgLines = strings(numel(dead),1);
            for i = 1:numel(dead)
                k = dead(i);
                msgLines(i) = proc.solver.SolverDiagnostics.describeUnknown(map(k));
                logFcn('Jacobian dead-column candidate: x(%d) %s (||J(:,k)||_inf=%.3e)', ...
                    k, msgLines(i), colNormInf(k));
            end

            msg = sprintf(['Detected %d unknown(s) with near-zero initial Jacobian columns. ' ...
                'This indicates disconnected DOFs, conflicting constraints, or numerically flat equations.'], numel(dead));
            if failOnJacobianDeadColumns
                error('%s Unknown(s): %s', msg, strjoin(cellstr(msgLines), '; '));
            else
                warning('%s Unknown(s): %s', msg, strjoin(cellstr(msgLines), '; '));
            end
        end

        function tf = isNearZeroFlowStream(streamIndex, streams, nDotMin)
            tf = false;
            if ~isfinite(streamIndex) || streamIndex < 1 || streamIndex > numel(streams)
                return
            end
            s = streams{streamIndex};
            if ~isprop(s, 'n_dot') || ~isfinite(s.n_dot)
                return
            end
            tf = abs(s.n_dot) <= max(1e3 * nDotMin, 1e-9);
        end

        function txt = describeUnknown(m)
            if strcmp(m.var, 'u')
                txt = sprintf('[unit %d] manipulated %s.%s', m.unitIndex, class(m.owner), m.field);
                return
            end
            si = m.streamIndex;
            switch m.var
                case 'z', txt = sprintf('[stream %d] n_dot(log)', si);
                case 'a', txt = sprintf('[stream %d] composition logit comp=%d', si, m.subIndex);
                case 'T', txt = sprintf('[stream %d] temperature', si);
                case 'P', txt = sprintf('[stream %d] pressure', si);
                otherwise, txt = sprintf('[stream %d] var=%s', si, m.var);
            end
        end

        function detail = buildFailureReport(ME, stage, iter, r, w, eqNames, logLines, residualEvalCount)
            header = "HERE IS WHAT HAPPENED";
            lines = strings(0,1);
            lines(end+1,1) = header;
            lines(end+1,1) = string(repmat('=', 1, strlength(header)));
            lines(end+1,1) = sprintf('Failure stage: %s', stage);
            lines(end+1,1) = sprintf('Iteration: %d', iter);
            lines(end+1,1) = sprintf('Reason: %s', string(ME.message));
            lines(end+1,1) = sprintf('Residual evaluations: %d', residualEvalCount);

            if ~isempty(ME.stack)
                lines(end+1,1) = 'Stack trace (most recent first):';
                nStack = min(6, numel(ME.stack));
                for i = 1:nStack
                    st = ME.stack(i);
                    lines(end+1,1) = sprintf('  at %s (line %d)', string(st.name), st.line); %#ok<AGROW>
                end
            end

            if ~isempty(r)
                ru = norm(r);
                if ~isempty(w)
                    rw = norm(w .* r);
                else
                    rw = ru;
                end
                lines(end+1,1) = sprintf('Residual norms: ||r||=%.6e, ||W*r||=%.6e', ru, rw);
                lines(end+1,1) = proc.solver.SolverDiagnostics.summarizeTopResiduals(r, eqNames, 10);
            else
                lines(end+1,1) = 'Residual norms: unavailable (failure occurred before initial residual evaluation).';
            end

            lines(end+1,1) = 'Recent solver log lines:';
            nLog = numel(logLines);
            nTail = min(12, nLog);
            if nTail == 0
                lines(end+1,1) = '  (none)';
            else
                for i = nLog-nTail+1:nLog
                    lines(end+1,1) = "  - " + logLines(i); %#ok<AGROW>
                end
            end

            detail = strjoin(lines, newline);
        end

        function txt = summarizeTopResiduals(r, eqNames, topN)
            if nargin < 3 || isempty(topN), topN = 10; end
            n = min([numel(r), max(1, topN)]);
            if n == 0
                txt = 'Top residuals: none.';
                return
            end
            [~, order] = sort(abs(r), 'descend');
            idx = order(1:n);
            parts = strings(n,1);
            for i = 1:n
                k = idx(i);
                label = sprintf('eq %d', k);
                if k <= numel(eqNames) && strlength(eqNames(k)) > 0
                    label = char(eqNames(k));
                end
                parts(i) = sprintf('[%d] %s = %+.3e', k, label, r(k));
            end
            txt = "Top residuals: " + strjoin(parts, '; ');
        end

        function [dominantMixer, eqIdx, eqVal] = findDominantMixer(r, units)
            dominantMixer = [];
            eqIdx = NaN;
            eqVal = NaN;
            cursor = 1;
            bestAbs = -Inf;
            for u = 1:numel(units)
                unit = units{u};
                nEq = numel(unit.equations());
                idx = cursor:(cursor + nEq - 1);
                if isa(unit, 'proc.units.Mixer') && ~isempty(idx)
                    [localAbs, localPos] = max(abs(r(idx)));
                    if isfinite(localAbs) && localAbs > bestAbs
                        bestAbs = localAbs;
                        dominantMixer = unit;
                        eqIdx = idx(localPos);
                        eqVal = r(eqIdx);
                    end
                end
                cursor = cursor + nEq;
            end
        end

        function warnIfCompositionNotNormalized(s, y, debugLevel, debugOut)
            if debugLevel < 1, return; end
            sumY = sum(y);
            delta = sumY - 1;
            if isfinite(delta) && abs(delta) > 1e-10
                fprintf(debugOut, 'WARN composition normalization drift: stream=%s, sum(y)-1=%+.3e\n', ...
                    string(s.name), delta);
            end
        end
    end
end
