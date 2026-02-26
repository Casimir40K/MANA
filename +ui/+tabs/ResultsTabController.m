classdef ResultsTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = ResultsTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end
    end
end
