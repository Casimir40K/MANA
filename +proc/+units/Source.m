classdef Source < handle
    %SOURCE Fixed-spec stream source block (0 inlets, 1 outlet).
    % Adds equations only for user-selected outlet specifications.
    properties
        outlet
        totalFlow double = NaN            % optional scalar n_dot spec
        componentFlows double = []        % optional vector n_i specs (NaN = unspecified)
        composition double = []           % optional y_i specs (NaN = unspecified)
        specifyT logical = false
        specifyP logical = false
        T double = NaN
        P double = NaN
    end

    methods
        function obj = Source(outlet, varargin)
            obj.outlet = outlet;
            if nargin >= 2 && isstruct(varargin{1})
                s = varargin{1};
                f = fieldnames(s);
                for i = 1:numel(f)
                    if isprop(obj, f{i})
                        obj.(f{i}) = s.(f{i});
                    end
                end
            end
        end

        function eqs = equations(obj)
            ns = numel(obj.outlet.y);

            % Count total equations for pre-allocation
            nEqs = 0;
            cfMask = [];
            if ~isempty(obj.componentFlows)
                if numel(obj.componentFlows) ~= ns
                    error('Source %s: componentFlows must match species count.', string(obj.outlet.name));
                end
                cfMask = ~isnan(obj.componentFlows(:));
                nEqs = nEqs + nnz(cfMask);
            end
            if ~isnan(obj.totalFlow)
                nEqs = nEqs + 1;
            end
            compMask = [];
            if ~isempty(obj.composition)
                if numel(obj.composition) ~= ns
                    error('Source %s: composition must match species count.', string(obj.outlet.name));
                end
                compMask = ~isnan(obj.composition(:));
                nEqs = nEqs + nnz(compMask);
            end
            if obj.specifyT && isfinite(obj.T)
                nEqs = nEqs + 1;
            end
            if obj.specifyP && isfinite(obj.P)
                nEqs = nEqs + 1;
            end

            eqs = zeros(nEqs, 1);
            pos = 0;

            if ~isempty(cfMask)
                specIdx = find(cfMask);
                nCf = numel(specIdx);
                cf = obj.componentFlows(:);
                eqs(pos+1:pos+nCf) = obj.outlet.n_dot * obj.outlet.y(specIdx) ...
                                    - cf(specIdx);
                pos = pos + nCf;
            end

            if ~isnan(obj.totalFlow)
                pos = pos + 1;
                eqs(pos) = obj.outlet.n_dot - obj.totalFlow;
            end

            if ~isempty(compMask)
                specIdx = find(compMask);
                nComp = numel(specIdx);
                comp = obj.composition(:);
                eqs(pos+1:pos+nComp) = obj.outlet.y(specIdx) ...
                                      - comp(specIdx);
                pos = pos + nComp;
            end

            if obj.specifyT && isfinite(obj.T)
                pos = pos + 1;
                eqs(pos) = obj.outlet.T - obj.T;
            end
            if obj.specifyP && isfinite(obj.P)
                pos = pos + 1;
                eqs(pos) = obj.outlet.P - obj.P;
            end
        end

        function str = describe(obj)
            str = sprintf('Source: -> %s', string(obj.outlet.name));
        end
    end
end
