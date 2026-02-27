classdef Turbine < handle
    %TURBINE Adiabatic turbine (expander) with isentropic efficiency.
    %
    %   Supported specification modes:
    %     'Pout'  — outlet pressure [Pa] + eta_isentropic
    %     'PR'    — pressure ratio Pin/Pout (expansion ratio) + eta_isentropic
    %
    %   Equations (ns+2 total):
    %     - ns component balances (pass-through)
    %     - 1 pressure spec
    %     - 1 energy balance (h2 = h1 - eta*(h1 - h2s))
    %
    %   Sign convention: W > 0 means power produced by turbine.
    %   Units: T [K], P [Pa], h [kJ/kmol], W [kW], n_dot [kmol/s].

    properties
        inlet               % proc.Stream
        outlet              % proc.Stream
        thermoMix           % proc.thermo.IdealGasMixture

        Pout        double = NaN    % outlet pressure [Pa]
        PR          double = NaN    % expansion ratio Pin/Pout (>1 for expansion)
        eta         double = 1.0    % isentropic efficiency (0-1]
    end

    methods
        function obj = Turbine(inlet, outlet, thermoMix, varargin)
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
            ns = numel(obj.inlet.y);
            eqs = zeros(ns + 2, 1);

            % Component balances
            eqs(1:ns) = obj.outlet.n_dot * obj.outlet.y(:) ...
                       - obj.inlet.n_dot * obj.inlet.y(:);

            % Outlet pressure
            if isfinite(obj.Pout)
                P2 = obj.Pout;
            elseif isfinite(obj.PR)
                P2 = obj.inlet.P / obj.PR;  % PR = Pin/Pout for turbine
            else
                error('Turbine: must specify Pout or PR.');
            end

            eqs(ns+1) = obj.outlet.P - P2;

            % Isentropic calculation
            z = obj.inlet.y(:)' / max(sum(obj.inlet.y), eps);
            T1 = obj.inlet.T;
            P1 = obj.inlet.P;
            h1 = obj.thermoMix.h_mix_sensible(T1, z);
            s1 = obj.thermoMix.s_mix(T1, P1, z);

            T2s_guess = T1 * (P2/P1)^0.3;
            T2s = obj.thermoMix.solveT_isentropic(s1, P2, z, T2s_guess);
            h2s = obj.thermoMix.h_mix_sensible(T2s, z);

            % Turbine: h2 = h1 - eta * (h1 - h2s)
            h2_actual = h1 - obj.eta * (h1 - h2s);

            h2_outlet = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            eqs(ns+2) = h2_outlet - h2_actual;
        end

        function labels = equationLabels(obj)
            ns = numel(obj.inlet.y);
            labels = strings(ns + 2, 1);
            for i = 1:ns
                labels(i) = sprintf('Turbine %s->%s: component %d mole flow', ...
                    string(obj.inlet.name), string(obj.outlet.name), i);
            end
            labels(ns+1) = sprintf('Turbine %s->%s: pressure', ...
                string(obj.inlet.name), string(obj.outlet.name));
            labels(ns+2) = sprintf('Turbine %s->%s: enthalpy balance', ...
                string(obj.inlet.name), string(obj.outlet.name));
        end

        function W = getPower(obj)
            %GETPOWER Power produced [kW]. W > 0 = power out.
            z = obj.inlet.y(:)' / max(sum(obj.inlet.y), eps);
            h1 = obj.thermoMix.h_mix_sensible(obj.inlet.T, z);
            h2 = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            W = obj.inlet.n_dot * (h1 - h2);
        end

        function str = describe(obj)
            str = sprintf('Turbine: %s -> %s (eta=%.3f)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.eta);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end
