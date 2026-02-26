classdef Compressor < handle
    %COMPRESSOR Adiabatic compressor with isentropic efficiency.
    %
    %   Supported specification modes (set exactly one pressure spec):
    %     'Pout'  — outlet pressure [Pa] + eta_isentropic
    %     'PR'    — pressure ratio Pout/Pin + eta_isentropic
    %
    %   Equations provided (ns+2 total):
    %     - ns component balances (pass-through, no reaction)
    %     - 1 pressure spec (Pout equation)
    %     - 1 energy balance (h_out from isentropic + efficiency)
    %
    %   Sign convention: W > 0 means power consumed by compressor.
    %   No pressure drop (ΔP = 0 on inlet side).
    %
    %   Units: T [K], P [Pa], h [kJ/kmol], W [kW], n_dot [kmol/s].

    properties
        inlet               % proc.Stream
        outlet              % proc.Stream
        thermoMix           % proc.thermo.IdealGasMixture

        % Specifications (user sets these)
        Pout        double = NaN    % outlet pressure [Pa]
        PR          double = NaN    % pressure ratio (Pout/Pin)
        eta         double = 1.0    % isentropic efficiency (0-1]
    end

    methods
        function obj = Compressor(inlet, outlet, thermoMix, varargin)
            obj.inlet     = inlet;
            obj.outlet    = outlet;
            obj.thermoMix = thermoMix;
            for k = 1:2:numel(varargin)
                if isprop(obj, varargin{k})
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);

            % Component balances: pass-through (no reaction)
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(i) ...
                           - obj.inlet.n_dot * obj.inlet.y(i);
            end

            % Determine outlet pressure
            if isfinite(obj.Pout)
                P2 = obj.Pout;
            elseif isfinite(obj.PR)
                P2 = obj.inlet.P * obj.PR;
            else
                error('Compressor: must specify Pout or PR.');
            end

            % Pressure equation
            eqs(end+1) = obj.outlet.P - P2;

            % Isentropic calculation
            z = obj.inlet.y(:)' / max(sum(obj.inlet.y), eps);
            T1 = obj.inlet.T;
            P1 = obj.inlet.P;
            h1 = obj.thermoMix.h_mix_sensible(T1, z);
            s1 = obj.thermoMix.s_mix(T1, P1, z);

            % Isentropic outlet temperature
            T2s_guess = T1 * (P2/P1)^0.3;  % rough estimate
            T2s = obj.thermoMix.solveT_isentropic(s1, P2, z, T2s_guess);
            h2s = obj.thermoMix.h_mix_sensible(T2s, z);

            % Actual outlet enthalpy: h2 = h1 + (h2s - h1) / eta
            h2_actual = h1 + (h2s - h1) / obj.eta;

            % Energy balance: outlet enthalpy must match
            h2_outlet = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            eqs(end+1) = h2_outlet - h2_actual;
        end

        function labels = equationLabels(obj)
            ns = numel(obj.inlet.y);
            labels = strings(ns + 2, 1);
            for i = 1:ns
                labels(i) = sprintf('Compressor %s->%s: component %d mole flow', ...
                    string(obj.inlet.name), string(obj.outlet.name), i);
            end
            labels(ns+1) = sprintf('Compressor %s->%s: pressure', ...
                string(obj.inlet.name), string(obj.outlet.name));
            labels(ns+2) = sprintf('Compressor %s->%s: enthalpy balance', ...
                string(obj.inlet.name), string(obj.outlet.name));
        end

        function W = getPower(obj)
            %GETPOWER Compute shaft power [kW] from current stream states.
            z = obj.inlet.y(:)' / max(sum(obj.inlet.y), eps);
            h1 = obj.thermoMix.h_mix_sensible(obj.inlet.T, z);
            h2 = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            W = obj.inlet.n_dot * (h2 - h1);
        end

        function str = describe(obj)
            str = sprintf('Compressor: %s -> %s (eta=%.3f)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.eta);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end
