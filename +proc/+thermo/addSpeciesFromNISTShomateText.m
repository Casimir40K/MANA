function sp = addSpeciesFromNISTShomateText(name, MW, text, varargin)
%ADDSPECIESFROMNISTSHOMATE Parse NIST Shomate coefficient text into a ShomateSpecies.
%
%   sp = proc.thermo.addSpeciesFromNISTShomateText(name, MW, text)
%   sp = proc.thermo.addSpeciesFromNISTShomateText(name, MW, text, 'Hf298_kJkmol', val)
%
%   The input 'text' should be a multi-line string copied from the NIST
%   Chemistry WebBook Shomate equation page. Expected format (tab or
%   space separated, one or two temperature ranges side by side):
%
%   Temperature (K)    298. - 1300.    1300. - 6000.
%   A                  25.56759        35.15070
%   B                  6.096130        1.300095
%   C                  4.054656        -0.205921
%   D                  -2.671301       0.013550
%   E                  0.131021        -3.282780
%   F                  -118.0089       -127.8375
%   G                  227.3665        231.7120
%   H                  -110.5271       -110.5271
%
%   Returns a proc.thermo.ShomateSpecies object.
%
%   Example:
%     txt = fileread('nist_co_shomate.txt');
%     sp = proc.thermo.addSpeciesFromNISTShomateText('CO', 28.01, txt, ...
%         'Hf298_kJkmol', -110530);
%     lib = proc.thermo.ThermoLibrary();
%     lib.addSpecies(sp);

    p = inputParser;
    p.KeepUnmatched = true;
    p.addParameter('Hf298_kJkmol', NaN);
    p.addParameter('S298_kJkmolK', NaN);
    p.addParameter('formula', '');
    p.addParameter('source', 'NIST Shomate (user paste)');
    p.addParameter('notes', '');
    p.parse(varargin{:});

    lines = splitlines(strtrim(text));
    lines = lines(~cellfun(@isempty, lines));

    % Parse temperature ranges from first line
    tempLine = lines{1};
    % Extract all numbers from temperature line
    nums = regexp(tempLine, '[\d.]+', 'match');
    nums = str2double(nums);

    nRanges = floor(numel(nums) / 2);
    ranges = struct([]);

    for r = 1:nRanges
        ranges(r).Tmin = nums(2*r - 1);
        ranges(r).Tmax = nums(2*r);
    end

    % Parse coefficients A through H (lines 2-9)
    coeffNames = {'A','B','C','D','E','F','G','H'};
    for i = 1:8
        if i + 1 > numel(lines)
            error('Expected at least 9 lines (Temperature + 8 coefficients). Got %d.', numel(lines));
        end
        ln = lines{i + 1};
        nums = regexp(ln, '[-+]?[\d.]+[eE]?[-+]?[\d]*', 'match');
        vals = str2double(nums);

        % First value might be coefficient label if non-numeric
        if numel(vals) < nRanges
            error('Line %d (%s): expected %d values, got %d.', i+1, coeffNames{i}, nRanges, numel(vals));
        end
        % Take last nRanges values (in case label parses as number)
        vals = vals(end-nRanges+1:end);

        for r = 1:nRanges
            ranges(r).(coeffNames{i}) = vals(r);
        end
    end

    sp = proc.thermo.ShomateSpecies(name, MW, ranges, ...
        'Hf298_kJkmol', p.Results.Hf298_kJkmol, ...
        'S298_kJkmolK', p.Results.S298_kJkmolK, ...
        'formula', p.Results.formula, ...
        'source', p.Results.source, ...
        'notes', p.Results.notes);
end
