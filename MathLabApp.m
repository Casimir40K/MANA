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

        % -- Debug popup --
        DebugFig
        DebugLevelDD
        DebugTopNField
        DebugEveryField
        DebugEqNamesCheck
        DebugLogArea

        % -- Unit Table popup --
        UnitTableFig
        UnitTable
        UnitTableStatusLabel

        % -- Stream Table popup --
        StreamTableFig
        StreamTable
        StreamTableStatusLabel
        StreamExportFormatDD
        StreamExportFileField
        StreamExportPathField
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
                'addDialogButtons', @(d,okFcn) app.addDialogButtons(d,okFcn)));
            app.SolveController = ui.tabs.SolveTabController(app.AppState, struct( ...
                'syncStreamsFromTable', @() app.syncStreamsFromTable(), ...
                'validateSolvePreconditions', @() app.validateSolvePreconditions(), ...
                'buildFlowsheet', @() app.buildFlowsheet(), ...
                'setLastFlowsheet', @(fs) app.setLastFlowsheet(fs), ...
                'updateDOF', @() app.updateDOF(), ...
                'getSolveInputs', @() app.getSolveInputs(), ...
                'prepareSolveRun', @(tol) app.prepareSolveRun(tol), ...
                'onSolveIter', @(iter,rNorm) app.onSolveIter(iter,rNorm), ...
                'getDebugSettings', @() app.debugSettings, ...
                'setLastSolver', @(solver) app.setLastSolver(solver), ...
                'onSolveSuccess', @(solver) app.onSolveSuccess(solver), ...
                'onSolveFailure', @(ME) app.onSolveFailure(ME)));
            app.ResultsController = ui.tabs.ResultsTabController(app.AppState, struct());
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
            leftG = uigridlayout(leftP, [5 1], ...
                'RowHeight',{30, 72, 36, 36, 24}, 'Padding',[8 8 8 8], 'RowSpacing',4);

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
            app.syncModelToState();
            app.UnitsController.dialogLink(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogMixer(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogMixer(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogReactor(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogStoichiometricReactor(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogStoichiometricReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogConversionReactor(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogConversionReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogYieldReactor(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogYieldReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogEquilibriumReactor(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogEquilibriumReactor(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogHeater(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Heater', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the heater.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Heated stream leaving the heater.'}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'},'Set outlet temperature or heat duty.'}, ...
                 {sprintf('Thermal value (%s or %s):', app.unitLabel('temperature','T'), app.unitLabel('duty','Q')),'numeric',app.fromSI(400,'temperature'),'Numerical value for the chosen thermal spec.'}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'},'How to handle outlet pressure.'}, ...
                 {sprintf('Pressure value (%s or ratio):', app.unitLabel('pressure','P')),'numeric',0,'Value for the chosen pressure spec (ignored for pass-through).'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=app.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=app.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=app.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=app.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Heater'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;

                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal)
                    uialert(d,'Thermal value must be finite.','Error'); return;
                end
                if strcmp(tMode,'Tout'), def.Tout=app.toSI(tVal,'temperature'); else, def.duty=app.toSI(tVal,'duty'); end

                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', app.unitPrefs.pressure),'Error'); return; end
                    def.Pout = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end

                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end

                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Heater(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCooler(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Cooler', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the cooler.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Cooled stream leaving the cooler.'}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'},'Set outlet temperature or heat duty.'}, ...
                 {sprintf('Thermal value (%s or %s):', app.unitLabel('temperature','T'), app.unitLabel('duty','Q')),'numeric',app.fromSI(300,'temperature'),'Numerical value for the chosen thermal spec.'}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'},'How to handle outlet pressure.'}, ...
                 {sprintf('Pressure value (%s or ratio):', app.unitLabel('pressure','P')),'numeric',0,'Value for the chosen pressure spec (ignored for pass-through).'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=app.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=app.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=app.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=app.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Cooler'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;

                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal)
                    uialert(d,'Thermal value must be finite.','Error'); return;
                end
                if strcmp(tMode,'Tout'), def.Tout=app.toSI(tVal,'temperature'); else, def.duty=app.toSI(tVal,'duty'); end

                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', app.unitPrefs.pressure),'Error'); return; end
                    def.Pout = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end

                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end

                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Cooler(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogHeatExchanger(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Heat Exchanger', 650, 300, ...
                {{'Hot inlet:','dropdown',sNames,'Hot stream entering the exchanger.'}, ...
                 {'Hot outlet:','dropdown',sNames,'Hot stream leaving the exchanger.'}, ...
                 {'Cold inlet:','dropdown',sNames,'Cold stream entering the exchanger.'}, ...
                 {'Cold outlet:','dropdown',sNames,'Cold stream leaving the exchanger.'}, ...
                 {'Spec mode:','dropdown',{'Th_out','Tc_out','duty'},'Specify hot outlet T, cold outlet T, or heat duty.'}, ...
                 {sprintf('Spec value (%s or %s):', app.unitLabel('temperature','T'), app.unitLabel('duty','Q')),'numeric',app.fromSI(350,'temperature'),'Value for the chosen specification.'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.hotInlet.name));
                ctrls{2}.Value=char(string(u.hotOutlet.name));
                ctrls{3}.Value=char(string(u.coldInlet.name));
                ctrls{4}.Value=char(string(u.coldOutlet.name));
                if isfinite(u.Th_out), ctrls{5}.Value='Th_out'; ctrls{6}.Value=app.fromSI(u.Th_out,'temperature');
                elseif isfinite(u.Tc_out), ctrls{5}.Value='Tc_out'; ctrls{6}.Value=app.fromSI(u.Tc_out,'temperature');
                else, ctrls{5}.Value='duty'; ctrls{6}.Value=app.fromSI(u.duty,'duty'); end
            elseif numel(sNames)>=4
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3}; ctrls{4}.Value=sNames{4};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='HeatExchanger';
                def.hotInlet=ctrls{1}.Value; def.hotOutlet=ctrls{2}.Value;
                def.coldInlet=ctrls{3}.Value; def.coldOutlet=ctrls{4}.Value;
                mode=ctrls{5}.Value; val=ctrls{6}.Value;
                if strcmp(mode,'Th_out'), def.Th_out=app.toSI(val,'temperature');
                elseif strcmp(mode,'Tc_out'), def.Tc_out=app.toSI(val,'temperature');
                else, def.duty=app.toSI(val,'duty'); end
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                u=proc.units.HeatExchanger(app.findStream(def.hotInlet),app.findStream(def.hotOutlet),...
                    app.findStream(def.coldInlet),app.findStream(def.coldOutlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCompressor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Compressor', 560, 240, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the compressor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Compressed stream leaving the compressor.'}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'},'Set outlet pressure or pressure ratio.'}, ...
                 {sprintf('Pressure value (%s or ratio):', app.unitLabel('pressure','P')),'numeric',app.fromSI(2e5,'pressure'),'Numerical value for the chosen pressure spec.'}, ...
                 {'Isentropic efficiency (0 to 1):','numeric',0.85,'Compressor isentropic efficiency.'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=app.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Compressor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=app.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Compressor(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogTurbine(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Turbine', 560, 240, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the turbine.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Expanded stream leaving the turbine.'}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'},'Set outlet pressure or pressure ratio.'}, ...
                 {sprintf('Pressure value (%s or ratio):', app.unitLabel('pressure','P')),'numeric',app.fromSI(5e4,'pressure'),'Numerical value for the chosen pressure spec.'}, ...
                 {'Isentropic efficiency (0 to 1):','numeric',0.85,'Turbine isentropic efficiency.'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=app.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Turbine'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=app.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Turbine(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogSeparator(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Separator', 620, 240, ...
                {{'Feed stream:','dropdown',sNames,'Stream entering the separator.'}, ...
                 {'Outlet A:','dropdown',sNames,'First outlet stream.'}, ...
                 {'Outlet B:','dropdown',sNames,'Second outlet stream (remainder).'}, ...
                 {sprintf('Split fractions to A (%d species):',ns),'text',num2str(repmat(0.5,1,ns)),'Fraction of each species sent to outlet A (0 to 1). Remainder goes to B.'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outletA.name));
                ctrls{3}.Value=char(string(u.outletB.name));
                ctrls{4}.Value=num2str(u.phi);
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                phi=str2num(ctrls{4}.Value); %#ok
                if numel(phi)~=ns
                    uialert(d,sprintf('phi needs %d values.',ns),'Error'); return;
                end
                def.type='Separator'; def.inlet=ctrls{1}.Value;
                def.outletA=ctrls{2}.Value; def.outletB=ctrls{3}.Value; def.phi=phi;
                u=proc.units.Separator(app.findStream(def.inlet),...
                    app.findStream(def.outletA),app.findStream(def.outletB),phi);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogPurge(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Purge Split', 560, 230, ...
                {{'Feed stream:','dropdown',sNames,'Stream to split into recycle and purge.'}, ...
                 {'Recycle stream:','dropdown',sNames,'Stream returned to the loop.'}, ...
                 {'Purge stream:','dropdown',sNames,'Bleed stream removed from the loop.'}, ...
                 {'Recycle fraction (0 to 1):','numeric',0.9,'Fraction of feed sent to recycle. Remainder goes to purge.'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.recycle.name));
                ctrls{3}.Value=char(string(u.purge.name));
                ctrls{4}.Value=u.beta;
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Purge'; def.inlet=ctrls{1}.Value;
                def.recycle=ctrls{2}.Value; def.purge=ctrls{3}.Value;
                def.beta=ctrls{4}.Value;
                u=proc.units.Purge(app.findStream(def.inlet),...
                    app.findStream(def.recycle),app.findStream(def.purge),def.beta);
                app.commitUnit(u,def,editIdx); delete(d);
            end
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

            app.LogArea.Value = cellstr(solver.logLines);
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
            app.LogArea.Value = logLines;
            app.writeErrorLog('solve_error', logLines);
            if strcmp(ME.identifier, 'Flowsheet:NonConvergedSolve')
                app.setStatus('Non-converged iterate; balances not satisfied.');
            else
                app.setStatus('Solve failed — see log (saved to output/logs).');
            end
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
            if isempty(app.ResultsAxes) || ~isvalid(app.ResultsAxes)
                return;
            end

            cla(app.ResultsAxes, 'reset');
            yyaxis(app.ResultsAxes,'left');
            yyaxis(app.ResultsAxes,'right');
            yyaxis(app.ResultsAxes,'left');
            hold(app.ResultsAxes,'on');
            grid(app.ResultsAxes,'on');
            app.ResultsAxes.XScale = app.ResultsXScaleDropDown.Value;
            app.ResultsAxes.YScale = app.ResultsYScaleDropDown.Value;

            plotted = false;
            for idx = 1:4
                plotted = app.plotResultsConfig(idx) || plotted;
            end

            if plotted
                if strcmp(app.ResultsLegendDD.Value,'off')
                    legend(app.ResultsAxes,'off');
                else
                    legend(app.ResultsAxes,'Location',app.ResultsLegendDD.Value);
                end
                app.ResultsPlotStatusLabel.Text = sprintf('Snapshots: %d | smoothing: %s(%d)', ...
                    numel(app.resultsSnapshots), app.ResultsSmoothingDD.Value, round(app.ResultsSmoothWindowField.Value));
            else
                app.ResultsPlotStatusLabel.Text = 'No plottable data. Solve first and verify target/variables.';
            end
            hold(app.ResultsAxes,'off');
            app.refreshResultsTargetOptions();
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

        function refreshResultsSummaryModel(app)
            prevResidual = app.resultsSummary.residual;
            summary = struct('status','Not solved','residual',NaN,'iterations',0, ...
                'streamKey','-','unitKey','-','streamText','-','unitText','-','deltaText','-');
            if isempty(app.lastSolver)
                app.resultsSummary = summary;
                return;
            end

            iters = 0;
            try
                iters = max(0, numel(app.lastSolver.residualHistory)-1);
            catch
                iters = 0;
            end
            residual = NaN;
            try
                if ~isempty(app.lastSolver.residualHistory)
                    residual = app.lastSolver.residualHistory(end);
                end
            catch
            end
            try
                if app.lastSolver.converged
                    summary.status = 'Converged';
                else
                    summary.status = 'Non-converged';
                end
            catch
                summary.status = 'Solved';
            end
            summary.residual = residual;
            summary.iterations = iters;

            if ~isempty(app.lastFlowsheet) && ~isempty(app.lastFlowsheet.streamDisplayNames)
                nm = char(string(app.lastFlowsheet.streamDisplayNames{1}));
                summary.streamKey = nm;
                sref = app.lastFlowsheet.streamDisplayRefs{1};
                summary.streamText = sprintf('%s | %s=%.4g | %s=%.4g | %s=%.4g', nm, ...
                    app.unitLabel('flow','n_dot'), app.fromSI(sref.n_dot,'flow'), ...
                    app.unitLabel('temperature','T'), app.fromSI(sref.T,'temperature'), ...
                    app.unitLabel('pressure','P'), app.fromSI(sref.P,'pressure'));
            end

            if ~isempty(app.lastFlowsheet) && ~isempty(app.lastFlowsheet.units)
                u = app.lastFlowsheet.units{1};
                uk = sprintf('U1_%s', app.shortTypeName(u));
                summary.unitKey = uk;
                upairs = app.unitObjectResultPairs(u);
                if isempty(upairs)
                    summary.unitText = sprintf('%s | no reportable metrics', uk);
                else
                    summary.unitText = sprintf('%s | %s: %s', uk, upairs{1,1}, app.formatSpecValue(upairs{1,2}));
                end
            end

            if isfinite(prevResidual) && isfinite(summary.residual)
                d = summary.residual - prevResidual;
                summary.deltaText = sprintf('Residual delta vs previous run: %+0.3e', d);
            else
                summary.deltaText = 'Residual delta vs previous run: n/a';
            end
            app.resultsSummary = summary;
        end

        function refreshResultsSummaryPanel(app)
            % Update the compact status banner on the Results-Tables tab
            s = app.resultsSummary;

            if ~isempty(app.ResultsTablesStatusBanner) && isvalid(app.ResultsTablesStatusBanner)
                statusColor = [0.6 0.1 0.1];
                if strcmp(s.status, 'Converged'), statusColor = [0.1 0.5 0.1]; end
                app.ResultsTablesStatusBanner.Text = sprintf('Status: %s', s.status);
                app.ResultsTablesStatusBanner.FontColor = statusColor;
            end
            if ~isempty(app.ResultsTablesResidualLabel) && isvalid(app.ResultsTablesResidualLabel)
                if isfinite(s.residual)
                    app.ResultsTablesResidualLabel.Text = sprintf('Residual: %.3e', s.residual);
                else
                    app.ResultsTablesResidualLabel.Text = 'Residual: -';
                end
            end
            if ~isempty(app.ResultsTablesIterLabel) && isvalid(app.ResultsTablesIterLabel)
                app.ResultsTablesIterLabel.Text = sprintf('Iterations: %d', s.iterations);
            end
        end

        function exportResultsSummaryCsv(app)
            T = table(string(app.resultsSummary.status), app.resultsSummary.residual, app.resultsSummary.iterations, ...
                string(app.resultsSummary.streamKey), string(app.resultsSummary.streamText), ...
                string(app.resultsSummary.unitKey), string(app.resultsSummary.unitText), ...
                string(app.resultsSummary.deltaText), ...
                'VariableNames', {'status','final_residual','iterations','key_stream','key_stream_summary', ...
                'key_unit','key_unit_summary','delta_note'});
            outDir = app.resolveInitialExportPath();
            filepath = fullfile(outDir, app.autoFileName('results_summary', 'csv'));
            writetable(T, filepath);
            app.setStatus(sprintf('Results summary exported to %s', filepath));
            app.appendResultsExportLog(sprintf('Results summary exported: %s', filepath));
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

        function refreshResultsTablesTab(app)
            if ~isempty(app.ResultsStreamTable) && isvalid(app.ResultsStreamTable)
                Ts = app.buildDisplayStreamTable();
                app.ResultsStreamTable.Data = Ts;
                app.ResultsStreamTable.ColumnName = Ts.Properties.VariableNames;
            end
            if ~isempty(app.ResultsUnitTable) && isvalid(app.ResultsUnitTable)
                Tu = app.buildUnitResultsTable();
                app.ResultsUnitTable.Data = Tu;
                app.ResultsUnitTable.ColumnName = Tu.Properties.VariableNames;
            end
            if ~isempty(app.ResultsTablesStatusLabel) && isvalid(app.ResultsTablesStatusLabel)
                if isempty(app.lastSolver)
                    app.ResultsTablesStatusLabel.Text = 'Tables show current configured values. Run solve for final solved metrics.';
                else
                    app.ResultsTablesStatusLabel.Text = 'Tables refreshed from latest solved state.';
                end
            end
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
            if cond, txt = a; else, txt = b; end
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
            if isempty(app.ResultsAxes) || ~isvalid(app.ResultsAxes)
                return;
            end
            outDir = fullfile(pwd, 'output');
            if ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            outFile = fullfile(outDir, sprintf('%s_results_plot_%s.png', app.projectTitle, stamp));
            try
                exportgraphics(app.ResultsAxes, outFile, 'Resolution', 150);
                app.setStatus(sprintf('Results plot exported: %s', outFile));
            catch
                app.setStatus('Failed to export results figure.');
            end
        end

    end


    % =====================================================================
    %  DEBUG TOOLS POPUP
    % =====================================================================
    methods (Access = private)
        function openDebugPopup(app)
            if ~isempty(app.DebugFig) && isvalid(app.DebugFig)
                app.DebugFig.Visible = 'on';
                return;
            end

            app.DebugFig = uifigure('Name','MathLab — Debug Tools', ...
                'Position',[150 120 620 520], 'Color',[0.97 0.97 0.98]);
            app.DebugFig.CloseRequestFcn = @(src,~) app.onDebugPopupClosed(src);

            gl = uigridlayout(app.DebugFig, [4 1], ...
                'RowHeight',{28, 'fit', 'fit', '1x'}, 'Padding',[10 10 10 10], 'RowSpacing',8);

            uilabel(gl, 'Text','Debug & Diagnostics', 'FontWeight','bold', 'FontSize',14);

            % --- Solver debug settings ---
            solverP = uipanel(gl, 'Title','Solver Debug Settings', 'FontWeight','bold');
            sg = uigridlayout(solverP, [4 4], 'ColumnWidth',{'fit','1x','fit','1x'}, ...
                'RowHeight',{28,28,28,28}, 'Padding',[8 8 8 8], 'RowSpacing',4, 'ColumnSpacing',8);

            uilabel(sg,'Text','Debug level:','FontWeight','bold');
            app.DebugLevelDD = uidropdown(sg, 'Items',{'0 — off','1 — summary','2 — top residuals','3 — periodic'}, 'Value','0 — off');
            uilabel(sg,'Text','Top N equations:','FontWeight','bold');
            app.DebugTopNField = uieditfield(sg, 'numeric', 'Value',10, 'Limits',[1 100], 'RoundFractionalValues','on');

            uilabel(sg,'Text','Print every N iters:','FontWeight','bold');
            app.DebugEveryField = uieditfield(sg, 'numeric', 'Value',0, 'Limits',[0 10000], 'RoundFractionalValues','on');
            uilabel(sg,'Text','Show eq. labels:','FontWeight','bold');
            app.DebugEqNamesCheck = uicheckbox(sg, 'Text','', 'Value',true);

            uilabel(sg,'Text','');
            uilabel(sg,'Text','');
            uilabel(sg,'Text','');
            applyBtn = uibutton(sg, 'push', 'Text','Apply to Next Solve', ...
                'FontWeight','bold', 'BackgroundColor',[0.88 0.93 0.85], ...
                'ButtonPushedFcn',@(~,~) app.applyDebugSettings());

            % --- Diagnostic actions ---
            actionsP = uipanel(gl, 'Title','Diagnostic Actions', 'FontWeight','bold');
            ag = uigridlayout(actionsP, [2 3], 'ColumnWidth',{'1x','1x','1x'}, ...
                'RowHeight',{30,30}, 'Padding',[8 8 8 8], 'RowSpacing',4, 'ColumnSpacing',8);

            uibutton(ag, 'push', 'Text','Show Jacobian Sparsity', ...
                'ButtonPushedFcn',@(~,~) app.debugShowJacobianSparsity());
            uibutton(ag, 'push', 'Text','Show Worst Residuals', ...
                'ButtonPushedFcn',@(~,~) app.debugShowWorstResiduals());
            uibutton(ag, 'push', 'Text','Show DOF Analysis', ...
                'ButtonPushedFcn',@(~,~) app.debugShowDOF());
            uibutton(ag, 'push', 'Text','Dump Solver State', ...
                'ButtonPushedFcn',@(~,~) app.debugDumpSolverState());
            uibutton(ag, 'push', 'Text','Show Pole Summary', ...
                'ButtonPushedFcn',@(~,~) app.debugShowPoles());
            uibutton(ag, 'push', 'Text','Open Unit Table', ...
                'ButtonPushedFcn',@(~,~) app.openUnitTablePopup());

            % --- Log area ---
            app.DebugLogArea = uitextarea(gl, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',11, ...
                'Value',{'Debug output will appear here.'; ''; 'Use the actions above or apply debug settings before solving.'});
        end

        function onDebugPopupClosed(app, src)
            if ~isempty(src) && isvalid(src)
                delete(src);
            end
            app.DebugFig = [];
        end

        function applyDebugSettings(app)
            levelStr = app.DebugLevelDD.Value;
            level = str2double(levelStr(1));
            topN = round(app.DebugTopNField.Value);
            every = round(app.DebugEveryField.Value);
            eqNames = app.DebugEqNamesCheck.Value;

            % Store for next solve
            app.debugSettings = struct('debugLevel',level,'debugTopN',topN, ...
                'debugEvery',every,'debugEqNames',eqNames);

            msg = sprintf('Debug settings applied: level=%d, topN=%d, every=%d, eqNames=%s', ...
                level, topN, every, app.ternary(eqNames, 'on', 'off'));
            app.appendDebugLog(msg);
        end

        function appendDebugLog(app, msg)
            if isempty(app.DebugLogArea) || ~isvalid(app.DebugLogArea)
                return;
            end
            vals = app.DebugLogArea.Value;
            if ischar(vals), vals = {vals}; end
            ts = datestr(now, 'HH:MM:SS');
            vals{end+1} = sprintf('[%s] %s', ts, msg);
            if numel(vals) > 100
                vals = vals(end-99:end);
            end
            app.DebugLogArea.Value = vals;
        end

        function debugShowJacobianSparsity(app)
            if isempty(app.lastSolver)
                app.appendDebugLog('No solver available. Run solve first.');
                return;
            end
            try
                st = app.lastSolver.localStabilityProxy();
                J = st.J;
                nz = nnz(abs(J) > 1e-15);
                tot = numel(J);
                density = nz / max(1,tot) * 100;
                app.appendDebugLog(sprintf('Jacobian: %dx%d, %d non-zero (%.1f%% density)', ...
                    size(J,1), size(J,2), nz, density));
                app.appendDebugLog(sprintf('  Condition number: %.3e', cond(J)));
                app.appendDebugLog(sprintf('  Rank: %d / %d', rank(J), min(size(J))));
            catch ME
                app.appendDebugLog(sprintf('Jacobian analysis failed: %s', ME.message));
            end
        end

        function debugShowWorstResiduals(app)
            if isempty(app.lastSolver)
                app.appendDebugLog('No solver available. Run solve first.');
                return;
            end
            try
                sv = app.lastSolver;
                app.appendDebugLog(sprintf('--- Residual Summary ---'));
                app.appendDebugLog(sprintf('  Final residual: %.4e', sv.finalResidual));
                if ~isempty(sv.residualHistory)
                    rh = sv.residualHistory(isfinite(sv.residualHistory));
                    app.appendDebugLog(sprintf('  Residual history: %d points', numel(rh)));
                    app.appendDebugLog(sprintf('  Initial: %.4e | Final: %.4e', rh(1), rh(end)));
                    if numel(rh) >= 2
                        ratio = rh(end) / max(rh(1), eps);
                        app.appendDebugLog(sprintf('  Reduction ratio: %.4e', ratio));
                    end
                end
                if ~isempty(sv.weightedResidualHistory)
                    wrh = sv.weightedResidualHistory(isfinite(sv.weightedResidualHistory));
                    if ~isempty(wrh)
                        app.appendDebugLog(sprintf('  Final weighted residual: %.4e', wrh(end)));
                    end
                end
            catch ME
                app.appendDebugLog(sprintf('Residual analysis failed: %s', ME.message));
            end
        end

        function debugShowDOF(app)
            try
                fs = app.buildFlowsheet();
                [nEq, nUnk, dof] = fs.checkDOF();
                app.appendDebugLog(sprintf('DOF Analysis: %d equations, %d unknowns, DOF=%d', nEq, nUnk, dof));
                if dof == 0
                    app.appendDebugLog('  System is exactly determined.');
                elseif dof > 0
                    app.appendDebugLog(sprintf('  Under-specified by %d (need more specs).', dof));
                else
                    app.appendDebugLog(sprintf('  Over-specified by %d (too many specs).', abs(dof)));
                end
            catch ME
                app.appendDebugLog(sprintf('DOF analysis failed: %s', ME.message));
            end
        end

        function debugDumpSolverState(app)
            if isempty(app.lastSolver)
                app.appendDebugLog('No solver available. Run solve first.');
                return;
            end
            try
                sv = app.lastSolver;
                app.appendDebugLog('--- Solver State Dump ---');
                app.appendDebugLog(sprintf('  Converged: %s', app.ternary(sv.converged,'yes','no')));
                app.appendDebugLog(sprintf('  Exit flag: %s', sv.exitFlag));
                app.appendDebugLog(sprintf('  Final residual: %.4e', sv.finalResidual));
                app.appendDebugLog(sprintf('  Iterations: %d', numel(sv.residualHistory)-1));
                try
                    st = sv.localStabilityProxy();
                    app.appendDebugLog(sprintf('  Unknowns: %d', st.nUnknowns));
                    app.appendDebugLog(sprintf('  Equations: %d', st.nEquations));
                catch
                    app.appendDebugLog('  Unknowns/Equations: unavailable');
                end
                if ~isempty(sv.residualHistory)
                    app.appendDebugLog(sprintf('  Residual range: [%.3e, %.3e]', ...
                        min(sv.residualHistory(isfinite(sv.residualHistory))), ...
                        max(sv.residualHistory(isfinite(sv.residualHistory)))));
                end
                % Save full dump to output
                outDir = fullfile(pwd, 'output');
                if ~exist(outDir, 'dir'), mkdir(outDir); end
                stamp = datestr(now, 'yyyymmdd_HHMMSS');
                outFile = fullfile(outDir, sprintf('debug_dump_%s.mat', stamp));
                solver = app.lastSolver; %#ok<PROPLC>
                save(outFile, 'solver');
                app.appendDebugLog(sprintf('  Full dump saved: %s', outFile));
            catch ME
                app.appendDebugLog(sprintf('Dump failed: %s', ME.message));
            end
        end

        function debugShowPoles(app)
            if isempty(app.lastSolver)
                app.appendDebugLog('No solver available. Run solve first.');
                return;
            end
            try
                st = app.lastSolver.localStabilityProxy();
                poles = st.poles;
                nStable = sum(real(poles) < 0);
                nUnstable = sum(real(poles) >= 0);
                app.appendDebugLog(sprintf('--- Pole Summary (%d total) ---', numel(poles)));
                app.appendDebugLog(sprintf('  Stable: %d | Unstable: %d', nStable, nUnstable));
                app.appendDebugLog(sprintf('  Max Re(pole): %.4e', st.maxReal));
                app.appendDebugLog(sprintf('  Min Re(pole): %.4e', st.minReal));
                % Show 5 most unstable
                [~, idx] = sort(real(poles), 'descend');
                topN = min(5, numel(poles));
                app.appendDebugLog(sprintf('  Top %d most unstable:', topN));
                for i = 1:topN
                    p = poles(idx(i));
                    app.appendDebugLog(sprintf('    %+.4e %+.4ej', real(p), imag(p)));
                end
            catch ME
                app.appendDebugLog(sprintf('Pole analysis failed: %s', ME.message));
            end
        end
    end

    % =====================================================================
    %  UNIT TABLE POPUP
    % =====================================================================
    methods (Access = private)
        function openUnitTablePopup(app)
            if ~isempty(app.UnitTableFig) && isvalid(app.UnitTableFig)
                app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
                app.UnitTableFig.Visible = 'on';
                return;
            end

            app.UnitTableFig = uifigure('Name','MathLab — Unit Results Table', ...
                'Position',[120 80 980 480], 'Color',[0.97 0.97 0.98]);
            app.UnitTableFig.CloseRequestFcn = @(src,~) app.onUnitTablePopupClosed(src);

            gl = uigridlayout(app.UnitTableFig, [3 1], ...
                'RowHeight',{34,'1x',32}, 'Padding',[10 10 10 10], 'RowSpacing',6);

            topG = uigridlayout(gl, [1 4], 'ColumnWidth',{'fit','1x',110,110}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Unit Results Table (Read-only)', 'FontWeight','bold', 'FontSize',13);
            uilabel(topG, 'Text','Type + connected streams + solved metrics (duty/power/conversion) are flattened for quick review.', ...
                'FontColor',[0.35 0.35 0.35]);
            uibutton(topG, 'push', 'Text','Export CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportUnitTableToOutput('csv'));
            uibutton(topG, 'push', 'Text','Export MAT', ...
                'ButtonPushedFcn',@(~,~) app.exportUnitTableToOutput('mat'));

            app.UnitTable = uitable(gl, ...
                'ColumnEditable', false(1,9), ...
                'ColumnName', {'Unit #','Type','Connected Streams', ...
                               'Spec 1 Label','Spec 1 Value', ...
                               'Spec 2 Label','Spec 2 Value', ...
                               'Spec 3 Label','Spec 3 Value'});
            app.UnitTable.Layout.Row = 2;

            app.UnitTableStatusLabel = uilabel(gl, 'Text','', 'FontColor',[0.3 0.3 0.3]);
            app.UnitTableStatusLabel.Layout.Row = 3;

            app.refreshUnitTablePopup();
            app.refreshStreamTablePopup();
            app.refreshResultsTablesTab();
        end

        function onUnitTablePopupClosed(app, src)
            if ~isempty(src) && isvalid(src)
                delete(src);
            end
            app.UnitTableFig = [];
            app.UnitTable = [];
            app.UnitTableStatusLabel = [];
        end

        function refreshUnitTablePopup(app)
            if isempty(app.UnitTable) || ~isvalid(app.UnitTable)
                return;
            end
            T = app.buildUnitResultsTable();
            app.UnitTable.Data = T;
            app.UnitTable.ColumnName = T.Properties.VariableNames;
            if isempty(T)
                status = 'No units defined yet.';
            elseif isempty(app.lastSolver) || isempty(app.lastFlowsheet)
                status = sprintf('%d unit(s). Showing configured values. Run Solve for calculated metrics.', height(T));
            else
                status = sprintf('%d unit(s). Read-only simulation view with solved metrics.', height(T));
            end
            if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                app.UnitTableStatusLabel.Text = status;
            end
        end

        function T = buildUnitResultsTable(app)
            if ~isempty(app.lastFlowsheet) && isprop(app.lastFlowsheet, 'units')
                T = app.buildUnitTableFromObjects(app.lastFlowsheet.units);
            elseif ~isempty(app.units)
                T = app.buildUnitTableFromObjects(app.units);
            else
                T = app.buildUnitTable();
            end
        end

        function T = buildUnitTableFromObjects(app, units)
            n = numel(units);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Result1_Label','Result1_Value','Result2_Label','Result2_Value','Result3_Label','Result3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = app.serializeUnitObjectRow(i, units{i});
            end
            T = cell2table(data, 'VariableNames', cols);
        end

        function row = serializeUnitObjectRow(app, idx, u)
            row = {idx, app.shortTypeName(u), '-', '-', '-', '-', '-', '-', '-'};
            row{3} = app.unitObjectConnectedStreams(u);
            pairs = app.unitObjectResultPairs(u);
            for k = 1:min(3,size(pairs,1))
                row{3 + (k-1)*2 + 1} = pairs{k,1};
                row{3 + (k-1)*2 + 2} = pairs{k,2};
            end
        end

        function streamText = unitObjectConnectedStreams(app, u)
            names = {};
            if ismethod(u, 'streamNames')
                try
                    names = u.streamNames();
                catch
                    names = {};
                end
            end
            if isempty(names)
                streamText = '-';
            else
                streamText = app.formatSpecValue(names);
            end
        end

        function pairs = unitObjectResultPairs(app, u)
            pairs = {};
            cn = class(u);
            if contains(cn,'HeatExchanger')
                pairs = {app.unitLabel('duty','Duty'), app.safeMethodValue(u,'getDuty','duty'); ...
                         app.unitLabel('temperature','Hot Tout'), app.safePropValue(u,'hotOutlet','T','temperature'); ...
                         app.unitLabel('temperature','Cold Tout'), app.safePropValue(u,'coldOutlet','T','temperature')};
            elseif contains(cn,'Heater') || contains(cn,'Cooler')
                pairs = {app.unitLabel('duty','Duty'), app.safeMethodValue(u,'getDuty','duty'); ...
                         app.unitLabel('temperature','Tin'), app.safePropValue(u,'inlet','T','temperature'); ...
                         app.unitLabel('temperature','Tout'), app.safePropValue(u,'outlet','T','temperature')};
            elseif contains(cn,'Compressor') || contains(cn,'Turbine')
                pairs = {app.unitLabel('power','Power'), app.safeMethodValue(u,'getPower','power'); ...
                         'Pressure ratio', app.safePressureRatio(u); ...
                         'Eta', app.safeSimpleProp(u,'eta')};
            elseif contains(cn,'StoichiometricReactor')
                pairs = {'Extent', app.safeSimpleProp(u,'extent'); ...
                         'Extent mode', app.safeSimpleProp(u,'extentMode'); ...
                         'Ref species', app.safeSimpleProp(u,'referenceSpecies')};
            elseif contains(cn,'EquilibriumReactor')
                pairs = {'Keq', app.safeSimpleProp(u,'Keq'); ...
                         'Ref species', app.safeSimpleProp(u,'referenceSpecies'); ...
                         app.unitLabel('temperature','Tout'), app.safePropValue(u,'outlet','T','temperature')};
            elseif contains(cn,'ConversionReactor') || contains(cn,'YieldReactor') || contains(cn,'Reactor')
                pairs = {'Conversion', app.safeSimpleProp(u,'conversion'); ...
                         app.unitLabel('temperature','Tin'), app.safePropValue(u,'inlet','T','temperature'); ...
                         app.unitLabel('temperature','Tout'), app.safePropValue(u,'outlet','T','temperature')};
            elseif contains(cn,'Separator')
                pairs = {'Split phi', app.safeSimpleProp(u,'phi')};
            elseif contains(cn,'Purge')
                pairs = {'Purge beta', app.safeSimpleProp(u,'beta')};
            else
                pairs = {'Description', app.safeDescribe(u)};
            end
        end

        function val = safeMethodValue(app, u, m, quantity)
            try
                if ismethod(u,m)
                    raw = u.(m)();
                    if nargin >= 4 && ~isempty(quantity)
                        raw = app.fromSI(raw, quantity);
                    end
                    val = app.formatSpecValue(raw);
                else
                    val = '-';
                end
            catch
                val = '-';
            end
        end

        function val = safeSimpleProp(app, u, p)
            try
                if isprop(u,p)
                    val = app.formatSpecValue(u.(p));
                else
                    val = '-';
                end
            catch
                val = '-';
            end
        end

        function val = safePropValue(app, u, ownerProp, fieldProp, quantity)
            try
                if isprop(u, ownerProp)
                    owner = u.(ownerProp);
                    if isprop(owner, fieldProp)
                        raw = owner.(fieldProp);
                        if nargin >= 5 && ~isempty(quantity)
                            raw = app.fromSI(raw, quantity);
                        end
                        val = app.formatSpecValue(raw);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function val = safePressureRatio(app, u)
            try
                if isprop(u,'PR') && isfinite(u.PR)
                    val = app.formatSpecValue(u.PR);
                    return;
                end
                if isprop(u,'inlet') && isprop(u,'outlet')
                    p1 = u.inlet.P;
                    p2 = u.outlet.P;
                    if isfinite(p1) && p1 ~= 0 && isfinite(p2)
                        val = app.formatSpecValue(p2/p1);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function txt = safeDescribe(~, u)
            try
                if ismethod(u,'describe')
                    txt = char(string(u.describe()));
                else
                    txt = class(u);
                end
            catch
                txt = class(u);
            end
        end

        function T = buildUnitTable(app)
            n = numel(app.unitDefs);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Spec1_Label','Spec1_Value','Spec2_Label','Spec2_Value','Spec3_Label','Spec3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = app.serializeUnitDefRow(i, app.unitDefs{i});
            end
            T = cell2table(data, 'VariableNames', cols);
        end

        function row = serializeUnitDefRow(app, idx, def)
            row = {idx, '-', '-', '-', '-', '-', '-', '-', '-'};
            if ~isstruct(def) || ~isfield(def,'type')
                return;
            end
            typ = char(string(def.type));
            row{2} = typ;
            row{3} = app.unitConnectedStreams(def);

            specs = app.unitSpecPairs(def);
            for k = 1:min(3,size(specs,1))
                row{3 + (k-1)*2 + 1} = specs{k,1};
                row{3 + (k-1)*2 + 2} = specs{k,2};
            end
        end

        function streamText = unitConnectedStreams(app, def)
            parts = {};
            fSingle = {'inlet','outlet','source','tear','stream','recycle','purge','outletA','outletB', ...
                'processInlet','bypassStream','processReturn','hotInlet','hotOutlet','coldInlet','coldOutlet', ...
                'lhsStream','aStream','bStream'};
            for i = 1:numel(fSingle)
                f = fSingle{i};
                if isfield(def,f)
                    parts{end+1} = sprintf('%s=%s', f, app.formatSpecValue(def.(f))); %#ok<AGROW>
                end
            end
            if isfield(def,'inlets')
                parts{end+1} = sprintf('inlets=%s', app.formatSpecValue(def.inlets)); %#ok<AGROW>
            end
            if isfield(def,'outlets')
                parts{end+1} = sprintf('outlets=%s', app.formatSpecValue(def.outlets)); %#ok<AGROW>
            end
            if isempty(parts)
                streamText = '-';
            else
                streamText = strjoin(parts, ' | ');
            end
        end

        function specs = unitSpecPairs(app, def)
            specs = {};
            typ = char(string(def.type));
            switch typ
                case 'Mixer'
                    specs = {'No. inlets', app.formatSpecValue(numel(def.inlets)); 'Outlet', app.formatSpecValue(def.outlet)};
                case 'Heater'
                    specs = {app.unitLabel('temperature','Tout'), app.getDefField(def,'Tout','temperature'); app.unitLabel('duty','Qdot'), app.getDefField(def,'duty','duty'); 'dP/Pout/PR', app.getDefField(def,'dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = app.getDefField(def,'Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                            specs{3,2} = app.getDefField(def,'PR');
                        end
                    end
                case 'Cooler'
                    specs = {app.unitLabel('temperature','Tout'), app.getDefField(def,'Tout','temperature'); app.unitLabel('duty','Qdot'), app.getDefField(def,'duty','duty'); 'dP/Pout/PR', app.getDefField(def,'dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = app.getDefField(def,'Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                            specs{3,2} = app.getDefField(def,'PR');
                        end
                    end
                case 'Compressor'
                    specs = {'Pressure ratio', app.getDefField(def,'PR'); 'Efficiency', app.getDefField(def,'eta')};
                case 'Turbine'
                    specs = {'Pressure ratio', app.getDefField(def,'PR'); 'Efficiency', app.getDefField(def,'eta')};
                case 'Reactor'
                    specs = {'Conversion', app.getDefField(def,'conversion'); 'Reactions', app.getDefField(def,'reactions')};
                case 'ConversionReactor'
                    specs = {'Key species', app.getDefField(def,'keySpecies'); 'Conversion', app.getDefField(def,'conversion'); 'Mode', app.getDefField(def,'conversionMode')};
                case 'StoichiometricReactor'
                    specs = {'Extent', app.getDefField(def,'extent'); 'Mode', app.getDefField(def,'extentMode'); 'Ref species', app.getDefField(def,'referenceSpecies')};
                case 'YieldReactor'
                    specs = {'Basis species', app.getDefField(def,'basisSpecies'); 'Conversion', app.getDefField(def,'conversion'); 'Products', app.getDefField(def,'productSpecies')};
                case 'EquilibriumReactor'
                    specs = {'Keq', app.getDefField(def,'Keq'); 'Ref species', app.getDefField(def,'referenceSpecies'); 'Stoich nu', app.getDefField(def,'nu')};
                case 'Separator'
                    specs = {'Split phi', app.getDefField(def,'phi')};
                case 'Purge'
                    specs = {'Purge beta', app.getDefField(def,'beta')};
                case 'Splitter'
                    if isfield(def,'splitFractions')
                        specs = {'Mode', 'fractions'; 'Values', app.getDefField(def,'splitFractions')};
                    else
                        specs = {'Mode', 'flows'; 'Values', app.getDefField(def,'specifiedOutletFlows')};
                    end
                case 'Bypass'
                    specs = {'Bypass fraction', app.getDefField(def,'bypassFraction')};
                case 'Manifold'
                    specs = {'Route', app.getDefField(def,'route')};
                case 'Source'
                    specs = {app.unitLabel('flow','Total flow'), app.getDefField(def,'totalFlow','flow'); 'Composition', app.getDefField(def,'composition'); app.unitLabel('flow','Comp flows'), app.getDefField(def,'componentFlows','flow')};
                case 'DesignSpec'
                    specs = {'Metric', app.getDefField(def,'metric'); 'Target', app.getDefField(def,'target'); 'Species idx', app.getDefField(def,'speciesIndex')};
                case 'Adjust'
                    specs = {'Field', app.getDefField(def,'field'); 'Index', app.getDefField(def,'index'); 'Bounds', sprintf('[%s, %s]', app.getDefField(def,'minValue'), app.getDefField(def,'maxValue'))};
                case 'Calculator'
                    specs = {'LHS field', app.getDefField(def,'lhsField'); 'Operator', app.getDefField(def,'operator'); 'RHS fields', sprintf('%s %s %s', app.getDefField(def,'aField'), app.getDefField(def,'operator'), app.getDefField(def,'bField'))};
                case 'Constraint'
                    specs = {'Field', app.getDefField(def,'field'); 'Value', app.getDefField(def,'value'); 'Index', app.getDefField(def,'index')};
                otherwise
                    specs = {'Spec struct fields', app.formatSpecValue(fieldnames(def)')};
            end
        end

        function val = getDefField(app, def, fld, quantity)
            if nargin < 4
                quantity = '';
            end
            if isfield(def, fld)
                raw = def.(fld);
                if ~isempty(quantity)
                    raw = app.fromSI(raw, quantity);
                end
                val = app.formatSpecValue(raw);
            else
                val = '-';
            end
        end

        function txt = formatSpecValue(~, val)
            if ischar(val)
                txt = val;
            elseif isstring(val)
                txt = char(val);
            elseif isnumeric(val) || islogical(val)
                if isscalar(val)
                    txt = num2str(val);
                else
                    txt = mat2str(val);
                end
            elseif iscell(val)
                c = cell(size(val));
                for i = 1:numel(val)
                    c{i} = char(string(val{i}));
                end
                txt = ['{' strjoin(c, ', ') '}'];
            else
                txt = char(string(val));
            end
        end

        function valOut = toSI(app, valIn, quantity)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(app.unitPrefs.flow,'mol/s')
                        valOut = valIn / 1000;
                    end
                case 'temperature'
                    if strcmp(app.unitPrefs.temperature,'C')
                        valOut = valIn + 273.15;
                    end
                case 'pressure'
                    switch app.unitPrefs.pressure
                        case 'kPa', valOut = valIn * 1e3;
                        case 'bar', valOut = valIn * 1e5;
                    end
                case {'duty','power'}
                    unitName = app.unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn * 1e3;
                        case 'MW', valOut = valIn * 1e6;
                    end
            end
        end

        function valOut = fromSI(app, valIn, quantity)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(app.unitPrefs.flow,'mol/s')
                        valOut = valIn * 1000;
                    end
                case 'temperature'
                    if strcmp(app.unitPrefs.temperature,'C')
                        valOut = valIn - 273.15;
                    end
                case 'pressure'
                    switch app.unitPrefs.pressure
                        case 'kPa', valOut = valIn / 1e3;
                        case 'bar', valOut = valIn / 1e5;
                    end
                case {'duty','power'}
                    unitName = app.unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn / 1e3;
                        case 'MW', valOut = valIn / 1e6;
                    end
            end
        end

        function txt = unitLabel(app, quantity, base)
            switch quantity
                case 'flow', u = app.unitPrefs.flow;
                case 'temperature', u = app.unitPrefs.temperature;
                case 'pressure', u = app.unitPrefs.pressure;
                case 'duty', u = app.unitPrefs.duty;
                case 'power', u = app.unitPrefs.power;
                otherwise, u = '';
            end
            if isempty(u)
                txt = base;
            else
                txt = sprintf('%s (%s)', base, u);
            end
        end

        function T = convertDisplayStreamTable(app, T)
            if isempty(T)
                return;
            end
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                v = vars{i};
                if strcmp(v,'n_dot')
                    T.(v) = app.fromSI(T.(v), 'flow');
                elseif strcmp(v,'T')
                    T.(v) = app.fromSI(T.(v), 'temperature');
                elseif strcmp(v,'P')
                    T.(v) = app.fromSI(T.(v), 'pressure');
                end
            end
        end

        function names = displayColumnNames(app, names)
            for i = 1:numel(names)
                if strcmp(names{i},'n_dot')
                    names{i} = app.unitLabel('flow','n_dot');
                elseif strcmp(names{i},'T')
                    names{i} = app.unitLabel('temperature','T');
                elseif strcmp(names{i},'P')
                    names{i} = app.unitLabel('pressure','P');
                end
            end
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
            prefs = struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW');
            fns = fieldnames(prefs);
            for i = 1:numel(fns)
                f = fns{i};
                if isfield(inPrefs,f) && ~(isempty(inPrefs.(f)))
                    prefs.(f) = char(string(inPrefs.(f)));
                end
            end
        end

        function applyUnitPrefsToControls(app)
            if ~isempty(app.FlowUnitDropDown), app.FlowUnitDropDown.Value = app.unitPrefs.flow; end
            if ~isempty(app.TempUnitDropDown), app.TempUnitDropDown.Value = app.unitPrefs.temperature; end
            if ~isempty(app.PressureUnitDropDown), app.PressureUnitDropDown.Value = app.unitPrefs.pressure; end
            if ~isempty(app.DutyUnitDropDown), app.DutyUnitDropDown.Value = app.unitPrefs.duty; end
            if ~isempty(app.PowerUnitDropDown), app.PowerUnitDropDown.Value = app.unitPrefs.power; end
        end

        function openStreamTablePopup(app)
            if ~isempty(app.StreamTableFig) && isvalid(app.StreamTableFig)
                app.refreshStreamTablePopup();
                app.StreamTableFig.Visible = 'on';
                return;
            end

            app.StreamTableFig = uifigure('Name','MathLab — Solved Stream Table', ...
                'Position',[140 90 1060 560], 'Color',[0.97 0.97 0.98]);
            app.StreamTableFig.CloseRequestFcn = @(src,~) app.onStreamTablePopupClosed(src);

            gl = uigridlayout(app.StreamTableFig, [3 1], ...
                'RowHeight',{74,'1x',30}, 'Padding',[10 10 10 10], 'RowSpacing',6);

            topG = uigridlayout(gl, [2 6], 'ColumnWidth',{'fit',90,220,'fit','1x',100}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6, 'RowSpacing',4);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Solved Stream Table', 'FontWeight','bold', 'FontSize',13);
            uilabel(topG, 'Text','Format');
            app.StreamExportFormatDD = uidropdown(topG, 'Items', {'.mat','.csv'}, 'Value','.mat', ...
                'ValueChangedFcn', @(~,~) app.onStreamExportFormatChanged());
            uilabel(topG, 'Text','Filename');
            app.StreamExportFileField = uieditfield(topG,'text','Value',app.defaultStreamExportFilename('mat'));
            uibutton(topG, 'push', 'Text','Save', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.exportStreamTableFromPopup());

            uilabel(topG, 'Text','Destination');
            app.StreamExportPathField = uieditfield(topG,'text', ...
                'Value', app.resolveInitialExportPath(), 'Editable','off');
            uibutton(topG, 'push', 'Text','Choose...', ...
                'ButtonPushedFcn',@(~,~) app.chooseStreamExportPath());
            uilabel(topG, 'Text','');
            uilabel(topG, 'Text','');
            uibutton(topG, 'push', 'Text','Default Save Path', ...
                'ButtonPushedFcn',@(~,~) app.saveStreamTableWithDefaults());

            app.StreamTable = uitable(gl, 'ColumnEditable', false);
            app.StreamTable.Layout.Row = 2;

            app.StreamTableStatusLabel = uilabel(gl, 'Text','', 'FontColor',[0.3 0.3 0.3]);
            app.StreamTableStatusLabel.Layout.Row = 3;

            app.refreshStreamTablePopup();
        end

        function onStreamTablePopupClosed(app, src)
            if ~isempty(src) && isvalid(src)
                delete(src);
            end
            app.StreamTableFig = [];
            app.StreamTable = [];
            app.StreamTableStatusLabel = [];
            app.StreamExportFormatDD = [];
            app.StreamExportFileField = [];
            app.StreamExportPathField = [];
        end

        function refreshStreamTablePopup(app)
            if isempty(app.StreamTable) || ~isvalid(app.StreamTable)
                return;
            end
            T = app.buildDisplayStreamTable();
            app.StreamTable.Data = T;
            app.StreamTable.ColumnName = T.Properties.VariableNames;
            if isempty(app.lastSolver) || isempty(app.lastFlowsheet)
                msg = sprintf('Showing current stream state (%d row(s)). Run Solve for final solved table.', height(T));
            else
                msg = sprintf('Solved stream table (%d row(s)).', height(T));
            end
            if ~isempty(app.StreamTableStatusLabel) && isvalid(app.StreamTableStatusLabel)
                app.StreamTableStatusLabel.Text = msg;
            end
        end

        function T = buildDisplayStreamTable(app)
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
            T = app.convertDisplayStreamTable(T);
            T.Properties.VariableNames = app.displayColumnNames(T.Properties.VariableNames);
        end

        function fmt = normalizeStreamTableExportFormat(~, fmt)
            fmt = lower(strtrim(char(string(fmt))));
            if startsWith(fmt,'.')
                fmt = fmt(2:end);
            end
            if ~ismember(fmt, {'mat','csv'})
                error('MathLab:StreamTable:UnsupportedFormat', ...
                    'Unsupported stream table export format "%s". Use mat or csv.', fmt);
            end
        end

        function fname = defaultStreamExportFilename(app, fmt)
            fmt = app.normalizeStreamTableExportFormat(fmt);
            fname = app.autoFileName('stream_table', fmt);
        end

        function onStreamExportFormatChanged(app)
            if isempty(app.StreamExportFormatDD) || isempty(app.StreamExportFileField) ...
                    || ~isvalid(app.StreamExportFormatDD) || ~isvalid(app.StreamExportFileField)
                return;
            end
            fmt = app.normalizeStreamTableExportFormat(app.StreamExportFormatDD.Value);
            curr = strtrim(app.StreamExportFileField.Value);
            if isempty(curr)
                app.StreamExportFileField.Value = app.defaultStreamExportFilename(fmt);
                return;
            end
            [~, base, ext] = fileparts(curr);
            if isempty(base)
                base = 'stream_table';
            end
            if isempty(ext)
                app.StreamExportFileField.Value = sprintf('%s.%s', base, fmt);
            else
                app.StreamExportFileField.Value = sprintf('%s.%s', base, fmt);
            end
        end

        function chooseStreamExportPath(app)
            startPath = app.resolveInitialExportPath();
            sel = uigetdir(startPath, 'Choose Stream Table Export Folder');
            if isequal(sel, 0)
                return;
            end
            app.lastExportPath = char(string(sel));
            if ~isempty(app.StreamExportPathField) && isvalid(app.StreamExportPathField)
                app.StreamExportPathField.Value = app.lastExportPath;
            end
        end

        function exportStreamTableFromPopup(app)
            if isempty(app.StreamExportFormatDD) || ~isvalid(app.StreamExportFormatDD)
                return;
            end
            fmt = app.normalizeStreamTableExportFormat(app.StreamExportFormatDD.Value);
            folder = app.resolveInitialExportPath();
            if ~isempty(app.StreamExportPathField) && isvalid(app.StreamExportPathField)
                folder = strtrim(app.StreamExportPathField.Value);
            end
            if isempty(folder)
                folder = app.ensureOutputDir('results');
            end
            app.ensureWritableDir(folder);
            app.lastExportPath = char(string(folder));

            fname = '';
            if ~isempty(app.StreamExportFileField) && isvalid(app.StreamExportFileField)
                fname = strtrim(app.StreamExportFileField.Value);
            end
            if isempty(fname)
                fname = app.defaultStreamExportFilename(fmt);
            end
            [~, base, ext] = fileparts(fname);
            if isempty(base)
                base = 'stream_table';
            end
            if isempty(ext)
                fname = sprintf('%s.%s', base, fmt);
            else
                fname = sprintf('%s.%s', base, fmt);
            end

            T = app.buildDisplayStreamTable();
            filepath = fullfile(folder, fname);
            if strcmp(fmt,'csv')
                writetable(T, filepath);
            else
                streamTable = T; %#ok<NASGU>
                save(filepath, 'streamTable');
            end

            msg = sprintf('Stream table exported to %s', filepath);
            app.setStatus(msg);
            if ~isempty(app.StreamTableStatusLabel) && isvalid(app.StreamTableStatusLabel)
                app.StreamTableStatusLabel.Text = msg;
            end
        end

        function saveStreamTableWithDefaults(app)
            if isempty(app.StreamExportFormatDD) || ~isvalid(app.StreamExportFormatDD)
                return;
            end
            fmt = app.normalizeStreamTableExportFormat(app.StreamExportFormatDD.Value);
            app.lastExportPath = app.resolveInitialExportPath();
            if ~isempty(app.StreamExportPathField) && isvalid(app.StreamExportPathField)
                app.StreamExportPathField.Value = app.lastExportPath;
            end
            if ~isempty(app.StreamExportFileField) && isvalid(app.StreamExportFileField)
                app.StreamExportFileField.Value = app.defaultStreamExportFilename(fmt);
            end
            app.exportStreamTableFromPopup();
        end

        function pathOut = resolveInitialExportPath(app)
            pathOut = strtrim(char(string(app.lastExportPath)));
            if isempty(pathOut) || ~isfolder(pathOut)
                pathOut = app.ensureOutputDir('results');
                app.lastExportPath = pathOut;
            end
        end

        function fmt = normalizeUnitTableExportFormat(~, fmt)
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

        % Single export entry point for unit table exports (avoid duplicate methods during refactors).
        function exportUnitTableToOutput(app, fmt)
            fmt = app.normalizeUnitTableExportFormat(fmt);

            outDir = app.ensureOutputDir('results');
            outDirMsg = char(string(outDir));
            if isempty(strtrim(outDirMsg)) || ~isfolder(outDirMsg)
                reason = sprintf('Output directory is not valid: %s', outDirMsg);
                app.setStatus(sprintf('Unit table export failed: %s', reason));
                if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                    app.UnitTableStatusLabel.Text = sprintf('Unit table export failed: %s', reason);
                end
                uialert(app.Fig, sprintf(['Failed to export unit table.\nResolved output directory: %s\nReason: %s'], outDirMsg, reason), ...
                    'Unit Table Export Failed', 'Icon', 'error');
                return;
            end

            try
                T = app.buildUnitResultsTable();
                switch fmt
                    case 'csv'
                        filepath = fullfile(outDirMsg, app.autoFileName('unit_table', 'csv'));
                        writetable(T, filepath);
                    case 'mat'
                        filepath = fullfile(outDirMsg, app.autoFileName('unit_table', 'mat'));
                        unitTable = T; %#ok<NASGU>
                        save(filepath, 'unitTable');
                    otherwise
                        error('MathLab:UnitTable:UnsupportedFormat', ...
                            'Unsupported unit table export format "%s". Supported formats: csv, mat.', fmt);
                end
            catch ME
                reason = strtrim(ME.message);
                failMsg = sprintf('Unit table export failed: %s (output dir: %s)', reason, outDirMsg);
                app.setStatus(failMsg);
                if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                    app.UnitTableStatusLabel.Text = failMsg;
                end
                uialert(app.Fig, sprintf(['Failed to export unit table as %s.\nResolved output directory: %s\nReason: %s'], ...
                    upper(fmt), outDirMsg, reason), 'Unit Table Export Failed', 'Icon', 'error');
                return;
            end

            app.setStatus(sprintf('Unit table exported to %s (output dir: %s)', filepath, outDirMsg));
            if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                app.UnitTableStatusLabel.Text = sprintf('Exported %s (%d rows): %s [dir: %s]', upper(fmt), height(T), filepath, outDirMsg);
            end
        end

    end

    % =====================================================================
    %  SAVE / LOAD CONFIG
    % =====================================================================
    methods (Access = private)


        function dialogSplitter(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogSplitter(sNames, editIdx);
            app.syncStateToModel();
        end


        function dialogSource(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogSource(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogSink(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogSink(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogDesignSpec(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogDesignSpec(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogAdjust(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogAdjust(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogCalculator(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogCalculator(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogConstraint(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogConstraint(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogRecycle(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogRecycle(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogBypass(app, sNames, editIdx)
            app.syncModelToState();
            app.UnitsController.dialogBypass(sNames, editIdx);
            app.syncStateToModel();
        end

        function dialogManifold(app, sNames, editIdx)
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

        function loadConfigDialog(app)
            [file, path] = uigetfile('*.mat', 'Load Config');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            app.loadConfig(filepath);
            app.setStatus(sprintf('Config loaded from %s', filepath));
        end

        function saveConfig(app, filepath)
            % Serialize entire flowsheet state to a .mat file
            if ~(ischar(filepath) || isstring(filepath)) || strlength(string(filepath)) == 0
                error('MathLab:SaveConfig:InvalidPath', 'Config path must be a non-empty string.');
            end
            filepath = char(string(filepath));
            saveDir = fileparts(filepath);
            if isempty(saveDir)
                saveDir = pwd;
            end
            app.ensureWritableDir(saveDir);

            cfg = app.buildValidatedConfigPayload();
            save(filepath, '-struct', 'cfg');

            % Also generate a companion .m script
            mFile = strrep(filepath, '.mat', '_script.m');
            app.generateScript(mFile, cfg);
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
            u = [];
            p = inputParser;
            p.addParameter('includeIdentityLink', true, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            includeIdentityLink = p.Results.includeIdentityLink;
            switch def.type
                case 'Link'
                    if app.isIdentityLinkDef(def) && ~includeIdentityLink
                        return;
                    end
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Link(sIn, sOut);
                    end
                case 'Mixer'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = app.findStream(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sOut)
                        u = proc.units.Mixer(inS, sOut);
                    end
                case 'Reactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Reactor(sIn, sOut, def.reactions, def.conversion);
                    end
                case 'StoichiometricReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.StoichiometricReactor(sIn, sOut, def.nu, ...
                            'extent', def.extent, 'extentMode', def.extentMode, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'ConversionReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.ConversionReactor(sIn, sOut, def.nu, def.keySpecies, ...
                            def.conversion, 'conversionMode', def.conversionMode);
                    end
                case 'YieldReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.YieldReactor(sIn, sOut, def.basisSpecies, def.conversion, ...
                            def.productSpecies, def.productYields, 'conversionMode', def.conversionMode);
                    end
                case 'EquilibriumReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.EquilibriumReactor(sIn, sOut, def.nu, def.Keq, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'Separator'
                    sIn = app.findStream(def.inlet);
                    sA  = app.findStream(def.outletA);
                    sB  = app.findStream(def.outletB);
                    if ~isempty(sIn) && ~isempty(sA) && ~isempty(sB)
                        u = proc.units.Separator(sIn, sA, sB, def.phi);
                    end
                case 'Purge'
                    sIn  = app.findStream(def.inlet);
                    sRec = app.findStream(def.recycle);
                    sPur = app.findStream(def.purge);
                    if ~isempty(sIn) && ~isempty(sRec) && ~isempty(sPur)
                        u = proc.units.Purge(sIn, sRec, sPur, def.beta);
                    end
                case 'Splitter'
                    sIn = app.findStream(def.inlet);
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = app.findStream(def.outlets{k});
                        if isempty(s), return; end
                        outS{end+1} = s; %#ok
                    end
                    if ~isempty(sIn)
                        if isfield(def, 'splitFractions')
                            u = proc.units.Splitter(sIn, outS, 'fractions', def.splitFractions);
                        else
                            u = proc.units.Splitter(sIn, outS, 'flows', def.specifiedOutletFlows);
                        end
                    end
                case 'Recycle'
                    sSrc = app.findStream(def.source);
                    sTear = app.findStream(def.tear);
                    if ~isempty(sSrc) && ~isempty(sTear)
                        u = proc.units.Recycle(sSrc, sTear);
                    end
                case 'Bypass'
                    sIn = app.findStream(def.inlet);
                    sProcIn = app.findStream(def.processInlet);
                    sByp = app.findStream(def.bypassStream);
                    sRet = app.findStream(def.processReturn);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sProcIn) && ~isempty(sByp) && ~isempty(sRet) && ~isempty(sOut)
                        u = proc.units.Bypass(sIn, sProcIn, sByp, sRet, sOut, def.bypassFraction);
                    end
                case 'Manifold'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = app.findStream(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = app.findStream(def.outlets{k});
                        if isempty(s), return; end
                        outS{end+1} = s; %#ok
                    end
                    u = proc.units.Manifold(inS, outS, def.route);
                case 'Source'
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sOut)
                        opts = struct();
                        if isfield(def,'totalFlow'), opts.totalFlow = def.totalFlow; end
                        if isfield(def,'composition'), opts.composition = def.composition; end
                        if isfield(def,'componentFlows'), opts.componentFlows = def.componentFlows; end
                        u = proc.units.Source(sOut, opts);
                    end
                case 'Sink'
                    sIn = app.findStream(def.inlet);
                    if ~isempty(sIn), u = proc.units.Sink(sIn); end
                case 'DesignSpec'
                    s = app.findStream(def.stream);
                    if ~isempty(s)
                        u = proc.units.DesignSpec(s, def.metric, def.target, def.componentIndex);
                    end
                case 'Adjust'
                    if isfield(def,'designSpecIndex') && isfield(def,'ownerIndex') && ...
                            def.designSpecIndex <= numel(app.units) && def.ownerIndex <= numel(app.units)
                        ds = app.units{def.designSpecIndex};
                        owner = app.units{def.ownerIndex};
                        u = proc.units.Adjust(ds, owner, def.field, def.index, def.minValue, def.maxValue);
                    end
                case 'Calculator'
                    lhs = app.findStream(def.lhsStream);
                    a = app.findStream(def.aStream);
                    b = app.findStream(def.bStream);
                    if ~isempty(lhs) && ~isempty(a) && ~isempty(b)
                        u = proc.units.Calculator(lhs, def.lhsField, a, def.aField, def.operator, b, def.bField);
                    end
                case 'Constraint'
                    s = app.findStream(def.stream);
                    if ~isempty(s)
                        u = proc.units.Constraint(s, def.field, def.value, def.index);
                    end
                case 'Heater'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Heater(sIn, sOut, mix, args{:});
                    end
                case 'Cooler'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Cooler(sIn, sOut, mix, args{:});
                    end
                case 'HeatExchanger'
                    hIn = app.findStream(def.hotInlet);
                    hOut = app.findStream(def.hotOutlet);
                    cIn = app.findStream(def.coldInlet);
                    cOut = app.findStream(def.coldOutlet);
                    if ~isempty(hIn) && ~isempty(hOut) && ~isempty(cIn) && ~isempty(cOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                        if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        u = proc.units.HeatExchanger(hIn, hOut, cIn, cOut, mix, args{:});
                    end
                case 'Compressor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Compressor(sIn, sOut, mix, args{:});
                    end
                case 'Turbine'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Turbine(sIn, sOut, mix, args{:});
                    end
            end
        end

        function generateScript(~, filepath, cfg)
            % Write a human-readable .m script that recreates the flowsheet
            fid = fopen(filepath, 'w');
            if fid < 0, return; end

            fprintf(fid, '%%%% MathLab Config Script (auto-generated)\n');
            fprintf(fid, '%% Run this to recreate the flowsheet and solve.\n');
            fprintf(fid, '%% You can also use: [T, solver] = runFromConfig(''%s'');\n\n', ...
                strrep(filepath,'_script.m','.mat'));
            fprintf(fid, 'clear; clc;\n\n');

            % Species
            fprintf(fid, 'species = {');
            for i = 1:numel(cfg.speciesNames)
                if i>1, fprintf(fid, ', '); end
                fprintf(fid, '''%s''', cfg.speciesNames{i});
            end
            fprintf(fid, '};\n');
            fprintf(fid, 'fs = proc.Flowsheet(species);\n\n');

            % Streams
            fprintf(fid, '%% --- Streams ---\n');
            for i = 1:numel(cfg.streams)
                sd = cfg.streams(i);
                fprintf(fid, '%s = proc.Stream("%s", species);\n', sd.name, sd.name);
                fprintf(fid, '%s.n_dot = %.6g; %s.T = %.6g; %s.P = %.6g;\n', ...
                    sd.name, sd.n_dot, sd.name, sd.T, sd.name, sd.P);
                fprintf(fid, '%s.y = %s;\n', sd.name, mat2str(sd.y, 8));
                if sd.known_n_dot, fprintf(fid, '%s.known.n_dot = true;\n', sd.name); end
                if sd.known_T,     fprintf(fid, '%s.known.T = true;\n', sd.name); end
                if sd.known_P,     fprintf(fid, '%s.known.P = true;\n', sd.name); end
                if all(sd.known_y), fprintf(fid, '%s.known.y(:) = true;\n', sd.name); end
                fprintf(fid, 'fs.addStream(%s);\n\n', sd.name);
            end

            % Units
            if isfield(cfg,'unitDefs') && ~isempty(cfg.unitDefs)
                fprintf(fid, '%% --- Units ---\n');
                for i = 1:numel(cfg.unitDefs)
                    def = cfg.unitDefs{i};
                    switch def.type
                        case 'Link'
                            isIdentityLink = false;
                            if isfield(def, 'mode')
                                isIdentityLink = strcmp(def.mode, 'identity');
                            end
                            if isfield(def, 'isIdentity')
                                isIdentityLink = logical(def.isIdentity);
                            end
                            if ~isIdentityLink
                                fprintf(fid, 'fs.addUnit(proc.units.Link(%s, %s));\n', def.inlet, def.outlet);
                            end
                        case 'Mixer'
                            inStr = strjoin(cellfun(@(n) n, def.inlets, 'Uni',false), ', ');
                            fprintf(fid, 'fs.addUnit(proc.units.Mixer({%s}, %s));\n', inStr, def.outlet);
                        case 'Reactor'
                            fprintf(fid, 'rxn.reactants = %s;\n', mat2str(def.reactions.reactants));
                            fprintf(fid, 'rxn.products = %s;\n', mat2str(def.reactions.products));
                            fprintf(fid, 'rxn.stoich = %s;\n', mat2str(def.reactions.stoich));
                            fprintf(fid, 'rxn.name = "%s";\n', def.reactions.name);
                            fprintf(fid, 'fs.addUnit(proc.units.Reactor(%s, %s, rxn, %.4g));\n', ...
                                def.inlet, def.outlet, def.conversion);
                        case 'StoichiometricReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.StoichiometricReactor(%s, %s, %s, ''extent'', %.6g, ''extentMode'', ''%s'', ''referenceSpecies'', %d));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.extent, def.extentMode, def.referenceSpecies);
                        case 'ConversionReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.ConversionReactor(%s, %s, %s, %d, %.6g, ''conversionMode'', ''%s''));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.keySpecies, def.conversion, def.conversionMode);
                        case 'YieldReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.YieldReactor(%s, %s, %d, %.6g, %s, %s, ''conversionMode'', ''%s''));\n', ...
                                def.inlet, def.outlet, def.basisSpecies, def.conversion, mat2str(def.productSpecies), mat2str(def.productYields), def.conversionMode);
                        case 'EquilibriumReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.EquilibriumReactor(%s, %s, %s, %.6g, ''referenceSpecies'', %d));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.Keq, def.referenceSpecies);
                        case 'Separator'
                            fprintf(fid, 'fs.addUnit(proc.units.Separator(%s, %s, %s, %s));\n', ...
                                def.inlet, def.outletA, def.outletB, mat2str(def.phi,6));
                        case 'Purge'
                            fprintf(fid, 'fs.addUnit(proc.units.Purge(%s, %s, %s, %.4g));\n', ...
                                def.inlet, def.recycle, def.purge, def.beta);
                        case 'Splitter'
                            outStr = strjoin(cellfun(@(n) n, def.outlets, 'Uni',false), ', ');
                            if isfield(def, 'splitFractions')
                                fprintf(fid, 'fs.addUnit(proc.units.Splitter(%s, {%s}, ''fractions'', %s));\n', ...
                                    def.inlet, outStr, mat2str(def.splitFractions,6));
                            else
                                fprintf(fid, 'fs.addUnit(proc.units.Splitter(%s, {%s}, ''flows'', %s));\n', ...
                                    def.inlet, outStr, mat2str(def.specifiedOutletFlows,6));
                            end
                        case 'Recycle'
                            fprintf(fid, 'fs.addUnit(proc.units.Recycle(%s, %s));\n', def.source, def.tear);
                        case 'Bypass'
                            fprintf(fid, 'fs.addUnit(proc.units.Bypass(%s, %s, %s, %s, %s, %.4g));\n', ...
                                def.inlet, def.processInlet, def.bypassStream, def.processReturn, def.outlet, def.bypassFraction);
                        case 'Manifold'
                            inStr = strjoin(cellfun(@(n) n, def.inlets, 'Uni',false), ', ');
                            outStr = strjoin(cellfun(@(n) n, def.outlets, 'Uni',false), ', ');
                            fprintf(fid, 'fs.addUnit(proc.units.Manifold({%s}, {%s}, %s));\n', ...
                                inStr, outStr, mat2str(def.route));
                        case 'Source'
                            fprintf(fid, 'srcOpts = struct(''totalFlow'', %.6g, ''composition'', %s, ''componentFlows'', %s);\n', ...
                                def.totalFlow, mat2str(def.composition,6), mat2str(def.componentFlows,6));
                            fprintf(fid, 'fs.addUnit(proc.units.Source(%s, srcOpts));\n', def.outlet);
                        case 'Sink'
                            fprintf(fid, 'fs.addUnit(proc.units.Sink(%s));\n', def.inlet);
                        case 'DesignSpec'
                            fprintf(fid, 'fs.addUnit(proc.units.DesignSpec(%s, ''%s'', %.6g, %d));\n', ...
                                def.stream, def.metric, def.target, def.componentIndex);
                        case 'Calculator'
                            fprintf(fid, 'fs.addUnit(proc.units.Calculator(%s, ''%s'', %s, ''%s'', ''%s'', %s, ''%s''));\n', ...
                                def.lhsStream, def.lhsField, def.aStream, def.aField, def.operator, def.bStream, def.bField);
                        case 'Constraint'
                            fprintf(fid, 'fs.addUnit(proc.units.Constraint(%s, ''%s'', %.6g, %.6g));\n', ...
                                def.stream, def.field, def.value, def.index);
                        case 'Heater'
                            fprintf(fid, 'thermoLib = proc.thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = proc.thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Tout'), args = [args, sprintf(', ''Tout'', %.6g', def.Tout)]; end
                            if isfield(def,'duty'), args = [args, sprintf(', ''duty'', %.6g', def.duty)]; end
                            if isfield(def,'dP'), args = [args, sprintf(', ''dP'', %.6g', def.dP)]; end
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Heater(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'Cooler'
                            fprintf(fid, 'thermoLib = proc.thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = proc.thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Tout'), args = [args, sprintf(', ''Tout'', %.6g', def.Tout)]; end
                            if isfield(def,'duty'), args = [args, sprintf(', ''duty'', %.6g', def.duty)]; end
                            if isfield(def,'dP'), args = [args, sprintf(', ''dP'', %.6g', def.dP)]; end
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Cooler(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'HeatExchanger'
                            fprintf(fid, 'thermoLib = proc.thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = proc.thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Th_out'), args = sprintf(', ''Th_out'', %.6g', def.Th_out); end
                            if isfield(def,'Tc_out'), args = sprintf(', ''Tc_out'', %.6g', def.Tc_out); end
                            if isfield(def,'duty'), args = sprintf(', ''duty'', %.6g', def.duty); end
                            fprintf(fid, 'fs.addUnit(proc.units.HeatExchanger(%s, %s, %s, %s, mix%s));\n', ...
                                def.hotInlet, def.hotOutlet, def.coldInlet, def.coldOutlet, args);
                        case 'Compressor'
                            fprintf(fid, 'thermoLib = proc.thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = proc.thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            if isfield(def,'eta'), args = [args, sprintf(', ''eta'', %.6g', def.eta)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Compressor(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'Turbine'
                            fprintf(fid, 'thermoLib = proc.thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = proc.thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            if isfield(def,'eta'), args = [args, sprintf(', ''eta'', %.6g', def.eta)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Turbine(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                    end
                end
            end

            fprintf(fid, '\n%% --- Solve ---\n');
            fprintf(fid, 'solver = fs.solve(''maxIter'', %d, ''tolAbs'', %.2e, ''verbose'', true);\n', ...
                cfg.maxIter, cfg.tolAbs);
            fprintf(fid, 'T = fs.streamTable();\n');
            fprintf(fid, 'disp(T);\n');

            fclose(fid);
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
        function [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(app, unitDefs)
            aliasByOutlet = containers.Map('KeyType','char','ValueType','char');
            resolvedDefs = cell(size(unitDefs));
            for i = 1:numel(unitDefs)
                def = unitDefs{i};
                if ~isstruct(def)
                    resolvedDefs{i} = def;
                    continue;
                end
                def = app.rewriteDefStreams(def, aliasByOutlet);
                if strcmp(def.type, 'Link') && app.isIdentityLinkDef(def)
                    inletRoot = app.resolveAliasName(def.inlet, aliasByOutlet);
                    aliasByOutlet(char(def.outlet)) = inletRoot;
                    continue;
                end
                resolvedDefs{i} = def;
            end
            resolvedDefs = resolvedDefs(~cellfun(@isempty, resolvedDefs));
        end

        function def = rewriteDefStreams(app, def, aliasByOutlet)
            fnSingles = {'inlet','source','stream','tear','processInlet','bypassStream','processReturn', ...
                'lhsStream','aStream','bStream','recycle','purge','outlet','outletA','outletB', ...
                'hotInlet','hotOutlet','coldInlet','coldOutlet'};
            for i = 1:numel(fnSingles)
                f = fnSingles{i};
                if ~isfield(def, f)
                    continue;
                end
                if strcmp(f, 'outlet') && strcmp(def.type, 'Link') && app.isIdentityLinkDef(def)
                    continue;
                end
                def.(f) = app.resolveAliasName(def.(f), aliasByOutlet);
            end
            if isfield(def, 'inlets')
                for k = 1:numel(def.inlets)
                    def.inlets{k} = app.resolveAliasName(def.inlets{k}, aliasByOutlet);
                end
            end
            if isfield(def, 'outlets')
                for k = 1:numel(def.outlets)
                    def.outlets{k} = app.resolveAliasName(def.outlets{k}, aliasByOutlet);
                end
            end
        end

        function addStreamAliasesToFlowsheet(app, fs, aliasByOutlet)
            if isempty(aliasByOutlet)
                return;
            end
            keys = aliasByOutlet.keys;
            for i = 1:numel(keys)
                aliasName = keys{i};
                targetName = aliasByOutlet(aliasName);
                s = app.findStream(targetName);
                if ~isempty(s)
                    fs.addAlias(aliasName, s);
                end
            end
        end

        function tf = isIdentityLinkDef(~, def)
            tf = strcmp(def.type, 'Link') && isfield(def, 'mode') && strcmp(def.mode, 'identity');
            if isfield(def, 'isIdentity')
                tf = logical(def.isIdentity);
            end
        end

        function outName = resolveAliasName(~, name, aliasByOutlet)
            outName = char(string(name));
            visited = containers.Map('KeyType','char','ValueType','logical');
            while isKey(aliasByOutlet, outName)
                if isKey(visited, outName)
                    break;
                end
                visited(outName) = true;
                outName = aliasByOutlet(outName);
            end
        end

        function mix = buildThermoMixForGUI(app)
            % Build an IdealGasMixture from the current species list.
            % Returns [] if any species is missing from the thermo library.
            try
                lib = proc.thermo.ThermoLibrary();
                mix = proc.thermo.IdealGasMixture(app.speciesNames, lib);
            catch
                mix = [];
            end
        end

        function names = getStreamNames(app)
            names = cellfun(@(s) char(string(s.name)), app.streams, 'Uni', false);
        end

        function s = findStream(app, name)
            s = [];
            for i = 1:numel(app.streams)
                if strcmp(char(string(app.streams{i}.name)), char(name))
                    s = app.streams{i}; return;
                end
            end
        end

        function nm = shortTypeName(app, u)
            cn = class(u);
            parts = strsplit(cn,'.');
            nm = app.prettyUnitTypeName(parts{end});
        end

        function label = prettyUnitTypeName(app, type)
            catalog = app.unitTypeCatalog();
            idx = find(strcmp({catalog.type}, char(string(type))), 1);
            if isempty(idx)
                label = char(string(type));
            else
                label = catalog(idx).label;
            end
        end

        function catalog = unitTypeCatalog(~)
            catalog = struct( ...
                'type', {'Mixer','Link','Reactor','StoichiometricReactor','ConversionReactor','YieldReactor','EquilibriumReactor', ...
                         'Heater','Cooler','HeatExchanger','Compressor','Turbine','Separator','Purge','Splitter','Recycle', ...
                         'Bypass','Manifold','Source','Sink','DesignSpec','Adjust','Calculator','Constraint'}, ...
                'label', {'Mixer','Stream Link','Generic Reactor','Stoichiometric Reactor','Conversion Reactor','Yield Reactor','Equilibrium Reactor', ...
                          'Heater','Cooler','Heat Exchanger','Compressor','Turbine','Separator','Purge Split','Flow Splitter','Recycle Connection', ...
                          'Bypass Network','Routing Manifold','Feed Source','Product Sink','Design Specification','Adjust Controller','Stream Calculator','Fixed Constraint'}, ...
                'description', {'Combines multiple inlet streams into one outlet stream.', ...
                                'Copies one stream state directly to another stream.', ...
                                'Single-reaction conversion reactor using reactant/product index lists.', ...
                                'Applies a stoichiometric reaction with fixed or solved extent.', ...
                                'Applies stoichiometric conversion based on a key species.', ...
                                'Converts a basis species and distributes products using yield factors.', ...
                                'Solves a stoichiometric reaction at specified equilibrium constant K.', ...
                                'Adds heat to a process stream with optional pressure specification.', ...
                                'Removes heat from a process stream with optional pressure specification.', ...
                                'Transfers heat between hot and cold streams using one thermal spec.', ...
                                'Raises pressure and estimates shaft power from efficiency.', ...
                                'Drops pressure and estimates shaft power recovery from efficiency.', ...
                                'Splits species between two outlets using per-species split fractions.', ...
                                'Splits one stream into recycle and purge branches by recycle fraction.', ...
                                'Splits one stream into multiple outlets by fractions or outlet flows.', ...
                                'Defines recycle source and tear streams for convergence handling.', ...
                                'Routes a feed around a process path and recombines both paths.', ...
                                'Routes selected inlet streams to specified outlet streams.', ...
                                'Applies fixed feed conditions to an outlet stream.', ...
                                'Terminal unit that consumes an inlet stream.', ...
                                'Defines a measurable target used by controller-style units.', ...
                                'Adjusts a unit parameter so a linked design specification is met.', ...
                                'Sets one stream field from arithmetic on two other stream fields.', ...
                                'Fixes a stream field value directly (optionally at one index).'});
        end

        function cfg = buildValidatedConfigPayload(app)
            cfg = struct();
            cfg.speciesNames = app.speciesNames;
            cfg.speciesMW    = app.speciesMW;

            % Serialize streams
            N = numel(app.streams);
            if N == 0
                streamData = struct('name', {}, 'n_dot', {}, 'T', {}, 'P', {}, 'y', {}, ...
                    'known_n_dot', {}, 'known_T', {}, 'known_P', {}, 'known_y', {});
            else
                streamData = repmat(struct('name', '', 'n_dot', NaN, 'T', NaN, 'P', NaN, 'y', [], ...
                    'known_n_dot', false, 'known_T', false, 'known_P', false, 'known_y', false), 1, N);
            end
            for i = 1:N
                s = app.streams{i};
                sd = struct();
                sd.name  = char(string(s.name));
                sd.n_dot = s.n_dot;
                sd.T     = s.T;
                sd.P     = s.P;
                sd.y     = s.y;
                sd.known_n_dot = s.known.n_dot;
                sd.known_T     = s.known.T;
                sd.known_P     = s.known.P;
                sd.known_y     = s.known.y;
                streamData(i) = sd;
            end
            cfg.streams = streamData;

            % Serialize unit definitions (not the objects themselves)
            cfg.unitDefs = app.unitDefs;

            % Solver settings
            cfg.maxIter = app.MaxIterField.Value;
            cfg.tolAbs  = app.TolField.Value;

            % Project title
            cfg.projectTitle = app.projectTitle;
            cfg.unitPrefs = app.unitPrefs;
            cfg.lastExportPath = app.lastExportPath;

            app.validateConfigPayload(cfg);
        end

        function validateConfigPayload(~, cfg)
            requiredTop = {'speciesNames','speciesMW','streams','unitDefs','maxIter','tolAbs','projectTitle','unitPrefs','lastExportPath'};
            for i = 1:numel(requiredTop)
                key = requiredTop{i};
                if ~isfield(cfg, key)
                    error('MathLab:SaveConfig:MissingField', 'Config payload missing required field "%s".', key);
                end
            end

            if ~iscell(cfg.speciesNames) || isempty(cfg.speciesNames)
                error('MathLab:SaveConfig:InvalidSpecies', 'speciesNames must be a non-empty cell array.');
            end
            if ~isnumeric(cfg.speciesMW) || numel(cfg.speciesMW) ~= numel(cfg.speciesNames)
                error('MathLab:SaveConfig:InvalidSpecies', 'speciesMW must be numeric and match speciesNames length.');
            end

            if ~isstruct(cfg.streams)
                error('MathLab:SaveConfig:InvalidStreams', 'streams must be a struct array.');
            end
            streamRequired = {'name','n_dot','T','P','y','known_n_dot','known_T','known_P','known_y'};
            for i = 1:numel(cfg.streams)
                for k = 1:numel(streamRequired)
                    f = streamRequired{k};
                    if ~isfield(cfg.streams(i), f)
                        error('MathLab:SaveConfig:InvalidStreams', ...
                            'Stream %d missing required field "%s".', i, f);
                    end
                end
            end

            if ~iscell(cfg.unitDefs)
                error('MathLab:SaveConfig:InvalidUnits', 'unitDefs must be a cell array.');
            end
            if any(~cellfun(@isstruct, cfg.unitDefs))
                error('MathLab:SaveConfig:InvalidUnits', 'unitDefs entries must be structs.');
            end

            if ~isscalar(cfg.maxIter) || ~isfinite(cfg.maxIter) || cfg.maxIter <= 0
                error('MathLab:SaveConfig:InvalidSolver', 'maxIter must be a finite positive scalar.');
            end
            if ~isscalar(cfg.tolAbs) || ~isfinite(cfg.tolAbs) || cfg.tolAbs <= 0
                error('MathLab:SaveConfig:InvalidSolver', 'tolAbs must be a finite positive scalar.');
            end

            if ~isstruct(cfg.unitPrefs)
                error('MathLab:SaveConfig:InvalidUnits', 'unitPrefs must be a struct.');
            end
            if ~(ischar(cfg.lastExportPath) || (isstring(cfg.lastExportPath) && isscalar(cfg.lastExportPath)))
                error('MathLab:SaveConfig:InvalidPath', 'lastExportPath must be a text scalar.');
            end
        end

        function ensureWritableDir(~, dirPath)
            if ~(ischar(dirPath) || isstring(dirPath)) || strlength(string(dirPath)) == 0
                error('MathLab:SaveConfig:InvalidPath', 'Output directory path must be a non-empty string.');
            end
            dirPath = char(string(dirPath));
            if ~exist(dirPath, 'dir')
                [ok,msg] = mkdir(dirPath);
                if ~ok
                    error('MathLab:SaveConfig:CreateDirFailed', ...
                        'Could not create output directory "%s": %s', dirPath, msg);
                end
            end
            if ~isfolder(dirPath)
                error('MathLab:SaveConfig:InvalidPath', 'Output directory path is not a folder: %s', dirPath);
            end
            [fid,msg] = fopen(fullfile(dirPath, '.mathlab_write_test.tmp'), 'w');
            if fid < 0
                error('MathLab:SaveConfig:WritePermission', ...
                    'Directory is not writable "%s": %s', dirPath, msg);
            end
            fclose(fid);
            delete(fullfile(dirPath, '.mathlab_write_test.tmp'));
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
            % Ensure output/<subfolder> exists and return the path
            baseDir = fullfile(pwd, 'output');
            if ~exist(baseDir, 'dir')
                [ok,msg] = mkdir(baseDir);
                if ~ok
                    error('MathLab:OutputDir:CreateFailed', ...
                        'Failed to create output directory "%s": %s', baseDir, msg);
                end
            end
            dirPath = fullfile(baseDir, subfolder);
            if ~exist(dirPath, 'dir')
                [ok,msg] = mkdir(dirPath);
                if ~ok
                    error('MathLab:OutputDir:CreateFailed', ...
                        'Failed to create output subdirectory "%s": %s', dirPath, msg);
                end
            end
            if ~isfolder(dirPath)
                error('MathLab:OutputDir:InvalidPath', 'Output path is not a directory: %s', dirPath);
            end
        end

        function fname = autoFileName(app, prefix, ext)
            % Generate filename: <ProjectTitle>_<prefix>_YYYYMMDD_HHMMSS.<ext>
            safeTitle = regexprep(app.projectTitle, '[^A-Za-z0-9_-]', '_');
            stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok
            fname = sprintf('%s_%s_%s.%s', safeTitle, prefix, stamp, ext);
        end

        function writeErrorLog(app, prefix, logLines)
            % Write error log to output/logs
            try
                logDir = app.ensureOutputDir('logs');
                fname = app.autoFileName(prefix, 'txt');
                fpath = fullfile(logDir, fname);
                fid = fopen(fpath, 'w');
                if fid >= 0
                    for k = 1:numel(logLines)
                        fprintf(fid, '%s\n', logLines{k});
                    end
                    fclose(fid);
                end
            catch
                % Silently ignore logging failures
            end
        end
    end
end
