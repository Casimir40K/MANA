classdef Reactor < handle
    properties
        inlet      % Stream object
        outlet     % Stream object
        reactions  % struct array with fields: reactants, products, stoich, name
        conversion % fraction of limiting reactant reacted (0-1)
    end

    methods
        function obj = Reactor(inlet, outlet, reactions, conversion)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.reactions = reactions;
            obj.conversion = conversion;
        end

        function eqs = equations(obj)
            eqs = [];
            nspecies = length(obj.outlet.y);

            obj.validateReactions(nspecies);

            % Step 1: Copy inlet moles
            n_species = obj.inlet.n_dot * obj.inlet.y;

            % Step 2: Apply reactions
            for r = 1:length(obj.reactions)
                rxn = obj.reactions(r);

                % Limiting reactant (stoich-adjusted)
                limiting_n = inf;
                for i = 1:length(rxn.reactants)
                    idx = rxn.reactants(i);
                    nu = obj.signedStoichAtIndex(rxn, idx, 'reactant');
                    limiting_n = min(limiting_n, n_species(idx) / abs(nu));
                end

                % Extent of reaction
                xi = obj.conversion * limiting_n;

                % Update species moles
                for i = 1:length(rxn.reactants)
                    idx = rxn.reactants(i);
                    nu = obj.signedStoichAtIndex(rxn, idx, 'reactant');
                    n_species(idx) = n_species(idx) + nu * xi;
                end
                for i = 1:length(rxn.products)
                    idx = rxn.products(i);
                    nu = obj.signedStoichAtIndex(rxn, idx, 'product');
                    n_species(idx) = n_species(idx) + nu * xi;
                end
            end

            % Step 3: Compute total moles and mole fractions
            n_out = sum(n_species);
            y_out = n_species / n_out;

            % Step 4: Build residuals from component balances
            for j = 1:nspecies
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(j) - n_out * y_out(j);
            end
            eqs(end+1) = obj.outlet.T - obj.inlet.T;
            eqs(end+1) = obj.outlet.P - obj.inlet.P;
        end

        function labels = equationLabels(obj)
            ns = numel(obj.inlet.y);
            labels = strings(ns + 2, 1);
            prefix = sprintf('Reactor %s->%s', string(obj.inlet.name), string(obj.outlet.name));
            for i = 1:ns
                labels(i) = sprintf('%s: component %d mole flow', prefix, i);
            end
            labels(ns+1) = sprintf('%s: temperature', prefix);
            labels(ns+2) = sprintf('%s: pressure', prefix);
        end

        function str = describe(obj)
            if isfield(obj.reactions, 'name') && ~isempty(obj.reactions(1).name)
                rxnName = obj.reactions(1).name;
            else
                rxnName = "reaction";
            end
            str = sprintf('Reactor: %s -> %s (X=%.2f, %s)', ...
                string(obj.inlet.name), string(obj.outlet.name), ...
                obj.conversion, rxnName);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end

        function validateReactions(obj, nspecies)
            % Validate reaction indexing at runtime to surface malformed
            % configurations early (instead of silently producing bad
            % residuals that appear as solver stagnation).
            for r = 1:numel(obj.reactions)
                rxn = obj.reactions(r);
                if ~isfield(rxn, 'reactants') || ~isfield(rxn, 'products') || ~isfield(rxn, 'stoich')
                    error('Reactor: each reaction must contain reactants, products, and stoich fields.');
                end

                if numel(rxn.stoich) ~= nspecies
                    error('Reactor: stoich length (%d) must match number of species (%d).', ...
                        numel(rxn.stoich), nspecies);
                end

                allIdx = [rxn.reactants(:); rxn.products(:)];
                if isempty(allIdx)
                    error('Reactor: reaction %d has empty reactant/product index lists.', r);
                end

                if any(allIdx < 1 | allIdx > nspecies | abs(allIdx-round(allIdx)) > 0)
                    error('Reactor: reaction %d contains invalid species indices.', r);
                end
            end
        end

        function nu = signedStoichAtIndex(~, rxn, idx, role)
            if idx < 1 || idx > numel(rxn.stoich)
                error('Reactor: stoich vector missing entry for species index %d.', idx);
            end

            nuRaw = rxn.stoich(idx);
            if ~isfinite(nuRaw)
                error('Reactor: stoich(%d) must be finite.', idx);
            end

            if strcmpi(role, 'reactant')
                % Accept either sign convention from UI/config and enforce
                % consumption as negative in the reactor equations.
                nu = -abs(nuRaw);
            else
                % Accept either sign convention and enforce production as
                % positive in the reactor equations.
                nu = abs(nuRaw);
            end
        end
    end
end
