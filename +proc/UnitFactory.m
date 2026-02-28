classdef UnitFactory
    %UNITFACTORY  Creates unit operation objects from serialised definitions.
    %
    %   Static factory that converts a definition struct (as saved to .mat
    %   config files) into the corresponding proc.units.* object.  Also
    %   contains the identity-link / alias resolution helpers used when
    %   building a Flowsheet from a definition list.

    methods (Static)

        function u = buildUnitFromDef(def, streams, units, speciesNames, varargin)
            %BUILDUNITFROMDEF  Instantiate a proc.units.* object from a def struct.
            %
            %   u = UnitFactory.buildUnitFromDef(def, streams, units, speciesNames)
            %   u = UnitFactory.buildUnitFromDef(def, ..., 'includeIdentityLink', false)
            u = [];
            p = inputParser;
            p.addParameter('includeIdentityLink', true, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            includeIdentityLink = p.Results.includeIdentityLink;

            find = @(name) ui.AppUtils.findStream(streams, name);

            switch def.type
                case 'Link'
                    if proc.UnitFactory.isIdentityLinkDef(def) && ~includeIdentityLink
                        return;
                    end
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Link(sIn, sOut);
                    end
                case 'Mixer'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = find(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    sOut = find(def.outlet);
                    if ~isempty(sOut)
                        u = proc.units.Mixer(inS, sOut);
                    end
                case 'Reactor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Reactor(sIn, sOut, def.reactions, def.conversion);
                    end
                case 'StoichiometricReactor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.StoichiometricReactor(sIn, sOut, def.nu, ...
                            'extent', def.extent, 'extentMode', def.extentMode, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'ConversionReactor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.ConversionReactor(sIn, sOut, def.nu, def.keySpecies, ...
                            def.conversion, 'conversionMode', def.conversionMode);
                    end
                case 'YieldReactor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.YieldReactor(sIn, sOut, def.basisSpecies, def.conversion, ...
                            def.productSpecies, def.productYields, 'conversionMode', def.conversionMode);
                    end
                case 'EquilibriumReactor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.EquilibriumReactor(sIn, sOut, def.nu, def.Keq, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'Separator'
                    sIn = find(def.inlet);
                    sA  = find(def.outletA);
                    sB  = find(def.outletB);
                    if ~isempty(sIn) && ~isempty(sA) && ~isempty(sB)
                        u = proc.units.Separator(sIn, sA, sB, def.phi);
                    end
                case 'Purge'
                    sIn  = find(def.inlet);
                    sRec = find(def.recycle);
                    sPur = find(def.purge);
                    if ~isempty(sIn) && ~isempty(sRec) && ~isempty(sPur)
                        u = proc.units.Purge(sIn, sRec, sPur, def.beta);
                    end
                case 'Splitter'
                    sIn = find(def.inlet);
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = find(def.outlets{k});
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
                    sSrc = find(def.source);
                    sTear = find(def.tear);
                    if ~isempty(sSrc) && ~isempty(sTear)
                        u = proc.units.Recycle(sSrc, sTear);
                    end
                case 'Bypass'
                    sIn = find(def.inlet);
                    sProcIn = find(def.processInlet);
                    sByp = find(def.bypassStream);
                    sRet = find(def.processReturn);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sProcIn) && ~isempty(sByp) && ~isempty(sRet) && ~isempty(sOut)
                        u = proc.units.Bypass(sIn, sProcIn, sByp, sRet, sOut, def.bypassFraction);
                    end
                case 'Manifold'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = find(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = find(def.outlets{k});
                        if isempty(s), return; end
                        outS{end+1} = s; %#ok
                    end
                    u = proc.units.Manifold(inS, outS, def.route);
                case 'Source'
                    sOut = find(def.outlet);
                    if ~isempty(sOut)
                        opts = struct();
                        if isfield(def,'totalFlow'), opts.totalFlow = def.totalFlow; end
                        if isfield(def,'composition'), opts.composition = def.composition; end
                        if isfield(def,'componentFlows'), opts.componentFlows = def.componentFlows; end
                        u = proc.units.Source(sOut, opts);
                    end
                case 'Sink'
                    sIn = find(def.inlet);
                    if ~isempty(sIn), u = proc.units.Sink(sIn); end
                case 'DesignSpec'
                    s = find(def.stream);
                    if ~isempty(s)
                        u = proc.units.DesignSpec(s, def.metric, def.target, def.componentIndex);
                    end
                case 'Adjust'
                    if isfield(def,'designSpecIndex') && isfield(def,'ownerIndex') && ...
                            def.designSpecIndex <= numel(units) && def.ownerIndex <= numel(units)
                        ds = units{def.designSpecIndex};
                        owner = units{def.ownerIndex};
                        u = proc.units.Adjust(ds, owner, def.field, def.index, def.minValue, def.maxValue);
                    end
                case 'Calculator'
                    lhs = find(def.lhsStream);
                    a = find(def.aStream);
                    b = find(def.bStream);
                    if ~isempty(lhs) && ~isempty(a) && ~isempty(b)
                        u = proc.units.Calculator(lhs, def.lhsField, a, def.aField, def.operator, b, def.bField);
                    end
                case 'Constraint'
                    s = find(def.stream);
                    if ~isempty(s)
                        u = proc.units.Constraint(s, def.field, def.value, def.index);
                    end
                case 'Heater'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = ui.AppUtils.buildThermoMix(speciesNames);
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Heater(sIn, sOut, mix, args{:});
                    end
                case 'Cooler'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = ui.AppUtils.buildThermoMix(speciesNames);
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Cooler(sIn, sOut, mix, args{:});
                    end
                case 'HeatExchanger'
                    hIn = find(def.hotInlet);
                    hOut = find(def.hotOutlet);
                    cIn = find(def.coldInlet);
                    cOut = find(def.coldOutlet);
                    if ~isempty(hIn) && ~isempty(hOut) && ~isempty(cIn) && ~isempty(cOut)
                        mix = ui.AppUtils.buildThermoMix(speciesNames);
                        args = {};
                        if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                        if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        u = proc.units.HeatExchanger(hIn, hOut, cIn, cOut, mix, args{:});
                    end
                case 'Compressor'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = ui.AppUtils.buildThermoMix(speciesNames);
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Compressor(sIn, sOut, mix, args{:});
                    end
                case 'Turbine'
                    sIn = find(def.inlet);
                    sOut = find(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = ui.AppUtils.buildThermoMix(speciesNames);
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Turbine(sIn, sOut, mix, args{:});
                    end
            end
        end

        function [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(unitDefs)
            aliasByOutlet = containers.Map('KeyType','char','ValueType','char');
            resolvedDefs = cell(size(unitDefs));
            for i = 1:numel(unitDefs)
                def = unitDefs{i};
                if ~isstruct(def)
                    resolvedDefs{i} = def;
                    continue;
                end
                def = proc.UnitFactory.rewriteDefStreams(def, aliasByOutlet);
                if strcmp(def.type, 'Link') && proc.UnitFactory.isIdentityLinkDef(def)
                    inletRoot = proc.UnitFactory.resolveAliasName(def.inlet, aliasByOutlet);
                    aliasByOutlet(char(def.outlet)) = inletRoot;
                    continue;
                end
                resolvedDefs{i} = def;
            end
            resolvedDefs = resolvedDefs(~cellfun(@isempty, resolvedDefs));
        end

        function addStreamAliasesToFlowsheet(fs, streams, aliasByOutlet)
            if isempty(aliasByOutlet)
                return;
            end
            keys = aliasByOutlet.keys;
            for i = 1:numel(keys)
                aliasName = keys{i};
                targetName = aliasByOutlet(aliasName);
                s = ui.AppUtils.findStream(streams, targetName);
                if ~isempty(s)
                    fs.addAlias(aliasName, s);
                end
            end
        end

        function tf = isIdentityLinkDef(def)
            tf = strcmp(def.type, 'Link') && isfield(def, 'mode') && strcmp(def.mode, 'identity');
            if isfield(def, 'isIdentity')
                tf = logical(def.isIdentity);
            end
        end
    end

    methods (Static, Access = private)

        function def = rewriteDefStreams(def, aliasByOutlet)
            fnSingles = {'inlet','source','stream','tear','processInlet','bypassStream','processReturn', ...
                'lhsStream','aStream','bStream','recycle','purge','outlet','outletA','outletB', ...
                'hotInlet','hotOutlet','coldInlet','coldOutlet'};
            for i = 1:numel(fnSingles)
                f = fnSingles{i};
                if ~isfield(def, f)
                    continue;
                end
                if strcmp(f, 'outlet') && strcmp(def.type, 'Link') && proc.UnitFactory.isIdentityLinkDef(def)
                    continue;
                end
                def.(f) = proc.UnitFactory.resolveAliasName(def.(f), aliasByOutlet);
            end
            if isfield(def, 'inlets')
                for k = 1:numel(def.inlets)
                    def.inlets{k} = proc.UnitFactory.resolveAliasName(def.inlets{k}, aliasByOutlet);
                end
            end
            if isfield(def, 'outlets')
                for k = 1:numel(def.outlets)
                    def.outlets{k} = proc.UnitFactory.resolveAliasName(def.outlets{k}, aliasByOutlet);
                end
            end
        end

        function outName = resolveAliasName(name, aliasByOutlet)
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
    end
end
