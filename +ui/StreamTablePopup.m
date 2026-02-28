classdef StreamTablePopup < handle
    %STREAMTABLEPOPUP  Popup window for displaying / exporting the stream table.

    properties
        StreamTableFig
        StreamTable
        StreamTableStatusLabel
        StreamExportFormatDD
        StreamExportFileField
        StreamExportPathField

        lastExportPath char = ''

        % Injected handles
        getLastFlowsheet
        getStreams
        getSpeciesNames
        getUnitPrefs
        getProjectTitle
        setStatusFcn
    end

    methods
        function obj = StreamTablePopup(deps)
            obj.getLastFlowsheet = deps.getLastFlowsheet;
            obj.getStreams       = deps.getStreams;
            obj.getSpeciesNames  = deps.getSpeciesNames;
            obj.getUnitPrefs     = deps.getUnitPrefs;
            obj.getProjectTitle  = deps.getProjectTitle;
            obj.setStatusFcn     = deps.setStatusFcn;
            if isfield(deps, 'lastExportPath')
                obj.lastExportPath = deps.lastExportPath;
            end
        end

        function open(obj)
            if ~isempty(obj.StreamTableFig) && isvalid(obj.StreamTableFig)
                obj.refresh();
                obj.StreamTableFig.Visible = 'on';
                return;
            end

            obj.StreamTableFig = uifigure('Name','MathLab — Solved Stream Table', ...
                'Position',[140 90 1060 560], 'Color',[0.97 0.97 0.98]);
            obj.StreamTableFig.CloseRequestFcn = @(src,~) obj.onClosed(src);

            gl = uigridlayout(obj.StreamTableFig, [3 1], ...
                'RowHeight',{74,'1x',30}, 'Padding',[10 10 10 10], 'RowSpacing',6);

            topG = uigridlayout(gl, [2 6], 'ColumnWidth',{'fit',90,220,'fit','1x',100}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6, 'RowSpacing',4);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Solved Stream Table', 'FontWeight','bold', 'FontSize',13);
            uilabel(topG, 'Text','Format');
            obj.StreamExportFormatDD = uidropdown(topG, 'Items', {'.mat','.csv'}, 'Value','.mat', ...
                'ValueChangedFcn', @(~,~) obj.onFormatChanged());
            uilabel(topG, 'Text','Filename');
            obj.StreamExportFileField = uieditfield(topG,'text','Value',obj.defaultFilename('mat'));
            uibutton(topG, 'push', 'Text','Save', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) obj.exportFromPopup());

            uilabel(topG, 'Text','Destination');
            obj.StreamExportPathField = uieditfield(topG,'text', ...
                'Value', obj.resolveExportPath(), 'Editable','off');
            uibutton(topG, 'push', 'Text','Choose...', ...
                'ButtonPushedFcn',@(~,~) obj.chooseExportPath());
            uilabel(topG, 'Text','');
            uilabel(topG, 'Text','');
            uibutton(topG, 'push', 'Text','Default Save Path', ...
                'ButtonPushedFcn',@(~,~) obj.saveWithDefaults());

            obj.StreamTable = uitable(gl, 'ColumnEditable', false);
            obj.StreamTable.Layout.Row = 2;

            obj.StreamTableStatusLabel = uilabel(gl, 'Text','', 'FontColor',[0.3 0.3 0.3]);
            obj.StreamTableStatusLabel.Layout.Row = 3;

            obj.refresh();
        end

        function refresh(obj)
            if isempty(obj.StreamTable) || ~isvalid(obj.StreamTable), return; end
            T = obj.buildDisplayTable();
            obj.StreamTable.Data = T;
            obj.StreamTable.ColumnName = T.Properties.VariableNames;
            fs = obj.getLastFlowsheet();
            solver = []; % no direct solver dependency
            if isempty(fs)
                msg = sprintf('Showing current stream state (%d row(s)). Run Solve for final solved table.', height(T));
            else
                msg = sprintf('Solved stream table (%d row(s)).', height(T));
            end
            if ~isempty(obj.StreamTableStatusLabel) && isvalid(obj.StreamTableStatusLabel)
                obj.StreamTableStatusLabel.Text = msg;
            end
        end

        function T = buildDisplayTable(obj)
            fs = obj.getLastFlowsheet();
            if ~isempty(fs)
                T = fs.streamTable();
            else
                streams = obj.getStreams();
                speciesNames = obj.getSpeciesNames();
                fsTmp = proc.Flowsheet(speciesNames);
                for i = 1:numel(streams)
                    s = streams{i};
                    fsTmp.addStream(s, char(string(s.name)));
                end
                T = fsTmp.streamTable();
            end
            unitPrefs = obj.getUnitPrefs();
            T = ui.UnitConverter.convertDisplayStreamTable(T, unitPrefs);
            T.Properties.VariableNames = ui.UnitConverter.displayColumnNames(T.Properties.VariableNames, unitPrefs);
        end
    end

    methods (Access = private)
        function onClosed(obj, src)
            if ~isempty(src) && isvalid(src), delete(src); end
            obj.StreamTableFig = [];
            obj.StreamTable = [];
            obj.StreamTableStatusLabel = [];
            obj.StreamExportFormatDD = [];
            obj.StreamExportFileField = [];
            obj.StreamExportPathField = [];
        end

        function pathOut = resolveExportPath(obj)
            pathOut = strtrim(obj.lastExportPath);
            if isempty(pathOut) || ~isfolder(pathOut)
                pathOut = ui.AppUtils.ensureOutputDir('results');
                obj.lastExportPath = pathOut;
            end
        end

        function fname = defaultFilename(obj, fmt)
            fmt = ui.ResultsExporter.normalizeStreamTableExportFormat(fmt);
            fname = ui.AppUtils.autoFileName(obj.getProjectTitle(), 'stream_table', fmt);
        end

        function onFormatChanged(obj)
            if isempty(obj.StreamExportFormatDD) || isempty(obj.StreamExportFileField) ...
                    || ~isvalid(obj.StreamExportFormatDD) || ~isvalid(obj.StreamExportFileField)
                return;
            end
            fmt = ui.ResultsExporter.normalizeStreamTableExportFormat(obj.StreamExportFormatDD.Value);
            curr = strtrim(obj.StreamExportFileField.Value);
            if isempty(curr)
                obj.StreamExportFileField.Value = obj.defaultFilename(fmt);
                return;
            end
            [~, base, ~] = fileparts(curr);
            if isempty(base), base = 'stream_table'; end
            obj.StreamExportFileField.Value = sprintf('%s.%s', base, fmt);
        end

        function chooseExportPath(obj)
            startPath = obj.resolveExportPath();
            sel = uigetdir(startPath, 'Choose Stream Table Export Folder');
            if isequal(sel, 0), return; end
            obj.lastExportPath = char(string(sel));
            if ~isempty(obj.StreamExportPathField) && isvalid(obj.StreamExportPathField)
                obj.StreamExportPathField.Value = obj.lastExportPath;
            end
        end

        function exportFromPopup(obj)
            if isempty(obj.StreamExportFormatDD) || ~isvalid(obj.StreamExportFormatDD), return; end
            fmt = ui.ResultsExporter.normalizeStreamTableExportFormat(obj.StreamExportFormatDD.Value);
            folder = obj.resolveExportPath();
            if ~isempty(obj.StreamExportPathField) && isvalid(obj.StreamExportPathField)
                folder = strtrim(obj.StreamExportPathField.Value);
            end
            if isempty(folder), folder = ui.AppUtils.ensureOutputDir('results'); end
            ui.AppUtils.ensureWritableDir(folder);
            obj.lastExportPath = char(string(folder));

            fname = '';
            if ~isempty(obj.StreamExportFileField) && isvalid(obj.StreamExportFileField)
                fname = strtrim(obj.StreamExportFileField.Value);
            end
            if isempty(fname), fname = obj.defaultFilename(fmt); end
            [~, base, ~] = fileparts(fname);
            if isempty(base), base = 'stream_table'; end
            fname = sprintf('%s.%s', base, fmt);

            T = obj.buildDisplayTable();
            filepath = fullfile(folder, fname);
            if strcmp(fmt,'csv')
                writetable(T, filepath);
            else
                streamTable = T; %#ok<NASGU>
                save(filepath, 'streamTable');
            end

            msg = sprintf('Stream table exported to %s', filepath);
            obj.setStatusFcn(msg);
            if ~isempty(obj.StreamTableStatusLabel) && isvalid(obj.StreamTableStatusLabel)
                obj.StreamTableStatusLabel.Text = msg;
            end
        end

        function saveWithDefaults(obj)
            if isempty(obj.StreamExportFormatDD) || ~isvalid(obj.StreamExportFormatDD), return; end
            fmt = ui.ResultsExporter.normalizeStreamTableExportFormat(obj.StreamExportFormatDD.Value);
            obj.lastExportPath = obj.resolveExportPath();
            if ~isempty(obj.StreamExportPathField) && isvalid(obj.StreamExportPathField)
                obj.StreamExportPathField.Value = obj.lastExportPath;
            end
            if ~isempty(obj.StreamExportFileField) && isvalid(obj.StreamExportFileField)
                obj.StreamExportFileField.Value = obj.defaultFilename(fmt);
            end
            obj.exportFromPopup();
        end
    end
end
