classdef ShomateSpecies < handle
    %SHOMATESPECIES Ideal-gas thermodynamic properties for a single species
    %   using NIST Shomate equations.
    %
    %   Shomate equations (NIST convention):
    %     cp(T) = A + B*t + C*t^2 + D*t^3 + E/t^2        [J/(mol*K)]
    %     H(T) - H(298.15) = A*t + B*t^2/2 + C*t^3/3 + D*t^4/4 - E/t + F - H
    %                                                       [kJ/mol]
    %     S(T) = A*ln(t) + B*t + C*t^2/2 + D*t^3/3 - E/(2*t^2) + G
    %                                                       [J/(mol*K)]
    %   where t = T[K] / 1000.
    %
    %   Internal units:  kJ/kmol for enthalpy, kJ/(kmol*K) for cp and s.
    %   Temperature in K.  MW in kg/kmol.

    properties
        name        string = ""
        formula     string = ""
        MW          double = 0          % kg/kmol

        % Shomate coefficient ranges: struct array with fields
        %   Tmin, Tmax, A, B, C, D, E, F, G, H
        ranges      struct = struct([])

        % Formation enthalpy at 298.15 K  [kJ/kmol]  (optional; NaN if unknown)
        Hf298_kJkmol    double = NaN

        % Standard entropy at 298.15 K  [kJ/(kmol*K)]  (optional)
        S298_kJkmolK    double = NaN

        % Future phase-change data (stored but unused in v1)
        phase_change    struct = struct('Tb_K', NaN, 'Hvap_kJkmol', NaN, ...
                                        'Antoine', [NaN NaN NaN])

        % Metadata
        source      string = ""
        notes       string = ""
    end

    properties (Access = private)
        didWarnOutOfRange logical = false
    end

    methods
        function obj = ShomateSpecies(name, MW, ranges, varargin)
            %SHOMATESPECIES Construct species with Shomate data.
            %   sp = ShomateSpecies(name, MW, ranges)
            %   sp = ShomateSpecies(name, MW, ranges, 'Hf298_kJkmol', val, ...)
            if nargin == 0, return; end
            obj.name = string(name);
            obj.MW   = MW;
            obj.ranges = ranges;
            for k = 1:2:numel(varargin)
                if isprop(obj, varargin{k})
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
        end

        function c = selectRange(obj, T)
            %SELECTRANGE Return the Shomate coefficient struct for temperature T [K].
            c = [];
            for i = 1:numel(obj.ranges)
                if T >= obj.ranges(i).Tmin && T <= obj.ranges(i).Tmax
                    c = obj.ranges(i);
                    return
                end
            end
            % If not found, clamp to nearest range boundary and warn
            if T < obj.ranges(1).Tmin
                c = obj.ranges(1);
            elseif T > obj.ranges(end).Tmax
                c = obj.ranges(end);
            end
            if ~obj.didWarnOutOfRange
                warning('proc.thermo:outOfRange', ...
                    '%s: T=%.1f K outside Shomate range [%.0f, %.0f]. Clamping.', ...
                    obj.name, T, obj.ranges(1).Tmin, obj.ranges(end).Tmax);
                obj.didWarnOutOfRange = true;
            end
        end

        function cp = cp_molar(obj, T)
            %CP_MOLAR Molar heat capacity [kJ/(kmol*K)] at temperature T [K].
            %   Shomate cp in J/(mol*K) -> multiply by 1 to get kJ/(kmol*K)
            %   because 1 J/(mol*K) = 1 kJ/(kmol*K).
            c = obj.selectRange(T);
            t = T / 1000;
            % cp [J/(mol*K)] = A + B*t + C*t^2 + D*t^3 + E/t^2
            cp_Jmol = c.A + c.B*t + c.C*t^2 + c.D*t^3 + c.E/t^2;
            cp = cp_Jmol;  % kJ/(kmol*K) numerically identical to J/(mol*K)
        end

        function h = h_sensible(obj, T)
            %H_SENSIBLE Sensible enthalpy H(T) - H(298.15 K) [kJ/kmol].
            %   Shomate: H-H298 [kJ/mol] = A*t + B*t^2/2 + C*t^3/3 + D*t^4/4
            %                              - E/t + F - H
            %   Multiply by 1000 to get kJ/kmol (1 kJ/mol = 1000 kJ/kmol).
            c = obj.selectRange(T);
            t = T / 1000;
            h_kJmol = c.A*t + c.B*t^2/2 + c.C*t^3/3 + c.D*t^4/4 ...
                      - c.E/t + c.F - c.H;
            h = h_kJmol * 1000;  % kJ/kmol
        end

        function h = h_absolute(obj, T)
            %H_ABSOLUTE Absolute molar enthalpy [kJ/kmol] = Hf298 + h_sensible(T).
            %   Returns NaN if Hf298 is not set.
            h = obj.Hf298_kJkmol + obj.h_sensible(T);
        end

        function s = s_molar(obj, T)
            %S_MOLAR Standard-state molar entropy [kJ/(kmol*K)] at T [K] and P0=1 bar.
            %   Shomate: S [J/(mol*K)] = A*ln(t) + B*t + C*t^2/2 + D*t^3/3
            %                           - E/(2*t^2) + G
            %   1 J/(mol*K) = 1 kJ/(kmol*K).
            c = obj.selectRange(T);
            t = T / 1000;
            s = c.A*log(t) + c.B*t + c.C*t^2/2 + c.D*t^3/3 ...
                - c.E/(2*t^2) + c.G;
            % Already in kJ/(kmol*K) numerically
        end
    end
end
