classdef Purge < handle
    properties
        inlet       % Stream
        recycle     % Stream (goes back to process)
        purge       % Stream (leaves the process)
        beta        % recycle fraction (0..1)
        mode = "fixed"
        includeNormalizationConstraints logical = false
        
    end

    methods
        function obj = Purge(inlet, recycle, purge, beta)
            obj.inlet = inlet;
            obj.recycle = recycle;
            obj.purge = purge;
            obj.beta = beta;
        end

        function eqs = equations(obj)
            ns = numel(obj.inlet.y);
            b = obj.beta;
            nNorm = 2 * obj.includeNormalizationConstraints;
            eqs = zeros(2*ns + nNorm + 4, 1);

            % Component-wise split (vectorized, interleaved recycle/purge)
            inFlow = obj.inlet.n_dot * obj.inlet.y(:);
            eqs(1:2:2*ns-1) = obj.recycle.n_dot * obj.recycle.y(:) ...
                             - b * inFlow;
            eqs(2:2:2*ns)   = obj.purge.n_dot * obj.purge.y(:) ...
                             - (1 - b) * inFlow;

            pos = 2*ns;

            % Mole fraction normalization (legacy optional; disabled by default because y uses softmax parameterization)
            if obj.includeNormalizationConstraints
                eqs(pos+1) = sum(obj.recycle.y) - 1;
                eqs(pos+2) = sum(obj.purge.y) - 1;
                pos = pos + 2;
            end

            % T/P pass-through
            eqs(pos+1) = obj.recycle.T - obj.inlet.T;
            eqs(pos+2) = obj.purge.T   - obj.inlet.T;
            eqs(pos+3) = obj.recycle.P - obj.inlet.P;
            eqs(pos+4) = obj.purge.P   - obj.inlet.P;
        end

        function setFixed(obj, beta)
            obj.mode = "fixed";
            obj.beta = beta;
        end

        function str = describe(obj)
            str = sprintf('Purge: %s -> recycle=%s, purge=%s (beta=%.3f)', ...
                string(obj.inlet.name), string(obj.recycle.name), ...
                string(obj.purge.name), obj.beta);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.recycle.name)), ...
                     char(string(obj.purge.name))};
        end
    end
end
