classdef ThermoLibrary < handle
    %THERMOLIBRARY Species thermodynamic data registry.
    %   Loads species Shomate data from a JSON file and provides lookup.
    %
    %   Usage:
    %     lib = proc.thermo.ThermoLibrary();                    % default library
    %     lib = proc.thermo.ThermoLibrary('path/to/species.json');
    %     sp  = lib.get('N2');                              % returns ShomateSpecies

    properties
        speciesMap  containers.Map    % name -> ShomateSpecies
        dataFile    string = ""
    end

    methods
        function obj = ThermoLibrary(jsonPath)
            %THERMOLIBRARY Load species data from JSON file.
            obj.speciesMap = containers.Map('KeyType','char','ValueType','any');
            if nargin < 1 || isempty(jsonPath)
                % Default: library/thermo/species_shomate.json relative to project
                % File is at +proc/+thermo/ThermoLibrary.m, so 3 levels up to reach root
                root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
                jsonPath = fullfile(root, 'library', 'thermo', 'species_shomate.json');
            end
            obj.dataFile = string(jsonPath);
            if isfile(jsonPath)
                obj.loadJSON(jsonPath);
            else
                warning('proc.thermo:noLibrary', 'Species library not found: %s', jsonPath);
            end
        end

        function sp = get(obj, name)
            %GET Retrieve ShomateSpecies by name. Errors if not found.
            key = char(name);
            if obj.speciesMap.isKey(key)
                sp = obj.speciesMap(key);
            else
                error('proc.thermo:speciesNotFound', ...
                    'Species "%s" not found in thermo library. Available: %s', ...
                    key, strjoin(obj.speciesMap.keys(), ', '));
            end
        end

        function tf = hasSpecies(obj, name)
            tf = obj.speciesMap.isKey(char(name));
        end

        function names = listSpecies(obj)
            names = obj.speciesMap.keys();
        end

        function addSpecies(obj, sp)
            %ADDSPECIES Register a ShomateSpecies object.
            obj.speciesMap(char(sp.name)) = sp;
        end

        function saveJSON(obj, jsonPath)
            %SAVEJSON Write current library to JSON file.
            if nargin < 2, jsonPath = char(obj.dataFile); end
            keys = obj.speciesMap.keys();
            data = struct('species', {{}});
            for i = 1:numel(keys)
                sp = obj.speciesMap(keys{i});
                entry = struct();
                entry.name = char(sp.name);
                entry.formula = char(sp.formula);
                entry.MW = sp.MW;
                entry.Hf298_kJkmol = sp.Hf298_kJkmol;
                entry.S298_kJkmolK = sp.S298_kJkmolK;
                entry.source = char(sp.source);
                entry.notes = char(sp.notes);

                % Phase change (future)
                entry.phase_change = sp.phase_change;

                % Ranges
                entry.shomate_ranges = struct([]);
                for r = 1:numel(sp.ranges)
                    rng = sp.ranges(r);
                    entry.shomate_ranges(r).Tmin = rng.Tmin;
                    entry.shomate_ranges(r).Tmax = rng.Tmax;
                    entry.shomate_ranges(r).A = rng.A;
                    entry.shomate_ranges(r).B = rng.B;
                    entry.shomate_ranges(r).C = rng.C;
                    entry.shomate_ranges(r).D = rng.D;
                    entry.shomate_ranges(r).E = rng.E;
                    entry.shomate_ranges(r).F = rng.F;
                    entry.shomate_ranges(r).G = rng.G;
                    entry.shomate_ranges(r).H = rng.H;
                end
                data.species{end+1} = entry;
            end
            txt = jsonencode(data);
            fid = fopen(jsonPath, 'w');
            fwrite(fid, txt);
            fclose(fid);
        end
    end

    methods (Access = private)
        function loadJSON(obj, jsonPath)
            txt = fileread(jsonPath);
            data = jsondecode(txt);
            if isstruct(data) && isfield(data, 'species')
                entries = data.species;
                if isstruct(entries)
                    % jsondecode returns struct array when all have same fields
                    for i = 1:numel(entries)
                        obj.parseEntry(entries(i));
                    end
                elseif iscell(entries)
                    for i = 1:numel(entries)
                        obj.parseEntry(entries{i});
                    end
                end
            end
        end

        function parseEntry(obj, e)
            name = e.name;
            MW   = e.MW;

            % Build ranges struct array
            sr = e.shomate_ranges;
            if isstruct(sr)
                ranges = sr;
            else
                ranges = struct([]);
            end

            sp = proc.thermo.ShomateSpecies(name, MW, ranges);

            if isfield(e, 'formula'),       sp.formula = string(e.formula); end
            if isfield(e, 'source'),        sp.source = string(e.source); end
            if isfield(e, 'notes'),         sp.notes = string(e.notes); end
            if isfield(e, 'Hf298_kJkmol') && ~isempty(e.Hf298_kJkmol)
                sp.Hf298_kJkmol = e.Hf298_kJkmol;
            end
            if isfield(e, 'S298_kJkmolK') && ~isempty(e.S298_kJkmolK)
                sp.S298_kJkmolK = e.S298_kJkmolK;
            end
            if isfield(e, 'phase_change') && isstruct(e.phase_change)
                sp.phase_change = e.phase_change;
            end

            obj.speciesMap(char(name)) = sp;
        end
    end
end
