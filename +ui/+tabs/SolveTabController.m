classdef SolveTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = SolveTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function runSolve(obj)
            obj.Services.runSolve();
        end

        function updateConvergence(obj, iter, residual)
            if isfield(obj.Services, 'updateConvergence')
                obj.Services.updateConvergence(iter, residual);
            end
        end
    end
end
