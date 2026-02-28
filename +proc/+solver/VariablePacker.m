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
    end
end
