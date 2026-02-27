classdef Recycle < handle
    properties
        source   % Stream object (calculated stream in loop)
        tear     % Stream object (explicit tear stream guess)
    end

    methods
        function obj = Recycle(source, tear)
            obj.source = source;
            obj.tear = tear;
        end

        function eqs = equations(obj)
            ns = numel(obj.source.y);
            eqs = zeros(ns, 1);
            eqs(1:ns) = obj.tear.n_dot * obj.tear.y(:) ...
                      - obj.source.n_dot * obj.source.y(:);
        end

        function str = describe(obj)
            str = sprintf('Recycle: %s -> tear %s', string(obj.source.name), string(obj.tear.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.source.name)), char(string(obj.tear.name))};
        end
    end
end
