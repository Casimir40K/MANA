classdef ProcessSolver < handle
    properties
        streams
        units
        ns

        maxIter = 60
        tolAbs  = 1e-9
        fdEps   = 1e-7
        fdScheme string = "forward"   % forward|central|mixed
        fdCentralColumns double = []   % used when fdScheme="mixed"

        % Jacobian controls
        kFD = 6
        enableBroyden logical = true
        broydenMinStepNorm2 = 1e-20
        broydenMinRcond = 1e-14

        % Weighted residual controls (W * r, W * J)
        equationWeights double = []
        defaultResidualScale = 1
        flowResidualScale = 1
        temperatureResidualScale = 1
        pressureResidualScale = 1
        useWeightedNormForConvergence logical = true

        % Auto-scale: derive per-equation weights from initial residual
        % magnitudes so that all equations contribute equally to the norm.
        autoScale logical = false
        autoScaleMinMagnitude double = 1e-6
        autoScaleMaxWeightFactor double = 1e3

        % Jacobian refresh trigger when convergence stalls
        stallRatioThreshold = 0.9
        stallIterWindow = 3

        % Optional high-level settings bundle; fields matching solver
        % properties are applied at solve() start.
        solverSettings struct = struct()

        % Remove unit-level normalization residuals when y is already
        % constrained by softmax parameterization in unpackUnknowns().
        removeRedundantNormalizationConstraints logical = true

        % Preflight diagnostics for contradictory fixed stream specs.
        failOnKnownSpecConflicts logical = true

        % Preflight diagnostics for disconnected/flat unknowns whose
        % Jacobian column is numerically near-zero at initialization.
        failOnJacobianDeadColumns logical = true
        jacobianDeadColumnTol double = 1e-12

        printToConsole = false
        consoleStride  = 10

        damping = 1.0

        % Line-search acceptance guard: require weighted residual decrease
        % but allow small unweighted residual growth to avoid false
        % stagnation rejects in mixed-scale nonlinear systems.
        lineSearchMaxUnweightedIncreaseRatio double = 0.02

        % Safety bounds
        nDotMin = 1e-12
        nDotMax = 1e8
        TMin    = 1
        TMax    = 5000
        PMin    = 1
        PMax    = 1e9

        % Captured log lines for UI
        logLines string = strings(0,1)

        % Convergence history (populated during solve)
        residualHistory double = []
        weightedResidualHistory double = []
        stepHistory     double = []
        alphaHistory    double = []

        % Runtime counter (including line-search and FD probes)
        residualEvalCount double = 0

        % Explicit solve status (updated at solve() exit)
        converged logical = false
        exitFlag string = "not_run"
        finalResidual double = NaN
        finalWeightedResidual double = NaN

        % Optional callback: called each iteration as iterCallback(iter, rNorm)
        % Set this before calling solve() to get real-time updates.
        iterCallback = []   % function_handle or empty

        % Optional callback: called each time a solver log line is emitted as
        % logCallback(line, lineNumber).
        logCallback = []    % function_handle or empty

        % Parallel Computing Toolbox: enable parallel FD Jacobian
        % Set to true to use parfor when the Parallel Computing Toolbox
        % is available. Falls back to serial execution transparently.
        useParallel logical = false

        % Hidden debug controls (off by default)
        debug logical = false
        debugLevel double = 2
        debugTopN double = 10
        debugEvery double = 0
        debugOut double = 1
        debugEqNames logical = true
    end

    properties (Dependent)
        verbose
    end

    properties (Access = private)
        map
        zMin
        zMax

        % Cached equation structure (populated at solve start)
        eqCounts double = []      % number of equations per unit
        eqOffsets double = []     % cumulative offset per unit
        totalEqs double = 0       % total number of equations

        % Pre-computed unpack index maps (populated at packUnknowns)
        unpackMaps struct = struct()

        % Equation type classification for fast weight building
        eqTypes double = []       % 0=default,1=flow,2=temperature,3=pressure

        % Parallel toolbox availability (checked once)
        hasParallelToolbox logical = false
        parallelChecked logical = false

        % Jacobian sparsity (populated on first FD build)
        sparsityPattern logical = []
        columnColors double = []
        nColors double = 0
    end

    methods
        function obj = ProcessSolver(streams, units)
            obj.streams = streams;
            obj.units   = units;
            obj.ns      = numel(streams{1}.y);
            obj.zMin = log(obj.nDotMin);
            obj.zMax = log(obj.nDotMax);
            obj.logLines = strings(0,1);
        end

        function v = get.verbose(obj), v = obj.printToConsole; end
        function set.verbose(obj, v),  obj.printToConsole = logical(v); end

        function solve(obj)
            obj.applySolverSettingsStruct();
            dbg = obj.resolveDebugOptions();

            % Reset sparsity (re-detected on first Jacobian build)
            obj.sparsityPattern = [];
            obj.columnColors = [];
            obj.nColors = 0;

            % Check for Parallel Computing Toolbox (once per solver lifetime)
            if ~obj.parallelChecked
                obj.hasParallelToolbox = ~isempty(ver('parallel'));
                obj.parallelChecked = true;
            end
            if obj.useParallel && obj.hasParallelToolbox
                obj.log('Parallel FD Jacobian enabled (Parallel Computing Toolbox detected).');
            elseif obj.useParallel && ~obj.hasParallelToolbox
                obj.log('Parallel FD Jacobian requested but Parallel Computing Toolbox not found. Using serial execution.');
            end

            obj.converged = false;
            obj.exitFlag = "running";
            obj.finalResidual = NaN;
            obj.finalWeightedResidual = NaN;

            histAlloc = obj.maxIter + 2;
            obj.logLines = strings(0,1);
            obj.residualHistory = nan(1, histAlloc);
            obj.weightedResidualHistory = nan(1, histAlloc);
            obj.stepHistory     = nan(1, histAlloc);
            obj.alphaHistory    = nan(1, histAlloc);
            histIdx = 0;

            obj.residualEvalCount = 0;

            stage = "startup";
            iter = 0;
            x = [];
            r = [];
            w = [];
            eqNames = strings(0,1);

            try
                stage = "configure_normalization";
                nDisabled = obj.configureNormalizationConstraints();
                if obj.removeRedundantNormalizationConstraints
                    obj.log('Normalization constraints disabled on %d unit(s) (y uses softmax parameterization).', nDisabled);
                else
                    obj.log('Normalization constraints kept on all units.');
                end

                stage = "pack_unknowns";
                [x, obj.map] = obj.packUnknowns();
                obj.buildUnpackMaps();

                % Cache equation counts per unit (avoids dynamic array growth in tryResiduals)
                stage = "cache_equation_structure";
                nU = numel(obj.units);
                obj.eqCounts = zeros(nU, 1);
                for u = 1:nU
                    obj.eqCounts(u) = numel(obj.units{u}.equations());
                end
                obj.eqOffsets = [0; cumsum(obj.eqCounts)];
                obj.totalEqs = obj.eqOffsets(end);

                eqNames = obj.buildEquationLabels();

                stage = "preflight_spec_conflicts";
                specIssues = obj.detectKnownSpecConflicts();
                if ~isempty(specIssues)
                    for i = 1:numel(specIssues)
                        obj.log('Spec conflict: %s', specIssues(i));
                    end
                    msg = sprintf(['Detected %d contradictory known/spec constraint(s). ' ...
                        'This commonly causes apparent thermo non-convergence with static residuals.'], numel(specIssues));
                    if obj.failOnKnownSpecConflicts
                        error('%s Clear conflicting Known flags or unit specs and re-run.', msg);
                    else
                        warning(char(msg));
                    end
                end

                vars = string({obj.map.var});
                obj.log('Packed unknowns: %d total (%d T, %d P)', ...
                    numel(x), sum(vars=="T"), sum(vars=="P"));

                stage = "initial_residual";
                [r, ok] = obj.tryResiduals(x);
                if ~ok
                    error('Initial residual returned NaN/Inf. Check initial guesses (n_dot,y,T,P).');
                end

                stage = "preflight_jacobian_connectivity";
                obj.checkInitialJacobianConnectivity(x, r);

                stage = "build_weights";
                w = obj.buildEquationWeights(eqNames, numel(r), r);
                if obj.autoScale
                    obj.log('Auto-scaling enabled: weights derived from initial |r| (minMag=%.1e, wRange=[%.2e, %.2e])', ...
                        obj.autoScaleMinMagnitude, min(w), max(w));
                end
                r0u = norm(r);
                r0w = norm(w .* r);
                histIdx = histIdx + 1;
                obj.residualHistory(histIdx) = r0u;
                obj.weightedResidualHistory(histIdx) = r0w;
                obj.stepHistory(histIdx)     = NaN;
                obj.alphaHistory(histIdx)    = NaN;

                obj.log('Initial ||r|| = %.6e, ||W*r|| = %.6e (unknowns=%d, eqs=%d)', r0u, r0w, numel(x), numel(r));

                % Fire callback for initial state
                if obj.useWeightedNormForConvergence
                    obj.fireCallback(0, r0w);
                else
                    obj.fireCallback(0, r0u);
                end

                stage = "iteration_loop";
                J = [];
                forceFD = true;
                stallCount = 0;
                disableBroydenOnce = false;

                for k = 1:obj.maxIter
                    iter = k;
                    rnU = norm(r);
                    rnW = norm(w .* r);
                    rnConv = rnU;
                    if obj.useWeightedNormForConvergence
                        rnConv = rnW;
                    end
                    if rnConv < obj.tolAbs
                        histIdx = histIdx + 1;
                        obj.residualHistory(histIdx) = rnU;
                        obj.weightedResidualHistory(histIdx) = rnW;
                        obj.stepHistory(histIdx)     = 0;
                        obj.alphaHistory(histIdx)    = 0;
                        obj.converged = true;
                        obj.exitFlag = "converged";
                        obj.finalResidual = rnU;
                        obj.finalWeightedResidual = rnW;
                        obj.log('Converged at iter %d: ||r||=%.6e, ||W*r||=%.6e (resEvals=%d)', k, rnU, rnW, obj.residualEvalCount);
                        obj.fireCallback(k, rnConv);
                        break
                    end

                    doFD = forceFD || isempty(J) || mod(k-1, max(1,obj.kFD)) == 0;
                    if doFD
                        stage = sprintf('iter_%d_fd_jacobian', k);
                        J  = obj.fdJacobianSafe(x, r);
                        jacobianMode = "FD";
                        forceFD = false;
                    else
                        jacobianMode = "REUSE";
                    end

                    stage = sprintf('iter_%d_linear_solve', k);
                    dx = obj.solveLinearLM(J, -r, w);

                    if any(~isfinite(dx))
                        error('dx contains NaN/Inf. Model may be ill-conditioned.');
                    end

                    stage = sprintf('iter_%d_line_search', k);
                [accepted, x_new, r_new, alpha, bt, stagnationReject] = obj.backtrackingLineSearch(x, dx, rnU, rnW, w);
                    if ~accepted
                        if stagnationReject
                            obj.log('Iter %3d: stagnation reject (no strict ||W*r|| decrease found in line search).', k);
                        end

                        % Fallback: discard reused/Broyden Jacobian and retry with
                        % a fresh finite-difference Jacobian at the current state.
                        stage = sprintf('iter_%d_fd_retry', k);
                        J  = obj.fdJacobianSafe(x, r);
                        jacobianMode = "FD-RETRY";
                        forceFD = false;

                        stage = sprintf('iter_%d_linear_retry', k);
                        dx = obj.solveLinearLM(J, -r, w);

                        stage = sprintf('iter_%d_line_search_retry', k);
                        [accepted, x_new, r_new, alpha, bt, stagnationReject] = obj.backtrackingLineSearch(x, dx, rnU, rnW, w);

                        if ~accepted && stagnationReject
                            obj.log('Iter %3d: stagnation reject persisted after FD retry.', k);
                        end

                        if ~accepted
                            error('Line search failed at iteration %d.', k);
                        end
                    end

                    % Accepted step
                    s = x_new - x;
                    rPrev = r;
                    x = x_new;
                    r = r_new;

                    % Update Jacobian after accepted step
                    if obj.enableBroyden && ~disableBroydenOnce
                        [J, broydenAccepted] = obj.tryBroydenUpdate(J, s, r - rPrev);
                        if broydenAccepted
                            jacobianMode = jacobianMode + "+BROYDEN";
                        else
                            forceFD = true;
                            jacobianMode = jacobianMode + "+BROYDEN-SKIP";
                        end
                    elseif disableBroydenOnce
                        disableBroydenOnce = false;
                        jacobianMode = jacobianMode + "+BROYDEN-OFF";
                    end

                    rnWNew = norm(w .* r);
                    if rnWNew / max(rnW, eps) > obj.stallRatioThreshold
                        stallCount = stallCount + 1;
                    else
                        stallCount = 0;
                    end
                    if stallCount >= max(1, round(obj.stallIterWindow))
                        forceFD = true;
                        disableBroydenOnce = true;
                        stallCount = 0;
                        obj.log('Stall detected at iter %d (ratio=%.3f). Forcing FD rebuild and skipping Broyden next step.', ...
                            k, rnWNew / max(rnW, eps));
                    end

                    % Record history
                    histIdx = histIdx + 1;
                    obj.residualHistory(histIdx) = rnU;
                    obj.weightedResidualHistory(histIdx) = rnW;
                    obj.stepHistory(histIdx)     = norm(dx);
                    obj.alphaHistory(histIdx)    = alpha;

                    relRnU = rnU / max(r0u, eps);
                    relRnW = rnW / max(r0w, eps);
                    obj.log('Iter %3d: ||r||=%.4e (rel=%.3e)  ||W*r||=%.4e (rel=%.3e)  ||dx||=%.3e  alpha=%.3e  bt=%d  J=%s', ...
                        k, rnU, relRnU, rnW, relRnW, norm(dx), alpha, bt, jacobianMode);

                    if dbg.level >= 1
                        obj.debugPrintIter(k, rnW, r, dx, alpha, bt, dbg);
                        if dbg.level >= 3 && dbg.every > 0 && mod(k, dbg.every) == 0
                            obj.debugPrintTopResiduals(r, dbg, eqNames, sprintf('iter %d', k));
                        end
                        if dbg.level >= 2 && dbg.every > 0 && mod(k, dbg.every) == 0
                            obj.debugPrintMixerCompositionConsistency(r, dbg, sprintf('iter %d', k));
                        end
                    end

                    % Fire callback for real-time plotting
                    obj.fireCallback(k, rnConv);

                    if k == obj.maxIter
                        finalR = norm(r);
                        finalRW = norm(w .* r);
                        obj.converged = false;
                        obj.exitFlag = "max_iter_nonconverged";
                        obj.finalResidual = finalR;
                        obj.finalWeightedResidual = finalRW;
                        histIdx = histIdx + 1;
                        obj.residualHistory(histIdx) = finalR;
                        obj.weightedResidualHistory(histIdx) = finalRW;
                        obj.stepHistory(histIdx) = NaN;
                        obj.alphaHistory(histIdx) = NaN;
                        obj.log('Max iterations reached: non-converged iterate; balances not satisfied. Final ||r||=%.6e, ||W*r||=%.6e (resEvals=%d)', finalR, finalRW, obj.residualEvalCount);
                        if obj.useWeightedNormForConvergence
                            obj.fireCallback(k+1, finalRW);
                        else
                            obj.fireCallback(k+1, finalR);
                        end
                        meMax = MException('ProcessSolver:MaxIterNonConverged', ...
                            'Max iterations reached: non-converged iterate; balances not satisfied. Final ||r||=%.6e, ||W*r||=%.6e', finalR, finalRW);
                        detail = obj.buildFailureReport(meMax, sprintf('iter_%d_max_iter', k), k, r, w, eqNames);
                        obj.log('%s', detail);
                        fprintf(2, '%s\n', detail);
                        warning('%s', meMax.message);
                    end
                end

                % Trim pre-allocated history arrays
                obj.residualHistory = obj.residualHistory(1:histIdx);
                obj.weightedResidualHistory = obj.weightedResidualHistory(1:histIdx);
                obj.stepHistory = obj.stepHistory(1:histIdx);
                obj.alphaHistory = obj.alphaHistory(1:histIdx);

                stage = "post_iteration_diagnostics";
                if dbg.level >= 2
                    obj.debugPrintTopResiduals(r, dbg, eqNames, 'solver exit');
                    obj.debugPrintMixerCompositionConsistency(r, dbg, 'solver exit');
                end

                if ~obj.printToConsole && ~isempty(obj.logLines)
                    fprintf('%s\n', obj.logLines(end));
                end

                stage = "unpack_solution";
                obj.unpackUnknowns(x);

            catch ME
                % Trim pre-allocated history arrays on error
                obj.residualHistory = obj.residualHistory(1:max(histIdx,0));
                obj.weightedResidualHistory = obj.weightedResidualHistory(1:max(histIdx,0));
                obj.stepHistory = obj.stepHistory(1:max(histIdx,0));
                obj.alphaHistory = obj.alphaHistory(1:max(histIdx,0));

                obj.converged = false;
                obj.exitFlag = "error";
                if ~isempty(r)
                    obj.finalResidual = norm(r);
                    if ~isempty(w)
                        obj.finalWeightedResidual = norm(w .* r);
                    else
                        obj.finalWeightedResidual = obj.finalResidual;
                    end
                end

                detail = obj.buildFailureReport(ME, stage, iter, r, w, eqNames);
                obj.log('%s', detail);
                fprintf(2, '%s\n', detail);

                enriched = MException('ProcessSolver:DetailedFailure', '%s', detail);
                enriched = addCause(enriched, ME);
                throwAsCaller(enriched);
            end
        end

        function T = streamTable(obj)
            if ~obj.converged
                error('ProcessSolver:NonConvergedResults', ...
                    'Cannot present streamTable as final results: non-converged iterate; balances not satisfied. exitFlag=%s, finalResidual=%.6e, finalWeightedResidual=%.6e', ...
                    char(obj.exitFlag), obj.finalResidual, obj.finalWeightedResidual);
            end

            N = numel(obj.streams);
            names = strings(N,1); n_dot = nan(N,1);
            TT = nan(N,1); PP = nan(N,1); Y = nan(N,obj.ns);
            for i = 1:N
                s = obj.streams{i};
                names(i) = string(s.name);
                n_dot(i) = s.n_dot; TT(i) = s.T; PP(i) = s.P;
                Y(i,:)   = s.y(:).';
            end
            T = table(names, n_dot, TT, PP);
            for j = 1:obj.ns
                T.(sprintf('y_%s', obj.streams{1}.species{j})) = Y(:,j);
            end
        end

        function S = localStabilityProxy(obj)
            %LOCALSTABILITYPROXY Estimate local poles from residual Jacobian.
            %
            % Interprets the steady-state residual as pseudo-dynamics:
            %    dx/dt = -r(x)
            % Then the linearized state matrix at the current operating
            % point is A = -dr/dx = -J. Poles are eig(A).
            %
            % This is a local stability proxy for diagnostics/teaching,
            % not a substitute for full dynamic model linearization.

            [x, map] = obj.packUnknowns();
            [r, ok] = obj.tryResiduals(x);
            if ~ok
                error('Cannot compute stability proxy: residual contains NaN/Inf at current state.');
            end

            J = obj.fdJacobianSafe(x, r);
            A = -J;
            poles = eig(A);

            S = struct();
            S.J = J;
            S.A = A;
            S.poles = poles;
            S.maxReal = max(real(poles));
            S.minReal = min(real(poles));
            S.stable = all(real(poles) < 0);
            S.nUnknowns = numel(x);
            S.nEquations = numel(r);
            S.map = map;
        end

        function solveFsolve(obj)
            %SOLVEFSOLVE Solve using MATLAB's fsolve (Optimization Toolbox).
            %   Uses the sparsity pattern for efficient Jacobian computation.
            %   Requires the Optimization Toolbox.
            obj.applySolverSettingsStruct();
            obj.converged = false;
            obj.exitFlag = "running";
            obj.finalResidual = NaN;
            obj.finalWeightedResidual = NaN;
            obj.logLines = strings(0,1);
            obj.residualHistory = [];
            obj.weightedResidualHistory = [];
            obj.stepHistory = [];
            obj.alphaHistory = [];
            obj.residualEvalCount = 0;

            obj.configureNormalizationConstraints();
            [x0, obj.map] = obj.packUnknowns();
            obj.buildUnpackMaps();

            % Cache equation counts
            nU = numel(obj.units);
            obj.eqCounts = zeros(nU, 1);
            for u = 1:nU
                obj.eqCounts(u) = numel(obj.units{u}.equations());
            end
            obj.eqOffsets = [0; cumsum(obj.eqCounts)];
            obj.totalEqs = obj.eqOffsets(end);

            obj.log('fsolve backend: %d unknowns, %d equations', numel(x0), obj.totalEqs);

            % Build sparsity pattern for fsolve JacobianPattern
            [r0, ~] = obj.tryResiduals(x0);
            n = numel(x0); m = numel(r0);
            sp = false(m, n);
            for k = 1:n
                step = obj.fdEps * max(1, abs(x0(k)));
                x2 = x0; x2(k) = x2(k) + step;
                [r2, ok] = obj.tryResiduals(x2);
                if ok
                    sp(:, k) = abs(r2 - r0) > 1e-14 * max(1, abs(r0));
                else
                    sp(:, k) = true;
                end
            end
            obj.log('fsolve sparsity: nnz=%.1f%%', 100 * nnz(sp) / (m*n));

            opts = optimoptions('fsolve', ...
                'Display', 'iter', ...
                'MaxIterations', obj.maxIter, ...
                'FunctionTolerance', obj.tolAbs, ...
                'StepTolerance', 1e-12, ...
                'JacobianPattern', sparse(sp), ...
                'SpecifyObjectiveGradient', false);

            resFun = @(x) obj.tryResidualsValueOnly(x);
            [xSol, ~, exitflag] = fsolve(resFun, x0, opts);

            obj.unpackUnknowns(xSol);
            [rFinal, ~] = obj.tryResiduals(xSol);
            obj.finalResidual = norm(rFinal);
            obj.finalWeightedResidual = obj.finalResidual;
            obj.converged = (exitflag > 0) && obj.finalResidual < obj.tolAbs * 100;
            if obj.converged
                obj.exitFlag = "converged";
                obj.log('fsolve converged: ||r||=%.6e', obj.finalResidual);
            else
                obj.exitFlag = sprintf("fsolve_exit_%d", exitflag);
                obj.log('fsolve exit %d: ||r||=%.6e', exitflag, obj.finalResidual);
            end
        end
    end

    methods (Access = private)
        function r = tryResidualsValueOnly(obj, x)
            % Wrapper that returns only the residual vector (no ok flag).
            % Required for fsolve function handle interface.
            [r, ~] = obj.tryResiduals(x);
        end
        function applySolverSettingsStruct(obj)
            if isempty(obj.solverSettings) || ~isstruct(obj.solverSettings)
                return
            end
            fn = fieldnames(obj.solverSettings);
            for i = 1:numel(fn)
                if isprop(obj, fn{i})
                    obj.(fn{i}) = obj.solverSettings.(fn{i});
                end
            end
        end

        function nDisabled = configureNormalizationConstraints(obj)
            nDisabled = proc.solver.SolverDiagnostics.configureNormalizationConstraints( ...
                obj.units, obj.removeRedundantNormalizationConstraints);
        end

        function [J, accepted] = tryBroydenUpdate(obj, J, s, y)
            [J, accepted] = proc.solver.JacobianEngine.tryBroydenUpdate( ...
                J, s, y, obj.broydenMinStepNorm2, obj.broydenMinRcond);
        end

        function fireCallback(obj, iter, rNorm)
            if ~isempty(obj.iterCallback) && isa(obj.iterCallback, 'function_handle')
                try
                    obj.iterCallback(iter, rNorm);
                catch
                    % Don't let a callback crash the solver
                end
            end
        end

        function log(obj, msg, varargin)
            line = string(sprintf(msg, varargin{:}));
            obj.logLines(end+1,1) = line;
            k = numel(obj.logLines);
            if ~isempty(obj.logCallback) && isa(obj.logCallback, 'function_handle')
                try
                    obj.logCallback(line, k);
                catch
                    % Don't let a callback crash the solver
                end
            end
            if obj.printToConsole
                if obj.consoleStride <= 1 || mod(k, obj.consoleStride) == 0
                    fprintf('%s\n', line);
                end
            end
        end

        function [r, ok] = tryResiduals(obj, x)
            obj.residualEvalCount = obj.residualEvalCount + 1;
            obj.unpackUnknowns(x);
            if obj.totalEqs > 0
                % Pre-allocated path: fill by index (no dynamic growth)
                r = zeros(obj.totalEqs, 1);
                for u = 1:numel(obj.units)
                    ru = obj.units{u}.equations();
                    r(obj.eqOffsets(u)+1 : obj.eqOffsets(u)+numel(ru)) = ru(:);
                end
            else
                % Fallback for first call before caching
                r = [];
                for u = 1:numel(obj.units)
                    ru = obj.units{u}.equations();
                    r = [r; ru(:)]; %#ok<AGROW>
                end
            end
            ok = all(isfinite(r));
        end

        function dbg = resolveDebugOptions(obj)
            dbg = proc.solver.SolverDiagnostics.resolveDebugOptions(obj);
        end

        function debugPrintIter(~, iter, rn2, r, dx, alpha, bt, dbg)
            proc.solver.SolverDiagnostics.debugPrintIter(dbg, iter, rn2, r, dx, alpha, bt);
        end

        function debugPrintTopResiduals(~, r, dbg, eqNames, context)
            proc.solver.SolverDiagnostics.debugPrintTopResiduals(dbg, r, eqNames, context);
        end

        function eqNames = buildEquationLabels(obj)
            [eqNames, obj.eqTypes] = proc.solver.SolverDiagnostics.buildEquationLabels( ...
                obj.units, obj.eqCounts);
        end

        function J = fdJacobianSafe(obj, x, r0)
            ctx = obj.buildJacobianContext();
            [J, obj.sparsityPattern, obj.columnColors, obj.nColors] = ...
                proc.solver.JacobianEngine.fdJacobianSafe(x, r0, ctx);
        end

        function ctx = buildJacobianContext(obj)
            ctx = struct( ...
                'tryResidualsFcn', @(xp) obj.tryResiduals(xp), ...
                'fdEps', obj.fdEps, ...
                'map', obj.map, ...
                'fdScheme', obj.fdScheme, ...
                'fdCentralColumns', obj.fdCentralColumns, ...
                'sparsityPattern', obj.sparsityPattern, ...
                'columnColors', obj.columnColors, ...
                'nColors', obj.nColors);
        end

        function [accepted, x_new, r_new, alpha, bt, stagnationReject] = backtrackingLineSearch(obj, x, dx, rnU, rnW, w)
            [accepted, x_new, r_new, alpha, bt, stagnationReject] = ...
                proc.solver.LineSearch.backtrackingLineSearch( ...
                    @(xp) obj.tryResiduals(xp), x, dx, rnU, rnW, w, ...
                    obj.damping, obj.lineSearchMaxUnweightedIncreaseRatio);
        end

        function dx = solveLinearLM(~, J, b, w)
            dx = proc.solver.LineSearch.solveLinearLM(J, b, w);
        end

        function w = buildEquationWeights(obj, eqNames, nEq, r0)
            opts = struct( ...
                'equationWeights', obj.equationWeights, ...
                'autoScale', obj.autoScale, ...
                'autoScaleMinMagnitude', obj.autoScaleMinMagnitude, ...
                'autoScaleMaxWeightFactor', obj.autoScaleMaxWeightFactor, ...
                'defaultResidualScale', obj.defaultResidualScale, ...
                'flowResidualScale', obj.flowResidualScale, ...
                'temperatureResidualScale', obj.temperatureResidualScale, ...
                'pressureResidualScale', obj.pressureResidualScale);
            w = proc.solver.SolverDiagnostics.buildEquationWeights( ...
                eqNames, nEq, r0, obj.eqTypes, opts);
        end

        function [x, map] = packUnknowns(obj)
            [x, map] = proc.solver.VariablePacker.packUnknowns( ...
                obj.streams, obj.units, obj.ns, obj.nDotMin);
        end

        function buildUnpackMaps(obj)
            obj.unpackMaps = proc.solver.VariablePacker.buildUnpackMaps(obj.map);
        end

        function unpackUnknowns(obj, x)
            bounds = struct('zMin',obj.zMin,'zMax',obj.zMax, ...
                'TMin',obj.TMin,'TMax',obj.TMax,'PMin',obj.PMin,'PMax',obj.PMax);
            proc.solver.VariablePacker.unpackUnknowns( ...
                x, obj.streams, obj.ns, obj.unpackMaps, bounds);
        end

        function debugPrintMixerCompositionConsistency(obj, r, dbg, context)
            proc.solver.SolverDiagnostics.debugPrintMixerCompositionConsistency( ...
                r, dbg, obj.units, context);
        end

        function issues = detectKnownSpecConflicts(obj)
            issues = proc.solver.SolverDiagnostics.detectKnownSpecConflicts( ...
                obj.streams, obj.units);
        end

        function checkInitialJacobianConnectivity(obj, x, r0)
            proc.solver.SolverDiagnostics.checkInitialJacobianConnectivity( ...
                x, r0, @(xp, rp) obj.fdJacobianSafe(xp, rp), obj.map, obj.streams, ...
                obj.nDotMin, obj.jacobianDeadColumnTol, obj.failOnJacobianDeadColumns, ...
                @(msg, varargin) obj.log(msg, varargin{:}));
        end

        function detail = buildFailureReport(obj, ME, stage, iter, r, w, eqNames)
            detail = proc.solver.SolverDiagnostics.buildFailureReport( ...
                ME, stage, iter, r, w, eqNames, obj.logLines, obj.residualEvalCount);
        end
    end
end
