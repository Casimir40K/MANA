classdef DebugController < handle
    %DEBUGCONTROLLER  Debug popup window and diagnostic actions.
    %
    %   Owns the debug figure, controls, and log area.  Receives
    %   lastSolver / buildFlowsheetFcn from the app so it can run
    %   diagnostics without coupling back to MathLabApp internals.

    properties
        DebugFig
        DebugLevelDD
        DebugTopNField
        DebugEveryField
        DebugEqNamesCheck
        DebugLogArea

        debugSettings struct = struct('debugLevel',0,'debugTopN',10,'debugEvery',0,'debugEqNames',true)

        % Injected handles
        getLastSolver       % function_handle: () -> solver | []
        buildFlowsheetFcn   % function_handle: () -> Flowsheet
        openUnitTablePopupFcn  % function_handle: () -> void
    end

    methods
        function obj = DebugController(getLastSolver, buildFlowsheetFcn, openUnitTablePopupFcn)
            obj.getLastSolver = getLastSolver;
            obj.buildFlowsheetFcn = buildFlowsheetFcn;
            if nargin >= 3
                obj.openUnitTablePopupFcn = openUnitTablePopupFcn;
            else
                obj.openUnitTablePopupFcn = @() [];
            end
        end

        function openPopup(obj)
            if ~isempty(obj.DebugFig) && isvalid(obj.DebugFig)
                obj.DebugFig.Visible = 'on';
                return;
            end

            obj.DebugFig = uifigure('Name','MathLab — Debug Tools', ...
                'Position',[150 120 620 520], 'Color',[0.97 0.97 0.98]);
            obj.DebugFig.CloseRequestFcn = @(src,~) obj.onClosed(src);

            gl = uigridlayout(obj.DebugFig, [4 1], ...
                'RowHeight',{28, 'fit', 'fit', '1x'}, 'Padding',[10 10 10 10], 'RowSpacing',8);

            uilabel(gl, 'Text','Debug & Diagnostics', 'FontWeight','bold', 'FontSize',14);

            solverP = uipanel(gl, 'Title','Solver Debug Settings', 'FontWeight','bold');
            sg = uigridlayout(solverP, [4 4], 'ColumnWidth',{'fit','1x','fit','1x'}, ...
                'RowHeight',{28,28,28,28}, 'Padding',[8 8 8 8], 'RowSpacing',4, 'ColumnSpacing',8);

            uilabel(sg,'Text','Debug level:','FontWeight','bold');
            obj.DebugLevelDD = uidropdown(sg, 'Items',{'0 — off','1 — summary','2 — top residuals','3 — periodic'}, 'Value','0 — off');
            uilabel(sg,'Text','Top N equations:','FontWeight','bold');
            obj.DebugTopNField = uieditfield(sg, 'numeric', 'Value',10, 'Limits',[1 100], 'RoundFractionalValues','on');

            uilabel(sg,'Text','Print every N iters:','FontWeight','bold');
            obj.DebugEveryField = uieditfield(sg, 'numeric', 'Value',0, 'Limits',[0 10000], 'RoundFractionalValues','on');
            uilabel(sg,'Text','Show eq. labels:','FontWeight','bold');
            obj.DebugEqNamesCheck = uicheckbox(sg, 'Text','', 'Value',true);

            uilabel(sg,'Text','');
            uilabel(sg,'Text','');
            uilabel(sg,'Text','');
            uibutton(sg, 'push', 'Text','Apply to Next Solve', ...
                'FontWeight','bold', 'BackgroundColor',[0.88 0.93 0.85], ...
                'ButtonPushedFcn',@(~,~) obj.applySettings());

            actionsP = uipanel(gl, 'Title','Diagnostic Actions', 'FontWeight','bold');
            ag = uigridlayout(actionsP, [2 3], 'ColumnWidth',{'1x','1x','1x'}, ...
                'RowHeight',{30,30}, 'Padding',[8 8 8 8], 'RowSpacing',4, 'ColumnSpacing',8);

            uibutton(ag, 'push', 'Text','Show Jacobian Sparsity', ...
                'ButtonPushedFcn',@(~,~) obj.showJacobianSparsity());
            uibutton(ag, 'push', 'Text','Show Worst Residuals', ...
                'ButtonPushedFcn',@(~,~) obj.showWorstResiduals());
            uibutton(ag, 'push', 'Text','Show DOF Analysis', ...
                'ButtonPushedFcn',@(~,~) obj.showDOF());
            uibutton(ag, 'push', 'Text','Dump Solver State', ...
                'ButtonPushedFcn',@(~,~) obj.dumpSolverState());
            uibutton(ag, 'push', 'Text','Show Pole Summary', ...
                'ButtonPushedFcn',@(~,~) obj.showPoles());
            uibutton(ag, 'push', 'Text','Open Unit Table', ...
                'ButtonPushedFcn',@(~,~) obj.openUnitTablePopupFcn());

            obj.DebugLogArea = uitextarea(gl, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',11, ...
                'Value',{'Debug output will appear here.'; ''; 'Use the actions above or apply debug settings before solving.'});
        end

        function appendLog(obj, msg)
            if isempty(obj.DebugLogArea) || ~isvalid(obj.DebugLogArea), return; end
            vals = obj.DebugLogArea.Value;
            if ischar(vals), vals = {vals}; end
            ts = datestr(now, 'HH:MM:SS'); %#ok
            vals{end+1} = sprintf('[%s] %s', ts, msg);
            if numel(vals) > 100, vals = vals(end-99:end); end
            obj.DebugLogArea.Value = vals;
        end

        function s = getSettings(obj)
            s = obj.debugSettings;
        end
    end

    methods (Access = private)
        function onClosed(obj, src)
            if ~isempty(src) && isvalid(src), delete(src); end
            obj.DebugFig = [];
        end

        function applySettings(obj)
            levelStr = obj.DebugLevelDD.Value;
            level = str2double(levelStr(1));
            topN = round(obj.DebugTopNField.Value);
            every = round(obj.DebugEveryField.Value);
            eqNames = obj.DebugEqNamesCheck.Value;
            obj.debugSettings = struct('debugLevel',level,'debugTopN',topN,'debugEvery',every,'debugEqNames',eqNames);
            msg = sprintf('Debug settings applied: level=%d, topN=%d, every=%d, eqNames=%s', ...
                level, topN, every, ui.AppUtils.ternary(eqNames, 'on', 'off'));
            obj.appendLog(msg);
        end

        function showJacobianSparsity(obj)
            solver = obj.getLastSolver();
            if isempty(solver), obj.appendLog('No solver available. Run solve first.'); return; end
            try
                st = solver.localStabilityProxy();
                J = st.J;
                nz = nnz(abs(J) > 1e-15);
                tot = numel(J);
                density = nz / max(1,tot) * 100;
                obj.appendLog(sprintf('Jacobian: %dx%d, %d non-zero (%.1f%% density)', size(J,1), size(J,2), nz, density));
                obj.appendLog(sprintf('  Condition number: %.3e', cond(J)));
                obj.appendLog(sprintf('  Rank: %d / %d', rank(J), min(size(J))));
            catch ME
                obj.appendLog(sprintf('Jacobian analysis failed: %s', ME.message));
            end
        end

        function showWorstResiduals(obj)
            solver = obj.getLastSolver();
            if isempty(solver), obj.appendLog('No solver available. Run solve first.'); return; end
            try
                obj.appendLog('--- Residual Summary ---');
                obj.appendLog(sprintf('  Final residual: %.4e', solver.finalResidual));
                if ~isempty(solver.residualHistory)
                    rh = solver.residualHistory(isfinite(solver.residualHistory));
                    obj.appendLog(sprintf('  Residual history: %d points', numel(rh)));
                    obj.appendLog(sprintf('  Initial: %.4e | Final: %.4e', rh(1), rh(end)));
                    if numel(rh) >= 2
                        ratio = rh(end) / max(rh(1), eps);
                        obj.appendLog(sprintf('  Reduction ratio: %.4e', ratio));
                    end
                end
                if ~isempty(solver.weightedResidualHistory)
                    wrh = solver.weightedResidualHistory(isfinite(solver.weightedResidualHistory));
                    if ~isempty(wrh)
                        obj.appendLog(sprintf('  Final weighted residual: %.4e', wrh(end)));
                    end
                end
            catch ME
                obj.appendLog(sprintf('Residual analysis failed: %s', ME.message));
            end
        end

        function showDOF(obj)
            try
                fs = obj.buildFlowsheetFcn();
                [nEq, nUnk, dof] = fs.checkDOF();
                obj.appendLog(sprintf('DOF Analysis: %d equations, %d unknowns, DOF=%d', nEq, nUnk, dof));
                if dof == 0
                    obj.appendLog('  System is exactly determined.');
                elseif dof > 0
                    obj.appendLog(sprintf('  Under-specified by %d (need more specs).', dof));
                else
                    obj.appendLog(sprintf('  Over-specified by %d (too many specs).', abs(dof)));
                end
            catch ME
                obj.appendLog(sprintf('DOF analysis failed: %s', ME.message));
            end
        end

        function dumpSolverState(obj)
            solver = obj.getLastSolver();
            if isempty(solver), obj.appendLog('No solver available. Run solve first.'); return; end
            try
                obj.appendLog('--- Solver State Dump ---');
                obj.appendLog(sprintf('  Converged: %s', ui.AppUtils.ternary(solver.converged,'yes','no')));
                obj.appendLog(sprintf('  Exit flag: %s', solver.exitFlag));
                obj.appendLog(sprintf('  Final residual: %.4e', solver.finalResidual));
                obj.appendLog(sprintf('  Iterations: %d', numel(solver.residualHistory)-1));
                try
                    st = solver.localStabilityProxy();
                    obj.appendLog(sprintf('  Unknowns: %d', st.nUnknowns));
                    obj.appendLog(sprintf('  Equations: %d', st.nEquations));
                catch
                    obj.appendLog('  Unknowns/Equations: unavailable');
                end
                if ~isempty(solver.residualHistory)
                    rh = solver.residualHistory(isfinite(solver.residualHistory));
                    obj.appendLog(sprintf('  Residual range: [%.3e, %.3e]', min(rh), max(rh)));
                end
                outDir = fullfile(pwd, 'output');
                if ~exist(outDir, 'dir'), mkdir(outDir); end
                stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok
                outFile = fullfile(outDir, sprintf('debug_dump_%s.mat', stamp));
                solverDump = solver; %#ok<NASGU>
                save(outFile, 'solverDump');
                obj.appendLog(sprintf('  Full dump saved: %s', outFile));
            catch ME
                obj.appendLog(sprintf('Dump failed: %s', ME.message));
            end
        end

        function showPoles(obj)
            solver = obj.getLastSolver();
            if isempty(solver), obj.appendLog('No solver available. Run solve first.'); return; end
            try
                st = solver.localStabilityProxy();
                poles = st.poles;
                nStable = sum(real(poles) < 0);
                nUnstable = sum(real(poles) >= 0);
                obj.appendLog(sprintf('--- Pole Summary (%d total) ---', numel(poles)));
                obj.appendLog(sprintf('  Stable: %d | Unstable: %d', nStable, nUnstable));
                obj.appendLog(sprintf('  Max Re(pole): %.4e', st.maxReal));
                obj.appendLog(sprintf('  Min Re(pole): %.4e', st.minReal));
                [~, idx] = sort(real(poles), 'descend');
                topN = min(5, numel(poles));
                obj.appendLog(sprintf('  Top %d most unstable:', topN));
                for i = 1:topN
                    p = poles(idx(i));
                    obj.appendLog(sprintf('    %+.4e %+.4ej', real(p), imag(p)));
                end
            catch ME
                obj.appendLog(sprintf('Pole analysis failed: %s', ME.message));
            end
        end
    end
end
