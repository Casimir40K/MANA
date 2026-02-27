classdef Separator < handle
    properties
        inlet      % Stream object
        outletA    % Stream object (e.g. gas / recycle)
        outletB    % Stream object (e.g. liquid / product)
        phi        % split fraction to outletA for each species (0..1), size = nspecies
        includeNormalizationConstraints logical = false
    end

    methods
        function obj = Separator(inlet, outletA, outletB, phi)
            obj.inlet   = inlet;
            obj.outletA = outletA;
            obj.outletB = outletB;
            obj.phi     = phi(:).';
        end

        function eqs = equations(obj)
            ns = numel(obj.inlet.y);
            nNorm = 2 * obj.includeNormalizationConstraints;
            eqs = zeros(2*ns + nNorm + 4, 1);

            % Component split equations (vectorized, interleaved A/B)
            inFlow = obj.inlet.n_dot * obj.inlet.y(:);
            phi = obj.phi(:);
            eqs(1:2:2*ns-1) = obj.outletA.n_dot * obj.outletA.y(:) ...
                             - phi .* inFlow;
            eqs(2:2:2*ns)   = obj.outletB.n_dot * obj.outletB.y(:) ...
                             - (1 - phi) .* inFlow;

            pos = 2*ns;

            % Mole fraction sum constraints (legacy optional; disabled by default because y uses softmax parameterization)
            if obj.includeNormalizationConstraints
                eqs(pos+1) = sum(obj.outletA.y) - 1;
                eqs(pos+2) = sum(obj.outletB.y) - 1;
                pos = pos + 2;
            end

            % T/P pass-through
            eqs(pos+1) = obj.outletA.T - obj.inlet.T;
            eqs(pos+2) = obj.outletB.T - obj.inlet.T;
            eqs(pos+3) = obj.outletA.P - obj.inlet.P;
            eqs(pos+4) = obj.outletB.P - obj.inlet.P;
        end

        function str = describe(obj)
            str = sprintf('Separator: %s -> %s, %s (phi=%s)', ...
                string(obj.inlet.name), string(obj.outletA.name), ...
                string(obj.outletB.name), mat2str(obj.phi, 3));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.outletA.name)), ...
                     char(string(obj.outletB.name))};
        end
    end
end
