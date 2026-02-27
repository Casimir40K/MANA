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
        unpackZ struct = struct('xIdx',{},'sIdx',{})
        unpackA struct = struct('xIdx',{},'sIdx',{},'comp',{})
        unpackT struct = struct('xIdx',{},'sIdx',{})
        unpackP struct = struct('xIdx',{},'sIdx',{})
        unpackU struct = struct('xIdx',{},'owner',{},'field',{},'sub',{},'lb',{},'ub',{})

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
            nDisabled = 0;
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                if isprop(unit, 'includeNormalizationConstraints')
                    unit.includeNormalizationConstraints = ~obj.removeRedundantNormalizationConstraints;
                    if obj.removeRedundantNormalizationConstraints
                        nDisabled = nDisabled + 1;
                    end
                end
            end
        end

        function [J, accepted] = tryBroydenUpdate(obj, J, s, y)
            accepted = false;
            s2 = s.' * s;
            if ~(isfinite(s2) && s2 > obj.broydenMinStepNorm2)
                return
            end

            Js = J * s;
            u = (y - Js) / s2;
            Jcand = J + u * s.';

            if any(~isfinite(Jcand(:)))
                return
            end

            % Cheap quality check: verify the updated Jacobian can produce
            % a finite linear solve. Avoids the O(n^3) rcond computation.
            n = size(Jcand, 2);
            JTJ = Jcand.' * Jcand;
            lambda = 1e-12 * max(1, trace(JTJ) / max(1, n));
            dxTest = (JTJ + lambda * eye(n)) \ (Jcand.' * y);
            if ~all(isfinite(dxTest))
                return
            end

            J = Jcand;
            accepted = true;
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
            dbg = struct( ...
                'level', max(0, floor(obj.debugLevel)), ...
                'topN', max(1, floor(obj.debugTopN)), ...
                'every', max(0, floor(obj.debugEvery)), ...
                'out', obj.debugOut, ...
                'eqNames', logical(obj.debugEqNames));

            if obj.debug && dbg.level < 1
                dbg.level = 1;
            end

            if isstruct(obj.solverSettings) && isfield(obj.solverSettings, 'debugStruct')
                ds = obj.solverSettings.debugStruct;
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

        function debugPrintIter(obj, iter, rn2, r, dx, alpha, bt, dbg)
            rnInf = norm(r, inf);
            dxn = norm(dx, 2);
            [maxVal, maxIdx] = max(abs(r));
            if isempty(maxIdx), maxIdx = 0; maxVal = NaN; maxSigned = NaN;
            else, maxSigned = r(maxIdx);
            end

            fprintf(dbg.out, 'Iter %3d: ||r||2=%.3e  ||r||inf=%.3e  ||dx||=%.3e  alpha=%.3e  bt=%d  maxEq=%d (|r|=%.3e, r=%+.3e)\n', ...
                iter, rn2, rnInf, dxn, alpha, bt, maxIdx, maxVal, maxSigned);
        end

        function debugPrintTopResiduals(obj, r, dbg, eqNames, context)
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

        function eqNames = buildEquationLabels(obj)
            eqNames = strings(0,1);
            types = zeros(0,1);  % 0=default, 1=flow, 2=temperature, 3=pressure
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                % Use cached equation count instead of calling equations() again
                if ~isempty(obj.eqCounts) && u <= numel(obj.eqCounts)
                    nEq = obj.eqCounts(u);
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
                    % Classify equation type from label (done once, not per-weight-build)
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
            obj.eqTypes = types;
        end

        function J = fdJacobianSafe(obj, x, r0)
            n = numel(x); m = numel(r0);

            % Detect sparsity pattern on first call and compute column coloring
            if isempty(obj.sparsityPattern)
                obj.detectSparsityPattern(x, r0);
            end

            % Use graph-coloring compressed FD if coloring is available
            if obj.nColors > 0 && obj.nColors < n
                J = obj.fdJacobianCompressed(x, r0);
                return
            end

            % Fallback: standard column-by-column FD
            J = obj.fdJacobianColumnwise(x, r0);
        end

        function J = fdJacobianColumnwise(obj, x, r0)
            n = numel(x); m = numel(r0);
            J = zeros(m,n);

            % Pre-compute steps and central-difference flags
            steps = zeros(n, 1);
            isCentral = false(n, 1);
            for k = 1:n
                steps(k) = obj.fdStepForColumn(k, x(k));
                isCentral(k) = obj.useCentralDifferenceForColumn(k);
            end

            % Serial path (standard)
            for k = 1:n
                step = steps(k);
                if isCentral(k)
                    xPlus = x;
                    xMinus = x;
                    xPlus(k) = xPlus(k) + step;
                    xMinus(k) = xMinus(k) - step;
                    [rPlus, okPlus] = obj.tryResiduals(xPlus);
                    [rMinus, okMinus] = obj.tryResiduals(xMinus);

                    if okPlus && okMinus
                        J(:,k) = (rPlus - rMinus) / (2 * step);
                    elseif okPlus
                        J(:,k) = (rPlus - r0) / step;
                    elseif okMinus
                        J(:,k) = (r0 - rMinus) / step;
                    else
                        J(:,k) = 0;
                    end
                else
                    x2 = x;
                    x2(k) = x2(k) + step;
                    [r2, ok] = obj.tryResiduals(x2);
                    if ~ok
                        J(:,k) = 0;
                    else
                        J(:,k) = (r2 - r0) / step;
                    end
                end
            end
        end

        function J = fdJacobianCompressed(obj, x, r0)
            % Graph-coloring compressed finite differences.
            % Columns with non-overlapping sparsity patterns share the same
            % perturbation, reducing residual evaluations from n to nColors.
            n = numel(x); m = numel(r0);
            J = zeros(m, n);

            for c = 1:obj.nColors
                cols = find(obj.columnColors == c);
                if isempty(cols), continue; end

                % Compute per-column steps
                steps = zeros(numel(cols), 1);
                for j = 1:numel(cols)
                    steps(j) = obj.fdStepForColumn(cols(j), x(cols(j)));
                end

                % Perturb all same-color columns simultaneously
                xPert = x;
                for j = 1:numel(cols)
                    xPert(cols(j)) = xPert(cols(j)) + steps(j);
                end

                [rPert, okPert] = obj.tryResiduals(xPert);
                if ~okPert
                    % Fall back to column-by-column for this color group
                    for j = 1:numel(cols)
                        k = cols(j);
                        x2 = x;
                        x2(k) = x2(k) + steps(j);
                        [r2, ok] = obj.tryResiduals(x2);
                        if ok
                            rows = obj.sparsityPattern(:, k);
                            J(rows, k) = (r2(rows) - r0(rows)) / steps(j);
                        end
                    end
                    continue
                end

                % Extract columns from compressed perturbation
                for j = 1:numel(cols)
                    k = cols(j);
                    rows = obj.sparsityPattern(:, k);
                    J(rows, k) = (rPert(rows) - r0(rows)) / steps(j);
                end
            end
        end

        function step = fdStepForColumn(obj, colIdx, xVal)
            % Adaptive FD step sizing based on variable type (B6)
            if colIdx <= numel(obj.map)
                varType = obj.map(colIdx).var;
            else
                varType = '?';
            end
            switch varType
                case 'a'
                    % Composition logits: larger relative step for better sensitivity
                    step = 1e-6 * max(1, abs(xVal));
                case 'T'
                    step = obj.fdEps * max(1, abs(xVal));
                case 'P'
                    step = obj.fdEps * max(1, abs(xVal));
                otherwise
                    step = obj.fdEps * max(1, abs(xVal));
            end
        end

        function detectSparsityPattern(obj, x, r0)
            % Detect Jacobian sparsity by probing each column and recording
            % which rows change. Then compute greedy column coloring.
            n = numel(x); m = numel(r0);
            sp = false(m, n);
            dropTol = 1e-14;

            for k = 1:n
                step = obj.fdStepForColumn(k, x(k));
                x2 = x;
                x2(k) = x2(k) + step;
                [r2, ok] = obj.tryResiduals(x2);
                if ok
                    sp(:, k) = abs(r2 - r0) > dropTol * max(1, abs(r0));
                else
                    sp(:, k) = true;  % conservative: assume dense column
                end
            end

            obj.sparsityPattern = sp;

            % Greedy distance-2 column coloring
            obj.columnColors = obj.greedyColumnColoring(sp);
            obj.nColors = max(obj.columnColors);
            nnzFrac = nnz(sp) / (m * n);
            obj.log('Jacobian sparsity: %d x %d, nnz=%.1f%%, %d colors (vs %d columns, %.1fx compression)', ...
                m, n, nnzFrac*100, obj.nColors, n, n / max(obj.nColors, 1));
        end

        function colors = greedyColumnColoring(~, sp)
            % Greedy distance-2 column coloring for compressed FD.
            % Two columns conflict if they share any nonzero row.
            n = size(sp, 2);
            colors = zeros(n, 1);
            for k = 1:n
                rowsK = sp(:, k);
                % Find columns that conflict with k (share a nonzero row)
                conflictColors = zeros(0, 1);
                for j = 1:k-1
                    if colors(j) > 0 && any(rowsK & sp(:, j))
                        conflictColors(end+1) = colors(j); %#ok<AGROW>
                    end
                end
                % Assign smallest unused color
                c = 1;
                usedColors = unique(conflictColors);
                while any(c == usedColors)
                    c = c + 1;
                end
                colors(k) = c;
            end
        end

        function [accepted, x_new, r_new, alpha, bt, stagnationReject] = backtrackingLineSearch(obj, x, dx, rnU, rnW, w)
            alpha = obj.damping;
            bt = 0;
            accepted = false;
            stagnationReject = false;
            x_new = x;
            r_new = nan(size(dx));

            decreaseTol = 1e-8;
            noiseTol = 1e-14;
            strictTargetW = rnW * (1 - decreaseTol);
            % Keep weighted residual as the primary acceptance criterion.
            % Permit a small unweighted-residual increase to avoid
            % rejecting productive steps when scales are heterogeneous.
            maxTargetU = rnU * (1 + max(0, obj.lineSearchMaxUnweightedIncreaseRatio));
            flatSeen = false;

            while bt < 30
                xCand = x + alpha*dx;
                [rCand, okCand] = obj.tryResiduals(xCand);
                if okCand
                    rnUCand = norm(rCand);
                    rnWCand = norm(w .* rCand);
                    % Accept if weighted norm strictly decreases and the
                    % unweighted norm does not grow beyond a small guard.
                    if rnWCand <= strictTargetW && rnUCand <= maxTargetU
                        accepted = true;
                        x_new = xCand;
                        r_new = rCand;
                        return
                    end

                    if rnWCand <= rnW * (1 + noiseTol) || rnUCand <= rnU * (1 + noiseTol)
                        flatSeen = true;
                    end
                end
                alpha = alpha * 0.5;
                bt = bt + 1;
                if alpha < 1e-10
                    break;
                end
            end

            stagnationReject = flatSeen;
        end

        function dx = solveLinearLM(~, J, b, w)
            Jw = J .* w;
            bw = b .* w;
            n = size(J,2);
            JTJ = Jw.' * Jw;  JTb = Jw.' * bw;
            lambda = 1e-6 * max(1, trace(JTJ)/max(1,n));
            I = eye(n);
            for it = 1:12
                dx = (JTJ + lambda*I) \ JTb;
                if all(isfinite(dx)), return; end
                lambda = lambda * 10;
            end
            dx = zeros(n,1);
        end

        function tf = useCentralDifferenceForColumn(obj, idx)
            scheme = lower(strtrim(char(obj.fdScheme)));
            switch scheme
                case 'central'
                    tf = true;
                case 'mixed'
                    tf = any(idx == obj.fdCentralColumns);
                otherwise
                    tf = false;
            end
        end

        function w = buildEquationWeights(obj, eqNames, nEq, r0)
            if ~isempty(obj.equationWeights)
                ew = obj.equationWeights(:);
                if isscalar(ew)
                    w = repmat(ew, nEq, 1);
                elseif numel(ew) == nEq
                    w = ew;
                else
                    error('equationWeights must be scalar or length %d.', nEq);
                end
            elseif obj.autoScale && nargin >= 4 && ~isempty(r0)
                % Derive per-equation weights from initial residual
                % magnitudes so that all equations contribute equally.
                mag = abs(r0(1:min(nEq, numel(r0))));
                w = 1 ./ max(mag, obj.autoScaleMinMagnitude);
                if numel(w) < nEq
                    w(end+1:nEq) = 1;
                end

                % Cap dynamic range so one tiny initial residual cannot
                % dominate the weighted merit function and mislead line
                % search acceptance.
                wMin = min(w);
                wMax = wMin * max(1, obj.autoScaleMaxWeightFactor);
                w = min(w, wMax);
            else
                % Use pre-classified equation types for fast weight assignment
                w = ones(nEq,1) / max(obj.defaultResidualScale, eps);
                if ~isempty(obj.eqTypes) && numel(obj.eqTypes) == nEq
                    wFlow = 1 / max(obj.flowResidualScale, eps);
                    wTemp = 1 / max(obj.temperatureResidualScale, eps);
                    wPres = 1 / max(obj.pressureResidualScale, eps);
                    w(obj.eqTypes == 1) = wFlow;
                    w(obj.eqTypes == 2) = wTemp;
                    w(obj.eqTypes == 3) = wPres;
                else
                    % Fallback: string matching (slow path)
                    for i = 1:nEq
                        lbl = lower(char(eqNames(min(i, numel(eqNames)))));
                        if contains(lbl, 'pressure') || contains(lbl, ' p') || contains(lbl, 'dp')
                            w(i) = 1 / max(obj.pressureResidualScale, eps);
                        elseif contains(lbl, 'temp') || contains(lbl, 'enthalpy') || contains(lbl, 'energy')
                            w(i) = 1 / max(obj.temperatureResidualScale, eps);
                        elseif contains(lbl, 'flow') || contains(lbl, 'mass') || contains(lbl, 'mole') || contains(lbl, 'n_dot')
                            w(i) = 1 / max(obj.flowResidualScale, eps);
                        end
                    end
                end
            end
            w(~isfinite(w) | w <= 0) = 1;
        end

        function [x, map] = packUnknowns(obj)
            x = []; map = struct('streamIndex',{},'var',{},'subIndex',{},'unitIndex',{},'bounds',{},'owner',{},'field',{});
            for si = 1:numel(obj.streams)
                s = obj.streams{si};
                if obj.isUnknownScalar(s,'n_dot')
                    nd = obj.safeInit(s.n_dot,1.0);
                    x(end+1,1) = log(max(nd,obj.nDotMin));
                    map(end+1) = struct('streamIndex',si,'var','z','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
                if obj.anyYUnknown(s)
                    [packIdx, a0] = obj.initialCompositionLogits(s);

                    % Gauge-fixing for composition logits:
                    % Only (nUnknownComponents-1) logits are packed and one
                    % unknown component is anchored at zero in unpackUnknowns().
                    % This removes the softmax shift invariance so we do not
                    % re-introduce redundant composition DOFs.
                    for j = 1:numel(packIdx)
                        x(end+1,1) = a0(j);
                        map(end+1) = struct('streamIndex',si,'var','a','subIndex',packIdx(j), 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                    end
                end
                knownT = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'T')&&...
                    islogical(s.known.T)&&isscalar(s.known.T)&&s.known.T;
                if ~knownT
                    x(end+1,1) = obj.safeInit(s.T,300);
                    map(end+1) = struct('streamIndex',si,'var','T','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
                knownP = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'P')&&...
                    islogical(s.known.P)&&isscalar(s.known.P)&&s.known.P;
                if ~knownP
                    x(end+1,1) = obj.safeInit(s.P,1e5);
                    map(end+1) = struct('streamIndex',si,'var','P','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
            end

            % Optional unit-level manipulated unknowns (e.g., Adjust blocks)
            for ui = 1:numel(obj.units)
                u = obj.units{ui};
                if ~ismethod(u, 'unknownSpecs')
                    continue;
                end
                specs = u.unknownSpecs();
                if isempty(specs)
                    continue;
                end
                if ~isstruct(specs)
                    error('unknownSpecs() for %s must return a struct array.', class(u));
                end
                for k = 1:numel(specs)
                    s = specs(k);
                    x(end+1,1) = obj.safeInit(s.initial, 0); %#ok<AGROW>
                    map(end+1) = struct( ...
                        'streamIndex', NaN, ...
                        'var', 'u', ...
                        'subIndex', obj.structFieldOr(s, 'index', NaN), ...
                        'unitIndex', ui, ...
                        'bounds', [obj.structFieldOr(s, 'lower', -Inf), obj.structFieldOr(s, 'upper', Inf)], ...
                        'owner', s.owner, ...
                        'field', s.field); %#ok<GFLD>
                end
            end
        end

        function buildUnpackMaps(obj)
            % Pre-compute typed index maps for fast unpackUnknowns.
            % Called once after packUnknowns.
            nMap = numel(obj.map);
            obj.unpackZ = struct('xIdx',{},'sIdx',{});
            obj.unpackA = struct('xIdx',{},'sIdx',{},'comp',{});
            obj.unpackT = struct('xIdx',{},'sIdx',{});
            obj.unpackP = struct('xIdx',{},'sIdx',{});
            obj.unpackU = struct('xIdx',{},'owner',{},'field',{},'sub',{},'lb',{},'ub',{});
            for k = 1:nMap
                m = obj.map(k);
                switch m.var
                    case 'z'
                        obj.unpackZ(end+1) = struct('xIdx',k,'sIdx',m.streamIndex);
                    case 'a'
                        obj.unpackA(end+1) = struct('xIdx',k,'sIdx',m.streamIndex,'comp',m.subIndex);
                    case 'T'
                        obj.unpackT(end+1) = struct('xIdx',k,'sIdx',m.streamIndex);
                    case 'P'
                        obj.unpackP(end+1) = struct('xIdx',k,'sIdx',m.streamIndex);
                    case 'u'
                        obj.unpackU(end+1) = struct('xIdx',k,'owner',m.owner,'field',m.field,...
                            'sub',m.subIndex,'lb',m.bounds(1),'ub',m.bounds(2));
                end
            end
        end

        function unpackUnknowns(obj, x)
            nS = numel(obj.streams);
            z = nan(nS,1);
            a = nan(nS, obj.ns);

            % Typed index maps: direct indexing without switch per entry
            for i = 1:numel(obj.unpackZ)
                m = obj.unpackZ(i);
                z(m.sIdx) = x(m.xIdx);
            end
            for i = 1:numel(obj.unpackA)
                m = obj.unpackA(i);
                a(m.sIdx, m.comp) = x(m.xIdx);
            end
            for i = 1:numel(obj.unpackT)
                m = obj.unpackT(i);
                obj.streams{m.sIdx}.T = x(m.xIdx);
            end
            for i = 1:numel(obj.unpackP)
                m = obj.unpackP(i);
                obj.streams{m.sIdx}.P = x(m.xIdx);
            end
            for i = 1:numel(obj.unpackU)
                m = obj.unpackU(i);
                xi = min(max(x(m.xIdx), m.lb), m.ub);
                if isnan(m.sub)
                    m.owner.(m.field) = xi;
                else
                    arr = m.owner.(m.field);
                    arr(m.sub) = xi;
                    m.owner.(m.field) = arr;
                end
            end

            for si = 1:nS
                s = obj.streams{si};
                if ~isnan(z(si))
                    s.n_dot = exp(min(max(z(si),obj.zMin),obj.zMax));
                end
                if any(isfinite(a(si,:)))
                    s.y = obj.reconstructComposition(s, a(si,:));
                end
                if ~isnan(s.T), s.T = min(max(s.T,obj.TMin),obj.TMax); end
                if ~isnan(s.P), s.P = min(max(s.P,obj.PMin),obj.PMax); end
            end
        end


        function v = structFieldOr(~, s, fieldName, defaultValue)
            if isfield(s, fieldName)
                v = s.(fieldName);
            else
                v = defaultValue;
            end
        end

        function tf = isUnknownScalar(~,s,fn)
            if isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,fn)
                v=s.known.(fn);
                if islogical(v)&&isscalar(v), tf=~v; else, tf=true; end
            else, tf=true;
            end
        end

        function tf = anyYUnknown(obj,s)
            unknownIdx = obj.unknownCompositionIndices(s);
            tf = ~isempty(unknownIdx);
        end

        function knownMask = compositionKnownMask(obj, s)
            if isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'y')
                ky=s.known.y;
                if islogical(ky)&&numel(ky)==obj.ns
                    knownMask = logical(reshape(ky,1,[]));
                    return;
                end
            end

            knownMask = false(1,obj.ns);
        end

        function unknownIdx = unknownCompositionIndices(obj, s)
            knownMask = obj.compositionKnownMask(s);
            unknownIdx = find(~knownMask);
        end

        function [packIdx, a0] = initialCompositionLogits(obj, s)
            unknownIdx = obj.unknownCompositionIndices(s);
            nUnknown = numel(unknownIdx);
            if nUnknown <= 1
                packIdx = [];
                a0 = [];
                return;
            end

            y0 = s.y;
            if isempty(y0) || any(~isfinite(y0)) || numel(y0) ~= obj.ns
                y0 = ones(1,obj.ns) / obj.ns;
            end
            y0 = max(reshape(y0,1,[]), 0);

            knownMask = obj.compositionKnownMask(s);
            knownSum = sum(y0(knownMask));
            remaining = max(1 - knownSum, 0);

            yUnknown = y0(unknownIdx);
            yUnknown = max(yUnknown, 0);
            if sum(yUnknown) <= 0
                yUnknown = ones(1,nUnknown) / nUnknown;
            else
                yUnknown = yUnknown / sum(yUnknown);
            end

            % Represent unknown composition as remaining * softmax(aUnknown).
            % Pack only first (nUnknown-1) entries and anchor last one to 0.
            if remaining > 0
                pUnknown = yUnknown;
            else
                pUnknown = ones(1,nUnknown) / nUnknown;
            end

            aUnknown = log(max(pUnknown,1e-12));
            anchor = aUnknown(end);
            aUnknown = aUnknown - anchor;

            packIdx = unknownIdx(1:end-1);
            a0 = aUnknown(1:end-1).';
        end

        function y = reconstructComposition(obj, s, packedA)
            y = s.y;
            if isempty(y) || any(~isfinite(y)) || numel(y) ~= obj.ns
                y = ones(obj.ns,1) / obj.ns;
            end
            y = reshape(y,[],1);

            knownMask = obj.compositionKnownMask(s);
            unknownIdx = find(~knownMask);
            nUnknown = numel(unknownIdx);
            if nUnknown == 0
                y = obj.normalizeSimplex(y);
                obj.warnIfCompositionNotNormalized(s, y);
                return;
            end

            knownSum = sum(y(knownMask));
            remaining = 1 - knownSum;

            if nUnknown == 1
                y(unknownIdx) = remaining;
                y = y / sum(y);
                obj.warnIfCompositionNotNormalized(s, y);
                return;
            end

            % softmax() expects only the packed free logits (nUnknown-1).
            % It appends the anchored final logit internally.
            aUnknown = zeros(nUnknown-1,1);
            packIdx = unknownIdx(1:end-1);
            for j = 1:numel(packIdx)
                comp = packIdx(j);
                if isfinite(packedA(comp))
                    aUnknown(j) = packedA(comp);
                end
            end

            % Gauge-fixed softmax: last unknown component is anchored to 0,
            % so only (nUnknown-1) independent logits are required.
            y(unknownIdx) = remaining .* obj.softmax(aUnknown);
            y = y / sum(y);
            obj.warnIfCompositionNotNormalized(s, y);
        end

        function v = safeInit(~,c,fb)
            if isempty(c)||isnan(c), v=fb; else, v=c; end
        end

        function y = softmax(~,aPacked)
            % Reconstruct full logits by anchoring the final component at 0,
            % then apply stable shift-by-max softmax.
            aFull = [aPacked(:); 0];
            aFull = aFull - max(aFull);
            e = exp(aFull);
            y = e / sum(e);
        end

        function y = normalizeSimplex(~,y)
            y = y(:);
            s = sum(y);
            if ~isfinite(s) || s == 0
                y = ones(numel(y),1) / numel(y);
            else
                y = y / s;
            end
        end

        function warnIfCompositionNotNormalized(obj, s, y)
            if obj.debugLevel < 1
                return
            end
            sumY = sum(y);
            delta = sumY - 1;
            if isfinite(delta) && abs(delta) > 1e-10
                fprintf(obj.debugOut, 'WARN composition normalization drift: stream=%s, sum(y)-1=%+.3e\n', ...
                    string(s.name), delta);
            end
        end

        function debugPrintMixerCompositionConsistency(obj, r, dbg, context)
            [mixer, dominantEq, dominantVal] = obj.findDominantMixer(r);
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

        function issues = detectKnownSpecConflicts(obj)
            issues = strings(0,1);
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                uName = string(class(unit));
                if ismethod(unit, 'describe')
                    try
                        uName = string(unit.describe());
                    catch
                        uName = string(class(unit));
                    end
                end

                if isprop(unit, 'inlet') && isprop(unit, 'outlet')
                    sIn = unit.inlet;
                    sOut = unit.outlet;

                    if obj.isKnownFlagTrue(sIn, 'T') && obj.isKnownFlagTrue(sOut, 'T')
                        if abs(sOut.T - sIn.T) > 1e-9
                            issues(end+1,1) = sprintf('%s has both inlet/outlet T marked Known but T_out-T_in=%+.3e K.', uName, sOut.T - sIn.T);
                        end
                    end
                    if obj.isKnownFlagTrue(sIn, 'P') && obj.isKnownFlagTrue(sOut, 'P')
                        if abs(sOut.P - sIn.P) > 1e-6
                            issues(end+1,1) = sprintf('%s has both inlet/outlet P marked Known but P_out-P_in=%+.3e Pa.', uName, sOut.P - sIn.P);
                        end
                    end
                end

                if isprop(unit, 'Tout') && isfinite(unit.Tout) && isprop(unit, 'outlet')
                    sOut = unit.outlet;
                    if obj.isKnownFlagTrue(sOut, 'T') && abs(sOut.T - unit.Tout) > 1e-9
                        issues(end+1,1) = sprintf('%s Tout=%.6g K conflicts with Known outlet T=%.6g K on stream %s.', ...
                            uName, unit.Tout, sOut.T, string(sOut.name));
                    end
                end

                if isprop(unit, 'Pout') && isfinite(unit.Pout) && isprop(unit, 'outlet')
                    sOut = unit.outlet;
                    if obj.isKnownFlagTrue(sOut, 'P') && abs(sOut.P - unit.Pout) > 1e-6
                        issues(end+1,1) = sprintf('%s Pout=%.6g Pa conflicts with Known outlet P=%.6g Pa on stream %s.', ...
                            uName, unit.Pout, sOut.P, string(sOut.name));
                    end
                end
            end
        end

        function tf = isKnownFlagTrue(~, s, field)
            tf = false;
            if ~(isprop(s,'known') && isstruct(s.known) && isfield(s.known, field))
                return
            end
            v = s.known.(field);
            tf = islogical(v) && isscalar(v) && v;
        end

        function checkInitialJacobianConnectivity(obj, x, r0)
            if isempty(x)
                return
            end

            J0 = obj.fdJacobianSafe(x, r0);
            colNormInf = max(abs(J0), [], 1);
            dead = find(colNormInf <= obj.jacobianDeadColumnTol | ~isfinite(colNormInf));
            if isempty(dead)
                return
            end

            % Composition logits can appear disconnected at initialization
            % when the associated stream flow starts near zero. In that
            % regime component-flow equations are numerically flat in y,
            % but the DOF is still physically connected once n_dot lifts.
            keep = true(size(dead));
            for i = 1:numel(dead)
                k = dead(i);
                m = obj.map(k);
                if strcmp(m.var, 'a') && obj.isNearZeroFlowStream(m.streamIndex)
                    keep(i) = false;
                    obj.log(['Jacobian dead-column candidate ignored: x(%d) %s ' ...
                        '(near-zero stream flow n_dot=%.3e).'], ...
                        k, obj.describeUnknown(m), obj.streams{m.streamIndex}.n_dot);
                end
            end

            dead = dead(keep);
            if isempty(dead)
                return
            end

            msgLines = strings(numel(dead),1);
            for i = 1:numel(dead)
                k = dead(i);
                msgLines(i) = obj.describeUnknown(obj.map(k));
                obj.log('Jacobian dead-column candidate: x(%d) %s (||J(:,k)||_inf=%.3e)', ...
                    k, msgLines(i), colNormInf(k));
            end

            msg = sprintf(['Detected %d unknown(s) with near-zero initial Jacobian columns. ' ...
                'This indicates disconnected DOFs, conflicting constraints, or numerically flat equations.'], numel(dead));
            if obj.failOnJacobianDeadColumns
                error('%s Unknown(s): %s', msg, strjoin(cellstr(msgLines), '; '));
            else
                warning('%s Unknown(s): %s', msg, strjoin(cellstr(msgLines), '; '));
            end
        end

        function tf = isNearZeroFlowStream(obj, streamIndex)
            tf = false;
            if ~isfinite(streamIndex) || streamIndex < 1 || streamIndex > numel(obj.streams)
                return
            end

            s = obj.streams{streamIndex};
            if ~isprop(s, 'n_dot') || ~isfinite(s.n_dot)
                return
            end

            tf = abs(s.n_dot) <= max(1e3 * obj.nDotMin, 1e-9);
        end

        function txt = describeUnknown(~, m)
            if strcmp(m.var, 'u')
                txt = sprintf('[unit %d] manipulated %s.%s', m.unitIndex, class(m.owner), m.field);
                return
            end

            si = m.streamIndex;
            switch m.var
                case 'z'
                    txt = sprintf('[stream %d] n_dot(log)', si);
                case 'a'
                    txt = sprintf('[stream %d] composition logit comp=%d', si, m.subIndex);
                case 'T'
                    txt = sprintf('[stream %d] temperature', si);
                case 'P'
                    txt = sprintf('[stream %d] pressure', si);
                otherwise
                    txt = sprintf('[stream %d] var=%s', si, m.var);
            end
        end

        function detail = buildFailureReport(obj, ME, stage, iter, r, w, eqNames)
            header = "HERE IS WHAT HAPPENED";
            lines = strings(0,1);
            lines(end+1,1) = header;
            lines(end+1,1) = string(repmat('=', 1, strlength(header)));
            lines(end+1,1) = sprintf('Failure stage: %s', stage);
            lines(end+1,1) = sprintf('Iteration: %d', iter);
            lines(end+1,1) = sprintf('Reason: %s', string(ME.message));
            lines(end+1,1) = sprintf('Residual evaluations: %d', obj.residualEvalCount);

            if ~isempty(ME.stack)
                lines(end+1,1) = 'Stack trace (most recent first):';
                nStack = min(6, numel(ME.stack));
                for i = 1:nStack
                    st = ME.stack(i);
                    lines(end+1,1) = sprintf('  at %s (line %d)', string(st.name), st.line);
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
                lines(end+1,1) = obj.summarizeTopResiduals(r, eqNames, 10);
            else
                lines(end+1,1) = 'Residual norms: unavailable (failure occurred before initial residual evaluation).';
            end

            lines(end+1,1) = 'Recent solver log lines:';
            nLog = numel(obj.logLines);
            nTail = min(12, nLog);
            if nTail == 0
                lines(end+1,1) = '  (none)';
            else
                for i = nLog-nTail+1:nLog
                    lines(end+1,1) = "  - " + obj.logLines(i);
                end
            end

            detail = strjoin(lines, newline);
        end

        function txt = summarizeTopResiduals(~, r, eqNames, topN)
            if nargin < 4 || isempty(topN)
                topN = 10;
            end
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

        function [dominantMixer, eqIdx, eqVal] = findDominantMixer(obj, r)
            dominantMixer = [];
            eqIdx = NaN;
            eqVal = NaN;
            cursor = 1;
            bestAbs = -Inf;
            for u = 1:numel(obj.units)
                unit = obj.units{u};
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
    end
end
