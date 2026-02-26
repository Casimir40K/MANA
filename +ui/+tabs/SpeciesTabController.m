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
            if isfield(obj.Services, 'applySpeciesReset')
                obj.Services.applySpeciesReset();
            end
        end
    end
end
