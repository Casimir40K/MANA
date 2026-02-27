classdef IdealGasMixture < handle
    %IDEALGASMIXTURE Ideal-gas mixture thermodynamic property evaluator.
    %
    %   Units:
    %     T in K,  P in Pa,  enthalpy in kJ/kmol,  entropy in kJ/(kmol*K),
    %     cp in kJ/(kmol*K),  MW in kg/kmol.
    %
    %   Reference state: Tref = 298.15 K,  P0 = 1e5 Pa (1 bar).
    %   Ideal-gas mixture: properties are mole-fraction weighted sums.

    properties (Constant)
        Rbar = 8.314462618   % kJ/(kmol*K) — universal gas constant
        Tref = 298.15        % K — reference temperature
        P0   = 1e5           % Pa — standard pressure (1 bar)
    end

    properties
        speciesNames    cell   = {}         % cell of species name strings
        speciesObjects  cell   = {}         % cell of ShomateSpecies handles
        ns              double = 0          % number of species
    end

    properties (Access = private)
        MWvec   double = []    % cached MW vector for fast MW_mix
    end

    methods
        function obj = IdealGasMixture(speciesNames, thermoLib)
            %IDEALGASMIXTURE Construct from species names + ThermoLibrary.
            %   mix = IdealGasMixture({'N2','O2','H2O'}, lib)
            if nargin == 0, return; end
            obj.speciesNames = speciesNames(:)';
            obj.ns = numel(speciesNames);
            obj.speciesObjects = cell(1, obj.ns);
            obj.MWvec = zeros(obj.ns, 1);
            for i = 1:obj.ns
                obj.speciesObjects{i} = thermoLib.get(speciesNames{i});
                obj.MWvec(i) = obj.speciesObjects{i}.MW;
            end
        end

        % --- Pure-component accessors (delegate to ShomateSpecies) ---

        function cp = cp_species(obj, idx, T)
            %CP_SPECIES cp [kJ/(kmol*K)] for species index idx at T [K].
            cp = obj.speciesObjects{idx}.cp_molar(T);
        end

        function h = h_species_sensible(obj, idx, T)
            h = obj.speciesObjects{idx}.h_sensible(T);
        end

        function h = h_species_absolute(obj, idx, T)
            h = obj.speciesObjects{idx}.h_absolute(T);
        end

        function s = s_species(obj, idx, T)
            s = obj.speciesObjects{idx}.s_molar(T);
        end

        function mw = MW_species(obj, idx)
            mw = obj.speciesObjects{idx}.MW;
        end

        % --- Mixture properties ---

        function mw = MW_mix(obj, z)
            %MW_MIX Mean molecular weight [kg/kmol].
            mw = z(:)' * obj.MWvec;
        end

        function cp = cp_mix(obj, T, z)
            %CP_MIX Mixture cp [kJ/(kmol*K)] at T, mole fractions z.
            cp = 0;
            for i = 1:obj.ns
                zi = z(i);
                if zi > 0
                    cp = cp + zi * obj.speciesObjects{i}.cp_molar(T);
                end
            end
        end

        function h = h_mix_sensible(obj, T, z)
            %H_MIX_SENSIBLE Sensible enthalpy of mixture [kJ/kmol] relative to Tref.
            h = 0;
            for i = 1:obj.ns
                zi = z(i);
                if zi > 0
                    h = h + zi * obj.speciesObjects{i}.h_sensible(T);
                end
            end
        end

        function h = h_mix_absolute(obj, T, z)
            %H_MIX_ABSOLUTE Absolute enthalpy = sensible + formation [kJ/kmol].
            %   Requires Hf298 for all species; NaN propagates if any missing.
            h = 0;
            for i = 1:obj.ns
                zi = z(i);
                if zi > 0
                    h = h + zi * obj.speciesObjects{i}.h_absolute(T);
                end
            end
        end

        function s = s_mix(obj, T, P, z)
            %S_MIX Mixture entropy [kJ/(kmol*K)] at T, P, mole fractions z.
            %   s = sum(zi * s_i(T)) - R*ln(P/P0) - R*sum(zi*ln(zi))
            Rbar_ = obj.Rbar;
            s = 0;
            for i = 1:obj.ns
                zi = z(i);
                if zi > 0
                    s = s + zi * obj.speciesObjects{i}.s_molar(T) ...
                          - Rbar_ * zi * log(zi);
                end
            end
            s = s - Rbar_ * log(P / obj.P0);
        end

        function cv = cv_mix(obj, T, z)
            %CV_MIX Mixture cv [kJ/(kmol*K)] = cp - R.
            cv = obj.cp_mix(T, z) - obj.Rbar;
        end

        function g = gamma_mix(obj, T, z)
            %GAMMA_MIX Heat capacity ratio cp/cv.
            cp = obj.cp_mix(T, z);
            cv = cp - obj.Rbar;
            g = cp / cv;
        end

        % --- Inverse solvers ---

        function T = solveT_from_h(obj, h_target, z, T_guess)
            %SOLVET_FROM_H Find T such that h_mix_sensible(T,z) = h_target.
            %   Uses Newton-Raphson (dh/dT = cp) with fzero fallback.
            if nargin < 4, T_guess = 500; end
            Tlo = 200; Thi = 4500;
            T = min(max(T_guess, Tlo), Thi);
            for iter = 1:50
                f    = obj.h_mix_sensible(T, z) - h_target;
                if abs(f) < 1e-3; return; end   % 1e-3 kJ/kmol — far tighter than needed
                dfdT = obj.cp_mix(T, z);         % dh/dT = cp
                if abs(dfdT) < 1e-20; break; end
                T = min(max(T - f/dfdT, Tlo), Thi);
            end
            % Fallback: fzero with practical tolerance
            opts = optimset('TolX', 1e-4, 'Display', 'off');
            f_fun = @(Tv) obj.h_mix_sensible(Tv, z) - h_target;
            try
                T = fzero(f_fun, [Tlo, Thi], opts);
            catch
                T = fzero(f_fun, T_guess, opts);
            end
        end

        function T = solveT_isentropic(obj, s_target, P2, z, T_guess)
            %SOLVET_ISENTROPIC Find T2 such that s_mix(T2,P2,z) = s_target.
            %   Uses Newton-Raphson (ds/dT = cp/T) with fzero fallback.
            if nargin < 5, T_guess = 500; end
            Tlo = 200; Thi = 4500;
            T = min(max(T_guess, Tlo), Thi);
            for iter = 1:50
                f    = obj.s_mix(T, P2, z) - s_target;
                if abs(f) < 1e-6; return; end   % 1e-6 kJ/(kmol·K) — far tighter than needed
                dfdT = obj.cp_mix(T, z) / T;    % ds/dT = cp/T at const P,z
                if abs(dfdT) < 1e-20; break; end
                T = min(max(T - f/dfdT, Tlo), Thi);
            end
            % Fallback: fzero with practical tolerance
            opts = optimset('TolX', 1e-4, 'Display', 'off');
            f_fun = @(Tv) obj.s_mix(Tv, P2, z) - s_target;
            try
                T = fzero(f_fun, [Tlo, Thi], opts);
            catch
                T = fzero(f_fun, T_guess, opts);
            end
        end
    end
end
