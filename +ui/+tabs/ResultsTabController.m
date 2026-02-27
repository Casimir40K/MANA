classdef ResultsTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = ResultsTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function refreshResultsTable(obj)
            axesHandle = obj.Services.getResultsAxes();
            if isempty(axesHandle) || ~isvalid(axesHandle)
                return;
            end

            cla(axesHandle, 'reset');
            yyaxis(axesHandle,'left');
            yyaxis(axesHandle,'right');
            yyaxis(axesHandle,'left');
            hold(axesHandle,'on');
            grid(axesHandle,'on');
            axesHandle.XScale = obj.Services.getResultsXScale();
            axesHandle.YScale = obj.Services.getResultsYScale();

            plotted = false;
            for idx = 1:4
                plotted = obj.Services.plotResultsConfig(idx) || plotted;
            end

            if plotted
                legendLocation = obj.Services.getResultsLegendLocation();
                if strcmp(legendLocation,'off')
                    legend(axesHandle,'off');
                else
                    legend(axesHandle,'Location',legendLocation);
                end
                obj.Services.setResultsPlotStatus(sprintf('Snapshots: %d | smoothing: %s(%d)', ...
                    obj.Services.getResultsSnapshotCount(), obj.Services.getResultsSmoothingMode(), round(obj.Services.getResultsSmoothWindow())));
            else
                obj.Services.setResultsPlotStatus('No plottable data. Solve first and verify target/variables.');
            end
            hold(axesHandle,'off');
            obj.Services.refreshResultsTargetOptions();
        end

        function refreshResultsSummaryModel(obj)
            prevSummary = obj.Services.getResultsSummary();
            prevResidual = prevSummary.residual;
            summary = struct('status','Not solved','residual',NaN,'iterations',0, ...
                'streamKey','-','unitKey','-','streamText','-','unitText','-','deltaText','-');
            lastSolver = obj.Services.getLastSolver();
            if isempty(lastSolver)
                obj.Services.setResultsSummary(summary);
                return;
            end

            iters = 0;
            try
                iters = max(0, numel(lastSolver.residualHistory)-1);
            catch
                iters = 0;
            end
            residual = NaN;
            try
                if ~isempty(lastSolver.residualHistory)
                    residual = lastSolver.residualHistory(end);
                end
            catch
            end
            try
                if lastSolver.converged
                    summary.status = 'Converged';
                else
                    summary.status = 'Non-converged';
                end
            catch
                summary.status = 'Solved';
            end
            summary.residual = residual;
            summary.iterations = iters;

            lastFlowsheet = obj.Services.getLastFlowsheet();
            if ~isempty(lastFlowsheet) && ~isempty(lastFlowsheet.streamDisplayNames)
                nm = char(string(lastFlowsheet.streamDisplayNames{1}));
                summary.streamKey = nm;
                sref = lastFlowsheet.streamDisplayRefs{1};
                summary.streamText = sprintf('%s | %s=%.4g | %s=%.4g | %s=%.4g', nm, ...
                    obj.Services.unitLabel('flow','n_dot'), obj.Services.fromSI(sref.n_dot,'flow'), ...
                    obj.Services.unitLabel('temperature','T'), obj.Services.fromSI(sref.T,'temperature'), ...
                    obj.Services.unitLabel('pressure','P'), obj.Services.fromSI(sref.P,'pressure'));
            end

            if ~isempty(lastFlowsheet) && ~isempty(lastFlowsheet.units)
                u = lastFlowsheet.units{1};
                uk = sprintf('U1_%s', obj.Services.shortTypeName(u));
                summary.unitKey = uk;
                upairs = obj.Services.unitObjectResultPairs(u);
                if isempty(upairs)
                    summary.unitText = sprintf('%s | no reportable metrics', uk);
                else
                    summary.unitText = sprintf('%s | %s: %s', uk, upairs{1,1}, obj.Services.formatSpecValue(upairs{1,2}));
                end
            end

            if isfinite(prevResidual) && isfinite(summary.residual)
                d = summary.residual - prevResidual;
                summary.deltaText = sprintf('Residual delta vs previous run: %+0.3e', d);
            else
                summary.deltaText = 'Residual delta vs previous run: n/a';
            end
            obj.Services.setResultsSummary(summary);
        end

        function refreshResultsSummaryPanel(obj)
            s = obj.Services.getResultsSummary();

            statusBanner = obj.Services.getResultsTablesStatusBanner();
            if ~isempty(statusBanner) && isvalid(statusBanner)
                statusColor = [0.6 0.1 0.1];
                if strcmp(s.status, 'Converged'), statusColor = [0.1 0.5 0.1]; end
                statusBanner.Text = sprintf('Status: %s', s.status);
                statusBanner.FontColor = statusColor;
            end

            residualLabel = obj.Services.getResultsTablesResidualLabel();
            if ~isempty(residualLabel) && isvalid(residualLabel)
                if isfinite(s.residual)
                    residualLabel.Text = sprintf('Residual: %.3e', s.residual);
                else
                    residualLabel.Text = 'Residual: -';
                end
            end

            iterLabel = obj.Services.getResultsTablesIterLabel();
            if ~isempty(iterLabel) && isvalid(iterLabel)
                iterLabel.Text = sprintf('Iterations: %d', s.iterations);
            end
        end

        function refreshResultsTablesTab(obj)
            streamTable = obj.Services.getResultsStreamTable();
            if ~isempty(streamTable) && isvalid(streamTable)
                Ts = obj.Services.buildDisplayStreamTable();
                streamTable.Data = Ts;
                streamTable.ColumnName = Ts.Properties.VariableNames;
            end

            unitTable = obj.Services.getResultsUnitTable();
            if ~isempty(unitTable) && isvalid(unitTable)
                Tu = obj.Services.buildUnitResultsTable();
                unitTable.Data = Tu;
                unitTable.ColumnName = Tu.Properties.VariableNames;
            end

            statusLabel = obj.Services.getResultsTablesStatusLabel();
            if ~isempty(statusLabel) && isvalid(statusLabel)
                if isempty(obj.Services.getLastSolver())
                    statusLabel.Text = 'Tables show current configured values. Run solve for final solved metrics.';
                else
                    statusLabel.Text = 'Tables refreshed from latest solved state.';
                end
            end
        end
    end
end
