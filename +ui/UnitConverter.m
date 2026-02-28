classdef UnitConverter
    %UNITCONVERTER  Static helpers for SI <-> display-unit conversion.
    %
    %   All methods are static and take a unitPrefs struct as the first
    %   argument so that the class carries no mutable state.

    methods (Static)

        function valOut = toSI(valIn, quantity, unitPrefs)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(unitPrefs.flow,'mol/s')
                        valOut = valIn / 1000;
                    end
                case 'temperature'
                    if strcmp(unitPrefs.temperature,'C')
                        valOut = valIn + 273.15;
                    end
                case 'pressure'
                    switch unitPrefs.pressure
                        case 'kPa', valOut = valIn * 1e3;
                        case 'bar', valOut = valIn * 1e5;
                    end
                case {'duty','power'}
                    unitName = unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn * 1e3;
                        case 'MW', valOut = valIn * 1e6;
                    end
            end
        end

        function valOut = fromSI(valIn, quantity, unitPrefs)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(unitPrefs.flow,'mol/s')
                        valOut = valIn * 1000;
                    end
                case 'temperature'
                    if strcmp(unitPrefs.temperature,'C')
                        valOut = valIn - 273.15;
                    end
                case 'pressure'
                    switch unitPrefs.pressure
                        case 'kPa', valOut = valIn / 1e3;
                        case 'bar', valOut = valIn / 1e5;
                    end
                case {'duty','power'}
                    unitName = unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn / 1e3;
                        case 'MW', valOut = valIn / 1e6;
                    end
            end
        end

        function txt = unitLabel(quantity, base, unitPrefs)
            switch quantity
                case 'flow',        u = unitPrefs.flow;
                case 'temperature', u = unitPrefs.temperature;
                case 'pressure',    u = unitPrefs.pressure;
                case 'duty',        u = unitPrefs.duty;
                case 'power',       u = unitPrefs.power;
                otherwise,          u = '';
            end
            if isempty(u)
                txt = base;
            else
                txt = sprintf('%s (%s)', base, u);
            end
        end

        function T = convertDisplayStreamTable(T, unitPrefs)
            if isempty(T)
                return;
            end
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                v = vars{i};
                if strcmp(v,'n_dot')
                    T.(v) = ui.UnitConverter.fromSI(T.(v), 'flow', unitPrefs);
                elseif strcmp(v,'T')
                    T.(v) = ui.UnitConverter.fromSI(T.(v), 'temperature', unitPrefs);
                elseif strcmp(v,'P')
                    T.(v) = ui.UnitConverter.fromSI(T.(v), 'pressure', unitPrefs);
                end
            end
        end

        function names = displayColumnNames(names, unitPrefs)
            for i = 1:numel(names)
                if strcmp(names{i},'n_dot')
                    names{i} = ui.UnitConverter.unitLabel('flow','n_dot', unitPrefs);
                elseif strcmp(names{i},'T')
                    names{i} = ui.UnitConverter.unitLabel('temperature','T', unitPrefs);
                elseif strcmp(names{i},'P')
                    names{i} = ui.UnitConverter.unitLabel('pressure','P', unitPrefs);
                end
            end
        end

        function prefs = mergeUnitPrefs(inPrefs)
            prefs = struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW');
            fns = fieldnames(prefs);
            for i = 1:numel(fns)
                f = fns{i};
                if isfield(inPrefs,f) && ~(isempty(inPrefs.(f)))
                    prefs.(f) = char(string(inPrefs.(f)));
                end
            end
        end
    end
end
