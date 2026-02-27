classdef Mixer < handle
    properties
        inlets  % cell array of inlet streams
        outlet  % single outlet stream
    end

    methods
        function obj = Mixer(inlets, outlet)
            obj.inlets = inlets;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            nspecies = length(obj.outlet.y);
            eqs = zeros(nspecies + 2, 1);

            % Component molar-flow balances for every species.
            %
            % Note: we intentionally enforce all species component balances
            % and do NOT add an explicit total flow balance. With normalized
            % compositions, the total balance is implied by summing these
            % component equations. This avoids dropping one species balance
            % (typically the dominant recycle/product component), which can
            % otherwise leave the worst mismatch unrepresented and stall
            % convergence with mixer-dominated residuals.
            total_species_in = zeros(nspecies, 1);
            for i = 1:length(obj.inlets)
                total_species_in = total_species_in + obj.inlets{i}.n_dot * obj.inlets{i}.y(:);
            end
            eqs(1:nspecies) = obj.outlet.n_dot * obj.outlet.y(:) - total_species_in;

            % Mechanical/thermal closure: match first inlet (adiabatic/isobaric assumption)
            eqs(nspecies+1) = obj.outlet.T - obj.inlets{1}.T;
            eqs(nspecies+2) = obj.outlet.P - obj.inlets{1}.P;
        end

        function labels = equationLabels(obj)
            nspecies = length(obj.outlet.y);
            labels = strings(nspecies + 2, 1);
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            prefix = sprintf('Mixer {%s}->%s', strjoin(inNames, ','), string(obj.outlet.name));
            for j = 1:nspecies
                labels(j) = sprintf('%s: component %d mole flow', prefix, j);
            end
            labels(nspecies+1) = sprintf('%s: temperature', prefix);
            labels(nspecies+2) = sprintf('%s: pressure', prefix);
        end

        function str = describe(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            str = sprintf('Mixer: {%s} -> %s', strjoin(inNames, ', '), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            names = [inNames, {char(string(obj.outlet.name))}];
        end
    end
end
