classdef Bypass < handle
    properties
        inlet          % Stream object (fresh feed)
        processInlet   % Stream object (feed sent to process branch)
        bypassStream   % Stream object (bypassed branch)
        processReturn  % Stream object (return from process branch)
        outlet         % Stream object (mixed outlet)
        bypassFraction % scalar (0..1)
    end

    methods
        function obj = Bypass(inlet, processInlet, bypassStream, processReturn, outlet, bypassFraction)
            obj.inlet = inlet;
            obj.processInlet = processInlet;
            obj.bypassStream = bypassStream;
            obj.processReturn = processReturn;
            obj.outlet = outlet;
            obj.bypassFraction = bypassFraction;
        end

        function eqs = equations(obj)
            ns = numel(obj.inlet.y);
            b = obj.bypassFraction;
            eqs = zeros(3*ns, 1);

            % Internal splitter section (component balances, interleaved)
            inFlow = obj.inlet.n_dot * obj.inlet.y(:);
            eqs(1:2:2*ns-1) = obj.processInlet.n_dot * obj.processInlet.y(:) ...
                             - (1 - b) * inFlow;
            eqs(2:2:2*ns)   = obj.bypassStream.n_dot * obj.bypassStream.y(:) ...
                             - b * inFlow;

            % Internal mixer section (component balances)
            eqs(2*ns+1:3*ns) = obj.outlet.n_dot * obj.outlet.y(:) ...
                             - (obj.bypassStream.n_dot * obj.bypassStream.y(:) ...
                              + obj.processReturn.n_dot * obj.processReturn.y(:));
        end

        function str = describe(obj)
            str = sprintf('Bypass: %s -> (%s + %s) -> %s', ...
                string(obj.inlet.name), string(obj.bypassStream.name), ...
                string(obj.processReturn.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.processInlet.name)), ...
                     char(string(obj.bypassStream.name)), ...
                     char(string(obj.processReturn.name)), ...
                     char(string(obj.outlet.name))};
        end
    end
end
