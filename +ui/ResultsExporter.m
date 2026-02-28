classdef ResultsExporter
    %RESULTSEXPORTER  Static helpers for exporting solver results to files.

    methods (Static)

        function exportSummaryCsv(resultsSummary, projectTitle)
            if isempty(resultsSummary), return; end
            outDir = ui.AppUtils.ensureOutputDir('results');
            fname = ui.AppUtils.autoFileName(projectTitle, 'summary', 'csv');
            filepath = fullfile(outDir, fname);
            try
                T = struct2table(resultsSummary, 'AsArray', true);
            catch
                fns = fieldnames(resultsSummary);
                vals = cell(1, numel(fns));
                for k = 1:numel(fns)
                    v = resultsSummary.(fns{k});
                    if isnumeric(v)
                        vals{k} = v;
                    else
                        vals{k} = {char(string(v))};
                    end
                end
                T = table(vals{:}, 'VariableNames', fns);
            end
            writetable(T, filepath);
        end

        function exportSnapshotsCsv(resultsSnapshots, projectTitle)
            if isempty(resultsSnapshots), return; end
            outDir = ui.AppUtils.ensureOutputDir('results');
            fname = ui.AppUtils.autoFileName(projectTitle, 'snapshots', 'csv');
            filepath = fullfile(outDir, fname);
            try
                T = struct2table(resultsSnapshots);
            catch
                T = resultsSnapshots;
            end
            writetable(T, filepath);
        end

        function exportTracesCsv(traceData, projectTitle)
            if isempty(traceData), return; end
            outDir = ui.AppUtils.ensureOutputDir('results');
            fname = ui.AppUtils.autoFileName(projectTitle, 'traces', 'csv');
            filepath = fullfile(outDir, fname);
            writetable(traceData, filepath);
        end

        function exportStreamCsv(streamTable, projectTitle)
            if isempty(streamTable), return; end
            outDir = ui.AppUtils.ensureOutputDir('results');
            fname = ui.AppUtils.autoFileName(projectTitle, 'stream_table', 'csv');
            filepath = fullfile(outDir, fname);
            writetable(streamTable, filepath);
        end

        function exportFigure(ax, projectTitle)
            if isempty(ax) || ~isvalid(ax), return; end
            outDir = fullfile(pwd, 'output');
            if ~exist(outDir, 'dir'), mkdir(outDir); end
            stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok
            outFile = fullfile(outDir, sprintf('%s_results_plot_%s.png', projectTitle, stamp));
            try
                exportgraphics(ax, outFile, 'Resolution', 150);
            catch
            end
        end

        function fmt = normalizeUnitTableExportFormat(fmt)
            if ~(ischar(fmt) || (isstring(fmt) && isscalar(fmt)))
                error('MathLab:UnitTable:InvalidFormat', ...
                    'Unit table export format must be a non-empty text scalar (''csv'' or ''mat'').');
            end
            fmt = lower(strtrim(char(string(fmt))));
            if isempty(fmt)
                error('MathLab:UnitTable:InvalidFormat', ...
                    'Unit table export format must be a non-empty text scalar (''csv'' or ''mat'').');
            end
            if ~ismember(fmt, {'csv','mat'})
                error('MathLab:UnitTable:UnsupportedFormat', ...
                    'Unsupported unit table export format "%s". Supported formats: csv, mat.', fmt);
            end
        end

        function fmt = normalizeStreamTableExportFormat(fmt)
            fmt = lower(strtrim(char(string(fmt))));
            if startsWith(fmt,'.')
                fmt = fmt(2:end);
            end
            if ~ismember(fmt, {'mat','csv'})
                error('MathLab:StreamTable:UnsupportedFormat', ...
                    'Unsupported stream table export format "%s". Use mat or csv.', fmt);
            end
        end
    end
end
