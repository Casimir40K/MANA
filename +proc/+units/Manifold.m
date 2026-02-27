classdef Manifold < handle
    properties
        inlets   % cell array of inlet Stream objects
        outlets  % cell array of outlet Stream objects
        route    % row vector: route(k)=inlet index feeding outlet k
    end

    methods
        function obj = Manifold(inlets, outlets, route)
            obj.inlets = inlets;
            obj.outlets = outlets;
            obj.route = route(:).';
        end

        function eqs = equations(obj)
            ns = numel(obj.inlets{1}.y);
            nOut = numel(obj.outlets);
            eqs = zeros(nOut * ns, 1);

            for k = 1:nOut
                src = obj.inlets{obj.route(k)};
                out = obj.outlets{k};
                idx = (k-1)*ns + (1:ns);
                eqs(idx) = out.n_dot * out.y(:) - src.n_dot * src.y(:);
            end
        end

        function str = describe(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            outNames = cellfun(@(s) char(string(s.name)), obj.outlets, 'Uni', false);
            str = sprintf('Manifold: {%s} -> {%s} (route=%s)', ...
                strjoin(inNames, ', '), strjoin(outNames, ', '), mat2str(obj.route));
        end

        function names = streamNames(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            outNames = cellfun(@(s) char(string(s.name)), obj.outlets, 'Uni', false);
            names = [inNames, outNames];
        end
    end
end
