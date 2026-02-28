classdef AppUtils
    %APPUTILS  Static file-I/O and miscellaneous helpers for MathLab.

    methods (Static)

        function dirPath = ensureOutputDir(subfolder)
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

        function ensureWritableDir(dirPath)
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

        function fname = autoFileName(projectTitle, prefix, ext)
            safeTitle = regexprep(projectTitle, '[^A-Za-z0-9_-]', '_');
            stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok
            fname = sprintf('%s_%s_%s.%s', safeTitle, prefix, stamp, ext);
        end

        function writeErrorLog(projectTitle, prefix, logLines)
            try
                logDir = ui.AppUtils.ensureOutputDir('logs');
                fname = ui.AppUtils.autoFileName(projectTitle, prefix, 'txt');
                fpath = fullfile(logDir, fname);
                fid = fopen(fpath, 'w');
                if fid >= 0
                    for k = 1:numel(logLines)
                        fprintf(fid, '%s\n', logLines{k});
                    end
                    fclose(fid);
                end
            catch
            end
        end

        function txt = formatSpecValue(val)
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

        function txt = ternary(cond, a, b)
            if cond, txt = a; else, txt = b; end
        end

        function catalog = unitTypeCatalog()
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

        function nm = shortTypeName(u)
            cn = class(u);
            parts = strsplit(cn,'.');
            nm = ui.AppUtils.prettyUnitTypeName(parts{end});
        end

        function label = prettyUnitTypeName(type)
            catalog = ui.AppUtils.unitTypeCatalog();
            idx = find(strcmp({catalog.type}, char(string(type))), 1);
            if isempty(idx)
                label = char(string(type));
            else
                label = catalog(idx).label;
            end
        end

        function names = getStreamNames(streams)
            names = cellfun(@(s) char(string(s.name)), streams, 'Uni', false);
        end

        function s = findStream(streams, name)
            s = [];
            for i = 1:numel(streams)
                if strcmp(char(string(streams{i}.name)), char(name))
                    s = streams{i}; return;
                end
            end
        end

        function mix = buildThermoMix(speciesNames)
            try
                lib = proc.thermo.ThermoLibrary();
                mix = proc.thermo.IdealGasMixture(speciesNames, lib);
            catch
                mix = [];
            end
        end
    end
end
