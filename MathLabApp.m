classdef MathLabApp < handle
    %MATHLABAPP  Steady-state process solver GUI
    %
    %   app = MathLabApp;
    %   app = MathLabApp('config.mat');    % load a saved config on startup
    %
    %   Requires the +proc package folder in the same directory.

    % =====================================================================
    %  UI HANDLES
    % =====================================================================
    properties (Access = private)
        Fig
        Tabs
        StatusBar

        % -- Tab 0: Setup & Config --
        SetupTab
        SaveConfigBtn
        LoadConfigBtn
        InstructionsArea

        % -- Tab 1: Species & Properties --
        SpeciesTab
        SpeciesTable
        AddSpeciesBtn
        RemoveSpeciesBtn
        NewSpeciesName
        NewSpeciesMW
        ApplySpeciesBtn
        SpeciesPropsTable

        % -- Tab 2: Streams --
        StreamsTab
        StreamValTable
        StreamKnownTable
        AddStreamBtn
        RemoveStreamBtn
        StreamNameField
        StreamDOFLabel       % live DOF on this tab too

        % -- Tab 3: Units --
        UnitsTab
        UnitsListBox
        AddUnitDropDown
        AddUnitBtn
        ConfigUnitBtn
        RemoveUnitBtn
        FlowsheetAxes
        UnitDOFLabel         % live DOF on this tab too

        % -- Tab 4: Solve --
        SolveTab
        MaxIterField
        TolField
        SolveBtn
        DOFLabel
        ResidualAxes
        LogArea
        SolveIterLabel
        SolveAvgTimeLabel
        SolveElapsedLabel
        SolveTimer
        SolveStartTic

        % -- Tab 5: Results --
        ResultsTab
        ResultsTablesTab
        ResultsStabilityTab
        ResultsAxes
        ResultsXScaleDropDown
        ResultsYScaleDropDown
        ResultsConfig1XVarDD
        ResultsConfig1YVarDD
        ResultsConfig1TargetDD
        ResultsConfig1CompDD
        ResultsConfig1NormCheck
        ResultsConfig1ScaleField
        ResultsConfig1AxisDD
        ResultsConfig2XVarDD
        ResultsConfig2YVarDD
        ResultsConfig2TargetDD
        ResultsConfig2CompDD
        ResultsConfig2NormCheck
        ResultsConfig2ScaleField
        ResultsConfig2AxisDD
        ResultsConfig3XVarDD
        ResultsConfig3YVarDD
        ResultsConfig3TargetDD
        ResultsConfig3CompDD
        ResultsConfig3NormCheck
        ResultsConfig3ScaleField
        ResultsConfig3AxisDD
        ResultsConfig4XVarDD
        ResultsConfig4YVarDD
        ResultsConfig4TargetDD
        ResultsConfig4CompDD
        ResultsConfig4NormCheck
        ResultsConfig4ScaleField
        ResultsConfig4AxisDD
        ResultsPresetDD
        ResultsApplyPresetBtn
        ResultsSmoothingDD
        ResultsSmoothWindowField
        ResultsNormModeDD
        ResultsLegendDD
        ResultsExportBtn
        ResultsResetBtn
        ResultsClearChartBtn
        ResultsPlotStatusLabel
        OpenStreamTableBtn
        ResultsStabilityBtn
        ResultsStabilitySweepParamDD
        ResultsStabilitySweepMinField
        ResultsStabilitySweepMaxField
        ResultsStabilitySweepPtsField
        ResultsStreamTable
        ResultsUnitTable
        ResultsTablesStatusLabel
        ResultsTablesStatusBanner
        ResultsTablesResidualLabel
        ResultsTablesIterLabel
        ResultsNyquistAxes
        ResultsStabilitySweepAxes
        ResultsStabilityStatusLabel

        % -- Tab 6: Sensitivity --
        SensTab
        SensParamDropDown
        SensMinField
        SensMaxField
        SensNptsField
        SensOutputStreamDD
        SensOutputFieldDD
        SensRunBtn
        SensAxes
        SensMaxIterField
        SensTolField
        SensStatusLabel

        % -- Project & Output --
        ProjectTitleField
        FlowUnitDropDown
        TempUnitDropDown
        PressureUnitDropDown
        DutyUnitDropDown
        PowerUnitDropDown
        SaveResultsBtn
        OpenDebugBtn
        LogEveryNField

        % -- Popup controllers --
        debugCtrl
        unitTablePopupCtrl
        streamTablePopupCtrl
    end

    % =====================================================================
    %  MODEL STATE
    % =====================================================================
    properties (Access = private)
        AppState ui.AppState
        SpeciesController ui.tabs.SpeciesTabController
        StreamsController ui.tabs.StreamsTabController
        UnitsController ui.tabs.UnitsTabController
        SolveController ui.tabs.SolveTabController
        ResultsController ui.tabs.ResultsTabController
        SensitivityController ui.tabs.SensitivityTabController

        speciesNames cell   = {'H2','O2','H2O'}
        speciesMW    double = [2.016, 32.00, 18.015]

        streams  cell = {}
        units    cell = {}
        unitDefs cell = {}    % serializable unit definitions for save/load
        lastSolver = []
        lastFlowsheet = []
        resultsSnapshots cell = {}
        resultsSnapshotIters double = []
        resultsSnapshotResiduals double = []
        resultsSummary struct = struct('status','Not solved','residual',NaN,'iterations',0, ...
            'streamKey','-','unitKey','-','streamText','-','unitText','-','deltaText','-')
        projectTitle char = 'MathLab_Project'
        unitPrefs struct = struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW')
        lastExportPath char = ''
        stabilitySweepData struct = struct('param',[],'values',[],'maxRealPole',[],'stableMask',[],'warnings',strings(0,1))
        debugSettings struct = struct('debugLevel',0,'debugTopN',10,'debugEvery',0,'debugEqNames',true)
        logEveryN double = 0
    end

    % =====================================================================
    %  CONSTRUCTOR
    % =====================================================================
    methods (Access = public)
        function app = MathLabApp(configFile)
            app.AppState = ui.AppState();
            app.initControllers();
            app.buildUI();
            if nargin >= 1 && ~isempty(configFile)
                app.loadConfig(configFile);
            else
                app.refreshSpeciesTable();
                app.applySpecies();
            end
        end
    end

    % =====================================================================
    %  UI CONSTRUCTION
    % =====================================================================
    methods (Access = private)

        function initControllers(app)
            app.syncModelToState();
            app.SpeciesController = ui.tabs.SpeciesTabController(app.AppState, struct( ...
                'alertError', @(msg) uialert(app.Fig, msg, 'Error'), ...
                'addStreamInternal', @(name) app.addStreamInternal(name), ...
                'refreshStreamTables', @() app.refreshStreamTables(), ...
                'refreshUnitsListBox', @() app.refreshUnitsListBox(), ...
                'refreshFlowsheetDiagram', @() app.refreshFlowsheetDiagram(), ...
                'updateDOF', @() app.updateDOF(), ...
                'refreshUnitTablePopup', @() app.refreshUnitTablePopup(), ...
                'refreshStreamTablePopup', @() app.refreshStreamTablePopup(), ...
                'refreshResultsTablesTab', @() app.refreshResultsTablesTab(), ...
                'updateSensDropdowns', @() app.updateSensDropdowns(), ...
                'refreshSpeciesPropsTable', @() app.refreshSpeciesPropsTable(), ...
                'setNextStreamName', @(name) app.setNextStreamName(name), ...
                'setStatus', @(msg) app.setStatus(msg)));
            app.StreamsController = ui.tabs.StreamsTabController(app.AppState, struct( ...
                'alertError', @(msg) uialert(app.Fig,msg,'Error'), ...
                'alertWithTitle', @(msg,titleTxt) uialert(app.Fig,msg,titleTxt), ...
                'getNewStreamName', @() app.StreamNameField.Value, ...
                'setNextStreamName', @(name) app.setNextStreamName(name), ...
                'addStreamInternal', @(name) app.addStreamInternal(name), ...
                'refreshStreamTables', @() app.refreshStreamTables(), ...
                'updateDOF', @() app.updateDOF(), ...
                'updateSensDropdowns', @() app.updateSensDropdowns(), ...
                'getSelectedStreamRow', @() app.getSelectedStreamRow(), ...
                'toSI', @(val,quantity) app.toSI(val,quantity)));
            app.UnitsController = ui.tabs.UnitsTabController(app.AppState, struct( ...
                'findStream', @(name) app.findStream(name), ...
                'commitUnit', @(u,def,editIdx) app.commitUnit(u,def,editIdx), ...
                'makeDialog', @(titleStr,w,h,fields) app.makeDialog(titleStr,w,h,fields), ...
                'addDialogButtons', @(d,okFcn) app.addDialogButtons(d,okFcn), ...
                'unitLabel', @(quantity,base) app.unitLabel(quantity,base), ...
                'fromSI', @(val,quantity) app.fromSI(val,quantity), ...
                'toSI', @(val,quantity) app.toSI(val,quantity), ...
                'getUnitPrefs', @() app.unitPrefs, ...
                'buildThermoMixForGUI', @() app.buildThermoMixForGUI()));
            app.SolveController = ui.tabs.SolveTabController(app.AppState, struct( ...
                'syncStreamsFromTable', @() app.syncStreamsFromTable(), ...
                'validateSolvePreconditions', @() app.validateSolvePreconditions(), ...
                'buildFlowsheet', @() app.buildFlowsheet(), ...
                'setLastFlowsheet', @(fs) app.setLastFlowsheet(fs), ...
                'updateDOF', @() app.updateDOF(), ...
                'getSolveInputs', @() app.getSolveInputs(), ...
                'prepareSolveRun', @(tol) app.prepareSolveRun(tol), ...
                'onSolveIter', @(iter,rNorm) app.onSolveIter(iter,rNorm), ...
                'onSolveLogLine', @(line,lineIdx) app.onSolveLogLine(line,lineIdx), ...
                'getDebugSettings', @() app.getDebugSettings(), ...
                'setLastSolver', @(solver) app.setLastSolver(solver), ...
                'onSolveSuccess', @(solver) app.onSolveSuccess(solver), ...
                'onSolveFailure', @(ME) app.onSolveFailure(ME)));
            app.ResultsController = ui.tabs.ResultsTabController(app.AppState, struct( ...
                'getResultsAxes', @() app.ResultsAxes, ...
                'getResultsXScale', @() app.ResultsXScaleDropDown.Value, ...
                'getResultsYScale', @() app.ResultsYScaleDropDown.Value, ...
                'plotResultsConfig', @(idx) app.plotResultsConfig(idx), ...
                'getResultsLegendLocation', @() app.ResultsLegendDD.Value, ...
                'setResultsPlotStatus', @(txt) set(app.ResultsPlotStatusLabel, 'Text', txt), ...
                'getResultsSnapshotCount', @() numel(app.resultsSnapshots), ...
                'getResultsSmoothingMode', @() app.ResultsSmoothingDD.Value, ...
                'getResultsSmoothWindow', @() app.ResultsSmoothWindowField.Value, ...
                'refreshResultsTargetOptions', @() app.refreshResultsTargetOptions(), ...
                'getResultsSummary', @() app.resultsSummary, ...
                'setResultsSummary', @(summary) app.setResultsSummary(summary), ...
                'getLastSolver', @() app.lastSolver, ...
                'getLastFlowsheet', @() app.lastFlowsheet, ...
                'unitLabel', @(quantity,base) app.unitLabel(quantity,base), ...
                'fromSI', @(val,quantity) app.fromSI(val,quantity), ...
                'shortTypeName', @(u) app.shortTypeName(u), ...
                'unitObjectResultPairs', @(u) app.unitObjectResultPairs(u), ...
                'formatSpecValue', @(v) app.formatSpecValue(v), ...
                'getResultsTablesStatusBanner', @() app.ResultsTablesStatusBanner, ...
                'getResultsTablesResidualLabel', @() app.ResultsTablesResidualLabel, ...
                'getResultsTablesIterLabel', @() app.ResultsTablesIterLabel, ...
                'getResultsStreamTable', @() app.ResultsStreamTable, ...
                'buildDisplayStreamTable', @() app.buildDisplayStreamTable(), ...
                'getResultsUnitTable', @() app.ResultsUnitTable, ...
                'buildUnitResultsTable', @() app.buildUnitResultsTable(), ...
                'getResultsTablesStatusLabel', @() app.ResultsTablesStatusLabel));
            app.SensitivityController = ui.tabs.SensitivityTabController(app.AppState, struct( ...
                'syncStreamsFromTable', @() app.syncStreamsFromTable(), ...
                'alertError', @(msg) uialert(app.Fig,msg,'Error'), ...
                'getSensParamChoice', @() app.SensParamDropDown.Value, ...
                'getSensMin', @() app.SensMinField.Value, ...
                'getSensMax', @() app.SensMaxField.Value, ...
                'getSensNpts', @() app.SensNptsField.Value, ...
                'getSensOutputStream', @() app.SensOutputStreamDD.Value, ...
                'getSensOutputField', @() app.SensOutputFieldDD.Value, ...
                'getSensMaxIter', @() app.SensMaxIterField.Value, ...
                'getSensTol', @() app.SensTolField.Value, ...
                'clearSensitivityAxes', @() cla(app.SensAxes), ...
                'setSensitivityStatus', @(txt) app.setSensitivityStatusText(txt), ...
                'setSensitivityRunEnabled', @(tf) app.setSensitivityRunEnabled(tf), ...
                'buildFlowsheet', @() app.buildFlowsheet(), ...
                'findStream', @(name) app.findStream(name), ...
                'setStatus', @(msg) app.setStatus(msg), ...
                'plotSensitivity', @(vals,results,paramLabel,outStreamName,outFieldStr) app.plotSensitivityResults(vals,results,paramLabel,outStreamName,outFieldStr)));
        end

        function syncModelToState(app)
            app.AppState.speciesNames = app.speciesNames;
            app.AppState.speciesMW = app.speciesMW;
            app.AppState.streams = app.streams;
            app.AppState.units = app.units;
            app.AppState.unitDefs = app.unitDefs;
            app.AppState.lastSolver = app.lastSolver;
            app.AppState.lastFlowsheet = app.lastFlowsheet;
            app.AppState.metadata.projectTitle = app.projectTitle;
            app.AppState.metadata.unitPrefs = app.unitPrefs;
            app.AppState.metadata.lastExportPath = app.lastExportPath;
            app.AppState.metadata.logEveryN = app.logEveryN;
        end

        function syncStateToModel(app)
            app.speciesNames = app.AppState.speciesNames;
            app.speciesMW = app.AppState.speciesMW;
            app.streams = app.AppState.streams;
            app.units = app.AppState.units;
            app.unitDefs = app.AppState.unitDefs;
            app.lastSolver = app.AppState.lastSolver;
            app.lastFlowsheet = app.AppState.lastFlowsheet;
            app.projectTitle = app.AppState.metadata.projectTitle;
            app.unitPrefs = app.AppState.metadata.unitPrefs;
            app.lastExportPath = app.AppState.metadata.lastExportPath;
            if isfield(app.AppState.metadata, 'logEveryN')
                app.logEveryN = max(0, round(app.AppState.metadata.logEveryN));
            end
        end

        function buildUI(app)
            app.Fig = uifigure('Name','MathLab — Process Solver', ...
                'Position',[60 40 1120 720], 'Resize','on', ...
                'Color',[0.96 0.96 0.97], ...
                'DeleteFcn', @(~,~) app.stopSolveTimer());

            gl = uigridlayout(app.Fig, [2 1], ...
                'RowHeight',{'1x', 24}, 'Padding',[0 0 0 0], 'RowSpacing',0);

            app.Tabs = uitabgroup(gl);
            app.Tabs.Layout.Row = 1;

            app.StatusBar = uilabel(gl, 'Text','  Ready', ...
                'FontColor',[0.25 0.25 0.25], ...
                'BackgroundColor',[0.88 0.89 0.91], ...
                'FontSize', 12);
            app.StatusBar.Layout.Row = 2;

            app.buildSetupTab();
            app.buildSpeciesTab();
            app.buildStreamsTab();
            app.buildUnitsTab();
            app.buildSolveTab();
            app.buildResultsTab();
            app.buildResultsTablesTab();
            app.buildResultsStabilityTab();
            app.buildSensitivityTab();
        end

        % ================================================================
        %  TAB 0: SETUP & CONFIG
        % ================================================================
        function buildSetupTab(app)
            t = uitab(app.Tabs, 'Title', 'Setup');
            app.SetupTab = t;

            gl = uigridlayout(t, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',12);

            % --- Left: project config + save/load ---
            leftP = uipanel(gl, 'Title','Project & Config', 'FontWeight','bold');
            leftG = uigridlayout(leftP, [6 1], ...
                'RowHeight',{30, 72, 30, 36, 36, 24}, 'Padding',[8 8 8 8], 'RowSpacing',4);

            % Project title row
            titleRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{110,'1x'}, ...
                'Padding',[0 0 0 0]);
            uilabel(titleRow,'Text','Project title:','FontWeight','bold');
            app.ProjectTitleField = uieditfield(titleRow,'text', ...
                'Value',app.projectTitle, ...
                'ValueChangedFcn',@(src,~) app.onProjectTitleChanged(src));

            % Display units row
            unitRow = uigridlayout(leftG, [2 5], 'ColumnWidth', {'fit','1x','1x','1x','1x'}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6, 'RowSpacing',3);
            uilabel(unitRow,'Text','Display units:','FontWeight','bold');
            app.FlowUnitDropDown = uidropdown(unitRow, 'Items', {'mol/s','kmol/s'}, ...
                'Value', app.unitPrefs.flow, 'Tooltip', 'Molar flow rate unit', ...
                'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('flow', src.Value));
            app.TempUnitDropDown = uidropdown(unitRow, 'Items', {'K','C'}, ...
                'Value', app.unitPrefs.temperature, 'Tooltip', 'Temperature unit', ...
                'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('temperature', src.Value));
            app.PressureUnitDropDown = uidropdown(unitRow, 'Items', {'Pa','kPa','bar'}, ...
                'Value', app.unitPrefs.pressure, 'Tooltip', 'Pressure unit', ...
                'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('pressure', src.Value));
            app.DutyUnitDropDown = uidropdown(unitRow, 'Items', {'W','kW','MW'}, ...
                'Value', app.unitPrefs.duty, 'Tooltip', 'Heat duty unit', ...
                'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('duty', src.Value));

            uilabel(unitRow,'Text','');  % second row label spacer
            app.PowerUnitDropDown = uidropdown(unitRow, 'Items', {'W','kW','MW'}, ...
                'Value', app.unitPrefs.power, 'Tooltip', 'Shaft power unit', ...
                'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('power', src.Value));
            uilabel(unitRow,'Text','');  % spacer
            uilabel(unitRow,'Text','');  % spacer
            uilabel(unitRow,'Text','');  % spacer


            % Solver log thinning row
            logRow = uigridlayout(leftG, [1 3], 'ColumnWidth', {180, 80, '1x'}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6);
            uilabel(logRow,'Text','Solver log: print every N lines', 'FontWeight','bold');
            app.LogEveryNField = uieditfield(logRow, 'numeric', 'Value', app.logEveryN, ...
                'Limits',[0 100000], 'RoundFractionalValues','on', ...
                'ValueChangedFcn', @(src,~) app.onLogEveryNChanged(src));
            uilabel(logRow,'Text','(0 = every line)', 'FontColor',[0.45 0.45 0.45]);

            % Save / Load row
            slRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[0 0 0 0]);
            app.SaveConfigBtn = uibutton(slRow,'push','Text','Save Config', ...
                'Icon','', 'FontWeight','bold', ...
                'BackgroundColor',[0.92 0.95 0.85], ...
                'ButtonPushedFcn',@(~,~) app.saveConfigToOutput());
            app.LoadConfigBtn = uibutton(slRow,'push','Text','Load Config...', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.95 0.92 0.85], ...
                'ButtonPushedFcn',@(~,~) app.loadConfigDialog());

            % Save results + debug row
            resRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[0 0 0 0]);
            app.SaveResultsBtn = uibutton(resRow,'push','Text','Save Results', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.85 0.92 0.95], ...
                'ButtonPushedFcn',@(~,~) app.saveResultsToOutput());
            app.OpenDebugBtn = uibutton(resRow,'push','Text','Debug Tools', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.95 0.88 0.88], ...
                'ButtonPushedFcn',@(~,~) app.openDebugPopup());

            % Placeholder for spacing
            uilabel(leftG, 'Text', '');

            % --- Right: instructions ---
            rightP = uipanel(gl, 'Title','How to Use MathLab', 'FontWeight','bold');
            rightG = uigridlayout(rightP, [1 1], 'Padding',[8 8 8 8]);
            app.InstructionsArea = uitextarea(rightG, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',12, 'Value', { ...
                'WORKFLOW'; ...
                '========'; ...
                ''; ...
                '1. SETUP       — Set project title, save/load config.'; ...
                '2. SPECIES     — Define names, MW, thermo props. Apply.'; ...
                '3. STREAMS     — Add streams, set values & known flags.'; ...
                '4. UNITS       — Add unit operations, pick streams.'; ...
                '5. SOLVE       — Check DOF, click Solve, see residuals.'; ...
                '6. RESULTS     — View stream & unit tables, export CSV.'; ...
                '7. TRENDS      — Plot convergence & solved-state trends.'; ...
                '8. STABILITY   — Nyquist & pole analysis.'; ...
                '9. SENSITIVITY — Sweep any flowsheet parameter.'; ...
                ''; ...
                'SAVE / LOAD'; ...
                '==========='; ...
                'Save Config: saves your entire flowsheet setup'; ...
                '  to a .mat file you can reload later.'; ...
                'Load Config: restores species, streams, units.'; ...
                ''; ...
                'COMMAND LINE (no GUI):'; ...
                '  [T, solver] = runFromConfig(''myfile.mat'');'; ...
                '  This solves and saves solver to output/.'; ...
                ''; ...
                'TIPS'; ...
                '===='; ...
                '- Mole fractions (y) must sum to 1.0'; ...
                '- All streams need finite positive guesses'; ...
                '- Watch the DOF counter on Streams/Units tabs'; ...
                '- Feed streams: all values Known'; ...
                '- Species with Shomate data enable thermo units'});
        end

        % ================================================================
        %  TAB 1: SPECIES & PROPERTIES
        % ================================================================
        function buildSpeciesTab(app)
            t = uitab(app.Tabs, 'Title', 'Species');
            app.SpeciesTab = t;

            gl = uigridlayout(t, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',12);

            % --- Left: species editor ---
            leftP = uipanel(gl, 'Title','Species List', 'FontWeight','bold');
            leftG = uigridlayout(leftP, [4 1], ...
                'RowHeight',{'1x', 30, 30, 36}, 'Padding',[8 8 8 8], 'RowSpacing',4);

            app.SpeciesTable = uitable(leftG, 'ColumnEditable',[true true], ...
                'ColumnName', {'Name','MW (kg/kmol)'}, ...
                'CellEditCallback', @(src,evt) app.onSpeciesTableEdit(src,evt));

            % Add row
            addR = uigridlayout(leftG, [1 3], 'ColumnWidth',{'1x','1x',80}, ...
                'Padding',[0 0 0 0]);
            app.NewSpeciesName = uieditfield(addR,'text','Placeholder','Name');
            app.NewSpeciesMW   = uieditfield(addR,'numeric','Value',28.0,'Limits',[0.001 1e6]);
            app.AddSpeciesBtn  = uibutton(addR,'push','Text','+ Add', ...
                'ButtonPushedFcn',@(~,~) app.addSpeciesRow());

            app.RemoveSpeciesBtn = uibutton(leftG,'push','Text','Remove Selected Row', ...
                'ButtonPushedFcn',@(~,~) app.removeSpeciesRow());

            app.ApplySpeciesBtn = uibutton(leftG,'push', ...
                'Text','Apply Species (resets streams & units)', ...
                'FontWeight','bold', 'BackgroundColor',[0.82 0.90 1.0], ...
                'ButtonPushedFcn',@(~,~) app.applySpecies());

            % --- Right: thermodynamic properties (read-only from library) ---
            rightP = uipanel(gl, 'Title','Thermodynamic Properties (from library)', 'FontWeight','bold');
            rightG = uigridlayout(rightP, [1 1], 'Padding',[8 8 8 8]);
            app.SpeciesPropsTable = uitable(rightG, 'ColumnEditable',false, ...
                'ColumnName', {'Name','MW','Cp@298 (kJ/kmol/K)','Hf298 (kJ/kmol)','S298 (kJ/kmol/K)','T range (K)'});
        end

        % ================================================================
        %  TAB 2: STREAMS
        % ================================================================
        function buildStreamsTab(app)
            t = uitab(app.Tabs, 'Title', 'Streams');
            app.StreamsTab = t;
            gl = uigridlayout(t, [4 1], 'RowHeight',{24,'1x','1x',36}, ...
                'Padding',[12 12 12 12], 'RowSpacing',6);

            % DOF bar
            app.StreamDOFLabel = uilabel(gl, 'Text','DOF: —', ...
                'FontWeight','bold', 'FontSize',13, ...
                'BackgroundColor',[0.92 0.93 0.95]);
            app.StreamDOFLabel.Layout.Row = 1;

            % Stream values
            topP = uipanel(gl, 'Title', ...
                'Stream Values (double-click cell to edit)', 'FontWeight','bold');
            topP.Layout.Row = 2;
            topG = uigridlayout(topP, [1 1], 'Padding',[4 4 4 4]);
            app.StreamValTable = uitable(topG, 'ColumnEditable',true, ...
                'CellEditCallback', @(src,evt) app.onStreamValEdit(src,evt));

            % Known flags
            midP = uipanel(gl, 'Title', ...
                'Known Flags (checked = you specify it, unchecked = solver finds it)', ...
                'FontWeight','bold');
            midP.Layout.Row = 3;
            midG = uigridlayout(midP, [1 1], 'Padding',[4 4 4 4]);
            app.StreamKnownTable = uitable(midG, 'ColumnEditable',true, ...
                'CellEditCallback', @(src,evt) app.onKnownEdit(src,evt));

            % Add/Remove bar
            botG = uigridlayout(gl, [1 4], ...
                'ColumnWidth',{100, 120, 110, 140}, 'Padding',[0 0 0 0]);
            botG.Layout.Row = 4;
            uilabel(botG,'Text','New stream:','FontWeight','bold');
            app.StreamNameField = uieditfield(botG,'text','Value','S1');
            app.AddStreamBtn = uibutton(botG,'push','Text','Add Stream', ...
                'BackgroundColor',[0.82 0.95 0.82], ...
                'ButtonPushedFcn',@(~,~) app.addStreamFromUI());
            app.RemoveStreamBtn = uibutton(botG,'push','Text','Remove Selected', ...
                'BackgroundColor',[1.0 0.88 0.88], ...
                'ButtonPushedFcn',@(~,~) app.removeSelectedStream());
        end

        % ================================================================
        %  TAB 3: UNITS
        % ================================================================
        function buildUnitsTab(app)
            t = uitab(app.Tabs, 'Title', 'Units');
            app.UnitsTab = t;
            gl = uigridlayout(t, [2 2], 'ColumnWidth',{'1x','1x'}, ...
                'RowHeight',{24, '1x'}, 'Padding',[12 12 12 12], 'RowSpacing',6);

            % DOF bar spanning both columns
            app.UnitDOFLabel = uilabel(gl, 'Text','DOF: —', ...
                'FontWeight','bold', 'FontSize',13, ...
                'BackgroundColor',[0.92 0.93 0.95]);
            app.UnitDOFLabel.Layout.Row = 1;
            app.UnitDOFLabel.Layout.Column = [1 2];

            % Left: unit list + controls
            leftP = uipanel(gl, 'Title','Unit Operations', 'FontWeight','bold');
            leftP.Layout.Row = 2; leftP.Layout.Column = 1;
            leftG = uigridlayout(leftP, [3 1], 'RowHeight',{'1x',30,30}, ...
                'Padding',[6 6 6 6], 'RowSpacing',4);

            app.UnitsListBox = uilistbox(leftG, 'Items',{}, 'Value',{});

            addRow = uigridlayout(leftG, [1 2], ...
                'ColumnWidth',{140,'1x'}, 'Padding',[0 0 0 0]);
            catalog = app.unitTypeCatalog();
            app.AddUnitDropDown = uidropdown(addRow, ...
                'Items', {catalog.label}, ...
                'ItemsData', {catalog.type}, ...
                'Value', 'Mixer', ...
                'Tooltip', catalog(1).description, ...
                'ValueChangedFcn', @(src,~) app.updateUnitTypeTooltip(src));
            app.AddUnitBtn = uibutton(addRow,'push','Text','Add Unit...', ...
                'BackgroundColor',[0.82 0.95 0.82], ...
                'ButtonPushedFcn',@(~,~) app.addUnitFromUI());

            actRow = uigridlayout(leftG, [1 2], ...
                'ColumnWidth',{'1x','1x'}, 'Padding',[0 0 0 0]);
            app.ConfigUnitBtn = uibutton(actRow,'push','Text','Configure...', ...
                'ButtonPushedFcn',@(~,~) app.configureSelectedUnit());
            app.RemoveUnitBtn = uibutton(actRow,'push','Text','Remove', ...
                'BackgroundColor',[1.0 0.88 0.88], ...
                'ButtonPushedFcn',@(~,~) app.removeSelectedUnit());

            % Right: flowsheet diagram
            rightP = uipanel(gl, 'Title','Process Flow Diagram', 'FontWeight','bold');
            rightP.Layout.Row = 2; rightP.Layout.Column = 2;
            rightG = uigridlayout(rightP, [1 1], 'Padding',[4 4 4 4]);
            app.FlowsheetAxes = uiaxes(rightG);
            title(app.FlowsheetAxes, 'Add units to see diagram');
            app.FlowsheetAxes.XTick = []; app.FlowsheetAxes.YTick = [];
            box(app.FlowsheetAxes, 'on');
        end

        % ================================================================
        %  TAB 4: SOLVE  (rebuilt — simple 4-row layout)
        % ================================================================
        function buildSolveTab(app)
            t = uitab(app.Tabs, 'Title', 'Solve');
            app.SolveTab = t;

            % 5 rows: DOF bar | controls row | metrics bar | convergence plot | log
            gl = uigridlayout(t, [5 1], ...
                'RowHeight', {32, 42, 28, '2x', '1x'}, ...
                'Padding', [14 14 14 14], 'RowSpacing', 8);

            % --- Row 1: DOF status ---
            dofG = uigridlayout(gl, [1 1], 'Padding', [10 4 10 4]);
            dofG.Layout.Row = 1;
            dofG.BackgroundColor = [0.92 0.94 0.97];
            app.DOFLabel = uilabel(dofG, 'Text', 'DOF: — (add streams and units first)', ...
                'FontWeight','bold', 'FontSize', 13, ...
                'FontColor', [0.20 0.25 0.35]);

            % --- Row 2: solver controls ---
            ctrlG = uigridlayout(gl, [1 6], ...
                'ColumnWidth', {120, 80, 120, 110, '1x', 160}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 10);
            ctrlG.Layout.Row = 2;

            uilabel(ctrlG, 'Text', 'Max Iterations:', ...
                'HorizontalAlignment','right', 'FontWeight','bold', ...
                'FontSize', 12, 'FontColor', [0.25 0.25 0.30]);
            app.MaxIterField = uieditfield(ctrlG, 'numeric', 'Value', 200, ...
                'Limits', [1 100000], 'RoundFractionalValues', 'on');
            uilabel(ctrlG, 'Text', 'Tolerance (abs):', ...
                'HorizontalAlignment','right', 'FontWeight','bold', ...
                'FontSize', 12, 'FontColor', [0.25 0.25 0.30]);
            app.TolField = uieditfield(ctrlG, 'numeric', 'Value', 1e-9, ...
                'Limits', [1e-15 1]);
            uilabel(ctrlG, 'Text', '');  % spacer
            app.SolveBtn = uibutton(ctrlG, 'push', 'Text', 'SOLVE', ...
                'FontWeight','bold', 'FontSize', 16, ...
                'BackgroundColor', [0.18 0.62 0.30], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) app.runSolver());

            % --- Row 3: live metrics bar ---
            metG = uigridlayout(gl, [1 3], ...
                'ColumnWidth', {'1x','1x','1x'}, ...
                'Padding', [10 3 10 3], 'ColumnSpacing', 16);
            metG.Layout.Row = 3;
            metG.BackgroundColor = [0.94 0.95 0.97];
            app.SolveIterLabel = uilabel(metG, 'Text', 'Iteration: —', ...
                'FontSize', 12, 'FontColor', [0.30 0.30 0.35]);
            app.SolveAvgTimeLabel = uilabel(metG, 'Text', 'Avg time/iter: —', ...
                'FontSize', 12, 'FontColor', [0.30 0.30 0.35], ...
                'HorizontalAlignment', 'center');
            app.SolveElapsedLabel = uilabel(metG, 'Text', 'Elapsed: 00:00', ...
                'FontSize', 12, 'FontColor', [0.30 0.30 0.35], ...
                'HorizontalAlignment', 'right');

            % --- Row 4: convergence plot ---
            plotP = uipanel(gl, 'Title','Convergence', 'FontWeight','bold');
            plotP.Layout.Row = 4;
            plotG = uigridlayout(plotP, [1 1], 'Padding',[6 6 6 6]);
            app.ResidualAxes = uiaxes(plotG);
            ylabel(app.ResidualAxes, '||residual||');
            xlabel(app.ResidualAxes, 'Iteration');
            app.ResidualAxes.YScale = 'log';
            grid(app.ResidualAxes, 'on');
            title(app.ResidualAxes, 'Click SOLVE to start');

            % --- Row 5: solver log ---
            logP = uipanel(gl, 'Title','Solver Log', 'FontWeight','bold');
            logP.Layout.Row = 5;
            logG = uigridlayout(logP, [1 1], 'Padding',[6 6 6 6]);
            app.LogArea = uitextarea(logG, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',11);
        end

        % ================================================================
        %  TAB 5: RESULTS
        % ================================================================
        function buildResultsTab(app)
            t = uitab(app.Tabs, 'Title', 'Trends');
            app.ResultsTab = t;
            gl = uigridlayout(t, [1 2], 'ColumnWidth',{420,'1x'}, ...
                'Padding',[8 8 8 8], 'ColumnSpacing',6);

            ctrlP = uipanel(gl, 'Title','Trend Controls', 'FontWeight','bold');
            ctrlP.Layout.Column = 1;
            cg = uigridlayout(ctrlP, [8 1], ...
                'RowHeight',{66,66,66,66,26,26,26,'1x'}, ...
                'Padding',[4 4 4 4], 'RowSpacing',3);

            app.buildTraceRow(cg, 1, 'flow', 'left');
            app.buildTraceRow(cg, 2, 'T', 'right');
            app.buildTraceRow(cg, 3, 'residual', 'left');
            app.buildTraceRow(cg, 4, 'power', 'right');

            row5 = uigridlayout(cg,[1 6],'ColumnWidth',{'fit',130,'fit',110,'fit','1x'},'Padding',[0 0 0 0]);
            uilabel(row5,'Text','Preset','FontWeight','bold');
            app.ResultsPresetDD = uidropdown(row5, 'Items',{'custom','convergence','stream profiles','unit performance'}, 'Value','custom');
            app.ResultsApplyPresetBtn = uibutton(row5, 'push', 'Text','Apply', 'ButtonPushedFcn',@(~,~) app.applyResultsPreset());
            uilabel(row5,'Text','Smooth','FontWeight','bold');
            app.ResultsSmoothingDD = uidropdown(row5, 'Items',{'none','moving-average','median'}, 'Value','none', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            app.ResultsSmoothWindowField = uieditfield(row5, 'numeric', 'Value',3, 'Limits',[1 999], 'RoundFractionalValues','on', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());

            row6 = uigridlayout(cg,[1 8],'ColumnWidth',{'fit',90,'fit',90,'fit',90,'fit','1x'},'Padding',[0 0 0 0]);
            uilabel(row6,'Text','Norm','FontWeight','bold');
            app.ResultsNormModeDD = uidropdown(row6, 'Items',{'absolute','normalized'}, 'Value','absolute', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(row6,'Text','Legend','FontWeight','bold');
            app.ResultsLegendDD = uidropdown(row6, 'Items',{'best','northeast','northwest','southeast','southwest','off'}, 'Value','best', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(row6,'Text','Scale','FontWeight','bold');
            scales = uigridlayout(row6,[1 2],'ColumnWidth',{70,70},'Padding',[0 0 0 0]);
            app.ResultsXScaleDropDown = uidropdown(scales, 'Items',{'linear','log'}, 'Value','linear', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            app.ResultsYScaleDropDown = uidropdown(scales, 'Items',{'linear','log'}, 'Value','linear', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(row6,'Text','');
            app.ResultsPlotStatusLabel = uilabel(row6, 'Text','Run solve to see iteration trends.', 'FontColor',[0.35 0.35 0.35]);

            row7 = uigridlayout(cg,[1 4],'ColumnWidth',{100,100,100,'1x'},'Padding',[0 0 0 0]);
            app.ResultsResetBtn = uibutton(row7, 'push', 'Text','Reset', 'ButtonPushedFcn',@(~,~) app.resetResultsView());
            app.ResultsClearChartBtn = uibutton(row7, 'push', 'Text','Clear', 'ButtonPushedFcn',@(~,~) app.clearResultsChart());
            app.ResultsExportBtn = uibutton(row7, 'push', 'Text','Export', 'ButtonPushedFcn',@(~,~) app.exportResultsFigure());
            uilabel(row7,'Text','');

            axP = uipanel(gl, 'Title','Convergence & Solved-State Trends', 'FontWeight','bold');
            axP.Layout.Column = 2;
            axG = uigridlayout(axP,[1 1],'Padding',[4 4 4 4]);
            app.ResultsAxes = uiaxes(axG);
            grid(app.ResultsAxes,'on');
            xlabel(app.ResultsAxes,'Iteration');
            ylabel(app.ResultsAxes,'Value');
            title(app.ResultsAxes,'Solve to see iteration trends');

            app.resetResultsView();
            app.refreshResultsTargetOptions();
        end

        function buildTraceRow(app, parent, idx, yDefault, axisDefault)
            varsAll = {'iteration','residual','flow','T','P','conversion','efficiency','duty','power','y(i)','deltaT_hx','power_specific','conversion_profile'};
            varsY = varsAll(2:end);
            traceColors = {[0.00 0.45 0.74],[0.85 0.33 0.10],[0.47 0.67 0.19],[0.49 0.18 0.56]};
            p = uipanel(parent, 'Title', sprintf('Trace %d', idx));
            g = uigridlayout(p,[2 6],'ColumnWidth',{'fit',90,'fit',90,50,'1x'},'RowHeight',{22,22},'Padding',[2 2 2 2],'RowSpacing',1);
            uilabel(g,'Text','Y','FontWeight','bold','FontColor',traceColors{idx});
            app.(['ResultsConfig' num2str(idx) 'YVarDD']) = uidropdown(g, 'Items',varsY, 'Value',yDefault, 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(g,'Text','Axis','FontWeight','bold');
            app.(['ResultsConfig' num2str(idx) 'AxisDD']) = uidropdown(g, 'Items',{'left','right'}, 'Value',axisDefault, 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            app.(['ResultsConfig' num2str(idx) 'NormCheck']) = uicheckbox(g, 'Text','Norm', 'Value',false, 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            app.(['ResultsConfig' num2str(idx) 'ScaleField']) = uieditfield(g, 'numeric', 'Value',1, 'Limits',[-1e12 1e12], 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(g,'Text','Target','FontWeight','bold');
            app.(['ResultsConfig' num2str(idx) 'TargetDD']) = uidropdown(g, 'Items',{'(none)'}, 'Value','(none)', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            uilabel(g,'Text','Comp','FontWeight','bold');
            app.(['ResultsConfig' num2str(idx) 'CompDD']) = uidropdown(g, 'Items',{'1'}, 'Value','1', 'ValueChangedFcn',@(~,~) app.refreshResultsTable());
            % X var is always iteration for simplicity, store as hidden dropdown
            app.(['ResultsConfig' num2str(idx) 'XVarDD']) = uidropdown(g, 'Items',varsAll, 'Value','iteration', 'Visible','off');
            uilabel(g,'Text','');
        end

        function buildResultsTablesTab(app)
            t = uitab(app.Tabs, 'Title', 'Results');
            app.ResultsTablesTab = t;
            gl = uigridlayout(t, [5 2], ...
                'RowHeight',{28, 28, '1x', 'fit', 24}, ...
                'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',8, 'RowSpacing',6);

            % --- Row 1: Solve status banner ---
            bannerG = uigridlayout(gl, [1 3], ...
                'ColumnWidth',{'fit','fit','1x'}, ...
                'Padding',[8 3 8 3], 'ColumnSpacing',16);
            bannerG.Layout.Row = 1; bannerG.Layout.Column = [1 2];
            bannerG.BackgroundColor = [0.92 0.94 0.97];
            app.ResultsTablesStatusBanner = uilabel(bannerG, ...
                'Text','Status: Not solved', ...
                'FontWeight','bold', 'FontSize',12, ...
                'FontColor',[0.6 0.1 0.1]);
            app.ResultsTablesResidualLabel = uilabel(bannerG, ...
                'Text','Residual: -', 'FontSize',11, ...
                'FontColor',[0.3 0.3 0.3]);
            app.ResultsTablesIterLabel = uilabel(bannerG, ...
                'Text','Iterations: -', 'FontSize',11, ...
                'FontColor',[0.3 0.3 0.3]);

            % --- Row 2: Table headers ---
            uilabel(gl,'Text','Stream Results', 'FontWeight','bold');
            uilabel(gl,'Text','Unit Results', 'FontWeight','bold');

            % --- Row 3: Tables ---
            app.ResultsStreamTable = uitable(gl, 'ColumnEditable', false);
            app.ResultsUnitTable = uitable(gl, 'ColumnEditable', false);

            % --- Row 4: Export buttons ---
            expG = uigridlayout(gl, [1 6], ...
                'ColumnWidth',{130, 130, 130, 130, 150, '1x'}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6);
            expG.Layout.Row = 4; expG.Layout.Column = [1 2];
            uibutton(expG,'push','Text','Export Stream CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportResultsStreamCsv());
            uibutton(expG,'push','Text','Export Unit CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportResultsUnitCsv());
            uibutton(expG,'push','Text','Export Summary CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportResultsSummaryCsv());
            uibutton(expG,'push','Text','Export Traces CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportResultsTracesCsv());
            uibutton(expG,'push','Text','Export Full Bundle', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.exportResultsBundleCsv());
            uilabel(expG,'Text','');

            % --- Row 5: Status ---
            app.ResultsTablesStatusLabel = uilabel(gl, ...
                'Text','Run solve to populate results.', ...
                'FontColor',[0.35 0.35 0.35]);
            app.ResultsTablesStatusLabel.Layout.Row = 5;
            app.ResultsTablesStatusLabel.Layout.Column = [1 2];

            app.refreshResultsTablesTab();
        end

        function buildResultsStabilityTab(app)
            t = uitab(app.Tabs, 'Title', 'Stability');
            app.ResultsStabilityTab = t;
            gl = uigridlayout(t, [4 4], 'RowHeight',{28,34,48,'1x'}, ...
                'ColumnWidth',{'fit','1x','fit','1x'}, 'Padding',[12 12 12 12], 'ColumnSpacing',8, 'RowSpacing',6);

            % --- Row 1: Controls ---
            uilabel(gl,'Text','Sweep parameter','FontWeight','bold');
            app.ResultsStabilitySweepParamDD = uidropdown(gl, 'Items',{'none','Reactor conversion','Purge beta','Separator phi(1)'}, 'Value','none');
            uilabel(gl,'Text','min/max/pts','FontWeight','bold');
            sweepRangeG = uigridlayout(gl,[1 3], 'ColumnWidth',{'1x','1x',54}, 'Padding',[0 0 0 0]);
            app.ResultsStabilitySweepMinField = uieditfield(sweepRangeG, 'numeric', 'Value',0.1);
            app.ResultsStabilitySweepMaxField = uieditfield(sweepRangeG, 'numeric', 'Value',0.9);
            app.ResultsStabilitySweepPtsField = uieditfield(sweepRangeG, 'numeric', 'Value',11, 'Limits',[2 200], 'RoundFractionalValues','on');
            app.ResultsStabilitySweepPtsField.Layout.Column = 3;

            % --- Row 2: Run button + status ---
            app.ResultsStabilityBtn = uibutton(gl, 'push', 'Text','Run Stability Analysis', ...
                'FontWeight','bold', 'BackgroundColor',[0.93 0.88 0.99], 'ButtonPushedFcn',@(~,~) app.updateStabilityAnalysisTab());
            app.ResultsStabilityBtn.Layout.Column = [1 2];
            app.ResultsStabilityStatusLabel = uilabel(gl, 'Text','Run solve first, then run stability analysis.', 'FontColor',[0.35 0.35 0.35]);
            app.ResultsStabilityStatusLabel.Layout.Column = [3 4];

            % --- Row 3: Explainer / legend bar ---
            infoG = uigridlayout(gl,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0],'ColumnSpacing',8);
            infoG.Layout.Row = 3; infoG.Layout.Column = [1 4];
            nyqInfo = uilabel(infoG, 'Text', ...
                ['Nyquist (left): Plots eigenvalues of the resolvent L(j\omega) = (j\omega I - A)^{-1}. ' ...
                 'Solid = +\omega, dashed = -\omega. Red x marks the critical point (-1+0j). ' ...
                 'Encirclements of the origin indicate instability.'], ...
                'FontSize',11, 'FontColor',[0.35 0.35 0.40], 'WordWrap','on');
            nyqInfo.Layout.Column = 1;
            poleInfo = uilabel(infoG, 'Text', ...
                ['Pole Map (right): Shows eigenvalues of the Jacobian A. ' ...
                 'Blue x = stable poles (Re < 0), red x = unstable poles (Re >= 0). ' ...
                 'If sweep is set, plots max Re(pole) vs parameter -- below zero means stable.'], ...
                'FontSize',11, 'FontColor',[0.35 0.35 0.40], 'WordWrap','on');
            poleInfo.Layout.Column = 2;

            % --- Row 4: Plots ---
            p1 = uipanel(gl, 'Title','Nyquist Diagram (Characteristic Loci)', 'FontWeight','bold');
            p1.Layout.Row = 4; p1.Layout.Column = [1 2];
            g1 = uigridlayout(p1,[1 1],'Padding',[4 4 4 4]);
            app.ResultsNyquistAxes = uiaxes(g1);
            grid(app.ResultsNyquistAxes,'on'); xlabel(app.ResultsNyquistAxes,'Re(\lambda)'); ylabel(app.ResultsNyquistAxes,'Im(\lambda)');

            p2 = uipanel(gl, 'Title','Pole Map & Stability Sweep', 'FontWeight','bold');
            p2.Layout.Row = 4; p2.Layout.Column = [3 4];
            g2 = uigridlayout(p2,[1 1],'Padding',[4 4 4 4]);
            app.ResultsStabilitySweepAxes = uiaxes(g2);
            grid(app.ResultsStabilitySweepAxes,'on'); xlabel(app.ResultsStabilitySweepAxes,'Re(pole)'); ylabel(app.ResultsStabilitySweepAxes,'Im(pole)');
        end

        % ================================================================
        %  TAB 6: SENSITIVITY
        % ================================================================
        function buildSensitivityTab(app)
            t = uitab(app.Tabs, 'Title', 'Sensitivity');
            app.SensTab = t;
            gl = uigridlayout(t, [2 1], 'RowHeight',{190,'1x'}, ...
                'Padding',[12 12 12 12], 'RowSpacing',8);

            % Top: controls in a 5-row, 4-col grid
            topP = uipanel(gl, 'Title','Setup', 'FontWeight','bold');
            topP.Layout.Row = 1;
            topG = uigridlayout(topP, [5 4], ...
                'ColumnWidth', {130, '1x', 130, '1x'}, ...
                'RowHeight', {26, 26, 26, 26, 26}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 4, 'ColumnSpacing', 8);

            % Row 1
            uilabel(topG,'Text','Sweep parameter:','FontWeight','bold');
            app.SensParamDropDown = uidropdown(topG, ...
                'Items',{'(build flowsheet first)'}, ...
                'Value','(build flowsheet first)', ...
                'ValueChangedFcn',@(~,~) app.onSensParamChanged());
            app.SensParamDropDown.Layout.Column = [2 4];

            % Row 2
            uilabel(topG,'Text','Min / Max / Pts:','FontWeight','bold');
            rangeG = uigridlayout(topG, [1 3], ...
                'ColumnWidth',{'1x','1x',60}, 'Padding',[0 0 0 0]);
            app.SensMinField = uieditfield(rangeG,'numeric','Value',0.1);
            app.SensMaxField = uieditfield(rangeG,'numeric','Value',0.9);
            app.SensNptsField = uieditfield(rangeG,'numeric','Value',15, ...
                'Limits',[2 200],'RoundFractionalValues','on');
            uilabel(topG,'Text','Output stream:','FontWeight','bold');
            app.SensOutputStreamDD = uidropdown(topG,'Items',{'(none)'},'Value','(none)');

            % Row 3
            uilabel(topG,'Text','Output field:','FontWeight','bold');
            app.SensOutputFieldDD = uidropdown(topG, ...
                'Items',{'n_dot','T','P','y(1)','y(2)','y(3)'},'Value','n_dot');
            uilabel(topG,'Text','');
            uilabel(topG,'Text','');

            % Row 4: solver parameters
            uilabel(topG,'Text','Max iterations:','FontWeight','bold');
            app.SensMaxIterField = uieditfield(topG,'numeric','Value',300, ...
                'Limits',[1 100000],'RoundFractionalValues','on');
            uilabel(topG,'Text','Tolerance (abs):','FontWeight','bold');
            app.SensTolField = uieditfield(topG,'numeric','Value',1e-8, ...
                'Limits',[1e-15 1]);

            % Row 5: status + run button
            app.SensStatusLabel = uilabel(topG,'Text','', ...
                'FontColor',[0.5 0.5 0.5],'FontAngle','italic');
            app.SensStatusLabel.Layout.Column = [1 2];
            uilabel(topG,'Text','');
            app.SensRunBtn = uibutton(topG,'push','Text','Run Sensitivity', ...
                'FontWeight','bold','BackgroundColor',[0.25 0.50 0.80],'FontColor','w', ...
                'ButtonPushedFcn',@(~,~) app.runSensitivity());

            % Bottom: plot
            botP = uipanel(gl, 'Title','Results', 'FontWeight','bold');
            botP.Layout.Row = 2;
            botG = uigridlayout(botP, [1 1], 'Padding',[4 4 4 4]);
            app.SensAxes = uiaxes(botG);
            title(app.SensAxes, 'Run analysis to see results');
            grid(app.SensAxes, 'on');
        end
    end

    % =====================================================================
    %  SPECIES CALLBACKS
    % =====================================================================
    methods (Access = private)

        function refreshSpeciesTable(app)
            app.syncModelToState();
            app.SpeciesController.refreshSpeciesTable(app.SpeciesTable);
            app.syncStateToModel();
        end

        function onSpeciesTableEdit(app, ~, evt)
            app.syncModelToState();
            app.SpeciesController.onSpeciesTableEdit(evt);
            app.syncStateToModel();
        end

        function addSpeciesRow(app)
            app.syncModelToState();
            app.SpeciesController.addSpeciesRow(app.NewSpeciesName, app.NewSpeciesMW, app.SpeciesTable);
            app.syncStateToModel();
        end

        function removeSpeciesRow(app)
            app.syncModelToState();
            app.SpeciesController.removeSpeciesRow(app.SpeciesTable);
            app.syncStateToModel();
        end

        function applySpecies(app)
            app.syncModelToState();
            app.SpeciesController.applySpecies();
            app.syncStateToModel();
        end

        function refreshSpeciesPropsTable(app)
            % Populate the thermodynamic properties table from the library
            N = numel(app.speciesNames);
            data = cell(N, 6);
            try
                lib = proc.thermo.ThermoLibrary();
            catch
                lib = [];
            end
            for i = 1:N
                data{i,1} = app.speciesNames{i};
                data{i,2} = app.speciesMW(i);
                if ~isempty(lib) && lib.hasSpecies(app.speciesNames{i})
                    sp = lib.get(app.speciesNames{i});
                    try
                        data{i,3} = sp.cp_molar(298.15);
                    catch
                        data{i,3} = NaN;
                    end
                    data{i,4} = sp.Hf298_kJkmol;
                    data{i,5} = sp.S298_kJkmolK;
                    if ~isempty(sp.ranges)
                        Tlo = sp.ranges(1).Tmin;
                        Thi = sp.ranges(end).Tmax;
                        data{i,6} = sprintf('%.0f - %.0f', Tlo, Thi);
                    else
                        data{i,6} = 'N/A';
                    end
                else
                    data{i,3} = NaN; data{i,4} = NaN; data{i,5} = NaN;
                    data{i,6} = 'Not in library';
                end
            end
            app.SpeciesPropsTable.Data = data;
        end
    end

    % =====================================================================
    %  STREAM CALLBACKS
    % =====================================================================
    methods (Access = private)

        function addStreamInternal(app, name)
            s = proc.Stream(string(name), app.speciesNames);
            s.n_dot = 1; s.T = 300; s.P = 1e5;
            s.y = ones(1, numel(app.speciesNames)) / numel(app.speciesNames);
            app.streams{end+1} = s;
        end

        function setNextStreamName(app, name)
            app.StreamNameField.Value = char(string(name));
        end

        function setSensitivityStatusText(app, txt)
            app.SensStatusLabel.Text = txt;
        end

        function setSensitivityRunEnabled(app, tf)
            if tf
                app.SensRunBtn.Enable = 'on';
            else
                app.SensRunBtn.Enable = 'off';
            end
        end

        function plotSensitivityResults(app, vals, results, paramLabel, outStreamName, outFieldStr)
            plot(app.SensAxes, vals, results, '-o', 'LineWidth',1.5, ...
                'MarkerSize',5, 'Color',[0.2 0.5 0.8]);
            xlabel(app.SensAxes, paramLabel);
            ylabel(app.SensAxes, sprintf('%s . %s', outStreamName, strrep(outFieldStr,'_','\_')));
            title(app.SensAxes, 'Sensitivity Analysis');
            grid(app.SensAxes, 'on');
        end

        function row = getSelectedStreamRow(app)
            sel = app.StreamValTable.Selection;
            if isempty(sel)
                row = [];
                return;
            end
            row = sel(1);
        end

        function addStreamFromUI(app)
            app.syncModelToState();
            app.StreamsController.addStreamFromUI();
            app.syncStateToModel();
        end

        function removeSelectedStream(app)
            app.syncModelToState();
            app.StreamsController.removeSelectedStream();
            app.syncStateToModel();
        end

        function refreshStreamTables(app)
            ns = numel(app.speciesNames);
            N = numel(app.streams);
            yTol = app.getYSumTolerance();

            colNames = [{'Name', app.unitLabel('flow','n_dot'), app.unitLabel('temperature','T'), app.unitLabel('pressure','P')}, ...
                cellfun(@(sp) ['y_' sp], app.speciesNames, 'Uni',false), ...
                {'sum_y','y_ok'}];
            data = cell(N, 6+ns);
            for i = 1:N
                s = app.streams{i};
                data{i,1} = char(string(s.name));
                data{i,2} = app.fromSI(s.n_dot,'flow');
                data{i,3} = app.fromSI(s.T,'temperature');
                data{i,4} = app.fromSI(s.P,'pressure');
                for j = 1:ns
                    if j <= numel(s.y), data{i,4+j} = s.y(j);
                    else,               data{i,4+j} = 0;
                    end
                end
                [sumY, yStatus] = app.evaluateYSumStatus(s, yTol);
                data{i,5+ns} = sumY;
                data{i,6+ns} = yStatus;
            end
            app.StreamValTable.Data = data;
            app.StreamValTable.ColumnName = colNames;
            app.StreamValTable.ColumnEditable = [false, true(1, 3+ns), false, false];
            app.applyStreamYStyles();

            knData = cell(N, 5);
            for i = 1:N
                s = app.streams{i};
                knData{i,1} = char(string(s.name));
                knData{i,2} = s.known.n_dot;
                knData{i,3} = s.known.T;
                knData{i,4} = s.known.P;
                knData{i,5} = all(s.known.y);
            end
            app.StreamKnownTable.Data = knData;
            app.StreamKnownTable.ColumnName = {'Name',app.unitLabel('flow','n_dot'),app.unitLabel('temperature','T'),app.unitLabel('pressure','P'),'y (all)'};
            app.StreamKnownTable.ColumnEditable = [false, true, true, true, true];
        end

        function onStreamValEdit(app, src, evt)
            app.syncModelToState();
            app.StreamsController.onStreamValEdit(src, evt);
            app.syncStateToModel();
        end

        function onKnownEdit(app, src, evt)
            app.syncModelToState();
            app.StreamsController.onKnownEdit(src, evt);
            app.syncStateToModel();
        end

        function syncStreamsFromTable(app)
            D = app.StreamValTable.Data;
            if isempty(D), return; end
            ns = numel(app.speciesNames);
            for i = 1:min(size(D,1), numel(app.streams))
                s = app.streams{i};
                s.n_dot = app.toSI(D{i,2},'flow');
                s.T = app.toSI(D{i,3},'temperature');
                s.P = app.toSI(D{i,4},'pressure');
                for j = 1:ns, s.y(j) = D{i,4+j}; end
            end
        end

        function tol = getYSumTolerance(app)
            tol = 1e-9;
            if ~isempty(app.TolField) && isnumeric(app.TolField.Value) && isfinite(app.TolField.Value)
                tol = app.TolField.Value;
            end
            tol = max(tol, eps);
        end

        function [sumY, yStatus] = evaluateYSumStatus(~, s, tol)
            yVals = double(s.y(:));
            yVals = yVals(isfinite(yVals));
            sumY = sum(yVals);
            err = abs(sumY - 1.0);
            if err <= tol
                yStatus = 'OK';
            elseif err <= 10*tol
                yStatus = 'WARN';
            else
                yStatus = 'ERROR';
            end
        end

        function applyStreamYStyles(app)
            if isempty(app.StreamValTable) || isempty(app.StreamValTable.Data)
                return;
            end

            removeStyle(app.StreamValTable);

            ns = numel(app.speciesNames);
            sumCol = 5 + ns;
            statusCol = 6 + ns;
            yTol = app.getYSumTolerance();

            goodStyle = uistyle('BackgroundColor',[0.86 0.96 0.86], 'FontColor',[0.00 0.40 0.00]);
            warnStyle = uistyle('BackgroundColor',[1.00 0.95 0.80], 'FontColor',[0.55 0.35 0.00]);
            badStyle  = uistyle('BackgroundColor',[1.00 0.85 0.85], 'FontColor',[0.60 0.00 0.00]);

            for i = 1:numel(app.streams)
                [~, yStatus] = app.evaluateYSumStatus(app.streams{i}, yTol);
                switch yStatus
                    case 'OK'
                        sty = goodStyle;
                    case 'WARN'
                        sty = warnStyle;
                    otherwise
                        sty = badStyle;
                end
                addStyle(app.StreamValTable, sty, 'cell', [i, sumCol]);
                addStyle(app.StreamValTable, sty, 'cell', [i, statusCol]);
            end
        end
    end

    % =====================================================================
    %  LIVE DOF
    % =====================================================================
    methods (Access = private)
        function updateDOF(app)
            if isempty(app.streams) || isempty(app.units)
                txt = 'DOF: add streams and units first';
                clr = [0.5 0.5 0.5];
            else
                fs = app.buildFlowsheet();
                [nU, nE] = fs.checkDOF('quiet',true);
                if nU == nE
                    txt = sprintf('DOF: %d unknowns = %d equations  (square — ready to solve)', nU, nE);
                    clr = [0.0 0.45 0.0];
                elseif nU > nE
                    txt = sprintf('DOF: %d unknowns, %d equations  (under-constrained, need %d more specs)', nU, nE, nU-nE);
                    clr = [0.75 0.45 0.0];
                else
                    txt = sprintf('DOF: %d unknowns, %d equations  (over-constrained by %d)', nU, nE, nE-nU);
                    clr = [0.75 0.0 0.0];
                end
            end

            % Update all DOF labels
            app.DOFLabel.Text = txt;
            app.DOFLabel.FontColor = clr;
            app.StreamDOFLabel.Text = txt;
            app.StreamDOFLabel.FontColor = clr;
            app.UnitDOFLabel.Text = txt;
            app.UnitDOFLabel.FontColor = clr;
        end

        function fs = buildFlowsheet(app)
            [resolvedDefs, aliasByOutlet] = app.resolveIdentityLinks(app.unitDefs);
            fs = proc.Flowsheet(app.speciesNames);
            for i = 1:numel(app.streams)
                fs.addStream(app.streams{i});
            end
            app.addStreamAliasesToFlowsheet(fs, aliasByOutlet);
            for i = 1:numel(resolvedDefs)
                u = app.buildUnitFromDef(resolvedDefs{i}, 'includeIdentityLink', false);
                if ~isempty(u)
                    fs.addUnit(u);
                end
            end
        end
    end

    % =====================================================================
    %  UNITS
    % =====================================================================
    methods (Access = private)

        function refreshUnitsListBox(app)
            items = cell(1, numel(app.units));
            for i = 1:numel(app.units)
                u = app.units{i};
                if ismethod(u,'describe')
                    items{i} = sprintf('[%d] %s', i, u.describe());
                else
                    items{i} = sprintf('[%d] %s', i, class(u));
                end
            end
            if isempty(items)
                app.UnitsListBox.Items = {'(no units — add one above)'};
                app.UnitsListBox.Value = {};
            else
                app.UnitsListBox.Items = items;
                app.UnitsListBox.Value = items(1);
            end
            app.updateSensDropdowns();
        end

        function addUnitFromUI(app)
            typ = app.AddUnitDropDown.Value;
            sNames = app.getStreamNames();
            needsOne = ismember(typ, {'Source','Sink','DesignSpec','Constraint'});
            if needsOne
                if numel(sNames) < 1
                    uialert(app.Fig,'Need at least 1 stream.','Error'); return;
                end
            else
                if numel(sNames) < 2
                    uialert(app.Fig,'Need at least 2 streams.','Error'); return;
                end
            end
            switch typ
                case 'Link',      app.dialogLink(sNames);
                case 'Mixer',     app.dialogMixer(sNames);
                case 'Reactor',   app.dialogReactor(sNames);
                case 'StoichiometricReactor', app.dialogStoichiometricReactor(sNames);
                case 'ConversionReactor', app.dialogConversionReactor(sNames);
                case 'YieldReactor', app.dialogYieldReactor(sNames);
                case 'EquilibriumReactor', app.dialogEquilibriumReactor(sNames);
                case 'Heater',    app.dialogHeater(sNames);
                case 'Cooler',    app.dialogCooler(sNames);
                case 'HeatExchanger', app.dialogHeatExchanger(sNames);
                case 'Compressor', app.dialogCompressor(sNames);
                case 'Turbine',   app.dialogTurbine(sNames);
                case 'Separator', app.dialogSeparator(sNames);
                case 'Purge',     app.dialogPurge(sNames);
                case 'Splitter',  app.dialogSplitter(sNames);
                case 'Recycle',   app.dialogRecycle(sNames);
                case 'Bypass',    app.dialogBypass(sNames);
                case 'Manifold',  app.dialogManifold(sNames);
                case 'Source',    app.dialogSource(sNames);
                case 'Sink',      app.dialogSink(sNames);
                case 'DesignSpec', app.dialogDesignSpec(sNames);
                case 'Adjust',    app.dialogAdjust(sNames);
                case 'Calculator', app.dialogCalculator(sNames);
                case 'Constraint', app.dialogConstraint(sNames);
            end
        end

        function updateUnitTypeTooltip(app, src)
            if isempty(src) || ~isvalid(src)
                return;
            end
            catalog = app.unitTypeCatalog();
            idx = find(strcmp({catalog.type}, char(string(src.Value))), 1);
            if isempty(idx)
                src.Tooltip = '';
            else
                src.Tooltip = catalog(idx).description;
            end
        end

        function configureSelectedUnit(app)
            idx = app.getSelectedUnitIdx();
            if isempty(idx), return; end
            sNames = app.getStreamNames();
            cn = class(app.units{idx});
            if contains(cn,'Link'),      app.dialogLink(sNames,idx);
            elseif contains(cn,'Mixer'), app.dialogMixer(sNames,idx);
            elseif contains(cn,'StoichiometricReactor'), app.dialogStoichiometricReactor(sNames,idx);
            elseif contains(cn,'ConversionReactor'), app.dialogConversionReactor(sNames,idx);
            elseif contains(cn,'YieldReactor'), app.dialogYieldReactor(sNames,idx);
            elseif contains(cn,'EquilibriumReactor'), app.dialogEquilibriumReactor(sNames,idx);
            elseif contains(cn,'Reactor'), app.dialogReactor(sNames,idx);
            elseif contains(cn,'Heater'), app.dialogHeater(sNames,idx);
            elseif contains(cn,'Cooler'), app.dialogCooler(sNames,idx);
            elseif contains(cn,'HeatExchanger'), app.dialogHeatExchanger(sNames,idx);
            elseif contains(cn,'Compressor'), app.dialogCompressor(sNames,idx);
            elseif contains(cn,'Turbine'), app.dialogTurbine(sNames,idx);
            elseif contains(cn,'Separator'), app.dialogSeparator(sNames,idx);
            elseif contains(cn,'Purge'), app.dialogPurge(sNames,idx);
            elseif contains(cn,'Splitter'), app.dialogSplitter(sNames,idx);
            elseif contains(cn,'Recycle'), app.dialogRecycle(sNames,idx);
            elseif contains(cn,'Bypass'), app.dialogBypass(sNames,idx);
            elseif contains(cn,'Manifold'), app.dialogManifold(sNames,idx);
            elseif contains(cn,'Source'), app.dialogSource(sNames,idx);
            elseif contains(cn,'Sink'), app.dialogSink(sNames,idx);
            elseif contains(cn,'DesignSpec'), app.dialogDesignSpec(sNames,idx);
            elseif contains(cn,'Adjust'), app.dialogAdjust(sNames,idx);
            elseif contains(cn,'Calculator'), app.dialogCalculator(sNames,idx);
            elseif contains(cn,'Constraint'), app.dialogConstraint(sNames,idx);
            end
        end

        function removeSelectedUnit(app)
            idx = app.getSelectedUnitIdx();
            if isempty(idx), return; end
            app.units(idx) = [];
            app.unitDefs(idx) = [];
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
        end

        function idx = getSelectedUnitIdx(app)
            idx = [];
            sel = app.UnitsListBox.Value;
            if isempty(sel) || isempty(app.units), return; end
            if iscell(sel), sel = sel{1}; end
            tok = regexp(sel,'^\[(\d+)\]','tokens');
            if isempty(tok), return; end
            idx = str2double(tok{1}{1});
            if idx < 1 || idx > numel(app.units), idx = []; end
        end

        function commitUnit(app, u, def, editIdx)
            if isempty(editIdx)
                app.units{end+1} = u;
                app.unitDefs{end+1} = def;
            else
                app.units{editIdx} = u;
                app.unitDefs{editIdx} = def;
            end
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
        end
    end

    % =====================================================================
    %  FLOWSHEET DIAGRAM
    % =====================================================================
    methods (Access = private)
        function refreshFlowsheetDiagram(app)
            ax = app.FlowsheetAxes;
            cla(ax);
            if isempty(app.units)
                title(ax,'Add units to see diagram'); return;
            end

            src = {}; tgt = {}; elbl = {};
            for i = 1:numel(app.units)
                u = app.units{i};
                uName = sprintf('U%d:%s', i, app.shortTypeName(u));
                cn = class(u);
                if contains(cn,'Link')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Mixer')
                    for k=1:numel(u.inlets)
                        src{end+1}=char(string(u.inlets{k}.name)); tgt{end+1}=uName; elbl{end+1}='';
                    end
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Heater') || contains(cn,'Cooler') || contains(cn,'Compressor') || contains(cn,'Turbine')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'HeatExchanger')
                    src{end+1}=char(string(u.hotInlet.name)); tgt{end+1}=uName; elbl{end+1}='hot in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.hotOutlet.name)); elbl{end+1}='hot out';
                    src{end+1}=char(string(u.coldInlet.name)); tgt{end+1}=uName; elbl{end+1}='cold in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.coldOutlet.name)); elbl{end+1}='cold out';
                elseif contains(cn,'Reactor')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Separator')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outletA.name)); elbl{end+1}='A';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outletB.name)); elbl{end+1}='B';
                elseif contains(cn,'Purge')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.recycle.name)); elbl{end+1}='rec';
                    src{end+1}=uName; tgt{end+1}=char(string(u.purge.name)); elbl{end+1}='pur';
                elseif contains(cn,'Splitter')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    for k=1:numel(u.outlets)
                        src{end+1}=uName; tgt{end+1}=char(string(u.outlets{k}.name)); elbl{end+1}=sprintf('out%d',k);
                    end
                elseif contains(cn,'Recycle')
                    src{end+1}=char(string(u.source.name)); tgt{end+1}=uName; elbl{end+1}='src';
                    src{end+1}=uName; tgt{end+1}=char(string(u.tear.name)); elbl{end+1}='tear';
                elseif contains(cn,'Bypass')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.processInlet.name)); elbl{end+1}='proc in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.bypassStream.name)); elbl{end+1}='bypass';
                    src{end+1}=char(string(u.processReturn.name)); tgt{end+1}=uName; elbl{end+1}='proc ret';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='out';
                elseif contains(cn,'Manifold')
                    for k=1:numel(u.inlets)
                        src{end+1}=char(string(u.inlets{k}.name)); tgt{end+1}=uName; elbl{end+1}=sprintf('in%d',k);
                    end
                    for k=1:numel(u.outlets)
                        src{end+1}=uName; tgt{end+1}=char(string(u.outlets{k}.name)); elbl{end+1}=sprintf('out%d',k);
                    end
                elseif contains(cn,'Source')
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='out';
                elseif contains(cn,'Sink')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='in';
                elseif contains(cn,'DesignSpec')
                    src{end+1}=char(string(u.stream.name)); tgt{end+1}=uName; elbl{end+1}=char(string(u.metric));
                elseif contains(cn,'Adjust')
                    src{end+1}=char(string(u.targetSpec.stream.name)); tgt{end+1}=uName; elbl{end+1}='spec';
                elseif contains(cn,'Calculator')
                    src{end+1}=uName; tgt{end+1}=uName; elbl{end+1}='calc';
                elseif contains(cn,'Constraint')
                    src{end+1}=uName; tgt{end+1}=uName; elbl{end+1}='=';
                end
            end
            if isempty(src), title(ax,'No connections'); return; end

            G = digraph(src, tgt);
            nNames = G.Nodes.Name; nN = numel(nNames);
            nc = zeros(nN,3); ms = 8*ones(nN,1);
            for n=1:nN
                if startsWith(nNames{n},'U')
                    nc(n,:)=[0.2 0.5 0.8]; ms(n)=14;
                else
                    nc(n,:)=[0.85 0.33 0.1]; ms(n)=7;
                end
            end
            h = plot(ax,G,'Layout','layered','Direction','right', ...
                'EdgeLabel',elbl,'NodeColor',nc,'MarkerSize',ms, ...
                'NodeFontSize',9,'EdgeFontSize',8,'ArrowSize',10, ...
                'LineWidth',1.5,'NodeFontWeight','bold');

            % Distinct markers and colors per unit type
            unitColors = struct( ...
                'Mixer',    [0.20 0.60 0.30], ...
                'Link',     [0.40 0.40 0.40], ...
                'Reactor',  [0.85 0.20 0.20], ...
                'StoichiometricReactor', [0.85 0.20 0.20], ...
                'ConversionReactor', [0.85 0.20 0.20], ...
                'YieldReactor', [0.85 0.20 0.20], ...
                'EquilibriumReactor', [0.85 0.20 0.20], ...
                'Heater',   [0.85 0.45 0.10], ...
                'Cooler',   [0.10 0.55 0.85], ...
                'HeatExchanger', [0.65 0.35 0.65], ...
                'Compressor',[0.40 0.70 0.30], ...
                'Turbine',  [0.30 0.50 0.70], ...
                'Separator',[0.10 0.40 0.80], ...
                'Purge',    [0.70 0.40 0.80], ...
                'Splitter', [0.90 0.55 0.10], ...
                'Recycle',  [0.50 0.50 0.10], ...
                'Bypass',   [0.10 0.65 0.65], ...
                'Manifold', [0.35 0.25 0.70], ...
                'Source',   [0.15 0.55 0.20], ...
                'Sink',     [0.55 0.15 0.20], ...
                'DesignSpec',[0.25 0.25 0.85], ...
                'Adjust',   [0.55 0.20 0.65], ...
                'Calculator',[0.20 0.55 0.55], ...
                'Constraint',[0.55 0.55 0.20]);
            unitMarkers = struct( ...
                'Mixer',    'h', ...  % hexagon
                'Link',     's', ...  % square
                'Reactor',  'd', ...  % diamond
                'StoichiometricReactor', 'd', ...
                'ConversionReactor', 'd', ...
                'YieldReactor', 'd', ...
                'EquilibriumReactor', 'd', ...
                'Heater',   '*', ...
                'Cooler',   'x', ...
                'HeatExchanger','o', ...
                'Compressor','+', ...
                'Turbine',  '+', ...
                'Separator','^', ...  % triangle up
                'Purge',    'v', ...     % triangle down
                'Splitter', '>', ...
                'Recycle',  '<', ...
                'Bypass',   'p', ...
                'Manifold', 'o', ...
                'Source',   '>', ...
                'Sink',     '<', ...
                'DesignSpec','d', ...
                'Adjust',   'h', ...
                'Calculator','p', ...
                'Constraint','s');
            for i = 1:numel(app.units)
                uName = sprintf('U%d:%s', i, app.shortTypeName(app.units{i}));
                uType = app.shortTypeName(app.units{i});
                nodeIdx = find(strcmp(nNames, uName));
                if ~isempty(nodeIdx) && isfield(unitMarkers, uType)
                    highlight(h, nodeIdx, ...
                        'Marker', unitMarkers.(uType), ...
                        'NodeColor', unitColors.(uType), ...
                        'MarkerSize', 16);
                end
            end

            title(ax,'Process Flow Diagram');
            ax.XTick=[]; ax.YTick=[];
        end
    end

    % =====================================================================
    %  UNIT DIALOGS
    % =====================================================================
    methods (Access = private)

        function dialogLink(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogLink(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogMixer(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogMixer(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogStoichiometricReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogStoichiometricReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogConversionReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogConversionReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogYieldReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogYieldReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogEquilibriumReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogEquilibriumReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogHeater(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogHeater(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogCooler(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogCooler(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogHeatExchanger(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogHeatExchanger(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogCompressor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogCompressor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogTurbine(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogTurbine(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogSeparator(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogSeparator(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogPurge(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogPurge(sNames, editIdx);
            app.syncStateToModel();
        end

        % Generic dialog builder
        function [d, ctrls] = makeDialog(~, titleStr, w, h, fields)
            nf = numel(fields);
            totalH = max(h, 50 + nf*36);
            d = uifigure('Name',titleStr,'Position',[300 300 w totalH], ...
                'Resize','off','WindowStyle','modal');
            dg = uigridlayout(d, [nf+1, 2], 'ColumnWidth',{160,'1x'}, ...
                'RowHeight',[repmat({28},1,nf),{36}], 'Padding',[12 12 12 12]);
            ctrls = cell(1,nf);
            for i = 1:nf
                f = fields{i};
                uilabel(dg,'Text',f{1},'FontWeight','bold');
                switch f{2}
                    case 'dropdown'
                        ctrls{i} = uidropdown(dg,'Items',f{3},'Value',f{3}{1});
                    case 'text'
                        ctrls{i} = uieditfield(dg,'text','Value',f{3});
                    case 'numeric'
                        ctrls{i} = uieditfield(dg,'numeric','Value',f{3});
                end
                if numel(f) >= 4
                    tip = char(string(f{4}));
                    ctrls{i}.Tooltip = tip;
                end
            end
        end

        function addDialogButtons(~, d, okFcn)
            dg = d.Children(1);
            nRows = numel(dg.RowHeight);
            btnG = uigridlayout(dg,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0]);
            btnG.Layout.Row = nRows; btnG.Layout.Column = [1 2];
            uibutton(btnG,'push','Text','OK','FontWeight','bold', ...
                'BackgroundColor',[0.82 0.95 0.82],'ButtonPushedFcn',@(~,~)okFcn());
            uibutton(btnG,'push','Text','Cancel','ButtonPushedFcn',@(~,~)delete(d));
        end
    end

    % =====================================================================
    %  SOLVER (with real-time residual plot)
    % =====================================================================
    methods (Access = private)

        function ok = validateSolvePreconditions(app)
            ok = false;
            if isempty(app.streams)
                uialert(app.Fig,'No streams.','Error');
                return;
            end
            if isempty(app.units)
                uialert(app.Fig,'No units.','Error');
                return;
            end
            ok = true;
        end

        function setLastFlowsheet(app, fs)
            app.lastFlowsheet = fs;
        end

        function [maxIt, tol] = getSolveInputs(app)
            maxIt = app.MaxIterField.Value;
            tol = app.TolField.Value;
        end

        function hLine = prepareSolveRun(app, tol)
            cla(app.ResidualAxes);
            hLine = animatedline(app.ResidualAxes, 'Color',[0.15 0.50 0.75], ...
                'LineWidth',1.8, 'Marker','o', 'MarkerSize',3);
            yline(app.ResidualAxes, tol, '--r', 'Tolerance', 'LineWidth',1);
            xlabel(app.ResidualAxes,'Iteration');
            ylabel(app.ResidualAxes,'||r||');
            app.ResidualAxes.YScale = 'log';
            grid(app.ResidualAxes,'on');
            title(app.ResidualAxes,'Solving...');

            app.LogArea.Value = {'Solving...'};
            drawnow;
            app.SolveIterLabel.Text = 'Iteration: 0';
            app.SolveAvgTimeLabel.Text = 'Avg time/iter: —';
            app.SolveElapsedLabel.Text = 'Elapsed: 00:00';

            app.SolveStartTic = tic;
            app.SolveTimer = timer('ExecutionMode','fixedRate', ...
                'Period', 0.25, 'TimerFcn', @(~,~) app.updateElapsedClock(), ...
                'ErrorFcn', @(~,~) []);
            start(app.SolveTimer);

            drawnow;

            app.resultsSnapshots = {};
            app.resultsSnapshotIters = [];
            app.resultsSnapshotResiduals = [];
            app.captureResultsSnapshot(0, NaN);
        end

        function onSolveLogLine(app, line, lineIdx)
            stride = max(0, round(app.logEveryN));
            if stride > 0 && mod(lineIdx - 1, stride) ~= 0
                return;
            end

            vals = app.LogArea.Value;
            if ischar(vals), vals = {vals}; end
            if isempty(vals)
                vals = cell(0,1);
            end
            if numel(vals) == 1 && strcmp(vals{1}, 'Solving...')
                vals = cell(0,1);
            end

            vals{end+1,1} = char(line);
            if numel(vals) > 500
                vals = vals(end-499:end);
            end
            app.LogArea.Value = vals;
            drawnow limitrate;
        end

        function onSolveIter(app, iter, rNorm)
            app.captureResultsSnapshot(iter, rNorm);
            elapsed = toc(app.SolveStartTic);
            app.SolveIterLabel.Text = sprintf('Iteration: %d', iter);
            if iter > 0
                avgMs = (elapsed / iter) * 1000;
                if avgMs >= 1000
                    app.SolveAvgTimeLabel.Text = sprintf('Avg time/iter: %.2f s', avgMs/1000);
                else
                    app.SolveAvgTimeLabel.Text = sprintf('Avg time/iter: %.1f ms', avgMs);
                end
            end
        end

        function setLastSolver(app, solver)
            app.lastSolver = solver;
        end

        function onSolveSuccess(app, solver)
            app.stopSolveTimer();
            nIter = numel(solver.residualHistory) - 1;
            elapsed = toc(app.SolveStartTic);
            app.SolveIterLabel.Text = sprintf('Iteration: %d', nIter);
            app.updateElapsedClock();
            if nIter > 0
                avgMs = (elapsed / nIter) * 1000;
                if avgMs >= 1000
                    app.SolveAvgTimeLabel.Text = sprintf('Avg time/iter: %.2f s', avgMs/1000);
                else
                    app.SolveAvgTimeLabel.Text = sprintf('Avg time/iter: %.1f ms', avgMs);
                end
            end

            if solver.converged
                title(app.ResidualAxes, sprintf('Converged in %d iterations', nIter));
                app.setStatus('Solve completed.');
            else
                title(app.ResidualAxes, 'NON-CONVERGED');
                app.setStatus('Non-converged iterate; balances not satisfied.');
            end

            app.updateSolveLogFromSolver(solver.logLines);
            app.captureResultsSnapshot(nIter, solver.residualHistory(end));
            app.refreshResultsSummaryModel();
            app.refreshResultsTable();
            app.updateStabilityAnalysisTab();
            app.refreshResultsSummaryPanel();
            app.refreshResultsTablesTab();
            app.refreshStreamTables();
        end

        function onSolveFailure(app, ME)
            app.stopSolveTimer();
            app.resultsSummary = struct('status','Solve failed','residual',NaN,'iterations',0, ...
                'streamKey','-','unitKey','-','streamText','-','unitText','-','deltaText','-');
            app.refreshResultsSummaryPanel();
            app.refreshResultsTablesTab();
            title(app.ResidualAxes, 'FAILED');
            logLines = [{'SOLVE FAILED:'; ME.message; ''}; ...
                arrayfun(@(f) sprintf('  %s (line %d)',f.name,f.line), ME.stack,'Uni',false)];
            app.updateSolveLogFromSolver(string(logLines));
            app.writeErrorLog('solve_error', logLines);
            if strcmp(ME.identifier, 'Flowsheet:NonConvergedSolve')
                app.setStatus('Non-converged iterate; balances not satisfied.');
            else
                app.setStatus('Solve failed — see log (saved to output/logs).');
            end
        end

        function updateSolveLogFromSolver(app, lines)
            vals = cellstr(lines);
            stride = max(0, round(app.logEveryN));
            if stride > 0 && ~isempty(vals)
                idx = 1:stride:numel(vals);
                vals = vals(idx);
            end
            app.LogArea.Value = vals;
        end

        function runSolver(app)
            app.syncModelToState();
            app.SolveController.runSolve();
            app.syncStateToModel();
        end


        function updateElapsedClock(app)
            if isempty(app.SolveStartTic), return; end
            elapsed = toc(app.SolveStartTic);
            mins = floor(elapsed / 60);
            secs = floor(mod(elapsed, 60));
            if mins >= 60
                hrs = floor(mins / 60);
                mins = mod(mins, 60);
                app.SolveElapsedLabel.Text = sprintf('Elapsed: %d:%02d:%02d', hrs, mins, secs);
            else
                app.SolveElapsedLabel.Text = sprintf('Elapsed: %02d:%02d', mins, secs);
            end
        end

        function stopSolveTimer(app)
            if ~isempty(app.SolveTimer) && isvalid(app.SolveTimer)
                stop(app.SolveTimer);
                delete(app.SolveTimer);
            end
            app.SolveTimer = [];
        end


        function refreshResultsTable(app)
            app.syncModelToState();
            app.ResultsController.refreshResultsTable();
            app.syncStateToModel();
        end

        function refreshResultsSummaryModel(app)
            app.syncModelToState();
            app.ResultsController.refreshResultsSummaryModel();
            app.syncStateToModel();
        end

        function refreshResultsSummaryPanel(app)
            app.syncModelToState();
            app.ResultsController.refreshResultsSummaryPanel();
            app.syncStateToModel();
        end

        function refreshResultsTablesTab(app)
            app.syncModelToState();
            app.ResultsController.refreshResultsTablesTab();
            app.syncStateToModel();
        end

        function setResultsSummary(app, summary)
            app.resultsSummary = summary;
        end


        function updateStabilityOverlay(app)
            if isempty(app.ResultsAxes) || ~isvalid(app.ResultsAxes)
                return;
            end
            if isempty(app.lastSolver)
                return;
            end

            holdState = ishold(app.ResultsAxes);
            hold(app.ResultsAxes, 'on');
            cleanupObj = onCleanup(@() app.restoreHoldState(app.ResultsAxes, holdState)); %#ok<NASGU>

            try
                st = app.lastSolver.localStabilityProxy();
                poles = st.poles(:);
                if isempty(poles)
                    return;
                end

                yyaxis(app.ResultsAxes, 'right');
                plot(app.ResultsAxes, imag(poles), real(poles), 'x', ...
                    'Color',[0.55 0.15 0.65], 'LineWidth',1.3, ...
                    'DisplayName','Stability poles (local)');
                xline(app.ResultsAxes, 0, ':', 'Color',[0.5 0.5 0.5], 'HandleVisibility','off');
                yline(app.ResultsAxes, 0, ':', 'Color',[0.5 0.5 0.5], 'HandleVisibility','off');
                ylabel(app.ResultsAxes, 'Right axis / Real(pole)');
                xlabel(app.ResultsAxes, 'Configured X variable / Imag(pole)');

                stabText = 'stable';
                if ~st.stable
                    stabText = 'unstable';
                end

                sweepData = app.runStabilitySweepIfRequested();
                if ~isempty(sweepData.values)
                    yyaxis(app.ResultsAxes, 'left');
                    xVals = sweepData.values(:);
                    yVals = sweepData.maxRealPole(:);
                    plot(app.ResultsAxes, xVals, yVals, '-s', 'LineWidth',1.4, ...
                        'Color',[0.85 0.33 0.10], 'MarkerSize',4, ...
                        'DisplayName', sprintf('Max Re(pole) sweep: %s', sweepData.param));
                    yline(app.ResultsAxes, 0, '--', 'Color',[0.85 0.33 0.10], 'HandleVisibility','off');
                    app.stabilitySweepData = sweepData;
                    app.ResultsPlotStatusLabel.Text = sprintf('Local poles: max Re=%.3e (%s). Sweep points: %d.', ...
                        st.maxReal, stabText, numel(sweepData.values));
                else
                    app.ResultsPlotStatusLabel.Text = sprintf('Local poles: max Re=%.3e (%s).', st.maxReal, stabText);
                end
            catch ME
                app.ResultsPlotStatusLabel.Text = sprintf('Stability overlay unavailable: %s', ME.message);
            end
        end

        function sweepData = runStabilitySweepIfRequested(app)
            sweepData = struct('param',[],'values',[],'maxRealPole',[],'stableMask',[],'warnings',strings(0,1));
            if isempty(app.ResultsStabilitySweepParamDD) || strcmp(app.ResultsStabilitySweepParamDD.Value, 'none')
                return;
            end
            if isempty(app.lastFlowsheet)
                return;
            end

            paramChoice = app.ResultsStabilitySweepParamDD.Value;
            vMin = app.ResultsStabilitySweepMinField.Value;
            vMax = app.ResultsStabilitySweepMaxField.Value;
            nPts = round(app.ResultsStabilitySweepPtsField.Value);
            vals = linspace(vMin, vMax, nPts);

            [unitIdx, unitLabel] = app.pickStabilitySweepTarget(paramChoice);
            if isempty(unitIdx)
                sweepData.warnings(end+1) = "No compatible unit for selected stability sweep.";
                return;
            end

            origVal = app.getSensParamValue(paramChoice, unitIdx, unitLabel);
            maxReal = nan(1, nPts);
            stableMask = false(1, nPts);

            for i = 1:nPts
                try
                    app.applySensParam(paramChoice, unitIdx, vals(i), unitLabel);
                    fs = app.buildFlowsheet();
                    solver = fs.solve('maxIter', app.MaxIterField.Value, 'tolAbs', app.TolField.Value, ...
                        'autoScale', true, 'printToConsole', false);
                    st = solver.localStabilityProxy();
                    maxReal(i) = st.maxReal;
                    stableMask(i) = st.stable;
                catch
                    maxReal(i) = NaN;
                    stableMask(i) = false;
                end
            end

            if ~isnan(origVal)
                app.applySensParam(paramChoice, unitIdx, origVal, unitLabel);
            end

            sweepData.param = sprintf('%s @ %s', paramChoice, unitLabel);
            sweepData.values = vals;
            sweepData.maxRealPole = maxReal;
            sweepData.stableMask = stableMask;
        end

        function [unitIdx, unitLabel] = pickStabilitySweepTarget(app, paramChoice)
            unitIdx = [];
            unitLabel = '(none)';
            for i = 1:numel(app.units)
                u = app.units{i};
                if contains(paramChoice, 'conversion') && isprop(u, 'conversion')
                    unitIdx = i;
                elseif contains(paramChoice, 'beta') && isprop(u, 'beta')
                    unitIdx = i;
                elseif contains(paramChoice, 'phi') && isprop(u, 'phi')
                    unitIdx = i;
                else
                    continue;
                end
                unitLabel = sprintf('[%d] %s', i, app.shortTypeName(u));
                return;
            end
        end

        function restoreHoldState(~, ax, holdState)
            if holdState
                hold(ax, 'on');
            else
                hold(ax, 'off');
            end
        end

        function ok = plotResultsConfig(app, idx)
            ok = false;
            cfg = app.resultsConfigControls(idx);
            if isempty(cfg.targetDD.Items)
                return;
            end
            if strcmp(cfg.targetDD.Value,'(none)') && ~strcmp(cfg.xVarDD.Value,'iteration') && ~strcmp(cfg.yVarDD.Value,'residual')
                return;
            end
            x = app.resultsSeriesForConfig(cfg.xVarDD.Value, cfg.targetDD.Value, cfg.compDD.Value);
            y = app.resultsSeriesForConfig(cfg.yVarDD.Value, cfg.targetDD.Value, cfg.compDD.Value);
            if isempty(x) || isempty(y)
                return;
            end
            n = min(numel(x), numel(y));
            x = x(1:n); y = y(1:n);
            mask = isfinite(x) & isfinite(y);
            x = x(mask); y = y(mask);
            if isempty(x)
                return;
            end

            y = app.applyResultsSmoothing(y);
            x = app.applyResultsSmoothing(x);

            if cfg.normCheck.Value || strcmp(app.ResultsNormModeDD.Value, 'normalized')
                y0 = max(abs(y(1)), eps);
                y = y ./ y0;
            end
            y = y .* cfg.scaleField.Value;
            traceColors = {[0.00 0.45 0.74],[0.85 0.33 0.10],[0.47 0.67 0.19],[0.49 0.18 0.56]};
            yyaxis(app.ResultsAxes, cfg.axisDD.Value);
            tgtShort = cfg.targetDD.Value;
            if startsWith(tgtShort,'Stream: '), tgtShort = extractAfter(tgtShort,'Stream: '); end
            if startsWith(tgtShort,'Unit: '), tgtShort = extractAfter(tgtShort,'Unit: '); end
            plot(app.ResultsAxes, x, y, '-', 'LineWidth',1.5, ...
                'Color', traceColors{idx}, ...
                'DisplayName', sprintf('%s @ %s', cfg.yVarDD.Value, tgtShort));
            if strcmp(cfg.axisDD.Value,'left')
                ylabel(app.ResultsAxes, cfg.yVarDD.Value);
            else
                ylabel(app.ResultsAxes, cfg.yVarDD.Value);
            end
            xlabel(app.ResultsAxes, cfg.xVarDD.Value);
            ok = true;
        end

        function s = applyResultsSmoothing(app, s)
            mode = app.ResultsSmoothingDD.Value;
            w = max(1, round(app.ResultsSmoothWindowField.Value));
            if w <= 1 || strcmp(mode,'none') || numel(s) < 3
                return;
            end
            if mod(w,2) == 0
                w = w + 1;
            end
            switch mode
                case 'moving-average'
                    kern = ones(w,1) / w;
                    s = conv(s(:), kern, 'same');
                case 'median'
                    try
                        s = medfilt1(s(:), w, 'truncate');
                    catch
                        s = s(:);
                        hw = floor(w/2);
                        out = s;
                        for i = 1:numel(s)
                            lo = max(1, i-hw);
                            hi = min(numel(s), i+hw);
                            out(i) = median(s(lo:hi));
                        end
                        s = out;
                    end
            end
            s = s(:);
        end

        function s = resultsSeriesForConfig(app, varName, targetName, compIdxStr)
            s = [];
            n = numel(app.resultsSnapshots);
            if n == 0
                return;
            end
            s = nan(n,1);
            compIdx = str2double(compIdxStr);
            for k = 1:n
                snap = app.resultsSnapshots{k};
                s(k) = app.extractSnapshotValue(snap, varName, targetName, compIdx);
            end
            if strcmp(varName,'iteration')
                s = app.resultsSnapshotIters(:);
            elseif strcmp(varName,'residual')
                s = app.resultsSnapshotResiduals(:);
            end
        end

        function val = extractSnapshotValue(app, snap, varName, targetName, compIdx)
            val = NaN;
            if strcmp(varName,'iteration')
                if isfield(snap,'iteration'), val = snap.iteration; end
                return;
            elseif strcmp(varName,'residual')
                if isfield(snap,'residual'), val = snap.residual; end
                return;
            end

            if startsWith(targetName,'Stream: ')
                key = strtrim(extractAfter(targetName,'Stream: '));
                if ~isfield(snap.streams, matlab.lang.makeValidName(key)), return; end
                st = snap.streams.(matlab.lang.makeValidName(key));
                switch varName
                    case 'flow', val = app.fromSI(st.n_dot, 'flow');
                    case 'T', val = app.fromSI(st.T, 'temperature');
                    case 'P', val = app.fromSI(st.P, 'pressure');
                    case 'y(i)'
                        if isfinite(compIdx) && compIdx >= 1 && compIdx <= numel(st.y)
                            val = st.y(compIdx);
                        end
                    case 'conversion_profile'
                        if isfinite(compIdx) && compIdx >= 1 && compIdx <= numel(st.y)
                            val = 1 - st.y(compIdx);
                        end
                end
            elseif startsWith(targetName,'Unit: ')
                key = strtrim(extractAfter(targetName,'Unit: '));
                fn = matlab.lang.makeValidName(key);
                if ~isfield(snap.units, fn), return; end
                uu = snap.units.(fn);
                switch varName
                    case 'conversion', if isfield(uu,'conversion'), val = uu.conversion; end
                    case 'efficiency', if isfield(uu,'eta'), val = uu.eta; end
                    case 'duty', if isfield(uu,'duty'), val = app.fromSI(uu.duty, 'duty'); end
                    case 'power', if isfield(uu,'power'), val = app.fromSI(uu.power, 'power'); end
                    case 'deltaT_hx'
                        if isfield(uu,'deltaT_hx'), val = app.fromSI(uu.deltaT_hx, 'temperature'); end
                    case 'power_specific'
                        if isfield(uu,'powerSpecific'), val = uu.powerSpecific; end
                end
            end
        end

        function captureResultsSnapshot(app, iter, rNorm)
            if isempty(app.lastFlowsheet)
                return;
            end
            snap = struct();
            snap.iteration = iter;
            snap.residual = rNorm;
            snap.streams = struct();
            snap.units = struct();

            for i = 1:numel(app.lastFlowsheet.streamDisplayRefs)
                s = app.lastFlowsheet.streamDisplayRefs{i};
                name = matlab.lang.makeValidName(char(string(app.lastFlowsheet.streamDisplayNames{i})));
                snap.streams.(name) = struct('n_dot',s.n_dot,'T',s.T,'P',s.P,'y',s.y(:).');
            end

            for i = 1:numel(app.lastFlowsheet.units)
                u = app.lastFlowsheet.units{i};
                uname = sprintf('U%d_%s', i, app.shortTypeName(u));
                fn = matlab.lang.makeValidName(uname);
                us = struct();
                if isprop(u,'conversion'), us.conversion = u.conversion; end
                if isprop(u,'eta'), us.eta = u.eta; end
                if ismethod(u,'getDuty')
                    try, us.duty = u.getDuty(); catch, end
                elseif isprop(u,'duty')
                    us.duty = u.duty;
                end
                if ismethod(u,'getPower')
                    try, us.power = u.getPower(); catch, end
                end
                if isa(u, 'proc.units.HeatExchanger')
                    try
                        us.deltaT_hx = u.hotInlet.T - u.coldInlet.T;
                    catch
                    end
                end
                if isa(u, 'proc.units.Compressor')
                    try
                        pw = u.getPower();
                        us.powerSpecific = pw / max(u.inlet.n_dot, eps);
                    catch
                    end
                end
                snap.units.(fn) = us;
            end

            app.resultsSnapshots{end+1} = snap;
            app.resultsSnapshotIters(end+1,1) = iter;
            app.resultsSnapshotResiduals(end+1,1) = rNorm;
        end

        function refreshResultsTargetOptions(app)
            if isempty(app.ResultsConfig1TargetDD)
                return;
            end
            targets = {'(none)'};
            if ~isempty(app.lastFlowsheet)
                for i = 1:numel(app.lastFlowsheet.streamDisplayNames)
                    targets{end+1} = sprintf('Stream: %s', app.lastFlowsheet.streamDisplayNames{i}); %#ok<AGROW>
                end
                for i = 1:numel(app.lastFlowsheet.units)
                    targets{end+1} = sprintf('Unit: U%d_%s', i, app.shortTypeName(app.lastFlowsheet.units{i})); %#ok<AGROW>
                end
            end
            dds = {app.ResultsConfig1TargetDD, app.ResultsConfig2TargetDD, app.ResultsConfig3TargetDD, app.ResultsConfig4TargetDD};
            for i = 1:numel(dds)
                dd = dds{i};
                prev = dd.Value;
                dd.Items = targets;
                if any(strcmp(targets, prev))
                    dd.Value = prev;
                else
                    dd.Value = targets{1};
                end
            end

            nSpec = max(1, numel(app.speciesNames));
            compItems = arrayfun(@num2str, 1:nSpec, 'Uni', false);
            cdds = {app.ResultsConfig1CompDD, app.ResultsConfig2CompDD, app.ResultsConfig3CompDD, app.ResultsConfig4CompDD};
            for i = 1:numel(cdds)
                cdds{i}.Items = compItems;
                if ~any(strcmp(compItems, cdds{i}.Value))
                    cdds{i}.Value = compItems{1};
                end
            end
        end

        function cfg = resultsConfigControls(app, idx)
            if idx == 1
                cfg = struct('xVarDD',app.ResultsConfig1XVarDD,'yVarDD',app.ResultsConfig1YVarDD, ...
                    'targetDD',app.ResultsConfig1TargetDD,'compDD',app.ResultsConfig1CompDD, ...
                    'normCheck',app.ResultsConfig1NormCheck,'scaleField',app.ResultsConfig1ScaleField, ...
                    'axisDD',app.ResultsConfig1AxisDD);
            elseif idx == 2
                cfg = struct('xVarDD',app.ResultsConfig2XVarDD,'yVarDD',app.ResultsConfig2YVarDD, ...
                    'targetDD',app.ResultsConfig2TargetDD,'compDD',app.ResultsConfig2CompDD, ...
                    'normCheck',app.ResultsConfig2NormCheck,'scaleField',app.ResultsConfig2ScaleField, ...
                    'axisDD',app.ResultsConfig2AxisDD);
            elseif idx == 3
                cfg = struct('xVarDD',app.ResultsConfig3XVarDD,'yVarDD',app.ResultsConfig3YVarDD, ...
                    'targetDD',app.ResultsConfig3TargetDD,'compDD',app.ResultsConfig3CompDD, ...
                    'normCheck',app.ResultsConfig3NormCheck,'scaleField',app.ResultsConfig3ScaleField, ...
                    'axisDD',app.ResultsConfig3AxisDD);
            else
                cfg = struct('xVarDD',app.ResultsConfig4XVarDD,'yVarDD',app.ResultsConfig4YVarDD, ...
                    'targetDD',app.ResultsConfig4TargetDD,'compDD',app.ResultsConfig4CompDD, ...
                    'normCheck',app.ResultsConfig4NormCheck,'scaleField',app.ResultsConfig4ScaleField, ...
                    'axisDD',app.ResultsConfig4AxisDD);
            end
        end

        function applyResultsPreset(app)
            % Find first available stream and unit targets
            app.refreshResultsTargetOptions();
            targets = app.ResultsConfig1TargetDD.Items;
            firstStream = '(none)';
            firstUnit = '(none)';
            for i = 1:numel(targets)
                if startsWith(targets{i}, 'Stream: ') && strcmp(firstStream,'(none)')
                    firstStream = targets{i};
                end
                if startsWith(targets{i}, 'Unit: ') && strcmp(firstUnit,'(none)')
                    firstUnit = targets{i};
                end
            end

            switch app.ResultsPresetDD.Value
                case 'convergence'
                    app.setResultsTrace(1, 'iteration','residual','left',1,false,'1','(none)');
                    app.setResultsTrace(2, 'iteration','flow','right',1,true,'1',firstStream);
                    app.setResultsTrace(3, 'iteration','T','left',1,false,'1',firstStream);
                    app.setResultsTrace(4, 'iteration','P','right',1,false,'1',firstStream);
                    app.ResultsSmoothingDD.Value = 'none';
                    app.ResultsSmoothWindowField.Value = 3;
                    app.ResultsYScaleDropDown.Value = 'log';
                case 'stream profiles'
                    app.setResultsTrace(1, 'iteration','flow','left',1,false,'1',firstStream);
                    app.setResultsTrace(2, 'iteration','T','right',1,false,'1',firstStream);
                    app.setResultsTrace(3, 'iteration','P','left',1,false,'1',firstStream);
                    app.setResultsTrace(4, 'iteration','y(i)','right',1,false,'1',firstStream);
                    app.ResultsSmoothingDD.Value = 'none';
                    app.ResultsSmoothWindowField.Value = 3;
                    app.ResultsYScaleDropDown.Value = 'linear';
                case 'unit performance'
                    app.setResultsTrace(1, 'iteration','duty','left',1,false,'1',firstUnit);
                    app.setResultsTrace(2, 'iteration','power','right',1,false,'1',firstUnit);
                    app.setResultsTrace(3, 'iteration','conversion','left',1,false,'1',firstUnit);
                    app.setResultsTrace(4, 'iteration','efficiency','right',1,false,'1',firstUnit);
                    app.ResultsSmoothingDD.Value = 'none';
                    app.ResultsSmoothWindowField.Value = 3;
                    app.ResultsYScaleDropDown.Value = 'linear';
            end
            app.autofillResultTargets();
            app.refreshResultsTable();
        end

        function setResultsTrace(app, idx, xVar, yVar, axisName, scaleVal, normVal, compVal, targetVal)
            cfg = app.resultsConfigControls(idx);
            cfg.xVarDD.Value = xVar;
            cfg.yVarDD.Value = yVar;
            cfg.axisDD.Value = axisName;
            cfg.scaleField.Value = scaleVal;
            cfg.normCheck.Value = normVal;
            if any(strcmp(cfg.compDD.Items, compVal))
                cfg.compDD.Value = compVal;
            end
            if any(strcmp(cfg.targetDD.Items, targetVal))
                cfg.targetDD.Value = targetVal;
            else
                cfg.targetDD.Value = '(none)';
            end
        end

        function autofillResultTargets(app)
            targets = app.ResultsConfig1TargetDD.Items;
            if isempty(targets)
                return;
            end
            streamTargets = targets(startsWith(targets, 'Stream: '));
            unitTargets = targets(startsWith(targets, 'Unit: '));
            for idx = 1:4
                cfg = app.resultsConfigControls(idx);
                if startsWith(cfg.yVarDD.Value, 'conversion') || strcmp(cfg.yVarDD.Value,'duty') || strcmp(cfg.yVarDD.Value,'power') || ...
                        strcmp(cfg.yVarDD.Value,'deltaT_hx') || strcmp(cfg.yVarDD.Value,'power_specific') || strcmp(cfg.yVarDD.Value,'efficiency')
                    if ~isempty(unitTargets)
                        cfg.targetDD.Value = unitTargets{1};
                    end
                elseif ~strcmp(cfg.yVarDD.Value,'residual') && ~strcmp(cfg.yVarDD.Value,'iteration')
                    if ~isempty(streamTargets)
                        cfg.targetDD.Value = streamTargets{1};
                    end
                end
            end
        end

        function exportResultsSummaryCsv(app)
            ui.ResultsExporter.exportSummaryCsv(app.resultsSummary, app.projectTitle);
            app.setStatus('Results summary CSV exported.');
        end

        function exportResultsSnapshotsCsv(app)
            if isempty(app.resultsSnapshots)
                uialert(app.Fig,'No snapshots available. Run solve first.','No snapshot data');
                return;
            end
            n = numel(app.resultsSnapshots);
            residual = app.resultsSnapshotResiduals(:);
            iter = app.resultsSnapshotIters(:);
            status = repmat(string(app.resultsSummary.status), n, 1);
            T = table(iter, residual, status, 'VariableNames', {'iteration','residual','solve_status'});
            outDir = app.resolveInitialExportPath();
            filepath = fullfile(outDir, app.autoFileName('results_snapshots', 'csv'));
            writetable(T, filepath);
            app.setStatus(sprintf('Snapshot history exported to %s', filepath));
            app.appendResultsExportLog(sprintf('Snapshot history exported: %s', filepath));
        end

        function exportResultsTracesCsv(app)
            traces = {};
            rows = 0;
            for idxCfg = 1:4
                cfg = app.resultsConfigControls(idxCfg);
                x = app.resultsSeriesForConfig(cfg.xVarDD.Value, cfg.targetDD.Value, cfg.compDD.Value);
                y = app.resultsSeriesForConfig(cfg.yVarDD.Value, cfg.targetDD.Value, cfg.compDD.Value);
                n = min(numel(x), numel(y));
                if n == 0
                    continue;
                end
                x = x(1:n);
                y = y(1:n);
                name = repmat(string(sprintf('plot_%d', idxCfg)), n, 1);
                tx = repmat(string(cfg.xVarDD.Value), n, 1);
                ty = repmat(string(cfg.yVarDD.Value), n, 1);
                tgt = repmat(string(cfg.targetDD.Value), n, 1);
                comp = repmat(string(cfg.compDD.Value), n, 1);
                axisName = repmat(string(cfg.axisDD.Value), n, 1);
                part = table(name, tx, ty, tgt, comp, axisName, x(:), y(:), ...
                    'VariableNames', {'trace_name','x_var','y_var','target','component','axis','x','y'});
                traces{end+1} = part; %#ok<AGROW>
                rows = rows + n;
            end
            if rows == 0
                uialert(app.Fig,'No trace data available for CSV export.','No trace data');
                return;
            end
            T = vertcat(traces{:});
            outDir = app.resolveInitialExportPath();
            filepath = fullfile(outDir, app.autoFileName('results_traces', 'csv'));
            writetable(T, filepath);
            app.setStatus(sprintf('Results traces exported to %s', filepath));
            app.appendResultsExportLog(sprintf('Results traces exported: %s', filepath));
        end

        function exportResultsStreamCsv(app)
            T = app.buildDisplayStreamTable();
            outDir = app.resolveInitialExportPath();
            filepath = fullfile(outDir, app.autoFileName('stream_table', 'csv'));
            writetable(T, filepath);
            app.setStatus(sprintf('Stream table exported to %s', filepath));
            app.appendResultsExportLog(sprintf('Stream table exported: %s', filepath));
        end

        function exportResultsUnitCsv(app)
            app.exportUnitTableToOutput('csv');
            app.appendResultsExportLog('Unit table CSV export requested (see status/output folder).');
        end

        function updateStabilityAnalysisTab(app)
            if isempty(app.lastSolver)
                if ~isempty(app.ResultsStabilityStatusLabel) && isvalid(app.ResultsStabilityStatusLabel)
                    app.ResultsStabilityStatusLabel.Text = 'No solve available. Run solver first.';
                end
                return;
            end
            try
                st = app.lastSolver.localStabilityProxy();
                A = st.A;
                n = size(A,1);
                poles = st.poles;

                % --- Nyquist via Characteristic Loci (Generalised Nyquist) ---
                % Laplace transform of the linearised system dx/dt = Ax gives
                % the resolvent L(s) = (sI - A)^{-1}.  The generalised
                % Nyquist criterion plots the eigenvalues of L(jw) as w
                % sweeps from -inf to +inf.  Encirclements of the origin by
                % any locus indicate instability.
                nW = 400;
                w = logspace(-4, 4, nW);
                I_n = eye(n);
                % nLoci x nW matrix of characteristic loci
                lociEig = nan(n, nW);
                for k = 1:nW
                    Ljw = (1i*w(k)*I_n - A) \ I_n;
                    lociEig(:,k) = eig(Ljw);
                end
                % Sort loci for continuity: at each freq step, match
                % eigenvalues to previous step by nearest distance
                for k = 2:nW
                    prev = lociEig(:,k-1);
                    curr = lociEig(:,k);
                    used = false(n,1);
                    order = zeros(n,1);
                    for j = 1:n
                        dists = abs(curr - prev(j));
                        dists(used) = inf;
                        [~, best] = min(dists);
                        order(j) = best;
                        used(best) = true;
                    end
                    lociEig(:,k) = curr(order);
                end

                % --- Left plot: Nyquist characteristic loci ---
                if ~isempty(app.ResultsNyquistAxes) && isvalid(app.ResultsNyquistAxes)
                    cla(app.ResultsNyquistAxes, 'reset');
                    hold(app.ResultsNyquistAxes,'on');
                    colors = lines(min(n, 12));
                    nShow = min(n, 12);  % cap visible loci for readability
                    for j = 1:nShow
                        lj = lociEig(j,:);
                        % positive frequency
                        plot(app.ResultsNyquistAxes, real(lj), imag(lj), ...
                            '-', 'LineWidth',1.4, 'Color',colors(j,:), ...
                            'DisplayName', sprintf('\\lambda_{%d}(+\\omega)', j));
                        % negative frequency (conjugate mirror)
                        plot(app.ResultsNyquistAxes, real(lj), -imag(lj), ...
                            '--', 'LineWidth',1.0, 'Color',colors(j,:), ...
                            'HandleVisibility','off');
                    end
                    % Critical point and origin
                    plot(app.ResultsNyquistAxes, 0, 0, 'ko', 'MarkerSize',7, 'LineWidth',1.5, 'DisplayName','Origin');
                    plot(app.ResultsNyquistAxes, -1, 0, 'rx', 'MarkerSize',9, 'LineWidth',1.8, 'DisplayName','-1+0j');
                    % Unit circle for reference
                    th = linspace(0,2*pi,100);
                    plot(app.ResultsNyquistAxes, cos(th), sin(th), ':', 'Color',[0.7 0.7 0.7], 'DisplayName','Unit circle');
                    grid(app.ResultsNyquistAxes,'on');
                    xlabel(app.ResultsNyquistAxes,'Re(\lambda)');
                    ylabel(app.ResultsNyquistAxes,'Im(\lambda)');
                    stableTxt = app.ternary(st.stable, 'STABLE', 'UNSTABLE');
                    title(app.ResultsNyquistAxes, sprintf('Generalised Nyquist | %s | max Re(pole)=%.3e', stableTxt, st.maxReal));
                    hold(app.ResultsNyquistAxes,'off');
                end

                % --- Right plot: Pole map (and sweep if configured) ---
                sweepData = app.runStabilitySweepIfRequested();
                if ~isempty(app.ResultsStabilitySweepAxes) && isvalid(app.ResultsStabilitySweepAxes)
                    cla(app.ResultsStabilitySweepAxes, 'reset');
                    hold(app.ResultsStabilitySweepAxes,'on');

                    if ~isempty(sweepData.values)
                        % Stability sweep mode: max Re(pole) vs parameter
                        plot(app.ResultsStabilitySweepAxes, sweepData.values, sweepData.maxRealPole, '-o', ...
                            'LineWidth',1.4, 'Color',[0.85 0.33 0.10], 'MarkerSize',5, ...
                            'DisplayName','max Re(pole)');
                        yline(app.ResultsStabilitySweepAxes, 0, '--r', 'LineWidth',1.0, 'DisplayName','Stability boundary');
                        xlabel(app.ResultsStabilitySweepAxes, sprintf('Sweep: %s', sweepData.param));
                        ylabel(app.ResultsStabilitySweepAxes, 'max Re(pole)');
                        nUnstable = sum(sweepData.maxRealPole >= 0);
                        title(app.ResultsStabilitySweepAxes, sprintf('Stability Sweep -- %d/%d pts unstable', nUnstable, numel(sweepData.values)));
                        legend(app.ResultsStabilitySweepAxes,'Location','best','FontSize',9);
                    else
                        % Pole map of current operating point
                        stableIdx = real(poles) < 0;
                        if any(stableIdx)
                            plot(app.ResultsStabilitySweepAxes, real(poles(stableIdx)), imag(poles(stableIdx)), ...
                                'bx', 'MarkerSize',8, 'LineWidth',1.5, 'DisplayName',sprintf('Stable poles (Re<0) [%d]', sum(stableIdx)));
                        end
                        if any(~stableIdx)
                            plot(app.ResultsStabilitySweepAxes, real(poles(~stableIdx)), imag(poles(~stableIdx)), ...
                                'rx', 'MarkerSize',10, 'LineWidth',2.0, 'DisplayName',sprintf('Unstable poles (Re>=0) [%d]', sum(~stableIdx)));
                        end
                        xline(app.ResultsStabilitySweepAxes, 0, '--', 'Color',[0.5 0.5 0.5], 'DisplayName','Imaginary axis (stability boundary)');
                        yline(app.ResultsStabilitySweepAxes, 0, '--', 'Color',[0.5 0.5 0.5], 'HandleVisibility','off');
                        xlabel(app.ResultsStabilitySweepAxes, 'Re(pole)');
                        ylabel(app.ResultsStabilitySweepAxes, 'Im(pole)');
                        title(app.ResultsStabilitySweepAxes, sprintf('Pole Map (%d poles, %d stable)', n, sum(stableIdx)));
                        legend(app.ResultsStabilitySweepAxes,'Location','best','FontSize',9);
                    end
                    grid(app.ResultsStabilitySweepAxes,'on');
                    hold(app.ResultsStabilitySweepAxes,'off');
                end

                app.stabilitySweepData = sweepData;
                stableTxt = app.ternary(st.stable, 'stable', 'unstable');
                nStable = sum(real(poles) < 0);
                statusParts = {sprintf('System is %s (max Re=%.3e). %d/%d poles stable.', stableTxt, st.maxReal, nStable, n)};
                if ~isempty(sweepData.values)
                    statusParts{end+1} = sprintf(' Sweep: %d pts.', numel(sweepData.values));
                end
                if ~isempty(app.ResultsStabilityStatusLabel) && isvalid(app.ResultsStabilityStatusLabel)
                    app.ResultsStabilityStatusLabel.Text = strjoin(statusParts, '');
                end
            catch ME
                if ~isempty(app.ResultsStabilityStatusLabel) && isvalid(app.ResultsStabilityStatusLabel)
                    app.ResultsStabilityStatusLabel.Text = sprintf('Stability analysis failed: %s', ME.message);
                end
            end
        end

        function txt = ternary(~, cond, a, b) %#ok<INUSL>
            txt = ui.AppUtils.ternary(cond, a, b);
        end

        function appendResultsExportLog(~, ~)
            % No-op: export log area removed during UI cleanup
        end

        function exportResultsBundleCsv(app)
            try
                app.exportResultsSummaryCsv();
                app.exportResultsTracesCsv();
                app.exportResultsSnapshotsCsv();
                app.exportResultsStreamCsv();
                app.exportResultsUnitCsv();
                app.appendResultsExportLog('Full CSV bundle exported successfully.');
            catch ME
                app.appendResultsExportLog(sprintf('Bundle export failed: %s', ME.message));
            end
        end

        function resetResultsView(app)
            app.ResultsPresetDD.Value = 'custom';
            app.ResultsNormModeDD.Value = 'absolute';
            app.ResultsLegendDD.Value = 'best';
            app.ResultsSmoothingDD.Value = 'none';
            app.ResultsSmoothWindowField.Value = 3;
            app.ResultsXScaleDropDown.Value = 'linear';
            app.ResultsYScaleDropDown.Value = 'linear';
            app.setResultsTrace(1, 'iteration','flow','left',1,false,'1','(none)');
            app.setResultsTrace(2, 'iteration','T','right',1,false,'1','(none)');
            app.setResultsTrace(3, 'iteration','residual','left',1,false,'1','(none)');
            app.setResultsTrace(4, 'iteration','power','right',1,false,'1','(none)');
            app.refreshResultsTable();
            app.stabilitySweepData = struct('param',[],'values',[],'maxRealPole',[],'stableMask',[],'warnings',strings(0,1));
        end

        function clearResultsChart(app)
            if isempty(app.ResultsAxes) || ~isvalid(app.ResultsAxes)
                return;
            end
            cla(app.ResultsAxes, 'reset');
            grid(app.ResultsAxes,'on');
            xlabel(app.ResultsAxes,'Iteration');
            ylabel(app.ResultsAxes,'Value');
            title(app.ResultsAxes,'Solve to see iteration trends');
            legend(app.ResultsAxes,'off');
            app.ResultsPlotStatusLabel.Text = 'Chart cleared. Configure traces and solve to plot.';
        end

        function exportResultsFigure(app)
            ui.ResultsExporter.exportFigure(app.ResultsAxes, app.projectTitle);
            app.setStatus('Results plot exported.');
        end

    end


    % =====================================================================
    %  DEBUG TOOLS POPUP  (delegated to ui.DebugController)
    % =====================================================================
    methods (Access = private)
        function openDebugPopup(app)
            if isempty(app.debugCtrl)
                app.debugCtrl = ui.DebugController( ...
                    @() app.lastSolver, ...
                    @() app.buildFlowsheet(), ...
                    @() app.openUnitTablePopup());
            end
            app.debugCtrl.openPopup();
        end

        function appendDebugLog(app, msg)
            if ~isempty(app.debugCtrl)
                app.debugCtrl.appendLog(msg);
            end
        end

        function s = getDebugSettings(app)
            if ~isempty(app.debugCtrl)
                s = app.debugCtrl.getSettings();
            else
                s = app.debugSettings;
            end
        end
    end

    % =====================================================================
    %  UNIT TABLE POPUP
    % =====================================================================
    methods (Access = private)
        function openUnitTablePopup(app)
            if isempty(app.unitTablePopupCtrl)
                deps = struct( ...
                    'getLastSolver', @() app.lastSolver, ...
                    'getLastFlowsheet', @() app.lastFlowsheet, ...
                    'getUnits', @() app.units, ...
                    'getUnitDefs', @() app.unitDefs, ...
                    'getSpeciesNames', @() app.speciesNames, ...
                    'getUnitPrefs', @() app.unitPrefs, ...
                    'getProjectTitle', @() app.projectTitle, ...
                    'setStatusFcn', @(msg) app.setStatus(msg), ...
                    'refreshStreamTablePopupFcn', @() app.refreshStreamTablePopup(), ...
                    'refreshResultsTablesTabFcn', @() app.refreshResultsTablesTab());
                app.unitTablePopupCtrl = ui.UnitTablePopup(deps);
            end
            app.unitTablePopupCtrl.open();
        end

        function refreshUnitTablePopup(app)
            if ~isempty(app.unitTablePopupCtrl)
                app.unitTablePopupCtrl.refresh();
            end
        end

        function T = buildUnitResultsTable(app)
            if ~isempty(app.unitTablePopupCtrl)
                T = app.unitTablePopupCtrl.buildResultsTable();
            elseif ~isempty(app.lastFlowsheet) && isprop(app.lastFlowsheet, 'units')
                T = ui.UnitTablePopup.buildTableFromObjects(app.lastFlowsheet.units, app.unitPrefs);
            elseif ~isempty(app.units)
                T = ui.UnitTablePopup.buildTableFromObjects(app.units, app.unitPrefs);
            else
                T = ui.UnitTablePopup.buildTableFromDefs(app.unitDefs, app.unitPrefs);
            end
        end

        function exportUnitTableToOutput(app, fmt)
            if isempty(app.unitTablePopupCtrl)
                app.openUnitTablePopup();
            end
            app.unitTablePopupCtrl.exportToOutput(fmt);
        end

        function txt = formatSpecValue(~, val)
            txt = ui.AppUtils.formatSpecValue(val);
        end

        function valOut = toSI(app, valIn, quantity)
            valOut = ui.UnitConverter.toSI(valIn, quantity, app.unitPrefs);
        end

        function valOut = fromSI(app, valIn, quantity)
            valOut = ui.UnitConverter.fromSI(valIn, quantity, app.unitPrefs);
        end

        function txt = unitLabel(app, quantity, base)
            txt = ui.UnitConverter.unitLabel(quantity, base, app.unitPrefs);
        end

        function T = convertDisplayStreamTable(app, T)
            T = ui.UnitConverter.convertDisplayStreamTable(T, app.unitPrefs);
        end

        function names = displayColumnNames(app, names)
            names = ui.UnitConverter.displayColumnNames(names, app.unitPrefs);
        end

        function onUnitPrefsChanged(app, key, value)
            app.unitPrefs.(key) = char(string(value));
            app.refreshStreamTables();
            app.refreshResultsTable();
            app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
        end

        function prefs = mergeUnitPrefs(~, inPrefs)
            prefs = ui.UnitConverter.mergeUnitPrefs(inPrefs);
        end

        function applyUnitPrefsToControls(app)
            if ~isempty(app.FlowUnitDropDown), app.FlowUnitDropDown.Value = app.unitPrefs.flow; end
            if ~isempty(app.TempUnitDropDown), app.TempUnitDropDown.Value = app.unitPrefs.temperature; end
            if ~isempty(app.PressureUnitDropDown), app.PressureUnitDropDown.Value = app.unitPrefs.pressure; end
            if ~isempty(app.DutyUnitDropDown), app.DutyUnitDropDown.Value = app.unitPrefs.duty; end
            if ~isempty(app.PowerUnitDropDown), app.PowerUnitDropDown.Value = app.unitPrefs.power; end
        end

        function openStreamTablePopup(app)
            if isempty(app.streamTablePopupCtrl)
                deps = struct( ...
                    'getLastFlowsheet', @() app.lastFlowsheet, ...
                    'getStreams', @() app.streams, ...
                    'getSpeciesNames', @() app.speciesNames, ...
                    'getUnitPrefs', @() app.unitPrefs, ...
                    'getProjectTitle', @() app.projectTitle, ...
                    'setStatusFcn', @(msg) app.setStatus(msg), ...
                    'lastExportPath', app.lastExportPath);
                app.streamTablePopupCtrl = ui.StreamTablePopup(deps);
            end
            app.streamTablePopupCtrl.open();
        end

        function refreshStreamTablePopup(app)
            if ~isempty(app.streamTablePopupCtrl)
                app.streamTablePopupCtrl.refresh();
            end
        end

        function T = buildDisplayStreamTable(app)
            if ~isempty(app.streamTablePopupCtrl)
                T = app.streamTablePopupCtrl.buildDisplayTable();
            else
                if ~isempty(app.lastFlowsheet)
                    T = app.lastFlowsheet.streamTable();
                else
                    fsTmp = proc.Flowsheet(app.speciesNames);
                    for i = 1:numel(app.streams)
                        s = app.streams{i};
                        fsTmp.addStream(s, char(string(s.name)));
                    end
                    T = fsTmp.streamTable();
                end
                T = ui.UnitConverter.convertDisplayStreamTable(T, app.unitPrefs);
                T.Properties.VariableNames = ui.UnitConverter.displayColumnNames(T.Properties.VariableNames, app.unitPrefs);
            end
        end

        function pathOut = resolveInitialExportPath(app)
            pathOut = strtrim(char(string(app.lastExportPath)));
            if isempty(pathOut) || ~isfolder(pathOut)
                pathOut = app.ensureOutputDir('results');
                app.lastExportPath = pathOut;
            end
        end

    end

    % =====================================================================
    %  SAVE / LOAD CONFIG
    % =====================================================================
    methods (Access = private)


        function dialogSplitter(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogSplitter(sNames, editIdx);
            app.syncStateToModel();
        end


        function dialogSource(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogSource(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogSink(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogSink(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogDesignSpec(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogDesignSpec(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogAdjust(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogAdjust(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogCalculator(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogCalculator(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogConstraint(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogConstraint(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogRecycle(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogRecycle(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogBypass(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogBypass(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogManifold(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            app.syncModelToState();
            app.UnitsController.dialogManifold(sNames, editIdx);
            app.syncStateToModel();
        end

        function saveConfigDialog(app)
            [file, path] = uiputfile('*.mat', 'Save Config', 'mathlab_config.mat');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            try
                app.syncStreamsFromTable();
                app.saveConfig(filepath);
                app.setStatus(sprintf('Config save succeeded: %s', filepath));
            catch ME
                app.setStatus(sprintf('Config save failed: %s', filepath));
                uialert(app.Fig, sprintf('Failed to save config to:\n%s\n\n%s', filepath, ME.message), ...
                    'Save Config Failed', 'Icon', 'error');
            end
        end

        function saveConfigToOutput(app)
            filepath = '';
            try
                app.syncStreamsFromTable();
                outDir = app.ensureOutputDir('saves');
                fname = app.autoFileName('config', 'mat');
                filepath = fullfile(outDir, fname);
                app.saveConfig(filepath);
                app.setStatus(sprintf('Config save succeeded: %s', filepath));
            catch ME
                if isempty(filepath)
                    filepath = fullfile(pwd, 'output', 'saves');
                end
                app.setStatus(sprintf('Config save failed: %s', filepath));
                uialert(app.Fig, sprintf('Failed to save config to:\n%s\n\n%s', filepath, ME.message), ...
                    'Save Config Failed', 'Icon', 'error');
            end
        end

        function saveResultsToOutput(app)
            if isempty(app.lastSolver)
                uialert(app.Fig,'No solver results yet. Run the solver first.','No Results');
                return;
            end
            outDir = app.resolveInitialExportPath();
            fname = app.autoFileName('results', 'mat');
            filepath = fullfile(outDir, fname);
            app.lastExportPath = outDir;
            solverData = app.lastSolver; %#ok
            if ~isempty(app.lastFlowsheet)
                streamTable = app.lastFlowsheet.streamTable(); %#ok
                save(filepath, 'solverData', 'streamTable');
            else
                save(filepath, 'solverData');
            end
            app.setStatus(sprintf('Results saved to %s', filepath));
        end

        function onProjectTitleChanged(app, src)
            app.projectTitle = strtrim(src.Value);
            if isempty(app.projectTitle)
                app.projectTitle = 'MathLab_Project';
                src.Value = app.projectTitle;
            end
        end

        function onLogEveryNChanged(app, src)
            val = max(0, round(src.Value));
            app.logEveryN = val;
            src.Value = val;
        end

        function loadConfigDialog(app)
            [file, path] = uigetfile('*.mat', 'Load Config');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            app.loadConfig(filepath);
            app.setStatus(sprintf('Config loaded from %s', filepath));
        end

        function saveConfig(app, filepath)
            cfg = app.buildValidatedConfigPayload();
            ui.ConfigManager.saveConfig(filepath, cfg);
        end

        function loadConfig(app, filepath)
            cfg = load(filepath);

            % Restore species
            app.speciesNames = cfg.speciesNames;
            app.speciesMW    = cfg.speciesMW;
            app.refreshSpeciesTable();

            % Restore streams
            app.streams = {};
            for i = 1:numel(cfg.streams)
                sd = cfg.streams(i);
                s = proc.Stream(string(sd.name), app.speciesNames);
                s.n_dot = sd.n_dot;
                s.T     = sd.T;
                s.P     = sd.P;
                s.y     = sd.y;
                s.known.n_dot = sd.known_n_dot;
                s.known.T     = sd.known_T;
                s.known.P     = sd.known_P;
                s.known.y     = sd.known_y;
                app.streams{end+1} = s;
            end

            % Restore units from definitions
            app.units = {};
            app.unitDefs = {};
            skippedUnits = strings(0,1);
            if isfield(cfg, 'unitDefs') && ~isempty(cfg.unitDefs)
                for i = 1:numel(cfg.unitDefs)
                    def = cfg.unitDefs{i};
                    u = app.buildUnitFromDef(def);
                    if ~isempty(u)
                        app.units{end+1} = u;
                        app.unitDefs{end+1} = def;
                    else
                        dType = "<unknown>";
                        if isstruct(def) && isfield(def,'type')
                            dType = string(def.type);
                        end
                        skippedUnits(end+1,1) = sprintf('#%d %s', i, dType); %#ok<AGROW>
                    end
                end
            end

            if ~isempty(skippedUnits)
                warnMsg = sprintf('Loaded %d/%d units. Skipped unit defs: %s', ...
                    numel(app.units), numel(cfg.unitDefs), strjoin(cellstr(skippedUnits), ', '));
                warning('%s', warnMsg);
                app.setStatus(warnMsg);
            end

            % Restore solver settings
            if isfield(cfg,'maxIter'), app.MaxIterField.Value = cfg.maxIter; end
            if isfield(cfg,'tolAbs'),  app.TolField.Value = cfg.tolAbs; end

            % Restore project title
            if isfield(cfg,'projectTitle')
                app.projectTitle = cfg.projectTitle;
                app.ProjectTitleField.Value = cfg.projectTitle;
            end

            if isfield(cfg,'unitPrefs') && isstruct(cfg.unitPrefs)
                app.unitPrefs = app.mergeUnitPrefs(cfg.unitPrefs);
            end
            if isfield(cfg,'lastExportPath')
                app.lastExportPath = char(string(cfg.lastExportPath));
            end
            if isfield(cfg,'logEveryN')
                app.logEveryN = max(0, round(cfg.logEveryN));
                if ~isempty(app.LogEveryNField) && isvalid(app.LogEveryNField)
                    app.LogEveryNField.Value = app.logEveryN;
                end
            end
            app.applyUnitPrefsToControls();

            app.refreshStreamTables();
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
            app.updateSensDropdowns();
            app.refreshSpeciesPropsTable();

            % Auto-suggest next stream name
            if ~isempty(app.streams)
                lastName = char(string(app.streams{end}.name));
                tok = regexp(lastName,'^([A-Za-z_]*)(\d+)$','tokens');
                if ~isempty(tok)
                    app.StreamNameField.Value = sprintf('%s%d',tok{1}{1},str2double(tok{1}{2})+1);
                end
            end
        end

        function u = buildUnitFromDef(app, def, varargin)
            u = proc.UnitFactory.buildUnitFromDef(def, app.streams, app.units, app.speciesNames, varargin{:});
        end

        function generateScript(~, filepath, cfg)
            ui.ConfigManager.generateScript(filepath, cfg);
        end

    end

    % =====================================================================
    %  SENSITIVITY
    % =====================================================================
    methods (Access = private)

        function updateSensDropdowns(app)
            % --- Output stream / field dropdowns ---
            sNames = app.getStreamNames();
            if isempty(sNames), sNames = {'(none)'}; end
            app.SensOutputStreamDD.Items = sNames;

            flds = {'n_dot','T','P'};
            for j = 1:numel(app.speciesNames)
                flds{end+1} = sprintf('y(%d) [%s]', j, app.speciesNames{j}); %#ok
            end
            app.SensOutputFieldDD.Items = flds;

            % --- Sweep parameter dropdown: auto-discover from units + streams ---
            paramItems = {};

            % Discover unit parameters
            for i = 1:numel(app.units)
                u = app.units{i};
                uLabel = sprintf('[%d] %s', i, app.shortTypeName(u));
                paramMap = app.discoverUnitParams(u);
                keys = paramMap.keys;
                for k = 1:numel(keys)
                    paramItems{end+1} = sprintf('Unit %s . %s', uLabel, keys{k}); %#ok
                end
            end

            % Discover stream parameters
            for i = 1:numel(sNames)
                paramItems{end+1} = sprintf('Stream %s . n_dot', sNames{i}); %#ok
                paramItems{end+1} = sprintf('Stream %s . T', sNames{i}); %#ok
                paramItems{end+1} = sprintf('Stream %s . P', sNames{i}); %#ok
                for j = 1:numel(app.speciesNames)
                    paramItems{end+1} = sprintf('Stream %s . y(%d) [%s]', sNames{i}, j, app.speciesNames{j}); %#ok
                end
            end

            if isempty(paramItems)
                paramItems = {'(add units or streams first)'};
            end
            app.SensParamDropDown.Items = paramItems;
        end

        function paramMap = discoverUnitParams(~, u)
            % Returns a containers.Map of sweepable parameter names -> current values
            % for a given unit object. Only numeric scalar/vector properties are included.
            paramMap = containers.Map('KeyType','char','ValueType','any');
            cn = class(u);

            % Common numeric properties to check for each unit type
            candidates = {};
            if contains(cn,'Reactor') || contains(cn,'ConversionReactor') || contains(cn,'YieldReactor')
                candidates = [candidates, {'conversion'}];
            end
            if contains(cn,'StoichiometricReactor')
                candidates = [candidates, {'extent'}];
            end
            if contains(cn,'EquilibriumReactor')
                candidates = [candidates, {'Keq'}];
            end
            if contains(cn,'Purge')
                candidates = [candidates, {'beta'}];
            end
            if contains(cn,'Separator')
                candidates = [candidates, {'phi'}];
            end
            if contains(cn,'Splitter')
                candidates = [candidates, {'splitFractions'}];
            end
            if contains(cn,'Bypass')
                candidates = [candidates, {'bypassFraction'}];
            end
            if contains(cn,'Heater') || contains(cn,'Cooler')
                candidates = [candidates, {'Tout','duty','dP','Pout','PR'}];
            end
            if contains(cn,'HeatExchanger')
                candidates = [candidates, {'Th_out','Tc_out','duty'}];
            end
            if contains(cn,'Compressor') || contains(cn,'Turbine')
                candidates = [candidates, {'Pout','PR','eta'}];
            end

            for k = 1:numel(candidates)
                fld = candidates{k};
                if isprop(u, fld)
                    try
                        val = u.(fld);
                        if isnumeric(val) && ~isempty(val)
                            if isscalar(val)
                                paramMap(fld) = val;
                            else
                                % For vectors (like phi, splitFractions), add each element
                                for idx = 1:numel(val)
                                    paramMap(sprintf('%s(%d)', fld, idx)) = val(idx);
                                end
                            end
                        end
                    catch
                    end
                end
            end
        end

        function onSensParamChanged(app)
            app.validateSensSelection();
        end

        function validateSensSelection(app)
            choice = app.SensParamDropDown.Value;
            if contains(choice, '(') && contains(choice, 'first)')
                app.SensRunBtn.Enable = 'off';
                app.SensStatusLabel.Text = 'Add units or streams, then refresh.';
                return;
            end
            app.SensRunBtn.Enable = 'on';
            app.SensStatusLabel.Text = '';
        end

        function runSensitivity(app)
            app.syncModelToState();
            app.SensitivityController.onRunSensitivity();
            app.syncStateToModel();
        end

        function applySensParam(app, paramChoice, varargin)
            if numel(varargin) == 1
                val = varargin{1};
                app.syncModelToState();
                app.SensitivityController.applySensParam(paramChoice, val);
                app.syncStateToModel();
                return;
            end

            unitIdx = varargin{1};
            val = varargin{2};
            if isempty(unitIdx) || unitIdx < 1 || unitIdx > numel(app.units)
                return;
            end
            u = app.units{unitIdx};
            if contains(paramChoice, 'conversion') && isprop(u, 'conversion')
                u.conversion = val;
            elseif contains(paramChoice, 'beta') && isprop(u, 'beta')
                u.beta = val;
            elseif contains(paramChoice, 'phi') && isprop(u, 'phi')
                phi = u.phi;
                if ~isempty(phi)
                    phi(:) = val;
                    u.phi = phi;
                end
            end
        end

        function val = getSensParamValue(app, paramChoice, varargin)
            if isempty(varargin)
                app.syncModelToState();
                val = app.SensitivityController.getSensParamValueForApp(paramChoice);
                app.syncStateToModel();
                return;
            end

            unitIdx = varargin{1};
            val = NaN;
            if isempty(unitIdx) || unitIdx < 1 || unitIdx > numel(app.units)
                return;
            end
            u = app.units{unitIdx};
            if contains(paramChoice, 'conversion') && isprop(u, 'conversion')
                val = u.conversion;
            elseif contains(paramChoice, 'beta') && isprop(u, 'beta')
                val = u.beta;
            elseif contains(paramChoice, 'phi') && isprop(u, 'phi')
                phi = u.phi;
                if ~isempty(phi)
                    val = phi(1);
                end
            end
        end

        function val = extractOutput(app, streamName, fieldStr)
            app.syncModelToState();
            val = app.SensitivityController.extractOutput(streamName, fieldStr);
            app.syncStateToModel();
        end
    end

    % =====================================================================
    %  HELPERS
    % =====================================================================
    methods (Access = private)
        function [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(~, unitDefs)
            [resolvedDefs, aliasByOutlet] = proc.UnitFactory.resolveIdentityLinks(unitDefs);
        end

        function addStreamAliasesToFlowsheet(app, fs, aliasByOutlet)
            proc.UnitFactory.addStreamAliasesToFlowsheet(fs, app.streams, aliasByOutlet);
        end

        function tf = isIdentityLinkDef(~, def)
            tf = proc.UnitFactory.isIdentityLinkDef(def);
        end

        function mix = buildThermoMixForGUI(app)
            mix = ui.AppUtils.buildThermoMix(app.speciesNames);
        end

        function names = getStreamNames(app)
            names = ui.AppUtils.getStreamNames(app.streams);
        end

        function s = findStream(app, name)
            s = ui.AppUtils.findStream(app.streams, name);
        end

        function nm = shortTypeName(~, u)
            nm = ui.AppUtils.shortTypeName(u);
        end

        function label = prettyUnitTypeName(~, type)
            label = ui.AppUtils.prettyUnitTypeName(type);
        end

        function catalog = unitTypeCatalog(~)
            catalog = ui.AppUtils.unitTypeCatalog();
        end

        function cfg = buildValidatedConfigPayload(app)
            cfg = ui.ConfigManager.buildConfigPayload( ...
                app.speciesNames, app.speciesMW, app.streams, app.unitDefs, ...
                app.MaxIterField.Value, app.TolField.Value, ...
                app.projectTitle, app.unitPrefs, app.lastExportPath, app.logEveryN);
        end

        function validateConfigPayload(~, cfg)
            ui.ConfigManager.validateConfigPayload(cfg);
        end

        function ensureWritableDir(~, dirPath)
            ui.AppUtils.ensureWritableDir(dirPath);
        end

        function setStatus(app, msg)
            app.StatusBar.Text = ['  ' msg];
        end
    end

    % =====================================================================
    %  OUTPUT FOLDER MANAGEMENT
    % =====================================================================
    methods (Access = private)
        function dirPath = ensureOutputDir(~, subfolder)
            dirPath = ui.AppUtils.ensureOutputDir(subfolder);
        end

        function fname = autoFileName(app, prefix, ext)
            fname = ui.AppUtils.autoFileName(app.projectTitle, prefix, ext);
        end

        function writeErrorLog(app, prefix, logLines)
            ui.AppUtils.writeErrorLog(app.projectTitle, prefix, logLines);
        end
    end
end
