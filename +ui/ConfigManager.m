classdef ConfigManager
    %CONFIGMANAGER  Save / load / validate / script-generation for MathLab configs.
    %
    %   All methods are static.  The app passes its state in and gets
    %   results back — no handle-class coupling.

    methods (Static)

        function saveConfig(filepath, cfg)
            if ~(ischar(filepath) || isstring(filepath)) || strlength(string(filepath)) == 0
                error('MathLab:SaveConfig:InvalidPath', 'Config path must be a non-empty string.');
            end
            filepath = char(string(filepath));
            saveDir = fileparts(filepath);
            if isempty(saveDir)
                saveDir = pwd;
            end
            ui.AppUtils.ensureWritableDir(saveDir);

            ui.ConfigManager.validateConfigPayload(cfg);
            save(filepath, '-struct', 'cfg');

            mFile = strrep(filepath, '.mat', '_script.m');
            ui.ConfigManager.generateScript(mFile, cfg);
        end

        function cfg = buildConfigPayload(speciesNames, speciesMW, streams, unitDefs, ...
                maxIter, tolAbs, projectTitle, unitPrefs, lastExportPath, logEveryN)
            cfg = struct();
            cfg.speciesNames = speciesNames;
            cfg.speciesMW    = speciesMW;

            N = numel(streams);
            if N == 0
                streamData = struct('name', {}, 'n_dot', {}, 'T', {}, 'P', {}, 'y', {}, ...
                    'known_n_dot', {}, 'known_T', {}, 'known_P', {}, 'known_y', {});
            else
                streamData = repmat(struct('name', '', 'n_dot', NaN, 'T', NaN, 'P', NaN, 'y', [], ...
                    'known_n_dot', false, 'known_T', false, 'known_P', false, 'known_y', false), 1, N);
            end
            for i = 1:N
                s = streams{i};
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
            cfg.unitDefs = unitDefs;
            cfg.maxIter = maxIter;
            cfg.tolAbs  = tolAbs;
            cfg.projectTitle = projectTitle;
            cfg.unitPrefs = unitPrefs;
            cfg.lastExportPath = lastExportPath;
            cfg.logEveryN = logEveryN;

            ui.ConfigManager.validateConfigPayload(cfg);
        end

        function validateConfigPayload(cfg)
            requiredTop = {'speciesNames','speciesMW','streams','unitDefs','maxIter','tolAbs','projectTitle','unitPrefs','lastExportPath','logEveryN'};
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
            if ~isscalar(cfg.logEveryN) || ~isfinite(cfg.logEveryN) || cfg.logEveryN < 0
                error('MathLab:SaveConfig:InvalidSolverLog', 'logEveryN must be a finite nonnegative scalar.');
            end
            if ~(ischar(cfg.lastExportPath) || (isstring(cfg.lastExportPath) && isscalar(cfg.lastExportPath)))
                error('MathLab:SaveConfig:InvalidPath', 'lastExportPath must be a text scalar.');
            end
        end

        function generateScript(filepath, cfg)
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
                    ui.ConfigManager.writeUnitToScript(fid, def);
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

    methods (Static, Access = private)
        function writeUnitToScript(fid, def)
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
end
