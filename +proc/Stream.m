classdef Stream < handle
    properties
        name
        species
        n_dot
        T
        P
        y
        known

        % Optional thermo mixture object (set externally for thermo-enabled streams)
        thermoMix       % proc.thermo.IdealGasMixture or []
    end

    methods
        function obj = Stream(name, species)
            obj.name = name;
            obj.species = species;

            ns = numel(species);

            % Default values (guesses can overwrite)
            obj.n_dot = 1;
            obj.T     = 300;
            obj.P     = 1e5;
            obj.y     = ones(1, ns) / ns;

            % Default "unknown" flags
            obj.known = struct();
            obj.known.n_dot = false;
            obj.known.T     = false;
            obj.known.P     = false;
            obj.known.y     = false(1, ns);

            obj.thermoMix = [];
        end

        function setKnown(obj, field, value)
            % Convenience: set a field value and mark it known
            %   s.setKnown('n_dot', 10)
            %   s.setKnown('T', 300)
            %   s.setKnown('y', [0.8 0.2 0])
            if strcmp(field, 'y')
                obj.y = value;
                obj.known.y(:) = true;
            else
                obj.(field) = value;
                obj.known.(field) = true;
            end
        end

        function setGuess(obj, n_dot, y, T, P)
            % Set initial guesses without marking known
            %   s.setGuess(10, [0.8 0.2 0])
            %   s.setGuess(10, [0.8 0.2 0], 400, 2e5)
            if nargin >= 2 && ~isempty(n_dot), obj.n_dot = n_dot; end
            if nargin >= 3 && ~isempty(y),     obj.y = y;         end
            if nargin >= 4 && ~isempty(T),     obj.T = T;         end
            if nargin >= 5 && ~isempty(P),     obj.P = P;         end
        end

        % --- Thermo convenience methods ---

        function z = getZ(obj)
            %GETZ Normalized mole fractions.
            z = obj.y(:)' / sum(obj.y);
        end

        function cp = cp(obj)
            %CP Mixture molar heat capacity [kJ/(kmol*K)] at current T.
            obj.requireThermo();
            cp = obj.thermoMix.cp_mix(obj.T, obj.getZ());
        end

        function h = h(obj)
            %H Sensible molar enthalpy [kJ/kmol] at current T.
            h = obj.hAt(obj.T);
        end

        function h = hAt(obj, T)
            %HAT Sensible molar enthalpy [kJ/kmol] at specified T.
            obj.requireThermo();
            h = obj.thermoMix.h_mix_sensible(T, obj.getZ());
        end

        function s = s(obj)
            %S Mixture molar entropy [kJ/(kmol*K)] at current T and P.
            obj.requireThermo();
            s = obj.thermoMix.s_mix(obj.T, obj.P, obj.getZ());
        end

        function g = gamma(obj)
            %GAMMA Heat capacity ratio cp/cv at current T.
            obj.requireThermo();
            g = obj.thermoMix.gamma_mix(obj.T, obj.getZ());
        end

        function mw = MW(obj)
            %MW Mean molecular weight [kg/kmol].
            obj.requireThermo();
            mw = obj.thermoMix.MW_mix(obj.getZ());
        end
    end

    methods (Access = private)
        function requireThermo(obj)
            if isempty(obj.thermoMix)
                error('Stream "%s": no thermoMix assigned. Set stream.thermoMix first.', ...
                    string(obj.name));
            end
        end
    end
end
