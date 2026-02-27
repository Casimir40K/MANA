classdef HeatExchanger < handle
    %HEATEXCHANGER Two-stream counter/co-current heat exchanger.
    %
    %   Energy balance model (no UA/LMTD in v1):
    %     Hot side:  Q = Fh * (h_h_in - h_h_out)   (Q > 0 = heat transferred)
    %     Cold side: Q = Fc * (h_c_out - h_c_in)
    %
    %   Specification modes (set exactly one):
    %     'Th_out' — hot outlet temperature [K]
    %     'Tc_out' — cold outlet temperature [K]
    %     'duty'   — heat duty Q [kW]
    %
    %   Equations (2*ns + 4 total):
    %     - ns hot component balances
    %     - ns cold component balances
    %     - 1 hot pressure pass-through
    %     - 1 cold pressure pass-through
    %     - 1 spec equation (Th_out, Tc_out, or duty)
    %     - 1 energy balance (Q_hot = Q_cold)
    %
    %   No pressure drop (ΔP = 0 on both sides).
    %   Units: T [K], P [Pa], Q [kW], n_dot [kmol/s].

    properties
        hotInlet            % proc.Stream
        hotOutlet           % proc.Stream
        coldInlet           % proc.Stream
        coldOutlet          % proc.Stream
        thermoMix           % proc.thermo.IdealGasMixture (shared for both sides)

        Th_out      double = NaN    % hot outlet temperature [K]
        Tc_out      double = NaN    % cold outlet temperature [K]
        duty        double = NaN    % heat duty [kW]
    end

    methods
        function obj = HeatExchanger(hotIn, hotOut, coldIn, coldOut, thermoMix, varargin)
            obj.hotInlet   = hotIn;
            obj.hotOutlet  = hotOut;
            obj.coldInlet  = coldIn;
            obj.coldOutlet = coldOut;
            obj.thermoMix  = thermoMix;
            for k = 1:2:numel(varargin)
                if isprop(obj, varargin{k})
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.hotInlet.y);

            % Hot side component balances
            for i = 1:ns
                eqs(end+1) = obj.hotOutlet.n_dot * obj.hotOutlet.y(i) ...
                           - obj.hotInlet.n_dot * obj.hotInlet.y(i);
            end

            % Cold side component balances
            for i = 1:ns
                eqs(end+1) = obj.coldOutlet.n_dot * obj.coldOutlet.y(i) ...
                           - obj.coldInlet.n_dot * obj.coldInlet.y(i);
            end

            % Pressure pass-through (ΔP = 0 both sides)
            eqs(end+1) = obj.hotOutlet.P  - obj.hotInlet.P;
            eqs(end+1) = obj.coldOutlet.P - obj.coldInlet.P;

            % Enthalpy calculations
            zh = obj.hotInlet.y(:)' / max(sum(obj.hotInlet.y), eps);
            zc = obj.coldInlet.y(:)' / max(sum(obj.coldInlet.y), eps);

            h_h_in  = obj.thermoMix.h_mix_sensible(obj.hotInlet.T,  zh);
            h_h_out = obj.thermoMix.h_mix_sensible(obj.hotOutlet.T, zh);
            h_c_in  = obj.thermoMix.h_mix_sensible(obj.coldInlet.T,  zc);
            h_c_out = obj.thermoMix.h_mix_sensible(obj.coldOutlet.T, zc);

            Fh = obj.hotInlet.n_dot;
            Fc = obj.coldInlet.n_dot;

            Q_hot  = Fh * (h_h_in - h_h_out);  % heat released by hot side
            Q_cold = Fc * (h_c_out - h_c_in);   % heat absorbed by cold side

            if isfinite(obj.Th_out)
                % Spec: hot outlet temperature
                eqs(end+1) = obj.hotOutlet.T - obj.Th_out;
            elseif isfinite(obj.Tc_out)
                % Spec: cold outlet temperature
                eqs(end+1) = obj.coldOutlet.T - obj.Tc_out;
            elseif isfinite(obj.duty)
                % Spec: duty Q [kW]
                eqs(end+1) = obj.duty - Q_hot;
            else
                error('HeatExchanger: must specify Th_out, Tc_out, or duty.');
            end

            % Energy balance: Q_hot = Q_cold (always enforced)
            eqs(end+1) = Q_hot - Q_cold;
        end

        function labels = equationLabels(obj)
            ns = numel(obj.hotInlet.y);
            nEq = 2*ns + 4;
            labels = strings(nEq, 1);
            idx = 0;
            for i = 1:ns
                idx = idx + 1;
                labels(idx) = sprintf('HX: hot component %d mole flow', i);
            end
            for i = 1:ns
                idx = idx + 1;
                labels(idx) = sprintf('HX: cold component %d mole flow', i);
            end
            idx = idx + 1; labels(idx) = "HX: hot pressure";
            idx = idx + 1; labels(idx) = "HX: cold pressure";
            if isfinite(obj.Th_out)
                idx = idx + 1; labels(idx) = "HX: temperature spec (Th_out)";
            elseif isfinite(obj.Tc_out)
                idx = idx + 1; labels(idx) = "HX: temperature spec (Tc_out)";
            elseif isfinite(obj.duty)
                idx = idx + 1; labels(idx) = "HX: energy spec (duty)";
            else
                idx = idx + 1; labels(idx) = "HX: spec equation";
            end
            idx = idx + 1; labels(idx) = "HX: energy balance";
        end

        function Q = getDuty(obj)
            %GETDUTY Compute heat duty [kW] from current states.
            zh = obj.hotInlet.y(:)' / max(sum(obj.hotInlet.y), eps);
            h_h_in  = obj.thermoMix.h_mix_sensible(obj.hotInlet.T, zh);
            h_h_out = obj.thermoMix.h_mix_sensible(obj.hotOutlet.T, zh);
            Q = obj.hotInlet.n_dot * (h_h_in - h_h_out);
        end

        function str = describe(obj)
            str = sprintf('HeatExchanger: hot(%s->%s) cold(%s->%s)', ...
                string(obj.hotInlet.name), string(obj.hotOutlet.name), ...
                string(obj.coldInlet.name), string(obj.coldOutlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.hotInlet.name)),  char(string(obj.hotOutlet.name)), ...
                     char(string(obj.coldInlet.name)), char(string(obj.coldOutlet.name))};
        end
    end
end
