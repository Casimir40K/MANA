classdef VariablePacker
    %VARIABLEPACKER  Static helpers for composition logit math.
    %
    %   Softmax, simplex normalization, and composition logit
    %   initialization / reconstruction. Used by ProcessSolver's
    %   packUnknowns and unpackUnknowns.

    methods (Static)

        function y = softmax(aPacked)
            %SOFTMAX  Gauge-fixed softmax: last component anchored at 0.
            aFull = [aPacked(:); 0];
            aFull = aFull - max(aFull);
            e = exp(aFull);
            y = e / sum(e);
        end

        function y = normalizeSimplex(y)
            y = y(:);
            s = sum(y);
            if ~isfinite(s) || s == 0
                y = ones(numel(y),1) / numel(y);
            else
                y = y / s;
            end
        end

        function knownMask = compositionKnownMask(s, ns)
            if isprop(s,'known') && isstruct(s.known) && isfield(s.known,'y')
                ky = s.known.y;
                if islogical(ky) && numel(ky) == ns
                    knownMask = logical(reshape(ky,1,[]));
                    return;
                end
            end
            knownMask = false(1, ns);
        end

        function unknownIdx = unknownCompositionIndices(s, ns)
            knownMask = proc.solver.VariablePacker.compositionKnownMask(s, ns);
            unknownIdx = find(~knownMask);
        end

        function tf = anyYUnknown(s, ns)
            unknownIdx = proc.solver.VariablePacker.unknownCompositionIndices(s, ns);
            tf = ~isempty(unknownIdx);
        end

        function [packIdx, a0] = initialCompositionLogits(s, ns)
            VP = proc.solver.VariablePacker;
            unknownIdx = VP.unknownCompositionIndices(s, ns);
            nUnknown = numel(unknownIdx);
            if nUnknown <= 1
                packIdx = [];
                a0 = [];
                return;
            end

            y0 = s.y;
            if isempty(y0) || any(~isfinite(y0)) || numel(y0) ~= ns
                y0 = ones(1, ns) / ns;
            end
            y0 = max(reshape(y0,1,[]), 0);

            knownMask = VP.compositionKnownMask(s, ns);
            knownSum = sum(y0(knownMask));
            remaining = max(1 - knownSum, 0);

            yUnknown = y0(unknownIdx);
            yUnknown = max(yUnknown, 0);
            if sum(yUnknown) <= 0
                yUnknown = ones(1,nUnknown) / nUnknown;
            else
                yUnknown = yUnknown / sum(yUnknown);
            end

            if remaining > 0
                pUnknown = yUnknown;
            else
                pUnknown = ones(1,nUnknown) / nUnknown;
            end

            aUnknown = log(max(pUnknown, 1e-12));
            anchor = aUnknown(end);
            aUnknown = aUnknown - anchor;

            packIdx = unknownIdx(1:end-1);
            a0 = aUnknown(1:end-1).';
        end

        function y = reconstructComposition(s, packedA, ns)
            VP = proc.solver.VariablePacker;
            y = s.y;
            if isempty(y) || any(~isfinite(y)) || numel(y) ~= ns
                y = ones(ns,1) / ns;
            end
            y = reshape(y,[],1);

            knownMask = VP.compositionKnownMask(s, ns);
            unknownIdx = find(~knownMask);
            nUnknown = numel(unknownIdx);
            if nUnknown == 0
                y = VP.normalizeSimplex(y);
                return;
            end

            knownSum = sum(y(knownMask));
            remaining = 1 - knownSum;

            if nUnknown == 1
                y(unknownIdx) = remaining;
                y = y / sum(y);
                return;
            end

            aUnknown = zeros(nUnknown-1, 1);
            packIdx = unknownIdx(1:end-1);
            for j = 1:numel(packIdx)
                comp = packIdx(j);
                if isfinite(packedA(comp))
                    aUnknown(j) = packedA(comp);
                end
            end

            y(unknownIdx) = remaining .* VP.softmax(aUnknown);
            y = y / sum(y);
        end

        function tf = isUnknownScalar(s, fn)
            if isprop(s,'known') && isstruct(s.known) && isfield(s.known, fn)
                v = s.known.(fn);
                if islogical(v) && isscalar(v)
                    tf = ~v;
                else
                    tf = true;
                end
            else
                tf = true;
            end
        end

        function v = safeInit(c, fb)
            if isempty(c) || isnan(c)
                v = fb;
            else
                v = c;
            end
        end

        function v = structFieldOr(s, fieldName, defaultValue)
            if isfield(s, fieldName)
                v = s.(fieldName);
            else
                v = defaultValue;
            end
        end

        function [x, map] = packUnknowns(streams, units, ns, nDotMin)
            %PACKUNKNOWNS  Build the unknown vector x and variable map.
            VP = proc.solver.VariablePacker;
            x = []; map = struct('streamIndex',{},'var',{},'subIndex',{},'unitIndex',{},'bounds',{},'owner',{},'field',{});
            for si = 1:numel(streams)
                s = streams{si};
                if VP.isUnknownScalar(s,'n_dot')
                    nd = VP.safeInit(s.n_dot,1.0);
                    x(end+1,1) = log(max(nd,nDotMin)); %#ok<AGROW>
                    map(end+1) = struct('streamIndex',si,'var','z','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field',''); %#ok<AGROW>
                end
                if VP.anyYUnknown(s, ns)
                    [packIdx, a0] = VP.initialCompositionLogits(s, ns);
                    for j = 1:numel(packIdx)
                        x(end+1,1) = a0(j); %#ok<AGROW>
                        map(end+1) = struct('streamIndex',si,'var','a','subIndex',packIdx(j), 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field',''); %#ok<AGROW>
                    end
                end
                knownT = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'T')&&...
                    islogical(s.known.T)&&isscalar(s.known.T)&&s.known.T;
                if ~knownT
                    x(end+1,1) = VP.safeInit(s.T,300); %#ok<AGROW>
                    map(end+1) = struct('streamIndex',si,'var','T','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field',''); %#ok<AGROW>
                end
                knownP = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'P')&&...
                    islogical(s.known.P)&&isscalar(s.known.P)&&s.known.P;
                if ~knownP
                    x(end+1,1) = VP.safeInit(s.P,1e5); %#ok<AGROW>
                    map(end+1) = struct('streamIndex',si,'var','P','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field',''); %#ok<AGROW>
                end
            end

            % Optional unit-level manipulated unknowns (e.g., Adjust blocks)
            for ui = 1:numel(units)
                u = units{ui};
                if ~ismethod(u, 'unknownSpecs')
                    continue;
                end
                specs = u.unknownSpecs();
                if isempty(specs)
                    continue;
                end
                if ~isstruct(specs)
                    error('unknownSpecs() for %s must return a struct array.', class(u));
                end
                for k = 1:numel(specs)
                    sp = specs(k);
                    x(end+1,1) = VP.safeInit(sp.initial, 0); %#ok<AGROW>
                    map(end+1) = struct( ...
                        'streamIndex', NaN, ...
                        'var', 'u', ...
                        'subIndex', VP.structFieldOr(sp, 'index', NaN), ...
                        'unitIndex', ui, ...
                        'bounds', [VP.structFieldOr(sp, 'lower', -Inf), VP.structFieldOr(sp, 'upper', Inf)], ...
                        'owner', sp.owner, ...
                        'field', sp.field); %#ok<AGROW>
                end
            end
        end

        function maps = buildUnpackMaps(map)
            %BUILDUNPACKMAPS  Pre-compute typed index maps for fast unpackUnknowns.
            nMap = numel(map);
            unpackZ = struct('xIdx',{},'sIdx',{});
            unpackA = struct('xIdx',{},'sIdx',{},'comp',{});
            unpackT = struct('xIdx',{},'sIdx',{});
            unpackP = struct('xIdx',{},'sIdx',{});
            unpackU = struct('xIdx',{},'owner',{},'field',{},'sub',{},'lb',{},'ub',{});
            for k = 1:nMap
                m = map(k);
                switch m.var
                    case 'z'
                        unpackZ(end+1) = struct('xIdx',k,'sIdx',m.streamIndex); %#ok<AGROW>
                    case 'a'
                        unpackA(end+1) = struct('xIdx',k,'sIdx',m.streamIndex,'comp',m.subIndex); %#ok<AGROW>
                    case 'T'
                        unpackT(end+1) = struct('xIdx',k,'sIdx',m.streamIndex); %#ok<AGROW>
                    case 'P'
                        unpackP(end+1) = struct('xIdx',k,'sIdx',m.streamIndex); %#ok<AGROW>
                    case 'u'
                        unpackU(end+1) = struct('xIdx',k,'owner',m.owner,'field',m.field,...
                            'sub',m.subIndex,'lb',m.bounds(1),'ub',m.bounds(2)); %#ok<AGROW>
                end
            end
            maps = struct('unpackZ',unpackZ,'unpackA',unpackA,'unpackT',unpackT,...
                'unpackP',unpackP,'unpackU',unpackU);
        end

        function unpackUnknowns(x, streams, ns, maps, bounds)
            %UNPACKUNKNOWNS  Reconstruct stream/unit variables from x vector.
            VP = proc.solver.VariablePacker;
            nS = numel(streams);
            z = nan(nS,1);
            a = nan(nS, ns);

            for i = 1:numel(maps.unpackZ)
                m = maps.unpackZ(i);
                z(m.sIdx) = x(m.xIdx);
            end
            for i = 1:numel(maps.unpackA)
                m = maps.unpackA(i);
                a(m.sIdx, m.comp) = x(m.xIdx);
            end
            for i = 1:numel(maps.unpackT)
                m = maps.unpackT(i);
                streams{m.sIdx}.T = x(m.xIdx);
            end
            for i = 1:numel(maps.unpackP)
                m = maps.unpackP(i);
                streams{m.sIdx}.P = x(m.xIdx);
            end
            for i = 1:numel(maps.unpackU)
                m = maps.unpackU(i);
                xi = min(max(x(m.xIdx), m.lb), m.ub);
                if isnan(m.sub)
                    m.owner.(m.field) = xi;
                else
                    arr = m.owner.(m.field);
                    arr(m.sub) = xi;
                    m.owner.(m.field) = arr;
                end
            end

            for si = 1:nS
                s = streams{si};
                if ~isnan(z(si))
                    s.n_dot = exp(min(max(z(si),bounds.zMin),bounds.zMax));
                end
                if any(isfinite(a(si,:)))
                    s.y = VP.reconstructComposition(s, a(si,:), ns);
                end
                if ~isnan(s.T), s.T = min(max(s.T,bounds.TMin),bounds.TMax); end
                if ~isnan(s.P), s.P = min(max(s.P,bounds.PMin),bounds.PMax); end
            end
        end
    end
end
