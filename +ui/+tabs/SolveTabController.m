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
            obj.Services.syncStreamsFromTable();
            if ~obj.Services.validateSolvePreconditions()
                return;
            end

            fs = obj.Services.buildFlowsheet();
            obj.Services.setLastFlowsheet(fs);
            obj.Services.updateDOF();

            [maxIt, tol] = obj.Services.getSolveInputs();
            hLine = obj.Services.prepareSolveRun(tol);

            function iterCb(iter, rNorm)
                addpoints(hLine, iter, rNorm);
                obj.Services.onSolveIter(iter, rNorm);
                drawnow limitrate;
            end

            try
                dbg = obj.Services.getDebugSettings();
                solver = fs.solve('maxIter',maxIt,'tolAbs',tol, ...
                    'autoScale',true, ...
                    'printToConsole', false, ...
                    'debugLevel', dbg.debugLevel, ...
                    'debugTopN', dbg.debugTopN, ...
                    'debugEvery', dbg.debugEvery, ...
                    'debugEqNames', dbg.debugEqNames, ...
                    'iterCallback',@iterCb);
                obj.Services.setLastSolver(solver);
                obj.Services.onSolveSuccess(solver);
            catch ME
                obj.Services.onSolveFailure(ME);
            end
        end
    end
end
