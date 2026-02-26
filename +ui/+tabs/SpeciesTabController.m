classdef SpeciesTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = SpeciesTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function refreshSpeciesTable(obj, speciesTable)
            N = numel(obj.State.speciesNames);
            data = cell(N, 2);
            for i = 1:N
                data{i,1} = obj.State.speciesNames{i};
                data{i,2} = obj.State.speciesMW(i);
            end
            speciesTable.Data = data;
        end

        function onSpeciesTableEdit(obj, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            if r < 1 || r > numel(obj.State.speciesNames), return; end
            if c == 1
                obj.State.speciesNames{r} = evt.NewData;
            elseif c == 2
                obj.State.speciesMW(r) = evt.NewData;
            end
        end

        function addSpeciesRow(obj, nameField, mwField, speciesTable)
            nm = strtrim(nameField.Value);
            if isempty(nm), return; end
            obj.State.speciesNames{end+1} = nm;
            obj.State.speciesMW(end+1) = mwField.Value;
            nameField.Value = '';
            obj.refreshSpeciesTable(speciesTable);
        end

        function removeSpeciesRow(obj, speciesTable)
            sel = speciesTable.Selection;
            if isempty(sel), return; end
            r = sel(1);
            if r >= 1 && r <= numel(obj.State.speciesNames)
                obj.State.speciesNames(r) = [];
                obj.State.speciesMW(r) = [];
                obj.refreshSpeciesTable(speciesTable);
            end
        end

        function applySpecies(obj)
            if isempty(obj.State.speciesNames)
                obj.Services.alertError('Species list cannot be empty.');
                return;
            end

            obj.State.streams = {};
            obj.State.units = {};
            obj.State.unitDefs = {};
            obj.State.lastSolver = [];

            obj.Services.addStreamInternal('Feed');
            s = obj.State.streams{1};
            s.n_dot = 10;
            s.T = 300;
            s.P = 1e5;
            ns = numel(obj.State.speciesNames);
            y0 = zeros(1, ns);
            y0(1) = 1;
            s.y = y0;
            s.known.n_dot = true;
            s.known.T = true;
            s.known.P = true;
            s.known.y(:) = true;

            obj.Services.refreshStreamTables();
            obj.Services.refreshUnitsListBox();
            obj.Services.refreshFlowsheetDiagram();
            obj.Services.updateDOF();
            obj.Services.refreshUnitTablePopup();
            obj.Services.refreshStreamTablePopup();
            obj.Services.refreshResultsTablesTab();
            obj.Services.updateSensDropdowns();
            obj.Services.refreshSpeciesPropsTable();
            obj.Services.setNextStreamName('S2');
            obj.Services.setStatus(sprintf('Species set: {%s}. Feed created.', ...
                strjoin(obj.State.speciesNames, ', ')));
        end
    end
end
