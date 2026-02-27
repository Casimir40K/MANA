classdef Link < handle
    properties
        inlet
        outlet
    end

    methods
        function obj = Link(inlet, outlet)
            obj.inlet = inlet;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            ns = numel(obj.inlet.y);
            eqs = zeros(ns + 2, 1);
            eqs(1:ns) = obj.outlet.n_dot * obj.outlet.y(:) ...
                      - obj.inlet.n_dot * obj.inlet.y(:);
            eqs(ns+1) = obj.outlet.T - obj.inlet.T;
            eqs(ns+2) = obj.outlet.P - obj.inlet.P;
        end

        function str = describe(obj)
            str = sprintf('Link: %s -> %s', string(obj.inlet.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end
