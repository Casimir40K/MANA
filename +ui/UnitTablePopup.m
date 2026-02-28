classdef UnitTablePopup < handle
    %UNITTABLEPOPUP  Popup window for displaying / exporting the unit table.

    properties
        UnitTableFig
        UnitTable
        UnitTableStatusLabel

        % Injected handles
        getLastSolver
        getLastFlowsheet
        getUnits
        getUnitDefs
        getSpeciesNames
        getUnitPrefs
        getProjectTitle
        setStatusFcn
        refreshStreamTablePopupFcn
        refreshResultsTablesTabFcn
    end

    methods
        function obj = UnitTablePopup(deps)
            obj.getLastSolver   = deps.getLastSolver;
            obj.getLastFlowsheet = deps.getLastFlowsheet;
            obj.getUnits        = deps.getUnits;
            obj.getUnitDefs     = deps.getUnitDefs;
            obj.getSpeciesNames = deps.getSpeciesNames;
            obj.getUnitPrefs    = deps.getUnitPrefs;
            obj.getProjectTitle = deps.getProjectTitle;
            obj.setStatusFcn    = deps.setStatusFcn;
            if isfield(deps, 'refreshStreamTablePopupFcn')
                obj.refreshStreamTablePopupFcn = deps.refreshStreamTablePopupFcn;
            else
                obj.refreshStreamTablePopupFcn = @() [];
            end
            if isfield(deps, 'refreshResultsTablesTabFcn')
                obj.refreshResultsTablesTabFcn = deps.refreshResultsTablesTabFcn;
            else
                obj.refreshResultsTablesTabFcn = @() [];
            end
        end

        function open(obj)
            if ~isempty(obj.UnitTableFig) && isvalid(obj.UnitTableFig)
                obj.refresh();
                obj.refreshStreamTablePopupFcn();
                obj.refreshResultsTablesTabFcn();
                obj.UnitTableFig.Visible = 'on';
                return;
            end

            obj.UnitTableFig = uifigure('Name','MathLab — Unit Results Table', ...
                'Position',[120 80 980 480], 'Color',[0.97 0.97 0.98]);
            obj.UnitTableFig.CloseRequestFcn = @(src,~) obj.onClosed(src);

            gl = uigridlayout(obj.UnitTableFig, [3 1], ...
                'RowHeight',{34,'1x',32}, 'Padding',[10 10 10 10], 'RowSpacing',6);

            topG = uigridlayout(gl, [1 4], 'ColumnWidth',{'fit','1x',110,110}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Unit Results Table (Read-only)', 'FontWeight','bold', 'FontSize',13);
            uilabel(topG, 'Text','Type + connected streams + solved metrics (duty/power/conversion) are flattened for quick review.', ...
                'FontColor',[0.35 0.35 0.35]);
            uibutton(topG, 'push', 'Text','Export CSV', ...
                'ButtonPushedFcn',@(~,~) obj.exportToOutput('csv'));
            uibutton(topG, 'push', 'Text','Export MAT', ...
                'ButtonPushedFcn',@(~,~) obj.exportToOutput('mat'));

            obj.UnitTable = uitable(gl, ...
                'ColumnEditable', false(1,9), ...
                'ColumnName', {'Unit #','Type','Connected Streams', ...
                               'Spec 1 Label','Spec 1 Value', ...
                               'Spec 2 Label','Spec 2 Value', ...
                               'Spec 3 Label','Spec 3 Value'});
            obj.UnitTable.Layout.Row = 2;

            obj.UnitTableStatusLabel = uilabel(gl, 'Text','', 'FontColor',[0.3 0.3 0.3]);
            obj.UnitTableStatusLabel.Layout.Row = 3;

            obj.refresh();
            obj.refreshStreamTablePopupFcn();
            obj.refreshResultsTablesTabFcn();
        end

        function refresh(obj)
            if isempty(obj.UnitTable) || ~isvalid(obj.UnitTable), return; end
            T = obj.buildResultsTable();
            obj.UnitTable.Data = T;
            obj.UnitTable.ColumnName = T.Properties.VariableNames;
            solver = obj.getLastSolver();
            fs = obj.getLastFlowsheet();
            if isempty(T) || height(T) == 0
                status = 'No units defined yet.';
            elseif isempty(solver) || isempty(fs)
                status = sprintf('%d unit(s). Showing configured values. Run Solve for calculated metrics.', height(T));
            else
                status = sprintf('%d unit(s). Read-only simulation view with solved metrics.', height(T));
            end
            if ~isempty(obj.UnitTableStatusLabel) && isvalid(obj.UnitTableStatusLabel)
                obj.UnitTableStatusLabel.Text = status;
            end
        end

        function T = buildResultsTable(obj)
            fs = obj.getLastFlowsheet();
            units = obj.getUnits();
            if ~isempty(fs) && isprop(fs, 'units')
                T = ui.UnitTablePopup.buildTableFromObjects(fs.units, obj.getUnitPrefs());
            elseif ~isempty(units)
                T = ui.UnitTablePopup.buildTableFromObjects(units, obj.getUnitPrefs());
            else
                T = ui.UnitTablePopup.buildTableFromDefs(obj.getUnitDefs(), obj.getUnitPrefs());
            end
        end

        function exportToOutput(obj, fmt)
            fmt = ui.ResultsExporter.normalizeUnitTableExportFormat(fmt);
            outDir = ui.AppUtils.ensureOutputDir('results');
            outDirMsg = char(string(outDir));
            if isempty(strtrim(outDirMsg)) || ~isfolder(outDirMsg)
                reason = sprintf('Output directory is not valid: %s', outDirMsg);
                obj.setStatusFcn(sprintf('Unit table export failed: %s', reason));
                if ~isempty(obj.UnitTableStatusLabel) && isvalid(obj.UnitTableStatusLabel)
                    obj.UnitTableStatusLabel.Text = sprintf('Unit table export failed: %s', reason);
                end
                return;
            end
            try
                T = obj.buildResultsTable();
                projectTitle = obj.getProjectTitle();
                switch fmt
                    case 'csv'
                        filepath = fullfile(outDirMsg, ui.AppUtils.autoFileName(projectTitle, 'unit_table', 'csv'));
                        writetable(T, filepath);
                    case 'mat'
                        filepath = fullfile(outDirMsg, ui.AppUtils.autoFileName(projectTitle, 'unit_table', 'mat'));
                        unitTable = T; %#ok<NASGU>
                        save(filepath, 'unitTable');
                end
            catch ME
                reason = strtrim(ME.message);
                failMsg = sprintf('Unit table export failed: %s (output dir: %s)', reason, outDirMsg);
                obj.setStatusFcn(failMsg);
                if ~isempty(obj.UnitTableStatusLabel) && isvalid(obj.UnitTableStatusLabel)
                    obj.UnitTableStatusLabel.Text = failMsg;
                end
                return;
            end
            obj.setStatusFcn(sprintf('Unit table exported to %s', filepath));
            if ~isempty(obj.UnitTableStatusLabel) && isvalid(obj.UnitTableStatusLabel)
                obj.UnitTableStatusLabel.Text = sprintf('Exported %s (%d rows): %s', upper(fmt), height(T), filepath);
            end
        end
    end

    methods (Static)
        function T = buildTableFromObjects(units, unitPrefs)
            n = numel(units);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Result1_Label','Result1_Value','Result2_Label','Result2_Value','Result3_Label','Result3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = ui.UnitTablePopup.serializeObjectRow(i, units{i}, unitPrefs);
            end
            T = cell2table(data, 'VariableNames', cols);
        end

        function T = buildTableFromDefs(unitDefs, unitPrefs)
            n = numel(unitDefs);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Spec1_Label','Spec1_Value','Spec2_Label','Spec2_Value','Spec3_Label','Spec3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = ui.UnitTablePopup.serializeDefRow(i, unitDefs{i}, unitPrefs);
            end
            T = cell2table(data, 'VariableNames', cols);
        end
    end

    methods (Access = private)
        function onClosed(obj, src)
            if ~isempty(src) && isvalid(src), delete(src); end
            obj.UnitTableFig = [];
            obj.UnitTable = [];
            obj.UnitTableStatusLabel = [];
        end
    end

    methods (Static, Access = private)
        function row = serializeObjectRow(idx, u, unitPrefs)
            row = {idx, ui.AppUtils.shortTypeName(u), '-', '-', '-', '-', '-', '-', '-'};
            row{3} = ui.UnitTablePopup.unitObjectConnectedStreams(u);
            pairs = ui.UnitTablePopup.unitObjectResultPairs(u, unitPrefs);
            for k = 1:min(3,size(pairs,1))
                row{3 + (k-1)*2 + 1} = pairs{k,1};
                row{3 + (k-1)*2 + 2} = pairs{k,2};
            end
        end

        function streamText = unitObjectConnectedStreams(u)
            names = {};
            if ismethod(u, 'streamNames')
                try, names = u.streamNames(); catch, names = {}; end
            end
            if isempty(names), streamText = '-'; else, streamText = ui.AppUtils.formatSpecValue(names); end
        end

        function pairs = unitObjectResultPairs(u, unitPrefs)
            pairs = {};
            cn = class(u);
            lbl = @(q,b) ui.UnitConverter.unitLabel(q, b, unitPrefs);
            smv = @(m, q) ui.UnitTablePopup.safeMethodValue(u, m, q, unitPrefs);
            spv = @(o, f, q) ui.UnitTablePopup.safePropValue(u, o, f, q, unitPrefs);
            ssp = @(p) ui.UnitTablePopup.safeSimpleProp(u, p);

            if contains(cn,'HeatExchanger')
                pairs = {lbl('duty','Duty'), smv('getDuty','duty'); ...
                         lbl('temperature','Hot Tout'), spv('hotOutlet','T','temperature'); ...
                         lbl('temperature','Cold Tout'), spv('coldOutlet','T','temperature')};
            elseif contains(cn,'Heater') || contains(cn,'Cooler')
                pairs = {lbl('duty','Duty'), smv('getDuty','duty'); ...
                         lbl('temperature','Tin'), spv('inlet','T','temperature'); ...
                         lbl('temperature','Tout'), spv('outlet','T','temperature')};
            elseif contains(cn,'Compressor') || contains(cn,'Turbine')
                pairs = {lbl('power','Power'), smv('getPower','power'); ...
                         'Pressure ratio', ui.UnitTablePopup.safePressureRatio(u); ...
                         'Eta', ssp('eta')};
            elseif contains(cn,'StoichiometricReactor')
                pairs = {'Extent', ssp('extent'); ...
                         'Extent mode', ssp('extentMode'); ...
                         'Ref species', ssp('referenceSpecies')};
            elseif contains(cn,'EquilibriumReactor')
                pairs = {'Keq', ssp('Keq'); ...
                         'Ref species', ssp('referenceSpecies'); ...
                         lbl('temperature','Tout'), spv('outlet','T','temperature')};
            elseif contains(cn,'ConversionReactor') || contains(cn,'YieldReactor') || contains(cn,'Reactor')
                pairs = {'Conversion', ssp('conversion'); ...
                         lbl('temperature','Tin'), spv('inlet','T','temperature'); ...
                         lbl('temperature','Tout'), spv('outlet','T','temperature')};
            elseif contains(cn,'Separator')
                pairs = {'Split phi', ssp('phi')};
            elseif contains(cn,'Purge')
                pairs = {'Purge beta', ssp('beta')};
            else
                pairs = {'Description', ui.UnitTablePopup.safeDescribe(u)};
            end
        end

        function val = safeMethodValue(u, m, quantity, unitPrefs)
            try
                if ismethod(u,m)
                    raw = u.(m)();
                    if ~isempty(quantity)
                        raw = ui.UnitConverter.fromSI(raw, quantity, unitPrefs);
                    end
                    val = ui.AppUtils.formatSpecValue(raw);
                else
                    val = '-';
                end
            catch
                val = '-';
            end
        end

        function val = safeSimpleProp(u, p)
            try
                if isprop(u,p), val = ui.AppUtils.formatSpecValue(u.(p)); else, val = '-'; end
            catch
                val = '-';
            end
        end

        function val = safePropValue(u, ownerProp, fieldProp, quantity, unitPrefs)
            try
                if isprop(u, ownerProp)
                    owner = u.(ownerProp);
                    if isprop(owner, fieldProp)
                        raw = owner.(fieldProp);
                        if ~isempty(quantity)
                            raw = ui.UnitConverter.fromSI(raw, quantity, unitPrefs);
                        end
                        val = ui.AppUtils.formatSpecValue(raw);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function val = safePressureRatio(u)
            try
                if isprop(u,'PR') && isfinite(u.PR)
                    val = ui.AppUtils.formatSpecValue(u.PR);
                    return;
                end
                if isprop(u,'inlet') && isprop(u,'outlet')
                    p1 = u.inlet.P;
                    p2 = u.outlet.P;
                    if isfinite(p1) && p1 ~= 0 && isfinite(p2)
                        val = ui.AppUtils.formatSpecValue(p2/p1);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function txt = safeDescribe(u)
            try
                if ismethod(u,'describe'), txt = char(string(u.describe())); else, txt = class(u); end
            catch
                txt = class(u);
            end
        end

        function row = serializeDefRow(idx, def, unitPrefs)
            row = {idx, '-', '-', '-', '-', '-', '-', '-', '-'};
            if ~isstruct(def) || ~isfield(def,'type'), return; end
            typ = char(string(def.type));
            row{2} = typ;
            row{3} = ui.UnitTablePopup.unitConnectedStreams(def);
            specs = ui.UnitTablePopup.unitSpecPairs(def, unitPrefs);
            for k = 1:min(3,size(specs,1))
                row{3 + (k-1)*2 + 1} = specs{k,1};
                row{3 + (k-1)*2 + 2} = specs{k,2};
            end
        end

        function streamText = unitConnectedStreams(def)
            parts = {};
            fSingle = {'inlet','outlet','source','tear','stream','recycle','purge','outletA','outletB', ...
                'processInlet','bypassStream','processReturn','hotInlet','hotOutlet','coldInlet','coldOutlet', ...
                'lhsStream','aStream','bStream'};
            for i = 1:numel(fSingle)
                f = fSingle{i};
                if isfield(def,f)
                    parts{end+1} = sprintf('%s=%s', f, ui.AppUtils.formatSpecValue(def.(f))); %#ok<AGROW>
                end
            end
            if isfield(def,'inlets')
                parts{end+1} = sprintf('inlets=%s', ui.AppUtils.formatSpecValue(def.inlets)); %#ok<AGROW>
            end
            if isfield(def,'outlets')
                parts{end+1} = sprintf('outlets=%s', ui.AppUtils.formatSpecValue(def.outlets)); %#ok<AGROW>
            end
            if isempty(parts), streamText = '-'; else, streamText = strjoin(parts, ' | '); end
        end

        function specs = unitSpecPairs(def, unitPrefs)
            specs = {};
            typ = char(string(def.type));
            lbl = @(q,b) ui.UnitConverter.unitLabel(q, b, unitPrefs);
            gdf = @(fld, varargin) ui.UnitTablePopup.getDefField(def, fld, unitPrefs, varargin{:});

            switch typ
                case 'Mixer'
                    specs = {'No. inlets', ui.AppUtils.formatSpecValue(numel(def.inlets)); 'Outlet', ui.AppUtils.formatSpecValue(def.outlet)};
                case 'Heater'
                    specs = {lbl('temperature','Tout'), gdf('Tout','temperature'); lbl('duty','Qdot'), gdf('duty','duty'); 'dP/Pout/PR', gdf('dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = gdf('Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-'), specs{3,2} = gdf('PR'); end
                    end
                case 'Cooler'
                    specs = {lbl('temperature','Tout'), gdf('Tout','temperature'); lbl('duty','Qdot'), gdf('duty','duty'); 'dP/Pout/PR', gdf('dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = gdf('Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-'), specs{3,2} = gdf('PR'); end
                    end
                case 'Compressor',           specs = {'Pressure ratio', gdf('PR'); 'Efficiency', gdf('eta')};
                case 'Turbine',              specs = {'Pressure ratio', gdf('PR'); 'Efficiency', gdf('eta')};
                case 'Reactor',              specs = {'Conversion', gdf('conversion'); 'Reactions', gdf('reactions')};
                case 'ConversionReactor',    specs = {'Key species', gdf('keySpecies'); 'Conversion', gdf('conversion'); 'Mode', gdf('conversionMode')};
                case 'StoichiometricReactor', specs = {'Extent', gdf('extent'); 'Mode', gdf('extentMode'); 'Ref species', gdf('referenceSpecies')};
                case 'YieldReactor',         specs = {'Basis species', gdf('basisSpecies'); 'Conversion', gdf('conversion'); 'Products', gdf('productSpecies')};
                case 'EquilibriumReactor',   specs = {'Keq', gdf('Keq'); 'Ref species', gdf('referenceSpecies'); 'Stoich nu', gdf('nu')};
                case 'Separator',            specs = {'Split phi', gdf('phi')};
                case 'Purge',                specs = {'Purge beta', gdf('beta')};
                case 'Splitter'
                    if isfield(def,'splitFractions')
                        specs = {'Mode', 'fractions'; 'Values', gdf('splitFractions')};
                    else
                        specs = {'Mode', 'flows'; 'Values', gdf('specifiedOutletFlows')};
                    end
                case 'Bypass',   specs = {'Bypass fraction', gdf('bypassFraction')};
                case 'Manifold', specs = {'Route', gdf('route')};
                case 'Source',   specs = {lbl('flow','Total flow'), gdf('totalFlow','flow'); 'Composition', gdf('composition'); lbl('flow','Comp flows'), gdf('componentFlows','flow')};
                case 'DesignSpec', specs = {'Metric', gdf('metric'); 'Target', gdf('target'); 'Species idx', gdf('speciesIndex')};
                case 'Adjust',   specs = {'Field', gdf('field'); 'Index', gdf('index'); 'Bounds', sprintf('[%s, %s]', gdf('minValue'), gdf('maxValue'))};
                case 'Calculator', specs = {'LHS field', gdf('lhsField'); 'Operator', gdf('operator'); 'RHS fields', sprintf('%s %s %s', gdf('aField'), gdf('operator'), gdf('bField'))};
                case 'Constraint', specs = {'Field', gdf('field'); 'Value', gdf('value'); 'Index', gdf('index')};
                otherwise
                    specs = {'Spec struct fields', ui.AppUtils.formatSpecValue(fieldnames(def)')};
            end
        end

        function val = getDefField(def, fld, unitPrefs, quantity)
            if nargin < 4, quantity = ''; end
            if isfield(def, fld)
                raw = def.(fld);
                if ~isempty(quantity)
                    raw = ui.UnitConverter.fromSI(raw, quantity, unitPrefs);
                end
                val = ui.AppUtils.formatSpecValue(raw);
            else
                val = '-';
            end
        end
    end
end
