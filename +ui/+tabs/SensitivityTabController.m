classdef SensitivityTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = SensitivityTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function onRunSensitivity(obj)
            obj.Services.runSensitivity();
        end

        function applySensParam(obj, paramChoice, val)
            obj.Services.applySensParam(paramChoice, val);
        end

        function val = extractOutput(obj, streamName, fieldStr)
            val = obj.Services.extractOutput(streamName, fieldStr);
        end
    end
end
